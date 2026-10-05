extends SceneTree

func _initialize():
	_run_tests()

func _run_tests() -> void:
	print("\n=== Running Rock Proximity Relief & Clearance Tests ===")

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

	# Ground terrain surface at y = 0.0
	var ground_body = StaticBody3D.new()
	ground_body.name = "rough_Static_1"
	ground_body.set_meta("surface_type", 2)
	ground_body.collision_layer = 1
	var ground_shape = CollisionShape3D.new()
	var ground_box = BoxShape3D.new()
	ground_box.size = Vector3(100.0, 1.0, 100.0)
	ground_shape.shape = ground_box
	ground_shape.position = Vector3(0.0, -0.5, 0.0)
	ground_body.add_child(ground_shape)
	range_instance.add_child(ground_body)

	# Spawn a test rock at (10.0, 0.0, 10.0)
	var rock = StaticBody3D.new()
	rock.name = "Rock_10.0_10.0"
	rock.set_meta("surface_type", 2)
	rock.set_meta("is_rock", true)
	rock.add_to_group("rocks")
	rock.collision_layer = 1
	rock.position = Vector3(10.0, 0.0, 10.0)

	var rock_col = CollisionShape3D.new()
	var rock_sphere = SphereShape3D.new()
	rock_sphere.radius = 0.5 # 0.5m rock radius
	rock_col.shape = rock_sphere
	rock.add_child(rock_col)
	range_instance.add_child(rock)

	# Spawn GolfBall instance
	var BallScript = load("res://Player/ball.gd")
	assert(BallScript != null, "Player/ball.gd must load")
	var ball = CharacterBody3D.new()
	ball.name = "GolfBall"
	ball.set_script(BallScript)
	range_instance.add_child(ball)
	if ball.has_method("initialize_ball"):
		ball.initialize_ball()

	await process_frame
	await physics_frame

	var TWO_FEET: float = 0.6096

	# ----------------------------------------------------
	# Test 1: Ball placed 0.2m (~8 inches) from rock surface
	# Rock is at (10.0, 0.0, 10.0) with radius 0.5m.
	# Rock surface extends to x = 10.5m.
	# Ball at x = 10.7m is 0.2m (approx 0.66 feet) from rock surface.
	# ----------------------------------------------------
	print("\n--- Test 1: Ball ending 0.2m (within 2 feet) of rock ---")
	ball.global_position = Vector3(10.7, 0.021, 10.0)
	await physics_frame

	var initial_nearby = ball._get_nearby_rocks(ball.global_position, TWO_FEET)
	print("  Nearby rocks detected before relief: ", initial_nearby.size())
	assert(initial_nearby.size() > 0, "Rock must be detected within 2 feet")

	var relief_applied: bool = ball.ensure_rock_clearance()
	print("  Relief applied: ", relief_applied)
	assert(relief_applied == true, "ensure_rock_clearance must return true when ball is within 2 feet of rock")

	await physics_frame
	var after_nearby = ball._get_nearby_rocks(ball.global_position, TWO_FEET)
	print("  Nearby rocks detected after relief: ", after_nearby.size())
	assert(after_nearby.is_empty(), "Ball must have no rocks within 2 feet after relief")

	var dist_to_rock_center = Vector2(ball.global_position.x - 10.0, ball.global_position.z - 10.0).length()
	var dist_to_rock_surface = dist_to_rock_center - 0.5
	print("  Distance to rock surface after relief: %.3f meters (%.2f feet)" % [dist_to_rock_surface, dist_to_rock_surface * 3.28084])
	assert(dist_to_rock_surface >= (TWO_FEET - 0.05), "Ball must be at least 2 feet from rock surface")
	print("  PASS: Ball was moved 2 feet from the rock!")

	# ----------------------------------------------------
	# Test 2: Ball placed 5.0m away from rock (clear)
	# ----------------------------------------------------
	print("\n--- Test 2: Ball placed 5.0m (clear) from rock ---")
	ball.global_position = Vector3(20.0, 0.021, 20.0)
	await physics_frame

	var no_relief: bool = ball.ensure_rock_clearance()
	print("  Relief applied for clear ball: ", no_relief)
	assert(no_relief == false, "ensure_rock_clearance must return false when ball is not near any rock")
	print("  PASS: Clear ball position is unaffected.")

	# ----------------------------------------------------
	# Test 3: Automatic relief on _enter_rest_state()
	# ----------------------------------------------------
	print("\n--- Test 3: Automatic relief triggered on _enter_rest_state() ---")
	ball.global_position = Vector3(10.6, 0.021, 10.0) # 0.1m from rock surface
	ball.state = 1 # FLIGHT / ROLLOUT
	await physics_frame

	var rest_emitted := false
	ball.rest.connect(func(): rest_emitted = true)

	ball._enter_rest_state()
	await physics_frame

	assert(rest_emitted == true, "rest signal must be emitted on _enter_rest_state")
	var post_rest_nearby = ball._get_nearby_rocks(ball.global_position, TWO_FEET)
	print("  Rocks within 2 feet after _enter_rest_state: ", post_rest_nearby.size())
	assert(post_rest_nearby.is_empty(), "Ball must not have any rocks within 2 feet after _enter_rest_state")
	print("  PASS: _enter_rest_state automatically applies 2-foot rock relief!")

	print("\n=======================================================")
	print("ALL ROCK PROXIMITY RELIEF TESTS PASSED!")
	print("=======================================================\n")

	quit(0)
