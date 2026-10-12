extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: Course Play Hole Selection & MultiplayerManager Filtering")
	print("=======================================================")

	# 1. Test MultiplayerManager.filter_hole_ids_by_length
	var mp_script = load("res://Utils/MultiplayerManager.gd")
	assert(mp_script != null, "MultiplayerManager.gd must load")

	var sample_25_holes: Array = []
	for i in range(1, 26):
		sample_25_holes.append("Hole %02d" % i)

	# A: Default Front 9 + Back 9
	var filtered_f_b = mp_script.filter_hole_ids_by_length(sample_25_holes, "Front 9, Back 9")
	assert(filtered_f_b.size() == 18, "Front 9, Back 9 must yield 18 holes")
	assert(filtered_f_b[0] == "Hole 01", "Starts with Hole 01")
	assert(filtered_f_b[8] == "Hole 09", "Ends Front 9 with Hole 09")
	assert(filtered_f_b[9] == "Hole 10", "Starts Back 9 with Hole 10")
	assert(filtered_f_b[17] == "Hole 18", "Ends with Hole 18")
	print("  PASS: Front 9 + Back 9 yields holes 1-18.")

	# B: Front 9 + Extra Holes (1-9 and 19-25)
	var filtered_f_e = mp_script.filter_hole_ids_by_length(sample_25_holes, "Front 9, Extra Holes")
	assert(filtered_f_e.size() == 16, "Front 9 (9) + Extra Holes (7) must yield 16 holes")
	assert(filtered_f_e[0] == "Hole 01", "Starts with Hole 01")
	assert(filtered_f_e[8] == "Hole 09", "Ends Front 9 with Hole 09")
	assert(filtered_f_e[9] == "Hole 19", "Next hole is Hole 19")
	assert(filtered_f_e[15] == "Hole 25", "Ends with Hole 25")
	print("  PASS: Front 9 + Extra Holes yields holes 1-9 and 19-25.")

	# C: Back 9 + Extra Holes (10-18 and 19-25)
	var filtered_b_e = mp_script.filter_hole_ids_by_length(sample_25_holes, "Back 9, Extra Holes")
	assert(filtered_b_e.size() == 16, "Back 9 (9) + Extra Holes (7) must yield 16 holes")
	assert(filtered_b_e[0] == "Hole 10", "Starts with Hole 10")
	assert(filtered_b_e[8] == "Hole 18", "Ends Back 9 with Hole 18")
	assert(filtered_b_e[9] == "Hole 19", "Next hole is Hole 19")
	assert(filtered_b_e[15] == "Hole 25", "Ends with Hole 25")
	print("  PASS: Back 9 + Extra Holes yields holes 10-18 and 19-25.")

	# D: Extra Holes only
	var filtered_e = mp_script.filter_hole_ids_by_length(sample_25_holes, "Extra Holes")
	assert(filtered_e.size() == 7, "Extra Holes only must yield 7 holes")
	assert(filtered_e[0] == "Hole 19", "Starts with Hole 19")
	assert(filtered_e[6] == "Hole 25", "Ends with Hole 25")
	print("  PASS: Extra Holes only yields holes 19-25.")

	# E: All three selected
	var filtered_all = mp_script.filter_hole_ids_by_length(sample_25_holes, "Front 9, Back 9, Extra Holes")
	assert(filtered_all.size() == 25, "All 3 selected must yield all 25 holes")
	assert(filtered_all[0] == "Hole 01")
	assert(filtered_all[24] == "Hole 25")
	print("  PASS: All 3 selected yields all 25 holes.")

	# F: Backward compatibility with 'Full 18'
	var filtered_legacy = mp_script.filter_hole_ids_by_length(sample_25_holes, "Full 18")
	assert(filtered_legacy.size() == 18, "Legacy 'Full 18' yields 18 holes")
	print("  PASS: Legacy 'Full 18' backward compatibility verified.")

	# G: Non-consecutive holes with gaps (e.g. Hilly Haven: 21 holes, numbers 1-24)
	var hilly_holes = [
		"Hole 01", "Hole 03", "Hole 05", "Hole 07", "Hole 08", "Hole 09",
		"Hole 10", "Hole 11", "Hole 12", "Hole 13", "Hole 14", "Hole 15", "Hole 16", "Hole 17", "Hole 18",
		"Hole 19", "Hole 20", "Hole 21", "Hole 22", "Hole 23", "Hole 24"
	]
	var hilly_extra = mp_script.filter_hole_ids_by_length(hilly_holes, "Extra Holes")
	assert(hilly_extra.size() == 6, "Hilly Haven Extra Holes must yield all 6 holes 19-24, got %d" % hilly_extra.size())
	assert(hilly_extra[0] == "Hole 19", "Hilly Haven Extra Holes starts with Hole 19 (not skipped!)")
	assert(hilly_extra[1] == "Hole 20", "Hilly Haven Extra Holes includes Hole 20 (not skipped!)")
	assert(hilly_extra[2] == "Hole 21", "Hilly Haven Extra Holes includes Hole 21 (not skipped!)")
	assert(hilly_extra[3] == "Hole 22", "Hilly Haven Extra Holes includes Hole 22")
	assert(hilly_extra[4] == "Hole 23", "Hilly Haven Extra Holes includes Hole 23")
	assert(hilly_extra[5] == "Hole 24", "Hilly Haven Extra Holes includes Hole 24")
	print("  PASS: Non-consecutive holes course correctly includes holes 19, 20, 21 in Extra Holes.")

	var hilly_front = mp_script.filter_hole_ids_by_length(hilly_holes, "Front 9")
	assert(hilly_front.size() == 6, "Hilly Haven Front 9 yields 6 holes")
	var hilly_back = mp_script.filter_hole_ids_by_length(hilly_holes, "Back 9")
	assert(hilly_back.size() == 9, "Hilly Haven Back 9 yields 9 holes (10-18)")
	var hilly_front_extra = mp_script.filter_hole_ids_by_length(hilly_holes, "Front 9, Extra Holes")
	assert(hilly_front_extra.size() == 12, "Hilly Haven Front 9 + Extra Holes yields 12 holes")
	print("  PASS: Non-consecutive Front 9, Back 9, and Extra combinations match expected hole numbers.")

	# 2. Test course_play_setup.gd button toggles and methods
	var setup_script = load("res://Courses/CoursePlay/course_play_setup.gd")
	assert(setup_script != null, "course_play_setup.gd must load")
	var setup = setup_script.new()
	root.add_child(setup)

	# Verify button instances created in _ready
	assert(setup.front_9_btn != null, "front_9_btn exists")
	assert(setup.back_9_btn != null, "back_9_btn exists")
	assert(setup.extra_holes_btn != null, "extra_holes_btn exists")

	# Write dummy config for 27-hole course
	var path_27 = "user://test_27_hole_course.json"
	var f27 = FileAccess.open(path_27, FileAccess.WRITE)
	var holes_27 = {}
	for i in range(1, 28):
		holes_27["Hole %02d" % i] = {"Par": 4}
	f27.store_string(JSON.stringify({"Hole Info": holes_27}))
	f27.close()

	# Test 27-hole course: Front 9 & Back 9 enabled, Extra Holes enabled
	setup.course_list.clear()
	setup.course_list.add_item("Mid Vallee 27")
	setup.course_list.set_item_metadata(0, {"config_path": path_27})
	# Pre-condition: user had only Extra Holes selected previously
	setup.front_9_selected = false
	setup.back_9_selected = false
	setup.extra_holes_selected = true
	setup._update_course_length_options(0)

	# Must auto-default to Front 9 + Back 9 selected for any course with at least 18 holes
	assert(setup.front_9_selected == true, "front_9_selected automatically reset to true")
	assert(setup.back_9_selected == true, "back_9_selected automatically reset to true")
	assert(setup.extra_holes_selected == false, "extra_holes_selected automatically reset to false")
	assert(setup.back_9_btn.disabled == false, "back_9_btn enabled on 27-hole course")
	assert(setup.extra_holes_btn.disabled == false, "extra_holes_btn enabled on 27-hole course")
	assert(setup.selected_length == "Front 9, Back 9", "selected_length is 'Front 9, Back 9'")
	print("  PASS: >= 18-hole course automatically defaults to Front 9 + Back 9 selected even after Extra Holes was picked.")

	# Toggle Extra Holes on -> Front 9, Back 9, Extra Holes
	setup._toggle_length("Extra Holes")
	assert(setup.extra_holes_selected == true, "extra_holes_selected now true")
	assert(setup.selected_length == "Front 9, Back 9, Extra Holes")

	# Toggle Back 9 off -> Front 9, Extra Holes
	setup._toggle_length("Back 9")
	assert(setup.back_9_selected == false, "back_9_selected now false")
	assert(setup.selected_length == "Front 9, Extra Holes")
	print("  PASS: Toggling produced 'Front 9, Extra Holes'.")

	# Ensure at least 1 must remain selected
	setup._toggle_length("Front 9")
	assert(setup.front_9_selected == false)
	assert(setup.selected_length == "Extra Holes")
	# Try toggling Extra Holes off when it's the only one left -> should be prevented
	setup._toggle_length("Extra Holes")
	assert(setup.extra_holes_selected == true, "Cannot deselect the only selected toggle")
	print("  PASS: Cannot deselect the only remaining active toggle.")

	# Test 18-hole course: Extra Holes must be disabled and unselected, Front 9 + Back 9 selected
	var path_18 = "user://test_18_hole_course.json"
	var f18 = FileAccess.open(path_18, FileAccess.WRITE)
	var holes_18 = {}
	for i in range(1, 19):
		holes_18["Hole %02d" % i] = {"Par": 4}
	f18.store_string(JSON.stringify({"Hole Info": holes_18}))
	f18.close()

	setup.course_list.clear()
	setup.course_list.add_item("Regulation 18")
	setup.course_list.set_item_metadata(0, {"config_path": path_18})
	# Prior state was Extra Holes only
	setup.front_9_selected = false
	setup.back_9_selected = false
	setup.extra_holes_selected = true
	setup._update_course_length_options(0)

	assert(setup.front_9_selected == true, "front_9_selected defaults to true on 18-hole course")
	assert(setup.back_9_selected == true, "back_9_selected defaults to true on 18-hole course")
	assert(setup.back_9_btn.disabled == false, "back_9_btn enabled on 18-hole course")
	assert(setup.extra_holes_btn.disabled == true, "extra_holes_btn disabled on 18-hole course")
	assert(setup.extra_holes_selected == false, "extra_holes_selected false on 18-hole course")
	print("  PASS: 18-hole course automatically defaults to Front 9 + Back 9 selected and disables Extra Holes.")

	# Cleanup temp files
	DirAccess.remove_absolute(path_27)
	DirAccess.remove_absolute(path_18)

	print("\nALL COURSE PLAY HOLE SELECTION TESTS PASSED SUCCESSFULLY!")
	print("=======================================================\n")
	quit(0)
	return true
