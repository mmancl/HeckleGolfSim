extends SceneTree

# Targeted Unit Test: Golf Ball Size, Regulation Cup (Hole) Geometry, and Address Camera Framing

func _initialize() -> void:
	print("\n=======================================================")
	print("  Running Ball & Hole Size and Address Camera Tests")
	print("=======================================================\n")

	test_regulation_cup_geometry()
	test_address_camera_distance()
	test_ball_visual_scale_and_offsets()

	print("\n=======================================================")
	print("  ALL BALL & HOLE SIZE / CAMERA TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)


func test_regulation_cup_geometry() -> void:
	print("--- Test 1: Regulation Cup (Hole) Geometry ---")
	var RangeScript = load("res://Courses/Range/range.gd")
	assert(RangeScript != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.set_script(RangeScript)
	root.add_child(range_instance)

	# 1. Regulation cup radius check
	assert(is_equal_approx(range_instance.cup_radius, 0.054), "Range cup_radius must be 0.054m (regulation 4.25 in diameter), got: %f" % range_instance.cup_radius)
	print("  PASS: Range cup_radius is 0.054m (regulation 4.25 inch diameter).")

	# 2. Spawning flag pin checks visual cup liner and inner hole meshes
	range_instance.current_hole_location = Vector3(20.0, 0.0, 0.0)
	range_instance._spawn_flag_pin()
	var pin_node = range_instance.get_node_or_null("FlagPin")
	assert(pin_node != null, "FlagPin must exist")

	var cup_white = pin_node.get_node_or_null("CupWhite") as MeshInstance3D
	assert(cup_white != null, "CupWhite mesh must exist")
	var white_mesh = cup_white.mesh as CylinderMesh
	assert(white_mesh != null, "CupWhite must have a CylinderMesh")
	assert(is_equal_approx(white_mesh.top_radius, 0.054), "CupWhite top_radius must match cup_radius 0.054m, got: %f" % white_mesh.top_radius)
	print("  PASS: CupWhite rim radius correctly matches 0.054m.")

	var cup_dark = pin_node.get_node_or_null("Cup") as MeshInstance3D
	assert(cup_dark != null, "Cup inner dark mesh must exist")
	var dark_mesh = cup_dark.mesh as CylinderMesh
	assert(dark_mesh != null, "Cup must have a CylinderMesh")
	assert(dark_mesh.top_radius < 0.054 and dark_mesh.top_radius >= 0.045, "Cup dark interior radius must fit inside cup rim (0.048m), got: %f" % dark_mesh.top_radius)
	print("  PASS: Cup inner dark mesh radius (%.3fm) cleanly fits within 0.054m outer liner." % dark_mesh.top_radius)

	# 3. Putting Practice cup radius
	var PuttingPracticeScript = load("res://Courses/Minigames/PuttingPractice/putting_practice.gd")
	assert(PuttingPracticeScript != null, "putting_practice.gd must load")
	var pp_instance = Node3D.new()
	pp_instance.set_script(PuttingPracticeScript)
	root.add_child(pp_instance)
	assert(is_equal_approx(pp_instance.cup_radius, 0.054), "PuttingPractice cup_radius must be 0.054m, got: %f" % pp_instance.cup_radius)
	print("  PASS: PuttingPractice cup_radius is 0.054m.")

	# 4. Ball _get_cup_radius fallback
	var BallScript = load("res://Player/ball.gd")
	var ball = BallScript.new()
	root.add_child(ball)
	assert(is_equal_approx(ball._get_cup_radius(), 0.054), "ball._get_cup_radius() fallback must be 0.054m, got: %f" % ball._get_cup_radius())
	print("  PASS: ball._get_cup_radius() returns regulation 0.054m.")

	ball.queue_free()
	pp_instance.queue_free()
	range_instance.queue_free()


func test_address_camera_distance() -> void:
	print("\n--- Test 2: Address Camera Distance & Framing ---")
	var RangeScript = load("res://Courses/Range/range.gd")
	var range_instance = Node3D.new()
	range_instance.set_script(RangeScript)
	root.add_child(range_instance)

	var ball_pos = Vector3(0.0, 0.0, 0.0)
	var rot_yaw = 0.0

	var cam_pos = range_instance.get_address_camera_position(ball_pos, rot_yaw, false)
	# For rot_yaw = 0, back_dir is (-1, 0, 0), so cam_pos should be ball_pos + (-cam_dist, cam_height, 0)
	var expected_dist = 3.6
	var expected_height = 1.35
	assert(is_equal_approx(cam_pos.x, -expected_dist), "Address camera X should be -3.6m behind ball, got: %f" % cam_pos.x)
	assert(is_equal_approx(cam_pos.y, expected_height), "Address camera Y should be 1.35m high, got: %f" % cam_pos.y)
	assert(is_equal_approx(cam_pos.z, 0.0), "Address camera Z should be 0.0, got: %f" % cam_pos.z)
	print("  PASS: Address camera positioned at (-%.1fm, %.2fm) behind ball for full shots (well framed, ball no longer a speck)." % [expected_dist, expected_height])

	# Check aiming address camera position (smooth clamped default)
	var aiming_cam_pos = range_instance.get_address_camera_position(ball_pos, rot_yaw, false, true)
	assert(is_equal_approx(aiming_cam_pos.x, -expected_dist), "Aiming address camera X should match expected dist")
	assert(is_equal_approx(aiming_cam_pos.y, expected_height), "Aiming address camera Y should match expected height")
	print("  PASS: get_address_camera_position with is_aiming=true returns smooth camera position.")

	range_instance.queue_free()


func test_ball_visual_scale_and_offsets() -> void:
	print("\n--- Test 3: Ball Visual Scale and Alignment Offsets ---")
	var BallScript = load("res://Player/ball.gd")
	var ball = BallScript.new()
	root.add_child(ball)
	ball.initialize_ball()

	# 1. Default visual scale
	var default_scale = ball.get_visual_scale()
	assert(is_equal_approx(default_scale, 1.35), "Default visual scale should be 1.35x, got: %f" % default_scale)
	print("  PASS: Default visual scale is 1.35x.")

	# 2. Mesh scale and Y offset
	var expected_mesh_scale = (ball._ball_radius / 1.007168) * 1.35
	assert(is_equal_approx(ball.get_mesh_scale(), expected_mesh_scale), "Mesh scale calculation must match (radius / 1.007168) * 1.35")
	var expected_y_off = ball._ball_radius * 0.35
	assert(is_equal_approx(ball.get_visual_y_offset(), expected_y_off), "Visual Y offset must equal radius * 0.35")
	print("  PASS: Mesh scale and ground-alignment Y offset calculated accurately.")

	# 3. Ball mesh instance transform
	assert(ball._ball_mesh != null, "_ball_mesh must be instantiated")
	var mesh_scale_vec = ball._ball_mesh.scale
	assert(is_equal_approx(mesh_scale_vec.x, expected_mesh_scale), "ball._ball_mesh.scale.x must match expected_mesh_scale")
	assert(is_equal_approx(ball._ball_mesh.position.y, expected_y_off), "ball._ball_mesh.position.y must be raised by visual Y offset")
	print("  PASS: _ball_mesh properly scaled and elevated to sit cleanly on ground surface.")

	# 4. Setting change dynamic update
	var gs = root.get_node_or_null("GlobalSettings")
	if gs != null and gs.range_settings != null and gs.range_settings.settings.has("ball_visual_scale"):
		gs.range_settings.ball_visual_scale.set_value(1.5)
		assert(is_equal_approx(ball.get_visual_scale(), 1.5), "get_visual_scale must react to GlobalSettings change")
		var updated_expected_scale = (ball._ball_radius / 1.007168) * 1.5
		assert(is_equal_approx(ball._ball_mesh.scale.x, updated_expected_scale), "_ball_mesh must update scale to 1.5x on setting change")
		print("  PASS: Dynamic setting change instantly rescales _ball_mesh.")
		# Restore
		gs.range_settings.ball_visual_scale.set_value(1.35)

	ball.queue_free()
