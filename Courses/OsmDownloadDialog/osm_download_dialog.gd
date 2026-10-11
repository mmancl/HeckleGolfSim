extends Control

signal course_downloaded(course_name: String)

const SETTINGS_FILE = "user://osm_download_settings.cfg"
const RATE_LIMIT_COOLDOWN_SECONDS: int = 86400 # 24 hours (1 course per day)
const RATE_LIMIT_SECTION = "osm_rate_limit"
const KEY_LAST_OSM_DOWNLOAD_TIME = "last_osm_download_time"
const KEY_LAST_OSM_DOWNLOAD_COURSE = "last_osm_download_course"
const INSTRUCTION_HEADER_TEXT = "Select from the cached courses, or if not seen in list search to download from OSM"

@onready var search_input: LineEdit = %SearchInput
@onready var settings_button: Button = %SettingsButton
@onready var results_list: ItemList = %ResultsList
@onready var status_label: Label = %StatusLabel
@onready var expand_search_button: Button = %ExpandSearchButton
@onready var cancel_button: Button = %CancelButton
@onready var download_button: Button = %DownloadButton
@onready var spinner: Control = %Spinner
@onready var notice_panel: Control = %NoticePanel
@onready var rate_limit_warning_panel: PanelContainer = %RateLimitWarningPanel
@onready var rate_limit_label: Label = %RateLimitLabel

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
@onready var cached_only_check: CheckBox = %CachedOnlyCheck
@onready var force_online_check: CheckBox = %ForceOnlineCheck
@onready var reset_defaults_button: Button = %ResetDefaultsButton
@onready var settings_done_button: Button = %SettingsDoneButton

var _loader: Node = null
var _all_cached_courses: Array = []
var _displayed_courses: Array = []
var _download_in_progress: bool = false
var _download_token: int = 0
var _is_showing_cached: bool = true


func _ready() -> void:
	var panel = get_node_or_null("CenterContainer/PanelContainer")
	if panel != null:
		ThemeManager.apply_modal_style(panel, 12)

	ThemeManager.apply_primary_button_style(download_button, 6)
	ThemeManager.apply_nav_button_style(cancel_button, 6)
	ThemeManager.apply_input_style(search_input)
	ThemeManager.apply_item_list_style(results_list)

	# Remove / hide scrollbars from the course search menu
	_remove_search_menu_scrollbars()

	search_input.placeholder_text = INSTRUCTION_HEADER_TEXT
	search_input.text_changed.connect(_on_search_text_changed)

	if expand_search_button != null:
		ThemeManager.apply_secondary_button_style(expand_search_button, 6)
		expand_search_button.pressed.connect(func(): _perform_search(true))
		expand_search_button.visible = false

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

	cancel_button.pressed.connect(_on_cancel_pressed)
	download_button.pressed.connect(_on_download_pressed)
	results_list.item_selected.connect(_on_item_selected)
	search_input.text_submitted.connect(func(_text): _perform_search(false))

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

	# Load offline cached courses and populate alphabetically
	_load_cached_courses()
	_show_all_cached_courses()
	_update_rate_limit_ui()


func _remove_search_menu_scrollbars() -> void:
	if results_list == null:
		return

	var v_bar = results_list.get_v_scroll_bar()
	if v_bar != null:
		v_bar.visible = false
		v_bar.modulate = Color(0, 0, 0, 0)
		v_bar.custom_minimum_size = Vector2.ZERO
		v_bar.size_flags_horizontal = 0
		v_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not v_bar.visibility_changed.is_connected(_hide_v_scroll):
			v_bar.visibility_changed.connect(_hide_v_scroll.bind(v_bar))

	var h_bar = results_list.get_h_scroll_bar()
	if h_bar != null:
		h_bar.visible = false
		h_bar.modulate = Color(0, 0, 0, 0)
		h_bar.custom_minimum_size = Vector2.ZERO
		h_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not h_bar.visibility_changed.is_connected(_hide_h_scroll):
			h_bar.visibility_changed.connect(_hide_h_scroll.bind(h_bar))

	# Clean glass panel with symmetric margins since scrollbar is removed
	var clean_panel = StyleBoxFlat.new()
	clean_panel.bg_color = Color(0.05, 0.08, 0.12, 0.50)
	clean_panel.border_color = Color(0.24, 0.44, 0.65, 0.25)
	clean_panel.set_border_width_all(1)
	clean_panel.set_corner_radius_all(8)
	clean_panel.content_margin_left = 14
	clean_panel.content_margin_top = 10
	clean_panel.content_margin_right = 14
	clean_panel.content_margin_bottom = 10
	results_list.add_theme_stylebox_override("panel", clean_panel)

	var empty_sb = StyleBoxEmpty.new()
	results_list.add_theme_stylebox_override("scroll", empty_sb)
	results_list.add_theme_stylebox_override("scroll_focus", empty_sb)

	if not results_list.resized.is_connected(_on_results_list_resized):
		results_list.resized.connect(_on_results_list_resized)


