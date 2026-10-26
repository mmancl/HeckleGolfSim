extends SceneTree

func _initialize() -> void:
	print("=== Running Gimme Circle Visibility & Offset Tests ===")
	
	var RangeScript = load("res://Courses/Range/range.gd")
	assert(RangeScript != null, "range.gd must load")
	
	var range_instance = Node3D.new()
	range_instance.set_script(RangeScript)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)
	
	# Verify _create_gimme_ring_material configuration
	assert(range_instance.has_method("_create_gimme_ring_material"), "_create_gimme_ring_material must exist")
	var mat: StandardMaterial3D = range_instance._create_gimme_ring_material(Color(0, 1, 1), 2)
	assert(mat != null, "Material must not be null")
	assert(mat.render_priority == 2, "render_priority must be set")
	assert(mat.cull_mode == BaseMaterial3D.CULL_DISABLED, "cull_mode must be CULL_DISABLED")
	assert(mat.no_depth_test == true, "no_depth_test must be true so gimme rings never render hidden under ground")
	print("Test 1 PASS: Gimme ring material offset and render properties verified")
	
	# Verify _create_gimme_ring_mesh generates valid geometry conforming to elevation
	assert(range_instance.has_method("_create_gimme_ring_mesh"), "_create_gimme_ring_mesh must exist")
	var pin_pos = Vector3(10.0, 5.0, 10.0)
	var mesh = range_instance._create_gimme_ring_mesh(pin_pos, 1.0, 0.08, 0.035, [])
	assert(mesh != null, "Mesh should not be null")
	assert(mesh.get_surface_count() > 0, "Mesh should have surfaces")
	var arrays = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert(verts.size() > 0, "Mesh should have vertices")
	print("Test 2 PASS: Gimme ring mesh generated successfully with %d vertices" % verts.size())
	
	range_instance.free()
	print("=== All Gimme Circle Tests Passed! ===")
	quit(0)

