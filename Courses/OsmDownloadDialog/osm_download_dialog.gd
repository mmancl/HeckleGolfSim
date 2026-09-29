extends Control

signal course_downloaded(course_name: String)

const SETTINGS_FILE = "user://osm_download_settings.cfg"

@onready var search_input: LineEdit = %SearchInput
@onready var search_button: Button = %SearchButton
@onready var settings_button: Button = %SettingsButton
@onready var results_list: ItemList = %ResultsList
@onready var status_label: Label = %StatusLabel
@onready var cancel_button: Button = %CancelButton
@onready var download_button: Button = %DownloadButton
@onready var spinner: Control = %Spinner
@onready var notice_panel: Control = %NoticePanel

# Settings menu nodes
@onready var settings_overlay: Control = %SettingsOverlay
@onready var settings_dimmer: ColorRect = %SettingsDimmer
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var settings_close_button: Button = %SettingsCloseButton
@onready var hole_count_card: PanelContainer = %HoleCountCard
@onready var tag_filter_card: PanelContainer = %TagFilterCard
@onready var btn_9_hole: Button = %Btn9Hole
@onready var btn_18_hole: Button = %Btn18Hole
@onready var btn_all_holes: Button = %BtnAllHoles
@onready var leisure_golf_check: CheckBox = %LeisureGolfCheck
@onready var custom_tags_input: LineEdit = %CustomTagsInput
@onready var reset_defaults_button: Button = %ResetDefaultsButton
@onready var settings_done_button: Button = %SettingsDoneButton

var _loader: Node = null
var _results: Array = []
var _download_in_progress: bool = false
var _download_token: int = 0


