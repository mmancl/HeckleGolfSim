class_name CourseValidator

const COURSE_CONFIG_FILE := "course.json"
const COURSE_SCENE_FILE := "course.tscn"
const COURSE_TITLE_KEY := "Title"
const COURSE_INFO_KEY := "Course Info"


## Validates a single course directory. Returns a dictionary with "title",
## "scene_path", and "config_path" on success, or an empty dictionary on failure.
static func validate(course_dir: String, dir_name: String) -> Dictionary:
	var config_path := "%s/%s/%s" % [course_dir, dir_name, COURSE_CONFIG_FILE]

	if not FileAccess.file_exists(config_path):
		printerr("[CourseValidator] Missing %s for course '%s'." % [COURSE_CONFIG_FILE, dir_name])
		return {}

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		printerr("[CourseValidator] Unable to read course config: %s" % config_path)
		return {}

	var json_text := file.get_as_text()
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("[CourseValidator] Invalid JSON in %s." % config_path)
		return {}

	var title := _extract_title(parsed, dir_name)
	var scene_path := "%s/%s/%s" % [course_dir, dir_name, COURSE_SCENE_FILE]
	if not ResourceLoader.exists(scene_path) and not FileAccess.file_exists(scene_path) and not FileAccess.file_exists(scene_path + ".remap"):
		if dir_name.begins_with("custom_") and course_dir.begins_with("user://"):
			print("[CourseValidator] Cleaning up incomplete custom course folder: %s" % dir_name)
			_delete_dir_recursive(course_dir.path_join(dir_name))
		else:
			printerr("[CourseValidator] Missing %s for course '%s'." % [COURSE_SCENE_FILE, dir_name])
		return {}

	var is_custom: bool = parsed.get("is_custom", false) or parsed.get("IsCustom", false) or dir_name.begins_with("custom_")
	return { "title": title, "scene_path": scene_path, "config_path": config_path, "is_custom": is_custom }


static func _delete_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var files := DirAccess.get_files_at(path)
	for f in files:
		DirAccess.remove_absolute(path.path_join(f))
	var subdirs := DirAccess.get_directories_at(path)
	for d in subdirs:
		_delete_dir_recursive(path.path_join(d))
	DirAccess.remove_absolute(path)


static func _extract_title(parsed: Dictionary, dir_name: String) -> String:
	var top_level_title = parsed.get(COURSE_TITLE_KEY, "")
	if typeof(top_level_title) == TYPE_STRING:
		var normalized := String(top_level_title).strip_edges()
		if not normalized.is_empty():
			return normalized

	var course_info = parsed.get(COURSE_INFO_KEY, {})
	if typeof(course_info) == TYPE_DICTIONARY:
		var legacy_title = course_info.get(COURSE_TITLE_KEY, "")
		if typeof(legacy_title) == TYPE_STRING:
			var normalized_legacy := String(legacy_title).strip_edges()
			if not normalized_legacy.is_empty():
				return normalized_legacy

	return dir_name


