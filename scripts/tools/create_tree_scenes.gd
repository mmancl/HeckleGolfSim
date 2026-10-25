@tool
extends SceneTree

## Enhances the authentic Shapespark 3D tree meshes and StaticBody3D scenes:
## 1. Surface 0 (Trunk & Boughs): Welds split face vertices, computes smooth radial normals,
##    adds a natural root flare, and applies Curved Phong Tessellation (3x3 subdivision per triangle)
##    so trunks and branches are smooth, round 3D cylinders while preserving their exact realistic proportions.
## 2. Surface 1 & Surface 2 (3D Curved Branch Layers): Preserves all authentic 9-vertex arched branch
##    components and adds multi-layered rotated & core-filling 3D branch passes with smooth hemispherical
##    canopy normals for dense, lush parkland golf course foliage.

const MATERIALS_DIR = "res://addons/shapespark-low-poly-exterior-plants/materials/"
const BODIES_DIR = "res://addons/shapespark-low-poly-exterior-plants/bodies/"
const MESHES_DIR = "res://addons/shapespark-low-poly-exterior-plants/meshes/"
const TEXTURES_DIR = "res://addons/shapespark-low-poly-exterior-plants/textures/"


func _init():
	print("[create_tree_scenes] Enhancing authentic 3D tree materials, meshes, and staticbody scenes...")
	_create_materials()
	_enhance_all_base_tree_meshes_and_bodies()
	_create_variant_tree_bodies()
	print("[create_tree_scenes] All realistic tree meshes and scenes built successfully!")
	quit(0)


func _create_mat_branch(tex_path: String) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.42
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.78
	mat.metallic_specular = 0.16
	mat.albedo_texture = load(tex_path)
	return mat


func _create_mat_bark(tex_path: String) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.roughness = 0.94
	mat.metallic_specular = 0.05
	mat.albedo_texture = load(tex_path)
	return mat


func _create_materials():
	ResourceSaver.save(_create_mat_bark(TEXTURES_DIR + "bark.jpg"), MATERIALS_DIR + "bark-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "branch-01.png"), MATERIALS_DIR + "branch-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "branch-02.png"), MATERIALS_DIR + "branch-02-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "branch-1-01.png"), MATERIALS_DIR + "branch-1-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "branch-1-02.png"), MATERIALS_DIR + "branch-1-02-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "branch-2-01.png"), MATERIALS_DIR + "branch-2-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "branch-2-02.png"), MATERIALS_DIR + "branch-2-02-material.tres")

	# Willow
	ResourceSaver.save(_create_mat_bark(TEXTURES_DIR + "willow-bark.jpg"), MATERIALS_DIR + "willow-bark-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "willow-branch-01.png"), MATERIALS_DIR + "willow-branch-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "willow-branch-02.png"), MATERIALS_DIR + "willow-branch-02-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "willow-branch-1-01.png"), MATERIALS_DIR + "willow-branch-1-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "willow-branch-1-02.png"), MATERIALS_DIR + "willow-branch-1-02-material.tres")

	# Birch
	ResourceSaver.save(_create_mat_bark(TEXTURES_DIR + "birch-bark.jpg"), MATERIALS_DIR + "birch-bark-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "birch-branch-01.png"), MATERIALS_DIR + "birch-branch-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "birch-branch-02.png"), MATERIALS_DIR + "birch-branch-02-material.tres")

	# Autumn Gold
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "autumn-gold-branch-01.png"), MATERIALS_DIR + "autumn-gold-branch-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "autumn-gold-branch-02.png"), MATERIALS_DIR + "autumn-gold-branch-02-material.tres")

	# Autumn Red
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "autumn-red-branch-01.png"), MATERIALS_DIR + "autumn-red-branch-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "autumn-red-branch-02.png"), MATERIALS_DIR + "autumn-red-branch-02-material.tres")

	# Pine
	ResourceSaver.save(_create_mat_bark(TEXTURES_DIR + "pine-bark.jpg"), MATERIALS_DIR + "pine-bark-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "pine-branch-01.png"), MATERIALS_DIR + "pine-branch-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "pine-branch-02.png"), MATERIALS_DIR + "pine-branch-02-material.tres")

	# Blossom
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "blossom-branch-01.png"), MATERIALS_DIR + "blossom-branch-01-material.tres")
	ResourceSaver.save(_create_mat_branch(TEXTURES_DIR + "blossom-branch-02.png"), MATERIALS_DIR + "blossom-branch-02-material.tres")

	print("[create_tree_scenes] Materials saved.")


