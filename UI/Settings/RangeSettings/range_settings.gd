extends PanelContainer

signal toggle_settings_requested
signal close_settings_requested
signal manage_players_requested

var reset_spin_box : SpinBox = null
var temperature_spin_box : SpinBox = null
var altitude_spin_box : SpinBox = null
var surface_option : OptionButton = null
var ball_type_option : OptionButton = null
var tracer_count_spin_box : SpinBox = null
var square_enabled_button : CheckButton = null
var square_device_option : OptionButton = null
var square_scan_button : Button = null
var square_connect_button : Button = null
var square_disconnect_button : Button = null
var square_ready_button : Button = null
var square_status_label : Label = null
var square_battery_label : Label = null
var square_firmware_label : Label = null
var square_club_option : OptionButton = null
var square_handedness_option : OptionButton = null
var temperature_unit_label : Label = null
var altitude_unit_label : Label = null
var _stats_count_label : Label = null
var _stat_limit_modal : Control = null

const SQUARE_UI_LOG_PREFIX := "[SquareUI]"
const SQUARE_CLUBS := {
	"Driver": "0104",
	"Putter": "0107",
	"3 Wood": "0305",
	"5 Wood": "0505",
	"7 Wood": "0705",
	"4 Iron": "0406",
	"5 Iron": "0506",
	"6 Iron": "0606",
	"7 Iron": "0706",
	"8 Iron": "0806",
	"9 Iron": "0906",
	"PW": "0a06",
	"LW": "0b06",
	"SW": "0c06"
}


func _setup_spin_box(spin_box: SpinBox, setting: Setting, step: float) -> void:
	if spin_box == null:
		return
	spin_box.set_block_signals(true)
	spin_box.step = step
	if setting.min_value != null:
		spin_box.min_value = setting.min_value
	if setting.max_value != null:
		spin_box.max_value = setting.max_value
	spin_box.value = setting.value
	spin_box.set_block_signals(false)
	
	spin_box.custom_minimum_size = Vector2(110, 52)
	var line_edit = spin_box.get_line_edit()
	if line_edit != null:
		line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		line_edit.add_theme_font_size_override("font_size", 19)
		ThemeManager.apply_input_style(line_edit, 8)
	
	if spin_box.value != setting.value:
		setting.set_value(spin_box.value)


func _enhance_spinbox_with_stepper(spin_box: SpinBox, step: float) -> void:
	if spin_box == null:
		return
	var parent = spin_box.get_parent()
	if parent == null:
		return
		
	var minus_btn = Button.new()
	minus_btn.name = spin_box.name + "_MinusBtn"
	minus_btn.text = "－"
	minus_btn.custom_minimum_size = Vector2(52, 52)
	minus_btn.add_theme_font_size_override("font_size", 22)
	ThemeManager.apply_nav_button_style(minus_btn, 8)
	minus_btn.pressed.connect(func():
		spin_box.value = clamp(spin_box.value - step, spin_box.min_value, spin_box.max_value)
	)
	
	var plus_btn = Button.new()
	plus_btn.name = spin_box.name + "_PlusBtn"
	plus_btn.text = "＋"
	plus_btn.custom_minimum_size = Vector2(52, 52)
	plus_btn.add_theme_font_size_override("font_size", 22)
	ThemeManager.apply_nav_button_style(plus_btn, 8)
	plus_btn.pressed.connect(func():
		spin_box.value = clamp(spin_box.value + step, spin_box.min_value, spin_box.max_value)
	)
	
	var spin_index = spin_box.get_index()
	parent.add_child(minus_btn)
	parent.move_child(minus_btn, spin_index)
	
	parent.add_child(plus_btn)
	parent.move_child(plus_btn, spin_index + 2)


func _setup_touch_option_button(opt: OptionButton) -> void:
	if opt == null:
		return
	ThemeManager.apply_option_button_style(opt, 18, Vector2(220, 52))


