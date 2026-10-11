extends SceneTree

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=======================================================")
	print("  RUNNING HIT DISTANCE DEBUG TOGGLE & KEYBIND TESTS    ")
	print("=======================================================")

	var root_node = root

	var gs = root_node.get_node_or_null("/root/GlobalSettings")
	if gs == null:
		var gs_script = load("res://Utils/Settings/global_settings.gd")
		gs = gs_script.new()
		gs.name = "GlobalSettings"
		root_node.add_child(gs)

	var km = root_node.get_node_or_null("/root/KeybindingManager")
	if km == null:
		var km_script = load("res://Utils/keybinding_manager.gd")
		km = km_script.new()
		km.name = "KeybindingManager"
		root_node.add_child(km)

	# Ensure default state: debug_show_hit_distance = false
	assert(gs.range_settings.settings.has("debug_show_hit_distance"), "RangeSettings must have debug_show_hit_distance")
	gs.range_settings.debug_show_hit_distance.set_value(false)

	# --- Test 1: KeybindingManager input map state when toggle is OFF ---
	print("\n--- TEST 1: Keybinding disabled when toggle is OFF ---")
	km._apply_action_to_input_map("distance_menu_toggle")
	assert(InputMap.has_action("distance_menu_toggle"), "Action must be defined in InputMap")
	assert(InputMap.action_get_events("distance_menu_toggle").is_empty(), "distance_menu_toggle should have NO events when debug toggle is OFF")
	print("  PASS: Keybind action has 0 input events when debug_show_hit_distance is OFF.")

	# --- Test 2: CoursePlay HitDistanceButton visibility when toggle is OFF vs ON ---
	print("\n--- TEST 2: CoursePlay HitDistanceButton visibility ---")
	var cp_script = load("res://Courses/CoursePlay/course_play.gd")
	var cp = Node3D.new()
	cp.set_script(cp_script)
	root_node.add_child(cp)
	await process_frame

	var cp_dist_btn = cp.find_child("HitDistanceButton", true, false) as Button
	assert(cp_dist_btn != null, "HitDistanceButton must exist in CoursePlay")
	assert(cp_dist_btn.visible == false, "HitDistanceButton must be hidden in CoursePlay when debug toggle is OFF")

	# Turn debug toggle ON
	gs.range_settings.debug_show_hit_distance.set_value(true)
	await process_frame
	assert(cp_dist_btn.visible == true, "HitDistanceButton must be visible in CoursePlay when debug toggle is ON")

	# Turn debug toggle back OFF
	gs.range_settings.debug_show_hit_distance.set_value(false)
	await process_frame
	assert(cp_dist_btn.visible == false, "HitDistanceButton must be hidden again when debug toggle is OFF")
	print("  PASS: CoursePlay HitDistanceButton dynamically respects debug toggle.")

	# --- Test 3: RangeUI HitDistanceButton visibility when toggle is OFF vs ON ---
	print("\n--- TEST 3: RangeUI HitDistanceButton visibility ---")
	var range_scene = load("res://Courses/Range/range.tscn")
	var range_instance = range_scene.instantiate()
	root_node.add_child(range_instance)
	await process_frame
	await process_frame

	var rui = range_instance.get_node_or_null("RangeUI")
	assert(rui != null, "RangeUI must exist in Range scene")
	var rui_dist_btn = rui.find_child("HitDistanceButton", true, false) as Button
	assert(rui_dist_btn != null, "HitDistanceButton must exist in RangeUI")
	assert(rui_dist_btn.visible == false, "HitDistanceButton must be hidden in RangeUI when debug toggle is OFF")

	# Turn debug toggle ON
	gs.range_settings.debug_show_hit_distance.set_value(true)
	await process_frame
	assert(rui_dist_btn.visible == true, "HitDistanceButton must be visible in RangeUI when debug toggle is ON")

	# Check KeybindingManager input events when ON
	km._apply_action_to_input_map("distance_menu_toggle")
	assert(not InputMap.action_get_events("distance_menu_toggle").is_empty(), "distance_menu_toggle must have input events when debug toggle is ON")
	print("  PASS: RangeUI HitDistanceButton and KeybindingManager dynamically update when toggle is ON.")

	# Turn debug toggle OFF
	gs.range_settings.debug_show_hit_distance.set_value(false)
	await process_frame
	assert(rui_dist_btn.visible == false, "HitDistanceButton must be hidden in RangeUI when debug toggle is OFF")
	assert(InputMap.action_get_events("distance_menu_toggle").is_empty(), "distance_menu_toggle must have 0 events when debug toggle is OFF")
	print("  PASS: Keybind and RangeUI button properly disabled when toggled OFF.")

	# --- Test 4: Keybind press handling when toggle is OFF vs ON ---
	print("\n--- TEST 4: Keybind input processing ignored when toggle is OFF ---")
	var dist_menu = rui.find_child("DistanceMenu", true, false)
	assert(dist_menu != null, "DistanceMenu must exist in RangeUI")
	assert(dist_menu.visible == false, "DistanceMenu should start hidden")

	# Call toggle_distance_menu directly while OFF
	rui.toggle_distance_menu()
	assert(dist_menu.visible == false, "DistanceMenu must NOT open via toggle_distance_menu() when debug toggle is OFF")

	# Enable toggle and call toggle_distance_menu
	gs.range_settings.debug_show_hit_distance.set_value(true)
	await process_frame
	rui.toggle_distance_menu()
	assert(dist_menu.visible == true, "DistanceMenu must open via toggle_distance_menu() when debug toggle is ON")

	# Toggle off should close it
	gs.range_settings.debug_show_hit_distance.set_value(false)
	await process_frame
	assert(dist_menu.visible == false, "DistanceMenu must close when debug toggle is turned OFF")
	print("  PASS: DistanceMenu ignore/close behavior verified.")

	# Cleanup
	cp.queue_free()
	range_instance.queue_free()
	await process_frame

	print("\n=======================================================")
	print("  ALL HIT DISTANCE DEBUG TOGGLE TESTS PASSED! 🎉        ")
	print("=======================================================\n")
	quit(0)