func _enhance_all_base_tree_meshes_and_bodies():
	var bark_mat = load(MATERIALS_DIR + "bark-material.tres") as Material
	var b01_mat = load(MATERIALS_DIR + "branch-01-material.tres") as Material
	var b02_mat = load(MATERIALS_DIR + "branch-02-material.tres") as Material
	var b1_01_mat = load(MATERIALS_DIR + "branch-1-01-material.tres") as Material
	var b1_02_mat = load(MATERIALS_DIR + "branch-1-02-material.tres") as Material
	var b2_01_mat = load(MATERIALS_DIR + "branch-2-01-material.tres") as Material
	var b2_02_mat = load(MATERIALS_DIR + "branch-2-02-material.tres") as Material

	var family_configs = [
		{"prefix": "01", "b1": b01_mat, "b2": b02_mat, "canopy_y": 3.4, "canopy_r": 2.3, "trunk_r": 0.16, "trunk_h": 2.4},
		{"prefix": "02", "b1": b1_01_mat, "b2": b1_02_mat, "canopy_y": 3.5, "canopy_r": 2.2, "trunk_r": 0.16, "trunk_h": 2.5},
		{"prefix": "03", "b1": b2_01_mat, "b2": b2_02_mat, "canopy_y": 3.3, "canopy_r": 2.1, "trunk_r": 0.15, "trunk_h": 2.6},
	]

	for fam in family_configs:
		var prefix: String = fam["prefix"]
		for variant_idx in range(1, 5):
			var id_str = str(variant_idx)
			var mesh_scene_path = MESHES_DIR + "tree-%s-%s-mesh.tscn" % [prefix, id_str]
			var body_scene_path = BODIES_DIR + "tree-%s-%s-staticbody.tscn" % [prefix, id_str]

			var ps = load(mesh_scene_path) as PackedScene
			if ps == null:
				push_error("Missing base mesh scene: " + mesh_scene_path)
				continue
			var inst = ps.instantiate() as MeshInstance3D
			var orig_mesh = inst.mesh as ArrayMesh
			inst.free()

			var enhanced_mesh = _build_enhanced_photographic_tree_mesh(
				orig_mesh,
				bark_mat,
				fam["b1"],
				fam["b2"],
				"tree-%s-%s_v4_photo" % [prefix, id_str]
			)

			_save_mesh_scene("Tree-%s-%s" % [prefix, id_str], enhanced_mesh, mesh_scene_path)
			_save_standard_body_scene(
				"Tree-%s-%s-StaticBody" % [prefix, id_str],
				"Tree-%s-%s" % [prefix, id_str],
				mesh_scene_path,
				body_scene_path,
				Vector3(0.0, fam["canopy_y"], 0.0),
				fam["canopy_r"],
				fam["trunk_r"],
				fam["trunk_h"]
			)


func _build_enhanced_photographic_tree_mesh(
	orig_mesh: ArrayMesh,
	bark_mat: Material,
	branch1_mat: Material,
	branch2_mat: Material,
	res_name: String
) -> ArrayMesh:
	var new_mesh = ArrayMesh.new()
	new_mesh.resource_name = res_name

	if orig_mesh.get_surface_count() >= 1:
		_add_smoothed_subdivided_trunk_surface(new_mesh, orig_mesh.surface_get_arrays(0), bark_mat)
		new_mesh.surface_set_name(0, "Trunk")
	if orig_mesh.get_surface_count() >= 2:
		_add_densified_branch_surface(new_mesh, orig_mesh.surface_get_arrays(1), branch1_mat, 0.0)
		new_mesh.surface_set_name(1, "Branch-1")
	if orig_mesh.get_surface_count() >= 3:
		_add_densified_branch_surface(new_mesh, orig_mesh.surface_get_arrays(2), branch2_mat, 0.55)
		new_mesh.surface_set_name(2, "Branch-2")

	return new_mesh


