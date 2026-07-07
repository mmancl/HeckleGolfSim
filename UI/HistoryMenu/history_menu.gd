extends Control

@onready var matches_list_vbox = VBoxContainer.new()
@onready var delete_confirm_dialog = ConfirmationDialog.new()

var selected_match_to_delete: Dictionary = {}
var scorecard_overlay: ColorRect

func _ready() -> void:
	name = "HistoryMenu"
	
	# Background Cabo Texture
	var bg_texture = TextureRect.new()
	bg_texture.name = "Background"
	bg_texture.texture = load("res://assets/images/menu/cabo_openfairway_bnw.png")
	bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_texture.stretch_mode = TextureRect.STRETCH_SCALE
	bg_texture.anchor_left = 0.0
	bg_texture.anchor_right = 1.0
	bg_texture.anchor_top = 0.0
	bg_texture.anchor_bottom = 1.0
	bg_texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_texture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(bg_texture)
	
	# Dark semi-transparent color overlay for glassmorphism
	var glass_panel = ColorRect.new()
	glass_panel.color = Color(0.05, 0.08, 0.05, 0.82)
	glass_panel.anchor_left = 0.0
	glass_panel.anchor_right = 1.0
	glass_panel.anchor_top = 0.0
	glass_panel.anchor_bottom = 1.0
	add_child(glass_panel)
	
	# Main layout margin
	var main_margin = MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 60)
	main_margin.add_theme_constant_override("margin_right", 60)
	main_margin.add_theme_constant_override("margin_top", 40)
	main_margin.add_theme_constant_override("margin_bottom", 40)
	main_margin.anchor_left = 0.0
	main_margin.anchor_right = 1.0
	main_margin.anchor_top = 0.0
	main_margin.anchor_bottom = 1.0
	add_child(main_margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 24)
	main_margin.add_child(main_vbox)
	
	# Header with Title & Back Button
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "Match History"
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	header_hbox.add_child(title_lbl)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)
	
	var back_btn = Button.new()
	back_btn.text = "⬅ Main Menu"
	back_btn.custom_minimum_size = Vector2(160, 48)
	apply_button_style(back_btn, Color(0.2, 0.25, 0.3, 0.9))
	back_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
	header_hbox.add_child(back_btn)
	
	# Scrollable area for matches list
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll_container)
	
	matches_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	matches_list_vbox.add_theme_constant_override("separation", 16)
	scroll_container.add_child(matches_list_vbox)
	
	# Deletion Confirmation Dialog
	delete_confirm_dialog.title = "Delete Match"
	delete_confirm_dialog.dialog_text = "Are you sure you want to delete this match from history?"
	delete_confirm_dialog.confirmed.connect(_confirm_delete_match)
	add_child(delete_confirm_dialog)
	
	# Setup Scorecard overlay
	_setup_scorecard_overlay()
	
	# Load and render matches
	_render_history_list()

func _setup_scorecard_overlay() -> void:
	scorecard_overlay = ColorRect.new()
	scorecard_overlay.visible = false
	scorecard_overlay.color = Color(0.0, 0.0, 0.0, 0.75)
	scorecard_overlay.anchor_left = 0.0
	scorecard_overlay.anchor_right = 1.0
	scorecard_overlay.anchor_top = 0.0
	scorecard_overlay.anchor_bottom = 1.0
	add_child(scorecard_overlay)
	
	var center = CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.0
	center.anchor_bottom = 1.0
	scorecard_overlay.add_child(center)
	
	var card_panel = PanelContainer.new()
	card_panel.custom_minimum_size = Vector2(1400, 600)
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.12, 0.16, 0.98)
	card_style.corner_radius_top_left = 12
	card_style.corner_radius_top_right = 12
	card_style.corner_radius_bottom_left = 12
	card_style.corner_radius_bottom_right = 12
	card_style.border_width_left = 2
	card_style.border_width_right = 2
	card_style.border_width_top = 2
	card_style.border_width_bottom = 2
	card_style.border_color = Color(0.3, 0.35, 0.4, 0.4)
	card_style.content_margin_left = 30
	card_style.content_margin_right = 30
	card_style.content_margin_top = 24
	card_style.content_margin_bottom = 24
	card_panel.add_theme_stylebox_override("panel", card_style)
	center.add_child(card_panel)

