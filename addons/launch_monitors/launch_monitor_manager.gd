extends Node

# Monitor implementations live in sibling folders (e.g. `square/`); shared transports and external receivers live under `common/`.

signal hit_ball(data: Dictionary)
signal device_discovered(device_id: String, name: String, rssi: int)
signal status_changed(status: String)
signal error_occurred(message: String)
signal battery_changed(level: int)
signal firmware_changed(firmware: String)
signal ready_changed(is_ready: bool)
signal club_code_changed(club_code: String)
signal sensor_data_updated(pos_x: int, pos_y: int, pos_z: int, is_ready: bool, is_detected: bool)

const SETTINGS_PATH := "user://square_launch_monitor.cfg"
const DEFAULT_CLUB_CODE := "0204"
const SQUARE_CLASS_NAME := "SquareLaunchMonitor"
const SQUARE_SCRIPT_PATH := "res://addons/launch_monitors/square/SquareLaunchMonitor.cs"
const SQUARE_LOG_PREFIX := "[SquareLM]"
const SQUARE_DEVICE_PREFIX := "squaregolf"
const GARMIN_CLASS_NAME := "GarminLaunchMonitor"
const GARMIN_SCRIPT_PATH := "res://addons/launch_monitors/garmin/GarminLaunchMonitor.cs"
const GARMIN_LOG_PREFIX := "[GarminLM]"
const BLUEZ_DEVICE_SEGMENT_PREFIX := "/dev_"
const LINUX_AUTO_CONNECT_SCAN_SECONDS := 15.0
const TRANSIENT_CONNECT_ERROR_MARKERS := [
	"not ready yet",
	"could not open the selected bluetooth device",
	"unreachable"
]

var devices: Dictionary = {}
var status := "Disconnected"
var battery_level := -1
var firmware := ""
var is_ready := false
var last_sensor_data := {"pos_x": 0, "pos_y": 0, "pos_z": 0, "ready": false, "detected": false}
var _square_init_error := ""
var _garmin_init_error := ""
var _active_driver := "" # "square" or "garmin"
var settings := {
	"enabled": false,
	"device_id": "",
	"device_name": "",
	"device_type": "auto", # "auto", "square", "garmin"
	"club_code": DEFAULT_CLUB_CODE,
	"handedness": 0,
	"ready_ding_enabled": true,
	"ready_indicator_enabled": true,
	"ball_placement_guide_enabled": true
}

var _square: Node = null
var _garmin: Node = null
var _config := ConfigFile.new()
var _linux_auto_connect_active := false
var _linux_auto_connect_target_address := ""
var _linux_auto_connect_timer: Timer = null
var _auto_reconnect_timer: Timer = null
const MAX_AUTO_RECONNECT_ATTEMPTS := 5
var _auto_reconnect_attempts := 0
var _current_club_name := ""
var _ready_audio_player: AudioStreamPlayer = null
var _ready_hud: CanvasLayer = null
var _is_manual_connect := false


func _ready() -> void:
	_debug_log("Launch monitor ready. OS=%s, C# runtime class exists=%s, assembly=%s" % [
		OS.get_name(),
		str(ClassDB.class_exists("CSharpScript")),
		str(ProjectSettings.get_setting("dotnet/project/assembly_name", ""))
	])
	_load_settings()
	_setup_audio_player()
	_setup_ready_hud()
	_create_square_monitor()
	_create_garmin_monitor()
	if _square == null and _garmin == null:
		_debug_error("Neither Square nor Garmin monitor could be loaded: Square='%s', Garmin='%s'" % [_square_init_error, _garmin_init_error])
	if bool(settings.get("enabled", false)):
		_connect_saved_device_on_startup(str(settings.get("device_id", "")))
	
	if EventBus.has_signal("club_selected"):
		EventBus.club_selected.connect(_on_club_selected)


func _setup_audio_player() -> void:
	_ready_audio_player = AudioStreamPlayer.new()
	_ready_audio_player.name = "ReadyDingPlayer"
	_ready_audio_player.bus = "Master"
	add_child(_ready_audio_player)
	
	var ding_path := "res://assets/audio/sfx/ready_ding.wav"
	if ResourceLoader.exists(ding_path):
		var stream = load(ding_path) as AudioStream
		if stream != null:
			_ready_audio_player.stream = stream
			return
	_ready_audio_player.stream = _generate_fallback_ding_stream()


