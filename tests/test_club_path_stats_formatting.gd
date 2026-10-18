extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Club Path Stats Formatting and Overflow Prevention Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	# Test 1: ShotFormatter formats club path with concise I-O and O-I
	print("\n--- Test 1: ShotFormatter Formats ClubPath as I-O / O-I ---")
	var in_to_out_raw = {
		"Speed": 100.0,
		"VLA": 12.0,
		"HLA": 0.0,
		"TotalSpin": 2500.0,
		"SpinAxis": 0.0,
		"ClubPath": 2.4
	}
	var in_to_out_fmt = ShotFormatter.format_ball_display(in_to_out_raw, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(in_to_out_fmt["ClubPath"] == "2.4 I-O", "Expected '2.4 I-O', got: %s" % in_to_out_fmt["ClubPath"])

	var out_to_in_raw = {
		"Speed": 100.0,
		"VLA": 12.0,
		"HLA": 0.0,
		"TotalSpin": 2500.0,
		"SpinAxis": 0.0,
		"ClubPath": -3.2
	}
	var out_to_in_fmt = ShotFormatter.format_ball_display(out_to_in_raw, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(out_to_in_fmt["ClubPath"] == "3.2 O-I", "Expected '3.2 O-I', got: %s" % out_to_in_fmt["ClubPath"])

	var straight_raw = {
		"Speed": 100.0,
		"VLA": 12.0,
		"HLA": 0.0,
		"TotalSpin": 2500.0,
		"SpinAxis": 0.0,
		"ClubPath": 0.0
	}
	var straight_fmt = ShotFormatter.format_ball_display(straight_raw, null, PhysicsEnums.Units.IMPERIAL, true)
	assert(straight_fmt["ClubPath"] == "0.0 Str", "Expected '0.0 Str', got: %s" % straight_fmt["ClubPath"])
	print("  PASS: ShotFormatter properly outputs concise I-O, O-I, and Str notation.")

	# Test 2: RangeUI _format_club_path normalizes verbose legacy strings and numbers
	print("\n--- Test 2: RangeUI _format_club_path Normalization ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must be loadable")
	var r_ui = range_ui_scene.instantiate()
	root.add_child(r_ui)
	await process_frame

	assert(r_ui.call("_format_club_path", "1.5 In-Out") == "1.5 I-O", "In-Out must convert to I-O")
	assert(r_ui.call("_format_club_path", "2.1 Out-In") == "2.1 O-I", "Out-In must convert to O-I")
	assert(r_ui.call("_format_club_path", "1.5 in-out") == "1.5 I-O", "Case-insensitive in-out must convert to I-O")
	assert(r_ui.call("_format_club_path", "2.1 out-in") == "2.1 O-I", "Case-insensitive out-in must convert to O-I")
	assert(r_ui.call("_format_club_path", 3.5) == "3.5 I-O", "Positive float must format to I-O")
	assert(r_ui.call("_format_club_path", -4.2) == "4.2 O-I", "Negative float must format to O-I")
	assert(r_ui.call("_format_club_path", "---") == "---", "Placeholder '---' must be preserved")
	assert(r_ui.call("_format_club_path", "N/A") == "N/A", "Placeholder 'N/A' must be preserved")
	print("  PASS: RangeUI _format_club_path normalizes legacy strings and floats.")

	# Test 3: RangeUI set_data updates ClubPath card with abbreviated text
	print("\n--- Test 3: RangeUI set_data with ClubPath Card ---")
	var test_shot = {
		"Speed": "105.0",
		"ClubPath": "1.8 In-Out",
		"FaceAngle": "0.5 O"
	}
	r_ui.set_data(test_shot, false)
	await process_frame

	var grid = r_ui.get_node_or_null("GridCanvas")
	assert(grid != null, "GridCanvas must exist")
	var path_panel = grid.get_node_or_null("ClubPath")
	assert(path_panel != null, "ClubPath panel must exist")
	assert(path_panel.data == "1.8 I-O", "ClubPath card data must be normalized to '1.8 I-O', got: %s" % path_panel.data)
	print("  PASS: RangeUI set_data sets normalized I-O text on ClubPath card.")

	# Test 4: DataPanel clipping and dynamic font resizing
	print("\n--- Test 4: DataPanel Dynamic Font Sizing & Clipping ---")
	var panel_scene = load("res://UI/data_panel.tscn")
	assert(panel_scene != null, "data_panel.tscn must be loadable")
	var panel = panel_scene.instantiate()
	root.add_child(panel)
	await process_frame

	assert(panel.clip_contents, "DataPanel must have clip_contents = true")
	var data_lbl = panel.get_node("VBoxContainer/Data")
	assert(data_lbl.clip_text, "Data label must have clip_text = true")

	# Test font size for short text
	panel.set_data("1.8 O")
	var short_font_size = data_lbl.get_theme_font_size("font_size")
	assert(short_font_size == 22, "Short text must use font size 22, got: %d" % short_font_size)

	# Test font size for medium text (e.g. 1.8 I-O)
	panel.set_data("1.8 I-O")
	var med_font_size = data_lbl.get_theme_font_size("font_size")
	assert(med_font_size <= 18, "Medium text (7 chars) must scale down to <= 18, got: %d" % med_font_size)

	# Test font size for long text (e.g. 12.4 Out-In)
	panel.set_data("12.4 Out-In")
	var long_font_size = data_lbl.get_theme_font_size("font_size")
	assert(long_font_size <= 13, "Long text (11 chars) must scale down to <= 13, got: %d" % long_font_size)
	print("  PASS: DataPanel scales font size dynamically and enforces clipping.")

	# Test 5: Club delivery visuals path parsing with I-O and O-I
	print("\n--- Test 5: Club Delivery Visuals Compatibility with I-O and O-I ---")
	var delivery_data_io = {
		"ClubPath": "2.5 I-O",
		"FaceAngle": 1.0,
		"HorizontalFaceImpact": 0.0,
		"VerticalFaceImpact": 0.0
	}
	var panel_io = ClubDeliveryVisuals.create_panel(delivery_data_io, false)
	assert(panel_io.has_path_data, "Panel must detect path data with 'I-O'")
	assert(is_equal_approx(panel_io.path_visual.club_path, 2.5), "Path visual value must be 2.5")
	panel_io.free()

	var delivery_data_oi = {
		"ClubPath": "3.1 O-I",
		"FaceAngle": 1.0,
		"HorizontalFaceImpact": 0.0,
		"VerticalFaceImpact": 0.0
	}
	var panel_oi = ClubDeliveryVisuals.create_panel(delivery_data_oi, false)
	assert(panel_oi.has_path_data, "Panel must detect path data with 'O-I'")
	assert(is_equal_approx(panel_oi.path_visual.club_path, -3.1), "Path visual value must be -3.1")
	panel_oi.free()
	print("  PASS: Club Delivery Visuals parses both I-O and O-I accurately.")

	r_ui.queue_free()
	panel.queue_free()
	await process_frame

	print("\n=======================================================")
	print("  ALL CLUB PATH STATS FORMATTING TESTS PASSED!         ")
	print("=======================================================\n")
	quit(0)
