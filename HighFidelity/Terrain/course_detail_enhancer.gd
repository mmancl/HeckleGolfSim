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
		"horizon_skirt": false,
		"cart_paths": false,
		"thick_rough_grass": 0,
		"thick_rough_bushes": 0
	}
	if scene_root == null or MobilePerformance.is_driving_range_node(scene_root):
		return result

	_strip_legacy_grass_nodes(scene_root)
	var height_map := _build_terrain_height_lookup(scene_root)
	result["bunkers_built"] = _build_recessed_3d_bunkers(scene_root, height_map, persist_for_save)
	result["shoreline_reeds"] = _build_shoreline_reeds(scene_root, height_map, persist_for_save)
	result["horizon_skirt"] = _build_horizon_skirt(scene_root, height_map, persist_for_save)
	result["cart_paths"] = _build_cart_paths(scene_root, height_map, persist_for_save)
	result["thick_rough_grass"] = 0
	result["thick_rough_bushes"] = _build_thick_rough_bushes(scene_root, height_map, persist_for_save)
	ensure_deep_rough_map(scene_root)
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
					or cn == "ThickRoughGrassMultiMesh" \
					or cn == "ThickRoughBushes" \
					or cn.begins_with("ThickRough_") \
					or cn.begins_with("BushChunk_") or cn.begins_with("Bush_") \
					or cn.begins_with("RockChunk_") or cn.begins_with("Rock_"):
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
	var t_pos := terrain.global_position if terrain.is_inside_tree() else terrain.position
	info["min_x"] = t_pos.x + aabb.position.x
	info["max_x"] = t_pos.x + aabb.position.x + aabb.size.x
	info["min_z"] = t_pos.z + aabb.position.z
	info["max_z"] = t_pos.z + aabb.position.z + aabb.size.z

	var arrays := terrain.mesh.surface_get_arrays(0)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return info
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var grid: Dictionary = {}
	var edge_sum := 0.0
	var edge_cnt := 0
	var cell := 4.0

	for v in verts:
		var vx := t_pos.x + v.x
		var vy := t_pos.y + v.y
		var vz := t_pos.z + v.z
		var gx := int(round(vx / cell))
		var gz := int(round(vz / cell))
		grid[Vector2i(gx, gz)] = vy
		if absf(vx - info["min_x"]) < 8.0 or absf(vx - info["max_x"]) < 8.0 or absf(vz - info["min_z"]) < 8.0 or absf(vz - info["max_z"]) < 8.0:
			edge_sum += vy
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
	var existing_bunkers = scene_root.get_node_or_null("HighFidelityBunkers")
	if existing_bunkers != null:
		if existing_bunkers.is_inside_tree():
			existing_bunkers.queue_free()
		else:
			existing_bunkers.free()

	var polygons: Array[PackedVector2Array] = []
	var base_heights: Array[float] = []

	for child in scene_root.find_children("*", "CollisionObject3D", true, false):
		var cname := child.name.to_lower()
		var is_bunker: bool = (cname.begins_with("bunker") or cname.contains("bunker") or bool(child.get_meta("is_sand", false)) or int(child.get_meta("surface_type", -1)) == 5) and not bool(child.get_meta("is_water", false)) and not cname.contains("terrain") and not cname.contains("rough")
		if is_bunker:
			# 1. Prefer explicit boundary polygon preserved in metadata (from course generator)
			if child.has_meta("boundary_polygon"):
				var poly_meta = child.get_meta("boundary_polygon")
				var boundary_pts := PackedVector2Array()
				if poly_meta is PackedVector2Array:
					boundary_pts = poly_meta
				elif poly_meta is Array:
					for p in poly_meta:
						if p is Vector2:
							boundary_pts.append(p)
				if boundary_pts.size() >= 3:
					var world_poly := PackedVector2Array()
					var child_xform: Transform3D = (child as Node3D).transform
					for pt in boundary_pts:
						var wp := child_xform * Vector3(pt.x, 0.0, pt.y)
						world_poly.append(Vector2(wp.x, wp.z))
					polygons.append(world_poly)
					base_heights.append((child as Node3D).position.y)
					continue

			# 2. Inspect collision shapes without convex hull distortion
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
					if cs.shape is ConcavePolygonShape3D:
						var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
						var boundary := _extract_boundary_polygon_from_faces(faces, (child as Node3D).transform * cs.transform)
						if boundary.size() >= 3:
							polygons.append(boundary)
							base_heights.append((child as Node3D).position.y)
						else:
							# Fallback if boundary extraction could not trace a valid loop
							var world_pts := PackedVector2Array()
							for f in faces:
								var wp := (child as Node3D).transform * (cs.transform * f)
								world_pts.append(Vector2(wp.x, wp.z))
							if world_pts.size() >= 3:
								var hull := Geometry2D.convex_hull(world_pts)
								if hull.size() > 3 and hull[hull.size() - 1].is_equal_approx(hull[0]):
									hull.remove_at(hull.size() - 1)
								if hull.size() >= 3:
									polygons.append(hull)
									base_heights.append((child as Node3D).position.y)
					elif cs.shape is ConvexPolygonShape3D:
						var points := (cs.shape as ConvexPolygonShape3D).points
						var world_pts := PackedVector2Array()
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



