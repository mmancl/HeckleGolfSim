extends SceneTree

# Test suite for new achievements:
# 1. 18-hole 150+ strokes pity achievement (pity_150_18)
# 2. 9-hole 80+ strokes pity achievement (pity_80_9)
# 3. 20+, 40+, 50+ putt achievements (putt_20_ft, putt_40_ft, putt_50_ft)
# 4. 50+, 75+, 100+ iron chip-in achievements (chip_in_50, chip_in_75, chip_in_100)
# 5. Grand Slam Champion completion achievement (all_achievements)

func _initialize() -> void:
	print("\n=======================================================")
	print("  Running New Achievements Verification Tests")
	print("=======================================================\n")
	
	test_pity_achievements()
	test_putting_distance_achievements()
	test_iron_chip_in_achievements()
	test_grand_slam_completion_achievement()
	
	print("\n=======================================================")
	print("  ALL NEW ACHIEVEMENT TESTS PASSED SUCCESSFULLY! 🎉")
	print("=======================================================")
	quit(0)

func _get_test_mgr() -> Node:
	var ach_mgr = root.get_node_or_null("AchievementManager")
	if ach_mgr == null:
		ach_mgr = load("res://Utils/AchievementManager.gd").new()
		root.add_child(ach_mgr)
	return ach_mgr

func test_pity_achievements() -> void:
	print("--- Test 1: Pity Achievements (150+ in 18 holes, 80+ in 9 holes / front / back 9) ---")
	var mgr = _get_test_mgr()
	var p = "PityGolfer"
	mgr._player_data[p] = {}

	# 18 holes with 149 strokes -> Should NOT unlock pity_150_18
	mgr.check_round_achievements(p, 149, 18, false, 0, 75, 74)
	assert(not mgr.is_unlocked(p, "pity_150_18"), "149 strokes should NOT unlock 150+ pity")
	assert(not mgr.is_unlocked(p, "pity_80_9"), "75/74 strokes should NOT unlock 80+ 9-hole pity")
	print("  PASS: 149 strokes on 18 holes did not unlock 150+ pity.")

	# 18 holes with 150 strokes -> MUST unlock pity_150_18
	mgr.check_round_achievements(p, 150, 18, false, 0, 75, 75)
	assert(mgr.is_unlocked(p, "pity_150_18"), "150 strokes MUST unlock 150+ pity")
	print("  PASS: 150 strokes on 18 holes unlocked pity_150_18.")

	# 9-hole round with 79 strokes -> Should NOT unlock pity_80_9
	var p2 = "PityGolfer9"
	mgr._player_data[p2] = {}
	mgr.check_round_achievements(p2, 79, 9, false, 0, 79, 0)
	assert(not mgr.is_unlocked(p2, "pity_80_9"), "79 strokes should NOT unlock 80+ 9-hole pity")
	print("  PASS: 79 strokes on 9 holes did not unlock 80+ pity.")

	# 9-hole round with 82 strokes -> MUST unlock pity_80_9
	mgr.check_round_achievements(p2, 82, 9, false, 0, 82, 0)
	assert(mgr.is_unlocked(p2, "pity_80_9"), "82 strokes MUST unlock 80+ 9-hole pity")
	print("  PASS: 82 strokes on 9 holes unlocked pity_80_9.")

	# 18-hole round with Front 9 = 81 strokes, Back 9 = 45 strokes -> MUST unlock pity_80_9
	var p3 = "PityGolferSplit"
	mgr._player_data[p3] = {}
	mgr.check_round_achievements(p3, 126, 18, false, 0, 81, 45)
	assert(mgr.is_unlocked(p3, "pity_80_9"), "Front 9 with 81 strokes MUST unlock pity_80_9")
	print("  PASS: Front 9 with 81 strokes during 18-hole round unlocked pity_80_9.")

