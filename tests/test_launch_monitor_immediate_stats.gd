extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Launch Monitor Immediate Stats Update Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must be loadable")

	var r_ui = range_ui_scene.instantiate()
	root.add_child(r_ui)
	await process_frame

	var grid = r_ui.get_node_or_null("GridCanvas")
	assert(grid != null, "GridCanvas must exist in RangeUI")

	# Helper to read card data
	var get_card_data = func(stat_id: String) -> String:
		var card = grid.get_node_or_null(stat_id)
		if card == null and stat_id == "BallSpeed":
			card = grid.get_node_or_null("Speed")
		elif card == null and stat_id == "Speed":
			card = grid.get_node_or_null("BallSpeed")
		if card != null and "data" in card:
			return str(card.data)
		return ""

	# Test 1: Immediate update of static metrics upon shot receipt (is_final_rest = false)
	print("\n--- Test 1: Static Launch Monitor Data Updates Right Away on Shot Receipt ---")
	var launch_monitor_shot = {
		"Speed": "112.5",
		"BallSpeed": "112.5",
		"ClubSpeed": "79.0",
		"SmashFactor": "1.42",
		"VLA": "14.5",
		"HLA": "-1.2",
		"BackSpin": "2750",
		"SideSpin": "-120",
		"SpinAxis": "-2.5",
		"FaceAngle": "0.5 O",
		"ClubPath": "1.0 In-Out",
		"FaceToPath": "0.5 C",
		"Distance": "0.0",
		"Carry": "0.0"
	}

	# Simulated strike from launch monitor: is_final_rest is false!
	r_ui.set_data(launch_monitor_shot, false)
	await process_frame

	var ball_spd = get_card_data.call("BallSpeed")
	assert(ball_spd == "112.5", "BallSpeed card must be updated immediately to 112.5, got: %s" % ball_spd)

	var club_spd = get_card_data.call("ClubSpeed")
	if club_spd != "":
		assert(club_spd == "79.0", "ClubSpeed card must be updated immediately to 79.0, got: %s" % club_spd)

	var smash = get_card_data.call("SmashFactor")
	if smash != "":
		assert(smash == "1.42", "SmashFactor card must be updated immediately to 1.42, got: %s" % smash)

	var back_spin = get_card_data.call("BackSpin")
	if back_spin != "":
		assert(back_spin == "2750", "BackSpin card must be updated immediately to 2750, got: %s" % back_spin)

	var spin_axis = get_card_data.call("SpinAxis")
	if spin_axis != "":
		assert(spin_axis == "-2.5", "SpinAxis card must be updated immediately to -2.5, got: %s" % spin_axis)

	print("  PASS: Static launch monitor data updated in stats cards right away without waiting for ball rest.")

	# Test 2: In-flight live tick updating dynamic stats does not wipe static stats
	print("\n--- Test 2: In-Flight Live Tick Preserves Static Stats ---")
	var inflight_tick = {
		"Distance": "75.0",
		"Carry": "75.0",
		"Apex": "42.0",
		"Offline": "R2.1"
	}
	r_ui.set_data(inflight_tick, false)
	await process_frame

	var dist_val = get_card_data.call("Distance")
	assert(dist_val == "75.0", "Distance card must update to in-flight value 75.0, got: %s" % dist_val)

	var ball_spd_after = get_card_data.call("BallSpeed")
	assert(ball_spd_after == "112.5", "BallSpeed card must remain 112.5 during in-flight dynamic update, got: %s" % ball_spd_after)

	var back_spin_after = get_card_data.call("BackSpin")
	if back_spin_after != "":
		assert(back_spin_after == "2750", "BackSpin card must remain 2750 during in-flight dynamic update, got: %s" % back_spin_after)

	print("  PASS: In-flight updates properly updated dynamic stats while preserving static cards.")

	# Test 3: Shot reset clears stats cards to placeholder '---'
	print("\n--- Test 3: Shot Reset Resets Cards ---")
	var reset_data = {
		"Distance": "---",
		"Carry": "---",
		"BallSpeed": "---",
		"Speed": "---",
		"ClubSpeed": "---",
		"SmashFactor": "---",
		"BackSpin": "---",
		"SideSpin": "---",
		"SpinAxis": "---",
		"Offline": "---",
		"Apex": "---",
		"VLA": "---",
		"HLA": "---"
	}
	r_ui.set_data(reset_data, false)
	await process_frame

	var dist_reset = get_card_data.call("Distance")
	assert(dist_reset == "---", "Distance card must reset to '---', got: %s" % dist_reset)

	var ball_spd_reset = get_card_data.call("BallSpeed")
	assert(ball_spd_reset == "---", "BallSpeed card must reset to '---', got: %s" % ball_spd_reset)

	print("  PASS: Reset data properly resets cards to '---'.")

	r_ui.queue_free()
	await process_frame

	print("\n=======================================================")
	print("  ALL LAUNCH MONITOR IMMEDIATE STATS TESTS PASSED!     ")
	print("=======================================================\n")
	quit(0)
