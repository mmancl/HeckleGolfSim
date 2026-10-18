extends RefCounted
class_name CourseDetailEnhancer

## CourseDetailEnhancer
## Builds high-resolution 3D course detail features for both newly generated courses,
## in-place upgraded courses (CourseGraphicsUpgrader), and HighFidelityBuilder:
## 1. Recessed 3D Bunker Lip & Sand Bowl Meshes (`HighFidelityBunkers`)
## 2. Overhanging 3D Bunker-Lip Fescue Grass (`BunkerLipGrassMultiMesh`)
## 3. Pond Shoreline Reeds (`ShorelineReedsMultiMesh`)
## 4. Outer Rolling Terrain Horizon Skirt (`HorizonSkirt`)

const ProceduralTreeGeneratorScript = preload("res://HighFidelity/Foliage/procedural_tree_generator.gd")
const HighFidelityGrassScript = preload("res://HighFidelity/Foliage/high_fidelity_grass.gd")


static func enhance_course_scene(scene_root: Node, persist_for_save: bool = false) -> Dictionary:
	var result := {
		"bunkers_built": 0,
		"shoreline_reeds": 0,
		"horizon_skirt": false
	}
	if scene_root == null or MobilePerformance.is_driving_range_node(scene_root):
		return result

	_strip_legacy_grass_nodes(scene_root)
	var height_map := _build_terrain_height_lookup(scene_root)
	result["bunkers_built"] = _build_recessed_3d_bunkers(scene_root, height_map, persist_for_save)
	result["shoreline_reeds"] = _build_shoreline_reeds(scene_root, height_map, persist_for_save)
	result["horizon_skirt"] = _build_horizon_skirt(scene_root, height_map, persist_for_save)
	result["cart_paths"] = _build_cart_paths(scene_root, height_map, persist_for_save)
	_upgrade_water_materials(scene_root)
	return result


static func _strip_legacy_grass_nodes(scene_root: Node) -> void:
	var to_remove: Array[Node] = []
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			var cn := String(c.name)
			if cn == "BunkerLipGrassMultiMesh" or cn == "ShorelineReedsMultiMesh" \
					or cn == "HighFidelityBunkers" \
					or cn.begins_with("BushChunk_") or cn.begins_with("Bush_"):
				to_remove.append(c)
			else:
				stack.append(c)
	for r in to_remove:
		r.get_parent().remove_child(r)
		if r.is_inside_tree():
			r.queue_free()
		else:
			r.free()


static func _build_terrain_height_lookup(scene_root: Node) -> Dictionary:
	var info := {
		"min_x": -300.0,
		"max_x": 300.0,
		"min_z": -300.0,
		"max_z": 300.0,
		"avg_edge_y": 0.0,
		"grid": {}
	}
	var terrain := scene_root.find_child("UnifiedTerrain", true, false) as MeshInstance3D
	if terrain == null or terrain.mesh == null or terrain.mesh.get_surface_count() == 0:
		return info

	var aabb := terrain.mesh.get_aabb()
	info["min_x"] = aabb.position.x
	info["max_x"] = aabb.position.x + aabb.size.x
	info["min_z"] = aabb.position.z
	info["max_z"] = aabb.position.z + aabb.size.z

	var arrays := terrain.mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return info
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var grid: Dictionary = {}
	var edge_sum := 0.0
	var edge_cnt := 0
	var cell := 4.0

	for v in verts:
		var gx := int(round(v.x / cell))
		var gz := int(round(v.z / cell))
		grid[Vector2i(gx, gz)] = v.y
		if absf(v.x - info["min_x"]) < 8.0 or absf(v.x - info["max_x"]) < 8.0 or absf(v.z - info["min_z"]) < 8.0 or absf(v.z - info["max_z"]) < 8.0:
			edge_sum += v.y
			edge_cnt += 1

	if edge_cnt > 0:
		info["avg_edge_y"] = edge_sum / float(edge_cnt)
	info["grid"] = grid
	return info