func _ready() -> void:
	var panel = get_node_or_null("CenterContainer/PanelContainer")
	if panel != null:
		ThemeManager.apply_modal_style(panel, 12)

	ThemeManager.apply_secondary_button_style(search_button, 6)
	ThemeManager.apply_primary_button_style(download_button, 6)
	ThemeManager.apply_nav_button_style(cancel_button, 6)
	ThemeManager.apply_input_style(search_input)
	ThemeManager.apply_item_list_style(results_list)

	# Setup settings button
	if settings_button != null:
		ThemeManager.apply_icon_button_style(settings_button, 6, 8)
		settings_button.icon = load("res://Utils/Settings/Gear.png")
		settings_button.pressed.connect(_on_settings_pressed)

	# Setup settings overlay & controls
	if settings_panel != null:
		ThemeManager.apply_modal_style(settings_panel, 12)
	if settings_close_button != null:
		ThemeManager.apply_nav_button_style(settings_close_button, 6)
		settings_close_button.pressed.connect(_on_settings_closed)
	if hole_count_card != null:
		ThemeManager.apply_card_panel_style(hole_count_card, false, 8, 14, 10, 14, 10)
	if tag_filter_card != null:
		ThemeManager.apply_card_panel_style(tag_filter_card, false, 8, 14, 10, 14, 10)
	if reset_defaults_button != null:
		ThemeManager.apply_secondary_button_style(reset_defaults_button, 6)
		reset_defaults_button.pressed.connect(_on_reset_defaults_pressed)
	if settings_done_button != null:
		ThemeManager.apply_primary_button_style(settings_done_button, 6)
		settings_done_button.pressed.connect(_on_settings_closed)
	if custom_tags_input != null:
		ThemeManager.apply_input_style(custom_tags_input)
	if settings_dimmer != null:
		settings_dimmer.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				_on_settings_closed()
		)

	if btn_9_hole != null:
		btn_9_hole.toggled.connect(_on_btn_9_hole_toggled)
	if btn_18_hole != null:
		btn_18_hole.toggled.connect(_on_btn_18_hole_toggled)
	if btn_all_holes != null:
		btn_all_holes.toggled.connect(_on_btn_all_holes_toggled)

	_load_search_settings()
	_update_hole_buttons_visual()

	search_button.pressed.connect(_on_search_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	download_button.pressed.connect(_on_download_pressed)
	results_list.item_selected.connect(_on_item_selected)
	search_input.text_submitted.connect(func(_text): _on_search_pressed())
	
	results_list.clear()
	download_button.disabled = true
	if notice_panel != null:
		notice_panel.visible = false
	if settings_overlay != null:
		settings_overlay.visible = false
	
	search_input.call_deferred("grab_focus")
	
	var loader_script = load("res://Courses/OsmMapLoader.cs")
	if loader_script != null:
		_loader = loader_script.new()
		add_child(_loader)
		if _loader.has_signal("DownloadProgress"):
			_loader.DownloadProgress.connect(func(msg: String):
				call_deferred("_update_progress_status", msg)
			)
	else:
		status_label.text = "Error: Failed to load OsmMapLoader.cs script."
		search_button.disabled = true
		search_input.editable = false


func _on_settings_pressed() -> void:
	if settings_overlay != null:
		settings_overlay.visible = true


func _on_settings_closed() -> void:
	_save_search_settings()
	if settings_overlay != null:
		settings_overlay.visible = false


func _on_btn_9_hole_toggled(pressed: bool) -> void:
	if pressed:
		btn_all_holes.set_pressed_no_signal(false)
	else:
		if not btn_18_hole.button_pressed:
			btn_all_holes.set_pressed_no_signal(true)
	_update_hole_buttons_visual()
	_save_search_settings()


func _on_btn_18_hole_toggled(pressed: bool) -> void:
	if pressed:
		btn_all_holes.set_pressed_no_signal(false)
	else:
		if not btn_9_hole.button_pressed:
			btn_all_holes.set_pressed_no_signal(true)
	_update_hole_buttons_visual()
	_save_search_settings()


func _on_btn_all_holes_toggled(pressed: bool) -> void:
	if pressed:
		btn_9_hole.set_pressed_no_signal(false)
		btn_18_hole.set_pressed_no_signal(false)
	else:
		if not btn_9_hole.button_pressed and not btn_18_hole.button_pressed:
			btn_9_hole.set_pressed_no_signal(true)
			btn_18_hole.set_pressed_no_signal(true)
	_update_hole_buttons_visual()
	_save_search_settings()


func _update_hole_buttons_visual() -> void:
	if btn_9_hole == null or btn_18_hole == null or btn_all_holes == null:
		return
	if btn_9_hole.button_pressed:
		ThemeManager.apply_primary_button_style(btn_9_hole, 6)
	else:
		ThemeManager.apply_nav_button_style(btn_9_hole, 6)
		
	if btn_18_hole.button_pressed:
		ThemeManager.apply_primary_button_style(btn_18_hole, 6)
	else:
		ThemeManager.apply_nav_button_style(btn_18_hole, 6)
		
	if btn_all_holes.button_pressed:
		ThemeManager.apply_primary_button_style(btn_all_holes, 6)
	else:
		ThemeManager.apply_nav_button_style(btn_all_holes, 6)


func _on_reset_defaults_pressed() -> void:
	if btn_9_hole != null:
		btn_9_hole.set_pressed_no_signal(true)
	if btn_18_hole != null:
		btn_18_hole.set_pressed_no_signal(true)
	if btn_all_holes != null:
		btn_all_holes.set_pressed_no_signal(false)
	if leisure_golf_check != null:
		leisure_golf_check.button_pressed = true
	if custom_tags_input != null:
		custom_tags_input.text = ""
	_update_hole_buttons_visual()
	_save_search_settings()


func _load_search_settings() -> void:
	var cfg = ConfigFile.new()
	var err = cfg.load(SETTINGS_FILE)
	if err == OK:
		var has_all = cfg.get_value("search_filter", "include_all_holes", false)
		var has_9 = cfg.get_value("search_filter", "include_9_hole", true)
		var has_18 = cfg.get_value("search_filter", "include_18_hole", true)
		if has_all:
			if btn_all_holes != null: btn_all_holes.set_pressed_no_signal(true)
			if btn_9_hole != null: btn_9_hole.set_pressed_no_signal(false)
			if btn_18_hole != null: btn_18_hole.set_pressed_no_signal(false)
		else:
			if btn_all_holes != null: btn_all_holes.set_pressed_no_signal(false)
			if btn_9_hole != null: btn_9_hole.set_pressed_no_signal(has_9)
			if btn_18_hole != null: btn_18_hole.set_pressed_no_signal(has_18)
			if not has_9 and not has_18:
				if btn_9_hole != null: btn_9_hole.set_pressed_no_signal(true)
				if btn_18_hole != null: btn_18_hole.set_pressed_no_signal(true)
				
		if leisure_golf_check != null:
			leisure_golf_check.button_pressed = cfg.get_value("search_filter", "require_leisure_golf", true)
		if custom_tags_input != null:
			custom_tags_input.text = cfg.get_value("search_filter", "custom_tags", "")
	else:
		if btn_9_hole != null: btn_9_hole.set_pressed_no_signal(true)
		if btn_18_hole != null: btn_18_hole.set_pressed_no_signal(true)
		if btn_all_holes != null: btn_all_holes.set_pressed_no_signal(false)
		if leisure_golf_check != null: leisure_golf_check.button_pressed = true
		if custom_tags_input != null: custom_tags_input.text = ""


func _save_search_settings() -> void:
	var cfg = ConfigFile.new()
	if btn_all_holes != null:
		cfg.set_value("search_filter", "include_all_holes", btn_all_holes.button_pressed)
	if btn_9_hole != null:
		cfg.set_value("search_filter", "include_9_hole", btn_9_hole.button_pressed)
	if btn_18_hole != null:
		cfg.set_value("search_filter", "include_18_hole", btn_18_hole.button_pressed)
	if leisure_golf_check != null:
		cfg.set_value("search_filter", "require_leisure_golf", leisure_golf_check.button_pressed)
	if custom_tags_input != null:
		cfg.set_value("search_filter", "custom_tags", custom_tags_input.text.strip_edges())
	cfg.save(SETTINGS_FILE)


func _on_search_pressed() -> void:
	var query = search_input.text.strip_edges()
	if query.is_empty():
		status_label.text = "Please enter a search query."
		return
		
	status_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 1.0))
	status_label.text = "Searching OpenStreetMap for '" + query + "'..."
	_set_ui_disabled(true)
	results_list.clear()
	_results.clear()
	download_button.disabled = true
	spinner.visible = true
	if notice_panel != null:
		notice_panel.visible = false
	
	_save_search_settings()
	var filter_options = {
		"include_9_hole": btn_9_hole.button_pressed if btn_9_hole != null else true,
		"include_18_hole": btn_18_hole.button_pressed if btn_18_hole != null else true,
		"include_all_holes": btn_all_holes.button_pressed if btn_all_holes != null else false,
		"require_leisure_golf": leisure_golf_check.button_pressed if leisure_golf_check != null else true,
		"custom_tags": custom_tags_input.text.strip_edges() if custom_tags_input != null else ""
	}
	
	# Call C# search and await signal
	_loader.SearchGolfCourses(query, filter_options)
	var results_array = await _loader.SearchCompleted
	
	spinner.visible = false
	_set_ui_disabled(false)
	
	if results_array == null or results_array.is_empty():
		var hole_desc = ""
		if btn_all_holes != null and btn_all_holes.button_pressed:
			hole_desc = ""
		elif btn_9_hole != null and btn_18_hole != null and btn_9_hole.button_pressed and btn_18_hole.button_pressed:
			hole_desc = " with 9 or 18 holes"
		elif btn_9_hole != null and btn_9_hole.button_pressed:
			hole_desc = " with 9 holes"
		elif btn_18_hole != null and btn_18_hole.button_pressed:
			hole_desc = " with 18 holes"
		status_label.text = "No golf courses" + hole_desc + " found matching '" + query + "' with active filters."
		return
		
	_results = results_array
	for item in _results:
		var name_text = item.get("name", "Unnamed Course")
		var loc_text = item.get("location", "")
		var holes = item.get("hole_count", 0)
		var updated_ts = item.get("last_updated", "")
		
		var meta_parts = []
		if holes > 0:
			meta_parts.append(str(holes) + " Holes")
		elif btn_all_holes != null and btn_all_holes.button_pressed:
			meta_parts.append("Holes: N/A")
		if not updated_ts.is_empty():
			var date_only = updated_ts.split("T")[0]
			meta_parts.append("Updated: " + date_only)
			
		var display_text = name_text
		if not meta_parts.is_empty():
			display_text += " [" + " | ".join(meta_parts) + "]"
		if not loc_text.is_empty():
			display_text += " (" + loc_text + ")"
		results_list.add_item(display_text)
		
	status_label.text = "Found " + str(_results.size()) + " course(s) (newest first). Select one to download."


