extends SceneTree

func _initialize():
	print("=== Running Manual Hit Aim Distance Test ===")
	
	var dist_menu_script = load("res://UI/distance_menu.gd")
	assert(dist_menu_script != null, "distance_menu.gd must load")
	
	# Test 1: Calculate Aim Distance static helper
	var ball_pos = Vector3(0, 0, 0)
	var target_pos = Vector3(100, 10, 0) # 100m horizontal (~109.36 yds), 10m elevation (~10.94 yds)
	var expected_dist = 100.0 * 1.09361 + 10.0 * 1.09361
	var calculated_dist = dist_menu_script.calculate_aim_distance_yards(ball_pos, target_pos)
	print("Calculated dist: ", calculated_dist, ", expected: ", expected_dist)
	assert(abs(calculated_dist - expected_dist) < 0.01, "Distance calculation must match expected elevation-adjusted yards")
	
	# Test 2: Build shot payload for distance
	var payload_150 = dist_menu_script.build_shot_payload(150.0, "7i")
	print("Payload 150y: ", payload_150)
	assert(abs(payload_150["Speed"] - 105.0) < 0.01, "150y speed should be 105 mph")
	assert(abs(payload_150["VLA"] - 20.0) < 0.01, "150y VLA should be 20 deg")
	assert(abs(payload_150["TotalSpin"] - 6000.0) < 0.01, "150y spin should be 6000 rpm")
	
	# Test 3: Putter payload
	var payload_putt = dist_menu_script.build_shot_payload(25.0, "Pt")
	print("Payload 25y putt: ", payload_putt)
	assert(payload_putt["ShotType"] == "putt", "ShotType must be putt")
	assert(payload_putt["VLA"] == 0.0, "Putter VLA must be 0")
	var expected_putt_speed = 1.8 * sqrt(25.0)
	assert(abs(payload_putt["Speed"] - expected_putt_speed) < 0.01, "Putt speed must follow 1.8 * sqrt(dist)")
	
	# Test 4: Interpolation between 50y and 100y
	var payload_75 = dist_menu_script.build_shot_payload(75.0, "Pw")
	print("Payload 75y: ", payload_75)
	assert(payload_75["Speed"] > 50.0 and payload_75["Speed"] < 82.0, "75y speed should be between 50 and 82")
	
	print("\n=== ALL MANUAL HIT AIM DISTANCE TESTS PASSED! ===")
	quit()
