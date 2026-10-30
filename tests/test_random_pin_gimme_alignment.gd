extends SceneTree

func _initialize() -> void:
	print("=== Running Random Pin Gimme Alignment Tests ===")

	# Set up mock GlobalSettings in root
	var mock_gs = Node.new()
	mock_gs.name = "GlobalSettings"
	var RangeSettingsClass = load("res://Utils/Settings/range_settings.gd")
	var rs = RangeSettingsClass.new()
	rs.gimme_range_1_enabled.set_value(true)
	rs.gimme_range_1_distance.set_value(10.0)
	rs.gimme_range_2_enabled.set_value(false)
	rs.gimme_range_3_enabled.set_value(false)
	mock_gs.set("range_settings", rs)
	root.add_child(mock_gs)

	var RangeScript = load("res://Courses/Range/range.gd")
	assert(RangeScript != null, "range.gd must load")

	var range_instance = Node3D.new()
	range_instance.set_script(RangeScript)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)

	# -------------------------------------------------------------
	# Test 1: MultiplayerManager._get_target_pin_position reflects randomized pin
	# -------------------------------------------------------------
	var mp = root.get_node_or_null("MultiplayerManager")
	if mp == null:
		mp = load("res://Utils/MultiplayerManager.gd").new()
		mp.name = "MultiplayerManager"
		root.add_child(mp)

	var hole_id = "Hole_1"
	mp.hole_ids = [hole_id]
	mp.current_hole_index = 0
	mp.hole_info = {
		hole_id: {
			"Par": 4,
			"Hole Location": [100.0, 200.0] # Static center
		}
	}
	var player_dict: Dictionary = {
		"name": "Golfer1",
		"active": true,
		"strokes": 2,
		"total_strokes": 2,
		"holed_out": false,
		"lie_type": "green",
		"position": Vector3(100.0, 0.0, 150.0),
		"shot_history": [],
		"hole_scores": {}
	}
	mp.players.clear()
	mp.players.append(player_dict)
	mp.active_player_index = 0

	# When current_pin_position is ZERO and no course_instance, it falls back to static JSON
	var default_pin = mp._get_target_pin_position()
	assert(default_pin.is_equal_approx(Vector3(100.0, 0.0, 200.0)), "Fallback pin should match static Hole Location")
	print("  PASS: Default pin fallback returns static Hole Location")

	# Set randomized pin position
	var randomized_pin = Vector3(125.0, 3.5, 218.0)
	mp.current_pin_position = randomized_pin
	var resolved_pin = mp._get_target_pin_position()
	assert(resolved_pin.is_equal_approx(randomized_pin), "Resolved pin must match current_pin_position")
	print("  PASS: _get_target_pin_position() honors current_pin_position")

	# -------------------------------------------------------------
	# Test 2: Gimme is awarded for ball near randomized pin, NOT static center
	# -------------------------------------------------------------
	# Ball A: Landed at 1.0m from randomized pin (within 10 ft / 3.048 m)
	# But ~29m away from static center!
	var ball_near_rand_pin = Vector3(125.8, 3.5, 218.0)
	var p = mp.get_active_player()
	p["lie_type"] = "green"
	p["holed_out"] = false
	p["strokes"] = 2

	var gimme_state = {"called": false, "strokes": 0}
	mp.gimme_awarded.connect(func(_player, strokes):
		gimme_state["called"] = true
		gimme_state["strokes"] = strokes
	)

	mp.record_shot(ball_near_rand_pin, {"TotalDistance": 50.0})
	assert(gimme_state["called"] == true, "Gimme must be awarded for ball resting within 10 ft of randomized pin")
	assert(gimme_state["strokes"] == 1, "Gimme should be +1 stroke")
	assert(p["holed_out"] == true, "Player should be marked holed out after gimme")
	print("  PASS: Ball near randomized pin (far from static center) correctly awarded gimme")

	# -------------------------------------------------------------
	# Test 3: Ball near static center (far from randomized pin) must NOT receive gimme
	# -------------------------------------------------------------
	p["holed_out"] = false
	p["strokes"] = 2
	p["lie_type"] = "green"
	gimme_state["called"] = false
	gimme_state["strokes"] = 0

	# Ball B: Landed at static center (0.2m away), which is ~28m away from randomized pin!
	var ball_near_static_center = Vector3(100.2, 0.0, 200.0)
	mp.record_shot(ball_near_static_center, {"TotalDistance": 50.0})
	assert(gimme_state["called"] == false, "Ball near old static center must NOT receive gimme when pin was randomized elsewhere")
	assert(p["holed_out"] == false, "Player must NOT be holed out when far from actual pin")
	print("  PASS: Ball near old static center correctly rejected from gimme")

	# -------------------------------------------------------------
	# Test 4: range.gd is_point_within_gimme_ring geometry test
	# -------------------------------------------------------------
	var pin = Vector3(10.0, 0.0, 10.0)
	# Boundary segment: wall at x = 12.0 (2m to the east)
	var boundary = [
		[Vector2(12.0, -10.0), Vector2(12.0, 30.0)]
	]
	range_instance.get_meta_list() # ensure instance is valid

	var u_east = Vector2(1, 0)
	var edge_d = range_instance._get_green_edge_distance(Vector2(10.0, 10.0), u_east, boundary)
	assert(absf(edge_d - 2.0) < 0.01, "Edge distance along east should be 2.0m")

	# -------------------------------------------------------------
	# Test 5: Verify range.gd current_hole_location setter updates MultiplayerManager
	# -------------------------------------------------------------
	range_instance.current_hole_location = Vector3(42.0, 1.2, 84.0)
	assert(mp.current_pin_position.is_equal_approx(Vector3(42.0, 1.2, 84.0)), "range.gd setter must update MultiplayerManager.current_pin_position")
	print("  PASS: Range setter successfully synchronized MultiplayerManager.current_pin_position")

	range_instance.free()
	mock_gs.free()

	print("\nALL RANDOM PIN GIMME ALIGNMENT TESTS PASSED SUCCESSFULLY!")
	quit(0)
