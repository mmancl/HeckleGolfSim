extends Node3D
class_name HighFidelityGrass

## HighFidelityGrass
## GPU-instanced 3D grass blade system for High graphics mode:
## 1. Immediate Golfer Address Turf (0m - 15m around ball/camera)
## 2. Tall Clumped Rough & Fescue Blades (around tee perimeter, rough borders, & bunker lips)
## 3. Updates active tee divot scar position & hole mowing alignment on UnifiedTerrain shader.

const ADDRESS_CLUSTER_COUNT: int = 900
const ROUGH_CLUMP_COUNT: int = 1100

var _scene_root: Node = null
var _terrain_mesh_inst: MeshInstance3D = null
var _address_mmi: MultiMeshInstance3D = null
var _rough_mmi: MultiMeshInstance3D = null
var _last_anchor_pos: Vector3 = Vector3(99999.0, 99999.0, 99999.0)
var _last_lie_type: String = ""
var _last_shot_reduction: float = 0.0
var _tracked_ball: Node3D = null
var _was_ball_moving: bool = false
var _cached_player: Node = null
var _update_timer: float = 0.0
var _terrain_min_xz: Vector2 = Vector2(-500.0, -500.0)
var _terrain_size_xz: Vector2 = Vector2(1000.0, 1000.0)
var _splat_tex: Texture2D = null
var _is_driving_range: bool = false
## Deep-rough blade field LOD (18 m / 0.45 m = 6,400 instances with smooth radial edge fade)
var deep_radius: float = 18.0
var deep_cell: float = 0.45
var _deep_mmi: MultiMeshInstance3D = null
var _deep_img: Image = null
var _splat_img: Image = null
var _bunker_polys: Array = []
var _water_polys: Array = []
var _cart_path_segments: Array = []
var _height_info: Dictionary = {}
var _deep_rough_generated: bool = false


func setup(scene_root: Node) -> void:
	_scene_root = scene_root
	if _scene_root == null:
		return

	_is_driving_range = MobilePerformance.is_driving_range_node(_scene_root)
	_discover_terrain()
	if not _is_driving_range:
		_build_deep_rough_multimesh()
	if is_inside_tree():
		_refresh_anchor(true)
	else:
		_deep_rough_generated = true


func _ready() -> void:
	if _scene_root != null:
		_refresh_anchor(true)


func _is_ball_moving() -> bool:
	var b := _find_ball()
	if b == null:
		return false
	if b.get("state") != null and int(b.get("state")) != 0:
		return true
	if b is CharacterBody3D and (b as CharacterBody3D).velocity.length_squared() > 0.05:
		return true
	return false


