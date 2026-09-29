class_name PuttingCameraStateMachine
extends Node

signal putt_detected(speed_mph: float, hla_deg: float)
signal putt_rejected(reason: String, speed_mph: float)

enum State { IDLE, READY, TRACKING, EXECUTION }

var current_state: State = State.IDLE
var overlay: PuttingCameraOverlay = null:
	set(val):
		if overlay != null and overlay.has_signal("circle_position_changed") and overlay.circle_position_changed.is_connected(_on_circle_position_changed):
			overlay.circle_position_changed.disconnect(_on_circle_position_changed)
		overlay = val
		if overlay != null:
			if overlay.has_signal("circle_position_changed") and not overlay.circle_position_changed.is_connected(_on_circle_position_changed):
				overlay.circle_position_changed.connect(_on_circle_position_changed)
			_established_ball_pos = overlay.circle_center
var detector: PuttingBallDetector = PuttingBallDetector.new()

## Framerate (used for timeouts and fallback estimates)
var active_fps: float = 30.0

## Sensor / image dimensions of the most recent frame
var last_frame_size: Vector2 = Vector2(1280, 720)

## Established resting position of the ball in READY state
var _established_ball_pos: Vector2 = Vector2(0.5, 0.70)

## Tracking state variables (timestamp and trajectory based)
var _tracking_start_frame: int = 0
var _tracking_frame_count: int = 0
var _tracking_start_time_msec: int = 0
var _last_seen_time_msec: int = 0
var _tracking_start_position: Vector2 = Vector2.ZERO
var _last_seen_pos: Vector2 = Vector2.ZERO
var _trajectory: Array[Dictionary] = []
var _total_frames_processed: int = 0
var _ball_last_seen_in_frame: bool = false
var _lateral_offset_at_departure: float = 0.0
var _frames_since_ball_lost: int = 0
const BALL_LOST_CONFIRM_FRAMES: int = 3   # Frames without detection to confirm exit

## Speed calibration constant
## Maps normalized speed (screen heights per second) to mph.
## Baseline: a putt crossing ~0.75 of screen height in ~0.35s = ~2.14 units/sec.
## At ~5.3 mph: 5.3 / 2.14 = 2.5.
var speed_calibration_constant: float = 2.5

## Direction calibration: pixels-to-degrees conversion
## Field of view baseline across camera frame width
var field_of_view_deg: float = 30.0

## Absolute physical bounds (safety clamps)
const ABSOLUTE_MAX_PUTT_SPEED_MPH: float = 25.0
const ABSOLUTE_MIN_PUTT_SPEED_MPH: float = 0.5

## Dynamic settings (synced with GlobalSettings.range_settings with fallbacks)
var min_putt_speed_mph: float:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			var gs = get_node("/root/GlobalSettings")
			if gs.range_settings != null and gs.range_settings.settings.has("putting_min_speed_mph"):
				return float(gs.range_settings.putting_min_speed_mph.value)
		return _local_min_putt_speed_mph
	set(val):
		_local_min_putt_speed_mph = val

var max_putt_speed_mph: float:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			var gs = get_node("/root/GlobalSettings")
			if gs.range_settings != null and gs.range_settings.settings.has("putting_max_speed_mph"):
				return float(gs.range_settings.putting_max_speed_mph.value)
		return _local_max_putt_speed_mph
	set(val):
		_local_max_putt_speed_mph = val

var mishit_filter_enabled: bool:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			var gs = get_node("/root/GlobalSettings")
			if gs.range_settings != null and gs.range_settings.settings.has("putting_mishit_filter_enabled"):
				return bool(gs.range_settings.putting_mishit_filter_enabled.value)
		return _local_mishit_filter_enabled
	set(val):
		_local_mishit_filter_enabled = val

var _local_min_putt_speed_mph: float = 1.5
var _local_max_putt_speed_mph: float = 20.0
var _local_mishit_filter_enabled: bool = true


