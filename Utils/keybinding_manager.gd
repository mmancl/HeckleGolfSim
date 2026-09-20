extends Node

signal keybindings_changed
signal controller_connection_changed(connected: bool, device_name: String)

# Categories for display in the Keybindings settings UI
const CATEGORY_GAMEPLAY := "Gameplay & Views"
const CATEGORY_AIM := "Aim Controls"
const CATEGORY_HUD := "HUD & Helpers"
const CATEGORY_STATS := "Individual Stat Toggles"

# Action definition structure:
# action_name: {
#   "label": String,
#   "category": String,
#   "default_key": Key,
#   "current_key": Key,
#   "default_joy": int,
#   "current_joy": int
# }
var _actions: Dictionary = {}

const SETTINGS_FILE := "user://global_settings.cfg"
const SETTINGS_SECTION := "keybindings"
const SETTINGS_CONTROLLER_SECTION := "controller_bindings"


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_init_action_definitions()
	load_keybindings()
	_apply_all_to_input_map()


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	var name_str = Input.get_joy_name(device_id) if connected else ""
	emit_signal("controller_connection_changed", connected, name_str)
	emit_signal("keybindings_changed")


func is_controller_connected() -> bool:
	return Input.get_connected_joypads().size() > 0


func get_connected_controller_name() -> String:
	var pads = Input.get_connected_joypads()
	if pads.is_empty():
		return ""
	var joy_name = Input.get_joy_name(pads[0])
	if joy_name.is_empty():
		return "Generic Controller"
	return joy_name


func get_all_connected_controller_names() -> Array[String]:
	var list: Array[String] = []
	for id in Input.get_connected_joypads():
		var n = Input.get_joy_name(id)
		list.append(n if not n.is_empty() else "Controller %d" % id)
	return list


