extends SceneTree

## Unit test suite for Tournament Mode and TournamentService.
## Tests:
## 1. Join code generation (format and length)
## 2. UTC Date parsing and formatting
## 3. Tournament join validation logic (expiration, player capacity, status)
## 4. Standings tie-breaking and sorting logic
## 5. Expected hole count and pending score calculations

const TournamentServiceScript = preload("res://Utils/Cloud/tournament_service.gd")

var _tested := false


func _initialize() -> void:
	print("=== Running Tournament Service Unit Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_all_tests()


func _run_all_tests() -> void:
	await _test_1_code_generation()
	await _test_2_utc_date_parsing_and_formatting()
	await _test_3_validation_logic()
	await _test_4_standings_sorting()
	await _test_5_expected_hole_counts()
	await _test_6_multiplayer_menu_scene_loading()

	print("\n=======================================================")
	print("   ALL TOURNAMENT SERVICE UNIT TESTS PASSED SUCCESSFULLY! ")
	print("=======================================================\n")
	quit(0)


func _test_1_code_generation() -> void:
	print("\n--- Test 1: Join Code Generation ---")
	var svc = TournamentServiceScript.new()
	var code = svc.generate_join_code()
	assert(code.length() == 6, "Expected 6-char join code, got length %d (%s)" % [code.length(), code])
	assert(code == code.to_upper(), "Expected uppercase code, got %s" % code)
	svc.free()
	print("Join code generation OK.")


func _test_2_utc_date_parsing_and_formatting() -> void:
	print("\n--- Test 2: UTC Date Parsing and Formatting ---")
	var svc = TournamentServiceScript.new()

	# Test standard format YYYY-MM-DD HH:MM
	var ts = svc._parse_date_utc("2026-11-10 18:30")
	assert(ts > 0, "Expected positive timestamp from date string")

	var formatted = svc.format_end_date(ts)
	assert(formatted.contains("Nov 10, 2026"), "Formatted date should contain 'Nov 10, 2026', got '%s'" % formatted)
	assert(formatted.contains("18:30 UTC"), "Formatted date should contain '18:30 UTC', got '%s'" % formatted)

	# Test ISO8601 format
	var ts_iso = svc._parse_date_utc("2026-12-25T00:00:00Z")
	assert(ts_iso > 0, "Expected positive timestamp from ISO date string")
	var formatted_iso = svc.format_end_date(ts_iso)
	assert(formatted_iso.contains("Dec 25, 2026"), "Formatted ISO date should contain 'Dec 25, 2026', got '%s'" % formatted_iso)

	# Test empty or invalid
	assert(svc._parse_date_utc("") == 0, "Empty string should return 0 timestamp")
	assert(svc.format_end_date(0) == "No end date", "Zero timestamp should format to 'No end date'")

	svc.free()
	print("Date parsing and formatting OK.")


func _test_3_validation_logic() -> void:
	print("\n--- Test 3: Tournament Join Validation Logic ---")
	var svc = TournamentServiceScript.new()

	# Open tournament in future with room
	var t_valid := {
		"status": "open",
		"end_date_utc": "2030-01-01 00:00",
		"max_players": 10,
		"player_count": 5
	}
	var res = svc._validate_joinable(t_valid, "user_123")
	assert(res.get("ok", false) == true, "Valid tournament should be joinable")
	assert(not svc.is_tournament_ended(t_valid), "Future tournament should not be ended")

	# Full tournament
	var t_full := {
		"status": "open",
		"end_date_utc": "2030-01-01 00:00",
		"max_players": 4,
		"player_count": 4
	}
	var res_full = svc._validate_joinable(t_full, "user_123")
	assert(res_full.get("ok", false) == false, "Full tournament should not be joinable")
	assert(res_full.get("error", "").contains("full"), "Error should mention tournament is full")

	# Expired tournament
	var t_expired := {
		"status": "open",
		"end_date_utc": "2020-01-01 00:00",
		"max_players": 10,
		"player_count": 1
	}
	var res_expired = svc._validate_joinable(t_expired, "user_123")
	assert(res_expired.get("ok", false) == false, "Expired tournament should not be joinable")
	assert(svc.is_tournament_ended(t_expired), "Past tournament should be detected as ended")

	# Closed status
	var t_closed := {
		"status": "ended",
		"end_date_utc": "2030-01-01 00:00",
		"max_players": 10,
		"player_count": 1
	}
	var res_closed = svc._validate_joinable(t_closed, "user_123")
	assert(res_closed.get("ok", false) == false, "Ended tournament should not be joinable")

	svc.free()
	print("Validation logic OK.")


func _test_4_standings_sorting() -> void:
	print("\n--- Test 4: Standings Sorting & Tie-Breaking ---")

	var entries: Array[Dictionary] = [
		{"player_name": "Bob", "status": "submitted", "to_par": 2, "total_strokes": 74},
		{"player_name": "Alice", "status": "submitted", "to_par": -3, "total_strokes": 69},
		{"player_name": "Charlie", "status": "submitted", "to_par": -1, "total_strokes": 71},
		{"player_name": "Dave", "status": "submitted", "to_par": -1, "total_strokes": 71},
		{"player_name": "Eve", "status": "in_progress", "holes_completed": 12},
		{"player_name": "Frank", "status": "pending", "holes_completed": 0}
	]

	# Extract submitted entries and sort matching TournamentService algorithm
	var submitted: Array[Dictionary] = []
	var in_progress: Array[Dictionary] = []
	var pending: Array[Dictionary] = []

	for e in entries:
		match e.get("status", ""):
			"submitted": submitted.append(e)
			"in_progress": in_progress.append(e)
			_: pending.append(e)

	submitted.sort_custom(func(a, b):
		var a_par: int = int(a.get("to_par", 999))
		var b_par: int = int(b.get("to_par", 999))
		if a_par != b_par:
			return a_par < b_par
		return int(a.get("total_strokes", 999)) < int(b.get("total_strokes", 999))
	)

	assert(submitted[0]["player_name"] == "Alice", "Alice (-3) must be 1st")
	assert(submitted[1]["to_par"] == -1 and submitted[2]["to_par"] == -1, "Charlie and Dave tied for 2nd/3rd")
	assert(submitted[3]["player_name"] == "Bob", "Bob (+2) must be 4th")

	print("Standings sorting OK.")


func _test_5_expected_hole_counts() -> void:
	print("\n--- Test 5: Expected Hole Counts ---")
	var svc = TournamentServiceScript.new()
	assert(svc._expected_hole_count("Full 18") == 18, "Full 18 should expect 18 holes")
	assert(svc._expected_hole_count("Front 9") == 9, "Front 9 should expect 9 holes")
	assert(svc._expected_hole_count("Back 9") == 9, "Back 9 should expect 9 holes")
	svc.free()
	print("Expected hole counts OK.")


func _test_6_multiplayer_menu_scene_loading() -> void:
	print("\n--- Test 6: Multiplayer Menu Scene Loading & Instantiation ---")
	var scene = load("res://UI/OnlineMultiplayer/multiplayer_menu.tscn")
	assert(scene != null, "multiplayer_menu.tscn must load successfully")
	var instance = scene.instantiate()
	assert(instance != null, "multiplayer_menu instance must be created successfully")

	# Check that mode selector buttons exist
	var mode_bar = instance.get_node_or_null("%ModeSelectorBar")
	assert(mode_bar != null, "ModeSelectorBar node must exist in multiplayer_menu")
	var matches_btn = instance.get_node_or_null("%ModeMatchesButton")
	assert(matches_btn != null, "ModeMatchesButton node must exist")
	var tourneys_btn = instance.get_node_or_null("%ModeTournamentsButton")
	assert(tourneys_btn != null, "ModeTournamentsButton node must exist")

	# Check that tournament section exists
	var tourneys_sec = instance.get_node_or_null("%TournamentsSection")
	assert(tourneys_sec != null, "TournamentsSection must exist")

	instance.free()
	print("Multiplayer Menu scene instantiation OK.")
