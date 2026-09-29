@tool
extends SceneTree

const MATERIALS_DIR = "res://addons/shapespark-low-poly-exterior-plants/materials/"
const BODIES_DIR = "res://addons/shapespark-low-poly-exterior-plants/bodies/"
const TEXTURES_DIR = "res://addons/shapespark-low-poly-exterior-plants/textures/"

func _init():
	print("[build_willow_model] Generating full-domed SpeedTree-style Weeping Willow models...")
	_create_willow_materials()
	_generate_willow_scene("green", BODIES_DIR + "tree-willow-1-staticbody.tscn", 111)
	_generate_willow_scene("gold",  BODIES_DIR + "tree-willow-2-staticbody.tscn", 222)
	_generate_willow_scene("green", BODIES_DIR + "tree-willow-3-staticbody.tscn", 333)
	print("[build_willow_model] Weeping Willow models created successfully!")
	quit(0)

func _create_willow_materials():
	# Bark material
	var bark_mat = StandardMaterial3D.new()
	bark_mat.roughness = 0.95
	var bark_tex = load(TEXTURES_DIR + "willow-bark.jpg")
	if bark_tex:
		bark_mat.albedo_texture = bark_tex
	else:
		bark_mat.albedo_color = Color(0.22, 0.18, 0.14)
	bark_mat.uv1_scale = Vector3(1.0, 4.0, 1.0)
	ResourceSaver.save(bark_mat, MATERIALS_DIR + "willow-bark-material.tres")

	# Green Crown dome material
	var crown_green = StandardMaterial3D.new()
	crown_green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	crown_green.alpha_scissor_threshold = 0.45
	crown_green.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown_green.roughness = 0.75
	crown_green.albedo_texture = load(TEXTURES_DIR + "willow-crown-green.png")
	ResourceSaver.save(crown_green, MATERIALS_DIR + "willow-crown-green-material.tres")

	# Gold Crown dome material
	var crown_gold = StandardMaterial3D.new()
	crown_gold.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	crown_gold.alpha_scissor_threshold = 0.45
	crown_gold.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown_gold.roughness = 0.75
	crown_gold.albedo_texture = load(TEXTURES_DIR + "willow-crown-gold.png")
	ResourceSaver.save(crown_gold, MATERIALS_DIR + "willow-crown-gold-material.tres")

	# Green Curtain material
	var curtain_green = StandardMaterial3D.new()
	curtain_green.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	curtain_green.alpha_scissor_threshold = 0.45
	curtain_green.cull_mode = BaseMaterial3D.CULL_DISABLED
	curtain_green.roughness = 0.75
	curtain_green.albedo_texture = load(TEXTURES_DIR + "willow-curtain-green.png")
	ResourceSaver.save(curtain_green, MATERIALS_DIR + "willow-curtain-green-material.tres")

	# Gold Curtain material
	var curtain_gold = StandardMaterial3D.new()
	curtain_gold.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	curtain_gold.alpha_scissor_threshold = 0.45
	curtain_gold.cull_mode = BaseMaterial3D.CULL_DISABLED
	curtain_gold.roughness = 0.75
	curtain_gold.albedo_texture = load(TEXTURES_DIR + "willow-curtain-gold.png")
	ResourceSaver.save(curtain_gold, MATERIALS_DIR + "willow-curtain-gold-material.tres")

	print("[build_willow_model] Saved willow materials.")


