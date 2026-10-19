extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Modal Focus Isolation Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	var ufg = root.get_node_or_null("UIFocusGuard")
	assert(ufg != null, "UIFocusGuard autoload must exist")

	print("\n--- Test 1: Background button setup & modal focus containment ---")
	var bg_container = Control.new()
	bg_container.name = "BackgroundScreen"
	bg_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg_container)
	current_scene = bg_container

	var bg_btn1 = Button.new()
	bg_btn1.name = "PlayCourseButton"
	bg_btn1.text = "Play Course"
	bg_container.add_child(bg_btn1)

	var bg_btn2 = Button.new()
	bg_btn2.name = "BackgroundSettingsButton"
	bg_btn2.text = "Background Settings"
	bg_container.add_child(bg_btn2)

	bg_btn1.grab_focus()
	await process_frame
	await process_frame

	assert(root.gui_get_focus_owner() == bg_btn1, "bg_btn1 should initially have focus")
	assert(not ufg.is_modal_active(), "No modal should be active initially")
	print("  PASS: Initial background focus established.")

	print("\n--- Test 2: LaunchMonitorConnectModal locks focus and prevents background interaction ---")
	var lm_modal_scene = load("res://UI/LaunchMonitorConnectModal/launch_monitor_connect_modal.tscn")
	assert(lm_modal_scene != null, "launch_monitor_connect_modal.tscn must be loadable")

	var lm_modal = lm_modal_scene.instantiate()
	bg_container.add_child(lm_modal)

	await process_frame
	await process_frame

	assert(ufg.is_modal_active(), "UIFocusGuard.is_modal_active() must be true when LaunchMonitorConnectModal is open")
	assert(ufg.current_lock_root() == lm_modal, "Current lock root must be LaunchMonitorConnectModal")

	var modal_focus = root.gui_get_focus_owner()
	assert(modal_focus != null, "Modal must have a focused control")
	assert(lm_modal.is_ancestor_of(modal_focus) or modal_focus == lm_modal, "Focused control must be inside LaunchMonitorConnectModal")
	print("  PASS: LaunchMonitorConnectModal successfully locked focus to: %s" % modal_focus.name)

	# Ensure Tab 0 (Bluetooth) is active for deterministic testing
	var tab_container = lm_modal.find_child("TabContainer", true, false) as TabContainer
	assert(tab_container != null, "TabContainer must exist")
	tab_container.current_tab = 0
	await process_frame
	await process_frame

	print("\n--- Test 3: Attempting to focus background button redirects to modal ---")
	bg_btn1.grab_focus()
	await process_frame
	var cur_f = root.gui_get_focus_owner()
	assert(cur_f != bg_btn1, "Background button bg_btn1 must NOT be allowed to keep focus while modal is open")
	assert(lm_modal.is_ancestor_of(cur_f), "Focus must have been redirected back into LaunchMonitorConnectModal")
	print("  PASS: Focus theft by background button successfully blocked and restored to modal.")

	print("\n--- Focusables in LaunchMonitorConnectModal ---")
	for f in ufg._get_all_focusable_controls(lm_modal):
		print("  Focusable: %s, rect: %s, focus_mode: %s" % [f.name, str(f.get_global_rect()), str(f.focus_mode)])

	print("\n--- Test 4: Directional navigation inside LaunchMonitorConnectModal ---")
	var cont_btn = lm_modal.find_child("ContinueButton", true, false) as Button
	var skip_btn = lm_modal.find_child("SkipButton", true, false) as Button
	assert(cont_btn != null and skip_btn != null, "Footer buttons must exist")

	cont_btn.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == cont_btn, "cont_btn should be focused")

	# Move LEFT: ContinueButton -> SkipButton
	var ev_left = InputEventKey.new()
	ev_left.keycode = KEY_LEFT
	ev_left.pressed = true
	ufg._input(ev_left)
	await process_frame
	assert(root.gui_get_focus_owner() == skip_btn, "Focus should have moved LEFT to SkipButton, got: %s" % str(root.gui_get_focus_owner()))
	print("  PASS: LEFT navigation from ContinueButton moved to SkipButton.")

	# Move RIGHT: SkipButton -> ContinueButton
	var ev_right = InputEventKey.new()
	ev_right.keycode = KEY_RIGHT
	ev_right.pressed = true
	ufg._input(ev_right)
	await process_frame
	assert(root.gui_get_focus_owner() == cont_btn, "Focus should have moved RIGHT to ContinueButton, got: %s" % str(root.gui_get_focus_owner()))
	print("  PASS: RIGHT navigation from SkipButton moved to ContinueButton.")

	# Move UP from ContinueButton into active Bluetooth tab (should NOT jump to hidden OtherTab IpLocalButton)
	var ev_up = InputEventKey.new()
	ev_up.keycode = KEY_UP
	ev_up.pressed = true
	ufg._input(ev_up)
	await process_frame
	var cur_up_focus = root.gui_get_focus_owner()
	assert(cur_up_focus != null and cur_up_focus.is_visible_in_tree(), "Focused control must be visible")
	assert(cur_up_focus.name != "IpLocalButton" and cur_up_focus.name != "IpAllButton", "Focus must NOT enter hidden OtherTab controls!")
	print("  PASS: UP navigation from ContinueButton safely moved to visible control: %s" % cur_up_focus.name)

	# Analog Stick navigation: simulate Left Stick negative X to move left
	cont_btn.grab_focus()
	await process_frame
	var ev_stick_left = InputEventJoypadMotion.new()
	ev_stick_left.axis = JOY_AXIS_LEFT_X
	ev_stick_left.axis_value = -1.0
	ufg._input(ev_stick_left)
	await process_frame
	assert(root.gui_get_focus_owner() == skip_btn, "Joypad left stick should move focus to SkipButton")
	print("  PASS: Controller analog left stick navigated smoothly to SkipButton.")

	# Test boundary protection: pressing DOWN on ContinueButton keeps focus on ContinueButton
	cont_btn.grab_focus()
	await process_frame
	var ev_down = InputEventKey.new()
	ev_down.keycode = KEY_DOWN
	ev_down.pressed = true
	ufg._input(ev_down)
	await process_frame
	assert(root.gui_get_focus_owner() == cont_btn, "Focus must stay on ContinueButton at bottom boundary")
	print("  PASS: Bottom boundary preserved; focus stayed on ContinueButton.")

	print("\n--- Test 5: Tab switching via TabBar arrows, Q/E keys, and Gamepad Shoulder / Page keys ---")
	tab_container = lm_modal.find_child("TabContainer", true, false) as TabContainer
	assert(tab_container != null, "TabContainer must exist")
	assert(tab_container.current_tab == 0, "Initial tab should be Bluetooth (0)")

	# 1. Switch using TabBar directional navigation (Arrow Left / Right on TabBar)
	var tab_bar = tab_container.get_tab_bar()
	assert(tab_bar != null, "TabBar must exist")
	tab_bar.grab_focus()
	await process_frame
	assert(root.gui_get_focus_owner() == tab_bar, "TabBar should have focus")

	# Press KEY_RIGHT on TabBar -> switches to Other tab (1)
	var ev_arrow_right = InputEventKey.new()
	ev_arrow_right.keycode = KEY_RIGHT
	ev_arrow_right.pressed = true
	ufg._input(ev_arrow_right)
	await process_frame
	await process_frame
	assert(tab_container.current_tab == 1, "TabBar Arrow Right should switch to Other tab (1)")
	print("  PASS: TabBar Arrow Right switched to tab 1 (Other).")

	# Press KEY_LEFT on TabBar -> switches back to Bluetooth tab (0)
	var ev_arrow_left = InputEventKey.new()
	ev_arrow_left.keycode = KEY_LEFT
	ev_arrow_left.pressed = true
	ufg._input(ev_arrow_left)
	await process_frame
	await process_frame
	assert(tab_container.current_tab == 0, "TabBar Arrow Left should switch to Bluetooth tab (0)")
	print("  PASS: TabBar Arrow Left switched back to tab 0 (Bluetooth).")

	# 2. Switch using Q / E keys
	cont_btn.grab_focus()
	await process_frame
	var ev_key_e = InputEventKey.new()
	ev_key_e.keycode = KEY_E
	ev_key_e.pressed = true
	ufg._input(ev_key_e)
	await process_frame
	await process_frame
	assert(tab_container.current_tab == 1, "E key should switch to Other tab (1)")
	print("  PASS: Key E switched to tab 1 (Other).")

	var ev_key_q = InputEventKey.new()
	ev_key_q.keycode = KEY_Q
	ev_key_q.pressed = true
	ufg._input(ev_key_q)
	await process_frame
	await process_frame
	assert(tab_container.current_tab == 0, "Q key should switch back to Bluetooth tab (0)")
	print("  PASS: Key Q switched back to tab 0 (Bluetooth).")

	# 3. Switch using RB / PageDown to Other tab
	var ev_tab_next = InputEventKey.new()
	ev_tab_next.keycode = KEY_PAGEDOWN
	ev_tab_next.pressed = true
	ufg._input(ev_tab_next)
	await process_frame
	await process_frame
	assert(tab_container.current_tab == 1, "PageDown should switch to Other tab (1)")
	var tab1_focus = root.gui_get_focus_owner()
	assert(tab1_focus != null and tab1_focus.is_visible_in_tree(), "Focus after tab switch must be on a visible control")
	print("  PASS: Tab switched to tab 1 (Other) and focused: %s" % tab1_focus.name)

	# Switch using LB / PageUp to Bluetooth tab
	var ev_tab_prev = InputEventKey.new()
	ev_tab_prev.keycode = KEY_PAGEUP
	ev_tab_prev.pressed = true
	ufg._input(ev_tab_prev)
	await process_frame
	await process_frame
	assert(tab_container.current_tab == 0, "PageUp should switch back to Bluetooth tab (0)")
	print("  PASS: Tab switched back to tab 0 (Bluetooth).")

	print("\n--- Test 6: Tab cycling is confined within modal controls ---")
	var ev_tab = InputEventAction.new()
	ev_tab.action = "ui_focus_next"
	ev_tab.pressed = true
	ufg._input(ev_tab)
	await process_frame

	var after_tab_focus = root.gui_get_focus_owner()
	assert(after_tab_focus != null and lm_modal.is_ancestor_of(after_tab_focus), "Tab focus must remain strictly inside LaunchMonitorConnectModal")
	print("  PASS: Tab cycling remains confined inside modal.")

	print("\n--- Test 7: Closing LaunchMonitorConnectModal restores focus ---")
	lm_modal.queue_free()
	await process_frame
	await process_frame

	assert(not ufg.is_modal_active(), "UIFocusGuard.is_modal_active() must be false after modal is freed")
	print("  PASS: Focus lock successfully released on modal close.")

	print("\n--- Test 8: OsmDownloadDialog locks focus, navigates LineEdit down, and confines boundaries ---")
	var osm_scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
	assert(osm_scene != null, "osm_download_dialog.tscn must be loadable")

	var osm_dialog = osm_scene.instantiate()
	bg_container.add_child(osm_dialog)

	await process_frame
	await process_frame

	assert(ufg.is_modal_active(), "UIFocusGuard.is_modal_active() must be true when OsmDownloadDialog is open")
	assert(ufg.current_lock_root() == osm_dialog, "Current lock root must be OsmDownloadDialog")

	var osm_focus = root.gui_get_focus_owner()
	assert(osm_focus != null and osm_dialog.is_ancestor_of(osm_focus), "Focused control must be inside OsmDownloadDialog")
	print("  PASS: OsmDownloadDialog locked focus to: %s" % osm_focus.name)

	var search_in = osm_dialog.find_child("SearchInput", true, false) as LineEdit
	assert(search_in != null, "SearchInput must exist")
	search_in.grab_focus()
	await process_frame

	# Press KEY_DOWN on SearchInput -> moves to ResultsList
	var ev_d = InputEventKey.new()
	ev_d.keycode = KEY_DOWN
	ev_d.pressed = true
	ufg._input(ev_d)
	await process_frame

	var focus_after_down = root.gui_get_focus_owner()
	assert(focus_after_down != null and focus_after_down != search_in, "Focus must have moved DOWN from SearchInput")
	print("  PASS: Navigated DOWN from SearchInput to: %s" % focus_after_down.name)

	# From ResultsList, press KEY_UP -> moves back to SearchInput
	var ev_u = InputEventKey.new()
	ev_u.keycode = KEY_UP
	ev_u.pressed = true
	ufg._input(ev_u)
	await process_frame
	assert(root.gui_get_focus_owner() == search_in, "Focus should have moved UP back to SearchInput")
	print("  PASS: Navigated UP back to SearchInput.")

	# From SearchInput, press KEY_UP -> moves up to OsmDownloadDialog's own SettingsButton
	ufg._input(ev_u)
	await process_frame
	var settings_btn = osm_dialog.find_child("SettingsButton", true, false)
	assert(root.gui_get_focus_owner() == settings_btn, "Focus should have moved UP to dialog's SettingsButton")
	assert(osm_dialog.is_ancestor_of(root.gui_get_focus_owner()), "Focus must remain inside OsmDownloadDialog")
	print("  PASS: Navigated UP to dialog's SettingsButton (%s)." % root.gui_get_focus_owner().name)

	# Boundary test: Press KEY_UP on SettingsButton -> stays on SettingsButton, does not bleed to background
	ufg._input(ev_u)
	await process_frame
	assert(root.gui_get_focus_owner() == settings_btn, "Focus must remain on SettingsButton at top boundary")
	assert(osm_dialog.is_ancestor_of(root.gui_get_focus_owner()), "Focus must not bleed outside modal")
	print("  PASS: Top boundary preserved on SettingsButton without background bleed.")

	# Move DOWN back to SearchInput
	ufg._input(ev_d)
	await process_frame
	assert(root.gui_get_focus_owner() == search_in, "Focus should have moved DOWN back to SearchInput")
	print("  PASS: Navigated DOWN back to SearchInput.")

	print("\n--- Test 9: Course search results auto-selection and download activation ---")
	var results_list = osm_dialog.find_child("ResultsList", true, false) as ItemList
	var download_btn = osm_dialog.find_child("DownloadButton", true, false) as Button
	assert(results_list != null and download_btn != null, "ResultsList and DownloadButton must exist")

	# Populate search results
	var test_courses = [
		{"name": "Pebble Beach Golf Links", "lat": 36.56, "lon": -121.95, "hole_count": 18, "location": "California, US"},
		{"name": "Spyglass Hill Golf Course", "lat": 36.58, "lon": -121.96, "hole_count": 18, "location": "California, US"}
	]
	osm_dialog._display_courses_in_list(test_courses, true)
	await process_frame

	assert(results_list.get_selected_items().size() > 0, "First search result should be automatically selected")
	assert(results_list.get_selected_items()[0] == 0, "Selected item index should be 0")
	assert(download_btn.disabled == false, "DownloadButton should be enabled once course is selected")
	print("  PASS: Search result automatically selected (Pebble Beach) and DownloadButton enabled.")

	# Navigate DOWN from SearchInput to ResultsList
	search_in.grab_focus()
	await process_frame
	ufg._input(ev_d)
	await process_frame
	assert(root.gui_get_focus_owner() == results_list, "Focus should be on ResultsList")

	# Navigate DOWN within ResultsList from course 0 to course 1
	ufg._input(ev_d)
	await process_frame
	assert(results_list.get_selected_items()[0] == 1, "Selection should move DOWN to course 1 (Spyglass Hill)")
	print("  PASS: DOWN within ResultsList selected course 1 (Spyglass Hill).")

	# Navigate DOWN from course 1 (last course) -> moves focus to footer buttons
	var cancel_btn = osm_dialog.find_child("CancelButton", true, false) as Button
	ufg._input(ev_d)
	await process_frame
	var cur_footer = root.gui_get_focus_owner()
	assert(cur_footer == download_btn or cur_footer == cancel_btn, "Focus should move from bottom of ResultsList to footer buttons, got: %s" % str(cur_footer))
	if cur_footer == cancel_btn:
		var ev_r = InputEventKey.new()
		ev_r.keycode = KEY_RIGHT
		ev_r.pressed = true
		ufg._input(ev_r)
		await process_frame
		assert(root.gui_get_focus_owner() == download_btn, "Moving RIGHT should focus DownloadButton")
	print("  PASS: DOWN from bottom of ResultsList moved focus to footer buttons (%s)." % root.gui_get_focus_owner().name)

	# Navigate UP from footer buttons -> moves focus back to ResultsList
	ufg._input(ev_u)
	await process_frame
	assert(root.gui_get_focus_owner() == results_list, "Focus should move UP from footer buttons back to ResultsList")
	print("  PASS: UP from footer buttons moved focus back to ResultsList.")

	# Clean up OsmDownloadDialog
	osm_dialog.queue_free()
	await process_frame
	await process_frame

	assert(not ufg.is_modal_active(), "UIFocusGuard.is_modal_active() must be false after OsmDownloadDialog is freed")
	print("  PASS: OsmDownloadDialog closed and focus lock cleared.")

	bg_container.queue_free()
	print("\n=== ALL MODAL FOCUS ISOLATION TESTS PASSED ===")
	quit(0)
