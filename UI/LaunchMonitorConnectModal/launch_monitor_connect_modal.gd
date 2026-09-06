class_name LaunchMonitorConnectModal
extends Control

signal closed
signal skipped
signal connected_and_continued

@onready var modal_panel: PanelContainer = $CenterContainer/ModalPanel
@onready var close_header_button: Button = %CloseHeaderButton
@onready var tab_container: TabContainer = %TabContainer
@onready var bluetooth_tab: ScrollContainer = %BluetoothTab
@onready var other_tab: ScrollContainer = %OtherTab

# Bluetooth controls
@onready var device_option: OptionButton = %DeviceOption
@onready var scan_button: Button = %ScanButton
@onready var connect_button: Button = %ConnectButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var status_label: Label = %StatusLabel
@onready var battery_label: Label = %BatteryLabel
@onready var device_card: PanelContainer = %DeviceCard
@onready var status_card: PanelContainer = %StatusCard

# Other / GSPro controls
@onready var other_device_option: OptionButton = %OtherDeviceOption
@onready var other_selector_card: PanelContainer = %OtherSelectorCard
@onready var network_info_card: PanelContainer = %NetworkInfoCard
@onready var instructions_card: PanelContainer = %InstructionsCard
@onready var instructions_text: RichTextLabel = %InstructionsText

# Footer controls
@onready var skip_button: Button = %SkipButton
@onready var continue_button: Button = %ContinueButton

var _launch_monitor: Node = null

