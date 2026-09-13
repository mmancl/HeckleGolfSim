extends Node

# TensionManager: Manages heartbeat SFX, pulsing screen border vignette,
# early trajectory prediction suspense, and camera tension effects for close putts and chips.

signal tension_started(mode: String)
signal tension_stopped()

const PUTT_THRESHOLD_METERS := 3.048   # 10 feet in meters (10.0 * 0.3048)
const CHIP_THRESHOLD_METERS := 7.62    # 25 feet in meters (25.0 * 0.3048)
const PUTT_MIN_SUSPENSE_DISTANCE_METERS := 12.192  # 40 feet in meters (40.0 * 0.3048)
const CHIP_MIN_SUSPENSE_DISTANCE_METERS := 30.48   # 100 feet in meters (100.0 * 0.3048)
const PAST_HOLE_THRESHOLD_METERS := 0.3048         # 1 foot past the hole in meters (1.0 * 0.3048)
const CYCLE_DURATION := 0.80          # ~75 BPM double-thump heartbeat cycle

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

func is_course_play_active() -> bool:
	# 1. Global Settings minigame and menu checks
	if has_node("/root/GlobalSettings"):
		if GlobalSettings.is_minigames_scene() or GlobalSettings.is_chipping_minigame or GlobalSettings.is_putting_minigame:
			return false
		if GlobalSettings.is_menu_screen():
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

func is_shot_eligible_for_suspense(start_pos: Vector3, target_pos: Vector3, is_putt: bool, is_sand: bool = false) -> bool:
	if not is_course_play_active():
		return false
	if target_pos.is_zero_approx():
		return false
	var dist_2d = Vector2(start_pos.x, start_pos.z).distance_to(Vector2(target_pos.x, target_pos.z))
	if is_putt:
		return dist_2d > PUTT_MIN_SUSPENSE_DISTANCE_METERS
	else:
		return is_sand or (dist_2d > CHIP_MIN_SUSPENSE_DISTANCE_METERS)

# ---------------- TRAJECTORY PREDICTION ----------------