func _process(_delta: float) -> void:
	var ball_moving := _is_ball_moving()
	if _was_ball_moving and not ball_moving:
		_was_ball_moving = false
		_refresh_anchor(true)
		return
	_was_ball_moving = ball_moving

	# While the ball is in motion (hit / flight / roll), NEVER rebuild grass
	if ball_moving:
		return

	var p := _get_player_node()
	var cur_lie := str(p.get("current_lie_type")).to_lower() if p != null else ""
	var cur_red := float(p.get("current_shot_reduction")) if p != null else 0.0
	if cur_red <= 0.0 and p != null:
		cur_red = float(p.get("last_shot_reduction"))
	var b_node := _find_ball()
	if b_node != null and (cur_lie.is_empty() or cur_lie in ["teebox", "fairway"]):
		var b_lie = str(b_node.get("lie_type")).to_lower()
		if b_lie in ["rough", "deep_rough", "heavy_rough"]:
			cur_lie = b_lie
	if is_inside_tree():
		var mp_mgr = get_tree().root.get_node_or_null("MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty():
			var ap = mp_mgr.get_active_player()
			if not ap.is_empty():
				if cur_red <= 0.0:
					cur_red = float(ap.get("shot_reduction", 0.0))
				if cur_red <= 0.0:
					cur_red = float(ap.get("last_shot_reduction", 0.0))
				if cur_lie.is_empty() or cur_lie in ["teebox", "fairway"]:
					var ap_lie = str(ap.get("lie_type", "")).to_lower()
					if not ap_lie.is_empty():
						cur_lie = ap_lie
	var lie_changed := (cur_lie != _last_lie_type or absf(cur_red - _last_shot_reduction) > 0.01)
	if lie_changed:
		_refresh_anchor(true)


func _discover_terrain() -> void:
	if _scene_root == null:
		return
	for tname in ["UnifiedTerrain", "DynamicGround", "RoughGround", "Terrain", "TerrainMesh"]:
		_terrain_mesh_inst = _scene_root.find_child(tname, true, false) as MeshInstance3D
		if _terrain_mesh_inst != null:
			break

	if _terrain_mesh_inst != null and _terrain_mesh_inst.mesh != null:
		var aabb := _terrain_mesh_inst.mesh.get_aabb()
		var gx := _terrain_mesh_inst.global_position.x if _terrain_mesh_inst.is_inside_tree() else _terrain_mesh_inst.position.x
		var gz := _terrain_mesh_inst.global_position.z if _terrain_mesh_inst.is_inside_tree() else _terrain_mesh_inst.position.z
		_terrain_min_xz = Vector2(gx + aabb.position.x, gz + aabb.position.z)
		_terrain_size_xz = Vector2(maxf(aabb.size.x, 1.0), maxf(aabb.size.z, 1.0))

		var mat: Material = _terrain_mesh_inst.material_override
		if mat == null and _terrain_mesh_inst.mesh.get_surface_count() > 0:
			mat = _terrain_mesh_inst.mesh.surface_get_material(0)
		if mat is ShaderMaterial:
			_splat_tex = (mat as ShaderMaterial).get_shader_parameter("splat_map")
		if _splat_tex == null and _terrain_mesh_inst.has_meta("orig_splat_map"):
			_splat_tex = _terrain_mesh_inst.get_meta("orig_splat_map")

		_splat_img = null
		if _splat_tex != null:
			var img = _splat_tex.get_image()
			if img != null:
				if img.is_compressed():
					img = img.duplicate()
					img.decompress()
				_splat_img = img

	_bunker_polys.clear()
	_water_polys.clear()
	if _scene_root != null:
		for child in _scene_root.find_children("*", "CollisionObject3D", true, false):
			var cname := child.name.to_lower()
			var st: int = int(child.get_meta("surface_type", -1))
			var is_sand: bool = bool(child.get_meta("is_sand", false))
			var is_wat: bool = bool(child.get_meta("is_water", false)) or cname.begins_with("water") or cname.contains("water")
			if is_sand or st == 5 or cname.begins_with("bunker") or cname.contains("bunker"):
				var poly := PackedVector2Array()
				if child.has_meta("boundary_polygon"):
					var p_meta = child.get_meta("boundary_polygon")
					if p_meta is PackedVector2Array:
						poly = p_meta
					elif p_meta is Array:
						for pt in p_meta:
							if pt is Vector2:
								poly.append(pt)
				if poly.size() < 3:
					for sub in child.get_children():
						if sub is CollisionPolygon3D and (sub as CollisionPolygon3D).polygon.size() >= 3:
							poly = (sub as CollisionPolygon3D).polygon
							break
				if poly.size() >= 3:
					var child_xform: Transform3D = (child as Node3D).global_transform if (child as Node3D).is_inside_tree() else (child as Node3D).transform
					var world_poly := PackedVector2Array()
					var min_p := Vector2(99999.0, 99999.0)
					var max_p := Vector2(-99999.0, -99999.0)
					for pt in poly:
						var wp := child_xform * Vector3(pt.x, 0.0, pt.y)
						var p2 := Vector2(wp.x, wp.z)
						world_poly.append(p2)
						min_p.x = minf(min_p.x, p2.x)
						min_p.y = minf(min_p.y, p2.y)
						max_p.x = maxf(max_p.x, p2.x)
						max_p.y = maxf(max_p.y, p2.y)
					_bunker_polys.append({
						"poly": world_poly,
						"aabb": Rect2(min_p, max_p - min_p)
					})
			elif is_wat:
				var poly := PackedVector2Array()
				for meta_key in ["water_points", "boundary_polygon"]:
					if child.has_meta(meta_key):
						var p_meta = child.get_meta(meta_key)
						if p_meta is PackedVector2Array:
							poly = p_meta
						elif p_meta is Array:
							for pt in p_meta:
								if pt is Vector2:
									poly.append(pt)
						if poly.size() >= 3:
							break
				if poly.size() < 3:
					for sub in child.get_children():
						if sub is CollisionPolygon3D and (sub as CollisionPolygon3D).polygon.size() >= 3:
							poly = (sub as CollisionPolygon3D).polygon
							break
				if poly.size() >= 3:
					var child_xform: Transform3D = (child as Node3D).global_transform if (child as Node3D).is_inside_tree() else (child as Node3D).transform
					var world_poly := PackedVector2Array()
					var min_p := Vector2(99999.0, 99999.0)
					var max_p := Vector2(-99999.0, -99999.0)
					for pt in poly:
						var wp := child_xform * Vector3(pt.x, 0.0, pt.y)
						var p2 := Vector2(wp.x, wp.z)
						world_poly.append(p2)
						min_p.x = minf(min_p.x, p2.x)
						min_p.y = minf(min_p.y, p2.y)
						max_p.x = maxf(max_p.x, p2.x)
						max_p.y = maxf(max_p.y, p2.y)
					_water_polys.append({
						"poly": world_poly,
						"aabb": Rect2(min_p, max_p - min_p)
					})

		# 3. Collect cart path segments to prevent any rough grass from rendering inside cart paths
		_cart_path_segments.clear()
		if _scene_root.has_meta("cart_path_polylines"):
			var meta_lines = _scene_root.get_meta("cart_path_polylines")
			if meta_lines is Array:
				for raw_line in meta_lines:
					if (raw_line is PackedVector2Array or raw_line is Array) and raw_line.size() >= 2:
						var pts := PackedVector2Array()
						for p in raw_line:
							if p is Vector2:
								pts.append(p)
							elif p is Vector3:
								pts.append(Vector2(p.x, p.z))
						for i in range(pts.size() - 1):
							var a: Vector2 = pts[i]
							var b: Vector2 = pts[i + 1]
							var r := 1.55 # Cart path half-width (~1.25m) + grass clearance (~0.30m)
							var min_x = minf(a.x, b.x) - r
							var max_x = maxf(a.x, b.x) + r
							var min_y = minf(a.y, b.y) - r
							var max_y = maxf(a.y, b.y) + r
							_cart_path_segments.append({
								"a": a,
								"b": b,
								"radius": r,
								"aabb": Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
							})

		# Also extract ribbon geometry from any cartpath MeshInstance3D nodes
		for child in _scene_root.get_children():
			var cname := child.name.to_lower()
			if child is MeshInstance3D and (cname.begins_with("cartpath_") or cname == "cartpaths"):
				var mi := child as MeshInstance3D
				if mi.mesh is ArrayMesh and mi.mesh.get_surface_count() > 0:
					var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
					var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					if verts.size() >= 4:
						for i in range(0, verts.size() - 3, 2):
							var p0 := Vector2((verts[i].x + verts[i + 1].x) * 0.5, (verts[i].z + verts[i + 1].z) * 0.5)
							var p1 := Vector2((verts[i + 2].x + verts[i + 3].x) * 0.5, (verts[i + 2].z + verts[i + 3].z) * 0.5)
							var hw := maxf(1.55, verts[i].distance_to(verts[i + 1]) * 0.5 + 0.30)
							var min_x = minf(p0.x, p1.x) - hw
							var max_x = maxf(p0.x, p1.x) + hw
							var min_y = minf(p0.y, p1.y) - hw
							var max_y = maxf(p0.y, p1.y) + hw
							_cart_path_segments.append({
								"a": p0,
								"b": p1,
								"radius": hw,
								"aabb": Rect2(min_x, min_y, max_x - min_x, max_y - min_y)
							})


func _build_address_turf_multimesh() -> void:
	var shader := load("res://Courses/Environments/shaders/grass_blades_high.gdshader") as Shader
	if shader == null:
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("root_color", Color(0.14, 0.25, 0.10))
	mat.set_shader_parameter("tip_color", Color(0.36, 0.52, 0.22))
	mat.set_shader_parameter("dry_tip_color", Color(0.46, 0.48, 0.28))
	mat.set_shader_parameter("dry_tip_ratio", 0.08)
	mat.set_shader_parameter("wind_strength", 0.025)
	mat.set_shader_parameter("max_render_distance", 16.5)
	mat.set_shader_parameter("fade_start_distance", 10.5)
	if _splat_tex != null and not _is_driving_range:
		mat.set_shader_parameter("use_splat_mask", true)
		mat.set_shader_parameter("mask_allow_fairway", true)
		mat.set_shader_parameter("splat_map", _splat_tex)
		mat.set_shader_parameter("terrain_min_xz", _terrain_min_xz)
		mat.set_shader_parameter("terrain_size_xz", _terrain_size_xz)

	var cluster_mesh := _create_grass_clump_mesh(10, 0.22, 0.032, 0.055, 0.012, 0.04)
	cluster_mesh.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = cluster_mesh
	mm.instance_count = ADDRESS_CLUSTER_COUNT

	_address_mmi = MultiMeshInstance3D.new()
	_address_mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_address_mmi.name = "AddressTurfMultiMesh"
	_address_mmi.multimesh = mm
	_address_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_address_mmi)