func _generate_fallback_ding_stream() -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	wav.stereo = false
	var sample_rate := 44100.0
	var duration := 0.22
	var num_samples := int(sample_rate * duration)
	var byte_array := PackedByteArray()
	byte_array.resize(num_samples * 2)

	var attack_samples := float(sample_rate * 0.006)
	var fadeout_samples := float(sample_rate * 0.010)

	var p0_f := 1046.50; var p0_w := 0.65; var p0_d := 18.0
	var p1_f := 1567.98; var p1_w := 0.25; var p1_d := 28.0
	var p2_f := 2637.02; var p2_w := 0.08; var p2_d := 55.0
	var p3_f := 523.25;  var p3_w := 0.15; var p3_d := 22.0

	for i in range(num_samples):
		var t := float(i) / sample_rate
		var env_attack: float = (float(i) / attack_samples) ** 2 if i < attack_samples else 1.0
		var env_fade: float = float(num_samples - 1 - i) / fadeout_samples if i >= (num_samples - int(fadeout_samples)) else 1.0

		var val := (sin(2.0 * PI * p0_f * t) * p0_w * exp(-p0_d * t) + \
				sin(2.0 * PI * p1_f * t) * p1_w * exp(-p1_d * t) + \
				sin(2.0 * PI * p2_f * t) * p2_w * exp(-p2_d * t) + \
				sin(2.0 * PI * p3_f * t) * p3_w * exp(-p3_d * t)) * env_attack * env_fade * 0.42
		val = clampf(val, -1.0, 1.0)
		var sample := int(val * 32767.0)
		byte_array.encode_s16(i * 2, sample)
	wav.data = byte_array
	return wav


func _setup_ready_hud() -> void:
	var hud_script_path := "res://UI/ReadyIndicator/ready_indicator_hud.gd"
	var script := load(hud_script_path) as Script
	if script != null and script.can_instantiate():
		_ready_hud = script.new() as CanvasLayer
		if _ready_hud != null:
			add_child(_ready_hud)
			_update_hud_display()


func play_ready_ding() -> void:
	if not bool(settings.get("ready_ding_enabled", true)):
		return
	if _ready_audio_player != null and _ready_audio_player.stream != null:
		_ready_audio_player.play()


func set_ready_ding_enabled(enabled: bool) -> void:
	settings["ready_ding_enabled"] = enabled
	_save_settings()


func set_ready_indicator_enabled(enabled: bool) -> void:
	settings["ready_indicator_enabled"] = enabled
	_save_settings()
	_update_hud_display()


func set_device_type(type_name: String) -> void:
	settings["device_type"] = type_name
	_save_settings()


func is_garmin_device_name(name: String) -> bool:
	var n := name.strip_edges().to_lower()
	return n.contains("approach") or n.contains("r10") or n.contains("garmin")


func is_square_device_name(name: String) -> bool:
	var n := name.strip_edges().to_lower()
	return n.begins_with(SQUARE_DEVICE_PREFIX) or n.contains("square")


func detect_device_type(device_id: String, device_name: String = "") -> String:
	var explicit_type := str(settings.get("device_type", "auto"))
	if explicit_type == "square" or explicit_type == "garmin":
		return explicit_type
	if device_name != "":
		if is_garmin_device_name(device_name):
			return "garmin"
		if is_square_device_name(device_name):
			return "square"
	if devices.has(device_id):
		var dev: Dictionary = devices[device_id]
		var dev_type := str(dev.get("type", ""))
		if dev_type != "":
			return dev_type
		var dname := str(dev.get("name", ""))
		if is_garmin_device_name(dname):
			return "garmin"
		if is_square_device_name(dname):
			return "square"
	return "square"


func start_scan() -> void:
	_cancel_linux_auto_connect_scan()
	devices.clear()
	var dev_type := str(settings.get("device_type", "auto"))
	_set_status("Scanning")
	if dev_type == "garmin":
		_start_garmin_scan()
	elif dev_type == "square":
		_start_square_scan()
	else:
		_start_square_scan()
		_start_garmin_scan()


func stop_scan() -> void:
	_cancel_linux_auto_connect_scan()
	_stop_square_scan()
	_stop_garmin_scan()
	if status == "Scanning":
		_set_status("Disconnected")


