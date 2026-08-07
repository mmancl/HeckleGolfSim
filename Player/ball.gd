extends CharacterBody3D
class_name GolfBall

signal rest

const START_HEIGHT := 0.02
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
var spawn_position := Vector3(0.0, START_HEIGHT, 0.0)

# Preloaded sound streams
var _sfx_hit_drive = preload("res://assets/audio/sfx/ball_hit_drive.ogg")
var _sfx_hit_putt = preload("res://assets/audio/sfx/ball_hit_putt.ogg")
var _sfx_tree_hit = preload("res://assets/audio/sfx/tree_hit.ogg")
var _sfx_leaf_rustle = preload("res://assets/audio/sfx/leaf_rustle.ogg")
var _sfx_water_splash = preload("res://assets/audio/sfx/water_splash.ogg")
var _sfx_sand_thud = preload("res://assets/audio/sfx/sand_thud.ogg")
var _sfx_bounce_fairway = preload("res://assets/audio/sfx/bounce_fairway.ogg")
var _sfx_bounce_green = preload("res://assets/audio/sfx/bounce_green.ogg")
var _sfx_rough_thump = preload("res://assets/audio/sfx/rough_thump.ogg")

# SFX players
var _sfx_player: AudioStreamPlayer = null
var _leaves_player: AudioStreamPlayer = null
var _detection_area: Area3D = null

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
var shot_dir := Vector3(1.0, 0.0, 0.0)  # Normalized horizontal direction
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


func _has_openfairway_property(target: Object, property_name: StringName) -> bool:
	if target == null:
		return false
	for property_info in target.get_property_list():
		if StringName(property_info.get("name", "")) == property_name:
			return true
	return false


func _get_openfairway_property(target: Object, snake_name: StringName, pascal_name: StringName, default_value = null):
	if _has_openfairway_property(target, snake_name):
		return target.get(snake_name)
	if _has_openfairway_property(target, pascal_name):
		return target.get(pascal_name)
	return default_value


func _set_openfairway_property(target: Object, snake_name: StringName, pascal_name: StringName, value) -> bool:
	if _has_openfairway_property(target, snake_name):
		target.set(snake_name, value)
		return true
	if _has_openfairway_property(target, pascal_name):
		target.set(pascal_name, value)
		return true
	return false


func _call_openfairway_method(target: Object, snake_name: StringName, pascal_name: StringName, args: Array = []):
	if target == null:
		return null
	if target.has_method(snake_name):
		return target.callv(snake_name, args)
	if target.has_method(pascal_name):
		return target.callv(pascal_name, args)
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

	# Create canopy detection area on the ball
	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 1
	var detect_collision = CollisionShape3D.new()
	var detect_shape = SphereShape3D.new()
	detect_shape.radius = _ball_radius
	detect_collision.shape = detect_shape
	_detection_area.add_child(detect_collision)
	add_child(_detection_area)


func _connect_settings() -> void:
	GlobalSettings.range_settings.temperature.setting_changed.connect(_on_environment_changed)
	GlobalSettings.range_settings.altitude.setting_changed.connect(_on_environment_changed)
	GlobalSettings.range_settings.range_units.setting_changed.connect(_on_environment_changed)
	GlobalSettings.range_settings.surface_type.setting_changed.connect(_on_surface_type_changed)
	GlobalSettings.range_settings.green_speed.setting_changed.connect(_on_green_speed_changed)


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
		surface_params = {"u_k": 0.30, "u_kr": 0.03, "nu_g": 0.0010, "theta_c": 0.25}
	_kinetic_friction = float(surface_params.get("u_k", 0.30)) * _kinetic_mult
	_rolling_friction = float(surface_params.get("u_kr", 0.03)) * _rolling_mult
	
	# Determine green speed scaling exponent based on surface type
	var green_speed = float(GlobalSettings.range_settings.green_speed.value)
	var exponent := 0.0
	if is_in_sand:
		exponent = 0.05
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


func get_downrange_yards() -> float:
	var delta: Vector3 = position - shot_start_pos
	var meters: float = delta.dot(shot_dir)
	return meters * 1.09361


