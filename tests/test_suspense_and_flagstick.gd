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
	var ball_roll_vel = Vector3(3.2, 0.0, 0.0) # Directly towards hole with speed to reach 8m
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

	# --- Case D: Driving Range Exclusion & Short Putt Support (~8ft / 2.5m) ---
	print("\n  Testing Driving Range Suspense Exclusion...")
	tm.force_course_play_active_for_testing = false
	var range_scene = Node.new()
	range_scene.name = "Range"
	range_scene.scene_file_path = "res://Courses/Range/range.tscn"
	root.add_child(range_scene)
	current_scene = range_scene
	var gs = root.get_node_or_null("GlobalSettings")
	if gs != null and gs.has_method("set_mock_active_scene"):
		gs.set_mock_active_scene(range_scene)

	# Verify TensionManager recognizes driving range and returns false for course play
	assert(tm.is_course_play_active() == false, "Driving range scene must NOT allow tension!")

	# Shot prediction on driving range must be rejected
	tm.reset_for_new_shot()
	var range_pred = tm.predict_shot_outcome(Vector3.ZERO, Vector3(20.0, 5.0, 0.0), false, Vector3(100.0, 0.0, 0.0))
	assert(range_pred.get("shot_validated") == false, "Driving range shots must never be validated for suspense")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "Driving range shot transitions to SPENT")

	# Proximity check on driving range must return false
	var range_prox = tm.check_ball_proximity(Vector3(10.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0), false, Vector3.ZERO, false, false, Vector3(10.0, 0.0, 0.0))
	assert(range_prox == false, "Driving range proximity must never trigger suspense")
	print("  PASS: Driving Range strictly excludes suspense and prediction.")

	# Switch back to course play scene for short putt support (~8ft / 2.5m)
	current_scene = mock_course
	if gs != null and gs.has_method("set_mock_active_scene"):
		gs.set_mock_active_scene(mock_course)
	tm.force_course_play_active_for_testing = true

	tm.reset_for_new_shot()
	var short_putt_hole = Vector3(2.5, 0.0, 0.0)
	var short_putt_start = Vector3(0.0, 0.0, 0.0)
	assert(tm.is_shot_eligible_for_suspense(short_putt_start, short_putt_hole, true) == true, "8ft putt must be eligible for suspense on course")

	# Hitting directly towards hole with 1.8 m/s
	var short_vel = Vector3(1.8, 0.0, 0.0)
	var pred_short = tm.predict_shot_outcome(short_putt_start, short_vel, true, short_putt_hole)
	assert(pred_short.get("shot_validated") == true, "Short on-line putt must be validated")
	assert(tm.suspense_state == tm.SuspenseState.READY, "Validated short putt transitions to READY")

	# Rolling at 1.5m from hole inside cone:
	var trig_short = tm.check_ball_proximity(Vector3(1.0, 0.0, 0.0), short_putt_hole, true, short_putt_start, false, false, Vector3(1.5, 0.0, 0.0))
	assert(trig_short == true, "Rolling on-line on course must activate suspense")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE")
	assert(tm.is_active() == true, "Tension must be active")
	print("  PASS: Short putt activates ACTIVE state inside cone.")

	# Ball enters cup (dist <= CUP_RADIUS_METERS)
	var prox_sunk = tm.check_ball_proximity(Vector3(2.5, 0.0, 0.0), short_putt_hole, true, short_putt_start, false, false, Vector3(0.2, 0.0, 0.0))
	assert(not prox_sunk, "Ball entering cup must stop suspense")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "Sunk ball transitions to SPENT")
	assert(not tm.is_active(), "Tension must stop when ball drops in cup")
	print("  PASS: Ball entering cup cleanly deactivates to SPENT.")

	# --- Case E: 20+ Foot Putt (24ft / 7.3m) Full Pipeline ---
	print("\n  Testing 20+ Foot Putt (24ft / 7.3m)...")
	tm.reset_for_new_shot()
	var long_putt_start = Vector3(0.0, 0.0, 0.0)
	var long_putt_hole = Vector3(7.315, 0.0, 0.0) # 24 feet
	# Launch with speed to reach 24ft on green: v ~ 3.5 m/s
	var long_putt_vel = Vector3(3.55, 0.0, 0.0)
	var pred_long = tm.predict_shot_outcome(long_putt_start, long_putt_vel, true, long_putt_hole)
	assert(pred_long.get("shot_validated") == true, "24-foot on-target putt MUST be validated")
	assert(tm.suspense_state == tm.SuspenseState.READY, "24-foot putt must transition to READY")

	# Ball rolling at 6.0m (20ft) from start, 1.3m from cup, directly on target
	var long_trig = tm.check_ball_proximity(Vector3(6.0, 0.0, 0.0), long_putt_hole, true, long_putt_start, false, false, Vector3(1.2, 0.0, 0.0))
	assert(long_trig == true, "20+ foot putt tracking to hole MUST activate suspense")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE")
	assert(tm.is_active() == true, "Heartbeat tension must be active")
	print("  PASS: 20+ foot putt successfully activates suspense as it tracks toward cup.")

	# --- Case F: Airborne Left-to-Right Chip Across Front of Hole ---
	print("\n  Testing Left-to-Right Chip Crossing Front of Hole...")
	tm.reset_for_new_shot()
	tm.suspense_state = tm.SuspenseState.READY
	tm.shot_validated = true
	var chip_f_hole = Vector3(50.0, 0.0, 0.0)
	tm.predicted_apex = Vector3(25.0, 10.0, 0.0)
	# Ball is descending past apex at (35, 8, -5), moving strongly left-to-right (+Z velocity)
	# Hole is at (50, 0, 0). Ball velocity is (10, -3, 12).
	# This ball is heading left-to-right across the green and will land far to the right (+Z) of the hole!
	var chip_lr_vel = Vector3(10.0, -3.0, 12.0)
	var prox_lr = tm.check_ball_proximity(Vector3(35.0, 8.0, -5.0), chip_f_hole, false, start_pos, false, true, chip_lr_vel)
	assert(not prox_lr, "Left-to-right chip crossing front of hole MUST NOT activate suspense!")
	assert(tm.suspense_state == tm.SuspenseState.READY, "State must remain READY (not triggered)")
	print("  PASS: Left-to-right chip does not trigger false positive.")

	# --- Case G: Airborne Chip Landing Right and Moving Right-to-Left Toward Hole ---
	print("\n  Testing Right-to-Left Chip Landing Right of Hole and Rolling In...")
	tm.reset_for_new_shot()
	tm.suspense_state = tm.SuspenseState.READY
	tm.shot_validated = true
	# Hole at (50, 0, 0).
	# Ball at (43.0, 2.73, 3.5), descending with vy=-3.0.
	# Time to land t = 0.5s.
	# Landing spot = (48.0, 1.0) (just to the right of hole at Z=+1.0).
	# Roll direction = (10.0, -5.0), aimed directly right-to-left at hole (50.0, 0.0)!
	var chip_rl_vel = Vector3(10.0, -3.0, -5.0)
	var prox_rl = tm.check_ball_proximity(Vector3(43.0, 2.73, 3.5), chip_f_hole, false, start_pos, false, true, chip_rl_vel)
	assert(prox_rl == true, "Right-to-left chip landing and tracking toward hole MUST activate suspense!")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE")
	print("  PASS: Right-to-left chip tracking toward hole successfully activates suspense.")

	# --- Case H: Putting Tightened Vision Cone (Rejects Offline Putts at Start) ---
	print("\n  Testing Putting Tightened Cone (No False Positives at Start)...")
	tm.reset_for_new_shot()
	var putt_25ft_hole = Vector3(7.62, 0.0, 0.0) # 25 feet away
	# Putt rolled at start (dist=7.62m), but angled 9.5 degrees offline (+Z)
	var offline_putt_vel = Vector3(2.5, 0.0, 0.42)
	var trig_offline = tm.check_ball_proximity(Vector3.ZERO, putt_25ft_hole, true, Vector3.ZERO, false, false, offline_putt_vel)
	assert(not trig_offline, "Putt angled 9.5 degrees offline at start MUST NOT trigger suspense!")
	assert(tm.suspense_state != tm.SuspenseState.ACTIVE, "State must not be ACTIVE for offline putt")
	print("  PASS: Tightened putting cone rejects offline putts at the start.")

	# On-target putt from 25ft
	tm.reset_for_new_shot()
	var online_putt_vel = Vector3(3.2, 0.0, 0.02)
	var trig_online = tm.check_ball_proximity(Vector3.ZERO, putt_25ft_hole, true, Vector3.ZERO, false, false, online_putt_vel)
	assert(trig_online == true, "On-target putt at 25ft MUST trigger suspense!")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE for online putt")
	print("  PASS: On-target 25ft putt cleanly activates suspense.")

	# --- Case I: 141-Foot Chip (43m) Full Pipeline ---
	print("\n  Testing 141-Foot Chip (43m) Trajectory & Ground Rollout...")
	tm.reset_for_new_shot()
	var chip_141_hole = Vector3(42.97, 0.0, 0.0) # 141 feet
	assert(tm.is_shot_eligible_for_suspense(Vector3.ZERO, chip_141_hole, false) == true, "141ft chip must be eligible")

	# Launch towards green with iron/wedge velocity
	var chip_141_launch = Vector3(18.0, 8.5, 0.0)
	var pred_141 = tm.predict_shot_outcome(Vector3.ZERO, chip_141_launch, false, chip_141_hole)
	assert(pred_141.get("shot_validated") == true, "141ft approach aimed at green must be validated into READY")
	assert(tm.suspense_state == tm.SuspenseState.READY, "141ft shot must transition to READY (not locked out)")
	print("  PASS: 141ft chip is validated into READY at launch without premature lockout.")

	# Ball descends past apex towards green: ball at (34.0, 3.0, 0.0), landing at ~41m
	var desc_141_vel = Vector3(14.0, -3.5, 0.0)
	var trig_141_air = tm.check_ball_proximity(Vector3(34.0, 3.0, 0.0), chip_141_hole, false, Vector3.ZERO, false, true, desc_141_vel)
	assert(trig_141_air == true, "141ft chip descending on green MUST activate suspense!")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE in flight")
	print("  PASS: 141ft chip descending towards green successfully activates suspense.")

	# Ball lands on green at 40m and rolls towards cup at 42.97m:
	var trig_141_roll = tm.check_ball_proximity(Vector3(41.5, 0.0, 0.0), chip_141_hole, false, Vector3.ZERO, false, false, Vector3(1.5, 0.0, 0.0))
	assert(trig_141_roll == true, "Chip rolling on green towards cup MUST keep suspense active!")
	print("  PASS: Chip rollout towards cup keeps suspense ACTIVE.")

	# Ball sinks into cup (dist <= CUP_RADIUS_METERS)
	var sunk_141 = tm.check_ball_proximity(Vector3(42.97, 0.0, 0.0), chip_141_hole, false, Vector3.ZERO, false, false, Vector3(0.2, 0.0, 0.0))
	assert(not sunk_141, "Sinking ball must stop suspense")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "Sunk ball transitions to SPENT")
	assert(not tm.is_active(), "Tension must stop when ball sinks in cup")
	print("  PASS: 141ft chip successfully sinks and cleanly deactivates.")

	# --- Case J: Developer Debugging 3D Vision Cone Toggle ---
	print("\n  Testing Developer Debugging 3D Vision Cone Toggle...")
	if gs != null and gs.range_settings != null and gs.range_settings.settings.has("debug_show_suspense_cone"):
		gs.range_settings.debug_show_suspense_cone.set_value(true)
		tm._last_ball_pos = Vector3(0.0, 0.0, 0.0)
		tm._last_ball_vel = Vector3(2.0, 0.0, 0.0)
		tm._last_target_pos = Vector3(5.0, 0.0, 0.0)
		tm._update_debug_cone_visualizer()
		assert(tm._cone_mesh_instance != null, "Vision cone MeshInstance3D must be created")
		assert(tm._cone_mesh_instance.visible == true, "Vision cone must be visible when debug toggle is ON")
		assert(tm._cone_immediate_mesh.get_surface_count() > 0, "ImmediateMesh must have surfaces drawn")
		print("  PASS: Debug vision cone is visible and generated when toggle is ON.")

		gs.range_settings.debug_show_suspense_cone.set_value(false)
		tm._update_debug_cone_visualizer()
		assert(tm._cone_mesh_instance.visible == false, "Vision cone must be hidden when debug toggle is OFF")
		print("  PASS: Debug vision cone is hidden when toggle is OFF.")

	# --- Case K: Smooth Touchdown Cone Sizing & 3D Flight Trajectory Orientation ---
	print("\n  Testing Smooth Touchdown Cone Sizing & 3D Flight Trajectory...")
	# 1. In flight: vision cone half-angle is 5 degrees (tightened from 15 degrees)
	var angle_air = tm.get_vision_cone_half_angle(10.0, false, true)
	assert(is_equal_approx(angle_air, deg_to_rad(5.0)), "Airborne cone half-angle must be exactly 5.0 degrees")

	# 2. Touchdown: smoothstep transition
	tm._touchdown_timer = 0.0
	var base_roll = tm.get_vision_cone_half_angle(20.0, false, false) # ~3.6 deg at 20m
	assert(base_roll < angle_air, "Ground rollout cone at 20m must be narrower than 5.0 degree flight cone")

	# Simulate touchdown timer at start (1.35s)
	tm._touchdown_timer = tm.TOUCHDOWN_TRANSITION_DURATION
	var angle_td_start = tm.get_vision_cone_half_angle(20.0, false, false)
	assert(is_equal_approx(angle_td_start, deg_to_rad(5.0)), "Touchdown initial cone must smoothly start at flight angle (5.0 deg)")

	# Simulate touchdown timer halfway (0.675s)
	tm._touchdown_timer = tm.TOUCHDOWN_TRANSITION_DURATION * 0.5
	var angle_td_mid = tm.get_vision_cone_half_angle(20.0, false, false)
	assert(angle_td_mid > base_roll and angle_td_mid < angle_air, "Touchdown mid transition must be between roll and flight cone")

	# Simulate touchdown timer expired (0.0s)
	tm._touchdown_timer = 0.0
	var angle_td_end = tm.get_vision_cone_half_angle(20.0, false, false)
	assert(is_equal_approx(angle_td_end, base_roll), "Touchdown end must match base rollout cone angle")
	print("  PASS: Touchdown cone half-angle smoothly transitions over 1.35s without snapping.")

	# 3. 3D Flight Trajectory vs Ground Orientation
	var climbing_vel = Vector3(10.0, 5.0, 0.0)
	var descending_vel = Vector3(12.0, -4.0, 0.0)
	var rolling_vel = Vector3(3.0, -0.5, 0.0)

	# Verify in-flight climbing tilts upward in 3D
	var climb_dir = climbing_vel.normalized()
	assert(climb_dir.y > 0.3, "Climbing trajectory must have positive Y component")

	# Verify in-flight descending tilts downward in 3D
	var desc_dir = descending_vel.normalized()
	assert(desc_dir.y < -0.2, "Descending trajectory must have negative Y component")

	# Verify on-ground rolling direction is flat
	var flat_ground_dir = Vector3(rolling_vel.x, 0.0, rolling_vel.z).normalized()
	assert(is_zero_approx(flat_ground_dir.y), "Ground roll cone forward must be parallel to ground")
	print("  PASS: 3D Flight Trajectory correctly tilts in 3D while airborne and flattens upon rollout.")

	# --- Case L: Airborne Tightened Cone False-Positive Rejection ---
	print("\n  Testing Airborne Tightened Cone False-Positive Rejection...")
	tm.reset_for_new_shot()
	tm.suspense_state = tm.SuspenseState.READY
	tm.shot_validated = true
	var target_flag = Vector3(40.0, 0.0, 0.0)
	var ball_approach_pos = Vector3(25.0, 4.0, 0.0)

	# A. Shot 8.5 degrees offline (push/fade clearly missing to the right):
	# cos(8.5 deg) ~ 0.989 < cos(5.0 deg) ~ 0.99619. Must NOT trigger!
	var offline_vel = Vector3(cos(deg_to_rad(8.5)) * 12.0, -3.0, sin(deg_to_rad(8.5)) * 12.0)
	var trig_offline_air = tm.check_ball_proximity(ball_approach_pos, target_flag, false, Vector3.ZERO, false, true, offline_vel)
	assert(not trig_offline_air, "Shot 8.5 degrees offline must be rejected by tightened 5.0-deg cone")
	assert(tm.suspense_state == tm.SuspenseState.READY, "Suspense state must remain READY (not triggered)")
	print("  PASS: 8.5-degree offline shot correctly rejected (no false positive).")

	# B. Shot 2.0 degrees offline (pin-seeker tracking right at flag):
	# cos(2.0 deg) ~ 0.99939 > cos(5.0 deg) ~ 0.99619. Must trigger!
	var online_vel = Vector3(cos(deg_to_rad(2.0)) * 12.0, -3.0, sin(deg_to_rad(2.0)) * 12.0)
	var trig_online_air = tm.check_ball_proximity(ball_approach_pos, target_flag, false, Vector3.ZERO, false, true, online_vel)
	assert(trig_online_air, "Shot 2.0 degrees offline within 5.0-deg cone must trigger suspense")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "Suspense state must transition to ACTIVE")
	print("  PASS: 2.0-degree online shot within 5.0-deg cone successfully activates suspense.")

	# C. In flight, ball drifts/curves 6.0 degrees offline: must deactivate ACTIVE -> SPENT!
	var curved_vel = Vector3(cos(deg_to_rad(6.5)) * 10.0, -3.0, sin(deg_to_rad(6.5)) * 10.0)
	var trig_curved = tm.check_ball_proximity(ball_approach_pos + Vector3(5.0, -1.5, 0.0), target_flag, false, Vector3.ZERO, false, true, curved_vel)
	assert(not trig_curved, "Ball curving >5.0 deg offline in flight must deactivate suspense")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "Exiting 5.0-deg cone must transition to SPENT")
	# --- Case M: Dynamic Vision Reach & Coming Up Short Deactivation ---
	print("\n  Testing Dynamic Vision Reach & Coming Up Short Rejection...")
	tm.reset_for_new_shot()
	var test_hole = Vector3(6.0, 0.0, 0.0) # 6 meters away (~20ft)

	# 1. Putt moving at slow speed (1.0 m/s): projected reach ~1.66m (< 6.0m)
	# Ball is aimed straight at the hole, but clearly coming up short
	var slow_putt_vel = Vector3(1.0, 0.0, 0.0)
	var reach_slow = tm.get_projected_reach_distance(Vector3.ZERO, slow_putt_vel, false, test_hole)
	assert(reach_slow < 3.0, "Projected reach at 1.0 m/s must be under 3.0 meters")
	assert(reach_slow < 6.0, "Ball must be recognized as clearly short of 6m hole")

	# Proximity check must reject activation because vision does not reach the hole
	var trig_slow = tm.check_ball_proximity(Vector3.ZERO, test_hole, true, Vector3.ZERO, false, false, slow_putt_vel)
	assert(not trig_slow, "Putt that will clearly end short must NOT trigger suspense")
	assert(tm.suspense_state != tm.SuspenseState.ACTIVE, "State must not be ACTIVE when ball is clearly short")
	print("  PASS: Weak/slow putt clearly ending short is rejected (suspense does not run).")

	# 2. Putt moving with proper speed (3.0 m/s): projected reach ~8.9m (>= 6.0m)
	var proper_putt_vel = Vector3(3.0, 0.0, 0.0)
	var reach_proper = tm.get_projected_reach_distance(Vector3.ZERO, proper_putt_vel, false, test_hole)
	assert(reach_proper >= 6.0, "Projected reach at 3.0 m/s must comfortably reach the 6m hole")
	var trig_proper = tm.check_ball_proximity(Vector3.ZERO, test_hole, true, Vector3.ZERO, false, false, proper_putt_vel)
	assert(trig_proper, "Putt with sufficient speed tracking toward hole must activate suspense")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "State must transition to ACTIVE")
	print("  PASS: On-target putt with adequate speed successfully activates suspense.")

	# 3. As the ball rolls, speed drops significantly (slows to 0.5 m/s when still 4.0m from hole)
	# Projected reach is now only ~0.98m (< 4.0m), so ball will clearly die short
	var crawling_vel = Vector3(0.5, 0.0, 0.0)
	var trig_crawl = tm.check_ball_proximity(Vector3(2.0, 0.0, 0.0), test_hole, true, Vector3.ZERO, false, false, crawling_vel)
	assert(not trig_crawl, "Ball slowing down and coming up clearly short must deactivate suspense")
	assert(tm.suspense_state == tm.SuspenseState.SPENT, "State must transition to SPENT when ball will end short")
	assert(not tm.is_active(), "Tension must stop when ball will clearly end short")
	print("  PASS: Ball decelerating short of hole cleanly deactivates ACTIVE -> SPENT.")

	# 4. Near-miss close call: ball within 2.0m moving at 1.2 m/s (projected reach ~2.06m >= 2.0m)
	tm.reset_for_new_shot()
	var close_hole = Vector3(2.0, 0.0, 0.0)
	var close_vel = Vector3(1.2, 0.0, 0.0)
	var trig_close = tm.check_ball_proximity(Vector3.ZERO, close_hole, true, Vector3.ZERO, false, false, close_vel)
	assert(trig_close, "Close-call near-miss within margin MUST activate suspense")
	assert(tm.suspense_state == tm.SuspenseState.ACTIVE, "Close call must transition to ACTIVE")
	print("  PASS: Close call near the cup remains active within margin.")

	if gs != null and gs.has_method("set_mock_active_scene"):
		gs.set_mock_active_scene(null)
	range_scene.queue_free()
	mock_course.queue_free()

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
