extends Node

# PoseDetectionBridge
# Autoload singleton that manages the pose detection & desktop camera backend.
# Automatically selects the right backend for the current platform:
#   - Android: Native Java plugin (MediaPipe Android SDK via GodotPlugin)
#   - Desktop: Auto-started Python HTTP server (mediapipe + OpenCV camera server)
# Provides a unified API for GolferSkeletonOverlay and UI components.

signal pose_detected(landmarks: Dictionary)
signal pose_lost()
signal server_ready()

# Desktop camera signals
signal desktop_cameras_updated(cameras: Array)
signal desktop_frame_received(image: Image, texture: Texture2D, landmarks: Dictionary)

# Platform state
var _is_android: bool = false
var _plugin = null  # Android GodotPlugin singleton

# Desktop HTTP state
var _http_req: HTTPRequest = null
var _health_req: HTTPRequest = null
var _cam_scan_req: HTTPRequest = null
var _cam_select_req: HTTPRequest = null
var _cam_capture_req: HTTPRequest = null
var _python_pid: int = -1
var _server_is_ready: bool = false
var _health_check_attempts: int = 0

# Desktop system camera state
var desktop_cameras: Array = []
var active_desktop_camera_index: int = -1
var _desktop_polling_active: bool = false
var _desktop_polling_in_flight: bool = false

# Rate limiting
var _last_req_time: float = 0.0
var _request_in_flight: bool = false

const SERVER_PORT: int = 49154
const SERVER_URL: String = "http://127.0.0.1:49154/pose"
const HEALTH_URL: String = "http://127.0.0.1:49154/health"
const CAMERAS_URL: String = "http://127.0.0.1:49154/cameras"
const CAM_SELECT_URL: String = "http://127.0.0.1:49154/camera/select"
const CAM_CAPTURE_URL: String = "http://127.0.0.1:49154/camera/capture"

const MAX_HEALTH_RETRIES: int = 15
const FRAME_INTERVAL: float = 0.04  # ~25 FPS cap for desktop camera streaming


func _ready() -> void:
	_is_android = OS.get_name() == "Android"
	
	if _is_android:
		_init_android_plugin()
	else:
		_init_desktop_server()


func is_ready() -> bool:
	return _server_is_ready


# ─── Android Plugin Backend ──────────────────────────────────────────────────

func _init_android_plugin() -> void:
	if Engine.has_singleton("MediaPipePosePlugin"):
		_plugin = Engine.get_singleton("MediaPipePosePlugin")
		if _plugin.has_signal("pose_result"):
			_plugin.connect("pose_result", _on_android_pose_result)
		if _plugin.has_signal("camera_frame"):
			_plugin.connect("camera_frame", _on_android_camera_frame)
		_server_is_ready = true
		var is_loaded: bool = _plugin.call("isModelLoaded") if _plugin.has_method("isModelLoaded") else true
		var is_gpu: bool = _plugin.call("isGpuAccelerated") if _plugin.has_method("isGpuAccelerated") else false
		if _plugin.has_method("setLiveInferenceEnabled"):
			_plugin.call("setLiveInferenceEnabled", false)
		print("[PoseDetectionBridge] Android On-Device MediaPipe plugin loaded. (Model ready: %s, GPU: %s, Live inference: deferred)" % [is_loaded, is_gpu])
		server_ready.emit()
	else:
		print("[PoseDetectionBridge] Android native MediaPipe plugin not found.")
		_server_is_ready = false
		pose_lost.emit()


func _on_android_pose_result(json_str: String) -> void:
	_request_in_flight = false
	_parse_and_emit(json_str)


func _on_android_camera_frame(jpg_bytes: PackedByteArray, json_str: String) -> void:
	if jpg_bytes.is_empty():
		return
	
	var img := Image.new()
	var err := img.load_jpg_from_buffer(jpg_bytes)
	if err != OK or img.is_empty():
		return
	
	var tex := ImageTexture.create_from_image(img)
	
	var landmarks: Dictionary = {}
	var detected: bool = false
	var json := JSON.new()
	if json.parse(json_str) == OK and json.data is Dictionary:
		detected = json.data.get("detected", false)
		if detected:
			landmarks = json.data.get("landmarks", {})
	
	if detected:
		pose_detected.emit(landmarks)
	else:
		pose_lost.emit()
	
	desktop_frame_received.emit(img, tex, landmarks)