func _create_tab_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 0
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	ThemeManager.apply_modal_style(self, 0)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Header Close Button Styling
	var header_close_btn = get_node_or_null("MarginContainer/VBoxContainer/HeaderHBox/HeaderCloseButton")
	if header_close_btn != null:
		header_close_btn.custom_minimum_size = Vector2(48, 48)
		header_close_btn.add_theme_font_size_override("font_size", 20)
		ThemeManager.apply_nav_button_style(header_close_btn, 8)

	# Style TabContainer
	var tab_container = get_node_or_null("MarginContainer/VBoxContainer/TabContainer")
	if tab_container != null:
		tab_container.add_theme_font_size_override("font_size", 20)
		tab_container.add_theme_constant_override("side_margin", 16)
		tab_container.add_theme_stylebox_override("tab_selected", _create_tab_style(ThemeManager.COLOR_PRIMARY_NORMAL, ThemeManager.COLOR_PRIMARY_NORMAL.lightened(0.2)))
		tab_container.add_theme_stylebox_override("tab_unselected", _create_tab_style(ThemeManager.COLOR_NAV_NORMAL, Color(1, 1, 1, 0.15)))
		tab_container.add_theme_stylebox_override("tab_hovered", _create_tab_style(ThemeManager.COLOR_NAV_HOVER, Color(1, 1, 1, 0.3)))
		
		# Set clear, attractive tab labels
		tab_container.set_tab_title(0, "⛳ Gameplay")
		tab_container.set_tab_title(1, "📊 Stats")
		tab_container.set_tab_title(2, "📷 Camera")
		tab_container.set_tab_title(3, "📡 Launch Monitor")
		tab_container.set_tab_title(4, "🎙 Announcer")

	# Apply touch-friendly scrollbar styling and kinetic swipe scrolling to all tabs
	for tab_name in ["Gameplay", "Stats", "Camera", "LaunchMonitor", "Announcer"]:
		var tab_scroll = get_node_or_null("MarginContainer/VBoxContainer/TabContainer/" + tab_name) as ScrollContainer
		if tab_scroll != null:
			ThemeManager.apply_scroll_container_style(tab_scroll, 28)

	reset_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/BallResetTimer/ResetSpinBox
	temperature_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Temperature/TemperatureSpinBox
	altitude_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Altitude/AltitudeSpinBox
	surface_option = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/SurfaceType/SurfaceOption
	ball_type_option = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/BallType/BallTypeOption
	tracer_count_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/TracerCount/TracerCountSpinBox
	temperature_unit_label = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Temperature/Label2
	altitude_unit_label = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Altitude/Label2

	# Reset Timer Settings
	_setup_spin_box(reset_spin_box, GlobalSettings.range_settings.ball_reset_timer, 0.5)
	_enhance_spinbox_with_stepper(reset_spin_box, 0.5)

	# Temperature Settings
	_setup_spin_box(temperature_spin_box, GlobalSettings.range_settings.temperature, 1.0)
	_enhance_spinbox_with_stepper(temperature_spin_box, 1.0)

	# Altitude Settings
	_setup_spin_box(altitude_spin_box, GlobalSettings.range_settings.altitude, 10.0)
	_enhance_spinbox_with_stepper(altitude_spin_box, 10.0)

	# Tracer count
	_setup_spin_box(tracer_count_spin_box, GlobalSettings.range_settings.shot_tracer_count, 1.0)
	_enhance_spinbox_with_stepper(tracer_count_spin_box, 1.0)

	# Surface type options
	surface_option.clear()
	surface_option.add_item("Fairway", PhysicsEnums.SurfaceType.FAIRWAY)
	surface_option.add_item("Soft Fairway", PhysicsEnums.SurfaceType.FAIRWAY_SOFT)
	surface_option.add_item("Rough", PhysicsEnums.SurfaceType.ROUGH)
	surface_option.add_item("Firm", PhysicsEnums.SurfaceType.FIRM)
	var surface_id: int = GlobalSettings.range_settings.surface_type.value
	var surface_index := surface_option.get_item_index(surface_id)
	if surface_index >= 0:
		surface_option.select(surface_index)
	_setup_touch_option_button(surface_option)

	# Ball type options
	if ball_type_option != null:
		ball_type_option.clear()
		ball_type_option.add_item("Standard Ball", 0)
		ball_type_option.add_item("Tour Soft", 1)
		ball_type_option.add_item("Distance / Firm", 2)
		var ball_id: int = GlobalSettings.range_settings.ball_type.value
		if ball_id < ball_type_option.item_count:
			ball_type_option.select(ball_id)
		_setup_touch_option_button(ball_type_option)

	GlobalSettings.range_settings.range_units.setting_changed.connect(update_units)

	# Initialize toggle button states
	$MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Units/CheckButton.set_pressed_no_signal(
		GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.METRIC
	)
	$MarginContainer/VBoxContainer/TabContainer/Camera/MarginContainer/CameraVBox/CameraFollow/CheckButton.set_pressed_no_signal(
		GlobalSettings.range_settings.camera_follow_mode.value
	)
	$MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/AutoBallReset/CheckButton.set_pressed_no_signal(
		GlobalSettings.range_settings.auto_ball_reset.value
	)
	$MarginContainer/VBoxContainer/TabContainer/LaunchMonitor/MarginContainer/LaunchMonitorVBox/ShotInjector/CheckButton.set_pressed_no_signal(
		GlobalSettings.range_settings.shot_injector_enabled.value
	)
	_setup_displayed_stats_section()
	_setup_square_monitor_section()
	_setup_hecklelinks_announcer_section()

	# Create and insert Gimme Range configuration settings rows in the Gameplay tab
	var gameplay_vbox = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox
	
	var gimme_sep = HSeparator.new()
	gameplay_vbox.add_child(gimme_sep)
	
	var gimme_label = Label.new()
	gimme_label.text = "Gimme Ranges"
	gimme_label.add_theme_font_size_override("font_size", 22)
	gimme_label.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	gameplay_vbox.add_child(gimme_label)
	
	var gimme_1_toggle = _create_toggle_setting_row("Gimme +1 Stroke Circle", "gimme_range_1_enabled")
	gameplay_vbox.add_child(gimme_1_toggle)
	
	var gimme_1_dist = _create_spinbox_setting_row("Gimme +1 Distance", "gimme_range_1_distance", 0.5, 20.0, 0.5, "yd")
	gameplay_vbox.add_child(gimme_1_dist)
	
	var gimme_2_toggle = _create_toggle_setting_row("Gimme +2 Strokes Circle", "gimme_range_2_enabled")
	gameplay_vbox.add_child(gimme_2_toggle)
	
	var gimme_2_dist = _create_spinbox_setting_row("Gimme +2 Distance", "gimme_range_2_distance", 0.5, 30.0, 0.5, "yd")
	gameplay_vbox.add_child(gimme_2_dist)

	var turn_sep = HSeparator.new()
	gameplay_vbox.add_child(turn_sep)
	
	var turn_label = Label.new()
	turn_label.text = "Audio & Turn Settings"
	turn_label.add_theme_font_size_override("font_size", 22)
	turn_label.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	gameplay_vbox.add_child(turn_label)
	
	var turn_order_row = _create_option_setting_row("Turn Order Mode", "turn_order_mode", ["Stay Up", "Classic", "Full Hole"])
	gameplay_vbox.add_child(turn_order_row)
	
	var custom_next_player_toggle = _create_toggle_setting_row("Repeat Shot if <= 20 Yards", "custom_next_player")
	gameplay_vbox.add_child(custom_next_player_toggle)

	var golf_clap_toggle = _create_toggle_setting_row("Golf Clap Audio", "golf_clap_enabled")
	gameplay_vbox.add_child(golf_clap_toggle)

	var ambient_sound_toggle = _create_toggle_setting_row("Ambient Nature Sounds", "ambient_sound_enabled")
	gameplay_vbox.add_child(ambient_sound_toggle)

	var menu_music_toggle = _create_toggle_setting_row("Menu Soundtrack", "menu_music_enabled")
	gameplay_vbox.add_child(menu_music_toggle)

	var minigame_music_toggle = _create_toggle_setting_row("Minigame Music Soundtrack", "minigame_music_enabled")
	gameplay_vbox.add_child(minigame_music_toggle)

	var suspense_toggle = _create_toggle_setting_row("Course Play Suspense (Heartbeat & Tunnel Vision)", "tension_effects_enabled")
	gameplay_vbox.add_child(suspense_toggle)

	var shot_analysis_toggle = _create_toggle_setting_row("Shot Analysis Suggestions", "shot_analysis_enabled")
	gameplay_vbox.add_child(shot_analysis_toggle)

	var gs_sep = HSeparator.new()
	gameplay_vbox.add_child(gs_sep)
	
	var green_speed_row = _create_slider_setting_row("Green Speed (Courses)", "green_speed", 1.0, 50.0, 1.0)
	gameplay_vbox.add_child(green_speed_row)

	var putting_green_speed_row = _create_slider_setting_row("Putting Minigame Green Speed", "putting_green_speed", 1.0, 50.0, 1.0)
	gameplay_vbox.add_child(putting_green_speed_row)


	# Create and insert camera configuration settings rows in the Camera tab
	var camera_vbox = $MarginContainer/VBoxContainer/TabContainer/Camera/MarginContainer/CameraVBox
	
	var height_row = _create_spinbox_setting_row("Camera Height", "camera_height", 0.5, 10.0, 0.1, "m")
	camera_vbox.add_child(height_row)
	
	var dist_row = _create_spinbox_setting_row("Camera Distance", "camera_distance", 1.0, 30.0, 0.1, "m")
	camera_vbox.add_child(dist_row)
	
	var fov_row = _create_spinbox_setting_row("Camera FOV", "camera_fov", 1.0, 90.0, 0.1, "deg")
	camera_vbox.add_child(fov_row)

	var far_row = _create_spinbox_setting_row("Camera Far", "camera_far", 100.0, 1000.0, 1.0, "m")
	camera_vbox.add_child(far_row)
	
	# Visual effects separator
	var fx_sep = HSeparator.new()
	camera_vbox.add_child(fx_sep)

	var fx_label = Label.new()
	fx_label.text = "Visual Effects"
	fx_label.add_theme_font_size_override("font_size", 22)
	fx_label.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	camera_vbox.add_child(fx_label)
	
	# DOF toggle
	var dof_row = _create_toggle_setting_row("Depth of Field", "dof_enabled")
	camera_vbox.add_child(dof_row)
	
	# DOF blur amount
	var blur_row = _create_spinbox_setting_row("DOF Blur", "dof_blur_amount", 0.0, 0.3, 0.01, "")
	camera_vbox.add_child(blur_row)
	
	# Vignette toggle
	var vig_row = _create_toggle_setting_row("Vignette", "vignette_enabled")
	camera_vbox.add_child(vig_row)
	
	# Vignette intensity
	var vig_int_row = _create_spinbox_setting_row("Vignette Intensity", "vignette_intensity", 0.0, 3.0, 0.1, "")
	camera_vbox.add_child(vig_int_row)

	# Add Close button dynamically to ButtonsHBox and style all buttons
	var buttons_hbox = get_node_or_null("MarginContainer/VBoxContainer/ButtonsHBox")
	if buttons_hbox != null:
		var reset_btn = buttons_hbox.get_node_or_null("ResetLayoutButton")
		if reset_btn != null:
			reset_btn.custom_minimum_size = Vector2(170, 54)
			reset_btn.add_theme_font_size_override("font_size", 18)
			ThemeManager.apply_secondary_button_style(reset_btn, 8)

		var exit_btn = buttons_hbox.get_node_or_null("ExitButton")
		if exit_btn != null:
			exit_btn.custom_minimum_size = Vector2(170, 54)
			exit_btn.add_theme_font_size_override("font_size", 18)
			ThemeManager.apply_danger_button_style(exit_btn, 8)

		if not MultiplayerManager.players.is_empty() and not MultiplayerManager.practice_mode_active:
			var players_btn = Button.new()
			players_btn.name = "PlayersButton"
			players_btn.text = "👥 Players"
			players_btn.custom_minimum_size = Vector2(170, 54)
			players_btn.add_theme_font_size_override("font_size", 18)
			ThemeManager.apply_primary_button_style(players_btn, 8)
			players_btn.pressed.connect(func():
				manage_players_requested.emit()
				close_settings_requested.emit()
			)
			buttons_hbox.add_child(players_btn)

		var close_btn = Button.new()
		close_btn.name = "CloseButton"
		close_btn.text = "Close"
		close_btn.custom_minimum_size = Vector2(170, 54)
		close_btn.add_theme_font_size_override("font_size", 18)
		ThemeManager.apply_primary_button_style(close_btn, 8)
		close_btn.pressed.connect(func(): close_settings_requested.emit())
		buttons_hbox.add_child(close_btn)