func _process(_delta: float) -> void:
	if _ball_mesh != null:
		if is_in_sand:
			_ball_mesh.position.y = -0.017 # Sink 1.7 cm in sand traps
		elif lie_type == "rough":
			_ball_mesh.position.y = -0.014 # Sink 1/3 of ball diameter
		elif lie_type == "green" or surface_type == PhysicsEnums.SurfaceType.GREEN or is_putt:
			_ball_mesh.position.y = 0.005 # Float ontop of the ground (e.g. 5mm)
		else:
			_ball_mesh.position.y = 0.0


func _physics_process(delta: float) -> void:
	if state == PhysicsEnums.BallState.REST:
		return

	# Check if we should fall into the hole
	if not is_falling_in_hole:
		var target_hole = null
		var parent_scene = get_parent().get_parent()
		if parent_scene != null:
			if "current_hole_location" in parent_scene:
				target_hole = parent_scene.current_hole_location
			elif "holes" in parent_scene and "selected_hole_index" in parent_scene:
				target_hole = parent_scene.holes[parent_scene.selected_hole_index]
		
		if target_hole != null and not target_hole.is_zero_approx():
			var ball_pos = global_position
			var dist_2d = Vector2(ball_pos.x, ball_pos.z).distance_to(Vector2(target_hole.x, target_hole.z))
			var vertical_diff = ball_pos.y - target_hole.y
			# Only drop if the ball is close to the ground/green height
			if vertical_diff > -0.05 and vertical_diff < 0.15:
				var cup_radius := 0.12
				var speed = velocity.length()
				if dist_2d < cup_radius:
					# Drop in if rolling slow enough or very close to center
					if speed < 3.0 or dist_2d < 0.04:
						is_falling_in_hole = true
						falling_target_hole = target_hole
						falling_time = 0.0
						velocity = Vector3.ZERO
						omega = Vector3.ZERO

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

	_update_surface_from_underneath()

	var was_on_ground := on_ground
	var prev_velocity := velocity

	if params != null:
		_set_openfairway_property(params, &"floor_normal", &"FloorNormal", floor_normal)
		_set_openfairway_property(params, &"rollout_impact_spin", &"RolloutImpactSpin", rollout_impact_spin_rpm)
		_set_openfairway_property(params, &"kinetic_friction", &"KineticFriction", _kinetic_friction)
		_set_openfairway_property(params, &"rolling_friction", &"RollingFriction", _rolling_friction)
		_set_openfairway_property(params, &"grass_viscosity", &"GrassViscosity", _grass_viscosity)
		_set_openfairway_property(params, &"critical_angle", &"CriticalAngle", _critical_angle)
		_set_openfairway_property(params, &"surface_type", &"SurfaceType", surface_type)
		_set_openfairway_property(params, &"slope_force_scale", &"SlopeForceScale", slope_force_scale)

	# Calculate forces and torques using BallPhysics
	var total_force = _call_openfairway_method(_physics, &"calculate_forces", &"CalculateForces", [velocity, omega, was_on_ground, params])
	var total_torque = _call_openfairway_method(_physics, &"calculate_torques", &"CalculateTorques", [velocity, omega, was_on_ground, params])
	if total_force == null or total_torque == null:
		return

	# Update velocity and angular velocity
	velocity += (total_force / _ball_mass) * delta
	omega += (total_torque / _ball_moi) * delta

	# Apply tree leaves reduction/damping
	if state == PhysicsEnums.BallState.FLIGHT:
		var inside_canopy := false
		var detection_area = get_node_or_null("DetectionArea")
		if detection_area:
			var overlapping_areas = detection_area.get_overlapping_areas()
			for area in overlapping_areas:
				if area.name == "CanopyArea" or area.has_meta("is_canopy"):
					inside_canopy = true
					break
		
		if inside_canopy:
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
	var collision := move_and_collide(velocity * delta, false, COLLISION_SAFE_MARGIN)
	_handle_collision(collision, was_on_ground, prev_velocity)

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
		if collider != null and collider.has_meta("is_water") and bool(collider.get_meta("is_water")):
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

		if _is_ground_normal(normal):
			floor_normal = normal
			var prev_normal_velocity := prev_velocity.dot(normal)
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

				# Slightly scale the height of the bounce (normal component of velocity) based on green speed
				var green_speed : float = float(GlobalSettings.range_settings.green_speed.value)
				var bounce_sensitivity : float = 0.0025
				var bounce_mult : float = 1.0 + (green_speed - 10.0) * bounce_sensitivity
				var bounce_normal_vel := velocity.dot(normal)
				if bounce_normal_vel > 0.0:
					velocity = velocity - bounce_normal_vel * normal + (bounce_normal_vel * bounce_mult) * normal

				print("  Velocity after bounce: ", velocity, " (%.2f m/s)" % velocity.length())
				var normal_velocity := velocity.dot(normal)
				if absf(normal_velocity) < 0.5 and state == PhysicsEnums.BallState.ROLLOUT:
					on_ground = true
					velocity = _remove_velocity_along_normal(velocity, normal)
					print("  -> Ball grounded, continuing roll at %.2f m/s" % velocity.length())
				else:
					on_ground = false
			else:
				on_ground = true
				velocity = _remove_velocity_along_normal(velocity, normal)
		else:
			# Wall collision - damped reflection
			on_ground = false
			floor_normal = Vector3.UP
			velocity = velocity.bounce(normal) * 0.30
			
			if collider != null and collider.name.to_lower().contains("tree"):
				if _sfx_player != null and not _skipping_flight:
					_sfx_player.pitch_scale = randf_range(0.95, 1.05)
					_sfx_player.stream = _sfx_tree_hit
					_sfx_player.play()
	else:
		# No collision - only stay grounded if terrain is still directly beneath the ball.
		var probe := _try_probe_ground()
		if state != PhysicsEnums.BallState.FLIGHT and was_on_ground and bool(probe.get("hit", false)):
			on_ground = true
			floor_normal = probe.get("normal", Vector3.UP)
			# Snap ball height to the ground to prevent floating when rolling down slopes
			var hit_pos = probe.get("position", Vector3.ZERO)
			global_position.y = hit_pos.y + _ball_radius
			# Align velocity with the slope tangent
			velocity = _remove_velocity_along_normal(velocity, floor_normal)
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

	var ray_start := global_position + Vector3.UP * 0.05
	var ray_end := global_position + Vector3.DOWN * (_ball_radius + GROUND_PROBE_DISTANCE)
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
	return {"hit": true, "normal": ground_normal, "position": ray_hit["position"]}


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


