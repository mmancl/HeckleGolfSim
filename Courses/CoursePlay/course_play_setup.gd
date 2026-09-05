extends Control

@onready var player_list_vbox = VBoxContainer.new()
@onready var course_list = ItemList.new()
@onready var start_button = Button.new()
var preview_button = Button.new()
var delete_confirm_dialog: ConfirmationDialog

var available_courses: Array[Dictionary] = []
var players_to_add: Array[Dictionary] = []

var selected_length: String = "Full 18"
var front_9_btn: Button
var back_9_btn: Button
var full_18_btn: Button

var active_course_tab: String = "Real" # "Real" or "Custom"
var real_tab_btn: Button
var custom_tab_btn: Button
var create_custom_btn: Button

var selected_game_mode: String = "Standard"
var mode_std_btn: Button
var mode_scramble_btn: Button
var mode_2v2_btn: Button
var mode_skins_btn: Button
var mode_closest_btn: Button
var mode_desc_lbl: Label
var team_assignments: Dictionary = {}

func _ready() -> void:
	# Build the setup screen dynamically
	name = "CoursePlaySetup"
	
	# Background Cabo Texture (matching history/practice screens)
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
	title_lbl.text = "Course Play Setup"
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
	
	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 50)
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(main_hbox)
	
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
	
	# Add player control row - enlarged for touch usability
	var add_row = HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 10)
	
	var player_select_opt = OptionButton.new()
	player_select_opt.custom_minimum_size = Vector2(250, 56)
	player_select_opt.add_theme_font_size_override("font_size", 24)
	add_row.add_child(player_select_opt)
	
	var name_input = LineEdit.new()
	name_input.placeholder_text = "Player Name"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_input.custom_minimum_size = Vector2(0, 56)
	name_input.add_theme_font_size_override("font_size", 24)
	ThemeManager.apply_input_style(name_input)
	add_row.add_child(name_input)
	
	# Helper to refresh the dropdown selection list
	var refresh_player_select = func():
		player_select_opt.clear()
		player_select_opt.add_item("New Player...", 0)
		var registered = MultiplayerManager.get_registered_players()
		for i in range(registered.size()):
			player_select_opt.add_item(registered[i].get("name", "Player"), i + 1)
		player_select_opt.selected = 0
		name_input.visible = true
	
	refresh_player_select.call()
	
	player_select_opt.item_selected.connect(func(index):
		if index == 0:
			name_input.visible = true
		else:
			name_input.visible = false
	)
	
	var tee_opt = OptionButton.new()
	tee_opt.add_item("Blue", 0)
	tee_opt.add_item("Red", 1)
	tee_opt.add_item("White", 2)
	tee_opt.add_item("Black", 3)
	tee_opt.custom_minimum_size = Vector2(150, 56)
	tee_opt.add_theme_font_size_override("font_size", 24)
	add_row.add_child(tee_opt)
	
	var add_btn = Button.new()
	add_btn.text = "Add Player"
	add_btn.custom_minimum_size = Vector2(180, 56)
	add_btn.add_theme_font_size_override("font_size", 24)
	ThemeManager.apply_primary_button_style(add_btn)
	add_btn.pressed.connect(func():
		var name_text = ""
		if player_select_opt.selected == 0:
			name_text = name_input.text.strip_edges()
			if name_text.is_empty():
				name_text = "Player " + str(players_to_add.size() + 1)
		else:
			name_text = player_select_opt.get_item_text(player_select_opt.selected)
			
		var tee_color = tee_opt.get_item_text(tee_opt.selected)
		_add_player_ui(name_text, tee_color)
		
		# Ensure registered persistently
		MultiplayerManager.register_player(name_text)
		
		name_input.clear()
		refresh_player_select.call()
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

	var tab_selector = _create_tab_selector()
	right_vbox.add_child(tab_selector)
	
	# Course list
	course_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	course_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	course_list.add_theme_font_size_override("font_size", 24)
	course_list.add_theme_constant_override("v_separation", 20)
	right_vbox.add_child(course_list)
	
	var game_mode_selector = _create_game_mode_selector()
	right_vbox.add_child(game_mode_selector)

	var length_selector = _create_length_selector()
	right_vbox.add_child(length_selector)
	
	course_list.item_selected.connect(func(idx):
		_update_start_button()
		_update_course_length_options(idx)
	)
	course_list.item_activated.connect(func(_idx):
		if not start_button.disabled:
			_on_start_pressed()
	)
	_scan_available_courses()
	
	# Footer Actions
	var action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	
	var download_btn = Button.new()
	download_btn.text = "Download Course"
	download_btn.custom_minimum_size = Vector2(220, 64)
	download_btn.add_theme_font_size_override("font_size", 22)
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
	delete_btn.custom_minimum_size = Vector2(180, 64)
	delete_btn.add_theme_font_size_override("font_size", 22)
	delete_btn.pressed.connect(_on_delete_course_pressed)
	action_row.add_child(delete_btn)
	
	# Confirmation dialog for course deletion
	delete_confirm_dialog = ConfirmationDialog.new()
	delete_confirm_dialog.title = "Confirm Delete"
	delete_confirm_dialog.dialog_text = "Are you sure you want to delete this course?"
	delete_confirm_dialog.min_size = Vector2(400, 150)
	add_child(delete_confirm_dialog)
	
	preview_button.text = "Preview Course"
	preview_button.custom_minimum_size = Vector2(200, 64)
	preview_button.add_theme_font_size_override("font_size", 22)
	ThemeManager.apply_secondary_button_style(preview_button)
	preview_button.disabled = true
	preview_button.pressed.connect(_on_preview_pressed)
	action_row.add_child(preview_button)

	start_button.text = "Play Course"
	start_button.custom_minimum_size = Vector2(200, 64)
	start_button.add_theme_font_size_override("font_size", 22)
	ThemeManager.apply_primary_button_style(start_button)
	start_button.disabled = true
	start_button.pressed.connect(_on_start_pressed)
	action_row.add_child(start_button)
	
	right_vbox.add_child(action_row)
	
	# Add default Player 1
	_add_player_ui("Player 1", "Blue")


func _add_player_ui(p_name: String, tee: String) -> void:
	var idx = players_to_add.size()
	var avatar_path = MultiplayerManager.get_player_avatar(p_name)
	var email = MultiplayerManager.get_player_email(p_name)
	var player_data = {"name": p_name, "tee": tee, "avatar": avatar_path, "email": email}
	players_to_add.append(player_data)
	
	var row = HBoxContainer.new()
	row.name = "PlayerRow_" + str(idx)
	row.add_theme_constant_override("separation", 20)
	
	if not avatar_path.is_empty() and ResourceLoader.exists(avatar_path):
		var avatar_rect = TextureRect.new()
		avatar_rect.texture = load(avatar_path)
		avatar_rect.custom_minimum_size = Vector2(44, 44)
		avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(avatar_rect)
	else:
		var badge = PanelContainer.new()
		badge.custom_minimum_size = Vector2(40, 40)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var badge_style = StyleBoxFlat.new()
		var p_color = MultiplayerManager.player_colors[idx % MultiplayerManager.player_colors.size()]
		badge_style.bg_color = p_color
		badge_style.corner_radius_top_left = 20
		badge_style.corner_radius_top_right = 20
		badge_style.corner_radius_bottom_left = 20
		badge_style.corner_radius_bottom_right = 20
		badge.add_theme_stylebox_override("panel", badge_style)
		var badge_lbl = Label.new()
		badge_lbl.text = p_name.substr(0, 1).to_upper()
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_lbl.add_theme_font_size_override("font_size", 20)
		badge.add_child(badge_lbl)
		row.add_child(badge)

	var name_lbl = Label.new()
	name_lbl.text = p_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 24)
	row.add_child(name_lbl)
	
	var tee_lbl = Label.new()
	tee_lbl.text = "Tee: " + tee
	tee_lbl.custom_minimum_size = Vector2(160, 0)
	tee_lbl.add_theme_font_size_override("font_size", 24)
	row.add_child(tee_lbl)
	
	var remove_btn = Button.new()
	remove_btn.text = "Remove"
	remove_btn.custom_minimum_size = Vector2(140, 56)
	remove_btn.add_theme_font_size_override("font_size", 24)
	ThemeManager.apply_danger_button_style(remove_btn)
	remove_btn.pressed.connect(func():
		players_to_add.erase(player_data)
		row.queue_free()
		_update_start_button()
	)
	row.add_child(remove_btn)
	
	player_list_vbox.add_child(row)
	_update_start_button()


