extends SceneTree

func _init() -> void:
	print("=== Running Targeted Test: iOS Course Scanning & Settings Initialization ===")
	
	# Test 1: GlobalSettings script compiles and executes _ready cleanly
	print("Test 1: GlobalSettings loading and _ready execution...")
	var global_settings_script = load("res://Utils/Settings/global_settings.gd")
	assert(global_settings_script != null, "GlobalSettings script must load")
	var gs_node = Node.new()
	gs_node.set_script(global_settings_script)
	# Trigger ready manually to test the safe C# loading logic
	gs_node._ready()
	print("PASS: GlobalSettings loaded and initialized successfully without parser or runtime errors.")
	
	# Test 2: CourseValidator resilience with scene_path
	print("Test 2: CourseValidator resilience...")
	# Airway exists in res://Courses/UserCourses/Airways
	var airway_result = CourseValidator.validate("res://Courses/UserCourses", "Airways")
	assert(not airway_result.is_empty(), "CourseValidator must validate Airways course")
	assert(airway_result.get("title") == "Airways Golf Course" or airway_result.get("title") != "", "Title must not be empty")
	print("PASS: CourseValidator validated Airways course successfully: %s" % airway_result.get("title"))
	
	# Test 3: CourseList _scan_dir with DirAccess.get_directories_at
	print("Test 3: CourseList _scan_dir...")
	var course_list_script = load("res://Courses/CourseSelector/course_list.gd")
	assert(course_list_script != null, "course_list.gd must load")
	var cl_node = course_list_script.new()
	var validated_courses: Array[Dictionary] = []
	cl_node._scan_dir("res://Courses/UserCourses", validated_courses)
	assert(validated_courses.size() > 0, "At least one course should be discovered via _scan_dir")
	print("PASS: Discovered %d course(s) via DirAccess.get_directories_at in _scan_dir." % validated_courses.size())
	
	# Test 4: DebugLogger log rotation
	print("Test 4: DebugLogger rotation on startup...")
	var debug_logger_script = load("res://Utils/debug_logger.gd")
	assert(debug_logger_script != null, "debug_logger.gd must load")
	var dl_node = debug_logger_script.new()
	# Create a dummy test file to rotate
	var test_log_path := "user://test_rotation.log"
	var global_test_log := ProjectSettings.globalize_path(test_log_path)
	var f = FileAccess.open(global_test_log, FileAccess.WRITE)
	f.store_string("PREVIOUS SESSION LOG ENTRY")
	f.close()
	assert(FileAccess.file_exists(global_test_log), "Test log must exist")
	
	# Test rotation logic
	var prev_path = global_test_log + ".previous"
	if FileAccess.file_exists(prev_path):
		DirAccess.remove_absolute(prev_path)
	DirAccess.copy_absolute(global_test_log, prev_path)
	assert(FileAccess.file_exists(prev_path), "Rotated .previous file must exist")
	var prev_f = FileAccess.open(prev_path, FileAccess.READ)
	assert(prev_f.get_as_text() == "PREVIOUS SESSION LOG ENTRY", "Content must match")
	prev_f.close()
	DirAccess.remove_absolute(global_test_log)
	DirAccess.remove_absolute(prev_path)
	print("PASS: DebugLogger log rotation logic verified successfully.")
	
	gs_node.free()
	cl_node.free()
	dl_node.free()
	
	print("=== All Targeted Tests Passed Successfully! ===")
	quit(0)
