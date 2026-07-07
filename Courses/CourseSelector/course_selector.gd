extends Control

@onready var _course_list = $ContentPanel/ContentMargin/VBoxContainer/ScrollContainer/CourseList
@onready var _course_directory_text: LineEdit = $ContentPanel/ContentMargin/VBoxContainer/CourseDirectory/CourseDirectoryText
@onready var _status_label: Label = $ContentPanel/ContentMargin/VBoxContainer/StatusLabel
@onready var _refresh_button: Button = $ContentPanel/ContentMargin/VBoxContainer/CourseDirectory/RefreshButton
var _play_button: Button


func _ready() -> void:
	_refresh_button.mouse_entered.connect(_on_refresh_button_mouse_entered)
	_refresh_button.mouse_exited.connect(_on_refresh_button_mouse_exited)
	_course_list.item_selected.connect(_on_course_selected)
	_request_course_reload()

	# Dynamic OSM Download UI
	var vbox = $ContentPanel/ContentMargin/VBoxContainer
	if vbox != null:
		var download_panel = PanelContainer.new()
		download_panel.name = "OsmDownloadPanel"
		
		var panel_style = StyleBoxFlat.new()
		panel_style.bg_color = Color(0.1, 0.15, 0.2, 0.7)
		panel_style.border_width_left = 1
		panel_style.border_width_right = 1
		panel_style.border_width_top = 1
		panel_style.border_width_bottom = 1
		panel_style.border_color = Color(0.3, 0.45, 0.6, 0.8)
		panel_style.corner_radius_top_left = 8
		panel_style.corner_radius_top_right = 8
		panel_style.corner_radius_bottom_left = 8
		panel_style.corner_radius_bottom_right = 8
		panel_style.content_margin_left = 12
		panel_style.content_margin_right = 12
		panel_style.content_margin_top = 12
		panel_style.content_margin_bottom = 12
		download_panel.add_theme_stylebox_override("panel", panel_style)
		
		var download_hbox = HBoxContainer.new()
		download_hbox.add_theme_constant_override("separation", 15)
		download_panel.add_child(download_hbox)
		
		var section_title = Label.new()
		section_title.text = "Want to play a new course? Search and download from OpenStreetMap:"
		section_title.add_theme_font_size_override("font_size", 20)
		section_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		download_hbox.add_child(section_title)
		
		var dl_btn = Button.new()
		dl_btn.text = "Search & Download Course"
		dl_btn.custom_minimum_size = Vector2(280, 45)
		dl_btn.add_theme_font_size_override("font_size", 20)
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
		delete_btn.custom_minimum_size = Vector2(250, 45)
		delete_btn.add_theme_font_size_override("font_size", 20)
		download_hbox.add_child(delete_btn)
		delete_btn.pressed.connect(_on_delete_course_pressed)
		
		vbox.add_child(download_panel)
		vbox.move_child(download_panel, 0)

		# Add Footer with Play Course button
		var footer_hbox = HBoxContainer.new()
		footer_hbox.alignment = BoxContainer.ALIGNMENT_END
		footer_hbox.add_theme_constant_override("separation", 20)
		
		_play_button = Button.new()
		_play_button.text = "Play Course"
		_play_button.custom_minimum_size = Vector2(200, 50)
		_play_button.add_theme_font_size_override("font_size", 20)
		_play_button.disabled = true
		_play_button.pressed.connect(_on_play_pressed)
		
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
					mp_mgr.setup_game(players_to_add, config_dict)
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
	confirm.min_size = Vector2(450, 200)
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


func _on_course_selected(_index: int) -> void:
	_update_play_button()


func _update_play_button() -> void:
	if _play_button != null:
		_play_button.disabled = _course_list.get_selected_items().is_empty()


func _on_play_pressed() -> void:
	var selected = _course_list.get_selected_items()
	if not selected.is_empty():
		_on_course_list_item_activated(selected[0])

