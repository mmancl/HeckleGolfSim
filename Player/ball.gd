extends CharacterBody3D
class_name GolfBall

signal rest

const BALL_RADIUS := 0.021335
const TEE_LIFT_HEIGHT := 0.0381 # 1.5 inches in meters
const TEED_CENTER_HEIGHT := BALL_RADIUS + TEE_LIFT_HEIGHT # 0.059435m
const GROUND_CENTER_HEIGHT := BALL_RADIUS # 0.021335m
const START_HEIGHT := TEED_CENTER_HEIGHT
const COLLISION_SAFE_MARGIN := 0.0005
const BELOW_GROUND_RECOVERY_Y := -0.5
const FALLTHROUGH_FAILSAFE_Y := -5.0
const GROUND_SNAP_OFFSET := 0.001
const GROUND_RAYCAST_UP := 2.0
const GROUND_RAYCAST_DOWN := 8.0
const GROUND_PROBE_DISTANCE := 0.08
const MIN_GROUND_NORMAL := 0.7

var ball_model : PackedScene = preload("res://assets/models/balls/golf_ball.glb")
var _ball_mesh: Node3D = null
var _tee_mesh: Node3D = null
var current_selected_club: String = "Dr"
var spawn_position := Vector3(0.0, START_HEIGHT, 0.0)

# Preloaded sound streams
var _sfx_hit_drive = preload("res://assets/audio/sfx/golf_tee_shot.wav")
var _sfx_hit_other = preload("res://assets/audio/sfx/golf_sand_shot.mp3")
var _sfx_hit_putt = preload("res://assets/audio/sfx/putt.mp3")
var _sfx_tree_hit = preload("res://assets/audio/sfx/ball_hit_tree.mp3")
var _sfx_leaf_rustle = preload("res://assets/audio/sfx/leaves.mp3")
var _sfx_water_splash = preload("res://assets/audio/sfx/water.mp3")
var _sfx_sand_thud = preload("res://assets/audio/sfx/sand.mp3")
var _sfx_bounce_fairway = preload("res://assets/audio/sfx/fairway_maybe.mp3")
var _sfx_bounce_green = preload("res://assets/audio/sfx/fairway_maybe.mp3")
var _sfx_rough_thump = preload("res://assets/audio/sfx/rough.mp3")
var _sfx_cup_drop = preload("res://assets/audio/sfx/cup_drop.mp3")

# SFX players
var _sfx_player: AudioStreamPlayer = null
var _leaves_player: AudioStreamPlayer = null
var _cup_player: AudioStreamPlayer = null

# C# addon instances
var _physics
var _aero
var _surface
var _shot_setup

# Physics parameters
var params = null

# Ball state variables
var state: int = PhysicsEnums.BallState.REST
var omega := Vector3.ZERO  # Angular velocity (rad/s)
var on_ground := false
var floor_normal := Vector3.UP
var is_in_water := false
var water_collider: Node3D = null
var is_in_sand := false
var lie_type: String = "fairway"

# Cup/hole fall animation variables
var is_falling_in_hole := false
var falling_target_hole := Vector3.ZERO
var falling_time := 0.0
var flight_time := 0.0
var _cached_target_hole := Vector3.ZERO

# Tree canopy detection variables (throttled point check, 5 Hz)
var _has_canopy_trees: bool = false
var _scene_tree_checked: bool = false
var _tree_check_timer: float = 0.0
var _is_in_tree_canopy: bool = false
var _surface_check_timer: float = 0.0

# Precise physics tick tracking for visual camera interpolation
var prev_physics_pos := Vector3.ZERO
var curr_physics_pos := Vector3.ZERO
var _physics_pos_initialized := false

# Cached world colliders
var _cached_terrain_static: CollisionObject3D = null
var _cached_rough_static: CollisionObject3D = null
var _terrain_cache_searched: bool = false


# Surface parameters (base values from C# Surface addon, then multiplied below).
# TODO - some of these values should not be in ball. Ball type shouldn't matter grass viscosity.
# Change the *_mult values to create a different "feel" for this ball without touching global settings.
var surface_type: int = PhysicsEnums.SurfaceType.FAIRWAY
var _surface_zone_stack: Array[int] = []
var _kinetic_friction: float = 0.42
var _rolling_friction: float = 0.18
var _grass_viscosity: float = 0.0020
var _critical_angle: float = 0.30  # radians
var _kinetic_mult := 1.0
var _rolling_mult := 1.0
var _grass_mult := 1.0
var _critical_mult := 1.0
@export var slope_force_scale: float = 0.5

# Environment
var _air_density: float
var _air_viscosity: float
# TODO: takeout these scale and mult variables
var _drag_scale := 1.0
var _lift_scale := 1.0

# Shot tracking
var shot_start_pos := Vector3.ZERO
var shot_start_pos_global := Vector3.ZERO
var shot_was_in_sand := false
var shot_was_from_teebox := false
var shot_hit_other_ground := false
var shot_dir := Vector3(1.0, 0.0, 0.0)  # Normalized horizontal direction
var target_dir := Vector3(1.0, 0.0, 0.0)  # Normalized target aim direction (horizontal)
var aim_yaw_offset_deg := 0.0  # Camera/world rotation offset applied at launch
var launch_spin_rpm := 0.0  # Stored for bounce calculations
var rollout_impact_spin_rpm := 0.0  # Spin on first impact; used for rollout friction
var is_putt := false
var _hit_leaves_this_shot := false
var _skipping_flight := false


# Ball physics constants (cached from C# addon in _init)
var _ball_mass: float
var _ball_radius: float
var _ball_moi: float
var _ball_initialized := false
var _openfairway_error_reported: Dictionary = {}

const OPENFAIRWAY_CLASS_PATHS := {
	"BallPhysics": "res://addons/openfairway/physics/BallPhysics.cs",
	"Aerodynamics": "res://addons/openfairway/physics/Aerodynamics.cs",
	"Surface": "res://addons/openfairway/physics/Surface.cs",
	"PhysicsParams": "res://addons/openfairway/physics/PhysicsParams.cs",
	"ShotSetup": "res://addons/openfairway/physics/ShotSetup.cs",
}
const DEFAULT_BALL_MASS := 0.04592623
const DEFAULT_BALL_RADIUS := 0.021335
const DEFAULT_BALL_MOI := 0.4 * DEFAULT_BALL_MASS * DEFAULT_BALL_RADIUS * DEFAULT_BALL_RADIUS


func _ready() -> void:
	_try_initialize_ball()
	_create_physics_params()
	reset()
	
	# Create physical impact SFX player
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.name = "BallSfxPlayer"
	add_child(_sfx_player)

	# Create leaves rustling SFX player
	_leaves_player = AudioStreamPlayer.new()
	_leaves_player.name = "BallLeavesPlayer"
	_leaves_player.stream = _sfx_leaf_rustle
	add_child(_leaves_player)

	# Create ball cup drop SFX player
	_cup_player = AudioStreamPlayer.new()
	_cup_player.name = "BallCupPlayer"
	_cup_player.stream = _sfx_cup_drop
	add_child(_cup_player)



func _new_openfairway(openfairway_class: StringName):
	var class_key := String(openfairway_class)
	var fallback_script_path: String = OPENFAIRWAY_CLASS_PATHS.get(class_key, "")
	if fallback_script_path != "":
		var script_resource: Script = load(fallback_script_path) as Script
		if script_resource != null:
			var instance = script_resource.new()
			if instance != null:
				return instance

	if fallback_script_path == "" and ClassDB.class_exists(openfairway_class) and ClassDB.can_instantiate(openfairway_class):
		var classdb_instance = ClassDB.instantiate(openfairway_class)
		if classdb_instance != null:
			return classdb_instance

	if not _openfairway_error_reported.has(class_key):
		_openfairway_error_reported[class_key] = true
		if not OS.has_feature("C#"):
			push_error("OpenFairway class '%s' is unavailable because this runtime has no C# support. Launch the project with the Godot .NET editor/runtime." % class_key)
		elif fallback_script_path != "":
			push_error("OpenFairway class '%s' could not be instantiated from '%s'. Build OpenShotGolf.csproj and restart the Godot .NET editor/runtime." % [class_key, fallback_script_path])
		else:
			push_error("OpenFairway class '%s' is unavailable. Build OpenShotGolf.csproj and restart the Godot .NET editor/runtime." % class_key)
	return null


var _property_name_cache: Dictionary = {}
var _method_name_cache: Dictionary = {}