func _build_rough_fescue_multimesh() -> void:
	var shader := load("res://Courses/Environments/shaders/grass_blades_high.gdshader") as Shader
	if shader == null:
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("root_color", Color(0.11, 0.21, 0.09))
	mat.set_shader_parameter("tip_color", Color(0.34, 0.50, 0.22))
	mat.set_shader_parameter("dry_tip_color", Color(0.58, 0.53, 0.33))
	mat.set_shader_parameter("dry_tip_ratio", 0.26)
	mat.set_shader_parameter("wind_strength", 0.085)
	mat.set_shader_parameter("max_render_distance", 34.0)
	mat.set_shader_parameter("fade_start_distance", 22.0)
	if _splat_tex != null and not _is_driving_range:
		mat.set_shader_parameter("use_splat_mask", true)
		mat.set_shader_parameter("mask_allow_fairway", false)
		mat.set_shader_parameter("splat_map", _splat_tex)
		mat.set_shader_parameter("terrain_min_xz", _terrain_min_xz)
		mat.set_shader_parameter("terrain_size_xz", _terrain_size_xz)

	var clump_mesh := _create_grass_clump_mesh(16, 0.42, 0.05, 0.11, 0.012, 0.08)
	clump_mesh.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = clump_mesh
	mm.instance_count = ROUGH_CLUMP_COUNT

	_rough_mmi = MultiMeshInstance3D.new()
	_rough_mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rough_mmi.name = "RoughFescueMultiMesh"
	_rough_mmi.multimesh = mm
	_rough_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rough_mmi)


func _find_ball() -> Node3D:
	if _scene_root != null:
		var p := _get_player_node()
		if p != null:
			var b = p.get("ball")
			if b is Node3D and is_instance_valid(b):
				return b as Node3D
	if is_inside_tree():
		var balls := get_tree().get_nodes_in_group("golf_ball")
		for b in balls:
			if b is Node3D and is_instance_valid(b):
				return b as Node3D
		var cp = get_tree().root.find_child("CoursePlay", true, false)
		if cp != null and cp.get("active_ball") is Node3D:
			var ab = cp.get("active_ball")
			if is_instance_valid(ab):
				return ab as Node3D
	if _scene_root != null:
		for candidate in ["GolfBall", "ball", "Ball"]:
			var node := _scene_root.find_child(candidate, true, false) as Node3D
			if node != null and is_instance_valid(node):
				return node
	return null


func _get_player_node() -> Node:
	# Cached: this is called every frame and the fallbacks below do recursive tree searches.
	if _cached_player != null and is_instance_valid(_cached_player) and _cached_player.is_inside_tree():
		return _cached_player
	_cached_player = _lookup_player_node()
	return _cached_player


func _lookup_player_node() -> Node:
	if _scene_root != null:
		var p := _scene_root.get_node_or_null("Player")
		if p != null:
			return p
		p = _scene_root.find_child("Player", true, false)
		if p != null:
			return p
	if is_inside_tree():
		var p := get_tree().root.find_child("Player", true, false)
		if p != null:
			return p
	return null


func _get_course_node() -> Node:
	if _scene_root != null:
		if _scene_root.has_method("get_distance_to_nearest_fairway"):
			return _scene_root
		for child in _scene_root.get_children():
			if child.has_method("get_distance_to_nearest_fairway"):
				return child
		var cp = _scene_root.get_node_or_null("CoursePlay") if _scene_root.name != "CoursePlay" else _scene_root
		if cp != null and cp.get("course_instance") != null and cp.course_instance.has_method("get_distance_to_nearest_fairway"):
			return cp.course_instance
	if is_inside_tree():
		var root = get_tree().root
		var cp = root.find_child("CoursePlay", true, false)
		if cp != null and cp.get("course_instance") != null and cp.course_instance.has_method("get_distance_to_nearest_fairway"):
			return cp.course_instance
		for candidate in root.find_children("*", "", true, false):
			if candidate.has_method("get_distance_to_nearest_fairway"):
				return candidate
	return null


func _on_ball_rest() -> void:
	_refresh_anchor(true)