func test_putting_distance_achievements() -> void:
	print("\n--- Test 2: Putting Achievements (20+, 40+, 50+ feet) ---")
	var mgr = _get_test_mgr()
	var p = "PuttMaster"
	mgr._player_data[p] = {}

	# 15 ft putt (5.0 yds) -> None should unlock
	mgr.check_hole_achievements(p, 4, 2, ["green"], 5.0, true, "Pt")
	assert(not mgr.is_unlocked(p, "putt_20_ft"), "15 ft putt should NOT unlock 20+ ft putt")
	assert(not mgr.is_unlocked(p, "long_putt"), "15 ft putt should NOT unlock 30+ ft putt")
	assert(not mgr.is_unlocked(p, "putt_40_ft"), "15 ft putt should NOT unlock 40+ ft putt")
	assert(not mgr.is_unlocked(p, "putt_50_ft"), "15 ft putt should NOT unlock 50+ ft putt")
	print("  PASS: 15 ft putt did not unlock any long putt achievements.")

	# 22 ft putt (7.33 yds) -> putt_20_ft MUST unlock, others not
	mgr.check_hole_achievements(p, 4, 2, ["green"], 7.34, true, "Pt")
	assert(mgr.is_unlocked(p, "putt_20_ft"), "22 ft putt MUST unlock putt_20_ft")
	assert(not mgr.is_unlocked(p, "long_putt"), "22 ft putt should NOT unlock 30+ ft")
	assert(not mgr.is_unlocked(p, "putt_40_ft"), "22 ft putt should NOT unlock 40+ ft")
	assert(not mgr.is_unlocked(p, "putt_50_ft"), "22 ft putt should NOT unlock 50+ ft")
	print("  PASS: 22 ft putt unlocked putt_20_ft.")

	# 33 ft putt (11.0 yds) -> long_putt (30+ ft) MUST unlock
	mgr.check_hole_achievements(p, 4, 2, ["green"], 11.0, true, "Pt")
	assert(mgr.is_unlocked(p, "long_putt"), "33 ft putt MUST unlock long_putt")
	assert(not mgr.is_unlocked(p, "putt_40_ft"), "33 ft putt should NOT unlock 40+ ft")
	print("  PASS: 33 ft putt unlocked long_putt.")

	# 42 ft putt (14.0 yds) -> putt_40_ft MUST unlock
	mgr.check_hole_achievements(p, 4, 2, ["green"], 14.0, true, "Pt")
	assert(mgr.is_unlocked(p, "putt_40_ft"), "42 ft putt MUST unlock putt_40_ft")
	assert(not mgr.is_unlocked(p, "putt_50_ft"), "42 ft putt should NOT unlock 50+ ft")
	print("  PASS: 42 ft putt unlocked putt_40_ft.")

	# 55 ft putt (18.33 yds) -> putt_50_ft MUST unlock
	mgr.check_hole_achievements(p, 4, 2, ["green"], 18.34, true, "Pt")
	assert(mgr.is_unlocked(p, "putt_50_ft"), "55 ft putt MUST unlock putt_50_ft")
	print("  PASS: 55 ft putt unlocked putt_50_ft.")

	# Non-putter test: 55 ft shot holed with wedge should NOT unlock putt achievements
	var p_wedge = "WedgeGolfer"
	mgr._player_data[p_wedge] = {}
	mgr.check_hole_achievements(p_wedge, 4, 2, ["green"], 18.34, true, "Pw")
	assert(not mgr.is_unlocked(p_wedge, "putt_20_ft"), "Pw should not unlock putt_20_ft")
	assert(not mgr.is_unlocked(p_wedge, "putt_50_ft"), "Pw should not unlock putt_50_ft")
	print("  PASS: Pw cannot unlock putt achievements.")

