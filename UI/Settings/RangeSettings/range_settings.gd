extends PanelContainer

signal toggle_settings_requested
signal close_settings_requested
signal manage_players_requested

var reset_spin_box : SpinBox = null
var temperature_spin_box : SpinBox = null
var altitude_spin_box : SpinBox = null
var surface_option : OptionButton = null
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

const SQUARE_UI_LOG_PREFIX := "[SquareUI]"
const SQUARE_CLUBS := {
	"Driver": "0204",
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
	spin_box.set_block_signals(true)
	spin_box.step = step
	if setting.min_value != null:
		spin_box.min_value = setting.min_value
	if setting.max_value != null:
		spin_box.max_value = setting.max_value
	spin_box.value = setting.value
	spin_box.set_block_signals(false)
	
	if spin_box.value != setting.value:
		setting.set_value(spin_box.value)

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	reset_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/BallResetTimer/ResetSpinBox
	temperature_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Temperature/TemperatureSpinBox
	altitude_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Altitude/AltitudeSpinBox
	surface_option = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/SurfaceType/SurfaceOption
	tracer_count_spin_box = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/TracerCount/TracerCountSpinBox

	# Reset Timer Settings
	_setup_spin_box(reset_spin_box, GlobalSettings.range_settings.ball_reset_timer, 0.5)

	# Temperature Settings
	_setup_spin_box(temperature_spin_box, GlobalSettings.range_settings.temperature, 1.0)

	# Altitude Settings
	_setup_spin_box(altitude_spin_box, GlobalSettings.range_settings.altitude, 10.0)

	# Tracer count
	_setup_spin_box(tracer_count_spin_box, GlobalSettings.range_settings.shot_tracer_count, 1.0)

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
	_setup_square_monitor_section()
	_setup_hecklelinks_announcer_section()

	# Create and insert Gimme Range configuration settings rows in the Gameplay tab
	var gameplay_vbox = $MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox
	
	var gimme_sep = HSeparator.new()
	gameplay_vbox.add_child(gimme_sep)
	
	var gimme_label = Label.new()
	gimme_label.text = "Gimme Ranges"
	gimme_label.add_theme_font_size_override("font_size", 18)
	gimme_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
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
	turn_label.text = "Turn Order Settings"
	turn_label.add_theme_font_size_override("font_size", 18)
	turn_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	gameplay_vbox.add_child(turn_label)
	
	var custom_next_player_toggle = _create_toggle_setting_row("Custom Next Player to Hit", "custom_next_player")
	gameplay_vbox.add_child(custom_next_player_toggle)

	# Create and insert camera configuration settings rows in the Camera tab
	var camera_vbox = $MarginContainer/VBoxContainer/TabContainer/Camera/MarginContainer/CameraVBox
	
	var height_row = _create_spinbox_setting_row("Camera Height", "camera_height", 0.5, 10.0, 0.1, "m")
	camera_vbox.add_child(height_row)
	
	var dist_row = _create_spinbox_setting_row("Camera Distance", "camera_distance", 2.0, 30.0, 0.1, "m")
	camera_vbox.add_child(dist_row)
	
	var fov_row = _create_spinbox_setting_row("Camera FOV", "camera_fov", 1.0, 60.0, 0.1, "deg")
	camera_vbox.add_child(fov_row)

	var far_row = _create_spinbox_setting_row("Camera Far", "camera_far", 100.0, 1000.0, 1.0, "m")
	camera_vbox.add_child(far_row)
	
	# Visual effects separator
	var fx_label = Label.new()
	fx_label.text = "Visual Effects"
	fx_label.add_theme_font_size_override("font_size", 18)
	fx_label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.8))
	camera_vbox.add_child(fx_label)
	
	# DOF toggle
	var dof_row = HBoxContainer.new()
	dof_row.name = "DOFToggle"
	var dof_label = Label.new()
	dof_label.text = "Depth of Field"
	dof_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dof_row.add_child(dof_label)
	var dof_check = CheckButton.new()
	dof_check.set_pressed_no_signal(GlobalSettings.range_settings.dof_enabled.value)
	dof_check.toggled.connect(func(on): GlobalSettings.range_settings.dof_enabled.set_value(on))
	dof_row.add_child(dof_check)
	camera_vbox.add_child(dof_row)
	
	# DOF blur amount
	var blur_row = _create_spinbox_setting_row("DOF Blur", "dof_blur_amount", 0.0, 0.3, 0.01, "")
	camera_vbox.add_child(blur_row)
	
	# Vignette toggle
	var vig_row = HBoxContainer.new()
	vig_row.name = "VignetteToggle"
	var vig_label = Label.new()
	vig_label.text = "Vignette"
	vig_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vig_row.add_child(vig_label)
	var vig_check = CheckButton.new()
	vig_check.set_pressed_no_signal(GlobalSettings.range_settings.vignette_enabled.value)
	vig_check.toggled.connect(func(on): GlobalSettings.range_settings.vignette_enabled.set_value(on))
	vig_row.add_child(vig_check)
	camera_vbox.add_child(vig_row)
	
	# Vignette intensity
	var vig_int_row = _create_spinbox_setting_row("Vignette Intensity", "vignette_intensity", 0.0, 3.0, 0.1, "")
	camera_vbox.add_child(vig_int_row)

	# Add Close button dynamically to ButtonsHBox
	var buttons_hbox = get_node_or_null("MarginContainer/VBoxContainer/ButtonsHBox")
	if buttons_hbox != null:
		if not MultiplayerManager.players.is_empty() and not MultiplayerManager.practice_mode_active:
			var players_btn = Button.new()
			players_btn.name = "PlayersButton"
			players_btn.text = "👥 Players"
			players_btn.custom_minimum_size = Vector2(140, 40)
			_apply_material_button_style(players_btn, Color(0.25, 0.55, 0.35, 0.85)) # Green-ish
			players_btn.pressed.connect(func():
				manage_players_requested.emit()
				close_settings_requested.emit()
			)
			buttons_hbox.add_child(players_btn)

		var close_btn = Button.new()
		close_btn.name = "CloseButton"
		close_btn.text = "Close"
		close_btn.custom_minimum_size = Vector2(140, 40)
		close_btn.pressed.connect(func(): close_settings_requested.emit())
		buttons_hbox.add_child(close_btn)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func _on_settings_button_pressed() -> void:
	toggle_settings_requested.emit()


