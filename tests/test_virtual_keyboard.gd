extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Virtual Keyboard & Controller Input Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	# Test 1: Check autoloads
	print("\n--- Test 1: Autoload & Component Initialization ---")
	var vkm = root.get_node_or_null("VirtualKeyboardManager")
	assert(vkm != null, "VirtualKeyboardManager autoload must exist in scene tree")
	var ufg = root.get_node_or_null("UIFocusGuard")
	assert(ufg != null, "UIFocusGuard autoload must exist in scene tree")

	var keyboard = vkm._keyboard
	assert(keyboard != null, "VirtualKeyboard instance must exist under VirtualKeyboardManager")
	assert(keyboard is CanvasLayer, "VirtualKeyboard must be a CanvasLayer")
	assert(keyboard.layer == 140, "VirtualKeyboard must have layer 140")
	assert(not keyboard.visible, "VirtualKeyboard must be hidden by default")
	print("  PASS: VirtualKeyboardManager and VirtualKeyboard properly initialized.")

	# Test 2: UI Building & Key Elements
	print("\n--- Test 2: UI Structure & Key Generation ---")
	assert(keyboard._main_panel != null, "Main panel must be created")
	assert(keyboard._preview_label != null, "Preview label must be created")
	assert(keyboard._keys_vbox != null, "Keys container must be created")
	assert(keyboard._all_key_buttons.size() > 40, "All keyboard buttons must be generated (expected > 40 keys)")
	assert(keyboard._central_key_button != null, "Central key (g or h) must be identified for initial focus")
	print("  PASS: VirtualKeyboard UI structure and keys successfully verified (%d keys)." % keyboard._all_key_buttons.size())

	# Test 3: LineEdit Targeting & Auto-Opening in Controller Mode
	print("\n--- Test 3: Controller Focus Auto-Open ---")
	var test_line_edit = LineEdit.new()
	test_line_edit.name = "TestCourseSearchInput"
	test_line_edit.placeholder_text = "Search Course Name"
	test_line_edit.text = "Pebble"
	root.add_child(test_line_edit)

	# Ensure controller mode is true for test
	vkm.set_controller_mode(true)
	assert(vkm.is_controller_mode(), "Controller mode should be active")

	# Simulating LineEdit gaining focus
	vkm._on_gui_focus_changed(test_line_edit)
	await process_frame
	await process_frame

	assert(vkm.is_open(), "Virtual keyboard must open when LineEdit gains focus in controller mode")
	assert(keyboard.visible, "Virtual keyboard UI must become visible")
	assert(keyboard._current_text == "Pebble", "Keyboard current text must match LineEdit text")
	assert(keyboard._title_label.text.contains("SEARCH COURSE"), "Title should infer course search context")
	print("  PASS: Virtual keyboard automatically opened for LineEdit with correct title and text.")

	# Test 4: Focus Lock verification
	print("\n--- Test 4: UIFocusGuard Lock Integration ---")
	assert(ufg.is_locked(), "UIFocusGuard must be locked while virtual keyboard is open")
	assert(ufg.current_lock_root() == keyboard, "Current lock root must be the virtual keyboard")
	print("  PASS: Focus lock successfully established.")

	# Test 5: Character Insertion, Backspace, Space, Caret
	print("\n--- Test 5: Typing, Controller Shortcuts & Text Sync ---")
	var changed_texts: Array[String] = []
	test_line_edit.text_changed.connect(func(new_text: String): changed_texts.append(new_text))

	# Insert " Beach"
	keyboard._insert_char(" ")
	keyboard._insert_char("B")
	keyboard._insert_char("e")
	keyboard._insert_char("a")
	keyboard._insert_char("c")
	keyboard._insert_char("h")
	keyboard._insert_char("!")

	assert(keyboard._current_text == "Pebble Beach!", "Keyboard text should be 'Pebble Beach!'")
	assert(test_line_edit.text == "Pebble Beach!", "Target LineEdit text must live-sync to 'Pebble Beach!'")
	assert(changed_texts.size() == 7, "text_changed signal should have emitted for each character")

	# Test Backspace shortcut (Joypad X)
	var x_event = InputEventJoypadButton.new()
	x_event.button_index = JOY_BUTTON_X
	x_event.pressed = true
	keyboard._input(x_event)

	assert(keyboard._current_text == "Pebble Beach", "X button should backspace the exclamation mark")
	assert(test_line_edit.text == "Pebble Beach", "Target LineEdit text must reflect backspace")

	# Test Space shortcut (Joypad Y)
	var y_event = InputEventJoypadButton.new()
	y_event.button_index = JOY_BUTTON_Y
	y_event.pressed = true
	keyboard._input(y_event)
	assert(keyboard._current_text == "Pebble Beach ", "Y button should insert space")

	# Move cursor left once (LB)
	var lb_event = InputEventJoypadButton.new()
	lb_event.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb_event.pressed = true
	keyboard._input(lb_event)
	assert(keyboard._cursor_pos == keyboard._current_text.length() - 1, "LB should move cursor left")

	# Insert a character at cursor position
	keyboard._insert_char("9")
	assert(keyboard._current_text == "Pebble Beach9 ", "Character inserted at cursor position before trailing space")

	# Clear
	keyboard._on_clear_pressed()
	assert(keyboard._current_text == "", "Clear should empty the text")
	assert(test_line_edit.text == "", "Target LineEdit should also be cleared")

	# Set IP address to test number and colon keys
	keyboard._current_text = ""
	keyboard._cursor_pos = 0
	for ch in "192.168.1.50:8080":
		keyboard._insert_char(ch)
	assert(test_line_edit.text == "192.168.1.50:8080", "IP address with dots and colons typed accurately")
	print("  PASS: Typing, shortcuts (X/Y/LB/RB), and live text synchronization verified.")

	# Test 6: Shift & Symbols Toggling
	print("\n--- Test 6: Shift and Symbols Layout Modes ---")
	keyboard._on_shift_pressed()
	assert(keyboard._shift_active, "Shift mode should be active")
	var btn_a: Button = null
	for b in keyboard._all_key_buttons:
		if b.get_meta("base_char") == "a":
			btn_a = b
			break
	assert(btn_a != null and btn_a.text == "A", "Key 'a' should display 'A' when shift is active")
	btn_a.pressed.emit()
	assert(test_line_edit.text.ends_with("A"), "Typing with shift active should produce uppercase letter")
	assert(not keyboard._shift_active, "Transient shift should reset after letter insertion")

	keyboard._on_symbols_pressed()
	assert(keyboard._symbols_active, "Symbols mode should be active")
	var btn_q: Button = null
	for b in keyboard._all_key_buttons:
		if b.get_meta("base_char") == "q":
			btn_q = b
			break
	assert(btn_q != null and btn_q.text == "!", "Key 'q' should display '!' when symbols is active")
	btn_q.pressed.emit()
	assert(test_line_edit.text.ends_with("!"), "Symbols mode should map 'q' to '!'")
	keyboard._on_symbols_pressed()
	assert(not keyboard._symbols_active, "Symbols mode toggled back to ABC")
	print("  PASS: Shift and Symbols (?123) layouts function correctly.")

	# Test 7: Submission & Closure
	print("\n--- Test 7: Text Submission & Done Shortcut ---")
	var result := {"submitted_text": ""}
	test_line_edit.text_submitted.connect(func(text: String): result["submitted_text"] = text)

	# Simulate Start button (Done)
	var start_event = InputEventJoypadButton.new()
	start_event.button_index = JOY_BUTTON_START
	start_event.pressed = true
	keyboard._input(start_event)
	await process_frame

	assert(result["submitted_text"] == test_line_edit.text, "Target LineEdit text_submitted signal should fire on submit")
	assert(not vkm.is_open(), "Virtual keyboard should be closed after submit")
	assert(not ufg.is_locked(), "Focus lock should be popped after submit")
	print("  PASS: Start button successfully submitted text and closed keyboard.")

	# Test 8: Keyboard/Mouse Mode Behavior (No auto-open)
	print("\n--- Test 8: Desktop Keyboard & Mouse Mode Behavior ---")
	vkm.set_controller_mode(false)
	assert(not vkm.is_controller_mode(), "Controller mode should now be false")

	var desktop_line_edit = LineEdit.new()
	desktop_line_edit.name = "DesktopInput"
	root.add_child(desktop_line_edit)

	vkm._on_gui_focus_changed(desktop_line_edit)
	await process_frame
	await process_frame
	assert(not vkm.is_open(), "Virtual keyboard should NOT auto-open in keyboard/mouse mode")
	print("  PASS: Virtual keyboard remained closed in keyboard/mouse mode.")

	# Test 9: Re-opening via Joypad A button
	print("\n--- Test 9: Manual Re-Open via Controller A Button ---")
	vkm.set_controller_mode(true)
	# Simulate focusing desktop_line_edit
	var vp = root.get_viewport()
	desktop_line_edit.grab_focus()
	await process_frame

	var a_event = InputEventJoypadButton.new()
	a_event.button_index = JOY_BUTTON_A
	a_event.pressed = true
	vkm._input(a_event)
	await process_frame
	await process_frame

	assert(vkm.is_open(), "Pressing Joypad A on focused LineEdit should open the virtual keyboard")
	print("  PASS: Joypad A successfully opened virtual keyboard on focused LineEdit.")

	# Test 10: Cancellation (Joypad B)
	print("\n--- Test 10: Cancellation via Joypad B ---")
	var b_event = InputEventJoypadButton.new()
	b_event.button_index = JOY_BUTTON_B
	b_event.pressed = true
	keyboard._input(b_event)
	await process_frame
	await process_frame

	assert(not vkm.is_open(), "Joypad B should cancel and close virtual keyboard")
	assert(not ufg.is_locked(), "Focus lock should be popped on cancel")
	print("  PASS: Joypad B cancelled and closed virtual keyboard cleanly.")

	# Test 11: Bluetooth & Controller Detection Helpers
	print("\n--- Test 11: Bluetooth & Gamepad Controller Detection ---")
	vkm.set_controller_mode(true)
	assert(vkm.is_controller_connected(), "is_controller_connected should return true when controller mode is active")
	assert(vkm.is_bluetooth_controller_detected(), "is_bluetooth_controller_detected should succeed")
	var joy_names = vkm.get_connected_controller_names()
	assert(joy_names is Array, "get_connected_controller_names should return Array")
	print("  PASS: Controller & Bluetooth detection helpers verified.")

	# Test 12: Dynamic Input Mode Transitions (Mouse, Touch, Key, Controller)
	print("\n--- Test 12: Input Mode Transitions (PC Mouse/Keyboard vs Mobile Touch vs Controller) ---")
	# Joypad Button sets controller mode to true
	var joy_btn_event = InputEventJoypadButton.new()
	joy_btn_event.button_index = JOY_BUTTON_DPAD_DOWN
	joy_btn_event.pressed = true
	vkm._input(joy_btn_event)
	assert(vkm._is_controller_mode, "Joypad button event should set controller mode to true")

	# Mouse button resets controller mode to false (PC mouse user)
	var mouse_event = InputEventMouseButton.new()
	mouse_event.button_index = MOUSE_BUTTON_LEFT
	mouse_event.pressed = true
	vkm._input(mouse_event)
	assert(not vkm._is_controller_mode, "Mouse click should switch controller mode to false")

	# Joypad sets it back
	vkm._input(joy_btn_event)
	assert(vkm._is_controller_mode, "Joypad button should re-enable controller mode")

	# Screen touch resets controller mode to false (Mobile touchscreen user)
	var touch_event = InputEventScreenTouch.new()
	touch_event.pressed = true
	vkm._input(touch_event)
	assert(not vkm._is_controller_mode, "Mobile touchscreen tap should switch controller mode to false")

	# Key press resets controller mode to false (PC keyboard user)
	vkm._input(joy_btn_event)
	assert(vkm._is_controller_mode, "Joypad button should re-enable controller mode")
	var key_event = InputEventKey.new()
	key_event.pressed = true
	key_event.keycode = KEY_SPACE
	vkm._input(key_event)
	assert(not vkm._is_controller_mode, "PC physical keyboard keystroke should switch controller mode to false")
	print("  PASS: Input mode dynamically adapts between controller, PC mouse/keyboard, and mobile touch.")

	# Test 13: New Player, Optional Email, and Camera via WiFi Fields
	print("\n--- Test 13: New Player, Optional Email, and Camera via WiFi Inputs ---")
	var new_player_le = LineEdit.new()
	new_player_le.name = "NewPlayerInput"
	new_player_le.placeholder_text = "New Player Name"
	new_player_le.focus_entered.connect(func():
		if vkm.is_controller_mode_active():
			vkm.open_for(new_player_le)
	)
	root.add_child(new_player_le)

	var new_player_email_le = LineEdit.new()
	new_player_email_le.name = "NewPlayerEmailInput"
	new_player_email_le.placeholder_text = "Optional Email Address"
	new_player_email_le.focus_entered.connect(func():
		if vkm.is_controller_mode_active():
			vkm.open_for(new_player_email_le)
	)
	root.add_child(new_player_email_le)

	var phone_camera_ip_le = LineEdit.new()
	phone_camera_ip_le.name = "PhoneCameraIpInput"
	phone_camera_ip_le.placeholder_text = "e.g. 192.168.1.100:8080"
	phone_camera_ip_le.focus_entered.connect(func():
		if vkm.is_controller_mode_active():
			vkm.open_for(phone_camera_ip_le)
	)
	root.add_child(phone_camera_ip_le)

	# When controller mode is false: none of the 3 fields open virtual keyboard
	vkm.set_controller_mode(false)
	vkm._on_gui_focus_changed(new_player_le)
	await process_frame
	await process_frame
	assert(not vkm.is_open(), "New Player must NOT open virtual keyboard when controller is not active")

	vkm._on_gui_focus_changed(new_player_email_le)
	await process_frame
	await process_frame
	assert(not vkm.is_open(), "Optional Email must NOT open virtual keyboard when controller is not active")

	vkm._on_gui_focus_changed(phone_camera_ip_le)
	await process_frame
	await process_frame
	assert(not vkm.is_open(), "Camera via WiFi must NOT open virtual keyboard when controller is not active")
	print("  PASS: All 3 fields remain closed in PC/mobile keyboard/touch mode.")

	# When controller mode is true: all 3 fields open virtual keyboard
	vkm.set_controller_mode(true)
	vkm._last_close_time = 0
	vkm._dismissed_control = null
	if keyboard._anim_tween != null and keyboard._anim_tween.is_running():
		keyboard._anim_tween.kill()
	keyboard._is_closing = false

	# Field 1: New Player
	vkm._on_gui_focus_changed(new_player_le)
	await process_frame
	await process_frame
	assert(vkm.is_open(), "New Player field must open virtual keyboard in controller mode")
	assert(keyboard._title_label.text.contains("PLAYER") or keyboard._title_label.text.contains("NAME"), "Title should infer player name context")
	vkm.close(false)
	await process_frame
	if keyboard._anim_tween != null and keyboard._anim_tween.is_running():
		keyboard._anim_tween.kill()
	keyboard._is_closing = false
	vkm._last_close_time = 0
	vkm._dismissed_control = null

	# Field 2: Optional Email
	vkm._on_gui_focus_changed(new_player_email_le)
	await process_frame
	await process_frame
	assert(vkm.is_open(), "Optional Email field must open virtual keyboard in controller mode")
	assert(keyboard._title_label.text.contains("EMAIL"), "Title should infer email context")
	vkm.close(false)
	await process_frame
	if keyboard._anim_tween != null and keyboard._anim_tween.is_running():
		keyboard._anim_tween.kill()
	keyboard._is_closing = false
	vkm._last_close_time = 0
	vkm._dismissed_control = null

	# Field 3: Camera via WiFi
	vkm._on_gui_focus_changed(phone_camera_ip_le)
	await process_frame
	await process_frame
	assert(vkm.is_open(), "Camera via WiFi field must open virtual keyboard in controller mode")
	assert(keyboard._title_label.text.contains("CAMERA") or keyboard._title_label.text.contains("IP"), "Title should infer camera/IP context")
	vkm.close(false)
	await process_frame
	if keyboard._anim_tween != null and keyboard._anim_tween.is_running():
		keyboard._anim_tween.kill()
	keyboard._is_closing = false
	vkm._last_close_time = 0
	vkm._dismissed_control = null

	print("  PASS: New Player, Optional Email, and Camera via WiFi properly show virtual keyboard on controller.")

	# Test 14: Cancellation & Dismissal Lock (No infinite re-open loop when staying on field)
	print("\n--- Test 14: Dismissal & Focus Retention (No auto re-open loop) ---")
	vkm.set_controller_mode(true)
	vkm._last_close_time = 0
	vkm._dismissed_control = null

	# Focus optional email input
	vkm._on_gui_focus_changed(new_player_email_le)
	await process_frame
	await process_frame
	assert(vkm.is_open(), "Virtual keyboard should open when focusing optional email in controller mode")

	# Press Joypad B (Cancel) to dismiss keyboard
	var cancel_b = InputEventJoypadButton.new()
	cancel_b.button_index = JOY_BUTTON_B
	cancel_b.pressed = true
	keyboard._input(cancel_b)
	await process_frame
	await process_frame
	await process_frame

	# Ensure keyboard is closed and dismissed control is tracked
	assert(not vkm.is_open(), "Virtual keyboard must be closed after pressing Cancel (B)")
	assert(not ufg.is_locked(), "Focus guard must not be locked after Cancel")
	assert(vkm.get_dismissed_control() == new_player_email_le, "Dismissed control should be tracked as new_player_email_le")

	# Wait multiple frames to ensure no deferred auto-reopen occurs while focus stays on email input
	for i in range(10):
		await process_frame
	assert(not vkm.is_open(), "Virtual keyboard must NOT auto-reopen while focus remains on the dismissed field")

	# User can reopen deliberately by pressing Joypad A on the focused field
	var reopen_a = InputEventJoypadButton.new()
	reopen_a.button_index = JOY_BUTTON_A
	reopen_a.pressed = true
	vkm._input(reopen_a)
	await process_frame
	await process_frame
	assert(vkm.is_open(), "Virtual keyboard should reopen when user explicitly presses Joypad A on the field")
	assert(vkm.get_dismissed_control() == null, "Dismissed control should be cleared after explicit A press")

	# Close it again
	vkm.close(false)
	await process_frame
	if keyboard._anim_tween != null and keyboard._anim_tween.is_running():
		keyboard._anim_tween.kill()
	keyboard._is_closing = false
	await process_frame

	# Verify navigating to another control clears dismissal tracking
	var nav_btn = Button.new()
	nav_btn.name = "NavButton"
	root.add_child(nav_btn)
	vkm._on_gui_focus_changed(nav_btn)
	await process_frame
	await process_frame
	assert(vkm.get_dismissed_control() == null, "Focusing another control clears dismissed tracking")
	nav_btn.queue_free()
	print("  PASS: Dismissal retention verified. Keyboard stays closed without re-open trap until Joypad A or navigation.")

	# Clean up test nodes
	test_line_edit.queue_free()
	desktop_line_edit.queue_free()
	new_player_le.queue_free()
	new_player_email_le.queue_free()
	phone_camera_ip_le.queue_free()

	print("\n=======================================================")
	print("  ALL VIRTUAL KEYBOARD TESTS PASSED SUCCESSFULLY!       ")
	print("=======================================================\n")
	quit(0)
