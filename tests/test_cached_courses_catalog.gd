extends SceneTree

# Test suite for cached courses catalog and geometry discovery

func _init() -> void:
	print("\n=======================================================")
	print("STARTING TEST: Cached Courses Catalog & Geometry Cache")
	print("=======================================================")

	# 1. Test golf_courses.json catalog size
	print("\n--- Test 1: golf_courses.json contains full catalog ---")
	var catalog_path = "res://Courses/Catalog/golf_courses.json"
	assert(FileAccess.file_exists(catalog_path), "Catalog file must exist at " + catalog_path)

	var file = FileAccess.open(catalog_path, FileAccess.ModeFlags.READ)
	assert(file != null, "Catalog file must be readable")
	var text = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(text)
	assert(err == OK, "Catalog JSON must parse cleanly without errors")
	assert(json.data is Array, "Catalog must be an Array")
	var course_count = json.data.size()
	print("  Found %d courses in golf_courses.json." % course_count)
	assert(course_count > 2500, "Catalog should have thousands of verified courses, got: %d" % course_count)
	print("  PASS: golf_courses.json contains %d courses (far more than 145)." % course_count)

	# 2. Test OsmDownloadDialog loading cached courses
	print("\n--- Test 2: OsmDownloadDialog _load_cached_courses ---")
	var dialog_script = load("res://Courses/OsmDownloadDialog/osm_download_dialog.gd")
	assert(dialog_script != null, "osm_download_dialog.gd must load")

	var dialog = Control.new()
	dialog.set_script(dialog_script)

	# Mock nodes needed by dialog if any
	dialog.call("_load_cached_courses")
	var all_cached: Array = dialog.get("_all_cached_courses")
	print("  _all_cached_courses loaded: %d courses." % all_cached.size())
	assert(all_cached.size() > 2500, "Expected > 2500 verified cached courses, got: %d" % all_cached.size())
	print("  PASS: OsmDownloadDialog loaded %d cached courses." % all_cached.size())

	# Verify PGA Tour & Major courses are prioritized at the top of all_cached
	assert(dialog.call("is_pga_tour_course", all_cached[0]) == true, "First cached course should be a PGA Tour/Major course")
	var saw_non_pga = false
	var pga_count = 0
	for i in range(all_cached.size()):
		var c = all_cached[i]
		var is_pga: bool = dialog.call("is_pga_tour_course", c)
		if is_pga:
			assert(not saw_non_pga, "PGA course '%s' found after non-PGA course at index %d" % [c.get("name", ""), i])
			pga_count += 1
		else:
			saw_non_pga = true
	assert(pga_count > 50, "Expected > 50 PGA Tour courses, got %d" % pga_count)
	print("  PASS: PGA Tour & Major courses (%d) are strictly at the top of the cached list." % pga_count)

	# 3. Test _is_course_cached
	print("\n--- Test 3: _is_course_cached lookup ---")
	var test_course = all_cached[0]
	assert(dialog.call("_is_course_cached", test_course) == true, "Course from all_cached should report cached")
	var dummy_uncached = {"name": "NonExistentCourseXYZ123"}
	assert(dialog.call("_is_course_cached", dummy_uncached) == false, "Non-existent course should report not cached")
	
	# Verify that an uncached catalog course correctly reports false
	var uncached_catalog_course = {"name": "Torrey Pines Golf Course (North)", "is_catalog": true, "is_cached": false}
	assert(dialog.call("_is_course_cached", uncached_catalog_course) == false, "Uncached catalog course must not report cached")

	# Verify that cached course with apostrophe correctly resolves
	var apostrophe_course = {"name": "Bear's Paw Country Club"}
	if FileAccess.file_exists("res://Courses/CachedGeometry/bear_s_paw_country_club.json.gz"):
		assert(dialog.call("_is_course_cached", apostrophe_course) == true, "Bear's Paw Country Club should report cached")
	print("  PASS: _is_course_cached accurately distinguishes cached vs non-cached courses.")

	# 4. Test .gitignore
	print("\n--- Test 4: .gitignore verification ---")
	var gitignore_file = FileAccess.open("res://.gitignore", FileAccess.ModeFlags.READ)
	assert(gitignore_file != null, ".gitignore must exist")
	var gitignore_text = gitignore_file.get_as_text()
	assert(gitignore_text.contains("Courses/CachedGeometry/"), ".gitignore must contain Courses/CachedGeometry/")
	print("  PASS: .gitignore correctly ignores Courses/CachedGeometry/.")

	print("\n=======================================================")
	print("ALL CACHED COURSES TESTS PASSED SUCCESSFULLY!")
	print("=======================================================\n")
	quit(0)