func _load_history() -> Array:
	var matches = []
	var dir_path = "user://match_history"
	if not DirAccess.dir_exists_absolute(dir_path):
		return matches
		
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return matches
		
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path = dir_path.path_join(file_name)
			var f = FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var json = JSON.parse_string(f.get_as_text())
				if typeof(json) == TYPE_DICTIONARY:
					matches.append(json)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# Sort most recent first
	matches.sort_custom(func(a, b): return a.get("unix_time", 0.0) > b.get("unix_time", 0.0))
	return matches

func _render_history_list() -> void:
	# Clear previous entries
	for child in matches_list_vbox.get_children():
		child.queue_free()
		
	var history = _load_history()
	if history.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No matches played yet."
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		matches_list_vbox.add_child(empty_lbl)
		return
		
	for match_data in history:
		var item_panel = PanelContainer.new()
		var item_style = StyleBoxFlat.new()
		item_style.bg_color = Color(0.12, 0.16, 0.14, 0.85)
		item_style.corner_radius_top_left = 8
		item_style.corner_radius_top_right = 8
		item_style.corner_radius_bottom_left = 8
		item_style.corner_radius_bottom_right = 8
		item_style.border_width_left = 1
		item_style.border_width_right = 1
		item_style.border_width_top = 1
		item_style.border_width_bottom = 1
		item_style.border_color = Color(0.2, 0.3, 0.2, 0.3)
		item_style.content_margin_left = 20
		item_style.content_margin_right = 20
		item_style.content_margin_top = 14
		item_style.content_margin_bottom = 14
		item_panel.add_theme_stylebox_override("panel", item_style)
		matches_list_vbox.add_child(item_panel)
		
		var item_hbox = HBoxContainer.new()
		item_hbox.add_theme_constant_override("separation", 24)
		item_panel.add_child(item_hbox)
		
		# Info column
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item_hbox.add_child(info_vbox)
		
		var title_hbox = HBoxContainer.new()
		info_vbox.add_child(title_hbox)
		
		var course_lbl = Label.new()
		course_lbl.text = match_data.get("course_title", "Unknown Course")
		course_lbl.add_theme_font_size_override("font_size", 22)
		course_lbl.add_theme_color_override("font_color", Color.WHITE)
		title_hbox.add_child(course_lbl)
		
		var status_lbl = Label.new()
		var is_finished = match_data.get("is_finished", false)
		if is_finished:
			status_lbl.text = "[Finished]"
			status_lbl.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		else:
			status_lbl.text = "[In Progress]"
			status_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
		status_lbl.add_theme_font_size_override("font_size", 16)
		title_hbox.add_child(status_lbl)
		
		var players_lbl = Label.new()
		var players_array = match_data.get("players", [])
		var names = []
		for p in players_array:
			names.append(p.get("name", "Player"))
		players_lbl.text = "Players: " + ", ".join(names)
		players_lbl.add_theme_font_size_override("font_size", 16)
		players_lbl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.75))
		info_vbox.add_child(players_lbl)
		
		var date_lbl = Label.new()
		date_lbl.text = match_data.get("formatted_date", "Unknown Date")
		date_lbl.add_theme_font_size_override("font_size", 13)
		date_lbl.add_theme_color_override("font_color", Color(0.55, 0.6, 0.55))
		info_vbox.add_child(date_lbl)
		
		# Action buttons
		var btn_hbox = HBoxContainer.new()
		btn_hbox.add_theme_constant_override("separation", 12)
		item_hbox.add_child(btn_hbox)
		
		if not is_finished:
			var resume_btn = Button.new()
			resume_btn.text = "Resume"
			resume_btn.custom_minimum_size = Vector2(110, 40)
			apply_button_style(resume_btn, Color(0.72, 0.56, 0.24, 0.85)) # Gold
			resume_btn.pressed.connect(func():
				MultiplayerManager.resume_match(match_data)
			)
			btn_hbox.add_child(resume_btn)
			
		var card_btn = Button.new()
		card_btn.text = "Scorecard"
		card_btn.custom_minimum_size = Vector2(110, 40)
		apply_button_style(card_btn, Color(0.24, 0.46, 0.72, 0.85)) # Blue
		card_btn.pressed.connect(func():
			_show_scorecard(match_data)
		)
		btn_hbox.add_child(card_btn)
		
		var delete_btn = Button.new()
		delete_btn.text = "Delete"
		delete_btn.custom_minimum_size = Vector2(90, 40)
		apply_button_style(delete_btn, Color(0.72, 0.24, 0.24, 0.85)) # Red
		delete_btn.pressed.connect(func():
			selected_match_to_delete = match_data
			delete_confirm_dialog.popup_centered()
		)
		btn_hbox.add_child(delete_btn)