## Welds split vertices on Surface 0 (Trunk), computes smooth outward cylindrical normals,
## adds a subtle ground root flare, and applies Curved Phong Tessellation (3x3 triangles per face)
## so the trunk and limbs are smooth cylinders while retaining exact Shapespark proportions.
func _add_smoothed_subdivided_trunk_surface(target_mesh: ArrayMesh, arrays: Array, mat: Material):
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var n_verts = verts.size()
	if n_verts == 0 or indices.size() == 0:
		return

	# 1. Apply subtle organic ground root flare near base (y < 0.45m)
	var flared_verts = PackedVector3Array()
	flared_verts.resize(n_verts)
	for i in range(n_verts):
		var v = verts[i]
		if v.y < 0.45:
			var t = clampf(1.0 - (v.y / 0.45), 0.0, 1.0)
			var ang = atan2(v.z, v.x)
			var flute = 1.0 + 0.07 * cos(ang * 5.0)
			var flare = 1.0 + (0.28 * t * t * flute)
			v = Vector3(v.x * flare, maxf(0.0, v.y), v.z * flare)
		flared_verts[i] = v

	# 2. Weld coincident vertices (distance < 0.004m) to accumulate smooth area-weighted normals
	var weld_rep = PackedInt32Array()
	weld_rep.resize(n_verts)
	var unique_pos: Array[Vector3] = []
	for i in range(n_verts):
		var v = flared_verts[i]
		var found = -1
		for u_idx in range(unique_pos.size()):
			if unique_pos[u_idx].distance_squared_to(v) < 0.000016:
				found = u_idx
				break
		if found == -1:
			found = unique_pos.size()
			unique_pos.append(v)
		weld_rep[i] = found

	var smooth_unique_normals: Array[Vector3] = []
	smooth_unique_normals.resize(unique_pos.size())
	for u_idx in range(unique_pos.size()):
		smooth_unique_normals[u_idx] = Vector3.ZERO

	var n_tris = indices.size() / 3
	for t_idx in range(n_tris):
		var i0 = indices[t_idx * 3 + 0]
		var i1 = indices[t_idx * 3 + 1]
		var i2 = indices[t_idx * 3 + 2]
		var v0 = flared_verts[i0]
		var v1 = flared_verts[i1]
		var v2 = flared_verts[i2]
		# Godot clockwise / counter-clockwise outward cross product
		var fn = (v2 - v0).cross(v1 - v0)
		smooth_unique_normals[weld_rep[i0]] += fn
		smooth_unique_normals[weld_rep[i1]] += fn
		smooth_unique_normals[weld_rep[i2]] += fn

	for u_idx in range(unique_pos.size()):
		var n = smooth_unique_normals[u_idx]
		if n.length_squared() > 0.000001:
			n = n.normalized()
		else:
			var upos = unique_pos[u_idx]
			n = Vector3(upos.x, 0.0, upos.z).normalized()
		# For lower trunk (y < 1.8m), blend slightly with pure radial outward vector for cylinder perfection
		var pos_u = unique_pos[u_idx]
		if pos_u.y < 1.8:
			var rad = Vector3(pos_u.x, 0.0, pos_u.z)
			if rad.length_squared() > 0.0001:
				var rad_n = rad.normalized()
				if n.dot(rad_n) < 0.0:
					n = -n
				n = n.lerp(rad_n, 0.35).normalized()
		smooth_unique_normals[u_idx] = n

	# 3. Curved Phong Tessellation (subdivide each triangle into 3x3 = 9 curved triangles)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var sub_steps = 3
	var phong_alpha = 0.62

	for t_idx in range(n_tris):
		var i0 = indices[t_idx * 3 + 0]
		var i1 = indices[t_idx * 3 + 1]
		var i2 = indices[t_idx * 3 + 2]

		var p0 = flared_verts[i0]
		var p1 = flared_verts[i1]
		var p2 = flared_verts[i2]

		var n0 = smooth_unique_normals[weld_rep[i0]]
		var n1 = smooth_unique_normals[weld_rep[i1]]
		var n2 = smooth_unique_normals[weld_rep[i2]]

		var uv0 = uvs[i0]
		var uv1 = uvs[i1]
		var uv2 = uvs[i2]

		# Precompute barycentric grid points for this triangle
		var row_v: Array = []
		var row_n: Array = []
		var row_uv: Array = []

		for r in range(sub_steps + 1):
			var v_list: Array[Vector3] = []
			var n_list: Array[Vector3] = []
			var uv_list: Array[Vector2] = []
			var max_c = sub_steps - r
			for c in range(max_c + 1):
				var w1 = float(r) / float(sub_steps)
				var w2 = float(c) / float(sub_steps)
				var w0 = maxf(0.0, 1.0 - w1 - w2)

				var p_lin = p0 * w0 + p1 * w1 + p2 * w2
				var uv_interp = uv0 * w0 + uv1 * w1 + uv2 * w2
				var n_interp = (n0 * w0 + n1 * w1 + n2 * w2).normalized()

				# Project onto tangent planes of the 3 corners (Phong tessellation)
				var proj0 = p_lin - n0 * ((p_lin - p0).dot(n0))
				var proj1 = p_lin - n1 * ((p_lin - p1).dot(n1))
				var proj2 = p_lin - n2 * ((p_lin - p2).dot(n2))
				var p_phong = proj0 * w0 + proj1 * w1 + proj2 * w2
				var p_final = p_lin.lerp(p_phong, phong_alpha)

				v_list.append(p_final)
				n_list.append(n_interp)
				uv_list.append(uv_interp)
			row_v.append(v_list)
			row_n.append(n_list)
			row_uv.append(uv_list)

		for r in range(sub_steps):
			var max_c = sub_steps - r
			for c in range(max_c):
				# Upright sub-triangle
				st.set_normal(row_n[r][c])
				st.set_uv(row_uv[r][c])
				st.add_vertex(row_v[r][c])

				st.set_normal(row_n[r][c + 1])
				st.set_uv(row_uv[r][c + 1])
				st.add_vertex(row_v[r][c + 1])

				st.set_normal(row_n[r + 1][c])
				st.set_uv(row_uv[r + 1][c])
				st.add_vertex(row_v[r + 1][c])

				# Inverted sub-triangle (if inside triangle bounds)
				if c + 1 < max_c:
					st.set_normal(row_n[r][c + 1])
					st.set_uv(row_uv[r][c + 1])
					st.add_vertex(row_v[r][c + 1])

					st.set_normal(row_n[r + 1][c + 1])
					st.set_uv(row_uv[r + 1][c + 1])
					st.add_vertex(row_v[r + 1][c + 1])

					st.set_normal(row_n[r + 1][c])
					st.set_uv(row_uv[r + 1][c])
					st.add_vertex(row_v[r + 1][c])

	st.generate_tangents()
	st.commit(target_mesh)


