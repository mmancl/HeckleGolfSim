extends SceneTree

func _initialize() -> void:
	print("==================================================")
	print("Running Camera Backend & Pose Detection Bridge Tests")
	print("==================================================")

	var bridge_class = load("res://UI/GolferCamera/pose_detection_bridge.gd")
	assert(bridge_class != null, "PoseDetectionBridge class must load successfully")

	var bridge = bridge_class.new()
	bridge.name = "PoseDetectionBridge"
	root.add_child(bridge)

	# --- Test 1: Desktop Script Resolution & Fallback Extraction ---
	print("\n--- Test 1: Desktop Server Script Resolution ---")
	var script_path = bridge._resolve_server_script_path()
	print("Resolved pose_server.py path: %s" % script_path)
	assert(not script_path.is_empty(), "pose_server.py path must not be empty")
	assert(FileAccess.file_exists(script_path), "Resolved pose_server.py path must exist on disk: %s" % script_path)
	print("PASS: pose_server.py successfully resolved to valid filesystem path.")

	# --- Test 2: Python Executable Detection ---
	print("\n--- Test 2: Python Executable Detection ---")
	var python_cmd = bridge._find_python_executable()
	print("Detected Python executable: '%s'" % python_cmd)
	# python_cmd may be empty on environments without Python 3, but should not crash
	assert(python_cmd is String, "Python cmd must be a String")
	print("PASS: _find_python_executable completed safely.")

	# --- Test 3: Android Camera Emulation ---
	print("\n--- Test 3: Android Camera Emulation ---")
	bridge._is_android = true
	bridge.desktop_cameras = []
	bridge.fetch_desktop_cameras()
	assert(bridge.desktop_cameras.size() >= 2, "Android must expose default cameras (Back/Front)")
	bridge.select_desktop_camera(0)
	assert(bridge.active_desktop_camera_index == 0, "Active camera index should be 0")
	bridge.select_desktop_camera(1)
	assert(bridge.active_desktop_camera_index == 1, "Active camera index should be 1")
	bridge.select_desktop_camera(-1)
	assert(bridge.active_desktop_camera_index == -1, "Active camera index should be -1 after stop")
	print("PASS: Android camera indexing and selection functions correctly.")

	bridge.queue_free()

	print("\n==================================================")
	print("ALL CAMERA BACKEND TESTS PASSED!")
	print("==================================================")
	quit(0)
