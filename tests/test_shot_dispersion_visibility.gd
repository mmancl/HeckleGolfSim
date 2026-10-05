extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Shot Dispersion Visibility Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	print("\n--- Test 1: Dispersion on Driving Range vs Course Play ---")
	var RangeUIScene = load("res://UI/range_ui.tscn")
	assert(RangeUIScene != null, "range_ui.tscn must load")

	# Scenario A: Under a Course scene (Course Play)
	var course_node = Node3D.new()
	course_node.name = "Airways"
	course_node.scene_file_path = "res://Courses/UserCourses/Airways/course.tscn"
	course_node.set("is_driving_range", false)
	root.add_child(course_node)

	var course_range_ui = RangeUIScene.instantiate()
	course_node.add_child(course_range_ui)
	await process_frame

	assert(not course_range_ui.is_driving_range(), "RangeUI on course scene must report is_driving_range() == false")

	# Attempt to show dispersion in Course Play
	var sample_shots: Array[Dictionary] = [
		{"carry": 250.0, "offline": 5.0, "club": "Dr"},
		{"carry": 245.0, "offline": -3.0, "club": "Dr"},
		{"carry": 255.0, "offline": 8.0, "club": "Dr"}
	]
	course_range_ui.show_dispersion(sample_shots, "Dr")
	await process_frame

	var dispersion_on_course = course_range_ui.get_node_or_null("OverlayLayer/DispersionOverlay")
	var is_course_disp_vis = dispersion_on_course != null and dispersion_on_course.visible
	assert(not is_course_disp_vis, "Dispersion overlay MUST NOT be visible during course play")
	print("  PASS: Dispersion window is not visible in course play.")

	# Scenario B: Under Driving Range scene
	var range_node = Node3D.new()
	range_node.name = "Range"
	range_node.scene_file_path = "res://Courses/Range/range.tscn"
	range_node.set("is_driving_range", true)
	root.add_child(range_node)

	var range_ui = RangeUIScene.instantiate()
	range_node.add_child(range_ui)
	await process_frame

	assert(range_ui.is_driving_range(), "RangeUI on range scene must report is_driving_range() == true")

	# With shot traces active on range -> show_dispersion should display overlay
	assert(range_ui.is_shot_traces_active(), "Shot traces should default to active")
	range_ui.show_dispersion(sample_shots, "Dr")
	await process_frame

	var dispersion_on_range = range_ui.get_node_or_null("OverlayLayer/DispersionOverlay")
	assert(dispersion_on_range != null, "Dispersion overlay must exist on range")
	assert(dispersion_on_range.visible, "Dispersion overlay must be visible on range when shot traces are active")
	print("  PASS: Dispersion window is visible on driving range when shot traces are on.")

	# Test toggling shot traces off
	range_ui.toggle_shot_traces()
	await process_frame
	assert(not range_ui.is_shot_traces_active(), "Shot traces should now be inactive")
	assert(not dispersion_on_range.visible, "Dispersion overlay must be hidden when shot traces are turned off")
	print("  PASS: Dispersion window hides when shot traces are toggled off.")

	# Attempt to show dispersion while shot traces are off
	range_ui.show_dispersion(sample_shots, "Dr")
	await process_frame
	assert(not dispersion_on_range.visible, "Dispersion overlay must remain hidden while shot traces are off")
	print("  PASS: show_dispersion ignored when shot traces are off.")

	# Toggle shot traces back on
	range_ui.toggle_shot_traces()
	await process_frame
	assert(range_ui.is_shot_traces_active(), "Shot traces should now be active")
	range_ui.show_dispersion(sample_shots, "Dr")
	await process_frame
	assert(dispersion_on_range.visible, "Dispersion overlay should be visible again after re-enabling traces and calling show_dispersion")
	print("  PASS: Dispersion overlay displays properly when re-enabled.")

	# Clean up
	course_node.queue_free()
	range_node.queue_free()
	await process_frame

	print("\n=== ALL SHOT DISPERSION VISIBILITY TESTS PASSED ===")
	quit(0)
