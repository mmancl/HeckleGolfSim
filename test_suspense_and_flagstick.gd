extends SceneTree

# Test suite for Suspense Overhaul, Flagstick Collision, and Downtown Drain Achievement

class MockCourse extends Node3D:
	var current_hole_location := Vector3.ZERO
	func is_default_club_putter() -> bool: return false

func _initialize() -> void:
	print("\n=======================================================")
	print("  Running Suspense, Flagstick & Achievement Tests")
	print("=======================================================\n")
	
	test_downtown_drain_achievement()
	test_suspense_state_machine_and_cone()
	test_flagstick_collision()
	
	print("\n=======================================================")
	print("  ALL TESTS PASSED SUCCESSFULLY! 🎉")
	print("=======================================================")
	quit(0)


func test_downtown_drain_achievement() -> void:
	print("--- Test 1: Downtown Drain Achievement (Putter Requirement) ---")
	var ach_mgr = root.get_node_or_null("AchievementManager")
	var created_mgr := false
	if ach_mgr == null:
		ach_mgr = load("res://Utils/AchievementManager.gd").new()
		root.add_child(ach_mgr)
		created_mgr = true
	
	var player_name = "TestGolfer"
	if ach_mgr._player_data.has(player_name):
		ach_mgr._player_data[player_name] = {}
	
	# Scenario A: Holing out from 35 feet (11.6 yds) with a 9-iron
	ach_mgr.check_hole_achievements(player_name, 4, 3, ["green"], 11.6, true, "9i")
	assert(not ach_mgr.is_unlocked(player_name, "long_putt"), "Downtown Drain MUST NOT unlock with 9-iron!")
	print("  PASS: 9-iron from 35ft did not unlock Downtown Drain.")
	
	# Scenario B: Holing out from 35 feet (11.6 yds) with a Lob Wedge
	ach_mgr.check_hole_achievements(player_name, 4, 3, ["green"], 11.6, true, "Lw")
	assert(not ach_mgr.is_unlocked(player_name, "long_putt"), "Downtown Drain MUST NOT unlock with Lob Wedge!")
	print("  PASS: Lob Wedge from 35ft did not unlock Downtown Drain.")
	
	# Scenario C: Holing out from 8 feet (2.6 yds) with a Putter (too short)
	ach_mgr.check_hole_achievements(player_name, 4, 3, ["green"], 2.6, true, "Pt")
	assert(not ach_mgr.is_unlocked(player_name, "long_putt"), "Downtown Drain MUST NOT unlock from short range (< 30 ft)!")
	print("  PASS: Short putt (< 30ft) did not unlock Downtown Drain.")
	
	# Scenario D: Holing out from 35 feet (11.6 yds) with a Putter
	ach_mgr.check_hole_achievements(player_name, 4, 3, ["green"], 11.6, true, "Pt")
	assert(ach_mgr.is_unlocked(player_name, "long_putt"), "Downtown Drain MUST unlock with Putter from 30+ feet!")
	print("  PASS: Putter from 35ft successfully unlocked Downtown Drain.")
	
	if created_mgr:
		ach_mgr.queue_free()


