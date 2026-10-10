extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Launch Monitor Auto-Detect & Switching Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	var lm = root.get_node_or_null("LaunchMonitorManager")
	assert(lm != null, "LaunchMonitorManager autoload must exist in scene tree")

	# Save original settings to restore at test end
	var original_settings = lm.settings.duplicate()

	print("\n--- Test 1: Device Name Classification ---")
	assert(not lm.is_garmin_device_name(""), "Empty name should NOT be classified as Garmin")
	assert(not lm.is_garmin_device_name("   "), "Whitespace name should NOT be classified as Garmin")
	assert(not lm.is_square_device_name(""), "Empty name should NOT be classified as Square")
	assert(not lm.is_square_device_name("   "), "Whitespace name should NOT be classified as Square")
	assert(lm.is_garmin_device_name("Garmin Approach R10"), "Garmin Approach R10 must match Garmin")
	assert(lm.is_garmin_device_name("Approach R10 [1234]"), "Approach R10 must match Garmin")
	assert(lm.is_square_device_name("Square Golf"), "Square Golf (with space) must match Square")
	assert(lm.is_square_device_name("SquareGolf_4321"), "SquareGolf_4321 must match Square")
	assert(lm.is_square_device_name("SGO300A"), "SGO300A must match Square")
	assert(lm.is_square_device_name("SGO-300"), "SGO-300 must match Square")
	assert(lm.is_square_device_name("sgo_mini"), "sgo_mini must match Square")
	assert(not lm.is_garmin_device_name("Square Golf"), "Square Golf must not match Garmin")
	assert(not lm.is_garmin_device_name("SGO300A"), "SGO300A must not match Garmin")
	assert(not lm.is_square_device_name("Approach R10"), "Approach R10 must not match Square")
	print("  PASS: Device name classification properly separates Square Golf (including SGO models) and Garmin.")

	print("\n--- Test 2: Unknown Device Ignored by Garmin Discovery ---")
	lm.devices.clear()
	lm._on_garmin_device_discovered("UNKNOWN_DEVICE", "", -55)
	assert(not lm.devices.has("UNKNOWN_DEVICE"), "Garmin discovery must ignore devices with empty/unknown names")
	lm._on_garmin_device_discovered("SQUARE_DEVICE", "Square Golf", -60)
	assert(not lm.devices.has("SQUARE_DEVICE"), "Garmin discovery must ignore Square Golf device name")
	print("  PASS: Garmin discovery rejects empty and non-Garmin names.")

	print("\n--- Test 3: Auto-Detect Prioritizes Live Square Golf over Offline Garmin ---")
	# Simulate previous connection with Garmin
	lm.settings["device_id"] = "GARMIN_SAVED_123"
	lm.settings["device_name"] = "Garmin Approach R10"
	lm.settings["device_type"] = "auto"
	lm.devices.clear()

	# Seed offline Garmin (as startup or modal does)
	lm.devices["GARMIN_SAVED_123"] = {
		"name": "Garmin Approach R10",
		"rssi": 0,
		"type": "garmin",
		"is_discovered": false
	}

	# Now Square Golf is discovered live over Bluetooth
	lm._on_square_device_discovered("SQUARE_LIVE_456", "Square Golf", -62)
	assert(lm.devices.has("SQUARE_LIVE_456"), "Square device must be added to devices")
	assert(lm.devices["SQUARE_LIVE_456"]["type"] == "square", "Square device type must be square")
	assert(lm.devices["SQUARE_LIVE_456"]["is_discovered"] == true, "Square device must be marked live")

	# Detection on Square ID must return square even when previous settings were Garmin
	var detected = lm.detect_device_type("SQUARE_LIVE_456")
	assert(detected == "square", "detect_device_type must return square for discovered Square device, got %s" % detected)
	print("  PASS: Live Square Golf device detected as square despite saved Garmin settings.")

	print("\n--- Test 4: Modal Selects Live Square Golf and Displays Correct Status ---")
	var modal_scene = load("res://UI/LaunchMonitorConnectModal/launch_monitor_connect_modal.tscn")
	assert(modal_scene != null, "Modal scene must exist")
	var modal: LaunchMonitorConnectModal = modal_scene.instantiate()
	root.add_child(modal)
	await process_frame
	await process_frame

	# Simulate Square Golf discovered event in modal
	modal._on_device_discovered("SQUARE_LIVE_456", "Square Golf", -62)
	await process_frame

	var selected_meta = modal.device_option.get_item_metadata(modal.device_option.selected)
	assert(str(selected_meta) == "SQUARE_LIVE_456", "Modal device dropdown must select live Square Golf, got %s" % str(selected_meta))
	assert(modal.status_label.text.contains("Square Golf"), "Status label must show Square Golf, got: %s" % modal.status_label.text)
	assert(not modal.status_label.text.contains("Garmin"), "Status label must NOT show Garmin when Square Golf is found, got: %s" % modal.status_label.text)
	print("  PASS: Modal selects Square Golf and updates status label correctly.")

	modal.queue_free()
	await process_frame

	print("\n--- Test 5: connect_to_device Transitions to Square Driver Cleanly ---")
	lm.connect_to_device("SQUARE_LIVE_456", true)
	assert(lm._active_driver == "square", "Active driver must be square, got %s" % lm._active_driver)
	assert(lm.settings["device_id"] == "SQUARE_LIVE_456", "Device id must update to Square id")
	assert(lm.settings["device_name"] == "Square Golf", "Device name must update to Square Golf, got %s" % lm.settings["device_name"])
	print("  PASS: connect_to_device successfully sets active driver and device_name to Square Golf.")

	# Restore original settings
	lm.settings = original_settings
	lm._save_settings()

	print("\n=======================================================")
	print("  ALL AUTO-DETECT TESTS PASSED SUCCESSFULLY!          ")
	print("=======================================================\n")
	quit(0)
