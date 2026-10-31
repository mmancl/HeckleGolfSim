extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Computed Stats Indicator (* Stat *) Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	# -------------------------------------------------------------
	# TEST 1: ShotFormatter identifies computed vs direct stats in _computed_stats
	# -------------------------------------------------------------
	print("\n--- Test 1: ShotFormatter _computed_stats identification ---")

	# 1A. Computed Smash Factor & Computed Face to Path
	var raw_calc = {
		"Speed": 120.0,
		"BallSpeed": 120.0,
		"ClubSpeed": 80.0,
		"FaceAngle": 1.5,
		"ClubPath": 0.5
	}
	var fmt_calc = ShotFormatter.format_ball_display(raw_calc, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(fmt_calc.get("SmashFactor") == "1.50", "SmashFactor must be 1.50, got: %s" % fmt_calc.get("SmashFactor"))
	assert(fmt_calc.get("FaceToPath") == "1.0 O", "FaceToPath must be 1.0 O, got: %s" % fmt_calc.get("FaceToPath"))
	assert(fmt_calc.has("_computed_stats"), "_computed_stats must exist in formatted output")
	var comp_list = fmt_calc.get("_computed_stats") as Array
	assert("SmashFactor" in comp_list, "SmashFactor must be in _computed_stats when calculated")
	assert("FaceToPath" in comp_list, "FaceToPath must be in _computed_stats when calculated")
	print("  PASS: Calculated SmashFactor and FaceToPath recorded in _computed_stats.")

	# 1B. Direct Smash Factor & Direct Face to Path
	var raw_direct = {
		"Speed": 120.0,
		"BallSpeed": 120.0,
		"ClubSpeed": 80.0,
		"SmashFactor": 1.48,
		"FaceAngle": 1.5,
		"ClubPath": 0.5,
		"FaceToPath": 0.8
	}
	var fmt_direct = ShotFormatter.format_ball_display(raw_direct, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(fmt_direct.get("SmashFactor") == "1.48", "SmashFactor must be direct 1.48, got: %s" % fmt_direct.get("SmashFactor"))
	assert(fmt_direct.get("FaceToPath") == "0.8 O", "FaceToPath must be direct 0.8 O, got: %s" % fmt_direct.get("FaceToPath"))
	var comp_direct_list = fmt_direct.get("_computed_stats") as Array
	assert(not ("SmashFactor" in comp_direct_list), "SmashFactor must NOT be in _computed_stats when sent directly")
	assert(not ("FaceToPath" in comp_direct_list), "FaceToPath must NOT be in _computed_stats when sent directly")
	print("  PASS: Directly sent SmashFactor and FaceToPath not flagged as computed.")

	# 1C. Missing stats that cannot be computed
	var raw_missing = {
		"Speed": 110.0,
		"BallSpeed": 110.0
	}
	var fmt_missing = ShotFormatter.format_ball_display(raw_missing, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(fmt_missing.get("SmashFactor") == "N/A", "SmashFactor must be N/A when club speed is missing")
	assert(fmt_missing.get("ClubSpeed") == "N/A", "ClubSpeed must be N/A when missing")
	assert(fmt_missing.get("FaceToPath") == "N/A", "FaceToPath must be N/A when face angle and path are missing")
	assert(fmt_missing.get("FaceAngle") == "N/A", "FaceAngle must be N/A when missing and not computable")
	assert(fmt_missing.get("ClubPath") == "N/A", "ClubPath must be N/A when missing and not computable")
	print("  PASS: Missing, uncomputable metrics correctly show N/A.")

	# -------------------------------------------------------------
	# TEST 2: RangeUI Card Labels update with * around computed text
	# -------------------------------------------------------------
	print("\n--- Test 2: RangeUI Card Labels with * Asterisk Indicators ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must load")
	var r_ui = range_ui_scene.instantiate()
	root.add_child(r_ui)
	await process_frame

	var grid = r_ui.get_node_or_null("GridCanvas")
	assert(grid != null, "GridCanvas must exist")

	var get_card_label = func(stat_id: String) -> String:
		var c = grid.get_node_or_null(stat_id)
		if c != null and "label" in c:
			return str(c.label)
		return ""

	var get_card_val = func(stat_id: String) -> String:
		var c = grid.get_node_or_null(stat_id)
		if c != null and "data" in c:
			return str(c.data)
		return ""

	# Ensure cards exist
	if grid.get_node_or_null("SmashFactor") == null:
		var sf_p = load("res://UI/data_panel.tscn").instantiate()
		sf_p.name = "SmashFactor"
		sf_p.set_label("Smash Factor")
		grid.add_child(sf_p)
	if grid.get_node_or_null("FaceToPath") == null:
		var ftp_p = load("res://UI/data_panel.tscn").instantiate()
		ftp_p.name = "FaceToPath"
		ftp_p.set_label("Face to Path")
		grid.add_child(ftp_p)

	# 2A. Send shot with computed stats (fmt_calc)
	r_ui.set_data(fmt_calc, true)
	await process_frame

	var sf_lbl_calc = get_card_label.call("SmashFactor")
	var ftp_lbl_calc = get_card_label.call("FaceToPath")
	assert(sf_lbl_calc == "* Smash Factor *", "Computed SmashFactor label must be '* Smash Factor *', got: %s" % sf_lbl_calc)
	assert(ftp_lbl_calc == "* Face to Path *", "Computed FaceToPath label must be '* Face to Path *', got: %s" % ftp_lbl_calc)
	assert(get_card_val.call("SmashFactor") == "1.50", "SmashFactor value must be 1.50")
	assert(get_card_val.call("FaceToPath") == "1.0 O", "FaceToPath value must be 1.0 O")
	print("  PASS: RangeUI displayed '* Smash Factor *' and '* Face to Path *' for computed stats.")

	# 2B. Send shot with direct stats (fmt_direct)
	r_ui.set_data(fmt_direct, true)
	await process_frame

	var sf_lbl_direct = get_card_label.call("SmashFactor")
	var ftp_lbl_direct = get_card_label.call("FaceToPath")
	assert(sf_lbl_direct == "Smash Factor", "Direct SmashFactor label must be 'Smash Factor' (no asterisks), got: %s" % sf_lbl_direct)
	assert(ftp_lbl_direct == "Face to Path", "Direct FaceToPath label must be 'Face to Path' (no asterisks), got: %s" % ftp_lbl_direct)
	assert(get_card_val.call("SmashFactor") == "1.48", "SmashFactor value must be 1.48")
	assert(get_card_val.call("FaceToPath") == "0.8 O", "FaceToPath value must be 0.8 O")
	print("  PASS: RangeUI displayed clean labels without asterisks for direct LM stats.")

	# 2C. Send shot with missing stats (fmt_missing)
	r_ui.set_data(fmt_missing, true)
	await process_frame

	var sf_lbl_missing = get_card_label.call("SmashFactor")
	var ftp_lbl_missing = get_card_label.call("FaceToPath")
	assert(sf_lbl_missing == "Smash Factor", "Uncomputed missing SmashFactor label must be 'Smash Factor', got: %s" % sf_lbl_missing)
	assert(ftp_lbl_missing == "Face to Path", "Uncomputed missing FaceToPath label must be 'Face to Path', got: %s" % ftp_lbl_missing)
	assert(get_card_val.call("SmashFactor") == "N/A", "SmashFactor value must be N/A")
	assert(get_card_val.call("FaceToPath") == "N/A", "FaceToPath value must be N/A")
	print("  PASS: RangeUI shows N/A and standard labels for uncomputable stats.")

	# 2D. Reset data resets labels to clean base labels and values to '---'
	var reset_data = {
		"Distance": "---",
		"Carry": "---",
		"BallSpeed": "---",
		"Speed": "---",
		"SmashFactor": "---",
		"FaceToPath": "---"
	}
	r_ui.set_data(reset_data, false)
	await process_frame

	assert(get_card_label.call("SmashFactor") == "Smash Factor", "Reset must restore Smash Factor label without asterisks")
	assert(get_card_label.call("FaceToPath") == "Face to Path", "Reset must restore Face to Path label without asterisks")
	assert(get_card_val.call("SmashFactor") == "---", "Reset must restore SmashFactor value to ---")
	assert(get_card_val.call("FaceToPath") == "---", "Reset must restore FaceToPath value to ---")
	print("  PASS: Reset data cleanly restores '---' and removes all asterisks.")

	# -------------------------------------------------------------
	# TEST 3: Shot details text formatting includes asterisks
	# -------------------------------------------------------------
	print("\n--- Test 3: Shot Details Text Formatting ---")
	var details_calc = r_ui.call("_format_shot_details_text", fmt_calc)
	assert("* Smash Factor *" in details_calc, "Details text must contain '* Smash Factor *' when computed")
	assert("* Face to Path *" in details_calc, "Details text must contain '* Face to Path *' when computed")

	var details_direct = r_ui.call("_format_shot_details_text", fmt_direct)
	assert("Smash Factor: 1.48" in details_direct, "Details text must contain 'Smash Factor: 1.48' without asterisks when direct")
	assert("Face to Path: 0.8 O" in details_direct, "Details text must contain 'Face to Path: 0.8 O' without asterisks when direct")
	print("  PASS: Shot details summary accurately formats computed vs direct labels.")

	print("\n=======================================================")
	print("ALL COMPUTED STATS INDICATOR TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
