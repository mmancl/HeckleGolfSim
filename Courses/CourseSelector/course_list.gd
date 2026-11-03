extends ItemList

var course_dir := ""


var filter_mode: String = "Real" # "Real", "Custom", or "All"


## Scan the course directory, validate each course, repopulate the list,
## and return the count (-1 on open failure).
func parse_directory(path: String) -> int:
	clear()
	if path.is_empty() or path == "res://Courses/UserCourses":
		path = "user://courses"
	if path.ends_with("/"):
		path = path.substr(0, path.length() - 1)
	course_dir = path
	print("[CourseList] Scanning directory: %s" % course_dir)

	var validated: Array[Dictionary] = []

	_scan_dir(course_dir, validated)
	if course_dir != "user://courses":
		_scan_dir("user://courses", validated)

	validated.sort_custom(func(a, b): return a["dir_name"] < b["dir_name"])
	for course in validated:
		var is_custom: bool = course.get("is_custom", false)
		if filter_mode == "Real" and is_custom:
			continue
		elif filter_mode == "Custom" and not is_custom:
			continue

		var item_index := get_item_count()
		var display_title: String = str(course.get("title", ""))
		var is_corrupt: bool = bool(course.get("is_corrupted", false))
		if is_corrupt:
			display_title += " [Corrupted - Redownload]"
		add_item(display_title)
		if is_corrupt:
			set_item_tooltip(item_index, "This course scene file is corrupted. Please delete it and redownload it from the Course Catalog.")
			set_item_custom_fg_color(item_index, Color(0.95, 0.45, 0.45))
		set_item_metadata(item_index, course)

	print("[CourseList] Found %d valid course(s) for filter '%s'." % [get_item_count(), filter_mode])
	return get_item_count()


func set_filter_mode(mode: String) -> void:
	filter_mode = mode
	var target_path = course_dir if not course_dir.is_empty() and course_dir != "res://Courses/UserCourses" else "user://courses"
	parse_directory(target_path)


func _scan_dir(dir_path: String, validated: Array[Dictionary]) -> void:
	if dir_path.begins_with("res://Courses/UserCourses"):
		return
	var path_to_scan = dir_path
	if not DirAccess.dir_exists_absolute(path_to_scan):
		var global_dir = ProjectSettings.globalize_path(dir_path)
		if DirAccess.dir_exists_absolute(global_dir):
			path_to_scan = global_dir
		else:
			return
	var dir_names := DirAccess.get_directories_at(path_to_scan)
	if dir_names.is_empty() and path_to_scan == dir_path:
		var global_dir = ProjectSettings.globalize_path(dir_path)
		if DirAccess.dir_exists_absolute(global_dir):
			dir_names = DirAccess.get_directories_at(global_dir)
			if not dir_names.is_empty():
				path_to_scan = global_dir

	for dir_name in dir_names:
		if not dir_name.begins_with("."):
			var lower_name = dir_name.to_lower()
			if lower_name == "airways" or lower_name == "dragonfly" or lower_name == "dragon_fly":
				continue
			var result: Dictionary = CourseValidator.validate(path_to_scan, dir_name)
			if not result.is_empty():
				result["dir_name"] = dir_name
				validated.append(result)


## Normalize a reload request and return a status string.
func reload_courses(path: String) -> String:
	var normalized_path := path.strip_edges()
	print("[CourseList] Refresh requested. Path: %s" % normalized_path)
	var course_count: int = parse_directory(normalized_path)
	var stamp := str(Time.get_ticks_msec())

	if course_count < 0:
		printerr("[CourseList] Refresh failed. Invalid course directory: %s" % normalized_path)
		return "Refresh [%s]: invalid course directory" % stamp

	if course_count == 0:
		print("[CourseList] Refresh completed. No valid courses found.")
		return "Refresh [%s]: no valid courses found" % stamp

	print("[CourseList] Refresh completed. Loaded %d course(s)." % course_count)
	return ""


func get_scene_path_for_index(selected_index: int) -> String:
	if selected_index < 0 or selected_index >= get_item_count():
		printerr("[CourseList] Selected course index is out of bounds.")
		return ""
	return get_item_metadata(selected_index).get("scene_path", "")


func get_config_path_for_index(selected_index: int) -> String:
	if selected_index < 0 or selected_index >= get_item_count():
		printerr("[CourseList] Selected course index is out of bounds.")
		return ""
	return get_item_metadata(selected_index).get("config_path", "")
