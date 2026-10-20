extends SceneTree

# Targeted Unit Test Suite for Realistic Golf Flag on Medium/High Graphics & Wind Simulation

func _initialize() -> void:
	print("\n=======================================================")
	print("  Running Realistic Flag & Wind Simulation Tests")
	print("=======================================================\n")

	test_flag_node_structure_and_backward_compatibility()
	test_low_vs_realistic_quality_modes()
	test_wind_direction_alignment()
	test_wind_speed_scaling_parameters()
	test_dynamic_quality_switching()

	print("\n=======================================================")
	print("  ALL REALISTIC FLAG TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)


func test_flag_node_structure_and_backward_compatibility() -> void:
	print("--- Test 1: Flag Node Structure & Backward Compatibility ---")
	var FlagBuilderScript = load("res://Courses/Range/flag_builder.gd")
	var pin = Node3D.new()
	root.add_child(pin)

	FlagBuilderScript.build_flag_pin(pin, 3.0, Color(0.95, 0.12, 0.12), 0.054, "High")

	# Verify required nodes for physics and gameplay
	var pole = pin.get_node_or_null("Pole") as MeshInstance3D
	assert(pole != null, "Pole mesh must exist on FlagPin")
	assert(pole.mesh is CylinderMesh, "Pole mesh must be CylinderMesh")
	print("  PASS: Pole mesh exists.")

	var col = pin.get_node_or_null("FlagstickCollider/CollisionShape") as CollisionShape3D
	assert(col != null, "FlagstickCollider/CollisionShape must exist for physics collision")
	var body = pin.get_node_or_null("FlagstickCollider")
	assert(body.get_meta("is_flagstick") == true, "FlagstickCollider must have is_flagstick meta")
	print("  PASS: Flagstick 3D collider and meta present.")

	var flag = pin.get_node_or_null("Flag") as MeshInstance3D
	assert(flag != null, "Flag MeshInstance3D must exist on FlagPin")
	assert(flag.get_meta("is_golf_flag") == true, "Flag must have is_golf_flag meta")
	print("  PASS: Flag node exists and has golf flag metadata.")

	var cup_white = pin.get_node_or_null("CupWhite") as MeshInstance3D
	assert(cup_white != null, "CupWhite must exist on FlagPin")
	var cup_dark = pin.get_node_or_null("Cup") as MeshInstance3D
	assert(cup_dark != null, "Cup interior must exist on FlagPin")
	print("  PASS: Cup liner and cup interior meshes exist.")

	pin.queue_free()


func test_low_vs_realistic_quality_modes() -> void:
	print("\n--- Test 2: Low vs Medium/High Graphics Quality Modes ---")
	var FlagBuilderScript = load("res://Courses/Range/flag_builder.gd")

	# A. Test Low Quality Mode
	var pin_low = Node3D.new()
	root.add_child(pin_low)
	FlagBuilderScript.build_flag_pin(pin_low, 3.0, Color(0.9, 0.1, 0.1), 0.054, "Low")
	var flag_low = pin_low.get_node_or_null("Flag") as MeshInstance3D
	assert(flag_low != null, "Flag must exist on Low")
	assert(not flag_low.get("is_realistic"), "Low quality must NOT be in realistic mode")
	assert(flag_low.material_override is StandardMaterial3D, "Low quality must use lightweight StandardMaterial3D")
	var finial_low = pin_low.get_node_or_null("Finial")
	assert(finial_low == null or not finial_low.visible, "Finial hardware must not be visible on Low")
	print("  PASS: Low quality uses lightweight StandardMaterial3D without extra hardware overhead.")

	# B. Test High Quality Mode
	var pin_high = Node3D.new()
	root.add_child(pin_high)
	FlagBuilderScript.build_flag_pin(pin_high, 3.0, Color(0.9, 0.1, 0.1), 0.054, "High")
	var flag_high = pin_high.get_node_or_null("Flag") as MeshInstance3D
	assert(flag_high != null, "Flag must exist on High")
	assert(flag_high.get("is_realistic"), "High quality MUST be in realistic mode")
	assert(flag_high.material_override is ShaderMaterial, "High quality MUST use ShaderMaterial")
	var sm = flag_high.material_override as ShaderMaterial
	assert(sm.shader != null, "Shader must be assigned to ShaderMaterial")
	assert(sm.shader.resource_path.ends_with("golf_flag.gdshader"), "Shader must be golf_flag.gdshader")

	# Hardware finial & collars should be present on High
	var finial_high = pin_high.get_node_or_null("Finial") as MeshInstance3D
	assert(finial_high != null and finial_high.visible, "Finial acorn knob must exist and be visible on High")
	var top_collar = pin_high.get_node_or_null("TopCollar") as MeshInstance3D
	var bot_collar = pin_high.get_node_or_null("BottomCollar") as MeshInstance3D
	assert(top_collar != null and top_collar.visible, "Top swivel collar must be visible on High")
	assert(bot_collar != null and bot_collar.visible, "Bottom swivel collar must be visible on High")
	print("  PASS: High quality uses realistic subdivided mesh, golf_flag.gdshader, and pole hardware.")

	pin_low.queue_free()
	pin_high.queue_free()


func test_wind_direction_alignment() -> void:
	print("\n--- Test 3: Wind Direction Dynamic Alignment (Blowing Downwind) ---")
	var FlagBuilderScript = load("res://Courses/Range/flag_builder.gd")
	var pin = Node3D.new()
	root.add_child(pin)
	FlagBuilderScript.build_flag_pin(pin, 3.0, Color.RED, 0.054, "High")
	var flag = pin.get_node_or_null("Flag") as MeshInstance3D
	assert(flag != null)

	var gs = root.get_node_or_null("GlobalSettings")
	var had_gs = gs != null

	# Test 4 cardinal wind directions
	var test_headings = [
		{"name": "East (+X)", "rad": 0.0, "expected_vec": Vector3(1.0, 0.0, 0.0)},
		{"name": "South (+Z)", "rad": PI * 0.5, "expected_vec": Vector3(0.0, 0.0, 1.0)},
		{"name": "West (-X)", "rad": PI, "expected_vec": Vector3(-1.0, 0.0, 0.0)},
		{"name": "North (-Z)", "rad": PI * 1.5, "expected_vec": Vector3(0.0, 0.0, -1.0)}
	]

	for entry in test_headings:
		flag.call("set_wind", 12.0, entry["rad"])

		# The flag cloth extends along local +X (from flagpole x=0 outwards to tip x=w).
		# Transforming local Vector3(1, 0, 0) by flag's basis yields the direction the flag is pointing.
		var basis = flag.global_transform.basis if flag.is_inside_tree() else flag.transform.basis
		var flag_pointing_dir = (basis * Vector3(1.0, 0.0, 0.0)).normalized()
		var expected: Vector3 = entry["expected_vec"]
		var dot = flag_pointing_dir.dot(expected)

		assert(dot > 0.99, "Flag must point downwind towards %s! Expected: %s, got: %s (dot: %f)" % [entry["name"], str(expected), str(flag_pointing_dir), dot])
		print("  PASS: Flag correctly streams downwind towards %s (dot=%.4f)" % [entry["name"], dot])

	pin.queue_free()


func test_wind_speed_scaling_parameters() -> void:
	print("\n--- Test 4: Wind Speed Scaling on Wave Amplitude, Speed & Droop ---")
	var FlagBuilderScript = load("res://Courses/Range/flag_builder.gd")
	var pin = Node3D.new()
	root.add_child(pin)
	FlagBuilderScript.build_flag_pin(pin, 3.0, Color.RED, 0.054, "High")
	var flag = pin.get_node_or_null("Flag") as MeshInstance3D
	var sm = flag.material_override as ShaderMaterial
	assert(sm != null)

	# A. Light wind (2 MPH): slow wave speed, low amplitude, high gravity droop
	flag.call("_update_shader_parameters", 2.0)
	var speed_light = sm.get_shader_parameter("wave_speed")
	var amp_light = sm.get_shader_parameter("wave_amplitude")
	var droop_light = sm.get_shader_parameter("droop_amount")

	# B. Strong wind (22 MPH): fast wave speed, higher amplitude, minimal droop (taut)
	flag.call("_update_shader_parameters", 22.0)
	var speed_strong = sm.get_shader_parameter("wave_speed")
	var amp_strong = sm.get_shader_parameter("wave_amplitude")
	var droop_strong = sm.get_shader_parameter("droop_amount")

	assert(speed_strong > speed_light, "Strong wind must produce faster traveling wave speed")
	assert(amp_strong > amp_light, "Strong wind must produce deeper billowing wave amplitude")
	assert(droop_strong < droop_light, "Strong wind must lift the flag taut with less gravity droop")

	print("  PASS: Light Wind (2 MPH)   -> Speed: %.2f, Amplitude: %.3f, Droop: %.3f" % [speed_light, amp_light, droop_light])
	print("  PASS: Strong Wind (22 MPH) -> Speed: %.2f, Amplitude: %.3f, Droop: %.3f" % [speed_strong, amp_strong, droop_strong])

	pin.queue_free()


func test_dynamic_quality_switching() -> void:
	print("\n--- Test 5: Dynamic Graphics Quality Switching ---")
	var FlagBuilderScript = load("res://Courses/Range/flag_builder.gd")
	var pin = Node3D.new()
	root.add_child(pin)
	FlagBuilderScript.build_flag_pin(pin, 3.0, Color.RED, 0.054, "Low")
	var flag = pin.get_node_or_null("Flag") as MeshInstance3D

	# 1. Start at Low
	assert(flag.material_override is StandardMaterial3D, "Should start with StandardMaterial3D")

	# 2. Switch to Medium
	FlagBuilderScript.apply_graphics_quality_to_flags(pin, "Medium")
	assert(flag.material_override is ShaderMaterial, "Medium quality should switch to ShaderMaterial")
	assert(flag.get("is_realistic") == true, "Medium quality should be realistic")

	# 3. Switch to High
	FlagBuilderScript.apply_graphics_quality_to_flags(pin, "High")
	assert(flag.material_override is ShaderMaterial, "High quality should remain ShaderMaterial")
	assert(flag.get("is_realistic") == true, "High quality should be realistic")

	# 4. Switch back to Low
	FlagBuilderScript.apply_graphics_quality_to_flags(pin, "Low")
	assert(flag.material_override is StandardMaterial3D, "Low quality should revert to StandardMaterial3D")
	assert(flag.get("is_realistic") == false, "Low quality should not be realistic")

	print("  PASS: Seamless dynamic switching Low -> Medium -> High -> Low verified.")
	pin.queue_free()