func _refresh_anchor(force: bool) -> void:
	if _scene_root == null or not is_inside_tree():
		return

	var anchor := Vector3.ZERO
	var ball := _find_ball()
	if ball != null:
		anchor = ball.global_position
		if _tracked_ball != ball:
			if _tracked_ball != null and is_instance_valid(_tracked_ball) and _tracked_ball.is_connected("rest", _on_ball_rest):
				_tracked_ball.disconnect("rest", _on_ball_rest)
			_tracked_ball = ball
			if ball.has_signal("rest") and not ball.is_connected("rest", _on_ball_rest):
				ball.connect("rest", _on_ball_rest)
	else:
		var vp := get_viewport()
		if vp != null and vp.get_camera_3d() != null:
			anchor = vp.get_camera_3d().global_position

	var p := _get_player_node()
	var cur_lie := str(p.get("current_lie_type")).to_lower() if p != null else ""
	var cur_red := float(p.get("current_shot_reduction")) if p != null else 0.0
	if cur_red <= 0.0 and p != null:
		cur_red = float(p.get("last_shot_reduction"))
	if ball != null and (cur_lie.is_empty() or cur_lie in ["teebox", "fairway"]):
		var b_lie = str(ball.get("lie_type")).to_lower()
		if b_lie in ["rough", "deep_rough", "heavy_rough"]:
			cur_lie = b_lie
	if is_inside_tree():
		var mp_mgr = get_tree().root.get_node_or_null("MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty():
			var ap = mp_mgr.get_active_player()
			if not ap.is_empty():
				if cur_red <= 0.0:
					cur_red = float(ap.get("shot_reduction", 0.0))
				if cur_red <= 0.0:
					cur_red = float(ap.get("last_shot_reduction", 0.0))
				if cur_lie.is_empty() or cur_lie in ["teebox", "fairway"]:
					var ap_lie = str(ap.get("lie_type", "")).to_lower()
					if not ap_lie.is_empty():
						cur_lie = ap_lie
	if cur_red <= 0.0 and (cur_lie in ["rough", "deep_rough", "heavy_rough"] or cur_lie.is_empty()):
		var cnode = _get_course_node()
		if cnode != null and cnode.has_method("get_distance_to_nearest_fairway") and cnode.has_method("get_distance_to_nearest_green"):
			var df = cnode.get_distance_to_nearest_fairway(anchor)
			var dg = cnode.get_distance_to_nearest_green(anchor)
			var d = minf(df, dg)
			if d >= 36.0:
				cur_red = 0.10 + 0.20 * clampf(d / 50.0, 0.0, 1.0)
				if cur_lie.is_empty() or cur_lie in ["teebox", "fairway"]:
					cur_lie = "rough"
	var lie_changed := (cur_lie != _last_lie_type or absf(cur_red - _last_shot_reduction) > 0.01)

	if not force and not lie_changed and anchor.distance_squared_to(_last_anchor_pos) < 4.0:
		return
	if anchor.distance_squared_to(_last_anchor_pos) < 0.25 and cur_lie == _last_lie_type and absf(cur_red - _last_shot_reduction) <= 0.01:
		return
	_last_anchor_pos = anchor
	_last_lie_type = cur_lie
	_last_shot_reduction = cur_red

	# Update tee divot position & hole mowing alignment on UnifiedTerrain if on High
	_update_terrain_tee_and_mow_uniforms(anchor)

	# Pre-filter all course hazards once within 52m bounding box for all multimeshes
	var max_r := 52.0
	var anchor_rect := Rect2(anchor.x - max_r, anchor.z - max_r, max_r * 2.0, max_r * 2.0)
	var nearby_bunkers: Array = []
	for b in _bunker_polys:
		if anchor_rect.intersects(b["aabb"]):
			nearby_bunkers.append(b)
	var nearby_water: Array = []
	for w in _water_polys:
		if anchor_rect.intersects(w["aabb"]):
			nearby_water.append(w)
	var nearby_paths: Array = []
	for cp in _cart_path_segments:
		if anchor_rect.intersects(cp["aabb"]):
			nearby_paths.append(cp)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(floor(anchor.x * 0.5)) * 73856093 ^ int(floor(anchor.z * 0.5)) * 19349663

	# Snap anchor grid to 2m steps so grass patches stay world-anchored when camera nudges slightly
	var grid_center := Vector3(snappedf(anchor.x, 2.0), anchor.y, snappedf(anchor.z, 2.0))

	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)

	if _address_mmi != null and _address_mmi.multimesh != null:
		var mm := _address_mmi.multimesh
		for i in range(ADDRESS_CLUSTER_COUNT):
			var r := sqrt(rng.randf()) * 14.5
			var theta := rng.randf_range(0.0, TAU)
			var wx := grid_center.x + cos(theta) * r
			var wz := grid_center.z + sin(theta) * r
			if _is_in_bunker_or_hazard(wx, wz, nearby_bunkers, nearby_paths, nearby_water):
				mm.set_instance_transform(i, hidden)
				continue
			var wy := _sample_ground_y(wx, wz, anchor.y)
			var rot_y := rng.randf_range(0.0, TAU)
			var s := rng.randf_range(0.85, 1.25)
			var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(wx, wy, wz)))
			var tint := Color(rng.randf_range(0.92, 1.06), rng.randf_range(0.95, 1.05), rng.randf_range(0.90, 1.04), rng.randf_range(0.05, 0.99))
			mm.set_instance_custom_data(i, tint)

	if _rough_mmi != null and _rough_mmi.multimesh != null:
		var mm := _rough_mmi.multimesh
		for i in range(ROUGH_CLUMP_COUNT):
			if _is_driving_range:
				# No long grass or rough clumps on driving range
				mm.set_instance_transform(i, hidden)
				continue
			var r := 2.2 + sqrt(rng.randf()) * 48.0
			var theta := rng.randf_range(0.0, TAU)
			var wx := grid_center.x + cos(theta) * r
			var wz := grid_center.z + sin(theta) * r
			if _is_in_bunker_or_hazard(wx, wz, nearby_bunkers, nearby_paths, nearby_water):
				mm.set_instance_transform(i, hidden)
				continue
			var wy := _sample_ground_y(wx, wz, anchor.y)
			var rot_y := rng.randf_range(0.0, TAU)
			var s := rng.randf_range(0.80, 1.38)
			var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(wx, wy, wz)))
			var tint := Color(rng.randf_range(0.88, 1.08), rng.randf_range(0.92, 1.06), rng.randf_range(0.86, 1.02), rng.randf_range(0.05, 0.99))
			mm.set_instance_custom_data(i, tint)

	if not _is_driving_range and _deep_mmi != null and _deep_mmi.multimesh != null:
		_update_deep_rough_blades(anchor, nearby_bunkers, nearby_paths, nearby_water)


