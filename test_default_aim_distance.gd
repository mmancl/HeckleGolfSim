extends SceneTree

class MockBall extends Node3D:
	signal rest
	var aim_yaw_offset_deg := 0.0
	var lie_type := "teebox"
	var spawn_position := Vector3.ZERO
	var is_in_sand := false
	var current_selected_club := "Dr"
	func _on_club_selected(_club): pass
	func reset(): pass
	func _update_surface_from_underneath(): pass
	func set_surface(_val): pass

class MockPlayer extends Node3D:
	signal rest
	var ball: Node3D = null
	var current_lie_type: String = "teebox"
	var current_shot_reduction := 0.0
	func reset_ball(): pass
	func get_ball_state() -> int: return 0

func _initialize():
	print("=== Running Default Aim Distance & Fairway Midpoint Tests ===")
	
	var RangeScene = load("res://Courses/Range/range.gd")
	assert(RangeScene != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.scene_file_path = "res://TestCourse/test.tscn"
	range_instance.set_script(RangeScene)

	# Mock minimal player and ball
	var player_node = MockPlayer.new()
	player_node.name = "Player"
	range_instance.add_child(player_node)

	var ball_node = MockBall.new()
	ball_node.name = "GolfBall"
	player_node.add_child(ball_node)
	player_node.ball = ball_node

	# Mock AimMarker
	var aim_marker = Marker3D.new()
	aim_marker.name = "AimMarker"
	range_instance.add_child(aim_marker)

	root.add_child(range_instance)

	# Setup hole: 520 yards away (475.488 m) along +Z
	var hole_dist_yards = 520.0
	var hole_dist_m = hole_dist_yards / 1.09361
	range_instance.current_hole_location = Vector3(0, 0, hole_dist_m)
	ball_node.global_position = Vector3(0, 0, 0)

	print("\n--- Test 1: Club Distance Calculations ---")
	var dr_dist = range_instance._get_club_effective_distance_yards("Dr")
	var w3_dist = range_instance._get_club_effective_distance_yards("3w")
	var i7_dist = range_instance._get_club_effective_distance_yards("7i")
	var pt_dist = range_instance._get_club_effective_distance_yards("Pt")
	print("  Dr distance: ", dr_dist, " yd")
	print("  3w distance: ", w3_dist, " yd")
	print("  7i distance: ", i7_dist, " yd")
	print("  Pt distance: ", pt_dist, " yd")
	assert(dr_dist >= 240.0 and dr_dist <= 260.0, "Dr should be approx 250 yd")
	assert(w3_dist >= 215.0 and w3_dist <= 235.0, "3w should be approx 225 yd")
	assert(i7_dist >= 130.0 and i7_dist <= 150.0, "7i should be approx 140 yd")
	print("  PASS: Effective club distances correct.")

	print("\n--- Test 2: Hole unreachable (520 yd Par 5 with Driver) ---")
	var aim_dr = range_instance.get_default_aim_target(ball_node.global_position, "Dr")
	var aim_dr_dist_yd = ball_node.global_position.distance_to(aim_dr) * 1.09361
	print("  Driver aim distance: ", aim_dr_dist_yd, " yd (expected ~250 yd)")
	assert(abs(aim_dr_dist_yd - dr_dist) < 1.0, "Driver aim distance should match club distance")
	assert(aim_dr.distance_to(range_instance.current_hole_location) > 50.0, "Should NOT aim at hole 520 yd away")
	print("  PASS: Unreachable hole aims at Driver distance along corridor.")

	print("\n--- Test 3: Club switching changes aim distance ---")
	var aim_3w = range_instance.get_default_aim_target(ball_node.global_position, "3w")
	var aim_3w_dist_yd = ball_node.global_position.distance_to(aim_3w) * 1.09361
	print("  3-Wood aim distance: ", aim_3w_dist_yd, " yd (expected ~225 yd)")
	assert(abs(aim_3w_dist_yd - w3_dist) < 1.0, "3w aim distance should match 3w club distance")

	var aim_7i = range_instance.get_default_aim_target(ball_node.global_position, "7i")
	var aim_7i_dist_yd = ball_node.global_position.distance_to(aim_7i) * 1.09361
	print("  7-Iron aim distance: ", aim_7i_dist_yd, " yd (expected ~140 yd)")
	assert(abs(aim_7i_dist_yd - i7_dist) < 1.0, "7i aim distance should match 7i club distance")
	print("  PASS: Switching clubs updates default aim distance accordingly.")

	print("\n--- Test 4: Hole reachable (Approach shot: 130 yd with 7i) ---")
	# Position ball 130 yards from hole
	var approach_pos = range_instance.current_hole_location - Vector3(0, 0, 130.0 / 1.09361)
	var aim_approach = range_instance.get_default_aim_target(approach_pos, "7i")
	print("  Aim target for reachable shot: ", aim_approach, " (Hole: ", range_instance.current_hole_location, ")")
	assert(aim_approach.is_equal_approx(range_instance.current_hole_location), "Should aim directly at hole when club can reach")
	print("  PASS: Reachable hole aims directly at the pin.")

	print("\n--- Test 5: Ball on green with Putter ---")
	ball_node.lie_type = "green"
	var aim_green = range_instance.get_default_aim_target(range_instance.current_hole_location - Vector3(5, 0, 0), "Pt")
	assert(aim_green.is_equal_approx(range_instance.current_hole_location), "Ball on green must aim directly at hole")
	ball_node.lie_type = "teebox"
	print("  PASS: On green aims directly at the cup.")

	print("\n--- Test 6: Fairway Midpoint Detection with Mesh Geometry ---")
	# Create fairway entry spanning X in [5, 25] and Z around 228.6m
	var fairway_body = StaticBody3D.new()
	fairway_body.name = "Fairway_Mock"
	var faces = PackedVector3Array([
		Vector3(5, 0, 200), Vector3(25, 0, 200), Vector3(25, 0, 260),
		Vector3(5, 0, 200), Vector3(25, 0, 260), Vector3(5, 0, 260)
	])
	var entry: Dictionary = {
		"body": fairway_body,
		"transform": Transform3D.IDENTITY,
		"shapes": [faces],
		"center_2d": Vector2(15, 230),
		"radius": 40.0
	}
	range_instance._cached_fairway_bodies.clear()
	range_instance._cached_fairway_bodies.append(entry)

	var mid_pt = range_instance._find_fairway_midpoint_at_radius(Vector2(0, 0), Vector2(0, 1), dr_dist / 1.09361)
	print("  Fairway midpoint found: ", mid_pt, " (Expected X around 15, Z around ", dr_dist / 1.09361, ")")
	assert(mid_pt != Vector2.ZERO, "Fairway midpoint must be detected")
	assert(mid_pt.x > 8.0 and mid_pt.x < 22.0, "Fairway midpoint X should center within fairway [5, 25]")
	assert(abs(mid_pt.length() - (dr_dist / 1.09361)) < 0.5, "Distance from ball must be equal to radius")
	print("  PASS: Fairway midpoint correctly centers inside fairway collision mesh.")

	print("\n--- Test 7: Multi-Hole Adjacent Fairway Isolation ---")
	# Configure course data with two parallel holes:
	# Hole 1 along X = 0 (Z: 0 to 475)
	# Hole 2 along X = 70 (Z: 0 to 475)
	range_instance.course_data_dict = {
		"Hole Info": {
			"Hole 1": {
				"Name": "Hole 1",
				"Par": 4,
				"Hole Location": [0.0, hole_dist_m],
				"Tee Boxes": {"Blue": [0.0, 0.0]},
				"Hole Path": [[0.0, 0.0], [0.0, hole_dist_m]]
			},
			"Hole 2": {
				"Name": "Hole 2",
				"Par": 4,
				"Hole Location": [70.0, hole_dist_m],
				"Tee Boxes": {"Blue": [70.0, 0.0]},
				"Hole Path": [[70.0, 0.0], [70.0, hole_dist_m]]
			}
		}
	}

	# Create fairway entry belonging to Hole 2 (X in [60, 80], Z in [200, 260])
	var hole2_fairway = StaticBody3D.new()
	hole2_fairway.name = "Fairway_Hole2"
	var h2_faces = PackedVector3Array([
		Vector3(60, 0, 200), Vector3(80, 0, 200), Vector3(80, 0, 260),
		Vector3(60, 0, 200), Vector3(80, 0, 260), Vector3(60, 0, 260)
	])
	var h2_entry: Dictionary = {
		"body": hole2_fairway,
		"transform": Transform3D.IDENTITY,
		"shapes": [h2_faces],
		"center_2d": Vector2(70, 230),
		"radius": 40.0
	}

	# Cache contains ONLY Hole 2's fairway (e.g. Hole 1 has rough at 250y)
	range_instance._cached_fairway_bodies.clear()
	range_instance._cached_fairway_bodies.append(h2_entry)

	# Player is on Hole 1
	range_instance.current_hole_name = "Hole 1"
	range_instance.current_hole_location = Vector3(0, 0, hole_dist_m)
	ball_node.global_position = Vector3(0, 0, 0)

	var aim_hole1 = range_instance.get_default_aim_target(ball_node.global_position, "Dr")
	print("  Aim target on Hole 1 when adjacent Hole 2 has fairway: ", aim_hole1)
	# It MUST NOT aim at Hole 2's fairway at X=70! It must stay on Hole 1's corridor (X close to 0)
	assert(abs(aim_hole1.x) < 5.0, "Should NEVER aim at adjacent Hole 2 fairway (X=70), must stay on Hole 1 (X=0)!")
	print("  PASS: Adjacent hole's fairway is rejected; aim stays on current hole's corridor.")

	print("\n--- Test 8: Active Hole Resolution on Practice / Next Hole ---")
	# Now switch to Hole 2
	range_instance.current_hole_name = "Hole 2"
	range_instance.current_hole_location = Vector3(70, 0, hole_dist_m)
	ball_node.global_position = Vector3(70, 0, 0)
	range_instance.current_practice_hole_index = 1

	var active_cfg = range_instance.get_active_hole_config()
	assert(active_cfg.get("Name") == "Hole 2", "get_active_hole_config must return Hole 2, not default to Hole 1")

	var aim_hole2 = range_instance.get_default_aim_target(ball_node.global_position, "Dr")
	print("  Aim target on Hole 2: ", aim_hole2)
	assert(abs(aim_hole2.x - 70.0) < 5.0, "Aim target on Hole 2 must be centered along Hole 2 at X=70")
	print("  PASS: Switching hole resolves correct active hole and aims at Hole 2's fairway.")

	print("\n--- Test 9: Manual Aim Preservation ---")
	range_instance.apply_default_aim("Dr")
	assert(not range_instance._aim_is_manual, "_aim_is_manual must be false after default aim")
	var manual_target = Vector3(50, range_instance.get_height(50, 100), 100)
	range_instance.set_aim_target(manual_target, false)
	assert(range_instance._aim_is_manual, "_aim_is_manual must be true after manual aim")
	assert(range_instance.aim_target_pos.is_equal_approx(manual_target), "Aim target must match manual setting")

	# Selecting club should NOT overwrite manual target
	range_instance._on_club_selected("3w")
	assert(range_instance.aim_target_pos.is_equal_approx(manual_target), "Manual aim target must be preserved on club change")

	# Resetting player / hole should reset manual flag
	range_instance._on_active_player_changed({})
	assert(not range_instance._aim_is_manual, "_aim_is_manual must be reset to false on active player change")
	print("  PASS: Manual aim is properly respected and reset.")

	print("\n--- Test 10: SW to LW Approach Aim Stability ---")
	# Position ball 75 yards from hole
	var wedge_pos = range_instance.current_hole_location - Vector3(0, 0, 75.0 / 1.09361)
	var aim_sw = range_instance.get_default_aim_target(wedge_pos, "Sw")
	var aim_lw = range_instance.get_default_aim_target(wedge_pos, "Lw")
	print("  SW aim: ", aim_sw, " | LW aim: ", aim_lw, " (Hole: ", range_instance.current_hole_location, ")")
	assert(aim_sw.is_equal_approx(range_instance.current_hole_location), "SW at 75y should aim directly at hole")
	assert(aim_lw.is_equal_approx(range_instance.current_hole_location), "LW at 75y should aim directly at hole, not twist away to fairway")
	print("  PASS: SW and LW maintain consistent aim directly to pin on approach.")

	print("\n--- Test 11: Smooth Camera Target Look (No step jump or pitch-down) ---")
	var origin = Vector3(0, 0, 0)
	var look_10m = range_instance.get_camera_target_look(Vector3(0, 0, 10), origin, false)
	var look_40m = range_instance.get_camera_target_look(Vector3(0, 0, 40), origin, false)
	var look_50m = range_instance.get_camera_target_look(Vector3(0, 0, 50), origin, false)
	var look_150m = range_instance.get_camera_target_look(Vector3(0, 0, 150), origin, false)
	print("  Look 10m: ", look_10m, " | Look 40m: ", look_40m, " | Look 50m: ", look_50m, " | Look 150m: ", look_150m)
	assert(look_10m.y >= 1.0, "Short chip look target should stay at eye level (+1.0m)")
	assert(look_40m.y >= 1.0 and look_50m.y >= 1.0, "Medium approach look targets should stay at eye level")
	assert(abs(look_40m.z - 40.0) < 0.1, "40m look target should be at 40m")
	assert(abs(look_50m.z - 50.0) < 0.1, "50m look target should be at 50m")
	assert(abs(look_150m.z - 50.0) < 0.1, "150m look target distance should smoothly cap at 50m downrange")
	print("\n--- Test 12: Driving Range Club and Target Preservation ---")
	range_instance.is_driving_range = true
	range_instance.current_hole_location = Vector3.ZERO
	range_instance._user_custom_club = "7i"
	var custom_target = Vector3(137.16, 0, 0)
	range_instance.aim_target_pos = custom_target
	range_instance._aim_is_manual = true

	assert(range_instance._get_current_club() == "7i", "Current club must be 7i before shot")
	assert(range_instance.aim_target_pos.is_equal_approx(custom_target), "Aim target must be custom_target before shot")

	# Simulate shot rest event in driving range
	await range_instance._on_golf_ball_rest({"Speed": 45.0, "TotalDistance": 160.0})

	assert(range_instance._get_current_club() == "7i", "Current club MUST remain 7i after driving range shot rest")
	assert(range_instance.aim_target_pos.is_equal_approx(custom_target), "Aim target MUST remain custom_target after driving range shot rest")
	print("  PASS: Driving Range club and aim target are successfully preserved between shots.")

	print("\n=======================================================")
	print("ALL DEFAULT AIM DISTANCE & FAIRWAY TESTS PASSED!")
	print("=======================================================\n")
	quit(0)

