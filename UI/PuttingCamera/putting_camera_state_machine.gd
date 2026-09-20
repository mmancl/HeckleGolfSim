class_name PuttingCameraStateMachine
extends Node

signal putt_detected(speed_mph: float, hla_deg: float)

enum State { IDLE, READY, TRACKING, EXECUTION }

var current_state: State = State.IDLE
var overlay: PuttingCameraOverlay = null
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

## Maximum allowable putt speed (sanity check)
const MAX_PUTT_SPEED_MPH: float = 25.0
const MIN_PUTT_SPEED_MPH: float = 0.5


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
			_handle_idle(result)
		State.READY:
			_handle_ready(result)
		State.TRACKING:
			_handle_tracking(result)
		State.EXECUTION:
			_handle_execution(result)


func _handle_idle(result: Dictionary) -> void:
	if result.get("found", false):
		var center: Vector2 = result.get("center", Vector2.ZERO)
		overlay.set_ball_position(center)

		if detector.is_ball_in_circle(center, overlay.circle_center, overlay.circle_radius_norm):
			overlay.set_ball_in_circle(true)
			if result.get("at_rest", false):
				_established_ball_pos = center
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
	_trajectory = [{ "pos": _established_ball_pos, "time": _tracking_start_time_msec }]
	if first_seen_pos != _established_ball_pos:
		_trajectory.append({ "pos": first_seen_pos, "time": _tracking_start_time_msec })
	_frames_since_ball_lost = 0
	_lateral_offset_at_departure = detector.calculate_lateral_offset(first_seen_pos, overlay.circle_center.x)
	_transition_to(State.TRACKING)


func _handle_tracking(result: Dictionary) -> void:
	_tracking_frame_count += 1
	var now_msec: int = Time.get_ticks_msec()

	if result.get("found", false):
		var center: Vector2 = result.get("center", Vector2.ZERO)

		# Kinematic forward gating:
		# A rolling golf ball ONLY advances forward (-Y direction down the green).
		# It NEVER jumps backwards toward the golfer/putter, nor can it jump sideways by >0.18.
		var last_known = _last_seen_pos if _last_seen_pos != Vector2.ZERO else _tracking_start_position
		var delta_y = center.y - last_known.y
		var delta_x = absf(center.x - last_known.x)

		if delta_y <= 0.015 and delta_x <= 0.18:
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

	# Standard exit / lost timeout
	if _frames_since_ball_lost >= BALL_LOST_CONFIRM_FRAMES:
		_calculate_and_dispatch_putt()
		return

	# Safety timeout: if tracking for too long (>4 seconds), abort
	if (now_msec - _tracking_start_time_msec) > 4000:
		print("[PuttingCam] Tracking timeout — resetting to IDLE")
		_transition_to(State.IDLE)


## Handles frame processing while in EXECUTION state (after a putt is registered).
## Watches for the next ball to be placed and settle in the circle to transition directly to READY.
func _handle_execution(result: Dictionary) -> void:
	if result.get("found", false):
		var center: Vector2 = result.get("center", Vector2.ZERO)
		overlay.set_ball_position(center)
		if detector.is_ball_in_circle(center, overlay.circle_center, overlay.circle_radius_norm):
			overlay.set_ball_in_circle(true)
			if result.get("at_rest", false):
				_established_ball_pos = center
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
			if cur_p.y <= last_p.y + 0.015 and absf(cur_p.x - last_p.x) <= 0.18:
				clean_trajectory.append(_trajectory[i])
	_trajectory = clean_trajectory

	if _trajectory.size() > 0:
		_last_seen_pos = _trajectory[_trajectory.size() - 1]["pos"]
		_last_seen_time_msec = _trajectory[_trajectory.size() - 1]["time"]

	var total_displacement: Vector2 = _last_seen_pos - _tracking_start_position
	var forward_y_norm: float = -total_displacement.y  # positive = forward (-Y in screen space)
	var distance_norm: float = total_displacement.length()
	var elapsed_sec: float = float(_last_seen_time_msec - _tracking_start_time_msec) / 1000.0

	# VALIDATION: A real putt must move forward down the mat!
	# Reject ball pickup, hand occlusions, and putter head movement
	var is_fast_top_exit = (_last_seen_pos.y <= 0.18 and forward_y_norm > 0.02)
	if forward_y_norm < 0.05 or distance_norm < 0.05:
		if not is_fast_top_exit:
			print("[PuttingCam] Tracking aborted: insufficient forward displacement (dist=%.2f, fwd_y=%.2f, pts=%d) — not a valid putt" % [
				distance_norm, forward_y_norm, _trajectory.size()
			])
			_transition_to(State.IDLE)
			return

	# Elapsed time sanity check
	if elapsed_sec < 0.02:
		var now_msec = Time.get_ticks_msec()
		elapsed_sec = clampf(float(now_msec - _tracking_start_time_msec) / 1000.0, 0.05, 1.5)

	# Calculate speed in normalized screen units per second
	# Use segment speeds across trajectory if available to reject network stalls and packet jitter
	var norm_speed: float = 0.0
	var segment_speeds: Array[float] = []

	if _trajectory.size() >= 2:
		for i in range(1, _trajectory.size()):
			var dt = float(_trajectory[i]["time"] - _trajectory[i - 1]["time"]) / 1000.0
			var d = (_trajectory[i]["pos"] as Vector2).distance_to(_trajectory[i - 1]["pos"] as Vector2)
			if dt >= 0.01 and dt <= 0.5 and d >= 0.005:
				segment_speeds.append(d / dt)

	if segment_speeds.size() >= 2:
		segment_speeds.sort()
		var mid = segment_speeds.size() / 2
		norm_speed = segment_speeds[mid]
	else:
		norm_speed = distance_norm / maxf(elapsed_sec, 0.04)

	# Speed mapping: norm_speed * speed_calibration_constant
	var speed_mph: float = norm_speed * speed_calibration_constant
	speed_mph = clampf(speed_mph, MIN_PUTT_SPEED_MPH, MAX_PUTT_SPEED_MPH)

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