func _enter_rest_state() -> void:
	state = PhysicsEnums.BallState.REST
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	emit_signal("rest")


func reset() -> void:
	global_position = spawn_position
	velocity = Vector3.ZERO
	omega = Vector3.ZERO
	aim_yaw_offset_deg = 0.0
	launch_spin_rpm = 0.0
	rollout_impact_spin_rpm = 0.0
	is_putt = false
	_surface_zone_stack.clear()
	set_surface(int(GlobalSettings.range_settings.surface_type.value))
	state = PhysicsEnums.BallState.REST
	on_ground = false
	is_in_water = false
	is_in_sand = false
	water_collider = null
	is_falling_in_hole = false
	falling_target_hole = Vector3.ZERO
	falling_time = 0.0


func hit() -> void:
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
	is_falling_in_hole = false
	falling_target_hole = Vector3.ZERO
	falling_time = 0.0
	
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

	var shot_type: String = str(data.get("ShotType", ""))
	var club_name: String = str(data.get("Club", data.get("club", "")))
	is_putt = shot_type.to_lower() == "putt" or club_name.to_lower() in ["pt", "putt", "putter"]

	if is_putt:
		state = PhysicsEnums.BallState.ROLLOUT
		on_ground = true
		set_surface(PhysicsEnums.SurfaceType.GREEN)
	else:
		state = PhysicsEnums.BallState.FLIGHT
		on_ground = false
		_surface_zone_stack.clear()
		set_surface(int(GlobalSettings.range_settings.surface_type.value))

	rollout_impact_spin_rpm = 0.0
	if position.length_squared() < 0.0001:
		position = Vector3(0.0, START_HEIGHT, 0.0)

	if is_putt:
		var probe := _try_probe_ground()
		if probe.get("hit", false):
			global_position.y = probe.get("position", Vector3.ZERO).y + _ball_radius
			floor_normal = probe.get("normal", Vector3.UP)
		launch_velocity.y = 0.0
		var flat_vel := Vector3(launch_velocity.x, 0.0, launch_velocity.z)
		if flat_vel.length_squared() > 0.000001:
			launch_velocity = flat_vel

	velocity = launch_velocity
	omega = launch_omega
	shot_dir = launch_direction

	shot_start_pos = position
	launch_spin_rpm = total_spin

	_print_launch_debug(data, speed_mps, vla_deg, hla_deg, total_spin, spin_axis)

	# Play hit sound effect
	if _sfx_player != null:
		_sfx_player.volume_db = 0.0
		_sfx_player.pitch_scale = randf_range(0.97, 1.03)
		if is_putt:
			_sfx_player.stream = _sfx_hit_putt
		else:
			_sfx_player.stream = _sfx_hit_drive
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
	var is_sand = (collider.has_meta("is_sand") and bool(collider.get_meta("is_sand"))) or name_lower.contains("bunker") or name_lower.contains("sand")
	var is_green = name_lower.contains("green") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == 4)
	var is_tee = name_lower.contains("tee")
	var is_fairway = name_lower.contains("fairway") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == 0)
	var is_rough = name_lower.contains("rough") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == 2)

	var changed_sand = (is_in_sand != is_sand)
	is_in_sand = is_sand

	if is_sand:
		lie_type = "sand"
		set_surface(PhysicsEnums.SurfaceType.ROUGH)
		if changed_sand:
			_apply_surface_params()
	elif is_green:
		lie_type = "green"
		set_surface(PhysicsEnums.SurfaceType.GREEN)
		if changed_sand:
			_apply_surface_params()
	elif is_tee or is_fairway:
		lie_type = "fairway"
		set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		if changed_sand:
			_apply_surface_params()
	elif is_rough:
		lie_type = "rough"
		set_surface(PhysicsEnums.SurfaceType.ROUGH)
		if changed_sand:
			_apply_surface_params()
	else:
		# Fallback to original checks
		if collider.has_meta("surface_type"):
			var st = int(collider.get_meta("surface_type"))
			set_surface(st)
			if name_lower.contains("green") or st == 4:
				lie_type = "green"
			elif name_lower.contains("fairway") or name_lower.contains("tee") or st == 0:
				lie_type = "fairway"
			elif name_lower.contains("rough") or st == 2:
				lie_type = "rough"
			else:
				lie_type = "rough"
		else:
			if name_lower.contains("green"):
				set_surface(PhysicsEnums.SurfaceType.GREEN)
				lie_type = "green"
			elif name_lower.contains("fairway") or name_lower.contains("tee"):
				set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
				lie_type = "fairway"
			elif name_lower.contains("rough"):
				set_surface(PhysicsEnums.SurfaceType.ROUGH)
				lie_type = "rough"
			else:
				set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
				lie_type = "fairway"
		if changed_sand:
			_apply_surface_params()

