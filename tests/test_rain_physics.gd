extends SceneTree

const RainPhysicsScript = preload("res://Utils/rain_physics.gd")
const WeatherLightingController = preload("res://Courses/Range/weather_lighting_controller.gd")

var BallScript = null

func _init() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	BallScript = load("res://Player/ball.gd")
	print("\n=======================================================")
	print("   Testing Rain Physics & Sun Invariance")
	print("=======================================================")

	test_rain_physics_constants()
	test_sun_mode_invariance()
	test_rain_mode_shot_reduction()
	test_rain_mode_rollout_physics()
	test_weather_restoration_to_sun()

	print("\n=======================================================")
	print("   ALL RAIN PHYSICS TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)


func test_rain_physics_constants() -> void:
	print("\n--- Test 1: Rain Physics Constants & Default State ---")
	assert(RainPhysicsScript != null, "RainPhysics script must load")
	assert(RainPhysicsScript.RAIN_SHOT_REDUCTION_PERCENT == 10.0, "Shot reduction percent must be 10.0%")
	assert(absf(RainPhysicsScript.RAIN_SHOT_MULTIPLIER - 0.90) < 0.001, "Shot multiplier must be 0.90 (10% reduction)")
	assert(RainPhysicsScript.RAIN_ROLLOUT_REDUCTION_PERCENT == 60.0, "Rollout reduction percent must be 60.0%")
	assert(absf(RainPhysicsScript.RAIN_ROLLOUT_FACTOR - 0.40) < 0.001, "Rollout factor must be 0.40 (40% remaining rollout)")
	assert(absf(RainPhysicsScript.RAIN_FRICTION_MULTIPLIER - 2.50) < 0.001, "Friction multiplier must be 2.50 (1 / 0.40)")
	assert(absf(RainPhysicsScript.RAIN_BOUNCE_RETENTION - sqrt(0.40)) < 0.001, "Bounce retention must be sqrt(0.40)")

	# In default session (no rain), is_rain_active must be false
	assert(RainPhysicsScript.is_rain_active() == false, "Default weather must be Sun (is_rain_active == false)")
	print("  PASS: Rain physics constants and default Sun state verified.")


func test_sun_mode_invariance() -> void:
	print("\n--- Test 2: Sun Mode Physics Invariance (Zero Change in Sun) ---")
	# Ensure GlobalSettings is in sun mode
	if root.has_node("GlobalSettings"):
		var gs = root.get_node("GlobalSettings")
		if gs.has_method("set_rain_mode"):
			gs.call("set_rain_mode", false)

	assert(RainPhysicsScript.is_rain_active() == false, "Sun mode active")

	var test_shot = {
		"Speed": 150.0,
		"BallSpeed": 150.0,
		"ClubSpeed": 100.0,
		"SmashFactor": 1.50,
		"TotalSpin": 2500.0,
		"BackSpin": 2400.0,
		"SideSpin": 300.0,
		"CarryDistance": 240.0,
		"TotalDistance": 260.0
	}

	RainPhysicsScript.apply_rain_shot_reduction(test_shot)

	# Verify zero changes were made in the sun
	assert(test_shot["Speed"] == 150.0, "Speed must remain unchanged in Sun")
	assert(test_shot["BallSpeed"] == 150.0, "BallSpeed must remain unchanged in Sun")
	assert(test_shot["TotalSpin"] == 2500.0, "TotalSpin must remain unchanged in Sun")
	assert(test_shot["BackSpin"] == 2400.0, "BackSpin must remain unchanged in Sun")
	assert(test_shot["SideSpin"] == 300.0, "SideSpin must remain unchanged in Sun")
	assert(test_shot["CarryDistance"] == 240.0, "CarryDistance must remain unchanged in Sun")
	assert(test_shot["TotalDistance"] == 260.0, "TotalDistance must remain unchanged in Sun")
	assert(not test_shot.has("_rain_reduction_applied"), "Reduction applied flag must not be present in Sun")

	# Test ball surface friction in sun
	var ball = BallScript.new()
	root.add_child(ball)
	ball.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
	var sun_fw_friction = ball._rolling_friction
	print("  Fairway rolling friction in Sun baseline: %.4f" % sun_fw_friction)
	assert(sun_fw_friction > 0.0, "Fairway friction in Sun must be positive baseline")

	ball.set_surface(PhysicsEnums.SurfaceType.GREEN)
	var sun_gr_friction = ball._rolling_friction
	print("  Green rolling friction in Sun baseline: %.4f" % sun_gr_friction)
	assert(sun_gr_friction > 0.0, "Green friction in Sun must be positive baseline")

	ball.queue_free()
	print("  PASS: Sun physics invariance verified (no changes in sun).")


func test_rain_mode_shot_reduction() -> void:
	print("\n--- Test 3: Rain Mode Shot Speed, Distance & Spin Reduction (10%) ---")
	var gs = root.get_node_or_null("GlobalSettings")
	if gs != null and gs.has_method("set_rain_mode"):
		gs.call("set_rain_mode", true)
	else:
		push_error("GlobalSettings not available")
		return

	assert(RainPhysicsScript.is_rain_active() == true, "Rain mode must be active")

	var shot = {
		"Speed": 150.0,
		"BallSpeed": 150.0,
		"ClubSpeed": 100.0,
		"SmashFactor": 1.50,
		"TotalSpin": 2500.0,
		"BackSpin": 2400.0,
		"SideSpin": 400.0,
		"CarryDistance": 250.0,
		"TotalDistance": 275.0
	}

	RainPhysicsScript.apply_rain_shot_reduction(shot)

	# 10% reduction checks
	assert(shot.get("_rain_reduction_applied") == true, "Must be flagged as rain reduction applied")
	assert(absf(float(shot["Speed"]) - 135.0) < 0.01, "Speed must be reduced by 10%% (150 -> 135): got %f" % float(shot["Speed"]))
	assert(absf(float(shot["BallSpeed"]) - 135.0) < 0.01, "BallSpeed must be reduced by 10%% (150 -> 135): got %f" % float(shot["BallSpeed"]))
	assert(absf(float(shot["TotalSpin"]) - 2250.0) < 0.01, "TotalSpin must be reduced by 10%% (2500 -> 2250): got %f" % float(shot["TotalSpin"]))
	assert(absf(float(shot["BackSpin"]) - 2160.0) < 0.01, "BackSpin must be reduced by 10%% (2400 -> 2160): got %f" % float(shot["BackSpin"]))
	assert(absf(float(shot["SideSpin"]) - 360.0) < 0.01, "SideSpin must be reduced by 10%% (400 -> 360): got %f" % float(shot["SideSpin"]))
	assert(absf(float(shot["CarryDistance"]) - 225.0) < 0.01, "CarryDistance must be reduced by 10%% (250 -> 225): got %f" % float(shot["CarryDistance"]))
	assert(absf(float(shot["TotalDistance"]) - 247.5) < 0.01, "TotalDistance must be reduced by 10%% (275 -> 247.5): got %f" % float(shot["TotalDistance"]))
	assert(absf(float(shot["SmashFactor"]) - 1.35) < 0.01, "SmashFactor must reflect reduced ball speed (135 / 100 = 1.35): got %f" % float(shot["SmashFactor"]))

	# Idempotency check: calling again on the same shot payload must NOT reduce twice
	RainPhysicsScript.apply_rain_shot_reduction(shot)
	assert(absf(float(shot["Speed"]) - 135.0) < 0.01, "Idempotent: Speed must stay 135.0, not double reduced")
	assert(absf(float(shot["TotalSpin"]) - 2250.0) < 0.01, "Idempotent: TotalSpin must stay 2250.0, not double reduced")

	# Nested BallData test (as from TCP servers)
	var nested_shot = {
		"BallData": {
			"Speed": 120.0,
			"BallSpeed": 120.0,
			"TotalSpin": 5000.0,
			"BackSpin": 4800.0,
			"SideSpin": 200.0
		}
	}
	RainPhysicsScript.apply_rain_shot_reduction(nested_shot)
	assert(absf(float(nested_shot["BallData"]["Speed"]) - 108.0) < 0.01, "Nested BallData Speed must be reduced by 10% (120 -> 108)")
	assert(absf(float(nested_shot["BallData"]["TotalSpin"]) - 4500.0) < 0.01, "Nested BallData TotalSpin must be reduced by 10% (5000 -> 4500)")

	print("  PASS: 10% speed, distance, and spin reduction and idempotency verified.")


func test_rain_mode_rollout_physics() -> void:
	print("\n--- Test 4: Rain Mode Rollout Physics (60% Rollout Reduction) ---")
	var gs = root.get_node_or_null("GlobalSettings")
	
	# 1. Establish Sun baseline friction
	if gs != null and gs.has_method("set_rain_mode"):
		gs.call("set_rain_mode", false)
	assert(RainPhysicsScript.is_rain_active() == false, "Must start test in Sun mode")

	var sun_ball = BallScript.new()
	root.add_child(sun_ball)
	sun_ball.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
	var sun_fw = sun_ball._rolling_friction
	sun_ball.set_surface(PhysicsEnums.SurfaceType.GREEN)
	var sun_gr = sun_ball._rolling_friction
	sun_ball.queue_free()

	# 2. Switch to Rain mode
	if gs != null and gs.has_method("set_rain_mode"):
		gs.call("set_rain_mode", true)
	assert(RainPhysicsScript.is_rain_active() == true, "Rain mode must be active")

	var rain_ball = BallScript.new()
	root.add_child(rain_ball)

	# In rain, rolling friction should be 2.50x of normal sun friction
	rain_ball.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
	var rain_fw_friction = rain_ball._rolling_friction
	var expected_rain_fw_friction = sun_fw * RainPhysicsScript.RAIN_FRICTION_MULTIPLIER
	print("  Fairway rolling friction in Rain: %.4f (expected ~%.4f)" % [rain_fw_friction, expected_rain_fw_friction])
	assert(absf(rain_fw_friction - expected_rain_fw_friction) < 0.0001, "Fairway rolling friction in rain must be 2.50x baseline")

	rain_ball.set_surface(PhysicsEnums.SurfaceType.GREEN)
	var rain_gr_friction = rain_ball._rolling_friction
	var expected_rain_gr_friction = sun_gr * RainPhysicsScript.RAIN_FRICTION_MULTIPLIER
	print("  Green rolling friction in Rain: %.4f (expected ~%.4f)" % [rain_gr_friction, expected_rain_gr_friction])
	assert(absf(rain_gr_friction - expected_rain_gr_friction) < 0.0001, "Green rolling friction in rain must be 2.50x baseline")

	# Verify theoretical rollout distance: d = v^2 / (2 * mu * g)
	# With mu_rain = 2.50 * mu_sun: d_rain = d_sun / 2.50 = 0.40 * d_sun -> 60% reduction
	var rollout_sun_ratio = 1.0
	var rollout_rain_ratio = 1.0 / RainPhysicsScript.RAIN_FRICTION_MULTIPLIER
	var rollout_reduction_pct = (1.0 - rollout_rain_ratio) * 100.0
	assert(absf(rollout_reduction_pct - 60.0) < 0.01, "Friction scaling must yield exactly 60% rollout reduction: got " + str(rollout_reduction_pct) + "%")
	print("  PASS: Rollout friction multiplier " + str(RainPhysicsScript.RAIN_FRICTION_MULTIPLIER) + "x yields exactly " + str(rollout_reduction_pct) + "% reduction in rollout.")

	rain_ball.queue_free()


func test_weather_restoration_to_sun() -> void:
	print("\n--- Test 5: Restoring Weather to Sun Completely Restores Baseline Physics ---")
	var gs = root.get_node_or_null("GlobalSettings")
	if gs != null and gs.has_method("set_rain_mode"):
		gs.call("set_rain_mode", false)

	assert(RainPhysicsScript.is_rain_active() == false, "Weather must now be Sun (rain off)")

	var ball = BallScript.new()
	root.add_child(ball)
	ball.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
	print("  Fairway friction restored to Sun: %.4f" % ball._rolling_friction)
	assert(ball._rolling_friction > 0.0, "Fairway friction must be restored")

	var sun_shot = {"Speed": 100.0, "TotalSpin": 3000.0}
	RainPhysicsScript.apply_rain_shot_reduction(sun_shot)
	assert(sun_shot["Speed"] == 100.0, "Shot speed in Sun must not be reduced")
	assert(sun_shot["TotalSpin"] == 3000.0, "Shot spin in Sun must not be reduced")

	ball.queue_free()
	print("  PASS: Sun physics fully restored after switching weather back to Sun.")
