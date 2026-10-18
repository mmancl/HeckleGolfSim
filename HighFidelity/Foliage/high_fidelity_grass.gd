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
var _update_timer: float = 0.0
var _terrain_min_xz: Vector2 = Vector2(-500.0, -500.0)
var _terrain_size_xz: Vector2 = Vector2(1000.0, 1000.0)
var _splat_tex: Texture2D = null
var _is_driving_range: bool = false


func setup(scene_root: Node) -> void:
	_scene_root = scene_root
	if _scene_root == null:
		return

	_is_driving_range = MobilePerformance.is_driving_range_node(_scene_root)
	_discover_terrain()
	# Geometry grass blades removed: they floated above terrain and looked unrealistic.
	# Turf detail is handled entirely by the terrain shader.
	_refresh_anchor(true)


func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < 0.35:
		return
	_update_timer = 0.0
	_refresh_anchor(false)


func _discover_terrain() -> void:
	if _scene_root == null:
		return
	_terrain_mesh_inst = _scene_root.find_child("UnifiedTerrain", true, false) as MeshInstance3D
	if _terrain_mesh_inst == null:
		_terrain_mesh_inst = _scene_root.get_node_or_null("DynamicGround") as MeshInstance3D
	if _terrain_mesh_inst == null:
		return

	if _terrain_mesh_inst.mesh != null:
		var aabb := _terrain_mesh_inst.mesh.get_aabb()
		_terrain_min_xz = Vector2(aabb.position.x, aabb.position.z)
		_terrain_size_xz = Vector2(maxf(aabb.size.x, 1.0), maxf(aabb.size.z, 1.0))

	var mat: Material = _terrain_mesh_inst.material_override
	if mat == null and _terrain_mesh_inst.mesh != null and _terrain_mesh_inst.mesh.get_surface_count() > 0:
		mat = _terrain_mesh_inst.mesh.surface_get_material(0)
	if mat is ShaderMaterial:
		_splat_tex = (mat as ShaderMaterial).get_shader_parameter("splat_map")
	if _splat_tex == null and _terrain_mesh_inst.has_meta("orig_splat_map"):
		_splat_tex = _terrain_mesh_inst.get_meta("orig_splat_map")


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
	_rough_mmi.name = "RoughFescueMultiMesh"
	_rough_mmi.multimesh = mm
	_rough_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rough_mmi)


func _refresh_anchor(force: bool) -> void:
	if _scene_root == null or not is_inside_tree():
		return

	var anchor := Vector3.ZERO
	var ball := _scene_root.get_node_or_null("Ball") as Node3D
	if ball == null:
		ball = _scene_root.get_node_or_null("Player/ball") as Node3D
	if ball == null:
		ball = _scene_root.find_child("ball", true, false) as Node3D
	if ball == null:
		ball = _scene_root.find_child("Ball", true, false) as Node3D
	if ball != null:
		anchor = ball.global_position
	else:
		var vp := get_viewport()
		if vp != null and vp.get_camera_3d() != null:
			anchor = vp.get_camera_3d().global_position

	if not force and anchor.distance_squared_to(_last_anchor_pos) < 9.0:
		return
	_last_anchor_pos = anchor

	# Update tee divot position & hole mowing alignment on UnifiedTerrain if on High
	_update_terrain_tee_and_mow_uniforms(anchor)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(floor(anchor.x * 0.5)) * 73856093 ^ int(floor(anchor.z * 0.5)) * 19349663

	# Snap anchor grid to 2m steps so grass patches stay world-anchored when camera nudges slightly
	var grid_center := Vector3(snappedf(anchor.x, 2.0), anchor.y, snappedf(anchor.z, 2.0))

	if _address_mmi != null and _address_mmi.multimesh != null:
		var mm := _address_mmi.multimesh
		for i in range(ADDRESS_CLUSTER_COUNT):
			var r := sqrt(rng.randf()) * 14.5
			var theta := rng.randf_range(0.0, TAU)
			var wx := grid_center.x + cos(theta) * r
			var wz := grid_center.z + sin(theta) * r
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
			var r := 2.2 + sqrt(rng.randf()) * 48.0
			var theta := rng.randf_range(0.0, TAU)
			var wx := grid_center.x + cos(theta) * r
			var wz := grid_center.z + sin(theta) * r
			if _is_driving_range and absf(wz) < 25.5 and wx > -10.0:
				# On driving range, push tall rough outside the fairway corridor or behind tee
				wz = (26.0 + rng.randf_range(0.5, 22.0)) * (1.0 if rng.randf() > 0.5 else -1.0)
			var wy := _sample_ground_y(wx, wz, anchor.y)
			var rot_y := rng.randf_range(0.0, TAU)
			var s := rng.randf_range(0.80, 1.38)
			var basis := Basis(Vector3.UP, rot_y).scaled(Vector3(s, s, s))
			mm.set_instance_transform(i, Transform3D(basis, Vector3(wx, wy, wz)))
			var tint := Color(rng.randf_range(0.88, 1.08), rng.randf_range(0.92, 1.06), rng.randf_range(0.86, 1.02), rng.randf_range(0.05, 0.99))
			mm.set_instance_custom_data(i, tint)


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
	if _scene_root != null and _scene_root.has_method("_query_terrain_surface_height"):
		var h = _scene_root.call("_query_terrain_surface_height", Vector3(wx, fallback_y, wz))
		if typeof(h) == TYPE_FLOAT and not is_nan(h):
			return float(h)
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
