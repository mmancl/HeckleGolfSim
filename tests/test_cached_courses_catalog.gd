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
	assert(course_count > 5000, "Catalog should have thousands of courses, got: %d" % course_count)
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
	assert(all_cached.size() > 5000, "Expected > 5000 cached courses, got: %d" % all_cached.size())
	print("  PASS: OsmDownloadDialog loaded %d cached courses." % all_cached.size())

	# 3. Test _is_course_cached
	print("\n--- Test 3: _is_course_cached lookup ---")
	var test_course = all_cached[0]
	assert(dialog.call("_is_course_cached", test_course) == true, "Course from all_cached should report cached")
	var dummy_uncached = {"name": "NonExistentCourseXYZ123"}
	assert(dialog.call("_is_course_cached", dummy_uncached) == false, "Non-existent course should report not cached")
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
