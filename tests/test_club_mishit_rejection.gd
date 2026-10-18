extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Club Miss-Hit Rejection & 65% Cold-Start Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	var mp = root.get_node_or_null("MultiplayerManager")
	if mp == null:
		return
	_tested = true

	var test_player = "__MishitTester__"
	mp.clear_player_club_shot_data(test_player, "7i")
	mp.clear_player_club_shot_data(test_player, "Pt")

	# TEST 1: Cold-start 7-iron miss-hit rejection (The exact user scenario)
	# User hits 150 yards 3 times, but hits 70 yards twice.
	print("\n--- Test 1: User Scenario (150 yds vs 70 yds Miss-Hits) ---")
	var shot_150_m = 150.0 / 1.09361 # 137.16 m
	var shot_70_m = 70.0 / 1.09361   # 64.01 m

	# Shot 1: 150 yds -> Should be accepted
	var r1 = mp.record_global_shot(test_player, "7i", {"TotalDistance": shot_150_m})
	assert(r1, "Shot 1 (150 yds) must be accepted")

	# Shot 2: 70 yds -> Below 65% of 140 yd benchmark (91 yds) -> MUST BE REJECTED
	var r2 = mp.record_global_shot(test_player, "7i", {"TotalDistance": shot_70_m})
	assert(not r2, "Shot 2 (70 yds) must be rejected as cold-start miss-hit (< 65% benchmark)")

	# Shot 3: 150 yds -> Accepted
	var r3 = mp.record_global_shot(test_player, "7i", {"TotalDistance": shot_150_m})
	assert(r3, "Shot 3 (150 yds) must be accepted")

	# Shot 4: 70 yds -> MUST BE REJECTED
	var r4 = mp.record_global_shot(test_player, "7i", {"TotalDistance": shot_70_m})
	assert(not r4, "Shot 4 (70 yds) must be rejected as miss-hit (< 65% benchmark)")

	# Shot 5: 150 yds -> Accepted
	var r5 = mp.record_global_shot(test_player, "7i", {"TotalDistance": shot_150_m})
	assert(r5, "Shot 5 (150 yds) must be accepted")

	# Verify stored stats in player_club_stats
	var p_stats = mp.get_player_club_stats(test_player)
	assert(p_stats["7i"].size() == 3, "Only the 3 well-struck shots should be recorded (size: %d)" % p_stats["7i"].size())

	# Verify calculated averages: MUST BE 150 yards, NOT ~120 yards!
	var avgs = mp.calculate_player_club_averages(test_player)
	var avg_total_yds = avgs["7i"]["avg_total_m"] * 1.09361
	assert(is_equal_approx(avg_total_yds, 150.0), "Average 7-iron distance must be 150 yards (actual: %.1f)" % avg_total_yds)
	assert(avgs["7i"]["shot_count"] == 3, "Valid shot count must be 3")
	print("  PASS: 70-yard miss-hits were rejected at the 65% floor and average stayed at 150 yards.")

	# TEST 2: Cold-start first shot rejection
	print("\n--- Test 2: Cold-Start Shot #1 Miss-Hit Rejection ---")
	mp.clear_player_club_shot_data(test_player, "8i")
	# 8-iron benchmark is 130 yds. 65% is 84.5 yds. Shot is 50 yds (45.72 m).
	var first_duff = mp.record_global_shot(test_player, "8i", {"TotalDistance": 50.0 / 1.09361})
	assert(not first_duff, "Shot 1 duff (50 yds with 8i) must be rejected even with 0 baseline shots")
	var stats_8i = mp.get_player_club_stats(test_player).get("8i", [])
	assert(stats_8i.is_empty(), "8-iron stats must remain empty after first shot duff")
	print("  PASS: First swing duff rejected prior to baseline establishment.")

	# TEST 3: Retrospective auto-filtering of corrupted historical data
	print("\n--- Test 3: Retrospective Filtering of Corrupted Historical Data ---")
	# Simulate a legacy or unvetted array containing [150, 70, 70, 150, 150]
	var corrupted_raw = [
		{"TotalDistance": shot_150_m},
		{"TotalDistance": shot_70_m},
		{"TotalDistance": shot_70_m},
		{"TotalDistance": shot_150_m},
		{"TotalDistance": shot_150_m}
	]
	var filtered = mp.filter_valid_club_shots(corrupted_raw, "7i")
	assert(filtered.size() == 3, "Filtered shots must contain only the 3 valid 150y shots (size: %d)" % filtered.size())
	for s in filtered:
		var yds = s["TotalDistance"] * 1.09361
		assert(is_equal_approx(yds, 150.0), "Each filtered shot must be 150 yards")
	print("  PASS: Historical corrupted data retroactively filtered to prune miss-hits.")

	# TEST 4: Putter exemption
	print("\n--- Test 4: Putter Exemption ---")
	# Short putts (e.g. 2 yards) and long putts (e.g. 25 yards) must never be rejected by 65% floor
	var putt_short = mp.record_global_shot(test_player, "Pt", {"TotalDistance": 2.0 / 1.09361})
	var putt_long = mp.record_global_shot(test_player, "Pt", {"TotalDistance": 25.0 / 1.09361})
	assert(putt_short, "Short putt must be recorded")
	assert(putt_long, "Long putt must be recorded")
	var pt_stats = mp.get_player_club_stats(test_player).get("Pt", [])
	assert(pt_stats.size() == 2, "Both putts must be present in stats")
	print("  PASS: Putter shots are exempt from full-swing 65% floor.")

	# TEST 5: Median & MAD robustness vs Arithmetic Mean & Std Dev
	print("\n--- Test 5: Median & MAD Outlier Robustness ---")
	var mad_data = [
		{"TotalDistance": 137.16}, # 150y
		{"TotalDistance": 137.16}, # 150y
		{"TotalDistance": 137.16}, # 150y
		{"TotalDistance": 137.16}, # 150y
		{"TotalDistance": 137.16}  # 150y
	]
	var mad_stats = mp.calculate_shots_median_and_mad(mad_data)
	assert(is_equal_approx(mad_stats["median"], 137.16), "Median must equal 137.16m")
	assert(is_equal_approx(mad_stats["mad"], 0.0), "MAD must be 0 for identical shots")
	assert(is_equal_approx(mad_stats["effective_std_dev"], mp.MIN_EFFECTIVE_STD_DEV_METERS), "Effective scale must clamp to minimum bound")
	print("  PASS: Median & MAD statistical computations verified.")

	# Cleanup test data
	mp.clear_player_club_shot_data(test_player, "7i")
	mp.clear_player_club_shot_data(test_player, "8i")
	mp.clear_player_club_shot_data(test_player, "Pt")

	print("\nALL CLUB MISS-HIT REJECTION TESTS PASSED SUCCESSFULLY! 🎉")
	quit(0)
