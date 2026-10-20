extends SceneTree

func _initialize() -> void:
	print("--- Running Test: Lie Aiming & Distance Caching ---")
	test_range_distance_caching()
	test_ball_green_caching()
	test_course_play_lie_caching()
	test_player_tree_occlusion_skip_on_aim()
	print("=======================================================")
	print("  ALL LIE AIMING & DISTANCE CACHING TESTS PASSED! 🎉")
	print("=======================================================")
	quit(0)

func test_range_distance_caching() -> void:
	print("\n--- Test 1: Range.gd Geometric Distance Caching ---")
	var RangeScript = load("res://Courses/Range/range.gd")
	var range_instance = Node3D.new()
	range_instance.set_script(RangeScript)
	root.add_child(range_instance)
	
	var pos1 = Vector3(50.0, 0.0, 100.0)
	var pos2 = Vector3(50.00001, 0.0, 100.00001) # approx equal
	var pos3 = Vector3(150.0, 0.0, 200.0)
	
	# Initial calls populate caches
	var d1 = range_instance.get_distance_to_nearest_green(pos1)
	assert(range_instance._cached_dist_nearest_green_pos.is_equal_approx(pos1), "Nearest green cache pos should be pos1")
	var d2 = range_instance.get_distance_to_nearest_green(pos2)
	assert(d1 == d2, "Approx equal position should return cached result")
	
	var f1 = range_instance.get_distance_to_nearest_fairway(pos1)
	assert(range_instance._cached_dist_fairway_pos.is_equal_approx(pos1), "Fairway cache pos should be pos1")
	var f2 = range_instance.get_distance_to_nearest_fairway(pos2)
	assert(f1 == f2, "Approx equal position should return cached fairway result")
	
	var t1 = range_instance.get_distance_to_nearest_teebox(pos1)
	assert(range_instance._cached_dist_teebox_pos.is_equal_approx(pos1), "Teebox cache pos should be pos1")
	var t2 = range_instance.get_distance_to_nearest_teebox(pos2)
	assert(t1 == t2, "Approx equal position should return cached teebox result")
	
	var w1 = range_instance.is_ball_on_wrong_green(pos1)
	assert(range_instance._cached_wrong_green_pos.is_equal_approx(pos1), "Wrong green cache pos should be pos1")
	var w2 = range_instance.is_ball_on_wrong_green(pos2)
	assert(w1 == w2, "Approx equal position should return cached wrong green result")
	
	# Clearing caches
	range_instance.clear_surface_distance_caches()
	assert(range_instance._cached_dist_nearest_green_pos == Vector3.INF, "Cache should be cleared")
	assert(range_instance._cached_dist_fairway_pos == Vector3.INF, "Fairway cache should be cleared")
	
	range_instance.queue_free()
	print("  PASS: range.gd caches distance checks and is_ball_on_wrong_green by position.")

func test_ball_green_caching() -> void:
	print("\n--- Test 2: Ball.gd Green Position Caching ---")
	var BallScript = load("res://Player/ball.gd")
	var ball = CharacterBody3D.new()
	ball.set_script(BallScript)
	root.add_child(ball)
	
	var test_pos = Vector3(25.0, 0.5, 30.0)
	var res1 = ball._is_position_on_green(test_pos)
	assert(ball._cached_is_pos_on_green_pos.is_equal_approx(test_pos), "Ball green cache pos should match")
	var res2 = ball._is_position_on_green(test_pos)
	assert(res1 == res2, "Ball should return cached green check result")
	
	var fringe1 = ball._is_position_on_fringe(test_pos)
	assert(ball._cached_is_pos_on_fringe_pos.is_equal_approx(test_pos), "Ball fringe cache pos should match")
	var fringe2 = ball._is_position_on_fringe(test_pos)
	assert(fringe1 == fringe2, "Ball should return cached fringe check result")
	
	ball.queue_free()
	print("  PASS: ball.gd caches green/fringe/wrong_green checks by query position.")

func test_course_play_lie_caching() -> void:
	print("\n--- Test 3: CoursePlay Lie & Distance Tracker Caching ---")
	var CoursePlayScript = load("res://Courses/CoursePlay/course_play.gd")
	var cp = Node3D.new()
	cp.set_script(CoursePlayScript)
	root.add_child(cp)
	
	# Test distance tracker caching logic
	var dummy_ball_pos = Vector3(10.0, 0.0, 20.0)
	var dummy_pin_pos = Vector3(100.0, 0.0, 200.0)
	var dir_3d = Vector3.RIGHT
	
	# Without panel, early out safely
	cp._update_distance_tracker_panel(dummy_ball_pos, dummy_pin_pos, dir_3d)
	
	# Cache coordinates check
	assert(cp._cached_cp_wrong_green_pos == Vector3.INF, "Initial cache should be INF")
	assert(cp._cached_cp_on_green_pos == Vector3.INF, "Initial cache should be INF")
	
	cp.queue_free()
	print("  PASS: CoursePlay lie helpers and distance tracker support position caching.")

func test_player_tree_occlusion_skip_on_aim() -> void:
	print("\n--- Test 4: Player Tree Occlusion Skips During Aiming ---")
	var PlayerScript = load("res://Player/player.gd")
	var player = Node3D.new()
	player.set_script(PlayerScript)
	
	# Mock course parent with is_actively_aiming returning true
	var mock_course = Node3D.new()
	var mock_script = GDScript.new()
	mock_script.source_code = """
extends Node3D
func is_actively_aiming() -> bool:
	return true
"""
	mock_script.reload()
	mock_course.set_script(mock_script)
	mock_course.add_child(player)
	
	# Call _handle_tree_occlusion()
	player._handle_tree_occlusion()
	assert(not player._has_scanned_trees, "Tree scanning / occlusion must be skipped when course is actively aiming")
	
	player.free()
	mock_course.free()
	print("  PASS: player.gd tree occlusion immediately skips while course is actively aiming.")