## Preserves all authentic 3D branch components in Surface 1 / Surface 2, applies 3D dome curvature
## to eliminate flat planes, generates secondary interlocking 3D cross-wings along the bough spine,
## applies spherical crown lighting normals, and adds a compact interior core fill for rich volumetric depth.
func _add_densified_branch_surface(
	target_mesh: ArrayMesh,
	arrays: Array,
	mat: Material,
	angle_offset_rad: float
):
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var n_verts = verts.size()
	if n_verts == 0 or indices.size() == 0:
		return

	# Compute canopy dome center for smooth spherical lighting normals
	var sum_v = Vector3.ZERO
	var min_y = 999.0
	var max_y = -999.0
	for v in verts:
		sum_v += v
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
	var canopy_center = sum_v / float(n_verts)
	canopy_center.y = lerpf(min_y, max_y, 0.44)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)

	var n_tris = indices.size() / 3
	var cards_count = n_tris / 8

	for c_idx in range(cards_count):
		var start_t = c_idx * 8
		var stem_pos = Vector3.ZERO
		var tip_pos = Vector3.ZERO
		var min_stem_d = 999.0
		var min_tip_d = 999.0

		for t in range(8):
			for k in range(3):
				var idx = indices[(start_t + t) * 3 + k]
				var uv = uvs[idx]
				var ds = uv.distance_to(Vector2(0.5, 0.0))
				var dt = uv.distance_to(Vector2(0.5, 1.0))
				if ds < min_stem_d:
					min_stem_d = ds
					stem_pos = verts[idx]
				if dt < min_tip_d:
					min_tip_d = dt
					tip_pos = verts[idx]

		var bough_dir = (tip_pos - stem_pos).normalized()
		if bough_dir.length_squared() < 0.01:
			bough_dir = Vector3.FORWARD
		var card_norm = Vector3.UP.cross(bough_dir).normalized()
		if card_norm.length_squared() < 0.01:
			card_norm = Vector3.RIGHT

		var wing_angle = deg_to_rad(48.0) if (c_idx % 2 == 0) else deg_to_rad(-48.0)
		var wing_basis = Basis(bough_dir, wing_angle)

		# 1. Primary 3D domed bough card
		for t in range(8):
			var tri_offset = (start_t + t) * 3
			for k in range(3):
				var idx = indices[tri_offset + k]
				var v = verts[idx]
				var uv = uvs[idx]

				var dome_factor = maxf(0.0, 1.0 - 4.0 * ((uv.x - 0.5) * (uv.x - 0.5) + (uv.y - 0.5) * (uv.y - 0.5)))
				var curved_v = v + card_norm * (dome_factor * 0.28)
				var sphere_n = (curved_v - canopy_center).normalized()

				st.set_normal(sphere_n)
				st.set_uv(uv)
				st.add_vertex(curved_v)

		# 2. Secondary interlocking 3D cross-wing along bough spine
		for t in range(8):
			var tri_offset = (start_t + t) * 3
			for k in range(3):
				var idx = indices[tri_offset + k]
				var v = verts[idx]
				var uv = uvs[idx]

				var rel = v - stem_pos
				var spine_comp = bough_dir * rel.dot(bough_dir)
				var lateral_comp = (rel - spine_comp) * 0.76
				var scaled_rel = spine_comp + lateral_comp
				var rotated_rel = wing_basis * scaled_rel
				var wing_v = stem_pos + rotated_rel

				var sphere_n = (wing_v - canopy_center).normalized()
				st.set_normal(sphere_n)
				st.set_uv(uv)
				st.add_vertex(wing_v)

	# 3. Compact interior core fill (eliminates hollow see-through holes in canopy center)
	var core_passes = [
		{"ang": deg_to_rad(65.0) + angle_offset_rad, "scale_xz": 0.46, "scale_y": 0.65, "dy": 0.10},
		{"ang": deg_to_rad(195.0) + angle_offset_rad, "scale_xz": 0.42, "scale_y": 0.62, "dy": -0.10},
	]

	for cp in core_passes:
		var ang: float = cp["ang"]
		var ca = cos(ang)
		var sa = sin(ang)
		var sxz: float = cp["scale_xz"]
		var sy: float = cp["scale_y"]
		var dy: float = cp["dy"]

		for t_idx in range(n_tris):
			var i0 = indices[t_idx * 3 + 0]
			var i1 = indices[t_idx * 3 + 1]
			var i2 = indices[t_idx * 3 + 2]
			var v0 = verts[i0]
			var v1 = verts[i1]
			var v2 = verts[i2]
			var avg_y = (v0.y + v1.y + v2.y) / 3.0
			if avg_y < 2.4 or avg_y > 5.5:
				continue

			for idx in [i0, i1, i2]:
				var v = verts[idx]
				var rx = (v.x * ca - v.z * sa) * sxz
				var rz = (v.x * sa + v.z * ca) * sxz
				var ry = canopy_center.y + (v.y - canopy_center.y) * sy + dy
				var new_v = Vector3(rx, ry, rz)

				var sphere_n = (new_v - canopy_center).normalized()
				st.set_normal(sphere_n)
				st.set_uv(uvs[idx])
				st.add_vertex(new_v)

	st.generate_tangents()
	st.commit(target_mesh)


