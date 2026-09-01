extends Control

signal course_created(course_dict: Dictionary)

@onready var course_opt: OptionButton = %CourseOptionButton
@onready var hole_opt: OptionButton = %HoleOptionButton
@onready var add_hole_btn: Button = %AddHoleButton
@onready var hole_list: ItemList = %AddedHolesList
@onready var remove_hole_btn: Button = %RemoveHoleButton
@onready var clear_holes_btn: Button = %ClearHolesButton
@onready var title_input: LineEdit = %CourseTitleInput
@onready var done_btn: Button = %DoneButton
@onready var cancel_btn: Button = %CancelButton
@onready var preview_texture_rect: TextureRect = %PreviewTextureRect
@onready var fallback_canvas: Control = %FallbackCanvas
@onready var aerial_label: Label = %AerialLabel
@onready var mode_toggle_btn: Button = %ModeToggleButton
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var sub_viewport: SubViewport = %SubViewport
@onready var loading_overlay: CenterContainer = %LoadingOverlay
@onready var generation_overlay: CenterContainer = %GenerationOverlay
@onready var gen_subtitle: Label = %GenSubtitle

var available_real_courses: Array[Dictionary] = []
var current_course_holes: Array[Dictionary] = [] # [{key: "Hole 1", par: 4, dist: 385, data: {}}]
var selected_holes: Array[Dictionary] = [] # [{source_title, source_config_path, hole_key, hole_data, par, dist}]

var preview_mode: String = "2D" # "2D" or "3D"
var loaded_course_path: String = ""
var loaded_course_node: Node = null
var aerial_camera: Camera3D = null
var _is_loading_3d: bool = false
var _build_thread: Thread = null


func _exit_tree() -> void:
	if _build_thread != null and _build_thread.is_alive():
		_build_thread.wait_to_finish()
		_build_thread = null


func _ready() -> void:
	var main_panel = get_node_or_null("MainPanel")
	if main_panel != null:
		ThemeManager.apply_modal_style(main_panel, 12)

	ThemeManager.apply_primary_button_style(done_btn, 6)
	ThemeManager.apply_nav_button_style(cancel_btn, 6)
	ThemeManager.apply_secondary_button_style(add_hole_btn, 6)
	ThemeManager.apply_danger_button_style(remove_hole_btn, 6)
	ThemeManager.apply_danger_button_style(clear_holes_btn, 6)
	ThemeManager.apply_secondary_button_style(mode_toggle_btn, 6)
	ThemeManager.apply_input_style(title_input)

	done_btn.pressed.connect(_on_done_pressed)
	cancel_btn.pressed.connect(_on_cancel_pressed)
	add_hole_btn.pressed.connect(_on_add_hole_pressed)
	remove_hole_btn.pressed.connect(_on_remove_hole_pressed)
	clear_holes_btn.pressed.connect(_on_clear_holes_pressed)

	if title_input.text.strip_edges().is_empty():
		title_input.text = "My Custom Course"
	title_input.text_changed.connect(func(_t): _update_done_button())

	course_opt.item_selected.connect(_on_course_selected)
	hole_opt.item_selected.connect(_on_hole_selected)
	mode_toggle_btn.pressed.connect(_on_toggle_mode)

	if fallback_canvas != null:
		fallback_canvas.draw.connect(_on_fallback_canvas_draw)

	generation_overlay.visible = false

	_scan_real_courses()
	_update_done_button()


func _on_cancel_pressed() -> void:
	_cleanup_3d_course()
	queue_free()


func _scan_real_courses() -> void:
	available_real_courses.clear()
	course_opt.clear()

	var validated: Array[Dictionary] = []
	_scan_dir("res://Courses/UserCourses", validated)
	_scan_dir("user://courses", validated)

	validated.sort_custom(func(a, b): return a["title"] < b["title"])

	for course in validated:
		# Only include non-custom (real) courses as sources
		if not course.get("is_custom", false):
			var idx = available_real_courses.size()
			available_real_courses.append(course)
			course_opt.add_item(course["title"], idx)

	if not available_real_courses.is_empty():
		course_opt.select(0)
		_on_course_selected(0)
	else:
		hole_opt.clear()
		aerial_label.text = "No real courses available."