func _on_item_selected(_index: int) -> void:
	download_button.disabled = false


func _on_download_pressed() -> void:
	var selected_items = results_list.get_selected_items()
	if selected_items.is_empty():
		return
		
	var idx = selected_items[0]
	if idx < 0 or idx >= _results.size():
		return
		
	var course = _results[idx]
	var course_name = course.get("name", "Unnamed Course")
	var lat = course.get("lat", 0.0)
	var lon = course.get("lon", 0.0)
	
	status_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 1.0))
	status_label.text = "Downloading and generating 3D map for '" + course_name + "'..."
	_set_ui_disabled(true)
	download_button.disabled = true
	cancel_button.disabled = true
	spinner.visible = true
	if notice_panel != null:
		notice_panel.visible = false
	
	_download_in_progress = true
	_download_token += 1
	var current_token = _download_token
	_start_download_notice_timer(current_token)
	
	# Call C# download and generate and await signal
	_loader.DownloadAndGenerateCourse(lat, lon, course_name)
	var success = await _loader.CourseGenerated
	
	_download_in_progress = false
	spinner.visible = false
	if success:
		status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1.0))
		var msg = ""
		if _loader.has_method("GetGenerationMessage"):
			msg = _loader.GetGenerationMessage()
		if msg != "":
			status_label.text = msg
		else:
			status_label.text = "Successfully generated course: " + course_name + "!"
		course_downloaded.emit(course_name)
		# Wait 1.5 seconds before auto-closing
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(self):
			queue_free()
	else:
		if notice_panel != null:
			notice_panel.visible = false
		status_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.65, 1.0))
		var msg = ""
		if _loader.has_method("GetGenerationMessage"):
			msg = _loader.GetGenerationMessage()
		if msg != "":
			status_label.text = msg
		else:
			status_label.text = "Error: Course generation timed out or failed. Please retry the download, and if it continues to fail, please log a bug."
		_set_ui_disabled(false)
		download_button.disabled = false
		cancel_button.disabled = false


