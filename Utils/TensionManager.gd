extends Node

# TensionManager: Manages heartbeat SFX, pulsing screen border vignette,
# early trajectory prediction suspense, and camera tension effects for close putts and chips.

signal tension_started(mode: String)
signal tension_stopped()

const PUTT_THRESHOLD_METERS := 3.048   # 10 feet in meters (10.0 * 0.3048)
const CHIP_THRESHOLD_METERS := 7.62    # 25 feet in meters (25.0 * 0.3048)
const PUTT_MIN_SUSPENSE_DISTANCE_METERS := 6.096   # 20 feet in meters (20.0 * 0.3048)
const CHIP_MIN_SUSPENSE_DISTANCE_METERS := 30.48   # 100 feet in meters (100.0 * 0.3048)
const MAX_PROJECTED_LANDING_DISTANCE_METERS := 18.288 # 20 yards in meters (20.0 * 0.9144)
const PAST_HOLE_THRESHOLD_METERS := 0.3048         # 1 foot past the hole in meters (1.0 * 0.3048)
const CYCLE_DURATION := 0.80          # ~75 BPM double-thump heartbeat cycle
const CONE_HALF_ANGLE_DEG := 15.0
const MIN_COS_THETA := 0.965925826    # cos(15 deg)
const CUP_RADIUS_METERS := 0.054       # 4.25 in / 2 (standard golf cup)
const MAX_HOLEABLE_SPEED_MPS := 2.8    # Max entry speed into cup

enum SuspenseState {
	IDLE,    # Before shot launched
	READY,   # Shot launched & trajectory validated to enter cup; awaiting apex & cone criteria
	ACTIVE,  # Suspense active (heartbeat, vignette, cone tracking)
	SPENT    # Shot missed, completed, overshot, or broken offline; latched out for remainder of shot
}

var suspense_state: SuspenseState = SuspenseState.IDLE
var shot_validated: bool = false

# Predicted trajectory data
var predicted_apex: Vector3 = Vector3.ZERO
var predicted_land_pos: Vector3 = Vector3.ZERO
var predicted_land_vel: Vector3 = Vector3.ZERO
var predicted_roll_path: Array[Vector3] = []
var predicted_holed_out: bool = false

var tension_active: bool = false
var current_mode: String = ""
var current_intensity: float = 0.0
var current_closeness: float = 0.0
var pulse_timer: float = 0.0
var current_pulse: float = 0.0

var _is_scheduled: bool = false
var _scheduled_mode: String = ""
var _closest_dist_reached: float = 9999.0
var _has_entered_suspense_zone: bool = false
var _shot_suspense_locked_out: bool = false
var _tree_hit_this_shot: bool = false
var _suspense_predicted_close: bool = false
var _predicted_ending_dist: float = 0.0

# Visual nodes
var canvas_layer: CanvasLayer = null
var vignette_rect: ColorRect = null
var vignette_material: ShaderMaterial = null

# Audio player
var sfx_player: AudioStreamPlayer = null
var _heartbeat_stream: AudioStream = null

# Camera tracking
var target_camera: Camera3D = null
var base_camera_fov: float = 55.0

# Scene-level caching for is_course_play_active
var _cached_scene_ref: WeakRef = null
var _cached_is_course_play: bool = false
var _cached_practice_mode: bool = false
var _cached_players_empty: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_visuals()
	_setup_audio()
	print("[TensionManager] Ready and initialized.")


func _setup_visuals() -> void:
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "TensionCanvasLayer"
	canvas_layer.layer = 20 # Render above 3D world and gameplay UI, below debug/dialogs
	add_child(canvas_layer)

	vignette_rect = ColorRect.new()
	vignette_rect.name = "HeartbeatVignetteRect"
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_rect.anchor_left = 0.0
	vignette_rect.anchor_top = 0.0
	vignette_rect.anchor_right = 1.0
	vignette_rect.anchor_bottom = 1.0
	vignette_rect.offset_left = 0.0
	vignette_rect.offset_top = 0.0
	vignette_rect.offset_right = 0.0
	vignette_rect.offset_bottom = 0.0
	vignette_rect.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vignette_rect.grow_vertical = Control.GROW_DIRECTION_BOTH

	var shader_path = "res://Courses/Environments/shaders/heartbeat_vignette.gdshader"
	var shader = load(shader_path) as Shader
	if shader != null:
		vignette_material = ShaderMaterial.new()
		vignette_material.shader = shader
		vignette_material.set_shader_parameter("intensity", 0.0)
		vignette_material.set_shader_parameter("pulse", 0.0)
		vignette_material.set_shader_parameter("closeness", 0.0)
		vignette_rect.material = vignette_material
	else:
		push_warning("[TensionManager] Could not load heartbeat_vignette.gdshader")

	vignette_rect.visible = false
	canvas_layer.add_child(vignette_rect)

