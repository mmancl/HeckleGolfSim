extends Node

## Dedicated Putting Camera Service
## Manages the lightweight local putting camera MJPEG streaming server (putting_camera_server.py)
## on desktop, providing high-framerate 30 FPS video streaming directly to MJPEGStreamReader
## completely decoupled from GolferCamera and pose_server.py.

signal server_ready()
signal cameras_updated(cameras: Array)
signal camera_selected(index: int)

const SERVER_PORT: int = 49155
const SERVER_URL: String = "http://127.0.0.1:49155"
const HEALTH_URL: String = "http://127.0.0.1:49155/health"
const CAMERAS_URL: String = "http://127.0.0.1:49155/cameras"
const CAM_SELECT_URL: String = "http://127.0.0.1:49155/camera/select"
const STREAM_URL: String = "http://127.0.0.1:49155/video"
const MAX_HEALTH_RETRIES: int = 12

var desktop_cameras: Array = []
var active_camera_index: int = -1
var is_server_ready: bool = false
var _python_pid: int = -1

var _health_req: HTTPRequest = null
var _cam_list_req: HTTPRequest = null
var _cam_select_req: HTTPRequest = null
var _health_check_attempts: int = 0
var _is_android: bool = false


func _ready() -> void:
	_is_android = OS.get_name() == "Android" or OS.has_feature("android")
	if DisplayServer.get_name() == "headless" or _is_android or OS.has_feature("ios"):
		return
	ensure_server()


func _exit_tree() -> void:
	stop_camera()
	_shutdown_server()


func get_stream_url() -> String:
	return STREAM_URL


func ensure_server() -> void:
	if _is_android or OS.has_feature("ios"):
		return
	if is_server_ready:
		return
	_check_existing_server()


func fetch_cameras() -> void:
	if _is_android:
		desktop_cameras = []
		var count = 2
		desktop_cameras.append({"index": 0, "name": "Back Camera (Device)", "facing": 0})
		desktop_cameras.append({"index": 1, "name": "Front Camera (Device)", "facing": 1})
		cameras_updated.emit(desktop_cameras)
		return

	if not is_server_ready:
		ensure_server()
		# Retry in 0.8s
		if is_inside_tree():
			get_tree().create_timer(0.8).timeout.connect(func():
				if is_server_ready:
					fetch_cameras()
			)
		return

	if _cam_list_req == null:
		_cam_list_req = HTTPRequest.new()
		_cam_list_req.name = "PuttingCamListReq"
		_cam_list_req.timeout = 3.0
		_cam_list_req.request_completed.connect(_on_cam_list_response)
		add_child(_cam_list_req)
	elif _cam_list_req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_cam_list_req.cancel_request()

	_cam_list_req.request(CAMERAS_URL)


func _on_cam_list_response(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if response_code == 200 and body.size() > 0:
		var json := JSON.new()
		if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
			desktop_cameras = json.data.get("cameras", [])
			print("[PuttingCameraService] Detected %d putting system cameras." % desktop_cameras.size())
			cameras_updated.emit(desktop_cameras)
			return

	desktop_cameras = []
	cameras_updated.emit([])


func select_camera(index: int) -> void:
	active_camera_index = index
	if _is_android:
		camera_selected.emit(index)
		return

	if not is_server_ready:
		ensure_server()
		if is_inside_tree():
			get_tree().create_timer(0.8).timeout.connect(func():
				if is_server_ready:
					select_camera(index)
			)
		return

	if _cam_select_req == null:
		_cam_select_req = HTTPRequest.new()
		_cam_select_req.name = "PuttingCamSelectReq"
		_cam_select_req.timeout = 4.0
		_cam_select_req.request_completed.connect(func(_res: int, code: int, _hdr: PackedStringArray, _body: PackedByteArray):
			print("[PuttingCameraService] Camera select response code=%d, active_idx=%d" % [code, active_camera_index])
			camera_selected.emit(active_camera_index)
		)
		add_child(_cam_select_req)
	elif _cam_select_req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_cam_select_req.cancel_request()

	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body_json := JSON.stringify({"index": index})
	_cam_select_req.request(CAM_SELECT_URL, headers, HTTPClient.METHOD_POST, body_json)


func stop_camera() -> void:
	active_camera_index = -1
	if not _is_android and is_server_ready:
		select_camera(-1)


# ─── Server Process Lifecycle ────────────────────────────────────────────────
func _check_existing_server() -> void:
	if _health_req != null:
		_health_req.queue_free()
	_health_req = HTTPRequest.new()
	_health_req.name = "PuttingInitialHealthCheck"
	_health_req.timeout = 0.8
	_health_req.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if _health_req != null:
			_health_req.queue_free()
			_health_req = null
		if response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				var pid_val = json.data.get("pid", -1)
				if pid_val is int and pid_val > 0:
					_python_pid = pid_val
			print("[PuttingCameraService] Reusing existing putting camera server (PID: %d)." % _python_pid)
			is_server_ready = true
			server_ready.emit()
			fetch_cameras()
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
		push_error("[PuttingCameraService] Could not find putting_camera_server.py")
		return

	var python_cmd := _find_python_executable()
	if python_cmd.is_empty():
		push_error("[PuttingCameraService] Python 3 not found. Install Python & OpenCV to enable local putting webcam.")
		return

	print("[PuttingCameraService] Starting Putting Camera MJPEG server...")
	print("[PuttingCameraService]   Python: %s" % python_cmd)
	print("[PuttingCameraService]   Script: %s" % script_path)

	var args: PackedStringArray = [
		"-u",
		script_path,
		"--port",
		str(SERVER_PORT),
		"--parent-pid",
		str(OS.get_process_id())
	]
	_python_pid = OS.create_process(python_cmd, args)
	if _python_pid <= 0:
		push_error("[PuttingCameraService] Failed to start putting_camera_server.py process.")
		return

	_health_check_attempts = 0
	if is_inside_tree():
		get_tree().create_timer(0.6).timeout.connect(_poll_server_health)


func _poll_server_health() -> void:
	_health_check_attempts += 1
	if _health_check_attempts > MAX_HEALTH_RETRIES:
		push_error("[PuttingCameraService] Server failed to respond after %d attempts." % MAX_HEALTH_RETRIES)
		return

	if _health_req != null:
		_health_req.queue_free()

	_health_req = HTTPRequest.new()
	_health_req.name = "PuttingHealthCheckRequest"
	_health_req.timeout = 1.5
	_health_req.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if _health_req != null:
			_health_req.queue_free()
			_health_req = null
		if response_code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				var pid_val = json.data.get("pid", -1)
				if pid_val is int and pid_val > 0:
					_python_pid = pid_val
			print("[PuttingCameraService] Putting camera server is ready on port %d (PID: %d)." % [SERVER_PORT, _python_pid])
			is_server_ready = true
			server_ready.emit()
			fetch_cameras()
		else:
			if is_inside_tree():
				get_tree().create_timer(0.5).timeout.connect(_poll_server_health)
	)
	add_child(_health_req)
	_health_req.request(HEALTH_URL)


