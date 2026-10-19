class_name GolfFlag
extends MeshInstance3D

## GolfFlag
## Controls 3D golf pin flag visuals, realistic cloth simulation, and wind tracking.
## - Low Graphics: Lightweight, performant static geometry with minimal draw calls.
## - Medium & High Graphics: Subdivided cloth mesh displaced by dynamic wind wave shader,
##   with realistic droop, fluttering ripples, tournament detailing, top acorn finial,
##   and swivel collars on the flagpole.
## - Dynamically tracks wind direction from GlobalSettings and blows downwind.

const SHADER_PATH := "res://Courses/Environments/shaders/golf_flag.gdshader"

@export var flag_color: Color = Color(0.95, 0.12, 0.12):
	set(val):
		flag_color = val
		_apply_flag_color()

@export var flag_width: float = 0.52
@export var flag_height: float = 0.36
@export var pole_height: float = 3.0

var current_quality: String = ""
var is_realistic: bool = false
var _finial_node: MeshInstance3D = null
var _top_collar_node: MeshInstance3D = null
var _bottom_collar_node: MeshInstance3D = null
var _shader_mat: ShaderMaterial = null
var _simple_mat: StandardMaterial3D = null


func _init() -> void:
	name = "Flag"
	set_meta("is_golf_flag", true)


func _ready() -> void:
	set_meta("is_golf_flag", true)

	var gs = _get_global_settings()
	if gs != null and gs.has_signal("wind_changed"):
		if not gs.wind_changed.is_connected(_on_global_wind_changed):
			gs.wind_changed.connect(_on_global_wind_changed)

	var q = current_quality if not current_quality.is_empty() else _detect_initial_quality()
	update_quality(q)
	update_wind(true)


func _process(delta: float) -> void:
	update_wind(false, delta)


## Sets the flag color and updates active materials
func set_flag_color(col: Color) -> void:
	flag_color = col


## Detects the current active graphics quality ("Low", "Medium", or "High")
func _detect_initial_quality() -> String:
	var gs = _get_global_settings()
	if gs != null and gs.has_method("get_graphics_quality"):
		return gs.get_graphics_quality()
	if gs != null and gs.has_method("is_low_graphics") and gs.is_low_graphics():
		return "Low"
	return "Medium"


## Dynamically sets visual fidelity according to graphics quality setting
func update_quality(quality: String) -> void:
	if quality != "Low" and quality != "Medium" and quality != "High":
		quality = "Medium"
	current_quality = quality

	if quality == "Low":
		_setup_low_graphics()
	else:
		_setup_realistic_graphics(quality == "High")

	update_wind(true)


## Sets up lightweight, performant representation for low-end / mobile hardware
func _setup_low_graphics() -> void:
	is_realistic = false

	# Simple lightweight mesh (2-triangle plane oriented along X)
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w = flag_width
	var h_half = flag_height * 0.5

	# Front face
	st.set_uv(Vector2(0, 0))
	st.add_vertex(Vector3(0.0, h_half, 0.0))
	st.set_uv(Vector2(0, 1))
	st.add_vertex(Vector3(0.0, -h_half, 0.0))
	st.set_uv(Vector2(1, 0))
	st.add_vertex(Vector3(w, h_half, 0.0))

	st.set_uv(Vector2(1, 0))
	st.add_vertex(Vector3(w, h_half, 0.0))
	st.set_uv(Vector2(0, 1))
	st.add_vertex(Vector3(0.0, -h_half, 0.0))
	st.set_uv(Vector2(1, 1))
	st.add_vertex(Vector3(w, -h_half, 0.0))

	# Back face
	st.set_uv(Vector2(0, 0))
	st.add_vertex(Vector3(0.0, h_half, 0.0))
	st.set_uv(Vector2(1, 0))
	st.add_vertex(Vector3(w, h_half, 0.0))
	st.set_uv(Vector2(0, 1))
	st.add_vertex(Vector3(0.0, -h_half, 0.0))

	st.set_uv(Vector2(1, 0))
	st.add_vertex(Vector3(w, h_half, 0.0))
	st.set_uv(Vector2(1, 1))
	st.add_vertex(Vector3(w, -h_half, 0.0))
	st.set_uv(Vector2(0, 1))
	st.add_vertex(Vector3(0.0, -h_half, 0.0))

	mesh = st.commit()

	if _simple_mat == null:
		_simple_mat = StandardMaterial3D.new()
		_simple_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_simple_mat.roughness = 0.6
		_simple_mat.emission_enabled = true
	_simple_mat.albedo_color = flag_color
	_simple_mat.emission = flag_color * 0.4
	material_override = _simple_mat

	_cleanup_hardware_nodes()