func _setup_audio() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "HeartbeatAudioPlayer"
	sfx_player.bus = "Master"
	add_child(sfx_player)

	var ogg_path = "res://assets/audio/sfx/heartbeat.ogg"
	var wav_path = "res://assets/audio/sfx/heartbeat.wav"

	# Method 1: Load directly from file via AudioStreamOggVorbis
	if ClassDB.class_exists("AudioStreamOggVorbis") and FileAccess.file_exists(ogg_path):
		var ogg_stream = AudioStreamOggVorbis.load_from_file(ogg_path)
		if ogg_stream != null:
			ogg_stream.loop = true
			_heartbeat_stream = ogg_stream

	# Method 2: Fallback to ResourceLoader
	if _heartbeat_stream == null:
		if ResourceLoader.exists(ogg_path):
			_heartbeat_stream = load(ogg_path)
		elif ResourceLoader.exists(wav_path):
			_heartbeat_stream = load(wav_path)

	# Method 3: Procedural AudioStreamWAV fallback (guarantees punchy sound ALWAYS plays)
	if _heartbeat_stream == null:
		_heartbeat_stream = _create_procedural_heartbeat_wav()

	if _heartbeat_stream != null:
		sfx_player.stream = _heartbeat_stream
		sfx_player.finished.connect(func():
			if tension_active:
				sfx_player.play()
		)
		print("[TensionManager] Heartbeat audio initialized successfully.")

func _create_procedural_heartbeat_wav() -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	
	var dur = 3.2
	var num_samples = int(dur * 22050)
	var stream_data = PackedByteArray()
	stream_data.resize(num_samples * 2)
	
	for i in range(num_samples):
		var t = float(i) / 22050.0
		var t_cycle = fmod(t, 0.8)
		var sample_val = 0.0
		
		# S1 at 0.0s (Audible thump + harmonic punch)
		if t_cycle < 0.22:
			var env = exp(-t_cycle * 16.0)
			var freq1 = 85.0 - 30.0 * (t_cycle / 0.22)
			var freq2 = 140.0 - 50.0 * (t_cycle / 0.22)
			sample_val += sin(TAU * freq1 * t_cycle) * env * 0.85
			sample_val += sin(TAU * freq2 * t_cycle) * env * 0.55
			sample_val += sin(TAU * 240.0 * t_cycle) * exp(-t_cycle * 35.0) * 0.30
		# S2 at 0.28s (Audible valve snap + body resonance)
		elif t_cycle >= 0.28 and t_cycle < 0.46:
			var dt2 = t_cycle - 0.28
			var env2 = exp(-dt2 * 20.0)
			var freq1 = 110.0 - 35.0 * (dt2 / 0.18)
			var freq2 = 180.0
			sample_val += (sin(TAU * freq1 * dt2) * env2 * 0.75 + sin(TAU * freq2 * dt2) * exp(-dt2 * 28.0) * 0.55 + sin(TAU * 310.0 * dt2) * exp(-dt2 * 40.0) * 0.28) * 0.90
			
		var saturated = tanh(sample_val * 1.5)
		var pcm16 = int(clamp(saturated, -1.0, 1.0) * 31500.0)
		stream_data.encode_s16(i * 2, pcm16)
		
	stream.data = stream_data
	return stream

func is_active() -> bool:
	return tension_active

var force_course_play_active_for_testing: bool = false