func connect_to_device(device_id: String, is_auto: bool = false) -> void:
	_is_manual_connect = not is_auto
	if _is_manual_connect:
		_auto_reconnect_attempts = 0
	_cancel_linux_auto_connect_scan()
	stop_scan()
	_debug_log("connect_to_device requested for %s (auto=%s)" % [device_id, str(is_auto)])
	settings["device_id"] = device_id
	var device_name := ""
	var detected_type := ""
	if devices.has(device_id):
		device_name = str(devices[device_id].get("name", ""))
		detected_type = str(devices[device_id].get("type", ""))
	if device_name != "":
		settings["device_name"] = device_name
	elif str(settings.get("device_name", "")) != "":
		device_name = str(settings.get("device_name", ""))
	
	if detected_type == "":
		detected_type = detect_device_type(device_id, device_name)

	if detected_type == "garmin":
		if device_name == "":
			device_name = "Garmin Approach R10"
			settings["device_name"] = device_name
		_active_driver = "garmin"
		settings["device_type"] = "garmin"
		_save_settings()
		if not devices.has(device_id):
			devices[device_id] = { "name": device_name, "rssi": 0, "type": "garmin" }
		if _garmin == null:
			var msg := "Garmin support is unavailable in this build."
			_set_status(msg)
			if _is_manual_connect:
				emit_signal("error_occurred", msg)
			return
		_update_garmin_weather_config()
		_garmin.call("ConnectToDevice", device_id)
	else:
		if device_name == "":
			device_name = "Square Golf"
			settings["device_name"] = device_name
		_active_driver = "square"
		if str(settings.get("device_type", "auto")) != "auto":
			settings["device_type"] = "square"
		_save_settings()
		if not devices.has(device_id):
			devices[device_id] = { "name": device_name, "rssi": 0, "type": "square" }
		if _square == null:
			var msg := _missing_support_message()
			_set_status(msg)
			if _is_manual_connect:
				emit_signal("error_occurred", msg)
			return
		_square.call("SetHandedness", int(settings.get("handedness", 0)))
		_square.call("SetClub", str(settings.get("club_code", DEFAULT_CLUB_CODE)))
		_square.call("ConnectToDevice", device_id)


func disconnect_device() -> void:
	_cancel_linux_auto_connect_scan()
	_cancel_auto_reconnect()
	_auto_reconnect_attempts = 0
	settings["enabled"] = false
	_save_settings()
	_debug_log("disconnect_device requested")
	if _square != null:
		_square.call("DisconnectFromDevice")
	if _garmin != null:
		_garmin.call("DisconnectFromDevice")
	_active_driver = ""


func _start_square_scan() -> void:
	if _square != null:
		_debug_log("Square start_scan requested")
		_square.call("StartScan")


func _stop_square_scan() -> void:
	if _square != null:
		_debug_log("Square stop_scan requested")
		_square.call("StopScan")


func _start_garmin_scan() -> void:
	if _garmin != null:
		_debug_log("Garmin start_scan requested")
		_garmin.call("StartScan")


func _stop_garmin_scan() -> void:
	if _garmin != null:
		_debug_log("Garmin stop_scan requested")
		_garmin.call("StopScan")


func set_enabled(value: bool) -> void:
	if not value:
		_cancel_linux_auto_connect_scan()
	settings["enabled"] = value
	_save_settings()


func set_club_code(club_code: String) -> void:
	settings["club_code"] = club_code
	_save_settings()
	if _square != null:
		_square.call("SetClub", club_code)
	emit_signal("club_code_changed", club_code)


func set_handedness(handedness: int) -> void:
	settings["handedness"] = handedness
	_save_settings()
	if _square != null:
		_square.call("SetHandedness", handedness)


var _pending_ready_ding := false


func is_ball_in_flight() -> bool:
	if _ready_hud != null and _ready_hud.has_method("is_ball_in_flight"):
		return bool(_ready_hud.call("is_ball_in_flight"))
	return false


func notify_shot_started() -> void:
	is_ready = false
	_pending_ready_ding = false
	if _ready_hud != null and _ready_hud.has_method("notify_shot_started"):
		_ready_hud.call("notify_shot_started")


