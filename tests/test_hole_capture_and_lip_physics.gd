extends SceneTree

# Targeted Unit Test: Hole Capture Speeds, No High-Speed Suction, Lip Deflection, and Gravity Drop

var _has_run := false

class MockHoleCourse extends Node3D:
	var current_hole_location := Vector3(5.0, 0.0, 0.0)
	var cup_radius := 0.054
	func get_height(_x: float, _z: float) -> float:
		return 0.0


func _process(_delta: float) -> bool:
	if _has_run:
		return true
	_has_run = true

	print("\n=======================================================")
	print("  Running Hole Physics & Lip Deflection Unit Tests")
	print("=======================================================\n")

	test_high_speed_center_putt_does_not_get_sucked_in()
	test_high_speed_off_center_putt_deflects_and_passes()
	test_medium_speed_lip_out()
	test_correct_speed_falls_smoothly_into_cup()

	print("\n=======================================================")
	print("  ALL HOLE PHYSICS & LIP DEFLECTION TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
	return true


func _setup_test_ball(course: MockHoleCourse) -> Node:
	var player_node = Node3D.new()
	player_node.name = "Player"
	course.add_child(player_node)

	var BallScript = load("res://Player/ball.gd")
	var ball = BallScript.new()
	player_node.add_child(ball)
	ball.initialize_ball()
	ball.set_surface(PhysicsEnums.SurfaceType.GREEN)
	return ball


func test_high_speed_center_putt_does_not_get_sucked_in() -> void:
	print("--- Test 1: Fast Center Putt Skips/Rolls Past (No Suction) ---")
	var course = MockHoleCourse.new()
	root.add_child(course)
	var ball = _setup_test_ball(course)

	# Ball approaching center of hole at 2.6 m/s (fast putt hit with lots of speed)
	ball.state = PhysicsEnums.BallState.ROLLOUT
	ball.on_ground = true
	ball.is_putt = true
	ball.is_falling_in_hole = false
	ball.holed_out_this_shot = false
	ball.global_position = Vector3(5.0, ball._ball_radius, -0.045) # Entering cup mouth along +Z
	ball.velocity = Vector3(0.0, 0.0, 2.6)

	# Step physics frames across the cup
	for _i in range(10):
		ball._physics_process(0.016)

	assert(not ball.is_falling_in_hole, "Fast center putt (2.6 m/s) must NOT get sucked into the cup")
	assert(not ball.holed_out_this_shot, "holed_out_this_shot must remain false for high-speed putt")
	assert(ball.global_position.z > 0.0, "Ball must roll past the hole center")
	print("  PASS: Fast center putt (2.6 m/s) did NOT get sucked in; rolled past the hole (z=%.4fm)." % ball.global_position.z)

	course.queue_free()


func test_high_speed_off_center_putt_deflects_and_passes() -> void:
	print("--- Test 2: Fast Off-Center Putt Deflects Left/Right (No Suction) ---")
	var course = MockHoleCourse.new()
	root.add_child(course)
	var ball = _setup_test_ball(course)

	# Ball approaching 3.5 cm to the right of center (+X) at 2.2 m/s along +Z
	ball.state = PhysicsEnums.BallState.ROLLOUT
	ball.on_ground = true
	ball.is_putt = true
	ball.is_falling_in_hole = false
	ball.holed_out_this_shot = false
	ball.global_position = Vector3(5.035, ball._ball_radius, -0.040)
	ball.velocity = Vector3(0.0, 0.0, 2.2)

	# Step physics across the lip
	var deflected_x := false
	for _i in range(8):
		ball._physics_process(0.016)
		if ball.velocity.x != 0.0:
			deflected_x = true

	assert(not ball.is_falling_in_hole, "Fast off-center putt (2.2 m/s) must NOT get sucked into the cup")
	assert(deflected_x, "Hole rim must cause the ball to deflect laterally (vx != 0)")
	assert(ball.velocity.x < 0.0, "Rim normal tilt must deflect off-center putt slightly toward hole (-X direction)")
	assert(ball.global_position.z > 0.0, "Ball must continue rolling past the hole")
	print("  PASS: Fast off-center putt deflected laterally (vx=%.4f) and rolled past the hole." % ball.velocity.x)

	course.queue_free()


func test_medium_speed_lip_out() -> void:
	print("--- Test 3: Off-Center Putt at Moderate Speed Lips Out ---")
	var course = MockHoleCourse.new()
	root.add_child(course)
	var ball = _setup_test_ball(course)

	# Ball at 4.6 cm offset (grazing lip) at 1.1 m/s (critical capture speed at 4.6cm is ~0.8m/s)
	ball.state = PhysicsEnums.BallState.ROLLOUT
	ball.on_ground = true
	ball.is_putt = true
	ball.is_falling_in_hole = false
	ball.holed_out_this_shot = false
	ball.global_position = Vector3(5.046, ball._ball_radius, -0.030)
	ball.velocity = Vector3(0.0, 0.0, 1.1)

	for _i in range(8):
		ball._physics_process(0.016)

	assert(not ball.is_falling_in_hole, "Grazing putt at 1.1 m/s exceeding off-center capture speed must lip out")
	assert(ball.velocity.x < -0.01, "Rim tilt must deflect grazing putt around the lip (vx=%.4f < -0.01)" % ball.velocity.x)
	print("  PASS: Medium speed grazing putt lipped out with strong lateral deflection (vx=%.4f)." % ball.velocity.x)

	course.queue_free()


func test_correct_speed_falls_smoothly_into_cup() -> void:
	print("--- Test 4: Correct Speed Ball Drops into Hole without Teleporting ---")
	var course = MockHoleCourse.new()
	root.add_child(course)
	var ball = _setup_test_ball(course)

	# Ball approaching center at 1.1 m/s (ideal putting speed, well under 1.63 m/s)
	ball.state = PhysicsEnums.BallState.ROLLOUT
	ball.on_ground = true
	ball.is_putt = true
	ball.is_falling_in_hole = false
	ball.holed_out_this_shot = false
	ball.global_position = Vector3(5.0, ball._ball_radius, -0.045)
	ball.velocity = Vector3(0.0, 0.0, 1.1)

	# Step 1: Enters cup opening
	ball._physics_process(0.016)
	assert(ball.is_falling_in_hole, "Ball at 1.1 m/s must be captured into hole")
	assert(ball.holed_out_this_shot, "holed_out_this_shot must be true")
	# Forward momentum preserved (not artificially choked to near-zero)
	assert(ball.velocity.z > 0.8, "Forward momentum must be preserved on cup entry (vz=%.3f > 0.8)" % ball.velocity.z)
	# Ball position along Z must advance forward smoothly into the hole (no instant snap to center)
	assert(ball.global_position.z < -0.02, "Ball must NOT teleport to hole center on entry (z=%.4f)" % ball.global_position.z)

	# Step multiple frames until ball falls to the bottom of the cup
	for _i in range(50):
		if ball.state == PhysicsEnums.BallState.REST:
			break
		ball._physics_process(0.016)

	var expected_floor_y = course.current_hole_location.y - ball.CUP_DEPTH + ball._ball_radius
	assert(ball.state == PhysicsEnums.BallState.REST, "Holed ball must settle to REST")
	assert(is_equal_approx(ball.global_position.y, expected_floor_y), "Ball must rest at bottom of physical cup")
	print("  PASS: Correct speed putt dropped naturally, hit cup floor, and settled at bottom (y=%.4fm)." % ball.global_position.y)

	course.queue_free()