func _on_header_close_button_pressed() -> void:
	close_settings_requested.emit()


func _on_settings_button_pressed() -> void:
	toggle_settings_requested.emit()


func _on_background_clicked(event: InputEvent) -> void:
	# Close the menu when clicking on the background
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_settings_requested.emit()


func _on_exit_button_pressed() -> void:
	SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")


func _on_reset_layout_button_pressed() -> void:
	GlobalSettings.range_settings.displayed_stats.set_value(StatDefinitions.DEFAULT_ENABLED_STAT_IDS.duplicate())
	GlobalSettings.save_settings()
	_setup_displayed_stats_section()
	var grid_canvas = get_node_or_null("../../../GridCanvas")
	if grid_canvas != null and grid_canvas.has_method("reset_layout"):
		grid_canvas.reset_layout()
	else:
		var dir = DirAccess.open("user://")
		if dir and dir.file_exists("layout.cfg"):
			dir.remove("layout.cfg")


func _on_units_check_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		GlobalSettings.range_settings.range_units.set_value(PhysicsEnums.Units.METRIC)
	else:
		GlobalSettings.range_settings.range_units.set_value(PhysicsEnums.Units.IMPERIAL)


func _on_camer_check_button_toggled(toggled_on: bool) -> void:
	GlobalSettings.range_settings.camera_follow_mode.set_value(toggled_on)


func _on_auto_reset_check_button_toggled(toggled_on: bool) -> void:
	GlobalSettings.range_settings.auto_ball_reset.set_value(toggled_on)


func _on_injector_check_button_toggled(toggled_on: bool) -> void:
	GlobalSettings.range_settings.shot_injector_enabled.set_value(toggled_on)


func _on_reset_spin_box_value_changed(value: float) -> void:
	GlobalSettings.range_settings.ball_reset_timer.set_value(value)


func _on_temperature_spin_box_value_changed(value: float) -> void:
	GlobalSettings.range_settings.temperature.set_value(value)


func _on_altitude_spin_box_value_changed(value: float) -> void:
	GlobalSettings.range_settings.altitude.set_value(value)


func _on_drag_spin_box_value_changed(_value: float) -> void:
	pass


func _on_surface_option_item_selected(index: int) -> void:
	var id: int = surface_option.get_item_id(index)
	GlobalSettings.range_settings.surface_type.set_value(id)


func _on_tracer_count_spin_box_value_changed(value: float) -> void:
	GlobalSettings.range_settings.shot_tracer_count.set_value(int(value))


func _on_ball_type_option_item_selected(index: int) -> void:
	GlobalSettings.range_settings.ball_type.set_value(index)


