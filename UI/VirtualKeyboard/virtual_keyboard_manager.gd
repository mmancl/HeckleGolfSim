extends Node
## VirtualKeyboardManager — Global Autoload for controller-driven text input.
##
## Automatically displays an on-screen console-style virtual keyboard whenever
## a player using a gamepad/controller focuses or opens any control expecting
## text input (e.g. Course Search/Download, Player Name, Camera/Network IP, etc.).

signal keyboard_opened(target_control: Control)
signal keyboard_closed

const VirtualKeyboardScript = preload("res://UI/VirtualKeyboard/virtual_keyboard.gd")

var _is_controller_mode: bool = false
var _keyboard: CanvasLayer = null
var _dismissed_control: Control = null
var _enabled: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Initial controller state: Start false so PC keyboard/mouse and mobile touchscreen
	# don't trigger the virtual keyboard until a controller is actively used.
	_is_controller_mode = false
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	# Create VirtualKeyboard instance
	_keyboard = VirtualKeyboardScript.new()
	_keyboard.name = "GlobalVirtualKeyboard"
	add_child(_keyboard)
	_keyboard.closing.connect(_on_keyboard_closing)
	_keyboard.closed.connect(_on_keyboard_closed)

	# Monitor GUI focus changes globally across the entire application
	var vp := get_viewport()
	if vp != null:
		vp.gui_focus_changed.connect(_on_gui_focus_changed)

	# Also monitor new modal dialogs entering the tree
	get_tree().node_added.connect(_on_node_added)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected:
		# If a controller was just connected, don't set active mode until user presses a button on it
		pass
	elif Input.get_connected_joypads().is_empty():
		_is_controller_mode = false
		if is_open():
			close(false)


# ── INPUT INTERCEPTION & CONTROLLER DETECTION ──────────────────────────

func _input(event: InputEvent) -> void:
	# Update active input mode
	if event is InputEventJoypadButton:
		_is_controller_mode = true
	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.35:
		_is_controller_mode = true
	elif event is InputEventKey:
		# Physical PC keyboard used: switch out of controller mode and dismiss virtual keyboard if open
		if _is_controller_mode:
			_is_controller_mode = false
			if is_open():
				close(false)
	elif event is InputEventMouseButton:
		# Mouse clicked: switch out of controller mode and dismiss virtual keyboard if open
		if _is_controller_mode:
			_is_controller_mode = false
			if is_open():
				close(false)
	elif event is InputEventScreenTouch or event is InputEventScreenDrag:
		# Mobile touchscreen tapped: switch out of controller mode so native mobile keyboard handles input
		if _is_controller_mode:
			_is_controller_mode = false
			if is_open():
				close(false)

	if not _enabled:
		return

	# If keyboard is already open, the keyboard itself handles inputs
	if is_open():
		return

	# Re-opening: If player on controller presses Joypad A on an already-focused LineEdit
	if is_controller_mode_active():
		var is_a_press = (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A)
		if is_a_press or (event.is_action_pressed("ui_accept") and (event is InputEventJoypadButton or event is InputEventJoypadMotion)):
			var vp := get_viewport()
			if vp != null:
				var cur_focus = vp.gui_get_focus_owner()
				if cur_focus != null and cur_focus is LineEdit and not (cur_focus.get_parent() is SpinBox):
					var le = cur_focus as LineEdit
					if le.editable and le.is_visible_in_tree():
						_dismissed_control = null
						open_for(le, true)
						vp.set_input_as_handled()
						return


var _last_close_time: int = 0


# ── FOCUS & MODAL DETECTION ────────────────────────────────────────────

func _on_gui_focus_changed(node: Control) -> void:
	if not _enabled or node == null:
		return

	# If keyboard is currently open or closing, don't react to focus changes inside the keyboard
	if is_open() or (_keyboard != null and is_instance_valid(_keyboard) and _keyboard.is_closing()):
		return

	# Reset dismissed control if focus moved to a different node
	if node != _dismissed_control:
		_dismissed_control = null
	else:
		return

	# If in controller mode, automatically pop open the virtual keyboard for any LineEdit
	if is_controller_mode_active():
		if node is LineEdit and not (node.get_parent() is SpinBox):
			var le = node as LineEdit
			if le.editable and le.is_visible_in_tree():
				call_deferred("open_for", le, false)


func _on_node_added(node: Node) -> void:
	if not _enabled or not is_controller_mode_active():
		return

	if node is Control or node is CanvasLayer:
		var n_name = node.name.to_lower()
		if n_name.contains("dialog") or n_name.contains("popup") or n_name.contains("modal"):
			call_deferred("_check_auto_focus_modal_input", node)


