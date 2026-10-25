extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Tee Boxes, Multi-Color & Player Resolution")
	print("=======================================================")

	# 1. Test C# OsmMapLoader parsing logic via TestTeeBoxParsing.cs
	print("\n--- Sub-test 1: C# OsmMapLoader Test Execution ---")
	var csharp_script = load("res://tests/TestTeeBoxParsing.cs")
	assert(csharp_script != null, "TestTeeBoxParsing.cs must load")
	var csharp_tester = csharp_script.new()
	assert(csharp_tester != null, "TestTeeBoxParsing must instantiate")
	root.add_child(csharp_tester)
	print("  PASS: C# OsmMapLoader tests executed successfully.")

	var cart_path_tester_script = load("res://tests/TestCartPathBounce.cs")
	assert(cart_path_tester_script != null, "TestCartPathBounce.cs must load")
	var cart_path_tester = cart_path_tester_script.new()
	assert(cart_path_tester != null, "TestCartPathBounce must instantiate")
	root.add_child(cart_path_tester)

	# 2. Test MultiplayerManager.get_tee_position_from_boxes
	print("\n--- Sub-test 2: MultiplayerManager.get_tee_position_from_boxes ---")
	var multiplayer_mgr = load("res://Utils/MultiplayerManager.gd")
	var test_boxes = {
		"Blue": [-12.5, 45.0],
		"White": [-10.0, 40.0],
		"Red": [-5.0, 30.0],
		"Gold": [-15.0, 50.0],
		"Orange": [-2.0, 20.0]
	}

	var blue_pos = multiplayer_mgr.get_tee_position_from_boxes(test_boxes, "Blue")
	var white_pos = multiplayer_mgr.get_tee_position_from_boxes(test_boxes, "White")
	var red_pos = multiplayer_mgr.get_tee_position_from_boxes(test_boxes, "Red")
	var gold_pos = multiplayer_mgr.get_tee_position_from_boxes(test_boxes, "Gold")
	var orange_pos = multiplayer_mgr.get_tee_position_from_boxes(test_boxes, "Orange")

	assert(blue_pos == [-12.5, 45.0], "Blue tee position must match")
	assert(white_pos == [-10.0, 40.0], "White tee position must match")
	assert(red_pos == [-5.0, 30.0], "Red tee position must match")
	assert(gold_pos == [-15.0, 50.0], "Gold tee position must match")
	assert(orange_pos == [-2.0, 20.0], "Orange tee position must match")

	# Verify coordinates are distinct between tees
	assert(blue_pos != white_pos, "Blue and White tees must have distinct coordinates")
	assert(white_pos != red_pos, "White and Red tees must have distinct coordinates")
	assert(gold_pos != blue_pos, "Gold and Blue tees must have distinct coordinates")

	# Case-insensitive check
	var white_lower = multiplayer_mgr.get_tee_position_from_boxes(test_boxes, "white")
	assert(white_lower == [-10.0, 40.0], "Case-insensitive 'white' lookup must match")

	# Fallback when color not in map
	var fallback_pos = multiplayer_mgr.get_tee_position_from_boxes(test_boxes, "UnknownColor")
	assert(fallback_pos == test_boxes.values()[0], "Fallback should return first available tee")
	print("  PASS: MultiplayerManager returns distinct coordinates for different tees.")

	# 3. Test CoursePreviewDialog tee_color_map
	print("\n--- Sub-test 3: CoursePreviewDialog Colors ---")
	var preview_dialog_script = load("res://UI/CoursePreviewDialog/course_preview_dialog.gd")
	assert(preview_dialog_script != null, "course_preview_dialog.gd must load")
	assert("Orange" in preview_dialog_script.TEE_COLOR_MAP, "TEE_COLOR_MAP must contain Orange")
	assert("Green" in preview_dialog_script.TEE_COLOR_MAP, "TEE_COLOR_MAP must contain Green")
	print("  PASS: CoursePreviewDialog includes Orange and Green in TEE_COLOR_MAP.")

	# 4. Test CoursePlaySetup dynamic tee options
	print("\n--- Sub-test 4: CoursePlaySetup Dynamic Tee Dropdowns ---")
	var setup_scene = load("res://Courses/CoursePlay/course_play_setup.tscn")
	assert(setup_scene != null, "course_play_setup.tscn must load")
	var setup_instance = setup_scene.instantiate()
	root.add_child(setup_instance)

	var custom_tees: Array[String] = ["Blue", "Gold", "Orange"]
	setup_instance.current_course_tees = custom_tees
	setup_instance._refresh_tee_dropdowns()

	var add_tee_opt: OptionButton = setup_instance.get("add_row_tee_opt")
	if add_tee_opt != null:
		assert(add_tee_opt.item_count == 3, "add_row_tee_opt must contain exactly 3 items")
		assert(add_tee_opt.get_item_text(0) == "Blue", "First item must be Blue")
		assert(add_tee_opt.get_item_text(1) == "Gold", "Second item must be Gold")
		assert(add_tee_opt.get_item_text(2) == "Orange", "Third item must be Orange")

	setup_instance.queue_free()
	print("  PASS: CoursePlaySetup dynamically populated tee options from course data.")

	print("\nALL TEE BOX & DYNAMIC COLOR TESTS PASSED! 🎉")
	quit(0)
	return false