func notify_ball_at_rest() -> void:
	if _ready_hud != null and _ready_hud.has_method("notify_ball_at_rest"):
		_ready_hud.call("notify_ball_at_rest")
	if is_ready and _pending_ready_ding:
		_pending_ready_ding = false
		play_ready_ding()
	_update_hud_display()


func set_ready() -> void:
	_debug_log("set_ready requested")
	if _active_driver == "garmin" and _garmin != null:
		_garmin.call("SetReady")
	elif _square != null:
		_square.call("SetReady")


func rearm() -> void:
	_debug_log("rearm requested")
	if _active_driver == "garmin" and _garmin != null:
		_garmin.call("SetReady")
	elif _square != null:
		_square.call("SetReady")


func calibrate_garmin_tilt() -> void:
	_debug_log("calibrate_garmin_tilt requested")
	if _garmin != null:
		_garmin.call("CalibrateTilt")


func _update_garmin_weather_config() -> void:
	if _garmin == null:
		return
	var temp := 72.0
	var alt := 0.0
	var tee := 7.0
	if has_node("/root/GlobalSettings"):
		var gs = get_node("/root/GlobalSettings")
		if gs.get("range_settings") != null:
			if "temperature" in gs.range_settings:
				temp = float(gs.range_settings.temperature.value)
			if "altitude" in gs.range_settings:
				alt = float(gs.range_settings.altitude.value)
	_debug_log("Sending shot config to Garmin R10: Temp=%.1f F, Alt=%.1f ft, Tee=%.1f ft" % [temp, alt, tee])
	_garmin.call("SetShotConfig", temp, alt, tee)


func _create_square_monitor() -> void:
	_square_init_error = ""
	_debug_log("Attempting to load script %s" % SQUARE_SCRIPT_PATH)
	var square_script := load(SQUARE_SCRIPT_PATH) as Script
	if square_script == null:
		_square_init_error = "Square script could not be loaded at %s." % SQUARE_SCRIPT_PATH
		_debug_error(_square_init_error)
		return

	if not square_script.can_instantiate():
		_square_init_error = "%s script is loaded but cannot instantiate." % SQUARE_CLASS_NAME
		_debug_error(_square_init_error)
		return

	_square = square_script.new() as Node
	if _square == null:
		_square_init_error = "%s could not be created from %s." % [SQUARE_CLASS_NAME, SQUARE_SCRIPT_PATH]
		_debug_error(_square_init_error)
		return

	add_child(_square)
	_debug_log("%s instantiated and signals connected." % SQUARE_CLASS_NAME)
	_square.connect("DeviceDiscovered", _on_square_device_discovered)
	_square.connect("StatusChanged", _on_square_status_changed)
	_square.connect("ErrorOccurred", _on_square_error_occurred)
	_square.connect("BatteryChanged", _on_square_battery_changed)
	_square.connect("FirmwareChanged", _on_square_firmware_changed)
	_square.connect("ReadyChanged", _on_square_ready_changed)
	if _square.has_signal("SensorDataReceived"):
		_square.connect("SensorDataReceived", _on_square_sensor_data_received)
	_square.connect("ShotReceived", _on_square_shot_received)


func _create_garmin_monitor() -> void:
	_garmin_init_error = ""
	_debug_log("Attempting to load script %s" % GARMIN_SCRIPT_PATH)
	var garmin_script := load(GARMIN_SCRIPT_PATH) as Script
	if garmin_script == null:
		_garmin_init_error = "Garmin script could not be loaded at %s." % GARMIN_SCRIPT_PATH
		_debug_error(_garmin_init_error)
		return

	if not garmin_script.can_instantiate():
		_garmin_init_error = "%s script is loaded but cannot instantiate." % GARMIN_CLASS_NAME
		_debug_error(_garmin_init_error)
		return

	_garmin = garmin_script.new() as Node
	if _garmin == null:
		_garmin_init_error = "%s could not be created from %s." % [GARMIN_CLASS_NAME, GARMIN_SCRIPT_PATH]
		_debug_error(_garmin_init_error)
		return

	add_child(_garmin)
	_debug_log("%s instantiated and signals connected." % GARMIN_CLASS_NAME)
	_garmin.connect("DeviceDiscovered", _on_garmin_device_discovered)
	_garmin.connect("StatusChanged", _on_garmin_status_changed)
	_garmin.connect("ErrorOccurred", _on_garmin_error_occurred)
	_garmin.connect("BatteryChanged", _on_garmin_battery_changed)
	_garmin.connect("FirmwareChanged", _on_garmin_firmware_changed)
	_garmin.connect("ReadyChanged", _on_garmin_ready_changed)
	_garmin.connect("ShotReceived", _on_garmin_shot_received)


