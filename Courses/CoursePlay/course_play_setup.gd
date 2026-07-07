extends Control

@onready var player_list_vbox = VBoxContainer.new()
@onready var course_list = ItemList.new()
@onready var start_button = Button.new()
var delete_confirm_dialog: ConfirmationDialog

var available_courses: Array[Dictionary] = []
var players_to_add: Array[Dictionary] = []

func _ready() -> void:
	# Build the setup screen dynamically
	name = "CoursePlaySetup"
	
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.1, 1.0)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.custom_minimum_size = Vector2(1728, 972)
	add_child(bg)
	
	var main_margin = MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 50)
	main_margin.add_theme_constant_override("margin_right", 50)
	main_margin.add_theme_constant_override("margin_top", 50)
	main_margin.add_theme_constant_override("margin_bottom", 50)
	main_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_margin.custom_minimum_size = Vector2(1728, 972)
	add_child(main_margin)
	
	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 50)
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_margin.add_child(main_hbox)
	
	# Left Column: Player Setup
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 1.2
	left_vbox.add_theme_constant_override("separation", 20)
	main_hbox.add_child(left_vbox)
	
	var title = Label.new()
	title.text = "Player Setup (Multiplayer)"
	title.add_theme_font_size_override("font_size", 32)
	left_vbox.add_child(title)
	
	# Add player control row
	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 10)
	
	var name_input = LineEdit.new()
	name_input.placeholder_text = "Player Name"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(name_input)
	
	var tee_opt = OptionButton.new()
	tee_opt.add_item("Blue", 0)
	tee_opt.add_item("Red", 1)
	tee_opt.add_item("White", 2)
	tee_opt.add_item("Black", 3)
	add_row.add_child(tee_opt)
	
	var add_btn = Button.new()
	add_btn.text = "Add Player"
	add_btn.pressed.connect(func():
		var name_text = name_input.text.strip_edges()
		if name_text.is_empty():
			name_text = "Player " + str(players_to_add.size() + 1)
		var tee_color = tee_opt.get_item_text(tee_opt.selected)
		_add_player_ui(name_text, tee_color)
		name_input.clear()
	)
	add_row.add_child(add_btn)
	left_vbox.add_child(add_row)
	
	# Players list vbox container
	player_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_list_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(player_list_vbox)
	
	# Right Column: Course Select & Play
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 20)
	main_hbox.add_child(right_vbox)
	
	var course_title = Label.new()
	course_title.text = "Select Course"
	course_title.add_theme_font_size_override("font_size", 32)
	right_vbox.add_child(course_title)
	
	# Course list
	course_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(course_list)
	course_list.item_selected.connect(func(_idx): _update_start_button())
	course_list.item_activated.connect(func(_idx):
		if not start_button.disabled:
			_on_start_pressed()
	)
	_scan_available_courses()
	
	# Footer Actions
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 20)
	
	var back_btn = Button.new()
	back_btn.text = "Main Menu"
	back_btn.custom_minimum_size = Vector2(150, 50)
	back_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
	action_row.add_child(back_btn)
	
	var download_btn = Button.new()
	download_btn.text = "Search & Download OSM Course"
	download_btn.custom_minimum_size = Vector2(300, 50)
	download_btn.pressed.connect(func():
		var dialog_scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
		if dialog_scene != null:
			var dialog = dialog_scene.instantiate()
			add_child(dialog)
			dialog.course_downloaded.connect(func(_course_name):
				_scan_available_courses()
			)
	)
	action_row.add_child(download_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "Delete Course"
	delete_btn.custom_minimum_size = Vector2(200, 50)
	delete_btn.pressed.connect(_on_delete_course_pressed)
	action_row.add_child(delete_btn)
	
	# Confirmation dialog for course deletion
	delete_confirm_dialog = ConfirmationDialog.new()
	delete_confirm_dialog.title = "Confirm Delete"
	delete_confirm_dialog.dialog_text = "Are you sure you want to delete this course?"
	delete_confirm_dialog.min_size = Vector2(400, 150)
	add_child(delete_confirm_dialog)
	
	start_button.text = "Play Course"
	start_button.custom_minimum_size = Vector2(200, 50)
	start_button.disabled = true
	start_button.pressed.connect(_on_start_pressed)
	action_row.add_child(start_button)
	
	right_vbox.add_child(action_row)
	
	# Add default Player 1
	_add_player_ui("Player 1", "Blue")


func _add_player_ui(p_name: String, tee: String) -> void:
	var idx = players_to_add.size()
	var player_data = {"name": p_name, "tee": tee}
	players_to_add.append(player_data)
	
	var row = HBoxContainer.new()
	row.name = "PlayerRow_" + str(idx)
	row.add_theme_constant_override("separation", 20)
	
	var name_lbl = Label.new()
	name_lbl.text = p_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)
	
	var tee_lbl = Label.new()
	tee_lbl.text = "Tee: " + tee
	tee_lbl.custom_minimum_size = Vector2(100, 0)
	row.add_child(tee_lbl)
	
	var remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(func():
		players_to_add.erase(player_data)
		row.queue_free()
		_update_start_button()
	)
	row.add_child(remove_btn)
	
	player_list_vbox.add_child(row)
	_update_start_button()


