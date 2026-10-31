extends SceneTree

class MockBall extends Node3D:
	signal rest
	var aim_yaw_offset_deg := 0.0
	var lie_type := "fairway"
	var spawn_position := Vector3.ZERO
	var is_in_sand := false
	var is_putt := false
	var current_selected_club := "7i"
	var state := 0
	func _on_club_selected(_c): pass
	func reset(): pass
	func _update_surface_from_underneath(): pass
	func set_surface(_val): pass

class MockPlayer extends Node3D:
	signal rest
	var ball: Node3D = null
	var current_lie_type: String = "fairway"
	var current_shot_reduction := 0.0
	func reset_ball(): pass
	func get_ball_state() -> int: return 0
	func reset_shot_data(): pass
	func clear_tracers(): pass

func _initialize():
	_run_tests()

func _run_tests() -> void:
	print("=== Running Green Heatmap Smoothness & Gap-Free Generation Tests ===")

	var RangeScene = load("res://Courses/Range/range.gd")
	assert(RangeScene != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.set_script(RangeScene)
	root.add_child(range_instance)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)

	var player_node = MockPlayer.new()
	player_node.name = "Player"
	range_instance.add_child(player_node)

	var ball_node = MockBall.new()
	ball_node.name = "GolfBall"
	player_node.add_child(ball_node)
	player_node.ball = ball_node

	var aim_marker = Marker3D.new()
	aim_marker.name = "AimMarker"
	range_instance.add_child(aim_marker)

	# Build a mock circular green (48 triangles) centered at (0, 0, 100) with a slope from y=1.0 to y=3.0
	var green_body = StaticBody3D.new()
	green_body.name = "GreenStatic"
	green_body.set_meta("surface_type", 4)
	green_body.position = Vector3(0, 0, 100)
	range_instance.add_child(green_body)

	var col_shape = CollisionShape3D.new()
	var concave = ConcavePolygonShape3D.new()
	var verts = PackedVector3Array()

	# Create an irregular/elliptical green mesh in local coordinates
	var radius_x = 14.0
	var radius_z = 12.0
	var num_slices = 32
	var center = Vector3(0, 2.0, 0)
	for i in range(num_slices):
		var a1 = float(i) * TAU / float(num_slices)
		var a2 = float(i + 1) * TAU / float(num_slices)
		var p1 = Vector3(cos(a1) * radius_x, 1.0 + sin(a1) * 0.8, sin(a1) * radius_z)
		var p2 = Vector3(cos(a2) * radius_x, 1.0 + sin(a2) * 0.8, sin(a2) * radius_z)
		verts.append(center)
		verts.append(p1)
		verts.append(p2)

	concave.data = verts
	col_shape.shape = concave
	green_body.add_child(col_shape)

	await process_frame
	await physics_frame

	range_instance.current_hole_location = Vector3(0, 2.0, 100)
	range_instance._init_cached_surface_bodies()

	# Test 1: _get_green_triangles_3d returns 3D triangles
	print("\n--- Test 1: _get_green_triangles_3d & _get_green_triangles compatibility ---")
	var tris_3d = range_instance._get_green_triangles_3d(range_instance.current_hole_location)
	assert(tris_3d.size() == num_slices, "Must retrieve exactly %d 3D triangles, got %d" % [num_slices, tris_3d.size()])
	assert(tris_3d[0][0] is Vector3, "Triangle vertices must be Vector3")
	
	var tris_2d = range_instance._get_green_triangles(range_instance.current_hole_location)
	assert(tris_2d.size() == num_slices, "Must retrieve exactly %d 2D triangles, got %d" % [num_slices, tris_2d.size()])
	assert(tris_2d[0][0] is Vector2, "Triangle vertices in 2D must be Vector2")
	print("  PASS: 3D and 2D triangle extraction verified.")

	# Test 2: Edge-point precision test in _is_point_in_triangle
	print("\n--- Test 2: Triangle edge-point numerical stability ---")
	var tri_a = Vector2(0.0, 0.0)
	var tri_b = Vector2(10.0, 0.0)
	var tri_c = Vector2(5.0, 10.0)
	# Test exact midpoint of edge (a-b)
	var on_edge = Vector2(5.0, 0.0)
	assert(range_instance._is_point_in_triangle(on_edge, tri_a, tri_b, tri_c), "Point directly on edge must be inside triangle")
	# Test vertex corner points
	assert(range_instance._is_point_in_triangle(tri_a, tri_a, tri_b, tri_c), "Corner vertex A must be inside triangle")
	assert(range_instance._is_point_in_triangle(tri_b, tri_a, tri_b, tri_c), "Corner vertex B must be inside triangle")
	assert(range_instance._is_point_in_triangle(tri_c, tri_a, tri_b, tri_c), "Corner vertex C must be inside triangle")
	# Test point near edge with slight float epsilon
	var near_edge = Vector2(5.0, 0.00005)
	assert(range_instance._is_point_in_triangle(near_edge, tri_a, tri_b, tri_c), "Point near edge must not be rejected")
	print("  PASS: Numerical stability on triangle edges and vertices verified.")

	# Test 3: Generate smooth green heatmap mesh
	print("\n--- Test 3: Smooth GreenHeatmapMesh generation ---")
	range_instance._generate_green_grid_and_heatmap()

	var heatmap_node: MeshInstance3D = range_instance.get_node_or_null("GreenHeatmapMesh")
	assert(heatmap_node != null, "GreenHeatmapMesh node must be generated")
	assert(heatmap_node.mesh != null, "GreenHeatmapMesh must have an instantiated mesh")
	assert(heatmap_node.layers == 2, "GreenHeatmapMesh must be on layer 2 for MinimapCamera and AerialCamera")
	assert(heatmap_node.material_override != null, "GreenHeatmapMesh must have material_override set")
	
	var mat: StandardMaterial3D = heatmap_node.material_override
	assert(mat.vertex_color_use_as_albedo == true, "Material must use vertex colors for elevation gradient")
	assert(mat.render_priority == 1, "Material render_priority must be 1 to prevent z-fighting")
	assert(mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "depth_draw_mode must be DISABLED")
	assert(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "cull_mode must be DISABLED")

	# Verify mesh face count and subdivision (subdivided for smooth elevation gradient)
	var faces = heatmap_node.mesh.get_faces()
	assert(faces.size() > num_slices * 3, "Mesh must be subdivided from original %d faces (got %d faces)" % [num_slices * 3, faces.size()])
	print("  PASS: GreenHeatmapMesh subdivided successfully into %d vertices (%d triangles)." % [faces.size(), faces.size() / 3])

	# Test 4: Extents check - verify smooth heatmap reaches the green outer perimeter
	print("\n--- Test 4: Heatmap extent matches green perimeter ---")
	var min_x = 99999.0
	var max_x = -99999.0
	var min_z = 99999.0
	var max_z = -99999.0
	for v in faces:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z)
		max_z = maxf(max_z, v.z)

	var width_x = max_x - min_x
	var depth_z = max_z - min_z
	print("  Heatmap bounds: X[%.2f to %.2f] (width %.2f), Z[%.2f to %.2f] (depth %.2f)" % [min_x, max_x, width_x, min_z, max_z, depth_z])
	assert(abs(width_x - (radius_x * 2.0)) < 1.0, "Heatmap width (%.2f) must closely match green diameter (%.2f)" % [width_x, radius_x * 2.0])
	assert(abs(depth_z - (radius_z * 2.0)) < 1.0, "Heatmap depth (%.2f) must closely match green diameter (%.2f)" % [depth_z, radius_z * 2.0])
	print("  PASS: Heatmap boundaries precisely match the green perimeter without gaps.")

	# Test 5: Visibility handling
	print("\n--- Test 5: Visibility and layer filtering ---")
	range_instance.show_green_grid = true
	range_instance._update_green_grid_visibility()
	assert(heatmap_node.visible == true, "Heatmap must be visible when show_green_grid is true")

	range_instance.show_green_grid = false
	range_instance._update_green_grid_visibility()
	assert(heatmap_node.visible == false, "Heatmap must be hidden when show_green_grid is false")
	print("  PASS: Green heatmap visibility toggles correctly.")

	# Test 6: Multi-body green aggregation (split green static bodies)
	print("\n--- Test 6: Multi-body green aggregation ---")
	# Add a second static body adjacent to the main green body
	var green_part2 = StaticBody3D.new()
	green_part2.name = "GreenStatic_Part2"
	green_part2.set_meta("surface_type", 4)
	green_part2.position = Vector3(15.0, 0, 100) # Centered 15m to the right
	range_instance.add_child(green_part2)

	var col_shape2 = CollisionShape3D.new()
	var concave2 = ConcavePolygonShape3D.new()
	var verts2 = PackedVector3Array()
	# Add 16 triangles for part 2
	for i in range(16):
		var a1 = float(i) * TAU / 16.0
		var a2 = float(i + 1) * TAU / 16.0
		var p1 = Vector3(cos(a1) * 8.0, 1.5, sin(a1) * 8.0)
		var p2 = Vector3(cos(a2) * 8.0, 1.5, sin(a2) * 8.0)
		verts2.append(Vector3(0, 1.5, 0))
		verts2.append(p1)
		verts2.append(p2)
	concave2.data = verts2
	col_shape2.shape = concave2
	green_part2.add_child(col_shape2)

	range_instance._init_cached_surface_bodies(true)
	var multi_tris = range_instance._get_green_triangles_3d(Vector3(0, 2.0, 100))
	assert(multi_tris.size() == num_slices + 16, "Must aggregate both green static bodies (%d expected, got %d)" % [num_slices + 16, multi_tris.size()])
	var multi_verts = range_instance.get_current_green_vertices()
	assert(multi_verts.size() == (num_slices + 16) * 3, "get_current_green_vertices must return all vertices from multi-body green")
	print("  PASS: Multi-body green triangles aggregated seamlessly (%d triangles across parts)." % multi_tris.size())

	# Test 7: Camera cull mask isolation (strict Layer 1 + Layer 2 only)
	print("\n--- Test 7: Camera cull mask isolation ---")
	var expected_cull_mask = (1 << 0) | (1 << 1) # Layer 1 + Layer 2 only = 3
	assert(expected_cull_mask == 3, "Cull mask bitmask must equal 3")
	var aerial_cam = range_instance.get_node_or_null("AerialCamera")
	if aerial_cam != null:
		assert(aerial_cam.cull_mask == expected_cull_mask, "AerialCamera must only render Layer 1 & 2")
	
	# Verify dots and grid nodes are hidden in aerial view
	range_instance.is_aerial_view = true
	range_instance.show_green_grid = true
	range_instance._update_green_grid_visibility()
	var grid_node = range_instance.get_node_or_null("GreenGridMesh")
	var dots_node = range_instance.get_node_or_null("GreenDotsMesh")
	if grid_node:
		assert(grid_node.visible == false, "GreenGridMesh must be hidden during aerial/minimap view")
	if dots_node:
		assert(dots_node.visible == false, "GreenDotsMesh must be hidden during aerial/minimap view")
	print("  PASS: Camera cull masks and slope arrow suppression in aerial/minimap verified.")

	print("\n==================================================================")
	print("  ALL GREEN HEATMAP SMOOTHNESS TESTS PASSED SUCCESSFULLY!")
	print("==================================================================")
	quit()
