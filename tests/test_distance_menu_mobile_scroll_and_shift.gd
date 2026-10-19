extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== Running DistanceMenu Mobile Scrollbar & Shift Tests ===")
	# =========================================================================
	# TEST 1: DistanceMenu Scrollbar Styling & Touch Helper
	# =========================================================================
	print("\n--- Test 1: DistanceMenu Scrollbar & TouchScrollHelper ---")
	var dist_menu_script = load("res://UI/distance_menu.gd")
	assert(dist_menu_script != null, "distance_menu.gd must load")

	var dist_menu = dist_menu_script.new()
	root.add_child(dist_menu)

	assert(dist_menu.size_flags_horizontal == Control.SIZE_SHRINK_BEGIN, "DistanceMenu should align to start (left)")
	assert(dist_menu.custom_minimum_size.x >= 340.0, "DistanceMenu min width should be at least 340")

	var scroll = dist_menu.find_child("ScrollContainer", true, false) as ScrollContainer
	if scroll == null:
		for ch in dist_menu.get_children():
			if ch is ScrollContainer:
				scroll = ch
				break
	assert(scroll != null, "DistanceMenu must contain a ScrollContainer")
	assert(scroll.follow_focus, "ScrollContainer must have follow_focus enabled")

	var v_bar = scroll.get_v_scroll_bar()
	assert(v_bar != null, "ScrollContainer must have a VScrollBar")

	var is_mob = MobilePerformance.is_mobile()
	var expected_scrollbar_w = 56 if is_mob else 28
	assert(v_bar.custom_minimum_size.x >= expected_scrollbar_w, "VScrollBar width (%f) must be >= %d" % [v_bar.custom_minimum_size.x, expected_scrollbar_w])

	var touch_helper = scroll.get_node_or_null("TouchScrollHelper")
	assert(touch_helper != null, "TouchScrollHelper must be attached to DistanceMenu's ScrollContainer")

	var scroll_margin = scroll.get_node_or_null("ScrollMargin") as MarginContainer
	assert(scroll_margin != null, "DistanceMenu ScrollContainer must contain ScrollMargin to prevent slider overlapping buttons")
	var margin_r = scroll_margin.get_theme_constant("margin_right")
	assert(margin_r >= int(v_bar.custom_minimum_size.x), "ScrollMargin margin_right (%d) must be >= scrollbar width (%d)" % [margin_r, int(v_bar.custom_minimum_size.x)])

	var backspin_btn = dist_menu.find_child("100YBackspinButton", true, false) as Button
	assert(backspin_btn != null, "100-Yard Backspin button must exist in DistanceMenu")
	assert(backspin_btn.text == "🔄 100-Yard Backspin", "Backspin button text must match")

	var emitted_shots = []
	dist_menu.inject_shot.connect(func(data): emitted_shots.append(data))
	dist_menu._on_hit_100y_backspin()
	assert(emitted_shots.size() == 1, "Must emit shot on _on_hit_100y_backspin")
	var shot = emitted_shots[0]
	assert(shot["TotalSpin"] >= 9750.0 and shot["TotalSpin"] <= 10250.0, "TotalSpin must be ~10,000 RPM")
	assert(shot["BackSpin"] >= 9750.0 and shot["BackSpin"] <= 10250.0, "BackSpin must be ~10,000 RPM")
	assert(shot["VLA"] >= 28.0 and shot["VLA"] <= 31.0, "VLA must be high wedge angle")
	assert(abs(shot["SpinAxis"]) <= 0.6, "SpinAxis must be near 0")

	print("  PASS: DistanceMenu scrollbar width (%d), TouchScrollHelper, ScrollMargin padding (%d), and 100Y Backspin button verified." % [int(v_bar.custom_minimum_size.x), margin_r])
	dist_menu.queue_free()

	# =========================================================================
	# TEST 2: RangeUI Helper Layout Shift on DistanceMenu Visibility
	# =========================================================================
	print("\n--- Test 2: RangeUI Helper Layout Shift with DistanceMenu ---")
	var range_scene = load("res://Courses/Range/range.tscn")
	assert(range_scene != null, "range.tscn must load")

	var range_instance = range_scene.instantiate()
	root.add_child(range_instance)

	for f in range(3):
		await process_frame

	var rui = range_instance.get_node_or_null("RangeUI")
	assert(rui != null, "RangeUI must exist in range_instance")

	var r_right_panel = rui.get("_right_panel") as Control
	assert(r_right_panel != null, "RangeUI must have _right_panel")

	var r_dist_menu = rui.find_child("DistanceMenu", true, false) as Control
	assert(r_dist_menu != null, "DistanceMenu must exist in RangeUI")
	assert(not r_dist_menu.visible, "DistanceMenu should start hidden")

	var r_toggles_scroll = rui.get("_toggles_scroll") as ScrollContainer
	assert(r_toggles_scroll != null, "RangeUI must have _toggles_scroll")

	# Show helpers scroll
	r_toggles_scroll.visible = true
	for f in range(2):
		await process_frame
	rui.call("_update_helpers_scroll_layout")
	await process_frame

	var initial_offset = r_right_panel.offset_left
	print("  Initial RangeUI offset_left with DistanceMenu hidden: %f" % initial_offset)

	# Open DistanceMenu
	r_dist_menu.visible = true
	rui.call("_update_helpers_scroll_layout")
	for f in range(2):
		await process_frame

	var shifted_offset = r_right_panel.offset_left
	print("  Shifted RangeUI offset_left with DistanceMenu visible: %f" % shifted_offset)
	assert(shifted_offset < initial_offset, "RangeUI _right_panel must shift further left when DistanceMenu is visible (%f < %f)" % [shifted_offset, initial_offset])
	var expected_dist_shift = 220.0 if is_mob else 160.0
	var r_v_bar = r_toggles_scroll.get_v_scroll_bar()
	var r_scroll_w = int(r_v_bar.size.x) if (r_v_bar != null and r_v_bar.visible) else (int(r_v_bar.custom_minimum_size.x) if r_v_bar != null and r_v_bar.visible else 0)
	var r_shift = (r_scroll_w + 6) if r_scroll_w > 0 else 0
	var r_expected_shifted_offset = -280.0 - r_shift - expected_dist_shift
	assert(is_equal_approx(shifted_offset, r_expected_shifted_offset), "RangeUI _right_panel shifted offset (%f) should match expected (%f)" % [shifted_offset, r_expected_shifted_offset])

	# Close DistanceMenu by pressing HitDistanceButton while open
	var r_dist_btn = rui.find_child("HitDistanceButton", true, false) as Button
	assert(r_dist_btn != null, "RangeUI must have HitDistanceButton")
	assert(r_dist_btn.action_mode == BaseButton.ACTION_MODE_BUTTON_PRESS, "HitDistanceButton must trigger on press")
	assert(r_dist_btn.get_meta("toggle_target") == r_dist_menu, "HitDistanceButton meta toggle_target must be r_dist_menu")

	# Focus HitDistanceButton while focus lock is active - focus should NOT be snatched away
	r_dist_btn.grab_focus()
	for f in range(2):
		await process_frame
	var cur_f = root.get_viewport().gui_get_focus_owner()
	assert(cur_f == r_dist_btn, "HitDistanceButton must retain focus even when UIFocusGuard has DistanceMenu locked")

	# Press HitDistanceButton to close
	r_dist_btn.emit_signal("pressed")
	for f in range(2):
		await process_frame
	assert(not r_dist_menu.visible, "Pressing HitDistanceButton while open must close DistanceMenu")

	var restored_offset = r_right_panel.offset_left
	print("  Restored RangeUI offset_left with DistanceMenu hidden: %f" % restored_offset)
	assert(is_equal_approx(restored_offset, initial_offset), "RangeUI _right_panel offset_left must restore when DistanceMenu is hidden (%f == %f)" % [restored_offset, initial_offset])
	print("  PASS: RangeUI helper layout shift and HitDistanceButton close verified.")
	range_instance.queue_free()

	# =========================================================================
	# TEST 3: CoursePlay Helper Layout Shift on DistanceMenu Visibility
	# =========================================================================
	print("\n--- Test 3: CoursePlay Helper Layout Shift with DistanceMenu ---")
	var course_play_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(course_play_script != null, "course_play.gd must load")

	var cp = Node3D.new()
	cp.set_script(course_play_script)
	root.add_child(cp)

	for f in range(3):
		await process_frame

	var cp_right_panel = cp.get("right_panel") as Control
	assert(cp_right_panel != null, "CoursePlay must have right_panel")

	var cp_toggles_scroll = cp.get("toggles_scroll") as ScrollContainer
	assert(cp_toggles_scroll != null, "CoursePlay must have toggles_scroll")

	var cp_dist_menu = cp_toggles_scroll.find_child("DistanceMenu", true, false) as Control
	assert(cp_dist_menu != null, "DistanceMenu must exist in CoursePlay")
	assert(not cp_dist_menu.visible, "DistanceMenu should start hidden")

	# Show helpers scroll
	cp_toggles_scroll.visible = true
	cp.call("_update_helpers_scroll_layout")
	for f in range(2):
		await process_frame

	var cp_initial_offset = cp_right_panel.offset_left
	print("  Initial CoursePlay offset_left with DistanceMenu hidden: %f" % cp_initial_offset)

	# Open DistanceMenu
	cp_dist_menu.visible = true
	cp.call("_update_helpers_scroll_layout")
	for f in range(2):
		await process_frame

	var cp_shifted_offset = cp_right_panel.offset_left
	print("  Shifted CoursePlay offset_left with DistanceMenu visible: %f" % cp_shifted_offset)
	var cp_v_bar = cp_toggles_scroll.get_v_scroll_bar()
	var cp_scroll_w = int(cp_v_bar.size.x) if (cp_v_bar != null and cp_v_bar.visible) else (int(cp_v_bar.custom_minimum_size.x) if cp_v_bar != null and cp_v_bar.visible else 0)
	var cp_shift = (cp_scroll_w + 6) if cp_scroll_w > 0 else 0
	var expected_shifted_offset = -280.0 - cp_shift - expected_dist_shift
	assert(is_equal_approx(cp_shifted_offset, expected_shifted_offset), "CoursePlay right_panel shifted offset (%f) should match expected (%f)" % [cp_shifted_offset, expected_shifted_offset])

	# Close DistanceMenu
	cp_dist_menu.visible = false
	cp.call("_update_helpers_scroll_layout")
	for f in range(2):
		await process_frame

	var cp_restored_offset = cp_right_panel.offset_left
	print("  Restored CoursePlay offset_left with DistanceMenu hidden: %f" % cp_restored_offset)
	assert(is_equal_approx(cp_restored_offset, cp_initial_offset), "CoursePlay right_panel offset_left must restore when DistanceMenu is hidden (%f == %f)" % [cp_restored_offset, cp_initial_offset])
	print("  PASS: CoursePlay helper layout shift verified.")
	cp.queue_free()

	print("\n=======================================================")
	print("ALL DISTANCE MENU MOBILE SCROLL & SHIFT TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