func predict_shot_outcome(start_pos: Vector3, launch_vel: Vector3, is_putt: bool, target_pos: Vector3, is_sand: bool = false) -> Dictionary:
	if not is_course_play_active():
		return {"will_enter_zone": false, "min_dist": 999.0, "ending_dist": 999.0}
	if target_pos.is_zero_approx():
		return {"will_enter_zone": false, "min_dist": 999.0, "ending_dist": 999.0}
	if not is_shot_eligible_for_suspense(start_pos, target_pos, is_putt, is_sand):
		return {"will_enter_zone": false, "min_dist": 999.0, "ending_dist": 999.0, "mode": "putt" if is_putt else "chip"}

	var target_2d = Vector2(target_pos.x, target_pos.z)
	var mode = "putt" if is_putt else "chip"

	var sim_pos = start_pos
	var sim_vel = launch_vel
	var min_dist_2d = 9999.0
	var dt = 0.025
	var holed_out = false
	var landing_dist_from_start = 0.0

	if is_putt:
		sim_vel.y = 0.0
		for step in range(350):
			var current_2d = Vector2(sim_pos.x, sim_pos.z)
			var d = current_2d.distance_to(target_2d)
			if d < min_dist_2d:
				min_dist_2d = d

			var speed = sim_vel.length()
			# Ball sinks into cup on center/near-center roll at holeable speed (< 2.8 m/s)
			if d < 0.054 and speed < 2.8:
				holed_out = true
				min_dist_2d = 0.0
				sim_pos = Vector3(target_pos.x, sim_pos.y, target_pos.z)
				break

			if speed < 0.05:
				break
			sim_pos += sim_vel * dt
			var decel = 0.48 * dt
			var new_speed = max(0.0, speed - decel)
			sim_vel = sim_vel.normalized() * new_speed
	else:
		var on_ground = false
		var total_dist_2d = Vector2(start_pos.x, start_pos.z).distance_to(target_2d)
		for step in range(350):
			var current_2d = Vector2(sim_pos.x, sim_pos.z)
			var d = current_2d.distance_to(target_2d)

			# Interpolate local ground elevation along the path from start to hole
			var dist_from_start = Vector2(sim_pos.x - start_pos.x, sim_pos.z - start_pos.z).length()
			var t_path = clampf(dist_from_start / maxf(total_dist_2d, 0.01), 0.0, 1.0)
			var local_ground_y = lerpf(start_pos.y, target_pos.y, t_path)

			if not on_ground:
				sim_pos += sim_vel * dt
				sim_vel.y -= 9.81 * dt
				sim_vel.x *= (1.0 - 0.035 * dt)
				sim_vel.z *= (1.0 - 0.035 * dt)

				# Ball only contacts the turf when descending and at or below interpolated ground
				if sim_vel.y <= 0.0 and sim_pos.y <= local_ground_y:
					sim_pos.y = local_ground_y
					on_ground = true
					landing_dist_from_start = dist_from_start
					sim_vel.y = absf(sim_vel.y) * 0.20
					sim_vel.x *= 0.52
					sim_vel.z *= 0.52
			else:
				var flat_speed = Vector2(sim_vel.x, sim_vel.z).length()
				if d < min_dist_2d:
					min_dist_2d = d

				# Chip ball rolls directly into cup
				if d < 0.054 and flat_speed < 2.0:
					holed_out = true
					min_dist_2d = 0.0
					sim_pos = Vector3(target_pos.x, sim_pos.y, target_pos.z)
					break

				if flat_speed < 0.05:
					break
				sim_pos += sim_vel * dt
				var new_flat_speed = max(0.0, flat_speed - 0.55 * dt)
				var dir_2d = Vector2(sim_vel.x, sim_vel.z).normalized()
				sim_vel.x = dir_2d.x * new_flat_speed
				sim_vel.z = dir_2d.y * new_flat_speed
				sim_vel.y = 0.0

	var ending_dist_2d = 0.0 if holed_out else Vector2(sim_pos.x, sim_pos.z).distance_to(target_2d)
	var will_enter = false
	if is_putt:
		# Putt prediction:
		# Does the simulated roll enter within 10 ft, or does the stroke line & speed target the cup?
		var total_target_dist = Vector2(start_pos.x, start_pos.z).distance_to(target_2d)
		var putt_speed = Vector2(launch_vel.x, launch_vel.z).length()
		var dir_to_hole = (target_2d - Vector2(start_pos.x, start_pos.z)).normalized()
		var putt_dir = Vector2(launch_vel.x, launch_vel.z).normalized()
		var heading_dot = putt_dir.dot(dir_to_hole)

		if min_dist_2d <= PUTT_THRESHOLD_METERS or ending_dist_2d <= PUTT_THRESHOLD_METERS or holed_out:
			will_enter = true
		elif heading_dot > 0.94 and putt_speed > 1.2:
			# Kinematic check: flat/mildly sloped green roll estimate (v^2 / 2a)
			var est_roll = (putt_speed * putt_speed) / 0.80
			if est_roll >= (total_target_dist - PUTT_THRESHOLD_METERS) and est_roll <= (total_target_dist + 5.0):
				will_enter = true
	else:
		# Chip prediction:
		# Ensure the ball flight doesn't carry 6+ feet (1.8m) past the hole in the air
		var total_target_dist = Vector2(start_pos.x, start_pos.z).distance_to(target_2d)
		var carry_past_hole = landing_dist_from_start > (total_target_dist + 1.8)

		# If the flight or rollout enters within the 25 ft threshold, or ends near the hole, or holes out:
		if not carry_past_hole and (min_dist_2d <= CHIP_THRESHOLD_METERS or ending_dist_2d <= (CHIP_THRESHOLD_METERS + 2.0) or holed_out):
			will_enter = true

	var time_to_apex: float = 0.0
	var delay_to_apex: float = 0.25
	if not is_putt and launch_vel.y > 0.5:
		time_to_apex = launch_vel.y / 9.81
		delay_to_apex = time_to_apex + 0.15 # Shortly after the apex of the shot!

	return {
		"will_enter_zone": will_enter,
		"ending_dist": ending_dist_2d,
		"min_dist": min_dist_2d if holed_out else ending_dist_2d,
		"mode": mode,
		"time_to_apex": time_to_apex,
		"delay_to_apex": delay_to_apex
	}

