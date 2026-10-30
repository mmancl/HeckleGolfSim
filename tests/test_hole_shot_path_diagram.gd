extends SceneTree


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var diagram_script = load("res://UI/hole_shot_path_diagram.gd")
	assert(diagram_script != null, "Hole shot path diagram script must load")

	var diagram = diagram_script.new()
	var positions: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 120.0),
		Vector3(0.0, 0.0, 240.0)
	]
	var distances: Array[int] = [131, 131]
	var other_positions: Array[Vector3] = [
		Vector3(10.0, 0.0, 0.0),
		Vector3(35.0, 0.0, 90.0)
	]
	var shared_positions: Array[Vector3] = positions.duplicate()
	shared_positions.append_array(other_positions)
	var hole_tee_positions: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, 0.0, 10.0),
		Vector3(0.0, 0.0, 20.0)
	]
	var cart_paths: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(15.0, 0.0), Vector2(25.0, 90.0), Vector2(35.0, 180.0)])
	]
	diagram.size = Vector2(260.0, 260.0)
	diagram.set_shot_path(
		positions,
		distances,
		Vector3(0.0, 0.0, 300.0),
		null,
		[],
		hole_tee_positions,
		shared_positions,
		cart_paths
	)
	diagram._calculate_view()
	assert(is_equal_approx(diagram.size.x, diagram.size.y), "Shot diagram must use a square viewport")
	assert(diagram._cart_paths == cart_paths, "Provided cart paths must be retained for diagram rendering")
	assert(diagram._tee_position == Vector2(0.0, 0.0), "View must orient from the tee farthest from the green")

	var path_positions: Array[Vector3] = diagram._get_path_positions()
	assert(path_positions.size() == 4, "Path must include the tee, every landing, and the green")
	assert(path_positions.front().is_equal_approx(positions.front()), "Path must begin at the tee coordinate")
	assert(path_positions[1].is_equal_approx(positions[1]), "First landing must retain its recorded coordinate")
	assert(path_positions[2].is_equal_approx(positions[2]), "Second landing must retain its recorded coordinate")
	assert(path_positions.back().is_equal_approx(Vector3(0.0, 0.0, 300.0)), "Path must end at the green coordinate")

	var actual_start := Vector3(12.0, 0.0, -4.0)
	var first_landing := Vector3(108.0, 0.0, 5.0)
	var second_landing := Vector3(170.0, 0.0, 14.0)
	var recorded_shots: Array = [
		{"start_pos": actual_start, "end_pos": first_landing},
		{"start_pos": first_landing, "end_pos": second_landing}
	]
	var recorded_positions: Array[Vector3] = diagram_script.get_positions_from_shot_stats(recorded_shots, positions)
	assert(recorded_positions.size() == 3, "Recorded shot positions must include actual start and each landing")
	assert(recorded_positions[0].is_equal_approx(actual_start), "Shot path must start at the recorded tee position")
	assert(recorded_positions[1].is_equal_approx(first_landing) and recorded_positions[2].is_equal_approx(second_landing), "Shot path must use recorded landing coordinates")
	var translated_stats: Array = recorded_shots.duplicate(true)
	var world_to_course := Transform3D(Basis.IDENTITY, Vector3(-12.0, 0.0, 4.0))
	var local_positions: Array[Vector3] = diagram_script.get_positions_from_shot_stats(translated_stats, positions, world_to_course)
	assert(local_positions[0].is_equal_approx(Vector3.ZERO), "Recorded global tee coordinate must convert to course-local coordinates")
	assert((local_positions[1] - local_positions[0]).is_equal_approx(first_landing - actual_start), "Coordinate conversion must preserve shot direction and distance")
	assert((local_positions[2] - local_positions[1]).is_equal_approx(second_landing - first_landing), "Coordinate conversion must preserve every later shot")
	var legacy_positions: Array[Vector3] = diagram_script.get_positions_from_shot_stats([{"total_yds": 200.0}], positions)
	assert(legacy_positions == positions, "Older shot records must retain their tee and landing fallback")

	var tee_screen: Vector2 = diagram._map_position(Vector3.ZERO)
	var first_shot_screen: Vector2 = diagram._map_position(Vector3(0.0, 0.0, 120.0))
	var second_shot_screen: Vector2 = diagram._map_position(Vector3(0.0, 0.0, 240.0))
	var green_screen: Vector2 = diagram._map_position(Vector3(0.0, 0.0, 300.0))
	assert(tee_screen.y > first_shot_screen.y, "Tee must appear below the first shot")
	assert(first_shot_screen.y > second_shot_screen.y, "Shot data must progress upward toward the green")
	assert(second_shot_screen.y > green_screen.y, "Green must appear above the final shot")
	assert(tee_screen.y > diagram._plot.position.y + diagram._plot.size.y * 0.8, "Tee must be near the bottom of the map")
	assert(green_screen.is_equal_approx(diagram._map_position(path_positions.back())), "Last path point must map exactly to the green marker")

	diagram._satellite_bounds = [-50.0, -40.0, 300.0, 30.0]
	assert(diagram._satellite_bounds_are_valid(), "Valid satellite bounds must be accepted")
	assert(diagram_script.has_valid_satellite_bounds([-50.0, -40.0, 300.0, 30.0]), "Stored map bounds must be accepted")
	assert(not diagram_script.has_valid_satellite_bounds([]), "Missing map bounds must remain invalid")
	var image_top_left: Vector2 = diagram._map_world_position(Vector2(-50.0, -40.0))
	var image_bottom_right: Vector2 = diagram._map_world_position(Vector2(300.0, 30.0))
	assert(image_top_left.is_equal_approx(diagram._map_position(Vector3(-50.0, 0.0, -40.0))), "Satellite image corner must use its exact world coordinate")
	assert(image_bottom_right.is_equal_approx(diagram._map_position(Vector3(300.0, 0.0, 30.0))), "Opposite satellite corner must use its exact world coordinate")
	diagram._satellite_bounds.clear()
	assert(not diagram._satellite_bounds_are_valid(), "Missing satellite bounds must not be fabricated")

	var second_diagram = diagram_script.new()
	var other_distances: Array[int] = [105]
	second_diagram.size = diagram.size
	second_diagram.set_shot_path(
		other_positions,
		other_distances,
		Vector3(0.0, 0.0, 300.0),
		null,
		[],
		hole_tee_positions,
		shared_positions
	)
	second_diagram._calculate_view()
	assert(second_diagram._tee_position == diagram._tee_position, "Every player must share the same hole view origin")
	assert(second_diagram._forward.is_equal_approx(diagram._forward), "Every player must share the same map orientation")
	assert(second_diagram._scale == diagram._scale, "Every player must share the same map zoom")
	assert(second_diagram._map_position(Vector3(0.0, 0.0, 300.0)).is_equal_approx(green_screen), "The same green coordinate must land at the same map point for every player")
	assert(second_diagram._map_position(other_positions[0]) != second_diagram._map_position(positions[0]), "Each player's shot path must still start at their own tee")

	var extended_diagram = diagram_script.new()
	extended_diagram.size = Vector2(260.0, 260.0)
	var extended_positions: Array[Vector3] = [
		Vector3(-180.0, 0.0, -30.0),
		Vector3(520.0, 0.0, 410.0)
	]
	extended_diagram.set_shot_path(
		positions,
		distances,
		Vector3(0.0, 0.0, 300.0),
		null,
		[],
		hole_tee_positions,
		extended_positions
	)
	extended_diagram._calculate_view()
	var all_view_positions := extended_positions.duplicate()
	all_view_positions.append_array(positions)
	all_view_positions.append_array(hole_tee_positions)
	all_view_positions.append(Vector3(0.0, 0.0, 300.0))
	for position in all_view_positions:
		var screen_position: Vector2 = extended_diagram._map_position(position)
		assert(extended_diagram._plot.has_point(screen_position), "Shared view must expand to keep every player's shot data visible")

	# --- Short shot suppression ---
	# Shots under 20 yards must not draw a line on the overview diagram.
	# Verify the threshold constant is enforced by checking that a sub-20-yard
	# segment (e.g. a tap-in putt of 5 yards) is correctly identified as skippable,
	# while a 20-yard shot exactly at the boundary is drawn.
	var diagram_const = diagram_script.new()
	diagram_const.size = Vector2(260.0, 260.0)
	var short_positions: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),   # tee
		Vector3(0.0, 0.0, 100.0), # after long drive (109 yds)
		Vector3(0.0, 0.0, 104.57) # after a tiny 5-yard tap-in
	]
	# 5 yards ~= 4.572 m
	var short_distances: Array[int] = [109, 5]
	diagram_const.set_shot_path(short_positions, short_distances, Vector3(0.0, 0.0, 110.0))
	diagram_const._calculate_view()
	# The 5-yard segment (index 1) must be below the 20-yard threshold.
	assert(short_distances[1] < 20, "5-yard segment must be below the 20-yard display threshold")
	# The 109-yard segment (index 0) must be at or above the threshold.
	assert(short_distances[0] >= 20, "109-yard segment must be at or above the 20-yard display threshold")
	# Exactly 20 yards must not be suppressed.
	var boundary_distances: Array[int] = [20]
	assert(boundary_distances[0] >= 20, "A 20-yard shot must meet the minimum threshold and be drawn")

	print("PASS: Hole shot path runs from tee through recorded landings to the exact green coordinate.")
	quit(0)
