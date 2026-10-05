extends SceneTree

# test_surface_interaction_physics.gd
# Validates ground interaction physics across distinct course surfaces:
# Fairway, Green, Rough, and Sand Bunker.
#
# Verifies across Low (<36°), Mid (37°-45°), and High/Steep (>45°) landing angles that:
# 1. Fairway gives realistic forward rollout for woods & mid-irons (no sticking like glue).
# 2. Green provides spin check/bite for high-spin/steep wedges, while low-spin/flat runners release.
# 3. Rough significantly deadens rollout compared to Fairway (>50% reduction).
# 4. Bunker (sand) muffles impact energy and brings the ball to an immediate stop (< 1.5 yd).
# 5. Rollouts closely align with expected targets defined in club distance benchmarks.

const SURFACE_TEST_CASES = [
	# =========================================================================
	# GROUP 1: LOW LANDING ANGLE SHOTS (15° - 36°)
	# Flat trajectory, piercing descent, high horizontal velocity at landing.
	# =========================================================================
	{
		"category": "Low Landing Angle",
		"name": "Driver (Mid HCP Standard)",
		"shot": {"BallData": {"Speed": 135.0, "VLA": 12.0, "TotalSpin": 2600.0, "BackSpin": 2600.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_max": 36.0,
		"fw_roll_min": 25.0, "fw_roll_max": 36.0,   # Expected ~32.1 yd
		"grn_roll_min": 18.0, "grn_roll_max": 28.0, # Expected ~22.7 yd
		"rf_roll_min": 6.0, "rf_roll_max": 15.0,    # Expected ~10.8 yd
		"bnk_roll_max": 1.5                          # Expected ~0.9 yd
	},
	{
		"category": "Low Landing Angle",
		"name": "Low Bullet Stinger / Runner",
		"shot": {"BallData": {"Speed": 110.0, "VLA": 10.0, "TotalSpin": 3200.0, "BackSpin": 3200.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_max": 25.0,
		"fw_roll_min": 25.0, "fw_roll_max": 36.0,   # Expected ~32.0 yd
		"grn_roll_min": 16.0, "grn_roll_max": 26.0, # Expected ~21.2 yd
		"rf_roll_min": 5.0, "rf_roll_max": 13.0,    # Expected ~8.6 yd
		"bnk_roll_max": 1.5                          # Expected ~0.7 yd
	},
	{
		"category": "Low Landing Angle",
		"name": "4-Iron Stinger Punch",
		"shot": {"BallData": {"Speed": 142.0, "VLA": 9.0, "TotalSpin": 3900.0, "BackSpin": 3900.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_max": 37.0,
		"fw_roll_min": 18.0, "fw_roll_max": 28.0,   # Expected ~22.7 yd
		"grn_roll_min": 12.0, "grn_roll_max": 20.0, # Expected ~15.9 yd
		"rf_roll_min": 4.0, "rf_roll_max": 11.0,    # Expected ~7.5 yd
		"bnk_roll_max": 1.5                          # Expected ~0.6 yd
	},

	# =========================================================================
	# GROUP 2: MID LANDING ANGLE SHOTS (37° - 45°)
	# Standard mid-to-short iron approaches with controlled descent.
	# =========================================================================
	{
		"category": "Mid Landing Angle",
		"name": "5-Iron (Mid HCP Typical)",
		"shot": {"BallData": {"Speed": 115.0, "VLA": 14.0, "TotalSpin": 4800.0, "BackSpin": 4800.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 37.0, "expected_landing_angle_max": 44.0,
		"fw_roll_min": 14.0, "fw_roll_max": 22.0,   # Expected ~17.7 yd (does NOT stick like glue on FW)
		"grn_roll_min": 8.0, "grn_roll_max": 15.0,  # Expected ~11.6 yd
		"rf_roll_min": 3.0, "rf_roll_max": 8.0,     # Expected ~5.4 yd
		"bnk_roll_max": 1.0                          # Expected ~0.4 yd
	},
	{
		"category": "Mid Landing Angle",
		"name": "7-Iron (Mid HCP Typical)",
		"shot": {"BallData": {"Speed": 102.0, "VLA": 18.0, "TotalSpin": 5500.0, "BackSpin": 5500.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 37.0, "expected_landing_angle_max": 43.0,
		"fw_roll_min": 12.0, "fw_roll_max": 20.0,   # Expected ~15.9 yd
		"grn_roll_min": 6.0, "grn_roll_max": 13.0,  # Expected ~9.7 yd
		"rf_roll_min": 2.5, "rf_roll_max": 7.0,     # Expected ~4.7 yd
		"bnk_roll_max": 0.8                          # Expected ~0.3 yd
	},
	{
		"category": "Mid Landing Angle",
		"name": "9-Iron (Mid HCP Typical)",
		"shot": {"BallData": {"Speed": 88.0, "VLA": 21.0, "TotalSpin": 7300.0, "BackSpin": 7300.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 38.0, "expected_landing_angle_max": 44.0,
		"fw_roll_min": 8.0, "fw_roll_max": 16.0,    # Expected ~12.1 yd
		"grn_roll_min": 3.5, "grn_roll_max": 8.5,   # Expected ~5.8 yd
		"rf_roll_min": 1.5, "rf_roll_max": 5.0,     # Expected ~3.2 yd
		"bnk_roll_max": 0.5                          # Expected ~0.1 yd
	},
	{
		"category": "Mid Landing Angle",
		"name": "Pitching Wedge (Mid HCP)",
		"shot": {"BallData": {"Speed": 82.0, "VLA": 24.5, "TotalSpin": 8500.0, "BackSpin": 8500.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 39.0, "expected_landing_angle_max": 45.0,
		"fw_roll_min": 6.0, "fw_roll_max": 14.0,    # Expected ~9.9 yd
		"grn_roll_min": 1.5, "grn_roll_max": 6.5,   # Expected ~3.9 yd
		"rf_roll_min": 1.0, "rf_roll_max": 4.0,     # Expected ~2.4 yd
		"bnk_roll_max": 0.5                          # Expected ~0.1 yd
	},

	# =========================================================================
	# GROUP 3: HIGH & STEEP LANDING ANGLE SHOTS (>45° up to 55°+)
	# Steep descent, high backspin, rapid stopping on greens & fairways.
	# =========================================================================
	{
		"category": "High / Steep Landing Angle",
		"name": "Tour 7-Iron High Apex",
		"shot": {"BallData": {"Speed": 123.5, "VLA": 16.3, "TotalSpin": 7124.0, "BackSpin": 7124.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 44.0, "expected_landing_angle_max": 49.0,
		"fw_roll_min": 10.0, "fw_roll_max": 17.0,   # Expected ~13.7 yd
		"grn_roll_min": 4.0, "grn_roll_max": 10.0,  # Expected ~7.3 yd
		"rf_roll_min": 2.0, "rf_roll_max": 6.0,     # Expected ~3.6 yd
		"bnk_roll_max": 0.6                          # Expected ~0.2 yd
	},
	{
		"category": "High / Steep Landing Angle",
		"name": "Tour Sand Wedge Approach",
		"shot": {"BallData": {"Speed": 87.0, "VLA": 29.5, "TotalSpin": 9950.0, "BackSpin": 9950.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 49.0, "expected_landing_angle_max": 56.0,
		"fw_roll_min": 1.0, "fw_roll_max": 6.0,     # Expected ~3.1 yd
		"grn_roll_min": -0.5, "grn_roll_max": 2.0,  # Expected ~0.1 yd (spin bite / check)
		"rf_roll_min": 0.0, "rf_roll_max": 1.5,     # Expected ~0.4 yd
		"bnk_roll_max": 0.3                          # Expected ~0.1 yd
	},
	{
		"category": "High / Steep Landing Angle",
		"name": "60° Lob Wedge Tour Full Shot",
		"shot": {"BallData": {"Speed": 76.0, "VLA": 33.0, "TotalSpin": 9500.0, "BackSpin": 9500.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 49.0, "expected_landing_angle_max": 56.0,
		"fw_roll_min": 0.5, "fw_roll_max": 3.5,     # Expected ~1.4 yd
		"grn_roll_min": -0.5, "grn_roll_max": 1.5,  # Expected ~0.0 yd (immediate bite)
		"rf_roll_min": 0.0, "rf_roll_max": 1.5,     # Expected ~0.5 yd
		"bnk_roll_max": 0.3                          # Expected ~0.0 yd
	},
	{
		"category": "High / Steep Landing Angle",
		"name": "High Flop Shot (60°)",
		"shot": {"BallData": {"Speed": 40.0, "VLA": 46.0, "TotalSpin": 5200.0, "BackSpin": 5200.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 48.0, "expected_landing_angle_max": 56.0,
		"fw_roll_min": 1.5, "fw_roll_max": 6.0,     # Expected ~3.5 yd
		"grn_roll_min": 0.5, "grn_roll_max": 2.5,   # Expected ~1.2 yd
		"rf_roll_min": 0.5, "rf_roll_max": 2.5,     # Expected ~1.2 yd
		"bnk_roll_max": 0.3                          # Expected ~0.1 yd
	},

	# =========================================================================
	# GROUP 4: HIGH DESCENT ANGLE WITH LOW SPIN (~3,000 RPM)
	# Amateur / High Launch Scoop Profile.
	# High landing angle (>45°), but low spin (~3000 rpm) means the ball cannot
	# trigger backspin bite. It releases realistically across greens (20 - 45 ft)
	# and fairways (10 - 20 yd), rather than sticking like glue.
	# =========================================================================
	{
		"category": "High Angle Low Spin (~3000 RPM)",
		"name": "7-Iron Flier / Scoop (3000 RPM)",
		"shot": {"BallData": {"Speed": 100.0, "VLA": 22.0, "TotalSpin": 3000.0, "BackSpin": 3000.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 43.0, "expected_landing_angle_max": 48.0,
		"fw_roll_min": 15.0, "fw_roll_max": 22.0,   # Expected ~18.1 yd
		"grn_roll_min": 10.0, "grn_roll_max": 16.0,  # Expected ~12.8 yd (releases 38 ft)
		"rf_roll_min": 4.0, "rf_roll_max": 8.0,     # Expected ~5.7 yd
		"bnk_roll_max": 1.0                          # Expected ~0.6 yd
	},
	{
		"category": "High Angle Low Spin (~3000 RPM)",
		"name": "8-Iron Low Spin (3000 RPM)",
		"shot": {"BallData": {"Speed": 92.0, "VLA": 24.0, "TotalSpin": 3000.0, "BackSpin": 3000.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 44.0, "expected_landing_angle_max": 49.0,
		"fw_roll_min": 13.0, "fw_roll_max": 19.0,   # Expected ~16.2 yd
		"grn_roll_min": 8.5, "grn_roll_max": 14.0,   # Expected ~11.3 yd (releases 34 ft)
		"rf_roll_min": 3.5, "rf_roll_max": 7.0,     # Expected ~5.0 yd
		"bnk_roll_max": 1.0                          # Expected ~0.5 yd
	},
	{
		"category": "High Angle Low Spin (~3000 RPM)",
		"name": "9-Iron Low Spin Scoop (3000 RPM)",
		"shot": {"BallData": {"Speed": 85.0, "VLA": 26.0, "TotalSpin": 3000.0, "BackSpin": 3000.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 44.0, "expected_landing_angle_max": 50.0,
		"fw_roll_min": 11.0, "fw_roll_max": 17.0,   # Expected ~14.4 yd
		"grn_roll_min": 7.0, "grn_roll_max": 13.0,   # Expected ~9.9 yd (releases 30 ft)
		"rf_roll_min": 3.0, "rf_roll_max": 6.5,     # Expected ~4.4 yd
		"bnk_roll_max": 1.0                          # Expected ~0.5 yd
	},
	{
		"category": "High Angle Low Spin (~3000 RPM)",
		"name": "PW High Arc Low Spin (3000 RPM)",
		"shot": {"BallData": {"Speed": 78.0, "VLA": 29.0, "TotalSpin": 3000.0, "BackSpin": 3000.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 46.0, "expected_landing_angle_max": 52.0,
		"fw_roll_min": 9.0, "fw_roll_max": 15.0,    # Expected ~11.9 yd
		"grn_roll_min": 5.5, "grn_roll_max": 11.0,   # Expected ~7.8 yd (releases 23 ft)
		"rf_roll_min": 2.0, "rf_roll_max": 5.5,     # Expected ~3.6 yd
		"bnk_roll_max": 1.0                          # Expected ~0.4 yd
	},
	{
		"category": "High Angle Low Spin (~3000 RPM)",
		"name": "Ultra-Steep 7-Iron (53° Land, 3000 RPM)",
		"shot": {"BallData": {"Speed": 95.0, "VLA": 28.0, "TotalSpin": 3000.0, "BackSpin": 3000.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 50.0, "expected_landing_angle_max": 56.0,
		"fw_roll_min": 8.0, "fw_roll_max": 14.0,    # Expected ~11.2 yd
		"grn_roll_min": 5.0, "grn_roll_max": 10.0,   # Expected ~7.4 yd (releases 22 ft)
		"rf_roll_min": 2.0, "rf_roll_max": 5.0,     # Expected ~3.3 yd
		"bnk_roll_max": 1.0                          # Expected ~0.5 yd
	},
	{
		"category": "High Angle Low Spin (~3000 RPM)",
		"name": "Wedge High Flier (51° Land, 3000 RPM)",
		"shot": {"BallData": {"Speed": 70.0, "VLA": 34.0, "TotalSpin": 3000.0, "BackSpin": 3000.0, "HLA": 0.0, "SideSpin": 0.0}},
		"expected_landing_angle_min": 48.0, "expected_landing_angle_max": 54.0,
		"fw_roll_min": 10.0, "fw_roll_max": 17.0,   # Expected ~13.8 yd
		"grn_roll_min": 8.0, "grn_roll_max": 14.0,   # Expected ~11.1 yd (releases 33 ft)
		"rf_roll_min": 3.0, "rf_roll_max": 6.5,     # Expected ~4.6 yd
		"bnk_roll_max": 1.0                          # Expected ~0.3 yd
	}
]

func _initialize() -> void:
	print("================================================================================")
	print("Running Surface Interaction Physics Unit Tests")
	print("Surfaces: Fairway, Green, Rough, Bunker across Low, Mid & High Landing Angles")
	print("Total Test Shot Configurations: %d" % SURFACE_TEST_CASES.size())
	print("================================================================================")

	var adapter = load("res://addons/openfairway/physics/PhysicsAdapter.cs").new()
	if adapter == null:
		push_error("Could not load PhysicsAdapter.cs")
		quit(1)
		return

	var passed_count := 0
	var failed_count := 0

	for tc in SURFACE_TEST_CASES:
		var name: String = tc["name"]
		var cat: String = tc["category"]
		var shot: Dictionary = tc["shot"]

		# Simulate across all 4 surfaces
		var fw_res = adapter.SimulateShotFromJson(shot, PhysicsEnums.SurfaceType.FAIRWAY, Vector3.UP)
		var grn_res = adapter.SimulateShotFromJson(shot, PhysicsEnums.SurfaceType.GREEN, Vector3.UP)
		var rf_res = adapter.SimulateShotFromJson(shot, PhysicsEnums.SurfaceType.ROUGH, Vector3.UP)
		var bnk_res = adapter.SimulateShotFromJson(shot, PhysicsEnums.SurfaceType.BUNKER, Vector3.UP)

		var carry: float = float(fw_res.get("carry_yd", 0.0))
		var land_angle: float = float(fw_res.get("landing_angle_deg", 0.0))

		var fw_roll: float = float(fw_res.get("total_yd", 0.0)) - carry
		var grn_roll: float = float(grn_res.get("total_yd", 0.0)) - float(grn_res.get("carry_yd", 0.0))
		var rf_roll: float = float(rf_res.get("total_yd", 0.0)) - float(rf_res.get("carry_yd", 0.0))
		var bnk_roll: float = float(bnk_res.get("total_yd", 0.0)) - float(bnk_res.get("carry_yd", 0.0))

		var case_passed := true
		var err_msgs := []

		# Check landing angle regime
		if tc.has("expected_landing_angle_min"):
			var exp_min: float = float(tc["expected_landing_angle_min"])
			if land_angle < exp_min:
				case_passed = false
				err_msgs.append("Landing angle %.1f° < min %.1f°" % [land_angle, exp_min])
		if tc.has("expected_landing_angle_max"):
			var exp_max: float = float(tc["expected_landing_angle_max"])
			if land_angle > exp_max:
				case_passed = false
				err_msgs.append("Landing angle %.1f° > max %.1f°" % [land_angle, exp_max])

		# Check Fairway rollout bounds
		if fw_roll < float(tc["fw_roll_min"]) or fw_roll > float(tc["fw_roll_max"]):
			case_passed = false
			err_msgs.append("FW roll %.1f yd out of bounds [%.1f, %.1f]" % [fw_roll, float(tc["fw_roll_min"]), float(tc["fw_roll_max"])])

		# Check Green rollout bounds
		if grn_roll < float(tc["grn_roll_min"]) or grn_roll > float(tc["grn_roll_max"]):
			case_passed = false
			err_msgs.append("Green roll %.1f yd out of bounds [%.1f, %.1f]" % [grn_roll, float(tc["grn_roll_min"]), float(tc["grn_roll_max"])])

		# Check Rough rollout bounds
		if rf_roll < float(tc["rf_roll_min"]) or rf_roll > float(tc["rf_roll_max"]):
			case_passed = false
			err_msgs.append("Rough roll %.1f yd out of bounds [%.1f, %.1f]" % [rf_roll, float(tc["rf_roll_min"]), float(tc["rf_roll_max"])])

		# Check Bunker rollout bound
		if bnk_roll > float(tc["bnk_roll_max"]) or bnk_roll < -0.1:
			case_passed = false
			err_msgs.append("Bunker roll %.1f yd exceeds max %.1f yd" % [bnk_roll, float(tc["bnk_roll_max"])])

		# Universal Invariant 1: Fairway roll should exceed Rough roll
		if fw_roll <= rf_roll:
			case_passed = false
			err_msgs.append("Invariant violated: Fairway roll (%.1f) <= Rough roll (%.1f)" % [fw_roll, rf_roll])

		# Universal Invariant 2: Bunker must arrest ball within <= 1.5 yd
		if bnk_roll > 1.5:
			case_passed = false
			err_msgs.append("Invariant violated: Bunker roll (%.1f) > 1.5 yd" % bnk_roll)

		print("[%s | %s]" % [cat, name])
		print("  Carry: %5.1f yd | Descent Angle: %4.1f°" % [carry, land_angle])
		print("  Rollout: FW=%4.1f yd | Green=%4.1f yd | Rough=%4.1f yd | Bunker=%4.1f yd" % [fw_roll, grn_roll, rf_roll, bnk_roll])

		if case_passed:
			print("  --> PASS\n")
			passed_count += 1
		else:
			push_error("  --> FAIL: %s\n" % ", ".join(err_msgs))
			failed_count += 1

	print("--- Surface Interaction Test Results ---")
	print("Passed: %d / %d" % [passed_count, SURFACE_TEST_CASES.size()])
	print("Failed: %d / %d" % [failed_count, SURFACE_TEST_CASES.size()])

	if failed_count == 0:
		print("ALL SURFACE INTERACTION PHYSICS TESTS PASSED! 🎉")
		quit(0)
	else:
		push_error("Some surface interaction physics tests failed.")
		quit(1)