func set_ball_placement_guide_enabled(enabled: bool) -> void:
	settings["ball_placement_guide_enabled"] = enabled
	_save_settings()
	_update_hud_display()


func _load_settings() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		return
	settings["enabled"] = bool(_config.get_value("square", "enabled", false))
	settings["device_id"] = str(_config.get_value("square", "device_id", ""))
	settings["device_name"] = str(_config.get_value("square", "device_name", ""))
	settings["device_type"] = str(_config.get_value("square", "device_type", "auto"))
	settings["club_code"] = str(_config.get_value("square", "club_code", DEFAULT_CLUB_CODE))
	settings["handedness"] = int(_config.get_value("square", "handedness", 0))
	settings["ready_ding_enabled"] = bool(_config.get_value("square", "ready_ding_enabled", true))
	settings["ready_indicator_enabled"] = bool(_config.get_value("square", "ready_indicator_enabled", true))
	settings["ball_placement_guide_enabled"] = bool(_config.get_value("square", "ball_placement_guide_enabled", true))


func _save_settings() -> void:
	_config.set_value("square", "enabled", bool(settings.get("enabled", false)))
	_config.set_value("square", "device_id", str(settings.get("device_id", "")))
	_config.set_value("square", "device_name", str(settings.get("device_name", "")))
	_config.set_value("square", "device_type", str(settings.get("device_type", "auto")))
	_config.set_value("square", "club_code", str(settings.get("club_code", DEFAULT_CLUB_CODE)))
	_config.set_value("square", "handedness", int(settings.get("handedness", 0)))
	_config.set_value("square", "ready_ding_enabled", bool(settings.get("ready_ding_enabled", true)))
	_config.set_value("square", "ready_indicator_enabled", bool(settings.get("ready_indicator_enabled", true)))
	_config.set_value("square", "ball_placement_guide_enabled", bool(settings.get("ball_placement_guide_enabled", true)))
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		_debug_error("Failed to save launch monitor settings file at %s" % SETTINGS_PATH)
		emit_signal("error_occurred", "Launch monitor settings could not be saved.")


func _on_square_device_discovered(device_id: String, name: String, rssi: int) -> void:
	if str(settings.get("device_type", "auto")) == "garmin":
		return
	if not is_square_device_name(name):
		return
	var is_new := not devices.has(device_id)
	devices[device_id] = {
		"name": name,
		"rssi": rssi,
		"type": "square"
	}
	if is_new:
		_debug_log("Square device discovered: %s (%s) RSSI=%d" % [name, device_id, rssi])
		if device_id == str(settings.get("device_id", "")):
			settings["device_name"] = name
			_save_settings()
		emit_signal("device_discovered", device_id, name, rssi)
		if _is_linux_auto_connect_match(device_id):
			_debug_log("saved Linux Square discovered; connecting automatically")
			connect_to_device(device_id, true)


func _on_garmin_device_discovered(device_id: String, name: String, rssi: int) -> void:
	if str(settings.get("device_type", "auto")) == "square":
		return
	var display_name := name if name.strip_edges() != "" else "Garmin Approach R10"
	var is_new := not devices.has(device_id)
	devices[device_id] = {
		"name": display_name,
		"rssi": rssi,
		"type": "garmin"
	}
	if is_new:
		_debug_log("Garmin device discovered: %s (%s) RSSI=%d" % [display_name, device_id, rssi])
		if device_id == str(settings.get("device_id", "")):
			settings["device_name"] = display_name
			_save_settings()
		emit_signal("device_discovered", device_id, display_name, rssi)
		if _is_linux_auto_connect_match(device_id):
			_debug_log("saved Linux Garmin discovered; connecting automatically")
			connect_to_device(device_id, true)


