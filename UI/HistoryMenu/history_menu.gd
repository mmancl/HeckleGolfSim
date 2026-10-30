extends Control

const ScorecardBadge = preload("res://UI/scorecard_badge.gd")
const HoleShotPathDiagram = preload("res://UI/hole_shot_path_diagram.gd")

@onready var matches_list_vbox = VBoxContainer.new()
@onready var delete_confirm_dialog = ConfirmationDialog.new()

var selected_match_to_delete: Dictionary = {}
var scorecard_overlay: ColorRect

# Shot Review state for the history scorecard overlay
var _shot_review_container: VBoxContainer = null
var _shot_review_selected_hole: String = ""
var _shot_review_match_data: Dictionary = {}
var _shot_review_cards_container: VBoxContainer = null
var _shot_review_hole_btns: Array = []

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
	title_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	header_hbox.add_child(title_lbl)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)
	
	var back_btn = Button.new()
	back_btn.text = "Main Menu"
	back_btn.icon = load("res://UI/MainMenu/images/menu.svg")
	back_btn.expand_icon = true
	back_btn.custom_minimum_size = Vector2(160, 48)
	back_btn.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_nav_button_style(back_btn)
	back_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
	header_hbox.add_child(back_btn)
	
	# Scrollable area for matches list
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(scroll_container, 28)
	main_vbox.add_child(scroll_container)
	
	matches_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	matches_list_vbox.add_theme_constant_override("separation", 16)
	scroll_container.add_child(matches_list_vbox)
	
	# Deletion Confirmation Dialog
	delete_confirm_dialog.title = "Delete Match"
	delete_confirm_dialog.dialog_text = "Are you sure you want to delete this match from history?"
	delete_confirm_dialog.min_size = Vector2(480, 180)
	ThemeManager.apply_dialog_style(delete_confirm_dialog)
	delete_confirm_dialog.confirmed.connect(_confirm_delete_match)
	add_child(delete_confirm_dialog)
	
	# Setup Scorecard overlay
	_setup_scorecard_overlay()
	
	# Load and render matches
	_render_history_list()
	call_deferred("_grab_initial_focus")


func _grab_initial_focus() -> void:
	if not is_visible_in_tree():
		return
	if has_node("/root/KeybindingManager"):
		var km = get_node("/root/KeybindingManager")
		km.focus_first_control(self)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if has_node("/root/UIFocusGuard"):
		var ufg = get_node("/root/UIFocusGuard")
		if ufg.is_modal_active():
			return
	if event.is_action_pressed("ui_cancel"):
		if delete_confirm_dialog != null and delete_confirm_dialog.visible:
			delete_confirm_dialog.visible = false
			get_viewport().set_input_as_handled()
			return
		if scorecard_overlay != null and scorecard_overlay.visible:
			scorecard_overlay.visible = false
			get_viewport().set_input_as_handled()
			return
		SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
		get_viewport().set_input_as_handled()


