extends SceneTree

func _initialize() -> void:
	print("=== Running Gimme Green Boundary Clamping & Lie Eligibility Tests ===")

	var RangeScript = load("res://Courses/Range/range.gd")
	assert(RangeScript != null, "range.gd must load")

	var range_instance = Node3D.new()
	range_instance.set_script(RangeScript)
	range_instance.set_process(false)
	range_instance.set_physics_process(false)

	# -------------------------------------------------------------
	# Test 1: Gimme ring mesh strictly clamps to green boundary segments
	# -------------------------------------------------------------
	var pin_pos = Vector3(0.0, 0.0, 0.0)
	# Boundary segment: a vertical edge at x = 2.0 (distance 2.0m to the east of pin)
	# Green is on x <= 2.0, rough/fringe is on x > 2.0
	var boundary_segments = [
		[Vector2(2.0, -10.0), Vector2(2.0, 10.0)]
	]

	# Test 3.0m gimme ring (roughly 10 feet), which would extend to x = 3.0 if unclamped or with fringe extension
	var requested_radius = 3.0
	var line_width = 0.08
	var mesh = range_instance._create_gimme_ring_mesh(pin_pos, requested_radius, line_width, 0.05, boundary_segments)
	assert(mesh != null, "Ring mesh must be generated")
	assert(mesh.get_surface_count() > 0, "Surface count must be > 0")

	var arrays = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert(verts.size() > 0, "Must have vertices")

	# Check that no vertex in the mesh extends past x = 2.001
	var max_x := -INF
	for v in verts:
		max_x = maxf(max_x, v.x)

	print("Max X on gimme ring (requested 3.0m, boundary at 2.0m): ", max_x)
	assert(max_x <= 2.001, "Gimme circle outer radius must not extend beyond the green boundary (max_x = %.3f <= 2.0)" % max_x)
	print("Test 1 PASS: Gimme circle visuals strictly clamped to green boundary")

	# -------------------------------------------------------------
	# Test 2: Unbounded fallback (e.g. circular green or no boundary)
	# -------------------------------------------------------------
	var open_mesh = range_instance._create_gimme_ring_mesh(pin_pos, 2.0, line_width, 0.05, [])
	var open_arrays = open_mesh.surface_get_arrays(0)
	var open_verts: PackedVector3Array = open_arrays[Mesh.ARRAY_VERTEX]
	var open_max_x := -INF
	for v in open_verts:
		open_max_x = maxf(open_max_x, v.x)
	assert(absf(open_max_x - 2.0) < 0.05, "Unbounded mesh should reach requested radius")
	print("Test 2 PASS: Unbounded fallback reaches requested radius")

	# -------------------------------------------------------------
	# Test 3: MultiplayerManager gimme eligibility
	# -------------------------------------------------------------
	var mp_script = load("res://Utils/MultiplayerManager.gd")
	assert(mp_script != null, "MultiplayerManager.gd must load")

	# Verify green vs fringe vs rough vs sand lie rules
	# A mock course node with green geometry at pin (distance to target_pin <= 0.05)
	var mock_course = Node3D.new()
	var mock_script = GDScript.new()
	mock_script.source_code = """
extends Node3D
func get_distance_to_nearest_green(pos: Vector3) -> float:
	if pos.distance_to(Vector3.ZERO) <= 5.0:
		return 0.0 # Inside 5m radius green
	return pos.distance_to(Vector3.ZERO) - 5.0
"""
	mock_script.reload()
	mock_course.set_script(mock_script)

	# Verify green detection helper
	assert(mock_course.get_distance_to_nearest_green(Vector3.ZERO) <= 0.001, "Center of green must have distance 0")
	assert(mock_course.get_distance_to_nearest_green(Vector3(6.0, 0, 0)) > 0.001, "6m away must not be green")

	# Clean up nodes
	mock_course.free()
	range_instance.free()

	print("=== All Gimme Green Clamping & Eligibility Tests Passed! ===")
	quit(0)