## Extracts the outer 2D boundary polygon from a ConcavePolygonShape3D face array in world space.
## In a triangulated 2D manifold mesh, interior edges are shared by 2 triangles,
## while boundary edges belong to exactly 1 triangle.
## Chaining these single-occurrence boundary edges produces the exact (potentially concave) polygon.
static func _extract_boundary_polygon_from_faces(faces: PackedVector3Array, xform: Transform3D) -> PackedVector2Array:
	if faces.size() < 3 or (faces.size() % 3) != 0:
		return PackedVector2Array()

	var edge_counts := {}
	var edge_directed := {}
	var snapped_to_world := {}

	var tri_count := faces.size() / 3
	for t in range(tri_count):
		var base := t * 3
		var v0 := xform * faces[base]
		var v1 := xform * faces[base + 1]
		var v2 := xform * faces[base + 2]

		var p0 := Vector2(v0.x, v0.z)
		var p1 := Vector2(v1.x, v1.z)
		var p2 := Vector2(v2.x, v2.z)

		var s0 := Vector2i(roundi(p0.x * 1000.0), roundi(p0.y * 1000.0))
		var s1 := Vector2i(roundi(p1.x * 1000.0), roundi(p1.y * 1000.0))
		var s2 := Vector2i(roundi(p2.x * 1000.0), roundi(p2.y * 1000.0))

		if s0 == s1 or s1 == s2 or s2 == s0:
			continue

		snapped_to_world[s0] = p0
		snapped_to_world[s1] = p1
		snapped_to_world[s2] = p2

		var tri_edges := [
			Vector4i(s0.x, s0.y, s1.x, s1.y),
			Vector4i(s1.x, s1.y, s2.x, s2.y),
			Vector4i(s2.x, s2.y, s0.x, s0.y)
		]

		for edge in tri_edges:
			var u := Vector2i(edge.x, edge.y)
			var v := Vector2i(edge.z, edge.w)
			var undirected_key: Vector4i
			if u.x < v.x or (u.x == v.x and u.y < v.y):
				undirected_key = Vector4i(u.x, u.y, v.x, v.y)
			else:
				undirected_key = Vector4i(v.x, v.y, u.x, u.y)

			edge_counts[undirected_key] = edge_counts.get(undirected_key, 0) + 1
			edge_directed[undirected_key] = edge

	var adj := {}
	for key in edge_counts:
		if edge_counts[key] == 1:
			var dir_edge: Vector4i = edge_directed[key]
			var from_pt := Vector2i(dir_edge.x, dir_edge.y)
			var to_pt := Vector2i(dir_edge.z, dir_edge.w)
			adj[from_pt] = to_pt

	if adj.is_empty():
		return PackedVector2Array()

	# Trace closed loops of boundary edges and select the primary outer loop
	var best_loop := PackedVector2Array()
	var best_area := 0.0
	var visited := {}

	for start_node in adj.keys():
		if visited.has(start_node):
			continue
		var loop := PackedVector2Array()
		var curr: Vector2i = start_node
		while not visited.has(curr) and adj.has(curr):
			visited[curr] = true
			if snapped_to_world.has(curr):
				loop.append(snapped_to_world[curr])
			var nxt: Vector2i = adj[curr]
			if nxt == start_node:
				break
			curr = nxt

		if loop.size() >= 3:
			# Remove near-zero distance consecutive duplicate points
			var cleaned := PackedVector2Array()
			for pt in loop:
				if cleaned.is_empty() or cleaned[cleaned.size() - 1].distance_squared_to(pt) > 0.0001:
					cleaned.append(pt)
			if cleaned.size() > 3 and cleaned[cleaned.size() - 1].distance_squared_to(cleaned[0]) < 0.0001:
				cleaned.remove_at(cleaned.size() - 1)

			# Remove redundant collinear vertices along straight edges
			if cleaned.size() > 3:
				var simplified := PackedVector2Array()
				var c_cnt := cleaned.size()
				for i in range(c_cnt):
					var prev_p: Vector2 = cleaned[(i - 1 + c_cnt) % c_cnt]
					var curr_p: Vector2 = cleaned[i]
					var next_p: Vector2 = cleaned[(i + 1) % c_cnt]
					var e1 := (curr_p - prev_p).normalized()
					var e2 := (next_p - curr_p).normalized()
					var cross := absf(e1.x * e2.y - e1.y * e2.x)
					var dot := e1.dot(e2)
					if cross < 0.001 and dot > 0.999:
						continue
					simplified.append(curr_p)
				if simplified.size() >= 3:
					cleaned = simplified

			if cleaned.size() >= 3:
				var loop_area := 0.0
				var c_size := cleaned.size()
				for i in range(c_size):
					var a: Vector2 = cleaned[i]
					var b: Vector2 = cleaned[(i + 1) % c_size]
					loop_area += (a.x * b.y - b.x * a.y)
				var abs_area := absf(loop_area)
				if abs_area > best_area:
					best_area = abs_area
					if loop_area < 0.0:
						cleaned.reverse()
					best_loop = cleaned

	return best_loop


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

	# Compute inward unit normals at each vertex.
	# For any strictly CCW polygon in (X, Z), inward normal to (dx, dz) is (-dz, dx).
	var inward_dirs := PackedVector2Array()
	inward_dirs.resize(count)
	for i in range(count):
		var prev := poly[(i - 1 + count) % count]
		var curr := poly[i]
		var next := poly[(i + 1) % count]
		var e1 := (curr - prev).normalized()
		var e2 := (next - curr).normalized()
		var n1 := Vector2(-e1.y, e1.x)
		var n2 := Vector2(-e2.y, e2.x)
		var sum_n := n1 + n2
		var avg_n := sum_n.normalized() if sum_n.length_squared() > 0.0001 else n1
		inward_dirs[i] = avg_n

	var ring_outer := PackedVector3Array()
	var ring_rim := PackedVector3Array()
	var ring_wall_base := PackedVector3Array()
	var ring_sand_inner := PackedVector3Array()
	ring_outer.resize(count)
	ring_rim.resize(count)
	ring_wall_base.resize(count)
	ring_sand_inner.resize(count)

	# Calculate distance to opposite boundary along inward ray to strictly prevent
	# inward insets from crossing narrow tongues, fingers, or opposite shores
	var opp_dists := PackedFloat32Array()
	opp_dists.resize(count)
	for i in range(count):
		var p := poly[i]
		var r := inward_dirs[i]
		var min_opp := 999.0
		for j in range(count):
			if j == i or (j + 1) % count == i or (i + 1) % count == j:
				continue
			var a := poly[j]
			var b := poly[(j + 1) % count]
			var v1 := p - a
			var v2 := b - a
			var dot := v2.x * (-r.y) + v2.y * r.x
			if absf(dot) > 0.00001:
				var t := (v2.x * v1.y - v2.y * v1.x) / dot
				var u := (v1.x * (-r.y) + v1.y * r.x) / dot
				if t > 0.01 and u >= 0.0 and u <= 1.0:
					if t < min_opp:
						min_opp = t
		opp_dists[i] = min_opp

	for i in range(count):
		var p := poly[i]
		var in_d := inward_dirs[i]
		var opp := opp_dists[i]
		var max_safe := minf(0.65, opp * 0.35) if opp < 900.0 else 0.65

		var inset_wall := clampf(max_safe * 0.30, 0.04, 0.16)
		var inset_sand := clampf(max_safe, 0.12, 0.65)
		var collar_out := clampf(minf(0.42, opp * 0.30), 0.10, 0.42)

		var p_out := p - in_d * collar_out
		var p_rim := p
		var p_wall := p + in_d * inset_wall
		var p_sand := p + in_d * inset_sand

		# Bunker perimeter elevation profiles:
		# p_out is in outer turf; p_rim is at cut boundary; p_wall & p_sand are inset lip apron
		var y_out := _sample_height(p_out.x, p_out.y, height_info, fallback_y) + 0.010
		var y_rim := _sample_height(p_rim.x, p_rim.y, height_info, fallback_y) + 0.015
		var y_sand := _sample_height(p_sand.x, p_sand.y, height_info, fallback_y) + 0.005
		# Lip drop gently steps down to sand floor without penetrating into or cutting across terrain
		var y_wall := clampf(y_rim - 0.06, y_sand, y_rim)

		ring_outer[i] = Vector3(p_out.x, y_out, p_out.y)
		ring_rim[i] = Vector3(p_rim.x, y_rim, p_rim.y)
		ring_wall_base[i] = Vector3(p_wall.x, y_wall, p_wall.y)
		ring_sand_inner[i] = Vector3(p_sand.x, y_sand, p_sand.y)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Color encoding: R = sand, G = vertical soil lip, B = turf collar, A = alpha
	var col_outer := Color(0.0, 0.0, 1.0, 0.0)
	var col_rim := Color(0.0, 0.40, 0.60, 0.85)
	var col_wall := Color(0.25, 0.75, 0.0, 0.95)
	var col_sand := Color(1.0, 0.0, 0.0, 0.0)

	for i in range(count):
		var ni := (i + 1) % count
		# Band 1: Outer turf feather collar up to sod lip crest
		_add_quad(st, ring_outer[i], ring_outer[ni], ring_rim[ni], ring_rim[i], col_outer, col_outer, col_rim, col_rim, Vector3.UP)
		# Band 2: Warm earthy brown soil lip apron (tucks down to sand level)
		var wall_n := Vector3(inward_dirs[i].x, 0.50, inward_dirs[i].y).normalized()
		_add_quad(st, ring_rim[i], ring_rim[ni], ring_wall_base[ni], ring_wall_base[i], col_rim, col_rim, col_wall, col_wall, wall_n)
		# Band 3: Transition apron feathering into sand floor (alpha feathers to 0.0 to seamlessly hand off to UnifiedTerrain)
		_add_quad(st, ring_wall_base[i], ring_wall_base[ni], ring_sand_inner[ni], ring_sand_inner[i], col_wall, col_wall, col_sand, col_sand, Vector3.UP)

	# The interior bunker sand floor is rendered directly by UnifiedTerrain with the realistic
	# splat shader (and bowl depression), avoiding planar chord protrusions or Z-fighting across
	# undulating sand terrain. The lip perimeter mesh provides the authentic 3D turf/soil transition lip.

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