func _build_deep_rough_multimesh() -> void:
	var shader := load("res://Courses/Environments/shaders/grass_blades_high.gdshader") as Shader
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	# Calibrated to authentic lush deep rough from golf photography (Image 2):
	mat.set_shader_parameter("root_color", Color(0.16, 0.25, 0.09))
	mat.set_shader_parameter("tip_color", Color(0.35, 0.50, 0.18))
	mat.set_shader_parameter("dry_tip_color", Color(0.44, 0.52, 0.22))
	mat.set_shader_parameter("dry_tip_ratio", 0.08)
	mat.set_shader_parameter("backlight_color", Color(0.36, 0.54, 0.18))
	mat.set_shader_parameter("backlight_strength", 0.85)
	mat.set_shader_parameter("roughness", 0.54)
	mat.set_shader_parameter("specular", 0.18)
	mat.set_shader_parameter("wind_strength", 0.028)
	mat.set_shader_parameter("max_render_distance", 50.0)
	mat.set_shader_parameter("fade_start_distance", 35.0)
	if _splat_tex != null:
		mat.set_shader_parameter("use_splat_mask", true)
		mat.set_shader_parameter("mask_allow_fairway", false)
		mat.set_shader_parameter("splat_map", _splat_tex)
		mat.set_shader_parameter("terrain_min_xz", _terrain_min_xz)
		mat.set_shader_parameter("terrain_size_xz", _terrain_size_xz)

	# Dense 3-tier turf clump: 20 thatch blades, 22 mid blades, 16 canopy blades (58 slender arched blades)
	var clump_mesh := _create_dense_deep_rough_mesh(0.28, 0.011, 0.045)
	clump_mesh.surface_set_material(0, mat)

	var side := int(deep_radius * 2.0 / deep_cell)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = clump_mesh
	mm.instance_count = side * side

	_deep_mmi = MultiMeshInstance3D.new()
	_deep_mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_deep_mmi.name = "DeepRoughBladesMultiMesh"
	_deep_mmi.top_level = true
	_deep_mmi.multimesh = mm
	_deep_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_deep_mmi.extra_cull_margin = 150.0
	_deep_mmi.visibility_range_end = 140.0
	_deep_mmi.visibility_range_end_margin = 25.0
	_deep_mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_deep_mmi.visible = true
	add_child(_deep_mmi)


static func _cell_hash(a: int, b: int, salt: float) -> float:
	return fposmod(sin(float(a) * 12.9898 + float(b) * 78.233 + salt) * 43758.5453, 1.0)


func _is_on_cart_path(wx: float, wz: float, nearby_segments = null) -> bool:
	var segs: Array = nearby_segments if nearby_segments != null else _cart_path_segments
	if segs.is_empty():
		return false
	var pt := Vector2(wx, wz)
	for seg in segs:
		var aabb: Rect2 = seg["aabb"]
		if pt.x >= aabb.position.x and pt.x <= aabb.end.x and \
		   pt.y >= aabb.position.y and pt.y <= aabb.end.y:
			var a: Vector2 = seg["a"]
			var b: Vector2 = seg["b"]
			var closest := Geometry2D.get_closest_point_to_segment(pt, a, b)
			var r: float = seg["radius"]
			if pt.distance_squared_to(closest) <= r * r:
				return true
	return false


func _is_in_bunker_or_hazard(wx: float, wz: float, nearby_bunkers = null, nearby_cart_paths = null, nearby_water = null) -> bool:
	if _is_on_cart_path(wx, wz, nearby_cart_paths):
		return true
	if _splat_img != null and _terrain_size_xz.x > 1.0 and _terrain_size_xz.y > 1.0:
		var px := clampi(int((wx - _terrain_min_xz.x) / _terrain_size_xz.x * float(_splat_img.get_width() - 1)), 0, _splat_img.get_width() - 1)
		var pz := clampi(int((wz - _terrain_min_xz.y) / _terrain_size_xz.y * float(_splat_img.get_height() - 1)), 0, _splat_img.get_height() - 1)
		var c := _splat_img.get_pixel(px, pz)
		# B channel = Bunker/Sand, R channel = Green
		# Disallow only true interior of sand trap (c.b > 0.45) or green (c.r > 0.45)
		if c.b > 0.45 or c.r > 0.45:
			return true

	var pt := Vector2(wx, wz)
	var bunkers_to_check: Array = nearby_bunkers if nearby_bunkers != null else _bunker_polys
	for b in bunkers_to_check:
		var aabb: Rect2 = b["aabb"]
		if pt.x >= aabb.position.x and pt.x <= aabb.end.x and \
		   pt.y >= aabb.position.y and pt.y <= aabb.end.y:
			if Geometry2D.is_point_in_polygon(pt, b["poly"]):
				return true
	var water_to_check: Array = nearby_water if nearby_water != null else _water_polys
	for w in water_to_check:
		var aabb: Rect2 = w["aabb"]
		if pt.x >= aabb.position.x - 0.25 and pt.x <= aabb.end.x + 0.25 and \
		   pt.y >= aabb.position.y - 0.25 and pt.y <= aabb.end.y + 0.25:
			if Geometry2D.is_point_in_polygon(pt, w["poly"]):
				return true
	return false


