extends SceneTree

const MATERIALS_DIR = "res://addons/shapespark-low-poly-exterior-plants/materials/"
const BODIES_DIR = "res://addons/shapespark-low-poly-exterior-plants/bodies/"
const MESHES_DIR = "res://addons/shapespark-low-poly-exterior-plants/meshes/"
const TEXTURES_DIR = "res://addons/shapespark-low-poly-exterior-plants/textures/"

func _init():
	print("[create_tree_scenes] Starting creation of tree materials and scenes...")
	_create_materials()
	_create_tree_bodies()
	print("[create_tree_scenes] Finished successfully!")
	quit(0)

func _create_mat_branch(tex_path: String) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.85
	mat.albedo_texture = load(tex_path)
	return mat

func _create_mat_bark(tex_path: String) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.95
	mat.albedo_texture = load(tex_path)
	return mat

func _create_materials():
	# Willow
	var willow_bark = _create_mat_bark(TEXTURES_DIR + "willow-bark.jpg")
	ResourceSaver.save(willow_bark, MATERIALS_DIR + "willow-bark-material.tres")

	var wb01 = _create_mat_branch(TEXTURES_DIR + "willow-branch-01.png")
	ResourceSaver.save(wb01, MATERIALS_DIR + "willow-branch-01-material.tres")

	var wb02 = _create_mat_branch(TEXTURES_DIR + "willow-branch-02.png")
	ResourceSaver.save(wb02, MATERIALS_DIR + "willow-branch-02-material.tres")

	var wb1_01 = _create_mat_branch(TEXTURES_DIR + "willow-branch-1-01.png")
	ResourceSaver.save(wb1_01, MATERIALS_DIR + "willow-branch-1-01-material.tres")

	var wb1_02 = _create_mat_branch(TEXTURES_DIR + "willow-branch-1-02.png")
	ResourceSaver.save(wb1_02, MATERIALS_DIR + "willow-branch-1-02-material.tres")

	# Birch
	var birch_bark = _create_mat_bark(TEXTURES_DIR + "birch-bark.jpg")
	ResourceSaver.save(birch_bark, MATERIALS_DIR + "birch-bark-material.tres")

	var bb01 = _create_mat_branch(TEXTURES_DIR + "birch-branch-01.png")
	ResourceSaver.save(bb01, MATERIALS_DIR + "birch-branch-01-material.tres")

	var bb02 = _create_mat_branch(TEXTURES_DIR + "birch-branch-02.png")
	ResourceSaver.save(bb02, MATERIALS_DIR + "birch-branch-02-material.tres")

	# Autumn Gold
	var agb01 = _create_mat_branch(TEXTURES_DIR + "autumn-gold-branch-01.png")
	ResourceSaver.save(agb01, MATERIALS_DIR + "autumn-gold-branch-01-material.tres")

	var agb02 = _create_mat_branch(TEXTURES_DIR + "autumn-gold-branch-02.png")
	ResourceSaver.save(agb02, MATERIALS_DIR + "autumn-gold-branch-02-material.tres")

	# Autumn Red
	var arb01 = _create_mat_branch(TEXTURES_DIR + "autumn-red-branch-01.png")
	ResourceSaver.save(arb01, MATERIALS_DIR + "autumn-red-branch-01-material.tres")

	var arb02 = _create_mat_branch(TEXTURES_DIR + "autumn-red-branch-02.png")
	ResourceSaver.save(arb02, MATERIALS_DIR + "autumn-red-branch-02-material.tres")

	# Pine
	var pine_bark = _create_mat_bark(TEXTURES_DIR + "pine-bark.jpg")
	ResourceSaver.save(pine_bark, MATERIALS_DIR + "pine-bark-material.tres")

	var pb01 = _create_mat_branch(TEXTURES_DIR + "pine-branch-01.png")
	ResourceSaver.save(pb01, MATERIALS_DIR + "pine-branch-01-material.tres")

	var pb02 = _create_mat_branch(TEXTURES_DIR + "pine-branch-02.png")
	ResourceSaver.save(pb02, MATERIALS_DIR + "pine-branch-02-material.tres")

	# Blossom
	var bl01 = _create_mat_branch(TEXTURES_DIR + "blossom-branch-01.png")
	ResourceSaver.save(bl01, MATERIALS_DIR + "blossom-branch-01-material.tres")

	var bl02 = _create_mat_branch(TEXTURES_DIR + "blossom-branch-02.png")
	ResourceSaver.save(bl02, MATERIALS_DIR + "blossom-branch-02-material.tres")

	print("[create_tree_scenes] Materials saved successfully.")


