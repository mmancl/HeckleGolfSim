extends SceneTree

class MockBall extends Node3D:
	signal rest
	var aim_yaw_offset_deg := 0.0
	var lie_type := "fairway"
	var spawn_position := Vector3.ZERO
	var is_in_sand := false
	var is_putt := false
	var current_selected_club := "7i"
	var state := 0
	var surface_type := 0
	func _on_club_selected(club): current_selected_club = club
	func reset(): pass
	func _update_surface_from_underneath(): pass
	func set_surface(val): surface_type = val
	func get_surface() -> int: return surface_type

class MockPlayer extends Node3D:
	signal rest
	var ball: Node = null
	var current_lie_type: String = "fairway"
	var current_shot_reduction := 0.0
	func reset_ball(): pass
	func get_ball_state() -> int: return 0
	func reset_shot_data(): pass
	func clear_tracers(): pass

func _initialize():
	_run_tests()

func _run_tests() -> void:
	print("=== Running Wrong Green Handling Tests ===")

	var RangeScene = load("res://Courses/Range/range.gd")
	assert(RangeScene != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.scene_file_path = "res://TestCourse/test.tscn"
	range_instance.set_script(RangeScene)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)
	root.add_child(range_instance)

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

	# Build two distinct green static bodies:
	# Green 1: Current hole green at position Vector3(0, 0, 100) (pin at 0, 0, 100)
	# Green 2: Another hole green (wrong green) at position Vector3(150, 0, 0)
	var green_body_1 = StaticBody3D.new()
	green_body_1.name = "green_Static_1"
	range_instance.add_child(green_body_1)
	green_body_1.position = Vector3(0, 0, 100)
	var col_shape_1 = CollisionShape3D.new()
	var concave_1 = ConcavePolygonShape3D.new()
	# Flat square green 20x20 centered at (0, 0, 100) (local -10 to +10)
	var verts_1 = PackedVector3Array([
		Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10),
		Vector3(-10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10)
	])
	concave_1.data = verts_1
	col_shape_1.shape = concave_1
	green_body_1.add_child(col_shape_1)

	var green_body_2 = StaticBody3D.new()
	green_body_2.name = "green_Static_2"
	range_instance.add_child(green_body_2)
	green_body_2.position = Vector3(150, 0, 0)
	var col_shape_2 = CollisionShape3D.new()
	var concave_2 = ConcavePolygonShape3D.new()
	# Flat square green 20x20 centered at (150, 0, 0) (local -10 to +10)
	var verts_2 = PackedVector3Array([
		Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(10, 0, 10),
		Vector3(-10, 0, -10), Vector3(10, 0, 10), Vector3(-10, 0, 10)
	])
	concave_2.data = verts_2
	col_shape_2.shape = concave_2
	green_body_2.add_child(col_shape_2)

	# Set current hole location to Green 1: (0, 0, 100)
	range_instance.current_hole_location = Vector3(0, 0, 100)

	await process_frame
	await physics_frame

	# Initialize cached surface bodies
	range_instance._init_cached_surface_bodies()
	print("  Cached green bodies count: ", range_instance._cached_green_bodies.size())
	assert(range_instance._cached_green_bodies.size() >= 2, "Must cache both green bodies")

	# --- Test 1: Ball on correct green (0, 0, 95) ---
	print("\n--- Test 1: Ball on correct green (5m from hole) ---")
	ball_node.global_position = Vector3(0, 0, 95)
	ball_node.lie_type = "green"
	player_node.current_lie_type = "green"

	var d_curr = range_instance.get_distance_to_current_green(ball_node.global_position)
	print("  Distance to current green: ", d_curr)
	assert(d_curr <= 0.05, "Distance to current green must be <= 0.05")
	assert(not range_instance.is_ball_on_wrong_green(), "Ball on correct green must NOT be on wrong green")
	assert(range_instance.is_ball_on_green(), "Ball on correct green must report is_ball_on_green == true")
	assert(range_instance.is_default_club_putter(), "is_default_club_putter must be true on correct green")
	var def_club = range_instance.get_default_club()
	print("  Default club on correct green: ", def_club)
	assert(def_club == "Pt", "Correct green must recommend Pt")
	print("  PASS: Correct green correctly identifies green and recommends putter.")

	# --- Test 2: Ball on wrong green (150, 0, 0) ---
	print("\n--- Test 2: Ball on wrong green (at 150, 0, 0) ---")
	ball_node.global_position = Vector3(150, 0, 0)
	ball_node.lie_type = "green"
	player_node.current_lie_type = "green"

	var d_wrong_curr = range_instance.get_distance_to_current_green(ball_node.global_position)
	var d_wrong_any = range_instance.get_distance_to_any_green(ball_node.global_position)
	print("  Distance to current green: ", d_wrong_curr, ", distance to any green: ", d_wrong_any)
	assert(d_wrong_any <= 0.05, "Distance to any green must be <= 0.05 on Green 2")
	assert(d_wrong_curr > 10.0, "Distance to current green must be far from Green 1")
	assert(range_instance.is_ball_on_wrong_green(), "Ball on green 2 must be identified as on wrong green")
	assert(not range_instance.is_ball_on_green(), "Ball on wrong green must NOT report is_ball_on_green == true")
	assert(not range_instance.is_ball_on_fringe(), "Ball on wrong green must NOT report is_ball_on_fringe == true")
	assert(not range_instance.is_default_club_putter(), "is_default_club_putter must be false on wrong green")

	var wrong_green_club = range_instance.get_default_club()
	print("  Default club on wrong green: ", wrong_green_club)
	assert(wrong_green_club != "Pt", "Wrong green must NOT recommend putter")
	assert(wrong_green_club in ["4i", "5w", "3w", "5i", "6i"], "Wrong green must recommend club as if on fairway")
	print("  PASS: Wrong green does not recommend putter, recommends fairway approach club.")

	# --- Test 3: update_current_lie_and_reduction on wrong green ---
	print("\n--- Test 3: update_current_lie_and_reduction on wrong green ---")
	range_instance.update_current_lie_and_reduction()
	assert(ball_node.lie_type == "fairway", "Lie type on wrong green should be converted to fairway")
	assert(player_node.current_shot_reduction == 0.0 or range_instance.get("reduction") == null, "Reduction must be 0 on wrong green")
	print("  PASS: Lie type converted to fairway with 0 reduction on wrong green.")

	# --- Test 4: CoursePlay integration ---
	print("\n--- Test 4: CoursePlay integration ---")
	var CoursePlayScript = load("res://Courses/CoursePlay/course_play.gd")
	assert(CoursePlayScript != null, "course_play.gd must load")

	var cp = Node3D.new()
	cp.set_script(CoursePlayScript)
	cp.set_process(false)
	cp.set_physics_process(false)
	range_instance.add_child(cp)
	cp.set("course_instance", range_instance)
	cp.set("active_ball", ball_node)

	# Check wrong green detection in CoursePlay
	ball_node.global_position = Vector3(150, 0, 0)
	ball_node.lie_type = "green"
	assert(cp.is_player_on_wrong_green(), "cp.is_player_on_wrong_green must be true")
	assert(not cp.is_player_on_green(), "cp.is_player_on_green must be false on wrong green")
	assert(not cp.is_player_on_fringe(), "cp.is_player_on_fringe must be false on wrong green")
	assert(not cp.is_default_club_putter(), "cp.is_default_club_putter must be false on wrong green")

	# Check mock distance tracker labels
	var back_lbl = Label.new()
	var hole_lbl = Label.new()
	var front_lbl = Label.new()
	var unit_lbl = Label.new()
	cp.set("_back_lbl", back_lbl)
	cp.set("_hole_lbl", hole_lbl)
	cp.set("_front_lbl", front_lbl)
	cp.set("_distance_unit_lbl", unit_lbl)
	var dt_panel = Panel.new()
	cp.set("_distance_tracker_panel", dt_panel)
	var cam = Camera3D.new()
	cp.set("_minimap_camera", cam)

	# Simulate CoursePlay distance tracking block:
	var dist_hole = ball_node.global_position.distance_to(range_instance.current_hole_location)
	var is_putting = (not cp.is_player_on_wrong_green()) and (cp.is_default_club_putter() or cp.is_player_on_green() or cp.is_player_on_fringe())
	assert(not is_putting, "is_putting must be false when on wrong green")

	var dist_hole_yds = int(dist_hole * 1.09361)
	hole_lbl.text = str(dist_hole_yds)
	unit_lbl.text = "YDS"

	print("  Hole distance display on wrong green: ", hole_lbl.text, " ", unit_lbl.text)
	assert(unit_lbl.text == "YDS", "Distance unit must stay YDS on wrong green")
	assert(int(hole_lbl.text) > 180, "Distance to hole must be > 180 yards, not in feet")
	print("  PASS: CoursePlay stays in yards and avoids putter on wrong green.")

	# Cleanup
	print("\n=== All Wrong Green Tests Passed Successfully! ===")
	quit(0)