static func _get_water_surface_max_y(faces: PackedVector3Array, xform: Transform3D) -> float:
	var my := -99999.0
	for i in range(faces.size()):
		var vy := (xform * faces[i]).y
		if vy > my:
			my = vy
	return my if my > -90000.0 else xform.origin.y


static func _orient_polygon_ccw(poly: PackedVector2Array) -> PackedVector2Array:
	var n := poly.size()
	if n < 3:
		return poly
	var area := 0.0
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += (a.x * b.y - b.x * a.y)
	if area < 0.0:
		var rev := poly.duplicate()
		rev.reverse()
		return rev
	return poly


static func _build_shoreline_reeds(scene_root: Node, height_info: Dictionary, persist_for_save: bool) -> int:
	# If shoreline reeds already exist on this scene, remove them so they can be re-generated
	var existing_reeds := scene_root.get_node_or_null("ShorelineReedsMultiMesh")
	if existing_reeds != null:
		if existing_reeds.is_inside_tree():
			existing_reeds.queue_free()
		else:
			existing_reeds.free()

	var water_polygons: Array[PackedVector2Array] = []
	var water_fallback_y: Array[float] = []

	# 1. Extract exact water polygons and accurate surface elevations from water StaticBody3D / CollisionObject3D nodes
	for child in scene_root.find_children("*", "CollisionObject3D", true, false):
		var cname := child.name.to_lower()
		var is_wat: bool = bool(child.get_meta("is_water", false)) or cname.begins_with("water") or cname.contains("water")
		if not is_wat:
			continue

		var child_xform: Transform3D = (child as Node3D).global_transform if (child as Node3D).is_inside_tree() else _get_relative_transform_to_root(child as Node3D, scene_root)
		var poly := PackedVector2Array()
		var poly_water_y := child_xform.origin.y

		# Find exact water surface Y from collision mesh faces
		var found_faces := false
		for sub in child.get_children():
			if sub is CollisionShape3D and (sub as CollisionShape3D).shape is ConcavePolygonShape3D:
				var faces := ((sub as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces()
				if not faces.is_empty():
					poly_water_y = _get_water_surface_max_y(faces, child_xform * (sub as CollisionShape3D).transform)
					found_faces = true
					break

		# Also check companion MeshInstance3D if collision shape didn't provide faces
		if not found_faces:
			var mi_name := child.name.replace("Static_", "")
			var mi := scene_root.find_child(mi_name, true, false) as MeshInstance3D
			if mi != null and mi.mesh != null:
				var mi_xform: Transform3D = mi.global_transform if mi.is_inside_tree() else _get_relative_transform_to_root(mi, scene_root)
				var faces := mi.mesh.get_faces()
				if not faces.is_empty():
					poly_water_y = _get_water_surface_max_y(faces, mi_xform)

		for meta_key in ["water_points", "boundary_polygon"]:
			if child.has_meta(meta_key):
				var p_meta = child.get_meta(meta_key)
				if p_meta is PackedVector2Array and (p_meta as PackedVector2Array).size() >= 3:
					for pt in (p_meta as PackedVector2Array):
						var wp := child_xform * Vector3(pt.x, 0.0, pt.y)
						poly.append(Vector2(wp.x, wp.z))
					break
				elif p_meta is Array and (p_meta as Array).size() >= 3:
					for pt in (p_meta as Array):
						if pt is Vector2:
							var wp := child_xform * Vector3((pt as Vector2).x, 0.0, (pt as Vector2).y)
							poly.append(Vector2(wp.x, wp.z))
					if poly.size() >= 3:
						break

		if poly.size() < 3:
			for sub in child.get_children():
				if sub is CollisionPolygon3D and (sub as CollisionPolygon3D).polygon.size() >= 3:
					var cp := sub as CollisionPolygon3D
					for pt in cp.polygon:
						var wp := child_xform * (cp.transform * Vector3(pt.x, 0.0, pt.y))
						poly.append(Vector2(wp.x, wp.z))
					break
				elif sub is CollisionShape3D and (sub as CollisionShape3D).shape is ConcavePolygonShape3D:
					var cs := sub as CollisionShape3D
					var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
					var boundary := _extract_boundary_polygon_from_faces(faces, child_xform * cs.transform)
					if boundary.size() >= 3:
						poly = boundary
						break

		if poly.size() >= 3:
			water_polygons.append(poly)
			water_fallback_y.append(poly_water_y)

	# 2. Fallback: Extract boundary polygons from any Water MeshInstance3D if no water StaticBody3D was found
	if water_polygons.is_empty():
		var search_roots: Array[Node] = [scene_root]
		for child in scene_root.get_children():
			if child is Node3D and child.name.begins_with("Hole"):
				search_roots.append(child)
		for sr in search_roots:
			for child in sr.get_children():
				if not (child is MeshInstance3D):
					continue
				if not child.name.to_lower().begins_with("water"):
					continue
				var mi := child as MeshInstance3D
				if mi.mesh == null or mi.mesh.get_surface_count() == 0:
					continue
				var mi_xform: Transform3D = mi.global_transform if mi.is_inside_tree() else _get_relative_transform_to_root(mi, scene_root)
				var faces := mi.mesh.get_faces()
				var boundary := _extract_boundary_polygon_from_faces(faces, mi_xform)
				var mi_water_y := _get_water_surface_max_y(faces, mi_xform)
				if boundary.size() >= 3:
					water_polygons.append(boundary)
					water_fallback_y.append(mi_water_y)
				else:
					var arrays := mi.mesh.surface_get_arrays(0)
					if arrays.size() > Mesh.ARRAY_VERTEX:
						var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
						if verts.size() >= 3:
							var world_pts := PackedVector2Array()
							for v in verts:
								var wp := mi_xform * v
								world_pts.append(Vector2(wp.x, wp.z))
							var hull := Geometry2D.convex_hull(world_pts)
							if hull.size() > 3 and hull[hull.size() - 1].is_equal_approx(hull[0]):
								hull.remove_at(hull.size() - 1)
							if hull.size() >= 3:
								water_polygons.append(hull)
								water_fallback_y.append(mi_water_y)

	if water_polygons.is_empty():
		return 0

	var reed_xforms: Array[Transform3D] = []
	var reed_colors: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 777111

	# Place tall grass / marsh reeds continuously ALL the way around every water hazard with no limit
	# Staggered multi-layer band (shallow water line + shore bank) to match real natural cattail stands
	var min_step := 0.65
	var step_jitter := 0.20

	for p_idx in range(water_polygons.size()):
		var raw_poly := water_polygons[p_idx]
		var water_level_y := water_fallback_y[p_idx]
		# Orient CCW so outward normal points reliably onto dry land
		var poly := _orient_polygon_ccw(raw_poly)
		var num_pts := poly.size()
		for i in range(num_pts):
			var p1 := poly[i]
			var p2 := poly[(i + 1) % num_pts]
			var seg_len := p1.distance_to(p2)
			if seg_len < 0.05:
				continue

			var dir := (p2 - p1) / seg_len
			# Inward normal is (-dir.y, dir.x); Outward normal (toward shore bank) is (dir.y, -dir.x)
			var outward := Vector2(dir.y, -dir.x)
			var d := 0.0
			while d < seg_len:
				var t := d / seg_len
				var base_pt := p1.lerp(p2, t)

				# Cluster 1: Waterline bank border (0.25m to 0.70m from water edge onto bank)
				var off1 := outward * rng.randf_range(0.25, 0.70)
				var pos1 := base_pt + off1
				var wy1 := _sample_height(pos1.x, pos1.y, height_info, water_level_y)
				wy1 = maxf(wy1, water_level_y + 0.02)
				var rot_y1 := rng.randf_range(0.0, TAU)
				var s_xz1 := rng.randf_range(0.90, 1.25)
				var s_y1 := rng.randf_range(0.90, 1.20)
				reed_xforms.append(Transform3D(Basis(Vector3.UP, rot_y1).scaled(Vector3(s_xz1, s_y1, s_xz1)), Vector3(pos1.x, maxf(wy1 - 0.03, water_level_y + 0.01), pos1.y)))
				reed_colors.append(Color(rng.randf_range(0.86, 1.06), rng.randf_range(0.90, 1.08), rng.randf_range(0.80, 1.02), rng.randf_range(0.05, 0.99)))

				# Cluster 2: Shore bank buffer (0.70m to 1.45m up the bank slope)
				var off2 := outward * rng.randf_range(0.70, 1.45)
				var pos2 := base_pt + off2
				var wy2 := _sample_height(pos2.x, pos2.y, height_info, water_level_y)
				wy2 = maxf(wy2, water_level_y + 0.04)
				var rot_y2 := rng.randf_range(0.0, TAU)
				var s_xz2 := rng.randf_range(0.85, 1.20)
				var s_y2 := rng.randf_range(0.85, 1.15)
				reed_xforms.append(Transform3D(Basis(Vector3.UP, rot_y2).scaled(Vector3(s_xz2, s_y2, s_xz2)), Vector3(pos2.x, maxf(wy2 - 0.03, water_level_y + 0.02), pos2.y)))
				reed_colors.append(Color(rng.randf_range(0.84, 1.04), rng.randf_range(0.88, 1.06), rng.randf_range(0.78, 1.00), rng.randf_range(0.05, 0.99)))

				d += min_step + rng.randf() * step_jitter

	if reed_xforms.is_empty():
		return 0

	var reed_mesh := ProceduralTreeGeneratorScript.create_shoreline_reed_cluster_mesh()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = reed_mesh
	mm.instance_count = reed_xforms.size()

	var buf := PackedFloat32Array()
	buf.resize(reed_xforms.size() * 16)
	for i in range(reed_xforms.size()):
		var xf: Transform3D = reed_xforms[i]
		var col: Color = reed_colors[i]
		var base_idx := i * 16
		buf[base_idx + 0] = xf.basis.x.x
		buf[base_idx + 1] = xf.basis.y.x
		buf[base_idx + 2] = xf.basis.z.x
		buf[base_idx + 3] = xf.origin.x
		buf[base_idx + 4] = xf.basis.x.y
		buf[base_idx + 5] = xf.basis.y.y
		buf[base_idx + 6] = xf.basis.z.y
		buf[base_idx + 7] = xf.origin.y
		buf[base_idx + 8] = xf.basis.x.z
		buf[base_idx + 9] = xf.basis.y.z
		buf[base_idx + 10] = xf.basis.z.z
		buf[base_idx + 11] = xf.origin.z
		buf[base_idx + 12] = col.r
		buf[base_idx + 13] = col.g
		buf[base_idx + 14] = col.b
		buf[base_idx + 15] = col.a
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, col)
	mm.buffer = buf

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ShorelineReedsMultiMesh"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 350.0
	mmi.visibility_range_end_margin = 40.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	scene_root.add_child(mmi)
	if persist_for_save:
		mmi.owner = scene_root
	return reed_xforms.size()


static func _get_relative_transform_to_root(node: Node3D, root_node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var curr: Node = node
	while curr != null and curr != root_node:
		if curr is Node3D:
			t = (curr as Node3D).transform * t
		curr = curr.get_parent()
	return t


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


# ==============================================================================
# THICK ROUGH SYSTEM (High Graphics Mode)
# Thick 3D fescue grass clusters and sporadic bushes in the rough beyond the
# mapped manicured rough, creating authentic coastal dune / deep rough vegetation.
# ==============================================================================

static func _build_thick_rough_grass(scene_root: Node, _height_info: Dictionary, _persist_for_save: bool) -> int:
	# Long 3D grass patches are disabled in favor of the elevated deep rough terrain shader texture
	# wherever ball lie resistance is 25% or more.
	if scene_root != null:
		var existing := scene_root.get_node_or_null("ThickRoughGrassMultiMesh")
		if existing != null:
			scene_root.remove_child(existing)
			if existing.is_inside_tree():
				existing.queue_free()
			else:
				existing.free()
	return 0


static func ensure_deep_rough_map(scene_root: Node, terrain_node: MeshInstance3D = null) -> Texture2D:
	if scene_root == null:
		return null
	var terrain := terrain_node
	if terrain == null:
		terrain = scene_root.find_child("UnifiedTerrain", true, false) as MeshInstance3D
	if terrain == null or terrain.mesh == null or terrain.mesh.get_surface_count() == 0:
		return null

	var deep_tex: Texture2D = null
	if terrain.has_meta("deep_rough_map"):
		deep_tex = terrain.get_meta("deep_rough_map") as Texture2D
	if deep_tex == null:
		deep_tex = _build_deep_rough_map(scene_root, terrain)
		if deep_tex != null:
			terrain.set_meta("deep_rough_map", deep_tex)

	if deep_tex != null:
		var mats: Array[ShaderMaterial] = []
		if terrain.material_override is ShaderMaterial:
			mats.append(terrain.material_override as ShaderMaterial)
		if terrain.get_surface_override_material(0) is ShaderMaterial:
			mats.append(terrain.get_surface_override_material(0) as ShaderMaterial)
		if terrain.mesh.surface_get_material(0) is ShaderMaterial:
			mats.append(terrain.mesh.surface_get_material(0) as ShaderMaterial)
		for m in mats:
			m.set_shader_parameter("deep_rough_map", deep_tex)
			m.set_shader_parameter("has_deep_rough_map", true)
	return deep_tex


static func _build_deep_rough_map(scene_root: Node, terrain: MeshInstance3D) -> ImageTexture:
	var aabb := terrain.mesh.get_aabb()
	var min_x: float = aabb.position.x
	var max_x: float = aabb.position.x + aabb.size.x
	var min_z: float = aabb.position.z
	var max_z: float = aabb.position.z + aabb.size.z
	var width: float = maxf(max_x - min_x, 1.0)
	var depth: float = maxf(max_z - min_z, 1.0)

	var tex_size: int = 256
	var total_cells: int = tex_size * tex_size
	var dist_grid := PackedFloat32Array()
	dist_grid.resize(total_cells)
	dist_grid.fill(99999.0)

	var tee_mask := PackedByteArray()
	tee_mask.resize(total_cells)
	tee_mask.fill(0)

	var inv_w: float = float(tex_size - 1) / width
	var inv_d: float = float(tex_size - 1) / depth
	var step_x: float = width / float(tex_size - 1)
	var step_z: float = depth / float(tex_size - 1)

	var seeded_any := false

	# 1. Seed fairways, greens, and tees directly from StaticBody3D shapes/polygons (matching range.gd)
	for child in scene_root.find_children("*", "CollisionObject3D", true, false):
		var cname := child.name.to_lower()
		var st: int = int(child.get_meta("surface_type", -1))
		var is_wat: bool = bool(child.get_meta("is_water", false)) or cname.begins_with("water") or cname.contains("water")
		var is_sand: bool = (bool(child.get_meta("is_sand", false)) or st == 5 or cname.begins_with("bunker") or cname.contains("bunker")) and not is_wat
		if is_wat or is_sand:
			continue

		var is_green: bool = cname.begins_with("green_static") or cname.contains("green") or st == 4
		var is_tee: bool = (cname.begins_with("tee_static") or cname.contains("tee")) and not is_green
		var is_fairway: bool = (cname.begins_with("fairway_static") or cname.contains("fairway") or (st == 0 and not is_tee)) and not is_green and not is_tee
		if not is_green and not is_fairway and not is_tee:
			continue

		var child_xform: Transform3D = (child as Node3D).transform
		var has_concave := false

		for sub in child.get_children():
			if sub is CollisionShape3D and (sub as CollisionShape3D).shape is ConcavePolygonShape3D:
				var cs := sub as CollisionShape3D
				var faces: PackedVector3Array = (cs.shape as ConcavePolygonShape3D).get_faces()
				var full_xform: Transform3D = child_xform * cs.transform
				var face_count := faces.size()
				if face_count >= 3:
					has_concave = true
					for i in range(0, face_count - 2, 3):
						var va := full_xform * faces[i]
						var vb := full_xform * faces[i + 1]
						var vc := full_xform * faces[i + 2]
						var a := Vector2(va.x, va.z)
						var b := Vector2(vb.x, vb.z)
						var c := Vector2(vc.x, vc.z)
						if is_tee:
							_mark_triangle_on_mask(tee_mask, tex_size, min_x, min_z, inv_w, inv_d, a, b, c, 1)
						else:
							_seed_triangle_on_dist_grid(dist_grid, tex_size, min_x, min_z, step_x, step_z, inv_w, inv_d, a, b, c)
							seeded_any = true

		if not has_concave:
			var poly := PackedVector2Array()
			if child.has_meta("boundary_polygon"):
				var p_meta = child.get_meta("boundary_polygon")
				if p_meta is PackedVector2Array:
					for pt in p_meta:
						var wp := child_xform * Vector3(pt.x, 0.0, pt.y)
						poly.append(Vector2(wp.x, wp.z))
			if poly.size() < 3:
				for sub in child.get_children():
					if sub is CollisionPolygon3D and (sub as CollisionPolygon3D).polygon.size() >= 3:
						var cp := sub as CollisionPolygon3D
						for pt in cp.polygon:
							var wp := child_xform * (cp.transform * Vector3(pt.x, 0.0, pt.y))
							poly.append(Vector2(wp.x, wp.z))
						break
			if poly.size() >= 3:
				var tri_indices := Geometry2D.triangulate_polygon(poly)
				for i in range(0, tri_indices.size() - 2, 3):
					var a := poly[tri_indices[i]]
					var b := poly[tri_indices[i + 1]]
					var c := poly[tri_indices[i + 2]]
					if is_tee:
						_mark_triangle_on_mask(tee_mask, tex_size, min_x, min_z, inv_w, inv_d, a, b, c, 1)
					else:
						_seed_triangle_on_dist_grid(dist_grid, tex_size, min_x, min_z, step_x, step_z, inv_w, inv_d, a, b, c)
						seeded_any = true

	# Fallback: If no static bodies were present, seed from splat_map R (green) and G (fairway) channels
	if not seeded_any:
		var splat_tex: Texture2D = null
		var base_m: Material = terrain.mesh.surface_get_material(0)
		if base_m == null:
			base_m = terrain.material_override
		if base_m is ShaderMaterial:
			splat_tex = (base_m as ShaderMaterial).get_shader_parameter("splat_map") as Texture2D
		if splat_tex == null and terrain.has_meta("orig_splat_map"):
			splat_tex = terrain.get_meta("orig_splat_map") as Texture2D
		if splat_tex != null:
			var simg := splat_tex.get_image()
			if simg != null and not simg.is_compressed():
				var sw := simg.get_width()
				var sh := simg.get_height()
				for gz in range(tex_size):
					var sy := clampi(int(round(float(gz) / float(tex_size - 1) * float(sh - 1))), 0, sh - 1)
					for gx in range(tex_size):
						var sx := clampi(int(round(float(gx) / float(tex_size - 1) * float(sw - 1))), 0, sw - 1)
						var c := simg.get_pixel(sx, sy)
						if c.r > 0.45 or c.g > 0.45:
							dist_grid[gz * tex_size + gx] = 0.0
							seeded_any = true

	# Also mark cart paths into tee_mask so elevated deep rough never overlaps paths
	var cart_paths: Array = []
	if scene_root.has_meta("cart_path_polylines"):
		cart_paths = scene_root.get_meta("cart_path_polylines")
	else:
		cart_paths = _synthesize_hole_cart_paths(scene_root)
	for path in cart_paths:
		var pts: PackedVector2Array = path as PackedVector2Array
		for i in range(pts.size() - 1):
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var seg_len := p0.distance_to(p1)
			var steps := maxi(1, int(ceil(seg_len / 1.5)))
			for s in range(steps + 1):
				var p := p0.lerp(p1, float(s) / float(steps))
				var gx := clampi(int(round((p.x - min_x) * inv_w)), 0, tex_size - 1)
				var gz := clampi(int(round((p.y - min_z) * inv_d)), 0, tex_size - 1)
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var nx := clampi(gx + dx, 0, tex_size - 1)
						var nz := clampi(gz + dz, 0, tex_size - 1)
						tee_mask[nz * tex_size + nx] = 1

	# 2. Fast 2-pass Chamfer 5-7-11 Euclidean Distance Transform in world meters
	if seeded_any:
		var d_diag := sqrt(step_x * step_x + step_z * step_z)
		var d_kx := sqrt((2.0 * step_x) * (2.0 * step_x) + step_z * step_z)
		var d_kz := sqrt(step_x * step_x + (2.0 * step_z) * (2.0 * step_z))

		# Forward pass (top-left to bottom-right)
		for gz in range(tex_size):
			var row_off := gz * tex_size
			for gx in range(tex_size):
				var best: float = dist_grid[row_off + gx]
				if best <= 0.0:
					continue
				if gx > 0:
					best = minf(best, dist_grid[row_off + gx - 1] + step_x)
				if gz > 0:
					var prev_row := (gz - 1) * tex_size
					best = minf(best, dist_grid[prev_row + gx] + step_z)
					if gx > 0:
						best = minf(best, dist_grid[prev_row + gx - 1] + d_diag)
					if gx + 1 < tex_size:
						best = minf(best, dist_grid[prev_row + gx + 1] + d_diag)
					if gx > 1:
						best = minf(best, dist_grid[prev_row + gx - 2] + d_kx)
					if gx + 2 < tex_size:
						best = minf(best, dist_grid[prev_row + gx + 2] + d_kx)
				if gz > 1:
					var prev2_row := (gz - 2) * tex_size
					if gx > 0:
						best = minf(best, dist_grid[prev2_row + gx - 1] + d_kz)
					if gx + 1 < tex_size:
						best = minf(best, dist_grid[prev2_row + gx + 1] + d_kz)
				dist_grid[row_off + gx] = best

		# Backward pass (bottom-right to top-left)
		for gz in range(tex_size - 1, -1, -1):
			var row_off := gz * tex_size
			for gx in range(tex_size - 1, -1, -1):
				var best: float = dist_grid[row_off + gx]
				if best <= 0.0:
					continue
				if gx + 1 < tex_size:
					best = minf(best, dist_grid[row_off + gx + 1] + step_x)
				if gz + 1 < tex_size:
					var next_row := (gz + 1) * tex_size
					best = minf(best, dist_grid[next_row + gx] + step_z)
					if gx + 1 < tex_size:
						best = minf(best, dist_grid[next_row + gx + 1] + d_diag)
					if gx > 0:
						best = minf(best, dist_grid[next_row + gx - 1] + d_diag)
					if gx + 2 < tex_size:
						best = minf(best, dist_grid[next_row + gx + 2] + d_kx)
					if gx > 1:
						best = minf(best, dist_grid[next_row + gx - 2] + d_kx)
				if gz + 2 < tex_size:
					var next2_row := (gz + 2) * tex_size
					if gx + 1 < tex_size:
						best = minf(best, dist_grid[next2_row + gx + 1] + d_kz)
					if gx > 0:
						best = minf(best, dist_grid[next2_row + gx - 1] + d_kz)
				dist_grid[row_off + gx] = best

	# 3. Encode >= 25% ball lie resistance mask:
	# In range.gd: reduction = 0.10 + 0.20 * clampf(d / 50.0, 0.0, 1.0)
	# reduction >= 0.25 occurs where d = min(d_fairway, d_green) >= 37.5 meters.
	var pixels := PackedByteArray()
	pixels.resize(total_cells)
	for idx in range(total_cells):
		if tee_mask[idx] != 0:
			pixels[idx] = 0
			continue
		var d: float = dist_grid[idx]
		var w: float = smoothstep(36.0, 38.5, d)
		pixels[idx] = int(clampf(round(w * 255.0), 0.0, 255.0))

	var img := Image.create_from_data(tex_size, tex_size, false, Image.FORMAT_L8, pixels)
	terrain.set_meta("deep_rough_image", img)
	return ImageTexture.create_from_image(img)


static func _seed_triangle_on_dist_grid(
	dist_grid: PackedFloat32Array,
	tex_size: int,
	min_x: float,
	min_z: float,
	step_x: float,
	step_z: float,
	inv_w: float,
	inv_d: float,
	a: Vector2,
	b: Vector2,
	c: Vector2
) -> void:
	var gax := (a.x - min_x) * inv_w
	var gaz := (a.y - min_z) * inv_d
	var gbx := (b.x - min_x) * inv_w
	var gbz := (b.y - min_z) * inv_d
	var gcx := (c.x - min_x) * inv_w
	var gcz := (c.y - min_z) * inv_d

	var x0 := clampi(int(floor(minf(gax, minf(gbx, gcx)))), 0, tex_size - 1)
	var x1 := clampi(int(ceil(maxf(gax, maxf(gbx, gcx)))), 0, tex_size - 1)
	var z0 := clampi(int(floor(minf(gaz, minf(gbz, gcz)))), 0, tex_size - 1)
	var z1 := clampi(int(ceil(maxf(gaz, maxf(gbz, gcz)))), 0, tex_size - 1)

	dist_grid[clampi(int(round(gaz)), 0, tex_size - 1) * tex_size + clampi(int(round(gax)), 0, tex_size - 1)] = 0.0
	dist_grid[clampi(int(round(gbz)), 0, tex_size - 1) * tex_size + clampi(int(round(gbx)), 0, tex_size - 1)] = 0.0
	dist_grid[clampi(int(round(gcz)), 0, tex_size - 1) * tex_size + clampi(int(round(gcx)), 0, tex_size - 1)] = 0.0

	for gz in range(z0, z1 + 1):
		var wz := min_z + float(gz) * step_z
		var row_off := gz * tex_size
		for gx in range(x0, x1 + 1):
			if dist_grid[row_off + gx] <= 0.0:
				continue
			var wx := min_x + float(gx) * step_x
			if Geometry2D.point_is_inside_triangle(Vector2(wx, wz), a, b, c):
				dist_grid[row_off + gx] = 0.0


static func _mark_triangle_on_mask(
	mask: PackedByteArray,
	tex_size: int,
	min_x: float,
	min_z: float,
	inv_w: float,
	inv_d: float,
	a: Vector2,
	b: Vector2,
	c: Vector2,
	pad_cells: int
) -> void:
	var gax := (a.x - min_x) * inv_w
	var gaz := (a.y - min_z) * inv_d
	var gbx := (b.x - min_x) * inv_w
	var gbz := (b.y - min_z) * inv_d
	var gcx := (c.x - min_x) * inv_w
	var gcz := (c.y - min_z) * inv_d

	var x0 := clampi(int(floor(minf(gax, minf(gbx, gcx)))) - pad_cells, 0, tex_size - 1)
	var x1 := clampi(int(ceil(maxf(gax, maxf(gbx, gcx)))) + pad_cells, 0, tex_size - 1)
	var z0 := clampi(int(floor(minf(gaz, minf(gbz, gcz)))) - pad_cells, 0, tex_size - 1)
	var z1 := clampi(int(ceil(maxf(gaz, maxf(gbz, gcz)))) + pad_cells, 0, tex_size - 1)

	for gz in range(z0, z1 + 1):
		var row_off := gz * tex_size
		for gx in range(x0, x1 + 1):
			mask[row_off + gx] = 1


static func _build_thick_rough_bushes(scene_root: Node, height_info: Dictionary, persist_for_save: bool) -> int:
	if scene_root.get_node_or_null("ThickRoughBushes") != null:
		return 0

	var features := _extract_course_features(scene_root)
	var min_x: float = height_info.get("min_x", -300.0) + 10.0
	var max_x: float = height_info.get("max_x", 300.0) - 10.0
	var min_z: float = height_info.get("min_z", -300.0) + 10.0
	var max_z: float = height_info.get("max_z", 300.0) - 10.0

	var bush_mesh_paths := [
		"res://addons/shapespark-low-poly-exterior-plants/meshes/bush-01-mesh.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/bush-02-mesh.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/bush-03-mesh.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/bush-04-mesh.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/meshes/bush-05-mesh.tscn"
	]

	var bush_meshes: Array[Mesh] = []
	for bp in bush_mesh_paths:
		if ResourceLoader.exists(bp):
			var pscn := load(bp) as PackedScene
			if pscn != null:
				var inst = pscn.instantiate()
				if inst != null:
					if inst is MeshInstance3D and inst.mesh != null:
						bush_meshes.append(inst.mesh)
					else:
						for ch in inst.get_children():
							if ch is MeshInstance3D and ch.mesh != null:
								bush_meshes.append(ch.mesh)
								break
					inst.free()

	if bush_meshes.is_empty():
		return 0

	var placed_bushes: Array[Vector2] = []
	var bush_type_xforms: Array[Array] = []
	for m in range(bush_meshes.size()):
		bush_type_xforms.append([])

	var rng := RandomNumberGenerator.new()
	rng.seed = 882244

	var tree_positions: Array = features.get("tree_positions", [])
	var step := 12.0
	var z := min_z
	while z <= max_z:
		var x := min_x
		while x <= max_x:
			var jx := x + rng.randf_range(-3.5, 3.5)
			var jz := z + rng.randf_range(-3.5, 3.5)
			var pt := Vector2(jx, jz)

			# Sporadic probability in thick rough
			if rng.randf() < 0.38 and _is_point_in_thick_rough(pt, features, height_info, 18.0, 15.0):
				# Don't place on top of tree trunks
				var near_tree := false
				for tp in tree_positions:
					if (tp as Vector2).distance_squared_to(pt) < 9.0:
						near_tree = true
						break

				# Keep spacing between bushes
				var near_other_bush := false
				if not near_tree:
					for pb in placed_bushes:
						if pb.distance_squared_to(pt) < 100.0: # 10m minimum spacing
							near_other_bush = true
							break

				if not near_tree and not near_other_bush:
					placed_bushes.append(pt)
					var wy := _sample_height(jx, jz, height_info)
					var rot_y := rng.randf_range(0.0, TAU)
					var s := rng.randf_range(1.15, 2.25)
					var xf := Transform3D(Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s)), Vector3(jx, wy, jz))
					var type_idx := rng.randi() % bush_meshes.size()
					bush_type_xforms[type_idx].append(xf)
			x += step
		z += step

	var total_placed := placed_bushes.size()
	if total_placed == 0:
		return 0

	var container := Node3D.new()
	container.name = "ThickRoughBushes"
	scene_root.add_child(container)
	if persist_for_save:
		container.owner = scene_root

	for t_idx in range(bush_meshes.size()):
		var xforms: Array = bush_type_xforms[t_idx]
		if xforms.is_empty():
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = false
		mm.mesh = bush_meshes[t_idx]
		mm.instance_count = xforms.size()

		var b_buf := PackedFloat32Array()
		b_buf.resize(xforms.size() * 12)
		for i in range(xforms.size()):
			var xf: Transform3D = xforms[i]
			var b_idx := i * 12
			b_buf[b_idx + 0] = xf.basis.x.x
			b_buf[b_idx + 1] = xf.basis.y.x
			b_buf[b_idx + 2] = xf.basis.z.x
			b_buf[b_idx + 3] = xf.origin.x
			b_buf[b_idx + 4] = xf.basis.x.y
			b_buf[b_idx + 5] = xf.basis.y.y
			b_buf[b_idx + 6] = xf.basis.y.z
			b_buf[b_idx + 7] = xf.origin.y
			b_buf[b_idx + 8] = xf.basis.x.z
			b_buf[b_idx + 9] = xf.basis.y.z
			b_buf[b_idx + 10] = xf.basis.z.z
			b_buf[b_idx + 11] = xf.origin.z
			mm.set_instance_transform(i, xf)
		mm.buffer = b_buf

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "ThickRoughBushMesh_%d" % t_idx
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 260.0
		mmi.visibility_range_end_margin = 35.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		container.add_child(mmi)
		if persist_for_save:
			mmi.owner = scene_root

	return total_placed