const OTHER_DEVICE_GUIDES = {
	"mlm2pro": {
		"name": "Rapsodo MLM2PRO (MLM2PRO-GSPro-Connector)",
		"bridge": "MLM2PRO-GSPro-Connector (Community Bridge)",
		"text": "[b]Bridge Software:[/b] [color=#64b5f6]MLM2PRO-GSPro-Connector[/color] (by Springbok)\n[b]Protocol:[/b] GSPro Open Connect v1 over TCP\n[b]Destination Host / Port:[/b] [color=#81c784]127.0.0.1 : 49152[/color]\n\n[b]Step-by-Step Instructions:[/b]\n1. Power on your [b]MLM2PRO[/b] and connect it to your PC or mobile bridge app.\n2. In the MLM2PRO connector settings, configure the [b]GSPro Host / IP[/b] to [b]127.0.0.1[/b] (or your PC's LAN IP if running on phone) and [b]Port[/b] to [b]49152[/b].\n3. Click [b]Connect[/b] in the connector app.\n4. Start any [b]Course[/b], [b]Driving Range[/b], or [b]Minigame[/b] in Heckle Golf Simulator (the TCP server on port 49152 starts automatically).\n5. Hit shots! Ball speed, launch angles, total spin, and spin axis will stream directly into the simulation."
	},
	"garmin_r10": {
		"name": "Garmin Approach R10 (Garmin R10 OpenConnect)",
		"bridge": "Garmin R10 OpenConnect / E6 to GSPro Bridge",
		"text": "[b]Bridge Software:[/b] [color=#64b5f6]Garmin R10 OpenConnect / E6 Bridge[/color]\n[b]Protocol:[/b] GSPro Open Connect v1 over TCP\n[b]Destination Host / Port:[/b] [color=#81c784]127.0.0.1 : 49152[/color]\n\n[b]Step-by-Step Instructions:[/b]\n1. Turn on your [b]Garmin Approach R10[/b] and pair it with the Garmin Golf app or PC bridge.\n2. In your bridge settings, set the target IP address to [b]127.0.0.1[/b] (or PC local IP) and port to [b]49152[/b].\n3. Make sure your PC and mobile device are on the same Wi-Fi network.\n4. Load into any Range or Course in Heckle Golf Simulator.\n5. Take a swing — radar metrics will trigger real-time ball flight and announcer commentary."
	},
	"flightscope": {
		"name": "FlightScope Mevo+ / X3 (GSPro Bridge)",
		"bridge": "FlightScope PC / Mobile Connector for GSPro",
		"text": "[b]Bridge Software:[/b] [color=#64b5f6]FlightScope GSPro Interface[/color]\n[b]Protocol:[/b] GSPro Open Connect v1 over TCP\n[b]Destination Host / Port:[/b] [color=#81c784]127.0.0.1 : 49152[/color]\n\n[b]Step-by-Step Instructions:[/b]\n1. Connect your [b]Mevo+[/b] or [b]X3[/b] to your PC/tablet over Wi-Fi.\n2. In the FlightScope connector settings, set the GSPro destination IP to [b]127.0.0.1[/b] and port to [b]49152[/b].\n3. Open any Course or the Driving Range in Heckle Golf Simulator.\n4. Radar metrics will flow directly into OpenFairway physics with zero setup required."
	},
	"uneekor": {
		"name": "Uneekor (EYE XO / EYE XO2 / QED)",
		"bridge": "Uneekor Third-Party Connector (GSPro Mode)",
		"text": "[b]Bridge Software:[/b] [color=#64b5f6]Uneekor View / Ignite Connector[/color]\n[b]Protocol:[/b] GSPro Open Connect v1 over TCP\n[b]Destination Host / Port:[/b] [color=#81c784]127.0.0.1 : 49152[/color]\n\n[b]Step-by-Step Instructions:[/b]\n1. Start the [b]Uneekor View[/b] software and enable Third-Party Connector / GSPro integration.\n2. Set the outbound destination socket to [b]127.0.0.1:49152[/b].\n3. Enter any Course or Range session in Heckle Golf Simulator.\n4. High-speed overhead optical camera data will trigger shots instantaneously."
	},
	"bushnell": {
		"name": "Bushnell Launch Pro / Foresight (GC3 / GCQuad)",
		"bridge": "Game Changer / GSPro Connect Tool",
		"text": "[b]Bridge Software:[/b] [color=#64b5f6]Game Changer / Foresight GSPro Connect[/color]\n[b]Protocol:[/b] GSPro Open Connect v1 over TCP\n[b]Destination Host / Port:[/b] [color=#81c784]127.0.0.1 : 49152[/color]\n\n[b]Step-by-Step Instructions:[/b]\n1. Connect your [b]Bushnell Launch Pro[/b] or [b]Foresight GC3/GCQuad[/b] via USB, Ethernet, or Wi-Fi.\n2. In the connection tool, configure the forwarding socket to [b]127.0.0.1:49152[/b].\n3. Start your round or practice session in the simulator.\n4. Photometric ball data will be received and simulated in real time."
	},
	"pitrac": {
		"name": "PiTrac / Generic GSPro Open Connect v1",
		"bridge": "Any GSPro Open Connect v1 JSON TCP Client",
		"text": "[b]Bridge Software:[/b] [color=#64b5f6]PiTrac / Custom TCP Client[/color]\n[b]Protocol:[/b] GSPro Open Connect v1 over TCP\n[b]Destination Host / Port:[/b] [color=#81c784]127.0.0.1 : 49152[/color]\n\n[b]Step-by-Step Instructions:[/b]\n1. Configure your client to connect to [b]127.0.0.1:49152[/b].\n2. Send standard JSON shot payloads:\n[code]{\"ShotDataOptions\": {\"ContainsBallData\": true}, \"BallData\": {\"Speed\": 150.0, \"SpinAxis\": 0.0, \"TotalSpin\": 2500.0, \"HLA\": 0.0, \"VLA\": 12.0}}[/code]\n3. The simulator receives the shot, simulates the flight, and replies with [code]{\"Code\": 200}[/code]."
	},
	"shot_injector": {
		"name": "Built-in Python Shot Injector (inject_shot.py)",
		"bridge": "inject_shot.py (Included with Simulator)",
		"text": "[b]Utility:[/b] [color=#64b5f6]inject_shot.py[/color] (in project root)\n[b]Protocol:[/b] GSPro Open Connect v1 over TCP\n[b]Destination Host / Port:[/b] [color=#81c784]127.0.0.1 : 49152[/color]\n\n[b]Step-by-Step Instructions:[/b]\n1. Open Heckle Golf Simulator and go to [b]Range[/b] or start any [b]Course[/b].\n2. Open a terminal or command prompt in the HeckleGolfSim directory.\n3. Run: [code]python inject_shot.py[/code]\n4. Pick a preset shot (Driver bomb, approach wedge, slice, hook, duff, putt) or type 9 for custom numbers.\n5. The shot will immediately launch in-game so you can test ball flight, camera angles, and announcer roasts without hardware!"
	}
}