func _confirm_delete_match() -> void:
	if selected_match_to_delete.is_empty():
		return
		
	var match_id = selected_match_to_delete.get("match_id", "")
	if not match_id.is_empty():
		var file_path = "user://match_history".path_join(match_id + ".json")
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)
			print("[HistoryMenu] Deleted match history file: " + file_path)
			
	selected_match_to_delete.clear()
	_render_history_list()

func _show_scorecard(match_data: Dictionary) -> void:
	# Clear scorecard panel container children except background/structure
	var card_panel = scorecard_overlay.get_child(0).get_child(0) as PanelContainer
	for child in card_panel.get_children():
		child.queue_free()
		
	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 20)
	card_panel.add_child(card_vbox)
	
	# Header title
	var head_hbox = HBoxContainer.new()
	card_vbox.add_child(head_hbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "Scorecard - %s" % match_data.get("course_title", "Course")
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	head_hbox.add_child(title_lbl)
	
	var date_lbl = Label.new()
	date_lbl.text = "Played on: %s" % match_data.get("formatted_date", "Date")
	date_lbl.add_theme_font_size_override("font_size", 14)
	date_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	date_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head_hbox.add_child(date_lbl)
	
	# Grid scorecard container
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_vbox.add_child(scroll)
	
	var grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.add_child(grid)
	
	# Populate Grid
	_populate_grid_scorecard(grid, match_data)
	
	# Actions row
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_vbox.add_child(action_hbox)
	
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(160, 44)
	apply_button_style(close_btn, Color(0.3, 0.35, 0.4, 0.9))
	close_btn.pressed.connect(func(): scorecard_overlay.visible = false)
	action_hbox.add_child(close_btn)
	
	scorecard_overlay.visible = true

func _populate_grid_scorecard(grid: GridContainer, match_data: Dictionary) -> void:
	# Parse hole config to get par values
	var hole_pars = {}
	var hole_dists = {}
	var config_path = match_data.get("config_path", "")
	var tee_color = "Blue"
	var players_list = match_data.get("players", [])
	if not players_list.is_empty():
		tee_color = players_list[0].get("tee", "Blue")
		
	if not config_path.is_empty() and FileAccess.file_exists(config_path):
		var f = FileAccess.open(config_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var hole_info = parsed.get("Hole Info", {})
				for h_id in hole_info.keys():
					var h_data = hole_info[h_id]
					hole_pars[h_id] = h_data.get("Par", 4)
					var tee_boxes = h_data.get("Tee Boxes", {})
					var tee_pos = tee_boxes.get(tee_color, [0.0, 0.0])
					var hole_loc = h_data.get("Hole Location", [0.0, 0.0])
					var dist = int(Vector2(tee_pos[0], tee_pos[1]).distance_to(Vector2(hole_loc[0], hole_loc[1])) * 1.09361)
					hole_dists[h_id] = dist

	# Holes list sorted
	var hole_ids = hole_pars.keys()
	hole_ids.sort()
	var num_holes = hole_ids.size()
	
	if num_holes == 0:
		# Fallback if config is missing
		for i in range(18):
			hole_ids.append("Hole " + str(i + 1))
		num_holes = 18
		
	# Split into Front 9 and Back 9
	var front_holes = []
	var back_holes = []
	for i in range(num_holes):
		var h_id = hole_ids[i]
		if i < 9:
			front_holes.append(h_id)
		else:
			back_holes.append(h_id)
			
	# Columns: Player | 1..9 | [OUT] | 10..N | [IN] | TOT
	var columns = ["Player"]
	for i in range(front_holes.size()):
		columns.append(str(i + 1))
	if num_holes > 9:
		columns.append("OUT")
		for i in range(back_holes.size()):
			columns.append(str(10 + i))
		columns.append("IN")
	columns.append("TOT")
	
	grid.columns = columns.size()
	
	var header_bg = Color(0.12, 0.16, 0.24, 0.95)
	var par_bg = Color(0.18, 0.24, 0.35, 0.8)
	var dist_bg = Color(0.15, 0.20, 0.30, 0.8)
	
	# Cell addition helper
	var add_cell = func(parent_grid: GridContainer, text: String, bg: Color, is_header: bool = false, fg: Color = Color.WHITE):
		var cell = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = bg
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.3, 0.3)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		cell.add_theme_stylebox_override("panel", style)
		
		var label = Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", fg)
		if is_header:
			label.add_theme_font_size_override("font_size", 14)
		else:
			label.add_theme_font_size_override("font_size", 13)
		cell.add_child(label)
		parent_grid.add_child(cell)
		return cell

	# 1. HEADER ROW
	for col in columns:
		add_cell.call(grid, col, header_bg, true)
		
	# 2. DISTANCE ROW (Yards)
	add_cell.call(grid, "Yds (%s)" % tee_color, dist_bg, false, Color(0.8, 0.8, 0.8))
	var front_dist_sum = 0
	for h_id in front_holes:
		var d = hole_dists.get(h_id, 0)
		front_dist_sum += d
		add_cell.call(grid, str(d) if d > 0 else "-", dist_bg, false, Color(0.8, 0.8, 0.8))
	if num_holes > 9:
		add_cell.call(grid, str(front_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9))
		var back_dist_sum = 0
		for h_id in back_holes:
			var d = hole_dists.get(h_id, 0)
			back_dist_sum += d
			add_cell.call(grid, str(d) if d > 0 else "-", dist_bg, false, Color(0.8, 0.8, 0.8))
		add_cell.call(grid, str(back_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9))
		add_cell.call(grid, str(front_dist_sum + back_dist_sum), dist_bg, false, Color.YELLOW)
	else:
		add_cell.call(grid, str(front_dist_sum), dist_bg, false, Color.YELLOW)

	# 3. PAR ROW
	add_cell.call(grid, "Par", par_bg, false, Color(0.8, 0.8, 0.8))
	var front_par_sum = 0
	for h_id in front_holes:
		var p_val = hole_pars.get(h_id, 4)
		front_par_sum += p_val
		add_cell.call(grid, str(p_val), par_bg, false, Color(0.8, 0.8, 0.8))
	if num_holes > 9:
		add_cell.call(grid, str(front_par_sum), par_bg, false, Color(0.9, 0.9, 0.9))
		var back_par_sum = 0
		for h_id in back_holes:
			var p_val = hole_pars.get(h_id, 4)
			back_par_sum += p_val
			add_cell.call(grid, str(p_val), par_bg, false, Color(0.8, 0.8, 0.8))
		add_cell.call(grid, str(back_par_sum), par_bg, false, Color(0.9, 0.9, 0.9))
		add_cell.call(grid, str(front_par_sum + back_par_sum), par_bg, false, Color.YELLOW)
	else:
		add_cell.call(grid, str(front_par_sum), par_bg, false, Color.YELLOW)

	# 4. PLAYER ROWS
	for p_idx in range(players_list.size()):
		var p = players_list[p_idx]
		var row_bg = Color(0.1, 0.12, 0.18, 0.9) if p_idx % 2 == 0 else Color(0.06, 0.08, 0.12, 0.9)
		
		# Name cell with Email button!
		var name_cell = PanelContainer.new()
		var cell_style = StyleBoxFlat.new()
		cell_style.bg_color = row_bg
		cell_style.border_width_right = 1
		cell_style.border_width_bottom = 1
		cell_style.border_color = Color(0.3, 0.3, 0.3, 0.3)
		cell_style.content_margin_left = 8
		cell_style.content_margin_right = 8
		cell_style.content_margin_top = 4
		cell_style.content_margin_bottom = 4
		name_cell.add_theme_stylebox_override("panel", cell_style)
		grid.add_child(name_cell)
		
		var name_hbox = HBoxContainer.new()
		name_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_hbox.add_theme_constant_override("separation", 10)
		name_cell.add_child(name_hbox)
		
		var name_lbl = Label.new()
		name_lbl.text = "%s (%s)" % [p.get("name", "Player"), p.get("tee", "Blue")]
		var name_fg = Color.WHITE
		if not p.get("active", true):
			name_lbl.text += " (Out)"
			name_fg = Color(0.6, 0.6, 0.6)
		name_lbl.add_theme_color_override("font_color", name_fg)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_hbox.add_child(name_lbl)
		
		# Email stats button next to player name
		var email_btn = Button.new()
		email_btn.text = "✉ Email"
		email_btn.custom_minimum_size = Vector2(65, 24)
		email_btn.add_theme_font_size_override("font_size", 11)
		apply_button_style(email_btn, Color(0.18, 0.45, 0.30, 0.9)) # Emerald Green
		email_btn.pressed.connect(func():
			_email_player_stats(p, match_data)
		)
		name_hbox.add_child(email_btn)
		
		# Front scores
		var front_sum = 0
		var hole_scores = p.get("hole_scores", {})
		for h_id in front_holes:
			var s = hole_scores.get(h_id)
			var display_s = "-"
			var score_fg = Color.WHITE
			if s != null:
				display_s = str(s)
				front_sum += s
				var par = hole_pars.get(h_id, 4)
				if s < par:
					score_fg = Color(0.5, 1.0, 0.5) # Under par (Green)
				elif s > par:
					score_fg = Color(1.0, 0.5, 0.5) # Over par (Red)
			add_cell.call(grid, display_s, row_bg, false, score_fg)
			
		if num_holes > 9:
			add_cell.call(grid, str(front_sum) if front_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9))
			
			# Back scores
			var back_sum = 0
			for h_id in back_holes:
				var s = hole_scores.get(h_id)
				var display_s = "-"
				var score_fg = Color.WHITE
				if s != null:
					display_s = str(s)
					back_sum += s
					var par = hole_pars.get(h_id, 4)
					if s < par:
						score_fg = Color(0.5, 1.0, 0.5)
					elif s > par:
						score_fg = Color(1.0, 0.5, 0.5)
				add_cell.call(grid, display_s, row_bg, false, score_fg)
				
			add_cell.call(grid, str(back_sum) if back_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9))
			var total = front_sum + back_sum
			add_cell.call(grid, str(total) if total > 0 else "-", row_bg, false, Color.YELLOW)
		else:
			add_cell.call(grid, str(front_sum) if front_sum > 0 else "-", row_bg, false, Color.YELLOW)

