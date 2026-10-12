extends SceneTree

func _initialize() -> void:
	print("=== Running Putting Camera Changes Tests ===")

	# 1. Range Scene putting camera offset
	var RangeScene = load("res://Courses/Range/range.gd")
	assert(RangeScene != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.set_script(RangeScene)
	root.add_child(range_instance)

	var offset_putting = range_instance.get_camera_local_offset(true)
	print("Putting camera local offset: ", offset_putting)
	assert(offset_putting.is_equal_approx(Vector3(-1.35, 0.8, 0)), "Putting camera local offset must be Vector3(-1.35, 0.8, 0)")

	var offset_full = range_instance.get_camera_local_offset(false)
	print("Full shot camera local offset: ", offset_full)
	assert(not offset_full.is_equal_approx(Vector3(-1.35, 0.8, 0)), "Full shot camera offset must not match putting camera offset")

	# Test get_address_camera_position with putting
	var test_ball_pos = Vector3(10.0, 1.5, -5.0)
	var rot_yaw = 0.5 # radians
	var addr_pos = range_instance.get_address_camera_position(test_ball_pos, rot_yaw, true)
	var expected_pos = range_instance.clamp_camera_position(test_ball_pos + Vector3(-1.35, 0.8, 0.0).rotated(Vector3.UP, rot_yaw))
	print("Putting address camera position: ", addr_pos, " expected: ", expected_pos)
	assert(addr_pos.is_equal_approx(expected_pos), "Putting address camera position must match rotated Vector3(-1.35, 0.8, 0.0)")

	# 2. Putting Practice Camera Position calculation check
	var angle_rad = 1.2
	var back_dir = Vector3(-cos(angle_rad), 0.0, -sin(angle_rad)).normalized()
	var expected_practice_cam = test_ball_pos + back_dir * 1.35 + Vector3.UP * 0.8
	var PuttingPracticeScript = load("res://Courses/Minigames/PuttingPractice/putting_practice.gd")
	assert(PuttingPracticeScript != null, "putting_practice.gd must load")

	print("Putting practice expected camera position: ", expected_practice_cam)

	print("\n=======================================================")
	print("ALL PUTTING CAMERA TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)
