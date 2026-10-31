extends Control

const ScorecardBadge = preload("res://UI/scorecard_badge.gd")
const HoleShotPathDiagram = preload("res://UI/hole_shot_path_diagram.gd")

@onready var matches_list_vbox = VBoxContainer.new()
@onready var delete_confirm_dialog = ConfirmationDialog.new()

var selected_match_to_delete: Dictionary = {}
var scorecard_overlay: ColorRect

# Scorecard and Shot Review state for the history scorecard overlay
var _scorecard_selected_hole_index: int = 0
var _current_scorecard_match_data: Dictionary = {}
var _scorecard_grid: GridContainer = null
var _shot_review_container: VBoxContainer = null
var _scorecard_scroll: ScrollContainer = null
var _scorecard_close_btn: Button = null
var _is_refreshing_scorecard: bool = false

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
	if is_inside_tree() and has_node("/root/KeybindingManager"):
		var km = get_node("/root/KeybindingManager")
		km.focus_first_control(self)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if scorecard_overlay != null and scorecard_overlay.visible:
		if _handle_scorecard_input(event):
			get_viewport().set_input_as_handled()
			return
	if is_inside_tree() and has_node("/root/UIFocusGuard"):
		var ufg = get_node("/root/UIFocusGuard")
		if ufg.is_modal_active():
			return
	if event.is_action_pressed("ui_cancel"):
		if delete_confirm_dialog != null and delete_confirm_dialog.visible:
			delete_confirm_dialog.visible = false
			get_viewport().set_input_as_handled()
			return
		if scorecard_overlay != null and scorecard_overlay.visible:
			_close_scorecard()
			get_viewport().set_input_as_handled()
			return
		SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
		get_viewport().set_input_as_handled()


func _handle_scorecard_input(event: InputEvent) -> bool:
	if scorecard_overlay == null or not scorecard_overlay.visible:
		return false

	var is_cancel = event.is_action_pressed("ui_cancel") or \
		(event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B and event.pressed) or \
		(event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed)
	if is_cancel:
		_close_scorecard()
		return true

	var hole_ids = _get_match_hole_ids(_current_scorecard_match_data)
	var num_holes = hole_ids.size()
	if num_holes == 0:
		return false

	var is_lb = (InputMap.has_action("suspense_toggle") and event.is_action_pressed("suspense_toggle")) or \
		(InputMap.has_action("prev_club") and event.is_action_pressed("prev_club")) or \
		(event is InputEventJoypadButton and event.button_index == JOY_BUTTON_LEFT_SHOULDER and event.pressed) or \
		(event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_PAGEUP)
	var is_rb = (InputMap.has_action("announcer_toggle") and event.is_action_pressed("announcer_toggle")) or \
		(InputMap.has_action("next_club") and event.is_action_pressed("next_club")) or \
		(event is InputEventJoypadButton and event.button_index == JOY_BUTTON_RIGHT_SHOULDER and event.pressed) or \
		(event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_PAGEDOWN)

	if is_lb:
		var cur = _scorecard_selected_hole_index
		var prev_idx = clampi(cur - 1, 0, num_holes - 1)
		_select_scorecard_hole(prev_idx)
		return true

	if is_rb:
		var cur = _scorecard_selected_hole_index
		var next_idx = clampi(cur + 1, 0, num_holes - 1)
		_select_scorecard_hole(next_idx)
		return true

	return false


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
				var text = f.get_as_text().strip_edges()
				if not text.is_empty():
					var json = JSON.parse_string(text)
					if typeof(json) == TYPE_DICTIONARY:
						if json.has("players") and typeof(json["players"]) == TYPE_ARRAY:
							json["players"] = MultiplayerManager.deserialize_players(json["players"])
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
	# Ensure player data is deserialized (positions, shot_stats, etc. converted back to Vector3)
	if match_data.has("players") and typeof(match_data["players"]) == TYPE_ARRAY:
		match_data["players"] = MultiplayerManager.deserialize_players(match_data["players"])
	_current_scorecard_match_data = match_data

	# Select default hole: first hole that has shot data, or hole 0
	var hole_ids = _get_match_hole_ids(_current_scorecard_match_data)
	_scorecard_selected_hole_index = 0
	for idx in range(hole_ids.size()):
		if _history_hole_has_shot_data(_current_scorecard_match_data, hole_ids[idx]):
			_scorecard_selected_hole_index = idx
			break

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
	_scorecard_scroll = ScrollContainer.new()
	_scorecard_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scorecard_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scorecard_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scorecard_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scorecard_scroll.follow_focus = true
	ThemeManager.apply_scroll_container_style(_scorecard_scroll, 28)
	card_vbox.add_child(_scorecard_scroll)
	
	# Scrollable content vbox (grid + shot review stacked vertically)
	var scroll_content = VBoxContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.add_theme_constant_override("separation", 20)
	_scorecard_scroll.add_child(scroll_content)
	
	_scorecard_grid = GridContainer.new()
	_scorecard_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scorecard_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_scorecard_grid.add_theme_constant_override("h_separation", 2)
	_scorecard_grid.add_theme_constant_override("v_separation", 2)
	scroll_content.add_child(_scorecard_grid)
	
	# Shot Review VBox (populated below the scorecard)
	_shot_review_container = VBoxContainer.new()
	_shot_review_container.name = "ShotReviewContainer"
	_shot_review_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shot_review_container.add_theme_constant_override("separation", 12)
	scroll_content.add_child(_shot_review_container)
	
	# Actions row
	var action_hbox = HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_vbox.add_child(action_hbox)
	
	_scorecard_close_btn = Button.new()
	_scorecard_close_btn.name = "ScorecardCloseBtn"
	_scorecard_close_btn.text = "Close"
	_scorecard_close_btn.custom_minimum_size = Vector2(160, 48)
	apply_button_style(_scorecard_close_btn, Color(0.3, 0.35, 0.4, 0.9))
	_scorecard_close_btn.pressed.connect(_close_scorecard)
	action_hbox.add_child(_scorecard_close_btn)
	
	_refresh_scorecard_view()
	
	scorecard_overlay.visible = true
	if is_inside_tree() and has_node("/root/UIFocusGuard"):
		var ufg = get_node("/root/UIFocusGuard")
		ufg.push_lock(scorecard_overlay)
	_focus_selected_hole_button()