func _resolve_openfairway_property(target: Object, snake_name: StringName, pascal_name: StringName) -> StringName:
	if target == null:
		return &""
	var target_class := target.get_class()
	var cache_key := target_class + ":" + String(snake_name)
	if _property_name_cache.has(cache_key):
		return _property_name_cache[cache_key]

	if snake_name in target:
		_property_name_cache[cache_key] = snake_name
		return snake_name
	elif pascal_name in target:
		_property_name_cache[cache_key] = pascal_name
		return pascal_name

	for property_info in target.get_property_list():
		var p_name = StringName(property_info.get("name", ""))
		if p_name == snake_name:
			_property_name_cache[cache_key] = snake_name
			return snake_name
		if p_name == pascal_name:
			_property_name_cache[cache_key] = pascal_name
			return pascal_name

	_property_name_cache[cache_key] = &""
	return &""


func _has_openfairway_property(target: Object, property_name: StringName) -> bool:
	if target == null:
		return false
	var target_class := target.get_class()
	var cache_key := target_class + ":" + String(property_name)
	if _property_name_cache.has(cache_key):
		return _property_name_cache[cache_key] != &""
	if property_name in target:
		_property_name_cache[cache_key] = property_name
		return true
	for property_info in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			_property_name_cache[cache_key] = property_name
			return true
	_property_name_cache[cache_key] = &""
	return false


func _get_openfairway_property(target: Object, snake_name: StringName, pascal_name: StringName, default_value = null):
	var prop_name := _resolve_openfairway_property(target, snake_name, pascal_name)
	if prop_name != &"":
		return target.get(prop_name)
	return default_value


func _set_openfairway_property(target: Object, snake_name: StringName, pascal_name: StringName, value) -> bool:
	var prop_name := _resolve_openfairway_property(target, snake_name, pascal_name)
	if prop_name != &"":
		target.set(prop_name, value)
		return true
	return false


func _resolve_openfairway_method(target: Object, snake_name: StringName, pascal_name: StringName) -> StringName:
	if target == null:
		return &""
	var target_class := target.get_class()
	var cache_key := target_class + ":" + String(snake_name)
	if _method_name_cache.has(cache_key):
		return _method_name_cache[cache_key]

	if target.has_method(snake_name):
		_method_name_cache[cache_key] = snake_name
		return snake_name
	elif target.has_method(pascal_name):
		_method_name_cache[cache_key] = pascal_name
		return pascal_name

	_method_name_cache[cache_key] = &""
	return &""


func _call_openfairway_method(target: Object, snake_name: StringName, pascal_name: StringName, args: Array = []):
	var method_name := _resolve_openfairway_method(target, snake_name, pascal_name)
	if method_name != &"":
		return target.callv(method_name, args)
	return null


func _init_openfairway_instances() -> bool:
	_physics = _new_openfairway(&"BallPhysics")
	_aero = _new_openfairway(&"Aerodynamics")
	_surface = _new_openfairway(&"Surface")
	_shot_setup = _new_openfairway(&"ShotSetup")
	if _physics == null or _aero == null or _surface == null:
		return false
	_ball_mass = float(_get_openfairway_property(_physics, &"ball_mass", &"BallMass", DEFAULT_BALL_MASS))
	_ball_radius = float(_get_openfairway_property(_physics, &"ball_radius", &"BallRadius", DEFAULT_BALL_RADIUS))
	_ball_moi = float(_get_openfairway_property(_physics, &"ball_moment_of_inertia", &"BallMomentOfInertia", DEFAULT_BALL_MOI))
	return true


func _try_initialize_ball() -> bool:
	if _ball_initialized:
		return true
	if not _init_openfairway_instances():
		return false
	initialize_ball()
	_ball_initialized = true
	return true


func initialize_ball() -> void:
	_connect_settings()
	_update_environment()
	set_surface(int(GlobalSettings.range_settings.surface_type.value))
	_create_collision_and_model()


func _create_collision_and_model():
	# Create collision shape
	var collision = CollisionShape3D.new()
	var shape = SphereShape3D.new()
	shape.set_radius(_ball_radius)
	collision.set_shape(shape)
	add_child(collision)
	# Create model
	_ball_mesh = ball_model.instantiate()
	var mesh_scale := 0.05
	_ball_mesh.scale = Vector3(mesh_scale, mesh_scale, mesh_scale)
	add_child(_ball_mesh)

	# Create 3D golf tee peg model
	_tee_mesh = Node3D.new()
	_tee_mesh.name = "TeePeg"
	var tee_instance = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.0045 # Flared head under ball
	cyl.bottom_radius = 0.0018 # Peg shaft
	cyl.height = TEE_LIFT_HEIGHT
	cyl.radial_segments = 16
	var tee_mat = StandardMaterial3D.new()
	tee_mat.albedo_color = Color(0.96, 0.95, 0.92) # Classic white golf tee
	tee_mat.roughness = 0.35
	tee_instance.mesh = cyl
	tee_instance.material_override = tee_mat
	tee_instance.position.y = -_ball_radius - (TEE_LIFT_HEIGHT / 2.0)
	_tee_mesh.add_child(tee_instance)
	_tee_mesh.visible = false
	add_child(_tee_mesh)


func _check_scene_has_trees() -> bool:
	if _scene_tree_checked:
		return _has_canopy_trees
	_scene_tree_checked = true
	var current_scene = get_tree().current_scene if is_inside_tree() else null
	if current_scene != null:
		# Range scene has no trees
		if current_scene.name == "Range" or (current_scene.scene_file_path != "" and current_scene.scene_file_path.ends_with("range.tscn")):
			_has_canopy_trees = false
			return false
		# Look for TreesFolder or CanopyArea in course
		if current_scene.has_node("TreesFolder") or current_scene.find_child("CanopyArea", true, false) != null:
			_has_canopy_trees = true
			return true
	_has_canopy_trees = false
	return false


func _check_tree_canopy() -> void:
	var world := get_world_3d()
	if world == null:
		_is_in_tree_canopy = false
		return
	var point_query := PhysicsPointQueryParameters3D.new()
	point_query.position = global_position
	point_query.collide_with_areas = true
	point_query.collide_with_bodies = false
	point_query.collision_mask = 1
	var results := world.direct_space_state.intersect_point(point_query, 4)
	var found_canopy := false
	for hit in results:
		var col = hit.get("collider")
		if col is Area3D and (col.name == "CanopyArea" or col.has_meta("is_canopy")):
			found_canopy = true
			break
	_is_in_tree_canopy = found_canopy


func _is_collider_tree(collider: Object) -> bool:
	if collider == null:
		return false
	if collider.has_meta("is_tree"):
		return bool(collider.get_meta("is_tree"))
	var c_name := String(collider.name)
	if c_name.containsn("tree") or c_name.containsn("trunk"):
		return true
	var parent := (collider as Node).get_parent() if collider is Node else null
	if parent != null:
		var p_name := String(parent.name)
		if p_name.containsn("tree") or p_name.containsn("trunk"):
			return true
	return false


func _connect_settings() -> void:
	GlobalSettings.range_settings.temperature.setting_changed.connect(_on_environment_changed)
	GlobalSettings.range_settings.altitude.setting_changed.connect(_on_environment_changed)
	GlobalSettings.range_settings.range_units.setting_changed.connect(_on_environment_changed)
	GlobalSettings.range_settings.surface_type.setting_changed.connect(_on_surface_type_changed)
	GlobalSettings.range_settings.green_speed.setting_changed.connect(_on_green_speed_changed)
	
	if has_node("/root/EventBus"):
		var eb = get_node("/root/EventBus")
		if eb.has_signal("club_selected") and not eb.is_connected("club_selected", Callable(self, "_on_club_selected")):
			eb.connect("club_selected", Callable(self, "_on_club_selected"))


func _on_club_selected(club_name: String) -> void:
	current_selected_club = club_name
	_update_tee_elevation()


func _update_tee_elevation() -> void:
	if _tee_mesh == null:
		return
	if state != PhysicsEnums.BallState.REST:
		_tee_mesh.visible = false
		return

	var is_teebox := (lie_type == "teebox")
	var is_driver := current_selected_club.to_lower() in ["dr", "driver", "1w"]

	if is_teebox and is_driver:
		_tee_mesh.visible = true
		var probe := _try_probe_ground()
		if probe.get("hit", false):
			var ground_y: float = probe.get("position", Vector3.ZERO).y
			global_position.y = ground_y + TEED_CENTER_HEIGHT
	else:
		_tee_mesh.visible = false
		# For all non-teed balls (green, fairway, rough, teebox with irons/putter),
		# probe the ground and seat the ball cleanly on top of the surface normal.
		var probe := _try_probe_ground()
		if probe.get("hit", false):
			var hit_pos: Vector3 = probe.get("position", Vector3.ZERO)
			var hit_norm: Vector3 = probe.get("normal", Vector3.UP)
			global_position = hit_pos + hit_norm * (_ball_radius + GROUND_SNAP_OFFSET)
			floor_normal = hit_norm
			on_ground = true
			if probe.has("collider") and probe["collider"] != null:
				_update_surface_from_collider(probe["collider"])