static func _sample_height(wx: float, wz: float, info: Dictionary, fallback_y: float = 0.0) -> float:
	var grid: Dictionary = info.get("grid", {})
	if grid.is_empty():
		return fallback_y
	var cell := 4.0
	var fx := wx / cell
	var fz := wz / cell
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)

	var k00 := Vector2i(ix, iz)
	var h00: float = grid.get(k00, NAN)
	if is_nan(h00):
		for r in range(1, 4):
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					var k := Vector2i(ix + dx, iz + dz)
					if grid.has(k):
						return float(grid[k])
		return fallback_y

	var h10: float = grid.get(Vector2i(ix + 1, iz), h00)
	var h01: float = grid.get(Vector2i(ix, iz + 1), h00)
	var h11: float = grid.get(Vector2i(ix + 1, iz + 1), h00)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


static func _build_recessed_3d_bunkers(scene_root: Node, height_info: Dictionary, persist_for_save: bool) -> int:
	if scene_root.get_node_or_null("HighFidelityBunkers") != null:
		return 0

	var polygons: Array[PackedVector2Array] = []
	var base_heights: Array[float] = []

	for child in scene_root.find_children("*", "CollisionObject3D", true, false):
		var cname := child.name.to_lower()
		var is_bunker: bool = (cname.begins_with("bunker") or cname.contains("bunker") or bool(child.get_meta("is_sand", false)) or int(child.get_meta("surface_type", -1)) == 5) and not bool(child.get_meta("is_water", false)) and not cname.contains("terrain") and not cname.contains("rough")
		if is_bunker:
			for sub in child.get_children():
				if sub is CollisionPolygon3D and (sub as CollisionPolygon3D).polygon.size() >= 3:
					var cp := sub as CollisionPolygon3D
					var world_poly := PackedVector2Array()
					for pt in cp.polygon:
						var wp := (child as Node3D).transform * (cp.transform * Vector3(pt.x, 0.0, pt.y))
						world_poly.append(Vector2(wp.x, wp.z))
					polygons.append(world_poly)
					base_heights.append((child as Node3D).position.y)
				elif sub is CollisionShape3D and (sub as CollisionShape3D).shape != null:
					var cs := sub as CollisionShape3D
					var world_pts := PackedVector2Array()
					if cs.shape is ConcavePolygonShape3D:
						var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
						for f in faces:
							var wp := (child as Node3D).transform * (cs.transform * f)
							world_pts.append(Vector2(wp.x, wp.z))
					elif cs.shape is ConvexPolygonShape3D:
						var points := (cs.shape as ConvexPolygonShape3D).points
						for p in points:
							var wp := (child as Node3D).transform * (cs.transform * p)
							world_pts.append(Vector2(wp.x, wp.z))
					if world_pts.size() >= 3:
						var hull := Geometry2D.convex_hull(world_pts)
						if hull.size() > 3 and hull[hull.size() - 1].is_equal_approx(hull[0]):
							hull.remove_at(hull.size() - 1)
						if hull.size() >= 3:
							polygons.append(hull)
							base_heights.append((child as Node3D).position.y)

	if polygons.is_empty():
		return 0

	var container := Node3D.new()
	container.name = "HighFidelityBunkers"
	scene_root.add_child(container)
	if persist_for_save:
		container.owner = scene_root

	var bunker_mat := _create_bunker_high_material()
	var built := 0
	for idx in range(polygons.size()):
		var poly := _subdivide_and_orient_ccw(polygons[idx], 0.95)
		if poly.size() < 4:
			continue

		var mesh := _create_single_bunker_lip_and_bowl_mesh(poly, height_info, base_heights[idx])
		if mesh == null:
			continue
		mesh.surface_set_material(0, bunker_mat)

		var mi := MeshInstance3D.new()
		mi.name = "RecessedBunker_%d" % idx
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 420.0
		mi.visibility_range_end_margin = 30.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		container.add_child(mi)
		if persist_for_save:
			mi.owner = scene_root
		built += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BunkerLipGrassMultiMesh"
	# Sand traps should be clean hazards without grass shoots or weeds
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.instance_count = 0
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(mmi)
	if persist_for_save:
		mmi.owner = scene_root

	return built