func _update_start_button() -> void:
	var has_course = not course_list.get_selected_items().is_empty()
	start_button.disabled = players_to_add.is_empty() or not has_course
	if preview_button != null:
		preview_button.disabled = not has_course


func _on_preview_pressed() -> void:
	var selected_items = course_list.get_selected_items()
	if selected_items.is_empty():
		return
		
	var selected_idx = selected_items[0]
	var course_data = course_list.get_item_metadata(selected_idx)
	var config_path = course_data.get("config_path", "")
	var scene_path = course_data.get("scene_path", "")
	
	var dialog_scene = load("res://UI/CoursePreviewDialog/course_preview_dialog.tscn")
	if dialog_scene != null:
		var dialog = dialog_scene.instantiate()
		add_child(dialog)
		dialog.setup(config_path, scene_path)


func _scan_available_courses() -> void:
	course_list.clear()
	available_courses.clear()
	
	var validated: Array[Dictionary] = []
	_scan_dir("res://Courses/UserCourses", validated)
	_scan_dir("user://courses", validated)
	
	for course in validated:
		var is_custom: bool = course.get("is_custom", false)
		if active_course_tab == "Real" and is_custom:
			continue
		elif active_course_tab == "Custom" and not is_custom:
			continue

		var item_idx = course_list.get_item_count()
		course_list.add_item(course["title"])
		course_list.set_item_metadata(item_idx, course)
		available_courses.append(course)

	_update_start_button()