func _email_player_stats(player: Dictionary, match_data: Dictionary) -> void:
	var course_title = match_data.get("course_title", "Unknown Course")
	var date_str = match_data.get("formatted_date", "Unknown Date")
	var player_name = player.get("name", "Player")
	var tee = player.get("tee", "Blue")
	
	var subject = "Heckle Golf Simulator stats: %s - %s (%s)" % [player_name, course_title, date_str]
	
	# Build email body
	var body = ""
	body += "HECKLE GOLF SIMULATOR ROUND STATS\n"
	body += "=================================\n"
	body += "Player: %s (%s Tee)\n" % [player_name, tee]
	body += "Course: %s\n" % course_title
	body += "Date: %s\n" % date_str
	body += "Total Strokes: %d\n\n" % player.get("total_strokes", 0)
	
	body += "HOLE-BY-HOLE SCORES:\n"
	body += "--------------------\n"
	
	# Load hole pars and distances
	var pars = {}
	var distances = {} # hole_id -> { tee: distance }
	var config_path = match_data.get("config_path", "")
	var hole_ids_list = []
	if not config_path.is_empty() and FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var hole_info = parsed.get("Hole Info", {})
				hole_ids_list = hole_info.keys()
				hole_ids_list.sort()
				for h_id in hole_ids_list:
					pars[h_id] = hole_info[h_id].get("Par", 4)
					var tee_info = hole_info[h_id].get("Tee Info", {})
					distances[h_id] = {}
					for t_name in tee_info.keys():
						distances[h_id][t_name] = tee_info[t_name].get("Distance", 0)

	var hole_scores = player.get("hole_scores", {})
	if hole_ids_list.is_empty():
		hole_ids_list = hole_scores.keys()
		hole_ids_list.sort()
	
	for h_id in hole_ids_list:
		var score = hole_scores.get(h_id)
		var score_str = "-"
		if score != null:
			score_str = str(score)
		var par_val = pars.get(h_id, 4)
		body += "Hole %s (Par %d): %s\n" % [h_id, par_val, score_str]
		
	body += "\nDETAILED SHOT-BY-SHOT STATISTICS:\n"
	body += "---------------------------------\n"
	
	var shot_stats = player.get("shot_stats", {})
	var has_stats = false
	if typeof(shot_stats) == TYPE_DICTIONARY:
		for h_id in shot_stats:
			if typeof(shot_stats[h_id]) == TYPE_ARRAY and not shot_stats[h_id].is_empty():
				has_stats = true
				break
	elif typeof(shot_stats) == TYPE_ARRAY:
		has_stats = not shot_stats.is_empty()

	if not has_stats:
		body += "No detailed shot statistics available.\n"
	else:
		if typeof(shot_stats) == TYPE_DICTIONARY:
			for h_id in hole_ids_list:
				var dist_val = 0
				if distances.has(h_id) and distances[h_id].has(tee):
					dist_val = distances[h_id][tee]
				var par_val = pars.get(h_id, 4)
				var score_val = hole_scores.get(h_id)
				var score_str = str(score_val) if score_val != null else "-"
				
				body += "\nHole %s (Par %d, %d Yds) - Score: %s\n" % [h_id, par_val, dist_val, score_str]
				
				var shots = shot_stats.get(h_id, [])
				if shots.is_empty():
					body += "  No shot data recorded for this hole.\n"
				else:
					for i in range(shots.size()):
						var shot = shots[i]
						var shot_num = i + 1
						var club = shot.get("club", "Unknown")
						if club == "": club = "Unknown"
						
						var carry = "%.1f yds" % shot.get("carry_yds", 0.0)
						var total = "%.1f yds" % shot.get("total_yds", 0.0)
						var speed = "%.1f mph" % shot.get("speed_mph", 0.0)
						var vla = "%.1f deg" % shot.get("vla_deg", 0.0)
						var hla = "%.1f deg" % shot.get("hla_deg", 0.0)
						var tot_spin = "%d rpm" % int(shot.get("total_spin_rpm", 0.0))
						var back_spin = "%d rpm" % int(shot.get("back_spin_rpm", 0.0))
						var side_spin = "%d rpm" % int(shot.get("side_spin_rpm", 0.0))
						var spin_axis = "%.1f deg" % shot.get("spin_axis_deg", 0.0)
						var apex = "%.1f ft" % shot.get("apex_ft", 0.0)
						
						var offline_val = shot.get("offline_yds", 0.0)
						var offline_dir = "R" if offline_val >= 0 else "L"
						var offline = "%s%.1f yds" % [offline_dir, abs(offline_val)]
						
						body += "  Shot %d (Club: %s):\n" % [shot_num, club]
						body += "    Carry: %s | Total: %s | Speed: %s | Apex: %s | Offline: %s\n" % [carry, total, speed, apex, offline]
						body += "    Launch Angle: %s (HLA: %s) | Spin: %s (Back: %s, Side: %s, Axis: %s)\n" % [vla, hla, tot_spin, back_spin, side_spin, spin_axis]
		
		elif typeof(shot_stats) == TYPE_ARRAY:
			var current_hole = ""
			for shot in shot_stats:
				if typeof(shot) != TYPE_DICTIONARY:
					continue
				var h_id = shot.get("hole_id", "")
				if h_id != current_hole:
					current_hole = h_id
					var par_val = pars.get(h_id, 4)
					var score_val = hole_scores.get(h_id, "-")
					body += "\nHole %s (Par %d, Score: %s):\n" % [h_id, par_val, str(score_val) if score_val != null else "-"]
					
				var stroke = shot.get("stroke", shot.get("shot_num", 1))
				var club = shot.get("club", "Dr")
				var carry = "%.1f yds" % shot.get("carry_yds", shot.get("raw_data", {}).get("CarryDistance", 0.0) * 1.09361)
				var total = "%.1f yds" % shot.get("total_yds", shot.get("raw_data", {}).get("TotalDistance", 0.0) * 1.09361)
				var speed = "%.1f mph" % shot.get("speed_mph", shot.get("raw_data", {}).get("Speed", 0.0))
				var vla = "%.1f deg" % shot.get("vla_deg", shot.get("raw_data", {}).get("VLA", 0.0))
				var hla = "%.1f deg" % shot.get("hla_deg", shot.get("raw_data", {}).get("HLA", 0.0))
				var tot_spin = "%d rpm" % int(shot.get("total_spin_rpm", shot.get("raw_data", {}).get("TotalSpin", 0.0)))
				var back_spin = "%d rpm" % int(shot.get("back_spin_rpm", shot.get("raw_data", {}).get("BackSpin", 0.0)))
				var side_spin = "%d rpm" % int(shot.get("side_spin_rpm", shot.get("raw_data", {}).get("SideSpin", 0.0)))
				var spin_axis = "%.1f deg" % shot.get("spin_axis_deg", shot.get("raw_data", {}).get("SpinAxis", 0.0))
				var apex = "%.1f ft" % shot.get("apex_ft", shot.get("raw_data", {}).get("Apex", 0.0) * 3.28084)
				var offline_val = shot.get("offline_yds", shot.get("raw_data", {}).get("SideDistance", 0.0) * 1.09361)
				var offline_dir = "R" if offline_val >= 0 else "L"
				var offline = "%s%.1f yds" % [offline_dir, abs(offline_val)]
				
				body += "  Shot %d (Club: %s):\n" % [stroke, club]
				body += "    Carry: %s | Total: %s | Speed: %s | Apex: %s | Offline: %s\n" % [carry, total, speed, apex, offline]
				body += "    Launch Angle: %s (HLA: %s) | Spin: %s (Back: %s, Side: %s, Axis: %s)\n" % [vla, hla, tot_spin, back_spin, side_spin, spin_axis]

	# Load and append historical averages by club
	var stats_path = "user://player_club_stats.json"
	if FileAccess.file_exists(stats_path):
		var file = FileAccess.open(stats_path, FileAccess.READ)
		if file != null:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
				var player_club_stats = json.data.get(player_name, {})
				if not player_club_stats.is_empty():
					body += "\nPLAYER CLUB STATISTICS (HISTORICAL AVERAGES):\n"
					body += "=============================================\n"
					body += "%-6s | %-10s | %-10s | %-9s | %-12s | %-14s\n" % ["Club", "Avg Carry", "Avg Speed", "Avg Spin", "Avg Offline", "Avg +/- Target"]
					body += "--------------------------------------------------------------------------------\n"
					
					var club_order = ["Dr", "3w", "5w", "2H", "3H", "4H", "1i", "2i", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"]
					for c in player_club_stats.keys():
						if not club_order.has(c):
							club_order.append(c)
							
					for club in club_order:
						if not player_club_stats.has(club) or player_club_stats[club].is_empty():
							continue
							
						var club_shots = player_club_stats[club]
						var sum_carry := 0.0
						var sum_speed := 0.0
						var sum_spin := 0.0
						var sum_offline := 0.0
						var sum_target_diff := 0.0
						var valid_target_diff_count := 0
						
						for shot in club_shots:
							sum_carry += float(shot.get("CarryDistance", 0.0))
							sum_speed += float(shot.get("Speed", 0.0))
							sum_spin += float(shot.get("TotalSpin", 0.0))
							sum_offline += absf(float(shot.get("SideDistance", 0.0)))
							
							var target_dist = float(shot.get("TargetDistance", 0.0))
							var total_dist = float(shot.get("TotalDistance", 0.0))
							if target_dist > 0.0:
								sum_target_diff += (total_dist - target_dist)
								valid_target_diff_count += 1
								
						var cnt = club_shots.size()
						var avg_carry = sum_carry / cnt
						var avg_speed = sum_speed / cnt
						var avg_spin = sum_spin / cnt
						var avg_offline = sum_offline / cnt
						var avg_target_diff = sum_target_diff / valid_target_diff_count if valid_target_diff_count > 0 else 0.0
						
						# Convert to imperial values for the email scorecard
						var carry_val = avg_carry * 1.09361
						var speed_val = avg_speed
						var spin_val = avg_spin
						var offline_val = avg_offline * 1.09361
						var target_diff_val = avg_target_diff * 1.09361
						
						var carry_str = "%.1f yds" % carry_val
						var speed_str = "%.1f mph" % speed_val
						var spin_str = "%.0f rpm" % spin_val
						var offline_str = "%.1f yds" % offline_val
						var target_diff_sign = "+" if target_diff_val >= 0.0 else ""
						var target_diff_str = "%s%.1f yds" % [target_diff_sign, target_diff_val]
						
						if valid_target_diff_count == 0:
							target_diff_str = "---"
							
						body += "%-6s | %-10s | %-10s | %-9s | %-12s | %-14s\n" % [club, carry_str, speed_str, spin_str, offline_str, target_diff_str]
					body += "\n"
		
	var mailto_url = "mailto:?subject=%s&body=%s" % [subject.uri_encode(), body.uri_encode()]
	OS.shell_open(mailto_url)
	print("[HistoryMenu] Opened email client for %s" % player_name)

func apply_button_style(btn: Button, bg_color: Color) -> void:
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.content_margin_left = 12
	style_normal.content_margin_right = 12
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.12)
	
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.12)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color(0.9, 0.9, 0.9))
	btn.add_theme_font_size_override("font_size", 14)