func _ready() -> void:
	# Apply Design System
	if modal_panel != null:
		ThemeManager.apply_modal_style(modal_panel, 14)
	if device_card != null:
		ThemeManager.apply_card_panel_style(device_card, false, 10, 14, 14, 14, 14)
	if status_card != null:
		ThemeManager.apply_card_panel_style(status_card, false, 10, 14, 12, 14, 12)
	if other_selector_card != null:
		ThemeManager.apply_card_panel_style(other_selector_card, false, 10, 14, 14, 14, 14)
	if instructions_card != null:
		ThemeManager.apply_card_panel_style(instructions_card, false, 10, 14, 14, 14, 14)

	# Responsive modal sizing
	var viewport_size = get_viewport().get_visible_rect().size
	var target_width = clamp(viewport_size.x * 0.78, 480.0, 780.0)
	var target_height = clamp(viewport_size.y * 0.82, 420.0, 680.0)
	modal_panel.custom_minimum_size = Vector2(target_width, target_height)

	# Style TabContainer
	if tab_container != null:
		tab_container.add_theme_font_size_override("font_size", 18)
		tab_container.add_theme_constant_override("side_margin", 12)
		tab_container.add_theme_stylebox_override("tab_selected", _create_tab_style(ThemeManager.COLOR_PRIMARY_NORMAL, ThemeManager.COLOR_PRIMARY_NORMAL.lightened(0.2)))
		tab_container.add_theme_stylebox_override("tab_unselected", _create_tab_style(ThemeManager.COLOR_NAV_NORMAL, Color(1, 1, 1, 0.15)))
		tab_container.add_theme_stylebox_override("tab_hovered", _create_tab_style(ThemeManager.COLOR_NAV_HOVER, Color(1, 1, 1, 0.3)))
		tab_container.set_tab_title(0, "📶 Bluetooth (Square)")
		tab_container.set_tab_title(1, "🌐 Other (GSPro / Network)")

	# Apply touch scroll styling
	if bluetooth_tab != null:
		ThemeManager.apply_scroll_container_style(bluetooth_tab, 24)
	if other_tab != null:
		ThemeManager.apply_scroll_container_style(other_tab, 24)

	# Setup buttons styling
	ThemeManager.apply_nav_button_style(close_header_button, 6)
	ThemeManager.apply_secondary_button_style(scan_button, 8)
	ThemeManager.apply_primary_button_style(connect_button, 8)
	ThemeManager.apply_danger_button_style(disconnect_button, 8)
	ThemeManager.apply_secondary_button_style(skip_button, 8)
	ThemeManager.apply_primary_button_style(continue_button, 8)

	_setup_touch_option_button(device_option)
	_setup_touch_option_button(other_device_option)

	# Button signal connections
	close_header_button.pressed.connect(_on_skip_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	scan_button.pressed.connect(_on_scan_pressed)
	connect_button.pressed.connect(_on_connect_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)

	# Setup Other Launch Monitor device dropdown
	_setup_other_devices_dropdown()

	if has_node("/root/LaunchMonitorManager"):
		_launch_monitor = get_node("/root/LaunchMonitorManager")
		if not _launch_monitor.device_discovered.is_connected(_on_device_discovered):
			_launch_monitor.device_discovered.connect(_on_device_discovered)
		if not _launch_monitor.status_changed.is_connected(_on_status_changed):
			_launch_monitor.status_changed.connect(_on_status_changed)
		if not _launch_monitor.error_occurred.is_connected(_on_error_occurred):
			_launch_monitor.error_occurred.connect(_on_error_occurred)
		if not _launch_monitor.battery_changed.is_connected(_on_battery_changed):
			_launch_monitor.battery_changed.connect(_on_battery_changed)
		if not _launch_monitor.ready_changed.is_connected(_on_ready_changed):
			_launch_monitor.ready_changed.connect(_on_ready_changed)

	_refresh_devices()
	_update_status_display()


func _create_tab_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 0
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _setup_touch_option_button(opt: OptionButton) -> void:
	if opt == null:
		return
	ThemeManager.apply_option_button_style(opt, 18, Vector2(220, 52))


func _setup_other_devices_dropdown() -> void:
	if other_device_option == null:
		return
	
	other_device_option.clear()
	var keys = ["mlm2pro", "garmin_r10", "flightscope", "uneekor", "bushnell", "pitrac", "shot_injector"]
	for i in range(keys.size()):
		var key = keys[i]
		var info = OTHER_DEVICE_GUIDES[key]
		other_device_option.add_item(info["name"], i)
		other_device_option.set_item_metadata(i, key)

	other_device_option.item_selected.connect(_on_other_device_selected)
	_on_other_device_selected(0)


func _on_other_device_selected(index: int) -> void:
	if other_device_option == null or instructions_text == null:
		return
	var key = str(other_device_option.get_item_metadata(index))
	if OTHER_DEVICE_GUIDES.has(key):
		instructions_text.text = OTHER_DEVICE_GUIDES[key]["text"]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse_pos = get_global_mouse_position()
		if modal_panel != null and not modal_panel.get_global_rect().has_point(mouse_pos):
			_on_skip_pressed()


func _on_skip_pressed() -> void:
	skipped.emit()
	closed.emit()
	queue_free()


func _on_continue_pressed() -> void:
	connected_and_continued.emit()
	closed.emit()
	queue_free()


func _on_scan_pressed() -> void:
	if _launch_monitor != null:
		_launch_monitor.start_scan()
		scan_button.text = "🔄 Scanning..."
		status_label.text = "Status: Scanning for devices..."
		status_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))


