extends SceneTree

# Targeted Unit Test: Ball Stationary Stability
# Ensures the ball does not jump or change lie when stationary at rest.

var _tested := false

func _initialize() -> void:
	print("=== Running Ball Stationary Stability Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	var BallScript = load("res://Player/ball.gd")
	assert(BallScript != null, "ball.gd must load")

	var sub_viewport = SubViewport.new()
	root.add_child(sub_viewport)

	var ball = CharacterBody3D.new()
	ball.name = "GolfBall"
	ball.set_script(BallScript)
	sub_viewport.add_child(ball)
	if ball.has_method("initialize_ball"):
		ball.initialize_ball()

	# Create a mock TerrainStatic body
	var terrain_body = StaticBody3D.new()
	terrain_body.name = "TerrainStatic"
	var col_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	col_shape.shape = box
	col_shape.position = Vector3(0.0, -0.5, 0.0)
	terrain_body.add_child(col_shape)
	sub_viewport.add_child(terrain_body)

	# -------------------------------------------------------------
	# Test 1: TerrainStatic collider classification
	# -------------------------------------------------------------
	print("\n--- Test 1: TerrainStatic Collider Classification ---")
	ball._update_surface_from_collider(terrain_body)
	assert(ball.lie_type == "rough", "TerrainStatic must classify as 'rough', got: %s" % ball.lie_type)
	assert(ball.surface_type == PhysicsEnums.SurfaceType.ROUGH, "TerrainStatic must set ROUGH surface type, got: %d" % ball.surface_type)
	print("  PASS: TerrainStatic correctly identified as rough.")

	# -------------------------------------------------------------
	# Test 2: Stationary Ball in Rough does not jump when club changes
	# -------------------------------------------------------------
	print("\n--- Test 2: Stationary Ball in Rough Stays Stable on Club Selection ---")
	ball.state = PhysicsEnums.BallState.REST
	ball.lie_type = "rough"
	ball.set_surface(PhysicsEnums.SurfaceType.ROUGH)
	ball.global_position = Vector3(10.0, 0.021335, 10.0)
	ball._enter_rest_state()

	# Let _process run a few frames to settle the visual mesh Y
	for frame in range(15):
		ball._process(1.0 / 30.0)

	var settled_mesh_y: float = ball._ball_mesh.position.y
	var settled_global_y: float = ball.global_position.y
	assert(settled_mesh_y < ball.get_visual_y_offset(), "Ball mesh in rough must be sunken below base_y")

	# Select different clubs
	ball._on_club_selected("7i")
	ball._process(1.0 / 30.0)
	assert(ball.lie_type == "rough", "Club selection must not change rough lie to fairway, got: %s" % ball.lie_type)
	assert(is_equal_approx(ball._ball_mesh.position.y, settled_mesh_y), "Ball mesh Y must not jump on club selection: %f vs %f" % [ball._ball_mesh.position.y, settled_mesh_y])
	assert(is_equal_approx(ball.global_position.y, settled_global_y), "Ball global Y must not jump on club selection: %f vs %f" % [ball.global_position.y, settled_global_y])

	ball._on_club_selected("Dr")
	ball._process(1.0 / 30.0)
	assert(ball.lie_type == "rough", "Selecting Driver while in rough must not change lie to teebox or fairway")
	assert(not ball._tee_mesh.visible, "Tee mesh must not show in rough even if Driver is selected")
	assert(is_equal_approx(ball._ball_mesh.position.y, settled_mesh_y), "Ball mesh Y must remain sunken when Driver selected in rough")

	print("  PASS: Ball remained stationary in rough across club changes.")

	# -------------------------------------------------------------
	# Test 3: Ball Reset initializes correct sunken height directly
	# -------------------------------------------------------------
	print("\n--- Test 3: Ball Reset Preserves Sunken Mesh Y in Rough ---")
	ball.lie_type = "rough"
	ball.reset()
	var expected_rough_y: float = ball.get_visual_y_offset() - 0.014
	assert(is_equal_approx(ball._ball_mesh.position.y, expected_rough_y), "reset() must initialize mesh Y directly to sunken rough height without popping up")
	print("  PASS: reset() initialized mesh Y directly to %f without visual pop." % ball._ball_mesh.position.y)

	# -------------------------------------------------------------
	# Test 4: Teebox Driver vs Non-Driver Behavior
	# -------------------------------------------------------------
	print("\n--- Test 4: Teebox Driver vs Non-Driver Elevation ---")
	ball.lie_type = "teebox"
	ball.current_selected_club = "Dr"
	ball._update_tee_elevation()
	assert(ball._tee_mesh.visible, "Tee mesh must be visible for Driver on teebox")
	var teed_y = ball.global_position.y

	ball.current_selected_club = "3W"
	ball._update_tee_elevation()
	assert(not ball._tee_mesh.visible, "Tee mesh must be hidden for 3W on teebox")
	assert(ball.global_position.y < teed_y, "Non-driver ball on teebox must be seated on grass, lower than teed ball")
	print("  PASS: Teebox properly toggles tee peg and elevation between driver and fairway wood/irons.")

	print("\n==================================================")
	print("  ALL BALL STATIONARY STABILITY TESTS PASSED! 🎉")
	print("==================================================")
	quit(0)