func _update_start_button() -> void:
	start_button.disabled = players_to_add.is_empty() or course_list.get_selected_items().is_empty()


func _scan_available_courses() -> void:
	course_list.clear()
	available_courses.clear()
	
	var validated: Array[Dictionary] = []
	_scan_dir("res://Courses/UserCourses", validated)
	_scan_dir("user://courses", validated)
	
	for course in validated:
		var item_idx = course_list.get_item_count()
		course_list.add_item(course["title"])
		course_list.set_item_metadata(item_idx, course)
		available_courses.append(course)


func _scan_dir(dir_path: String, validated: Array[Dictionary]) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var dir_name := dir.get_next()
	while dir_name != "":
		if dir.current_is_dir() and not dir_name.begins_with("."):
			var result: Dictionary = CourseValidator.validate(dir_path, dir_name)
			if not result.is_empty():
				result["dir_name"] = dir_name
				validated.append(result)
		dir_name = dir.get_next()
	dir.list_dir_end()


func _on_delete_course_pressed() -> void:
	var selected_items = course_list.get_selected_items()
	if selected_items.is_empty():
		push_warning("[CoursePlaySetup] No course selected to delete.")
		return
	
	var selected_idx = selected_items[0]
	var course_data = course_list.get_item_metadata(selected_idx)
	var config_path: String = course_data.get("config_path", "")
	var course_dir: String = config_path.get_base_dir()
	
	# Only allow deleting user-downloaded courses, not built-in ones
	if not course_dir.begins_with("user://courses/"):
		push_warning("[CoursePlaySetup] Cannot delete built-in course: " + course_dir)
		return
	
	var course_title: String = course_data.get("title", course_dir)
	delete_confirm_dialog.dialog_text = "Are you sure you want to delete the course '" + course_title + "'?\nThis cannot be undone."
	
	# Disconnect any previous confirmation to avoid stacking connections
	if delete_confirm_dialog.confirmed.is_connected(_confirm_delete_course):
		delete_confirm_dialog.confirmed.disconnect(_confirm_delete_course)
	delete_confirm_dialog.confirmed.connect(_confirm_delete_course.bind(course_dir, course_title))
	delete_confirm_dialog.popup_centered()


func _confirm_delete_course(course_dir: String, course_title: String) -> void:
	# Disconnect so it doesn't fire again for the next deletion
	if delete_confirm_dialog.confirmed.is_connected(_confirm_delete_course):
		delete_confirm_dialog.confirmed.disconnect(_confirm_delete_course)
	
	_delete_course_dir(course_dir)
	print("[CoursePlaySetup] Deleted course '" + course_title + "' at: " + course_dir)
	_scan_available_courses()


func _delete_course_dir(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[CoursePlaySetup] Failed to open directory for deletion: " + dir_path)
		return
	
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_delete_course_dir(full_path)
		else:
			var err := dir.remove(file_name)
			if err != OK:
				push_error("[CoursePlaySetup] Failed to delete file: " + full_path)
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# Remove the now-empty directory itself
	var parent_path := dir_path.get_base_dir()
	var parent_dir := DirAccess.open(parent_path)
	if parent_dir != null:
		var err := parent_dir.remove(dir_path.get_file())
		if err != OK:
			push_error("[CoursePlaySetup] Failed to remove directory: " + dir_path)


func _on_start_pressed() -> void:
	var selected_items = course_list.get_selected_items()
	if selected_items.is_empty():
		return
		
	var selected_idx = selected_items[0]
	var course_data = course_list.get_item_metadata(selected_idx)
	
	var scene_path = course_data.get("scene_path", "")
	var config_path = course_data.get("config_path", "")
	
	# Load config so MultiplayerManager can initialize hole/tee details
	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("[CoursePlaySetup] Failed to read course config JSON: " + config_path)
		return
		
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[CoursePlaySetup] Invalid course JSON: " + config_path)
		return
		
	# Setup MultiplayerManager
	get_node("/root/MultiplayerManager").setup_game(players_to_add, parsed, scene_path, config_path)
	get_node("/root/MultiplayerManager").start_hole()
	
	# Load course
	SceneManager.load_course(scene_path, config_path)