func start_android_camera(facing: int = 0) -> void:
	if _is_android and _plugin != null and _plugin.has_method("startCamera"):
		_plugin.call("startCamera", facing)


func stop_android_camera() -> void:
	if _is_android and _plugin != null and _plugin.has_method("stopCamera"):
		_plugin.call("stopCamera")


func is_android_camera_active() -> bool:
	if _is_android and _plugin != null and _plugin.has_method("isCameraActive"):
		return _plugin.call("isCameraActive")
	return false


func has_android_camera() -> bool:
	if _is_android and _plugin != null and _plugin.has_method("hasCamera"):
		return _plugin.call("hasCamera")
	return false


func get_android_camera_count() -> int:
	if _is_android and _plugin != null and _plugin.has_method("getCameraCount"):
		return _plugin.call("getCameraCount")
	return 0


func set_live_inference_enabled(enabled: bool) -> void:
	if _is_android and _plugin != null and _plugin.has_method("setLiveInferenceEnabled"):
		_plugin.call("setLiveInferenceEnabled", enabled)


func is_live_inference_enabled() -> bool:
	if _is_android and _plugin != null and _plugin.has_method("isLiveInferenceEnabled"):
		return _plugin.call("isLiveInferenceEnabled")
	return false


# ─── Desktop Python Server Backend ──────────────────────────────────────────

func _init_desktop_server() -> void:
	# Create HTTP request node for pose inference
	_http_req = HTTPRequest.new()
	_http_req.name = "PoseBridgeHTTPRequest"
	_http_req.timeout = 3.0
	_http_req.request_completed.connect(_on_pose_http_response)
	add_child(_http_req)
	
	# Check if server is already running first
	_check_existing_server()


func _check_existing_server() -> void:
	if _health_req != null:
		_health_req.queue_free()
	_health_req = HTTPRequest.new()
	_health_req.name = "InitialHealthCheck"
	_health_req.timeout = 0.8
	_health_req.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		if _health_req != null:
			_health_req.queue_free()
			_health_req = null
		if response_code == 200:
			print("[PoseDetectionBridge] Reusing existing Python server at %s." % SERVER_URL)
			_server_is_ready = true
			server_ready.emit()
			fetch_desktop_cameras()
		else:
			_start_python_server()
	)
	add_child(_health_req)
	var err := _health_req.request(HEALTH_URL)
	if err != OK:
		if _health_req != null:
			_health_req.queue_free()
			_health_req = null
		_start_python_server()


func _start_python_server() -> void:
	var script_path := _resolve_server_script_path()
	if script_path.is_empty():
		push_error("[PoseDetectionBridge] Could not find pose_server.py")
		_server_is_ready = false
		pose_lost.emit()
		return
	
	var python_cmd := _find_python_executable()
	if python_cmd.is_empty():
		push_error("[PoseDetectionBridge] Python 3.9+ not found. Install Python & mediapipe to enable AI pose detection.")
		_server_is_ready = false
		pose_lost.emit()
		return
	
	print("[PoseDetectionBridge] Starting Python pose & camera server...")
	print("[PoseDetectionBridge]   Python: %s" % python_cmd)
	print("[PoseDetectionBridge]   Script: %s" % script_path)
	
	var args: PackedStringArray = [
		"-u",
		script_path,
		"--parent-pid",
		str(OS.get_process_id())
	]
	_python_pid = OS.create_process(python_cmd, args)
	if _python_pid <= 0:
		push_error("[PoseDetectionBridge] Failed to start Python server process.")
		_server_is_ready = false
		pose_lost.emit()
		return
	
	print("[PoseDetectionBridge] Python server started (PID: %d)" % _python_pid)
	
	# Begin health check polling after a short delay
	_health_check_attempts = 0
	get_tree().create_timer(2.0).timeout.connect(_poll_server_health)