func _on_results_list_resized() -> void:
	if results_list == null:
		return
	var v_bar = results_list.get_v_scroll_bar()
	if v_bar != null:
		v_bar.visible = false
		v_bar.custom_minimum_size = Vector2.ZERO


func _hide_v_scroll(bar: ScrollBar) -> void:
	if is_instance_valid(bar) and bar.visible:
		bar.visible = false


func _hide_h_scroll(bar: ScrollBar) -> void:
	if is_instance_valid(bar) and bar.visible:
		bar.visible = false


func get_last_osm_download_time() -> int:
	var cfg = ConfigFile.new()
	var err = cfg.load(SETTINGS_FILE)
	if err == OK:
		return int(cfg.get_value(RATE_LIMIT_SECTION, KEY_LAST_OSM_DOWNLOAD_TIME, 0))
	return 0


func get_osm_cooldown_remaining_seconds() -> int:
	var last_time = get_last_osm_download_time()
	if last_time <= 0:
		return 0
	var now = int(Time.get_unix_time_from_system())
	var elapsed = now - last_time
	if elapsed < 0:
		return 0
	var remaining = RATE_LIMIT_COOLDOWN_SECONDS - elapsed
	return maxi(0, remaining)


func get_osm_cooldown_hours_remaining() -> int:
	var rem_sec = get_osm_cooldown_remaining_seconds()
	if rem_sec <= 0:
		return 0
	return maxi(1, int(ceil(float(rem_sec) / 3600.0)))


func is_rate_limit_bypassed() -> bool:
	if has_node("/root/GlobalSettings"):
		var gs = get_node("/root/GlobalSettings")
		if gs.range_settings != null and gs.range_settings.settings.has("debug_bypass_osm_limit"):
			return bool(gs.range_settings.debug_bypass_osm_limit.value)
	var cfg = ConfigFile.new()
	if cfg.load(SETTINGS_FILE) == OK:
		return bool(cfg.get_value("developer", "bypass_osm_limit", false))
	return false


func is_osm_rate_limited() -> bool:
	if is_rate_limit_bypassed():
		return false
	return get_osm_cooldown_remaining_seconds() > 0


func get_osm_rate_limit_warning_message() -> String:
	var hours = get_osm_cooldown_hours_remaining()
	var hour_text = "1 hour" if hours == 1 else str(hours) + " hours"
	return "You can download another course from OSM in %s. Additionally, you can still download any of the cached most popular courses which is 5,000+ courses in the US and Europe." % hour_text


func record_osm_download_success(course_name: String) -> void:
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS_FILE)
	var now = int(Time.get_unix_time_from_system())
	cfg.set_value(RATE_LIMIT_SECTION, KEY_LAST_OSM_DOWNLOAD_TIME, now)
	cfg.set_value(RATE_LIMIT_SECTION, KEY_LAST_OSM_DOWNLOAD_COURSE, course_name)
	cfg.save(SETTINGS_FILE)
	_update_rate_limit_ui()


func _load_cached_courses() -> void:
	_all_cached_courses.clear()
	var catalog_path = "res://Courses/Catalog/golf_courses.json"
	if FileAccess.file_exists(catalog_path):
		var file = FileAccess.open(catalog_path, FileAccess.ModeFlags.READ)
		if file != null:
			var text = file.get_as_text()
			var json = JSON.new()
			var parse_err = json.parse(text)
			if parse_err == OK and json.data is Array:
				for item in json.data:
					if item is Dictionary:
						var entry = item.duplicate()
						entry["is_catalog"] = true
						entry["is_cached"] = true
						_all_cached_courses.append(entry)

	if _loader != null and _loader.has_method("GetCachedCourses"):
		var loader_courses = _loader.call("GetCachedCourses")
		if loader_courses is Array and not loader_courses.is_empty():
			for lc in loader_courses:
				var exists = false
				var lc_name = lc.get("name", "")
				for ec in _all_cached_courses:
					if ec.get("name", "").nocasecmp_to(lc_name) == 0:
						exists = true
						break
				if not exists:
					_all_cached_courses.append(lc)

	# Sort all cached courses alphabetically by name
	_all_cached_courses.sort_custom(func(a, b):
		return a.get("name", "").to_lower() < b.get("name", "").to_lower()
	)