func is_course_play_active() -> bool:
	if force_course_play_active_for_testing:
		return true
	# 1. Global Settings minigame and menu checks
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs != null:
		if gs.is_minigames_scene() or gs.is_chipping_minigame or gs.is_putting_minigame:
			return false
		if gs.is_menu_screen():
			return false

	# 2. MultiplayerManager checks (Course Play requires active round without practice mode)
	var mp = get_node_or_null("/root/MultiplayerManager")
	var players_empty = (mp != null and mp.players.is_empty())
	var mp_practice = (mp != null and mp.practice_mode_active)
	if mp_practice or (players_empty and not (get_tree() != null and get_tree().current_scene != null and get_tree().current_scene.has_node("CoursePlay"))):
		return false

	# 3. Active Scene checks
	var tree = get_tree()
	if tree == null:
		return false
	var current_scene = tree.current_scene
	if current_scene == null:
		return false

	var practice_mode = (current_scene.get("practice_mode_active") == true)

	if _cached_scene_ref != null and _cached_scene_ref.get_ref() == current_scene \
		and _cached_practice_mode == practice_mode and _cached_players_empty == players_empty:
		return _cached_is_course_play

	_cached_scene_ref = weakref(current_scene)
	_cached_practice_mode = practice_mode
	_cached_players_empty = players_empty

	if practice_mode:
		_cached_is_course_play = false
		return false

	var scene_name = str(current_scene.name).to_lower()
	var script: Script = current_scene.get_script()
	var script_path = str(script.resource_path).to_lower() if script != null else ""
	var scene_path = str(current_scene.scene_file_path).to_lower() if "scene_file_path" in current_scene else ""
	var full_id = (scene_name + " " + script_path + " " + scene_path).to_lower()

	# Exclude menus and setup screens
	if full_id.contains("main_menu") or full_id.contains("mainmenu") \
		or full_id.contains("course_selector") or full_id.contains("courseselector") \
		or full_id.contains("course_play_setup") or full_id.contains("courseplaysetup") \
		or full_id.contains("minigames_menu") or full_id.contains("minigamesmenu") \
		or full_id.contains("players_menu") or full_id.contains("playersmenu") \
		or full_id.contains("analytics") or full_id.contains("history") \
		or full_id.contains("custom_course_creator") or full_id.contains("osm_download") \
		or full_id.contains("course_preview"):
		_cached_is_course_play = false
		return false

	# Exclude all Minigames
	if full_id.contains("chipping") or full_id.contains("putting") \
		or full_id.contains("loft_control") or full_id.contains("shape_practice") \
		or full_id.contains("minigame") or full_id.contains("minigames"):
		_cached_is_course_play = false
		return false

	# Exclude standalone Driving Range
	if (scene_name == "range" or scene_path.ends_with("range.tscn")) and not current_scene.has_node("CoursePlay"):
		_cached_is_course_play = false
		return false

	# Must have CoursePlay node or be a course scene with active hole play
	if current_scene.has_node("CoursePlay") or scene_name == "courseplay" or full_id.contains("course_play") or full_id.contains("usercourses") or scene_name.contains("course"):
		_cached_is_course_play = true
		return true

	_cached_is_course_play = false
	return false

# ---------------- SUSPENSE ELIGIBILITY ----------------

func is_shot_eligible_for_suspense(start_pos: Vector3, target_pos: Vector3, is_putt: bool, _is_sand: bool = false) -> bool:
	if not is_course_play_active() or _shot_suspense_locked_out or _tree_hit_this_shot:
		return false
	if target_pos.is_zero_approx():
		return false
	var dist_2d = Vector2(start_pos.x, start_pos.z).distance_to(Vector2(target_pos.x, target_pos.z))
	if dist_2d < 0.05:
		return false
	# Use small epsilon (0.01m / ~0.4 in) to avoid floating point precision rounding dropouts
	if is_putt:
		return (dist_2d + 0.01) >= PUTT_MIN_SUSPENSE_DISTANCE_METERS
	else:
		return (dist_2d + 0.01) >= CHIP_MIN_SUSPENSE_DISTANCE_METERS

# ---------------- TRAJECTORY PREDICTION ----------------