func _on_connect_pressed() -> void:
	if _launch_monitor == null or device_option == null or device_option.item_count == 0:
		return
	var index = device_option.selected
	var device_id = str(device_option.get_item_metadata(index))
	if device_id == "":
		return
	_launch_monitor.set_enabled(true)
	_launch_monitor.connect_to_device(device_id)
	status_label.text = "Status: Connecting..."
	status_label.add_theme_color_override("font_color", Color(0.4, 0.75, 0.95))


func _on_disconnect_pressed() -> void:
	if _launch_monitor != null:
		_launch_monitor.set_enabled(false)
		_launch_monitor.disconnect_device()
		status_label.text = "Status: Disconnected"
		status_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)


func _refresh_devices() -> void:
	if device_option == null or _launch_monitor == null:
		return
	
	var selected_device := str(_launch_monitor.settings.get("device_id", ""))
	var saved_name := str(_launch_monitor.settings.get("device_name", ""))
	if saved_name == "":
		saved_name = "Square Golf"

	if selected_device != "" and not _launch_monitor.devices.has(selected_device):
		_launch_monitor.devices[selected_device] = {
			"name": saved_name,
			"rssi": 0
		}

	device_option.clear()

	if _launch_monitor.devices.is_empty():
		device_option.add_item("No devices found (Click Scan)", 0)
		device_option.set_item_metadata(0, "")
		connect_button.disabled = true
		return

	connect_button.disabled = false
	for dev_id in _launch_monitor.devices.keys():
		var device = _launch_monitor.devices[dev_id]
		var label := str(device.get("name", "Square Golf"))
		var idx := device_option.item_count
		device_option.add_item(label, idx)
		device_option.set_item_metadata(idx, dev_id)
		if dev_id == selected_device:
			device_option.select(idx)

	if device_option.selected < 0 and device_option.item_count > 0:
		device_option.select(0)


func _update_status_display() -> void:
	if _launch_monitor == null or status_label == null:
		return

	var current_status: String = str(_launch_monitor.status)
	scan_button.text = "🔍 Scan"

	match current_status:
		"Connected", "Ready":
			status_label.text = "Status: Connected (%s)" % current_status
			status_label.add_theme_color_override("font_color", Color(0.35, 0.85, 0.45))
			continue_button.text = "Continue to Main Menu ➔"
		"Scanning":
			status_label.text = "Status: Scanning for devices..."
			status_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
			scan_button.text = "🔄 Scanning..."
		"Connecting":
			status_label.text = "Status: Connecting..."
			status_label.add_theme_color_override("font_color", Color(0.4, 0.75, 0.95))
		"Disconnected":
			status_label.text = "Status: Disconnected"
			status_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
			continue_button.text = "Continue to Main Menu"
		_:
			status_label.text = "Status: %s" % current_status
			status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))

	if battery_label != null:
		if int(_launch_monitor.battery_level) >= 0:
			battery_label.text = "🔋 Battery: %d%%" % int(_launch_monitor.battery_level)
			battery_label.visible = true
		else:
			battery_label.text = ""
			battery_label.visible = false


func _on_device_discovered(_device_id: String, _name: String, _rssi: int) -> void:
	_refresh_devices()


func _on_status_changed(_status: String) -> void:
	_update_status_display()


func _on_error_occurred(message: String) -> void:
	if status_label != null:
		status_label.text = "Status: %s" % message
		status_label.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))


func _on_battery_changed(_level: int) -> void:
	_update_status_display()


func _on_ready_changed(_is_ready: bool) -> void:
	_update_status_display()


func _exit_tree() -> void:
	if _launch_monitor != null:
		if _launch_monitor.device_discovered.is_connected(_on_device_discovered):
			_launch_monitor.device_discovered.disconnect(_on_device_discovered)
		if _launch_monitor.status_changed.is_connected(_on_status_changed):
			_launch_monitor.status_changed.disconnect(_on_status_changed)
		if _launch_monitor.error_occurred.is_connected(_on_error_occurred):
			_launch_monitor.error_occurred.disconnect(_on_error_occurred)
		if _launch_monitor.battery_changed.is_connected(_on_battery_changed):
			_launch_monitor.battery_changed.disconnect(_on_battery_changed)
		if _launch_monitor.ready_changed.is_connected(_on_ready_changed):
			_launch_monitor.ready_changed.disconnect(_on_ready_changed)