func test_iron_chip_in_achievements() -> void:
	print("\n--- Test 3: Iron Chip-In Achievements (50+, 75+, 100+ yards, only with iron) ---")
	var mgr = _get_test_mgr()
	var p = "IronGolfer"
	mgr._player_data[p] = {}

	# Test iron club validation
	assert(mgr.is_iron_club("7i"), "7i must be iron")
	assert(mgr.is_iron_club("5-Iron"), "5-Iron must be iron")
	assert(mgr.is_iron_club("3 Iron"), "3 Iron must be iron")
	assert(mgr.is_iron_club("9i"), "9i must be iron")
	assert(not mgr.is_iron_club("Dr"), "Dr must NOT be iron")
	assert(not mgr.is_iron_club("3w"), "3w must NOT be iron")
	assert(not mgr.is_iron_club("4H"), "4H must NOT be iron")
	assert(not mgr.is_iron_club("Pw"), "Pw must NOT be iron")
	assert(not mgr.is_iron_club("Sw"), "Sw must NOT be iron")
	assert(not mgr.is_iron_club("Lw"), "Lw must NOT be iron")
	assert(not mgr.is_iron_club("Pt"), "Pt must NOT be iron")
	print("  PASS: Iron classification verified for all club types.")

	# Case A: 45 yard chip-in with 8i -> Too short for 50+
	mgr.check_hole_achievements(p, 4, 2, ["fairway"], 0.0, true, "8i", 45.0)
	assert(not mgr.is_unlocked(p, "chip_in_50"), "45 yds should NOT unlock chip_in_50")
	assert(not mgr.is_unlocked(p, "chip_in_75"), "45 yds should NOT unlock chip_in_75")
	assert(not mgr.is_unlocked(p, "chip_in_100"), "45 yds should NOT unlock chip_in_100")
	print("  PASS: 45 yard 8i chip did not unlock chip-in achievements.")

	# Case B: 60 yard chip-in with 9i -> MUST unlock chip_in_50, but not 75 or 100
	mgr.check_hole_achievements(p, 4, 2, ["fairway"], 0.0, true, "9i", 60.0)
	assert(mgr.is_unlocked(p, "chip_in_50"), "60 yds 9i MUST unlock chip_in_50")
	assert(not mgr.is_unlocked(p, "chip_in_75"), "60 yds should NOT unlock chip_in_75")
	assert(not mgr.is_unlocked(p, "chip_in_100"), "60 yds should NOT unlock chip_in_100")
	print("  PASS: 60 yard 9i chip unlocked chip_in_50.")

	# Case C: 85 yard chip-in with 7i -> MUST unlock chip_in_75
	mgr.check_hole_achievements(p, 4, 2, ["rough"], 0.0, true, "7i", 85.0)
	assert(mgr.is_unlocked(p, "chip_in_75"), "85 yds 7i MUST unlock chip_in_75")
	assert(not mgr.is_unlocked(p, "chip_in_100"), "85 yds should NOT unlock chip_in_100")
	print("  PASS: 85 yard 7i chip unlocked chip_in_75.")

	# Case D: 140 yard hole out with 6i -> MUST unlock chip_in_100
	mgr.check_hole_achievements(p, 4, 2, ["fairway"], 0.0, true, "6i", 140.0)
	assert(mgr.is_unlocked(p, "chip_in_100"), "140 yds 6i MUST unlock chip_in_100")
	print("  PASS: 140 yard 6i hole out unlocked chip_in_100.")

	# Case E: 110 yard hole out with Pitching Wedge (Pw) -> MUST NOT unlock chip_in (iron only)
	var p_wedge = "WedgeHoleOut"
	mgr._player_data[p_wedge] = {}
	mgr.check_hole_achievements(p_wedge, 4, 2, ["fairway"], 0.0, true, "Pw", 110.0)
	assert(not mgr.is_unlocked(p_wedge, "chip_in_50"), "Pw MUST NOT unlock chip_in_50")
	assert(not mgr.is_unlocked(p_wedge, "chip_in_75"), "Pw MUST NOT unlock chip_in_75")
	assert(not mgr.is_unlocked(p_wedge, "chip_in_100"), "Pw MUST NOT unlock chip_in_100")
	print("  PASS: 110 yard Pw wedge hole-out correctly rejected for iron-only chip-in achievements.")

func test_grand_slam_completion_achievement() -> void:
	print("\n--- Test 4: Grand Slam Champion (Unlock All Achievements) ---")
	var mgr = _get_test_mgr()
	var p = "GrandSlamGolfer"
	mgr._player_data[p] = {}

	var all_ids = mgr.achievements_db.keys()
	var non_meta_ids: Array[String] = []
	for aid in all_ids:
		if aid != "all_achievements":
			non_meta_ids.append(aid)

	print("  Total achievements in DB: %d (Meta target: %d)" % [all_ids.size(), non_meta_ids.size()])

	# Unlock all except the last one
	for i in range(non_meta_ids.size() - 1):
		mgr.unlock_achievement(p, non_meta_ids[i])

	assert(not mgr.is_unlocked(p, "all_achievements"), "all_achievements MUST NOT unlock before the final achievement")
	print("  PASS: %d/%d achievements unlocked; all_achievements not yet triggered." % [non_meta_ids.size() - 1, non_meta_ids.size()])

	# Unlock the final required achievement
	var last_id = non_meta_ids[non_meta_ids.size() - 1]
	mgr.unlock_achievement(p, last_id)

	assert(mgr.is_unlocked(p, "all_achievements"), "all_achievements MUST unlock automatically once 100% completed!")
	print("  PASS: Unlocking '%s' automatically triggered Grand Slam Champion (all_achievements)!" % last_id)