func _setup_scorecard_overlay() -> void:
	scorecard_overlay = ColorRect.new()
	scorecard_overlay.visible = false
	scorecard_overlay.color = Color(0.0, 0.0, 0.0, 0.8)
	scorecard_overlay.anchor_left = 0.0
	scorecard_overlay.anchor_right = 1.0
	scorecard_overlay.anchor_top = 0.0
	scorecard_overlay.anchor_bottom = 1.0
	add_child(scorecard_overlay)
	
	var card_panel = PanelContainer.new()
	card_panel.name = "CardPanel"
	card_panel.anchor_left = 0.02
	card_panel.anchor_right = 0.98
	card_panel.anchor_top = 0.03
	card_panel.anchor_bottom = 0.97
	card_panel.offset_left = 0
	card_panel.offset_right = 0
	card_panel.offset_top = 0
	card_panel.offset_bottom = 0
	card_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	ThemeManager.apply_modal_style(card_panel, 12)
	scorecard_overlay.add_child(card_panel)

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

		var mode_lbl = Label.new()
		var g_mode = match_data.get("game_mode", "Standard")
		mode_lbl.text = "[%s]" % g_mode
		mode_lbl.add_theme_font_size_override("font_size", 16)
		mode_lbl.add_theme_color_override("font_color", Color(0.35, 0.75, 0.9))
		title_hbox.add_child(mode_lbl)
		
		var status_lbl = Label.new()
		var is_finished = match_data.get("is_finished", false)
		if is_finished:
			status_lbl.text = "[Finished]"
			status_lbl.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		else:
			status_lbl.text = "[In Progress]"
			status_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
		status_lbl.add_theme_font_size_override("font_size", 16)
		title_hbox.add_child(status_lbl)
		
		var players_lbl = Label.new()
		var players_array = match_data.get("players", [])
		var names = []
		for p in players_array:
			var p_str = p.get("name", "Player")
			if not p.get("team", "").is_empty() and g_mode == "2v2 Scramble":
				p_str += " (%s)" % p.get("team")
			names.append(p_str)
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
			resume_btn.custom_minimum_size = Vector2(120, 48)
			apply_button_style(resume_btn, Color(0.72, 0.56, 0.24, 0.85)) # Gold
			resume_btn.pressed.connect(func():
				MultiplayerManager.resume_match(match_data)
			)
			btn_hbox.add_child(resume_btn)
			
		var card_btn = Button.new()
		card_btn.text = "Scorecard"
		card_btn.custom_minimum_size = Vector2(120, 48)
		apply_button_style(card_btn, Color(0.24, 0.46, 0.72, 0.85)) # Blue
		card_btn.pressed.connect(func():
			_show_scorecard(match_data)
		)
		btn_hbox.add_child(card_btn)
		
		var delete_btn = Button.new()
		delete_btn.text = "Delete"
		delete_btn.custom_minimum_size = Vector2(100, 48)
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
	# Reset shot review state
	_shot_review_container = null
	_shot_review_selected_hole = ""
	_shot_review_match_data = match_data.duplicate()
	_shot_review_cards_container = null
	_shot_review_hole_btns.clear()

	# Clear scorecard panel container children except background/structure
	var card_panel = scorecard_overlay.get_node_or_null("CardPanel") as PanelContainer
	if card_panel == null and scorecard_overlay.get_child_count() > 0:
		card_panel = scorecard_overlay.get_child(0) as PanelContainer
	if card_panel == null:
		return
		
	for child in card_panel.get_children():
		child.queue_free()
		
	var card_vbox = VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 16)
	card_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	card_panel.add_child(card_vbox)
	
	# Header title
	var head_hbox = HBoxContainer.new()
	card_vbox.add_child(head_hbox)
	
	var g_mode = match_data.get("game_mode", "Standard")
	var title_lbl = Label.new()
	title_lbl.text = "Scorecard - %s [%s Mode]" % [match_data.get("course_title", "Course"), g_mode]
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 4)
	head_hbox.add_child(title_lbl)
	
	var date_lbl = Label.new()
	date_lbl.text = "Played on: %s" % match_data.get("formatted_date", "Date")
	date_lbl.add_theme_font_size_override("font_size", 16)
	date_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	date_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	date_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	date_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head_hbox.add_child(date_lbl)
	
	# Combined scroll area: grid scorecard + shot review
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ThemeManager.apply_scroll_container_style(scroll, 28)
	card_vbox.add_child(scroll)
	
	# Scrollable content vbox (grid + shot review stacked vertically)
	var scroll_content = VBoxContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.add_theme_constant_override("separation", 20)
	scroll.add_child(scroll_content)
	
	var grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	scroll_content.add_child(grid)
	
	# Populate Grid
	_populate_grid_scorecard(grid, match_data)
	
	# Shot Review section separator
	var sep_lbl = Label.new()
	sep_lbl.text = "📍 Shot Review"
	sep_lbl.add_theme_font_size_override("font_size", 20)
	sep_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	sep_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	sep_lbl.add_theme_constant_override("outline_size", 3)
	sep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scroll_content.add_child(sep_lbl)
	
	# Shot Review VBox
	_shot_review_container = VBoxContainer.new()
	_shot_review_container.name = "ShotReviewContainer"
	_shot_review_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shot_review_container.add_theme_constant_override("separation", 12)
	scroll_content.add_child(_shot_review_container)
	
	_populate_shot_review_hole_selector(match_data)
	
	# Actions row
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_vbox.add_child(action_hbox)
	
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(160, 48)
	apply_button_style(close_btn, Color(0.3, 0.35, 0.4, 0.9))
	close_btn.pressed.connect(func(): scorecard_overlay.visible = false)
	action_hbox.add_child(close_btn)
	
	scorecard_overlay.visible = true