func _is_anchor_in_deep_rough(anchor: Vector3) -> bool:
	# 1. Immediate exclusion if anchor is on cart path, inside a bunker, or hazard
	if _is_on_cart_path(anchor.x, anchor.z) or _is_in_bunker_or_hazard(anchor.x, anchor.z):
		return false

	var ball := _find_ball()
	if ball != null:
		var b_lie := str(ball.get("lie_type")).to_lower()
		if b_lie in ["sand", "bunker", "green", "fringe", "water", "penalty"]:
			return false

	var p := _get_player_node()
	var lie: String = ""
	var red: float = 0.0

	if p != null:
		lie = str(p.get("current_lie_type")).to_lower()
		red = float(p.get("current_shot_reduction"))
		if red <= 0.0:
			red = float(p.get("last_shot_reduction"))

	if is_inside_tree():
		var mp_mgr = get_tree().root.get_node_or_null("MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty():
			var ap = mp_mgr.get_active_player()
			if not ap.is_empty():
				if red <= 0.0:
					red = float(ap.get("shot_reduction", 0.0))
				if red <= 0.0:
					red = float(ap.get("last_shot_reduction", 0.0))
				if lie.is_empty() or lie in ["teebox", "fairway"]:
					var ap_lie = str(ap.get("lie_type", "")).to_lower()
					if not ap_lie.is_empty():
						lie = ap_lie

	if ball != null and (lie.is_empty() or lie in ["teebox", "fairway"]):
		var b_lie = str(ball.get("lie_type")).to_lower()
		if not b_lie.is_empty():
			lie = b_lie

	# Immediate exclusion if current surface is specifically sand, bunker, green, fringe, or penalty
	if lie in ["sand", "bunker", "green", "fringe", "water", "penalty"]:
		return false

	# If resistance is >= 24.5% in rough, this is definitely deep rough
	if (lie == "rough" or lie == "deep_rough" or lie == "heavy_rough") and red >= 0.245:
		return true

	# Check course node geometry and distances
	var course_node = _get_course_node()
	if course_node != null and course_node.has_method("get_distance_to_nearest_fairway") and course_node.has_method("get_distance_to_nearest_green"):
		var df: float = course_node.get_distance_to_nearest_fairway(anchor)
		var dg: float = course_node.get_distance_to_nearest_green(anchor)
		# Never activate if strictly inside fairway (<= 0.5m) or green (<= 0.001m)
		if df <= 0.5 or dg <= 0.001:
			return false
		if course_node.has_method("get_distance_to_nearest_teebox") and course_node.get_distance_to_nearest_teebox(anchor) <= 1.5:
			return false
		var d := minf(df, dg)
		if d >= 36.0:
			return true
		var calc_red = 0.10 + 0.20 * clampf(d / 50.0, 0.0, 1.0)
		if calc_red >= 0.245 and (lie == "rough" or lie == "deep_rough" or lie == "heavy_rough" or lie.is_empty()):
			return true

	if _deep_img != null and _terrain_size_xz.x > 1.0 and _terrain_size_xz.y > 1.0:
		var px := clampi(int((anchor.x - _terrain_min_xz.x) / _terrain_size_xz.x * float(_deep_img.get_width() - 1)), 0, _deep_img.get_width() - 1)
		var pz := clampi(int((anchor.z - _terrain_min_xz.y) / _terrain_size_xz.y * float(_deep_img.get_height() - 1)), 0, _deep_img.get_height() - 1)
		if _deep_img.get_pixel(px, pz).r > 0.15:
			return true

	return false


func _update_deep_rough_blades(anchor: Vector3 = Vector3.ZERO, prefiltered_bunkers = null, prefiltered_paths = null, prefiltered_water = null) -> void:
	if _deep_mmi == null or _deep_mmi.multimesh == null:
		return
	if _deep_img == null:
		if _terrain_mesh_inst != null and _terrain_mesh_inst.has_meta("deep_rough_image"):
			_deep_img = _terrain_mesh_inst.get_meta("deep_rough_image") as Image
		elif _scene_root != null and _scene_root.has_meta("deep_rough_image"):
			_deep_img = _scene_root.get_meta("deep_rough_image") as Image
		if _deep_img == null and _scene_root != null:
			CourseDetailEnhancer.ensure_deep_rough_map(_scene_root, _terrain_mesh_inst)
			if _terrain_mesh_inst != null and _terrain_mesh_inst.has_meta("deep_rough_image"):
				_deep_img = _terrain_mesh_inst.get_meta("deep_rough_image") as Image

	_deep_mmi.visible = true

	var anchor_is_deep := _is_anchor_in_deep_rough(anchor)

	var nearby_bunkers = prefiltered_bunkers
	var nearby_paths = prefiltered_paths
	var nearby_water = prefiltered_water
	if nearby_bunkers == null or nearby_paths == null or nearby_water == null:
		var margin := deep_radius + 2.0
		var anchor_rect := Rect2(anchor.x - margin, anchor.z - margin, margin * 2.0, margin * 2.0)
		if nearby_bunkers == null:
			nearby_bunkers = []
			for b in _bunker_polys:
				if anchor_rect.intersects(b["aabb"]):
					nearby_bunkers.append(b)
		if nearby_water == null:
			nearby_water = []
			for w in _water_polys:
				if anchor_rect.intersects(w["aabb"]):
					nearby_water.append(w)
		if nearby_paths == null:
			nearby_paths = []
			for cp in _cart_path_segments:
				if anchor_rect.intersects(cp["aabb"]):
					nearby_paths.append(cp)

	var side := int(deep_radius * 2.0 / deep_cell)
	var half := side / 2
	var cx := int(round(anchor.x / deep_cell))
	var cz := int(round(anchor.z / deep_cell))

	# Coarse local ground-height lattice (2.5 m) with bilinear lookup
	var h_step := 2.5
	var h_n := int(ceil(deep_radius * 2.0 / h_step)) + 2
	var ox := float(cx - half) * deep_cell
	var oz := float(cz - half) * deep_cell
	var heights := PackedFloat32Array()
	heights.resize(h_n * h_n)
	for i in range(h_n):
		var wz := oz + float(i) * h_step
		for j in range(h_n):
			var wx := ox + float(j) * h_step
			heights[i * h_n + j] = _sample_ground_y(wx, wz, anchor.y)

	var r2 := deep_radius * deep_radius
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var mm := _deep_mmi.multimesh
	var total_slots := mm.instance_count
	var idx := 0

	var img_w_m1 := (_deep_img.get_width() - 1) if _deep_img != null else 0
	var img_h_m1 := (_deep_img.get_height() - 1) if _deep_img != null else 0

	for iz in range(side):
		var gz := cz - half + iz
		for ix in range(side):
			if idx >= total_slots:
				break
			var gx := cx - half + ix
			var wx := (float(gx) + _cell_hash(gx, gz, 1.0)) * deep_cell
			var wz := (float(gz) + _cell_hash(gz, gx, 2.0)) * deep_cell
			var dx := wx - anchor.x
			var dz := wz - anchor.z
			var d2 := dx * dx + dz * dz
			var ok := d2 < r2

			if ok:
				if not anchor_is_deep:
					# Fast path: check deep rough map first - if pixel is not deep rough, skip immediately!
					if _deep_img != null and _terrain_size_xz.x > 1.0 and _terrain_size_xz.y > 1.0:
						var px := clampi(int((wx - _terrain_min_xz.x) / _terrain_size_xz.x * float(img_w_m1)), 0, img_w_m1)
						var pz := clampi(int((wz - _terrain_min_xz.y) / _terrain_size_xz.y * float(img_h_m1)), 0, img_h_m1)
						if _deep_img.get_pixel(px, pz).r <= 0.15:
							ok = false
					else:
						var cnode = _get_course_node()
						if cnode != null and cnode.has_method("get_distance_to_nearest_fairway") and cnode.has_method("get_distance_to_nearest_green"):
							var df = cnode.get_distance_to_nearest_fairway(Vector3(wx, 0.0, wz))
							var dg = cnode.get_distance_to_nearest_green(Vector3(wx, 0.0, wz))
							if minf(df, dg) < 36.0:
								ok = false
						else:
							ok = false
				else:
					# Ball is resting in deep rough. Suppress if cell is strictly inside core fairway (splat green channel > 0.60)
					if _splat_img != null and _terrain_size_xz.x > 1.0 and _terrain_size_xz.y > 1.0:
						var px := clampi(int((wx - _terrain_min_xz.x) / _terrain_size_xz.x * float(_splat_img.get_width() - 1)), 0, _splat_img.get_width() - 1)
						var pz := clampi(int((wz - _terrain_min_xz.y) / _terrain_size_xz.y * float(_splat_img.get_height() - 1)), 0, _splat_img.get_height() - 1)
						var sc := _splat_img.get_pixel(px, pz)
						if sc.g > 0.60 and sc.g > sc.r and sc.g > sc.b:
							ok = false

				if ok and _is_in_bunker_or_hazard(wx, wz, nearby_bunkers, nearby_paths, nearby_water):
					ok = false

			if not ok:
				mm.set_instance_transform(idx, hidden)
				idx += 1
				continue

			var fx := clampf((wx - ox) / h_step, 0.0, float(h_n - 2))
			var fz := clampf((wz - oz) / h_step, 0.0, float(h_n - 2))
			var ix0 := int(fx)
			var iz0 := int(fz)
			var tx := fx - float(ix0)
			var tz := fz - float(iz0)
			var wy := lerpf(
				lerpf(heights[iz0 * h_n + ix0], heights[iz0 * h_n + ix0 + 1], tx),
				lerpf(heights[(iz0 + 1) * h_n + ix0], heights[(iz0 + 1) * h_n + ix0 + 1], tx),
				tz)

			var s := 0.95 + _cell_hash(gx, gz, 3.0) * 0.25
			var rot_y := _cell_hash(gx, gz, 4.0) * TAU
			var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s))
			mm.set_instance_transform(idx, Transform3D(basis, Vector3(wx, wy - 0.005, wz)))
			mm.set_instance_custom_data(idx, Color(
				0.90 + _cell_hash(gx, gz, 5.0) * 0.16,
				0.94 + _cell_hash(gx, gz, 6.0) * 0.12,
				0.88 + _cell_hash(gx, gz, 7.0) * 0.14,
				_cell_hash(gx, gz, 8.0)
			))
			idx += 1

	while idx < total_slots:
		mm.set_instance_transform(idx, hidden)
		idx += 1

	_deep_rough_generated = true