static func _extract_course_features(scene_root: Node) -> Dictionary:
	var features := {
		"fairways": [],
		"greens": [],
		"tees": [],
		"bunkers": [],
		"water": [],
		"mapped_rough": [],
		"cart_paths": [],
		"hole_lines": [],
		"hole_paths": [],
		"tree_positions": []
	}

	for child in scene_root.find_children("*", "CollisionObject3D", true, false):
		var cname := child.name.to_lower()
		var poly := PackedVector2Array()

		if child.has_meta("boundary_polygon"):
			var p_meta = child.get_meta("boundary_polygon")
			if p_meta is PackedVector2Array:
				poly = p_meta
			elif p_meta is Array:
				for p in p_meta:
					if p is Vector2:
						poly.append(p)
			if poly.size() >= 3:
				var world_poly := PackedVector2Array()
				var child_xform: Transform3D = (child as Node3D).transform
				for pt in poly:
					var wp := child_xform * Vector3(pt.x, 0.0, pt.y)
					world_poly.append(Vector2(wp.x, wp.z))
				poly = world_poly

		if poly.size() < 3:
			for sub in child.get_children():
				if sub is CollisionPolygon3D and (sub as CollisionPolygon3D).polygon.size() >= 3:
					var cp := sub as CollisionPolygon3D
					var world_poly := PackedVector2Array()
					for pt in cp.polygon:
						var wp := (child as Node3D).transform * (cp.transform * Vector3(pt.x, 0.0, pt.y))
						world_poly.append(Vector2(wp.x, wp.z))
					poly = world_poly
					break
				elif sub is CollisionShape3D and (sub as CollisionShape3D).shape != null:
					var cs := sub as CollisionShape3D
					if cs.shape is ConcavePolygonShape3D:
						var faces := (cs.shape as ConcavePolygonShape3D).get_faces()
						var boundary := _extract_boundary_polygon_from_faces(faces, (child as Node3D).transform * cs.transform)
						if boundary.size() >= 3:
							poly = boundary
							break

		if poly.size() >= 3:
			var min_p := poly[0]
			var max_p := poly[0]
			for p in poly:
				min_p.x = minf(min_p.x, p.x)
				min_p.y = minf(min_p.y, p.y)
				max_p.x = maxf(max_p.x, p.x)
				max_p.y = maxf(max_p.y, p.y)
			var aabb := Rect2(min_p, max_p - min_p)
			var entry := { "poly": poly, "aabb": aabb }

			var st: int = int(child.get_meta("surface_type", -1))
			var is_sand: bool = bool(child.get_meta("is_sand", false))
			var is_wat: bool = bool(child.get_meta("is_water", false))

			if is_wat or cname.begins_with("water") or cname.contains("water"):
				features["water"].append(entry)
			elif is_sand or st == 5 or cname.begins_with("bunker") or cname.contains("bunker"):
				features["bunkers"].append(entry)
			elif st == 4 or cname.begins_with("green") or cname.contains("green"):
				features["greens"].append(entry)
			elif cname.begins_with("tee") or cname.contains("teebox"):
				features["tees"].append(entry)
			elif st == 0 or cname.begins_with("fairway") or cname.contains("fairway"):
				features["fairways"].append(entry)
			elif cname.begins_with("rough_") or bool(child.get_meta("is_mapped_rough", false)):
				features["mapped_rough"].append(entry)

	# Water meshes
	for child in scene_root.get_children():
		if child is MeshInstance3D and child.name.to_lower().begins_with("water"):
			var mi := child as MeshInstance3D
			if mi.mesh != null and mi.mesh.get_surface_count() > 0:
				var arrays := mi.mesh.surface_get_arrays(0)
				if arrays.size() > Mesh.ARRAY_VERTEX:
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					if verts.size() >= 3:
						var poly := PackedVector2Array()
						var min_p := Vector2(verts[0].x, verts[0].z)
						var max_p := min_p
						for v in verts:
							var p := Vector2(v.x, v.z)
							poly.append(p)
							min_p.x = minf(min_p.x, p.x)
							min_p.y = minf(min_p.y, p.y)
							max_p.x = maxf(max_p.x, p.x)
							max_p.y = maxf(max_p.y, p.y)
						features["water"].append({ "poly": poly, "aabb": Rect2(min_p, max_p - min_p) })

	# Cart paths
	if scene_root.has_meta("cart_path_polylines"):
		features["cart_paths"] = scene_root.get_meta("cart_path_polylines")
	else:
		features["cart_paths"] = _synthesize_hole_cart_paths(scene_root)

	# Hole lines and line-of-play paths
	if scene_root.has_meta("hole_paths"):
		var hpaths = scene_root.get_meta("hole_paths")
		if hpaths is Array:
			for p in hpaths:
				var pts: Array[Vector2] = []
				if p is PackedVector2Array:
					for pt in p: pts.append(pt)
				elif p is Array:
					for pt in p:
						if pt is Vector2: pts.append(pt)
						elif pt is Array and pt.size() >= 2: pts.append(Vector2(pt[0], pt[1]))
				if pts.size() >= 2:
					features["hole_paths"].append(pts)
					features["hole_lines"].append({ "p0": pts[0], "p1": pts[-1], "dist": pts[0].distance_to(pts[-1]) })

	# Also check course.json if present on course manager or adjacent to scene file
	if features["hole_paths"].is_empty():
		var json_path := ""
		if scene_root.is_inside_tree():
			var course_mgr := scene_root.get_node_or_null("/root/CourseManager")
			if course_mgr != null and course_mgr.has_method("get_current_config_path"):
				json_path = course_mgr.get_current_config_path()
		if json_path.is_empty() and scene_root.scene_file_path != "":
			json_path = scene_root.scene_file_path.get_base_dir() + "/course.json"
		if not json_path.is_empty() and FileAccess.file_exists(json_path):
			var f := FileAccess.open(json_path, FileAccess.READ)
			if f != null:
				var parsed = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary and parsed.has("Hole Info"):
					var hole_info_dict: Dictionary = parsed["Hole Info"]
					for hk in hole_info_dict.keys():
						var hd = hole_info_dict[hk]
						if hd is Dictionary and hd.has("Hole Path"):
							var hp_arr = hd["Hole Path"]
							if hp_arr is Array and hp_arr.size() >= 2:
								var pts: Array[Vector2] = []
								for pt_val in hp_arr:
									if pt_val is Array and pt_val.size() >= 2:
										pts.append(Vector2(float(pt_val[0]), float(pt_val[1])))
								if pts.size() >= 2:
									features["hole_paths"].append(pts)
									features["hole_lines"].append({ "p0": pts[0], "p1": pts[-1], "dist": pts[0].distance_to(pts[-1]) })

	for child in scene_root.get_children():
		if child.name.begins_with("Hole_"):
			var tee := child.get_node_or_null("TeeSpawn") as Node3D
			if tee == null: tee = child.get_node_or_null("Tee") as Node3D
			var target := child.get_node_or_null("TargetPoint") as Node3D
			if target == null: target = child.get_node_or_null("Flag") as Node3D
			if tee != null and target != null:
				var p0 := Vector2(tee.position.x, tee.position.z)
				var p1 := Vector2(target.position.x, target.position.z)
				features["hole_lines"].append({ "p0": p0, "p1": p1, "dist": p0.distance_to(p1) })
				features["hole_paths"].append([p0, p1])

	# Tree positions
	var mm_container := scene_root.get_node_or_null("MultiMeshFoliageContainer")
	if mm_container != null and mm_container.has_meta("tree_records"):
		var records: Array = mm_container.get_meta("tree_records", [])
		for i in range(0, records.size(), 8):
			features["tree_positions"].append(Vector2(float(records[i]), float(records[i + 2])))
	else:
		for child in scene_root.find_children("Tree_*", "Node3D", true, false):
			features["tree_positions"].append(Vector2(child.position.x, child.position.z))

	return features


