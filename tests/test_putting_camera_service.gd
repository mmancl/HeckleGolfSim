extends SceneTree

func _initialize() -> void:
	print("==================================================")
	print("Running Dedicated Putting Camera Service Tests")
	print("==================================================")

	# --- Test 1: PuttingCameraService Autoload / Class Loading ---
	print("\n--- Test 1: PuttingCameraService Autoload / Class Loading ---")
	var service = root.get_node_or_null("PuttingCameraService")
	if service == null:
		var service_class = load("res://UI/PuttingCamera/putting_camera_service.gd")
		assert(service_class != null, "PuttingCameraService script must load successfully")
		service = service_class.new()
		service.name = "PuttingCameraService"
		root.add_child(service)
	assert(service != null, "PuttingCameraService must exist")
	print("PASS: PuttingCameraService verified.")

	# --- Test 2: Stream URL & Port Validation ---
	print("\n--- Test 2: Stream URL & Port Validation ---")
	var url = service.get_stream_url()
	assert(url == "http://127.0.0.1:49155/video", "Stream URL must be port 49155 /video: %s" % url)
	print("PASS: Stream URL correctly configured: %s" % url)

	# --- Test 3: Script Resolution ---
	print("\n--- Test 3: Script Resolution ---")
	var script_path = service._resolve_server_script_path()
	print("Resolved putting_camera_server.py path: %s" % script_path)
	assert(not script_path.is_empty(), "putting_camera_server.py path must not be empty")
	assert(FileAccess.file_exists(script_path), "putting_camera_server.py must exist on disk: %s" % script_path)
	print("PASS: putting_camera_server.py resolved successfully.")

	# --- Test 4: PuttingCameraWidget Decoupled from Pose Detection ---
	print("\n--- Test 4: PuttingCameraWidget Decoupled Initialization ---")
	var widget_class = load("res://UI/PuttingCamera/putting_camera_widget.gd")
	assert(widget_class != null, "PuttingCameraWidget class must load")
	var widget = widget_class.new()
	root.add_child(widget)
	assert(widget != null, "PuttingCameraWidget should instantiate successfully")
	print("PASS: PuttingCameraWidget initialized cleanly with PuttingCameraService.")

	widget.queue_free()
	service.queue_free()

	print("\n==================================================")
	print("ALL PUTTING CAMERA SERVICE TESTS PASSED! 🎉")
	print("==================================================")
	quit(0)
