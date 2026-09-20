extends SceneTree

class MockBall extends Node:
	signal rest
	var aim_yaw_offset_deg := 0.0
	var lie_type := "fairway"
	var spawn_position := Vector3.ZERO
	var global_position := Vector3.ZERO
	var position := Vector3.ZERO
	var is_in_sand := false
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

	print("\n=======================================================")
	print("ALL PUTTER DEFAULT SELECTION & GRID TESTS PASSED! 🎉")
	print("=======================================================")
	OS.kill(OS.get_process_id())