func _start_download_notice_timer(token: int) -> void:
	await get_tree().create_timer(15.0).timeout
	if _download_in_progress and _download_token == token and is_instance_valid(self) and is_inside_tree():
		if notice_panel != null:
			notice_panel.visible = true
			notice_panel.modulate.a = 0.0
			var tween = create_tween()
			if tween != null:
				tween.tween_property(notice_panel, "modulate:a", 1.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		if event is InputEventKey and (event.keycode == KEY_BACKSPACE or event.physical_keycode == KEY_BACKSPACE):
			return
		if settings_overlay != null and settings_overlay.visible:
			_on_settings_closed()
			get_viewport().set_input_as_handled()
			return
		if not _download_in_progress:
			_on_cancel_pressed()
			get_viewport().set_input_as_handled()


func _on_cancel_pressed() -> void:
	_download_in_progress = false
	queue_free()


func _set_ui_disabled(disabled: bool) -> void:
	search_input.editable = not disabled
	search_button.disabled = disabled
	if settings_button != null:
		settings_button.disabled = disabled
	results_list.auto_height = false # Keep styling
	# Disable individual items in list during loading if needed, or mouse filtering
	results_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_PASS


func _update_progress_status(msg: String) -> void:
	if _download_in_progress and is_instance_valid(self):
		status_label.text = msg