func schedule_apex_tension(mode: String, delay_seconds: float = 0.25, ending_dist: float = 0.0) -> void:
	if not is_course_play_active() or _shot_suspense_locked_out:
		return
	cancel_scheduled_tension()
	_is_scheduled = true
	_scheduled_mode = mode
	_suspense_predicted_close = true
	_predicted_ending_dist = ending_dist
	_closest_dist_reached = 9999.0
	_has_entered_suspense_zone = false
	var timer = get_tree().create_timer(delay_seconds)
	await timer.timeout
	if _is_scheduled and not _shot_suspense_locked_out:
		_is_scheduled = false
		var threshold = PUTT_THRESHOLD_METERS if mode == "putt" else CHIP_THRESHOLD_METERS
		var closeness = clampf(1.0 - (ending_dist / maxf(threshold, 0.001)), 0.35, 1.0)
		start_tension(mode, closeness)

func schedule_early_tension(mode: String, delay_seconds: float = 0.02, ending_dist: float = 0.0) -> void:
	schedule_apex_tension(mode, delay_seconds, ending_dist)

func cancel_scheduled_tension() -> void:
	_is_scheduled = false

func reset_for_new_shot() -> void:
	cancel_scheduled_tension()
	_shot_suspense_locked_out = false
	_suspense_predicted_close = false
	_predicted_ending_dist = 0.0
	_closest_dist_reached = 9999.0
	_has_entered_suspense_zone = false
	current_closeness = 0.0
	if tension_active:
		tension_active = false
		emit_signal("tension_stopped")

# ---------------- LIVE PROXIMITY CHECK ----------------