func test_suspense_state_machine_and_cone() -> void:
	print("\n--- Test 2: Predictive Suspense & Vision Cone State Machine ---")
	var tm = root.get_node_or_null("TensionManager")
	var created_tm := false
	if tm == null:
		tm = load("res://Utils/TensionManager.gd").new()
		root.add_child(tm)
		created_tm = true
	
	tm.force_course_play_active_for_testing = true
	var mock_course = Node.new()
	mock_course.name = "CoursePlay"
	root.add_child(mock_course)
	current_scene = mock_course
	tm._cached_is_course_play = true
	tm._cached_scene_ref = weakref(mock_course)
	tm._cached_practice_mode = false
	tm._cached_players_empty = false
	
	# Target hole at 10m forward (+X)
	var hole_pos = Vector3(10.0, 0.0, 0.0)
	var start_pos = Vector3(0.0, 0.0, 0.0)
	
	# --- Case A: Confirmed Miss (Putt aimed 45 degrees away from hole) ---
	tm.reset_for_new_shot()
	assert(tm.suspense_state == tm.SuspenseState.IDLE, "Initial state must be IDLE")
	
	# Launch vector aimed at (3, 0, 3) - clearly misses hole at (10, 0, 0)
	var miss_vel = Vector3(3.0, 0.0, 3.0)
	var pred_miss = tm.predict_shot_outcome(start_pos, miss_vel, true, hole_pos)
	assert(pred_miss.get("shot_validated") == false, "Miss shot must NOT be validated")
	assert(pred_miss.get("will_enter_zone") == false, "Miss shot will_enter_zone must be false")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "Miss shot must transition directly to SPENT")
	
	# SPENT Latch check: check_ball_proximity must reject while in SPENT
	var prox_spent = tm.check_ball_proximity(Vector3(5.0, 0.0, 0.0), hole_pos, true, start_pos, false, false, Vector3(2.0, 0.0, 0.0))
	assert(not prox_spent, "SPENT latch must prevent suspense from triggering")
	print("  PASS: Confirmed miss immediately transitions to SPENT and latches lockout.")
	
	# --- Case B: Validated Putt & Vision Cone Tracking ---
	tm.reset_for_new_shot()
	assert(tm.suspense_state == tm.SuspenseState.IDLE, "Reset must return state to IDLE")
	
	# Launch vector aimed directly at hole with proper speed to reach 10m (v=4.15 m/s)
	var good_putt_vel = Vector3(4.15, 0.0, 0.0)
	var pred_good = tm.predict_shot_outcome(start_pos, good_putt_vel, true, hole_pos)
	assert(pred_good.get("shot_validated") == true, "Direct putt must be validated")
	assert(pred_good.get("will_enter_zone") == true, "Direct putt will_enter_zone must be true")
	assert(tm.suspense_state == tm.SuspenseState.READY, "Validated putt must be in READY state")
	print("  PASS: On-line trajectory validated and transitioned to READY state.")
	
	# Check READY -> ACTIVE when rolling inside cone towards hole
	var ball_roll_pos = Vector3(2.0, 0.0, 0.0)
	var ball_roll_vel = Vector3(2.5, 0.0, 0.0) # Directly towards hole
	var trig = tm.check_ball_proximity(ball_roll_pos, hole_pos, true, start_pos, false, false, ball_roll_vel)
	assert(trig, "Ball rolling on target must activate suspense")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE")
	assert(tm.is_active(), "Tension must be active")
	print("  PASS: READY -> ACTIVE triggered inside vision cone.")
	
	# Test Angle Loss (Slope breaks ball off-line -> exits cone)
	# Ball at (6, 0, 0), hole at (10, 0, 0), but velocity deflects 35 degrees offline (+Z)
	var break_vel = Vector3(1.2, 0.0, 1.2).normalized() * 1.5 # cos theta ~= 0.707 < cos(15 deg)
	var prox_break = tm.check_ball_proximity(Vector3(6.0, 0.0, 0.0), hole_pos, true, start_pos, false, false, break_vel)
	assert(not prox_break, "Ball breaking offline must deactivate suspense")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "Angle loss must transition to SPENT")
	assert(not tm.is_active(), "Tension must stop when hole exits cone")
	print("  PASS: Hole exiting vision cone deactivates suspense and latches to SPENT.")
	
	# Verify SPENT latch again: even if ball somehow returns towards hole, it cannot re-activate
	var prox_after = tm.check_ball_proximity(Vector3(8.0, 0.0, 0.0), hole_pos, true, start_pos, false, false, Vector3(1.0, 0.0, 0.0))
	assert(not prox_after, "SPENT latch must strictly prevent re-activation on same shot")
	print("  PASS: SPENT latch strictly verified.")
	
	# --- Case C: Airborne Shot Apex & Cone Trigger ---
	tm.reset_for_new_shot()
	tm.suspense_state = tm.SuspenseState.READY
	tm.shot_validated = true
	var chip_hole = Vector3(50.0, 0.0, 0.0) # > 30.48m (100ft) minimum chip suspense distance
	tm.predicted_apex = Vector3(25.0, 10.0, 0.0)
	tm.predicted_land_pos = Vector3(48.0, 0.0, 0.0)
	tm.predicted_land_vel = Vector3(3.0, 0.0, 0.0)
	
	# 1. Ascending (vy > 0): must NOT activate
	var prox_asc = tm.check_ball_proximity(Vector3(10.0, 5.0, 0.0), chip_hole, false, start_pos, false, true, Vector3(18.0, 5.0, 0.0))
	assert(not prox_asc, "Ascending ball must not trigger suspense")
	assert(tm.suspense_state == tm.SuspenseState.READY, "Ascending ball remains in READY")
	print("  PASS: Ascending ball correctly waits in READY before apex.")
	
	# 2. Descending past apex (vy < 0, y < apex.y): must activate
	var prox_desc = tm.check_ball_proximity(Vector3(35.0, 8.0, 0.0), chip_hole, false, start_pos, false, true, Vector3(12.0, -3.0, 0.0))
	assert(prox_desc, "Descending ball past apex aligned with cone must trigger suspense")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE")
	print("  PASS: Descending ball past apex successfully triggered ACTIVE state.")
	
	# 3. Overshoot past hole: must deactivate to SPENT
	# Hole is at (50, 0, 0), ball at (51.0, 0.0, 0.0) moving away (+X)
	var prox_over = tm.check_ball_proximity(Vector3(51.0, 0.0, 0.0), chip_hole, false, start_pos, false, false, Vector3(1.0, 0.0, 0.0))
	assert(not prox_over, "Overshoot past hole must deactivate suspense")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "Overshoot must transition to SPENT")
	print("  PASS: Overshooting past the hole deactivates to SPENT.")
	
	if created_tm:
		tm.queue_free()