func predict_shot_outcome(start_pos: Vector3, launch_vel: Vector3, is_putt: bool, target_pos: Vector3, is_sand: bool = false) -> Dictionary:
	if not is_course_play_active() or _shot_suspense_locked_out or _tree_hit_this_shot:
		suspense_state = SuspenseState.SPENT
		shot_validated = false
		return {"will_enter_zone": false, "shot_validated": false, "min_dist": 999.0, "ending_dist": 999.0}
	if target_pos.is_zero_approx():
		suspense_state = SuspenseState.SPENT
		shot_validated = false
		return {"will_enter_zone": false, "shot_validated": false, "min_dist": 999.0, "ending_dist": 999.0}
	if not is_shot_eligible_for_suspense(start_pos, target_pos, is_putt, is_sand):
		suspense_state = SuspenseState.SPENT
		shot_validated = false
		return {"will_enter_zone": false, "shot_validated": false, "min_dist": 999.0, "ending_dist": 999.0, "mode": "putt" if is_putt else "chip"}

	var target_2d := Vector2(target_pos.x, target_pos.z)
	var mode := "putt" if is_putt else "chip"

	# Get environmental parameters
	var gs = get_node_or_null("/root/GlobalSettings")
	var green_speed: float = 10.0
	if gs != null and gs.has_method("get_effective_green_speed"):
		green_speed = float(gs.get_effective_green_speed())
	var speed_mult := pow(10.0 / maxf(green_speed, 1.0), 0.30)
	var green_rolling_friction := 0.085 * speed_mult

	# Query green slope normal around the target hole
	var green_normal := Vector3.UP
	var tree := get_tree()
	if tree != null and tree.root != null and tree.root.get_world_3d() != null:
		var space_state = tree.root.get_world_3d().direct_space_state
		if space_state != null:
			var query = PhysicsRayQueryParameters3D.create(
				target_pos + Vector3.UP * 1.5,
				target_pos + Vector3.DOWN * 2.5
			)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit = space_state.intersect_ray(query)
			if not hit.is_empty():
				var norm: Vector3 = hit.get("normal", Vector3.UP)
				if norm.y > 0.5:
					green_normal = norm.normalized()

	# Wind vector (if enabled)
	var wind_vec := Vector3.ZERO
	if gs != null and gs.has_method("is_wind_enabled") and gs.is_wind_enabled() and gs.has_method("get_wind_vector_mps"):
		wind_vec = gs.get_wind_vector_mps()

	var sim_pos := start_pos
	var sim_vel := launch_vel
	var min_dist_2d := 9999.0
	var dt := 0.025
	var holed_out := false
	var did_land := false
	var p_apex := start_pos
	var p_land := start_pos
	var v_land := Vector3.ZERO
	var roll_path: Array[Vector3] = []

	var gravity_slope_2d = Vector2(green_normal.x, green_normal.z) * (9.81 * green_normal.y * 0.5)

	if is_putt:
		sim_vel.y = 0.0
		p_apex = start_pos
		p_land = start_pos
		v_land = sim_vel
		roll_path.append(start_pos)

		for step in range(400):
			var current_2d = Vector2(sim_pos.x, sim_pos.z)
			var d = current_2d.distance_to(target_2d)
			if d < min_dist_2d:
				min_dist_2d = d

			var flat_speed = Vector2(sim_vel.x, sim_vel.z).length()

			# Enter cup check: enters cup radius at holeable speed
			if d <= CUP_RADIUS_METERS and flat_speed <= MAX_HOLEABLE_SPEED_MPS:
				holed_out = true
				min_dist_2d = 0.0
				roll_path.append(target_pos)
				break

			if flat_speed < 0.03:
				break

			var slope_scale = clampf(flat_speed / 0.6, 0.0, 1.0)
			var slope_accel = gravity_slope_2d * slope_scale
			var friction_accel = -Vector2(sim_vel.x, sim_vel.z).normalized() * (green_rolling_friction * 9.81)

			var vel_2d = Vector2(sim_vel.x, sim_vel.z) + (slope_accel + friction_accel) * dt
			if vel_2d.dot(Vector2(sim_vel.x, sim_vel.z)) < 0.0:
				break
			sim_vel.x = vel_2d.x
			sim_vel.z = vel_2d.y
			sim_pos += sim_vel * dt
			roll_path.append(sim_pos)
	else:
		var in_flight := true
		var total_dist_2d := Vector2(start_pos.x, start_pos.z).distance_to(target_2d)

		for step in range(400):
			var current_2d = Vector2(sim_pos.x, sim_pos.z)
			var d = current_2d.distance_to(target_2d)

			if in_flight:
				if sim_pos.y > p_apex.y:
					p_apex = sim_pos

				var dist_from_start = Vector2(sim_pos.x - start_pos.x, sim_pos.z - start_pos.z).length()
				var t_path = clampf(dist_from_start / maxf(total_dist_2d, 0.01), 0.0, 1.0)
				var local_ground_y = lerpf(start_pos.y, target_pos.y, t_path)

				var height_above_ground = maxf(0.0, sim_pos.y - local_ground_y)
				var wind_factor = smoothstep(0.0, 25.0, height_above_ground)
				var effective_wind = wind_vec * wind_factor
				var v_rel = sim_vel - effective_wind
				var v_rel_len = v_rel.length()

				# Aerodynamic drag deceleration
				var drag_force = -0.5 * 0.28 * 1.204 * 0.0014303 * v_rel_len * v_rel
				var accel = (drag_force / 0.04593) + Vector3(0.0, -9.81, 0.0)
				sim_vel += accel * dt
				sim_pos += sim_vel * dt

				if sim_vel.y <= 0.0 and sim_pos.y <= local_ground_y:
					sim_pos.y = local_ground_y
					in_flight = false
					did_land = true
					p_land = sim_pos
					# Damped turf bounce
					sim_vel.y = absf(sim_vel.y) * 0.20
					sim_vel.x *= 0.52
					sim_vel.z *= 0.52
					v_land = sim_vel
					roll_path.append(p_land)
			else:
				var flat_speed = Vector2(sim_vel.x, sim_vel.z).length()
				if d < min_dist_2d:
					min_dist_2d = d

				if d <= CUP_RADIUS_METERS and flat_speed <= MAX_HOLEABLE_SPEED_MPS:
					holed_out = true
					min_dist_2d = 0.0
					roll_path.append(target_pos)
					break

				if flat_speed < 0.03:
					break

				var slope_scale = clampf(flat_speed / 0.6, 0.0, 1.0)
				var slope_accel = gravity_slope_2d * slope_scale
				var friction_accel = -Vector2(sim_vel.x, sim_vel.z).normalized() * (green_rolling_friction * 9.81)

				var vel_2d = Vector2(sim_vel.x, sim_vel.z) + (slope_accel + friction_accel) * dt
				if vel_2d.dot(Vector2(sim_vel.x, sim_vel.z)) < 0.0:
					break
				sim_vel.x = vel_2d.x
				sim_vel.z = vel_2d.y
				sim_vel.y = 0.0
				sim_pos += sim_vel * dt
				roll_path.append(sim_pos)

	var ending_dist_2d = 0.0 if holed_out else Vector2(sim_pos.x, sim_pos.z).distance_to(target_2d)

	# --- TRAJECTORY VALIDATION (READY state evaluation) ---
	# Does the entire predicted on-ground roll path (from P_land_predicted to final stop) ever enter the cup?
	# If NO, transition directly to SPENT. This shot is a confirmed miss and never gets to ACTIVE.
	if not holed_out:
		suspense_state = SuspenseState.SPENT
		_shot_suspense_locked_out = true
		shot_validated = false
		predicted_holed_out = false
		print("[TensionManager] Trajectory Validation: MISS confirmed (closest to cup: %.2fm). Transitioned directly to SPENT." % min_dist_2d)
		return {
			"will_enter_zone": false,
			"shot_validated": false,
			"ending_dist": ending_dist_2d,
			"min_dist": min_dist_2d,
			"mode": mode
		}

	# Validation SUCCESS: Shot enters cup!
	shot_validated = true
	suspense_state = SuspenseState.READY
	predicted_apex = p_apex
	predicted_land_pos = p_land
	predicted_land_vel = v_land
	predicted_roll_path = roll_path
	predicted_holed_out = true
	_suspense_predicted_close = true
	_predicted_ending_dist = 0.0

	var time_to_apex: float = 0.0
	var delay_to_apex: float = 0.25
	if not is_putt and launch_vel.y > 0.5:
		time_to_apex = launch_vel.y / 9.81
		delay_to_apex = time_to_apex + 0.15

	print("[TensionManager] Trajectory Validation: SUCCESS! Roll path enters cup! State -> READY. P_apex: %s, P_land: %s" % [p_apex, p_land])
	return {
		"will_enter_zone": true,
		"shot_validated": true,
		"ending_dist": 0.0,
		"min_dist": 0.0,
		"mode": mode,
		"time_to_apex": time_to_apex,
		"delay_to_apex": delay_to_apex,
		"p_apex": p_apex,
		"p_land": p_land
	}