func check_ball_proximity(
	ball_pos: Vector3,
	target_pos: Vector3,
	is_putt: bool,
	shot_start_pos: Vector3 = Vector3.ZERO,
	is_sand: bool = false,
	is_airborne: bool = false,
	ball_vel: Vector3 = Vector3.ZERO
) -> bool:
	# If tension is ALREADY active:
	if tension_active:
		# 1. Turn off if the ball has come to a complete rest:
		if not is_airborne and ball_vel.length() < 0.05:
			stop_tension(true) # Lock out for rest of shot now that ball is at rest
			return false

		var ball_pos_2d = Vector2(ball_pos.x, ball_pos.z)
		var hole_pos_2d = Vector2(target_pos.x, target_pos.z)
		var dist_2d = ball_pos_2d.distance_to(hole_pos_2d)

		# 2. Turn off if the ball is physically more than 1 foot past the hole
		# (on the other side of the hole relative to where the ball started):
		var start_pos_2d = Vector2(shot_start_pos.x, shot_start_pos.z) if not shot_start_pos.is_zero_approx() else Vector2.ZERO
		if not start_pos_2d.is_zero_approx():
			var shot_vec = hole_pos_2d - start_pos_2d
			if shot_vec.length_squared() > 0.01:
				var shot_dir = shot_vec.normalized()
				var hole_to_ball = ball_pos_2d - hole_pos_2d
				var along_shot = hole_to_ball.dot(shot_dir)
				# Physically past the hole (along_shot > 0) and physically more than 1 foot past:
				if along_shot > 0.0 and dist_2d > PAST_HOLE_THRESHOLD_METERS:
					stop_tension(true)
					return false

		# While still moving and not past the hole, maintain tension and update closeness:
		var threshold = PUTT_THRESHOLD_METERS if is_putt else CHIP_THRESHOLD_METERS
		var closeness = clampf(1.0 - (dist_2d / threshold), 0.25, 1.0)
		current_closeness = maxf(current_closeness, closeness)
		return true

	# If not active, but already locked out on this shot (e.g. shot previously reached rest or went past):
	if _shot_suspense_locked_out:
		return false

	if not is_course_play_active():
		return false
	if target_pos.is_zero_approx():
		return false
	if not shot_start_pos.is_zero_approx():
		if not is_shot_eligible_for_suspense(shot_start_pos, target_pos, is_putt, is_sand):
			return false

	var ball_pos_2d = Vector2(ball_pos.x, ball_pos.z)
	var hole_pos_2d = Vector2(target_pos.x, target_pos.z)
	var dist_2d = ball_pos_2d.distance_to(hole_pos_2d)
	var threshold = PUTT_THRESHOLD_METERS if is_putt else CHIP_THRESHOLD_METERS

	var vel_2d = Vector2(ball_vel.x, ball_vel.z)
	var speed_2d = vel_2d.length()

	# AIRBORNE APEX TRIGGER (For shots predicted to be close):
	# If predicted close, start the heartbeat shortly after apex (once descending: ball_vel.y <= -0.5)
	if _suspense_predicted_close and is_airborne and ball_vel.y <= -0.5:
		var pred_closeness = clampf(1.0 - (_predicted_ending_dist / maxf(threshold, 0.001)), 0.35, 1.0)
		start_tension("chip", pred_closeness)
		return true

	# LIVE PROXIMITY TRIGGER:
	# Inside threshold (25 ft for chips, 10 ft for putts)
	if dist_2d <= threshold and speed_2d > 0.08:
		# If the ball is already physically more than 1 foot past the hole, do not start:
		var start_pos_2d = Vector2(shot_start_pos.x, shot_start_pos.z) if not shot_start_pos.is_zero_approx() else Vector2.ZERO
		if not start_pos_2d.is_zero_approx():
			var shot_vec = hole_pos_2d - start_pos_2d
			if shot_vec.length_squared() > 0.01:
				var shot_dir = shot_vec.normalized()
				var hole_to_ball = ball_pos_2d - hole_pos_2d
				var along_shot = hole_to_ball.dot(shot_dir)
				if along_shot > 0.0 and dist_2d > PAST_HOLE_THRESHOLD_METERS:
					return false

		var dir_to_hole = (hole_pos_2d - ball_pos_2d).normalized() if dist_2d > 0.001 else Vector2.ZERO
		var move_dir = vel_2d.normalized()
		var heading_dot = move_dir.dot(dir_to_hole)

		# Moving generally towards the hole area (not straight backwards)
		if heading_dot > -0.25:
			# For airborne chips, check that ball flight won't carry 6+ ft past the pin in the air
			if is_airborne:
				var vy = ball_vel.y
				var height_above_target = ball_pos.y - target_pos.y
				var g = 9.81
				var discriminant = vy * vy + 2.0 * g * maxf(height_above_target, 0.0)
				var time_to_land = (vy + sqrt(maxf(0.0, discriminant))) / g
				var carry_remaining = speed_2d * time_to_land
				if carry_remaining > (dist_2d + 1.8):
					return false # Flying far past the hole in the air

			var closeness = clampf(1.0 - (dist_2d / threshold), 0.25, 1.0)
			start_tension("putt" if is_putt else "chip", closeness)
			return true

	return false

# ----------------- ACTIVATION / DEACTIVATION -----------------

func start_tension(mode: String = "putt", initial_closeness: float = 0.40) -> void:
	if _shot_suspense_locked_out:
		return
	if not is_course_play_active():
		return
	cancel_scheduled_tension()
	if has_node("/root/GlobalSettings") and not GlobalSettings.range_settings.tension_effects_enabled.value:
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
