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
		var global_cfg = ProjectSettings.globalize_path(config_path)
		if not FileAccess.file_exists(global_cfg):
			printerr("[CourseValidator] Missing %s for course '%s' at: %s" % [COURSE_CONFIG_FILE, dir_name, config_path])
			return {}
		config_path = global_cfg

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		var global_cfg = ProjectSettings.globalize_path(config_path)
		file = FileAccess.open(global_cfg, FileAccess.READ)
		if file == null:
			printerr("[CourseValidator] Unable to read course config: %s" % config_path)
			return {}
		config_path = global_cfg

	var json_text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("[CourseValidator] Invalid JSON in %s." % config_path)
		return {}

	var title := _extract_title(parsed, dir_name)

	var scene_file_name: String = COURSE_SCENE_FILE
	if parsed.has("scene_path") and typeof(parsed["scene_path"]) == TYPE_STRING and not parsed["scene_path"].is_empty():
		scene_file_name = parsed["scene_path"].get_file()
	elif parsed.has("ScenePath") and typeof(parsed["ScenePath"]) == TYPE_STRING and not parsed["ScenePath"].is_empty():
		scene_file_name = parsed["ScenePath"].get_file()

	var scene_path := "%s/%s/%s" % [course_dir, dir_name, scene_file_name]
	var scene_found: bool = ResourceLoader.exists(scene_path) or FileAccess.file_exists(scene_path) or FileAccess.file_exists(scene_path + ".remap")
	if not scene_found:
		var global_scene = ProjectSettings.globalize_path(scene_path)
		if FileAccess.file_exists(global_scene) or FileAccess.file_exists(global_scene + ".remap"):
			scene_found = true
			scene_path = global_scene
		else:
			# Check binary scene fallback (.scn instead of .tscn)
			var scn_path := "%s/%s/course.scn" % [course_dir, dir_name]
			if ResourceLoader.exists(scn_path) or FileAccess.file_exists(scn_path) or FileAccess.file_exists(scn_path + ".remap") or FileAccess.file_exists(ProjectSettings.globalize_path(scn_path)):
				scene_found = true
				scene_path = scn_path

	if not scene_found:
		if dir_name.begins_with("custom_") and course_dir.begins_with("user://"):
			print("[CourseValidator] Cleaning up incomplete custom course folder: %s" % dir_name)
			_delete_dir_recursive(course_dir.path_join(dir_name))
		else:
			printerr("[CourseValidator] Missing %s for course '%s' at: %s" % [scene_file_name, dir_name, scene_path])
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


