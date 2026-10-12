extends SceneTree

# test_slope_launch_angle.gd
# Validates that shots hit from uphill, downhill, and sidehill slopes
# adjust launch velocity and spin to match the golfer's stance on the hill
# rather than assuming a level flat horizon.

func _initialize() -> void:
	print("==================================================")
	print("Running Slope Launch Angle Verification Tests")
	print("==================================================")

	var ball_script = load("res://Player/ball.gd")
	if ball_script == null:
		push_error("Could not load ball.gd")
		quit(1)
		return

	# -------------------------------------------------------------
	# Test 1: Flat ground baseline (normal = Vector3.UP)
	# -------------------------------------------------------------
	print("\n--- Test 1: Flat ground baseline (normal = Vector3.UP) ---")
	var speed := 50.0  # m/s
	var vla_deg := 12.0
	var flat_vel := Vector3(speed * cos(deg_to_rad(vla_deg)), speed * sin(deg_to_rad(vla_deg)), 0.0)
	var flat_omega := Vector3(0.0, 0.0, 3000.0 * 0.10472)  # 3000 rpm backspin
	var aim_fwd := Vector3.RIGHT

	var res_flat = ball_script.calculate_slope_adjusted_launch(flat_vel, flat_omega, aim_fwd, Vector3.UP)
	var vel_flat: Vector3 = res_flat["velocity"]
	var om_flat: Vector3 = res_flat["omega"]
	assert(vel_flat.is_equal_approx(flat_vel), "Flat velocity should match input exactly")
	assert(om_flat.is_equal_approx(flat_omega), "Flat spin should match input exactly")
	print("PASS: Flat ground leaves launch vectors unchanged.")

	# -------------------------------------------------------------
	# Test 2: Uphill slope (15 degrees uphill)
	# -------------------------------------------------------------
	print("\n--- Test 2: Uphill slope (15 deg slope, 10 deg club VLA) ---")
	var slope_up_deg := 15.0
	var vla_up_deg := 10.0
	# An uphill slope leaning backward has normal with negative X component
	var norm_uphill := Vector3(-sin(deg_to_rad(slope_up_deg)), cos(deg_to_rad(slope_up_deg)), 0.0).normalized()
	var in_vel_up := Vector3(speed * cos(deg_to_rad(vla_up_deg)), speed * sin(deg_to_rad(vla_up_deg)), 0.0)

	var res_uphill = ball_script.calculate_slope_adjusted_launch(in_vel_up, flat_omega, aim_fwd, norm_uphill)
	var vel_uphill: Vector3 = res_uphill["velocity"]

	# On a 15-degree uphill slope, a 10-degree VLA stance shot should launch at 15 + 10 = 25 degrees in world space
	var expected_world_vla := slope_up_deg + vla_up_deg
	var actual_world_vla := rad_to_deg(atan2(vel_uphill.y, vel_uphill.x))
	print("Uphill world launch angle: %.2f deg (expected: %.2f deg)" % [actual_world_vla, expected_world_vla])
	assert(absf(actual_world_vla - expected_world_vla) < 0.1, "Launch angle on 15 deg hill must match golfer stance (~25 deg)")

	# Verify speed magnitude is strictly preserved
	assert(absf(vel_uphill.length() - speed) < 0.001, "Speed must be preserved through rotation")

	# Verify normal velocity is positive (directed cleanly away from the hill, not into it)
	var norm_component_uphill := vel_uphill.dot(norm_uphill)
	var expected_norm_vel := speed * sin(deg_to_rad(vla_up_deg))
	print("Velocity component perpendicular to slope: %.2f m/s (expected: %.2f m/s)" % [norm_component_uphill, expected_norm_vel])
	assert(absf(norm_component_uphill - expected_norm_vel) < 0.1, "Normal velocity must equal V * sin(VLA)")
	assert(norm_component_uphill > 0.0, "Ball must be flying away from hill, never straight into it")
	print("PASS: Uphill lie correctly launches at stance angle and avoids slamming into the hill.")

	# -------------------------------------------------------------
	# Test 3: Downhill slope (12 degrees downhill)
	# -------------------------------------------------------------
	print("\n--- Test 3: Downhill slope (12 deg slope, 15 deg club VLA) ---")
	var slope_down_deg := 12.0
	var vla_down_deg := 15.0
	# Downhill slope leaning forward has normal with positive X component
	var norm_downhill := Vector3(sin(deg_to_rad(slope_down_deg)), cos(deg_to_rad(slope_down_deg)), 0.0).normalized()
	var in_vel_down := Vector3(speed * cos(deg_to_rad(vla_down_deg)), speed * sin(deg_to_rad(vla_down_deg)), 0.0)

	var res_downhill = ball_script.calculate_slope_adjusted_launch(in_vel_down, flat_omega, aim_fwd, norm_downhill)
	var vel_downhill: Vector3 = res_downhill["velocity"]

	# On a 12-degree downhill slope, a 15-degree VLA shot launches at 15 - 12 = 3 degrees world horizon
	var expected_down_vla := vla_down_deg - slope_down_deg
	var actual_down_vla := rad_to_deg(atan2(vel_downhill.y, vel_downhill.x))
	print("Downhill world launch angle: %.2f deg (expected: %.2f deg)" % [actual_down_vla, expected_down_vla])
	assert(absf(actual_down_vla - expected_down_vla) < 0.1, "Downhill world launch angle must be ~3 deg")
	assert(absf(vel_downhill.length() - speed) < 0.001, "Speed must be preserved")

	var norm_component_downhill := vel_downhill.dot(norm_downhill)
	assert(norm_component_downhill > 0.0, "Ball must clear the descending slope")
	print("PASS: Downhill lie correctly aligns with slope contour.")

	# -------------------------------------------------------------
	# Test 4: Sidehill slope (10 degrees sidehill)
	# -------------------------------------------------------------
	print("\n--- Test 4: Sidehill slope (10 deg slope) ---")
	var slope_side_deg := 10.0
	# Sidehill slope leaning right (+Z)
	var norm_sidehill := Vector3(0.0, cos(deg_to_rad(slope_side_deg)), sin(deg_to_rad(slope_side_deg))).normalized()
	var in_vel_side := Vector3(speed * cos(deg_to_rad(20.0)), speed * sin(deg_to_rad(20.0)), 0.0)

	var res_sidehill = ball_script.calculate_slope_adjusted_launch(in_vel_side, flat_omega, aim_fwd, norm_sidehill)
	var vel_sidehill: Vector3 = res_sidehill["velocity"]
	var om_sidehill: Vector3 = res_sidehill["omega"]

	# In a sidehill lie, the club loft projects a lateral velocity component
	print("Sidehill velocity: %s (Z lateral: %.2f m/s)" % [vel_sidehill, vel_sidehill.z])
	assert(absf(vel_sidehill.z) > 0.5, "Sidehill lie must transfer loft into lateral trajectory")
	assert(absf(vel_sidehill.length() - speed) < 0.001, "Speed must be preserved on sidehill lie")
	assert(absf(om_sidehill.length() - flat_omega.length()) < 0.001, "Spin magnitude must be preserved")
	print("PASS: Sidehill lie correctly rotates velocity and spin along golfer stance.")

	# -------------------------------------------------------------
	# Test 5: Arbitrary aim yaw offset (aiming at 60 degrees)
	# -------------------------------------------------------------
	print("\n--- Test 5: Aim yaw rotated at 60 degrees on uphill slope ---")
	var yaw_deg := 60.0
	var aim_rotated := Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(yaw_deg)).normalized()
	var in_vel_rot := Vector3(speed * cos(deg_to_rad(12.0)), speed * sin(deg_to_rad(12.0)), 0.0).rotated(Vector3.UP, deg_to_rad(yaw_deg))
	# Hill sloping up along the rotated aim direction
	var norm_rot := (-aim_rotated * sin(deg_to_rad(15.0)) + Vector3.UP * cos(deg_to_rad(15.0))).normalized()

	var res_rot = ball_script.calculate_slope_adjusted_launch(in_vel_rot, flat_omega, aim_rotated, norm_rot)
	var vel_rot: Vector3 = res_rot["velocity"]

	assert(absf(vel_rot.length() - speed) < 0.001, "Speed must be preserved with arbitrary yaw")
	var norm_comp_rot := vel_rot.dot(norm_rot)
	assert(absf(norm_comp_rot - (speed * sin(deg_to_rad(12.0)))) < 0.1, "Perpendicular velocity must match VLA")
	print("PASS: Aim yaw correctly preserves 3D stance rotation.")

	print("\n==================================================")
	print("ALL SLOPE LAUNCH TESTS PASSED SUCCESSFULLY!")
	print("==================================================")
	quit(0)