static func _is_point_in_thick_rough(pt: Vector2, features: Dictionary, height_info: Dictionary, fairway_buffer: float = 6.5, green_buffer: float = 7.5) -> bool:
	var min_x: float = height_info.get("min_x", -300.0)
	var max_x: float = height_info.get("max_x", 300.0)
	var min_z: float = height_info.get("min_z", -300.0)
	var max_z: float = height_info.get("max_z", 300.0)

	if pt.x < min_x + 4.0 or pt.x > max_x - 4.0 or pt.y < min_z + 4.0 or pt.y > max_z - 4.0:
		return false

	# Fairway buffer: must be outside fairway and beyond mapped fairway rough corridor
	for f in features.get("fairways", []):
		var aabb: Rect2 = f["aabb"]
		if pt.x >= aabb.position.x - fairway_buffer and pt.x <= aabb.end.x + fairway_buffer and \
		   pt.y >= aabb.position.y - fairway_buffer and pt.y <= aabb.end.y + fairway_buffer:
			if _distance_to_polygon_2d(pt, f["poly"]) < fairway_buffer:
				return false

	# Green buffer: must be outside green and beyond manicured green fringe/rough
	for g in features.get("greens", []):
		var aabb: Rect2 = g["aabb"]
		if pt.x >= aabb.position.x - green_buffer and pt.x <= aabb.end.x + green_buffer and \
		   pt.y >= aabb.position.y - green_buffer and pt.y <= aabb.end.y + green_buffer:
			if _distance_to_polygon_2d(pt, g["poly"]) < green_buffer:
				return false

	# Tee buffer
	var tee_buffer := 5.0
	for t in features.get("tees", []):
		var aabb: Rect2 = t["aabb"]
		if pt.x >= aabb.position.x - tee_buffer and pt.x <= aabb.end.x + tee_buffer and \
		   pt.y >= aabb.position.y - tee_buffer and pt.y <= aabb.end.y + tee_buffer:
			if _distance_to_polygon_2d(pt, t["poly"]) < tee_buffer:
				return false

	# Bunker buffer
	var bunker_buffer := 1.8
	for b in features.get("bunkers", []):
		var aabb: Rect2 = b["aabb"]
		if pt.x >= aabb.position.x - bunker_buffer and pt.x <= aabb.end.x + bunker_buffer and \
		   pt.y >= aabb.position.y - bunker_buffer and pt.y <= aabb.end.y + bunker_buffer:
			if _distance_to_polygon_2d(pt, b["poly"]) < bunker_buffer:
				return false

	# Water buffer
	var water_buffer := 2.0
	for w in features.get("water", []):
		var aabb: Rect2 = w["aabb"]
		if pt.x >= aabb.position.x - water_buffer and pt.x <= aabb.end.x + water_buffer and \
		   pt.y >= aabb.position.y - water_buffer and pt.y <= aabb.end.y + water_buffer:
			if _distance_to_polygon_2d(pt, w["poly"]) < water_buffer:
				return false

	# Explicit mapped rough exclusion: if explicit rough was mapped in OSM, thick rough is beyond it
	for mr in features.get("mapped_rough", []):
		var aabb: Rect2 = mr["aabb"]
		if pt.x >= aabb.position.x and pt.x <= aabb.end.x and pt.y >= aabb.position.y and pt.y <= aabb.end.y:
			if Geometry2D.is_point_in_polygon(pt, mr["poly"]):
				return false

	# Cart paths
	var path_buffer_sq := 2.5 * 2.5
	for path in features.get("cart_paths", []):
		var pts: PackedVector2Array = path as PackedVector2Array
		for i in range(pts.size() - 1):
			if _distance_squared_to_segment_2d(pt, pts[i], pts[i + 1]) < path_buffer_sq:
				return false

	# Fallback hole corridor check if no fairways were detected in scene
	if (features.get("fairways", []) as Array).is_empty():
		for hl in features.get("hole_lines", []):
			if _distance_squared_to_segment_2d(pt, hl["p0"], hl["p1"]) < (9.0 * 9.0):
				return false

	return true


static func _distance_to_polygon_2d(pt: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 99999.0
	if Geometry2D.is_point_in_polygon(pt, poly):
		return 0.0
	var min_d_sq := 99999999.0
	var n := poly.size()
	for i in range(n):
		var p1 := poly[i]
		var p2 := poly[(i + 1) % n]
		var d_sq := _distance_squared_to_segment_2d(pt, p1, p2)
		if d_sq < min_d_sq:
			min_d_sq = d_sq
	return sqrt(min_d_sq)


static func _distance_squared_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var proj := a + ab * t
	return p.distance_squared_to(proj)