func _create_variant_tree_bodies():
	# Willow 1, 2, 3 (broad, overarching lush waterside willow crowns with photographic willow foliage)
	_build_variant_body(
		"Tree-Willow-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-4-mesh.tscn",
		MATERIALS_DIR + "willow-bark-material.tres",
		MATERIALS_DIR + "willow-branch-01-material.tres",
		MATERIALS_DIR + "willow-branch-02-material.tres",
		BODIES_DIR + "tree-willow-1-staticbody.tscn",
		Vector3(1.16, 0.95, 1.16),
		Vector3(0, 3.4, 0),
		2.5,
		"willow"
	)
	_build_variant_body(
		"Tree-Willow-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-1-mesh.tscn",
		MATERIALS_DIR + "willow-bark-material.tres",
		MATERIALS_DIR + "willow-branch-1-01-material.tres",
		MATERIALS_DIR + "willow-branch-1-02-material.tres",
		BODIES_DIR + "tree-willow-2-staticbody.tscn",
		Vector3(1.14, 0.94, 1.14),
		Vector3(0, 3.4, 0),
		2.5,
		"willow"
	)
	_build_variant_body(
		"Tree-Willow-3-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-3-mesh.tscn",
		MATERIALS_DIR + "willow-bark-material.tres",
		MATERIALS_DIR + "willow-branch-01-material.tres",
		MATERIALS_DIR + "willow-branch-02-material.tres",
		BODIES_DIR + "tree-willow-3-staticbody.tscn",
		Vector3(1.18, 0.96, 1.18),
		Vector3(0, 3.4, 0),
		2.55,
		"willow"
	)

	# Birch 1 & 2
	_build_variant_body(
		"Tree-Birch-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-02-2-mesh.tscn",
		MATERIALS_DIR + "birch-bark-material.tres",
		MATERIALS_DIR + "birch-branch-01-material.tres",
		MATERIALS_DIR + "birch-branch-02-material.tres",
		BODIES_DIR + "tree-birch-1-staticbody.tscn",
		Vector3(0.94, 1.12, 0.94),
		Vector3(0, 3.8, 0),
		2.2,
		"birch"
	)
	_build_variant_body(
		"Tree-Birch-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-02-4-mesh.tscn",
		MATERIALS_DIR + "birch-bark-material.tres",
		MATERIALS_DIR + "birch-branch-01-material.tres",
		MATERIALS_DIR + "birch-branch-02-material.tres",
		BODIES_DIR + "tree-birch-2-staticbody.tscn",
		Vector3(0.92, 1.15, 0.92),
		Vector3(0, 3.9, 0),
		2.2,
		"birch"
	)

	# Autumn Golden Oak 1 & 2
	_build_variant_body(
		"Tree-Autumn-Gold-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-1-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-01-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-gold-1-staticbody.tscn",
		Vector3(1.0, 1.0, 1.0),
		Vector3(0, 3.5, 0),
		2.3,
		"autumn_gold"
	)
	_build_variant_body(
		"Tree-Autumn-Gold-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-2-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-01-material.tres",
		MATERIALS_DIR + "autumn-gold-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-gold-2-staticbody.tscn",
		Vector3(1.04, 1.02, 1.04),
		Vector3(0, 3.5, 0),
		2.35,
		"autumn_gold"
	)

	# Autumn Crimson Maple 1 & 2
	_build_variant_body(
		"Tree-Autumn-Red-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-02-1-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-red-branch-01-material.tres",
		MATERIALS_DIR + "autumn-red-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-red-1-staticbody.tscn",
		Vector3(1.02, 1.0, 1.02),
		Vector3(0, 3.5, 0),
		2.25,
		"autumn_red"
	)
	_build_variant_body(
		"Tree-Autumn-Red-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-02-3-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "autumn-red-branch-01-material.tres",
		MATERIALS_DIR + "autumn-red-branch-02-material.tres",
		BODIES_DIR + "tree-autumn-red-2-staticbody.tscn",
		Vector3(1.0, 1.0, 1.0),
		Vector3(0, 3.5, 0),
		2.25,
		"autumn_red"
	)

	# Evergreen Pine 1 & 2
	_build_variant_body(
		"Tree-Pine-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-03-1-mesh.tscn",
		MATERIALS_DIR + "pine-bark-material.tres",
		MATERIALS_DIR + "pine-branch-01-material.tres",
		MATERIALS_DIR + "pine-branch-02-material.tres",
		BODIES_DIR + "tree-pine-1-staticbody.tscn",
		Vector3(0.95, 1.12, 0.95),
		Vector3(0, 3.6, 0),
		2.1,
		"pine"
	)
	_build_variant_body(
		"Tree-Pine-2-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-03-3-mesh.tscn",
		MATERIALS_DIR + "pine-bark-material.tres",
		MATERIALS_DIR + "pine-branch-01-material.tres",
		MATERIALS_DIR + "pine-branch-02-material.tres",
		BODIES_DIR + "tree-pine-2-staticbody.tscn",
		Vector3(0.92, 1.15, 0.92),
		Vector3(0, 3.7, 0),
		2.1,
		"pine"
	)

	# Flowering Blossom
	_build_variant_body(
		"Tree-Blossom-1-StaticBody",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/tree-01-3-mesh.tscn",
		MATERIALS_DIR + "bark-material.tres",
		MATERIALS_DIR + "blossom-branch-01-material.tres",
		MATERIALS_DIR + "blossom-branch-02-material.tres",
		BODIES_DIR + "tree-blossom-1-staticbody.tscn",
		Vector3(1.05, 0.98, 1.05),
		Vector3(0, 3.5, 0),
		2.35,
		"blossom"
	)