func _close_scorecard() -> void:
	if scorecard_overlay == null or not scorecard_overlay.visible:
		return
	if is_inside_tree() and has_node("/root/UIFocusGuard"):
		var ufg = get_node("/root/UIFocusGuard")
		if ufg.is_locked() and ufg.current_lock_root() == scorecard_overlay:
			ufg.pop_lock(scorecard_overlay, true)
	scorecard_overlay.visible = false
	call_deferred("_grab_initial_focus")


func _focus_selected_hole_button() -> void:
	if _scorecard_grid == null or not is_instance_valid(_scorecard_grid) or not is_inside_tree():
		return
	var target_btn = _scorecard_grid.find_child("HoleBtn_%d" % _scorecard_selected_hole_index, true, false) as Button
	if target_btn != null and target_btn.is_inside_tree() and target_btn.is_visible_in_tree():
		target_btn.call_deferred("grab_focus")
		if _scorecard_scroll != null and is_instance_valid(_scorecard_scroll):
			_scorecard_scroll.call_deferred("ensure_control_visible", target_btn)
	elif _scorecard_grid.get_child_count() > 0:
		for child in _scorecard_grid.get_children():
			if child is Button and child.name.begins_with("HoleBtn_") and child.is_inside_tree() and child.is_visible_in_tree():
				child.call_deferred("grab_focus")
				if _scorecard_scroll != null and is_instance_valid(_scorecard_scroll):
					_scorecard_scroll.call_deferred("ensure_control_visible", child)
				break


func _select_scorecard_hole(hole_idx: int) -> void:
	var hole_ids = _get_match_hole_ids(_current_scorecard_match_data)
	if hole_ids.is_empty():
		return
	var clamped_idx = clampi(hole_idx, 0, hole_ids.size() - 1)
	if _scorecard_selected_hole_index != clamped_idx:
		_scorecard_selected_hole_index = clamped_idx
		_refresh_scorecard_view()
	_focus_selected_hole_button()


func _on_scorecard_hole_selected(target_hole_idx: int) -> void:
	_select_scorecard_hole(target_hole_idx)