var _audio_player: AudioStreamPlayer = null


func _ready() -> void:
	set_process(false)  # Processing is driven by process_frame() calls, not _process()
	_setup_audio_player()


func _setup_audio_player() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.name = "PuttingReadyDingPlayer"
	_audio_player.bus = "Master"
	add_child(_audio_player)

	var ding_path := "res://assets/audio/sfx/ready_ding.wav"
	if ResourceLoader.exists(ding_path):
		var stream = load(ding_path) as AudioStream
		if stream != null:
			_audio_player.stream = stream
			return
	if is_inside_tree() and has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if lm != null and lm.has_method("_generate_fallback_ding_stream"):
			_audio_player.stream = lm._generate_fallback_ding_stream()


func _play_ready_sound() -> void:
	if is_inside_tree() and has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if lm != null:
			if "settings" in lm and not bool(lm.settings.get("ready_ding_enabled", true)):
				return
			if lm.has_method("play_ready_ding"):
				lm.play_ready_ding()
				return
	if _audio_player != null and _audio_player.stream != null:
		_audio_player.play()


## Called by range_ui.gd for every incoming camera frame
func process_frame(image: Image) -> void:
	if overlay == null or image == null:
		return

	_total_frames_processed += 1
	last_frame_size = Vector2(image.get_width(), image.get_height())

	var circle_center = overlay.circle_center
	var circle_radius = overlay.circle_radius_norm
	var result = detector.detect_ball(image, circle_center, circle_radius)

	match current_state:
		State.IDLE:
			_handle_idle(result, image)
		State.READY:
			_handle_ready(result)
		State.TRACKING:
			_handle_tracking(result)
		State.EXECUTION:
			_handle_execution(result, image)


func _handle_idle(result: Dictionary, image: Image = null) -> void:
	if result.get("found", false):
		var center: Vector2 = result.get("center", Vector2.ZERO)
		overlay.set_ball_position(center)

		if detector.is_ball_in_circle(center, overlay.circle_center, overlay.circle_radius_norm):
			overlay.set_ball_in_circle(true)
			if result.get("at_rest", false):
				_established_ball_pos = center
				if image != null:
					detector.sample_reference_color(image, center)
				_transition_to(State.READY)
		else:
			overlay.set_ball_in_circle(false)
	else:
		overlay.set_ball_in_circle(false)
		overlay.set_ball_position(Vector2.ZERO)


func _handle_ready(result: Dictionary) -> void:
	var center: Vector2 = result.get("center", Vector2.ZERO)
	var found: bool = result.get("found", false)

	if found:
		overlay.set_ball_position(center)

		# Check if the ball is still in the circle
		if detector.is_ball_in_circle(center, overlay.circle_center, overlay.circle_radius_norm):
			overlay.set_ball_in_circle(true)
			_established_ball_pos = center

			# Has it moved significantly forward?
			var dy = center.y - _established_ball_pos.y
			if dy <= -0.012:
				_start_tracking(center)
				return
		else:
			# Ball is outside circle: check if it moved FORWARD (putt launched!)
			if center.y < _established_ball_pos.y - 0.012:
				_start_tracking(center)
				return
			else:
				# Ball moved outside circle backwards or sideways without forward progress
				overlay.set_ball_in_circle(false)
				_transition_to(State.IDLE)
				return
	else:
		# Ball disappeared from circle!
		# Could be a fast-exit putt (exited circle in 1 frame) or ball picked up.
		# Start tracking from established ball position to search the forward corridor!
		_start_tracking(_established_ball_pos)


