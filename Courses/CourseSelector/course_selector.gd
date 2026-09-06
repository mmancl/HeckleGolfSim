extends Control

@onready var _course_list = $ContentPanel/ContentMargin/VBoxContainer/ScrollContainer/CourseList
@onready var _course_directory_text: LineEdit = $ContentPanel/ContentMargin/VBoxContainer/CourseDirectory/CourseDirectoryText
@onready var _status_label: Label = $ContentPanel/ContentMargin/VBoxContainer/StatusLabel
@onready var _refresh_button: Button = $ContentPanel/ContentMargin/VBoxContainer/CourseDirectory/RefreshButton
var _play_button: Button
var _preview_button: Button

var active_tab: String = "Real" # "Real" or "Custom"
var real_tab_btn: Button
var custom_tab_btn: Button
var create_custom_btn: Button

var selected_length: String = "Full 18"
var front_9_btn: Button
var back_9_btn: Button
var full_18_btn: Button


func _ready() -> void:
	# Configure back button style and icon
	var main_menu_btn = get_node_or_null("ContentPanel/ContentMargin/VBoxContainer/HeaderHBox/MainMenuButton")
	if main_menu_btn != null:
		main_menu_btn.icon = load("res://UI/MainMenu/images/menu.svg")
		main_menu_btn.expand_icon = true
		ThemeManager.apply_nav_button_style(main_menu_btn)

	_refresh_button.mouse_entered.connect(_on_refresh_button_mouse_entered)
	_refresh_button.mouse_exited.connect(_on_refresh_button_mouse_exited)
	_course_list.item_selected.connect(_on_course_selected)

	var vbox = $ContentPanel/ContentMargin/VBoxContainer
	if vbox != null:
		var tab_hbox = _create_tab_selector()
		vbox.add_child(tab_hbox)
		var scroll_node = vbox.get_node_or_null("ScrollContainer")
		if scroll_node != null:
			vbox.move_child(tab_hbox, scroll_node.get_index())
			if scroll_node is ScrollContainer:
				ThemeManager.apply_scroll_container_style(scroll_node, 28)

	_switch_course_tab("Real")

	# Dynamic OSM Download UI
	if vbox != null:
		var download_panel = PanelContainer.new()
		download_panel.name = "OsmDownloadPanel"
		ThemeManager.apply_card_panel_style(download_panel, false, 8)
		
		var download_hbox = HBoxContainer.new()
		download_hbox.add_theme_constant_override("separation", 15)
		download_panel.add_child(download_hbox)
		
		var section_title = Label.new()
		section_title.text = "Want to play a new course? Search and download from OpenStreetMap:"
		section_title.add_theme_font_size_override("font_size", 18)
		section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		download_hbox.add_child(section_title)
		
		var dl_btn = Button.new()
		dl_btn.text = "Search & Download Course"
		dl_btn.custom_minimum_size = Vector2(280, 56)
		dl_btn.add_theme_font_size_override("font_size", 20)
		ThemeManager.apply_secondary_button_style(dl_btn)
		download_hbox.add_child(dl_btn)
		
		dl_btn.pressed.connect(func():
			var dialog_scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
			if dialog_scene != null:
				var dialog = dialog_scene.instantiate()
				add_child(dialog)
				dialog.course_downloaded.connect(func(_course_name):
					_request_course_reload()
				)
		)
		
		var delete_btn = Button.new()
		delete_btn.text = "Delete Selected Course"
		delete_btn.custom_minimum_size = Vector2(240, 56)
		delete_btn.add_theme_font_size_override("font_size", 20)
		ThemeManager.apply_danger_button_style(delete_btn)
		download_hbox.add_child(delete_btn)
		delete_btn.pressed.connect(_on_delete_course_pressed)
		
		vbox.add_child(download_panel)
		vbox.move_child(download_panel, 0)

		var length_selector = _create_length_selector()
		vbox.add_child(length_selector)

		var green_speed_selector = _create_green_speed_selector()
		vbox.add_child(green_speed_selector)

		# Add Footer with Play Course button
		var footer_hbox = HBoxContainer.new()
		footer_hbox.alignment = BoxContainer.ALIGNMENT_END
		footer_hbox.add_theme_constant_override("separation", 20)
		
		_preview_button = Button.new()
		_preview_button.text = "Preview Course"
		_preview_button.custom_minimum_size = Vector2(240, 60)
		_preview_button.add_theme_font_size_override("font_size", 22)
		ThemeManager.apply_secondary_button_style(_preview_button)
		_preview_button.disabled = true
		_preview_button.pressed.connect(_on_preview_pressed)
		
		_play_button = Button.new()
		_play_button.text = "Play Course"
		_play_button.custom_minimum_size = Vector2(240, 60)
		_play_button.add_theme_font_size_override("font_size", 22)
		ThemeManager.apply_primary_button_style(_play_button)
		_play_button.disabled = true
		_play_button.pressed.connect(_on_play_pressed)
		
		footer_hbox.add_child(_preview_button)
		footer_hbox.add_child(_play_button)
		vbox.add_child(footer_hbox)