func _on_square_status_changed(value: String) -> void:
	_set_status(value)
	if value == "Disconnected" and bool(settings.get("enabled", false)) and str(settings.get("device_id", "")) != "" and _active_driver == "square":
		_schedule_auto_reconnect()
	elif value == "Connected" or value == "Connecting" or value == "Ready":
		_cancel_auto_reconnect()
		if value == "Connected":
			_auto_reconnect_attempts = 0


func _on_garmin_status_changed(value: String) -> void:
	_set_status(value)
	if value == "Disconnected" and bool(settings.get("enabled", false)) and str(settings.get("device_id", "")) != "" and _active_driver == "garmin":
		_schedule_auto_reconnect()
	elif value == "Connected" or value == "Connecting" or value == "Ready":
		_cancel_auto_reconnect()
		if value == "Connected":
			_auto_reconnect_attempts = 0


func _on_garmin_error_occurred(message: String) -> void:
	_debug_error("Garmin runtime error: %s" % message)
	_cancel_auto_reconnect()
	emit_signal("error_occurred", message)


func _on_garmin_battery_changed(level: int) -> void:
	_debug_log("Garmin battery changed: %d%%" % level)
	battery_level = level
	emit_signal("battery_changed", level)


func _on_garmin_firmware_changed(value: String) -> void:
	_debug_log("Garmin firmware changed: %s" % value)
	firmware = value
	emit_signal("firmware_changed", value)


func _on_garmin_ready_changed(value: bool) -> void:
	_debug_log("Garmin ready changed: %s" % str(value))
	var became_ready := value and not is_ready
	is_ready = value
	if became_ready:
		if is_ball_in_flight():
			_pending_ready_ding = true
		else:
			_pending_ready_ding = false
			play_ready_ding()
	elif not value:
		_pending_ready_ding = false
	emit_signal("ready_changed", value)
	_update_hud_display()


func _on_garmin_shot_received(data: Dictionary) -> void:
	_debug_log("Garmin shot received with %d fields" % data.size())
	FoamBallBoost.apply_boost(data, _current_club_name)
	notify_shot_started()
	emit_signal("hit_ball", data)
	_update_hud_display()


func _schedule_auto_reconnect() -> void:
	_cancel_auto_reconnect()
	if _auto_reconnect_attempts >= MAX_AUTO_RECONNECT_ATTEMPTS:
		_debug_log("Max auto-reconnect attempts (%d) reached. Stopping auto-reconnect." % MAX_AUTO_RECONNECT_ATTEMPTS)
		return
	_auto_reconnect_attempts += 1
	var delays := [3.0, 5.0, 8.0, 12.0, 18.0]
	var delay: float = delays[mini(_auto_reconnect_attempts - 1, delays.size() - 1)]
	_auto_reconnect_timer = Timer.new()
	_auto_reconnect_timer.one_shot = true
	_auto_reconnect_timer.wait_time = delay
	_auto_reconnect_timer.timeout.connect(_on_auto_reconnect_timeout)
	add_child(_auto_reconnect_timer)
	_auto_reconnect_timer.start()
	_debug_log("Auto-reconnect attempt %d/%d scheduled in %.1f seconds." % [
		_auto_reconnect_attempts, MAX_AUTO_RECONNECT_ATTEMPTS, delay
	])


func _on_auto_reconnect_timeout() -> void:
	_cancel_auto_reconnect()
	var dev_id := str(settings.get("device_id", ""))
	if bool(settings.get("enabled", false)) and dev_id != "" and status == "Disconnected":
		_debug_log("Attempting automatic reconnection to saved device %s" % dev_id)
		connect_to_device(dev_id, true)


func _cancel_auto_reconnect() -> void:
	if _auto_reconnect_timer != null:
		if _auto_reconnect_timer.timeout.is_connected(_on_auto_reconnect_timeout):
			_auto_reconnect_timer.timeout.disconnect(_on_auto_reconnect_timeout)
		_auto_reconnect_timer.stop()
		_auto_reconnect_timer.queue_free()
		_auto_reconnect_timer = null


func _on_square_error_occurred(message: String) -> void:
	var is_transient := _is_transient_square_connect_error(message)
	if not _is_manual_connect and is_transient:
		_debug_log("Square auto-connect suppressed error: %s" % message)
		return
	if is_transient:
		_debug_log("Square runtime warning: %s" % message)
	else:
		_debug_error("Square runtime error: %s" % message)
	emit_signal("error_occurred", message)