func _scan_dir(dir_path: String, validated: Array[Dictionary]) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var dir_name := dir.get_next()
	while dir_name != "":
		if dir.current_is_dir() and not dir_name.begins_with("."):
			var result: Dictionary = CourseValidator.validate(dir_path, dir_name)
			if not result.is_empty():
				result["dir_name"] = dir_name
				validated.append(result)
		dir_name = dir.get_next()
	dir.list_dir_end()


func _on_course_selected(idx: int) -> void:
	current_course_holes.clear()
	hole_opt.clear()
	_cleanup_3d_course()

	if idx < 0 or idx >= available_real_courses.size():
		_update_aerial_overview()
		return

	var course_data = available_real_courses[idx]
	var config_path: String = course_data.get("config_path", "")

	if FileAccess.file_exists(config_path):
		var file = FileAccess.open(config_path, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var hole_info = parsed.get("Hole Info", {})
				if typeof(hole_info) == TYPE_DICTIONARY:
					var keys = hole_info.keys()
					keys.sort_custom(func(a, b):
						var num_a = int(str(a).replace("Hole", "").strip_edges())
						var num_b = int(str(b).replace("Hole", "").strip_edges())
						if num_a > 0 and num_b > 0:
							return num_a < num_b
						return str(a) < str(b)
					)

					for k in keys:
						var h_dict = hole_info[k]
						var par_val = h_dict.get("Par", 4)
						var loc_arr = h_dict.get("Hole Location", [0.0, 0.0])
						var pin_vec = Vector2(float(loc_arr[0]), float(loc_arr[1]))

						var main_tee_vec = Vector2.ZERO
						var tees_raw = h_dict.get("Tee Boxes", {})
						if typeof(tees_raw) == TYPE_DICTIONARY and not tees_raw.is_empty():
							var default_key = "Blue" if "Blue" in tees_raw else tees_raw.keys()[0]
							var t_arr = tees_raw[default_key]
							main_tee_vec = Vector2(float(t_arr[0]), float(t_arr[1]))

						var dist_yds = int(round(main_tee_vec.distance_to(pin_vec) * 1.09361))

						current_course_holes.append({
							"key": str(k),
							"par": par_val,
							"dist": dist_yds,
							"pin": pin_vec,
							"tee": main_tee_vec,
							"data": h_dict
						})

						var item_label = "%s (Par %d - %d yds)" % [k, par_val, dist_yds]
						hole_opt.add_item(item_label, hole_opt.get_item_count())

	if not current_course_holes.is_empty():
		hole_opt.select(0)

	_update_aerial_overview()


func _on_hole_selected(_idx: int) -> void:
	_update_aerial_overview()


func _on_toggle_mode() -> void:
	if preview_mode == "2D":
		preview_mode = "3D"
		mode_toggle_btn.text = "2D View"
	else:
		preview_mode = "2D"
		mode_toggle_btn.text = "3D View"
	_update_aerial_overview()


func _update_aerial_overview() -> void:
	var course_idx = course_opt.selected
	var hole_idx = hole_opt.selected

	if course_idx < 0 or course_idx >= available_real_courses.size() or hole_idx < 0 or hole_idx >= current_course_holes.size():
		preview_texture_rect.visible = false
		fallback_canvas.visible = false
		viewport_container.visible = false
		loading_overlay.visible = false
		aerial_label.text = "Select a course and hole to view aerial overview."
		return

	var course_data = available_real_courses[course_idx]
	var hole_entry = current_course_holes[hole_idx]
	var course_dir = course_data.get("config_path", "").get_base_dir()

	aerial_label.text = "%s - %s (Par %d, %d yds)" % [course_data["title"], hole_entry["key"], hole_entry["par"], hole_entry["dist"]]

	if preview_mode == "2D":
		viewport_container.visible = false
		loading_overlay.visible = false

		var hole_num = int(str(hole_entry["key"]).replace("Hole", "").strip_edges())
		var image_filename = "aerial_hole_%d.png" % hole_num
		var image_path = course_dir.path_join(image_filename)

		var tex = _load_texture(image_path)
		if tex != null:
			preview_texture_rect.texture = tex
			preview_texture_rect.visible = true
			fallback_canvas.visible = false
			return

		# Fallback 2D schematic layout
		preview_texture_rect.visible = false
		fallback_canvas.visible = true
		fallback_canvas.queue_redraw()
	else:
		# 3D Viewport Mode
		preview_texture_rect.visible = false
		fallback_canvas.visible = false

		var scene_path = course_data.get("scene_path", "")
		if scene_path.is_empty():
			scene_path = course_dir.path_join("course.tscn")

		if loaded_course_node == null or loaded_course_path != scene_path:
			_load_3d_course(scene_path, hole_entry)
		else:
			viewport_container.visible = true
			loading_overlay.visible = false
			_update_live_camera(hole_entry)


func _load_3d_course(scene_path: String, hole_entry: Dictionary) -> void:
	if _is_loading_3d:
		return
	if not FileAccess.file_exists(scene_path):
		preview_mode = "2D"
		mode_toggle_btn.text = "3D View"
		_update_aerial_overview()
		return

	_cleanup_3d_course()
	_is_loading_3d = true
	loading_overlay.visible = true
	viewport_container.visible = false

	var scn = load(scene_path) as PackedScene
	if scn != null:
		loaded_course_node = scn.instantiate()
		loaded_course_path = scene_path
		_clean_course_ui(loaded_course_node)
		sub_viewport.add_child(loaded_course_node)

		aerial_camera = Camera3D.new()
		aerial_camera.name = "PreviewAerialCam"
		aerial_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		sub_viewport.add_child(aerial_camera)

		viewport_container.visible = true
		_update_live_camera(hole_entry)

	loading_overlay.visible = false
	_is_loading_3d = false


func _clean_course_ui(root: Node) -> void:
	if root == null:
		return
	var nodes_to_remove = ["RangeUI", "MapCanvas", "CanvasLayer", "DataPanel", "HUD", "SessionRecorder", "TCPServer"]
	for n_name in nodes_to_remove:
		if root.has_node(n_name):
			root.get_node(n_name).queue_free()

	for child in root.get_children():
		if child is CanvasLayer:
			child.queue_free()
		elif child is Control and child.name != "PreviewAerialCam":
			child.queue_free()
		elif child.name.begins_with("Player"):
			for p_child in child.get_children():
				if p_child is CanvasLayer or p_child is Control:
					p_child.queue_free()


func _update_live_camera(hole_entry: Dictionary) -> void:
	if aerial_camera == null:
		return

	var pin_2d = hole_entry["pin"]
	var tee_2d = hole_entry["tee"]

	var pin_pos = Vector3(pin_2d.x, 0.0, pin_2d.y)
	var tee_pos = Vector3(tee_2d.x, 0.0, tee_2d.y)

	var dir_3d = (pin_pos - tee_pos)
	dir_3d.y = 0
	if dir_3d.is_zero_approx():
		dir_3d = Vector3(1, 0, 0)
	else:
		dir_3d = dir_3d.normalized()

	var dist = tee_pos.distance_to(pin_pos)
	var current_zoom_size = max(dist * 1.35, 60.0)

	var right_vec = dir_3d.cross(Vector3.UP).normalized()
	var up_vec = dir_3d
	var back_vec = Vector3.UP

	aerial_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	aerial_camera.size = current_zoom_size
	aerial_camera.global_transform.basis = Basis(right_vec, up_vec, back_vec)

	var base_pos = tee_pos + dir_3d * (0.35 * current_zoom_size)
	aerial_camera.global_position = Vector3(base_pos.x, 150.0, base_pos.z)
	aerial_camera.make_current()


func _cleanup_3d_course() -> void:
	if loaded_course_node != null and is_instance_valid(loaded_course_node):
		loaded_course_node.queue_free()
	loaded_course_node = null
	loaded_course_path = ""
	aerial_camera = null


func _on_fallback_canvas_draw() -> void:
	if fallback_canvas == null or current_course_holes.is_empty():
		return
	var hole_idx = hole_opt.selected
	if hole_idx < 0 or hole_idx >= current_course_holes.size():
		return

	var size = fallback_canvas.size
	if size.x <= 0 or size.y <= 0:
		return

	var course_idx = course_opt.selected
	var course_title_str = available_real_courses[course_idx]["title"] if (course_idx >= 0 and course_idx < available_real_courses.size()) else "Course"

	var hole_entry = current_course_holes[hole_idx]
	var dist_yds = hole_entry["dist"]
	var par_val = hole_entry["par"]
	var hole_name_str = hole_entry["key"]

	var center = size / 2.0
	var font = ThemeDB.fallback_font

	# Background dark green pad
	var bg_rect = Rect2(Vector2.ZERO, size)
	fallback_canvas.draw_rect(bg_rect, Color(0.04, 0.08, 0.05), true)

	# 50ft rough boundary visualization
	var rough_rect = Rect2(Vector2(size.x * 0.12, size.y * 0.1), Vector2(size.x * 0.76, size.y * 0.8))
	fallback_canvas.draw_rect(rough_rect, Color(0.12, 0.32, 0.14, 0.6), true)
	fallback_canvas.draw_rect(rough_rect, Color(0.3, 0.65, 0.35, 0.8), false, 2.0)

	# Fairway corridor width scaling
	var fw_width = clamp(size.x * 0.3, 80.0, 180.0)
	var fw_rect = Rect2(Vector2(center.x - fw_width / 2.0, size.y * 0.22), Vector2(fw_width, size.y * 0.58))
	fallback_canvas.draw_rect(fw_rect, Color(0.22, 0.52, 0.2, 0.9), true)

	var tee_canvas = Vector2(center.x, size.y * 0.80)
	var pin_canvas = Vector2(center.x, size.y * 0.22)

	# Target line
	fallback_canvas.draw_line(tee_canvas, pin_canvas, Color(0.35, 0.85, 0.95, 0.85), 2.5)

	# Yardage arcs (100yd, 200yd, 300yd)
	for mark in [100, 200, 300]:
		if mark < dist_yds:
			var ratio = float(mark) / float(dist_yds)
			var mark_pos = tee_canvas.lerp(pin_canvas, ratio)
			fallback_canvas.draw_line(mark_pos + Vector2(-fw_width * 0.4, 0), mark_pos + Vector2(fw_width * 0.4, 0), Color(1, 1, 1, 0.35), 1.0)
			fallback_canvas.draw_string(font, mark_pos + Vector2(fw_width * 0.42, 4), "%d YDS" % mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.9, 0.8, 0.7))

	# Putting Green area
	fallback_canvas.draw_circle(pin_canvas, 28.0, Color(0.2, 0.78, 0.32, 0.9))
	fallback_canvas.draw_arc(pin_canvas, 28.0, 0, TAU, 32, Color(0.4, 0.95, 0.5, 0.9), 2.0)
	fallback_canvas.draw_circle(pin_canvas, 5.0, Color.RED) # Flag pin

	# Tee pad
	fallback_canvas.draw_rect(Rect2(tee_canvas - Vector2(10, 10), Vector2(20, 20)), Color(0.2, 0.55, 0.9), true)

	# Callouts & Badges
	fallback_canvas.draw_string(font, Vector2(size.x * 0.15, size.y * 0.06), "%s - %s" % [course_title_str, hole_name_str], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	fallback_canvas.draw_string(font, Vector2(size.x * 0.15, size.y * 0.95), "PAR %d  |  %d YARDS" % [par_val, dist_yds], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.95, 0.5))
	fallback_canvas.draw_string(font, Vector2(size.x * 0.65, size.y * 0.95), "+50ft Rough Buffer", HORIZONTAL_ALIGNMENT_RIGHT, -1, 12, Color(0.6, 0.85, 0.6, 0.8))