func _start_tracking(first_seen_pos: Vector2) -> void:
	_tracking_start_frame = _total_frames_processed
	_tracking_frame_count = 0
	_tracking_start_time_msec = Time.get_ticks_msec()
	_last_seen_time_msec = _tracking_start_time_msec
	_tracking_start_position = _established_ball_pos
	_last_seen_pos = first_seen_pos

	var frame_interval_msec: int = int(1000.0 / maxf(active_fps, 10.0))
	if first_seen_pos != _established_ball_pos:
		# Ball was detected at first_seen_pos on this frame, meaning it departed rest 1 frame prior.
		# Backdate the rest position timestamp so the initial segment duration is physically accurate.
		_tracking_start_time_msec = _last_seen_time_msec - frame_interval_msec
		_trajectory = [
			{ "pos": _established_ball_pos, "time": _tracking_start_time_msec },
			{ "pos": first_seen_pos, "time": _last_seen_time_msec }
		]
	else:
		_trajectory = [{ "pos": _established_ball_pos, "time": _tracking_start_time_msec }]

	_frames_since_ball_lost = 0
	_lateral_offset_at_departure = detector.calculate_lateral_offset(first_seen_pos, overlay.circle_center.x)
	_transition_to(State.TRACKING)


func _handle_tracking(result: Dictionary) -> void:
	_tracking_frame_count += 1
	var now_msec: int = Time.get_ticks_msec()

	if result.get("found", false):
		var center: Vector2 = result.get("center", Vector2.ZERO)

		# Kinematic forward gating:
		# Early frames allow slight departure jitter, later frames tighten considerably.
		var last_known = _last_seen_pos if _last_seen_pos != Vector2.ZERO else _tracking_start_position
		var delta_y = center.y - last_known.y
		var delta_x = absf(center.x - last_known.x)

		var max_backward = 0.015 if _tracking_frame_count <= 2 else 0.005
		var max_lateral = 0.18 if _tracking_frame_count <= 2 else 0.11

		# Maximum realistic forward jump per frame:
		# Prevents distractor blobs (putter follow-through, shoes, reflections near top of view)
		# from teleporting the ball across the frame in a single frame.
		var max_forward_jump = clampf((max_putt_speed_mph / speed_calibration_constant / maxf(active_fps, 15.0)) * 1.75, 0.28, 0.45)

		var kinematically_valid = (delta_y <= max_backward and -delta_y <= max_forward_jump and delta_x <= max_lateral)

		# Velocity direction consistency check when we already have trajectory history
		if kinematically_valid and _trajectory.size() >= 3:
			var prev_vector = (_trajectory[_trajectory.size() - 1]["pos"] as Vector2) - (_trajectory[0]["pos"] as Vector2)
			var cur_step = center - last_known
			if prev_vector.length_squared() > 0.0004 and cur_step.length_squared() > 0.0001:
				var dot = prev_vector.normalized().dot(cur_step.normalized())
				if dot < 0.25:  # Deviation > ~75 degrees from overall trajectory
					kinematically_valid = false

		if kinematically_valid:
			overlay.set_ball_position(center)
			_ball_last_seen_in_frame = true
			_frames_since_ball_lost = 0
			_last_seen_pos = center
			_last_seen_time_msec = now_msec
			_trajectory.append({ "pos": center, "time": now_msec })
			_lateral_offset_at_departure = detector.calculate_lateral_offset(center, overlay.circle_center.x)

			# Early exit check: ball reached upper frame boundary (top 10% of frame)
			if center.y <= 0.10:
				_calculate_and_dispatch_putt()
				return

			# Settle check: ball came to rest inside the camera view (short / soft putt)
			if _trajectory.size() >= 4 and center.distance_to(_tracking_start_position) >= 0.06:
				var prev_pt = _trajectory[_trajectory.size() - 2]["pos"] as Vector2
				if result.get("at_rest", false) or center.distance_to(prev_pt) < 0.005:
					_calculate_and_dispatch_putt()
					return
		else:
			# Distractor/outlier (putter follow-through, glare, shoe) — ignore!
			_ball_last_seen_in_frame = false
			_frames_since_ball_lost += 1
	else:
		_ball_last_seen_in_frame = false
		_frames_since_ball_lost += 1

	# Fast-exit detection:
	# If the ball was already near the upper boundary (y <= 0.18) and is lost,
	# it has cleanly exited the camera view. Dispatch immediately without waiting!
	if _last_seen_pos.y <= 0.18 and _frames_since_ball_lost >= 1 and _trajectory.size() >= 2:
		_calculate_and_dispatch_putt()
		return

	# Dynamic exit / lost timeout: allow more grace frames early on in case putter momentarily occludes ball
	var lost_threshold = 5 if _tracking_frame_count < 8 else BALL_LOST_CONFIRM_FRAMES
	if _frames_since_ball_lost >= lost_threshold:
		_calculate_and_dispatch_putt()
		return

	# Safety timeout: if tracking for too long (>4 seconds), abort
	if (now_msec - _tracking_start_time_msec) > 4000:
		print("[PuttingCam] Tracking timeout — resetting to IDLE")
		_transition_to(State.IDLE)


