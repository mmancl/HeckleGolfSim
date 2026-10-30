extends SceneTree

func _initialize() -> void:
	print("=== Running Flat Green Surface Elements (Gimme & Putting Grid) Tests ===")
	
	var RangeScript = load("res://Courses/Range/range.gd")
	assert(RangeScript != null, "range.gd must load")
	
	var range_instance = Node3D.new()
	range_instance.set_script(RangeScript)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)
	
	# Test 1: Verify Gimme Ring Material Properties for flat surface placement
	print("\n--- Test 1: Gimme Ring Material Properties ---")
	var gimme_mat: StandardMaterial3D = range_instance._create_gimme_ring_material(Color(0, 1, 1), 2)
	assert(gimme_mat != null, "Gimme material must not be null")
	assert(gimme_mat.no_depth_test == false, "no_depth_test must be false so gimme rings test depth correctly against green terrain and objects")
	assert(gimme_mat.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "depth_draw_mode must be DEPTH_DRAW_DISABLED for transparent overlays")
	assert(gimme_mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "cull_mode must be CULL_DISABLED")
	assert(gimme_mat.render_priority == 2, "render_priority must be set")
	print("  PASS: Gimme ring material depth and render properties correctly configured for flat green placement")
	
	# Test 2: Verify Gimme Ring Mesh Geometry Generation with flat offset
	print("\n--- Test 2: Gimme Ring Mesh Geometry with Flat Offset ---")
	var pin_pos = Vector3(15.0, 2.5, 20.0)
	var flat_offset = 0.004 # 4mm flat offset
	var ring_mesh = range_instance._create_gimme_ring_mesh(pin_pos, 1.5, 0.08, flat_offset, [])
	assert(ring_mesh != null, "Ring mesh must be generated")
	assert(ring_mesh.get_surface_count() > 0, "Ring mesh must have surfaces")
	var arrays = ring_mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert(verts.size() > 0, "Ring mesh must contain vertices")
	print("  PASS: Gimme ring mesh generated with %d vertices flat against green" % verts.size())
	
	# Test 3: Verify Slope Arrow Mesh is a slim flat chevron
	print("\n--- Test 3: Arrow Mesh Profile ---")
	var arrow_mesh = range_instance._create_arrow_mesh()
	assert(arrow_mesh != null, "Arrow mesh must be generated")
	var arrow_arrays = arrow_mesh.surface_get_arrays(0)
	var arrow_verts: PackedVector3Array = arrow_arrays[Mesh.ARRAY_VERTEX]
	assert(arrow_verts.size() > 0, "Arrow mesh must have vertices")
	var max_arrow_y := -INF
	var min_arrow_y := INF
	for v in arrow_verts:
		max_arrow_y = maxf(max_arrow_y, v.y)
		min_arrow_y = minf(min_arrow_y, v.y)
	var arrow_thickness = max_arrow_y - min_arrow_y
	assert(arrow_thickness <= 0.003, "Arrow thickness must be slim (<= 3mm), was %.4f" % arrow_thickness)
	print("  PASS: Slope arrow thickness is slim (%.4f m) to sit flat on turf" % arrow_thickness)
	
	range_instance.free()
	print("\n=== All Flat Green Surface Elements Tests Passed! ===")
	quit(0)