func _on_add_hole_pressed() -> void:
	var course_idx = course_opt.selected
	var hole_idx = hole_opt.selected

	if course_idx < 0 or course_idx >= available_real_courses.size() or hole_idx < 0 or hole_idx >= current_course_holes.size():
		return

	var source_course = available_real_courses[course_idx]
	var hole_entry = current_course_holes[hole_idx]

	var added_data = {
		"source_title": source_course["title"],
		"source_config_path": source_course["config_path"],
		"hole_key": hole_entry["key"],
		"par": hole_entry["par"],
		"dist": hole_entry["dist"],
		"hole_data": hole_entry["data"]
	}

	selected_holes.append(added_data)
	_refresh_hole_list()
	_update_done_button()


func _on_remove_hole_pressed() -> void:
	var items = hole_list.get_selected_items()
	if items.is_empty():
		return
	var selected_idx = items[0]
	if selected_idx >= 0 and selected_idx < selected_holes.size():
		selected_holes.remove_at(selected_idx)
		_refresh_hole_list()
		_update_done_button()


func _on_clear_holes_pressed() -> void:
	selected_holes.clear()
	_refresh_hole_list()
	_update_done_button()


func _refresh_hole_list() -> void:
	hole_list.clear()
	for i in range(selected_holes.size()):
		var h = selected_holes[i]
		var label_str = "Hole %d: %s - %s (Par %d, %d yds)" % [i + 1, h["source_title"], h["hole_key"], h["par"], h["dist"]]
		hole_list.add_item(label_str)