func _generate_willow_scene(palette: String, out_path: String, seed_val: int):
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val

	var bark_mat = load(MATERIALS_DIR + "willow-bark-material.tres") as Material
	var crown_mat = load(MATERIALS_DIR + ("willow-crown-green-material.tres" if palette == "green" else "willow-crown-gold-material.tres")) as Material
	var curtain_mat = load(MATERIALS_DIR + ("willow-curtain-green-material.tres" if palette == "green" else "willow-curtain-gold-material.tres")) as Material

	# Virtual lighting center for spherical normals (centered inside crown volume)
	var canopy_center = Vector3(0, 4.0, 0)
	var apex_y = 7.0 + rng.randf_range(-0.15, 0.15)
	var max_radius = 3.5 + rng.randf_range(-0.15, 0.15)
	var rim_y = 3.6 + rng.randf_range(-0.1, 0.1)

	# -------------------------------------------------------------
	# 1. Surface 0: Wood Trunk, Buttress Roots, and Ascending Scaffold Boughs
	# -------------------------------------------------------------
	var st_trunk = SurfaceTool.new()
	st_trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_trunk.set_material(bark_mat)

	# Buttressed root flare trunk nodes:
	var trunk_nodes = [
		{"pos": Vector3(0, 0, 0), "r": 0.60},
		{"pos": Vector3(rng.randf_range(-0.03, 0.03), 0.3, rng.randf_range(-0.03, 0.03)), "r": 0.48},
		{"pos": Vector3(rng.randf_range(-0.04, 0.04), 0.8, rng.randf_range(-0.04, 0.04)), "r": 0.40},
		{"pos": Vector3(rng.randf_range(-0.05, 0.05), 1.4, rng.randf_range(-0.05, 0.05)), "r": 0.35},
		{"pos": Vector3(rng.randf_range(-0.06, 0.06), 1.9, rng.randf_range(-0.06, 0.06)), "r": 0.30},
	]
	_build_tube_branch(st_trunk, trunk_nodes, 8, rng)

	# 4 Flaring buttress root spurs spreading onto ground
	for r_i in range(4):
		var r_angle = float(r_i) * (TAU / 4.0) + rng.randf_range(-0.2, 0.2)
		var root_nodes = [
			{"pos": Vector3(cos(r_angle) * 0.32, 0.35, sin(r_angle) * 0.32), "r": 0.16},
			{"pos": Vector3(cos(r_angle) * 0.60, 0.10, sin(r_angle) * 0.60), "r": 0.10},
			{"pos": Vector3(cos(r_angle) * 0.85, 0.0, sin(r_angle) * 0.85), "r": 0.04},
		]
		_build_tube_branch(st_trunk, root_nodes, 5, rng)

	var p_split = trunk_nodes[-1]["pos"]
	var curtain_attach_points: Array[Vector3] = []

	# Scaffold Boughs:
	# Central ascending boughs reaching high into the dome (up to Y=5.8m - 6.5m)
	var num_central_boughs = 2
	for i in range(num_central_boughs):
		var angle = float(i) * PI + rng.randf_range(-0.3, 0.3)
		var h_mid = rng.randf_range(4.2, 4.8)
		var h_top = rng.randf_range(5.8, 6.5)
		var r_top = rng.randf_range(0.6, 1.2)

		var p1 = p_split + Vector3(cos(angle) * 0.45, 1.5, sin(angle) * 0.45)
		var p2 = Vector3(cos(angle) * (r_top * 0.7), h_mid, sin(angle) * (r_top * 0.7))
		var p3 = Vector3(cos(angle) * r_top, h_top, sin(angle) * r_top)

		var bough_nodes = [
			{"pos": p_split, "r": 0.25},
			{"pos": p1, "r": 0.19},
			{"pos": p2, "r": 0.14},
			{"pos": p3, "r": 0.08},
		]
		_build_tube_branch(st_trunk, bough_nodes, 6, rng)

		# Sub-branches arching at top of central dome
		for sub_i in range(2):
			var sub_ang = angle + (1.0 if sub_i == 0 else -1.0) * rng.randf_range(0.6, 1.1)
			var sub_r = rng.randf_range(1.2, 2.0)
			var sub_h = h_top - rng.randf_range(0.5, 0.9)
			var sub_tip = Vector3(cos(sub_ang) * sub_r, sub_h, sin(sub_ang) * sub_r)
			var sub_nodes = [
				{"pos": p2, "r": 0.11},
				{"pos": (p2 + sub_tip) * 0.5 + Vector3(0, rng.randf_range(0.15, 0.3), 0), "r": 0.07},
				{"pos": sub_tip, "r": 0.04},
			]
			_build_tube_branch(st_trunk, sub_nodes, 5, rng)
			curtain_attach_points.append(sub_tip)

	# Outer spreading scaffold limbs arching outward and up to rim
	var num_outer_limbs = 5
	for i in range(num_outer_limbs):
		var angle = (float(i) / float(num_outer_limbs)) * TAU + rng.randf_range(-0.25, 0.25)
		var limb_reach = rng.randf_range(2.4, 3.2)
		var limb_peak_h = rng.randf_range(4.2, 5.0)
		var limb_tip_h = limb_peak_h - rng.randf_range(0.5, 0.9)

		var p1 = p_split + Vector3(cos(angle) * 0.8, 1.0, sin(angle) * 0.8)
		var p2 = Vector3(cos(angle) * (limb_reach * 0.65), limb_peak_h, sin(angle) * (limb_reach * 0.65))
		var p3 = Vector3(cos(angle) * limb_reach, limb_tip_h, sin(angle) * limb_reach)

		var limb_nodes = [
			{"pos": p_split, "r": 0.24},
			{"pos": p1, "r": 0.18},
			{"pos": p2, "r": 0.12},
			{"pos": p3, "r": 0.07},
		]
		_build_tube_branch(st_trunk, limb_nodes, 6, rng)
		curtain_attach_points.append(p3)

		# Secondary outward arching branch
		var sub_angle = angle + rng.randf_range(0.4, 0.75) * (1.0 if rng.randf() > 0.5 else -1.0)
		var sub_reach = rng.randf_range(2.0, 2.8)
		var sub_h = limb_peak_h - rng.randf_range(0.3, 0.7)
		var sub_tip = Vector3(cos(sub_angle) * sub_reach, sub_h, sin(sub_angle) * sub_reach)
		var sub_nodes = [
			{"pos": p2, "r": 0.10},
			{"pos": (p2 + sub_tip) * 0.5 + Vector3(0, rng.randf_range(0.1, 0.25), 0), "r": 0.06},
			{"pos": sub_tip, "r": 0.04},
		]
		_build_tube_branch(st_trunk, sub_nodes, 5, rng)
		curtain_attach_points.append(sub_tip)

	st_trunk.generate_normals()
	var willow_mesh = st_trunk.commit()

	# -------------------------------------------------------------
	# 2. Surface 1: Crown Foliage Dome (Lush, Full Rounded Canopy Top & Shell)
	# -------------------------------------------------------------
	var st_crown = SurfaceTool.new()
	st_crown.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_crown.set_material(crown_mat)

	# Helper lambda to compute dome surface height at radius r
	var dome_height = func(r: float) -> float:
		var norm_r = clamp(r / max_radius, 0.0, 1.0)
		return apex_y - (apex_y - rim_y) * pow(norm_r, 1.7)

	# Tier A: Apex Dome Cap (Highest rounded summit of tree, r in 0.0 to 1.3m)
	var num_apex_cards = 20
	for i in range(num_apex_cards):
		var angle = (float(i) / float(num_apex_cards)) * TAU + rng.randf_range(-0.15, 0.15)
		var rad = rng.randf_range(0.1, 1.3)
		var y = dome_height.call(rad) + rng.randf_range(-0.2, 0.1)
		var pos = Vector3(cos(angle) * rad, y, sin(angle) * rad)
		var card_w = rng.randf_range(1.6, 2.1)
		var card_h = rng.randf_range(1.4, 1.9)

		# Add crossed pair
		_add_oriented_quad(st_crown, pos, card_w, card_h, angle + PI * 0.5, -0.2, canopy_center, rng)
		_add_oriented_quad(st_crown, pos, card_w, card_h, angle, -0.15, canopy_center, rng)

	# Tier B: Upper Dome Shell (r in 1.1m to 2.4m, height ~5.2m to 6.4m)
	var num_upper_cards = 26
	for i in range(num_upper_cards):
		var angle = (float(i) / float(num_upper_cards)) * TAU + rng.randf_range(-0.18, 0.18)
		var rad = rng.randf_range(1.1, 2.4)
		var y = dome_height.call(rad) + rng.randf_range(-0.2, 0.2)
		var pos = Vector3(cos(angle) * rad, y, sin(angle) * rad)
		var card_w = rng.randf_range(1.7, 2.2)
		var card_h = rng.randf_range(1.5, 2.0)

		# Tangential card tilted along dome curvature (~35 degrees outward slope)
		_add_oriented_quad(st_crown, pos, card_w, card_h, angle + PI * 0.5, 0.60, canopy_center, rng)
		# Cross companion facing outward
		_add_oriented_quad(st_crown, pos, card_w * 0.9, card_h * 0.9, angle, 0.25, canopy_center, rng)

	# Tier C: Mid Dome & Outer Rim (r in 2.2m to 3.5m, height ~3.6m to 5.2m)
	# Downward sloping dome shell and perimeter filler
	var num_mid_cards = 28
	for i in range(num_mid_cards):
		var angle = (float(i) / float(num_mid_cards)) * TAU + rng.randf_range(-0.15, 0.15)
		var rad = rng.randf_range(2.1, max_radius * 0.95)
		var y = dome_height.call(rad) + rng.randf_range(-0.2, 0.2)
		var pos = Vector3(cos(angle) * rad, y, sin(angle) * rad)
		var card_w = rng.randf_range(1.7, 2.2)
		var card_h = rng.randf_range(1.6, 2.1)

		# Tilted steeply outward (~55 degrees) to round over the edge
		_add_oriented_quad(st_crown, pos, card_w, card_h, angle + PI * 0.5, 0.95, canopy_center, rng)
		_add_oriented_quad(st_crown, pos, card_w * 0.85, card_h * 0.85, angle, 0.35, canopy_center, rng)

	# Tier D: Internal Volume Fillers (along ascending boughs, r in 0.6m to 1.8m, y in 3.2m to 5.2m)
	# Ensures the tree looks lush and full from underneath and through curtain openings
	var num_inner_cards = 16
	for i in range(num_inner_cards):
		var angle = (float(i) / float(num_inner_cards)) * TAU + rng.randf_range(-0.25, 0.25)
		var rad = rng.randf_range(0.6, 1.8)
		var y = rng.randf_range(3.2, 5.2)
		var pos = Vector3(cos(angle) * rad, y, sin(angle) * rad)
		_add_oriented_quad(st_crown, pos, rng.randf_range(1.5, 2.0), rng.randf_range(1.4, 1.9), angle + rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.3), canopy_center, rng)

	st_crown.commit(willow_mesh)

	# -------------------------------------------------------------
	# 3. Surface 2: Cascading Weeping Foliage Curtains
	# -------------------------------------------------------------
	var st_curtain = SurfaceTool.new()
	st_curtain.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_curtain.set_material(curtain_mat)

	# Outer Low Skirt Curtains (Hanging from under the rim towards ground, Y=0.9m - 1.4m)
	var num_outer_curtains = 28
	for i in range(num_outer_curtains):
		var angle = (float(i) / float(num_outer_curtains)) * TAU + rng.randf_range(-0.12, 0.12)
		var rad = rng.randf_range(max_radius * 0.80, max_radius * 1.04)
		var top_y = dome_height.call(rad) - rng.randf_range(0.15, 0.5)
		var top_pos = Vector3(cos(angle) * rad, top_y, sin(angle) * rad)
		var card_w = rng.randf_range(1.4, 1.9)
		# Hanging curtain height: hangs down to Y = 0.9m - 1.4m!
		var card_h = top_y - rng.randf_range(0.9, 1.4)

		# Tangential card hanging down + subtle cross companion
		_add_hanging_curtain_quad(st_curtain, top_pos, card_w, card_h, angle + PI * 0.5 + rng.randf_range(-0.2, 0.2), canopy_center, rng)
		_add_hanging_curtain_quad(st_curtain, top_pos, card_w * 0.85, card_h * 0.95, angle + rng.randf_range(-0.25, 0.25), canopy_center, rng)

	# Mid Canopy Interior Curtains (Hanging from mid boughs at r in 1.4m to 2.4m down to Y=1.6m - 2.2m)
	var num_mid_curtains = 18
	for i in range(num_mid_curtains):
		var angle = (float(i) / float(num_mid_curtains)) * TAU + rng.randf_range(-0.2, 0.2)
		var rad = rng.randf_range(1.4, 2.4)
		var top_y = dome_height.call(rad) - rng.randf_range(0.2, 0.6)
		var top_pos = Vector3(cos(angle) * rad, top_y, sin(angle) * rad)
		var card_w = rng.randf_range(1.3, 1.7)
		var card_h = top_y - rng.randf_range(1.6, 2.2)

		_add_hanging_curtain_quad(st_curtain, top_pos, card_w, card_h, angle + PI * 0.5 + rng.randf_range(-0.3, 0.3), canopy_center, rng)
		_add_hanging_curtain_quad(st_curtain, top_pos, card_w * 0.85, card_h * 0.9, angle + rng.randf_range(-0.3, 0.3), canopy_center, rng)

	# Curtains attached directly to limb tips
	for tip in curtain_attach_points:
		var tip_angle = atan2(tip.z, tip.x)
		var card_w = rng.randf_range(1.4, 1.8)
		var card_h = tip.y - rng.randf_range(0.9, 1.4)
		_add_hanging_curtain_quad(st_curtain, tip, card_w, card_h, tip_angle + PI * 0.5, canopy_center, rng)
		_add_hanging_curtain_quad(st_curtain, tip, card_w * 0.85, card_h * 0.9, tip_angle + PI * 0.15, canopy_center, rng)

	st_curtain.commit(willow_mesh)

	# -------------------------------------------------------------
	# 4. Assemble StaticBody3D Scene
	# -------------------------------------------------------------
	var root = StaticBody3D.new()
	var id_num = "1" if palette == "green" and seed_val == 111 else ("2" if palette == "gold" else "3")
	root.name = "Tree-Willow-" + id_num + "-StaticBody"
	root.set_meta("is_tree", true)
	root.set_meta("is_willow", true)
	root.set_meta("tree_type", "weeping_willow")

	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "TreeMesh"
	mesh_inst.mesh = willow_mesh
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mesh_inst)
	mesh_inst.owner = root

	# Collision Shape for Trunk (Cylinder)
	var col_shape = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var cyl = CylinderShape3D.new()
	cyl.height = 2.6
	cyl.radius = 0.45
	col_shape.shape = cyl
	col_shape.position = Vector3(0, 1.3, 0)
	root.add_child(col_shape)
	col_shape.owner = root

	# Canopy Area3D for ball collision & leaves rustle
	var canopy_area = Area3D.new()
	canopy_area.name = "CanopyArea"
	canopy_area.collision_layer = 1
	canopy_area.collision_mask = 0
	canopy_area.set_meta("is_canopy", true)
	canopy_area.set_meta("is_willow", true)

	var canopy_shape = CollisionShape3D.new()
	canopy_shape.name = "CollisionShape3D"
	var sphere = SphereShape3D.new()
	sphere.radius = max_radius * 1.05
	canopy_shape.shape = sphere

	canopy_area.add_child(canopy_shape)
	canopy_shape.owner = canopy_area
	canopy_area.position = Vector3(0, 4.0, 0)

	root.add_child(canopy_area)
	canopy_area.owner = root
	canopy_shape.owner = root

	# Save packed scene
	var packed = PackedScene.new()
	var err = packed.pack(root)
	if err == OK:
		ResourceSaver.save(packed, out_path)
		print("Successfully saved full-domed Weeping Willow scene: ", out_path)
	else:
		push_error("Failed to pack willow scene: " + out_path)


