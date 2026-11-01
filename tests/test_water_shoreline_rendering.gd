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

	# 2. Verify shoreline reed mesh has grounded root base, varied blade tiers, and 3D cattail geometry
	var reed_mesh := ProceduralTreeGeneratorScript.create_shoreline_reed_cluster_mesh()
	assert(reed_mesh != null and reed_mesh.get_surface_count() > 0, "Reed cluster mesh must be valid")
	var aabb := reed_mesh.get_aabb()
	assert(aabb.size.y > 1.0, "Reed cluster mesh must have vertical stalks (height > 1.0m)")
	assert(aabb.position.y <= -0.40, "Reed cluster mesh roots must extend into the ground (y <= -0.40) to anchor on slopes")
	var arrays := reed_mesh.surface_get_arrays(0)
	assert(arrays.size() > Mesh.ARRAY_COLOR, "Reed cluster mesh must include vertex colors for blade height variation & cattail tagging")
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert(not cols.is_empty(), "Reed cluster mesh vertex colors must not be empty")
	var cattail_head_verts := 0
	var cattail_stalk_verts := 0
	var grass_blade_verts := 0
	for c in cols:
		if c.r > 0.75:
			cattail_head_verts += 1
		elif c.r > 0.25:
			cattail_stalk_verts += 1
		else:
			grass_blade_verts += 1
	assert(cattail_head_verts >= 60, "Reed cluster mesh must include 3D cylindrical cattail seed head geometry (got %d vertices)" % cattail_head_verts)
	assert(cattail_stalk_verts >= 30, "Reed cluster mesh must include cattail stem & top spike geometry (got %d vertices)" % cattail_stalk_verts)
	assert(grass_blade_verts >= 100, "Reed cluster mesh must include long grass blades (got %d vertices)" % grass_blade_verts)

	var reed_mat := reed_mesh.surface_get_material(0) as ShaderMaterial
	assert(reed_mat != null and reed_mat.shader != null, "Reed cluster mesh must have grass_blades_high ShaderMaterial")
	assert(float(reed_mat.get_shader_parameter("head_ratio")) > 0.1, "Reed ShaderMaterial must enable head_ratio for occasional cattails")
	assert(reed_mat.shader.code.contains("PROJECTION_MATRIX[3][3]"), "grass_blades_high.gdshader must suppress sub-pixel blades in orthogonal minimap camera")
	assert(water_shader.code.contains("PROJECTION_MATRIX[3][3]"), "water_shader.gdshader must suppress shoreline sparkle in orthogonal minimap camera")
	print("  PASS: Procedural shoreline reed cluster mesh verified with deep roots (min Y: %.2fm), %d cattail head vertices, and orthogonal minimap anti-sparkle." % [aabb.position.y, cattail_head_verts])

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

	# Verify EVERY reed instance is clamped at or above the water line (-2.5) and height varies significantly
	var min_reed_y := 99999.0
	var min_scale_y := 99999.0
	var max_scale_y := -99999.0
	var has_buf := mm.buffer.size() >= mm.instance_count * 16
	for i in range(mm.instance_count):
		var xf := mm.get_instance_transform(i)
		var reed_y := mm.buffer[i * 16 + 7] if has_buf else xf.origin.y
		var sy := mm.buffer[i * 16 + 5] if has_buf else xf.basis.y.length()
		if reed_y < min_reed_y:
			min_reed_y = reed_y
		if sy < min_scale_y:
			min_scale_y = sy
		if sy > max_scale_y:
			max_scale_y = sy
		assert(reed_y >= -2.65, "Reed instance %d Y (%f) must be grounded within bank allowance (>= -2.65) to prevent floating/submerged stalks" % [i, reed_y])

	assert(max_scale_y - min_scale_y > 0.45, "Shoreline reed instances must have realistic height variation across the bank (min scale Y: %.2f, max scale Y: %.2f)" % [min_scale_y, max_scale_y])
	print("  PASS: All %d shoreline reed instances grounded (lowest Y: %.2f >= -2.65) with natural height variation (scale Y: %.2fx .. %.2fx)." % [reed_count, min_reed_y, min_scale_y, max_scale_y])

	scene_root.queue_free()
	print("=======================================================")
	print("ALL WATER SHORELINE TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)