## Sets up subdivided realistic 3D cloth flag with wind wave shader & pole hardware
func _setup_realistic_graphics(is_high: bool) -> void:
	is_realistic = true

	# Higher vertex density on High for ultra-smooth fluid ripples; balanced on Medium
	var seg_x: int = 28 if is_high else 18
	var seg_y: int = 16 if is_high else 10
	mesh = _build_subdivided_cloth_mesh(flag_width, flag_height, seg_x, seg_y)

	if _shader_mat == null:
		_shader_mat = ShaderMaterial.new()
		if ResourceLoader.exists(SHADER_PATH):
			_shader_mat.shader = load(SHADER_PATH) as Shader

	material_override = _shader_mat
	_apply_flag_color()
	_update_hardware_nodes()


## Generates a finely subdivided grid mesh anchored along local X=0
static func _build_subdivided_cloth_mesh(w: float, h: float, seg_x: int, seg_y: int) -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for y in range(seg_y + 1):
		var v = float(y) / float(seg_y)
		var py = (0.5 - v) * h # top (+h/2) to bottom (-h/2)
		for x in range(seg_x + 1):
			var u = float(x) / float(seg_x)
			var px = u * w # 0.0 at flagpole to w at outer tip
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3(0.0, 0.0, 1.0))
			st.set_tangent(Plane(1.0, 0.0, 0.0, 1.0))
			st.add_vertex(Vector3(px, py, 0.0))

	for y in range(seg_y):
		for x in range(seg_x):
			var i0 = y * (seg_x + 1) + x
			var i1 = i0 + 1
			var i2 = (y + 1) * (seg_x + 1) + x
			var i3 = i2 + 1
			st.add_index(i0)
			st.add_index(i2)
			st.add_index(i1)
			st.add_index(i1)
			st.add_index(i2)
			st.add_index(i3)

	return st.commit()


## Updates top finial acorn knob and swivel rings on the flagpole
func _update_hardware_nodes() -> void:
	var parent_pin = get_parent_node_3d()
	if parent_pin == null:
		return

	# Top Acorn / Finial
	_finial_node = parent_pin.get_node_or_null("Finial") as MeshInstance3D
	if _finial_node == null and not parent_pin.is_queued_for_deletion():
		_finial_node = MeshInstance3D.new()
		_finial_node.name = "Finial"
		var s_mesh = SphereMesh.new()
		s_mesh.radius = 0.020
		s_mesh.height = 0.040
		_finial_node.mesh = s_mesh
		var finial_mat = StandardMaterial3D.new()
		finial_mat.albedo_color = Color(0.88, 0.74, 0.28) # Polished brass
		finial_mat.metallic = 0.90
		finial_mat.roughness = 0.22
		_finial_node.material_override = finial_mat
		parent_pin.add_child.call_deferred(_finial_node)

	if _finial_node != null:
		_finial_node.position = Vector3(0.0, pole_height + 0.015, 0.0)
		_finial_node.visible = true

	# Swivel attachment rings
	var top_y = position.y + (flag_height * 0.44)
	var bot_y = position.y - (flag_height * 0.44)

	_top_collar_node = parent_pin.get_node_or_null("TopCollar") as MeshInstance3D
	if _top_collar_node == null and not parent_pin.is_queued_for_deletion():
		_top_collar_node = _create_collar_node("TopCollar")
		parent_pin.add_child.call_deferred(_top_collar_node)
	if _top_collar_node != null:
		_top_collar_node.position = Vector3(0.0, top_y, 0.0)
		_top_collar_node.visible = true

	_bottom_collar_node = parent_pin.get_node_or_null("BottomCollar") as MeshInstance3D
	if _bottom_collar_node == null and not parent_pin.is_queued_for_deletion():
		_bottom_collar_node = _create_collar_node("BottomCollar")
		parent_pin.add_child.call_deferred(_bottom_collar_node)
	if _bottom_collar_node != null:
		_bottom_collar_node.position = Vector3(0.0, bot_y, 0.0)
		_bottom_collar_node.visible = true


func _create_collar_node(node_name: String) -> MeshInstance3D:
	var collar = MeshInstance3D.new()
	collar.name = node_name
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.017
	cyl.bottom_radius = 0.017
	cyl.height = 0.018
	collar.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.78)
	mat.metallic = 0.92
	mat.roughness = 0.28
	collar.material_override = mat
	return collar


func _cleanup_hardware_nodes() -> void:
	if _finial_node != null and is_instance_valid(_finial_node):
		_finial_node.visible = false
	if _top_collar_node != null and is_instance_valid(_top_collar_node):
		_top_collar_node.visible = false
	if _bottom_collar_node != null and is_instance_valid(_bottom_collar_node):
		_bottom_collar_node.visible = false