func schedule_apex_tension(mode: String, _delay_seconds: float = 0.25, ending_dist: float = 0.0) -> void:
	if not is_course_play_active() or _shot_suspense_locked_out or _tree_hit_this_shot:
		return
	cancel_scheduled_tension()
	_scheduled_mode = mode
	_predicted_ending_dist = ending_dist
	_closest_dist_reached = 9999.0
	_has_entered_suspense_zone = false
	# Note: Activation is evaluated dynamically by altitude and cone angle in check_ball_proximity.

func schedule_early_tension(mode: String, delay_seconds: float = 0.02, ending_dist: float = 0.0) -> void:
	schedule_apex_tension(mode, delay_seconds, ending_dist)

func cancel_scheduled_tension() -> void:
	_is_scheduled = false

func on_tree_hit() -> void:
	_tree_hit_this_shot = true
	_suspense_predicted_close = false
	shot_validated = false
	suspense_state = SuspenseState.SPENT
	_shot_suspense_locked_out = true
	cancel_scheduled_tension()
	stop_tension(true)

func reset_for_new_shot() -> void:
	cancel_scheduled_tension()
	suspense_state = SuspenseState.IDLE
	shot_validated = false
	predicted_apex = Vector3.ZERO
	predicted_land_pos = Vector3.ZERO
	predicted_land_vel = Vector3.ZERO
	predicted_roll_path.clear()
	predicted_holed_out = false
	_shot_suspense_locked_out = false
	_tree_hit_this_shot = false
	_suspense_predicted_close = false
	_predicted_ending_dist = 0.0
	_closest_dist_reached = 9999.0
	_has_entered_suspense_zone = false
	current_closeness = 0.0
	if tension_active:
		tension_active = false
		emit_signal("tension_stopped")

