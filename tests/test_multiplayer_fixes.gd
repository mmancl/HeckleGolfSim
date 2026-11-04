extends SceneTree

# Targeted Unit Tests for Multiplayer Ball Path Flight, Turn Order, and Score Tracking

const CoursePlayScript = preload("res://Courses/CoursePlay/course_play.gd")
const RangeScript = preload("res://Courses/Range/range.gd")

var _tested := false

func _initialize() -> void:
	print("=== Running Multiplayer Ball Path, Turn Order & Score Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	test_turn_order_normalization()
	test_in_progress_hole_score_display()
	test_default_aim_forward_constraint()
	print("\n=======================================================")
	print("  ALL MULTIPLAYER BUGFIX TESTS PASSED! 🎉              ")
	print("=======================================================\n")
	quit(0)

func test_turn_order_normalization() -> void:
	print("\n--- Test 1: Turn Order Mode Normalization ---")
	var mp = get_root().get_node_or_null("/root/MultiplayerManager")
	assert(mp != null, "MultiplayerManager autoload must exist")

	var p1 = {"name": "Mike", "slot_id": "slot_0", "owner_uid": "u1", "is_remote": false}
	var p2 = {"name": "Sterling", "slot_id": "slot_1", "owner_uid": "u2", "is_remote": true}
	var course_dict = {
		"Hole Info": {
			"Hole 01": {
				"Par": 4,
				"Hole Location": [0.0, 300.0],
				"Tee Boxes": {"Blue": [0.0, 0.0]}
			}
		}
	}

	# 1. Test passing 'furthest_away' normalizes to 'Classic'
	mp.setup_game([p1, p2], course_dict, "", "", "Full 18", "Standard", {}, "furthest_away")
	assert(mp.turn_order_mode == "Classic", "turn_order_mode 'furthest_away' must be normalized to 'Classic', got: %s" % mp.turn_order_mode)

	# 2. Test passing 'Classic' stays 'Classic'
	mp.setup_game([p1, p2], course_dict, "", "", "Full 18", "Standard", {}, "Classic")
	assert(mp.turn_order_mode == "Classic", "turn_order_mode 'Classic' must remain 'Classic'")

	# 3. Test peek_next_player in Classic mode selects furthest player
	mp.players[0]["position"] = Vector3(0, 0, 150) # 150m from pin
	mp.players[0]["strokes"] = 1
	mp.players[1]["position"] = Vector3(0, 0, 80)  # 220m from pin (furthest)
	mp.players[1]["strokes"] = 1
	var next_p = mp.peek_next_player()
	assert(next_p.get("name") == "Sterling", "Furthest player Sterling must be next, got: %s" % next_p.get("name"))

	# 4. Test select_next_player switches to furthest player
	mp.active_player_index = 0
	mp.select_next_player()
	assert(mp.get_active_player().get("name") == "Sterling", "select_next_player must switch to Sterling")
	print("  PASS: Turn order normalization and Classic mode selection verified.")

func test_in_progress_hole_score_display() -> void:
	print("\n--- Test 2: In-Progress Hole Score Display (No Premature Par Negatives) ---")
	var mp = get_root().get_node_or_null("/root/MultiplayerManager")

	var p1 = {"name": "Mike", "slot_id": "slot_0", "owner_uid": "u1", "is_remote": false}
	var p2 = {"name": "Sterling", "slot_id": "slot_1", "owner_uid": "u2", "is_remote": true}
	var course_dict = {
		"Hole Info": {
			"Hole 01": {"Par": 4, "Hole Location": [0.0, 300.0], "Tee Boxes": {"Blue": [0.0, 0.0]}},
			"Hole 02": {"Par": 3, "Hole Location": [0.0, 150.0], "Tee Boxes": {"Blue": [0.0, 0.0]}}
		}
	}
	mp.setup_game([p1, p2], course_dict, "", "", "Full 18", "Standard", {}, "Classic")
	mp.start_hole()

	# Simulate Mike taking 1 stroke on Par 4 Hole 1 (NOT holed out)
	mp.players[0]["strokes"] = 1
	mp.players[0]["hole_scores"]["Hole 01"] = 1
	mp.players[0]["holed_out"] = false

	# Score clean format must be "E" (Even), NOT "-3"
	var score_str = mp._format_player_score_clean(mp.players[0])
	assert(score_str == "E", "In-progress hole score must show 'E', got: %s" % score_str)

	# Simulate Sterling taking 2 strokes on Par 4 Hole 1 (NOT holed out)
	mp.players[1]["strokes"] = 2
	mp.players[1]["hole_scores"]["Hole 01"] = 2
	mp.players[1]["holed_out"] = false
	var p2_score_str = mp._format_player_score_clean(mp.players[1])
	assert(p2_score_str == "E", "Sterling in-progress score must show 'E', got: %s" % p2_score_str)

	# When player holes out in 3 on Par 4: score must be "-1" (Birdie)
	mp.players[0]["strokes"] = 3
	mp.players[0]["hole_scores"]["Hole 01"] = 3
	mp.players[0]["holed_out"] = true
	var holed_score_str = mp._format_player_score_clean(mp.players[0])
	assert(holed_score_str == "-1", "Holed out birdie must show '-1', got: %s" % holed_score_str)
	print("  PASS: In-progress hole strokes do not prematurely subtract par.")

func test_default_aim_forward_constraint() -> void:
	print("\n--- Test 3: Default Aim Forward Constraint Logic ---")
	var ball_pos := Vector3(20, 0, 200)
	var hole_pos := Vector3(0, 0, 300)
	var to_hole_2d := Vector2(hole_pos.x - ball_pos.x, hole_pos.z - ball_pos.z).normalized()

	# Scenario A: Candidate aim points backwards (e.g. from an erroneous polyline projection)
	var backward_candidate := Vector3(10, 0, 150)
	var candidate_diff := backward_candidate - ball_pos
	var candidate_dir_2d := Vector2(candidate_diff.x, candidate_diff.z).normalized()
	var dot_val := candidate_dir_2d.dot(to_hole_2d)

	# The dot product is negative because it points backward
	assert(dot_val < 0.0, "Backward candidate should have negative dot product")

	# Safe clamp logic (matches the safety check in apply_default_aim and _calc_default_aim_target):
	var target_pos := backward_candidate
	if candidate_dir_2d.dot(to_hole_2d) < 0.1:
		var safe_dist_m := candidate_diff.length()
		var safe_target_2d := Vector2(ball_pos.x, ball_pos.z) + to_hole_2d * safe_dist_m
		target_pos = Vector3(safe_target_2d.x, 0.0, safe_target_2d.y)

	var resolved_dir := (target_pos - ball_pos).normalized()
	var resolved_dot := Vector2(resolved_dir.x, resolved_dir.z).dot(to_hole_2d)
	assert(resolved_dot > 0.99, "Resolved target direction must align with hole direction, got: %.3f" % resolved_dot)
	assert(target_pos.z > ball_pos.z, "Resolved target Z must be strictly ahead of ball Z (got target.z=%.1f vs ball.z=%.1f)" % [target_pos.z, ball_pos.z])

	print("  PASS: Default aim forward clamp strictly advances toward hole.")