func _update_terrain_tee_and_mow_uniforms(anchor: Vector3) -> void:
	if _terrain_mesh_inst == null:
		_discover_terrain()
	if _terrain_mesh_inst == null:
		return

	var mat: Material = _terrain_mesh_inst.material_override
	if mat == null and _terrain_mesh_inst.mesh != null and _terrain_mesh_inst.mesh.get_surface_count() > 0:
		mat = _terrain_mesh_inst.mesh.surface_get_material(0)
	if not (mat is ShaderMaterial):
		return

	var sm := mat as ShaderMaterial
	if "_hole_start_position" in _scene_root:
		var tee_pos: Vector3 = _scene_root.get("_hole_start_position")
		sm.set_shader_parameter("active_tee_pos", tee_pos)
		if "hole_position" in _scene_root:
			var pin_pos: Vector3 = _scene_root.get("hole_position")
			var dir2d := Vector2(pin_pos.x - tee_pos.x, pin_pos.z - tee_pos.z)
			if dir2d.length_squared() > 1.0:
				sm.set_shader_parameter("hole_mow_direction", dir2d.normalized())
	else:
		sm.set_shader_parameter("active_tee_pos", anchor)


func _sample_ground_y(wx: float, wz: float, fallback_y: float) -> float:
	if not _height_info.is_empty():
		return CourseDetailEnhancer._sample_height(wx, wz, _height_info, fallback_y)
	if _scene_root != null:
		if _scene_root.has_meta("terrain_height_lookup"):
			_height_info = _scene_root.get_meta("terrain_height_lookup")
			if not _height_info.is_empty():
				return CourseDetailEnhancer._sample_height(wx, wz, _height_info, fallback_y)
		_height_info = CourseDetailEnhancer._build_terrain_height_lookup(_scene_root)
		if not _height_info.is_empty():
			return CourseDetailEnhancer._sample_height(wx, wz, _height_info, fallback_y)
	if _scene_root != null and _scene_root.has_method("get_height"):
		return _scene_root.get_height(wx, wz)
	return fallback_y