func _is_course_cached(course: Dictionary) -> bool:
	if course.get("is_catalog", false) or course.get("is_cached", false):
		return true
	var c_name = course.get("name", "")
	if not c_name.is_empty():
		for cached in _all_cached_courses:
			if cached.get("name", "").nocasecmp_to(c_name) == 0:
				return true
		if _loader != null and _loader.has_method("IsCourseCached"):
			if bool(_loader.call("IsCourseCached", c_name)):
				return true
	return false


func _filter_by_hole_settings(courses: Array) -> Array:
	var inc_all = btn_all_holes != null and btn_all_holes.button_pressed
	if inc_all:
		return courses
	var inc_9 = btn_9_hole != null and btn_9_hole.button_pressed
	var inc_18 = btn_18_hole != null and btn_18_hole.button_pressed
	if inc_9 and inc_18:
		return courses
	var res = []
	for c in courses:
		var h = c.get("hole_count", 18)
		if inc_9 and h == 9:
			res.append(c)
		elif inc_18 and h == 18:
			res.append(c)
	return res


func _display_courses_in_list(courses: Array, is_search_results: bool = false) -> void:
	results_list.clear()
	_displayed_courses = courses
	download_button.disabled = true

	# The first line of the search/list always shows the instruction
	results_list.add_item(INSTRUCTION_HEADER_TEXT)
	results_list.set_item_custom_fg_color(0, Color(0.65, 0.85, 1.0, 0.95))

	for item in courses:
		var name_text = item.get("name", "Unnamed Course")
		var loc_text = item.get("location", "")
		var holes = item.get("hole_count", 0)
		var updated_ts = item.get("last_updated", "")
		var is_cached = _is_course_cached(item)

		var meta_parts = []
		if holes > 0:
			meta_parts.append(str(holes) + " Holes")
		elif btn_all_holes != null and btn_all_holes.button_pressed:
			meta_parts.append("Holes: N/A")
		if not updated_ts.is_empty():
			var date_only = updated_ts.split("T")[0]
			meta_parts.append("Updated: " + date_only)
		if is_cached:
			meta_parts.append("Cached")

		var display_text = name_text
		if not meta_parts.is_empty():
			display_text += " [" + " | ".join(meta_parts) + "]"
		if not loc_text.is_empty():
			display_text += " (" + loc_text + ")"
		results_list.add_item(display_text)

	if courses.is_empty():
		if is_search_results:
			var query = search_input.text.strip_edges()
			status_label.text = "No courses found matching '" + query + "'."
		else:
			status_label.text = "No cached courses matching active filters."
	else:
		if is_search_results:
			status_label.text = "Found " + str(courses.size()) + " course(s). Select one to download."
		else:
			status_label.text = "Showing " + str(courses.size()) + " cached courses alphabetically. Select from list, or search to download from OSM."


func _show_all_cached_courses() -> void:
	_is_showing_cached = true
	var filtered = _filter_by_hole_settings(_all_cached_courses)
	_display_courses_in_list(filtered, false)
	_update_rate_limit_ui()