## Applies flag color to either shader material or standard material
func _apply_flag_color() -> void:
	if material_override is ShaderMaterial:
		var sm = material_override as ShaderMaterial
		sm.set_shader_parameter("flag_color", flag_color)
		sm.set_shader_parameter("backlight_color", Vector3(flag_color.r, flag_color.g, flag_color.b))
	elif material_override is StandardMaterial3D:
		var stm = material_override as StandardMaterial3D
		stm.albedo_color = flag_color
		stm.emission = flag_color * 0.4


var custom_wind_override: bool = false
var custom_wind_speed_mph: float = 0.0
var custom_wind_direction_rad: float = 0.0


## Manually overrides wind speed and direction on this flag (e.g. for testing or local conditions)
func set_wind(speed_mph: float, direction_rad: float) -> void:
	custom_wind_override = true
	custom_wind_speed_mph = speed_mph
	custom_wind_direction_rad = direction_rad
	update_wind(true)


## Clears manual wind override and resumes listening to GlobalSettings
func clear_wind_override() -> void:
	custom_wind_override = false
	update_wind(true)


## Returns the effective wind speed in MPH
func get_effective_wind_speed() -> float:
	if custom_wind_override:
		return custom_wind_speed_mph
	var gs = _get_global_settings()
	if gs != null:
		var active = (gs.has_method("is_wind_enabled") and gs.is_wind_enabled()) or gs.current_wind_speed_mph > 0.0
		if active and gs.current_wind_speed_mph > 0.0:
			return float(gs.current_wind_speed_mph)
	# Even in calm air, provide a gentle realistic ambient breeze
	return 2.5


## Returns the desired world-space wind vector
func get_world_wind_direction() -> Vector3:
	if custom_wind_override:
		return Vector3(cos(custom_wind_direction_rad), 0.0, sin(custom_wind_direction_rad)).normalized()
	var gs = _get_global_settings()
	if gs != null:
		var active = (gs.has_method("is_wind_enabled") and gs.is_wind_enabled()) or gs.current_wind_speed_mph > 0.0
		if active and gs.current_wind_speed_mph > 0.0:
			var rad = float(gs.current_wind_direction_rad)
			return Vector3(cos(rad), 0.0, sin(rad)).normalized()
	# Default gentle down-range breeze when wind is disabled or 0 MPH
	return Vector3(1.0, 0.0, 0.15).normalized()


## Calculates local Y rotation so local +X streams downwind
func get_local_wind_yaw() -> float:
	var world_dir = get_world_wind_direction()
	var parent_pin = get_parent_node_3d()
	var local_dir = world_dir
	if parent_pin != null and parent_pin.is_inside_tree() and is_inside_tree():
		local_dir = parent_pin.global_transform.basis.inverse() * world_dir
	local_dir.y = 0.0
	if local_dir.is_zero_approx():
		local_dir = Vector3.RIGHT
	local_dir = local_dir.normalized()
	return atan2(-local_dir.z, local_dir.x)


## Updates wind yaw and shader wave parameters
func update_wind(immediate: bool = false, delta: float = 0.0) -> void:
	var target_yaw = get_local_wind_yaw()
	var spd = get_effective_wind_speed()

	if immediate:
		rotation.y = target_yaw
	else:
		# Add subtle organic gust oscillation for natural air turbulence around the pole
		var gust = sin(Time.get_ticks_msec() * 0.0020 + float(get_instance_id() % 100)) * 0.038 * clampf(spd / 15.0, 0.25, 1.0)
		var rate = clampf(delta * 4.5, 0.0, 1.0) if delta > 0.0 else 1.0
		rotation.y = lerp_angle(rotation.y, target_yaw + gust, rate)

	if is_realistic and material_override is ShaderMaterial:
		_update_shader_parameters(spd)


func _update_shader_parameters(wind_spd: float) -> void:
	var sm = material_override as ShaderMaterial
	if sm == null:
		return

	var spd = clampf(wind_spd, 1.0, 35.0)

	# 1. Ripple wave speed: faster waves as wind increases
	var wave_speed = 3.2 + spd * 0.52

	# 2. Ripple wave amplitude: deeper billows at higher wind
	var wave_amp = clampf(0.022 + (spd / 20.0) * 0.058, 0.022, 0.090)

	# 3. Aerodynamic droop: flag hangs down in light air, lifts taut in strong wind
	var droop = clampf(0.130 - (spd / 20.0) * 0.120, 0.005, 0.130)

	sm.set_shader_parameter("wind_speed_mph", spd)
	sm.set_shader_parameter("wave_speed", wave_speed)
	sm.set_shader_parameter("wave_amplitude", wave_amp)
	sm.set_shader_parameter("droop_amount", droop)


func _on_global_wind_changed(_speed_mph: float, _direction_rad: float) -> void:
	update_wind(false, 0.016)


func _get_global_settings() -> Node:
	if Engine.has_singleton("GlobalSettings"):
		return Engine.get_singleton("GlobalSettings")
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("GlobalSettings"):
		return main_loop.root.get_node("GlobalSettings")
	return null
