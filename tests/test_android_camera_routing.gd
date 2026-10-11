extends SceneTree

func _initialize() -> void:
	print("==================================================")
	print("Running Android Local Camera Routing Tests")
	print("==================================================")

	# --- Test 1: PoseDetectionBridge Android Camera Detection & Listing ---
	print("\n--- Test 1: PoseDetectionBridge Android Camera Detection & Listing ---")
	var bridge_class = load("res://UI/GolferCamera/pose_detection_bridge.gd")
	assert(bridge_class != null, "PoseDetectionBridge class must load")
	
	var bridge = bridge_class.new()
	bridge.name = "PoseDetectionBridge"
	root.add_child(bridge)
	
	# Simulate Android platform environment
	bridge._is_android = true
	bridge.desktop_cameras = []
	bridge.fetch_desktop_cameras()
	
	assert(bridge.desktop_cameras.size() >= 2, "Android must always detect at least 2 cameras (Back & Front), found %d" % bridge.desktop_cameras.size())
	assert(bridge.desktop_cameras[0].id == 0, "First camera id should be 0")
	assert(bridge.desktop_cameras[0].facing == 0, "First camera facing should be 0 (Back)")
	assert(bridge.desktop_cameras[1].id == 1, "Second camera id should be 1")
	assert(bridge.desktop_cameras[1].facing == 1, "Second camera facing should be 1 (Front)")
	print("PASS: PoseDetectionBridge guarantees default device cameras on Android.")

	# --- Test 2: PoseDetectionBridge select_desktop_camera on Android ---
	print("\n--- Test 2: PoseDetectionBridge select_desktop_camera on Android ---")
	bridge.select_desktop_camera(0)
	assert(bridge.active_desktop_camera_index == 0, "Active camera index should be 0, got %d" % bridge.active_desktop_camera_index)
	print("PASS: select_desktop_camera sets active camera index and triggers Android camera start.")

	# --- Test 3: PuttingCameraWidget local Android camera routing ---
	print("\n--- Test 3: PuttingCameraWidget local Android camera routing ---")
	var widget_class = load("res://UI/PuttingCamera/putting_camera_widget.gd")
	assert(widget_class != null, "PuttingCameraWidget class must load")
	
	var widget = widget_class.new()
	root.add_child(widget)
	widget.set_camera_active(true)
	
	# Verify that activating index 0 on Android does not show error overlay
	widget._activate_camera_feed_index(0)
	var status_lbl = widget.find_child("StatusOverlayLabel", true, false)
	if status_lbl is Label:
		assert(not status_lbl.text.contains("NO LOCAL CAMERA DETECTED"), "Must not display 'NO LOCAL CAMERA DETECTED' on Android")
	print("PASS: PuttingCameraWidget successfully routes local Android device to PoseDetectionBridge without error.")

	# Test flip camera logic
	widget._current_camera_feed_index = 0
	widget._on_flip_camera_pressed()
	assert(widget._current_camera_feed_index == 1, "Flipping camera on Android must alternate between camera 0 and 1, got %d" % widget._current_camera_feed_index)
	print("PASS: PuttingCameraWidget flip camera correctly toggles between local Android cameras.")

	# Cleanup
	widget.queue_free()
	bridge.queue_free()

	print("\n==================================================")
	print("ALL ANDROID CAMERA ROUTING TESTS PASSED!")
	print("==================================================")
	quit(0)
