extends SceneTree

# Targeted verification tests for:
# 1. Glutton for Punishment achievement (all_heckles)
# 2. Tracking heard heckle voice lines
# 3. Filtering praise lines from heckles
# 4. Progress counting and unlocking

func _init() -> void:
	print("\n=======================================================")
	print("  Running Heckle Lines Achievement Verification Tests")
	print("=======================================================\n")
	
	test_heckle_achievement_definition()
	test_heckle_tracking_and_unlock()
	test_praise_lines_ignored()
	test_grand_slam_with_all_heckles()
	
	print("\n=======================================================")
	print("  ALL HECKLE ACHIEVEMENT TESTS PASSED SUCCESSFULLY! 🎉")
	print("=======================================================")
	quit(0)

func _get_test_mgr() -> Node:
	var ach_mgr = root.get_node_or_null("AchievementManager")
	if ach_mgr == null:
		ach_mgr = load("res://Utils/AchievementManager.gd").new()
		root.add_child(ach_mgr)
	return ach_mgr

func test_heckle_achievement_definition() -> void:
	print("--- Test 1: Achievement definition in DB ---")
	var mgr = _get_test_mgr()
	assert(mgr.achievements_db.has("all_heckles"), "achievements_db must have 'all_heckles'")
	var ach = mgr.achievements_db["all_heckles"]
	assert(ach["title"] == "Glutton for Punishment", "Title must be 'Glutton for Punishment'")
	assert(ach["category"] == "Special", "Category must be 'Special'")
	assert(ach["rarity"] == "Legendary", "Rarity must be 'Legendary'")
	assert(ach["badge_path"] == "res://assets/images/achievements/badge_heckle_master.svg", "Badge path must exist")
	
	var all_achs = mgr.get_all_achievements()
	var found = false
	for a in all_achs:
		if a.get("id") == "all_heckles":
			found = true
			break
	assert(found, "all_heckles must be in get_all_achievements()")
	print("  PASS: 'all_heckles' is properly defined and exposed.")

func test_heckle_tracking_and_unlock() -> void:
	print("\n--- Test 2: Tracking heard heckles and unlock trigger ---")
	var mgr = _get_test_mgr()
	var p = "HeckleListener"
	mgr._player_data[p] = {}

	var total_target = mgr.get_total_heckles_count()
	assert(total_target == 620, "Total heckle lines must be 620 (770 total - 150 praise), got %d" % total_target)
	print("  Total heckle lines identified: %d" % total_target)

	# Initially 0 heard
	assert(mgr.get_heard_heckles_count(p) == 0, "Initial heard count must be 0")
	assert(not mgr.is_unlocked(p, "all_heckles"), "Should not be unlocked initially")

	# Record a valid heckle line
	var sample_line = "res://assets/audio/heckler/ball_in_water/ball_in_water_0.wav"
	mgr.record_heckle_line_heard(p, sample_line, "ball_in_water")
	assert(mgr.get_heard_heckles_count(p) == 1, "Heard count must be 1")
	assert(not mgr.is_unlocked(p, "all_heckles"), "Should not unlock on 1 line")

	# Duplicate line should not increment
	mgr.record_heckle_line_heard(p, sample_line, "ball_in_water")
	assert(mgr.get_heard_heckles_count(p) == 1, "Duplicate line must not increment count")
	print("  PASS: Single line recorded and duplicates ignored.")

	# Simulate hearing all heckles
	var p2 = "FullHeckleMaster"
	mgr._player_data[p2] = {}
	for fp in mgr._all_heckle_filepaths.keys():
		mgr.record_heckle_line_heard(p2, fp, "")

	assert(mgr.get_heard_heckles_count(p2) == total_target, "Heard count must equal total target")
	assert(mgr.is_unlocked(p2, "all_heckles"), "'all_heckles' MUST unlock after hearing all heckle lines!")
	print("  PASS: All %d heckle lines heard successfully unlocked 'all_heckles'!" % total_target)

func test_praise_lines_ignored() -> void:
	print("\n--- Test 3: Praise lines ignored from heckle achievement ---")
	var mgr = _get_test_mgr()
	var p = "PraiseTester"
	mgr._player_data[p] = {}

	# Record praise lines
	mgr.record_heckle_line_heard(p, "res://assets/audio/heckler/good_shot_fairway/good_shot_fairway_0.wav", "good_shot_fairway")
	mgr.record_heckle_line_heard(p, "res://assets/audio/heckler/under_par/under_par_0.wav", "under_par")
	assert(mgr.get_heard_heckles_count(p) == 0, "Praise lines must not count towards heckle achievement")
	print("  PASS: Praise lines correctly ignored.")

func test_grand_slam_with_all_heckles() -> void:
	print("\n--- Test 4: Grand Slam Champion requires all_heckles ---")
	var mgr = _get_test_mgr()
	var p = "GrandSlamWithHeckles"
	mgr._player_data[p] = {}

	var all_ids = mgr.achievements_db.keys()
	# Unlock all except all_heckles and all_achievements
	for aid in all_ids:
		if aid != "all_heckles" and aid != "all_achievements":
			mgr.unlock_achievement(p, aid)

	assert(not mgr.is_unlocked(p, "all_achievements"), "all_achievements must NOT unlock without all_heckles")

	# Now unlock all_heckles
	mgr.unlock_achievement(p, "all_heckles")
	assert(mgr.is_unlocked(p, "all_achievements"), "all_achievements MUST unlock when all achievements including all_heckles are unlocked")
	print("  PASS: Grand Slam Champion successfully verified with 'all_heckles'.")