func _on_search_text_changed(new_text: String) -> void:
	var query = new_text.strip_edges()
	if query.is_empty():
		_show_all_cached_courses()
		return

	_is_showing_cached = true
	var query_tokens = query.to_lower().split(" ", false)
	var matches = []
	for course in _all_cached_courses:
		var name_lower = course.get("name", "").to_lower()
		var loc_lower = course.get("location", "").to_lower()
		var all_match = true
		for token in query_tokens:
			if not name_lower.contains(token) and not loc_lower.contains(token):
				all_match = false
				break
		if all_match:
			matches.append(course)

	matches = _filter_by_hole_settings(matches)
	_display_courses_in_list(matches, false)

	if is_osm_rate_limited():
		if matches.is_empty():
			var rem = get_osm_cooldown_hours_remaining()
			var rem_text = "1 hour" if rem == 1 else str(rem) + " hours"
			status_label.text = "No cached courses match '" + query + "'. (OSM direct download available in " + rem_text + ")"
		else:
			status_label.text = "Found " + str(matches.size()) + " cached course(s) matching '" + query + "'. Select one to download instantly."
		if expand_search_button != null:
			expand_search_button.visible = false
	else:
		if matches.is_empty():
			status_label.text = "No cached courses match '" + query + "'. Press Enter or click Expand Search to search OpenStreetMap."
			if expand_search_button != null:
				expand_search_button.visible = true
		else:
			status_label.text = "Found " + str(matches.size()) + " cached course(s) matching '" + query + "'. Select one, or press Enter to search OpenStreetMap."
			if expand_search_button != null:
				expand_search_button.visible = false


func _update_rate_limit_ui() -> void:
	if is_osm_rate_limited():
		_show_rate_limit_panel(true)
	else:
		_show_rate_limit_panel(false)


func _show_rate_limit_panel(show: bool, custom_msg: String = "") -> void:
	if rate_limit_warning_panel == null:
		return
	rate_limit_warning_panel.visible = show
	if show and rate_limit_label != null:
		if custom_msg.is_empty():
			rate_limit_label.text = get_osm_rate_limit_warning_message()
		else:
			rate_limit_label.text = custom_msg


func _on_settings_pressed() -> void:
	if settings_overlay != null:
		settings_overlay.visible = true


func _on_settings_closed() -> void:
	_save_search_settings()
	if settings_overlay != null:
		settings_overlay.visible = false
	if _is_showing_cached:
		_show_all_cached_courses()


func _on_btn_9_hole_toggled(pressed: bool) -> void:
	if pressed:
		btn_all_holes.set_pressed_no_signal(false)
	else:
		if not btn_18_hole.button_pressed:
			btn_all_holes.set_pressed_no_signal(true)
	_update_hole_buttons_visual()
	_save_search_settings()
	if _is_showing_cached:
		_on_search_text_changed(search_input.text)


func _on_btn_18_hole_toggled(pressed: bool) -> void:
	if pressed:
		btn_all_holes.set_pressed_no_signal(false)
	else:
		if not btn_9_hole.button_pressed:
			btn_all_holes.set_pressed_no_signal(true)
	_update_hole_buttons_visual()
	_save_search_settings()
	if _is_showing_cached:
		_on_search_text_changed(search_input.text)


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
	if _is_showing_cached:
		_on_search_text_changed(search_input.text)


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
	if cached_only_check != null:
		cached_only_check.button_pressed = false
	if force_online_check != null:
		force_online_check.button_pressed = false
	_update_hole_buttons_visual()
	_save_search_settings()
	if _is_showing_cached:
		_show_all_cached_courses()


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
		if cached_only_check != null:
			cached_only_check.button_pressed = cfg.get_value("search_filter", "cached_only", false)
		if force_online_check != null:
			force_online_check.button_pressed = cfg.get_value("search_filter", "force_online", false)
	else:
		if btn_9_hole != null: btn_9_hole.set_pressed_no_signal(true)
		if btn_18_hole != null: btn_18_hole.set_pressed_no_signal(true)
		if btn_all_holes != null: btn_all_holes.set_pressed_no_signal(false)
		if leisure_golf_check != null: leisure_golf_check.button_pressed = true
		if custom_tags_input != null: custom_tags_input.text = ""
		if cached_only_check != null: cached_only_check.button_pressed = false
		if force_online_check != null: force_online_check.button_pressed = false


func _save_search_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.load(SETTINGS_FILE)
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
	if cached_only_check != null:
		cfg.set_value("search_filter", "cached_only", cached_only_check.button_pressed)
	if force_online_check != null:
		cfg.set_value("search_filter", "force_online", force_online_check.button_pressed)
	cfg.save(SETTINGS_FILE)


