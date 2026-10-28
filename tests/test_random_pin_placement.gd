extends SceneTree

func _initialize():
	_run_tests()

func _run_tests() -> void:
	print("=== Running Random Pin Placement Tests ===")

	# 1. Verify setting is registered in RangeSettings and GlobalSettings
	var RangeSettingsScript = load("res://Utils/Settings/range_settings.gd")
	assert(RangeSettingsScript != null, "range_settings.gd must load")
	var rs = RangeSettingsScript.new()
	assert(rs.settings.has("random_pin_enabled"), "RangeSettings must include 'random_pin_enabled' in its settings dict")
	assert(bool(rs.random_pin_enabled.value) == true, "random_pin_enabled should default to true")

	# 2. Setup mock course with Range script
	var RangeScene = load("res://Courses/Range/range.gd")
	assert(RangeScene != null, "Courses/Range/range.gd must load")

	var range_instance = Node3D.new()
	range_instance.name = "TestCourse"
	range_instance.set_script(RangeScene)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)
	root.add_child(range_instance)

	# Build a 30m x 30m square green centered at (0, 0, 100)
	var green_body = StaticBody3D.new()
	green_body.name = "GreenStatic" # Using CustomCourseBuilder naming style
	green_body.set_meta("surface_type", 4)
	green_body.position = Vector3(0, 0, 100)
	range_instance.add_child(green_body)

	var col_shape = CollisionShape3D.new()
	var concave = ConcavePolygonShape3D.new()
	var verts = PackedVector3Array([
		Vector3(-15, 0, -15), Vector3(15, 0, -15), Vector3(15, 0, 15),
		Vector3(-15, 0, -15), Vector3(15, 0, 15), Vector3(-15, 0, 15)
	])
	concave.data = verts
	col_shape.shape = concave
	green_body.add_child(col_shape)

	await process_frame
	await physics_frame

	range_instance._init_cached_surface_bodies()
	assert(range_instance._cached_green_bodies.size() >= 1, "Must cache green body")

	# Test 1: When random_pin_enabled is false, returns exact base
	GlobalSettings.range_settings.random_pin_enabled.set_value(false)
	var base_loc = [0.0, 100.0]
	var fixed_pin = range_instance.get_hole_location_for(base_loc)
	print("  Fixed pin position: ", fixed_pin)
	assert(is_equal_approx(fixed_pin.x, 0.0) and is_equal_approx(fixed_pin.z, 100.0), "Fixed pin must be at exact base position (0, 0, 100)")
	print("  PASS: random_pin_enabled=false keeps pin in center of green.")

	# Test 2: When random_pin_enabled is true, returns randomized position
	GlobalSettings.range_settings.random_pin_enabled.set_value(true)
	var randomized_pins: Array[Vector3] = []
	for i in range(10):
		var rand_pin = range_instance.get_hole_location_for(base_loc)
		randomized_pins.append(rand_pin)
		# Must be within green bounds (-15 to 15 in X, 85 to 115 in Z)
		assert(rand_pin.x >= -14.0 and rand_pin.x <= 14.0, "Pin X (%f) must be on green" % rand_pin.x)
		assert(rand_pin.z >= 86.0 and rand_pin.z <= 114.0, "Pin Z (%f) must be on green" % rand_pin.z)

	print("  Randomized pins sample: ", randomized_pins[0], ", ", randomized_pins[1], ", ", randomized_pins[2])

	# Check for variance - not all pins should be identical
	var all_identical := true
	for i in range(1, randomized_pins.size()):
		if not randomized_pins[i].is_equal_approx(randomized_pins[0]):
			all_identical = false
			break
	assert(not all_identical, "Random pin must generate different locations across calls")
	print("  PASS: random_pin_enabled=true successfully randomizes pin placement.")

	# Clean up
	range_instance.queue_free()
	print("=== All Random Pin Placement Tests Passed! ===")
	quit(0)