func _on_square_battery_changed(level: int) -> void:
	_debug_log("battery changed: %d%%" % level)
	battery_level = level
	emit_signal("battery_changed", level)


func _on_square_firmware_changed(value: String) -> void:
	_debug_log("firmware changed: %s" % value)
	firmware = value
	emit_signal("firmware_changed", value)


func _on_square_ready_changed(value: bool) -> void:
	_debug_log("ready changed: %s" % str(value))
	var became_ready := value and not is_ready
	is_ready = value
	if became_ready:
		if is_ball_in_flight():
			_pending_ready_ding = true
		else:
			_pending_ready_ding = false
			play_ready_ding()
	elif not value:
		_pending_ready_ding = false
	emit_signal("ready_changed", value)
	_update_hud_display()


func _on_square_sensor_data_received(pos_x: int, pos_y: int, pos_z: int, ready: bool, detected: bool) -> void:
	last_sensor_data = {
		"pos_x": pos_x,
		"pos_y": pos_y,
		"pos_z": pos_z,
		"ready": ready,
		"detected": detected
	}
	emit_signal("sensor_data_updated", pos_x, pos_y, pos_z, ready, detected)
	if _ready_hud != null and _ready_hud.has_method("set_sensor_position"):
		_ready_hud.call("set_sensor_position", pos_x, pos_y, pos_z, ready, detected)


func _on_square_shot_received(data: Dictionary) -> void:
	_debug_log("shot received with %d fields" % data.size())
	FoamBallBoost.apply_boost(data, _current_club_name)
	notify_shot_started()
	emit_signal("hit_ball", data)
	_update_hud_display()


func _missing_support_message() -> String:
	if _square_init_error != "":
		return "Square support is unavailable in this build. %s" % _square_init_error
	if _garmin_init_error != "":
		return "Garmin support is unavailable in this build. %s" % _garmin_init_error
	return "Launch monitor support is unavailable in this build."


func _connect_saved_device_on_startup(device_id: String) -> void:
	if device_id == "":
		return
	var saved_name := str(settings.get("device_name", ""))
	var saved_type := str(settings.get("device_type", "auto"))
	if saved_name == "":
		saved_name = "Square Golf" if saved_type != "garmin" else "Garmin Approach R10"
	if not devices.has(device_id):
		devices[device_id] = {
			"name": saved_name,
			"rssi": 0,
			"type": saved_type if saved_type != "auto" else detect_device_type(device_id, saved_name)
		}
	if OS.get_name() != "Linux":
		connect_to_device(device_id, true)
		return
	_start_linux_auto_connect_scan(device_id)


func _start_linux_auto_connect_scan(device_id: String) -> void:
	_cancel_linux_auto_connect_scan()
	var target_address := _normalize_bluetooth_address(device_id)
	if target_address == "":
		_debug_log("saved Linux Bluetooth id cannot be matched automatically")
		return
	_linux_auto_connect_active = true
	_linux_auto_connect_target_address = target_address
	_debug_log("starting saved Linux Square scan")
	_start_square_scan()
	_start_linux_auto_connect_timer()


func _start_linux_auto_connect_timer() -> void:
	_clear_linux_auto_connect_timer()
	_linux_auto_connect_timer = Timer.new()
	_linux_auto_connect_timer.one_shot = true
	_linux_auto_connect_timer.wait_time = LINUX_AUTO_CONNECT_SCAN_SECONDS
	_linux_auto_connect_timer.timeout.connect(_on_linux_auto_connect_timeout)
	add_child(_linux_auto_connect_timer)
	_linux_auto_connect_timer.start()


func _on_linux_auto_connect_timeout() -> void:
	if not _linux_auto_connect_active:
		return
	_debug_log("saved Linux Square was not found during startup scan")
	_linux_auto_connect_active = false
	_linux_auto_connect_target_address = ""
	_clear_linux_auto_connect_timer()
	_stop_square_scan()
	if status == "Scanning":
		_set_status("Disconnected")


func _cancel_linux_auto_connect_scan() -> void:
	_linux_auto_connect_active = false
	_linux_auto_connect_target_address = ""
	_clear_linux_auto_connect_timer()