func _create_tab_selector() -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	real_tab_btn = Button.new()
	real_tab_btn.text = "Real Courses"
	real_tab_btn.custom_minimum_size = Vector2(160, 48)
	real_tab_btn.add_theme_font_size_override("font_size", 20)

	custom_tab_btn = Button.new()
	custom_tab_btn.text = "Custom Courses"
	custom_tab_btn.custom_minimum_size = Vector2(160, 48)
	custom_tab_btn.add_theme_font_size_override("font_size", 20)

	create_custom_btn = Button.new()
	create_custom_btn.text = "+ Create Custom Course"
	create_custom_btn.custom_minimum_size = Vector2(230, 48)
	create_custom_btn.add_theme_font_size_override("font_size", 20)

	real_tab_btn.pressed.connect(func(): _switch_course_tab("Real"))
	custom_tab_btn.pressed.connect(func(): _switch_course_tab("Custom"))
	create_custom_btn.pressed.connect(_on_create_custom_pressed)

	hbox.add_child(real_tab_btn)
	hbox.add_child(custom_tab_btn)
	hbox.add_child(create_custom_btn)

	_update_tab_button_styles()
	return hbox


func _switch_course_tab(tab: String) -> void:
	active_course_tab = tab
	_update_tab_button_styles()
	_scan_available_courses()


func _update_tab_button_styles() -> void:
	if real_tab_btn != null:
		_style_seg_button(real_tab_btn, "left", active_course_tab == "Real")
	if custom_tab_btn != null:
		_style_seg_button(custom_tab_btn, "right", active_course_tab == "Custom")
	if create_custom_btn != null:
		apply_button_style(create_custom_btn, Color(0.2, 0.55, 0.35))


func _on_create_custom_pressed() -> void:
	var dialog_scene = load("res://UI/CustomCourseCreator/custom_course_creator.tscn")
	if dialog_scene != null:
		var dialog = dialog_scene.instantiate()
		add_child(dialog)
		dialog.course_created.connect(func(_new_course):
			_switch_course_tab("Custom")
		)



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
	get_node("/root/MultiplayerManager").setup_game(players_to_add, parsed, scene_path, config_path, selected_length, selected_game_mode, team_assignments)
	get_node("/root/MultiplayerManager").start_hole()
	
	# Load course
	SceneManager.load_course(scene_path, config_path)