func _create_physics_params():
	if params != null:
		return
	var _params = _new_openfairway(&"PhysicsParams")
	if _params == null:
		return
	_set_openfairway_property(_params, &"air_density", &"AirDensity", _air_density)
	_set_openfairway_property(_params, &"air_viscosity", &"AirViscosity", _air_viscosity)
	_set_openfairway_property(_params, &"drag_scale", &"DragScale", _drag_scale)
	_set_openfairway_property(_params, &"lift_scale", &"LiftScale", _lift_scale)
	_set_openfairway_property(_params, &"kinetic_friction", &"KineticFriction", _kinetic_friction)
	_set_openfairway_property(_params, &"rolling_friction", &"RollingFriction", _rolling_friction)
	_set_openfairway_property(_params, &"grass_viscosity", &"GrassViscosity", _grass_viscosity)
	_set_openfairway_property(_params, &"critical_angle", &"CriticalAngle", _critical_angle)
	_set_openfairway_property(_params, &"floor_normal", &"FloorNormal", floor_normal)
	_set_openfairway_property(_params, &"rollout_impact_spin", &"RolloutImpactSpin", rollout_impact_spin_rpm)
	_set_openfairway_property(_params, &"slope_force_scale", &"SlopeForceScale", slope_force_scale)
	_set_openfairway_property(_params, &"initial_launch_angle_deg", &"InitialLaunchAngleDeg", 0.0)
	
	params = _params

func _on_environment_changed(_value) -> void:
	_update_environment()

# TODO: clean up surface type and surface stack
func _on_surface_type_changed(value) -> void:
	if _surface_zone_stack.is_empty():
		set_surface(int(value))


func _on_green_speed_changed(_value) -> void:
	_apply_surface_params()


func _update_environment() -> void:
	var units: int = GlobalSettings.range_settings.range_units.value
	var density = _call_openfairway_method(
		_aero,
		&"get_air_density",
		&"GetAirDensity",
		[GlobalSettings.range_settings.altitude.value, GlobalSettings.range_settings.temperature.value, units]
	)
	var viscosity = _call_openfairway_method(
		_aero,
		&"get_dynamic_viscosity",
		&"GetDynamicViscosity",
		[GlobalSettings.range_settings.temperature.value, units]
	)
	if density == null:
		_air_density = 1.225
	if viscosity == null:
		_air_viscosity = 0.0000181
		return
	_air_density = float(density)
	_air_viscosity = float(viscosity)


func set_surface(surface: int) -> void:
	if surface_type == surface:
		return
	surface_type = surface
	_apply_surface_params()


func enter_surface_zone(surface: int) -> void:
	_surface_zone_stack.append(surface)
	set_surface(surface)


func exit_surface_zone(surface: int) -> void:
	for i in range(_surface_zone_stack.size() - 1, -1, -1):
		if _surface_zone_stack[i] == surface:
			_surface_zone_stack.remove_at(i)
			break

	if not _surface_zone_stack.is_empty():
		set_surface(_surface_zone_stack[_surface_zone_stack.size() - 1])
	else:
		set_surface(int(GlobalSettings.range_settings.surface_type.value))


func _apply_surface_params() -> void:
	if _surface == null:
		return
	var params_variant = _call_openfairway_method(_surface, &"get_params", &"GetParams", [surface_type])
	var surface_params: Dictionary = {}
	if typeof(params_variant) == TYPE_DICTIONARY:
		surface_params = params_variant
	else:
		if is_in_sand or surface_type == PhysicsEnums.SurfaceType.BUNKER:
			surface_params = {"u_k": 0.95, "u_kr": 0.42, "nu_g": 0.020, "theta_c": 0.45}
		else:
			surface_params = {"u_k": 0.30, "u_kr": 0.03, "nu_g": 0.0010, "theta_c": 0.25}
	_kinetic_friction = float(surface_params.get("u_k", 0.30)) * _kinetic_mult
	_rolling_friction = float(surface_params.get("u_kr", 0.03)) * _rolling_mult
	
	# Determine green speed scaling exponent based on surface type
	var green_speed = float(GlobalSettings.range_settings.green_speed.value)
	var exponent := 0.0
	if is_in_sand or surface_type == PhysicsEnums.SurfaceType.BUNKER:
		exponent = 0.0
	elif surface_type == PhysicsEnums.SurfaceType.GREEN:
		exponent = 0.70
	elif surface_type == PhysicsEnums.SurfaceType.FAIRWAY or surface_type == PhysicsEnums.SurfaceType.FAIRWAY_SOFT:
		exponent = 0.40
	elif surface_type == PhysicsEnums.SurfaceType.ROUGH:
		exponent = 0.20
	else:
		exponent = 0.30 # Fallback for other surfaces like FIRM
		
	var speed_mult = pow(10.0 / green_speed, exponent)
	
	# Apply default friction scale to reduce default ball rollout speed
	var default_friction_scale := 1.35
	
	_kinetic_friction *= speed_mult * default_friction_scale
	_rolling_friction *= speed_mult * default_friction_scale
	
	_grass_viscosity = float(surface_params.get("nu_g", 0.0010)) * _grass_mult
	_critical_angle = float(surface_params.get("theta_c", 0.25)) * _critical_mult
	if OS.is_debug_build():
		print("Surface set to %s (sand=%s) -> u_k=%.3f, u_kr=%.3f, nu_g=%.4f, theta_c=%.3f, speed_mult=%.3f" % [
			str(surface_type), str(is_in_sand), _kinetic_friction, _rolling_friction, _grass_viscosity, _critical_angle, speed_mult
		])


func get_target_dir() -> Vector3:
	if target_dir.length_squared() > 0.001:
		return target_dir
	return Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(aim_yaw_offset_deg)).normalized()


func get_target_right() -> Vector3:
	return get_target_dir().cross(Vector3.UP).normalized()


func get_downrange_meters() -> float:
	if shot_start_pos_global.is_zero_approx():
		return 0.0
	var delta: Vector3 = global_position - shot_start_pos_global
	var delta_h := Vector3(delta.x, 0.0, delta.z)
	return delta_h.dot(get_target_dir())


func get_downrange_yards() -> float:
	return get_downrange_meters() * 1.09361


func get_side_distance_meters() -> float:
	if shot_start_pos_global.is_zero_approx():
		return 0.0
	var delta: Vector3 = global_position - shot_start_pos_global
	var delta_h := Vector3(delta.x, 0.0, delta.z)
	return delta_h.dot(get_target_right())


func get_side_distance_yards() -> float:
	return get_side_distance_meters() * 1.09361


func _process(_delta: float) -> void:
	if _ball_mesh != null:
		var target_y := 0.0
		if is_in_sand:
			target_y = -0.017 # Sink 1.7 cm in sand traps
		elif lie_type == "rough":
			target_y = -0.014 # Sink 1/3 of ball diameter
		if not is_equal_approx(_ball_mesh.position.y, target_y):
			_ball_mesh.position.y = target_y