func _populate_grid_scorecard(grid: GridContainer, match_data: Dictionary) -> void:
	var g_mode = match_data.get("game_mode", "Standard")
	var is_ctp_mode = (g_mode == "Closest to Pin")
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
					hole_pars[h_id] = int(round(float(h_data.get("Par", 4))))
					var tee_boxes = h_data.get("Tee Boxes", {})
					var tee_pos = tee_boxes.get(tee_color, [0.0, 0.0])
					var hole_loc = h_data.get("Hole Location", [0.0, 0.0])
					var dist = int(Vector2(tee_pos[0], tee_pos[1]).distance_to(Vector2(hole_loc[0], hole_loc[1])) * 1.09361)
					hole_dists[h_id] = dist

	# Fallback if hole_pars is empty but match_data has saved hole_pars
	if hole_pars.is_empty() and match_data.has("hole_pars"):
		var saved_pars = match_data.get("hole_pars", {})
		if typeof(saved_pars) == TYPE_DICTIONARY:
			for h_id in saved_pars:
				hole_pars[h_id] = int(round(float(saved_pars[h_id])))

	# Holes list sorted
	var hole_ids: Array = []
	if match_data.has("hole_ids") and not match_data["hole_ids"].is_empty():
		hole_ids = match_data["hole_ids"].duplicate()
	else:
		hole_ids = hole_pars.keys()
		hole_ids.sort_custom(func(a, b):
			return MultiplayerManager.get_hole_number_from_id(a) < MultiplayerManager.get_hole_number_from_id(b)
		)
		var course_len = match_data.get("selected_course_length", "Full 18")
		if course_len == "Back 9":
			hole_ids = hole_ids.filter(func(h_id): return MultiplayerManager.get_hole_number_from_id(h_id) >= 10)
		elif course_len == "Front 9":
			hole_ids = hole_ids.filter(func(h_id): return MultiplayerManager.get_hole_number_from_id(h_id) <= 9)
	var num_holes = hole_ids.size()
	
	if num_holes == 0:
		# Fallback if config is missing
		for i in range(18):
			hole_ids.append("Hole " + str(i + 1))
		num_holes = 18
		
	# Split into Front 9 and Back 9
	var front_holes = []
	var back_holes = []
	for h_id in hole_ids:
		var h_num = MultiplayerManager.get_hole_number_from_id(h_id)
		if h_num <= 9:
			front_holes.append(h_id)
		else:
			back_holes.append(h_id)
			
	var has_both_nines = not front_holes.is_empty() and not back_holes.is_empty()

	# Columns: Player | front holes | [OUT/TOT] | back holes | [IN] | [TOT if both]
	var columns = ["Player"]
	if not front_holes.is_empty():
		for h_id in front_holes:
			columns.append(str(MultiplayerManager.get_hole_number_from_id(h_id)))
		if not back_holes.is_empty():
			columns.append("OUT")
		else:
			columns.append("TOT")
	if not back_holes.is_empty():
		for h_id in back_holes:
			columns.append(str(MultiplayerManager.get_hole_number_from_id(h_id)))
		columns.append("IN")
	if has_both_nines:
		columns.append("TOT")
	
	grid.columns = columns.size()
	
	var header_bg = Color(0.10, 0.14, 0.22, 0.96)
	var par_bg = Color(0.16, 0.22, 0.34, 0.88)
	var dist_bg = Color(0.13, 0.18, 0.28, 0.88)
	
	# Cell addition helper
	var add_cell = func(parent_grid: GridContainer, text: String, bg: Color, is_header: bool = false, fg: Color = Color.WHITE, font_size: int = 16):
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(48, 38)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_FILL
		var style = StyleBoxFlat.new()
		style.bg_color = bg
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.35, 0.45, 0.35)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		cell.add_theme_stylebox_override("panel", style)
		
		var label = Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", fg)
		label.add_theme_font_size_override("font_size", font_size)
		if is_header:
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 3)
		cell.add_child(label)
		parent_grid.add_child(cell)
		return cell

	# Score cell addition helper with golfer lingo badges
	var add_score_cell = func(parent_grid: GridContainer, text: String, par: int, bg: Color, is_ctp: bool = false, font_size: int = 16):
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(48, 38)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_FILL
		var style = StyleBoxFlat.new()
		style.bg_color = bg
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.35, 0.45, 0.35)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		cell.add_theme_stylebox_override("panel", style)
		
		var widget = ScorecardBadge.create_score_widget(text, par, is_ctp, font_size)
		cell.add_child(widget)
		parent_grid.add_child(cell)
		return cell

	# 1. HEADER ROW
	for col in columns:
		add_cell.call(grid, col, header_bg, true, Color.WHITE, 16)
		
	# 2. DISTANCE ROW (Yards)
	add_cell.call(grid, "Yds (%s)" % tee_color, dist_bg, false, Color(0.8, 0.8, 0.8), 15)
	var front_dist_sum = 0
	for h_id in front_holes:
		var d = hole_dists.get(h_id, 0)
		front_dist_sum += d
		add_cell.call(grid, str(d) if d > 0 else "-", dist_bg, false, Color(0.8, 0.8, 0.8), 15)
	if not front_holes.is_empty():
		add_cell.call(grid, str(front_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9), 15)
	var back_dist_sum = 0
	for h_id in back_holes:
		var d = hole_dists.get(h_id, 0)
		back_dist_sum += d
		add_cell.call(grid, str(d) if d > 0 else "-", dist_bg, false, Color(0.8, 0.8, 0.8), 15)
	if not back_holes.is_empty():
		add_cell.call(grid, str(back_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9), 15)
	if has_both_nines:
		add_cell.call(grid, str(front_dist_sum + back_dist_sum), dist_bg, false, Color(1.0, 0.85, 0.38), 15)

	# 3. PAR ROW
	add_cell.call(grid, "Par", par_bg, false, Color(0.8, 0.8, 0.8), 15)
	var front_par_sum: int = 0
	for h_id in front_holes:
		var p_val: int = int(round(float(hole_pars.get(h_id, 4))))
		front_par_sum += p_val
		add_cell.call(grid, str(p_val), par_bg, false, Color(0.8, 0.8, 0.8), 15)
	if not front_holes.is_empty():
		add_cell.call(grid, str(front_par_sum), par_bg, false, Color(0.9, 0.9, 0.9), 15)
	var back_par_sum: int = 0
	for h_id in back_holes:
		var p_val: int = int(round(float(hole_pars.get(h_id, 4))))
		back_par_sum += p_val
		add_cell.call(grid, str(p_val), par_bg, false, Color(0.8, 0.8, 0.8), 15)
	if not back_holes.is_empty():
		add_cell.call(grid, str(back_par_sum), par_bg, false, Color(0.9, 0.9, 0.9), 15)
	if has_both_nines:
		var total_par: int = front_par_sum + back_par_sum
		add_cell.call(grid, str(total_par), par_bg, false, Color(1.0, 0.85, 0.38), 15)

	# 4. PLAYER ROWS
	for p_idx in range(players_list.size()):
		var p = players_list[p_idx]
		var row_bg = Color(0.14, 0.16, 0.20, 0.94) if p_idx % 2 == 0 else Color(0.09, 0.11, 0.14, 0.94)
		
		# Name cell with Email button!
		var name_cell = PanelContainer.new()
		name_cell.custom_minimum_size = Vector2(180, 38)
		name_cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_cell.size_flags_vertical = Control.SIZE_FILL
		var cell_style = StyleBoxFlat.new()
		cell_style.bg_color = row_bg
		cell_style.border_width_right = 1
		cell_style.border_width_bottom = 1
		cell_style.border_color = Color(0.3, 0.35, 0.45, 0.35)
		cell_style.content_margin_left = 8
		cell_style.content_margin_right = 8
		cell_style.content_margin_top = 4
		cell_style.content_margin_bottom = 4
		name_cell.add_theme_stylebox_override("panel", cell_style)
		grid.add_child(name_cell)
		
		var name_hbox = HBoxContainer.new()
		name_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_hbox.add_theme_constant_override("separation", 8)
		name_cell.add_child(name_hbox)
		
		var p_name = p.get("name", "Player")
		var avatar_path = p.get("avatar", "")
		if avatar_path.is_empty():
			avatar_path = MultiplayerManager.get_player_avatar(p_name)
		
		if not avatar_path.is_empty() and ResourceLoader.exists(avatar_path):
			var av_rect = TextureRect.new()
			av_rect.texture = load(avatar_path)
			av_rect.custom_minimum_size = Vector2(24, 24)
			av_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			av_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			av_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			name_hbox.add_child(av_rect)
		else:
			var badge = PanelContainer.new()
			badge.custom_minimum_size = Vector2(24, 24)
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var badge_style = StyleBoxFlat.new()
			var p_color = MultiplayerManager.player_colors[p_idx % MultiplayerManager.player_colors.size()]
			badge_style.bg_color = p_color
			badge_style.corner_radius_top_left = 12
			badge_style.corner_radius_top_right = 12
			badge_style.corner_radius_bottom_left = 12
			badge_style.corner_radius_bottom_right = 12
			badge.add_theme_stylebox_override("panel", badge_style)
			var badge_lbl = Label.new()
			badge_lbl.text = p_name.substr(0, 1).to_upper()
			badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge_lbl.add_theme_font_size_override("font_size", 12)
			badge.add_child(badge_lbl)
			name_hbox.add_child(badge)
		
		var name_lbl = Label.new()
		var p_tee = p.get("tee", "Blue")
		name_lbl.text = "%s (%s)" % [p_name, p_tee]
		var name_fg = Color.WHITE
		if not p.get("active", true):
			name_lbl.text += " (Out)"
			name_fg = Color(0.6, 0.6, 0.6)
		name_lbl.add_theme_color_override("font_color", name_fg)
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_hbox.add_child(name_lbl)
		
		# Tee color chip/indicator
		var tee_dot = PanelContainer.new()
		tee_dot.custom_minimum_size = Vector2(10, 10)
		tee_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var dot_style = StyleBoxFlat.new()
		dot_style.bg_color = TeeboxMarkerBuilder.get_tee_color(p_tee)
		dot_style.corner_radius_top_left = 5
		dot_style.corner_radius_top_right = 5
		dot_style.corner_radius_bottom_left = 5
		dot_style.corner_radius_bottom_right = 5
		dot_style.border_width_left = 1
		dot_style.border_width_top = 1
		dot_style.border_width_right = 1
		dot_style.border_width_bottom = 1
		dot_style.border_color = Color(0.1, 0.1, 0.1, 0.8) if dot_style.bg_color.get_luminance() > 0.5 else Color(0.9, 0.9, 0.9, 0.8)
		tee_dot.add_theme_stylebox_override("panel", dot_style)
		name_hbox.add_child(tee_dot)
		
		# Email stats button next to player name
		var email_btn = Button.new()
		email_btn.text = "✉"
		email_btn.custom_minimum_size = Vector2(30, 30)
		email_btn.add_theme_font_size_override("font_size", 13)
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
			var par = int(round(float(hole_pars.get(h_id, 4))))
			if s != null:
				var s_num = int(round(float(s)))
				display_s = str(s_num)
				front_sum += s_num
			add_score_cell.call(grid, display_s, par, row_bg, is_ctp_mode, 16)
			
		if not front_holes.is_empty():
			add_cell.call(grid, str(front_sum) if front_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9))
			
		# Back scores
		var back_sum = 0
		for h_id in back_holes:
			var s = hole_scores.get(h_id)
			var display_s = "-"
			var par = int(round(float(hole_pars.get(h_id, 4))))
			if s != null:
				var s_num = int(round(float(s)))
				display_s = str(s_num)
				back_sum += s_num
			add_score_cell.call(grid, display_s, par, row_bg, is_ctp_mode, 16)
			
		if not back_holes.is_empty():
			add_cell.call(grid, str(back_sum) if back_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9))
			
		if has_both_nines:
			var total = front_sum + back_sum
			var tot_str = str(total) if total > 0 else "-"
			if is_ctp_mode:
				tot_str = "%d pts" % total
			add_cell.call(grid, tot_str, row_bg, false, Color(1.0, 0.85, 0.38))