func _refresh_scorecard_view() -> void:
	if _scorecard_grid == null or _shot_review_container == null:
		return
	_is_refreshing_scorecard = true
	var prev_v = _scorecard_scroll.scroll_vertical if _scorecard_scroll != null else 0
	var prev_h = _scorecard_scroll.scroll_horizontal if _scorecard_scroll != null else 0

	for child in _scorecard_grid.get_children():
		_scorecard_grid.remove_child(child)
		child.queue_free()
	_populate_grid_scorecard(_scorecard_grid, _current_scorecard_match_data)

	for child in _shot_review_container.get_children():
		_shot_review_container.remove_child(child)
		child.queue_free()
	var hole_ids = _get_match_hole_ids(_current_scorecard_match_data)
	var active_hole_id = hole_ids[_scorecard_selected_hole_index] if (_scorecard_selected_hole_index >= 0 and _scorecard_selected_hole_index < hole_ids.size()) else (hole_ids[0] if not hole_ids.is_empty() else "")
	if not active_hole_id.is_empty():
		_populate_history_shot_review(_shot_review_container, active_hole_id, _current_scorecard_match_data)

	if _scorecard_scroll != null:
		_scorecard_scroll.set_deferred("scroll_vertical", prev_v)
		_scorecard_scroll.set_deferred("scroll_horizontal", prev_h)
	_is_refreshing_scorecard = false