func _on_main_menu_button_pressed() -> void:
	SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")


func _on_refresh_button_pressed() -> void:
	_flash_refresh_button()
	_request_course_reload()


func _on_course_list_item_activated(index: int) -> void:
	var scene_path: String = _course_list.get_scene_path_for_index(index)
	var config_path: String = _course_list.get_config_path_for_index(index)

	if scene_path.is_empty():
		printerr("[CourseSelector] Play requested with an empty scene scene_path.")
		return

	if GlobalSettings.practice_mode_primed:
		# Setup a single practice player in MultiplayerManager so it uses normal course play hud and flow
		var players_to_add = [
			{
				"name": "Practice Player",
				"tee": "Blue"
			}
		]
		
		# Load the course config first so MultiplayerManager has the hole info
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file != null:
			var json_text = file.get_as_text()
			var json = JSON.new()
			if json.parse(json_text) == OK:
				var config_dict = json.data
				var mp_mgr = get_node_or_null("/root/MultiplayerManager")
				if mp_mgr != null:
					mp_mgr.setup_game(players_to_add, config_dict, scene_path, config_path, selected_length)
					mp_mgr.practice_mode_active = true
					mp_mgr.start_hole()
					print("[PracticeMode] MultiplayerManager primed with single practice player")

	SceneManager.load_course(scene_path, config_path)


func _request_course_reload() -> void:
	var status_text: String = _course_list.reload_courses(_course_directory_text.text)
	_status_label.text = status_text if not status_text.is_empty() else "Ready"
	_update_play_button()


func _on_delete_course_pressed() -> void:
	var selected = _course_list.get_selected_items()
	if selected.is_empty():
		_status_label.text = "Select a course to delete first."
		return
	
	var metadata = _course_list.get_item_metadata(selected[0])
	var config_path: String = metadata.get("config_path", "")
	
	if config_path.is_empty():
		_status_label.text = "Cannot determine course path."
		return
	
	# Only allow deleting user-downloaded courses, not built-in ones
	if not config_path.begins_with("user://"):
		_status_label.text = "Cannot delete built-in courses."
		return
	
	var course_dir = config_path.get_base_dir()
	var course_title = metadata.get("title", course_dir.get_file())
	
	# Show confirmation dialog
	var confirm = ConfirmationDialog.new()
	confirm.title = "Delete Course"
	confirm.dialog_text = "Delete course \"%s\"?\n\nThis will permanently remove all files in:\n%s" % [course_title, course_dir]
	confirm.min_size = Vector2(480, 200)
	ThemeManager.apply_dialog_style(confirm)
	confirm.confirmed.connect(func():
		_delete_course_dir(course_dir)
		_status_label.text = "Deleted course: %s" % course_title
		_request_course_reload()
		confirm.queue_free()
	)
	confirm.canceled.connect(func():
		confirm.queue_free()
	)
	add_child(confirm)
	confirm.popup_centered()


func _delete_course_dir(dir_path: String) -> void:
	var global_path = ProjectSettings.globalize_path(dir_path)
	var dir = DirAccess.open(dir_path)
	if dir == null:
		printerr("[CourseSelector] Failed to open directory for deletion: %s" % dir_path)
		return
	
	# Delete all files in the directory
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			dir.remove(file_name)
			print("[CourseSelector] Deleted file: %s/%s" % [dir_path, file_name])
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# Remove the directory itself
	var parent_dir = DirAccess.open(dir_path.get_base_dir())
	if parent_dir != null:
		parent_dir.remove(dir_path.get_file())
		print("[CourseSelector] Deleted course directory: %s" % dir_path)


