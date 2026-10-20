extends SceneTree

# Targeted test for multi-track 27+ hole courses:
# Verifies that in match play with multiple 9-hole tracks, advancing holes
# correctly tracks hole IDs, updates pin/marker positions, resolves get_active_hole_config(),
# and avoids aiming back at previous holes or picking Track 1's duplicate holes.

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Multi-Track Hole Advance & Hole Resolution")
	print("=======================================================")

	var mp = root.get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		var mp_mgr_script = load("res://Utils/MultiplayerManager.gd")
		mp = mp_mgr_script.new()
		mp.name = "MultiplayerManager"
		root.add_child(mp)

	# 1. Build mock 27-hole course: 3 tracks (Blue 1-9, Red 1-9, White 1-9)
	# All 3 tracks share the same hole display name "Hole X" but have distinct hole IDs
	# and distinct physical coordinates.
	var mock_holes = {}
	# Blue track: Hole 01 .. Hole 09
	for i in range(1, 10):
		var k = "Hole %02d" % i
		mock_holes[k] = {
			"Name": "Hole %d" % i,
			"Par": 4,
			"Hole Location": [float(i * 100), 10.0],
			"Tee Boxes": {
				"Blue": [float(i * 100), 0.0]
			},
			"SubCourse": "Blue"
		}
	# Red track: Hole 10 .. Hole 18
	for i in range(1, 10):
		var k = "Hole %02d" % (i + 9)
		mock_holes[k] = {
			"Name": "Hole %d" % i, # Duplicate display name "Hole 1", "Hole 2", etc.!
			"Par": 4,
			"Hole Location": [float(i * 100 + 1000), 10.0],
			"Tee Boxes": {
				"Blue": [float(i * 100 + 1000), 0.0]
			},
			"SubCourse": "Red"
		}
	# White track: Hole 19 .. Hole 27
	for i in range(1, 10):
		var k = "Hole %02d" % (i + 18)
		mock_holes[k] = {
			"Name": "Hole %d" % i, # Duplicate display name
			"Par": 4,
			"Hole Location": [float(i * 100 + 2000), 10.0],
			"Tee Boxes": {
				"Blue": [float(i * 100 + 2000), 0.0]
			},
			"SubCourse": "White"
		}

	var mock_config = {
		"Title": "27 Hole Championship Course",
		"Hole Info": mock_holes
	}

	var test_players = [
		{"name": "Golfer 1", "tee": "Blue"}
	]

	print("\n--- Test 1: Setup Game with Track 2 & 3 ('Back 9, Extra Holes') ---")
	mp.setup_game(test_players, mock_config, "", "", "Back 9, Extra Holes")
	assert(mp.hole_ids.size() == 18, "Selected 18 holes across 2 tracks, got %d" % mp.hole_ids.size())
	assert(mp.hole_ids[0] == "Hole 10", "First hole must be Hole 10 (Red 1), got %s" % mp.hole_ids[0])
	assert(mp.hole_ids[1] == "Hole 11", "Second hole must be Hole 11 (Red 2), got %s" % mp.hole_ids[1])
	assert(mp.hole_ids[2] == "Hole 12", "Third hole must be Hole 12 (Red 3), got %s" % mp.hole_ids[2])
	print("  PASS: hole_ids correctly filtered to Red and White tracks: %s" % str(mp.hole_ids.slice(0, 3)))

	print("\n--- Test 2: Instantiating Range Scene & Testing get_active_hole_config() ---")
	var range_scene = load("res://Courses/Range/range.tscn").instantiate()
	range_scene.scene_file_path = "res://Courses/GeneratedCourses/27_hole_course.tscn"
	range_scene.name = "Course_27Hole"
	range_scene.course_data_dict = mock_config
	range_scene.current_hole_id = mp.hole_ids[0]
	range_scene.current_hole_name = mock_holes["Hole 10"]["Name"]
	var h10_loc = mock_holes["Hole 10"]["Hole Location"]
	range_scene.current_hole_location = Vector3(h10_loc[0], 0.0, h10_loc[1])
	root.add_child(range_scene)

	var active_cfg = range_scene.get_active_hole_config()
	assert(active_cfg.get("SubCourse") == "Red", "Active hole must be Red track, got %s" % active_cfg.get("SubCourse"))
	assert(range_scene.current_hole_id == "Hole 10", "Current hole ID must be Hole 10")
	print("  PASS: get_active_hole_config() resolved to Red track Hole 10 despite Hole 01 sharing the name 'Hole 1'.")

	print("\n--- Test 3: CoursePlay _on_active_player_changed and Hole Advance ---")
	var cp_node = load("res://Courses/CoursePlay/course_play.tscn").instantiate()
	cp_node.course_instance = range_scene
	root.add_child(cp_node)

	# Initial setup (Hole 1 of match = Hole 10)
	mp.start_hole()
	cp_node._on_active_player_changed(mp.get_active_player())
	assert(range_scene.current_hole_id == "Hole 10", "Expected Hole 10, got %s" % range_scene.current_hole_id)
	assert(range_scene.current_hole_location.x == 1100.0, "Expected pin X=1100.0 for Hole 10, got %f" % range_scene.current_hole_location.x)

	# Advance to Hole 2 of match (Hole 11 = Red 2)
	print("\n--- Advancing to Next Hole (Hole 11) ---")
	mp.advance_hole()
	assert(mp.current_hole_index == 1, "Expected current_hole_index=1")
	assert(mp.hole_ids[mp.current_hole_index] == "Hole 11", "Expected Hole 11")

	cp_node._on_active_player_changed(mp.get_active_player())
	assert(range_scene.current_hole_id == "Hole 11", "Range current_hole_id must be updated to Hole 11, got %s" % range_scene.current_hole_id)
	assert(range_scene.current_hole_location.x == 1200.0, "Pin location X must be 1200.0 for Hole 11, got %f" % range_scene.current_hole_location.x)

	var active_cfg_h2 = range_scene.get_active_hole_config()
	assert(active_cfg_h2.get("SubCourse") == "Red", "Active config on advance must be Red track, got %s" % active_cfg_h2.get("SubCourse"))
	print("  PASS: In-game hole advance correctly updated current_hole_id to Hole 11 and resolved Red track pin/config.")

	print("\n--- Test 4: Save & Resume Match directly restores hole_ids ---")
	var saved_match_data = {
		"match_id": "test_match_123",
		"course_title": "27 Hole Championship Course",
		"current_hole_index": 1,
		"selected_course_length": "Back 9, Extra Holes",
		"hole_ids": mp.hole_ids.duplicate(),
		"players": mp._serialize_players(mp.players)
	}
	# Clear mp hole_ids and verify resume_match restores them exactly
	mp.hole_ids.clear()
	mp.resume_match(saved_match_data)
	assert(mp.hole_ids.size() == 18, "Resumed match must have 18 holes")
	assert(mp.hole_ids[0] == "Hole 10", "Resumed hole 0 must be Hole 10")
	assert(mp.hole_ids[1] == "Hole 11", "Resumed hole 1 must be Hole 11")
	assert(mp.current_hole_index == 1, "Resumed current_hole_index must be 1")
	assert(not mp.players.is_empty(), "Players must be restored on resume")
	print("  PASS: resume_match accurately restored saved hole_ids and player state.")

	# Advance to Hole 3 of match (Hole 12 = Red 3)
	print("\n--- Advancing to Third Hole (Hole 12) ---")
	mp.advance_hole()
	assert(mp.current_hole_index == 2, "Expected current_hole_index=2")
	assert(mp.hole_ids[mp.current_hole_index] == "Hole 12", "Expected Hole 12")

	cp_node._on_active_player_changed(mp.get_active_player())
	assert(range_scene.current_hole_id == "Hole 12", "Range current_hole_id must be updated to Hole 12, got %s" % range_scene.current_hole_id)
	assert(range_scene.current_hole_location.x == 1300.0, "Pin location X must be 1300.0 for Hole 12, got %f" % range_scene.current_hole_location.x)
	var active_cfg_h3 = range_scene.get_active_hole_config()
	assert(active_cfg_h3.get("SubCourse") == "Red", "Active config on third hole must be Red track, got %s" % active_cfg_h3.get("SubCourse"))
	print("  PASS: Advancing after resume moves seamlessly to Hole 12.")

	print("\n=======================================================")
	print("ALL MULTI-TRACK HOLE ADVANCE TESTS PASSED SUCCESSFULLY!")
	print("=======================================================\n")
	quit(0)
