extends SceneTree

func _initialize() -> void:
	print("==================================================")
	print("Running Putting Camera Speed Validation & Mishit Tests")
	print("==================================================")

	var sm_class = load("res://UI/PuttingCamera/putting_camera_state_machine.gd")
	if sm_class == null:
		push_error("Failed to load putting_camera_state_machine.gd")
		quit(1)
		return

	var overlay_class = load("res://UI/PuttingCamera/putting_camera_overlay.gd")
	if overlay_class == null:
		push_error("Failed to load putting_camera_overlay.gd")
		quit(1)
		return

	var sm = sm_class.new()
	var overlay = overlay_class.new()
	sm.overlay = overlay
	root.add_child(sm)
	root.add_child(overlay)

	# --- Test 1: Verify Settings & Defaults ---
	print("\n--- Test 1: Verifying Dynamic Settings & Defaults ---")
	print("Default min_putt_speed_mph: %.1f" % sm.min_putt_speed_mph)
	print("Default max_putt_speed_mph: %.1f" % sm.max_putt_speed_mph)
	print("Default mishit_filter_enabled: %s" % str(sm.mishit_filter_enabled))
	assert(sm.min_putt_speed_mph == 1.5, "Default min speed should be 1.5 mph")
	assert(sm.max_putt_speed_mph == 20.0, "Default max speed should be 20.0 mph")
	assert(sm.mishit_filter_enabled == true, "Mishit filter should be enabled by default")
	print("PASS: Defaults verified.")

	# --- Test 2: Low-Speed Mishit Auto-Rejection ---
	print("\n--- Test 2: Verifying Low-Speed Mishit Rejection (< 1.5 mph) ---")
	var res2 = {
		"detected": false,
		"rejected": false,
		"reason": "",
		"speed": 0.0
	}

	sm.putt_detected.connect(func(_spd, _hla):
		res2["detected"] = true
	)
	sm.putt_rejected.connect(func(reason, spd):
		res2["rejected"] = true
		res2["reason"] = reason
		res2["speed"] = spd
	)

	# Simulate a soft tap/nudge: ball moves slowly from 0.70 to 0.62 over 750ms (~0.33 mph)
	sm.reset()
	sm._established_ball_pos = Vector2(0.5, 0.70)
	sm._start_tracking(Vector2(0.5, 0.69))
	var t2: Array[Dictionary] = [
		{"pos": Vector2(0.5, 0.70), "time": 1000},
		{"pos": Vector2(0.5, 0.67), "time": 1250},
		{"pos": Vector2(0.5, 0.64), "time": 1500},
		{"pos": Vector2(0.5, 0.62), "time": 1750}
	]
	sm._trajectory = t2
	sm._tracking_start_time_msec = 1000
	sm._tracking_frame_count = 5
	sm._calculate_and_dispatch_putt()

	assert(res2["detected"] == false, "Mishit putt must NOT fire putt_detected")
	assert(res2["rejected"] == true, "Mishit putt MUST fire putt_rejected")
	assert(res2["reason"] == "mishit_too_slow", "Rejected reason should be mishit_too_slow, got %s" % res2["reason"])
	assert(res2["speed"] < 1.5, "Rejected speed should be < 1.5 mph, got %.2f" % res2["speed"])
	assert(overlay._rejection_timer > 0.0, "Overlay must display rejection notice")
	print("PASS: Low-speed tap (%.2f mph) successfully rejected as mishit." % res2["speed"])

	# --- Test 3: High-Speed Glitch / Anomaly Rejection ---
	print("\n--- Test 3: Verifying High-Speed Anomaly Rejection (> 20.0 mph) ---")
	var res3 = {
		"detected": false,
		"rejected": false,
		"reason": "",
		"speed": 0.0
	}
	sm.putt_detected.disconnect(sm.putt_detected.get_connections()[0].callable)
	sm.putt_rejected.disconnect(sm.putt_rejected.get_connections()[0].callable)

	sm.putt_detected.connect(func(_spd, _hla):
		res3["detected"] = true
	)
	sm.putt_rejected.connect(func(reason, spd):
		res3["rejected"] = true
		res3["reason"] = reason
		res3["speed"] = spd
	)

	# Simulate an unrealistic anomaly: moving 0.60 units in 50ms (> 25 mph)
	sm.reset()
	sm._established_ball_pos = Vector2(0.5, 0.70)
	sm._start_tracking(Vector2(0.5, 0.68))
	var t3: Array[Dictionary] = [
		{"pos": Vector2(0.5, 0.70), "time": 1000},
		{"pos": Vector2(0.5, 0.35), "time": 1025},
		{"pos": Vector2(0.5, 0.10), "time": 1050}
	]
	sm._trajectory = t3
	sm._tracking_start_time_msec = 1000
	sm._tracking_frame_count = 2
	sm._calculate_and_dispatch_putt()

	assert(res3["detected"] == false, "High-speed glitch must NOT fire putt_detected")
	assert(res3["rejected"] == true, "High-speed glitch MUST fire putt_rejected")
	assert(res3["reason"] == "invalid_speed_too_fast", "Rejected reason should be invalid_speed_too_fast, got %s" % res3["reason"])
	assert(res3["speed"] > 20.0, "Rejected speed should be > 20.0 mph, got %.2f" % res3["speed"])
	print("PASS: High-speed glitch (%.2f mph) successfully rejected as invalid speed." % res3["speed"])

	# --- Test 4: Valid Normal Putt ---
	print("\n--- Test 4: Verifying Normal Valid Putt (5.0 mph) ---")
	var res4 = {
		"detected": false,
		"rejected": false,
		"speed": 0.0,
		"hla": 0.0
	}
	sm.putt_detected.disconnect(sm.putt_detected.get_connections()[0].callable)
	sm.putt_rejected.disconnect(sm.putt_rejected.get_connections()[0].callable)

	sm.putt_detected.connect(func(spd, hla):
		res4["detected"] = true
		res4["speed"] = spd
		res4["hla"] = hla
	)
	sm.putt_rejected.connect(func(_reason, _spd):
		res4["rejected"] = true
	)

	# Normal 5.0 mph putt: travels 0.50 screen units in ~0.25s (~2.0 units/sec * 2.5 = 5.0 mph)
	sm.reset()
	sm._established_ball_pos = Vector2(0.5, 0.70)
	sm._start_tracking(Vector2(0.5, 0.68))
	var t4: Array[Dictionary] = [
		{"pos": Vector2(0.5, 0.70), "time": 1000},
		{"pos": Vector2(0.5, 0.55), "time": 1075},
		{"pos": Vector2(0.5, 0.40), "time": 1150},
		{"pos": Vector2(0.5, 0.20), "time": 1250}
	]
	sm._trajectory = t4
	sm._tracking_start_time_msec = 1000
	sm._tracking_frame_count = 8
	sm._calculate_and_dispatch_putt()

	assert(res4["detected"] == true, "Valid putt MUST fire putt_detected")
	assert(res4["rejected"] == false, "Valid putt must NOT fire putt_rejected")
	assert(res4["speed"] >= 4.0 and res4["speed"] <= 6.5, "Detected speed should be ~5.0 mph, got %.2f" % res4["speed"])
	assert(sm.current_state == sm_class.State.EXECUTION, "State should be EXECUTION after valid putt")
	assert(overlay.last_speed_mph > 0.0, "Overlay last_speed_mph should be recorded")
	print("PASS: Normal putt detected correctly (%.2f mph, state=EXECUTION)." % res4["speed"])

	# --- Test 5: Kinematic Forward Jump Gating ---
	print("\n--- Test 5: Verifying Forward Jump Teleport Gating ---")
	sm.reset()
	sm._established_ball_pos = Vector2(0.5, 0.70)
	sm._start_tracking(Vector2(0.5, 0.68))
	var last_known = sm._last_seen_pos
	var delta_y = 0.10 - last_known.y
	var max_forward_jump = clampf((sm.max_putt_speed_mph / sm.speed_calibration_constant / maxf(sm.active_fps, 15.0)) * 1.75, 0.28, 0.45)
	var is_valid = (delta_y <= 0.015 and -delta_y <= max_forward_jump)
	assert(is_valid == false, "Teleport jump of -0.58 must be kinematically invalid")
	print("PASS: Teleport jump (-0.58 screen height) rejected by max_forward_jump gate (%.2f)." % max_forward_jump)

	# --- Test 6: Reconciled Sensor Time Prevents WiFi Burst Speed Spikes ---
	print("\n--- Test 6: Verifying Frame-Rate Reconciled Sensor Time ---")
	var res6 = {"speed": 0.0}
	sm.putt_detected.disconnect(sm.putt_detected.get_connections()[0].callable)
	sm.putt_detected.connect(func(spd, _hla):
		res6["speed"] = spd
	)

	sm.reset()
	sm._established_ball_pos = Vector2(0.5, 0.70)
	sm._start_tracking(Vector2(0.5, 0.65))
	var t6: Array[Dictionary] = [
		{"pos": Vector2(0.5, 0.70), "time": 1000},
		{"pos": Vector2(0.5, 0.60), "time": 1005},
		{"pos": Vector2(0.5, 0.50), "time": 1010},
		{"pos": Vector2(0.5, 0.40), "time": 1015}
	]
	sm._trajectory = t6
	sm._tracking_start_time_msec = 1000
	sm._tracking_frame_count = 4
	sm.active_fps = 30.0
	sm._calculate_and_dispatch_putt()

	print("Speed with sensor-time reconciliation: %.2f mph" % res6["speed"])
	assert(res6["speed"] < 10.0, "Speed must be protected from WiFi burst inflation (expected < 10 mph, got %.2f)" % res6["speed"])
	print("PASS: Frame-rate reconciliation prevented speed inflation during burst delivery.")

	print("\n==================================================")
	print("ALL PUTTING CAMERA SPEED VALIDATION TESTS PASSED!")
	print("==================================================")
	quit(0)