func _setup_square_monitor_section() -> void:
	if not has_node("/root/LaunchMonitorManager"):
		_square_debug("LaunchMonitorManager singleton not found; Square section not created.")
		return

	var launch_monitor = get_node("/root/LaunchMonitorManager")
	_square_debug("Creating Square settings section. Initial status=%s" % str(launch_monitor.status))
	var root := $MarginContainer/VBoxContainer/TabContainer/LaunchMonitor/MarginContainer/LaunchMonitorVBox
	var section := VBoxContainer.new()
	section.name = "SquareMonitor"
	section.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "Square Launch Monitor"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	section.add_child(title)

	var enabled_row := HBoxContainer.new()
	enabled_row.custom_minimum_size = Vector2(0, 52)
	enabled_row.add_child(_make_label("Enabled"))
	enabled_row.add_child(_make_spacer())
	square_enabled_button = CheckButton.new()
	square_enabled_button.custom_minimum_size = Vector2(72, 48)
	square_enabled_button.set_pressed_no_signal(bool(launch_monitor.settings.get("enabled", false)))
	square_enabled_button.toggled.connect(_on_square_enabled_toggled)
	enabled_row.add_child(square_enabled_button)
	section.add_child(enabled_row)

	var device_row := HBoxContainer.new()
	device_row.custom_minimum_size = Vector2(0, 52)
	device_row.add_child(_make_label("Device"))
	square_device_option = OptionButton.new()
	square_device_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_setup_touch_option_button(square_device_option)
	device_row.add_child(square_device_option)
	section.add_child(device_row)

	var action_row := HBoxContainer.new()
	action_row.custom_minimum_size = Vector2(0, 52)
	action_row.add_theme_constant_override("separation", 12)
	
	square_scan_button = Button.new()
	square_scan_button.text = "Scan"
	square_scan_button.custom_minimum_size = Vector2(120, 52)
	square_scan_button.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_secondary_button_style(square_scan_button, 8)
	square_scan_button.pressed.connect(_on_square_scan_pressed)
	action_row.add_child(square_scan_button)
	
	square_connect_button = Button.new()
	square_connect_button.text = "Connect"
	square_connect_button.custom_minimum_size = Vector2(120, 52)
	square_connect_button.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_primary_button_style(square_connect_button, 8)
	square_connect_button.pressed.connect(_on_square_connect_pressed)
	action_row.add_child(square_connect_button)
	
	square_disconnect_button = Button.new()
	square_disconnect_button.text = "Disconnect"
	square_disconnect_button.custom_minimum_size = Vector2(120, 52)
	square_disconnect_button.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_danger_button_style(square_disconnect_button, 8)
	square_disconnect_button.pressed.connect(_on_square_disconnect_pressed)
	action_row.add_child(square_disconnect_button)
	
	square_ready_button = Button.new()
	square_ready_button.text = "Ready"
	square_ready_button.custom_minimum_size = Vector2(120, 52)
	square_ready_button.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_primary_button_style(square_ready_button, 8)
	square_ready_button.pressed.connect(_on_square_ready_pressed)
	action_row.add_child(square_ready_button)
	
	section.add_child(action_row)

	var club_row := HBoxContainer.new()
	club_row.custom_minimum_size = Vector2(0, 52)
	club_row.add_child(_make_label("Club"))
	square_club_option = OptionButton.new()
	square_club_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for club_name in SQUARE_CLUBS.keys():
		var index := square_club_option.item_count
		square_club_option.add_item(club_name)
		square_club_option.set_item_metadata(index, SQUARE_CLUBS[club_name])
	var current_club := str(launch_monitor.settings.get("club_code", "0104"))
	_select_option_by_metadata(square_club_option, current_club)
	square_club_option.item_selected.connect(_on_square_club_selected)
	_setup_touch_option_button(square_club_option)
	club_row.add_child(square_club_option)
	section.add_child(club_row)

	var handedness_row := HBoxContainer.new()
	handedness_row.custom_minimum_size = Vector2(0, 52)
	handedness_row.add_child(_make_label("Handedness"))
	square_handedness_option = OptionButton.new()
	square_handedness_option.add_item("Right", 0)
	square_handedness_option.add_item("Left", 1)
	var handedness := int(launch_monitor.settings.get("handedness", 0))
	var hand_index := square_handedness_option.get_item_index(handedness)
	if hand_index >= 0:
		square_handedness_option.select(hand_index)
	square_handedness_option.item_selected.connect(_on_square_handedness_selected)
	_setup_touch_option_button(square_handedness_option)
	handedness_row.add_child(square_handedness_option)
	section.add_child(handedness_row)

	var sound_row := HBoxContainer.new()
	sound_row.custom_minimum_size = Vector2(0, 52)
	sound_row.add_child(_make_label("Ready Sound"))
	sound_row.add_child(_make_spacer())
	var sound_button := CheckButton.new()
	sound_button.custom_minimum_size = Vector2(72, 48)
	sound_button.set_pressed_no_signal(bool(launch_monitor.settings.get("ready_ding_enabled", true)))
	sound_button.toggled.connect(func(toggled_on: bool):
		launch_monitor.set_ready_ding_enabled(toggled_on)
	)
	sound_row.add_child(sound_button)
	section.add_child(sound_row)

	var hud_row := HBoxContainer.new()
	hud_row.custom_minimum_size = Vector2(0, 52)
	var hud_label := _make_label("Ready Indicator")
	hud_label.custom_minimum_size = Vector2(160, 0)
	hud_row.add_child(hud_label)
	hud_row.add_child(_make_spacer())
	var hud_button := CheckButton.new()
	hud_button.custom_minimum_size = Vector2(72, 48)
	hud_button.set_pressed_no_signal(bool(launch_monitor.settings.get("ready_indicator_enabled", true)))
	hud_button.toggled.connect(func(toggled_on: bool):
		launch_monitor.set_ready_indicator_enabled(toggled_on)
	)
	hud_row.add_child(hud_button)
	section.add_child(hud_row)

	var guide_row := HBoxContainer.new()
	guide_row.custom_minimum_size = Vector2(0, 52)
	var guide_label := _make_label("Placement Guide")
	guide_label.custom_minimum_size = Vector2(160, 0)
	guide_row.add_child(guide_label)
	guide_row.add_child(_make_spacer())
	var guide_button := CheckButton.new()
	guide_button.custom_minimum_size = Vector2(72, 48)
	guide_button.set_pressed_no_signal(bool(launch_monitor.settings.get("ball_placement_guide_enabled", true)))
	guide_button.toggled.connect(func(toggled_on: bool):
		if launch_monitor.has_method("set_ball_placement_guide_enabled"):
			launch_monitor.set_ball_placement_guide_enabled(toggled_on)
	)
	guide_row.add_child(guide_button)
	section.add_child(guide_row)

	square_status_label = Label.new()
	square_status_label.add_theme_font_size_override("font_size", 18)
	square_status_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	
	square_battery_label = Label.new()
	square_battery_label.add_theme_font_size_override("font_size", 18)
	square_battery_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	
	square_firmware_label = Label.new()
	square_firmware_label.add_theme_font_size_override("font_size", 18)
	square_firmware_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	
	section.add_child(square_status_label)
	section.add_child(square_battery_label)
	section.add_child(square_firmware_label)

	root.add_child(section)

	if not launch_monitor.device_discovered.is_connected(_on_square_device_discovered):
		launch_monitor.device_discovered.connect(_on_square_device_discovered)
	if not launch_monitor.status_changed.is_connected(_on_square_status_changed):
		launch_monitor.status_changed.connect(_on_square_status_changed)
	if not launch_monitor.error_occurred.is_connected(_on_square_error_occurred):
		launch_monitor.error_occurred.connect(_on_square_error_occurred)
	if not launch_monitor.battery_changed.is_connected(_on_square_battery_changed):
		launch_monitor.battery_changed.connect(_on_square_battery_changed)
	if not launch_monitor.firmware_changed.is_connected(_on_square_firmware_changed):
		launch_monitor.firmware_changed.connect(_on_square_firmware_changed)
	if not launch_monitor.ready_changed.is_connected(_on_square_ready_changed):
		launch_monitor.ready_changed.connect(_on_square_ready_changed)
	if not launch_monitor.club_code_changed.is_connected(_on_square_club_code_changed):
		launch_monitor.club_code_changed.connect(_on_square_club_code_changed)

	_refresh_square_devices()
	_update_square_status_labels()


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	label.custom_minimum_size = Vector2(140, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _make_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


func _select_option_by_metadata(option: OptionButton, metadata: String) -> void:
	for index in range(option.item_count):
		if str(option.get_item_metadata(index)) == metadata:
			option.select(index)
			return


func _refresh_square_devices() -> void:
	if square_device_option == null or not has_node("/root/LaunchMonitorManager"):
		return
	var launch_monitor = get_node("/root/LaunchMonitorManager")
	var selected_device := str(launch_monitor.settings.get("device_id", ""))
	var saved_name := str(launch_monitor.settings.get("device_name", ""))
	if saved_name == "":
		saved_name = "Square Golf"
	if selected_device != "" and not launch_monitor.devices.has(selected_device):
		launch_monitor.devices[selected_device] = {
			"name": saved_name,
			"rssi": 0
		}
	square_device_option.clear()
	for device_id in launch_monitor.devices.keys():
		var device = launch_monitor.devices[device_id]
		var label := str(device.get("name", "Square Golf"))
		var index := square_device_option.item_count
		square_device_option.add_item(label)
		square_device_option.set_item_metadata(index, device_id)
		if device_id == selected_device:
			square_device_option.select(index)


func _exit_tree() -> void:
	if has_node("/root/LaunchMonitorManager"):
		var launch_monitor = get_node("/root/LaunchMonitorManager")
		if launch_monitor.device_discovered.is_connected(_on_square_device_discovered):
			launch_monitor.device_discovered.disconnect(_on_square_device_discovered)
		if launch_monitor.status_changed.is_connected(_on_square_status_changed):
			launch_monitor.status_changed.disconnect(_on_square_status_changed)
		if launch_monitor.error_occurred.is_connected(_on_square_error_occurred):
			launch_monitor.error_occurred.disconnect(_on_square_error_occurred)
		if launch_monitor.battery_changed.is_connected(_on_square_battery_changed):
			launch_monitor.battery_changed.disconnect(_on_square_battery_changed)
		if launch_monitor.firmware_changed.is_connected(_on_square_firmware_changed):
			launch_monitor.firmware_changed.disconnect(_on_square_firmware_changed)
		if launch_monitor.ready_changed.is_connected(_on_square_ready_changed):
			launch_monitor.ready_changed.disconnect(_on_square_ready_changed)


func _update_square_status_labels() -> void:
	if not has_node("/root/LaunchMonitorManager") or square_status_label == null:
		return
	var launch_monitor = get_node("/root/LaunchMonitorManager")
	square_status_label.text = "Status: %s" % launch_monitor.status
	if int(launch_monitor.battery_level) >= 0:
		square_battery_label.text = "Battery: %d%%" % int(launch_monitor.battery_level)
	else:
		square_battery_label.text = "Battery: --"
	if str(launch_monitor.firmware) != "":
		square_firmware_label.text = "Firmware: %s" % str(launch_monitor.firmware)
	else:
		square_firmware_label.text = "Firmware: --"


func _on_square_enabled_toggled(toggled_on: bool) -> void:
	_square_debug("Enabled toggled: %s" % str(toggled_on))
	var launch_monitor = get_node("/root/LaunchMonitorManager")
	launch_monitor.set_enabled(toggled_on)
	if not toggled_on:
		launch_monitor.disconnect_device()


func _on_square_scan_pressed() -> void:
	_square_debug("Scan pressed")
	get_node("/root/LaunchMonitorManager").start_scan()


func _on_square_connect_pressed() -> void:
	if square_device_option == null or square_device_option.item_count == 0:
		_square_debug("Connect pressed with no selectable device.")
		return
	var index := square_device_option.selected
	var device_id := str(square_device_option.get_item_metadata(index))
	_square_debug("Connect pressed for device_id=%s" % device_id)
	var launch_monitor = get_node("/root/LaunchMonitorManager")
	launch_monitor.set_enabled(true)
	square_enabled_button.set_pressed_no_signal(true)
	launch_monitor.connect_to_device(device_id)


func _on_square_disconnect_pressed() -> void:
	_square_debug("Disconnect pressed")
	if square_enabled_button != null:
		square_enabled_button.set_pressed_no_signal(false)
	var launch_monitor = get_node("/root/LaunchMonitorManager")
	launch_monitor.set_enabled(false)
	launch_monitor.disconnect_device()


func _on_square_ready_pressed() -> void:
	_square_debug("Ready pressed")
	get_node("/root/LaunchMonitorManager").set_ready()


func _on_square_club_selected(index: int) -> void:
	var club_code := str(square_club_option.get_item_metadata(index))
	get_node("/root/LaunchMonitorManager").set_club_code(club_code)


func _on_square_club_code_changed(club_code: String) -> void:
	if square_club_option != null:
		_select_option_by_metadata(square_club_option, club_code)


func _on_square_handedness_selected(index: int) -> void:
	var handedness := square_handedness_option.get_item_id(index)
	get_node("/root/LaunchMonitorManager").set_handedness(handedness)


func _on_square_device_discovered(_device_id: String, _name: String, _rssi: int) -> void:
	_square_debug("Device discovered event received")
	_refresh_square_devices()


func _on_square_status_changed(status: String) -> void:
	_square_debug("Status changed: %s" % status)
	_update_square_status_labels()


func _on_square_error_occurred(message: String) -> void:
	_square_debug("Error occurred: %s" % message)
	if square_status_label != null:
		square_status_label.text = "Status: %s" % message


func _on_square_battery_changed(_level: int) -> void:
	_update_square_status_labels()


func _on_square_firmware_changed(_firmware: String) -> void:
	_update_square_status_labels()


func _on_square_ready_changed(_is_ready: bool) -> void:
	_update_square_status_labels()


func _square_debug(message: String) -> void:
	print("%s %s" % [SQUARE_UI_LOG_PREFIX, message])


func update_units(value) -> void:
	const m2ft = 3.28084

	# Block spin box signals to prevent _on_*_value_changed from firing
	# during conversion, which would double-write the setting.
	temperature_spin_box.set_block_signals(true)
	altitude_spin_box.set_block_signals(true)

	if value == PhysicsEnums.Units.IMPERIAL:
		if temperature_unit_label != null:
			temperature_unit_label.text = "F"
		var temp_f = GlobalSettings.range_settings.temperature.value * 9.0 / 5.0 + 32.0
		temperature_spin_box.value = temp_f
		GlobalSettings.range_settings.temperature.set_value(temp_f)

		if altitude_unit_label != null:
			altitude_unit_label.text = "ft"
		var alt_ft = GlobalSettings.range_settings.altitude.value * m2ft
		altitude_spin_box.value = alt_ft
		GlobalSettings.range_settings.altitude.set_value(alt_ft)
	else:
		if temperature_unit_label != null:
			temperature_unit_label.text = "C"
		var temp_c = (GlobalSettings.range_settings.temperature.value - 32.0) * 5.0 / 9.0
		temperature_spin_box.value = temp_c
		GlobalSettings.range_settings.temperature.set_value(temp_c)

		if altitude_unit_label != null:
			altitude_unit_label.text = "m"
		var alt_m = GlobalSettings.range_settings.altitude.value / m2ft
		altitude_spin_box.value = alt_m
		GlobalSettings.range_settings.altitude.set_value(alt_m)

	temperature_spin_box.set_block_signals(false)
	altitude_spin_box.set_block_signals(false)


func _create_announcer_toggle_row(label_text: String, prop_name: String, announcer: Node) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 52)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.custom_minimum_size = Vector2(200, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	
	var btn := CheckButton.new()
	btn.custom_minimum_size = Vector2(72, 48)
	btn.set_pressed_no_signal(bool(announcer.get(prop_name)))
	btn.toggled.connect(func(toggled_on: bool):
		announcer.set(prop_name, toggled_on)
		GlobalSettings.save_settings()
	)
	row.add_child(btn)
	return row


func _setup_hecklelinks_announcer_section() -> void:
	if not has_node("/root/AnnouncerEngine"):
		return

	var announcer = get_node("/root/AnnouncerEngine")
	var root := $MarginContainer/VBoxContainer/TabContainer/Announcer/MarginContainer/AnnouncerVBox
	
	for child in root.get_children():
		child.queue_free()

	var section := VBoxContainer.new()
	section.name = "AnnouncerSettings"
	section.add_theme_constant_override("separation", 16)

	var title := Label.new()
	title.text = "HeckleLinks Announcer Settings"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.8, 0.95, 0.8))
	section.add_child(title)

	# --- 1. COURSE PLAY ---
	var course_lbl := Label.new()
	course_lbl.text = "Course Play"
	course_lbl.add_theme_font_size_override("font_size", 18)
	course_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	section.add_child(course_lbl)

	section.add_child(_create_announcer_toggle_row("Announcer Voice", "AnnouncerCoursePlay", announcer))
	section.add_child(_create_announcer_toggle_row("Heckling", "HeckleCoursePlay", announcer))

	var sep1 := HSeparator.new()
	section.add_child(sep1)

	# --- 2. DRIVING RANGE ---
	var range_lbl := Label.new()
	range_lbl.text = "Driving Range"
	range_lbl.add_theme_font_size_override("font_size", 18)
	range_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	section.add_child(range_lbl)

	section.add_child(_create_announcer_toggle_row("Announcer Voice", "AnnouncerRange", announcer))
	section.add_child(_create_announcer_toggle_row("Heckling", "HeckleRange", announcer))

	var sep2 := HSeparator.new()
	section.add_child(sep2)

	# --- 3. MINI GAMES ---
	var mg_lbl := Label.new()
	mg_lbl.text = "Mini Games (Putting & Chipping)"
	mg_lbl.add_theme_font_size_override("font_size", 18)
	mg_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	section.add_child(mg_lbl)

	section.add_child(_create_announcer_toggle_row("Announcer Voice", "AnnouncerMiniGames", announcer))
	section.add_child(_create_announcer_toggle_row("Heckling", "HeckleMiniGames", announcer))

	var sep3 := HSeparator.new()
	section.add_child(sep3)

	# --- 4. VOICE OPTIONS ---
	var voice_header := Label.new()
	voice_header.text = "Voice & Commentary Options"
	voice_header.add_theme_font_size_override("font_size", 18)
	voice_header.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	section.add_child(voice_header)

	section.add_child(_create_announcer_toggle_row("Praise Commentary", "PraiseEnabled", announcer))

	var voice_row := HBoxContainer.new()
	voice_row.custom_minimum_size = Vector2(0, 52)
	var voice_lbl := Label.new()
	voice_lbl.text = "Voice Locale"
	voice_lbl.add_theme_font_size_override("font_size", 19)
	voice_lbl.custom_minimum_size = Vector2(200, 0)
	voice_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	voice_row.add_child(voice_lbl)
	
	var voice_opt := OptionButton.new()
	voice_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var voices = []
	if announcer.has_method("GetTtsVoices"):
		var voices_arr = announcer.call("GetTtsVoices")
		for i in range(voices_arr.size()):
			var v = voices_arr[i]
			var lang: String = v.get("language", "").to_lower()
			if lang.begins_with("en") or lang.contains("en"):
				voices.append(v)
		if voices.is_empty() and not voices_arr.is_empty():
			for i in range(voices_arr.size()):
				voices.append(voices_arr[i])
				
	if voices.is_empty():
		voices = [
			{"id": "en-US-default", "name": "US English (Default)", "language": "en_US"},
			{"id": "en-GB-default", "name": "British English", "language": "en_GB"},
			{"id": "en-US-southern", "name": "US Southern", "language": "en_US"}
		]
		
	var active_v = announcer.get("ActiveVoice")
	var active_index := 0
	for i in range(voices.size()):
		var v = voices[i]
		var v_id = v.get("id", "")
		var lang = v.get("language", "")
		var v_name = v.get("name", "")
		var label = _get_friendly_accent_name(lang) + " (" + v_name + ")"
		voice_opt.add_item(label)
		voice_opt.set_item_metadata(i, v_id)
		if v_id == active_v:
			active_index = i
			
	if voice_opt.item_count > 0:
		voice_opt.select(active_index)
		
	voice_opt.item_selected.connect(func(idx):
		var chosen_id = voice_opt.get_item_metadata(idx)
		announcer.set("ActiveVoice", chosen_id)
		GlobalSettings.save_settings()
	)
	_setup_touch_option_button(voice_opt)
	voice_row.add_child(voice_opt)
	section.add_child(voice_row)

	# Voice Pitch Slider Row with Touch Stepper
	var pitch_row := HBoxContainer.new()
	pitch_row.custom_minimum_size = Vector2(0, 52)
	pitch_row.add_theme_constant_override("separation", 10)
	
	var pitch_label := Label.new()
	pitch_label.text = "Voice Pitch: %.1f" % announcer.get("Pitch")
	pitch_label.add_theme_font_size_override("font_size", 19)
	pitch_label.custom_minimum_size = Vector2(200, 0)
	pitch_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pitch_row.add_child(pitch_label)
	
	var pitch_minus_btn := Button.new()
	pitch_minus_btn.text = "－"
	pitch_minus_btn.custom_minimum_size = Vector2(48, 48)
	pitch_minus_btn.add_theme_font_size_override("font_size", 20)
	ThemeManager.apply_nav_button_style(pitch_minus_btn, 8)
	pitch_row.add_child(pitch_minus_btn)
	
	var pitch_slider := HSlider.new()
	pitch_slider.min_value = 0.5
	pitch_slider.max_value = 2.0
	pitch_slider.step = 0.1
	pitch_slider.value = announcer.get("Pitch")
	pitch_slider.custom_minimum_size = Vector2(180, 48)
	pitch_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pitch_slider.value_changed.connect(func(val):
		announcer.set("Pitch", val)
		pitch_label.text = "Voice Pitch: %.1f" % val
		GlobalSettings.save_settings()
	)
	pitch_row.add_child(pitch_slider)
	
	var pitch_plus_btn := Button.new()
	pitch_plus_btn.text = "＋"
	pitch_plus_btn.custom_minimum_size = Vector2(48, 48)
	pitch_plus_btn.add_theme_font_size_override("font_size", 20)
	ThemeManager.apply_nav_button_style(pitch_plus_btn, 8)
	pitch_row.add_child(pitch_plus_btn)
	
	pitch_minus_btn.pressed.connect(func():
		pitch_slider.value = clamp(pitch_slider.value - 0.1, pitch_slider.min_value, pitch_slider.max_value)
	)
	pitch_plus_btn.pressed.connect(func():
		pitch_slider.value = clamp(pitch_slider.value + 0.1, pitch_slider.min_value, pitch_slider.max_value)
	)
	section.add_child(pitch_row)

	# Voice Speed/Rate Slider Row with Touch Stepper
	var rate_row := HBoxContainer.new()
	rate_row.custom_minimum_size = Vector2(0, 52)
	rate_row.add_theme_constant_override("separation", 10)
	
	var rate_label := Label.new()
	rate_label.text = "Voice Speed: %.1f" % announcer.get("Rate")
	rate_label.add_theme_font_size_override("font_size", 19)
	rate_label.custom_minimum_size = Vector2(200, 0)
	rate_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rate_row.add_child(rate_label)
	
	var rate_minus_btn := Button.new()
	rate_minus_btn.text = "－"
	rate_minus_btn.custom_minimum_size = Vector2(48, 48)
	rate_minus_btn.add_theme_font_size_override("font_size", 20)
	ThemeManager.apply_nav_button_style(rate_minus_btn, 8)
	rate_row.add_child(rate_minus_btn)
	
	var rate_slider := HSlider.new()
	rate_slider.min_value = 0.5
	rate_slider.max_value = 2.0
	rate_slider.step = 0.1
	rate_slider.value = announcer.get("Rate")
	rate_slider.custom_minimum_size = Vector2(180, 48)
	rate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_slider.value_changed.connect(func(val):
		announcer.set("Rate", val)
		rate_label.text = "Voice Speed: %.1f" % val
		GlobalSettings.save_settings()
	)
	rate_row.add_child(rate_slider)
	
	var rate_plus_btn := Button.new()
	rate_plus_btn.text = "＋"
	rate_plus_btn.custom_minimum_size = Vector2(48, 48)
	rate_plus_btn.add_theme_font_size_override("font_size", 20)
	ThemeManager.apply_nav_button_style(rate_plus_btn, 8)
	rate_row.add_child(rate_plus_btn)
	
	rate_minus_btn.pressed.connect(func():
		rate_slider.value = clamp(rate_slider.value - 0.1, rate_slider.min_value, rate_slider.max_value)
	)
	rate_plus_btn.pressed.connect(func():
		rate_slider.value = clamp(rate_slider.value + 0.1, rate_slider.min_value, rate_slider.max_value)
	)
	section.add_child(rate_row)

	root.add_child(section)


