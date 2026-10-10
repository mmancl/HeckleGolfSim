extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=======================================================")
	print("  RUNNING TOGGLES_CONTAINER SCOPE VALIDATION TEST      ")
	print("=======================================================")

	# 1. Load course_play.gd - verify it compiles without parser errors
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	assert(cp_script != null, "course_play.gd must compile and load successfully without parser errors")

	# 2. Instantiate CoursePlay and check member variable
	var cp = Node3D.new()
	cp.set_script(cp_script)
	root.add_child(cp)
	await process_frame

	assert("toggles_container" in cp, "CoursePlay must have 'toggles_container' property/member")

	# 3. Simulate distance_menu_toggle input event to ensure _unhandled_input resolves toggles_container
	if not InputMap.has_action("distance_menu_toggle"):
		InputMap.add_action("distance_menu_toggle")
	var event = InputEventAction.new()
	event.action = "distance_menu_toggle"
	event.pressed = true
	cp._unhandled_input(event)

	# 4. Clean up
	cp.queue_free()
	await process_frame

	print("  PASS: course_play.gd parsed successfully and toggles_container is valid in scope.")
	print("=======================================================")
	print("  TOGGLES_CONTAINER TEST PASSED!                       ")
	print("=======================================================\n")
	quit(0)
