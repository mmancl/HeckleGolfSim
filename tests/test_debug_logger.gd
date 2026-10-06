extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Debug Logger Unit & Integration Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true

	var test_log_path := "user://test_debug_output.log"
	var global_test_path := ProjectSettings.globalize_path(test_log_path)

	# Clean up any leftover test file
	if FileAccess.file_exists(test_log_path):
		DirAccess.remove_absolute(global_test_path)

	# 1. Verify GlobalSettings integration
	print("\n--- Test 1: GlobalSettings & RangeSettings Integration ---")
	var gs = root.get_node_or_null("GlobalSettings")
	assert(gs != null, "GlobalSettings autoload must be available")
	assert(gs.range_settings != null, "RangeSettings must be initialized")
	assert(gs.range_settings.settings.has("debug_logging_enabled"), "debug_logging_enabled setting must exist")
	assert(gs.range_settings.settings.has("debug_log_path"), "debug_log_path setting must exist")
	print("  PASS: debug_logging_enabled and debug_log_path registered in settings.")

	# 2. Verify DebugLogger autoload existence
	print("\n--- Test 2: DebugLogger Autoload Existence & State ---")
	var dl = root.get_node_or_null("DebugLogger")
	assert(dl != null, "DebugLogger autoload must be present at /root/DebugLogger")
	print("  PASS: DebugLogger autoload found.")

	# 3. Configure and enable debug logging to test path (and verify pre-existing log wipe)
	print("\n--- Test 3: Starting Debug Logger Session & Verifying Startup Wipe ---")
	var legacy_file := FileAccess.open(test_log_path, FileAccess.WRITE)
	legacy_file.store_line("LEGACY_GARBAGE_LOG_DATA_FROM_PREVIOUS_APP_RUN")
	legacy_file.close()
	assert(FileAccess.file_exists(test_log_path), "Pre-existing log file should exist before test start")

	gs.range_settings.debug_log_path.set_value(test_log_path)
	gs.range_settings.debug_logging_enabled.set_value(true)
	dl.start_logging(test_log_path)

	assert(dl.is_logging_active() == true, "DebugLogger must be active after start_logging")
	print("  PASS: DebugLogger active. Output path: %s" % dl.get_effective_log_path())

	# 4. Write Bluetooth, Shot, and Error telemetry
	print("\n--- Test 4: Writing Telemetry (Bluetooth, Shot, Errors) ---")
	dl.log_bluetooth("CBCentralManager state updated: 5 (5=PoweredOn)")
	dl.log_bluetooth("Discovered BLE peripheral: ID='E4:5F:01:23:45:67', Name='squaregolf_7890', RSSI=-58 dBm")
	dl.log_bluetooth("Connecting to peripheral E4:5F:01:23:45:67...")
	dl.log_bluetooth("Central connected to peripheral. Discovering services...")
	dl.log_bluetooth("Connected and GATT characteristics ready!")

	var test_shot = {
		"Speed": 105.4,
		"BallSpeed": 105.4,
		"ClubSpeed": 72.1,
		"VLA": 15.3,
		"HLA": -0.8,
		"TotalSpin": 2840.0,
		"BackSpin": 2800.0,
		"SideSpin": 150.0,
		"SpinAxis": 3.1,
		"CarryDistance": 215.4,
		"Offline": -3.2,
		"Club": "7I"
	}
	dl.log_shot(test_shot)

	dl.log_error("Simulated transient connection timeout during service discovery.")
	dl.log_info("Simulator round in progress.")

	# Flush and close file for verification
	dl.stop_logging()
	assert(dl.is_logging_active() == false, "DebugLogger must be inactive after stop_logging")
	print("  PASS: DebugLogger session stopped and flushed to disk.")

	# 5. Read and inspect file contents
	print("\n--- Test 5: Validating File Contents, Version, System Specs, File Sizes ---")
	assert(FileAccess.file_exists(test_log_path), "Log file must exist on disk")

	var f := FileAccess.open(test_log_path, FileAccess.READ)
	assert(f != null, "Log file must be readable")
	var content := f.get_as_text()
	f.close()

	print("  Log file size: %d bytes" % content.length())
	assert(!content.contains("LEGACY_GARBAGE_LOG_DATA_FROM_PREVIOUS_APP_RUN"), "Pre-existing log content must be wiped clean on startup")
	print("  PASS: Pre-existing log content wiped clean on session start.")

	# Verify App Version at top
	var expected_version = str(ProjectSettings.get_setting("application/config/version"))
	assert(content.contains("App Version:"), "Log file must have 'App Version:' header")
	assert(content.contains(expected_version), "Log file must contain current version '%s'" % expected_version)
	print("  PASS: App Version '%s' verified at top of log." % expected_version)

	# Verify System & OS specs
	assert(content.contains("SYSTEM & ENVIRONMENT SPECS:"), "Log must contain system specs header")
	assert(content.contains("OS Platform:"), "Log must contain OS Platform")
	assert(content.contains("Architecture:"), "Log must contain Architecture")
	assert(content.contains("Processor (CPU):"), "Log must contain CPU details")
	assert(content.contains("Video Adapter (GPU):"), "Log must contain GPU details")
	print("  PASS: System & Environment specifications verified.")

	# Verify Launch Monitor configuration snapshot
	assert(content.contains("LAUNCH MONITOR CONFIGURATION SNAPSHOT:"), "Log must contain LM snapshot")
	print("  PASS: Launch monitor settings snapshot verified.")

	# Verify Application Integrity and File Analysis
	assert(content.contains("APPLICATION INTEGRITY & FILE SIZE ANALYSIS:"), "Log must contain file analysis")
	assert(content.contains("project.godot"), "Log must contain project.godot analysis")
	assert(content.contains("launch_monitor_manager.gd"), "Log must contain launch_monitor_manager.gd analysis")
	assert(content.contains("AppleBluetoothGattClient.cs"), "Log must contain AppleBluetoothGattClient.cs analysis")
	assert(content.contains("bytes"), "Log must list file sizes in bytes")
	print("  PASS: Application integrity & file size analysis verified.")

	# Verify Bluetooth telemetry entries
	assert(content.contains("[BLE] CBCentralManager state updated: 5"), "Log must contain CoreBluetooth state log")
	assert(content.contains("[BLE] Discovered BLE peripheral: ID='E4:5F:01:23:45:67'"), "Log must contain discovered peripheral")
	assert(content.contains("[BLE] Connected and GATT characteristics ready!"), "Log must contain GATT ready log")
	print("  PASS: Bluetooth connection telemetry verified.")

	# Verify Shot details
	assert(content.contains("[SHOT]"), "Log must contain [SHOT] tag")
	assert(content.contains("BallSpeed: 105.4 mph"), "Log must contain formatted BallSpeed")
	assert(content.contains("ClubSpeed: 72.1 mph"), "Log must contain formatted ClubSpeed")
	assert(content.contains("VLA (Launch Angle): 15.3 deg"), "Log must contain formatted VLA")
	assert(content.contains("TotalSpin: 2840") and content.contains("rpm"), "Log must contain formatted TotalSpin")
	print("  PASS: Shot details and metrics verified.")

	# Verify Error logging
	assert(content.contains("[ERROR] Simulated transient connection timeout"), "Log must contain error log")
	print("  PASS: Error logging verified.")

	# Clean up test output
	DirAccess.remove_absolute(global_test_path)
	gs.range_settings.debug_logging_enabled.set_value(false)
	gs.range_settings.debug_log_path.set_value("user://debug.log")

	print("\n=== ALL DEBUG LOGGER TESTS PASSED SUCCESSFULLY! ===")
	quit(0)