func _get_friendly_accent_name(lang: String) -> String:
	var clean_lang = lang.to_lower().replace("-", "_")
	if clean_lang.begins_with("en_us"):
		return "US Accent"
	elif clean_lang.begins_with("en_gb"):
		return "British Accent"
	elif clean_lang.begins_with("en_au"):
		return "Australian Accent"
	elif clean_lang.begins_with("en_in"):
		return "Indian Accent"
	elif clean_lang.begins_with("en_ca"):
		return "Canadian Accent"
	elif clean_lang.begins_with("en_ie"):
		return "Irish Accent"
	elif clean_lang.begins_with("en_za"):
		return "South African Accent"
	elif clean_lang.begins_with("en_nz"):
		return "New Zealand Accent"
	elif clean_lang.begins_with("en"):
		return "English Accent"
	else:
		return lang.to_upper() + " Accent"


func _create_spinbox_setting_row(label_text: String, setting_name: String, min_val: float, max_val: float, step: float, suffix: String = "") -> HBoxContainer:
	var row = HBoxContainer.new()
	row.name = label_text.replace(" ", "")
	row.custom_minimum_size = Vector2(0, 52)
	row.add_theme_constant_override("separation", 8)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 19)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer1)
	
	var setting = GlobalSettings.range_settings.settings[setting_name]
	
	# Minus Button
	var minus_btn = Button.new()
	minus_btn.text = "－"
	minus_btn.custom_minimum_size = Vector2(52, 52)
	minus_btn.add_theme_font_size_override("font_size", 22)
	ThemeManager.apply_nav_button_style(minus_btn, 8)
	row.add_child(minus_btn)
	
	var spinbox = SpinBox.new()
	spinbox.custom_minimum_size = Vector2(110, 52)
	spinbox.min_value = min_val
	spinbox.max_value = max_val
	spinbox.step = step
	spinbox.value = setting.value
	
	var line_edit = spinbox.get_line_edit()
	if line_edit != null:
		line_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		line_edit.add_theme_font_size_override("font_size", 19)
		ThemeManager.apply_input_style(line_edit, 8)
		
	spinbox.value_changed.connect(func(val):
		setting.set_value(val)
	)
	row.add_child(spinbox)
	
	# Plus Button
	var plus_btn = Button.new()
	plus_btn.text = "＋"
	plus_btn.custom_minimum_size = Vector2(52, 52)
	plus_btn.add_theme_font_size_override("font_size", 22)
	ThemeManager.apply_nav_button_style(plus_btn, 8)
	row.add_child(plus_btn)
	
	minus_btn.pressed.connect(func():
		spinbox.value = clamp(spinbox.value - step, spinbox.min_value, spinbox.max_value)
	)
	plus_btn.pressed.connect(func():
		spinbox.value = clamp(spinbox.value + step, spinbox.min_value, spinbox.max_value)
	)
	
	if suffix != "":
		var label2 = Label.new()
		label2.text = suffix
		label2.custom_minimum_size = Vector2(30, 0)
		label2.add_theme_font_size_override("font_size", 18)
		label2.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
		label2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label2)
	
	return row


