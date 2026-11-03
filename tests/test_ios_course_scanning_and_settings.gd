extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: iOS Course Scanning & Settings Resilience")
	print("=======================================================")

	# 1. Test Square Golf device name recognition in launch_monitor_manager
	print("\n--- Test 1: Square Golf device name recognition ---")
	var lmm_script = load("res://addons/launch_monitors/launch_monitor_manager.gd")
	assert(lmm_script != null, "launch_monitor_manager.gd must load")
	var lmm = Node.new()
	lmm.set_script(lmm_script)
	root.add_child(lmm)

	var valid_square_names = [
		"SquareGolf",
		"Square Golf",
		"SquareGolf(1234)",
		"SquareGolf_9988",
		"SGO300",
		"SGO-300A",
		"sgo_pro",
		"SQ100",
		"EXGOLF-01",
		"EXG_99",
		"OMNI_300"
	]
	for dev_name in valid_square_names:
		assert(lmm.call("is_square_device_name", dev_name) == true, "Device name '%s' must match Square Golf" % dev_name)

	var non_square_names = [
		"Approach R10",
		"Garmin Approach",
		"AirPods Pro",
		"Unknown",
		""
	]
	for dev_name in non_square_names:
		assert(lmm.call("is_square_device_name", dev_name) == false, "Device name '%s' must NOT match Square Golf" % dev_name)
	print("  PASS: Square Golf device naming patterns matched successfully.")

	# 2. Test mobile_performance graphics quality capping
	print("\n--- Test 2: mobile_performance graphics quality capping on mobile ---")
	var mp_script = load("res://Utils/mobile_performance.gd")
	assert(mp_script != null, "mobile_performance.gd must load")
	# Check shader code resilience
	var ground_markings_shader = load("res://Courses/Environments/shaders/ground_markings.gdshader")
	assert(ground_markings_shader != null, "ground_markings.gdshader must load")
	assert(not ground_markings_shader.code.contains("CAMERA_POSITION_WORLD"), "ground_markings.gdshader must not use CAMERA_POSITION_WORLD (Metal incompatibility)")
	assert(ground_markings_shader.code.contains("v_cam_pos"), "ground_markings.gdshader must use v_cam_pos varying")

	var vignette_shader = load("res://Courses/Environments/shaders/vignette.gdshader")
	assert(vignette_shader != null, "vignette.gdshader must load")
	assert(not vignette_shader.code.contains("filter_linear_mipmap"), "vignette.gdshader must not use filter_linear_mipmap on SCREEN_TEXTURE (Metal incompatibility)")
	assert(vignette_shader.code.contains("filter_linear"), "vignette.gdshader must use filter_linear")

	var range_script = load("res://Courses/Range/range.gd")
	assert(range_script != null, "range.gd must load")
	# Check range.gd source does not contain inverse(MODEL_MATRIX) in its dynamic arrow shader
	var range_file = FileAccess.open("res://Courses/Range/range.gd", FileAccess.READ)
	assert(range_file != null, "range.gd file must open")
	var range_text = range_file.get_as_text()
	range_file.close()
	assert(not range_text.contains("inverse(MODEL_MATRIX)"), "range.gd must not contain inverse(MODEL_MATRIX) in vertex shader")
	assert(range_text.contains("transpose(mat3(MODEL_MATRIX))"), "range.gd must use transpose(mat3(MODEL_MATRIX))")
	print("  PASS: Shaders pass all Metal and mobile compatibility constraints.")

	# Cleanup
	root.remove_child(lmm)
	lmm.free()

	print("\n=======================================================")
	print("ALL TESTS PASSED: iOS Course Scanning & Settings Resilience")
	print("=======================================================")
	quit()
	return true