func _flash_refresh_button() -> void:
	_refresh_button.self_modulate = Color(1, 1, 1, 1)
	var tween := create_tween()
	tween.tween_property(_refresh_button, "self_modulate", Color(0.75, 0.9, 1.0, 1), 0.08)
	tween.tween_property(_refresh_button, "self_modulate", Color(1, 1, 1, 1), 0.16)


func _on_refresh_button_mouse_entered() -> void:
	_refresh_button.self_modulate = Color(0.8, 0.92, 1.0, 1)


func _on_refresh_button_mouse_exited() -> void:
	_refresh_button.self_modulate = Color(1, 1, 1, 1)


func _on_course_selected(index: int) -> void:
	_update_play_button()
	_update_course_length_options(index)


func _update_play_button() -> void:
	var has_selection = not _course_list.get_selected_items().is_empty()
	if _play_button != null:
		_play_button.disabled = not has_selection
	if _preview_button != null:
		_preview_button.disabled = not has_selection


func _on_play_pressed() -> void:
	var selected = _course_list.get_selected_items()
	if not selected.is_empty():
		_on_course_list_item_activated(selected[0])


func _on_preview_pressed() -> void:
	var selected = _course_list.get_selected_items()
	if selected.is_empty():
		return
		
	var idx = selected[0]
	var metadata = _course_list.get_item_metadata(idx)
	var config_path: String = metadata.get("config_path", "")
	var scene_path: String = metadata.get("scene_path", "")
	
	var dialog_scene = load("res://UI/CoursePreviewDialog/course_preview_dialog.tscn")
	if dialog_scene != null:
		var dialog = dialog_scene.instantiate()
		add_child(dialog)
		dialog.setup(config_path, scene_path)


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


func _create_length_selector() -> PanelContainer:
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.15, 0.2, 0.4)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.4, 0.5, 0.3)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	panel.add_child(hbox)

	var lbl = Label.new()
	lbl.text = "Select Holes:"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl)

	# Segmented buttons container
	var seg_hbox = HBoxContainer.new()
	seg_hbox.add_theme_constant_override("separation", 0) # Segments touch
	hbox.add_child(seg_hbox)

	front_9_btn = Button.new()
	front_9_btn.text = "Front 9"
	front_9_btn.custom_minimum_size = Vector2(150, 48)
	front_9_btn.add_theme_font_size_override("font_size", 20)
	seg_hbox.add_child(front_9_btn)

	back_9_btn = Button.new()
	back_9_btn.text = "Back 9"
	back_9_btn.custom_minimum_size = Vector2(150, 48)
	back_9_btn.add_theme_font_size_override("font_size", 20)
	seg_hbox.add_child(back_9_btn)

	full_18_btn = Button.new()
	full_18_btn.text = "Full 18"
	full_18_btn.custom_minimum_size = Vector2(150, 48)
	full_18_btn.add_theme_font_size_override("font_size", 20)
	seg_hbox.add_child(full_18_btn)

	# Style buttons and setup connections
	front_9_btn.pressed.connect(func(): _select_length("Front 9"))
	back_9_btn.pressed.connect(func(): _select_length("Back 9"))
	full_18_btn.pressed.connect(func(): _select_length("Full 18"))

	_select_length("Full 18") # Default selection
	return panel


func _style_seg_button(btn: Button, position: String, active: bool) -> void:
	var style = StyleBoxFlat.new()
	if btn.disabled:
		style.bg_color = Color(0.08, 0.08, 0.08, 0.3)
		style.border_color = Color(0.15, 0.15, 0.15, 0.2)
	elif active:
		style.bg_color = Color(0.18, 0.45, 0.35, 0.95) # active green
		style.border_color = Color(0.35, 0.8, 0.6, 0.8)
	else:
		style.bg_color = Color(0.1, 0.12, 0.16, 0.6)
		style.border_color = Color(0.2, 0.25, 0.3, 0.5)
	
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1

	if position == "left":
		style.corner_radius_top_left = 8
		style.corner_radius_bottom_left = 8
	elif position == "right":
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style.duplicate() if active else _get_hover_style(style))
	btn.add_theme_stylebox_override("pressed", style)
	
	if btn.disabled:
		btn.add_theme_color_override("font_disabled_color", Color(0.35, 0.35, 0.35))
	elif active:
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
	else:
		btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		btn.add_theme_color_override("font_hover_color", Color(0.9, 0.9, 0.9))