func _create_toggle_setting_row(label_text: String, setting_name: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.name = label_text.replace(" ", "")
	row.custom_minimum_size = Vector2(0, 52)
	
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 19)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	
	var check = CheckButton.new()
	check.custom_minimum_size = Vector2(72, 48)
	var setting = GlobalSettings.range_settings.settings[setting_name]
	check.set_pressed_no_signal(setting.value)
	check.toggled.connect(func(on):
		setting.set_value(on)
	)
	row.add_child(check)
	
	return row


func _create_option_setting_row(label_text: String, setting_name: String, options: Array[String]) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.name = label_text.replace(" ", "")
	row.custom_minimum_size = Vector2(0, 52)

	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 19)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)

	var opt = OptionButton.new()
	for i in range(options.size()):
		opt.add_item(options[i], i)
	_setup_touch_option_button(opt)

	var setting: Setting = GlobalSettings.range_settings.settings.get(setting_name, null)
	var active_val = ""
	if has_node("/root/MultiplayerManager"):
		var mp_mgr = get_node("/root/MultiplayerManager")
		if "turn_order_mode" in mp_mgr and not str(mp_mgr.turn_order_mode).is_empty():
			active_val = str(mp_mgr.turn_order_mode)
	if active_val.is_empty() and setting != null:
		active_val = str(setting.value)

	for i in range(options.size()):
		if options[i] == active_val:
			opt.selected = i
			break

	opt.item_selected.connect(func(index: int):
		var val = options[index]
		if setting != null:
			setting.set_value(val)
		if has_node("/root/MultiplayerManager"):
			var mp_mgr = get_node("/root/MultiplayerManager")
			mp_mgr.turn_order_mode = val
			if mp_mgr.has_method("save_current_match"):
				mp_mgr.save_current_match()
	)
	row.add_child(opt)

	return row