# ---------------- LIVE PROXIMITY & CONE CHECK ----------------

func check_ball_proximity(
	ball_pos: Vector3,
	target_pos: Vector3,
	is_putt: bool,
	shot_start_pos: Vector3 = Vector3.ZERO,
	_is_sand: bool = false,
	is_airborne: bool = false,
	ball_vel: Vector3 = Vector3.ZERO,
	hit_tree: bool = false
) -> bool:
	# Never trigger or continue after hitting a tree
	if _tree_hit_this_shot or hit_tree:
		_tree_hit_this_shot = true
		suspense_state = SuspenseState.SPENT
		_shot_suspense_locked_out = true
		cancel_scheduled_tension()
		if tension_active:
			stop_tension(true)
		return false

	# Strict SPENT Latch: Suspense must never turn on more than once per shot
	if suspense_state == SuspenseState.SPENT or _shot_suspense_locked_out:
		return false

	if not is_course_play_active() or target_pos.is_zero_approx():
		return false

	var ball_pos_2d = Vector2(ball_pos.x, ball_pos.z)
	var hole_pos_2d = Vector2(target_pos.x, target_pos.z)
	var dist_2d = ball_pos_2d.distance_to(hole_pos_2d)
	var threshold = PUTT_THRESHOLD_METERS if is_putt else CHIP_THRESHOLD_METERS

	# ========================================================
	# STATE: READY -> ACTIVE (Predictive Activation)
	# ========================================================
	if suspense_state == SuspenseState.READY:
		# 1. Validation check (redundant but safe)
		if not shot_validated:
			suspense_state = SuspenseState.SPENT
			_shot_suspense_locked_out = true
			return false

		# 2. Altitude Trigger: Ball must have passed predicted apex (Ball_Current_Altitude < P_apex.y and v_ball.y < 0)
		if is_airborne:
			if ball_vel.y >= 0.0 or ball_pos.y >= predicted_apex.y:
				return false # Ascending or at/above apex

		# 3. Angle Check (Critical): Cone projected forward from landing spot / ball must encompass hole
		var cone_valid := false
		if is_airborne:
			var land_2d = Vector2(predicted_land_pos.x, predicted_land_pos.z)
			var land_to_hole = (hole_pos_2d - land_2d).normalized() if land_2d.distance_to(hole_pos_2d) > 0.001 else Vector2.ZERO
			var land_v_2d = Vector2(predicted_land_vel.x, predicted_land_vel.z).normalized()
			var cos_theta_land = land_v_2d.dot(land_to_hole)

			var cur_to_hole = (hole_pos_2d - ball_pos_2d).normalized() if dist_2d > 0.001 else Vector2.ZERO
			var cur_v_2d = Vector2(ball_vel.x, ball_vel.z).normalized()
			var cos_theta_cur = cur_v_2d.dot(cur_to_hole)

			# Must satisfy cos_theta >= cos(cone_half_angle)
			cone_valid = (cos_theta_land >= MIN_COS_THETA) and (cos_theta_cur >= (MIN_COS_THETA - 0.05))
		else:
			# Putting / on-ground rollout
			var cur_to_hole = (hole_pos_2d - ball_pos_2d).normalized() if dist_2d > 0.001 else Vector2.ZERO
			var cur_v_2d = Vector2(ball_vel.x, ball_vel.z).normalized()
			var cos_theta_cur = cur_v_2d.dot(cur_to_hole)
			var theta_cup = asin(clampf(CUP_RADIUS_METERS / maxf(dist_2d, 0.001), 0.0, 1.0))
			var min_cos = minf(MIN_COS_THETA, cos(theta_cup))
			cone_valid = (cos_theta_cur >= min_cos)

		if cone_valid:
			suspense_state = SuspenseState.ACTIVE
			_closest_dist_reached = dist_2d
			var closeness = clampf(1.0 - (dist_2d / maxf(threshold, 0.001)), 0.35, 1.0)
			start_tension("putt" if is_putt else "chip", closeness)
			print("[TensionManager] READY -> ACTIVE! Vision cone encompass validated. Mode: %s, Closeness: %.2f" % [
				"putt" if is_putt else "chip", closeness
			])
			return true
		else:
			return false

	# ========================================================
	# STATE: ACTIVE (Ongoing Angle Loss & Deactivation Checks)
	# ========================================================
	if suspense_state == SuspenseState.ACTIVE:
		# 1. Rest / Sunk Check:
		var speed = ball_vel.length()
		if not is_airborne and speed < 0.05:
			print("[TensionManager] ACTIVE -> SPENT: Ball stopped at rest.")
			suspense_state = SuspenseState.SPENT
			stop_tension(true)
			return false

		if dist_2d <= CUP_RADIUS_METERS:
			print("[TensionManager] ACTIVE -> SPENT: Ball reached/sunk in cup!")
			suspense_state = SuspenseState.SPENT
			stop_tension(true)
			return false

		var cur_to_hole = (hole_pos_2d - ball_pos_2d).normalized() if dist_2d > 0.001 else Vector2.ZERO
		var cur_v_2d = Vector2(ball_vel.x, ball_vel.z).normalized()
		var vel_dot_hole = cur_v_2d.dot(cur_to_hole)

		# 2. Overshoot Check: Ball rolls past the hole
		if not is_airborne and dist_2d > (_closest_dist_reached + 0.05) and vel_dot_hole <= 0.0:
			print("[TensionManager] ACTIVE -> SPENT: Overshoot detected (moving away from hole). Dist: %.2fm" % dist_2d)
			suspense_state = SuspenseState.SPENT
			stop_tension(true)
			return false

		var start_pos_2d = Vector2(shot_start_pos.x, shot_start_pos.z) if not shot_start_pos.is_zero_approx() else Vector2.ZERO
		if not start_pos_2d.is_zero_approx():
			var shot_vec = hole_pos_2d - start_pos_2d
			if shot_vec.length_squared() > 0.01:
				var shot_dir = shot_vec.normalized()
				var hole_to_ball = ball_pos_2d - hole_pos_2d
				var along_shot = hole_to_ball.dot(shot_dir)
				if along_shot > PAST_HOLE_THRESHOLD_METERS:
					print("[TensionManager] ACTIVE -> SPENT: Ball physically > 1ft past hole.")
					suspense_state = SuspenseState.SPENT
					stop_tension(true)
					return false

		# 3. Hole Exits Cone (Angle Loss Check):
		var theta_cup = asin(clampf(CUP_RADIUS_METERS / maxf(dist_2d, 0.001), 0.0, 1.0))
		var min_cos = minf(MIN_COS_THETA, cos(theta_cup))
		if vel_dot_hole < min_cos:
			print("[TensionManager] ACTIVE -> SPENT: Hole exited cone! cos_theta: %.3f < min_cos: %.3f (Broke offline)." % [vel_dot_hole, min_cos])
			suspense_state = SuspenseState.SPENT
			stop_tension(true)
			return false

		# Track closest distance and update heartbeat closeness
		_closest_dist_reached = minf(_closest_dist_reached, dist_2d)
		var closeness = clampf(1.0 - (dist_2d / maxf(threshold, 0.001)), 0.35, 1.0)
		current_closeness = maxf(current_closeness, closeness)
		return true

	return false