func _build_tube_branch(st: SurfaceTool, nodes: Array, sides: int, rng: RandomNumberGenerator):
	if nodes.size() < 2:
		return

	var rings: Array[Array] = []
	for i in range(nodes.size()):
		var n = nodes[i]
		var pos: Vector3 = n["pos"]
		var r: float = n["r"]

		var fwd: Vector3
		if i == 0:
			fwd = (nodes[1]["pos"] - pos).normalized()
		elif i == nodes.size() - 1:
			fwd = (pos - nodes[i - 1]["pos"]).normalized()
		else:
			fwd = (nodes[i + 1]["pos"] - nodes[i - 1]["pos"]).normalized()

		var up = Vector3.UP
		if abs(fwd.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var right = fwd.cross(up).normalized()
		up = right.cross(fwd).normalized()

		var ring_verts: Array = []
		for s in range(sides):
			var theta = float(s) / float(sides) * TAU
			var offset = (right * cos(theta) + up * sin(theta)) * r
			var v = pos + offset
			var uv = Vector2(float(s) / float(sides), float(i) * 0.75)
			ring_verts.append({"v": v, "uv": uv})
		rings.append(ring_verts)

	for r_idx in range(rings.size() - 1):
		var r0 = rings[r_idx]
		var r1 = rings[r_idx + 1]
		for s in range(sides):
			var s_next = (s + 1) % sides
			var p0 = r0[s]
			var p1 = r0[s_next]
			var p2 = r1[s_next]
			var p3 = r1[s]

			st.set_uv(p0["uv"])
			st.add_vertex(p0["v"])
			st.set_uv(p1["uv"])
			st.add_vertex(p1["v"])
			st.set_uv(p2["uv"])
			st.add_vertex(p2["v"])

			st.set_uv(p0["uv"])
			st.add_vertex(p0["v"])
			st.set_uv(p2["uv"])
			st.add_vertex(p2["v"])
			st.set_uv(p3["uv"])
			st.add_vertex(p3["v"])


func _add_oriented_quad(st: SurfaceTool, center: Vector3, width: float, height: float, rot_y: float, tilt_forward: float, canopy_center: Vector3, rng: RandomNumberGenerator):
	# A foliage quad that can tilt along the dome curvature (tilt_forward > 0 tilts forward/outward)
	var half_w = width * 0.5
	var half_h = height * 0.5

	var right = Vector3(cos(rot_y), 0, sin(rot_y)).normalized()
	var forward = Vector3(-sin(rot_y), 0, cos(rot_y)).normalized()
	# Up vector rotated around right axis by tilt_forward
	var up = (Vector3.UP * cos(tilt_forward) + forward * sin(tilt_forward)).normalized()

	var v_tl = center - right * half_w + up * half_h
	var v_tr = center + right * half_w + up * half_h
	var v_br = center + right * half_w - up * half_h
	var v_bl = center - right * half_w - up * half_h

	# Spherical smoothed normals pointing away from canopy_center
	var n_tl = (v_tl - canopy_center).normalized()
	var n_tr = (v_tr - canopy_center).normalized()
	var n_br = (v_br - canopy_center).normalized()
	var n_bl = (v_bl - canopy_center).normalized()

	# Triangle 1
	st.set_normal(n_tl)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v_tl)

	st.set_normal(n_tr)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(v_tr)

	st.set_normal(n_br)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(v_br)

	# Triangle 2
	st.set_normal(n_tl)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v_tl)

	st.set_normal(n_br)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(v_br)

	st.set_normal(n_bl)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(v_bl)


