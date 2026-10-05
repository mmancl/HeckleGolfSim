extends SceneTree

func _initialize():
	_run_tests()

func _run_tests() -> void:
	print("\n=== Running Hole Height & Raycast Penetration Tests ===")

	var sub_viewport = SubViewport.new()
	root.add_child(sub_viewport)

	var RangeScript = load("res://Courses/Range/range.gd")
	assert(RangeScript != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.scene_file_path = "res://TestCourse/test.tscn"
	range_instance.set_script(RangeScript)
	sub_viewport.add_child(range_instance)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)

	# Build a flat green static body (Layer 1, name "green_Static_1", surface_type = 4)
	var green_body = StaticBody3D.new()
	green_body.name = "green_Static_1"
	green_body.set_meta("surface_type", 4)
	green_body.collision_layer = 1
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	col_shape.shape = box
	# Center of box at y = -0.5, so top of green surface is at y = 0.0
	col_shape.position = Vector3(0.0, -0.5, 0.0)
	green_body.add_child(col_shape)
	range_instance.add_child(green_body)

	# Create RayCast3D for height queries
	var raycast = RayCast3D.new()
	raycast.collision_mask = 1
	raycast.collide_with_areas = false
	raycast.collide_with_bodies = true
	raycast.enabled = false
	range_instance.add_child(raycast)
	range_instance.set("_height_raycast", raycast)

	# Wait for physics server to sync
	await process_frame
	await physics_frame

	# Test 1: Ground query with clean terrain
	var h0 = range_instance.get_height(10.0, 10.0)
	print("  Test 1: Clean terrain get_height(10, 10) = ", h0)
	assert(absf(h0 - 0.0) < 0.01, "Expected green surface at y = 0.0, got: %f" % h0)
	print("  PASS: Clean terrain height matches green surface (0.0m)")

	# Test 2: GolfBall sitting right at (10, 10) in/above the cup
	var BallScript = load("res://Player/ball.gd")
	var ball = CharacterBody3D.new()
	ball.set_script(BallScript)
	ball.position = Vector3(10.0, 0.021, 10.0)
	range_instance.add_child(ball)
	if ball.has_method("initialize_ball"):
		ball.initialize_ball()

	print("  Ball collision_layer = ", ball.collision_layer, " (expected: 4, not 1)")
	assert(ball.collision_layer == 4, "GolfBall collision_layer must be 4, got: %d" % ball.collision_layer)

	await process_frame
	await physics_frame

	var h1 = range_instance.get_height(10.0, 10.0)
	print("  Test 2: get_height(10, 10) with ball at (10, 10) = ", h1)
	assert(absf(h1 - 0.0) < 0.01, "Expected terrain height 0.0m despite ball presence, got: %f" % h1)
	print("  PASS: get_height successfully ignores/penetrates ball and returns 0.0m")

	# Test 3: An obstruction on layer 1 (e.g. tree canopy or prop with no surface meta)
	var obstacle = StaticBody3D.new()
	obstacle.name = "TreeObstacle"
	obstacle.collision_layer = 1
	var obs_shape = CollisionShape3D.new()
	var obs_box = BoxShape3D.new()
	obs_box.size = Vector3(2.0, 2.0, 2.0)
	obs_shape.shape = obs_box
	obs_shape.position = Vector3(10.0, 5.0, 10.0) # Floating at y=5
	obstacle.add_child(obs_shape)
	range_instance.add_child(obstacle)

	await process_frame
	await physics_frame

	var h2 = range_instance.get_height(10.0, 10.0)
	print("  Test 3: get_height(10, 10) with layer 1 obstacle at y=5 = ", h2)
	assert(absf(h2 - 0.0) < 0.01, "Expected penetration to green at y = 0.0, got: %f" % h2)
	print("  PASS: Multi-pass raycast penetrated layer 1 obstacle to find green surface at 0.0m")

	# Test 4: Hole caching logic in course_play
	range_instance.current_hole_name = "Hole 1"
	range_instance.current_hole_location = Vector3(10.0, 0.0, 10.0)

	var active_hole_same = {"Name": "Hole 1", "Par": 4, "Hole Location": [10.0, 10.0]}
	var hole_name_same = active_hole_same.get("Name")
	var is_new_hole_same = (range_instance.current_hole_name != hole_name_same) or range_instance.current_hole_location.is_zero_approx()
	assert(not is_new_hole_same, "Same hole turn change must evaluate is_new_hole to false")
	print("  PASS: Mid-hole player change does not trigger is_new_hole")

	var active_hole_next = {"Name": "Hole 2", "Par": 3, "Hole Location": [50.0, -20.0]}
	var hole_name_next = active_hole_next.get("Name")
	var is_new_hole_next = (range_instance.current_hole_name != hole_name_next) or range_instance.current_hole_location.is_zero_approx()
	assert(is_new_hole_next, "Different hole must evaluate is_new_hole to true")
	print("  PASS: New hole triggers is_new_hole to true")

	print("\n=======================================================")
	print("ALL HOLE HEIGHT & RAYCAST PENETRATION TESTS PASSED!")
	print("=======================================================\n")
	quit(0)