func _update_done_button() -> void:
	var name_valid = not title_input.text.strip_edges().is_empty()
	var has_holes = not selected_holes.is_empty()
	done_btn.disabled = not (name_valid and has_holes)


func _on_done_pressed() -> void:
	var course_title = title_input.text.strip_edges()
	if course_title.is_empty():
		course_title = "My Custom Course"
	if selected_holes.is_empty():
		return

	if gen_subtitle != null:
		gen_subtitle.text = "Starting custom course generation..."

	generation_overlay.visible = true
	done_btn.disabled = true
	cancel_btn.disabled = true

	_cleanup_3d_course()

	# Give Godot 2 frames to render the spinning wheel overlay on screen
	await get_tree().process_frame
	await get_tree().process_frame

	var progress_cb = func(_curr: int, _total: int, msg: String):
		Callable(func():
			if is_instance_valid(self) and gen_subtitle != null:
				gen_subtitle.text = msg
		).call_deferred()

	# Run course building in a background Thread so the main thread renders at 60 FPS and the spinner spins continuously
	_build_thread = Thread.new()
	var thread_err = _build_thread.start(
		func():
			return CustomCourseBuilder.build_custom_course(course_title, selected_holes, progress_cb)
	)

	if thread_err != OK:
		var res = CustomCourseBuilder.build_custom_course(course_title, selected_holes, progress_cb)
		_handle_generation_result(res)
		return

	while _build_thread != null and _build_thread.is_alive():
		await get_tree().process_frame

	if _build_thread != null:
		var result = _build_thread.wait_to_finish()
		_build_thread = null
		_handle_generation_result(result)


func _handle_generation_result(result: Dictionary) -> void:
	if not result.is_empty():
		course_created.emit(result)
		queue_free()
	else:
		generation_overlay.visible = false
		done_btn.disabled = false
		cancel_btn.disabled = false


func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img = Image.load_from_file(path)
	if img != null:
		return ImageTexture.create_from_image(img)
	return null