func _resolve_server_script_path() -> String:
	# In-editor: use res:// path globalized
	var res_path := "res://UI/GolferCamera/mediapipe_server/pose_server.py"
	if FileAccess.file_exists(res_path):
		return ProjectSettings.globalize_path(res_path)
	
	# Exported: check next to executable
	var exe_dir := OS.get_executable_path().get_base_dir()
	var export_path := exe_dir.path_join("UI/GolferCamera/mediapipe_server/pose_server.py")
	if FileAccess.file_exists(export_path):
		return export_path
	
	return ""


func _find_python_executable() -> String:
	var candidates: Array[String] = ["python", "python3", "py"]
	
	for cmd in candidates:
		var output: Array = []
		var exit_code := OS.execute(cmd, ["--version"], output, true)
		if exit_code == 0:
			var version_str := "".join(output).strip_edges()
			if "Python 3" in version_str:
				print("[PoseDetectionBridge] Found: %s (%s)" % [cmd, version_str])
				return cmd
	
	return ""


func _poll_server_health() -> void:
	_health_check_attempts += 1
	if _health_check_attempts > MAX_HEALTH_RETRIES:
		push_error("[PoseDetectionBridge] Server failed to start after %d attempts." % MAX_HEALTH_RETRIES)
		_server_is_ready = false
		pose_lost.emit()
		return
	
	if _health_req != null:
		_health_req.queue_free()
	
	_health_req = HTTPRequest.new()
	_health_req.name = "HealthCheckRequest"
	_health_req.timeout = 2.0
	_health_req.request_completed.connect(_on_health_response)
	add_child(_health_req)
	_health_req.request(HEALTH_URL)


func _on_health_response(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if _health_req != null:
		_health_req.queue_free()
		_health_req = null
	
	if response_code == 200:
		_server_is_ready = true
		print("[PoseDetectionBridge] MediaPipe pose & camera server is READY (%s)." % SERVER_URL)
		server_ready.emit()
		fetch_desktop_cameras()
	else:
		print("[PoseDetectionBridge] Health check attempt %d/%d — server not ready yet..." % [_health_check_attempts, MAX_HEALTH_RETRIES])
		get_tree().create_timer(1.5).timeout.connect(_poll_server_health)


# ─── Desktop System Camera Controls ──────────────────────────────────────────

func fetch_desktop_cameras() -> void:
	if _is_android or not _server_is_ready:
		desktop_cameras_updated.emit([])
		return
	
	if _cam_scan_req != null:
		_cam_scan_req.queue_free()
	
	_cam_scan_req = HTTPRequest.new()
	_cam_scan_req.name = "CamScanRequest"
	_cam_scan_req.timeout = 8.0
	_cam_scan_req.request_completed.connect(_on_scan_cameras_response)
	add_child(_cam_scan_req)
	_cam_scan_req.request(CAMERAS_URL)


func _on_scan_cameras_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _cam_scan_req != null:
		_cam_scan_req.queue_free()
		_cam_scan_req = null
	
	if response_code == 200 and body.size() > 0:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data: Dictionary = json.data
			desktop_cameras = data.get("cameras", [])
			print("[PoseDetectionBridge] Detected %d desktop system cameras." % desktop_cameras.size())
			desktop_cameras_updated.emit(desktop_cameras)
			return
	
	desktop_cameras = []
	desktop_cameras_updated.emit([])


func select_desktop_camera(index: int) -> void:
	if _is_android or not _server_is_ready:
		return
	
	active_desktop_camera_index = index
	if index < 0:
		_desktop_polling_active = false
		_desktop_polling_in_flight = false
	
	if _cam_select_req == null:
		_cam_select_req = HTTPRequest.new()
		_cam_select_req.name = "CamSelectRequest"
		_cam_select_req.timeout = 4.0
		_cam_select_req.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
			print("[PoseDetectionBridge] Camera select completed. code=%d active_idx=%d" % [response_code, active_desktop_camera_index])
			if active_desktop_camera_index >= 0:
				_desktop_polling_active = true
				_poll_desktop_camera_frame()
		)
		add_child(_cam_select_req)
	
	print("[PoseDetectionBridge] Requesting select camera %d..." % index)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body_json := JSON.stringify({"index": index})
	var err := _cam_select_req.request(CAM_SELECT_URL, headers, HTTPClient.METHOD_POST, body_json)
	if err != OK:
		print("[PoseDetectionBridge] Error sending cam select request: ", err)
		if index >= 0:
			_desktop_polling_active = true
			_poll_desktop_camera_frame()



