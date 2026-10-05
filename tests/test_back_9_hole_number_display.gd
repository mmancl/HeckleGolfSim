extends SceneTree

# Test suite for Back 9 hole number resolution and display

func _init() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Back 9 Hole Number Resolution & Display")
	print("=======================================================")

	# 1. Test get_hole_number_from_id
	print("\n--- Test 1: get_hole_number_from_id static method ---")
	var mp_mgr_script = load("res://Utils/MultiplayerManager.gd")
	assert(mp_mgr_script.get_hole_number_from_id("Hole 1") == 1, "Hole 1 must resolve to 1")
	assert(mp_mgr_script.get_hole_number_from_id("Hole 10") == 10, "Hole 10 must resolve to 10")
	assert(mp_mgr_script.get_hole_number_from_id("Hole 18") == 18, "Hole 18 must resolve to 18")
	assert(mp_mgr_script.get_hole_number_from_id("15") == 15, "'15' must resolve to 15")
	assert(mp_mgr_script.get_hole_number_from_id("Hole 12 - Par 4") == 12, "Hole 12 with suffix must resolve to 12")
	assert(mp_mgr_script.get_hole_number_from_id("NonNumeric", 4) == 5, "Fallback index + 1 must be used for non-numeric IDs")
	print("  PASS: get_hole_number_from_id correctly extracts numbers from various hole ID formats.")

	# 2. Setup mock 18-hole course config
	print("\n--- Test 2: Game Setup with 'Back 9' ---")
	var mock_holes = {}
	for i in range(1, 19):
		mock_holes["Hole %d" % i] = {
			"Name": "Hole %d" % i,
			"Par": 3 if i % 3 == 0 else 4,
			"Hole Location": [100.0 * i, 0.0],
			"Tee Boxes": {
				"Blue": [100.0 * (i - 1), 0.0]
			}
		}
	var mock_config = {
		"Title": "Test Course 18",
		"Hole Info": mock_holes
	}

	var mp = mp_mgr_script.new()
	root.add_child(mp)

	var test_players = [
		{"name": "Golfer A", "tee": "Blue"},
		{"name": "Golfer B", "tee": "Blue"}
	]

	# Setup Back 9 game
	mp.setup_game(test_players, mock_config, "", "", "Back 9")
	assert(mp.hole_ids.size() == 9, "Back 9 must have 9 holes")
	assert(mp.hole_ids[0] == "Hole 10", "First hole must be Hole 10, got %s" % mp.hole_ids[0])
	assert(mp.hole_ids[8] == "Hole 18", "Last hole must be Hole 18, got %s" % mp.hole_ids[8])

	# Check hole numbers:
	# Index 0 is Hole 10! MUST NOT BE 1!
	assert(mp.current_hole_index == 0, "Current hole index starts at 0")
	var hole_0_num = mp.get_current_hole_number()
	print("  Current hole index 0 displays hole number: ", hole_0_num)
	assert(hole_0_num == 10, "Hole index 0 on Back 9 MUST display 10, NOT 1!")

	# Simulate hole advance to hole 11
	mp.current_hole_index = 1
	var hole_1_num = mp.get_current_hole_number()
	print("  Current hole index 1 displays hole number: ", hole_1_num)
	assert(hole_1_num == 11, "Hole index 1 on Back 9 MUST display 11, NOT 2!")

	# Simulate hole advance to hole 18
	mp.current_hole_index = 8
	var hole_8_num = mp.get_current_hole_number()
	print("  Current hole index 8 displays hole number: ", hole_8_num)
	assert(hole_8_num == 18, "Hole index 8 on Back 9 MUST display 18, NOT 9!")
	print("  PASS: Back 9 hole numbering resolves to 10-18, not 1-9.")

	# 3. Test Scorecard split and columns logic for Back 9
	print("\n--- Test 3: Scorecard Split & Columns for Back 9 ---")
	var front_holes = []
	var back_holes = []
	for i in range(mp.hole_ids.size()):
		var hole_id = mp.hole_ids[i]
		var h_num = mp.get_hole_number_from_id(hole_id)
		if h_num <= 9:
			front_holes.append(hole_id)
		else:
			back_holes.append(hole_id)

	assert(front_holes.is_empty(), "Back 9 must have no front holes")
	assert(back_holes.size() == 9, "Back 9 must have 9 back holes")

	var has_both_nines = not front_holes.is_empty() and not back_holes.is_empty()
	assert(not has_both_nines, "Back 9 only round should not have both nines")

	var scorecard_view_tab = "All"
	var render_front = (scorecard_view_tab == "All" or scorecard_view_tab == "Front 9") and not front_holes.is_empty()
	var render_back = (scorecard_view_tab == "All" or scorecard_view_tab == "Back 9") and not back_holes.is_empty()

	assert(not render_front, "render_front must be false when only back 9 played")
	assert(render_back, "render_back must be true when back 9 played")

	var columns = ["Player"]
	if render_front:
		for h_id in front_holes:
			columns.append(str(mp.get_hole_number_from_id(h_id)))
		if not back_holes.is_empty() or scorecard_view_tab == "Front 9":
			columns.append("OUT")
		else:
			columns.append("TOT")

	if render_back:
		for h_id in back_holes:
			columns.append(str(mp.get_hole_number_from_id(h_id)))
		columns.append("IN")

	if scorecard_view_tab == "All" and has_both_nines:
		columns.append("TOT")

	print("  Scorecard columns for Back 9: ", columns)
	var expected_columns = ["Player", "10", "11", "12", "13", "14", "15", "16", "17", "18", "IN"]
	assert(columns == expected_columns, "Back 9 scorecard columns must be %s, got %s" % [expected_columns, columns])
	print("  PASS: Scorecard columns correctly display 10 through 18 and 'IN'.")

	# 4. Test Scorecard split and columns logic for Full 18
	print("\n--- Test 4: Scorecard Split & Columns for Full 18 ---")
	mp.setup_game(test_players, mock_config, "", "", "Full 18")
	var front_18 = []
	var back_18 = []
	for i in range(mp.hole_ids.size()):
		var hole_id = mp.hole_ids[i]
		var h_num = mp.get_hole_number_from_id(hole_id)
		if h_num <= 9:
			front_18.append(hole_id)
		else:
			back_18.append(hole_id)

	assert(front_18.size() == 9, "Full 18 must have 9 front holes")
	assert(back_18.size() == 9, "Full 18 must have 9 back holes")

	var has_both_18 = not front_18.is_empty() and not back_18.is_empty()
	assert(has_both_18, "Full 18 must have both nines")

	var columns_18 = ["Player"]
	for h_id in front_18:
		columns_18.append(str(mp.get_hole_number_from_id(h_id)))
	columns_18.append("OUT")
	for h_id in back_18:
		columns_18.append(str(mp.get_hole_number_from_id(h_id)))
	columns_18.append("IN")
	columns_18.append("TOT")

	print("  Scorecard columns for Full 18: ", columns_18)
	var expected_18 = ["Player", "1", "2", "3", "4", "5", "6", "7", "8", "9", "OUT", "10", "11", "12", "13", "14", "15", "16", "17", "18", "IN", "TOT"]
	assert(columns_18 == expected_18, "Full 18 columns must match standard scorecard")
	print("  PASS: Full 18 scorecard columns correctly display 1-9 OUT 10-18 IN TOT.")

	# Cleanup
	mp.queue_free()

	print("\n=======================================================")
	print("ALL BACK 9 HOLE NUMBER TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