func _physics_process(delta: float) -> void:
	if state == PhysicsEnums.BallState.REST:
		return

	# Live proximity check for suspense (Course Play only)
	var target_hole_live = _cached_target_hole
	if target_hole_live.is_zero_approx():
		target_hole_live = get_target_hole_position()
		_cached_target_hole = target_hole_live

	if has_node("/root/TensionManager") and not target_hole_live.is_zero_approx() and TensionManager.is_course_play_active():
		var start_p = shot_start_pos_global if not shot_start_pos_global.is_zero_approx() else (position if not position.is_zero_approx() else spawn_position)
		TensionManager.check_ball_proximity(global_position, target_hole_live, is_putt, start_p, shot_was_in_sand)

	# Check if we should fall into the hole
	if not is_falling_in_hole:
		var target_hole = target_hole_live
		
		if target_hole != null and not target_hole.is_zero_approx():
			var ball_pos = global_position
			var dist_2d = Vector2(ball_pos.x, ball_pos.z).distance_to(Vector2(target_hole.x, target_hole.z))
			var vertical_diff = ball_pos.y - target_hole.y
			# Only drop if the ball is close to the ground/green height
			if vertical_diff > -0.05 and vertical_diff < 0.15:
				var cup_radius := 0.054 # Regulation 4.25" cup radius (0.054m)
				var speed = velocity.length()
				if dist_2d <= 0.065:
					# Drop in if rolling at realistic entry speeds for cup position:
					# - Dead-center entry (dist < 2.5cm): drops in up to 2.0 m/s (~4.5 mph)
					# - Inside regulation lip (dist <= 5.4cm): drops in up to 1.4 m/s (~3.1 mph)
					# - Outer lip edge (dist <= 6.5cm): lips in for slow speeds under 0.3 m/s (~0.67 mph)
					if (dist_2d < 0.025 and speed < 2.0) or (dist_2d <= cup_radius and speed < 1.4) or (dist_2d <= 0.065 and speed < 0.3):
						is_falling_in_hole = true
						falling_target_hole = target_hole
						falling_time = 0.0
						velocity = Vector3.ZERO
						omega = Vector3.ZERO
						if _cup_player != null and not _skipping_flight:
							_cup_player.play()

	if is_falling_in_hole:
		falling_time += delta
		# Lerp position towards target hole center (XZ) and below ground level (Y)
		var target_pos = Vector3(falling_target_hole.x, falling_target_hole.y - 0.08, falling_target_hole.z)
		global_position = global_position.lerp(target_pos, delta * 12.0)
		
		if global_position.distance_to(target_pos) < 0.01 or falling_time > 0.5:
			global_position = target_pos
			is_falling_in_hole = false
			_enter_rest_state()
		return

	if state == PhysicsEnums.BallState.FLIGHT:
		flight_time += delta
	else:
		flight_time = 0.0

	if on_ground or state != PhysicsEnums.BallState.FLIGHT:
		_surface_check_timer += delta
		if _surface_check_timer >= 0.10:
			_surface_check_timer = 0.0
			_update_surface_from_underneath()

	var was_on_ground := on_ground
	var prev_velocity := velocity

	if params != null and was_on_ground:
		_set_openfairway_property(params, &"floor_normal", &"FloorNormal", floor_normal)
		_set_openfairway_property(params, &"rollout_impact_spin", &"RolloutImpactSpin", rollout_impact_spin_rpm)
		_set_openfairway_property(params, &"kinetic_friction", &"KineticFriction", _kinetic_friction)
		_set_openfairway_property(params, &"rolling_friction", &"RollingFriction", _rolling_friction)
		_set_openfairway_property(params, &"grass_viscosity", &"GrassViscosity", _grass_viscosity)
		_set_openfairway_property(params, &"critical_angle", &"CriticalAngle", _critical_angle)
		_set_openfairway_property(params, &"surface_type", &"SurfaceType", surface_type)
		_set_openfairway_property(params, &"slope_force_scale", &"SlopeForceScale", slope_force_scale)
		_set_openfairway_property(params, &"is_in_sand", &"IsInSand", is_in_sand or surface_type == PhysicsEnums.SurfaceType.BUNKER)

	# Calculate forces and torques using BallPhysics
	var total_force = _call_openfairway_method(_physics, &"calculate_forces", &"CalculateForces", [velocity, omega, was_on_ground, params])
	var total_torque = _call_openfairway_method(_physics, &"calculate_torques", &"CalculateTorques", [velocity, omega, was_on_ground, params])
	if total_force == null or total_torque == null:
		return

	# Update velocity and angular velocity
	velocity += (total_force / _ball_mass) * delta
	omega += (total_torque / _ball_moi) * delta

	# Apply tree leaves reduction/damping (throttled check, 5 Hz)
	if state == PhysicsEnums.BallState.FLIGHT and _has_canopy_trees:
		_tree_check_timer += delta
		if _tree_check_timer >= 0.20:
			_tree_check_timer = 0.0
			_check_tree_canopy()

		if _is_in_tree_canopy:
			var damping_factor := 0.35
			velocity *= (1.0 - damping_factor * delta)
			omega *= (1.0 - damping_factor * delta)
			
			if _leaves_player and not _leaves_player.playing and not _skipping_flight:
				_leaves_player.play()
			
			if not _hit_leaves_this_shot:
				_hit_leaves_this_shot = true
				print("[ball.gd] Hitting tree leaves! Reducing velocity.")
				if has_node("/root/AnnouncerEngine") and not _skipping_flight:
					get_node("/root/AnnouncerEngine").call("SpeakTreeHeckle")
		else:
			if _leaves_player and _leaves_player.playing:
				_leaves_player.stop()
	elif _leaves_player and _leaves_player.playing:
		_leaves_player.stop()

	# Safety: catch NaN/infinity before it reaches the physics engine
	# Without this, ROUGH appears to error with FINITE bug. Do not remove until someone
	# better understands this. 
	if not velocity.is_finite() or not omega.is_finite():
		push_warning("BallPhysics: non-finite velocity or omega detected, entering rest")
		_enter_rest_state()
		return

	# Safety bounds check
	#if _check_out_of_bounds():
		#return

	# Move and handle collisions
	prev_physics_pos = global_position
	var collision := move_and_collide(velocity * delta, false, COLLISION_SAFE_MARGIN)
	_handle_collision(collision, was_on_ground, prev_velocity)
	curr_physics_pos = global_position
	_physics_pos_initialized = true

	# If on ground (rollout / putt / grounded), ensure ball spin matches physical forward roll along ground normal
	if on_ground and (state == PhysicsEnums.BallState.ROLLOUT or is_putt):
		if velocity.length_squared() > 0.0001:
			omega = (floor_normal.cross(velocity)) / _ball_radius

	# Rotate ball mesh based on angular velocity (omega)
	if _ball_mesh != null and omega.length_squared() > 0.00001:
		var axis = omega.normalized()
		if axis.is_normalized():
			var angle = omega.length() * delta
			_ball_mesh.global_rotate(axis, angle)

	# Check for rest
	if velocity.length() < 0.1 and state != PhysicsEnums.BallState.REST:
		_enter_rest_state()


# TODO: this check needs to be updated for larger distances and below zero surfaces
func _check_out_of_bounds() -> bool:
	if absf(position.x) > 1000.0 or absf(position.z) > 1000.0:
		print("WARNING: Ball out of bounds at: ", position)
		_enter_rest_state()
		return true

	if global_position.y < BELOW_GROUND_RECOVERY_Y:
		if _try_recover_to_ground():
			return false
		if global_position.y > FALLTHROUGH_FAILSAFE_Y:
			return false
		print("WARNING: Ball fell through ground at: ", global_position)
		_enter_rest_state()
		return true

	return false