func _create_slider_setting_row(label_prefix: String, setting_name: String, min_val: float, max_val: float, step: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = label_prefix.replace(" ", "")
	row.custom_minimum_size = Vector2(0, 52)
	row.add_theme_constant_override("separation", 10)
	
	var setting = GlobalSettings.range_settings.settings[setting_name]
	
	var label := Label.new()
	label.text = "%s: %.0f" % [label_prefix, setting.value]
	label.add_theme_font_size_override("font_size", 19)
	label.custom_minimum_size = Vector2(300, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	
	var minus_btn := Button.new()
	minus_btn.text = "－"
	minus_btn.custom_minimum_size = Vector2(48, 48)
	minus_btn.add_theme_font_size_override("font_size", 20)
	ThemeManager.apply_nav_button_style(minus_btn, 8)
	row.add_child(minus_btn)
	
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = setting.value
	slider.custom_minimum_size = Vector2(180, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(val):
		setting.set_value(val)
		label.text = "%s: %.0f" % [label_prefix, val]
	)
	row.add_child(slider)
	
	var plus_btn := Button.new()
	plus_btn.text = "＋"
	plus_btn.custom_minimum_size = Vector2(48, 48)
	plus_btn.add_theme_font_size_override("font_size", 20)
	ThemeManager.apply_nav_button_style(plus_btn, 8)
	row.add_child(plus_btn)
	
	minus_btn.pressed.connect(func():
		slider.value = clamp(slider.value - step, slider.min_value, slider.max_value)
	)
	plus_btn.pressed.connect(func():
		slider.value = clamp(slider.value + step, slider.min_value, slider.max_value)
	)
	
	return row


func _setup_displayed_stats_section() -> void:
	var root := get_node_or_null("MarginContainer/VBoxContainer/TabContainer/Stats/MarginContainer/StatsVBox")
	if root == null:
		return
	for child in root.get_children():
		child.queue_free()

	# --- Header & Instruction Card ---
	var header_card := PanelContainer.new()
	ThemeManager.apply_card_panel_style(header_card, true, 10, 16, 14, 16, 14)
	
	var header_vbox := VBoxContainer.new()
	header_vbox.add_theme_constant_override("separation", 6)
	
	var header_top_hbox := HBoxContainer.new()
	var header_title := Label.new()
	header_title.text = "🎯 On-Screen Displayed Statistics"
	header_title.add_theme_font_size_override("font_size", 20)
	header_title.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_top_hbox.add_child(header_title)
	
	_stats_count_label = Label.new()
	_stats_count_label.add_theme_font_size_override("font_size", 18)
	header_top_hbox.add_child(_stats_count_label)
	header_vbox.add_child(header_top_hbox)
	
	var header_desc := Label.new()
	header_desc.text = "Select up to 12 metrics to display in on-screen tiles during play. You can drag and drop tiles on the range to customize your layout. Only 12 stats can be enabled at a time."
	header_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_desc.add_theme_font_size_override("font_size", 16)
	header_desc.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	header_vbox.add_child(header_desc)
	
	header_card.add_child(header_vbox)
	root.add_child(header_card)

	_update_stats_count_label()

	# --- Categorized Stat Cards ---
	var categories = ["Ball Flight", "Club Delivery", "Trajectory"]
	for cat in categories:
		var cat_label := Label.new()
		cat_label.text = cat.to_upper() + " METRICS"
		cat_label.add_theme_font_size_override("font_size", 18)
		cat_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		root.add_child(cat_label)

		for stat in StatDefinitions.STATS:
			if stat.get("category", "") != cat:
				continue
			var card = _create_stat_card_row(stat)
			root.add_child(card)

		var cat_sep := HSeparator.new()
		root.add_child(cat_sep)


func _update_stats_count_label() -> void:
	if _stats_count_label == null:
		return
	var active_count: int = GlobalSettings.range_settings.displayed_stats.value.size()
	var max_count := StatDefinitions.MAX_DISPLAYED_STATS
	_stats_count_label.text = "Active: %d / %d (Max %d)" % [active_count, max_count, max_count]
	if active_count >= max_count:
		_stats_count_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	else:
		_stats_count_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.6))