func _init_action_definitions() -> void:
	_actions.clear()

	# --- Category 1: Gameplay & Views ---
	# Controller defaults:
	# Aerial Aim -> Y / Triangle
	# Mulligan -> Back / View / Select
	# Green Grid -> Start / Menu
	# Toggle Stats -> LS Click (L3)
	# Skip Flight -> A / Cross
	# Reset Shot -> B / Circle
	# Hit Shot -> X / Square
	# Next Club -> RB / R1
	# Prev Club -> LB / L1
	_register_def("aerial_aim", "Aerial Aim / Map View", CATEGORY_GAMEPLAY, KEY_A, JOY_BUTTON_Y)
	_register_def("mulligan", "Mulligan (Undo Last Shot)", CATEGORY_GAMEPLAY, KEY_M, JOY_BUTTON_BACK)
	_register_def("green_grid", "Toggle Green Slope Grid", CATEGORY_GAMEPLAY, KEY_G, JOY_BUTTON_START)
	_register_def("toggle_stats", "Toggle Stats Display Panel", CATEGORY_GAMEPLAY, KEY_S, JOY_BUTTON_LEFT_STICK)
	_register_def("skip_flight", "Skip Ball Flight", CATEGORY_GAMEPLAY, KEY_SPACE, JOY_BUTTON_A)
	_register_def("reset_shot", "Reset Ball / Next Shot", CATEGORY_GAMEPLAY, KEY_R, JOY_BUTTON_B)
	_register_def("hit_shot", "Manual Hit Shot", CATEGORY_GAMEPLAY, KEY_H, JOY_BUTTON_X)
	_register_def("next_club", "Next Club (Longer)", CATEGORY_GAMEPLAY, KEY_E, JOY_BUTTON_RIGHT_SHOULDER)
	_register_def("prev_club", "Previous Club (Shorter)", CATEGORY_GAMEPLAY, KEY_Q, JOY_BUTTON_LEFT_SHOULDER)
	_register_def("concede_hole", "Concede Hole (White Flag)", CATEGORY_GAMEPLAY, KEY_F, -1)

	# --- Category 2: Aim Controls ---
	# Controller defaults: D-Pad directions
	_register_def("aim_left", "Aim Left (Rotate Counter-Clockwise)", CATEGORY_AIM, KEY_LEFT, JOY_BUTTON_DPAD_LEFT)
	_register_def("aim_right", "Aim Right (Rotate Clockwise)", CATEGORY_AIM, KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_register_def("aim_forward", "Aim Forward (Increase Target Distance)", CATEGORY_AIM, KEY_UP, JOY_BUTTON_DPAD_UP)
	_register_def("aim_backward", "Aim Backward (Decrease Target Distance)", CATEGORY_AIM, KEY_DOWN, JOY_BUTTON_DPAD_DOWN)

	# --- Category 3: HUD & Helpers ---
	_register_def("toggle_helpers", "Toggle Helper Buttons Panel", CATEGORY_HUD, KEY_Z, JOY_BUTTON_RIGHT_STICK)
	_register_def("announcer_toggle", "Announcer Mute / Unmute", CATEGORY_HUD, KEY_N, -1)
	_register_def("suspense_toggle", "Suspense Heartbeat Toggle", CATEGORY_HUD, KEY_U, -1)
	_register_def("golfer_cam_toggle", "Golfer Camera Toggle", CATEGORY_HUD, KEY_C, -1)
	_register_def("putting_cam_toggle", "Putting Camera Toggle", CATEGORY_HUD, KEY_P, -1)
	_register_def("shot_analysis_toggle", "Shot Analysis Toggle", CATEGORY_HUD, KEY_Y, -1)
	_register_def("distance_menu_toggle", "Hit Distance Menu", CATEGORY_HUD, KEY_D, -1)

	# --- Category 4: Individual Stat Toggles ---
	# Defaults assigned across number row and function keys for quick access
	var stat_default_keys: Dictionary = {
		"Distance": KEY_1,
		"Carry": KEY_2,
		"Speed": KEY_3,
		"VLA": KEY_4,
		"HLA": KEY_5,
		"BackSpin": KEY_6,
		"SideSpin": KEY_7,
		"TotalSpin": KEY_8,
		"SpinAxis": KEY_9,
		"Apex": KEY_0,
		"Offline": KEY_MINUS,
		"FaceAngle": KEY_EQUAL,
		"ClubPath": KEY_F1,
		"FaceToPath": KEY_F2,
		"AttackAngle": KEY_F3,
		"DynamicLoft": KEY_F4,
		"ClubSpeed": KEY_F5,
		"SmashFactor": KEY_F6,
		"HangTime": KEY_F7,
		"DescentAngle": KEY_F8
	}

	for stat in StatDefinitions.STATS:
		var stat_id = str(stat.get("id", ""))
		var stat_name = str(stat.get("name", stat_id))
		var def_key = stat_default_keys.get(stat_id, KEY_NONE) as Key
		_register_def("stat_toggle_" + stat_id, "Stat: " + stat_name, CATEGORY_STATS, def_key, -1)


func _register_def(action_name: String, label: String, category: String, default_key: Key, default_joy: int = -1) -> void:
	_actions[action_name] = {
		"label": label,
		"category": category,
		"default_key": default_key,
		"current_key": default_key,
		"default_joy": default_joy,
		"current_joy": default_joy
	}


func get_all_actions() -> Dictionary:
	return _actions


func get_categories() -> Array[String]:
	return [CATEGORY_GAMEPLAY, CATEGORY_AIM, CATEGORY_HUD, CATEGORY_STATS]


func get_actions_in_category(cat: String) -> Array[String]:
	var list: Array[String] = []
	for act_name in _actions.keys():
		if _actions[act_name]["category"] == cat:
			list.append(act_name)
	return list


func get_action_label(action_name: String) -> String:
	if _actions.has(action_name):
		return _actions[action_name]["label"]
	return action_name


func get_action_keycode(action_name: String) -> Key:
	if _actions.has(action_name):
		return _actions[action_name]["current_key"]
	return KEY_NONE


func get_action_default_keycode(action_name: String) -> Key:
	if _actions.has(action_name):
		return _actions[action_name]["default_key"]
	return KEY_NONE


func get_action_key_name(action_name: String) -> String:
	var code = get_action_keycode(action_name)
	return get_key_display_name(code)


func get_action_joy_button(action_name: String) -> int:
	if _actions.has(action_name):
		return _actions[action_name].get("current_joy", -1)
	return -1


func get_action_default_joy_button(action_name: String) -> int:
	if _actions.has(action_name):
		return _actions[action_name].get("default_joy", -1)
	return -1


func get_action_joy_button_name(action_name: String) -> String:
	var btn = get_action_joy_button(action_name)
	return get_joy_button_display_name(btn)


func get_action_summary_str(action_name: String) -> String:
	var k_name = get_action_key_name(action_name)
	var j_name = get_action_joy_button_name(action_name)
	if k_name != "None" and j_name != "None":
		return "%s / %s" % [k_name, j_name]
	elif k_name != "None":
		return k_name
	elif j_name != "None":
		return j_name
	return "None"


static func get_key_display_name(code: Key) -> String:
	if code == KEY_NONE or code == 0:
		return "None"
	match code:
		KEY_LEFT:
			return "Left Arrow"
		KEY_RIGHT:
			return "Right Arrow"
		KEY_UP:
			return "Up Arrow"
		KEY_DOWN:
			return "Down Arrow"
		KEY_SPACE:
			return "Space"
		KEY_ENTER:
			return "Enter"
		KEY_ESCAPE:
			return "Escape"
		KEY_TAB:
			return "Tab"
		KEY_MINUS:
			return "-"
		KEY_EQUAL:
			return "="
		KEY_BRACKETLEFT:
			return "["
		KEY_BRACKETRIGHT:
			return "]"
		KEY_SEMICOLON:
			return ";"
		KEY_APOSTROPHE:
			return "'"
		KEY_COMMA:
			return ","
		KEY_PERIOD:
			return "."
		KEY_SLASH:
			return "/"
		KEY_BACKSLASH:
			return "\\"
		_:
			var s = OS.get_keycode_string(code)
			if s.is_empty():
				return "Key " + str(int(code))
			return s


static func get_joy_button_display_name(btn: int) -> String:
	if btn < 0 or btn == JOY_BUTTON_INVALID:
		return "None"
	match btn:
		JOY_BUTTON_A:
			return "Xbox A / Cross"
		JOY_BUTTON_B:
			return "Xbox B / Circle"
		JOY_BUTTON_X:
			return "Xbox X / Square"
		JOY_BUTTON_Y:
			return "Xbox Y / Triangle"
		JOY_BUTTON_BACK:
			return "View (Back)"
		JOY_BUTTON_START:
			return "Menu (Start)"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB (L1)"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB (R1)"
		JOY_BUTTON_LEFT_STICK:
			return "LS Click (L3)"
		JOY_BUTTON_RIGHT_STICK:
			return "RS Click (R3)"
		JOY_BUTTON_DPAD_UP:
			return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-Pad Right"
		JOY_BUTTON_GUIDE:
			return "Guide / Xbox"
		JOY_BUTTON_MISC1:
			return "Share / Mic"
		JOY_BUTTON_PADDLE1:
			return "Paddle 1"
		JOY_BUTTON_PADDLE2:
			return "Paddle 2"
		JOY_BUTTON_PADDLE3:
			return "Paddle 3"
		JOY_BUTTON_PADDLE4:
			return "Paddle 4"
		JOY_BUTTON_TOUCHPAD:
			return "Touchpad"
		_:
			return "Button " + str(btn)


func rebind_key(action_name: String, new_keycode: Key) -> void:
	if not _actions.has(action_name):
		return

	_actions[action_name]["current_key"] = new_keycode
	_apply_action_to_input_map(action_name)
	save_keybindings()
	emit_signal("keybindings_changed")


func rebind_joy_button(action_name: String, new_button: int) -> void:
	if not _actions.has(action_name):
		return

	_actions[action_name]["current_joy"] = new_button
	_apply_action_to_input_map(action_name)
	save_keybindings()
	emit_signal("keybindings_changed")


func rebind_action(action_name: String, new_keycode: Key) -> void:
	rebind_key(action_name, new_keycode)


func reset_to_defaults() -> void:
	for action_name in _actions.keys():
		var def_key = _actions[action_name]["default_key"] as Key
		var def_joy = _actions[action_name].get("default_joy", -1) as int
		_actions[action_name]["current_key"] = def_key
		_actions[action_name]["current_joy"] = def_joy
		_apply_action_to_input_map(action_name)
	save_keybindings()
	emit_signal("keybindings_changed")


func reset_keys_to_defaults() -> void:
	for action_name in _actions.keys():
		var def_key = _actions[action_name]["default_key"] as Key
		_actions[action_name]["current_key"] = def_key
		_apply_action_to_input_map(action_name)
	save_keybindings()
	emit_signal("keybindings_changed")


func reset_joy_to_defaults() -> void:
	for action_name in _actions.keys():
		var def_joy = _actions[action_name].get("default_joy", -1) as int
		_actions[action_name]["current_joy"] = def_joy
		_apply_action_to_input_map(action_name)
	save_keybindings()
	emit_signal("keybindings_changed")


func _apply_action_to_input_map(action_name: String) -> void:
	var s_name = StringName(action_name)
	if not InputMap.has_action(s_name):
		InputMap.add_action(s_name)
	else:
		InputMap.action_erase_events(s_name)

	var keycode = _actions[action_name].get("current_key", KEY_NONE) as Key
	if keycode != KEY_NONE and keycode != 0:
		var ev = InputEventKey.new()
		ev.physical_keycode = keycode
		ev.keycode = keycode
		InputMap.action_add_event(s_name, ev)

	var joy_btn = _actions[action_name].get("current_joy", -1) as int
	if joy_btn >= 0 and joy_btn != JOY_BUTTON_INVALID:
		var joy_ev = InputEventJoypadButton.new()
		joy_ev.button_index = joy_btn as JoyButton
		InputMap.action_add_event(s_name, joy_ev)


func _apply_all_to_input_map() -> void:
	for action_name in _actions.keys():
		_apply_action_to_input_map(action_name)


func load_keybindings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	if err != OK:
		return

	if config.has_section(SETTINGS_SECTION):
		for action_name in _actions.keys():
			if config.has_section_key(SETTINGS_SECTION, action_name):
				var saved_val = config.get_value(SETTINGS_SECTION, action_name)
				if saved_val is int:
					_actions[action_name]["current_key"] = saved_val as Key

	if config.has_section(SETTINGS_CONTROLLER_SECTION):
		for action_name in _actions.keys():
			if config.has_section_key(SETTINGS_CONTROLLER_SECTION, action_name):
				var saved_joy = config.get_value(SETTINGS_CONTROLLER_SECTION, action_name)
				if saved_joy is int:
					_actions[action_name]["current_joy"] = saved_joy


func save_keybindings() -> void:
	var config = ConfigFile.new()
	# Load existing file first to preserve other sections
	config.load(SETTINGS_FILE)

	for action_name in _actions.keys():
		var code = _actions[action_name]["current_key"] as int
		config.set_value(SETTINGS_SECTION, action_name, code)
		var joy = _actions[action_name].get("current_joy", -1) as int
		config.set_value(SETTINGS_CONTROLLER_SECTION, action_name, joy)

	var err = config.save(SETTINGS_FILE)
	if err != OK:
		push_error("Failed to save keybindings to %s: %d" % [SETTINGS_FILE, err])


func toggle_stat(stat_id: String) -> void:
	if not has_node("/root/GlobalSettings"):
		return
	var gs = get_node("/root/GlobalSettings")
	if not ("range_settings" in gs) or gs.range_settings == null:
		return

	var active_stats: Array = gs.range_settings.displayed_stats.value.duplicate()
	if active_stats.has(stat_id):
		active_stats.erase(stat_id)
	else:
		if active_stats.size() >= StatDefinitions.MAX_DISPLAYED_STATS:
			return
		active_stats.append(stat_id)

	gs.range_settings.displayed_stats.set_value(active_stats)
	gs.save_settings()


func get_conflict_key_action(keycode: Key, except_action: String = "") -> String:
	if keycode == KEY_NONE or keycode == 0:
		return ""
	for act in _actions.keys():
		if act == except_action:
			continue
		if _actions[act]["current_key"] == keycode:
			return act
	return ""


func get_conflict_action(keycode: Key, except_action: String = "") -> String:
	return get_conflict_key_action(keycode, except_action)


func get_conflict_joy_action(button_index: int, except_action: String = "") -> String:
	if button_index < 0 or button_index == JOY_BUTTON_INVALID:
		return ""
	for act in _actions.keys():
		if act == except_action:
			continue
		if _actions[act].get("current_joy", -1) == button_index:
			return act
	return ""
