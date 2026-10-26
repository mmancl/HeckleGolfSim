extends SceneTree

const CourseDetailEnhancerScript = preload("res://HighFidelity/Terrain/course_detail_enhancer.gd")
const HighFidelityGrassScript = preload("res://HighFidelity/Foliage/high_fidelity_grass.gd")

func _init() -> void:
	print("=======================================================")
	print("TEST: Shoreline Elevation Following & Water Exclusion")
	print("=======================================================")

	# 1. Test sloped shoreline: water at Y = -2.0, terrain rises from -2.0 to +4.0 as distance from water increases
	var scene_root := Node3D.new()
	scene_root.name = "TestShorelineScene"
	root.add_child(scene_root)

	var water_body := StaticBody3D.new()
	water_body.name = "water_Static_500"
	water_body.set_meta("is_water", true)
	var water_pts := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(40.0, 0.0),
		Vector2(40.0, 40.0),
		Vector2(0.0, 40.0)
	])
	water_body.set_meta("water_points", water_pts)

	var col_shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	var faces := PackedVector3Array([
		Vector3(0.0, -2.0, 0.0), Vector3(40.0, -2.0, 0.0), Vector3(40.0, -2.0, 40.0),
		Vector3(0.0, -2.0, 0.0), Vector3(40.0, -2.0, 40.0), Vector3(0.0, -2.0, 40.0)
	])
	concave.set_faces(faces)
	col_shape.shape = concave
	water_body.add_child(col_shape)
	scene_root.add_child(water_body)

	# Terrain height grid: slope rising away from the water edge (Y = -2.0 at edge, rising up to +3.0)
	var height_info := {
		"min_x": -60.0, "max_x": 60.0,
		"min_z": -60.0, "max_z": 60.0,
		"avg_edge_y": 0.0,
		"cell_size": 2.0,
		"grid": {}
	}
	for gx in range(-30, 30):
		for gz in range(-30, 30):
			var wx := float(gx) * 2.0
			var wz := float(gz) * 2.0
			# Distance outside the [0..40]x[0..40] square
			var dx := maxf(0.0, maxf(-wx, wx - 40.0))
			var dz := maxf(0.0, maxf(-wz, wz - 40.0))
			var dist := sqrt(dx * dx + dz * dz)
			var y: float
			if dx == 0.0 and dz == 0.0:
				y = -3.5 # Depressed lake basin
			else:
				y = -2.0 + dist * 0.8 # Bank slopes upward by 0.8m per meter away from shore
			height_info["grid"][Vector2i(gx, gz)] = y

	var reed_count := CourseDetailEnhancerScript._build_shoreline_reeds(scene_root, height_info, false)
	assert(reed_count > 0, "Shoreline reeds must be generated")

	var reeds_mmi := scene_root.get_node("ShorelineReedsMultiMesh") as MultiMeshInstance3D
	var mm := reeds_mmi.multimesh
	assert(mm.instance_count == reed_count, "MultiMesh count must match")

	# Verify:
	# 1. No instance is below water level (-2.0)
	# 2. Instances vary in elevation as they climb the slope (not a flat plane!)
	var min_y := 99999.0
	var max_y := -99999.0
	var y_values: Array[float] = []
	var has_buf := mm.buffer.size() >= mm.instance_count * 16
	for i in range(mm.instance_count):
		var y: float
		if has_buf:
			y = mm.buffer[i * 16 + 7]
		else:
			y = mm.get_instance_transform(i).origin.y
		if y < min_y: min_y = y
		if y > max_y: max_y = y
		y_values.append(y)
		assert(y >= -2.15, "Reed instance %d at Y=%f must never be submerged below basin limit (-2.15)" % [i, y])

	print("  PASS: All %d reeds are securely grounded (min Y: %f >= -2.15)." % [reed_count, min_y])
	print("  PASS: Reed elevation spans [%.2f .. %.2f] (elevation delta: %.2fm), following terrain slope." % [min_y, max_y, max_y - min_y])
	assert(max_y - min_y > 0.3, "Reeds must follow bank slope and not be a flat plane (expected elevation delta > 0.3m, got %.2fm)" % [max_y - min_y])

	# 2. Test HighFidelityGrass water hazard exclusion
	var grass := HighFidelityGrassScript.new()
	scene_root.add_child(grass)
	grass.setup(scene_root)

	assert(grass.get("_water_polys").size() == 1, "HighFidelityGrass must detect water hazard polygon")
	assert(grass.call("_is_in_bunker_or_hazard", 20.0, 20.0) == true, "Center of water pond (20, 20) must be detected as hazard")
	assert(grass.call("_is_in_bunker_or_hazard", -10.0, -10.0) == false, "Dry land (-10, -10) must not be hazard")
	print("  PASS: HighFidelityGrass accurately detects water hazards and excludes grass in ponds.")

	scene_root.queue_free()
	print("=======================================================")
	print("ALL SHORELINE PROFILE & WATER EXCLUSION TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)