func _handle_collision(collision: KinematicCollision3D, was_on_ground: bool, prev_velocity: Vector3) -> void:
	if collision:
		var collider = collision.get_collider()
		var is_water_hit = collider != null and ((collider.has_meta("is_water") and bool(collider.get_meta("is_water"))) or collider.name.to_lower().contains("water"))
		if is_water_hit:
			is_in_water = true
			water_collider = collider
			velocity = Vector3.ZERO
			omega = Vector3.ZERO
			
			if _sfx_player != null and not _skipping_flight:
				_sfx_player.pitch_scale = randf_range(0.96, 1.04)
				_sfx_player.stream = _sfx_water_splash
				_sfx_player.play()
				
			_enter_rest_state()
			return

		var normal := collision.get_normal()

		var is_ground_norm := _is_ground_normal(normal)

		# Check for step-up / lip / mesh seam if rolling along ground (e.g. fringe-to-green collar or terrain seam)
		var is_rolling := was_on_ground or is_putt or state == PhysicsEnums.BallState.ROLLOUT
		if not is_ground_norm and is_rolling:
			var is_tree := _is_collider_tree(collider)
			if not is_tree:
				# Probe ahead across the edge to check if there is rollable ground on top of the step/lip
				var forward_dir := -Vector3(normal.x, 0.0, normal.z).normalized()
				if forward_dir.is_zero_approx():
					forward_dir = Vector3(prev_velocity.x, 0.0, prev_velocity.z).normalized()
				if not forward_dir.is_zero_approx():
					var probe_pos := collision.get_position() + forward_dir * 0.03
					var world := get_world_3d()
					if world != null:
						var step_query := PhysicsRayQueryParameters3D.create(probe_pos + Vector3.UP * 0.15, probe_pos + Vector3.DOWN * 0.25)
						step_query.collide_with_areas = false
						step_query.collide_with_bodies = true
						step_query.exclude = [get_rid()]
						var step_hit := world.direct_space_state.intersect_ray(step_query)
						if not step_hit.is_empty():
							var step_normal: Vector3 = step_hit["normal"]
							if _is_ground_normal(step_normal):
								var step_y: float = step_hit["position"].y
								var ball_bottom_y := global_position.y - _ball_radius
								var step_height := step_y - ball_bottom_y
								# Small step/lip up to 4cm (less than ball diameter) can be rolled over smoothly
								if step_height >= -0.02 and step_height <= 0.040:
									on_ground = true
									floor_normal = step_normal
									global_position.y = step_y + _ball_radius + GROUND_SNAP_OFFSET
									global_position += forward_dir * 0.005
									var prev_speed := prev_velocity.length()
									velocity = _remove_velocity_along_normal(prev_velocity, floor_normal)
									if velocity.length_squared() > 0.0001 and prev_speed > 0.05:
										velocity = velocity.normalized() * maxf(velocity.length(), prev_speed * 0.95)
									if step_hit.has("collider") and step_hit["collider"] != null:
										_update_surface_from_collider(step_hit["collider"])
									var remainder := collision.get_remainder()
									remainder = _remove_velocity_along_normal(remainder, floor_normal)
									if remainder.length_squared() > 0.000001:
										move_and_collide(remainder, false, COLLISION_SAFE_MARGIN)
									return

		if is_ground_norm:
			floor_normal = normal
			var prev_normal_velocity := prev_velocity.dot(normal)

			# Ignore ground collision depenetration on launch/ascent while in FLIGHT state.
			# For low-speed chip/pitch shots off turf, fringe collars, or uphill lies,
			# allow ground depenetration during initial launch (first 0.25s or while ascending)
			# rather than prematurely killing vertical loft into a ground rollout.
			var is_launch_ascent := state == PhysicsEnums.BallState.FLIGHT and (
				flight_time < 0.25
				or velocity.y > 0.05
				or prev_velocity.y > 0.05
				or prev_normal_velocity >= -0.15
			)
			if is_launch_ascent and prev_normal_velocity > -3.5:
				on_ground = false
				global_position += normal * (COLLISION_SAFE_MARGIN * 2.0 + 0.004)
				var remainder := collision.get_remainder()
				if remainder.length_squared() > 0.000001:
					move_and_collide(remainder, false, COLLISION_SAFE_MARGIN)
				return

			# Track if ball hit other ground outside the tee box
			if shot_was_from_teebox:
				var hit_dist = global_position.distance_to(shot_start_pos_global)
				var cname = collider.name.to_lower() if collider != null else ""
				if hit_dist > 3.0:
					shot_hit_other_ground = true
				elif cname.contains("fairway") or cname.contains("green") or cname.contains("rough") or cname.contains("bunker") or cname.contains("sand"):
					shot_hit_other_ground = true
				elif not cname.contains("tee") and hit_dist > 1.5:
					shot_hit_other_ground = true
			else:
				shot_hit_other_ground = true

			var is_landing := (state == PhysicsEnums.BallState.FLIGHT) or prev_normal_velocity < -0.5

			if is_landing:
				if collider != null:
					_update_surface_from_collider(collider)
					
				# Sync updated friction parameters to C# params before calculating bounce
				if params != null:
					_set_openfairway_property(params, &"kinetic_friction", &"KineticFriction", _kinetic_friction)
					_set_openfairway_property(params, &"rolling_friction", &"RollingFriction", _rolling_friction)
					_set_openfairway_property(params, &"grass_viscosity", &"GrassViscosity", _grass_viscosity)
					_set_openfairway_property(params, &"critical_angle", &"CriticalAngle", _critical_angle)
					_set_openfairway_property(params, &"surface_type", &"SurfaceType", surface_type)
					_set_openfairway_property(params, &"is_in_sand", &"IsInSand", is_in_sand or surface_type == PhysicsEnums.SurfaceType.BUNKER)

				if state == PhysicsEnums.BallState.FLIGHT:
					_print_impact_debug()
					rollout_impact_spin_rpm = omega.length() / 0.10472

				if _sfx_player != null and not _skipping_flight:
					_sfx_player.pitch_scale = randf_range(0.95, 1.05)
					if is_in_sand:
						_sfx_player.stream = _sfx_sand_thud
					elif lie_type == "green":
						_sfx_player.stream = _sfx_bounce_green
					elif lie_type == "fairway":
						_sfx_player.stream = _sfx_bounce_fairway
					elif lie_type == "rough":
						_sfx_player.stream = _sfx_rough_thump
					else:
						_sfx_player.stream = _sfx_bounce_fairway
					_sfx_player.play()

				var bounce_result = _call_openfairway_method(_physics, &"calculate_bounce", &"CalculateBounce", [velocity, omega, normal, state, params])
				if bounce_result == null:
					return
				velocity = _get_openfairway_property(bounce_result, &"new_velocity", &"NewVelocity", velocity)
				omega = _get_openfairway_property(bounce_result, &"new_omega", &"NewOmega", omega)
				state = int(_get_openfairway_property(bounce_result, &"new_state", &"NewState", state))

				var is_sand_surface = is_in_sand or (surface_type == PhysicsEnums.SurfaceType.BUNKER)
				if is_sand_surface:
					# Sand heavily deadens bounce height into a muffled pop (max normal vel 0.6 m/s)
					var normal_comp := velocity.dot(normal)
					if normal_comp > 0.6:
						velocity = velocity - (normal_comp - 0.6) * normal
					# Sand absorbs tangential momentum and immediately scrubs spin
					var tangent_vel := velocity - normal * velocity.dot(normal)
					if tangent_vel.length() > prev_velocity.length() * 0.25:
						velocity = (velocity.dot(normal) * normal) + (tangent_vel.normalized() * (prev_velocity.length() * 0.20))
					omega *= 0.15
				else:
					# Slightly scale the height of the bounce (normal component of velocity) based on green speed
					var green_speed : float = float(GlobalSettings.range_settings.green_speed.value)
					var bounce_sensitivity : float = 0.0025
					var bounce_mult : float = 1.0 + (green_speed - 10.0) * bounce_sensitivity
					var bounce_normal_vel := velocity.dot(normal)
					if bounce_normal_vel > 0.0:
						velocity = velocity - bounce_normal_vel * normal + (bounce_normal_vel * bounce_mult) * normal

				print("  Velocity after bounce: ", velocity, " (%.2f m/s)" % velocity.length())
				var normal_velocity := velocity.dot(normal)
				var grounding_threshold := 1.2 if is_sand_surface else 0.5
				if absf(normal_velocity) < grounding_threshold and state == PhysicsEnums.BallState.ROLLOUT:
					on_ground = true
					velocity = _remove_velocity_along_normal(velocity, normal)
					print("  -> Ball grounded, continuing roll at %.2f m/s" % velocity.length())
				else:
					on_ground = false
			else:
				# Rolling / putting contact on ground
				on_ground = true
				var prev_speed := velocity.length()
				velocity = _remove_velocity_along_normal(velocity, normal)
				# If internal mesh seam drastically killed horizontal roll speed, preserve momentum
				if prev_speed > 0.1 and velocity.length() < prev_speed * 0.90:
					if velocity.length_squared() > 0.0001:
						velocity = velocity.normalized() * (prev_speed * 0.98)
				# Slight depenetration along normal to prevent snagging on triangle mesh seams
				global_position += normal * (COLLISION_SAFE_MARGIN * 2.0 + GROUND_SNAP_OFFSET)
				# Continue motion along the slope tangent for the remainder of this frame
				var remainder := collision.get_remainder()
				remainder = _remove_velocity_along_normal(remainder, normal)
				if remainder.length_squared() > 0.000001:
					var col2 := move_and_collide(remainder, false, COLLISION_SAFE_MARGIN)
					if col2:
						var norm2 := col2.get_normal()
						if _is_ground_normal(norm2):
							floor_normal = norm2
							var p_spd2 := velocity.length()
							velocity = _remove_velocity_along_normal(velocity, norm2)
							if p_spd2 > 0.1 and velocity.length() < p_spd2 * 0.90:
								if velocity.length_squared() > 0.0001:
									velocity = velocity.normalized() * (p_spd2 * 0.98)
							global_position += norm2 * (COLLISION_SAFE_MARGIN * 2.0 + GROUND_SNAP_OFFSET)
		else:
			# Wall collision - damped reflection
			on_ground = false
			floor_normal = Vector3.UP
			var is_tree := _is_collider_tree(collider)
			if is_tree:
				if _sfx_player != null and not _skipping_flight:
					_sfx_player.pitch_scale = randf_range(0.95, 1.05)
					_sfx_player.stream = _sfx_tree_hit
					_sfx_player.play()

			# Damped reflection off vertical surfaces (walls, barriers, trees, etc.)
			velocity = velocity.bounce(normal) * 0.35
			omega = omega * 0.5
	else:
		# No collision - only stay grounded if terrain is still directly beneath the ball.
		if state != PhysicsEnums.BallState.FLIGHT and was_on_ground:
			var probe := _try_probe_ground()
			if bool(probe.get("hit", false)):
				on_ground = true
				floor_normal = probe.get("normal", Vector3.UP)
				# Snap ball height along normal to sit cleanly ontop of the surface without penetrating slopes
				var hit_pos: Vector3 = probe.get("position", Vector3.ZERO)
				global_position = hit_pos + floor_normal * (_ball_radius + GROUND_SNAP_OFFSET)
				# Align velocity with the slope tangent
				velocity = _remove_velocity_along_normal(velocity, floor_normal)
			else:
				on_ground = false
				floor_normal = Vector3.UP
		else:
			on_ground = false
			floor_normal = Vector3.UP