static func _subdivide_and_orient_ccw(poly: PackedVector2Array, max_seg_len: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	# Compute signed area in XZ
	var area := 0.0
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += (a.x * b.y - b.x * a.y)
	var ordered := poly.duplicate()
	if area < 0.0:
		ordered.reverse()

	var subdiv := PackedVector2Array()
	for i in range(ordered.size()):
		var p0 := ordered[i]
		var p1 := ordered[(i + 1) % ordered.size()]
		var d := p0.distance_to(p1)
		var steps := clampi(int(ceil(d / max_seg_len)), 1, 12)
		for s in range(steps):
			subdiv.append(p0.lerp(p1, float(s) / float(steps)))
	return subdiv


static func _create_single_bunker_lip_and_bowl_mesh(
	poly: PackedVector2Array,
	height_info: Dictionary,
	fallback_y: float
) -> ArrayMesh:
	var count := poly.size()
	if count < 4:
		return null

	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(count)

	# Compute inward unit normals at each vertex
	var inward_dirs := PackedVector2Array()
	inward_dirs.resize(count)
	for i in range(count):
		var prev := poly[(i - 1 + count) % count]
		var curr := poly[i]
		var next := poly[(i + 1) % count]
		var e1 := (curr - prev).normalized()
		var e2 := (next - curr).normalized()
		# For CCW polygon in (X, Z), inward normal is (-dz, dx)
		var n1 := Vector2(-e1.y, e1.x)
		var n2 := Vector2(-e2.y, e2.x)
		var avg_n := (n1 + n2).normalized()
		if avg_n.dot(centroid - curr) < 0.0:
			avg_n = -avg_n
		inward_dirs[i] = avg_n

	var ring_outer := PackedVector3Array()
	var ring_rim := PackedVector3Array()
	var ring_wall_base := PackedVector3Array()
	var ring_sand_inner := PackedVector3Array()
	ring_outer.resize(count)
	ring_rim.resize(count)
	ring_wall_base.resize(count)
	ring_sand_inner.resize(count)

	for i in range(count):
		var p := poly[i]
		var in_d := inward_dirs[i]
		var dist_to_center := p.distance_to(centroid)
		var inset_wall := minf(0.16, dist_to_center * 0.18)
		var inset_sand := minf(0.65, dist_to_center * 0.45)

		var p_out := p - in_d * 0.42
		var p_rim := p
		var p_wall := p + in_d * inset_wall
		var p_sand := p + in_d * inset_sand

		var y_out := _sample_height(p_out.x, p_out.y, height_info, fallback_y) + 0.015
		var y_rim := _sample_height(p_rim.x, p_rim.y, height_info, fallback_y) + 0.055
		var y_wall := y_rim - 0.24 # Steep 24cm vertical sod/soil bunker lip drop
		var y_sand := _sample_height(p_sand.x, p_sand.y, height_info, fallback_y) + 0.025

		ring_outer[i] = Vector3(p_out.x, y_out, p_out.y)
		ring_rim[i] = Vector3(p_rim.x, y_rim, p_rim.y)
		ring_wall_base[i] = Vector3(p_wall.x, minf(y_wall, y_sand), p_wall.y)
		ring_sand_inner[i] = Vector3(p_sand.x, minf(y_wall, y_sand), p_sand.y)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Color encoding: R = sand, G = vertical soil lip, B = turf collar, A = alpha
	var col_outer := Color(0.0, 0.0, 1.0, 0.0)
	var col_rim := Color(0.0, 0.35, 0.65, 1.0)
	var col_wall := Color(0.20, 0.80, 0.0, 1.0)
	var col_sand := Color(1.0, 0.0, 0.0, 1.0)

	for i in range(count):
		var ni := (i + 1) % count
		# Band 1: Outer turf feather collar up to raised sod lip crest
		_add_quad(st, ring_outer[i], ring_outer[ni], ring_rim[ni], ring_rim[i], col_outer, col_outer, col_rim, col_rim, Vector3.UP)
		# Band 2: Steep vertical sod/soil wall lip (casts real shadow onto sand floor)
		var wall_n := Vector3(inward_dirs[i].x, 0.25, inward_dirs[i].y).normalized()
		_add_quad(st, ring_rim[i], ring_rim[ni], ring_wall_base[ni], ring_wall_base[i], col_rim, col_rim, col_wall, col_wall, wall_n)
		# Band 3: Under-lip sand transition ring
		_add_quad(st, ring_wall_base[i], ring_wall_base[ni], ring_sand_inner[ni], ring_sand_inner[i], col_wall, col_wall, col_sand, col_sand, Vector3.UP)

	# Interior raked sand floor (triangulate inner ring)
	var inner_2d := PackedVector2Array()
	inner_2d.resize(count)
	for i in range(count):
		inner_2d[i] = Vector2(ring_sand_inner[i].x, ring_sand_inner[i].z)
	var tri_indices := Geometry2D.triangulate_polygon(inner_2d)
	for t in range(0, tri_indices.size(), 3):
		var i0 := tri_indices[t]
		var i1 := tri_indices[t + 1]
		var i2 := tri_indices[t + 2]
		var v0 := ring_sand_inner[i0]
		var v1 := ring_sand_inner[i1]
		var v2 := ring_sand_inner[i2]
		# Ensure upward normal
		var cross_n := (v1 - v0).cross(v2 - v0)
		if cross_n.y < 0.0:
			var tmp := v1
			v1 = v2
			v2 = tmp
		st.set_normal(Vector3.UP)
		st.set_color(col_sand)
		st.set_uv(Vector2(v0.x * 0.2, v0.z * 0.2))
		st.add_vertex(v0)
		st.set_normal(Vector3.UP)
		st.set_color(col_sand)
		st.set_uv(Vector2(v1.x * 0.2, v1.z * 0.2))
		st.add_vertex(v1)
		st.set_normal(Vector3.UP)
		st.set_color(col_sand)
		st.set_uv(Vector2(v2.x * 0.2, v2.z * 0.2))
		st.add_vertex(v2)

	return st.commit()


static func _add_quad(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3,
	ca: Color,
	cb: Color,
	cc: Color,
	cd: Color,
	n: Vector3
) -> void:
	# Ensure winding produces upward/outward normal matching `n`
	var tri_n := (b - a).cross(c - a)
	if tri_n.dot(n) < 0.0:
		st.set_normal(n)
		st.set_color(ca)
		st.set_uv(Vector2(a.x * 0.2, a.z * 0.2))
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(cc)
		st.set_uv(Vector2(c.x * 0.2, c.z * 0.2))
		st.add_vertex(c)
		st.set_normal(n)
		st.set_color(cb)
		st.set_uv(Vector2(b.x * 0.2, b.z * 0.2))
		st.add_vertex(b)

		st.set_normal(n)
		st.set_color(ca)
		st.set_uv(Vector2(a.x * 0.2, a.z * 0.2))
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(cd)
		st.set_uv(Vector2(d.x * 0.2, d.z * 0.2))
		st.add_vertex(d)
		st.set_normal(n)
		st.set_color(cc)
		st.set_uv(Vector2(c.x * 0.2, c.z * 0.2))
		st.add_vertex(c)
	else:
		st.set_normal(n)
		st.set_color(ca)
		st.set_uv(Vector2(a.x * 0.2, a.z * 0.2))
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(cb)
		st.set_uv(Vector2(b.x * 0.2, b.z * 0.2))
		st.add_vertex(b)
		st.set_normal(n)
		st.set_color(cc)
		st.set_uv(Vector2(c.x * 0.2, c.z * 0.2))
		st.add_vertex(c)

		st.set_normal(n)
		st.set_color(ca)
		st.set_uv(Vector2(a.x * 0.2, a.z * 0.2))
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(cc)
		st.set_uv(Vector2(c.x * 0.2, c.z * 0.2))
		st.add_vertex(c)
		st.set_normal(n)
		st.set_color(cd)
		st.set_uv(Vector2(d.x * 0.2, d.z * 0.2))
		st.add_vertex(d)


static func _create_bunker_high_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists("res://Courses/Environments/shaders/bunker_high.gdshader"):
		mat.shader = load("res://Courses/Environments/shaders/bunker_high.gdshader") as Shader
		if ResourceLoader.exists("res://Courses/Environments/sand-bunker/albedo.png"):
			mat.set_shader_parameter("tex_sand", load("res://Courses/Environments/sand-bunker/albedo.png"))
		if ResourceLoader.exists("res://Courses/Environments/sand-bunker/normal.png"):
			mat.set_shader_parameter("normal_sand", load("res://Courses/Environments/sand-bunker/normal.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
			mat.set_shader_parameter("tex_rough", load("res://Courses/Environments/grass-rough/albedo.png"))
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/normal.png"):
			mat.set_shader_parameter("normal_rough", load("res://Courses/Environments/grass-rough/normal.png"))
	return mat


static func _build_shoreline_reeds(scene_root: Node, height_info: Dictionary, persist_for_save: bool) -> int:
	if scene_root.get_node_or_null("ShorelineReedsMultiMesh") != null:
		return 0

	var reed_xforms: Array[Transform3D] = []
	var reed_colors: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 777111

	for child in scene_root.get_children():
		if not (child is MeshInstance3D):
			continue
		if not child.name.to_lower().begins_with("water"):
			continue
		var mi := child as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue

		var arrays := mi.mesh.surface_get_arrays(0)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if verts.size() < 3:
			continue

		# Sample shoreline points around the perimeter of the water mesh
		var step := maxi(1, int(verts.size() / 48))
		for i in range(0, verts.size(), step):
			if rng.randf() > 0.55:
				continue
			var wp := mi.transform * verts[i]
			var wy := _sample_height(wp.x, wp.z, height_info, wp.y)
			var rot_y := rng.randf_range(0.0, TAU)
			var s := rng.randf_range(0.85, 1.35)
			reed_xforms.append(Transform3D(Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s)), Vector3(wp.x, wy - 0.05, wp.z)))
			reed_colors.append(Color(rng.randf_range(0.88, 1.06), rng.randf_range(0.92, 1.08), rng.randf_range(0.82, 1.0), rng.randf_range(0.05, 0.99)))

	if reed_xforms.is_empty():
		return 0

	var reed_mesh := ProceduralTreeGeneratorScript.create_shoreline_reed_cluster_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = reed_mesh
	mm.instance_count = reed_xforms.size()

	for i in range(reed_xforms.size()):
		mm.set_instance_transform(i, reed_xforms[i])
		mm.set_instance_custom_data(i, reed_colors[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ShorelineReedsMultiMesh"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 180.0
	mmi.visibility_range_end_margin = 25.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	scene_root.add_child(mmi)
	if persist_for_save:
		mmi.owner = scene_root
	return reed_xforms.size()


static func _build_horizon_skirt(scene_root: Node, height_info: Dictionary, persist_for_save: bool) -> bool:
	if scene_root.get_node_or_null("HorizonSkirt") != null:
		return false
	if scene_root.find_child("UnifiedTerrain", true, false) == null:
		return false

	var min_x: float = height_info.get("min_x", -300.0)
	var max_x: float = height_info.get("max_x", 300.0)
	var min_z: float = height_info.get("min_z", -300.0)
	var max_z: float = height_info.get("max_z", 300.0)
	var base_y: float = height_info.get("avg_edge_y", 0.0)

	var pad := 450.0
	var out_min_x := min_x - pad
	var out_max_x := max_x + pad
	var out_min_z := min_z - pad
	var out_max_z := max_z + pad

	# Build a low-poly rolling terrain ring surrounding the course rectangular boundary
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var steps := 16
	var inner_pts := _rect_perimeter_points(min_x + 4.0, max_x - 4.0, min_z + 4.0, max_z - 4.0, steps)
	var mid_pts := _rect_perimeter_points(min_x - 160.0, max_x + 160.0, min_z - 160.0, max_z + 160.0, steps)
	var outer_pts := _rect_perimeter_points(out_min_x, out_max_x, out_min_z, out_max_z, steps)

	var ring_cnt := inner_pts.size()
	for i in range(ring_cnt):
		var ni := (i + 1) % ring_cnt
		var p_in0 := inner_pts[i]
		var p_in1 := inner_pts[ni]
		var p_mid0 := mid_pts[i]
		var p_mid1 := mid_pts[ni]
		var p_out0 := outer_pts[i]
		var p_out1 := outer_pts[ni]

		var y_in0 := _sample_height(p_in0.x, p_in0.y, height_info, base_y) - 0.35
		var y_in1 := _sample_height(p_in1.x, p_in1.y, height_info, base_y) - 0.35
		var y_mid0 := base_y + sin(p_mid0.x * 0.012 + p_mid0.y * 0.015) * 4.5 + 1.5
		var y_mid1 := base_y + sin(p_mid1.x * 0.012 + p_mid1.y * 0.015) * 4.5 + 1.5
		var y_out0 := base_y + sin(p_out0.x * 0.008 - p_out0.y * 0.011) * 9.0 + 5.0
		var y_out1 := base_y + sin(p_out1.x * 0.008 - p_out1.y * 0.011) * 9.0 + 5.0

		var v_in0 := Vector3(p_in0.x, y_in0, p_in0.y)
		var v_in1 := Vector3(p_in1.x, y_in1, p_in1.y)
		var v_mid0 := Vector3(p_mid0.x, y_mid0, p_mid0.y)
		var v_mid1 := Vector3(p_mid1.x, y_mid1, p_mid1.y)
		var v_out0 := Vector3(p_out0.x, y_out0, p_out0.y)
		var v_out1 := Vector3(p_out1.x, y_out1, p_out1.y)

		_add_quad(st, v_in0, v_in1, v_mid1, v_mid0, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Vector3.UP)
		_add_quad(st, v_mid0, v_mid1, v_out1, v_out0, Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE, Vector3.UP)

	var skirt_mesh := st.commit()
	var skirt_mat := StandardMaterial3D.new()
	skirt_mat.albedo_color = Color(0.24, 0.36, 0.20)
	skirt_mat.roughness = 0.95
	skirt_mat.metallic_specular = 0.02
	if ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
		skirt_mat.albedo_texture = load("res://Courses/Environments/grass-rough/albedo.png") as Texture2D
		skirt_mat.albedo_color = Color(0.76, 0.92, 0.70)
		skirt_mat.uv1_scale = Vector3(0.18, 0.18, 0.18)
	skirt_mesh.surface_set_material(0, skirt_mat)

	var skirt_mi := MeshInstance3D.new()
	skirt_mi.name = "HorizonSkirt"
	skirt_mi.mesh = skirt_mesh
	skirt_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(skirt_mi)
	if persist_for_save:
		skirt_mi.owner = scene_root
	return true


static func _rect_perimeter_points(min_x: float, max_x: float, min_z: float, max_z: float, steps_per_side: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for s in range(steps_per_side):
		var t := float(s) / float(steps_per_side)
		pts.append(Vector2(lerpf(min_x, max_x, t), min_z))
	for s in range(steps_per_side):
		var t := float(s) / float(steps_per_side)
		pts.append(Vector2(max_x, lerpf(min_z, max_z, t)))
	for s in range(steps_per_side):
		var t := float(s) / float(steps_per_side)
		pts.append(Vector2(lerpf(max_x, min_x, t), max_z))
	for s in range(steps_per_side):
		var t := float(s) / float(steps_per_side)
		pts.append(Vector2(min_x, lerpf(max_z, min_z, t)))
	return pts


static func _upgrade_water_materials(scene_root: Node) -> void:
	for child in scene_root.get_children():
		if child is MeshInstance3D and child.name.to_lower().begins_with("water"):
			var mi := child as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var mat := mi.mesh.surface_get_material(0)
				if mat is ShaderMaterial:
					var sm := mat as ShaderMaterial
					sm.set_shader_parameter("shallow_color", Color(0.12, 0.23, 0.18))
					sm.set_shader_parameter("deep_color", Color(0.03, 0.09, 0.11))
					sm.set_shader_parameter("foam_amount", 0.12)
					sm.set_shader_parameter("foam_color", Color(0.68, 0.74, 0.70))
					sm.set_shader_parameter("roughness", 0.04)
					sm.set_shader_parameter("height_scale", 0.025)


static func _build_cart_paths(scene_root: Node, height_info: Dictionary, persist_for_save: bool) -> bool:
	if scene_root.get_node_or_null("CartPaths") != null:
		return false

	var polylines: Array = []
	if scene_root.has_meta("cart_path_polylines"):
		var meta_lines = scene_root.get_meta("cart_path_polylines")
		if meta_lines is Array:
			polylines = meta_lines.duplicate()

	if polylines.is_empty():
		polylines = _synthesize_hole_cart_paths(scene_root)

	if polylines.is_empty():
		return false

	var base_y := float(height_info.get("avg_edge_y", 0.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_width := 1.1
	var seg_built := 0

	for raw_line in polylines:
		if not (raw_line is PackedVector2Array or raw_line is Array) or raw_line.size() < 2:
			continue
		var pts := PackedVector2Array()
		for p in raw_line:
			if p is Vector2:
				pts.append(p)
			elif p is Vector3:
				pts.append(Vector2(p.x, p.z))
		if pts.size() < 2:
			continue

		# Subdivide long segments so the ribbon drapes smoothly over terrain undulations
		var dense := PackedVector2Array()
		dense.append(pts[0])
		for i in range(pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var dist := a.distance_to(b)
			var steps := maxi(1, int(ceil(dist / 3.5)))
			for s in range(1, steps + 1):
				dense.append(a.lerp(b, float(s) / float(steps)))

		var cum_dist := 0.0
		var prev_left := Vector3.ZERO
		var prev_right := Vector3.ZERO
		var prev_v := 0.0

		for i in range(dense.size()):
			var cur := dense[i]
			var tangent := Vector2.ZERO
			if i == 0:
				tangent = (dense[1] - dense[0]).normalized()
			elif i == dense.size() - 1:
				tangent = (dense[i] - dense[i - 1]).normalized()
			else:
				tangent = (dense[i + 1] - dense[i - 1]).normalized()
			if tangent.length_squared() < 0.001:
				tangent = Vector2(1.0, 0.0)
			var perp := Vector2(-tangent.y, tangent.x)

			if i > 0:
				cum_dist += dense[i - 1].distance_to(cur)
			var v_coord := cum_dist * 0.25

			var lp2 := cur - perp * half_width
			var rp2 := cur + perp * half_width
			var ly := _sample_height(lp2.x, lp2.y, height_info, base_y) + 0.024
			var ry := _sample_height(rp2.x, rp2.y, height_info, base_y) + 0.024
			var cur_left := Vector3(lp2.x, ly, lp2.y)
			var cur_right := Vector3(rp2.x, ry, rp2.y)

			if i > 0:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.0, prev_v))
				st.add_vertex(prev_left)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(1.0, prev_v))
				st.add_vertex(prev_right)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(1.0, v_coord))
				st.add_vertex(cur_right)

				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.0, prev_v))
				st.add_vertex(prev_left)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(1.0, v_coord))
				st.add_vertex(cur_right)
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(0.0, v_coord))
				st.add_vertex(cur_left)
				seg_built += 1

			prev_left = cur_left
			prev_right = cur_right
			prev_v = v_coord

	if seg_built == 0:
		return false

	var path_mesh := st.commit()
	if ResourceLoader.exists("res://Courses/Environments/shaders/cart_path.gdshader"):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://Courses/Environments/shaders/cart_path.gdshader") as Shader
		path_mesh.surface_set_material(0, mat)

	var path_mi := MeshInstance3D.new()
	path_mi.name = "CartPaths"
	path_mi.mesh = path_mesh
	path_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	path_mi.visibility_range_end = 420.0
	path_mi.visibility_range_end_margin = 35.0
	path_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	scene_root.add_child(path_mi)
	if persist_for_save:
		path_mi.owner = scene_root
	return true


