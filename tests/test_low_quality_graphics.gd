extends SceneTree

const MobilePerformance = preload("res://Utils/mobile_performance.gd")

func _init() -> void:
	print("--- Running test_low_quality_graphics.gd ---")
	test_water_hazard_grass_hidden_on_low()
	test_water_hazard_grass_visible_on_medium()
	test_low_quality_tree_materials()
	print("ALL LOW QUALITY GRAPHICS TESTS PASSED!")
	quit(0)

func test_water_hazard_grass_hidden_on_low() -> void:
	print("Testing grass around water hazards hidden on Low quality...")
	var root := Node3D.new()
	var reeds := MultiMeshInstance3D.new()
	reeds.name = "ShorelineReedsMultiMesh"
	reeds.multimesh = MultiMesh.new()
	reeds.multimesh.mesh = BoxMesh.new()
	reeds.multimesh.instance_count = 10
	reeds.visible = true
	root.add_child(reeds)

	# Apply Low graphics quality
	MobilePerformance.apply_graphics_quality(root, "Low")

	assert(reeds.visible == false, "ShorelineReedsMultiMesh must be hidden on Low graphics quality")
	print("  PASS: Water hazard grass is hidden on Low quality")
	root.free()

func test_water_hazard_grass_visible_on_medium() -> void:
	print("Testing grass around water hazards visible on Medium quality...")
	var root := Node3D.new()
	var reeds := MultiMeshInstance3D.new()
	reeds.name = "ShorelineReedsMultiMesh"
	reeds.multimesh = MultiMesh.new()
	reeds.multimesh.mesh = BoxMesh.new()
	reeds.multimesh.instance_count = 10
	reeds.visible = false
	root.add_child(reeds)

	# Apply Medium
	MobilePerformance.apply_graphics_quality(root, "Medium")
	var reeds_node := root.get_node_or_null("ShorelineReedsMultiMesh") as MultiMeshInstance3D
	assert(reeds_node != null and reeds_node.visible == true, "ShorelineReedsMultiMesh must be visible on Medium graphics quality")

	print("  PASS: Water hazard grass is visible on Medium quality")
	root.free()

func test_low_quality_tree_materials() -> void:
	print("Testing stylized cartoon low quality tree materials...")
	var orig_trunk_mat: Material = load("res://addons/shapespark-low-poly-exterior-plants/materials/bark-material.tres")
	var orig_leaf_mat: Material = load("res://addons/shapespark-low-poly-exterior-plants/materials/branch-01-material.tres")

	var low_trunk_m = MobilePerformance._get_low_tree_material(orig_trunk_mat, "Trunk", 0)
	var low_leaf_m = MobilePerformance._get_low_tree_material(orig_leaf_mat, "Branch_1", 1)

	assert(low_trunk_m != null, "Low trunk material must not be null")
	assert(low_leaf_m != null, "Low leaf material must not be null")

	# Low trunk material must be stylized cartoon (either ShaderMaterial with trunk_low or non-photographic matte)
	if low_trunk_m is ShaderMaterial:
		assert((low_trunk_m as ShaderMaterial).shader != null, "Trunk shader must be loaded")
		assert((low_trunk_m as ShaderMaterial).shader.resource_path.contains("trunk_low"), "Must use trunk_low shader")
	elif low_trunk_m is BaseMaterial3D:
		assert((low_trunk_m as BaseMaterial3D).albedo_texture == null, "Trunk material must have zero photo noise (albedo_texture null)")

	# Low leaf material must be stylized cartoon (either ShaderMaterial with foliage_low or toon alpha cutout)
	if low_leaf_m is ShaderMaterial:
		assert((low_leaf_m as ShaderMaterial).shader != null, "Foliage shader must be loaded")
		assert((low_leaf_m as ShaderMaterial).shader.resource_path.contains("foliage_low"), "Must use foliage_low shader")
	elif low_leaf_m is BaseMaterial3D:
		assert((low_leaf_m as BaseMaterial3D).diffuse_mode == BaseMaterial3D.DIFFUSE_TOON, "Foliage must use toon diffuse")

	# Verify Low quality materials are distinctly different from Medium quality orig_mat
	assert(low_trunk_m != orig_trunk_mat, "Low trunk material must be distinct from Medium quality")
	assert(low_leaf_m != orig_leaf_mat, "Low foliage material must be distinct from Medium quality")

	print("  PASS: Low quality tree materials are stylized cartoon and distinct from Medium quality")