func test_flagstick_collision() -> void:
	print("\n--- Test 3: Flagstick 3D Collision & Putting Pass-Through ---")
	var RangeScene = load("res://Courses/Range/range.gd")
	var range_instance = Node3D.new()
	range_instance.set_script(RangeScene)
	root.add_child(range_instance)
	
	range_instance.current_hole_location = Vector3(20.0, 0.0, 0.0)
	range_instance._spawn_flag_pin()
	
	var pin_node = range_instance.get_node_or_null("FlagPin")
	assert(pin_node != null, "FlagPin node must be spawned")
	var col_shape = pin_node.get_node_or_null("FlagstickCollider/CollisionShape") as CollisionShape3D
	assert(col_shape != null, "FlagstickCollider/CollisionShape must exist on FlagPin")
	print("  PASS: Flagstick 3D collider exists on FlagPin.")
	
	# Test normal club (Iron / Wedge / Driver): collision enabled
	range_instance.update_flagstick_collision(false)
	assert(not col_shape.disabled, "Flagstick collider must be ENABLED for normal shots")
	print("  PASS: Non-putting shots have flagstick collision enabled.")
	
	# Test putting shot: collision disabled (flag pulled)
	range_instance.update_flagstick_collision(true)
	assert(col_shape.disabled, "Flagstick collider must be DISABLED when putting (flag pulled)")
	print("  PASS: Putting shots have flagstick collision disabled (flag pulled).")
	
	# Test ball flagstick collision detection
	var ball = load("res://Player/ball.gd").new()
	root.add_child(ball)
	
	var flag_body = pin_node.get_node_or_null("FlagstickCollider")
	assert(ball._is_collider_flagstick(flag_body), "Ball must recognize flagstick collider")
	assert(ball._is_collider_flagstick(pin_node), "Ball must recognize FlagPin parent")
	print("  PASS: Ball correctly identifies flagstick collider.")
	
	ball.queue_free()
	range_instance.queue_free()
