extends SceneTree

var _tested := false

func _process(_delta: float) -> bool:
	if _tested:
		return false
	_tested = true

	print("\n=======================================================")
	print("STARTING TEST: OSM Multi-Course Support & Sub-Course Holes")
	print("=======================================================")

	# 1. Test OsmMapLoader.ExtractSubCourseName
	var loader_script = load("res://Courses/OsmMapLoader.cs")
	assert(loader_script != null, "OsmMapLoader.cs must load")
	
	var loader = loader_script.new()
	assert(loader != null, "OsmMapLoader instance must be created")
	
	# Test ExtractSubCourseName with different tags via reflection / C# invocation
	assert(loader.ExtractSubCourseName({"golf:course:name": "Red"}) == "Red", "ExtractSubCourseName should read golf:course:name")
	assert(loader.ExtractSubCourseName({"course:name": "White"}) == "White", "ExtractSubCourseName should read course:name")
	assert(loader.ExtractSubCourseName({"golf:course": "Blue"}) == "Blue", "ExtractSubCourseName should read golf:course")
	assert(loader.ExtractSubCourseName({"course": "Gold"}) == "Gold", "ExtractSubCourseName should read course")
	assert(loader.ExtractSubCourseName({}) == "", "ExtractSubCourseName should return empty string if no course tag")
	print("  PASS: ExtractSubCourseName tag parsing verified.")

	# 2. Test OsmDownloadDialog hole filtering with multi-course (27-hole) courses
	var dialog_scene = load("res://Courses/OsmDownloadDialog/osm_download_dialog.tscn")
	assert(dialog_scene != null, "osm_download_dialog.tscn must load")
	var dialog = dialog_scene.instantiate()
	root.add_child(dialog)

	var sample_courses = [
		{"name": "Regulation 9", "hole_count": 9},
		{"name": "Regulation 18", "hole_count": 18},
		{"name": "Mid Vallee 27", "hole_count": 27},
		{"name": "Resort 36", "hole_count": 36}
	]

	# Test with 18-hole enabled, 9-hole disabled
	dialog.btn_9_hole.button_pressed = false
	dialog.btn_18_hole.button_pressed = true
	dialog.btn_all_holes.button_pressed = false
	var filtered_18 = dialog._filter_by_hole_settings(sample_courses)
	var names_18 = filtered_18.map(func(c): return c["name"])
	assert(names_18.has("Regulation 18"), "18-hole course must be included")
	assert(names_18.has("Mid Vallee 27"), "27-hole multi-course must be included in 18-hole filter")
	assert(names_18.has("Resort 36"), "36-hole multi-course must be included in 18-hole filter")
	assert(!names_18.has("Regulation 9"), "9-hole course must be excluded when only 18-hole is enabled")
	print("  PASS: 18-hole filter includes multi-course facilities (27 & 36 holes).")

	# Test with 9-hole enabled, 18-hole disabled
	dialog.btn_9_hole.button_pressed = true
	dialog.btn_18_hole.button_pressed = false
	dialog.btn_all_holes.button_pressed = false
	var filtered_9 = dialog._filter_by_hole_settings(sample_courses)
	var names_9 = filtered_9.map(func(c): return c["name"])
	assert(names_9.has("Regulation 9"), "9-hole course must be included")
	assert(names_9.has("Mid Vallee 27"), "27-hole multi-course (divisible by 9) must be included in 9-hole filter")
	assert(names_9.has("Resort 36"), "36-hole multi-course (divisible by 9) must be included in 9-hole filter")
	assert(!names_9.has("Regulation 18"), "18-hole course must be excluded when only 9-hole is enabled")
	print("  PASS: 9-hole filter includes multi-course facilities (27 & 36 holes).")

	# Test with both 9 and 18 enabled
	dialog.btn_9_hole.button_pressed = true
	dialog.btn_18_hole.button_pressed = true
	dialog.btn_all_holes.button_pressed = false
	var filtered_both = dialog._filter_by_hole_settings(sample_courses)
	assert(filtered_both.size() == 4, "Both 9 and 18 enabled must include all sample courses")
	print("  PASS: Both 9 and 18 enabled includes all multi-course and regulation courses.")

	loader.free()
	dialog.queue_free()

	print("\nALL OSM MULTI-COURSE TESTS PASSED! 🎉\n")
	quit(0)
	return false
