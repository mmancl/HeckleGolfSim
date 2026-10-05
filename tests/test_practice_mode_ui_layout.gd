extends SceneTree

var _tested := false

func _initialize() -> void:
	print("=== Running Practice Mode UI Layout Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	var scene = load("res://Courses/CourseSelector/course_selector.tscn")
	assert(scene != null, "course_selector.tscn must be loadable")

	var instance = scene.instantiate()
	root.add_child(instance)
	current_scene = instance

	await process_frame
	await process_frame

	print("\n--- Test 1: Course Directory section & Ready text removal ---")
	var course_dir_node = instance.find_child("CourseDirectory", true, false)
	assert(course_dir_node == null, "CourseDirectory section must be removed from Practice Mode scene")
	
	var status_label_node = instance.find_child("StatusLabel", true, false)
	assert(status_label_node == null, "StatusLabel / Ready text must be removed from Practice Mode scene")
	print("  PASS: Course Directory and Ready text are not present.")

	print("\n--- Test 2: Hole Length & Wind Selector share same line ---")
	var front_9 = instance.front_9_btn
	var back_9 = instance.back_9_btn
	var full_18 = instance.full_18_btn
	assert(front_9 != null and is_instance_valid(front_9), "Front 9 button must exist")
	assert(back_9 != null and is_instance_valid(back_9), "Back 9 button must exist")
	assert(full_18 != null and is_instance_valid(full_18), "Full 18 button must exist")

	var check_btn: CheckButton = null
	for child in instance.find_children("*", "CheckButton", true, false):
		if child is CheckButton:
			check_btn = child
			break
	assert(check_btn != null, "Wind Simulation toggle CheckButton must exist")

	# Find panel parents:
	# front_9 -> seg_hbox -> hbox -> length_panel
	var length_panel = front_9.get_parent().get_parent().get_parent()
	# check_btn -> hbox -> wind_panel
	var wind_panel = check_btn.get_parent().get_parent()
	assert(length_panel is PanelContainer, "Length panel must be a PanelContainer")
	assert(wind_panel is PanelContainer, "Wind panel must be a PanelContainer")

	# Both should share the same parent HBoxContainer
	var shared_parent = length_panel.get_parent()
	assert(shared_parent is HBoxContainer, "Length selector and Wind selector must be inside an HBoxContainer")
	assert(wind_panel.get_parent() == shared_parent, "Length selector and Wind selector must share the same parent row")
	print("  PASS: Hole length selector and Wind simulation share the same line.")

	print("\n=======================================================")
	print("ALL PRACTICE MODE UI LAYOUT TESTS PASSED! 🎉")
	print("=======================================================")

	instance.queue_free()
	quit(0)