# ----------------- ACTIVATION / DEACTIVATION -----------------

func start_tension(mode: String = "putt", initial_closeness: float = 0.40) -> void:
	if _shot_suspense_locked_out or _tree_hit_this_shot or suspense_state == SuspenseState.SPENT:
		return
	if not is_course_play_active():
		return
	cancel_scheduled_tension()
	var gs = get_node_or_null("/root/GlobalSettings")
	if gs != null and not gs.range_settings.tension_effects_enabled.value:
		return
	current_mode = mode
	current_closeness = initial_closeness
	if not tension_active:
		tension_active = true
		pulse_timer = 0.0
		current_intensity = 1.0
		if sfx_player != null and _heartbeat_stream != null:
			sfx_player.volume_db = 4.0 # Loud, punchy, clearly audible baseline
			sfx_player.pitch_scale = 1.0
			sfx_player.play()
		emit_signal("tension_started", mode)

func stop_tension(lockout: bool = true) -> void:
	cancel_scheduled_tension()
	if lockout:
		_shot_suspense_locked_out = true
		suspense_state = SuspenseState.SPENT
	_closest_dist_reached = 9999.0
	_has_entered_suspense_zone = false
	current_closeness = 0.0
	if tension_active:
		tension_active = false
		emit_signal("tension_stopped")

