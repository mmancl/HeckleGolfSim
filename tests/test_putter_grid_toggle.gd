extends SceneTree

class MockBall extends Node:
	signal rest
	var aim_yaw_offset_deg := 0.0
	var lie_type := "fairway"
	var spawn_position := Vector3.ZERO
	var global_position := Vector3.ZERO
	var position := Vector3.ZERO
	var is_in_sand := false
	var is_putt := false
	var current_selected_club := "7i"
	var state := 0
	func _on_club_selected(club): current_selected_club = club
	func reset(): pass
	func _update_surface_from_underneath(): pass
	func set_surface(_val): pass

class MockPlayer extends Node:
	signal rest
	var ball: Node = null
	var current_lie_type: String = "fairway"
	var current_shot_reduction := 0.0
	func reset_ball(): pass
	func get_ball_state() -> int: return 0
	func reset_shot_data(): pass
	func clear_tracers(): pass

func _initialize():
	print("=== Running Putter Default Selection & Green Grid Auto-Toggle Tests ===")
	
	var RangeScene = load("res://Courses/Range/range.gd")
	assert(RangeScene != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.scene_file_path = "res://TestCourse/test.tscn"
	range_instance.set_script(RangeScene)

	var player_node = MockPlayer.new()
	player_node.name = "Player"
	range_instance.add_child(player_node)

	var ball_node = MockBall.new()
	ball_node.name = "GolfBall"
	player_node.add_child(ball_node)
	player_node.ball = ball_node

	var aim_marker = Marker3D.new()
	aim_marker.name = "AimMarker"
	range_instance.add_child(aim_marker)

	root.add_child(range_instance)

	# Set hole location at Vector3(0, 0, 100) (approx 109 yards)
	range_instance.current_hole_location = Vector3(0, 0, 100)
	ball_node.global_position = Vector3(0, 0, 0)

	# Test 1: Fairway far from green -> default club is not putter, grid is false
	print("\n--- Test 1: Fairway lie (109 yards) ---")
	ball_node.lie_type = "fairway"
	player_node.current_lie_type = "fairway"
	var def_club = range_instance.get_default_club()
	print("  Default club: ", def_club)
	assert(def_club != "Pt", "Fairway 109 yards should not select putter")
	assert(not range_instance.is_default_club_putter(), "is_default_club_putter must be false on fairway")
	range_instance.update_auto_club(true)
	assert(not range_instance.show_green_grid, "show_green_grid should be false on fairway")
	print("  PASS: Fairway does not select putter or enable grid.")

	# Test 2: Green lie -> default club is putter, grid is true
	print("\n--- Test 2: Green lie (10 yards) ---")
	ball_node.global_position = Vector3(0, 0, 90) # 10m / ~11 yards from hole
	ball_node.lie_type = "green"
	player_node.current_lie_type = "green"
	var def_club_green = range_instance.get_default_club()
	print("  Default club on green: ", def_club_green)
	assert(def_club_green == "Pt", "On green must select Pt")
	assert(range_instance.is_default_club_putter(), "is_default_club_putter must be true on green")
	range_instance.update_auto_club(true)
	assert(range_instance.show_green_grid, "show_green_grid should be true on green")
	print("  PASS: Green lie selects putter and enables grid.")

	# Test 3: Fringe lie close to hole (15 yards) -> default club is putter, grid is true
	print("\n--- Test 3: Fringe lie close to hole (15 yards) ---")
	ball_node.global_position = Vector3(0, 0, 100 - (15.0 / 1.09361)) # 15 yards from hole
	ball_node.lie_type = "fringe"
	player_node.current_lie_type = "fringe"
	assert(range_instance.is_ball_on_fringe(), "is_ball_on_fringe must return true")
	assert(range_instance.is_ball_close_to_green(), "is_ball_close_to_green must return true on fringe")
	var def_club_fringe = range_instance.get_default_club()
	print("  Default club on fringe (15 yd): ", def_club_fringe)
	assert(def_club_fringe == "Pt", "Fringe within 35 yards must select Pt")
	assert(range_instance.is_default_club_putter(), "is_default_club_putter must be true on fringe <= 35yd")
	range_instance.update_auto_club(true)
	assert(range_instance.show_green_grid, "show_green_grid should be true on fringe when putter is default")
	print("  PASS: Fringe within 35 yards selects putter and enables grid.")

	# Test 4: Fringe lie far from hole (40 yards) -> default club is not putter, grid is false
	print("\n--- Test 4: Fringe lie far from hole (40 yards) ---")
	ball_node.global_position = Vector3(0, 0, 100 - (40.0 / 1.09361)) # 40 yards from hole
	ball_node.lie_type = "fringe"
	player_node.current_lie_type = "fringe"
	var def_club_fringe_far = range_instance.get_default_club()
	print("  Default club on fringe (40 yd): ", def_club_fringe_far)
	assert(def_club_fringe_far != "Pt", "Fringe > 35 yards must NOT select Pt")
	assert(not range_instance.is_default_club_putter(), "is_default_club_putter must be false on fringe > 35yd")
	range_instance.update_auto_club(true)
	assert(not range_instance.show_green_grid, "show_green_grid should be false on fringe > 35yd")
	print("  PASS: Fringe > 35 yards does not select putter or enable grid.")

	# Test 5: CoursePlay helper methods
	print("\n--- Test 5: CoursePlay helper methods ---")
	var CoursePlayScript = load("res://Courses/CoursePlay/course_play.gd")
	assert(CoursePlayScript != null, "course_play.gd must load")
	var cp_instance = Node3D.new()
	cp_instance.set_script(CoursePlayScript)
	cp_instance.set("course_instance", range_instance)
	cp_instance.set("active_ball", ball_node)
	range_instance.add_child(cp_instance)

	# Fringe close to hole
	ball_node.global_position = Vector3(0, 0, 100 - (10.0 / 1.09361))
	ball_node.lie_type = "fringe"
	player_node.current_lie_type = "fringe"
	assert(cp_instance.is_player_on_fringe(), "cp.is_player_on_fringe must be true")
	assert(cp_instance.is_player_close_to_green(), "cp.is_player_close_to_green must be true on fringe")
	assert(cp_instance.is_default_club_putter(), "cp.is_default_club_putter must be true on fringe <= 35yd")
	print("  PASS: CoursePlay helpers successfully detect fringe and default putter.")

	# Test 6: Fringe putting camera view
	print("\n--- Test 6: Fringe putting camera view ---")
	# On fringe, ball is on fringe, club defaults to Pt
	ball_node.current_selected_club = "Pt"
	range_instance._user_custom_club = "Pt"
	var fringe_offset = range_instance.get_camera_local_offset()
	print("  Fringe camera local offset: ", fringe_offset)
	assert(fringe_offset.is_equal_approx(Vector3(-1.05, 0.6, 0)), "Fringe with Pt must use close putting camera offset (-1.05, 0.6, 0)")
	var fringe_target_look = range_instance.get_camera_target_look(range_instance.current_hole_location, ball_node.global_position)
	var expected_dir = (range_instance.current_hole_location - ball_node.global_position).normalized()
	var expected_look = ball_node.global_position + expected_dir * 3.5
	print("  Fringe camera target look: ", fringe_target_look, " (expected: ", expected_look, ")")
	assert(fringe_target_look.is_equal_approx(expected_look), "Fringe camera target look must be 3.5m ahead")
	print("  PASS: Fringe uses close putting camera view.")

	# Test 7: Off-green fairway with putter manually selected
	print("\n--- Test 7: Fairway with putter selected ---")
	ball_node.lie_type = "fairway"
	player_node.current_lie_type = "fairway"
	ball_node.global_position = Vector3(0, 0, 40) # 60m from hole
	ball_node.current_selected_club = "Pt"
	range_instance._user_custom_club = "Pt"
	var fairway_pt_offset = range_instance.get_camera_local_offset()
	print("  Fairway with Pt camera offset: ", fairway_pt_offset)
	assert(fairway_pt_offset.is_equal_approx(Vector3(-1.05, 0.6, 0)), "Putter selected anywhere must use putting camera offset (-1.05, 0.6, 0)")
	var fairway_pt_look = range_instance.get_camera_target_look(range_instance.current_hole_location, ball_node.global_position)
	var pt_dir = (range_instance.current_hole_location - ball_node.global_position).normalized()
	assert(fairway_pt_look.is_equal_approx(ball_node.global_position + pt_dir * 3.5), "Putter selected must use 3.5m putting look-at")
	print("  PASS: Selecting putter uses putting camera view even from fairway.")

	# Test 8: Fairway with non-putter does not use putting camera view
	print("\n--- Test 8: Fairway with Driver ---")
	ball_node.current_selected_club = "Dr"
	range_instance._user_custom_club = "Dr"
	var dr_offset = range_instance.get_camera_local_offset()
	print("  Fairway with Dr camera offset: ", dr_offset)
	assert(not dr_offset.is_equal_approx(Vector3(-1.05, 0.6, 0)), "Driver on fairway must not use putting camera view")
	print("  PASS: Driver on fairway uses full shot camera view.")

	# Test 9: Putting camera follow mode follows at current camera angle without zooming out
	print("\n--- Test 9: Putting camera follow mode ---")
	var pcam_script = load("res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_3d.gd")
	var pcam = Node3D.new()
	pcam.name = "PhantomCamera3D"
	pcam.set_script(pcam_script)
	range_instance.add_child(pcam)

	ball_node.is_putt = true
	range_instance._shot_active = true
	range_instance.set_camera_follow_mode(true)
	print("  Putting follow mode: ", pcam.follow_mode)
	print("  Putting follow offset: ", pcam.follow_offset)
	print("  Putting look_at mode: ", pcam.look_at_mode)
	assert(pcam.follow_mode == 2, "Follow mode should be SIMPLE (2)")
	assert(pcam.follow_offset.is_equal_approx(Vector3(-1.05, 0.6, 0.0)), "Putting camera must follow at address offset (-1.05, 0.6, 0) without zooming out")
	assert(pcam.look_at_mode == 0, "Putting camera look_at_mode must be NONE (0) to maintain current camera angle")
	print("  PASS: Putting camera follows ball at current camera angle without zooming out.")

	# Test 10: Non-putting (Driver) camera follow mode zooms out to flight camera with SIMPLE look_at
	print("\n--- Test 10: Driver camera follow mode ---")
	ball_node.is_putt = false
	ball_node.current_selected_club = "Dr"
	range_instance._user_custom_club = "Dr"
	ball_node.lie_type = "teebox"
	player_node.current_lie_type = "teebox"
	range_instance.set_camera_follow_mode(true)
	print("  Driver follow mode: ", pcam.follow_mode)
	print("  Driver follow offset: ", pcam.follow_offset)
	print("  Driver look_at mode: ", pcam.look_at_mode)
	assert(pcam.follow_offset.is_equal_approx(Vector3(-10.0, 1.4, 0.0)), "Driver camera must follow at full shot offset (-10.0, 1.4, 0)")
	assert(pcam.look_at_mode == 2, "Driver camera look_at_mode must be SIMPLE (2)")
	print("  PASS: Driver camera uses full shot follow camera.")

	print("\n=======================================================")
	print("ALL PUTTER DEFAULT SELECTION & GRID TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)