func _perform_search(force_online: bool = false) -> void:
	var query = search_input.text.strip_edges()
	if query.is_empty():
		_show_all_cached_courses()
		return

	# When OSM direct rate limit is active and not bypassed, only allow searching cached courses
	if is_osm_rate_limited():
		_on_search_text_changed(query)
		_show_rate_limit_panel(true)
		return

	var is_cached_only = (cached_only_check != null and cached_only_check.button_pressed)
	if is_cached_only and not force_online:
		_on_search_text_changed(query)
		return

	status_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 1.0))
	if force_online:
		status_label.text = "Expanding search for '" + query + "' on OpenStreetMap..."
	else:
		status_label.text = "Searching OpenStreetMap for '" + query + "'..."

	if expand_search_button != null:
		expand_search_button.visible = false

	_set_ui_disabled(true)
	results_list.clear()
	_displayed_courses.clear()
	download_button.disabled = true
	spinner.visible = true
	if notice_panel != null:
		notice_panel.visible = false

	_save_search_settings()
	var should_force_online: bool = force_online or (force_online_check != null and force_online_check.button_pressed)
	var filter_options = {
		"include_9_hole": btn_9_hole.button_pressed if btn_9_hole != null else true,
		"include_18_hole": btn_18_hole.button_pressed if btn_18_hole != null else true,
		"include_all_holes": btn_all_holes.button_pressed if btn_all_holes != null else false,
		"require_leisure_golf": leisure_golf_check.button_pressed if leisure_golf_check != null else true,
		"force_online": should_force_online,
		"cached_only": is_cached_only,
		"custom_tags": custom_tags_input.text.strip_edges() if custom_tags_input != null else ""
	}

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
		if not should_force_online and expand_search_button != null:
			expand_search_button.visible = true
		return

	_is_showing_cached = false
	_display_courses_in_list(results_array, true)

	var from_catalog: bool = false
	for item in results_array:
		if item.get("is_catalog", false):
			from_catalog = true
			break

	if from_catalog and not should_force_online and expand_search_button != null:
		expand_search_button.visible = true
	elif expand_search_button != null:
		expand_search_button.visible = false


func _on_item_selected(index: int) -> void:
	if index == 0:
		# Header instruction selected
		results_list.deselect(0)
		download_button.disabled = true
		status_label.text = INSTRUCTION_HEADER_TEXT
		return

	var course_idx = index - 1
	if course_idx < 0 or course_idx >= _displayed_courses.size():
		download_button.disabled = true
		return

	var course = _displayed_courses[course_idx]
	var is_cached = _is_course_cached(course)

	if not is_cached and is_osm_rate_limited():
		download_button.disabled = true
		var warning = get_osm_rate_limit_warning_message()
		status_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3, 1.0))
		status_label.text = warning
		_show_rate_limit_panel(true, warning)
	else:
		download_button.disabled = false
		status_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88, 1.0))
		var note = " [Cached Course - Instant Download]" if is_cached else " [OpenStreetMap Direct]"
		if is_rate_limit_bypassed() and not is_cached:
			note += " [Dev Bypass Active]"
		status_label.text = "Selected: " + course.get("name", "Unnamed Course") + note + ". Click 'Download & Generate'."
		if is_cached or is_rate_limit_bypassed():
			_show_rate_limit_panel(false)


func _on_download_pressed() -> void:
	var selected_items = results_list.get_selected_items()
	if selected_items.is_empty():
		return

	var idx = selected_items[0]
	if idx == 0:
		return
	var course_idx = idx - 1
	if course_idx < 0 or course_idx >= _displayed_courses.size():
		return

	var course = _displayed_courses[course_idx]
	var course_name = course.get("name", "Unnamed Course")
	var lat = course.get("lat", 0.0)
	var lon = course.get("lon", 0.0)
	var is_cached = _is_course_cached(course)

	# Rate-limit enforcement for OSM direct downloads
	if not is_cached and is_osm_rate_limited():
		var warning = get_osm_rate_limit_warning_message()
		status_label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3, 1.0))
		status_label.text = warning
		_show_rate_limit_panel(true, warning)
		download_button.disabled = true
		return

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
		if not is_cached and not is_rate_limit_bypassed():
			record_osm_download_success(course_name)
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
	if settings_button != null:
		settings_button.disabled = disabled
	results_list.auto_height = false
	results_list.mouse_filter = Control.MOUSE_FILTER_IGNORE if disabled else Control.MOUSE_FILTER_PASS


func _update_progress_status(msg: String) -> void:
	if _download_in_progress and is_instance_valid(self):
		status_label.text = msg