func register_camera(cam: Camera3D, base_fov: float = 55.0) -> void:
	target_camera = cam
	base_camera_fov = base_fov

# ---------------- PROCESS & VISUAL/AUDIO PULSE ----------------

func _process(delta: float) -> void:
	if tension_active:
		pulse_timer += delta
		var t_in_cycle = fmod(pulse_timer, CYCLE_DURATION)

		if t_in_cycle < 0.22:
			var p1 = sin(PI * (t_in_cycle / 0.22))
			current_pulse = p1 * p1 * 1.0
		elif t_in_cycle >= 0.28 and t_in_cycle < 0.44:
			var p2 = sin(PI * ((t_in_cycle - 0.28) / 0.16))
			current_pulse = p2 * p2 * 0.75
		else:
			current_pulse = 0.0

		current_intensity = lerp(current_intensity, 1.45, delta * 4.0)

		# Scale heartbeat audio volume louder and louder as ball gets closer (+4 dB up to +11 dB!)
		if sfx_player != null:
			if not sfx_player.playing and _heartbeat_stream != null:
				sfx_player.play()
			var target_vol = lerpf(4.0, 11.0, current_closeness)
			sfx_player.volume_db = lerp(sfx_player.volume_db, target_vol, delta * 5.0)
			sfx_player.pitch_scale = lerp(sfx_player.pitch_scale, lerpf(1.0, 1.08, current_closeness), delta * 4.0)
	else:
		current_pulse = lerp(current_pulse, 0.0, delta * 6.0)
		current_intensity = lerp(current_intensity, 0.0, delta * 5.0)

		if sfx_player != null and sfx_player.playing:
			sfx_player.volume_db = lerp(sfx_player.volume_db, -40.0, delta * 6.0)
			if current_intensity < 0.01 and sfx_player.volume_db <= -35.0:
				sfx_player.stop()

	# Update 4-corner tunnel vision vignette
	if vignette_rect != null:
		var should_show_vignette = tension_active or current_intensity > 0.001
		if vignette_rect.visible != should_show_vignette:
			vignette_rect.visible = should_show_vignette
		if should_show_vignette and vignette_material != null:
			vignette_material.set_shader_parameter("intensity", current_intensity)
			vignette_material.set_shader_parameter("pulse", current_pulse)
			vignette_material.set_shader_parameter("closeness", current_closeness)

	var cam: Camera3D = target_camera
	if cam == null or not is_instance_valid(cam):
		var vp = get_viewport()
		if vp != null:
			var vp_cam = vp.get_camera_3d()
			if vp_cam != null and vp_cam.name != "MinimapCamera" and vp_cam.name != "AerialCamera":
				cam = vp_cam

	if cam != null and is_instance_valid(cam):
		var target_fov = base_camera_fov
		if current_intensity > 0.001:
			var fov_offset = -5.0 * (current_intensity / 1.45) * (0.85 + current_pulse * 0.25)
			target_fov = base_camera_fov + fov_offset
		cam.fov = lerp(cam.fov, target_fov, delta * 6.0)

func get_tension_intensity() -> float:
	return current_intensity

func get_tension_pulse() -> float:
	return current_pulse