## Handles frame processing while in EXECUTION state (after a putt is registered).
## Watches for the next ball to be placed and settle in the circle to transition directly to READY.
func _handle_execution(result: Dictionary, image: Image = null) -> void:
	if result.get("found", false):
		var center: Vector2 = result.get("center", Vector2.ZERO)
		overlay.set_ball_position(center)
		if detector.is_ball_in_circle(center, overlay.circle_center, overlay.circle_radius_norm):
			overlay.set_ball_in_circle(true)
			if result.get("at_rest", false):
				_established_ball_pos = center
				if image != null:
					detector.sample_reference_color(image, center)
				_transition_to(State.READY)
		else:
			overlay.set_ball_in_circle(false)
	else:
		overlay.set_ball_in_circle(false)
		overlay.set_ball_position(Vector2.ZERO)


func _calculate_and_dispatch_putt() -> void:
	# Filter trajectory to strictly forward points (strip any potential glitches)
	var clean_trajectory: Array[Dictionary] = []
	if _trajectory.size() > 0:
		clean_trajectory.append(_trajectory[0])
		for i in range(1, _trajectory.size()):
			var cur_p: Vector2 = _trajectory[i]["pos"]
			var last_p: Vector2 = clean_trajectory[clean_trajectory.size() - 1]["pos"]
			var fwd = last_p.y - cur_p.y
			var lat = absf(cur_p.x - last_p.x)
			if fwd >= -0.015 and lat <= 0.18:
				clean_trajectory.append(_trajectory[i])
	_trajectory = clean_trajectory

	if _trajectory.size() < 2:
		print("[PuttingCam] Tracking aborted: insufficient trajectory points (%d)" % _trajectory.size())
		_transition_to(State.IDLE)
		return

	if _trajectory.size() > 0:
		_last_seen_pos = _trajectory[_trajectory.size() - 1]["pos"]
		_last_seen_time_msec = _trajectory[_trajectory.size() - 1]["time"]

	var total_displacement: Vector2 = _last_seen_pos - _tracking_start_position
	var forward_y_norm: float = -total_displacement.y  # positive = forward (-Y in screen space)
	var distance_norm: float = total_displacement.length()

	# VALIDATION: A real putt must move forward down the mat!
	# Reject ball pickup, hand occlusions, and putter head movement
	var is_fast_top_exit = (_last_seen_pos.y <= 0.18 and forward_y_norm > 0.02)
	if forward_y_norm < 0.05 or distance_norm < 0.05:
		if not is_fast_top_exit:
			print("[PuttingCam] Tracking aborted: insufficient forward displacement (dist=%.2f, fwd_y=%.2f, pts=%d) — not a valid putt" % [
				distance_norm, forward_y_norm, _trajectory.size()
			])
			if mishit_filter_enabled and overlay != null:
				overlay.show_rejection_notice("⚠️ Mishit: Ball didn't leave circle")
			putt_rejected.emit("insufficient_displacement", 0.0)
			_transition_to(State.IDLE)
			return

	# Frame-rate reconciled elapsed time:
	# Protects against network/thread packet clustering where multiple frames arrive in rapid bursts.
	var wall_elapsed_sec: float = float(_last_seen_time_msec - _tracking_start_time_msec) / 1000.0
	var sensor_frame_count: int = max(_tracking_frame_count, _trajectory.size() - 1)
	var expected_sensor_sec: float = float(sensor_frame_count) / maxf(active_fps, 15.0)

	var elapsed_sec: float = maxf(wall_elapsed_sec, expected_sensor_sec * 0.85)
	elapsed_sec = maxf(elapsed_sec, 0.05)  # Enforce physical minimum elapsed time (50ms)

	# Calculate speed in normalized screen units per second
	# Use segment speeds across trajectory if available to reject network stalls and packet jitter
	var norm_speed: float = 0.0
	var segment_speeds: Array[float] = []
	var min_dt: float = 0.70 / maxf(active_fps, 15.0)
	var max_plausible_seg_norm: float = (max_putt_speed_mph / speed_calibration_constant) * 1.5

	if _trajectory.size() >= 2:
		for i in range(1, _trajectory.size()):
			var raw_dt = float(_trajectory[i]["time"] - _trajectory[i - 1]["time"]) / 1000.0
			var dt = maxf(raw_dt, min_dt)
			var d = (_trajectory[i]["pos"] as Vector2).distance_to(_trajectory[i - 1]["pos"] as Vector2)
			if dt >= 0.01 and dt <= 0.6 and d >= 0.005:
				var seg_spd = d / dt
				if seg_spd <= max_plausible_seg_norm:
					segment_speeds.append(seg_spd)

	var overall_norm_speed: float = distance_norm / elapsed_sec

	if segment_speeds.size() >= 3:
		segment_speeds.sort()
		var mid = segment_speeds.size() / 2
		var median_spd = segment_speeds[mid]
		if segment_speeds.size() % 2 == 0:
			median_spd = (segment_speeds[mid - 1] + segment_speeds[mid]) * 0.5
		norm_speed = 0.6 * median_spd + 0.4 * overall_norm_speed
	elif segment_speeds.size() >= 1:
		var sum_spd: float = 0.0
		for s in segment_speeds:
			sum_spd += s
		var avg_spd = sum_spd / float(segment_speeds.size())
		norm_speed = 0.5 * avg_spd + 0.5 * overall_norm_speed
	else:
		norm_speed = overall_norm_speed

	# Speed mapping: norm_speed * speed_calibration_constant
	var raw_speed_mph: float = norm_speed * speed_calibration_constant

	# AUTO-DETECT INVALID SPEEDS & MISHITS:
	var min_speed = min_putt_speed_mph
	var max_speed = max_putt_speed_mph
	var filter_active = mishit_filter_enabled

	# 1. Under-speed check (accidental ball nudge / practice waggle / tap too soft)
	if filter_active and raw_speed_mph < min_speed:
		print("[PuttingCam] Mishit ignored: speed (%.1f mph) is below minimum threshold (%.1f mph)" % [
			raw_speed_mph, min_speed
		])
		if overlay != null:
			overlay.show_rejection_notice("⚠️ Mishit: %.1f mph (Below %.1f mph - Ignored)" % [raw_speed_mph, min_speed])
		putt_rejected.emit("mishit_too_slow", raw_speed_mph)
		_transition_to(State.IDLE)
		return

	# 2. Over-speed check (tracking anomaly, teleporting blob, reflection spike > max speed)
	if filter_active and raw_speed_mph > max_speed:
		print("[PuttingCam] Invalid speed ignored: speed (%.1f mph) exceeds max realistic speed (%.1f mph)" % [
			raw_speed_mph, max_speed
		])
		if overlay != null:
			overlay.show_rejection_notice("⚠️ Invalid Speed: %.1f mph (Ignored)" % raw_speed_mph)
		putt_rejected.emit("invalid_speed_too_fast", raw_speed_mph)
		_transition_to(State.IDLE)
		return

	var speed_mph: float = clampf(raw_speed_mph, ABSOLUTE_MIN_PUTT_SPEED_MPH, ABSOLUTE_MAX_PUTT_SPEED_MPH)

	# Direction: calculate actual trajectory launch angle in sensor pixel space
	var W: float = last_frame_size.x if last_frame_size.x > 0.0 else 1280.0
	var H: float = last_frame_size.y if last_frame_size.y > 0.0 else 720.0
	var hla_deg: float = 0.0

	# If we have >= 3 points, compute linear regression slope across forward trajectory
	if _trajectory.size() >= 3:
		var sum_y: float = 0.0
		var sum_x: float = 0.0
		var sum_yy: float = 0.0
		var sum_yx: float = 0.0
		var n: float = 0.0

		for pt in _trajectory:
			var p: Vector2 = pt["pos"]
			var px_x: float = p.x * W
			var px_fwd_y: float = -p.y * H  # Forward progress in pixels
			sum_x += px_x
			sum_y += px_fwd_y
			sum_yy += px_fwd_y * px_fwd_y
			sum_yx += px_fwd_y * px_x
			n += 1.0

		var denom: float = n * sum_yy - (sum_y * sum_y)
		if absf(denom) > 1e-5:
			var slope: float = (n * sum_yx - sum_y * sum_x) / denom
			hla_deg = rad_to_deg(atan(slope))
		else:
			var dx_px = total_displacement.x * W
			var dy_fwd_px = -total_displacement.y * H
			hla_deg = rad_to_deg(atan2(dx_px, dy_fwd_px))
	else:
		var dx_px = total_displacement.x * W
		var dy_fwd_px = -total_displacement.y * H
		if dy_fwd_px > 0.0:
			hla_deg = rad_to_deg(atan2(dx_px, dy_fwd_px))
		else:
			hla_deg = 0.0

	hla_deg = clampf(hla_deg, -field_of_view_deg, field_of_view_deg)

	print("[PuttingCam] Putt detected: %.1f mph, %.1f° offline (norm_spd=%.2f, dist=%.2f, time=%.3fs, pts=%d)" % [
		speed_mph, hla_deg, norm_speed, distance_norm, elapsed_sec, _trajectory.size()
	])

	# Update overlay result (persists at bottom of feed until next hit)
	overlay.set_result(speed_mph, hla_deg)
	_transition_to(State.EXECUTION)

	# Emit signal for range_ui.gd
	putt_detected.emit(speed_mph, hla_deg)


func _transition_to(new_state: State) -> void:
	current_state = new_state
	if overlay != null:
		overlay.set_state(new_state)
	match new_state:
		State.IDLE:
			detector.reset()
			overlay.set_ball_in_circle(false)
			overlay.set_ball_position(Vector2.ZERO)
			_frames_since_ball_lost = 0
			_trajectory.clear()
		State.READY:
			detector.is_tracking = false
			_frames_since_ball_lost = 0
			if overlay != null:
				_established_ball_pos = overlay.circle_center
			if detector.ball_found:
				_established_ball_pos = detector.ball_center_norm
			_play_ready_sound()
		State.TRACKING:
			detector.is_tracking = true
		State.EXECUTION:
			detector.is_tracking = false


## Called when settings change to update the active FPS
func set_fps(fps: float) -> void:
	active_fps = maxf(fps, 1.0)


func reset() -> void:
	_transition_to(State.IDLE)
	_total_frames_processed = 0
	_trajectory.clear()


func _on_circle_position_changed(new_pos: Vector2) -> void:
	_established_ball_pos = new_pos
	if current_state == State.READY or current_state == State.TRACKING:
		_transition_to(State.IDLE)

