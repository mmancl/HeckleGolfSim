extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Club Suggestion & Outlier Exclusion Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true
	
	var mp = root.get_node_or_null("MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must exist")
	
	# TEST 1: Default distances constants
	print("\n--- Test 1: Default Club Distances Constants ---")
	assert(mp.DEFAULT_CLUB_DISTANCES.has("7i"), "DEFAULT_CLUB_DISTANCES must have 7i")
	assert(mp.DEFAULT_CLUB_DISTANCES["7i"] == 140.0, "7i default must be 140")
	assert(mp.DEFAULT_CLUB_DISTANCES["Dr"] == 250.0, "Dr default must be 250")
	assert(mp.DEFAULT_CLUB_DISTANCES["3w"] == 225.0, "3w default must be 225")
	assert(mp.DEFAULT_CLUB_DISTANCES["Pw"] == 100.0, "Pw default must be 100")
	assert(mp.DEFAULT_CLUB_DISTANCES["Sw"] == 80.0, "Sw default must be 80")
	print("  PASS: Default distances correct.")
	
	# TEST 2: Shot distance extractor
	print("\n--- Test 2: Distance Extractor ---")
	assert(mp.get_shot_distance_m({"TotalDistance": 150.0, "CarryDistance": 140.0}) == 150.0, "TotalDistance preferred")
	assert(mp.get_shot_distance_m({"TotalDistance": 0.0, "CarryDistance": 140.0}) == 140.0, "CarryDistance fallback")
	assert(mp.get_shot_distance_m({}) == 0.0, "Empty dictionary returns 0.0")
	print("  PASS: Distance extraction correct.")
	
	# TEST 3: Statistical mean and standard deviation
	print("\n--- Test 3: Mean & Standard Deviation Calculation ---")
	var sample_shots = [
		{"TotalDistance": 145.0},
		{"TotalDistance": 150.0},
		{"TotalDistance": 155.0}
	]
	var stats = mp.calculate_shots_mean_and_std_dev(sample_shots)
	assert(is_equal_approx(stats["mean"], 150.0), "Mean must be 150.0")
	# Population std dev of [145, 150, 155] is sqrt((25 + 0 + 25) / 3) = sqrt(50/3) = ~4.082
	assert(stats["std_dev"] > 4.0 and stats["std_dev"] < 4.2, "Std dev must be approx 4.08")
	assert(stats["effective_std_dev"] >= 3.0, "Effective std dev must be >= 3.0")
	print("  PASS: Mean and StdDev calculation correct.")
	
	# TEST 4: Outlier detection
	print("\n--- Test 4: Outlier Detection (2 Standard Deviations) ---")
	# When shots < 3, no outlier rejection
	assert(not mp.is_shot_outlier([{"TotalDistance": 150.0}], {"TotalDistance": 10.0}), "Cannot reject outliers with < 3 shots")
	
	# With sample_shots: mean = 150, effective_std_dev = 4.082. 2 * sigma = 8.165. Acceptable range: ~[141.8, 158.2]
	# Normal shot (152m)
	assert(not mp.is_shot_outlier(sample_shots, {"TotalDistance": 152.0}), "152m should NOT be outlier")
	# Extreme mishit / duff (20m)
	assert(mp.is_shot_outlier(sample_shots, {"TotalDistance": 20.0}), "20m duff MUST be outlier")
	# Glitch shot (300m)
	assert(mp.is_shot_outlier(sample_shots, {"TotalDistance": 300.0}), "300m glitch MUST be outlier")
	print("  PASS: Outlier detection accurately flags shots outside 2 std devs.")
	
	# TEST 5: Effective distance with < 10 vs >= 10 shots
	print("\n--- Test 5: Effective Distance (10-Shot Threshold) ---")
	var test_player = "__TestPlayer__"
	# Clean any existing test data
	mp.clear_player_club_shot_data(test_player, "7i")
	mp.clear_player_club_shot_data(test_player, "4H")
	
	# 0 shots: must return default 140.0
	var eff_0 = mp.get_club_effective_distance(test_player, "7i")
	assert(is_equal_approx(eff_0, 140.0), "0 shots must return default 140.0")
	
	# Add 9 shots of 150m (approx 164.04 yards)
	for i in range(9):
		mp.record_global_shot(test_player, "7i", {"TotalDistance": 150.0, "CarryDistance": 140.0})
	
	# 9 shots: still < 10, so must STILL return default 140.0!
	var eff_9 = mp.get_club_effective_distance(test_player, "7i")
	assert(is_equal_approx(eff_9, 140.0), "9 shots must still return default 140.0")
	
	# Add 10th shot
	mp.record_global_shot(test_player, "7i", {"TotalDistance": 150.0, "CarryDistance": 140.0})
	
	# 10 shots: now >= 10, must return player average (150.0m * 1.09361 = 164.04 yards)
	var eff_10 = mp.get_club_effective_distance(test_player, "7i")
	assert(is_equal_approx(eff_10, 150.0 * 1.09361), "10 shots must return average ~164 yards")
	print("  PASS: 10-shot threshold for averages verified.")
	
	# TEST 6: Outlier blocking during record_global_shot
	print("\n--- Test 6: Outlier Blocking in record_global_shot ---")
	var pre_count = mp.get_player_club_stats(test_player)["7i"].size()
	assert(pre_count == 10, "Should have 10 shots")
	
	# Try recording a duff (15 meters)
	var recorded = mp.record_global_shot(test_player, "7i", {"TotalDistance": 15.0})
	assert(not recorded, "record_global_shot must return false for outlier")
	var post_count = mp.get_player_club_stats(test_player)["7i"].size()
	assert(post_count == 10, "Outlier must NOT be appended to stats")
	print("  PASS: Outlier shot was successfully blocked from being recorded.")
	
	# TEST 7: Club suggestion logic
	print("\n--- Test 7: Club Suggestion Rules & Dynamic Distance Matching ---")
	# Rule 1: Green / Fringe
	assert(mp.get_suggested_club(test_player, 15.0, false, true, false) == "Pt", "On green selects Pt")
	assert(mp.get_suggested_club(test_player, 25.0, false, false, true) == "Pt", "On fringe <= 35 selects Pt")
	assert(mp.get_suggested_club(test_player, 40.0, false, false, true) != "Pt", "On fringe > 35 does not select Pt")
	
	# Rule 2: Teebox Driver
	assert(mp.get_suggested_club(test_player, 350.0, true, false, false) == "Dr", "Teebox > 200 selects Dr")
	assert(mp.get_suggested_club(test_player, 160.0, true, false, false) != "Dr", "Teebox <= 200 does not select Dr")
	
	# Rule 3: For a player with default clubs:
	# 7i is now 164 yards for this player.
	# At 163 yards, 7i (164) is closer than 6i (default 160)!
	var sugg_163 = mp.get_suggested_club(test_player, 163.0, false, false, false)
	assert(sugg_163 == "7i", "163 yards should suggest 7i based on 164yd average (got %s)" % sugg_163)
	
	# At 130 yards, 8i (default 130) should be suggested
	var sugg_130 = mp.get_suggested_club(test_player, 130.0, false, false, false)
	assert(sugg_130 == "8i", "130 yards should suggest 8i (got %s)" % sugg_130)
	
	# Clean up test player data
	mp.clear_player_club_shot_data(test_player, "7i")
	mp.clear_player_club_shot_data(test_player, "4H")
	print("  PASS: Club suggestion logic working as intended.")

	# TEST 8: Stay Up Mode 35% Club Average, Teebox & Green Restrictions
	print("\n--- Test 8: Dynamic Stay Up Mode (35% Club Avg, Teebox & Green Rules) ---")
	mp.turn_order_mode = "Stay Up"
	mp.hole_ids = ["hole_1"]
	mp.current_hole_index = 0
	mp.hole_info = {"hole_1": {"Hole Location": [0.0, 300.0], "Par": 4, "Tee Boxes": {"White": [0.0, 0.0]}}}
	mp.players = [
		{
			"name": "Alice", "tee": "White", "strokes": 1, "total_strokes": 1, "position": Vector3(0, 0, 80),
			"active": true, "paused": false, "holed_out": false, "last_shot_penalty": 0,
			"last_shot_distance_yards": 80.0, "last_shot_club": "Dr", "last_shot_starting_lie": "teebox",
			"lie_type": "fairway", "shot_history": [Vector3(0, 0, 80)], "hole_scores": {}
		},
		{
			"name": "Bob", "tee": "White", "strokes": 0, "total_strokes": 0, "position": Vector3(0, 0, 0),
			"active": true, "paused": false, "holed_out": false, "last_shot_penalty": 0,
			"last_shot_distance_yards": -1.0, "last_shot_club": "", "last_shot_starting_lie": "",
			"lie_type": "teebox", "shot_history": [], "hole_scores": {}
		}
	]
	mp.active_player_index = 0

	# Alice just hit 80 yards off the teebox with Driver (<= 35% of 250yd).
	# Because it was off the teebox and Bob has not teed off yet, Alice must NEVER stay up; Bob tees off!
	var rem = mp.players.filter(func(p): return p.get("active", true) and not p.get("paused", false) and not p["holed_out"])
	mp._select_next_player_stay_up(rem)
	assert(mp.get_active_player()["name"] == "Bob", "Alice must NOT stay up off the teebox; Bob tees off next")

	# Bob tees off to 200 yards
	mp.players[1]["strokes"] = 1
	mp.players[1]["total_strokes"] = 1
	mp.players[1]["position"] = Vector3(0, 0, 200)
	mp.players[1]["lie_type"] = "fairway"
	mp.players[1]["last_shot_starting_lie"] = "teebox"
	mp.active_player_index = 1

	# Now both players have teed off. Alice is furthest (80yd vs 200yd), so Alice hits next from fairway
	mp._select_next_player_stay_up(rem)
	assert(mp.get_active_player()["name"] == "Alice", "Alice is furthest and plays next from fairway")

	# Alice takes stroke 2 from fairway with 7-Iron (default 140 yds, 35% = 49 yds) and hits 40 yds to 120 yds
	mp.players[0]["strokes"] = 2
	mp.players[0]["total_strokes"] = 2
	mp.players[0]["position"] = Vector3(0, 0, 120)
	mp.players[0]["last_shot_club"] = "7i"
	mp.players[0]["last_shot_starting_lie"] = "fairway"
	mp.players[0]["last_shot_distance_yards"] = 40.0
	mp.active_player_index = 0

	# Alice hit 40 yds (<= 49 yds) from fairway -> Alice DOES stay up!
	mp._select_next_player_stay_up(rem)
	assert(mp.get_active_player()["name"] == "Alice", "Alice should stay up after 40yd 7-Iron shot from fairway (<= 35% of 140yd)")

	# Test Green Condition:
	# Alice is on green (lie_type = "green"), Bob is on fairway (lie_type = "fairway")
	mp.players[0]["strokes"] = 3
	mp.players[0]["position"] = Vector3(0, 0, 290)
	mp.players[0]["lie_type"] = "green"
	mp.players[0]["last_shot_starting_lie"] = "fairway"
	mp.players[0]["last_shot_club"] = "Pt"
	mp.players[0]["last_shot_distance_yards"] = 4.0 # 4 yds <= 35% of 15yd putter (5.25 yds)
	mp.active_player_index = 0

	# Alice just hit a 4yd putt on green, but Bob is still in the fairway -> Alice must NOT stay up! Furthest hits (Bob).
	mp._select_next_player_stay_up(rem)
	assert(mp.get_active_player()["name"] == "Bob", "Alice should NOT stay up on green while Bob is off green")

	# Now both Alice and Bob are on the green
	mp.players[1]["lie_type"] = "green"
	mp.players[1]["position"] = Vector3(0, 0, 280)
	mp.players[0]["last_shot_starting_lie"] = "green"
	mp.active_player_index = 0
	# Alice hits 4yd putt again
	mp._select_next_player_stay_up(rem)
	assert(mp.get_active_player()["name"] == "Alice", "Alice SHOULD stay up on green when all players are on green")
	print("  PASS: Dynamic Stay Up 35% threshold, teebox & green rules verified.")
	
	print("\nALL TESTS PASSED SUCCESSFULLY! 🎉")
	quit(0)