func _email_player_stats(player: Dictionary, match_data: Dictionary) -> void:
	var course_title = match_data.get("course_title", "Unknown Course")
	var date_str = match_data.get("formatted_date", "Unknown Date")
	var player_name = player.get("name", "Player")
	var tee = player.get("tee", "Blue")
	
	var subject = "Heckle Golf Simulator stats: %s - %s (%s)" % [player_name, course_title, date_str]
	
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
					pars[h_id] = int(round(float(hole_info[h_id].get("Par", 4))))
					var tee_info = hole_info[h_id].get("Tee Info", {})
					distances[h_id] = {}
					for t_name in tee_info.keys():
						distances[h_id][t_name] = tee_info[t_name].get("Distance", 0)

	var hole_scores = player.get("hole_scores", {})
	if hole_ids_list.is_empty():
		hole_ids_list = hole_scores.keys()
		hole_ids_list.sort()

	# Build concise, high-level email summary
	var body = ""
	body += "HECKLE GOLF SIMULATOR ROUND STATS\n"
	body += "=================================\n"
	body += "Player: %s (%s Tee)\n" % [player_name, tee]
	body += "Course: %s\n" % course_title
	body += "Date: %s\n" % date_str
	body += "Total Strokes: %d\n\n" % player.get("total_strokes", 0)
	
	body += "HOLE-BY-HOLE SCORES:\n"
	body += "--------------------\n"
	for h_id in hole_ids_list:
		var score = hole_scores.get(h_id)
		var score_str = "-"
		if score != null:
			score_str = str(score)
		var par_val = pars.get(h_id, 4)
		body += "Hole %s (Par %d): %s\n" % [h_id, par_val, score_str]

	# Build match data dictionary for CSV exporter
	var export_match_data = match_data.duplicate()
	export_match_data["pars"] = pars
	export_match_data["distances"] = distances
	export_match_data["hole_ids"] = hole_ids_list
	
	# Generate golf data CSV
	var csv_content = GolfDataExporter.generate_round_csv(player, export_match_data)
	var safe_player = GolfDataExporter.sanitize_filename(player_name)
	var safe_course = GolfDataExporter.sanitize_filename(course_title)
	var safe_date = GolfDataExporter.sanitize_filename(date_str)
	var attachment_basename = "%s_%s_%s_golf_data" % [safe_player, safe_course, safe_date]

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
							var s_dist = absf(float(shot.get("SideDistance", 0.0)))
							var t_dist = absf(float(shot.get("TotalDistance", shot.get("CarryDistance", 0.0))))
							if s_dist > 100.0 or (t_dist > 15.0 and s_dist > t_dist * 1.2):
								s_dist = 0.0
							sum_offline += s_dist
							
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
		
	body += MultiplayerManager.format_player_swing_issues_summary(player_name)
	
	var to_email = player.get("email", "")
	if to_email.is_empty():
		to_email = MultiplayerManager.get_player_email(player_name)

	GolfDataExporter.export_and_email(to_email, subject, body, attachment_basename, csv_content)
	print("[HistoryMenu] Opened email client with attached CSV for %s" % player_name)