func _create_stat_card_row(stat: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	ThemeManager.apply_card_panel_style(card, false, 8, 16, 12, 16, 12)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 4)
	
	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 10)
	
	var title_lbl := Label.new()
	title_lbl.text = str(stat.get("name", ""))
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	title_hbox.add_child(title_lbl)
	
	var u_str = str(stat.get("units_imperial", ""))
	var short_badge := Label.new()
	short_badge.text = "[Tile: %s | %s]" % [str(stat.get("short_label", "")), u_str]
	short_badge.add_theme_font_size_override("font_size", 14)
	short_badge.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
	title_hbox.add_child(short_badge)
	
	text_vbox.add_child(title_hbox)
	
	var desc_lbl := Label.new()
	desc_lbl.text = str(stat.get("description", ""))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 15)
	desc_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	text_vbox.add_child(desc_lbl)
	
	hbox.add_child(text_vbox)
	
	var check_btn := CheckButton.new()
	check_btn.custom_minimum_size = Vector2(72, 48)
	var stat_id := str(stat.get("id", ""))
	var active_stats: Array = GlobalSettings.range_settings.displayed_stats.value
	check_btn.set_pressed_no_signal(active_stats.has(stat_id))
	
	check_btn.toggled.connect(func(toggled_on: bool):
		_on_stat_toggled(stat_id, toggled_on, check_btn)
	)
	
	hbox.add_child(check_btn)
	card.add_child(hbox)
	return card


func _on_stat_toggled(stat_id: String, toggled_on: bool, btn: CheckButton) -> void:
	var active_stats: Array = GlobalSettings.range_settings.displayed_stats.value.duplicate()
	if toggled_on:
		if active_stats.size() >= StatDefinitions.MAX_DISPLAYED_STATS:
			# Max limit reached! Revert toggle and display modal warning prompt
			btn.set_pressed_no_signal(false)
			_show_stat_limit_popup()
			return
		if not active_stats.has(stat_id):
			active_stats.append(stat_id)
	else:
		active_stats.erase(stat_id)
		
	GlobalSettings.range_settings.displayed_stats.set_value(active_stats)
	GlobalSettings.save_settings()
	_update_stats_count_label()


func _show_stat_limit_popup() -> void:
	if _stat_limit_modal != null and is_instance_valid(_stat_limit_modal):
		_stat_limit_modal.queue_free()
		_stat_limit_modal = null
		
	var overlay := ColorRect.new()
	overlay.name = "StatLimitOverlay"
	overlay.color = Color(0, 0, 0, 0.70)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	
	var modal := PanelContainer.new()
	modal.custom_minimum_size = Vector2(520, 270)
	ThemeManager.apply_modal_style(modal, 14)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	
	var title := Label.new()
	title.text = "⚠️ Maximum Display Limit Reached"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var msg := Label.new()
	msg.text = "You can display a maximum of 12 stats on screen at a time.\n\nPlease disable one of your currently enabled stats before enabling this one to keep it at 12 total displayed stats."
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 17)
	msg.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	vbox.add_child(msg)
	
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
	var ok_btn := Button.new()
	ok_btn.text = "Got It"
	ok_btn.custom_minimum_size = Vector2(160, 52)
	ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ThemeManager.apply_primary_button_style(ok_btn, 8)
	ok_btn.pressed.connect(func():
		overlay.queue_free()
		_stat_limit_modal = null
	)
	vbox.add_child(ok_btn)
	
	modal.add_child(vbox)
	overlay.add_child(modal)
	
	modal.anchor_left = 0.5
	modal.anchor_top = 0.5
	modal.anchor_right = 0.5
	modal.anchor_bottom = 0.5
	modal.offset_left = -260
	modal.offset_top = -135
	modal.offset_right = 260
	modal.offset_bottom = 135
	
	add_child(overlay)
	_stat_limit_modal = overlay
