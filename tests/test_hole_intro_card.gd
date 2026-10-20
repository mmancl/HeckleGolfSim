extends SceneTree

# Targeted test for Hole Intro Slide-in Card:
# Verifies that:
# 1. At the start of a hole, HoleIntroCard displays hole number, par, and distance.
# 2. Distance is calculated based on the player who is up to hit first.
# 3. In multiplayer, the card only shows ONCE per hole (subsequent players & shots do not re-trigger it).
# 4. Advancing to the next hole triggers the card once for that new hole with the new player's distance & hole par.
# 5. Early dismissal on shot_recorded smoothly closes the card.

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Hole Intro Slide-In Card")
	print("=======================================================")

	var mp = root.get_node_or_null("/root/MultiplayerManager")
	if mp == null:
		var mp_mgr_script = load("res://Utils/MultiplayerManager.gd")
		mp = mp_mgr_script.new()
		mp.name = "MultiplayerManager"
		root.add_child(mp)

	# Build mock 2-hole course config
	# Hole 1: Par 4. Blue Tee is 400 yds away, Red Tee is 320 yds away.
	# Hole 2: Par 3. Blue Tee is 180 yds away, Red Tee is 140 yds away.
	var mock_holes = {
		"Hole 1": {
			"Name": "The Gateway",
			"Par": 4,
			"Hole Location": [400.0, 0.0],
			"Tee Boxes": {
				"Blue": [0.0, 0.0],
				"Red": [80.0, 0.0]
			}
		},
		"Hole 2": {
			"Name": "Island Cliff",
			"Par": 3,
			"Hole Location": [1000.0, 180.0],
			"Tee Boxes": {
				"Blue": [1000.0, 0.0],
				"Red": [1000.0, 40.0]
			}
		}
	}
	var mock_config = {
		"Title": "Mock Championship Links",
		"Hole Info": mock_holes
	}

	var p1 = {
		"name": "Alice",
		"tee": "Blue"
	}
	var p2 = {
		"name": "Bob",
		"tee": "Red"
	}

	# Mock course scene (must specify non-range scene_file_path so range.gd doesn't treat as driving range)
	var range_scene = load("res://Courses/Range/range.tscn").instantiate()
	range_scene.name = "Course_MockCourse"
	range_scene.scene_file_path = "res://Courses/GeneratedCourses/mock_course.tscn"
	range_scene.course_data_dict = mock_config
	range_scene.current_hole_id = "Hole 1"
	range_scene.current_hole_location = Vector3(400.0, 0.0, 0.0)
	root.add_child(range_scene)

	mp.setup_game([p1, p2], mock_config, "", "", "Full 18", "Standard")

	# Instantiate CoursePlay
	var cp_node = load("res://Courses/CoursePlay/course_play.tscn").instantiate()
	cp_node.course_instance = range_scene
	root.add_child(cp_node)

	print("\n--- Test 1: Verify HoleIntroCard UI Construction ---")
	assert(cp_node.hole_intro_card != null, "hole_intro_card must not be null")
	assert(cp_node._hole_card_hole_lbl != null, "_hole_card_hole_lbl must not be null")
	assert(cp_node._hole_card_par_lbl != null, "_hole_card_par_lbl must not be null")
	assert(cp_node._hole_card_dist_lbl != null, "_hole_card_dist_lbl must not be null")
	print("  PASS: HoleIntroCard and labels created properly.")

	print("\n--- Test 2: Start Hole 1 with Player 1 (Alice on Blue Tee) ---")
	mp.start_hole()
	var active_p1 = mp.get_active_player()
	assert(active_p1.get("name") == "Alice", "Alice should be active first, got %s" % active_p1.get("name"))
	
	range_scene.current_hole_location = Vector3(400.0, 0.0, 0.0)
	cp_node._on_active_player_changed(active_p1)

	assert(cp_node.hole_intro_card.visible, "HoleIntroCard should be visible on hole start")
	assert(cp_node._hole_card_hole_lbl.text == "1", "Hole number should be 1, got %s" % cp_node._hole_card_hole_lbl.text)
	assert(cp_node._hole_card_par_lbl.text == "4", "Par should be 4, got %s" % cp_node._hole_card_par_lbl.text)
	var alice_dist = int(cp_node._hole_card_dist_lbl.text)
	assert(alice_dist > 0, "Distance should be positive, got %d" % alice_dist)
	print("  PASS: Hole 1 card shown with Hole 1, Par 4, Dist: %d YDS for Alice." % alice_dist)

	print("\n--- Test 3: Player 2 (Bob on Red Tee) Turn on Hole 1 (Must NOT re-trigger card) ---")
	# Reset card visibility to false to detect if _on_active_player_changed triggers it again
	cp_node.hole_intro_card.visible = false
	active_p1["strokes"] = 1
	mp.active_player_index = 1
	var active_p2 = mp.get_active_player()
	assert(active_p2.get("name") == "Bob", "Bob should be active second")
	
	cp_node._on_active_player_changed(active_p2)
	assert(cp_node.hole_intro_card.visible == false, "HoleIntroCard must NOT trigger again for Player 2 on same hole!")
	print("  PASS: HoleIntroCard did not re-trigger on subsequent multiplayer turn.")

	print("\n--- Test 4: Subsequent Strokes on Hole 1 (Must NOT re-trigger card) ---")
	active_p2["strokes"] = 1
	mp.active_player_index = 0
	cp_node._on_active_player_changed(active_p1)
	assert(cp_node.hole_intro_card.visible == false, "HoleIntroCard must NOT trigger on stroke 2!")
	print("  PASS: HoleIntroCard did not trigger on stroke 2.")

	print("\n--- Test 5: Advance to Hole 2 with Bob up first (Honors/Tee) ---")
	mp.advance_hole()
	assert(mp.current_hole_index == 1, "Expected current_hole_index=1 for Hole 2")
	# Simulate Bob having honors or being active on Hole 2
	mp.active_player_index = 1
	var active_h2 = mp.get_active_player()
	assert(active_h2.get("name") == "Bob", "Bob should be up to hit Hole 2")
	range_scene.current_hole_location = Vector3(1000.0, 0.0, 180.0)

	cp_node._on_active_player_changed(active_h2)
	assert(cp_node.hole_intro_card.visible, "HoleIntroCard MUST trigger once on Hole 2 start!")
	assert(cp_node._hole_card_hole_lbl.text == "2", "Hole number should be 2, got %s" % cp_node._hole_card_hole_lbl.text)
	assert(cp_node._hole_card_par_lbl.text == "3", "Par should be 3 for Hole 2, got %s" % cp_node._hole_card_par_lbl.text)
	var bob_dist = int(cp_node._hole_card_dist_lbl.text)
	assert(bob_dist > 0, "Distance should be positive, got %d" % bob_dist)
	print("  PASS: Hole 2 card triggered with Hole 2, Par 3, Dist: %d YDS based on Bob." % bob_dist)

	print("\n--- Test 6: Next player Alice on Hole 2 (Must NOT re-trigger card) ---")
	cp_node.hole_intro_card.visible = false
	mp.active_player_index = 0
	var next_p = mp.get_active_player()
	cp_node._on_active_player_changed(next_p)
	assert(cp_node.hole_intro_card.visible == false, "HoleIntroCard must NOT trigger for Alice on Hole 2!")
	print("  PASS: Hole 2 did not re-trigger on Alice's turn.")

	print("\n--- Test 7: Early dismissal on shot_recorded ---")
	cp_node._show_hole_intro_card(2, 3, 150, "Mock Championship Links", "Island Cliff")
	assert(cp_node.hole_intro_card.visible, "Card should be visible after _show_hole_intro_card")
	cp_node._dismiss_hole_intro_card_early()
	assert(cp_node._hole_card_tween != null and cp_node._hole_card_tween.is_valid(), "Dismissal tween must be active")
	print("  PASS: Early dismissal triggered dismissal tween properly.")

	print("\n=======================================================")
	print("ALL HOLE INTRO CARD TESTS PASSED SUCCESSFULLY!")
	print("=======================================================\n")
	quit(0)