func _on_background_clicked(event: InputEvent) -> void:
	# Close the menu when clicking on the background
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close_settings_requested.emit()


func _on_exit_button_pressed() -> void:
	SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")


func _on_reset_layout_button_pressed() -> void:
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
	section.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Square"
	title.add_theme_font_size_override("font_size", 18)
	section.add_child(title)

	var enabled_row := HBoxContainer.new()
	enabled_row.add_child(_make_label("Enabled"))
	enabled_row.add_child(_make_spacer())
	square_enabled_button = CheckButton.new()
	square_enabled_button.set_pressed_no_signal(bool(launch_monitor.settings.get("enabled", false)))
	square_enabled_button.toggled.connect(_on_square_enabled_toggled)
	enabled_row.add_child(square_enabled_button)
	section.add_child(enabled_row)

	var device_row := HBoxContainer.new()
	device_row.add_child(_make_label("Device"))
	square_device_option = OptionButton.new()
	square_device_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	device_row.add_child(square_device_option)
	section.add_child(device_row)

	var action_row := HBoxContainer.new()
	square_scan_button = Button.new()
	square_scan_button.text = "Scan"
	square_scan_button.pressed.connect(_on_square_scan_pressed)
	action_row.add_child(square_scan_button)
	square_connect_button = Button.new()
	square_connect_button.text = "Connect"
	square_connect_button.pressed.connect(_on_square_connect_pressed)
	action_row.add_child(square_connect_button)
	square_disconnect_button = Button.new()
	square_disconnect_button.text = "Disconnect"
	square_disconnect_button.pressed.connect(_on_square_disconnect_pressed)
	action_row.add_child(square_disconnect_button)
	square_ready_button = Button.new()
	square_ready_button.text = "Ready"
	square_ready_button.pressed.connect(_on_square_ready_pressed)
	action_row.add_child(square_ready_button)
	section.add_child(action_row)

	var club_row := HBoxContainer.new()
	club_row.add_child(_make_label("Club"))
	square_club_option = OptionButton.new()
	square_club_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for club_name in SQUARE_CLUBS.keys():
		var index := square_club_option.item_count
		square_club_option.add_item(club_name)
		square_club_option.set_item_metadata(index, SQUARE_CLUBS[club_name])
	var current_club := str(launch_monitor.settings.get("club_code", "0204"))
	_select_option_by_metadata(square_club_option, current_club)
	square_club_option.item_selected.connect(_on_square_club_selected)
	club_row.add_child(square_club_option)
	section.add_child(club_row)

	var handedness_row := HBoxContainer.new()
	handedness_row.add_child(_make_label("Handedness"))
	square_handedness_option = OptionButton.new()
	square_handedness_option.add_item("Right", 0)
	square_handedness_option.add_item("Left", 1)
	var handedness := int(launch_monitor.settings.get("handedness", 0))
	var hand_index := square_handedness_option.get_item_index(handedness)
	if hand_index >= 0:
		square_handedness_option.select(hand_index)
	square_handedness_option.item_selected.connect(_on_square_handedness_selected)
	handedness_row.add_child(square_handedness_option)
	section.add_child(handedness_row)

	square_status_label = Label.new()
	square_battery_label = Label.new()
	square_firmware_label = Label.new()
	section.add_child(square_status_label)
	section.add_child(square_battery_label)
	section.add_child(square_firmware_label)

	root.add_child(section)

	launch_monitor.device_discovered.connect(_on_square_device_discovered)
	launch_monitor.status_changed.connect(_on_square_status_changed)
	launch_monitor.error_occurred.connect(_on_square_error_occurred)
	launch_monitor.battery_changed.connect(_on_square_battery_changed)
	launch_monitor.firmware_changed.connect(_on_square_firmware_changed)
	launch_monitor.ready_changed.connect(_on_square_ready_changed)

	_refresh_square_devices()
	_update_square_status_labels()


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(90, 0)
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
	square_device_option.clear()
	for device_id in launch_monitor.devices.keys():
		var device = launch_monitor.devices[device_id]
		var label := str(device.get("name", "Square"))
		var index := square_device_option.item_count
		square_device_option.add_item(label)
		square_device_option.set_item_metadata(index, device_id)
		if device_id == selected_device:
			square_device_option.select(index)


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
	get_node("/root/LaunchMonitorManager").disconnect_device()