func _get_hover_style(base_style: StyleBoxFlat) -> StyleBoxFlat:
	var hover = base_style.duplicate()
	hover.bg_color = base_style.bg_color.lightened(0.12)
	hover.border_color = base_style.border_color.lightened(0.12)
	return hover


func _select_length(length: String) -> void:
	selected_length = length
	_style_seg_button(front_9_btn, "left", selected_length == "Front 9")
	_style_seg_button(back_9_btn, "middle", selected_length == "Back 9")
	_style_seg_button(full_18_btn, "right", selected_length == "Full 18")


func _update_course_length_options(idx: int) -> void:
	var course_data = _course_list.get_item_metadata(idx)
	var config_path: String = course_data.get("config_path", "")
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			var holes = parsed.get("Hole Info", {})
			var num_holes = holes.keys().size()
			if num_holes < 10:
				back_9_btn.disabled = true
				if selected_length == "Back 9":
					_select_length("Front 9")
				else:
					_select_length(selected_length)
			else:
				back_9_btn.disabled = false
				_select_length(selected_length)


func _create_green_speed_selector() -> PanelContainer:
	var panel = PanelContainer.new()
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.15, 0.2, 0.4)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.4, 0.5, 0.3)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	panel.add_child(hbox)

	var lbl = Label.new()
	lbl.text = "Green Speed: "
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl)

	var slider = HSlider.new()
	slider.min_value = 1.0
	slider.max_value = 50.0
	slider.step = 1.0
	slider.value = GlobalSettings.range_settings.green_speed.value
	slider.custom_minimum_size = Vector2(300, 30)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(slider)

	var val_lbl = Label.new()
	val_lbl.text = str(slider.value)
	val_lbl.add_theme_font_size_override("font_size", 24)
	val_lbl.custom_minimum_size = Vector2(50, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(val_lbl)

	slider.value_changed.connect(func(val):
		GlobalSettings.range_settings.green_speed.set_value(val)
		val_lbl.text = str(val)
	)

	return panel


func _create_tab_selector() -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	real_tab_btn = Button.new()
	real_tab_btn.text = "Real Courses"
	real_tab_btn.custom_minimum_size = Vector2(180, 44)
	real_tab_btn.add_theme_font_size_override("font_size", 20)

	custom_tab_btn = Button.new()
	custom_tab_btn.text = "Custom Courses"
	custom_tab_btn.custom_minimum_size = Vector2(180, 44)
	custom_tab_btn.add_theme_font_size_override("font_size", 20)

	create_custom_btn = Button.new()
	create_custom_btn.text = "+ Create Custom Course"
	create_custom_btn.custom_minimum_size = Vector2(240, 44)
	create_custom_btn.add_theme_font_size_override("font_size", 20)

	real_tab_btn.pressed.connect(func(): _switch_course_tab("Real"))
	custom_tab_btn.pressed.connect(func(): _switch_course_tab("Custom"))
	create_custom_btn.pressed.connect(_on_create_custom_pressed)

	hbox.add_child(real_tab_btn)
	hbox.add_child(custom_tab_btn)
	hbox.add_child(create_custom_btn)

	return hbox


func _switch_course_tab(tab: String) -> void:
	active_tab = tab
	_update_tab_button_styles()
	if _course_list != null:
		_course_list.set_filter_mode(active_tab)
		_update_play_button()


func _update_tab_button_styles() -> void:
	if real_tab_btn != null:
		_style_seg_button(real_tab_btn, "left", active_tab == "Real")
	if custom_tab_btn != null:
		_style_seg_button(custom_tab_btn, "right", active_tab == "Custom")
	if create_custom_btn != null:
		apply_button_style(create_custom_btn, Color(0.2, 0.55, 0.35))


func _on_create_custom_pressed() -> void:
	var dialog_scene = load("res://UI/CustomCourseCreator/custom_course_creator.tscn")
	if dialog_scene != null:
		var dialog = dialog_scene.instantiate()
		add_child(dialog)
		dialog.course_created.connect(func(_new_course):
			_switch_course_tab("Custom")
			_request_course_reload()
		)
