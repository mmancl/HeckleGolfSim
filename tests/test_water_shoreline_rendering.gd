extends SceneTree

const CourseDetailEnhancerScript = preload("res://HighFidelity/Terrain/course_detail_enhancer.gd")
const ProceduralTreeGeneratorScript = preload("res://HighFidelity/Foliage/procedural_tree_generator.gd")

func _init() -> void:
	print("=======================================================")
	print("STARTING TEST: Water Shoreline & Long Grass Elevation")
	print("=======================================================")

	# 1. Verify water shader compiles and loads cleanly
	var water_shader := load("res://Courses/Environments/shaders/water_shader.gdshader") as Shader
	assert(water_shader != null, "water_shader.gdshader must load successfully")
	var water_mat := ShaderMaterial.new()
	water_mat.shader = water_shader
	assert(water_mat.shader != null, "ShaderMaterial with water_shader must be valid")
	print("  PASS: Water shader loaded and compiled cleanly.")

	# 2. Verify shoreline reed mesh has grounded root base
	var reed_mesh := ProceduralTreeGeneratorScript.create_shoreline_reed_cluster_mesh()
	assert(reed_mesh != null and reed_mesh.get_surface_count() > 0, "Reed cluster mesh must be valid")
	var aabb := reed_mesh.get_aabb()
	assert(aabb.size.y > 1.0, "Reed cluster mesh must have vertical stalks (height > 1.0m)")
	assert(aabb.position.y >= -0.01, "Reed cluster mesh roots must start at or above y=0 (no hanging negative roots)")
	print("  PASS: Procedural shoreline reed cluster mesh verified with grounded base.")

	# 3. Test CourseDetailEnhancer._build_shoreline_reeds elevation clamping
	# Create a mock scene with terrain and a water pond at Y = -2.5
	var scene_root := Node3D.new()
	scene_root.name = "MockCourse"
	root.add_child(scene_root)

	var water_body := StaticBody3D.new()
	water_body.name = "water_Static_1001"
	water_body.set_meta("is_water", true)
	var water_pts := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(20.0, 0.0),
		Vector2(20.0, 20.0),
		Vector2(0.0, 20.0)
	])
	water_body.set_meta("water_points", water_pts)

	# Water collision shape at Y = -2.5
	var col_shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array([
		Vector3(0.0, -2.5, 0.0), Vector3(20.0, -2.5, 0.0), Vector3(20.0, -2.5, 20.0),
		Vector3(0.0, -2.5, 0.0), Vector3(20.0, -2.5, 20.0), Vector3(0.0, -2.5, 20.0)
	])
	concave.set_faces(faces)
	col_shape.shape = concave
	water_body.add_child(col_shape)
	scene_root.add_child(water_body)

	# Simulate terrain that was depressed BELOW water level (e.g. Y = -2.85)
	var height_info := {
		"min_x": -50.0, "max_x": 50.0,
		"min_z": -50.0, "max_z": 50.0,
		"avg_edge_y": -2.85,
		"grid": {}
	}
	for gx in range(-15, 15):
		for gz in range(-15, 15):
			height_info["grid"][Vector2i(gx, gz)] = -2.85

	var reed_count := CourseDetailEnhancerScript._build_shoreline_reeds(scene_root, height_info, false)
	assert(reed_count > 0, "Shoreline reeds must be generated around water pond")
	assert(scene_root.has_node("ShorelineReedsMultiMesh"), "ShorelineReedsMultiMesh node must exist")

	var reeds_mmi := scene_root.get_node("ShorelineReedsMultiMesh") as MultiMeshInstance3D
	var mm := reeds_mmi.multimesh
	assert(mm != null, "MultiMesh must exist")
	assert(mm.instance_count == reed_count, "Instance count must match generated count")

	# Verify EVERY reed instance is clamped at or above the water line (-2.5)
	var min_reed_y := 99999.0
	for i in range(mm.instance_count):
		var xf := mm.get_instance_transform(i)
		var reed_y := xf.origin.y
		if reed_y < min_reed_y:
			min_reed_y = reed_y
		assert(reed_y >= -2.5, "Reed instance %d Y (%f) must be >= water level (-2.5) to prevent water under grass" % [i, reed_y])

	print("  PASS: All %d shoreline reed instances properly elevated above water surface (lowest Y: %f >= -2.5)." % [reed_count, min_reed_y])

	scene_root.queue_free()
	print("=======================================================")
	print("ALL WATER SHORELINE TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)
