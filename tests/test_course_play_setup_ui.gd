extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true
	
	print("\n=======================================================")
	print("STARTING TEST: Course Play Setup UI Layout")
	print("=======================================================")
	
	var scene = load("res://Courses/CoursePlay/course_play_setup.tscn")
	assert(scene != null, "course_play_setup.tscn must load successfully")
	var instance = scene.instantiate()
	assert(instance != null, "course_play_setup must instantiate")
	
	root.add_child(instance)
	
	var front_9 = instance.get("front_9_btn")
	var back_9 = instance.get("back_9_btn")
	var full_18 = instance.get("full_18_btn")
	var wind_off = instance.get("wind_off_btn")
	var wind_on = instance.get("wind_on_btn")
	
	assert(front_9 != null, "front_9_btn must exist")
	assert(back_9 != null, "back_9_btn must exist")
	assert(full_18 != null, "full_18_btn must exist")
	assert(wind_off != null, "wind_off_btn must exist")
	assert(wind_on != null, "wind_on_btn must exist")
	
	# Verify that length_selector and wind_selector share the same parent HBoxContainer
	var length_panel = front_9.get_parent().get_parent().get_parent()
	var wind_panel = wind_off.get_parent().get_parent().get_parent()
	assert(length_panel is PanelContainer, "length_selector must be a PanelContainer")
	assert(wind_panel is PanelContainer, "wind_selector must be a PanelContainer")
	assert(length_panel.get_parent() == wind_panel.get_parent(), "length_selector and wind_selector must share the same parent container")
	assert(length_panel.get_parent() is HBoxContainer, "Shared container must be an HBoxContainer")
	print("  PASS: Hole length and wind simulation share the same HBox row.")

	# Verify Green Speed slider exists in right_vbox
	var right_vbox = length_panel.get_parent().get_parent()
	assert(right_vbox is VBoxContainer, "Right column must be a VBoxContainer")
	var found_slider = false
	for child in right_vbox.get_children():
		if child is PanelContainer:
			for sub in child.find_children("", "HSlider", true, false):
				found_slider = true
				break
	assert(found_slider, "Green speed slider must be present below options row in right column")
	print("  PASS: Green speed slider is present in the right column.")

	instance.queue_free()
	print("ALL COURSE PLAY SETUP UI TESTS PASSED! 🎉")
	quit(0)
	return false
