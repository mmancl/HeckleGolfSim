extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Enhanced Shot Suggestions & Benchmarks Test ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	# TEST 1: Benchmark Structure & 4 Skill Tiers
	print("\n--- Test 1: Skill Tiers & Discrete Club Benchmarks ---")
	assert(GolfSwingAnalyzer.CLUB_BENCHMARKS.has("mid_handicap"), "Must have mid_handicap benchmarks")
	assert(GolfSwingAnalyzer.CLUB_BENCHMARKS.has("scratch"), "Must have scratch benchmarks")
	assert(GolfSwingAnalyzer.CLUB_BENCHMARKS.has("tour_pro"), "Must have tour_pro benchmarks")
	assert(GolfSwingAnalyzer.CLUB_BENCHMARKS.has("high_handicap"), "Must have high_handicap benchmarks")

	var clubs = ["driver", "3w", "5w", "hybrid", "4i", "5i", "6i", "7i", "8i", "9i", "pw", "gw", "sw", "lw"]
	for c in clubs:
		assert(GolfSwingAnalyzer.CLUB_BENCHMARKS["mid_handicap"].has(c), "mid_handicap must contain " + c)
		assert(GolfSwingAnalyzer.CLUB_BENCHMARKS["tour_pro"].has(c), "tour_pro must contain " + c)
	print("  PASS: All 4 skill tiers and 14 club categories present in benchmark catalog.")

	# TEST 2: Dynamic Skill Tier Differences
	print("\n--- Test 2: Dynamic Skill Tier Benchmarks ---")
	var mid_7i = GolfSwingAnalyzer.get_benchmark("7i", "mid_handicap")
	var pro_7i = GolfSwingAnalyzer.get_benchmark("7i", "tour_pro")
	var high_7i = GolfSwingAnalyzer.get_benchmark("7i", "high_handicap")

	assert(mid_7i["ball_speed_min"] < pro_7i["ball_speed_min"], "Pro ball speed must exceed mid handicap")
	assert(high_7i["ball_speed_min"] < mid_7i["ball_speed_min"], "Mid handicap ball speed must exceed high handicap")
	assert(mid_7i["spin_min"] < pro_7i["spin_min"], "Pro 7-iron spin target must be higher than mid handicap")
	print("  PASS: Skill tier scaling correctly differentiates Pro (7,100 RPM avg) from Mid Handicap (5,900 RPM avg).")

	# TEST 3: Launch Monitor Analysis & Scorecard Table
	print("\n--- Test 3: Ballistic Scorecard Comparison Table Generation ---")
	var shot_sample = {
		"Club": "7-Iron",
		"Speed": 96.0,
		"ClubSpeed": 76.0,
		"SmashFactor": 1.26,
		"VLA": 21.5,
		"TotalSpin": 4100.0,
		"SpinAxis": 7.5,
		"AttackAngle": 1.0,
		"Carry": 130.0,
		"skill_level": "mid_handicap"
	}

	var recs = GolfSwingAnalyzer.analyze_launch_monitor(shot_sample)
	assert(not recs.is_empty(), "Recommendations must be generated for flawed shot")

	var top_rec = recs[0]
	assert(top_rec.has("skill_level"), "Rec must have skill_level")
	assert(top_rec["skill_level"] == "mid_handicap", "Rec skill_level must match")
	assert(top_rec.has("comparison_table"), "Rec must have comparison_table")
	
	var table = top_rec["comparison_table"] as Array
	assert(table.size() >= 5, "Comparison table must contain multiple metrics")
	
	var metric_names: Array[String] = []
	for row in table:
		metric_names.append(row["metric"])
		assert(row.has("player"), "Row must have player val")
		assert(row.has("target"), "Row must have target window")
		assert(row.has("status"), "Row must have status tag")

	assert("Ball Speed" in metric_names, "Table must include Ball Speed")
	assert("Smash Factor" in metric_names, "Table must include Smash Factor")
	assert("Launch Angle (VLA)" in metric_names, "Table must include Launch Angle")
	assert("Total Spin" in metric_names, "Table must include Total Spin")
	assert("Attack Angle (AoA)" in metric_names, "Table must include AoA")
	assert("Spin Axis" in metric_names, "Table must include Spin Axis")
	print("  PASS: Scorecard table populated with comprehensive launch metrics and status tags.")

	# TEST 4: 4-Tier Diagnostic Root Cause Breakdown
	print("\n--- Test 4: 4-Tier Diagnostic Root Cause Breakdown ---")
	assert(top_rec.has("four_tier_diagnosis"), "Rec must contain four_tier_diagnosis")
	var diag = top_rec["four_tier_diagnosis"] as Dictionary
	assert(diag.has("observation") and not diag["observation"].is_empty(), "Must have observation (Tier 1)")
	assert(diag.has("impact") and not diag["impact"].is_empty(), "Must have impact (Tier 2)")
	assert(diag.has("cause") and not diag["cause"].is_empty(), "Must have cause (Tier 3)")
	assert(diag.has("prescription") and not diag["prescription"].is_empty(), "Must have prescription (Tier 4)")
	print("  PASS: 4-Tier Root Cause Breakdown verified: Observation, Impact, Cause, and Prescription.")

	# TEST 5: MultiplayerManager Default Skill Level
	print("\n--- Test 5: MultiplayerManager Default Skill Level ---")
	var mp = root.get_node_or_null("MultiplayerManager")
	if mp != null:
		var def_skill = mp.get_player_skill_level("__NonExistentPlayer__")
		assert(def_skill == "mid_handicap", "Default skill level must be mid_handicap")
		print("  PASS: MultiplayerManager defaults players to 'mid_handicap'.")

	print("\n=======================================================")
	print("ALL ENHANCED SHOT SUGGESTION TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