func _on_square_ready_pressed() -> void:
	_square_debug("Ready pressed")
	get_node("/root/LaunchMonitorManager").set_ready()


func _on_square_club_selected(index: int) -> void:
	var club_code := str(square_club_option.get_item_metadata(index))
	get_node("/root/LaunchMonitorManager").set_club_code(club_code)


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
		$MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Temperature/Label2.text = "F"
		var temp_f = GlobalSettings.range_settings.temperature.value * 9.0 / 5.0 + 32.0
		temperature_spin_box.value = temp_f
		GlobalSettings.range_settings.temperature.set_value(temp_f)

		$MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Altitude/Label2.text = "ft"
		var alt_ft = GlobalSettings.range_settings.altitude.value * m2ft
		altitude_spin_box.value = alt_ft
		GlobalSettings.range_settings.altitude.set_value(alt_ft)
	else:
		$MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Temperature/Label2.text = "C"
		var temp_c = (GlobalSettings.range_settings.temperature.value - 32.0) * 5.0 / 9.0
		temperature_spin_box.value = temp_c
		GlobalSettings.range_settings.temperature.set_value(temp_c)

		$MarginContainer/VBoxContainer/TabContainer/Gameplay/MarginContainer/GameplayVBox/Altitude/Label2.text = "m"
		var alt_m = GlobalSettings.range_settings.altitude.value / m2ft
		altitude_spin_box.value = alt_m
		GlobalSettings.range_settings.altitude.set_value(alt_m)

	temperature_spin_box.set_block_signals(false)
	altitude_spin_box.set_block_signals(false)


