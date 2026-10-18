extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Club Tracking Lie Resistance & Aim Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	var mp = root.get_node_or_null("MultiplayerManager")
	if mp == null:
		return
	_tested = true

	var test_player = "__LieAimTester__"
	mp.clear_player_club_shot_data(test_player, "Pw")
	mp.clear_player_club_shot_data(test_player, "7i")
	mp.clear_player_club_shot_data(test_player, "Pt")

	# Ensure club tracking is enabled
	mp.set_club_averages_tracking_enabled(true)

	# ---------------------------------------------------------
	# TEST 1: Default Average Distance Fallback
	# ---------------------------------------------------------
	print("\n--- Test 1: Default Average Distance Fallback ---")
	var default_pw_yds = mp.get_player_club_average_distance_yards(test_player, "Pw")
	assert(is_equal_approx(default_pw_yds, 100.0), "Default PW average must be 100.0 yards")
	print("  PASS: Default PW average distance is 100.0 yards.")

	# ---------------------------------------------------------
	# TEST 2: Aim Distance Partial Swing Exclusion (> 10 yds less)
	# ---------------------------------------------------------
	print("\n--- Test 2: Aim Distance Partial Swing Exclusion ---")
	# Case A: PW average is 100 yds, golfer aims at 50 yds (more than 10 yds below average)
	# Raw shot with 50 yds aim distance: 50 yds / 1.09361 meters
	var shot_50_yds_aim = {
		"TotalDistance": 45.72, # ~50 yards
		"CarryDistance": 40.0,
		"TargetDistance": 50.0 / 1.09361 # Aiming 50 yards
	}
	var recorded_partial = mp.record_global_shot(test_player, "Pw", shot_50_yds_aim)
	assert(not recorded_partial, "Shot aiming 50 yards with PW (100 yd avg) must NOT be recorded")
	var pw_stats = mp.get_player_club_stats(test_player)
	assert(not pw_stats.has("Pw") or pw_stats["Pw"].is_empty(), "Partial swing shot must NOT be saved in club stats")
	print("  PASS: Shot aiming 50 yds (< 90 yds threshold for 100 yd PW) was correctly excluded.")

	# Case B: PW average is 100 yds, golfer aims at 89.9 yds (more than 10 yds below average)
	var shot_89_yds_aim = {
		"TotalDistance": 89.0 / 1.09361,
		"CarryDistance": 85.0 / 1.09361,
		"AimDistanceYards": 89.0
	}
	var recorded_89 = mp.record_global_shot(test_player, "Pw", shot_89_yds_aim)
	assert(not recorded_89, "Shot aiming 89 yards (< 90 threshold) must NOT be recorded")
	print("  PASS: Shot aiming 89 yds (more than 10 yds below avg) was excluded.")

	# Case C: PW average is 100 yds, golfer aims at 95 yds (within 10 yds of average)
	var shot_95_yds_aim = {
		"TotalDistance": 98.0 / 1.09361,
		"CarryDistance": 95.0 / 1.09361,
		"AimDistanceYards": 95.0
	}
	var recorded_95 = mp.record_global_shot(test_player, "Pw", shot_95_yds_aim)
	assert(recorded_95, "Shot aiming 95 yards (>= 90 threshold) MUST be recorded")
	pw_stats = mp.get_player_club_stats(test_player)
	assert(pw_stats.has("Pw") and pw_stats["Pw"].size() == 1, "Recorded shot must be stored in PW stats")
	print("  PASS: Shot aiming 95 yds was successfully recorded.")

	# Case D: PW average is 100 yds, golfer aims at 110 yds (greater than average)
	var shot_110_yds_aim = {
		"TotalDistance": 105.0 / 1.09361,
		"CarryDistance": 100.0 / 1.09361,
		"AimDistanceYards": 110.0
	}
	var recorded_110 = mp.record_global_shot(test_player, "Pw", shot_110_yds_aim)
	assert(recorded_110, "Shot aiming 110 yards (> avg) MUST be recorded")
	print("  PASS: Shot aiming 110 yds was successfully recorded.")

	# Case E: Putter is exempt from partial swing check
	var putt_shot = {
		"TotalDistance": 3.0 / 1.09361,
		"CarryDistance": 1.0 / 1.09361,
		"AimDistanceYards": 3.0 # Aiming 3 yds with 10 yd default putter
	}
	var recorded_putt = mp.record_global_shot(test_player, "Pt", putt_shot)
	assert(recorded_putt, "Putter shots must be exempt from partial swing full swing filter")
	print("  PASS: Putter exempt from partial swing filter.")

	# ---------------------------------------------------------
	# TEST 3: Ball Lie Resistance / Distance Reduction Normalization
	# ---------------------------------------------------------
	print("\n--- Test 3: Ball Lie Resistance Distance Normalization ---")
	mp.clear_player_club_shot_data(test_player, "7i")

	# Scenario from prompt: Golfer is in the rough with 30% reduction (0.30) and hits ball 70 yards.
	# It should store the distance as 100 since that is the actual power/distance without resistance!
	var raw_70_yds_m: float = 70.0 / 1.09361
	var raw_60_carry_m: float = 60.0 / 1.09361
	var rough_shot = {
		"TotalDistance": raw_70_yds_m,
		"CarryDistance": raw_60_carry_m,
		"Speed": 70.0, # e.g. 70 mph
		"shot_reduction": 0.30, # 30% reduction from rough
		"AimDistanceYards": 140.0 # Aiming normal distance
	}

	var recorded_rough = mp.record_global_shot(test_player, "7i", rough_shot)
	assert(recorded_rough, "Rough shot should be recorded")

	var seven_stats = mp.get_player_club_stats(test_player)["7i"]
	assert(seven_stats.size() == 1, "Must have 1 recorded shot in 7i stats")

	var stored_entry = seven_stats[0]
	var stored_total_yds = float(stored_entry["TotalDistance"]) * 1.09361
	var stored_carry_yds = float(stored_entry["CarryDistance"]) * 1.09361
	var stored_speed = float(stored_entry["Speed"])

	print("  Rough shot: raw=70.0 yds, reduction=30%% -> stored=%.2f yds (carry: %.2f yds, speed: %.2f)" % [
		stored_total_yds, stored_carry_yds, stored_speed
	])

	# 70.0 / (1.0 - 0.30) = 70.0 / 0.70 = 100.0 yards!
	assert(is_equal_approx(stored_total_yds, 100.0), "Stored total distance must be normalized to 100.0 yards!")
	# 60.0 / 0.70 = 85.71 yards
	assert(is_equal_approx(stored_carry_yds, 60.0 / 0.70), "Stored carry distance must be normalized by (1 - 0.30)!")
	# Speed: 70.0 / 0.70 = 100.0
	assert(is_equal_approx(stored_speed, 100.0), "Stored speed must be normalized by (1 - 0.30)!")

	# Verify club average calculates using normalized 100 yards
	var averages = mp.calculate_player_club_averages(test_player)
	var avg_7i_total_yds = averages["7i"]["avg_total_m"] * 1.09361
	assert(is_equal_approx(avg_7i_total_yds, 100.0), "Average 7i total distance must be 100.0 yards")
	print("  PASS: Average 7i total distance calculated as %.2f yards." % avg_7i_total_yds)

	# ---------------------------------------------------------
	# TEST 4: Clean Lie Shot (0% reduction) Unchanged
	# ---------------------------------------------------------
	print("\n--- Test 4: Clean Lie Shot Unchanged ---")
	mp.clear_player_club_shot_data(test_player, "7i")
	var fairway_shot = {
		"TotalDistance": 140.0 / 1.09361,
		"CarryDistance": 130.0 / 1.09361,
		"Speed": 105.0,
		"shot_reduction": 0.0,
		"AimDistanceYards": 140.0
	}
	var recorded_fw = mp.record_global_shot(test_player, "7i", fairway_shot)
	assert(recorded_fw, "Fairway shot should be recorded")
	var fw_entry = mp.get_player_club_stats(test_player)["7i"][0]
	var fw_total_yds = float(fw_entry["TotalDistance"]) * 1.09361
	assert(is_equal_approx(fw_total_yds, 140.0), "Clean lie total distance must remain 140.0 yards")
	print("  PASS: Clean lie shot distance remains unchanged (140.0 yds).")

	# Clean up test player data
	mp.clear_player_club_shot_data(test_player, "Pw")
	mp.clear_player_club_shot_data(test_player, "7i")
	mp.clear_player_club_shot_data(test_player, "Pt")

	print("\nALL LIE RESISTANCE & AIM DISTANCE TESTS PASSED SUCCESSFULLY! 🎉")
	quit(0)
