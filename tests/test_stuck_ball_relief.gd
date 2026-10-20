extends SceneTree

# Targeted unit test for Stuck Ball Relief Button & Mechanics
var _tested := false

class MockBall extends CharacterBody3D:
	signal rest
	var aim_yaw_offset_deg := 0.0
	var lie_type := "rough"
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
	func ensure_tree_clearance() -> bool: return false
	func ensure_rock_clearance() -> bool: return false

class MockPlayer extends Node3D:
	signal rest
	var ball: CharacterBody3D = null
	var current_lie_type: String = "rough"
	var current_shot_reduction := 0.0
	var camera_target: Node3D = null
	var _last_starting_pos := Vector3.ZERO
	func reset_ball(): pass
	func get_ball_state() -> int: return 0
	func reset_shot_data(): pass
	func clear_tracers(): pass


func _initialize() -> void:
	print("=== Running Stuck Ball Relief Unit Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	# =========================================================================
	# TEST 1: RangeUI Helper Menu Stuck Ball Button
	# =========================================================================
	print("\n--- Test 1: RangeUI Helper Menu Stuck Ball Button ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must load")

	var test_range = Node3D.new()
	test_range.name = "Range"
	test_range.scene_file_path = "res://Courses/Range/range.tscn"
	root.add_child(test_range)

	var range_ui = range_ui_scene.instantiate()
	test_range.add_child(range_ui)

	var stuck_btn = range_ui.get_stuck_ball_button()
	assert(stuck_btn != null, "Stuck ball button must exist in RangeUI")
	assert(stuck_btn.name == "StuckBallButton", "Button node name must be StuckBallButton")
	assert(stuck_btn.text.contains("Stuck Ball"), "Button text must contain 'Stuck Ball': %s" % stuck_btn.text)
	assert(stuck_btn.tooltip_text.contains("2 yards"), "Tooltip must mention '2 yards': %s" % stuck_btn.tooltip_text)
	assert(stuck_btn.tooltip_text.contains("fairway"), "Tooltip must mention 'fairway': %s" % stuck_btn.tooltip_text)

	var signal_emitted = [false]
	range_ui.stuck_ball_requested.connect(func(): signal_emitted[0] = true)
	stuck_btn.pressed.emit()
	print("  signal_emitted: ", signal_emitted[0])
	assert(signal_emitted[0], "Clicking StuckBallButton must emit stuck_ball_requested signal")
	print("  PASS: RangeUI StuckBallButton verified.")

	range_ui.queue_free()
	test_range.queue_free()

	# =========================================================================
	# TEST 2: Fairway Proximity & Ball Movement (2 Yards Closer, No Stroke)
	# =========================================================================
	print("\n--- Test 2: Fairway Movement & Stroke Count Invariance ---")
	var RangeScene = load("res://Courses/Range/range.gd")
	assert(RangeScene != null, "range.gd must load")

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

	var cam_tgt = Node3D.new()
	cam_tgt.name = "CameraTarget"
	player_node.add_child(cam_tgt)
	player_node.camera_target = cam_tgt

	# Build a rectangular fairway static body:
	# Centered around Z=0 from Z=-10 to Z=+10, and X from 0 to 100
	var fairway_body = StaticBody3D.new()
	fairway_body.name = "fairway_Static_1"
	fairway_body.set_meta("surface_type", 0) # PhysicsEnums.SurfaceType.FAIRWAY
	range_instance.add_child(fairway_body)

	var col_shape = CollisionShape3D.new()
	var concave_poly = ConcavePolygonShape3D.new()
	# Two triangles forming rectangle [0, 100] in X, [-10, 10] in Z
	var verts = PackedVector3Array([
		Vector3(0, 0, -10), Vector3(100, 0, -10), Vector3(100, 0, 10),
		Vector3(0, 0, -10), Vector3(100, 0, 10), Vector3(0, 0, 10)
	])
	concave_poly.data = verts
	col_shape.shape = concave_poly
	fairway_body.add_child(col_shape)

	range_instance.current_hole_location = Vector3(100, 0, 0)
	range_instance._init_cached_surface_bodies(true)

	assert(range_instance._cached_fairway_bodies.size() >= 1, "Must cache the fairway body")

	# Place ball 10 meters off the fairway at Z = 20 (fairway edge is at Z = 10)
	ball_node.global_position = Vector3(50.0, 0.0, 20.0)
	ball_node.spawn_position = ball_node.global_position

	var initial_dist_to_fairway = range_instance.get_distance_to_nearest_fairway(ball_node.global_position)
	print("  Initial distance to fairway: %.4f meters" % initial_dist_to_fairway)
	assert(is_equal_approx(initial_dist_to_fairway, 10.0), "Initial distance should be 10.0m (20 - 10)")

	var closest_pt = range_instance.get_closest_point_on_nearest_fairway(ball_node.global_position)
	print("  Closest point on fairway: ", closest_pt)
	assert(is_equal_approx(closest_pt.x, 50.0), "Closest point X should be 50.0")
	assert(is_equal_approx(closest_pt.z, 10.0), "Closest point Z should be 10.0")

	# Setup MultiplayerManager active player to test strokes
	var mp_mgr = root.get_node_or_null("MultiplayerManager")
	var had_mock_mp := false
	if mp_mgr == null:
		var mp_script = load("res://Utils/MultiplayerManager.gd")
		mp_mgr = Node.new()
		mp_mgr.set_script(mp_script)
		mp_mgr.name = "MultiplayerManager"
		root.add_child(mp_mgr)
		had_mock_mp = true

	mp_mgr.players.clear()
	mp_mgr.players.append({
		"name": "TestGolfer",
		"strokes": 3,
		"total_strokes": 7,
		"position": ball_node.global_position,
		"lie_type": "rough"
	})
	mp_mgr.active_player_index = 0

	# Move stuck ball
	var success = range_instance.move_stuck_ball(2.0)
	assert(success, "move_stuck_ball should return true")

	var new_dist_to_fairway = range_instance.get_distance_to_nearest_fairway(ball_node.global_position)
	print("  New distance to fairway: %.4f meters" % new_dist_to_fairway)

	# 2 yards = 1.8288 meters
	var expected_dist = 10.0 - 1.8288 # 8.1712
	assert(abs(new_dist_to_fairway - expected_dist) < 0.01, "New distance should be exactly 2 yards (1.8288m) closer: expected %.4f, got %.4f" % [expected_dist, new_dist_to_fairway])
	assert(is_equal_approx(ball_node.global_position.x, 50.0), "X coordinate should stay aligned")
	assert(abs(ball_node.global_position.z - (20.0 - 1.8288)) < 0.01, "Z coordinate should move 1.8288m towards Z=10")

	# Verify strokes did NOT count / increment
	var active_p = mp_mgr.get_active_player()
	assert(active_p["strokes"] == 3, "Strokes MUST NOT increment! Expected 3, got %d" % active_p["strokes"])
	assert(active_p["total_strokes"] == 7, "Total strokes MUST NOT increment! Expected 7, got %d" % active_p["total_strokes"])
	assert(active_p["position"] == ball_node.global_position, "Active player position must match new ball position")
	print("  PASS: Ball moved 2 yards closer to fairway and stroke count remained unchanged.")

	# =========================================================================
	# TEST 3: Multiple Relief Applications
	# =========================================================================
	print("\n--- Test 3: Multiple Stuck Ball Relief Moves ---")
	var success2 = range_instance.move_stuck_ball(2.0)
	assert(success2, "Second move_stuck_ball should succeed")
	var expected_dist_2 = 10.0 - (1.8288 * 2.0) # 6.3424
	var dist2 = range_instance.get_distance_to_nearest_fairway(ball_node.global_position)
	assert(abs(dist2 - expected_dist_2) < 0.01, "Distance should be 4 yards closer: expected %.4f, got %.4f" % [expected_dist_2, dist2])
	assert(active_p["strokes"] == 3, "Strokes MUST NOT increment on multiple reliefs! Still 3")
	print("  PASS: Second stuck ball relief verified.")

	# =========================================================================
	# TEST 4: CoursePlay Delegator
	# =========================================================================
	print("\n--- Test 4: CoursePlay move_stuck_ball Delegator ---")
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	var cp = Node3D.new()
	cp.set_script(cp_script)
	cp.course_instance = range_instance
	range_instance.add_child(cp)

	var cp_res = cp.move_stuck_ball(2.0)
	assert(cp_res, "CoursePlay move_stuck_ball must return true")
	assert(active_p["strokes"] == 3, "CoursePlay delegation must not increment strokes")
	assert(cp.stuck_ball_btn != null, "CoursePlay stuck_ball_btn must exist")
	assert(cp.stuck_ball_btn.name == "StuckBallButton", "CoursePlay button node name must be StuckBallButton")
	assert(cp.stuck_ball_btn.text.contains("Stuck Ball"), "CoursePlay button text must contain 'Stuck Ball'")
	print("  PASS: CoursePlay delegator verified.")

	range_instance.queue_free()
	if had_mock_mp:
		mp_mgr.queue_free()

	print("\n=======================================================")
	print("ALL STUCK BALL RELIEF TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit()