func _setup_hecklelinks_announcer_section() -> void:
	if not has_node("/root/AnnouncerEngine"):
		return

	var announcer = get_node("/root/AnnouncerEngine")
	var root := $MarginContainer/VBoxContainer/TabContainer/Announcer/MarginContainer/AnnouncerVBox
	
	var section := VBoxContainer.new()
	section.name = "AnnouncerSettings"
	section.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "HeckleLinks Announcer"
	title.add_theme_font_size_override("font_size", 18)
	section.add_child(title)

	var announcer_row := HBoxContainer.new()
	var ann_label := Label.new()
	ann_label.text = "Announcer Voice"
	ann_label.custom_minimum_size = Vector2(150, 0)
	announcer_row.add_child(ann_label)
	
	var spacer1 := Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	announcer_row.add_child(spacer1)
	
	var ann_btn := CheckButton.new()
	ann_btn.set_pressed_no_signal(announcer.get("AnnouncerEnabled"))
	ann_btn.toggled.connect(func(toggled_on): announcer.set("AnnouncerEnabled", toggled_on))
	announcer_row.add_child(ann_btn)
	section.add_child(announcer_row)

	var praise_row := HBoxContainer.new()
	var praise_label := Label.new()
	praise_label.text = "Praise Enabled"
	praise_label.custom_minimum_size = Vector2(150, 0)
	praise_row.add_child(praise_label)
	
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	praise_row.add_child(spacer2)
	
	var praise_btn := CheckButton.new()
	praise_btn.set_pressed_no_signal(announcer.get("PraiseEnabled"))
	praise_btn.toggled.connect(func(toggled_on): announcer.set("PraiseEnabled", toggled_on))
	praise_row.add_child(praise_btn)
	section.add_child(praise_row)

	var heckle_row := HBoxContainer.new()
	var heckle_label := Label.new()
	heckle_label.text = "Heckling Enabled"
	heckle_label.custom_minimum_size = Vector2(150, 0)
	heckle_row.add_child(heckle_label)
	
	var spacer3 := Control.new()
	spacer3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heckle_row.add_child(spacer3)
	
	var heckle_btn := CheckButton.new()
	heckle_btn.set_pressed_no_signal(announcer.get("HeckleEnabled"))
	heckle_btn.toggled.connect(func(toggled_on): announcer.set("HeckleEnabled", toggled_on))
	heckle_row.add_child(heckle_btn)
	section.add_child(heckle_row)

	var voice_row := HBoxContainer.new()
	var voice_lbl := Label.new()
	voice_lbl.text = "Voice Locale"
	voice_lbl.custom_minimum_size = Vector2(150, 0)
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
	)
	voice_row.add_child(voice_opt)
	section.add_child(voice_row)

	# Voice Pitch Slider Row
	var pitch_row := HBoxContainer.new()
	var pitch_label := Label.new()
	pitch_label.text = "Voice Pitch: %.1f" % announcer.get("Pitch")
	pitch_label.custom_minimum_size = Vector2(150, 0)
	pitch_row.add_child(pitch_label)
	
	var pitch_slider := HSlider.new()
	pitch_slider.min_value = 0.5
	pitch_slider.max_value = 2.0
	pitch_slider.step = 0.1
	pitch_slider.value = announcer.get("Pitch")
	pitch_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pitch_slider.value_changed.connect(func(val):
		announcer.set("Pitch", val)
		pitch_label.text = "Voice Pitch: %.1f" % val
	)
	pitch_row.add_child(pitch_slider)
	section.add_child(pitch_row)

	# Voice Speed/Rate Slider Row
	var rate_row := HBoxContainer.new()
	var rate_label := Label.new()
	rate_label.text = "Voice Speed: %.1f" % announcer.get("Rate")
	rate_label.custom_minimum_size = Vector2(150, 0)
	rate_row.add_child(rate_label)
	
	var rate_slider := HSlider.new()
	rate_slider.min_value = 0.5
	rate_slider.max_value = 2.0
	rate_slider.step = 0.1
	rate_slider.value = announcer.get("Rate")
	rate_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate_slider.value_changed.connect(func(val):
		announcer.set("Rate", val)
		rate_label.text = "Voice Speed: %.1f" % val
	)
	rate_row.add_child(rate_slider)
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
	
	var label = Label.new()
	label.text = label_text + ": "
	row.add_child(label)
	
	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer1.size_flags_stretch_ratio = 0.6
	row.add_child(spacer1)
	
	var spinbox = SpinBox.new()
	spinbox.custom_minimum_size = Vector2(100, 0)
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spinbox.min_value = min_val
	spinbox.max_value = max_val
	spinbox.step = step
	
	var setting = GlobalSettings.range_settings.settings[setting_name]
	spinbox.value = setting.value
	spinbox.value_changed.connect(func(val):
		setting.set_value(val)
	)
	row.add_child(spinbox)
	
	if suffix != "":
		var label2 = Label.new()
		label2.text = suffix
		row.add_child(label2)
		
	var spacer2 = Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer2)
	
	return row


func _create_toggle_setting_row(label_text: String, setting_name: String) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.name = label_text.replace(" ", "")
	
	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	
	var check = CheckButton.new()
	var setting = GlobalSettings.range_settings.settings[setting_name]
	check.set_pressed_no_signal(setting.value)
	check.toggled.connect(func(on):
		setting.set_value(on)
	)
	row.add_child(check)
	
	return row


func _apply_material_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 20 # Pill style
	style_normal.corner_radius_top_right = 20
	style_normal.corner_radius_bottom_left = 20
	style_normal.corner_radius_bottom_right = 20
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