static func _synthesize_hole_cart_paths(scene_root: Node) -> Array:
	var result: Array = []
	for child in scene_root.get_children():
		if not child.name.begins_with("Hole_"):
			continue
		var tee := child.get_node_or_null("TeeSpawn") as Node3D
		if tee == null:
			tee = child.get_node_or_null("Tee") as Node3D
		var target := child.get_node_or_null("TargetPoint") as Node3D
		if target == null:
			target = child.get_node_or_null("Flag") as Node3D
		if tee == null or target == null:
			continue

		var p0 := Vector2(tee.position.x, tee.position.z)
		var p1 := Vector2(target.position.x, target.position.z)
		var delta := p1 - p0
		var dist := delta.length()
		if dist < 45.0:
			continue
		var dir := delta / dist
		var side := Vector2(-dir.y, dir.x)

		# Gently curved cart path running alongside the tee box and first 65m of the hole corridor
		var path_pts := PackedVector2Array()
		var offset_sign := 1.0 if (child.get_index() % 2 == 0) else -1.0
		path_pts.append(p0 - dir * 6.0 + side * (8.5 * offset_sign))
		path_pts.append(p0 + side * (7.5 * offset_sign))
		path_pts.append(p0 + dir * minf(dist * 0.25, 35.0) + side * (11.5 * offset_sign))
		path_pts.append(p0 + dir * minf(dist * 0.55, 75.0) + side * (14.0 * offset_sign))
		result.append(path_pts)
	return result