func _clear_linux_auto_connect_timer() -> void:
	if _linux_auto_connect_timer == null:
		return
	if _linux_auto_connect_timer.timeout.is_connected(_on_linux_auto_connect_timeout):
		_linux_auto_connect_timer.timeout.disconnect(_on_linux_auto_connect_timeout)
	_linux_auto_connect_timer.stop()
	_linux_auto_connect_timer.queue_free()
	_linux_auto_connect_timer = null


func _is_linux_auto_connect_match(device_id: String) -> bool:
	if not _linux_auto_connect_active or _linux_auto_connect_target_address == "":
		return false
	return _normalize_bluetooth_address(device_id) == _linux_auto_connect_target_address


func _normalize_bluetooth_address(value: String) -> String:
	var normalized := value.strip_edges()
	if normalized == "":
		return ""
	var device_segment_index := normalized.rfind(BLUEZ_DEVICE_SEGMENT_PREFIX)
	if device_segment_index >= 0:
		normalized = normalized.substr(device_segment_index + BLUEZ_DEVICE_SEGMENT_PREFIX.length())
		var child_path_index := normalized.find("/")
		if child_path_index >= 0:
			normalized = normalized.substr(0, child_path_index)
	normalized = normalized.replace("-", ":").replace("_", ":").to_upper()
	if normalized.length() == 12 and not normalized.contains(":"):
		var parts := PackedStringArray()
		for index in range(0, normalized.length(), 2):
			parts.append(normalized.substr(index, 2))
		normalized = ":".join(parts)
	if not _is_bluetooth_address(normalized):
		return ""
	return normalized


func _is_bluetooth_address(value: String) -> bool:
	var parts := value.split(":")
	if parts.size() != 6:
		return false
	for part in parts:
		if part.length() != 2:
			return false
		for index in range(part.length()):
			if not _is_hex_digit_code(part.unicode_at(index)):
				return false
	return true


func _is_hex_digit_code(value: int) -> bool:
	return (value >= 48 and value <= 57) or (value >= 65 and value <= 70)


func _set_status(value: String) -> void:
	status = value
	emit_signal("status_changed", value)
	_debug_log("status -> %s" % value)
	_update_hud_display()


func _update_hud_display() -> void:
	if _ready_hud != null and _ready_hud.has_method("set_ready_status"):
		var hud_enabled := bool(settings.get("ready_indicator_enabled", true))
		var guide_enabled := bool(settings.get("ball_placement_guide_enabled", true))
		if _active_driver == "garmin":
			guide_enabled = false
		if _ready_hud.has_method("set_placement_guide_enabled"):
			_ready_hud.call("set_placement_guide_enabled", guide_enabled)
		_ready_hud.call("set_ready_status", is_ready, status, hud_enabled)


func _debug_log(message: String) -> void:
	print("%s %s" % [SQUARE_LOG_PREFIX, message])


func _debug_error(message: String) -> void:
	push_error("%s %s" % [SQUARE_LOG_PREFIX, message])


func _is_transient_square_connect_error(message: String) -> bool:
	var normalized := message.strip_edges().to_lower()
	for marker in TRANSIENT_CONNECT_ERROR_MARKERS:
		if normalized.contains(marker):
			return true
	return false


func _is_square_device_name(name: String) -> bool:
	return name.strip_edges().to_lower().begins_with(SQUARE_DEVICE_PREFIX)


func _on_club_selected(club_name: String) -> void:
	_current_club_name = club_name
	var code := _map_in_game_club_to_square_code(club_name)
	_debug_log("In-game club changed to %s (code: %s)" % [club_name, code])
	set_club_code(code)


func _map_in_game_club_to_square_code(club_name: String) -> String:
	match club_name:
		"Dr": return "0204"
		"3w": return "0305"
		"5w": return "0505"
		"2H", "3H", "4H", "1i", "2i", "3i": return "0305" # Fallback to 3 Wood/Hybrids
		"4i": return "0406"
		"5i": return "0506"
		"6i": return "0606"
		"7i": return "0706"
		"8i": return "0806"
		"9i": return "0906"
		"Pw": return "0a06"
		"Gw": return "0b06"
		"Sw": return "0c06"
		"Lw": return "0b06"
		"Pt": return "0107"
		_: return "0204" # Default to Driver