func _create_tree_bodies():
	# 1. Weeping Willow 1 (based on Tree-01-1)
	_build_variant_body(
		"Tree-Willow-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-1-mesh.tscn",
		MATERIALS_DIR + "willow-bark-material.tres",
		MATERIALS_DIR + "willow-branch-01-material.tres",
		MATERIALS_DIR + "willow-branch-02-material.tres",
		BODIES_DIR + "tree-willow-1-staticbody.tscn",
		Vector3(1.3, 0.95, 1.3), # Broader, drooping canopy silhouette
		Vector3(0, 3.8, 0),       # Canopy position slightly lower
		3.2,                      # Canopy radius wider for cascading branches
		true                      # Is weeping willow
	)

	# 2. Weeping Willow 2 (based on Tree-02-1)
	_build_variant_body(
		"Tree-Willow-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-02-1-mesh.tscn",
		MATERIALS_DIR + "willow-bark-material.tres",
		MATERIALS_DIR + "willow-branch-1-01-material.tres",
		MATERIALS_DIR + "willow-branch-1-02-material.tres",
		BODIES_DIR + "tree-willow-2-staticbody.tscn",
		Vector3(1.35, 0.92, 1.35),
		Vector3(0, 3.7, 0),
		3.3,
		true
	)

	# 3. Weeping Willow 3 (based on Tree-01-3)
	_build_variant_body(
		"Tree-Willow-3-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-3-mesh.tscn",
		MATERIALS_DIR + "willow-bark-material.tres",
		MATERIALS_DIR + "willow-branch-01-material.tres",
		MATERIALS_DIR + "willow-branch-02-material.tres",
		BODIES_DIR + "tree-willow-3-staticbody.tscn",
		Vector3(1.25, 0.96, 1.25),
		Vector3(0, 3.9, 0),
		3.1,
		true
	)

	# 4. Birch 1 (based on Tree-01-2)
	_build_variant_body(
		"Tree-Birch-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-2-mesh.tscn",
		MATERIALS_DIR + "birch-bark-material.tres",
		MATERIALS_DIR + "birch-branch-01-material.tres",
		MATERIALS_DIR + "birch-branch-02-material.tres",
		BODIES_DIR + "tree-birch-1-staticbody.tscn",
		Vector3(0.9, 1.18, 0.9), # Slender, elegant tall birch silhouette
		Vector3(0, 4.6, 0),
		2.4,
		false,
		"birch"
	)

	# 5. Birch 2 (based on Tree-01-4)
	_build_variant_body(
		"Tree-Birch-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-4-mesh.tscn",
		MATERIALS_DIR + "birch-bark-material.tres",
		MATERIALS_DIR + "birch-branch-01-material.tres",
		MATERIALS_DIR + "birch-branch-02-material.tres",
		BODIES_DIR + "tree-birch-2-staticbody.tscn",
		Vector3(0.88, 1.22, 0.88),
		Vector3(0, 4.7, 0),
		2.3,
		false,
		"birch"
	)

	# 6. Autumn Golden Oak 1 (based on Tree-01-1)
	_build_variant_body(
		"Tree-Autumn-Gold-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-1-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-01-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-gold-1-staticbody.tscn",
		Vector3(1.0, 1.0, 1.0),
		Vector3(0, 4.3, 0),
		2.6,
		false,
		"autumn_gold"
	)

	# 7. Autumn Golden Oak 2 (based on Tree-01-2)
	_build_variant_body(
		"Tree-Autumn-Gold-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-2-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-01-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-gold-2-staticbody.tscn",
		Vector3(1.05, 1.02, 1.05),
		Vector3(0, 4.4, 0),
		2.7,
		false,
		"autumn_gold"
	)

	# 8. Autumn Crimson Maple 1 (based on Tree-02-1)
	_build_variant_body(
		"Tree-Autumn-Red-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-02-1-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-red-branch-01-material.tres",
		MATERIALS_DIR + "autumn-red-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-red-1-staticbody.tscn",
		Vector3(1.02, 1.0, 1.02),
		Vector3(0, 4.2, 0),
		2.7,
		false,
		"autumn_red"
	)

	# 9. Autumn Crimson Maple 2 (based on Tree-02-3)
	_build_variant_body(
		"Tree-Autumn-Red-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-02-3-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-red-branch-01-material.tres",
		MATERIALS_DIR + "autumn-red-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-red-2-staticbody.tscn",
		Vector3(1.0, 1.0, 1.0),
		Vector3(0, 4.3, 0),
		2.6,
		false,
		"autumn_red"
	)

	# 10. Evergreen Pine 1 (based on Tree-03-1)
	_build_variant_body(
		"Tree-Pine-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-03-1-mesh.tscn",
		MATERIALS_DIR + "pine-bark-material.tres",
		MATERIALS_DIR + "pine-branch-01-material.tres",
		MATERIALS_DIR + "pine-branch-02-material.tres",
		BODIES_DIR + "tree-pine-1-staticbody.tscn",
		Vector3(0.85, 1.25, 0.85), # Upright conical conifer profile
		Vector3(0, 4.8, 0),
		2.2,
		false,
		"pine"
	)

	# 11. Evergreen Pine 2 (based on Tree-03-3)
	_build_variant_body(
		"Tree-Pine-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-03-3-mesh.tscn",
		MATERIALS_DIR + "pine-bark-material.tres",
		MATERIALS_DIR + "pine-branch-01-material.tres",
		MATERIALS_DIR + "pine-branch-02-material.tres",
		BODIES_DIR + "tree-pine-2-staticbody.tscn",
		Vector3(0.82, 1.28, 0.82),
		Vector3(0, 4.9, 0),
		2.1,
		false,
		"pine"
	)

	# 12. Flowering Blossom (based on Tree-01-1)
	_build_variant_body(
		"Tree-Blossom-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-1-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "blossom-branch-01-material.tres",
		MATERIALS_DIR + "blossom-branch-02-material.tres",
		BODIES_DIR + "tree-blossom-1-staticbody.tscn",
		Vector3(1.08, 0.98, 1.08),
		Vector3(0, 4.1, 0),
		2.7,
		false,
		"blossom"
	)


