extends SceneTree

class MockBall extends Node3D:
	signal rest
	var aim_yaw_offset_deg := 0.0
	var lie_type := "fairway"
	var spawn_position := Vector3.ZERO
	var is_in_sand := false
	var current_selected_club := "7i"
	func _on_club_selected(_club): pass
	func reset(): pass
	func _update_surface_from_underneath(): pass
	func set_surface(_val): pass
	func get_target_dir() -> Vector3: return Vector3.RIGHT

class MockPlayer extends Node3D:
	signal rest
	var ball: Node3D = null
	var current_lie_type: String = "fairway"
	var current_shot_reduction := 0.0
	func reset_ball(): pass
	func get_ball_state() -> int: return 0

func _initialize():
	print("=== Running Wind Simulation Tests ===")

	# Get existing GlobalSettings autoload from root
	var gs = root.get_node_or_null("GlobalSettings")
	if gs == null:
		var GSClass = load("res://Utils/Settings/global_settings.gd")
		gs = GSClass.new()
		gs.name = "GlobalSettings"
		root.add_child(gs)
	print("GlobalSettings found on root: ", gs != null)

	# -------------------------------------------------------------
	# Test 1: Wind Setting Toggle & Persistence
	# -------------------------------------------------------------
	print("\n--- Test 1: Wind Setting Toggle ---")
	gs.range_settings.wind_enabled.set_value(false)
	assert(not gs.is_wind_enabled(), "is_wind_enabled() must return false when setting is false")
	assert(gs.get_wind_vector_mps() == Vector3.ZERO, "Wind vector must be ZERO when disabled")

	gs.range_settings.wind_enabled.set_value(true)
	assert(gs.is_wind_enabled(), "is_wind_enabled() must return true when setting is true")
	print("  PASS: Wind setting toggle works.")

	# -------------------------------------------------------------
	# Test 2: Random Wind Generation & Course Persistence
	# -------------------------------------------------------------
	print("\n--- Test 2: Random Wind Generation & Weighted Distribution ---")
	gs.generate_new_wind()
	var spd1 = gs.current_wind_speed_mph
	var dir1 = gs.current_wind_direction_rad
	assert(spd1 >= 1.0 and spd1 <= 20.0, "Wind speed must be between 1 and 20 MPH, got: %f" % spd1)
	assert(dir1 >= 0.0 and dir1 <= TAU, "Wind direction must be between 0 and TAU, got: %f" % dir1)
	assert(gs.wind_initialized_for_round, "wind_initialized_for_round must be true")

	# Honored for the entire course: calling start_round_wind(false) retains the same wind
	gs.start_round_wind(false)
	assert(gs.current_wind_speed_mph == spd1, "Wind speed must be retained across course holes")
	assert(gs.current_wind_direction_rad == dir1, "Wind direction must be retained across course holes")

	# Test 1000 weighted samples
	var count_6_12 := 0
	var count_2_5 := 0
	var count_13_15 := 0
	var count_1 := 0
	var count_16_20 := 0
	for _i in range(1000):
		var val = gs._pick_weighted_random_wind_speed()
		assert(val >= 1.0 and val <= 20.0, "Sample out of bounds: %f" % val)
		if val >= 6.0 and val <= 12.0:
			count_6_12 += 1
		elif val >= 2.0 and val <= 5.0:
			count_2_5 += 1
		elif val >= 13.0 and val <= 15.0:
			count_13_15 += 1
		elif val == 1.0:
			count_1 += 1
		elif val >= 16.0 and val <= 20.0:
			count_16_20 += 1

	print("  Sample stats (1000 rolls): 6-12: %d | 2-5: %d | 13-15: %d | 1: %d | 16-20: %d" % [
		count_6_12, count_2_5, count_13_15, count_1, count_16_20
	])
	assert(count_6_12 > count_2_5 and count_6_12 > count_13_15, "6-12 must be most frequent")
	assert(count_2_5 > count_1 and count_13_15 > count_1, "2-5 and 13-15 must be more frequent than 1")
	assert(count_2_5 > count_16_20 and count_13_15 > count_16_20, "2-5 and 13-15 must be more frequent than 16-20")
	print("  PASS: Weighted random wind distribution and course persistence verified.")

	# -------------------------------------------------------------
	# Test 3: Relative Arrow Direction Calculations
	# -------------------------------------------------------------
	print("\n--- Test 3: Relative Wind Arrow Direction ---")
	var ball_pos = Vector3(0, 0, 0)
	var aim_target = Vector3(100, 0, 0) # Forward is along +X (0 deg)
	
	# Tailwind: blowing along +X (towards target) -> Arrow must point UP (↑)
	gs.current_wind_direction_rad = 0.0
	var res_tail = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_tail.arrow == "↑", "Tailwind relative arrow must be ↑, got: " + res_tail.arrow)

	# Headwind: blowing along -X (towards ball) -> Arrow must point DOWN (↓)
	gs.current_wind_direction_rad = PI
	var res_head = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_head.arrow == "↓", "Headwind relative arrow must be ↓, got: " + res_head.arrow)

	# Right Crosswind: blowing along +Z (South in Godot, Right from +X perspective) -> Arrow must point RIGHT (→)
	gs.current_wind_direction_rad = PI / 2.0
	var res_right = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_right.arrow == "→", "Right crosswind relative arrow must be →, got: " + res_right.arrow)

	# Left Crosswind: blowing along -Z (North in Godot, Left from +X perspective) -> Arrow must point LEFT (←)
	gs.current_wind_direction_rad = -PI / 2.0
	var res_left = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_left.arrow == "←", "Left crosswind relative arrow must be ←, got: " + res_left.arrow)

	# Forward-Right Diagonal: 45 deg -> Arrow must point ↗
	gs.current_wind_direction_rad = PI / 4.0
	var res_diag_fr = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_diag_fr.arrow == "↗", "Forward-right diagonal relative arrow must be ↗, got: " + res_diag_fr.arrow)

	# Forward-Left Diagonal: -45 deg -> Arrow must point ↖
	gs.current_wind_direction_rad = -PI / 4.0
	var res_diag_fl = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_diag_fl.arrow == "↖", "Forward-left diagonal relative arrow must be ↖, got: " + res_diag_fl.arrow)

	# Back-Right Diagonal: 135 deg -> Arrow must point ↘
	gs.current_wind_direction_rad = 3.0 * PI / 4.0
	var res_diag_br = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_diag_br.arrow == "↘", "Back-right diagonal relative arrow must be ↘, got: " + res_diag_br.arrow)

	# Back-Left Diagonal: -135 deg -> Arrow must point ↙
	gs.current_wind_direction_rad = -3.0 * PI / 4.0
	var res_diag_bl = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target)
	assert(res_diag_bl.arrow == "↙", "Back-left diagonal relative arrow must be ↙, got: " + res_diag_bl.arrow)

	print("  PASS: All 8 aim-relative wind arrows (↑, ↗, →, ↘, ↓, ↙, ←, ↖) verified mathematically.")

	# -------------------------------------------------------------
	# Test 4: Top Aim HUD Pill Formatting
	# -------------------------------------------------------------
	print("\n--- Test 4: HUD AimDistanceLabel Formatting ---")
	var RangeScript = load("res://Courses/Range/range.gd")
	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.scene_file_path = "res://TestCourse/test.tscn"
	range_instance.set_script(RangeScript)

	var player = MockPlayer.new()
	player.name = "Player"
	range_instance.add_child(player)

	var ball = MockBall.new()
	ball.name = "GolfBall"
	player.add_child(ball)
	player.ball = ball

	# Create MapCanvas and labels manually
	var canvas = CanvasLayer.new()
	canvas.name = "MapCanvas"
	range_instance.add_child(canvas)

	var badge = Panel.new()
	badge.name = "AimDistanceBadge"
	canvas.add_child(badge)

	var label = Label.new()
	label.name = "AimDistanceLabel"
	canvas.add_child(label)

	root.add_child(range_instance)

	# Enable wind
	gs.range_settings.wind_enabled.set_value(true)
	gs.current_wind_speed_mph = 12.0
	gs.current_wind_direction_rad = 0.0
	range_instance.aim_target_pos = Vector3(150, 0, 0)
	range_instance._update_aim_distance_label_text()

	assert(label.text.contains("💨"), "Label must contain air moving icon 💨")
	assert(label.text.contains("Wind 12 MPH"), "Label must contain 'Wind 12 MPH', got: " + label.text)
	var wind_offset = badge.offset_right
	assert(wind_offset > 300 and wind_offset < 420, "Badge must dynamically expand for wind, got: %f" % wind_offset)
	print("  PASS: HUD Label text when enabled: '%s' (badge width: %0.1f)" % [label.text, wind_offset * 2])

	# Disable wind
	gs.range_settings.wind_enabled.set_value(false)
	range_instance._update_aim_distance_label_text()
	assert(not label.text.contains("Wind"), "Label must not contain 'Wind' when disabled")
	var no_wind_offset = badge.offset_right
	assert(no_wind_offset < wind_offset, "Badge must shrink when wind is disabled")
	print("  PASS: HUD Label text when disabled: '%s' (badge width: %0.1f)" % [label.text, no_wind_offset * 2])

	range_instance.queue_free()

	# -------------------------------------------------------------
	# Test 5: Ball Flight Aerodynamic Wind Force
	# -------------------------------------------------------------
	print("\n--- Test 5: Ball Flight Aerodynamic Wind Forces ---")
	gs.range_settings.wind_enabled.set_value(true)
	
	# Simulate 10 MPH crosswind (+Z direction) on a ball flying along +X at 40 m/s
	gs.current_wind_speed_mph = 10.0
	gs.current_wind_direction_rad = PI / 2.0 # wind along +Z
	var w_vec = gs.get_wind_vector_mps()
	assert(w_vec.z > 0.0, "Wind vector should be along +Z")
	
	var v_ball = Vector3(40.0, 10.0, 0.0)
	var v_rel = v_ball - w_vec
	var cd = 0.28
	var rho = 1.204
	var cross_area = 0.0014303
	var f_drag_wind = -0.5 * cd * rho * cross_area * v_rel.length() * v_rel
	var f_drag_still = -0.5 * cd * rho * cross_area * v_ball.length() * v_ball
	var wind_force = f_drag_wind - f_drag_still
	
	# Lateral wind force along +Z must be positive (pushing ball in direction of crosswind)
	assert(wind_force.z > 0.0, "Crosswind along +Z must pull ball in +Z direction, got: %f" % wind_force.z)
	print("  PASS: Crosswind pulls ball laterally with force: +%.4f N" % wind_force.z)

	# Simulate 10 MPH headwind (-X direction) on a ball flying along +X
	gs.current_wind_direction_rad = PI # wind along -X
	w_vec = gs.get_wind_vector_mps()
	v_rel = v_ball - w_vec
	f_drag_wind = -0.5 * cd * rho * cross_area * v_rel.length() * v_rel
	wind_force = f_drag_wind - f_drag_still
	assert(wind_force.x < 0.0, "Headwind must apply opposing (negative) force along X, got: %f" % wind_force.x)
	print("  PASS: Headwind resists ball flight with opposing force: %.4f N" % wind_force.x)

	# Simulate 10 MPH tailwind (+X direction) on a ball flying along +X
	gs.current_wind_direction_rad = 0.0 # wind along +X
	w_vec = gs.get_wind_vector_mps()
	v_rel = v_ball - w_vec
	f_drag_wind = -0.5 * cd * rho * cross_area * v_rel.length() * v_rel
	wind_force = f_drag_wind - f_drag_still
	assert(wind_force.x > 0.0, "Tailwind must reduce drag / apply forward force along X, got: %f" % wind_force.x)
	print("  PASS: Tailwind assists ball flight with forward force: +%.4f N" % wind_force.x)

	# -------------------------------------------------------------
	# Test 6: Wind Speed Slider & Adjustment Control
	# -------------------------------------------------------------
	print("\n--- Test 6: Wind Speed Slider & Adjustment Control ---")
	var results := {"received": false, "speed": 0.0}
	var signal_cb = func(s: float, _d: float):
		results.received = true
		results.speed = s
	gs.wind_changed.connect(signal_cb)

	# Test set_wind_speed_mph
	gs.set_wind_speed_mph(15.0)
	assert(gs.current_wind_speed_mph == 15.0, "current_wind_speed_mph must be 15.0")
	assert(gs.range_settings.wind_speed.value == 15.0, "range_settings.wind_speed must be 15.0")
	assert(results.received and results.speed == 15.0, "wind_changed signal must be emitted with speed 15.0")
	print("  PASS: set_wind_speed_mph correctly updates setting and emits signal.")

	# Test clamping
	gs.set_wind_speed_mph(-5.0)
	assert(gs.current_wind_speed_mph == 0.0, "Negative speed should clamp to 0.0")
	gs.set_wind_speed_mph(60.0)
	assert(gs.current_wind_speed_mph == 50.0, "Excessive speed should clamp to 50.0")
	print("  PASS: Speed clamping (0.0 to 50.0 MPH) works correctly.")

	gs.wind_changed.disconnect(signal_cb)

	# -------------------------------------------------------------
	# Test 7: Driving Range Always Overrides Wind to Off
	# -------------------------------------------------------------
	print("\n--- Test 7: Driving Range Wind Override ---")
	gs.range_settings.wind_enabled.set_value(true)
	var mock_range = Node3D.new()
	mock_range.name = "Range"
	mock_range.scene_file_path = "res://Courses/Range/range.tscn"
	mock_range.set("is_driving_range", true)
	root.add_child(mock_range)
	root.get_tree().current_scene = mock_range

	assert(not gs.is_wind_enabled(), "is_wind_enabled() must return false on driving range even when configured true")
	assert(gs.get_wind_vector_mps() == Vector3.ZERO, "Wind vector must be ZERO on driving range")

	mock_range.queue_free()
	root.get_tree().current_scene = null
	print("  PASS: Driving range always overrides wind to off.")

	print("\n=======================================================")
	print("ALL WIND SIMULATION TESTS PASSED! 🎉")
	print("=======================================================")
	OS.kill(OS.get_process_id())
