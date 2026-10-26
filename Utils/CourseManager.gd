extends Node3D

# Course data keys from JSON file
const COURSE_INFO_KEY := "Course Info"
const HOLE_INFO_KEY := "Hole Info"

# Defaults applied when Course Info is missing keys
const DEFAULT_TEE_COLORS: Array[String] = ["Black", "Blue", "White", "Red", "Gold"]
# TO be used in future implemenation at course hole level.
const DEFAULT_TEXTURE_INDICES := {
	"Green": [0],
	"Fairway": [1],
	"Rough": [2],
	"Sand": [3],
	"Water": [4],
	"Penalty": [5],
}

const CourseDetailEnhancerScript = preload("res://HighFidelity/Terrain/course_detail_enhancer.gd")
const CourseGraphicsUpgraderScript = preload("res://Utils/CourseGraphicsUpgrader.gd")

# Course state — populated after loading a course scene
var course_info: Dictionary = {}
var hole_info: Dictionary = {}
var course_graphics_version: int = 1
var _current_config_path: String = ""


func initialize(scene_path: String, config_path: String) -> void:
	# 0% - 4%: Reading course configuration
	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(0.0, "Reading course configuration...", 4.0)
	_load_course_config(config_path)
	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(4.0, "Reading course configuration...", 4.0)
	await get_tree().process_frame

	# 5% - 30%: Loading 3D course geometry & terrain...
	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(5.0, "Loading 3D course geometry & terrain...", 30.0)

	var err = ResourceLoader.load_threaded_request(scene_path)
	if err != OK:
		push_error("[CourseManager] Failed to start threaded load for: %s. Falling back to synchronous load." % scene_path)
		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_error("[CourseManager] Could not load course scene: %s" % scene_path)
			return
		var course_scene := packed.instantiate()
		if course_scene == null:
			push_error("[CourseManager] Could not instantiate course scene: %s" % scene_path)
			return
		add_child(course_scene)
		_ensure_course_details(course_scene)
		return
		
	var progress_arr := []
	while true:
		progress_arr.clear()
		var status = ResourceLoader.load_threaded_get_status(scene_path, progress_arr)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("[CourseManager] Failed to load course scene asynchronously: %s" % scene_path)
			return
		
		var raw_p: float = float(progress_arr[0]) if progress_arr.size() > 0 else 0.0
		var mapped_percent: float = 5.0 + (raw_p * 25.0)
		if SceneManager != null and SceneManager.has_method("set_loading_stage"):
			SceneManager.set_loading_stage(mapped_percent, "Loading 3D course geometry & terrain...", 30.0)
		await get_tree().process_frame
		
	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(30.0, "Loading 3D course geometry & terrain...", 30.0)
	await get_tree().process_frame

	# 31% - 40%: Constructing scene hierarchy...
	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(31.0, "Constructing scene hierarchy...", 40.0)
	await get_tree().process_frame

	var packed = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed == null:
		push_error("[CourseManager] Could not load course scene: %s" % scene_path)
		return
	var course_scene := packed.instantiate()
	if course_scene == null:
		push_error("[CourseManager] Could not instantiate course scene: %s" % scene_path)
		return

	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(40.0, "Constructing scene hierarchy...", 40.0)
	await get_tree().process_frame

	# 41% - 75%: Mounting objects & physics colliders...
	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(41.0, "Mounting objects & physics colliders...", 75.0)
	await get_tree().process_frame

	add_child(course_scene)

	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(75.0, "Mounting objects & physics colliders...", 75.0)
	await get_tree().process_frame

	# 76% - 99%: Finalizing terrain & graphics quality...
	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(76.0, "Finalizing terrain & graphics quality...", 99.0)
	await get_tree().process_frame

	_ensure_course_details(course_scene)

	if SceneManager != null and SceneManager.has_method("set_loading_stage"):
		SceneManager.set_loading_stage(99.0, "Finalizing terrain & graphics quality...", 99.0)
	await get_tree().process_frame


func _ensure_course_details(course_scene: Node) -> void:
	if course_scene == null:
		return
	var reeds := course_scene.get_node_or_null("ShorelineReedsMultiMesh")
	if reeds == null or course_graphics_version < CourseGraphicsUpgraderScript.CURRENT_COURSE_GRAPHICS_VERSION:
		CourseDetailEnhancerScript.enhance_course_scene(course_scene, false)
	else:
		# Ensure thick rough distance map is computed up front during loading screen
		CourseDetailEnhancerScript.ensure_deep_rough_map(course_scene)
	_apply_course_graphics_quality(course_scene)



func _load_course_config(config_path: String) -> void:
	_current_config_path = config_path
	if config_path.is_empty():
		return

	if not FileAccess.file_exists(config_path):
		push_error("[CourseManager] Course config not found: %s" % config_path)
		return

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_error("[CourseManager] Unable to read course config: %s" % config_path)
		return

	var json_text := file.get_as_text()
	var parsed = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("[CourseManager] Invalid JSON in %s." % config_path)
		return

	course_graphics_version = int(parsed.get("graphics_version", 1))

	# Extract Course Info with defaults for missing keys
	var info = parsed.get(COURSE_INFO_KEY, {})
	if typeof(info) != TYPE_DICTIONARY:
		info = {}
	if not info.has("Tee Colors"):
		info["Tee Colors"] = DEFAULT_TEE_COLORS.duplicate()
	if not info.has("Texture Indices"):
		info["Texture Indices"] = DEFAULT_TEXTURE_INDICES.duplicate()
	course_info = info

	# Extract Hole Info
	var holes = parsed.get(HOLE_INFO_KEY, {})
	if typeof(holes) != TYPE_DICTIONARY:
		holes = {}
	hole_info = holes


func reload_current_config() -> void:
	_load_course_config(_current_config_path)

func get_current_config_path() -> String:
	return _current_config_path


func _apply_course_graphics_quality(course_scene: Node) -> void:
	var quality = GlobalSettings.get_graphics_quality() if GlobalSettings != null else "High"
	MobilePerformance.apply_graphics_quality(course_scene, quality)