func _add_hanging_curtain_quad(st: SurfaceTool, top_center: Vector3, width: float, height: float, rot_y: float, canopy_center: Vector3, rng: RandomNumberGenerator):
	# A vertical weeping curtain card hanging straight down with slight outward gravity sway
	var half_w = width * 0.5
	var right = Vector3(cos(rot_y), 0, sin(rot_y)).normalized()

	var outward = Vector3(top_center.x, 0, top_center.z).normalized()
	var tilt_amount = rng.randf_range(0.20, 0.45)
	var bottom_center = Vector3(top_center.x + outward.x * tilt_amount, top_center.y - height, top_center.z + outward.z * tilt_amount)

	var v_tl = top_center - right * half_w
	var v_tr = top_center + right * half_w
	var v_bl = bottom_center - right * half_w
	var v_br = bottom_center + right * half_w

	var n_tl = (v_tl - canopy_center).normalized()
	var n_tr = (v_tr - canopy_center).normalized()
	var n_br = (v_br - canopy_center).normalized()
	var n_bl = (v_bl - canopy_center).normalized()

	# Triangle 1
	st.set_normal(n_tl)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v_tl)

	st.set_normal(n_tr)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(v_tr)

	st.set_normal(n_br)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(v_br)

	# Triangle 2
	st.set_normal(n_tl)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v_tl)

	st.set_normal(n_br)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(v_br)

	st.set_normal(n_bl)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(v_bl)