# ── Shot Review helpers ────────────────────────────────────────────────────────

func _populate_shot_review_hole_selector(match_data: Dictionary) -> void:
	if _shot_review_container == null:
		return

	# Build ordered hole list (mirrors _populate_grid_scorecard logic)
	var hole_pars: Dictionary = {}
	var config_path: String = match_data.get("config_path", "")
	if not config_path.is_empty() and FileAccess.file_exists(config_path):
		var f = FileAccess.open(config_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				for h_id in parsed.get("Hole Info", {}).keys():
					hole_pars[h_id] = int(round(float(parsed["Hole Info"][h_id].get("Par", 4))))
	if hole_pars.is_empty() and match_data.has("hole_pars"):
		var saved_pars = match_data.get("hole_pars", {})
		if typeof(saved_pars) == TYPE_DICTIONARY:
			for h_id in saved_pars:
				hole_pars[h_id] = int(round(float(saved_pars[h_id])))

	var hole_ids: Array = []
	if match_data.has("hole_ids") and not match_data["hole_ids"].is_empty():
		hole_ids = match_data["hole_ids"].duplicate()
	else:
		hole_ids = hole_pars.keys()
		hole_ids.sort_custom(func(a, b):
			return MultiplayerManager.get_hole_number_from_id(a) < MultiplayerManager.get_hole_number_from_id(b)
		)
		var course_len = match_data.get("selected_course_length", "Full 18")
		if course_len == "Back 9":
			hole_ids = hole_ids.filter(func(h_id): return MultiplayerManager.get_hole_number_from_id(h_id) >= 10)
		elif course_len == "Front 9":
			hole_ids = hole_ids.filter(func(h_id): return MultiplayerManager.get_hole_number_from_id(h_id) <= 9)

	if hole_ids.is_empty():
		var no_data_lbl = Label.new()
		no_data_lbl.text = "No shot data available for this match."
		no_data_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_data_lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
		no_data_lbl.add_theme_font_size_override("font_size", 15)
		_shot_review_container.add_child(no_data_lbl)
		return

	# Hint label
	var hint_lbl = Label.new()
	hint_lbl.text = "Select a hole to view the shot path diagram:"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 14)
	hint_lbl.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
	_shot_review_container.add_child(hint_lbl)

	# Hole selector buttons (scrollable row)
	var btn_scroll = ScrollContainer.new()
	btn_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	btn_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	btn_scroll.custom_minimum_size = Vector2(0, 52)
	_shot_review_container.add_child(btn_scroll)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 6)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_scroll.add_child(btn_hbox)

	_shot_review_hole_btns.clear()
	for h_id in hole_ids:
		var h_num = MultiplayerManager.get_hole_number_from_id(h_id)
		var par_val = hole_pars.get(h_id, 4)
		var btn = Button.new()
		btn.text = str(h_num)
		btn.tooltip_text = "Hole %d (Par %d)" % [h_num, par_val]
		btn.custom_minimum_size = Vector2(44, 44)
		apply_button_style(btn, Color(0.15, 0.20, 0.28, 0.90))
		btn.pressed.connect(func():
			_on_shot_review_hole_selected(h_id, hole_ids, match_data)
		)
		btn_hbox.add_child(btn)
		_shot_review_hole_btns.append({"btn": btn, "hole_id": h_id})

	# Cards area (replaced each time a hole is selected)
	_shot_review_cards_container = VBoxContainer.new()
	_shot_review_cards_container.name = "ShotReviewCards"
	_shot_review_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shot_review_cards_container.add_theme_constant_override("separation", 12)
	_shot_review_container.add_child(_shot_review_cards_container)

	# Auto-select first hole that has shot data
	for h_id in hole_ids:
		if _history_hole_has_shot_data(match_data, h_id):
			_on_shot_review_hole_selected(h_id, hole_ids, match_data)
			return
	# No shot data at all - show placeholder
	_on_shot_review_hole_selected(hole_ids[0], hole_ids, match_data)