func _check_auto_focus_modal_input(modal_root: Node) -> void:
	if not is_instance_valid(modal_root) or not is_controller_mode_active():
		return

	# If the modal already has a focused control, let gui_focus_changed handle it
	var vp := get_viewport()
	if vp != null:
		var cur_focus = vp.gui_get_focus_owner()
		if cur_focus != null and modal_root.is_ancestor_of(cur_focus):
			return

	# Look for an editable LineEdit in the modal to focus
	var line_edit = _find_first_editable_line_edit(modal_root)
	if line_edit != null and line_edit.is_visible_in_tree():
		line_edit.grab_focus()


func _find_first_editable_line_edit(parent: Node) -> LineEdit:
	if parent is LineEdit and not (parent.get_parent() is SpinBox):
		var le = parent as LineEdit
		if le.editable and le.is_visible_in_tree():
			return le

	for child in parent.get_children():
		if child is Control and not (child as Control).is_visible_in_tree():
			continue
		var res = _find_first_editable_line_edit(child)
		if res != null:
			return res

	return null


# ── PUBLIC API ─────────────────────────────────────────────────────────

func open_for(target_control: Control, force: bool = false) -> void:
	if not _enabled or target_control == null or not is_instance_valid(target_control):
		return

	# If keyboard is already open for this exact control, do nothing
	if is_open() and _keyboard._target_control == target_control:
		return

	# Guard: If user closed/dismissed the keyboard on this control, DO NOT auto-reopen!
	# Only re-open if force is true (e.g. user explicitly pressed Joypad A or clicked it).
	if not force:
		if target_control == _dismissed_control:
			return
		if _keyboard != null and is_instance_valid(_keyboard) and _keyboard.is_closing():
			return
		if Time.get_ticks_msec() - _last_close_time < 300:
			return

	# If forcing or opening for a different control, clear dismissed control
	if force or target_control != _dismissed_control:
		_dismissed_control = null

	if _keyboard != null and is_instance_valid(_keyboard):
		_keyboard.open(target_control)
		emit_signal("keyboard_opened", target_control)


func close(restore_original: bool = false) -> void:
	if _keyboard != null and is_instance_valid(_keyboard):
		_keyboard.close(restore_original)


func is_open() -> bool:
	return _keyboard != null and is_instance_valid(_keyboard) and _keyboard.is_keyboard_open()


var _force_controller_mode: bool = false


func is_controller_mode() -> bool:
	return _is_controller_mode or _force_controller_mode


func is_controller_mode_active() -> bool:
	if not _enabled:
		return false
	if _force_controller_mode:
		return true
	# Active only if enabled, user is in controller mode, AND at least one joypad is physically/bluetooth connected.
	return _is_controller_mode and (Input.get_connected_joypads().size() > 0)


func is_controller_connected() -> bool:
	return Input.get_connected_joypads().size() > 0 or _force_controller_mode


func is_bluetooth_controller_detected() -> bool:
	if Input.get_connected_joypads().is_empty():
		return _force_controller_mode
	# Check joypad names for Bluetooth/Wireless indicators
	for id in Input.get_connected_joypads():
		var jname = Input.get_joy_name(id).to_lower()
		if jname.contains("wireless") or jname.contains("bluetooth") or jname.contains("bt") or jname.contains("dualshock") or jname.contains("dualsense") or jname.contains("joy-con") or jname.contains("pro controller"):
			return true
	# On mobile devices, any connected gamepad is paired via Bluetooth
	if OS.has_feature("mobile") and Input.get_connected_joypads().size() > 0:
		return true
	return Input.get_connected_joypads().size() > 0


func get_connected_controller_names() -> Array[String]:
	var result: Array[String] = []
	for id in Input.get_connected_joypads():
		var n = Input.get_joy_name(id)
		result.append(n if not n.is_empty() else "Controller %d" % id)
	return result


func set_controller_mode(active: bool) -> void:
	_is_controller_mode = active
	_force_controller_mode = active


func set_enabled(value: bool) -> void:
	_enabled = value
	if not _enabled and is_open():
		close(true)


func get_dismissed_control() -> Control:
	return _dismissed_control


func _on_keyboard_closing() -> void:
	if _keyboard != null and is_instance_valid(_keyboard):
		_dismissed_control = _keyboard._target_control
		_last_close_time = Time.get_ticks_msec()


func _on_keyboard_closed() -> void:
	if _keyboard != null and is_instance_valid(_keyboard):
		_dismissed_control = _keyboard._target_control
		_last_close_time = Time.get_ticks_msec()
	emit_signal("keyboard_closed")