func _create_game_mode_selector() -> PanelContainer:
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

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	vbox.add_child(hbox)

	var lbl = Label.new()
	lbl.text = "Game Mode:"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl)

	var seg_hbox = HBoxContainer.new()
	seg_hbox.add_theme_constant_override("separation", 0)
	hbox.add_child(seg_hbox)

	mode_std_btn = Button.new()
	mode_std_btn.text = "Standard"
	mode_std_btn.custom_minimum_size = Vector2(115, 48)
	mode_std_btn.add_theme_font_size_override("font_size", 17)
	seg_hbox.add_child(mode_std_btn)

	mode_scramble_btn = Button.new()
	mode_scramble_btn.text = "Scramble"
	mode_scramble_btn.custom_minimum_size = Vector2(115, 48)
	mode_scramble_btn.add_theme_font_size_override("font_size", 17)
	seg_hbox.add_child(mode_scramble_btn)

	mode_2v2_btn = Button.new()
	mode_2v2_btn.text = "2v2 Scramble"
	mode_2v2_btn.custom_minimum_size = Vector2(135, 48)
	mode_2v2_btn.add_theme_font_size_override("font_size", 17)
	seg_hbox.add_child(mode_2v2_btn)

	mode_skins_btn = Button.new()
	mode_skins_btn.text = "Skins"
	mode_skins_btn.custom_minimum_size = Vector2(95, 48)
	mode_skins_btn.add_theme_font_size_override("font_size", 17)
	seg_hbox.add_child(mode_skins_btn)

	mode_closest_btn = Button.new()
	mode_closest_btn.text = "Closest to Pin"
	mode_closest_btn.custom_minimum_size = Vector2(145, 48)
	mode_closest_btn.add_theme_font_size_override("font_size", 17)
	seg_hbox.add_child(mode_closest_btn)

	mode_desc_lbl = Label.new()
	mode_desc_lbl.add_theme_font_size_override("font_size", 16)
	mode_desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	mode_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(mode_desc_lbl)

	mode_std_btn.pressed.connect(func(): _select_game_mode("Standard"))
	mode_scramble_btn.pressed.connect(func(): _select_game_mode("Scramble"))
	mode_2v2_btn.pressed.connect(func(): _select_game_mode("2v2 Scramble"))
	mode_skins_btn.pressed.connect(func(): _select_game_mode("Skins"))
	mode_closest_btn.pressed.connect(func(): _select_game_mode("Closest to Pin"))

	_select_game_mode("Standard")
	return panel

func _select_game_mode(mode_name: String) -> void:
	selected_game_mode = mode_name
	_style_seg_button(mode_std_btn, "left", selected_game_mode == "Standard")
	_style_seg_button(mode_scramble_btn, "middle", selected_game_mode == "Scramble")
	_style_seg_button(mode_2v2_btn, "middle", selected_game_mode == "2v2 Scramble")
	_style_seg_button(mode_skins_btn, "middle", selected_game_mode == "Skins")
	_style_seg_button(mode_closest_btn, "right", selected_game_mode == "Closest to Pin")

	match selected_game_mode:
		"Standard":
			mode_desc_lbl.text = "Standard: Traditional stroke play. Everyone plays their own ball from tee to hole."
		"Scramble":
			mode_desc_lbl.text = "Scramble: Everyone hits the ball and then the closest to the hole is where everyone hits the next shot from."
		"2v2 Scramble":
			mode_desc_lbl.text = "2v2 Scramble: Group makes 2 teams (Team 1 vs Team 2). Scramble works off your teammate's shot."
		"Skins":
			mode_desc_lbl.text = "Skins: Each hole is worth 1 Skin for the lowest score. Ties carry over to the next hole!"
		"Closest to Pin":
			mode_desc_lbl.text = "Closest to Pin: Each player takes one shot per hole. Whoever is closest to the pin gets 1 point, and everyone else gets 0. Highest score at the end wins!"


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
	var course_data = course_list.get_item_metadata(idx)
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
