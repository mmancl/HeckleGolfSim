extends SceneTree

# Targeted test for Toggle Helpers Scrollbar layout & ScreenOffset Center Buttons
var _tested := false


func _initialize() -> void:
	print("=== Running Toggle Helpers & Offset Center Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	# =========================================================================
	# TEST 1: ScreenOffsetControl Center Buttons for General & Putter Offsets
	# =========================================================================
	print("\n--- Test 1: ScreenOffsetControl Center Buttons ---")
	var so_ctrl_script = load("res://UI/ScreenOffset/screen_offset_control.gd")
	assert(so_ctrl_script != null, "screen_offset_control.gd must load")

	if root.has_node("GlobalSettings"):
		root.get_node("GlobalSettings").range_settings.screen_offset_enabled.value = true

	var so_ctrl = so_ctrl_script.new()
	so_ctrl.is_course_play = true
	so_ctrl.show_putter_slider = true
	root.add_child(so_ctrl)

	assert(so_ctrl._center_btn != null, "General offset center button must exist in Course Play mode")
	assert(so_ctrl._putter_center_btn != null, "Putter offset center button must exist in Course Play mode")
	assert(so_ctrl._value_label != null, "General value label must exist")
	assert(so_ctrl._putter_value_label != null, "Putter value label must exist")

	# Test centering actions
	so_ctrl._slider.value = 0.6
	assert(so_ctrl._slider.value > 0.1, "Slider value should be updated")
	so_ctrl._on_center_pressed()
	assert(is_zero_approx(so_ctrl._slider.value), "General slider must reset to 0.0 on center pressed")
	assert(so_ctrl._value_label.text == "Center", "Value label should read Center after reset")

	so_ctrl._putter_slider.value = -0.75
	assert(so_ctrl._putter_slider.value < -0.1, "Putter slider value should be updated")
	so_ctrl._on_putter_center_pressed()
	assert(is_zero_approx(so_ctrl._putter_slider.value), "Putter slider must reset to 0.0 on putter center pressed")
	assert(so_ctrl._putter_value_label.text == "Center", "Putter value label should read Center after reset")

	# Test focusables sequence
	var focusables = so_ctrl.get_focusables()
	assert(focusables.size() == 5, "Focusables must contain [Toggle, GeneralSlider, GeneralCenter, PutterSlider, PutterCenter]")
	assert(focusables[0] == so_ctrl._toggle_btn)
	assert(focusables[1] == so_ctrl._slider)
	assert(focusables[2] == so_ctrl._center_btn)
	assert(focusables[3] == so_ctrl._putter_slider)
	assert(focusables[4] == so_ctrl._putter_center_btn)
	print("  PASS: ScreenOffsetControl center buttons and values verified.")

	so_ctrl.queue_free()

	# =========================================================================
	# TEST 2: Toggle Helpers Scrollbar Dynamic Offset Shift
	# =========================================================================
	print("\n--- Test 2: Toggle Helpers Scrollbar Dynamic Layout Shift ---")

	var right_panel = VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_top = 0.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -280
	right_panel.offset_top = 166
	right_panel.offset_right = -24
	right_panel.offset_bottom = -96
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(right_panel)

	var toggles_scroll = ScrollContainer.new()
	toggles_scroll.name = "TogglesScroll"
	toggles_scroll.visible = true
	toggles_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	toggles_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toggles_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	right_panel.add_child(toggles_scroll)

	var toggles_container = VBoxContainer.new()
	toggles_container.name = "TogglesContainer"
	toggles_container.add_theme_constant_override("separation", 12)
	toggles_container.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggles_container.custom_minimum_size = Vector2(256, 0)
	toggles_scroll.add_child(toggles_container)

	var v_bar = toggles_scroll.get_v_scroll_bar()
	ThemeManager.apply_scroll_container_style(toggles_scroll, 28)

	var update_scroll_layout = func():
		var is_bar_visible = v_bar != null and v_bar.visible and toggles_scroll.visible
		var scroll_w = int(v_bar.size.x) if (v_bar != null and is_bar_visible) else 0
		if scroll_w <= 0 and is_bar_visible and v_bar != null:
			scroll_w = int(v_bar.custom_minimum_size.x)
		var shift = (scroll_w + 6) if scroll_w > 0 else 0
		right_panel.offset_left = -280 - shift

	v_bar.visibility_changed.connect(func(): update_scroll_layout.call_deferred())
	toggles_scroll.visibility_changed.connect(func(): update_scroll_layout.call_deferred())
	toggles_scroll.resized.connect(func(): update_scroll_layout.call_deferred())
	toggles_container.resized.connect(func(): update_scroll_layout.call_deferred())

	# Case A: Only 2 buttons (content fits without scrolling)
	for i in range(2):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(180, 56)
		toggles_container.add_child(btn)

	for f in range(5):
		await process_frame

	update_scroll_layout.call()
	assert(not v_bar.visible, "Scrollbar should NOT be visible when items fit")
	assert(is_equal_approx(right_panel.offset_left, -280.0), "Right panel offset_left must be default -280 when not scrolling")

	# Case B: 20 buttons (content overflows -> scrollbar visible)
	for i in range(18):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(180, 56)
		toggles_container.add_child(btn)

	for f in range(5):
		await process_frame

	update_scroll_layout.call()
	assert(v_bar.visible, "Scrollbar MUST be visible when content overflows")
	assert(right_panel.offset_left < -280.0, "Right panel must be pushed to the left when scrollbar is visible")

	var btn_first = toggles_container.get_child(0) as Button
	var btn_right_edge = btn_first.global_position.x + btn_first.size.x
	var v_bar_left_edge = v_bar.global_position.x

	assert(btn_right_edge <= v_bar_left_edge, "Button right edge (%f) must NOT overlap scrollbar left edge (%f)" % [btn_right_edge, v_bar_left_edge])
	print("  PASS: When scrollbar is visible, buttons pushed to the left (%f < %f) without overlap." % [btn_right_edge, v_bar_left_edge])

	# Case C: Remove buttons back to fitting
	while toggles_container.get_child_count() > 2:
		var ch = toggles_container.get_child(toggles_container.get_child_count() - 1)
		toggles_container.remove_child(ch)
		ch.queue_free()

	for f in range(5):
		await process_frame

	update_scroll_layout.call()
	assert(not v_bar.visible, "Scrollbar should hide when items fit again")
	assert(is_equal_approx(right_panel.offset_left, -280.0), "Right panel must return to -280 when not scrolling")
	print("  PASS: When scrollbar hides, panel restored to -280.")

	right_panel.queue_free()

	print("\n=======================================================")
	print("ALL TOGGLE HELPERS & OFFSET TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit()
