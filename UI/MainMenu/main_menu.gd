extends Control
# TODO - add settings menu system on future PR. 
@onready var _settings_button: Button = $VerticalLayout/TopStrip/HBoxContainer/SettingsButton
@onready var _exit_button: Button = $VerticalLayout/TopStrip/HBoxContainer/ExitButton
@onready var _courses_button: Button = $VerticalLayout/TilesRow/CoursesTile/CoursesTextBackdrop/CoursesButton
@onready var _range_button: Button = $VerticalLayout/TilesRow/RangeTile/RangeTextBackdrop/RangeButton
@onready var _practice_button: Button = $VerticalLayout/TilesRow/PracticeTile/PracticeTextBackdrop/PracticeButton
@onready var _history_button: Button = $VerticalLayout/TilesRow/HistoryTile/HistoryTextBackdrop/HistoryButton
@onready var _players_button: Button = $VerticalLayout/TilesRow/PlayersTile/PlayersTextBackdrop/PlayersButton
@onready var _minigames_button: Button = $VerticalLayout/TilesRow/MiniGamesTile/MiniGamesTextBackdrop/MiniGamesButton
@onready var _version_label: Label = $VerticalLayout/VersionContainer/VersionLabel
var _version_fall_back: String = "dev"
var _version_setting_path: String = "application/config/version"
var _version_text: String


# Called when the node enters the scene tree for the first time.
func _ready():
	_exit_button.pressed.connect(_on_exit_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_range_button.pressed.connect(_on_range_pressed)
	_courses_button.pressed.connect(_on_courses_pressed)
	_practice_button.pressed.connect(_on_practice_pressed)
	_history_button.pressed.connect(_on_history_pressed)
	_players_button.pressed.connect(_on_players_pressed)
	_minigames_button.pressed.connect(_on_minigames_pressed)
		
	_update_version_label()
	SceneManager.current_scene = self

	# Apply central theme styles to header buttons
	ThemeManager.apply_nav_button_style(_settings_button, 6)
	ThemeManager.apply_nav_button_style(_exit_button, 6)

	# Apply central theme card styling to tiles
	var tiles_row = get_node_or_null("VerticalLayout/TilesRow")
	if tiles_row != null:
		var viewport_width = get_viewport().get_visible_rect().size.x
		var target_width = clamp(viewport_width * 0.55, 640.0, viewport_width * 0.90)
		tiles_row.custom_minimum_size.x = target_width
		
		for tile in tiles_row.get_children():
			if tile is PanelContainer:
				tile.clip_contents = true
				ThemeManager.apply_card_panel_style(tile, false, 12, 0, 0, 0, 0)
				tile.mouse_entered.connect(func(): ThemeManager.apply_card_panel_style(tile, true, 12, 0, 0, 0, 0))
				tile.mouse_exited.connect(func(): ThemeManager.apply_card_panel_style(tile, false, 12, 0, 0, 0, 0))


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_range_pressed() -> void:
	SceneManager.change_scene("res://Courses/Range/range.tscn")


func _on_courses_pressed() -> void:
	SceneManager.change_scene("res://Courses/CoursePlay/course_play_setup.tscn")


func _on_practice_pressed() -> void:
	GlobalSettings.practice_mode_primed = true
	SceneManager.change_scene("res://Courses/CourseSelector/course_selector.tscn")


func _update_version_label():
	_version_text = _version_fall_back
	if (ProjectSettings.has_setting(_version_setting_path)):
		var _configured_version = str(ProjectSettings.get_setting(_version_setting_path)).strip_edges()
		_version_text = _configured_version;

	_version_label.text = "Version %s" % _version_text
	
func _on_settings_pressed() -> void:
	var settings_scene = load("res://UI/Settings/RangeSettings/range_settings.tscn")
	if settings_scene != null:
		var inst = settings_scene.instantiate()
		inst.name = "MainMenuSettings"
		add_child(inst)
		inst.close_settings_requested.connect(func(): inst.queue_free())


func _on_exit_pressed() -> void:
	get_tree().quit()


func _on_history_pressed() -> void:
	SceneManager.change_scene("res://UI/HistoryMenu/history_menu.tscn")


func _on_players_pressed() -> void:
	SceneManager.change_scene("res://UI/PlayersMenu/players_menu.tscn")


func _on_minigames_pressed() -> void:
	SceneManager.change_scene("res://UI/MiniGamesMenu/minigames_menu.tscn")
