extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Controller Fixes Verification Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	var ufg = root.get_node_or_null("UIFocusGuard")
	assert(ufg != null, "UIFocusGuard autoload must exist")

	# =========================================================================
	# TEST 1: OptionButton Controller Selection (Issue 1)
	# =========================================================================
	print("\n--- Test 1: OptionButton Controller Selection (Issue 1) ---")
	var opt = OptionButton.new()
	opt.add_item("Profile Alpha")
	opt.add_item("Profile Beta")
	opt.add_item("Profile Gamma")
	root.add_child(opt)
	ufg._hook_option_button(opt)
	opt.show_popup()
	await process_frame

	assert(ufg.is_dropdown_open(), "UIFocusGuard must detect open dropdown")
	var popup = opt.get_popup()
	assert(popup.visible, "Popup menu must be visible")

	var selected_idx := [-1]
	opt.item_selected.connect(func(idx): selected_idx[0] = idx)

	# Navigate down with D-pad
	var ev_down = InputEventJoypadButton.new()
	ev_down.button_index = JOY_BUTTON_DPAD_DOWN
	ev_down.pressed = true
	ufg._input(ev_down)
	assert(popup.get_focused_item() == 1, "Popup must focus index 1 on D-pad down")

	# Confirm selection with Joypad A
	var ev_a = InputEventJoypadButton.new()
	ev_a.button_index = JOY_BUTTON_A
	ev_a.pressed = true
	ufg._input(ev_a)
	await process_frame

	assert(opt.selected == 1, "OptionButton selected must be updated to 1")
	assert(selected_idx[0] == 1, "OptionButton item_selected must have emitted index 1")
	assert(not ufg.is_dropdown_open(), "Dropdown must be closed after controller selection")
	print("  PASS: OptionButton controller selection works cleanly with Joypad A.")
	opt.queue_free()
	await process_frame

	# =========================================================================
	# TEST 2: Avatar Picker Controller Focus (Issue 2)
	# =========================================================================
	print("\n--- Test 2: Avatar Picker Controller Focus (Issue 2) ---")
	var players_menu_scene = load("res://UI/PlayersMenu/players_menu.tscn")
	assert(players_menu_scene != null, "players_menu.tscn must load")
	var players_menu = players_menu_scene.instantiate()
	root.add_child(players_menu)
	await process_frame

	players_menu._open_avatar_picker("", func(_p): pass)
	await process_frame

	var avatar_buttons = players_menu.avatar_picker_buttons
	assert(avatar_buttons.size() > 0, "Avatar picker must instantiate avatar buttons")
	for entry in avatar_buttons:
		var btn: Button = entry["btn"]
		assert(btn.focus_mode == Control.FOCUS_ALL, "Avatar button must have focus_mode = FOCUS_ALL")
		assert(btn.has_theme_stylebox_override("focus"), "Avatar button must have focus stylebox override")

	var ok_btn = players_menu.avatar_picker_dialog.get_ok_button()
	assert(ok_btn.focus_neighbor_top != NodePath(), "Dialog OK button must have focus_neighbor_top wired")
	print("  PASS: Avatar picker buttons have FOCUS_ALL, focus style, and neighbor wiring.")

	players_menu.avatar_picker_dialog.hide()
	await process_frame

	# =========================================================================
	# TEST 3: Build Bag & Shot Recommendations Controller Focus (Issue 3)
	# =========================================================================
	print("\n--- Test 3: Build Bag & Shot Recommendations Controller Focus (Issue 3) ---")
	# 3A: Build Bag tab
	var bag_tab = players_menu._build_bag_tab("TestGolfer")
	root.add_child(bag_tab)
	await process_frame

	var club_buttons = bag_tab.find_children("*", "Button", true, false)
	var found_club_btn := false
	for btn in club_buttons:
		# Check if button is a club toggle button (minimum size 180x68)
		if btn.custom_minimum_size == Vector2(180, 68):
			found_club_btn = true
			assert(btn.focus_mode == Control.FOCUS_ALL, "Club button must have FOCUS_ALL for controller navigation")
			assert(btn.has_theme_stylebox_override("focus"), "Club button must have focus styling")
	assert(found_club_btn, "At least one club button must be present in bag tab")
	print("  PASS: Bag building club buttons have FOCUS_ALL and focus styleboxes.")
	bag_tab.queue_free()
	await process_frame

	# 3B: Issue card (recommendations)
	var issue_card = players_menu._create_issue_card("Slice / Out-to-In Path", 5, "This Month")
	assert(issue_card is Button, "Issue card must be a Button control")
	assert(issue_card.focus_mode == Control.FOCUS_ALL, "Issue card must have FOCUS_ALL")
	assert(issue_card.has_theme_stylebox_override("focus"), "Issue card must have focus styling")
	print("  PASS: Shot recommendations issue card is a focusable Button with focus styling.")
	issue_card.queue_free()

	players_menu.queue_free()
	await process_frame

	# =========================================================================
	# TEST 4: ScreenOffsetControl Controller Left/Right (Issue 4)
	# =========================================================================
	print("\n--- Test 4: ScreenOffsetControl Controller Left/Right (Issue 4) ---")
	var so_ctrl_script = load("res://UI/ScreenOffset/screen_offset_control.gd")
	var so_ctrl = so_ctrl_script.new()
	root.add_child(so_ctrl)
	await process_frame

	var toggled_emitted := [false]
	so_ctrl.offset_toggled.connect(func(_on): toggled_emitted[0] = true)

	assert(so_ctrl._slider.step == 0.05, "Slider step must be 0.05 (5%)")

	# Ensure offset is disabled initially for test
	var som = root.get_node_or_null("ScreenOffsetManager")
	if som != null:
		som.set_enabled(false)
		som.set_value(0.0, false)
	so_ctrl._sync_from_manager()
	assert(so_ctrl._toggle_btn.text.contains("OFF"), "Toggle button should start OFF")

	# Simulate D-pad Right on toggle button
	var ev_dpad_right = InputEventJoypadButton.new()
	ev_dpad_right.button_index = JOY_BUTTON_DPAD_RIGHT
	ev_dpad_right.pressed = true
	so_ctrl._on_toggle_gui_input(ev_dpad_right)
	await process_frame

	assert(toggled_emitted[0], "offset_toggled signal must emit on toggle change")
	assert(so_ctrl._slider.value >= 0.05, "D-pad right must nudge offset to at least 0.05")
	assert(not is_zero_approx(so_ctrl._slider.value), "Offset must not snap back to zero when adjusted via controller")
	print("  PASS: ScreenOffsetControl nudged via controller right input (value: %f)." % so_ctrl._slider.value)

	# Simulate D-pad Left on toggle button
	var ev_dpad_left = InputEventJoypadButton.new()
	ev_dpad_left.button_index = JOY_BUTTON_DPAD_LEFT
	ev_dpad_left.pressed = true
	so_ctrl._on_toggle_gui_input(ev_dpad_left)
	await process_frame

	# Center reset
	so_ctrl._on_center_pressed()
	assert(is_zero_approx(so_ctrl._slider.value), "Center button must reset offset to 0")

	so_ctrl.queue_free()
	await process_frame

	# =========================================================================
	# TEST 5: Mid-Game Add Player Dialog & Manage Players Navigation (Issue 5)
	# =========================================================================
	print("\n--- Test 5: Mid-Game Add Player Dialog & Manage Players Navigation ---")
	var course_play_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(course_play_script != null, "course_play.gd must load")
	var cp = course_play_script.new()
	root.add_child(cp)
	await process_frame

	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must exist")
	var test_players: Array[Dictionary] = [
		{"name": "Player 1", "tee": "Blue", "active": true, "paused": false, "score": 0},
		{"name": "Player 2", "tee": "Red", "active": true, "paused": false, "score": 0}
	]
	mp.players = test_players
	mp.active_player_index = 0
	mp.current_hole_index = 2 # Mid-game on Hole 3

	# 5A: Open Manage Players Panel
	cp._open_manage_players_panel()
	await process_frame

	assert(cp.hud_manage_players != null and cp.hud_manage_players.visible, "hud_manage_players must be visible")
	assert(ufg.is_locked() and ufg.current_lock_root() == cp.hud_manage_players, "hud_manage_players must lock focus in UIFocusGuard")

	var select_opt = cp.hud_manage_players.get_node_or_null("VBoxContainer/AddSection/AddRow/PlayerSelectOpt") as OptionButton
	var add_btn = cp.hud_manage_players.get_node_or_null("VBoxContainer/AddSection/AddRow/AddBtn") as Button
	var close_btn = cp.hud_manage_players.get_node_or_null("VBoxContainer/CloseBtn") as Button
	assert(select_opt != null and select_opt.focus_mode == Control.FOCUS_ALL, "PlayerSelectOpt must have FOCUS_ALL")
	assert(add_btn != null and add_btn.focus_mode == Control.FOCUS_ALL, "AddBtn must have FOCUS_ALL")
	assert(close_btn != null and close_btn.focus_mode == Control.FOCUS_ALL, "CloseBtn must have FOCUS_ALL")
	assert(select_opt.focus_neighbor_right != NodePath(), "PlayerSelectOpt must have focus_neighbor_right wired")
	print("  PASS: Manage Players panel locks focus with UIFocusGuard and wires 2D navigation.")

	# 5B: Show Mid-Game Add Player Dialog
	cp._show_add_player_dialog("Guest Golfer", "White")
	await process_frame

	var add_dlg = cp.add_player_prompt_dialog
	assert(add_dlg != null and add_dlg.visible, "add_player_prompt_dialog must be visible")
	assert(ufg.is_locked() and ufg.current_lock_root() == add_dlg, "add_player_prompt_dialog must lock focus in UIFocusGuard")

	var join_btn = add_dlg.find_child("JoinCurrentButton", true, false) as Button
	var play_btn = add_dlg.find_child("PlayMissedButton", true, false) as Button
	var cancel_btn = add_dlg.find_child("CancelButton", true, false) as Button
	assert(join_btn != null and join_btn.focus_mode == Control.FOCUS_ALL, "JoinCurrentButton must exist with FOCUS_ALL")
	assert(play_btn != null and play_btn.focus_mode == Control.FOCUS_ALL, "PlayMissedButton must exist with FOCUS_ALL")
	assert(cancel_btn != null and cancel_btn.focus_mode == Control.FOCUS_ALL, "CancelButton must exist with FOCUS_ALL")

	# Verify vertical focus neighbors
	assert(join_btn.focus_neighbor_bottom == join_btn.get_path_to(play_btn), "join_btn down neighbor must point to play_btn")
	assert(play_btn.focus_neighbor_bottom == play_btn.get_path_to(cancel_btn), "play_btn down neighbor must point to cancel_btn")
	assert(cancel_btn.focus_neighbor_bottom == cancel_btn.get_path_to(join_btn), "cancel_btn down neighbor must wrap to join_btn")
	assert(join_btn.focus_neighbor_top == join_btn.get_path_to(cancel_btn), "join_btn up neighbor must wrap to cancel_btn")
	assert(play_btn.focus_neighbor_top == play_btn.get_path_to(join_btn), "play_btn up neighbor must point to join_btn")

	# Test dialog button navigation helper
	var dlg_buttons: Array[Button] = [join_btn, play_btn, cancel_btn]
	join_btn.grab_focus()
	cp._navigate_dialog_buttons(dlg_buttons, 1)
	assert(play_btn.has_focus(), "Navigating down must focus PlayMissedButton")
	cp._navigate_dialog_buttons(dlg_buttons, 1)
	assert(cancel_btn.has_focus(), "Navigating down again must focus CancelButton")
	cp._navigate_dialog_buttons(dlg_buttons, 1)
	assert(join_btn.has_focus(), "Navigating down again must wrap focus to JoinCurrentButton")
	print("  PASS: Mid-game add player dialog has complete vertical focus loop and controller navigation.")

	# 5C: Dismiss Dialog and Return to Manage Players
	cp._dismiss_add_player_dialog()
	await process_frame
	assert(not add_dlg.visible, "add_player_prompt_dialog must be hidden after dismissal")
	assert(cp.hud_manage_players.visible, "hud_manage_players must be visible again after dialog dismissal")
	assert(ufg.is_locked() and ufg.current_lock_root() == cp.hud_manage_players, "Focus lock must return to hud_manage_players")

	# 5D: Close Manage Players Panel
	cp._close_manage_players_panel()
	await process_frame
	assert(not cp.hud_manage_players.visible, "hud_manage_players must be hidden")
	assert(not ufg.is_locked(), "UIFocusGuard lock must be released after closing Manage Players")
	print("  PASS: Dialog dismissal and panel close restore state and release focus lock cleanly.")

	cp.queue_free()
	await process_frame

	print("\n=======================================================")
	print("ALL 5 CONTROLLER FIXES VERIFIED SUCCESSFULLY! 🎉")
	print("=======================================================\n")
	quit(0)