func _update_surface_from_underneath() -> void:
	var world := get_world_3d()
	if world == null:
		return
	var query = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.1, global_position + Vector3.DOWN * 0.3)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	
	# Exclude TerrainStatic and RoughStatic from initial search if possible
	# to prioritize hitting specific surface colliders first.
	var terrain_static = null
	var rough_static = null
	var curr = get_parent()
	while curr != null:
		if terrain_static == null:
			terrain_static = curr.get_node_or_null("TerrainStatic")
		if rough_static == null:
			rough_static = curr.get_node_or_null("RoughStatic")
		curr = curr.get_parent()
		
	if terrain_static:
		query.exclude.append(terrain_static.get_rid())
	if rough_static:
		query.exclude.append(rough_static.get_rid())
		
	# Collect all colliders hit at this point
	var hit_colliders: Array = []
	for attempt in range(5):
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
		elif (collider.has_meta("is_sand") and bool(collider.get_meta("is_sand"))) or collider.name.to_lower().contains("bunker") or collider.name.to_lower().contains("sand"):
			priority = 5
		# 3. Check for green
		elif collider.name.to_lower().contains("green") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == 4):
			priority = 4
		# 4. Check for tee
		elif collider.name.to_lower().contains("tee"):
			priority = 3
		# 5. Check for fairway
		elif collider.name.to_lower().contains("fairway") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == 0):
			priority = 2
		# 6. Check for rough
		elif collider.name.to_lower().contains("rough") or (collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == 2):
			priority = 1
		else:
			# Unknown/default priority
			priority = 0
			
		if priority > best_priority:
			best_priority = priority
			best_collider = collider

	if best_collider != null:
		_update_surface_from_collider(best_collider)