func _try_recover_to_ground() -> bool:
	var world := get_world_3d()

	var ray_start := global_position + Vector3.UP * GROUND_RAYCAST_UP
	var ray_end := global_position + Vector3.DOWN * GROUND_RAYCAST_DOWN
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var ray_hit := world.direct_space_state.intersect_ray(query)
	if ray_hit.is_empty():
		return false

	var hit_position: Vector3 = ray_hit["position"]
	var hit_normal: Vector3 = ray_hit["normal"]
	if hit_normal.length_squared() < 0.000001:
		hit_normal = Vector3.UP
	else:
		hit_normal = hit_normal.normalized()

	global_position = hit_position + hit_normal * (_ball_radius + GROUND_SNAP_OFFSET)
	floor_normal = hit_normal
	velocity = _remove_velocity_along_normal(velocity, hit_normal)
	on_ground = true

	if state == PhysicsEnums.BallState.FLIGHT:
		state = PhysicsEnums.BallState.ROLLOUT

	print("Recovered ball-to-ground at %s (normal: %s)" % [str(global_position), str(hit_normal)])
	return true


func _try_probe_ground() -> Dictionary:
	var world := get_world_3d()
	if world == null:
		return {"hit": false, "normal": Vector3.UP}

	var ray_start := global_position + Vector3.UP * 1.5
	var ray_end := global_position + Vector3.DOWN * 4.0
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]

	var ray_hit := world.direct_space_state.intersect_ray(query)
	if ray_hit.is_empty():
		return {"hit": false, "normal": Vector3.UP}

	var ground_normal: Vector3 = ray_hit["normal"]
	if ground_normal.length_squared() < 0.000001:
		ground_normal = Vector3.UP
	else:
		ground_normal = ground_normal.normalized()
	return {
		"hit": true,
		"normal": ground_normal,
		"position": ray_hit["position"],
		"collider": ray_hit.get("collider", null)
	}


func _is_ground_normal(normal: Vector3) -> bool:
	return normal.y > MIN_GROUND_NORMAL


func _remove_velocity_along_normal(source_velocity: Vector3, normal: Vector3) -> Vector3:
	var normal_component : Vector3= source_velocity.dot(normal)*normal
	return source_velocity - normal_component


func _print_impact_debug() -> void:
	print("FIRST IMPACT at pos: ", position, ", downrange: %.2f yds" % get_downrange_yards())
	print("  Velocity at impact: ", velocity, " (%.2f m/s)" % velocity.length())
	print("  Spin at impact: ", omega, " (%.0f rpm)" % (omega.length() / 0.10472))
	print("  Normal: ", floor_normal)


func get_target_hole_position() -> Vector3:
	var target_hole := Vector3.ZERO
	var player_parent = get_parent()
	if player_parent != null:
		var parent_scene = player_parent.get_parent()
		if parent_scene != null:
			if "current_hole_location" in parent_scene and not parent_scene.current_hole_location.is_zero_approx():
				target_hole = parent_scene.current_hole_location
			elif "holes" in parent_scene and "selected_hole_index" in parent_scene and not parent_scene.holes.is_empty():
				target_hole = parent_scene.holes[parent_scene.selected_hole_index]
			elif "island_positions" in parent_scene and "selected_island_index" in parent_scene and not parent_scene.island_positions.is_empty():
				target_hole = parent_scene.island_positions[parent_scene.selected_island_index]
	return target_hole


func _enter_rest_state() -> void:
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	state = PhysicsEnums.BallState.REST
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	emit_signal("rest")


func reset() -> void:
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	global_position = spawn_position
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	aim_yaw_offset_deg = 0.0
	launch_spin_rpm = 0.0
	rollout_impact_spin_rpm = 0.0
	is_putt = false
	shot_start_pos = spawn_position
	shot_start_pos_global = spawn_position
	target_dir = Vector3.RIGHT
	shot_was_in_sand = false
	shot_was_from_teebox = false
	shot_hit_other_ground = false
	_is_in_tree_canopy = false
	_tree_check_timer = 0.0
	_surface_check_timer = 0.0
	if _leaves_player and _leaves_player.playing:
		_leaves_player.stop()
	_cached_target_hole = get_target_hole_position()
	_surface_zone_stack.clear()
	if lie_type == "teebox" or lie_type == "fairway" or lie_type == "fringe":
		set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
	elif lie_type == "rough":
		set_surface(PhysicsEnums.SurfaceType.ROUGH)
	elif lie_type == "sand":
		set_surface(PhysicsEnums.SurfaceType.BUNKER)
		is_in_sand = true
	elif lie_type == "green":
		set_surface(PhysicsEnums.SurfaceType.GREEN)
	else:
		set_surface(int(GlobalSettings.range_settings.surface_type.value))
	state = PhysicsEnums.BallState.REST
	on_ground = false
	is_in_water = false
	if lie_type != "sand":
		is_in_sand = false
	water_collider = null
	is_falling_in_hole = false
	falling_target_hole = Vector3.ZERO
	falling_time = 0.0
	prev_physics_pos = global_position
	curr_physics_pos = global_position
	_physics_pos_initialized = true
	_update_tee_elevation()


func get_interpolated_position() -> Vector3:
	if state == PhysicsEnums.BallState.REST or not _physics_pos_initialized:
		return global_position
	var fraction = Engine.get_physics_interpolation_fraction()
	return prev_physics_pos.lerp(curr_physics_pos, fraction)


func _is_position_on_fringe(pos: Vector3) -> bool:
	if lie_type == "fringe":
		return true
	var player_parent = get_parent()
	if player_parent != null:
		if str(player_parent.get("current_lie_type")).to_lower() == "fringe":
			return true
		var course = player_parent.get_parent()
		if course != null and course.has_method("get_distance_to_nearest_green"):
			var d: float = course.get_distance_to_nearest_green(pos)
			if d > 0.001 and d <= 2.5:
				return true
	return false


func _check_is_on_teebox() -> bool:
	if lie_type == "teebox":
		return true
	var p_node = get_parent()
	if p_node != null and p_node.get("current_lie_type") == "teebox":
		return true
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty():
		var ap = mp_mgr.get_active_player()
		if ap != null:
			if ap.get("lie_type") == "teebox" or ap.get("strokes", 0) == 0:
				return true
	var course = get_tree().current_scene
	if course != null:
		if course.has_method("get_distance_to_nearest_teebox"):
			if course.call("get_distance_to_nearest_teebox", global_position) <= 2.0:
				return true
		if "practice_start_pos" in course and typeof(course.practice_start_pos) == TYPE_VECTOR3:
			if not course.practice_start_pos.is_zero_approx() and global_position.distance_to(course.practice_start_pos) < 2.5:
				return true
		if "shot_count" in course and course.shot_count == 0:
			return true
	return false


func hit() -> void:
	var target_hole = get_target_hole_position()
	var dist_to_target = global_position.distance_to(target_hole) if not target_hole.is_zero_approx() else 999.0
	var is_on_green = (lie_type == "green" or lie_type == "fringe" or _is_position_on_fringe(global_position) or current_selected_club.to_lower() in ["pt", "putt", "putter"])
	if is_on_green:
		var dist_to_hole = global_position.distance_to(target_hole) if not target_hole.is_zero_approx() else 5.0
		var putt_speed_mps = sqrt(2.0 * 0.48 * maxf(dist_to_hole, 0.5)) * 1.02
		var putt_speed_mph = putt_speed_mps * 2.23694
		var data := {
			"Speed": clampf(putt_speed_mph, 3.0, 25.0),
			"VLA": 0.0,
			"HLA": 0.0,
			"TotalSpin": 0.0,
			"SpinAxis": 0.0,
			"Club": "Pt",
			"ShotType": "putt"
		}
		hit_from_data(data)
	else:
		var data := {
			"Speed": 100.0,
			"VLA": 22.0,
			"HLA": -3.1,
			"TotalSpin": 6000.0,
			"SpinAxis": 3.5,
		}
		hit_from_data(data)