func _shutdown_server() -> void:
	if is_server_ready:
		var shutdown_req := HTTPRequest.new()
		shutdown_req.timeout = 1.0
		add_child(shutdown_req)
		shutdown_req.request(SERVER_URL + "/shutdown")
	if _python_pid > 0 and OS.is_process_running(_python_pid):
		OS.kill(_python_pid)
		_python_pid = -1


func _resolve_server_script_path() -> String:
	var exe_dir := OS.get_executable_path().get_base_dir()

	# 1. Next to binary
	var direct_export := exe_dir.path_join("putting_camera_server.py")
	if FileAccess.file_exists(direct_export):
		return direct_export

	# 2. In-editor: res://
	var res_path := "res://UI/PuttingCamera/putting_camera_server.py"
	if OS.has_feature("editor") and FileAccess.file_exists(res_path):
		var glob := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(glob):
			return glob

	# 3. Exported fallback: extract from res:// into user://
	var user_dir := "user://putting_camera_server"
	var user_script := user_dir.path_join("putting_camera_server.py")
	if FileAccess.file_exists(res_path):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir))
		var script_content := FileAccess.get_file_as_string(res_path)
		if not script_content.is_empty():
			var f := FileAccess.open(user_script, FileAccess.WRITE)
			if f != null:
				f.store_string(script_content)
				f.close()
				print("[PuttingCameraService] Extracted putting_camera_server.py to: %s" % ProjectSettings.globalize_path(user_script))

	if FileAccess.file_exists(user_script):
		return ProjectSettings.globalize_path(user_script)

	var glob_res := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(glob_res):
		return glob_res

	return ""


func _find_python_executable() -> String:
	var candidates: Array[String] = ["python", "python3", "py"]

	if OS.get_name() == "Windows":
		var local_app_data := OS.get_environment("LOCALAPPDATA")
		if not local_app_data.is_empty():
			var py_programs := local_app_data.path_join("Programs/Python")
			var dir := DirAccess.open(py_programs)
			if dir != null:
				dir.list_dir_begin()
				var fn := dir.get_next()
				while not fn.is_empty():
					if dir.current_is_dir() and fn.to_lower().begins_with("python3"):
						var py_path := py_programs.path_join(fn).path_join("python.exe")
						if FileAccess.file_exists(py_path):
							candidates.append(py_path)
					fn = dir.get_next()
		var program_files := OS.get_environment("ProgramFiles")
		if not program_files.is_empty():
			for py_ver in ["Python313", "Python312", "Python311", "Python310"]:
				var p := program_files.path_join(py_ver).path_join("python.exe")
				if FileAccess.file_exists(p):
					candidates.append(p)

	for cmd in candidates:
		var output: Array = []
		var exit_code := OS.execute(cmd, ["--version"], output, true)
		if exit_code == 0:
			var version_str := "".join(output).strip_edges()
			if "Python 3" in version_str:
				return cmd

	return ""
