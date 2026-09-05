extends Node

# TensionManager: Manages heartbeat SFX, pulsing screen border vignette,
# early trajectory prediction suspense, and camera tension effects for close putts and chips.

signal tension_started(mode: String)
signal tension_stopped()

const PUTT_THRESHOLD_METERS := 1.524  # 5 feet in meters
const CHIP_THRESHOLD_METERS := 3.048  # 10 feet in meters
const PUTT_MIN_SUSPENSE_DISTANCE_METERS := 12.192  # 40 feet in meters (40.0 * 0.3048)
const CHIP_MIN_SUSPENSE_DISTANCE_METERS := 30.48   # 100 feet in meters (100.0 * 0.3048)
const CYCLE_DURATION := 0.80          # ~75 BPM double-thump heartbeat cycle

var tension_active: bool = false
var current_mode: String = ""
var current_intensity: float = 0.0
var current_closeness: float = 0.0
var pulse_timer: float = 0.0
var current_pulse: float = 0.0

var _is_scheduled: bool = false
var _scheduled_mode: String = ""

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
	if has_node("/root/MultiplayerManager"):
		var mp = get_node("/root/MultiplayerManager")
		if mp.practice_mode_active:
			return false
		if mp.players.is_empty():
			return false

	# 3. Active Scene checks
	var tree = get_tree()
	if tree == null:
		return false
	var current_scene = tree.current_scene
	if current_scene == null:
		return false

	# Check practice mode on current scene
	if current_scene.get("practice_mode_active") == true:
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
		return false

	# Exclude all Minigames
	if full_id.contains("chipping") or full_id.contains("putting") \
		or full_id.contains("loft_control") or full_id.contains("shape_practice") \
		or full_id.contains("minigame") or full_id.contains("minigames"):
		return false

	# Exclude standalone Driving Range
	if (scene_name == "range" or scene_path.ends_with("range.tscn")) and not current_scene.has_node("CoursePlay"):
		return false

	# Must have CoursePlay node or be a course scene with active hole play
	if current_scene.has_node("CoursePlay") or scene_name == "courseplay" or full_id.contains("course_play") or full_id.contains("usercourses") or scene_name.contains("course"):
		return true

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
		return {"will_enter_zone": false, "min_dist": 999.0}
	if target_pos.is_zero_approx():
		return {"will_enter_zone": false, "min_dist": 999.0}
	if not is_shot_eligible_for_suspense(start_pos, target_pos, is_putt, is_sand):
		return {"will_enter_zone": false, "min_dist": 999.0, "mode": "putt" if is_putt else "chip"}

	var target_2d = Vector2(target_pos.x, target_pos.z)
	# Broad prediction threshold to start suspense early on shots heading towards the target zone
	var threshold = (PUTT_THRESHOLD_METERS * 1.65) if is_putt else (CHIP_THRESHOLD_METERS * 1.5)
	var mode = "putt" if is_putt else "chip"

	var sim_pos = start_pos
	var sim_vel = launch_vel
	var min_dist_2d = 9999.0
	var dt = 0.025

	if is_putt:
		sim_vel.y = 0.0
		for step in range(180):
			var current_2d = Vector2(sim_pos.x, sim_pos.z)
			var d = current_2d.distance_to(target_2d)
			if d < min_dist_2d:
				min_dist_2d = d

			var speed = sim_vel.length()
			if speed < 0.05:
				break
			sim_pos += sim_vel * dt
			var decel = 0.48 * dt
			var new_speed = max(0.0, speed - decel)
			sim_vel = sim_vel.normalized() * new_speed
	else:
		var on_ground = false
		var ground_y = target_pos.y
		for step in range(200):
			var current_2d = Vector2(sim_pos.x, sim_pos.z)
			var d = current_2d.distance_to(target_2d)
			if d < min_dist_2d:
				min_dist_2d = d

			if not on_ground:
				sim_pos += sim_vel * dt
				sim_vel.y -= 9.81 * dt
				sim_vel *= (1.0 - 0.015 * dt)

				if sim_pos.y <= ground_y:
					sim_pos.y = ground_y
					on_ground = true
					sim_vel.y = absf(sim_vel.y) * 0.25
					sim_vel.x *= 0.55
					sim_vel.z *= 0.55
			else:
				var flat_speed = Vector2(sim_vel.x, sim_vel.z).length()
				if flat_speed < 0.08 and absf(sim_vel.y) < 0.1:
					break
				sim_pos += sim_vel * dt
				if sim_vel.y > 0.0:
					sim_vel.y -= 9.81 * dt
				else:
					sim_vel.y = 0.0
				sim_vel.x *= (1.0 - 1.2 * dt)
				sim_vel.z *= (1.0 - 1.2 * dt)

	var will_enter = (min_dist_2d <= threshold)
	return {
		"will_enter_zone": will_enter,
		"min_dist": min_dist_2d,
		"mode": mode
	}

func schedule_early_tension(mode: String, delay_seconds: float = 0.10) -> void:
	if not is_course_play_active():
		return
	cancel_scheduled_tension()
	_is_scheduled = true
	var timer = get_tree().create_timer(delay_seconds)
	await timer.timeout
	if _is_scheduled:
		_is_scheduled = false
		start_tension(mode, 0.40)

func cancel_scheduled_tension() -> void:
	_is_scheduled = false

# ---------------- LIVE PROXIMITY CHECK ----------------

func check_ball_proximity(ball_pos: Vector3, target_pos: Vector3, is_putt: bool, shot_start_pos: Vector3 = Vector3.ZERO, is_sand: bool = false) -> bool:
	if not is_course_play_active():
		return false
	if target_pos.is_zero_approx():
		return false
	if not shot_start_pos.is_zero_approx():
		if not is_shot_eligible_for_suspense(shot_start_pos, target_pos, is_putt, is_sand):
			return false

	var dist_2d = Vector2(ball_pos.x, ball_pos.z).distance_to(Vector2(target_pos.x, target_pos.z))
	var threshold = PUTT_THRESHOLD_METERS if is_putt else CHIP_THRESHOLD_METERS

	if dist_2d <= threshold:
		var closeness = clampf(1.0 - (dist_2d / threshold), 0.0, 1.0)
		current_closeness = maxf(current_closeness, closeness)
		if not tension_active:
			start_tension("putt" if is_putt else "chip", closeness)
		return true
	return false

# ----------------- ACTIVATION / DEACTIVATION -----------------

func start_tension(mode: String = "putt", initial_closeness: float = 0.40) -> void:
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

func stop_tension() -> void:
	cancel_scheduled_tension()
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
