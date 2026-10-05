extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Controller UI Navigation Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	# Test 1: KeybindingManager UI Actions Setup
	print("\n--- Test 1: KeybindingManager UI Navigation Action Mappings ---")
	var km = root.get_node_or_null("KeybindingManager")
	assert(km != null, "KeybindingManager autoload must exist")

	assert(InputMap.has_action("ui_up"), "ui_up action must exist")
	assert(InputMap.has_action("ui_down"), "ui_down action must exist")
	assert(InputMap.has_action("ui_left"), "ui_left action must exist")
	assert(InputMap.has_action("ui_right"), "ui_right action must exist")
	assert(InputMap.has_action("ui_accept"), "ui_accept action must exist")
	assert(InputMap.has_action("ui_cancel"), "ui_cancel action must exist")

	var has_joy_up = false
	for ev in InputMap.action_get_events("ui_up"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_DPAD_UP:
			has_joy_up = true
		elif ev is InputEventJoypadMotion and ev.axis == JOY_AXIS_LEFT_Y and ev.axis_value < 0:
			has_joy_up = true
	assert(has_joy_up, "ui_up must include D-Pad Up or Left Stick Up")

	var has_joy_accept = false
	for ev in InputMap.action_get_events("ui_accept"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A:
			has_joy_accept = true
	assert(has_joy_accept, "ui_accept must include Joypad A")

	var has_joy_cancel = false
	var has_backspace_cancel = false
	for ev in InputMap.action_get_events("ui_cancel"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_B:
			has_joy_cancel = true
		if ev is InputEventKey and (ev.physical_keycode == KEY_BACKSPACE or ev.keycode == KEY_BACKSPACE):
			has_backspace_cancel = true
	assert(has_joy_cancel, "ui_cancel must include Joypad B")
	assert(not has_backspace_cancel, "ui_cancel must NOT include Backspace (backspace fix)")
	print("  PASS: UI navigation actions correctly mapped for controller and keyboard.")

	# Test 2: Range UI Button Focus Mode & Focus Neighbors
	print("\n--- Test 2: Range UI Button Focus Mode & Neighbors ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must be loadable")
	var range_node = Node3D.new()
	range_node.name = "Range"
	root.add_child(range_node)
	current_scene = range_node
	var range_ui = range_ui_scene.instantiate()
	range_node.add_child(range_ui)
	await process_frame
	await process_frame

	var overlay = range_ui.get_node_or_null("OverlayLayer")
	assert(overlay != null, "OverlayLayer must exist")

	var settings_btn = overlay.get_node_or_null("SettingsButton") as Button
	var home_btn = overlay.get_node_or_null("HomeButton") as Button
	var hide_helpers_btn = overlay.get_node_or_null("HideHelpersButton") as Button
	var stats_btn = overlay.get_node_or_null("StatsButton") as Button
	var map_btn = overlay.get_node_or_null("MapButton") as Button

	assert(settings_btn != null, "SettingsButton must exist in OverlayLayer")
	assert(home_btn != null, "HomeButton must exist in OverlayLayer")
	assert(hide_helpers_btn != null, "HideHelpersButton must exist in OverlayLayer")
	assert(stats_btn != null, "StatsButton must exist in OverlayLayer")
	assert(map_btn != null, "MapButton must exist in OverlayLayer")

	assert(settings_btn.focus_mode == Control.FOCUS_ALL, "SettingsButton must have focus_mode FOCUS_ALL")
	assert(home_btn.focus_mode == Control.FOCUS_ALL, "HomeButton must have focus_mode FOCUS_ALL")
	assert(hide_helpers_btn.focus_mode == Control.FOCUS_ALL, "HideHelpersButton must have focus_mode FOCUS_ALL")
	assert(stats_btn.focus_mode == Control.FOCUS_ALL, "StatsButton must have focus_mode FOCUS_ALL")
	assert(map_btn.focus_mode == Control.FOCUS_ALL, "MapButton must have focus_mode FOCUS_ALL")

	# Check focus neighbors
	assert(not stats_btn.focus_neighbor_right.is_empty(), "StatsButton should have right focus neighbor")
	assert(not map_btn.focus_neighbor_left.is_empty(), "MapButton should have left focus neighbor")
	assert(not home_btn.focus_neighbor_left.is_empty() or not home_btn.focus_neighbor_right.is_empty(), "HomeButton should have focus neighbors")
	print("  PASS: Range UI buttons have FOCUS_ALL and wired focus neighbors.")

	# Test 3: ClubSelector Focus Mode & Focus Management
	print("\n--- Test 3: ClubSelector Focus & Grid Navigation ---")
	var club_sel = overlay.get_node_or_null("ClubSelector")
	assert(club_sel != null, "ClubSelector must exist in OverlayLayer")
	assert(club_sel.club_button != null, "ClubSelector club_button must exist")
	assert(club_sel.club_button.focus_mode == Control.FOCUS_ALL, "club_button must have FOCUS_ALL")

	# Test opening club grid
	club_sel._on_display_button_pressed()
	await process_frame
	await process_frame
	assert(club_sel.grid_container.visible, "Club grid must be visible after press")
	
	# Test closing club grid
	club_sel._on_display_button_pressed()
	await process_frame
	await process_frame
	assert(not club_sel.grid_container.visible, "Club grid must be closed after second press")
	print("  PASS: ClubSelector button and grid properly support controller focus.")

	# Test 4: KeybindingManager Auto-Focus in Menu Screen
	print("\n--- Test 4: KeybindingManager Auto-Focus in Menu Screen ---")
	range_node.name = "MainMenu"
	var vp = range_ui.get_viewport()
	vp.gui_release_focus()
	assert(vp.gui_get_focus_owner() == null, "Focus should be null before input")

	# Simulate directional unhandled input from joypad D-pad
	var ev_down = InputEventJoypadButton.new()
	ev_down.button_index = JOY_BUTTON_DPAD_DOWN
	ev_down.pressed = true
	km._unhandled_input(ev_down)
	await process_frame

	var focused = vp.gui_get_focus_owner()
	assert(focused != null, "Focus must be grabbed automatically on directional input when focus was null in menu screen")
	assert(focused.is_visible_in_tree(), "Focused control must be visible in tree")
	print("  PASS: KeybindingManager auto-focused %s on directional input." % focused.name)
	range_node.name = "Range"

	# Test 5: Topmost Modal Detection
	print("\n--- Test 5: Topmost Modal Priority Focus ---")
	var mock_modal = Panel.new()
	mock_modal.name = "TestDialogModal"
	var modal_btn = Button.new()
	modal_btn.name = "ModalConfirmBtn"
	modal_btn.focus_mode = Control.FOCUS_ALL
	mock_modal.add_child(modal_btn)
	range_ui.add_child(mock_modal)
	await process_frame

	var top_modal = km._find_topmost_modal()
	assert(top_modal == mock_modal, "KeybindingManager._find_topmost_modal must identify TestDialogModal")

	vp.gui_release_focus()
	km._unhandled_input(ev_down)
	await process_frame
	assert(vp.gui_get_focus_owner() == modal_btn, "Focus must go to control inside the modal")
	print("  PASS: Topmost modal detected and its child focused.")

	mock_modal.queue_free()
	range_node.queue_free()
	await process_frame

	# Test 6: UIFocusGuard Dropdown & Slider Isolation
	print("\n--- Test 6: UIFocusGuard Dropdown & Slider Isolation ---")
	var ufg = root.get_node_or_null("UIFocusGuard")
	assert(ufg != null, "UIFocusGuard autoload must exist")

	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 50
	root.add_child(slider)
	slider.grab_focus()
	await process_frame

	var ev_right = InputEventJoypadButton.new()
	ev_right.button_index = JOY_BUTTON_DPAD_RIGHT
	ev_right.pressed = true

	# Test slider guard: should mark input handled so focus doesn't jump
	ufg._input(ev_right)
	assert(slider.get_viewport().is_input_handled(), "UIFocusGuard must consume lateral navigation while Slider is focused")
	print("  PASS: Slider guard consumes lateral input without jumping focus.")
	slider.queue_free()
	await process_frame

	# Test 7: toggle_stats joypad mapping is unbound (-1) to avoid Joypad A double-toggle
	print("\n--- Test 7: toggle_stats Controller Binding Check ---")
	var stats_action_events = InputMap.action_get_events("toggle_stats")
	var has_joy_a_stats = false
	for ev in stats_action_events:
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A:
			has_joy_a_stats = true
	assert(not has_joy_a_stats, "toggle_stats must NOT be bound to JOY_BUTTON_A (avoids double-toggle collision with ui_accept)")
	print("  PASS: toggle_stats is not mapped to Joypad A.")

	# Test 8: OptionButton Dropdown Controller Navigation & Selection
	print("\n--- Test 8: OptionButton Dropdown Controller Navigation & Selection ---")
	var opt = OptionButton.new()
	opt.add_item("Golfer 1")
	opt.add_item("Golfer 2")
	opt.add_item("Golfer 3")
	root.add_child(opt)
	ufg._hook_option_button(opt)
	opt.show_popup()
	await process_frame
	assert(ufg.is_dropdown_open(), "UIFocusGuard must report is_dropdown_open == true")
	var popup = opt.get_popup()
	assert(popup.visible, "Popup must be visible")

	var selected_val := [-1]
	opt.item_selected.connect(func(idx): selected_val[0] = idx)

	# Simulate D-pad Down to move focus to index 1
	var ev_dpad_down = InputEventJoypadButton.new()
	ev_dpad_down.button_index = JOY_BUTTON_DPAD_DOWN
	ev_dpad_down.pressed = true
	ufg._input(ev_dpad_down)
	assert(popup.get_focused_item() == 1, "Popup focused item should advance to index 1 on D-pad down")

	# Simulate Joypad A to select index 1
	var ev_joy_a = InputEventJoypadButton.new()
	ev_joy_a.button_index = JOY_BUTTON_A
	ev_joy_a.pressed = true
	ufg._input(ev_joy_a)
	await process_frame

	assert(opt.selected == 1, "OptionButton selected must be updated to 1")
	assert(selected_val[0] == 1, "item_selected signal must have emitted with index 1")
	assert(not popup.visible, "Popup must be closed after Joypad A selection")
	assert(not ufg.is_dropdown_open(), "UIFocusGuard must report is_dropdown_open == false after selection")
	print("  PASS: OptionButton dropdown navigated with D-pad and confirmed with Joypad A.")
	opt.queue_free()
	await process_frame

	# Test 9: SwingReplayModal Focus Lock & Button Highlighting
	print("\n--- Test 9: SwingReplayModal Focus Lock & Initial Focus ---")
	var replay_modal_script = load("res://UI/GolferCamera/swing_replay_modal.gd")
	assert(replay_modal_script != null, "swing_replay_modal.gd must load")
	var replay_modal = replay_modal_script.new()
	root.add_child(replay_modal)
	replay_modal.setup_modal({"speed": 100.0, "carry": 200.0}, [], true)
	await process_frame
	await process_frame

	assert(ufg.is_locked(), "UIFocusGuard must be locked while SwingReplayModal is open")
	assert(ufg.current_lock_root() == replay_modal, "UIFocusGuard current_lock_root must be SwingReplayModal")
	var modal_focus = replay_modal.get_viewport().gui_get_focus_owner()
	assert(modal_focus != null, "A control inside SwingReplayModal must have focus")
	assert(replay_modal.is_ancestor_of(modal_focus), "Focused control must be inside SwingReplayModal")
	assert(modal_focus.name == "ResumePracticeButton" or modal_focus.name == "CloseDetachedButton", "Initial focus must land on Resume/Close button")

	# Dismiss modal via close button handler
	replay_modal._on_close_button_pressed()
	await process_frame
	assert(not ufg.is_locked(), "UIFocusGuard lock must be released after modal closed")
	print("  PASS: SwingReplayModal pushes lock, grabs focus on Resume button, and releases lock on close.")

	# Test 10: DistanceMenu Focus Lock & Initial Focus
	print("\n--- Test 10: DistanceMenu Focus Lock & Initial Focus ---")
	var dist_menu_script = load("res://UI/distance_menu.gd")
	assert(dist_menu_script != null, "distance_menu.gd must load")
	var dist_menu = dist_menu_script.new()
	root.add_child(dist_menu)
	dist_menu.visible = true
	await process_frame
	await process_frame

	assert(ufg.is_locked(), "UIFocusGuard must be locked while DistanceMenu is visible")
	assert(ufg.current_lock_root() == dist_menu, "UIFocusGuard current_lock_root must be DistanceMenu")
	var dist_focus = dist_menu.get_viewport().gui_get_focus_owner()
	assert(dist_focus != null, "A button inside DistanceMenu must have focus")
	assert(dist_menu.is_ancestor_of(dist_focus), "Focused button must be inside DistanceMenu")

	dist_menu.visible = false
	await process_frame
	assert(not ufg.is_locked(), "UIFocusGuard lock must be released after DistanceMenu hidden")
	print("  PASS: DistanceMenu pushes lock, acquires focus, and releases lock when hidden.")
	dist_menu.queue_free()
	await process_frame

	# Test 11: Slider Lateral Value Adjustment (Issue 2)
	print("\n--- Test 11: Slider Lateral Value Adjustment via Controller Input ---")
	var test_slider = HSlider.new()
	test_slider.min_value = 0.0
	test_slider.max_value = 100.0
	test_slider.step = 5.0
	test_slider.value = 50.0
	test_slider.focus_mode = Control.FOCUS_ALL
	root.add_child(test_slider)
	test_slider.grab_focus()
	await process_frame

	var ev_sl_right = InputEventAction.new()
	ev_sl_right.action = "ui_right"
	ev_sl_right.pressed = true
	ufg._input(ev_sl_right)
	assert(test_slider.value == 55.0, "HSlider value should increase by step 5 on ui_right (actual: %f)" % test_slider.value)

	var ev_sl_left = InputEventAction.new()
	ev_sl_left.action = "ui_left"
	ev_sl_left.pressed = true
	ufg._input(ev_sl_left)
	assert(test_slider.value == 50.0, "HSlider value should decrease by step 5 on ui_left (actual: %f)" % test_slider.value)
	test_slider.queue_free()
	await process_frame
	print("  PASS: Slider value adjusted directly via lateral controller navigation without jumping focus.")

	# Test 12: Dropdown Debounce Cooldown to Prevent Skipping Items (Issue 5)
	print("\n--- Test 12: Dropdown Navigation Debounce Cooldown ---")
	var debounce_opt = OptionButton.new()
	debounce_opt.add_item("Item 0")
	debounce_opt.add_item("Item 1")
	debounce_opt.add_item("Item 2")
	debounce_opt.add_item("Item 3")
	root.add_child(debounce_opt)
	ufg._hook_option_button(debounce_opt)
	debounce_opt.show_popup()
	await process_frame
	var d_popup = debounce_opt.get_popup()

	var ev_db_down = InputEventAction.new()
	ev_db_down.action = "ui_down"
	ev_db_down.pressed = true
	ufg._last_dropdown_nav_time = 0.0 # Reset timer to simulate initial press
	ufg._input(ev_db_down)
	assert(d_popup.get_focused_item() == 1, "First ui_down should move focus to item 1")

	# Immediate repeated ui_down within cooldown period should be debounced and ignored
	ufg._input(ev_db_down)
	assert(d_popup.get_focused_item() == 1, "Immediate consecutive ui_down must be debounced and NOT skip to item 2")

	d_popup.hide()
	debounce_opt.queue_free()
	await process_frame
	print("  PASS: Dropdown navigation debounces rapid repeated inputs, preventing skipping items.")

	# Test 13: Previous Shot Analysis Button Behavior (Issue 3)
	print("\n--- Test 13: Previous Shot Analysis Popup & Focus Lock ---")
	var r_ui = range_ui_scene.instantiate()
	root.add_child(r_ui)
	await process_frame

	var prev_shot_btn = r_ui.find_child("PrevShotAnalysisButton", true, false) as Button
	assert(prev_shot_btn != null, "PrevShotAnalysisButton must exist in r_ui")
	# When last shot data is empty, pressing previous shot analysis should open popup and focus CloseBtn
	r_ui._last_shot_data.clear()
	r_ui._on_prev_shot_analysis_pressed()
	await process_frame

	var prev_popup = r_ui.get_node_or_null("PrevShotPopup") as Control
	assert(prev_popup != null and prev_popup.visible, "PrevShotPopup should be visible when last shot data is empty")
	assert(ufg.is_locked() and ufg.current_lock_root() == prev_popup, "PrevShotPopup must push lock to UIFocusGuard")
	var popup_focus = r_ui.get_viewport().gui_get_focus_owner()
	assert(popup_focus != null and popup_focus.name == "CloseBtn", "CloseBtn must be focused when PrevShotPopup opens")

	# Pressing cancel pops lock and hides popup
	var ev_can = InputEventAction.new()
	ev_can.action = "ui_cancel"
	ev_can.pressed = true
	ufg._input(ev_can)
	await process_frame
	assert(not prev_popup.visible, "PrevShotPopup must be hidden after ui_cancel")
	assert(not ufg.is_locked(), "UIFocusGuard lock must be released after PrevShotPopup dismissed")
	r_ui.queue_free()
	await process_frame
	print("  PASS: Previous Shot Analysis opens informative popup and locks focus when shot data empty.")

	# Test 14: SwingReplayModal Detail Modal (Modal in Modal) (Issue 1)
	print("\n--- Test 14: SwingReplayModal Detail Modal (Modal in Modal) ---")
	var srm = replay_modal_script.new()
	root.add_child(srm)
	srm.setup_modal({"speed": 100.0, "carry": 200.0}, [], true)
	await process_frame

	assert(ufg.is_locked() and ufg.current_lock_root() == srm, "SwingReplayModal must be the current lock root")

	# Open Detail Modal (e.g. video/explanation modal)
	srm._on_detail_button_pressed({"title": "Test Flaw", "benchmark": 12.0, "value": 18.0}, "explain")
	await process_frame

	var detail_modal = srm.get_node_or_null("DetailModal") as Control
	assert(detail_modal != null and detail_modal.visible, "DetailModal must exist inside SwingReplayModal")
	assert(ufg.current_lock_root() == detail_modal, "UIFocusGuard lock must now be DetailModal (modal in modal)")
	var d_focus = srm.get_viewport().gui_get_focus_owner()
	assert(d_focus != null and (d_focus.name == "CloseButton" or d_focus.name == "FooterCloseButton"), "CloseButton must have initial focus in DetailModal")

	# Pressing cancel should dismiss DetailModal and return lock to SwingReplayModal
	ufg._input(ev_can)
	await process_frame
	assert(srm.get_node_or_null("DetailModal") == null, "DetailModal must be freed on cancel")
	assert(ufg.is_locked() and ufg.current_lock_root() == srm, "UIFocusGuard lock must be restored to SwingReplayModal")

	srm._on_close_button_pressed()
	await process_frame
	assert(not ufg.is_locked(), "Lock must be fully released after SwingReplayModal closed")
	print("  PASS: Detail Modal in SwingReplayModal correctly locks focus and dismisses cleanly without trapping user.")

	# Test 15: Mulligan Dialog Controller Navigation (Issue 4)
	print("\n--- Test 15: Mulligan Dialog Controller Navigation ---")
	var course_play_scene = load("res://Courses/CoursePlay/course_play.tscn")
	assert(course_play_scene != null, "course_play.tscn must load")
	var course_play = course_play_scene.instantiate()
	root.add_child(course_play)
	await process_frame

	var mp = root.get_node_or_null("MultiplayerManager")
	var test_players: Array[Dictionary] = [{"name": "Golfer 1", "score": 0, "mulligans": 1, "last_starting_pos": Vector3.ZERO, "hole_scores": {}, "position": Vector3.ZERO}]
	mp.players = test_players
	mp.active_player_index = 0
	mp.hole_ids = ["Hole 1"]
	mp.current_hole_index = 0

	course_play._on_mulligan_pressed()
	await process_frame

	var m_dialog = course_play.mulligan_confirm_dialog
	assert(m_dialog != null and m_dialog.visible, "mulligan_confirm_dialog must be visible")
	assert(ufg.is_locked() and ufg.current_lock_root() == m_dialog, "mulligan_confirm_dialog must push lock to UIFocusGuard")

	var mc_btn = course_play._mulligan_confirm_btn
	var can_btn = course_play._mulligan_cancel_btn
	assert(mc_btn != null and mc_btn.name == "ConfirmBtn", "Confirm button must exist and be named ConfirmBtn")
	assert(can_btn != null and can_btn.name == "CancelBtn", "Cancel button must exist and be named CancelBtn")

	# Test lateral navigation between Confirm and Cancel
	var ev_m_right = InputEventAction.new()
	ev_m_right.action = "ui_right"
	ev_m_right.pressed = true
	course_play._handle_mulligan_dialog_input(ev_m_right)
	assert(can_btn.has_focus(), "CancelBtn must acquire focus on ui_right")

	# Selecting Cancel with Enter / Joypad A dismisses dialog without confirming
	var ev_enter = InputEventAction.new()
	ev_enter.action = "ui_accept"
	ev_enter.pressed = true
	course_play._handle_mulligan_dialog_input(ev_enter)
	await process_frame
	assert(not m_dialog.visible, "mulligan_confirm_dialog must be closed when Cancel selected")
	assert(not ufg.is_locked(), "UIFocusGuard lock must be released after mulligan dialog closed")

	course_play.queue_free()
	await process_frame
	print("  PASS: Mulligan dialog supports controller left/right selection between Confirm and Cancel.")

	# Test 16: Practice Aerial Button Styling and Teleport Position (Issue 6)
	print("\n--- Test 16: Practice Aerial Button Styling & Focus Mode ---")
	var range_script = load("res://Courses/Range/range.gd")
	assert(range_script != null, "range.gd must load")
	var r_node = Node3D.new()
	r_node.set_script(range_script)
	root.add_child(r_node)
	await process_frame

	var dummy_btn = Button.new()
	r_node.apply_circular_button_style(dummy_btn, Color(0.2, 0.6, 0.3, 0.85))
	assert(dummy_btn.focus_mode == Control.FOCUS_ALL, "apply_circular_button_style must set focus_mode to FOCUS_ALL")
	assert(dummy_btn.has_theme_stylebox_override("focus"), "apply_circular_button_style must supply focus stylebox override")
	dummy_btn.queue_free()

	# Test _perform_practice_teleport_pos
	r_node.practice_mode_active = true
	r_node.place_ball_mode = true
	var test_target_pos = Vector3(120.0, 5.0, -80.0)
	r_node._perform_practice_teleport_pos(test_target_pos)
	assert(r_node.practice_start_pos.x == test_target_pos.x and r_node.practice_start_pos.z == test_target_pos.z, "practice_start_pos must update to teleported coordinates")
	print("  PASS: Circular button style provides FOCUS_ALL and focus border; practice ball teleport works via Vector3.")

	r_node.queue_free()
	await process_frame

	# Test 17: DetailModal Focus Navigation & InAppVideoPlayer Focus
	print("\n--- Test 17: DetailModal Focus Navigation & InAppVideoPlayer ---")
	var video_rec = {
		"title": "Slice Drill",
		"drill": "Path Alignment",
		"video_url": "https://youtu.be/mock_golf_tutorial"
	}
	var test_replay = replay_modal_script.new()
	root.add_child(test_replay)
	test_replay.setup_modal({"speed": 100.0}, [], true)
	await process_frame
	await process_frame

	var d_modal = test_replay._create_detail_modal(video_rec, "video")
	test_replay.add_child(d_modal)
	ufg.push_lock(d_modal)
	test_replay._setup_detail_modal_focus_navigation(d_modal)
	await process_frame

	var c_btn = d_modal.find_child("CloseButton", true, false) as Button
	var f_btn = d_modal.find_child("FooterCloseButton", true, false) as Button
	var v_frame = d_modal.find_child("VideoPlaceholderFrame", true, false) as PanelContainer
	assert(c_btn != null and f_btn != null, "CloseButton and FooterCloseButton must exist")
	assert(v_frame != null, "VideoPlaceholderFrame must exist")
	assert(v_frame.focus_mode == Control.FOCUS_ALL, "VideoPlaceholderFrame must have focus_mode FOCUS_ALL")
	assert(not c_btn.focus_neighbor_bottom.is_empty(), "CloseButton must have wired bottom focus neighbor")
	assert(not f_btn.focus_neighbor_bottom.is_empty(), "FooterCloseButton must have wired bottom focus neighbor wrapping to top")
	assert(ufg.is_locked() and ufg.current_lock_root() == d_modal, "UIFocusGuard must be locked to DetailModal")

	# Test dismiss via cancel / pop lock
	ufg.pop_lock(true)
	await process_frame
	assert(test_replay.get_node_or_null("DetailModal") == null, "DetailModal must dismiss on pop_lock")
	test_replay.queue_free()
	await process_frame
	print("  PASS: DetailModal wires focus neighbors and dismisses cleanly.")

	# Test 18: CoursePlay Manage Players Focus Lock & Initial Focus
	print("\n--- Test 18: CoursePlay Manage Players Focus Lock ---")
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(cp_script != null, "course_play.gd must load")
	var cp_node = Node3D.new()
	cp_node.set_script(cp_script)
	root.add_child(cp_node)
	await process_frame

	cp_node._on_manage_players_toggle_pressed()
	await process_frame
	assert(cp_node.hud_manage_players.visible, "hud_manage_players must be visible after toggle")
	assert(ufg.is_locked() and ufg.current_lock_root() == cp_node.hud_manage_players, "UIFocusGuard must be locked to hud_manage_players")

	cp_node._on_manage_players_toggle_pressed()
	await process_frame
	assert(not cp_node.hud_manage_players.visible, "hud_manage_players must be hidden after second toggle")
	assert(not ufg.is_locked(), "UIFocusGuard must unlock after closing hud_manage_players")

	cp_node.queue_free()
	await process_frame
	print("  PASS: CoursePlay manage players toggles focus lock properly.")

	# Test 19: D-Pad Controller Input Does Not Release Focus
	print("\n--- Test 19: D-Pad Controller Input Does Not Release Focus ---")
	var dummy_ctrl = Control.new()
	var test_btn = Button.new()
	test_btn.text = "Menu Button"
	test_btn.focus_mode = Control.FOCUS_ALL
	dummy_ctrl.add_child(test_btn)
	root.add_child(dummy_ctrl)
	await process_frame
	test_btn.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == test_btn, "test_btn must have focus initially")

	# Simulate D-pad up press (which was previously stripped by is_aim)
	var dpad_up_ev = InputEventJoypadButton.new()
	dpad_up_ev.button_index = JOY_BUTTON_DPAD_UP
	dpad_up_ev.pressed = true
	ufg._input(dpad_up_ev)
	await process_frame
	assert(root.gui_get_focus_owner() == test_btn, "test_btn must STILL have focus after D-pad Up (D-pad must never strip focus!)")

	# Simulate D-pad left press
	var dpad_left_ev = InputEventJoypadButton.new()
	dpad_left_ev.button_index = JOY_BUTTON_DPAD_LEFT
	dpad_left_ev.pressed = true
	ufg._input(dpad_left_ev)
	await process_frame
	assert(root.gui_get_focus_owner() == test_btn, "test_btn must STILL have focus after D-pad Left")
	print("  PASS: D-pad controller input does not strip UI focus.")

	# Test 20: Slider Controller Value Adjustment
	print("\n--- Test 20: Slider Controller Value Adjustment ---")
	var dpad_slider = HSlider.new()
	dpad_slider.min_value = 0.0
	dpad_slider.max_value = 20.0
	dpad_slider.step = 1.0
	dpad_slider.value = 5.0
	dpad_slider.focus_mode = Control.FOCUS_ALL
	dummy_ctrl.add_child(dpad_slider)
	await process_frame
	dpad_slider.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == dpad_slider, "dpad_slider must have focus")

	# Right arrow / D-pad right should increase value
	var slider_right_ev = InputEventJoypadButton.new()
	slider_right_ev.button_index = JOY_BUTTON_DPAD_RIGHT
	slider_right_ev.pressed = true
	ufg._input(slider_right_ev)
	assert(dpad_slider.value == 6.0, "Slider value must increment to 6.0 via D-Pad Right")

	# Left arrow / D-pad left should decrease value
	var slider_left_ev = InputEventJoypadButton.new()
	slider_left_ev.button_index = JOY_BUTTON_DPAD_LEFT
	slider_left_ev.pressed = true
	ufg._input(slider_left_ev)
	assert(dpad_slider.value == 5.0, "Slider value must decrement to 5.0 via D-Pad Left")
	print("  PASS: Slider adjusts properly via controller D-Pad.")

	# Test 21: OptionButton Controller Selection
	print("\n--- Test 21: OptionButton Controller Selection ---")
	var test_opt = OptionButton.new()
	test_opt.add_item("Player 1", 0)
	test_opt.add_item("Player 2", 1)
	test_opt.add_item("Player 3", 2)
	dummy_ctrl.add_child(test_opt)
	ufg._hook_option_button(test_opt)
	await process_frame

	# Show popup
	test_opt.show_popup()
	await process_frame
	assert(ufg.is_dropdown_open(), "UIFocusGuard must report dropdown open")

	var opt_popup = test_opt.get_popup()
	# Focus item 1
	opt_popup.set_focused_item(1)

	# Simulate Joypad A press
	var a_btn_ev = InputEventJoypadButton.new()
	a_btn_ev.button_index = JOY_BUTTON_A
	a_btn_ev.pressed = true
	ufg._input(a_btn_ev)
	await process_frame
	assert(test_opt.selected == 1, "test_opt must select item 1 on Joypad A")
	assert(not ufg.is_dropdown_open(), "UIFocusGuard dropdown must be closed after Joypad A selection")

	dummy_ctrl.queue_free()
	await process_frame
	print("  PASS: OptionButton selects item via controller Joypad A.")

	# Test 22: Controller Left Stick Motion Wakes Up HUD Focus When Null
	print("\n--- Test 22: Controller Left Stick Motion Wakes Up HUD Focus ---")
	var test_hud_scene = Control.new()
	var test_hud_scr = GDScript.new()
	test_hud_scr.source_code = "extends Control\nvar is_aerial_view: bool = false\n"
	test_hud_scr.reload()
	test_hud_scene.set_script(test_hud_scr)
	test_hud_scene.name = "Range"
	root.add_child(test_hud_scene)
	current_scene = test_hud_scene

	var test_hud_btn = Button.new()
	test_hud_btn.name = "HUDTestBtn"
	test_hud_btn.focus_mode = Control.FOCUS_ALL
	test_hud_scene.add_child(test_hud_btn)
	await process_frame
	await process_frame

	root.gui_release_focus()
	await process_frame
	print("Initial focus owner before stick: ", root.gui_get_focus_owner())

	var stick_ev = InputEventJoypadMotion.new()
	stick_ev.axis = JOY_AXIS_LEFT_Y
	stick_ev.axis_value = 1.0
	km._unhandled_input(stick_ev)
	await process_frame
	var cur_f = root.gui_get_focus_owner()
	print("Focus owner after stick: ", cur_f)
	if cur_f == null:
		push_error("Test 22 failed: focus was null after stick motion")
		quit(1)
		return
	print("  PASS: Controller stick motion successfully wakes up HUD focus when null.")

	# Test 23: Buttons Retain Focus on Pressed Signal
	print("\n--- Test 23: Buttons Retain Focus on Press ---")
	test_hud_btn.grab_focus()
	await process_frame
	print("Focus before press: ", root.gui_get_focus_owner())
	test_hud_btn.emit_signal("pressed")
	await process_frame
	print("Focus after press: ", root.gui_get_focus_owner())
	if root.gui_get_focus_owner() != test_hud_btn:
		push_error("Test 23 failed: HUDTestBtn did not retain focus on pressed signal")
		quit(1)
		return
	print("  PASS: Buttons retain focus on press without releasing.")

	# Test 24: Map View Controller Focus
	print("\n--- Test 24: Map View Controller Navigation Wake-Up ---")
	root.gui_release_focus()
	await process_frame
	test_hud_scene.set("is_aerial_view", true)
	var dpad_ev = InputEventJoypadButton.new()
	dpad_ev.button_index = JOY_BUTTON_DPAD_DOWN
	dpad_ev.pressed = true
	km._unhandled_input(dpad_ev)
	await process_frame
	var aerial_f = root.gui_get_focus_owner()
	print("Focus after aerial dpad: ", aerial_f)
	if aerial_f == null:
		push_error("Test 24 failed: focus was null in map view on directional input")
		quit(1)
		return
	test_hud_scene.queue_free()
	await process_frame
	print("  PASS: Aerial Map View correctly wakes up controller focus.")

	# Test 25: 3D Gameplay D-Pad Releases HUD Button Focus for Aiming
	print("\n--- Test 25: 3D Gameplay D-Pad Aim Focus Release ---")
	var cp_scene = Control.new()
	cp_scene.name = "CoursePlay"
	root.add_child(cp_scene)
	current_scene = cp_scene

	var cp_btn = Button.new()
	cp_btn.name = "HUDStatsBtn"
	cp_btn.focus_mode = Control.FOCUS_ALL
	cp_scene.add_child(cp_btn)
	await process_frame
	cp_btn.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == cp_btn, "cp_btn must have focus before aim test")

	var aim_dpad_ev = InputEventJoypadButton.new()
	aim_dpad_ev.button_index = JOY_BUTTON_DPAD_LEFT
	aim_dpad_ev.pressed = true
	ufg._input(aim_dpad_ev)
	await process_frame
	assert(root.gui_get_focus_owner() == null, "Focus must be released in 3D gameplay on D-pad aim so aiming works!")
	print("  PASS: In 3D gameplay, D-pad aim successfully releases HUD focus.")
	cp_scene.queue_free()
	await process_frame

	# Test 26: 3D Gameplay Analog Stick Motion Does NOT Release HUD Button Focus
	print("\n--- Test 26: 3D Gameplay Analog Stick Motion Preserves HUD Focus ---")
	var cp_stick_scene = Control.new()
	cp_stick_scene.name = "CoursePlay"
	root.add_child(cp_stick_scene)
	current_scene = cp_stick_scene

	var stick_btn1 = Button.new()
	stick_btn1.name = "StickBtn1"
	stick_btn1.focus_mode = Control.FOCUS_ALL
	cp_stick_scene.add_child(stick_btn1)
	await process_frame
	stick_btn1.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == stick_btn1, "stick_btn1 must have focus before stick motion test")

	var stick_motion_ev = InputEventJoypadMotion.new()
	stick_motion_ev.axis = JOY_AXIS_LEFT_X
	stick_motion_ev.axis_value = 1.0
	ufg._input(stick_motion_ev)
	await process_frame
	assert(root.gui_get_focus_owner() == stick_btn1, "Focus must NOT be released on analog stick motion!")
	print("  PASS: In 3D gameplay, analog stick motion preserves HUD focus for navigation.")
	cp_stick_scene.queue_free()
	await process_frame

	# Test 27: CoursePlaySetup D-Pad Navigation Does NOT Release Focus
	print("\n--- Test 27: CoursePlaySetup D-Pad Focus Retention ---")
	var setup_scene = Control.new()
	setup_scene.name = "CoursePlaySetup"
	root.add_child(setup_scene)
	current_scene = setup_scene

	var setup_item_list = ItemList.new()
	setup_item_list.name = "CourseList"
	setup_item_list.focus_mode = Control.FOCUS_ALL
	setup_item_list.add_item("Course 1")
	setup_item_list.add_item("Course 2")
	setup_item_list.select(0)
	setup_scene.add_child(setup_item_list)
	await process_frame
	setup_item_list.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == setup_item_list, "setup_item_list must have focus")

	var setup_dpad_ev = InputEventJoypadButton.new()
	setup_dpad_ev.button_index = JOY_BUTTON_DPAD_DOWN
	setup_dpad_ev.pressed = true
	ufg._input(setup_dpad_ev)
	await process_frame
	assert(root.gui_get_focus_owner() == setup_item_list, "CoursePlaySetup must NOT release focus on D-pad navigation!")
	print("  PASS: CoursePlaySetup preserves focus during D-pad navigation.")
	setup_scene.queue_free()
	await process_frame

	# Test 28: Range._process_keyboard_aiming preserves focus when idle
	print("\n--- Test 28: Range _process_keyboard_aiming Preserves Focus When Idle ---")
	var range_test_node = Node3D.new()
	range_test_node.name = "Range"
	root.add_child(range_test_node)
	current_scene = range_test_node

	var r_btn = Button.new()
	r_btn.name = "RangeTestBtn"
	r_btn.focus_mode = Control.FOCUS_ALL
	range_test_node.add_child(r_btn)
	await process_frame
	r_btn.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == r_btn, "r_btn must have focus")

	var range_scr = load("res://Courses/Range/range.gd")
	var dummy_range = range_test_node
	dummy_range.set_script(range_scr)
	dummy_range.call("_process_keyboard_aiming", 0.016)
	await process_frame
	assert(root.gui_get_focus_owner() == r_btn, "Idle _process_keyboard_aiming must NOT wipe focus!")
	print("  PASS: Range _process_keyboard_aiming preserves focus when not aiming.")
	range_test_node.queue_free()
	await process_frame

	print("\n=======================================================")
	print("  ALL CONTROLLER UI NAVIGATION TESTS PASSED SUCCESSFULLY! ")
	print("=======================================================\n")
	quit(0)
