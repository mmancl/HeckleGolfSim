class_name FrameRateMonitor
extends RefCounted

## Monitors camera frame arrival intervals, calculates rolling FPS and jitter,
## detects duplicate frames, and enforces the minimum framerate requirement.

const MIN_REQUIRED_FPS: float = 15.0
const STABLE_FPS_THRESHOLD: float = 25.0
const HIGH_FPS_THRESHOLD: float = 55.0
const MAX_SAMPLES: int = 40
const MIN_SAMPLES_FOR_VALIDATION: int = 6

enum StabilityTier {
	UNKNOWN,
	CRITICAL_LOW,  # < 15 FPS (hard-blocks tracking)
	DEGRADED,      # 15 - 24.9 FPS (allowed, but lower temporal resolution)
	STABLE,        # 25 - 54.9 FPS (standard operation)
	HIGH_PRECISION # >= 55 FPS (optimal)
}

var _timestamps_usec: Array[int] = []
var _deltas_usec: Array[int] = []
var _last_timestamp_usec: int = 0
var _last_frame_hash: int = 0
var _duplicate_frame_count: int = 0

var current_fps: float = 0.0
var average_interval_ms: float = 0.0
var jitter_ms: float = 0.0
var stability_tier: StabilityTier = StabilityTier.UNKNOWN
var is_valid_for_tracking: bool = false
var total_frames_measured: int = 0


## Registers an incoming frame timestamp (in microseconds).
## Returns true if frame is accepted as a unique valid frame, false if rejected as a duplicate.
func record_frame(source_time_usec: int = -1, frame_hash: int = 0) -> bool:
	var now_usec: int = source_time_usec if source_time_usec > 0 else Time.get_ticks_usec()
	
	if _last_timestamp_usec > 0:
		var dt_usec: int = now_usec - _last_timestamp_usec
		# Check for duplicate arrival (less than 2ms apart or identical hash)
		if dt_usec < 2000 or (frame_hash != 0 and frame_hash == _last_frame_hash and dt_usec < 15000):
			_duplicate_frame_count += 1
			return false
		
		_deltas_usec.append(dt_usec)
		if _deltas_usec.size() > MAX_SAMPLES:
			_deltas_usec.pop_front()
	
	_last_timestamp_usec = now_usec
	_last_frame_hash = frame_hash
	total_frames_measured += 1
	
	_timestamps_usec.append(now_usec)
	if _timestamps_usec.size() > MAX_SAMPLES:
		_timestamps_usec.pop_front()
	
	_update_metrics(now_usec)
	return true


func _update_metrics(now_usec: int) -> void:
	if _timestamps_usec.size() < 2 or _deltas_usec.is_empty():
		return
	
	# Calculate FPS over recent 1.0-second window
	var window_start_usec: int = now_usec - 1_000_000
	var recent_frames: int = 0
	for t in _timestamps_usec:
		if t >= window_start_usec:
			recent_frames += 1
	
	if recent_frames >= 2 and _timestamps_usec.size() >= 2:
		var span_usec: int = _timestamps_usec[_timestamps_usec.size() - 1] - _timestamps_usec[maxi(0, _timestamps_usec.size() - recent_frames)]
		if span_usec > 10_000:
			current_fps = float(recent_frames - 1) / (float(span_usec) / 1_000_000.0)
	elif _deltas_usec.size() > 0:
		var sum_dt: float = 0.0
		for dt in _deltas_usec:
			sum_dt += dt
		var avg_dt = sum_dt / float(_deltas_usec.size())
		if avg_dt > 1000.0:
			current_fps = 1_000_000.0 / avg_dt
	
	# Average interval and jitter (standard deviation)
	if _deltas_usec.size() >= 3:
		var sum_d: float = 0.0
		for dt in _deltas_usec:
			sum_d += float(dt) / 1000.0
		average_interval_ms = sum_d / float(_deltas_usec.size())
		
		var sum_sq: float = 0.0
		for dt in _deltas_usec:
			var diff = (float(dt) / 1000.0) - average_interval_ms
			sum_sq += diff * diff
		jitter_ms = sqrt(sum_sq / float(_deltas_usec.size()))
	
	# Evaluate stability tier & validation
	if _timestamps_usec.size() >= MIN_SAMPLES_FOR_VALIDATION:
		if current_fps < MIN_REQUIRED_FPS:
			stability_tier = StabilityTier.CRITICAL_LOW
			is_valid_for_tracking = false
		elif current_fps < STABLE_FPS_THRESHOLD:
			stability_tier = StabilityTier.DEGRADED
			is_valid_for_tracking = true
		elif current_fps < HIGH_FPS_THRESHOLD:
			stability_tier = StabilityTier.STABLE
			is_valid_for_tracking = true
		else:
			stability_tier = StabilityTier.HIGH_PRECISION
			is_valid_for_tracking = true
	else:
		stability_tier = StabilityTier.UNKNOWN
		is_valid_for_tracking = false


func get_status_text() -> String:
	match stability_tier:
		StabilityTier.UNKNOWN:
			return "Measuring FPS..."
		StabilityTier.CRITICAL_LOW:
			return "⚠️ %.1f FPS (Too Low)" % current_fps
		StabilityTier.DEGRADED:
			return "▲ %.1f FPS (Degraded)" % current_fps
		StabilityTier.STABLE:
			return "● %.1f FPS" % current_fps
		StabilityTier.HIGH_PRECISION:
			return "★ %.1f FPS (High)" % current_fps
		_:
			return "%.1f FPS" % current_fps


func reset() -> void:
	_timestamps_usec.clear()
	_deltas_usec.clear()
	_last_timestamp_usec = 0
	_last_frame_hash = 0
	current_fps = 0.0
	average_interval_ms = 0.0
	jitter_ms = 0.0
	stability_tier = StabilityTier.UNKNOWN
	is_valid_for_tracking = false
	total_frames_measured = 0