func pause_desktop_camera() -> void:
	_desktop_polling_active = false
	_desktop_polling_in_flight = false
	print("[PoseDetectionBridge] Desktop camera stream polling paused.")


func resume_desktop_camera() -> void:
	if _is_android or not _server_is_ready or active_desktop_camera_index < 0:
		return
	print("[PoseDetectionBridge] Resuming desktop camera stream polling (camera %d)..." % active_desktop_camera_index)
	_desktop_polling_active = true
	_desktop_polling_in_flight = false
	_poll_desktop_camera_frame()


func is_desktop_camera_active() -> bool:
	return _desktop_polling_active and active_desktop_camera_index >= 0


func stop_desktop_camera() -> void:
	_desktop_polling_active = false
	_desktop_polling_in_flight = false
	select_desktop_camera(-1)


func _poll_desktop_camera_frame() -> void:
	if not _desktop_polling_active or _desktop_polling_in_flight or not _server_is_ready:
		return
	
	_desktop_polling_in_flight = true
	
	if _cam_capture_req == null:
		_cam_capture_req = HTTPRequest.new()
		_cam_capture_req.name = "CamCaptureRequest"
		_cam_capture_req.timeout = 3.0
		_cam_capture_req.request_completed.connect(_on_cam_capture_response)
		add_child(_cam_capture_req)
	
	var err := _cam_capture_req.request(CAM_CAPTURE_URL)
	if err != OK:
		_desktop_polling_in_flight = false
		if _desktop_polling_active:
			get_tree().create_timer(FRAME_INTERVAL).timeout.connect(_poll_desktop_camera_frame)



func _on_cam_capture_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_desktop_polling_in_flight = false
	
	if response_code == 200 and body.size() > 0:
		var json = JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK:
			var data: Dictionary = json.data
			var b64_img: String = data.get("image_base64", "")
			var landmarks: Dictionary = data.get("landmarks", {})
			var detected: bool = data.get("detected", false)
			
			if not b64_img.is_empty():
				var bytes := Marshalls.base64_to_raw(b64_img)
				var img := Image.new()
				var err := img.load_jpg_from_buffer(bytes)
				if err == OK and not img.is_empty():
					var tex := ImageTexture.create_from_image(img)
					if detected:
						pose_detected.emit(landmarks)
					else:
						pose_lost.emit()
					desktop_frame_received.emit(img, tex, landmarks)
	
	if _desktop_polling_active:
		get_tree().create_timer(FRAME_INTERVAL).timeout.connect(_poll_desktop_camera_frame)


# ─── Public API ──────────────────────────────────────────────────────────────

## Send a camera frame for pose detection (Android / Viewport fallback).
func process_frame(img: Image) -> void:
	if img == null or img.is_empty() or not _server_is_ready:
		pose_lost.emit()
		return
	
	if _desktop_polling_active or is_android_camera_active():
		# When system camera is actively capturing, bypass manual frame processing
		return
	
	# Rate limit
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_req_time < FRAME_INTERVAL:
		return

	if _request_in_flight:
		return
	
	# Encode frame as JPEG
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGBA8)
	var jpg_bytes := img.save_jpg_to_buffer(0.7)
	if jpg_bytes.size() == 0:
		pose_lost.emit()
		return
	
	_last_req_time = now
	_request_in_flight = true
	
	if _is_android and _plugin != null:
		# Android: send bytes directly to native plugin
		_plugin.call("processFrame", jpg_bytes)
	elif _http_req != null:
		# Desktop: send via HTTP POST to Python server
		var headers: PackedStringArray = ["Content-Type: image/jpeg"]
		var err := _http_req.request_raw(SERVER_URL, headers, HTTPClient.METHOD_POST, jpg_bytes)
		if err != OK:
			_request_in_flight = false
			pose_lost.emit()