func _get_match_hole_ids(match_data: Dictionary) -> Array:
	if match_data.has("hole_ids") and not match_data["hole_ids"].is_empty():
		return match_data["hole_ids"].duplicate()
	var config_path: String = match_data.get("config_path", "")
	var hole_pars = {}
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
	var h_ids = hole_pars.keys()
	h_ids.sort_custom(func(a, b):
		return MultiplayerManager.get_hole_number_from_id(a) < MultiplayerManager.get_hole_number_from_id(b)
	)
	var course_len = match_data.get("selected_course_length", "Full 18")
	if course_len == "Back 9":
		h_ids = h_ids.filter(func(h_id): return MultiplayerManager.get_hole_number_from_id(h_id) >= 10)
	elif course_len == "Front 9":
		h_ids = h_ids.filter(func(h_id): return MultiplayerManager.get_hole_number_from_id(h_id) <= 9)
	if h_ids.is_empty():
		for i in range(18):
			h_ids.append("Hole " + str(i + 1))
	return h_ids


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
	var columns: Array[String] = ["Player"]
	var column_hole_indices: Array[int] = [-1]
	if not front_holes.is_empty():
		for h_id in front_holes:
			columns.append(str(MultiplayerManager.get_hole_number_from_id(h_id)))
			column_hole_indices.append(hole_ids.find(h_id))
		if not back_holes.is_empty():
			columns.append("OUT")
		else:
			columns.append("TOT")
		column_hole_indices.append(-1)
	if not back_holes.is_empty():
		for h_id in back_holes:
			columns.append(str(MultiplayerManager.get_hole_number_from_id(h_id)))
			column_hole_indices.append(hole_ids.find(h_id))
		columns.append("IN")
		column_hole_indices.append(-1)
	if has_both_nines:
		columns.append("TOT")
		column_hole_indices.append(-1)
	
	grid.columns = columns.size()
	
	var header_bg = Color(0.10, 0.14, 0.22, 0.96)
	var par_bg = Color(0.16, 0.22, 0.34, 0.88)
	var dist_bg = Color(0.13, 0.18, 0.28, 0.88)
	
	# Cell addition helper
	var add_cell = func(parent_grid: GridContainer, text: String, bg: Color, is_header: bool = false, fg: Color = Color.WHITE, font_size: int = 16, is_active: bool = false, min_width: float = 48.0):
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(min_width, 38)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_FILL
		var style = StyleBoxFlat.new()
		if is_active:
			style.bg_color = bg.lerp(Color(0.20, 0.42, 0.68, 0.95), 0.35)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.35, 0.72, 1.0, 0.85)
		else:
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
		if is_header or is_active:
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 3)
		cell.add_child(label)
		parent_grid.add_child(cell)
		return cell

	# Score cell addition helper with golfer lingo badges
	var add_score_cell = func(parent_grid: GridContainer, text: String, par: int, bg: Color, is_active: bool = false, is_ctp: bool = false, font_size: int = 16):
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(48, 38)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_FILL
		var style = StyleBoxFlat.new()
		if is_active:
			style.bg_color = bg.lerp(Color(0.20, 0.42, 0.68, 0.95), 0.35)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.35, 0.72, 1.0, 0.85)
		else:
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

	# 1. HEADER ROW (Clickable hole buttons matching CoursePlay)
	var hole_buttons: Array[Button] = []
	for c_idx in range(columns.size()):
		var col = columns[c_idx]
		var h_idx = column_hole_indices[c_idx]
		var is_hole_col = (h_idx >= 0)
		var is_act = (is_hole_col and h_idx == _scorecard_selected_hole_index)
		
		if is_hole_col:
			var btn = Button.new()
			btn.name = "HoleBtn_%d" % h_idx
			btn.custom_minimum_size = Vector2(48, 38)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.size_flags_vertical = Control.SIZE_FILL
			btn.text = col
			btn.focus_mode = Control.FOCUS_ALL
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			btn.add_theme_font_size_override("font_size", 16)
			btn.tooltip_text = "View Hole %s shot history [LB/RB to cycle]" % col
			
			var style_norm = StyleBoxFlat.new()
			if is_act:
				style_norm.bg_color = header_bg.lerp(Color(0.20, 0.42, 0.68, 0.95), 0.35)
				style_norm.border_width_left = 1
				style_norm.border_width_top = 1
				style_norm.border_width_right = 1
				style_norm.border_width_bottom = 1
				style_norm.border_color = Color(0.35, 0.72, 1.0, 0.85)
			else:
				style_norm.bg_color = header_bg
				style_norm.border_width_right = 1
				style_norm.border_width_bottom = 1
				style_norm.border_color = Color(0.3, 0.35, 0.45, 0.35)
			style_norm.content_margin_left = 6
			style_norm.content_margin_right = 6
			style_norm.content_margin_top = 4
			style_norm.content_margin_bottom = 4
			
			var style_hover = style_norm.duplicate()
			style_hover.bg_color = header_bg.lerp(Color(0.25, 0.50, 0.80, 0.95), 0.5)
			style_hover.border_color = Color(0.50, 0.82, 1.0, 1.0)
			
			var style_pressed = style_hover.duplicate()
			style_pressed.bg_color = header_bg.lerp(Color(0.15, 0.35, 0.60, 0.95), 0.6)

			var style_focus = style_hover.duplicate()
			style_focus.border_color = Color(1.0, 0.85, 0.38, 1.0)
			style_focus.border_width_left = 3
			style_focus.border_width_top = 3
			style_focus.border_width_right = 3
			style_focus.border_width_bottom = 3
			
			btn.add_theme_stylebox_override("normal", style_norm)
			btn.add_theme_stylebox_override("hover", style_hover)
			btn.add_theme_stylebox_override("pressed", style_pressed)
			btn.add_theme_stylebox_override("focus", style_focus)
			btn.add_theme_color_override("font_color", Color.WHITE)
			btn.add_theme_color_override("font_outline_color", Color.BLACK)
			btn.add_theme_constant_override("outline_size", 3)
			
			var target_hole_idx = h_idx
			btn.pressed.connect(func():
				_select_scorecard_hole(target_hole_idx)
			)
			btn.focus_entered.connect(func():
				if not _is_refreshing_scorecard and _scorecard_selected_hole_index != target_hole_idx:
					_select_scorecard_hole(target_hole_idx)
			)
			grid.add_child(btn)
			hole_buttons.append(btn)
		else:
			add_cell.call(grid, col, header_bg, true, Color.WHITE, 16, false, 180.0 if col == "Player" else 48.0)

	# Wire focus neighbors for hole buttons
	for i in range(hole_buttons.size()):
		var h_btn = hole_buttons[i]
		if i > 0:
			h_btn.focus_neighbor_left = hole_buttons[i - 1].get_path() if hole_buttons[i - 1].is_inside_tree() else h_btn.get_path_to(hole_buttons[i - 1])
		if i < hole_buttons.size() - 1:
			h_btn.focus_neighbor_right = hole_buttons[i + 1].get_path() if hole_buttons[i + 1].is_inside_tree() else h_btn.get_path_to(hole_buttons[i + 1])
		if _scorecard_close_btn != null and is_instance_valid(_scorecard_close_btn):
			h_btn.focus_neighbor_bottom = _scorecard_close_btn.get_path() if _scorecard_close_btn.is_inside_tree() else h_btn.get_path_to(_scorecard_close_btn)

	if _scorecard_close_btn != null and is_instance_valid(_scorecard_close_btn):
		_scorecard_close_btn.focus_mode = Control.FOCUS_ALL
		var sel_h_btn: Button = null
		for h_b in hole_buttons:
			if h_b.name == "HoleBtn_%d" % _scorecard_selected_hole_index:
				sel_h_btn = h_b
				break
		if sel_h_btn == null and not hole_buttons.is_empty():
			sel_h_btn = hole_buttons[0]
		if sel_h_btn != null:
			_scorecard_close_btn.focus_neighbor_top = sel_h_btn.get_path() if sel_h_btn.is_inside_tree() else _scorecard_close_btn.get_path_to(sel_h_btn)
		
	# 2. DISTANCE ROW (Yards)
	add_cell.call(grid, "Yds (%s)" % tee_color, dist_bg, false, Color(0.8, 0.8, 0.8), 15, false, 180.0)
	var front_dist_sum = 0
	for h_id in front_holes:
		var d = hole_dists.get(h_id, 0)
		front_dist_sum += d
		var is_act = (hole_ids.find(h_id) == _scorecard_selected_hole_index)
		add_cell.call(grid, str(d) if d > 0 else "-", dist_bg, false, Color(0.8, 0.8, 0.8), 15, is_act)
	if not front_holes.is_empty():
		add_cell.call(grid, str(front_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9), 15, false)
	var back_dist_sum = 0
	for h_id in back_holes:
		var d = hole_dists.get(h_id, 0)
		back_dist_sum += d
		var is_act = (hole_ids.find(h_id) == _scorecard_selected_hole_index)
		add_cell.call(grid, str(d) if d > 0 else "-", dist_bg, false, Color(0.8, 0.8, 0.8), 15, is_act)
	if not back_holes.is_empty():
		add_cell.call(grid, str(back_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9), 15, false)
	if has_both_nines:
		add_cell.call(grid, str(front_dist_sum + back_dist_sum), dist_bg, false, Color(1.0, 0.85, 0.38), 15, false)

	# 3. PAR ROW
	add_cell.call(grid, "Par", par_bg, false, Color(0.8, 0.8, 0.8), 15, false, 180.0)
	var front_par_sum: int = 0
	for h_id in front_holes:
		var p_val: int = int(round(float(hole_pars.get(h_id, 4))))
		front_par_sum += p_val
		var is_act = (hole_ids.find(h_id) == _scorecard_selected_hole_index)
		add_cell.call(grid, str(p_val), par_bg, false, Color(0.8, 0.8, 0.8), 15, is_act)
	if not front_holes.is_empty():
		add_cell.call(grid, str(front_par_sum), par_bg, false, Color(0.9, 0.9, 0.9), 15, false)
	var back_par_sum: int = 0
	for h_id in back_holes:
		var p_val: int = int(round(float(hole_pars.get(h_id, 4))))
		back_par_sum += p_val
		var is_act = (hole_ids.find(h_id) == _scorecard_selected_hole_index)
		add_cell.call(grid, str(p_val), par_bg, false, Color(0.8, 0.8, 0.8), 15, is_act)
	if not back_holes.is_empty():
		add_cell.call(grid, str(back_par_sum), par_bg, false, Color(0.9, 0.9, 0.9), 15, false)
	if has_both_nines:
		var total_par: int = front_par_sum + back_par_sum
		add_cell.call(grid, str(total_par), par_bg, false, Color(1.0, 0.85, 0.38), 15, false)

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
			var is_act = (hole_ids.find(h_id) == _scorecard_selected_hole_index)
			add_score_cell.call(grid, display_s, par, row_bg, is_act, is_ctp_mode, 16)
			
		if not front_holes.is_empty():
			add_cell.call(grid, str(front_sum) if front_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9), 16, false)
			
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
			var is_act = (hole_ids.find(h_id) == _scorecard_selected_hole_index)
			add_score_cell.call(grid, display_s, par, row_bg, is_act, is_ctp_mode, 16)
			
		if not back_holes.is_empty():
			add_cell.call(grid, str(back_sum) if back_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9), 16, false)
			
		if has_both_nines:
			var total = front_sum + back_sum
			var tot_str = str(total) if total > 0 else "-"
			if is_ctp_mode:
				tot_str = "%d pts" % total
			add_cell.call(grid, tot_str, row_bg, false, Color(1.0, 0.85, 0.38), 16, false)

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