func _save_mesh_scene(node_name: String, mesh: ArrayMesh, out_path: String):
	var mi = MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh

	var packed = PackedScene.new()
	var err = packed.pack(mi)
	mi.free()
	if err == OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_path))
		packed.take_over_path(out_path)
		ResourceSaver.save(packed, out_path)
		print("Saved enhanced mesh scene: ", out_path)
	else:
		push_error("Failed to pack mesh scene: " + out_path)


func _save_standard_body_scene(
	body_name: String,
	mesh_node_name: String,
	mesh_scene_path: String,
	out_path: String,
	canopy_pos: Vector3,
	canopy_radius: float,
	trunk_radius: float = 0.16,
	trunk_height: float = 2.5
):
	var root = StaticBody3D.new()
	root.name = body_name
	root.set_meta("is_tree", true)

	var mesh_scene = load(mesh_scene_path) as PackedScene
	var mesh_inst = mesh_scene.instantiate() as MeshInstance3D
	mesh_inst.name = mesh_node_name
	root.add_child(mesh_inst)
	mesh_inst.owner = root

	var col_shape = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var cyl = CylinderShape3D.new()
	cyl.height = trunk_height
	cyl.radius = trunk_radius
	col_shape.shape = cyl
	col_shape.position = Vector3(0.0, trunk_height * 0.5, 0.0)
	root.add_child(col_shape)
	col_shape.owner = root

	var canopy_area = Area3D.new()
	canopy_area.name = "CanopyArea"
	canopy_area.collision_layer = 1
	canopy_area.collision_mask = 0
	canopy_area.set_meta("is_canopy", true)
	canopy_area.position = canopy_pos

	var canopy_shape = CollisionShape3D.new()
	canopy_shape.name = "CollisionShape3D"
	var sphere = SphereShape3D.new()
	sphere.radius = canopy_radius
	canopy_shape.shape = sphere
	canopy_area.add_child(canopy_shape)

	root.add_child(canopy_area)
	canopy_area.owner = root
	canopy_shape.owner = root

	var packed = PackedScene.new()
	var err = packed.pack(root)
	root.free()
	if err == OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_path))
		packed.take_over_path(out_path)
		ResourceSaver.save(packed, out_path)
		print("Saved standard tree body: ", out_path)
	else:
		push_error("Failed to pack standard tree body: " + out_path)


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
	tree_type_tag: String = ""
):
	var root = StaticBody3D.new()
	root.name = body_name
	root.set_meta("is_tree", true)
	if tree_type_tag != "":
		root.set_meta("tree_type", tree_type_tag)

	var mesh_scene = load(mesh_scene_path) as PackedScene
	var mesh_inst = mesh_scene.instantiate() as MeshInstance3D
	mesh_inst.name = "TreeMesh"
	mesh_inst.scale = mesh_scale

	var bark_mat = load(bark_mat_path) as Material
	var b1_mat = load(branch1_mat_path) as Material
	var b2_mat = load(branch2_mat_path) as Material

	if mesh_inst.mesh != null:
		var dup_mesh = mesh_inst.mesh.duplicate() as ArrayMesh
		dup_mesh.resource_name = mesh_inst.mesh.resource_name + "_" + tree_type_tag + "_v4_photo"
		if dup_mesh.get_surface_count() >= 3:
			dup_mesh.surface_set_material(0, bark_mat)
			dup_mesh.surface_set_material(1, b1_mat)
			dup_mesh.surface_set_material(2, b2_mat)
		mesh_inst.mesh = dup_mesh

	mesh_inst.set_surface_override_material(0, bark_mat)
	mesh_inst.set_surface_override_material(1, b1_mat)
	mesh_inst.set_surface_override_material(2, b2_mat)

	root.add_child(mesh_inst)
	mesh_inst.owner = root

	var base_trunk_r := 0.16
	var base_trunk_h := 2.5

	var col_shape = CollisionShape3D.new()
	col_shape.name = "CollisionShape3D"
	var cyl = CylinderShape3D.new()
	cyl.height = snappedf(base_trunk_h * mesh_scale.y, 0.01)
	cyl.radius = snappedf(base_trunk_r * max(mesh_scale.x, mesh_scale.z), 0.01)
	col_shape.shape = cyl
	col_shape.position = Vector3(0.0, cyl.height * 0.5, 0.0)
	root.add_child(col_shape)
	col_shape.owner = root

	var canopy_area = Area3D.new()
	canopy_area.name = "CanopyArea"
	canopy_area.collision_layer = 1
	canopy_area.collision_mask = 0
	canopy_area.set_meta("is_canopy", true)
	canopy_area.position = canopy_pos

	var canopy_shape = CollisionShape3D.new()
	canopy_shape.name = "CollisionShape3D"
	var sphere = SphereShape3D.new()
	sphere.radius = canopy_radius
	canopy_shape.shape = sphere
	canopy_area.add_child(canopy_shape)

	root.add_child(canopy_area)
	canopy_area.owner = root
	canopy_shape.owner = root

	var packed = PackedScene.new()
	var err = packed.pack(root)
	root.free()
	if err == OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(out_path))
		packed.take_over_path(out_path)
		ResourceSaver.save(packed, out_path)
		print("Saved variant tree body: ", out_path)
	else:
		push_error("Failed to pack variant tree body: " + out_path)
