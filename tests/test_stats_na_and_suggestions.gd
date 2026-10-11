extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Stats N/A and Shot Suggestions Validation Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	# -------------------------------------------------------------
	# TEST 1: ShotFormatter formats unprovided, uncalculated, and dummy 0.0 stats as N/A
	# -------------------------------------------------------------
	print("\n--- Test 1: ShotFormatter formatting for Square / dummy stats ---")
	
	# Simulated Square shot (no SmashFactor, no ClubSpeed, no AoA)
	var square_raw = {
		"Speed": 115.0,
		"BallSpeed": 115.0,
		"VLA": 14.0,
		"HLA": 0.5,
		"TotalSpin": 2600.0,
		"SpinAxis": 1.2,
		"BackSpin": 2595.0,
		"SideSpin": 54.0
	}
	var square_formatted = ShotFormatter.format_ball_display(square_raw, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(square_formatted.get("SmashFactor") == "N/A", "SmashFactor must be N/A for Square without club speed, got: %s" % square_formatted.get("SmashFactor"))
	assert(square_formatted.get("ClubSpeed") == "N/A", "ClubSpeed must be N/A when missing, got: %s" % square_formatted.get("ClubSpeed"))
	assert(square_formatted.get("AttackAngle") == "N/A", "AttackAngle must be N/A when missing, got: %s" % square_formatted.get("AttackAngle"))
	assert(square_formatted.get("DynamicLoft") == "N/A", "DynamicLoft must be N/A when missing, got: %s" % square_formatted.get("DynamicLoft"))
	print("  PASS: Square shot correctly formatted missing stats as N/A.")

	# Shot with dummy 0.0 values
	var dummy_raw = {
		"Speed": 115.0,
		"BallSpeed": 115.0,
		"SmashFactor": 0.0,
		"ClubSpeed": 0.0,
		"AttackAngle": 0.0,
		"DynamicLoft": 0.0
	}
	var dummy_formatted = ShotFormatter.format_ball_display(dummy_raw, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(dummy_formatted.get("SmashFactor") == "N/A", "SmashFactor must be N/A when 0.0, got: %s" % dummy_formatted.get("SmashFactor"))
	assert(dummy_formatted.get("ClubSpeed") == "N/A", "ClubSpeed must be N/A when 0.0, got: %s" % dummy_formatted.get("ClubSpeed"))
	assert(dummy_formatted.get("AttackAngle") == "N/A", "AttackAngle must be N/A when 0.0, got: %s" % dummy_formatted.get("AttackAngle"))
	assert(dummy_formatted.get("DynamicLoft") == "N/A", "DynamicLoft must be N/A when 0.0, got: %s" % dummy_formatted.get("DynamicLoft"))
	print("  PASS: Dummy 0.0 stats correctly converted to N/A.")

	# Shot with calculable smash factor
	var calc_smash_raw = {
		"Speed": 120.0,
		"BallSpeed": 120.0,
		"ClubSpeed": 80.0
	}
	var calc_formatted = ShotFormatter.format_ball_display(calc_smash_raw, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(calc_formatted.get("SmashFactor") == "1.50", "SmashFactor must be calculated as 1.50, got: %s" % calc_formatted.get("SmashFactor"))
	print("  PASS: Calculable Smash Factor (120/80 = 1.50) successfully calculated.")

	# Shot with valid AoA
	var valid_aoa_raw = {
		"Speed": 120.0,
		"BallSpeed": 120.0,
		"AttackAngle": -3.5
	}
	var valid_aoa_formatted = ShotFormatter.format_ball_display(valid_aoa_raw, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(valid_aoa_formatted.get("AttackAngle") == "-3.5", "Valid negative AoA must format as -3.5, got: %s" % valid_aoa_formatted.get("AttackAngle"))
	print("  PASS: Valid non-zero AoA retained.")

	# -------------------------------------------------------------
	# TEST 2: RangeUI Stats Cards display N/A for Square and dummy stats
	# -------------------------------------------------------------
	print("\n--- Test 2: RangeUI cards update with N/A ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must load")
	var r_ui = range_ui_scene.instantiate()
	root.add_child(r_ui)
	await process_frame

	var grid = r_ui.get_node_or_null("GridCanvas")
	assert(grid != null, "GridCanvas must exist")

	var get_card_val = func(stat_id: String) -> String:
		var c = grid.get_node_or_null(stat_id)
		if c == null and stat_id == "BallSpeed":
			c = grid.get_node_or_null("Speed")
		elif c == null and stat_id == "Speed":
			c = grid.get_node_or_null("BallSpeed")
		if c != null and "data" in c:
			return str(c.data)
		return ""

	# Make sure SmashFactor and AttackAngle cards exist in grid
	if grid.get_node_or_null("SmashFactor") == null:
		var sf_panel = load("res://UI/data_panel.tscn").instantiate()
		sf_panel.name = "SmashFactor"
		grid.add_child(sf_panel)
	if grid.get_node_or_null("AttackAngle") == null:
		var aoa_panel = load("res://UI/data_panel.tscn").instantiate()
		aoa_panel.name = "AttackAngle"
		grid.add_child(aoa_panel)

	# Direct shot receipt from Square (no SmashFactor or AttackAngle fields in dictionary)
	r_ui.set_data(square_raw, false)
	await process_frame

	var sf_card = get_card_val.call("SmashFactor")
	assert(sf_card == "N/A", "SmashFactor card must show N/A for Square shot, got: %s" % sf_card)
	var aoa_card = get_card_val.call("AttackAngle")
	assert(aoa_card == "N/A", "AttackAngle card must show N/A for Square shot, got: %s" % aoa_card)
	print("  PASS: RangeUI cards showed N/A for missing Square stats.")

	# Receipt of shot with dummy 0.0 values
	r_ui.set_data(dummy_raw, false)
	await process_frame
	var sf_dummy_card = get_card_val.call("SmashFactor")
	assert(sf_dummy_card == "N/A", "SmashFactor card must show N/A when sent dummy 0.0, got: %s" % sf_dummy_card)
	var aoa_dummy_card = get_card_val.call("AttackAngle")
	assert(aoa_dummy_card == "N/A", "AttackAngle card must show N/A when sent dummy 0.0, got: %s" % aoa_dummy_card)
	print("  PASS: RangeUI cards showed N/A when sent dummy 0.0 stats.")

	# Reset data properly resets cards to '---'
	var reset_data = {
		"Distance": "---",
		"Carry": "---",
		"BallSpeed": "---",
		"Speed": "---",
		"SmashFactor": "---",
		"AttackAngle": "---"
	}
	r_ui.set_data(reset_data, false)
	await process_frame
	assert(get_card_val.call("SmashFactor") == "---", "SmashFactor must reset to --- on reset")
	assert(get_card_val.call("AttackAngle") == "---", "AttackAngle must reset to --- on reset")
	print("  PASS: Reset data properly resets cards to '---'.")

	r_ui.queue_free()
	await process_frame

	# -------------------------------------------------------------
	# TEST 3: Shot Suggestions only show actual retrieved values, no dummy AoA
	# -------------------------------------------------------------
	print("\n--- Test 3: Shot Suggestions and Comparison Table without dummy AoA ---")
	
	# Shot with dummy AoA (0.0)
	var shot_dummy_aoa = {
		"Club": "7-Iron",
		"Speed": 96.0,
		"BallSpeed": 96.0,
		"ClubSpeed": 76.0,
		"SmashFactor": 1.26,
		"VLA": 21.5,
		"TotalSpin": 4100.0,
		"SpinAxis": 7.5,
		"AttackAngle": 0.0,
		"Carry": 130.0,
		"skill_level": "mid_handicap"
	}

	var recs_dummy = GolfSwingAnalyzer.analyze_launch_monitor(shot_dummy_aoa)
	assert(not recs_dummy.is_empty(), "Recommendations should be produced")
	
	for rec in recs_dummy:
		assert(not ("AoA" in rec.get("title", "") and "0.0" in rec.get("title", "")), "No suggestion title should complain about dummy 0.0 AoA")
		if rec.has("comparison_table"):
			var tbl = rec["comparison_table"] as Array
			for row in tbl:
				assert(row["metric"] != "Attack Angle (AoA)", "Comparison table must NOT include AoA when it was dummy 0.0!")
	print("  PASS: Dummy 0.0 AoA omitted from recommendations and comparison table.")

	# Shot with valid AoA (1.0 - upward iron scoop flaw)
	var shot_real_aoa = {
		"Club": "7-Iron",
		"Speed": 96.0,
		"BallSpeed": 96.0,
		"ClubSpeed": 76.0,
		"SmashFactor": 1.26,
		"VLA": 21.5,
		"TotalSpin": 4100.0,
		"SpinAxis": 7.5,
		"AttackAngle": 1.0,
		"Carry": 130.0,
		"skill_level": "mid_handicap"
	}
	var recs_real = GolfSwingAnalyzer.analyze_launch_monitor(shot_real_aoa)
	var has_aoa_row := false
	for rec in recs_real:
		if rec.has("comparison_table"):
			var tbl = rec["comparison_table"] as Array
			for row in tbl:
				if row["metric"] == "Attack Angle (AoA)":
					has_aoa_row = true
					assert(row["player"] == "+1.0°", "Player AoA must be +1.0°")
	assert(has_aoa_row, "Comparison table must include AoA when real non-zero AoA is retrieved")
	print("  PASS: Actual retrieved AoA is present in comparison table.")

	# Unified skeleton analysis with wood posture loss and dummy AoA
	var skel_analysis = {
		"has_valid_data": true,
		"impact_spine_loss": 5.5,
		"impact_early_extension": 0.5
	}
	var wood_shot_dummy_aoa = {
		"Club": "3-Wood",
		"is_tee": false,
		"Speed": 120.0,
		"BallSpeed": 120.0,
		"AttackAngle": 0.0,
		"skill_level": "mid_handicap"
	}
	var unified_recs = GolfSwingAnalyzer.analyze_shot_unified(wood_shot_dummy_aoa, skel_analysis)
	for rec in unified_recs:
		var pv = str(rec.get("player_val", ""))
		assert(not ("AoA: +0.0°" in pv or "AoA: 0.0°" in pv), "Unified suggestion details must NOT show dummy 0.0 AoA, got: %s" % pv)
	print("  PASS: Unified recommendations do not display dummy AoA in player_val.")

	print("\n=================================================================")
	print("  ALL STATS N/A AND SHOT SUGGESTIONS TESTS PASSED! 🎉           ")
	print("=================================================================\n")
	quit(0)