static func _create_grass_clump_mesh(
	blade_count: int,
	radius: float,
	min_h: float,
	max_h: float,
	blade_width: float,
	outward_lean: float
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1337 + blade_count * 97

	for i in range(blade_count):
		var angle := rng.randf_range(0.0, TAU)
		var dist := sqrt(rng.randf()) * radius
		var bx := cos(angle) * dist
		var bz := sin(angle) * dist
		var base := Vector3(bx, 0.0, bz)

		var blade_yaw := angle + rng.randf_range(-0.65, 0.65)
		var fwd := Vector3(cos(blade_yaw), 0.0, sin(blade_yaw))
		var right := Vector3(-fwd.z, 0.0, fwd.x) * (blade_width * 0.5)

		var h := rng.randf_range(min_h, max_h)
		var lean := outward_lean * rng.randf_range(0.65, 1.35)

		var p0 := base
		var p1 := base + Vector3(0.0, h * 0.52, 0.0) + fwd * (lean * 0.42)
		var p2 := base + Vector3(0.0, h, 0.0) + fwd * lean

		var n := (-fwd * 0.35 + Vector3.UP).normalized()

		# Lower blade quad (2 triangles)
		st.set_normal(n)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(p0 - right)
		st.set_normal(n)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(p0 + right)
		st.set_normal(n)
		st.set_uv(Vector2(0.85, 0.5))
		st.add_vertex(p1 + right * 0.72)

		st.set_normal(n)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(p0 - right)
		st.set_normal(n)
		st.set_uv(Vector2(0.85, 0.5))
		st.add_vertex(p1 + right * 0.72)
		st.set_normal(n)
		st.set_uv(Vector2(0.15, 0.5))
		st.add_vertex(p1 - right * 0.72)

		# Upper tapered tip triangle
		st.set_normal(n)
		st.set_uv(Vector2(0.15, 0.5))
		st.add_vertex(p1 - right * 0.72)
		st.set_normal(n)
		st.set_uv(Vector2(0.85, 0.5))
		st.add_vertex(p1 + right * 0.72)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(p2)

	return st.commit()


## Creates a volumetric, ultra-dense deep rough turf clump matching reference golf photography (Image 2):
## 1. Ground Thatch & Sod Cushion: 20 spreading, arched blades (3.5-5.5 cm) providing 100% ground cover
## 2. Mid-Canopy Cushion: 22 intertwined curved blades (5.0-7.5 cm) providing thick sod depth
## 3. Top Elevated Rough: 16 graceful arched blades (6.5-8.8 cm) that nestle the 4.3 cm golf ball
static func _create_dense_deep_rough_mesh(
	radius: float,
	blade_width: float,
	outward_lean: float
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261025

	# Effective blade width scaled for realistic grass foliage (8mm - 12mm)
	var effective_w := clampf(blade_width, 0.008, 0.013)
	if blade_width > 0.020:
		effective_w = 0.011

	# Tier 1: Ground Thatch & Sod Cushion (20 broad arched ground blades, 3.5cm - 5.5cm tall)
	# Spreads in 360 degrees, forming an interwoven, solid turf carpet that completely covers ground
	for i in range(20):
		var angle := float(i) * (TAU / 20.0) + rng.randf_range(-0.12, 0.12)
		var dist := sqrt(rng.randf()) * (radius * 0.95)
		var base := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var yaw := angle + rng.randf_range(-0.45, 0.45)
		var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
		var w := effective_w * rng.randf_range(1.10, 1.35)
		var right := Vector3(-fwd.z, 0.0, fwd.x) * (w * 0.5)

		var h := rng.randf_range(0.035, 0.055)
		var lean := outward_lean * rng.randf_range(1.1, 1.8)

		# 2-segment blade arching outward and down to hug the turf
		var p0 := base
		var p1 := base + Vector3(0.0, h * 0.65, 0.0) + fwd * (lean * 0.55)
		var p2 := base + Vector3(0.0, h * 0.35, 0.0) + fwd * lean

		var n := (Vector3.UP * 0.85 - fwd * 0.20).normalized()

		_add_curved_blade(st, p0, p1, p2, right, n)

	# Tier 2: Mid-Canopy Interlocking Turf Blades (22 blades, 5.0cm - 7.5cm tall)
	for i in range(22):
		var angle := float(i) * (TAU / 22.0) + rng.randf_range(-0.15, 0.15)
		var dist := sqrt(rng.randf()) * (radius * 0.85)
		var base := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var yaw := angle + rng.randf_range(-0.60, 0.60)
		var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
		var w := effective_w * rng.randf_range(0.95, 1.20)
		var right := Vector3(-fwd.z, 0.0, fwd.x) * (w * 0.5)

		var h := rng.randf_range(0.050, 0.075)
		var lean := outward_lean * rng.randf_range(0.8, 1.4)

		var p0 := base
		var p1 := base + Vector3(0.0, h * 0.58, 0.0) + fwd * (lean * 0.48)
		var p2 := base + Vector3(0.0, h, 0.0) + fwd * lean

		var n := (Vector3.UP * 0.80 + Vector3(-fwd.z, 0.15, fwd.x) * 0.20).normalized()

		_add_curved_blade(st, p0, p1, p2, right, n)

	# Tier 3: Top Canopy Elevated Rough Blades (16 tall blades, 6.5cm - 8.8cm tall)
	# Nestles the 4.3cm golf ball authentically into realistic deep rough (Image 2)
	for i in range(16):
		var angle := float(i) * (TAU / 16.0) + rng.randf_range(-0.18, 0.18)
		var dist := sqrt(rng.randf()) * (radius * 0.75)
		var base := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)

		var yaw := angle + rng.randf_range(-0.55, 0.55)
		var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
		var w := effective_w * rng.randf_range(0.85, 1.05)
		var right := Vector3(-fwd.z, 0.0, fwd.x) * (w * 0.5)

		var h := rng.randf_range(0.065, 0.088)
		var lean := outward_lean * rng.randf_range(0.70, 1.20)

		var p0 := base
		var p1 := base + Vector3(0.0, h * 0.52, 0.0) + fwd * (lean * 0.42)
		var p2 := base + Vector3(0.0, h, 0.0) + fwd * lean

		var n := (Vector3.UP * 0.82 - fwd * 0.25).normalized()

		_add_curved_blade(st, p0, p1, p2, right, n)

	return st.commit()


static func _add_curved_blade(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	right: Vector3,
	n: Vector3
) -> void:
	# Lower quad: p0 to p1
	st.set_normal(n)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(p0 - right)

	st.set_normal(n)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(p0 + right)

	st.set_normal(n)
	st.set_uv(Vector2(0.85, 0.5))
	st.add_vertex(p1 + right * 0.75)

	st.set_normal(n)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(p0 - right)

	st.set_normal(n)
	st.set_uv(Vector2(0.85, 0.5))
	st.add_vertex(p1 + right * 0.75)

	st.set_normal(n)
	st.set_uv(Vector2(0.15, 0.5))
	st.add_vertex(p1 - right * 0.75)

	# Upper tapered tip triangle: p1 to p2
	st.set_normal(n)
	st.set_uv(Vector2(0.15, 0.5))
	st.add_vertex(p1 - right * 0.75)

	st.set_normal(n)
	st.set_uv(Vector2(0.85, 0.5))
	st.add_vertex(p1 + right * 0.75)

	st.set_normal(Vector3.UP)
	st.set_uv(Vector2(0.5, 0.0))
	st.add_vertex(p2)