func hit_from_data(data: Dictionary) -> void:
	if not _try_initialize_ball():
		push_error("Cannot hit shot: OpenFairway classes are not available yet.")
		return
	is_in_water = false
	is_in_sand = false
	water_collider = null
	_hit_leaves_this_shot = false
	_is_in_tree_canopy = false
	_tree_check_timer = 0.0
	_surface_check_timer = 0.0
	_check_scene_has_trees()
	_cached_target_hole = get_target_hole_position()
	is_falling_in_hole = false
	falling_target_hole = Vector3.ZERO
	falling_time = 0.0
	flight_time = 0.0
	shot_hit_other_ground = false
	shot_was_from_teebox = _check_is_on_teebox()
	
	var speed_mph: float = float(data.get("Speed", 0.0))
	
	# Apply lie reduction penalty if any
	var reduction := 0.0
	var player_node = get_parent()
	if player_node != null:
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty():
			var active_player = mp_mgr.get_active_player()
			reduction = active_player.get("shot_reduction", 0.0)
		else:
			var val = player_node.get("current_shot_reduction")
			reduction = val if val != null else 0.0

	if reduction > 0.0:
		var prev_speed = speed_mph
		speed_mph = speed_mph * (1.0 - reduction)
		data["Speed"] = speed_mph
		print("[ball.gd] Shot reduction applied! Speed reduced from %.2f to %.2f (%.1f%% reduction)" % [prev_speed, speed_mph, reduction * 100.0])
		
		# Reset the reduction now that it has been applied to this shot
		if player_node != null:
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				var active_player = mp_mgr.get_active_player()
				active_player["shot_reduction"] = 0.0
				active_player["lie_type"] = "fairway"
			else:
				player_node.current_shot_reduction = 0.0
				player_node.current_lie_type = "fairway"

	var speed_mps: float = speed_mph * 0.44704  # mph to m/s
	var vla_deg: float = float(data.get("VLA", 0.0))
	var hla_deg: float = float(data.get("HLA", 0.0))

	var shot_type: String = str(data.get("ShotType", ""))
	var club_name: String = str(data.get("Club", data.get("club", current_selected_club)))
	if club_name != "":
		current_selected_club = club_name

	var is_driver := current_selected_club.to_lower() in ["dr", "driver", "1w"]
	var is_putter := current_selected_club.to_lower() in ["pt", "putt", "putter"]
	var is_teebox := (lie_type == "teebox")

	# Putt determination logic:
	# Driver shots, teebox shots, and full swings (> 45 mph) are strictly never putts.
	if is_driver or is_teebox or speed_mph > 45.0:
		is_putt = false
	elif is_putter or shot_type.to_lower() == "putt":
		# Putting stroke with putter or putt shot type: allow putting up to 14.0 deg VLA
		# (permits natural turf pops off fringe collar grass without converting into an airborne iron flight)
		is_putt = (vla_deg < 14.0)
	elif lie_type == "green" or lie_type == "fringe" or _is_position_on_fringe(global_position):
		is_putt = (vla_deg < 5.5) or (shot_type.to_lower() == "putt") or is_putter
	else:
		is_putt = (shot_type.to_lower() == "putt" and vla_deg < 5.5)

	# If VLA is 0 or unmeasured on a driver shot with high speed (> 45 mph),
	# default VLA to standard driver launch angle (11.5 deg) to prevent grounded rollout.
	if is_driver and vla_deg <= 0.01 and speed_mph > 45.0 and not is_putt:
		vla_deg = 11.5
		print("[ball.gd] Driver shot detected with zero/missing VLA. Auto-correcting VLA to 11.5 deg.")

	var spin_data: Dictionary = {}
	if _shot_setup != null:
		var parsed_spin = _call_openfairway_method(_shot_setup, &"parse_spin", &"ParseSpin", [data])
		if typeof(parsed_spin) == TYPE_DICTIONARY:
			spin_data = parsed_spin
	if spin_data.is_empty():
		spin_data = _parse_spin_data(data)
	var total_spin: float = spin_data.total
	var spin_axis: float = spin_data.axis

	var launch_data: Dictionary = {}
	if _shot_setup != null:
		var launch_result = _call_openfairway_method(
			_shot_setup,
			&"build_launch_vectors",
			&"BuildLaunchVectors",
			[speed_mph, vla_deg, hla_deg, total_spin, spin_axis]
		)
		if typeof(launch_result) == TYPE_DICTIONARY:
			launch_data = launch_result

	var launch_velocity: Vector3
	var launch_omega: Vector3
	var launch_direction: Vector3
	if launch_data.is_empty():
		launch_velocity = Vector3(speed_mps, 0, 0) \
			.rotated(Vector3.FORWARD, deg_to_rad(-vla_deg)) \
			.rotated(Vector3.UP, deg_to_rad(-hla_deg))
		var flat_velocity := Vector3(launch_velocity.x, 0.0, launch_velocity.z)
		launch_direction = flat_velocity.normalized() if flat_velocity.length() > 0.001 else Vector3.RIGHT
		launch_omega = Vector3(0.0, 0.0, total_spin * 0.10472) \
			.rotated(Vector3.RIGHT, deg_to_rad(spin_axis))
	else:
		launch_velocity = launch_data.get("velocity", Vector3.ZERO)
		launch_omega = launch_data.get("omega", Vector3.ZERO)
		launch_direction = launch_data.get("shot_direction", Vector3.RIGHT)

	if absf(aim_yaw_offset_deg) > 0.0001:
		var aim_yaw_rad := deg_to_rad(aim_yaw_offset_deg)
		launch_velocity = launch_velocity.rotated(Vector3.UP, aim_yaw_rad)
		launch_omega = launch_omega.rotated(Vector3.UP, aim_yaw_rad)
		launch_direction = launch_direction.rotated(Vector3.UP, aim_yaw_rad)
	launch_direction.y = 0.0
	if launch_direction.length_squared() < 0.000001:
		launch_direction = Vector3.RIGHT
	launch_direction = launch_direction.normalized()

	if is_putt:
		state = PhysicsEnums.BallState.ROLLOUT
		on_ground = true
		if lie_type == "fringe" or _is_position_on_fringe(global_position):
			set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		else:
			set_surface(PhysicsEnums.SurfaceType.GREEN)
		if _tee_mesh != null:
			_tee_mesh.visible = false
	else:
		state = PhysicsEnums.BallState.FLIGHT
		on_ground = false
		_surface_zone_stack.clear()
		if is_teebox or lie_type == "teebox":
			set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		elif lie_type == "fairway":
			set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		elif lie_type == "rough":
			set_surface(PhysicsEnums.SurfaceType.ROUGH)
		elif lie_type == "sand":
			set_surface(PhysicsEnums.SurfaceType.BUNKER)
		else:
			set_surface(int(GlobalSettings.range_settings.surface_type.value))
		if _tee_mesh != null:
			_tee_mesh.visible = false

	rollout_impact_spin_rpm = 0.0
	if position.length_squared() < 0.0001:
		position = Vector3(0.0, START_HEIGHT, 0.0)

	if is_putt:
		var probe := _try_probe_ground()
		if probe.get("hit", false):
			var hit_pos: Vector3 = probe.get("position", global_position)
			floor_normal = probe.get("normal", Vector3.UP)
			global_position = hit_pos + floor_normal * (_ball_radius + GROUND_SNAP_OFFSET)
		var speed_mag := speed_mps
		var flat_vel := Vector3(launch_velocity.x, 0.0, launch_velocity.z)
		if flat_vel.length_squared() > 0.000001:
			launch_velocity = flat_vel
		# Project launch velocity along the slope contour to avoid ramming into uphill slopes or floating
		launch_velocity = _remove_velocity_along_normal(launch_velocity, floor_normal)
		if launch_velocity.length_squared() > 0.000001:
			launch_velocity = launch_velocity.normalized() * speed_mag
		launch_omega = (floor_normal.cross(launch_velocity)) / _ball_radius
	else:
		# Airborne shots (driver, woods, irons, wedges)
		var probe := _try_probe_ground()
		if probe.get("hit", false):
			var ground_y: float = probe.get("position", Vector3.ZERO).y
			var target_launch_y: float
			if is_teebox:
				# Teebox shot: Driver is teed up 1.5 inches above ground; other clubs rest right on grass
				target_launch_y = ground_y + (TEED_CENTER_HEIGHT if is_driver else GROUND_CENTER_HEIGHT)
			else:
				target_launch_y = ground_y + GROUND_CENTER_HEIGHT + 0.005
			if global_position.y < target_launch_y:
				global_position.y = target_launch_y
		elif global_position.y < (GROUND_CENTER_HEIGHT + 0.005):
			global_position.y = GROUND_CENTER_HEIGHT + 0.005

	if params != null:
		_set_openfairway_property(params, &"initial_launch_angle_deg", &"InitialLaunchAngleDeg", vla_deg)

	velocity = launch_velocity
	omega = launch_omega
	shot_dir = launch_direction
	target_dir = Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(aim_yaw_offset_deg)).normalized()

	shot_start_pos = position
	shot_start_pos_global = global_position
	shot_was_in_sand = is_in_sand or (lie_type == "sand")
	launch_spin_rpm = total_spin

	_print_launch_debug(data, speed_mps, vla_deg, hla_deg, total_spin, spin_axis)

	# Play hit sound effect
	if _sfx_player != null:
		_sfx_player.volume_db = 0.0
		_sfx_player.pitch_scale = randf_range(0.97, 1.03)
		if is_putt:
			_sfx_player.stream = _sfx_hit_putt
		elif is_driver:
			_sfx_player.stream = _sfx_hit_drive
		else:
			_sfx_player.stream = _sfx_hit_other
		_sfx_player.play()


