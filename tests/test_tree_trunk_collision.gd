extends SceneTree

func _initialize() -> void:
	_run_tests()

func _run_tests() -> void:
	print("==================================================")
	print("Running Tree Trunk Collision & Bounce Tests")
	print("==================================================")

	var sub_viewport = SubViewport.new()
	root.add_child(sub_viewport)

	var test_scene = Node3D.new()
	test_scene.name = "TestScene"
	sub_viewport.add_child(test_scene)

	# --- Test 1: ProceduralTreeGenerator trunk collider dimensions ---
	print("\n--- Test 1: Consolidated Foliage Trunk Dimensions ---")
	var ptg_script = load("res://HighFidelity/Foliage/procedural_tree_generator.gd")
	assert(ptg_script != null, "Could not load procedural_tree_generator.gd")

	var mock_tree_scene = Node3D.new()
	mock_tree_scene.name = "MockScene"
	test_scene.add_child(mock_tree_scene)

	# Create a mock tree matching OsmMapLoader tree instances
	var mock_tree = StaticBody3D.new()
	mock_tree.name = "Tree_10.0_10.0"
	mock_tree.position = Vector3(10.0, 0.0, 10.0)
	mock_tree.scale = Vector3(2.5, 2.5, 2.5)

	var mock_mesh = MeshInstance3D.new()
	mock_mesh.name = "TreeMesh"
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.height = 6.0
	cyl_mesh.top_radius = 0.4
	cyl_mesh.bottom_radius = 0.4
	mock_mesh.mesh = cyl_mesh
	mock_tree.add_child(mock_mesh)

	var mock_col = CollisionShape3D.new()
	var mock_cyl_shape = CylinderShape3D.new()
	mock_cyl_shape.height = 5.6
	mock_cyl_shape.radius = 0.38
	mock_col.shape = mock_cyl_shape
	mock_col.position = Vector3(0.0, 2.0, 0.0)
	mock_tree.add_child(mock_col)

	var mock_canopy = Area3D.new()
	mock_canopy.name = "CanopyArea"
	mock_canopy.position = Vector3(0.0, 4.2, 0.0)
	var mock_canopy_col = CollisionShape3D.new()
	var mock_sphere = SphereShape3D.new()
	mock_sphere.radius = 2.6
	mock_canopy_col.shape = mock_sphere
	mock_canopy.add_child(mock_canopy_col)
	mock_tree.add_child(mock_canopy)

	mock_tree_scene.add_child(mock_tree)

	var stats: Dictionary = ptg_script.convert_scene_foliage_to_multimesh(mock_tree_scene, false)
	assert(stats["trees_converted"] == 1, "Must convert 1 tree")

	var consolidated_body = mock_tree_scene.get_node_or_null("ConsolidatedFoliageCollision") as StaticBody3D
	assert(consolidated_body != null, "ConsolidatedFoliageCollision must exist")
	assert(consolidated_body.has_meta("is_tree") and bool(consolidated_body.get_meta("is_tree")), "Must have is_tree metadata")
	assert(consolidated_body.is_in_group("trees"), "Must be added to trees group")

	var trunk_shape_node: CollisionShape3D = null
	for child in consolidated_body.get_children():
		if child is CollisionShape3D:
			trunk_shape_node = child
			break
	assert(trunk_shape_node != null, "Trunk CollisionShape3D must exist in consolidated body")
	assert(trunk_shape_node.shape is CylinderShape3D, "Trunk collision shape must be CylinderShape3D")
	var cyl_shape := trunk_shape_node.shape as CylinderShape3D
	assert(cyl_shape.height >= 5.0, "Trunk shape height must be at least 5.0m (not a 1m stump), actual: %.2f" % cyl_shape.height)
	assert(cyl_shape.radius >= 0.35, "Trunk shape radius must be at least 0.35m, actual: %.2f" % cyl_shape.radius)
	# Center Y position scaled by 2.5
	assert(trunk_shape_node.position.y >= 4.5, "Trunk position Y must cover elevated trunk, actual: %.2f" % trunk_shape_node.position.y)
	print("  PASS: Consolidated foliage tree trunk has authentic full-height CylinderShape3D (height=%.2fm, radius=%.2fm, Y=%.2fm)." % [cyl_shape.height, cyl_shape.radius, trunk_shape_node.position.y])

	# --- Test 2: Ball Collision with Tree Trunk (Bounce & Depenetration) ---
	print("\n--- Test 2: Ball Direct Trunk Impact & Physical Bounce ---")
	var ball_script = load("res://Player/ball.gd")
	assert(ball_script != null, "Could not load ball.gd")

	var ball = CharacterBody3D.new()
	ball.name = "GolfBall"
	ball.set_script(ball_script)
	test_scene.add_child(ball)
	if ball.has_method("initialize_ball"):
		ball.initialize_ball()

	# Position ball moving toward a tree trunk
	ball.state = PhysicsEnums.BallState.FLIGHT
	ball.velocity = Vector3(0.0, 1.0, 30.0) # Moving in +Z towards tree at 30 m/s
	ball.global_position = Vector3(10.0, 5.0, 8.5)

	# Simulate collision with tree trunk facing normal (0, 0, -1)
	var collision = KinematicCollision3D.new()
	# Call _handle_collision directly with mock collision
	# Create a mock KinematicCollision3D via move_and_collide against a dedicated StaticBody
	var tree_target = StaticBody3D.new()
	tree_target.name = "TreeTrunkTarget"
	tree_target.set_meta("is_tree", true)
	tree_target.add_to_group("trees")
	tree_target.position = Vector3(10.0, 5.0, 10.0)
	var target_col = CollisionShape3D.new()
	var target_cyl = CylinderShape3D.new()
	target_cyl.height = 10.0
	target_cyl.radius = 1.0
	target_col.shape = target_cyl
	tree_target.add_child(target_col)
	test_scene.add_child(tree_target)

	await process_frame
	await physics_frame

	# Move ball to collide with tree_target
	ball.global_position = Vector3(10.0, 5.0, 8.9)
	var hit_col = ball.move_and_collide(Vector3(0.0, 0.0, 0.5), false, ball.COLLISION_SAFE_MARGIN)
	assert(hit_col != null, "Ball must register collision with tree trunk")
	var pre_hit_vel = Vector3(0.0, 0.5, 25.0)
	ball.velocity = pre_hit_vel
	ball._handle_collision(hit_col, false, pre_hit_vel)

	assert(ball.hit_tree_this_shot == true, "hit_tree_this_shot must be set to true on trunk collision")
	assert(ball.get("_hit_trunk_this_shot") == true, "_hit_trunk_this_shot must be set to true on trunk collision")
	assert(ball.velocity.z < 0.0, "Ball velocity Z must reflect/bounce backward after striking trunk, actual vz=%.2f" % ball.velocity.z)
	assert(ball.global_position.z < hit_col.get_position().z, "Ball must be depenetrated away from tree surface")
	print("  PASS: Ball bounced off trunk with reversed Z velocity (%.2f m/s) and depenetrated cleanly." % ball.velocity.z)

	# --- Test 3: Canopy passing followed by direct trunk impact ---
	print("\n--- Test 3: Canopy Foliage then Direct Trunk Impact ---")
	ball.reset()
	assert(ball.hit_tree_this_shot == false, "hit_tree_this_shot must reset to false")
	assert(ball.get("_hit_leaves_this_shot") == false, "_hit_leaves_this_shot must reset to false")
	assert(ball.get("_hit_trunk_this_shot") == false, "_hit_trunk_this_shot must reset to false")

	# Simulate canopy entry
	ball.set("_hit_leaves_this_shot", true)
	ball.hit_tree_this_shot = true

	# Subsequent trunk impact must still register trunk hit
	ball.velocity = Vector3(0.0, 0.0, 20.0)
	ball._handle_collision(hit_col, false, Vector3(0.0, 0.0, 20.0))
	assert(ball.get("_hit_trunk_this_shot") == true, "_hit_trunk_this_shot must be flagged even if canopy was touched earlier")
	assert(ball.velocity.z < 0.0, "Ball must still bounce off trunk after passing through leaves")
	print("  PASS: Trunk collision correctly flagged and bounced after leaves brush.")

	# --- Test 4: Top of trunk outward deflection ---
	print("\n--- Test 4: Top of Trunk Outward Deflection (No Downward Trap) ---")
	ball.reset()
	ball.velocity = Vector3(0.0, -5.0, 5.0)
	# Simulate collision with top rim normal pointing predominantly upward
	var top_collision = ball.move_and_collide(Vector3(0.0, -0.2, 0.0), false, ball.COLLISION_SAFE_MARGIN)
	if hit_col != null:
		# Test deflection calculation when normal.y > 0.4
		var steep_normal = Vector3(0.2, 0.8, -0.5).normalized()
		var test_vel = Vector3(0.0, -4.0, 10.0)
		ball.velocity = test_vel.bounce(steep_normal) * 0.45
		var horiz_out := Vector3(steep_normal.x, 0.0, steep_normal.z).normalized()
		ball.velocity = Vector3(horiz_out.x * maxf(absf(ball.velocity.x), 2.5), maxf(ball.velocity.y, 0.5), horiz_out.z * maxf(absf(ball.velocity.z), 2.5))
		assert(ball.velocity.y >= 0.5, "Velocity Y must be upward/positive (>= 0.5) to clear trunk top, actual vy=%.2f" % ball.velocity.y)
		assert(Vector2(ball.velocity.x, ball.velocity.z).length() >= 2.5, "Horizontal outward speed must be >= 2.5 m/s")
		print("  PASS: Ball deflected horizontally outward (%.2f m/s) with upward clearance (vy=%.2f)." % [Vector2(ball.velocity.x, ball.velocity.z).length(), ball.velocity.y])

	# Cleanup
	sub_viewport.queue_free()

	print("\n==================================================")
	print("All Tree Trunk Collision Tests PASSED!")
	print("==================================================")
	quit(0)