func _history_hole_has_shot_data(match_data: Dictionary, hole_id: String) -> bool:
	var players_list: Array = match_data.get("players", [])
	for p in players_list:
		var player_stats = p.get("shot_stats", {})
		if typeof(player_stats) == TYPE_DICTIONARY and player_stats.has(hole_id):
			var shots = player_stats[hole_id]
			if typeof(shots) == TYPE_ARRAY and not shots.is_empty():
				return true
		var shot_history = p.get("shot_history", [])
		if typeof(shot_history) == TYPE_ARRAY and not shot_history.is_empty():
			return true
	return false


func _populate_history_shot_review(container: VBoxContainer, hole_id: String, match_data: Dictionary) -> void:
	var h_num = MultiplayerManager.get_hole_number_from_id(hole_id)
	var players_list: Array = match_data.get("players", [])

	# Load course config for green positions, tee boxes, satellite, cart paths
	var config_path: String = match_data.get("config_path", "")
	var hole_info: Dictionary = {}
	var satellite_texture: Texture2D = null
	var satellite_bounds: Array = []
	var cart_paths: Array[PackedVector2Array] = []
	var course_info_val: Dictionary = {}

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
				var raw_ci = parsed.get("Course Info", {})
				if typeof(raw_ci) == TYPE_DICTIONARY:
					course_info_val = raw_ci
					var bounds_version := int(round(float(course_info_val.get("Satellite Image Bounds Version", 0))))
					if bounds_version == 5:
						var saved_bounds = course_info_val.get("Satellite Image Bounds", [])
						if typeof(saved_bounds) == TYPE_ARRAY:
							satellite_bounds = saved_bounds
				# Cart paths
				var saved_cart_paths = parsed.get("Cart Paths", [])
				if typeof(saved_cart_paths) != TYPE_ARRAY and course_info_val.has("Cart Paths"):
					saved_cart_paths = course_info_val.get("Cart Paths", [])
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

	var saved_pars = match_data.get("hole_pars", {})
	var fallback_par = int(round(float(saved_pars.get(hole_id, 4)))) if typeof(saved_pars) == TYPE_DICTIONARY else 4
	var hole_par = int(round(float(current_hole_info.get("Par", fallback_par))))

	# Player order sorted by score on this hole (matching CoursePlay)
	var player_order: Array[Dictionary] = []
	for player_index in range(players_list.size()):
		var player: Dictionary = players_list[player_index]
		var hole_scores: Dictionary = player.get("hole_scores", {})
		var score = hole_scores.get(hole_id)
		player_order.append({
			"player": player,
			"score": int(round(float(score))) if score != null else 2147483647,
			"player_index": player_index
		})
	player_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] < b["score"]
		return a["player_index"] < b["player_index"]
	)

	# Shared shot positions across all players
	var shared_shot_positions: Array[Vector3] = []
	for p_entry in player_order:
		shared_shot_positions.append_array(_get_history_hole_shot_positions(p_entry["player"], hole_id, tee_boxes))

	# Section Header for Shot Review (matching CoursePlay exactly)
	var header_box = VBoxContainer.new()
	header_box.alignment = BoxContainer.ALIGNMENT_CENTER
	header_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_box.add_theme_constant_override("separation", 2)
	container.add_child(header_box)

	var title_lbl = Label.new()
	title_lbl.name = "HoleShotTitleLabel"
	title_lbl.text = "Hole %s Shot Review (Par %d)" % [h_num, hole_par]
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 3)
	header_box.add_child(title_lbl)

	var hint_lbl = Label.new()
	hint_lbl.name = "HoleShotHintLabel"
	hint_lbl.text = "Select any hole number above or use LB/RB bumpers to view shot history"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_lbl.add_theme_font_size_override("font_size", 13)
	hint_lbl.add_theme_color_override("font_color", Color(0.68, 0.74, 0.84))
	header_box.add_child(hint_lbl)

	# Centering wrapper for cards
	var cards_wrapper = HBoxContainer.new()
	cards_wrapper.name = "HoleShotCardsWrapper"
	cards_wrapper.alignment = BoxContainer.ALIGNMENT_CENTER
	cards_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(cards_wrapper)

	var player_cards = GridContainer.new()
	player_cards.name = "HoleShotPlayerCards"
	player_cards.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	player_cards.add_theme_constant_override("h_separation", 16)
	player_cards.add_theme_constant_override("v_separation", 16)
	cards_wrapper.add_child(player_cards)

	var max_cols = mini(player_order.size(), maxi(1, int(floor(1200.0 / 340.0))))
	player_cards.columns = max(1, max_cols)

	var card_width = 340.0
	var image_width = card_width - 24.0 # 316.0
	var image_height = 340.0

	for rank in range(player_order.size()):
		var player: Dictionary = player_order[rank]["player"]
		var positions := _get_history_hole_shot_positions(player, hole_id, tee_boxes)

		var shot_distances: Array[int] = []
		for shot_index in range(maxi(0, positions.size() - 1)):
			var start_pos = positions[shot_index]
			var end_pos = positions[shot_index + 1]
			var dist_yds = Vector2(start_pos.x, start_pos.z).distance_to(Vector2(end_pos.x, end_pos.z)) * 1.09361
			shot_distances.append(int(round(dist_yds)))

		var player_card = PanelContainer.new()
		player_card.custom_minimum_size = Vector2(card_width, 0)
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
		var color_value = player.get("color")
		if typeof(color_value) == TYPE_COLOR:
			player_color = color_value
		var is_hole_winner = player_order[rank]["score"] == player_order[0]["score"] and player_order[rank]["score"] < 2147483647
		card_style.border_color = Color(0.72, 0.56, 0.24, 0.85) if is_hole_winner else player_color
		card_style.content_margin_left = 12
		card_style.content_margin_right = 12
		card_style.content_margin_top = 10
		card_style.content_margin_bottom = 12
		player_card.add_theme_stylebox_override("panel", card_style)

		var player_row = VBoxContainer.new()
		player_row.add_theme_constant_override("separation", 6)
		player_card.add_child(player_row)

		var score_label = Label.new()
		var score_text = "No score" if player_order[rank]["score"] == 2147483647 else "%d strokes" % player_order[rank]["score"]
		score_label.text = "%d. %s — %s · %d shots" % [rank + 1, player.get("name", "Player"), score_text, shot_distances.size()]
		score_label.add_theme_font_size_override("font_size", 17)
		score_label.add_theme_color_override("font_color", Color.WHITE)
		player_row.add_child(score_label)

		if shot_distances.is_empty():
			var no_shots_panel = PanelContainer.new()
			no_shots_panel.custom_minimum_size = Vector2(image_width, minf(160.0, image_height))
			var no_shots_style = StyleBoxFlat.new()
			no_shots_style.bg_color = Color(0.06, 0.08, 0.12, 0.6)
			no_shots_style.border_width_left = 1
			no_shots_style.border_width_top = 1
			no_shots_style.border_width_right = 1
			no_shots_style.border_width_bottom = 1
			no_shots_style.border_color = Color(0.25, 0.3, 0.4, 0.4)
			no_shots_style.corner_radius_top_left = 12
			no_shots_style.corner_radius_top_right = 12
			no_shots_style.corner_radius_bottom_left = 12
			no_shots_style.corner_radius_bottom_right = 12
			no_shots_panel.add_theme_stylebox_override("panel", no_shots_style)

			var no_shots_label = Label.new()
			no_shots_label.text = "No shots recorded for Hole %s" % h_num
			no_shots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			no_shots_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			no_shots_label.add_theme_color_override("font_color", Color(0.70, 0.75, 0.85))
			no_shots_label.add_theme_font_size_override("font_size", 14)
			no_shots_panel.add_child(no_shots_label)
			player_row.add_child(no_shots_panel)
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
			shot_path.custom_minimum_size = Vector2(image_width, image_height)
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
		player_cards.add_child(player_card)


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

	# Also check shot_history if shot_stats is empty
	if shot_stats.is_empty():
		var shot_history = player.get("shot_history", [])
		if typeof(shot_history) == TYPE_ARRAY:
			for pos in shot_history:
				if typeof(pos) == TYPE_VECTOR3:
					fallback_positions.append(pos)
				elif typeof(pos) == TYPE_ARRAY and pos.size() >= 3:
					fallback_positions.append(Vector3(float(pos[0]), float(pos[1]), float(pos[2])))

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
	
	var style_focus = style_hover.duplicate()
	style_focus.border_color = Color(1.0, 0.85, 0.38, 1.0)
	style_focus.border_width_left = 3
	style_focus.border_width_top = 3
	style_focus.border_width_right = 3
	style_focus.border_width_bottom = 3
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", style_focus)
	
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color(0.9, 0.9, 0.9))
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", 16)
	if btn.custom_minimum_size.y < 48:
		btn.custom_minimum_size.y = 48