func _on_pose_http_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_request_in_flight = false
	if response_code == 200 and body.size() > 0:
		_parse_and_emit(body.get_string_from_utf8())
	else:
		pose_lost.emit()


## Analyze a single image on demand (e.g. during replay wireframe background generation).
## Non-blocking, yields across frames as needed, and returns the landmarks dictionary.
func detect_pose_for_image_async(img: Image) -> Dictionary:
	if img == null or img.is_empty():
		return {}
	
	# Duplicate and format image to JPEG
	var work_img: Image = img.duplicate()
	if work_img.is_compressed():
		work_img.decompress()
	if work_img.get_format() != Image.FORMAT_RGBA8 and work_img.get_format() != Image.FORMAT_RGB8:
		work_img.convert(Image.FORMAT_RGBA8)
	var jpg_bytes := work_img.save_jpg_to_buffer(0.7)
	if jpg_bytes.is_empty():
		return {}
	
	# Android native MediaPipe plugin path
	if _is_android and _plugin != null:
		if _plugin.has_method("detectPoseFromJpeg"):
			var json_str: String = _plugin.call("detectPoseFromJpeg", jpg_bytes)
			return parse_landmarks_json(json_str)
		elif _plugin.has_method("processFrame"):
			_plugin.call("processFrame", jpg_bytes)
			return await _wait_for_android_pose_result(0.6)
	
	# Desktop Python server path
	if _server_is_ready:
		var req := HTTPRequest.new()
		req.name = "FrameAnalysisHTTPRequest"
		req.timeout = 2.0
		add_child(req)
		var headers: PackedStringArray = ["Content-Type: image/jpeg"]
		var err := req.request_raw(SERVER_URL, headers, HTTPClient.METHOD_POST, jpg_bytes)
		if err != OK:
			req.queue_free()
			return {}
		
		var result_arr = await req.request_completed
		req.queue_free()
		
		var response_code: int = result_arr[1]
		var body: PackedByteArray = result_arr[3]
		if response_code == 200 and body.size() > 0:
			return parse_landmarks_json(body.get_string_from_utf8())
	
	return {}


func parse_landmarks_json(json_str: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(json_str) != OK or not (json.data is Dictionary):
		return {}
	var data: Dictionary = json.data
	if data.get("detected", false) == true:
		return data.get("landmarks", {})
	return {}


func _wait_for_android_pose_result(timeout_sec: float) -> Dictionary:
	var result: Dictionary = {}
	var completed: bool = false
	var cb_success = func(landmarks: Dictionary):
		result = landmarks
		completed = true
	var cb_lost = func():
		completed = true
	
	pose_detected.connect(cb_success, CONNECT_ONE_SHOT)
	pose_lost.connect(cb_lost, CONNECT_ONE_SHOT)
	
	var elapsed: float = 0.0
	while not completed and elapsed < timeout_sec:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	
	if not completed:
		if pose_detected.is_connected(cb_success):
			pose_detected.disconnect(cb_success)
		if pose_lost.is_connected(cb_lost):
			pose_lost.disconnect(cb_lost)
	
	return result


# ─── Internal ────────────────────────────────────────────────────────────────

func _parse_and_emit(json_str: String) -> void:
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return
	
	var data: Dictionary = json.data
	if data.get("detected", false) == true:
		var landmarks: Dictionary = data.get("landmarks", {})
		pose_detected.emit(landmarks)
	else:
		pose_lost.emit()


func _exit_tree() -> void:
	stop_android_camera()
	_kill_python_server()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop_android_camera()
		_kill_python_server()


func _kill_python_server() -> void:
	if _python_pid > 0:
		print("[PoseDetectionBridge] Stopping Python server (PID: %d)..." % _python_pid)
		OS.kill(_python_pid)
		_python_pid = -1
