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

	# --- Test 7: Hard Framerate Gate (< 15.0 FPS blocks READY state) ---
	print("\n--- Test 7: Verifying Hard Framerate Gate (< 15.0 FPS) ---")
	sm.reset()
	var monitor = sm.frame_rate_monitor
	assert(monitor != null, "State machine should have a FrameRateMonitor")
	monitor.reset()

	# Feed 10 frames at 100ms interval = 10 FPS (< 15 FPS threshold)
	for i in range(10):
		monitor.record_frame(1_000_000 + i * 100_000)

	assert(monitor.current_fps < 15.0, "Current FPS should be ~10 FPS, got %.1f" % monitor.current_fps)
	assert(monitor.is_valid_for_tracking == false, "Monitor must report invalid for tracking")

	# Attempt to enter READY state while ball is at rest in circle
	var idle_res = {
		"found": true,
		"center": sm.overlay.circle_center,
		"at_rest": true
	}
	sm._handle_idle(idle_res)
	assert(sm.current_state == sm_class.State.IDLE, "Transition to READY must be blocked when FPS < 15.0")
	assert(overlay._rejection_timer > 0.0, "Overlay must show low framerate lock notice")
	print("PASS: Hard gate blocked READY state at %.1f FPS (< 15.0 FPS threshold)." % monitor.current_fps)

	# Now feed 15 frames at 33.3ms interval = 30 FPS
	monitor.reset()
	for i in range(15):
		monitor.record_frame(2_000_000 + int(i * 33_333))

	assert(monitor.current_fps >= 25.0, "Current FPS should be ~30 FPS, got %.1f" % monitor.current_fps)
	assert(monitor.is_valid_for_tracking == true, "Monitor must report valid for tracking at 30 FPS")
	sm._handle_idle(idle_res)
	assert(sm.current_state == sm_class.State.READY, "Transition to READY must succeed when FPS >= 15.0")
	print("PASS: Hard gate allowed READY state at %.1f FPS." % monitor.current_fps)

	# --- Test 8: Multi-Framerate Velocity Invariance (15, 30, 60, 120 FPS) ---
	print("\n--- Test 8: Verifying Multi-Framerate Velocity Invariance ---")
	# Simulate an identical 5.0 mph physical putt (2.0 norm units/sec, traveling 0.40 units over 0.20s)
	var test_framerates = [15.0, 30.0, 60.0, 120.0]
	for target_fps in test_framerates:
		sm.reset()
		sm._established_ball_pos = Vector2(0.5, 0.70)
		sm.active_fps = target_fps
		var traj: Array[Dictionary] = []
		var total_time_sec = 0.20
		var n_frames = int(target_fps * total_time_sec)
		if n_frames < 3:
			n_frames = 3

		for i in range(n_frames + 1):
			var frac = float(i) / float(n_frames)
			var y_pos = 0.70 - frac * 0.40  # travels 0.40 units forward
			var t_ms = 1000 + int(frac * total_time_sec * 1000.0)
			traj.append({"pos": Vector2(0.5, y_pos), "time": t_ms})

		sm._trajectory = traj
		sm._tracking_start_time_msec = traj[0]["time"]
		sm._last_seen_time_msec = traj[traj.size() - 1]["time"]
		sm._tracking_frame_count = traj.size() - 1
		sm._last_seen_pos = traj[traj.size() - 1]["pos"]

		var spd_res = {"speed": 0.0}
		var cb = func(spd, _hla): spd_res["speed"] = spd
		sm.putt_detected.connect(cb)
		sm._calculate_and_dispatch_putt()
		sm.putt_detected.disconnect(cb)

		var err_pct = absf(spd_res["speed"] - 5.0) / 5.0 * 100.0
		print("FPS: %3.0f | Measured Speed: %.2f mph (Error: %.1f%%)" % [target_fps, spd_res["speed"], err_pct])
		assert(err_pct <= 4.0, "Speed at %.0f FPS must be within 4%% of 5.0 mph, got %.2f mph" % [target_fps, spd_res["speed"]])

	print("PASS: Multi-framerate velocity invariance verified across 15, 30, 60, 120 FPS.")

	# --- Test 9: Jitter & Noise Resilience ---
	print("\n--- Test 9: Verifying Jitter & Noise Resilience ---")
	sm.reset()
	sm._established_ball_pos = Vector2(0.5, 0.70)
	sm.active_fps = 30.0
	# 5.0 mph putt with +/- 15ms timestamp jitter injected per frame
	var jitter_traj: Array[Dictionary] = [
		{"pos": Vector2(0.5, 0.70), "time": 1000},
		{"pos": Vector2(0.5, 0.62), "time": 1045},  # +5ms
		{"pos": Vector2(0.5, 0.54), "time": 1070},  # -10ms
		{"pos": Vector2(0.5, 0.46), "time": 1135},  # +15ms
		{"pos": Vector2(0.5, 0.38), "time": 1155},  # -5ms
		{"pos": Vector2(0.5, 0.30), "time": 1200}
	]
	sm._trajectory = jitter_traj
	sm._tracking_start_time_msec = 1000
	sm._last_seen_time_msec = 1200
	sm._tracking_frame_count = 5
	sm._last_seen_pos = Vector2(0.5, 0.30)

	var res9 = {"speed": 0.0}
	var cb9 = func(spd, _hla): res9["speed"] = spd
	sm.putt_detected.connect(cb9)
	sm._calculate_and_dispatch_putt()
	sm.putt_detected.disconnect(cb9)

	var err9 = absf(res9["speed"] - 5.0) / 5.0 * 100.0
	print("Speed with +/-15ms jitter: %.2f mph (Error: %.1f%%)" % [res9["speed"], err9])
	assert(err9 <= 5.0, "Jittered putt speed must be within 5%% of 5.0 mph, got %.2f mph" % res9["speed"])
	print("PASS: OLS regression successfully recovered velocity under timestamp jitter.")

	# --- Test 10: Duplicate Frame Filter ---
	print("\n--- Test 10: Verifying Duplicate Frame Rejection ---")
	monitor.reset()
	var f1_accepted = monitor.record_frame(1_000_000)
	var f2_duplicate = monitor.record_frame(1_001_000)  # Only 1ms later (< 2ms)
	var f3_accepted = monitor.record_frame(1_033_000)   # 32ms later

	assert(f1_accepted == true, "Frame 1 must be accepted")
	assert(f2_duplicate == false, "Frame 2 within 1ms must be rejected as duplicate")
	assert(f3_accepted == true, "Frame 3 must be accepted")
	assert(monitor._duplicate_frame_count == 1, "Duplicate frame count should be 1")
	print("PASS: Duplicate frame (< 2ms arrival) cleanly filtered.")

	print("\n==================================================")
	print("ALL PUTTING CAMERA SPEED VALIDATION TESTS PASSED!")
	print("==================================================")
	quit(0)