func _parse_spin_data(data: Dictionary) -> Dictionary:
	var has_backspin := data.has("BackSpin")
	var has_sidespin := data.has("SideSpin")
	var has_total := data.has("TotalSpin")
	var has_axis := data.has("SpinAxis")

	var backspin: float = float(data.get("BackSpin", 0.0))
	var sidespin: float = float(data.get("SideSpin", 0.0))
	var total_spin: float = float(data.get("TotalSpin", 0.0))
	var spin_axis: float = float(data.get("SpinAxis", 0.0))

	# Calculate missing values
	if total_spin == 0.0 and (has_backspin or has_sidespin):
		total_spin = sqrt(backspin * backspin + sidespin * sidespin)

	if not has_axis and (has_backspin or has_sidespin):
		spin_axis = rad_to_deg(atan2(sidespin, backspin))

	if has_total and has_axis:
		if not has_backspin:
			backspin = total_spin * cos(deg_to_rad(spin_axis))
		if not has_sidespin:
			sidespin = total_spin * sin(deg_to_rad(spin_axis))

	return {
		"backspin": backspin,
		"sidespin": sidespin,
		"total": total_spin,
		"axis": spin_axis
	}


func _print_launch_debug(data: Dictionary, speed_mps: float, vla: float, hla: float, spin: float, axis: float) -> void:
	print("=== SHOT DEBUG ===")
	print("Speed: %.2f mph (%.2f m/s)" % [data.get("Speed", 0.0), speed_mps])
	print("VLA: %.2f deg, HLA: %.2f deg" % [vla, hla])
	print("Aim yaw offset: %.2f deg" % aim_yaw_offset_deg)
	print("Spin: %.0f rpm, Axis: %.2f deg" % [spin, axis])
	print("drag_cf: %.2f, lift_cf: %.2f" % [_drag_scale, _lift_scale])
	print("Air density: %.4f kg/m^3" % _air_density)
	print("Dynamic viscosity: %.11f" % _air_viscosity)

	var Re_initial = _air_density * speed_mps * _ball_radius * 2.0 / _air_viscosity
	var spin_ratio = (spin * 0.10472) * _ball_radius / speed_mps if speed_mps > 0.1 else 0.0
	var cl_result = _call_openfairway_method(_aero, &"get_cl", &"GetCl", [Re_initial, spin_ratio])
	var Cl_initial = float(cl_result) if cl_result != null else 0.0
	print("Reynolds number: %.0f" % Re_initial)
	print("Spin ratio: %.3f" % spin_ratio)
	print("Cl (before scale): %.3f, after: %.3f" % [Cl_initial, Cl_initial * _lift_scale])
	print("Initial velocity: ", velocity)
	print("Initial omega: ", omega, " (%.0f rpm)" % (omega.length() / 0.10472))
	print("Shot direction: ", shot_dir)
	print("===================")
func _update_surface_from_collider(collider: Object) -> void:
	if collider == null:
		return
		
	if collider.has_meta("is_water") and bool(collider.get_meta("is_water")):
		var was_in_flight = (state != PhysicsEnums.BallState.REST)
		is_in_water = true
		water_collider = collider
		is_in_sand = false
		_enter_rest_state()
		if was_in_flight and _sfx_player != null and not _skipping_flight:
			_sfx_player.stream = _sfx_water_splash
			_sfx_player.play()
		return

	is_in_water = false
	water_collider = null

	var name_lower = collider.name.to_lower()
	var is_sand = (collider.has_meta("is_sand") and bool(collider.get_meta("is_sand"))) or name_lower.contains("bunker") or name_lower.contains("sand") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.BUNKER)
	var is_green = name_lower.contains("green") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.GREEN)
	var is_tee = name_lower.contains("tee")
	var is_fairway = name_lower.contains("fairway") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.FAIRWAY)
	var is_rough = name_lower.contains("rough") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.ROUGH)

	var changed_sand = (is_in_sand != is_sand)
	is_in_sand = is_sand

	if is_sand:
		lie_type = "sand"
		set_surface(PhysicsEnums.SurfaceType.BUNKER)
		if changed_sand:
			_apply_surface_params()
	elif is_green:
		lie_type = "green"
		set_surface(PhysicsEnums.SurfaceType.GREEN)
		if changed_sand:
			_apply_surface_params()
	elif is_tee:
		lie_type = "teebox"
		set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		if changed_sand:
			_apply_surface_params()
	elif is_fairway:
		lie_type = "fairway"
		set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		if changed_sand:
			_apply_surface_params()
	elif is_rough:
		if _is_position_on_fringe(global_position):
			lie_type = "fringe"
			set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		else:
			lie_type = "rough"
			set_surface(PhysicsEnums.SurfaceType.ROUGH)
		if changed_sand:
			_apply_surface_params()
	else:
		# Fallback to original checks
		if collider.has_meta("surface_type"):
			var st = int(collider.get_meta("surface_type"))
			set_surface(st)
			if name_lower.contains("green") or st == PhysicsEnums.SurfaceType.GREEN:
				lie_type = "green"
			elif st == PhysicsEnums.SurfaceType.BUNKER:
				lie_type = "sand"
				is_in_sand = true
			elif name_lower.contains("tee"):
				lie_type = "teebox"
			elif name_lower.contains("fairway") or st == PhysicsEnums.SurfaceType.FAIRWAY:
				lie_type = "fairway"
			elif name_lower.contains("rough") or st == PhysicsEnums.SurfaceType.ROUGH:
				if _is_position_on_fringe(global_position):
					lie_type = "fringe"
					set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
				else:
					lie_type = "rough"
			else:
				if _is_position_on_fringe(global_position):
					lie_type = "fringe"
					set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
				else:
					lie_type = "rough"
		else:
			if name_lower.contains("green"):
				set_surface(PhysicsEnums.SurfaceType.GREEN)
				lie_type = "green"
			elif name_lower.contains("tee"):
				set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
				lie_type = "teebox"
			elif name_lower.contains("fairway"):
				set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
				lie_type = "fairway"
			elif name_lower.contains("rough"):
				if _is_position_on_fringe(global_position):
					set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
					lie_type = "fringe"
				else:
					set_surface(PhysicsEnums.SurfaceType.ROUGH)
					lie_type = "rough"
			else:
				if _is_position_on_fringe(global_position):
					set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
					lie_type = "fringe"
				else:
					set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
					lie_type = "fairway"
		if changed_sand:
			_apply_surface_params()

func _update_surface_from_underneath() -> void:
	var world := get_world_3d()
	if world == null:
		return
	var query = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.DOWN * 0.6)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	
	# Exclude TerrainStatic and RoughStatic from initial search if possible
	# to prioritize hitting specific surface colliders first.
	if not _terrain_cache_searched:
		_terrain_cache_searched = true
		var curr = get_parent()
		while curr != null:
			if _cached_terrain_static == null:
				_cached_terrain_static = curr.get_node_or_null("TerrainStatic") as CollisionObject3D
			if _cached_rough_static == null:
				_cached_rough_static = curr.get_node_or_null("RoughStatic") as CollisionObject3D
			curr = curr.get_parent()
		
	if is_instance_valid(_cached_terrain_static):
		query.exclude.append(_cached_terrain_static.get_rid())
	if is_instance_valid(_cached_rough_static):
		query.exclude.append(_cached_rough_static.get_rid())
		
	# Collect all colliders hit at this point
	var hit_colliders: Array = []
	for attempt in range(4):
		var hit = world.direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider = hit["collider"]
		if collider:
			hit_colliders.append(collider)
			query.exclude.append(collider.get_rid())
		else:
			break

	if hit_colliders.is_empty():
		# Check if we are on the fringe bordering a green
		if _is_position_on_fringe(global_position):
			is_in_water = false
			water_collider = null
			var changed_sand = is_in_sand
			is_in_sand = false
			set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
			lie_type = "fringe"
			if changed_sand:
				_apply_surface_params()
			return

		# If the ray hit nothing specific, we are on the base rough terrain!
		is_in_water = false
		water_collider = null
		var changed_sand = is_in_sand
		is_in_sand = false
		set_surface(PhysicsEnums.SurfaceType.ROUGH)
		lie_type = "rough"
		if changed_sand:
			_apply_surface_params()
		return

	# Evaluate which is the highest-priority collider
	var best_collider = null
	var best_priority = -1 # Higher is better

	for collider in hit_colliders:
		var priority = 0
		
		# 1. Check for water
		if collider.has_meta("is_water") and bool(collider.get_meta("is_water")):
			priority = 6
		# 2. Check for sand
		elif (collider.has_meta("is_sand") and bool(collider.get_meta("is_sand"))) or collider.name.to_lower().contains("bunker") or collider.name.to_lower().contains("sand") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.BUNKER):
			priority = 5
		# 3. Check for green
		elif collider.name.to_lower().contains("green") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.GREEN):
			priority = 4
		# 4. Check for tee
		elif collider.name.to_lower().contains("tee"):
			priority = 3
		# 5. Check for fairway
		elif collider.name.to_lower().contains("fairway") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.FAIRWAY):
			priority = 2
		# 6. Check for rough
		elif collider.name.to_lower().contains("rough") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.ROUGH):
			priority = 1
		else:
			# Unknown/default priority
			priority = 0
			
		if priority > best_priority:
			best_priority = priority
			best_collider = collider

	if best_collider != null:
		_update_surface_from_collider(best_collider)