func _history_hole_has_shot_data(match_data: Dictionary, hole_id: String) -> bool:
	var players_list: Array = match_data.get("players", [])
	for p in players_list:
		var player_stats = p.get("shot_stats", {})
		if typeof(player_stats) == TYPE_DICTIONARY and player_stats.has(hole_id):
			var shots = player_stats[hole_id]
			if typeof(shots) == TYPE_ARRAY and not shots.is_empty():
				return true
	return false


func _on_shot_review_hole_selected(hole_id: String, hole_ids: Array, match_data: Dictionary) -> void:
	_shot_review_selected_hole = hole_id

	# Update button styles to highlight selected hole
	for entry in _shot_review_hole_btns:
		var is_selected = (entry["hole_id"] == hole_id)
		var color = Color(0.24, 0.50, 0.82, 0.95) if is_selected else Color(0.15, 0.20, 0.28, 0.90)
		apply_button_style(entry["btn"], color)

	# Clear previous cards
	if _shot_review_cards_container == null:
		return
	for child in _shot_review_cards_container.get_children():
		child.queue_free()

	_build_shot_review_for_hole(hole_id, match_data)


func _build_shot_review_for_hole(hole_id: String, match_data: Dictionary) -> void:
	if _shot_review_cards_container == null:
		return

	var h_num = MultiplayerManager.get_hole_number_from_id(hole_id)
	var players_list: Array = match_data.get("players", [])

	# Load course config for green positions, tee boxes, satellite, cart paths
	var config_path: String = match_data.get("config_path", "")
	var hole_info: Dictionary = {}
	var satellite_texture: Texture2D = null
	var satellite_bounds: Array = []
	var cart_paths: Array[PackedVector2Array] = []

	if not config_path.is_empty() and FileAccess.file_exists(config_path):
		var f = FileAccess.open(config_path, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				hole_info = parsed.get("Hole Info", {})
				# Satellite image
				var sat_path = config_path.get_base_dir().path_join("satellite.png")
				if FileAccess.file_exists(sat_path):
					var img = Image.load_from_file(sat_path)
					if img != null and not img.is_empty():
						satellite_texture = ImageTexture.create_from_image(img)
				# Satellite bounds from course_info if available
				var course_info_val = parsed.get("Course Info", {})
				if typeof(course_info_val) == TYPE_DICTIONARY:
					var bounds_version := int(course_info_val.get("Satellite Image Bounds Version", 0))
					if bounds_version == 5:
						var saved_bounds = course_info_val.get("Satellite Image Bounds", [])
						if typeof(saved_bounds) == TYPE_ARRAY:
							satellite_bounds = saved_bounds
				# Cart paths
				var saved_cart_paths = parsed.get("Cart Paths", [])
				if typeof(saved_cart_paths) != TYPE_ARRAY:
					saved_cart_paths = parsed.get("Course Info", {}).get("Cart Paths", [])
				if typeof(saved_cart_paths) == TYPE_ARRAY:
					for saved_path in saved_cart_paths:
						if typeof(saved_path) != TYPE_ARRAY:
							continue
						var cart_path := PackedVector2Array()
						for saved_point in saved_path:
							if typeof(saved_point) == TYPE_ARRAY and saved_point.size() >= 2:
								cart_path.append(Vector2(float(saved_point[0]), float(saved_point[1])))
						if cart_path.size() >= 2:
							cart_paths.append(cart_path)

	var current_hole_info: Dictionary = hole_info.get(hole_id, {})
	var hole_location: Array = current_hole_info.get("Hole Location", [0.0, 0.0])
	var green_position := Vector3.ZERO
	if hole_location.size() >= 2:
		green_position = Vector3(float(hole_location[0]), 0.0, float(hole_location[1]))

	var tee_boxes: Dictionary = current_hole_info.get("Tee Boxes", {})
	var hole_tee_positions: Array[Vector3] = []
	for tee_val in tee_boxes.values():
		if typeof(tee_val) == TYPE_ARRAY and tee_val.size() >= 2:
			hole_tee_positions.append(Vector3(float(tee_val[0]), 0.0, float(tee_val[1])))

	var hole_par = int(round(float(current_hole_info.get("Par", 4))))

	# Hole header
	var hole_title = Label.new()
	hole_title.text = "Hole %d Shot Review (Par %d)" % [h_num, hole_par]
	hole_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hole_title.add_theme_font_size_override("font_size", 17)
	hole_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	hole_title.add_theme_color_override("font_outline_color", Color.BLACK)
	hole_title.add_theme_constant_override("outline_size", 3)
	_shot_review_cards_container.add_child(hole_title)

	# Collect all player positions for shared context (so the diagram sizes correctly)
	var shared_shot_positions: Array[Vector3] = []
	for p in players_list:
		var p_positions := _get_history_hole_shot_positions(p, hole_id, tee_boxes)
		shared_shot_positions.append_array(p_positions)

	# Player cards grid
	var cards_wrapper = HBoxContainer.new()
	cards_wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shot_review_cards_container.add_child(cards_wrapper)

	var player_cards = GridContainer.new()
	player_cards.name = "ShotReviewPlayerCards"
	player_cards.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	player_cards.add_theme_constant_override("h_separation", 16)
	player_cards.add_theme_constant_override("v_separation", 16)
	cards_wrapper.add_child(player_cards)

	var max_cols = mini(players_list.size(), maxi(1, int(floor(1200.0 / 260.0))))
	player_cards.columns = max(1, max_cols)

	var image_size := Vector2(220.0, 220.0)

	for p_idx in range(players_list.size()):
		var p: Dictionary = players_list[p_idx]
		var p_name: String = p.get("name", "Player")
		var hole_scores: Dictionary = p.get("hole_scores", {})
		var score_val = hole_scores.get(hole_id)

		var positions := _get_history_hole_shot_positions(p, hole_id, tee_boxes)
		var shot_distances: Array[int] = []
		for i in range(maxi(0, positions.size() - 1)):
			var dist_yds = Vector2(positions[i].x, positions[i].z).distance_to(Vector2(positions[i + 1].x, positions[i + 1].z)) * 1.09361
			shot_distances.append(int(round(dist_yds)))

		# Player card panel
		var player_card = PanelContainer.new()
		player_card.custom_minimum_size = Vector2(image_size.x + 24.0, 0)
		player_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
		card_style.border_width_left = 2
		card_style.border_width_top = 2
		card_style.border_width_right = 2
		card_style.border_width_bottom = 2
		card_style.corner_radius_top_left = 16
		card_style.corner_radius_top_right = 16
		card_style.corner_radius_bottom_left = 16
		card_style.corner_radius_bottom_right = 16
		var player_color := Color(0.35, 0.65, 0.9)
		var color_value = p.get("color")
		if typeof(color_value) == TYPE_COLOR:
			player_color = color_value
		card_style.border_color = player_color
		card_style.content_margin_left = 12
		card_style.content_margin_right = 12
		card_style.content_margin_top = 10
		card_style.content_margin_bottom = 12
		player_card.add_theme_stylebox_override("panel", card_style)
		player_cards.add_child(player_card)

		var player_row = VBoxContainer.new()
		player_row.add_theme_constant_override("separation", 6)
		player_card.add_child(player_row)

		# Score header label
		var score_text: String
		if score_val == null:
			score_text = "No score"
		else:
			score_text = "%d strokes" % int(round(float(score_val)))
		var score_label = Label.new()
		score_label.text = "%s — %s · %d shots" % [p_name, score_text, shot_distances.size()]
		score_label.add_theme_font_size_override("font_size", 15)
		score_label.add_theme_color_override("font_color", Color.WHITE)
		score_label.clip_text = true
		player_row.add_child(score_label)

		if shot_distances.is_empty():
			var no_shots_lbl = Label.new()
			no_shots_lbl.text = "No shots recorded for Hole %d" % h_num
			no_shots_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			no_shots_lbl.add_theme_font_size_override("font_size", 13)
			no_shots_lbl.add_theme_color_override("font_color", Color(0.65, 0.68, 0.75))
			no_shots_lbl.custom_minimum_size = Vector2(image_size.x, 80)
			no_shots_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			player_row.add_child(no_shots_lbl)
		else:
			var diagram_frame = PanelContainer.new()
			diagram_frame.name = "DiagramFrame"
			diagram_frame.clip_contents = true
			var frame_style = StyleBoxFlat.new()
			frame_style.bg_color = Color(0.04, 0.07, 0.10, 0.95)
			frame_style.border_width_left = 1
			frame_style.border_width_top = 1
			frame_style.border_width_right = 1
			frame_style.border_width_bottom = 1
			frame_style.border_color = Color(0.35, 0.45, 0.60, 0.5)
			frame_style.corner_radius_top_left = 12
			frame_style.corner_radius_top_right = 12
			frame_style.corner_radius_bottom_left = 12
			frame_style.corner_radius_bottom_right = 12
			diagram_frame.add_theme_stylebox_override("panel", frame_style)

			var shot_path = HoleShotPathDiagram.new()
			shot_path.name = "HoleShotPathDiagram"
			shot_path.custom_minimum_size = image_size
			shot_path.set_shot_path(
				positions,
				shot_distances,
				green_position,
				satellite_texture,
				satellite_bounds,
				hole_tee_positions,
				shared_shot_positions,
				cart_paths
			)
			diagram_frame.add_child(shot_path)
			player_row.add_child(diagram_frame)


func _get_history_hole_shot_positions(player: Dictionary, hole_id: String, tee_boxes: Dictionary) -> Array[Vector3]:
	# Pull shot_stats for the given hole (restored from JSON - positions are Vector3 after deserialization)
	var shot_stats: Array = []
	var player_stats = player.get("shot_stats", {})
	if typeof(player_stats) == TYPE_DICTIONARY and player_stats.has(hole_id):
		var raw = player_stats[hole_id]
		if typeof(raw) == TYPE_ARRAY:
			shot_stats = raw

	# Build fallback from tee box position
	var fallback_positions: Array[Vector3] = []
	var tee_color: String = player.get("tee", "Blue")
	var tee_position: Array = MultiplayerManager.get_tee_position_from_boxes(tee_boxes, tee_color)
	if tee_position.size() >= 2:
		fallback_positions.append(Vector3(float(tee_position[0]), 0.0, float(tee_position[1])))

	return HoleShotPathDiagram.get_positions_from_shot_stats(shot_stats, fallback_positions)


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
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", 16)
	if btn.custom_minimum_size.y < 48:
		btn.custom_minimum_size.y = 48