func _build_variant_body(
	body_name: String,
	mesh_scene_path: String,
	bark_mat_path: String,
	branch1_mat_path: String,
	branch2_mat_path: String,
	out_path: String,
	mesh_scale: Vector3,
	canopy_pos: Vector3,
	canopy_radius: float,
	is_willow: bool = false,
	tree_type_tag: String = ""
):
	var root = StaticBody3D.new()
	root.name = body_name
	root.set_meta("is_tree", true)
	if is_willow:
		root.set_meta("is_willow", true)
		root.set_meta("tree_type", "weeping_willow")
	elif tree_type_tag != "":
		root.set_meta("tree_type", tree_type_tag)

	# Mesh instance child
	var mesh_scene = load(mesh_scene_path) as PackedScene
	var mesh_inst = mesh_scene.instantiate() as MeshInstance3D
	mesh_inst.name = "TreeMesh"
	mesh_inst.scale = mesh_scale

	# Apply surface material overrides
	mesh_inst.set_surface_override_material(0, load(bark_mat_path))
	mesh_inst.set_surface_override_material(1, load(branch1_mat_path))
	mesh_inst.set_surface_override_material(2, load(branch2_mat_path))

	root.add_child(mesh_inst)
	mesh_inst.owner = root

	# If Weeping Willow, add cascading hanging tendril planes around the canopy perimeter
	if is_willow:
		var willow_branch_mat = load(branch1_mat_path) as Material
		_add_hanging_tendrils(root, willow_branch_mat)

	# Trunk Collision Shape (Cylinder)
	var col_shape = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var cyl = CylinderShape3D.new()
	cyl.height = 5.6 * mesh_scale.y
	cyl.radius = 0.38 * max(mesh_scale.x, mesh_scale.z)
	col_shape.shape = cyl
	col_shape.position = Vector3(0, 2.0 * mesh_scale.y, 0)
	root.add_child(col_shape)
	col_shape.owner = root

	# Canopy Area3D for ball flight detection & sound
	var canopy_area = Area3D.new()
	canopy_area.name = "CanopyArea"
	canopy_area.collision_layer = 1
	canopy_area.collision_mask = 0
	canopy_area.set_meta("is_canopy", true)
	if is_willow:
		canopy_area.set_meta("is_willow", true)

	var canopy_shape = CollisionShape3D.new()
	canopy_shape.name = "CollisionShape3D"
	var sphere = SphereShape3D.new()
	sphere.radius = canopy_radius
	canopy_shape.shape = sphere

	canopy_area.add_child(canopy_shape)
	canopy_shape.owner = canopy_area
	canopy_area.position = canopy_pos

	root.add_child(canopy_area)
	canopy_area.owner = root
	canopy_shape.owner = root

	# Save packed scene
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err == OK:
		ResourceSaver.save(packed, out_path)
		print("Saved tree body: ", out_path)
	else:
		push_error("Failed to pack scene: " + out_path + " error: " + str(err))


func _add_hanging_tendrils(parent: Node3D, branch_mat: Material):
	# Creates 6 drooping hanging quads around the canopy perimeter
	var rng = RandomNumberGenerator.new()
	rng.seed = 777
	var tendril_root = Node3D.new()
	tendril_root.name = "WeepingTendrils"
	parent.add_child(tendril_root)
	tendril_root.owner = parent

	var num_tendrils = 7
	for i in range(num_tendrils):
		var angle = (float(i) / float(num_tendrils)) * TAU + rng.randf_range(-0.2, 0.2)
		var rad = rng.randf_range(2.0, 2.7)
		var tx = cos(angle) * rad
		var tz = sin(angle) * rad
		var ty = rng.randf_range(2.8, 3.5) # Hangs down into the lower canopy

		var quad = QuadMesh.new()
		quad.size = Vector2(rng.randf_range(1.6, 2.2), rng.randf_range(2.0, 2.6))
		quad.material = branch_mat

		var mi = MeshInstance3D.new()
		mi.name = "Tendril_%d" % i
		mi.mesh = quad
		mi.position = Vector3(tx, ty, tz)
		# Face tangential or outward + random tilt
		mi.rotation.y = angle + PI * 0.5 + rng.randf_range(-0.3, 0.3)
		mi.rotation.x = rng.randf_range(0.05, 0.25) # Slightly tilted outward so leaves drape down

		tendril_root.add_child(mi)
		mi.owner = parent
