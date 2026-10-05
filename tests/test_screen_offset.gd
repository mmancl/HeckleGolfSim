extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Screen Offset Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	var global_settings = root.get_node_or_null("GlobalSettings")
	assert(global_settings != null, "GlobalSettings autoload must exist in scene tree")
	var rs = global_settings.range_settings
	assert(rs != null, "range_settings must exist")
	assert("screen_offset_enabled" in rs, "screen_offset_enabled setting must exist")
	assert("screen_offset_value" in rs, "screen_offset_value setting must exist")

	var som = root.get_node_or_null("ScreenOffsetManager")
	assert(som != null, "ScreenOffsetManager autoload must exist in scene tree")

	# Test 1: Settings persistence and target calculation
	print("\n--- Test 1: Settings & Target Calculation ---")
	rs.screen_offset_enabled.value = false
	rs.screen_offset_value.value = 0.5
	assert(is_equal_approx(som.get_target(), 0.0), "Target should be 0 when disabled")

	rs.screen_offset_enabled.value = true
	assert(is_equal_approx(som.get_target(), 0.5), "Target should match setting when enabled")

	som.set_suppressed(true)
	assert(is_equal_approx(som.get_target(), 0.0), "Target should be 0 when suppressed")
	som.set_suppressed(false)
	assert(is_equal_approx(som.get_target(), 0.5), "Target should restore when unsuppressed")
	print("  PASS: Settings & Target Calculation verified.")

	# Test 2: Physical Lateral Displacement & Perspective Preservation
	print("\n--- Test 2: Physical Lateral Displacement & Perspective Preservation ---")
	var cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	root.add_child(cam)
	cam.global_position = Vector3(0.0, 1.5, -5.0)

	som.register_camera(cam)

	var orig_x = cam.global_position.x

	# Apply 0 offset: no displacement, perspective intact
	som._apply(0.0)
	assert(cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "0 offset must use PERSPECTIVE")
	assert(is_equal_approx(cam.global_position.x, orig_x), "0 offset should not translate camera")

	# Apply 0.5 offset: physical right shift
	som._apply(0.5)
	assert(cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "Offset must maintain standard PERSPECTIVE (no frustum distortion)")
	var expected_shift = 0.5 * som.MAX_LATERAL_OFFSET_METERS
	assert(is_equal_approx(cam.global_position.x, orig_x + expected_shift), "0.5 offset must physically translate camera right by expected meters")
	print("  PASS: Physical Lateral Displacement & Perspective Preservation verified.")

	# Test 3: Shot Sequence & Return
	print("\n--- Test 3: Shot Sequence & Return ---")
	som.on_ready_for_shot(0.0, true)
	assert(is_equal_approx(som._current, 0.5), "Current offset should be 0.5 at address")
	assert(is_equal_approx(cam.global_position.x, orig_x + expected_shift), "Camera should remain shifted at address")

	som.on_shot_started()
	assert(is_equal_approx(som.get_target(), 0.0), "Target in flight must be 0")

	som.on_ready_for_shot(0.0, true)
	assert(is_equal_approx(som._current, 0.5), "Current offset should restore to 0.5 when ready")
	print("  PASS: Shot Sequence & Return verified.")

	# Test 4: ScreenOffsetControl widget creation
	print("\n--- Test 4: ScreenOffsetControl UI Widget ---")
	var so_ctrl_script = load("res://UI/ScreenOffset/screen_offset_control.gd")
	assert(so_ctrl_script != null, "screen_offset_control.gd must load")
	var so_ctrl = so_ctrl_script.new()
	root.add_child(so_ctrl)
	assert(so_ctrl.get_node_or_null("ScreenOffsetToggleButton") != null, "Toggle button should exist")
	assert(so_ctrl.get_node_or_null("SliderContainer") != null, "SliderContainer should exist")
	var focusables = so_ctrl.get_focusables()
	assert(focusables.size() >= 1, "Should have focusable controls")
	so_ctrl.queue_free()
	print("  PASS: ScreenOffsetControl UI Widget verified.")

	# Test 5: Camera Unregister
	print("\n--- Test 5: Camera Unregister ---")
	som.unregister_camera(cam)
	assert(cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "Unregistering must restore PERSPECTIVE")
	assert(is_equal_approx(cam.global_position.x, orig_x), "Unregistering must restore original camera position")
	cam.queue_free()
	print("  PASS: Camera Unregister verified.")

	# Test 6: Dual Putter Offset & Course Play Mode
	print("\n--- Test 6: Dual Putter Offset & Course Play Mode ---")
	assert("screen_offset_putter_value" in rs, "screen_offset_putter_value must exist in range_settings")
	rs.screen_offset_enabled.value = true
	rs.screen_offset_value.value = 0.4
	rs.screen_offset_putter_value.value = -0.6

	som.set_putter_active(false)
	assert(is_equal_approx(som.get_target(), 0.4), "When putter inactive, target should be general offset value (0.4)")

	som.set_putter_active(true)
	assert(is_equal_approx(som.get_target(), -0.6), "When putter active, target should be putter offset value (-0.6)")

	# Verify Course Play UI mode (no recenter button, no percent label, dual sliders present)
	var cp_so_ctrl = so_ctrl_script.new()
	cp_so_ctrl.is_course_play = true
	cp_so_ctrl.show_putter_slider = true
	root.add_child(cp_so_ctrl)

	assert(cp_so_ctrl._center_btn == null, "Recenter button must not exist in Course Play mode")
	assert(cp_so_ctrl._value_label == null, "Percent value label must not exist in Course Play mode")
	assert(cp_so_ctrl._putter_slider != null, "Putter slider must exist when show_putter_slider is true")
	assert(cp_so_ctrl._slider != null, "General offset slider must exist")

	var cp_focusables = cp_so_ctrl.get_focusables()
	assert(cp_focusables.size() == 3, "Focusables in course play should be [ToggleBtn, GeneralSlider, PutterSlider]")
	assert(cp_focusables[0] == cp_so_ctrl._toggle_btn)
	assert(cp_focusables[1] == cp_so_ctrl._slider)
	assert(cp_focusables[2] == cp_so_ctrl._putter_slider)

	cp_so_ctrl.queue_free()
	som.set_putter_active(false)

	rs.screen_offset_enabled.value = false
	rs.screen_offset_value.value = 0.0
	rs.screen_offset_putter_value.value = 0.0
	print("  PASS: Dual Putter Offset & Course Play Mode verified.")

	print("\n=======================================================")
	print("ALL SCREEN OFFSET TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)
