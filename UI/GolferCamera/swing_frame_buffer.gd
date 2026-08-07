extends Node

# SwingFrameBuffer
# Maintains a circular buffer of camera frames and landmark snapshots
# for slow-motion swing replay when a shot is triggered.

class_name SwingFrameBuffer

const MAX_FRAMES: int = 90 # ~6 seconds at 15 FPS (e.g., 3.5s pre-shot, 2.5s post-shot)
const FRAME_INTERVAL: float = 0.066 # ~15 FPS cap

var _frames: Array[Dictionary] = []
var _last_push_time: float = 0.0
var _is_recording: bool = true


func set_recording(enabled: bool) -> void:
	_is_recording = enabled


func is_recording() -> bool:
	return _is_recording


func clear() -> void:
	_frames.clear()


## Push a frame image and landmark snapshot into the buffer
func push_frame(img: Image, landmarks: Dictionary) -> void:
	if not _is_recording or img == null or img.is_empty():
		return
	
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_push_time < FRAME_INTERVAL:
		return
	_last_push_time = now
	
	# Duplicate landmarks dictionary to prevent reference mutations
	var lm_copy := landmarks.duplicate(true)
	
	# Duplicate image so it isn't overwritten by the camera feed
	var img_copy: Image = img.duplicate()
	
	_frames.append({
		"image": img_copy,
		"landmarks": lm_copy,
		"timestamp": now
	})
	
	if _frames.size() > MAX_FRAMES:
		_frames.pop_front()


## Get a copy of the captured frames for replay
func get_captured_frames() -> Array[Dictionary]:
	return _frames.duplicate()


## Find impact frame index based on sudden motion or default to ~60% through buffer
func get_impact_frame_index() -> int:
	if _frames.is_empty():
		return 0
	# Default to ~60% into the buffer as impact point if no telemetry spike
	return int(_frames.size() * 0.6)
