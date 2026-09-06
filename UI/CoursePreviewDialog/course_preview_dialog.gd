extends Control

signal closed

@onready var dimmer: ColorRect = $Dimmer
@onready var title_label: Label = %TitleLabel
@onready var hole_option_btn: OptionButton = %HoleOptionButton
@onready var prev_hole_btn: Button = %PrevHoleButton
@onready var next_hole_btn: Button = %NextHoleButton
@onready var full_course_btn: Button = %FullCourseButton
@onready var close_btn: Button = %CloseButton
@onready var mode_toggle_btn: Button = %ModeToggleButton
@onready var preview_texture_rect: TextureRect = %PreviewTextureRect
@onready var viewport_container: SubViewportContainer = %ViewportContainer
@onready var sub_viewport: SubViewport = %SubViewport
@onready var layout_2d_canvas: Control = %Layout2DCanvas
@onready var loading_overlay: CenterContainer = %LoadingOverlay
@onready var zoom_in_btn: Button = %ZoomInButton
@onready var zoom_out_btn: Button = %ZoomOutButton
@onready var zoom_reset_btn: Button = %ZoomResetButton
@onready var hole_info_label: Label = %HoleInfoLabel
@onready var tee_info_label: Label = %TeeInfoLabel

var config_path: String = ""
var scene_path: String = ""
var course_dir: String = ""
var course_title: String = "Course Preview"

var hole_data_list: Array[Dictionary] = []
var current_view_index: int = 0 # 0 = Full Course, 1..N = Hole 1..N
var active_mode: String = "2D" # "2D" or "3D"

var loaded_course_node: Node = null
var aerial_camera: Camera3D = null
var current_zoom_size: float = 300.0
var base_zoom_size: float = 300.0
var _is_loading_3d: bool = false


func _ready() -> void:
	var panel = $CenterContainer/PanelContainer
	if panel != null:
		ThemeManager.apply_modal_style(panel, 12)

	ThemeManager.apply_nav_button_style(close_btn, 6)
	ThemeManager.apply_secondary_button_style(full_course_btn, 6)
	ThemeManager.apply_secondary_button_style(prev_hole_btn, 6)
	ThemeManager.apply_secondary_button_style(next_hole_btn, 6)
	ThemeManager.apply_option_button_style(hole_option_btn, 18, Vector2(250, 48))
	ThemeManager.apply_secondary_button_style(mode_toggle_btn, 6)
	ThemeManager.apply_nav_button_style(zoom_in_btn, 6)
	ThemeManager.apply_nav_button_style(zoom_out_btn, 6)
	ThemeManager.apply_nav_button_style(zoom_reset_btn, 6)

	close_btn.pressed.connect(_on_close_pressed)
	full_course_btn.pressed.connect(func(): select_view(0))
	prev_hole_btn.pressed.connect(_on_prev_pressed)
	next_hole_btn.pressed.connect(_on_next_pressed)
	hole_option_btn.item_selected.connect(_on_hole_option_selected)
	mode_toggle_btn.pressed.connect(_on_mode_toggle_pressed)
	
	zoom_in_btn.pressed.connect(_on_zoom_in)
	zoom_out_btn.pressed.connect(_on_zoom_out)
	zoom_reset_btn.pressed.connect(_on_zoom_reset)
	
	if layout_2d_canvas != null:
		layout_2d_canvas.draw.connect(_on_layout_2d_draw)


func setup(p_config_path: String, p_scene_path: String = "") -> void:
	config_path = p_config_path
	course_dir = config_path.get_base_dir()
	scene_path = p_scene_path
	if scene_path.is_empty():
		scene_path = course_dir.path_join("course.tscn")
		if not FileAccess.file_exists(scene_path):
			scene_path = course_dir.path_join("course.scn")
			
	_load_course_json()
	_setup_navigation_ui()
	await _ensure_aerial_snapshots_exist()
	select_view(0)


func _load_course_json() -> void:
	hole_data_list.clear()
	if not FileAccess.file_exists(config_path):
		printerr("[CoursePreviewDialog] Config file not found: ", config_path)
		return

	var file = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return
		
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	course_title = parsed.get("Title", course_dir.get_file())
	if title_label != null:
		title_label.text = course_title + " - Aerial Preview"

	var hole_info = parsed.get("Hole Info", {})
	if typeof(hole_info) == TYPE_DICTIONARY:
		var hole_keys = hole_info.keys()
		hole_keys.sort_custom(func(a, b):
			var num_a = int(str(a).replace("Hole", "").strip_edges())
			var num_b = int(str(b).replace("Hole", "").strip_edges())
			if num_a > 0 and num_b > 0:
				return num_a < num_b
			return str(a) < str(b)
		)

		for key in hole_keys:
			var h_dict = hole_info[key]
			var par_val = h_dict.get("Par", 4)
			var loc_arr = h_dict.get("Hole Location", [0.0, 0.0])
			var pin_pos = Vector3.ZERO
			if loc_arr.size() >= 2:
				pin_pos = Vector3(float(loc_arr[0]), 0.0, float(loc_arr[1]))

			var tees_dict = {}
			var tees_raw = h_dict.get("Tee Boxes", {})
			if typeof(tees_raw) == TYPE_DICTIONARY:
				for tee_color in tees_raw.keys():
					var t_arr = tees_raw[tee_color]
					if t_arr.size() >= 2:
						tees_dict[tee_color] = Vector3(float(t_arr[0]), 0.0, float(t_arr[1]))

			hole_data_list.append({
				"name": str(key),
				"par": par_val,
				"pin": pin_pos,
				"tees": tees_dict
			})


func _ensure_aerial_snapshots_exist() -> void:
	var main_img_path = course_dir.path_join("aerial_course.png")
	if FileAccess.file_exists(main_img_path):
		return # Snapshots already exist on disk!

	if not FileAccess.file_exists(scene_path):
		return

	if loading_overlay != null:
		loading_overlay.visible = true
		var lbl = loading_overlay.get_node_or_null("VBox/LoadingLabel")
		if lbl != null:
			lbl.text = "Generating Aerial Terrain Previews..."

	var scn = load(scene_path)
	if scn == null:
		if loading_overlay != null:
			loading_overlay.visible = false
		return

	var vp = SubViewport.new()
	vp.size = Vector2i(1024, 1024)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	vp.world_3d = World3D.new()

	var course_inst = scn.instantiate()
	_clean_preview_course_ui(course_inst)
	vp.add_child(course_inst)

	var snap_cam: Camera3D = null
	if course_inst.has_node("AerialCamera"):
		snap_cam = course_inst.get_node("AerialCamera") as Camera3D
	else:
		snap_cam = Camera3D.new()
		snap_cam.name = "SnapCam"
		snap_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		vp.add_child(snap_cam)

	add_child(vp)

	# 1. Render Full Course Terrain
	_position_camera_for_view(snap_cam, 0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var course_img = vp.get_texture().get_image()
	if course_img != null:
		var save_path = ProjectSettings.globalize_path(main_img_path)
		course_img.save_png(save_path)
		print("[CoursePreview] Saved full course aerial terrain snapshot: ", save_path)

	# 2. Render Each Hole Terrain
	for i in range(hole_data_list.size()):
		var hole_idx = i + 1
		var hole_img_path = course_dir.path_join("aerial_hole_%d.png" % hole_idx)
		_position_camera_for_view(snap_cam, hole_idx)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

		var hole_img = vp.get_texture().get_image()
		if hole_img != null:
			var save_h_path = ProjectSettings.globalize_path(hole_img_path)
			hole_img.save_png(save_h_path)
			print("[CoursePreview] Saved Hole %d aerial terrain snapshot: %s" % [hole_idx, save_h_path])

	remove_child(vp)
	vp.queue_free()

	if loading_overlay != null:
		loading_overlay.visible = false


func _position_camera_for_view(cam: Camera3D, view_idx: int) -> void:
	if cam == null:
		return

	if view_idx == 0:
		var min_pos = Vector3(99999, 0, 99999)
		var max_pos = Vector3(-99999, 0, -99999)
		for h in hole_data_list:
			min_pos.x = min(min_pos.x, h["pin"].x)
			min_pos.z = min(min_pos.z, h["pin"].z)
			max_pos.x = max(max_pos.x, h["pin"].x)
			max_pos.z = max(max_pos.z, h["pin"].z)
			for t in h["tees"].values():
				min_pos.x = min(min_pos.x, t.x)
				min_pos.z = min(min_pos.z, t.z)
				max_pos.x = max(max_pos.x, t.x)
				max_pos.z = max(max_pos.z, t.z)

		if min_pos.x > max_pos.x:
			min_pos = Vector3(-150, 0, -150)
			max_pos = Vector3(150, 0, 150)

		var center = (min_pos + max_pos) / 2.0
		var width = max_pos.x - min_pos.x
		var depth = max_pos.z - min_pos.z
		var full_zoom = max(max(width, depth) * 1.25, 300.0)

		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = full_zoom
		cam.global_transform.basis = Basis(Vector3(1,0,0), Vector3(0,0,-1), Vector3(0,1,0))
		cam.global_position = Vector3(center.x, 150.0, center.z)

	else:
		var h = hole_data_list[view_idx - 1]
		var pin_pos = h["pin"]
		var tee_pos = pin_pos + Vector3(0, 0, 150)
		if not h["tees"].is_empty():
			var tee_keys = h["tees"].keys()
			var default_key = "Blue" if "Blue" in tee_keys else tee_keys[0]
			tee_pos = h["tees"][default_key]

		var dir_3d = (pin_pos - tee_pos)
		dir_3d.y = 0
		if dir_3d.is_zero_approx():
			dir_3d = Vector3(0, 0, -1)
		else:
			dir_3d = dir_3d.normalized()

		var dist = tee_pos.distance_to(pin_pos)
		var hole_zoom = max(dist * 1.35, 60.0)

		var right_vec = dir_3d.cross(Vector3.UP).normalized()
		var up_vec = dir_3d
		var back_vec = Vector3.UP

		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = hole_zoom
		cam.global_transform.basis = Basis(right_vec, up_vec, back_vec)

		var base_pos = tee_pos + dir_3d * (0.35 * hole_zoom)
		cam.global_position = Vector3(base_pos.x, 150.0, base_pos.z)


func _setup_navigation_ui() -> void:
	hole_option_btn.clear()
	hole_option_btn.add_item("Overview - Full Course", 0)

	for i in range(hole_data_list.size()):
		var h = hole_data_list[i]
		var dist_yds = 0
		var main_tee_pos = Vector3.ZERO
		if not h["tees"].is_empty():
			var tee_keys = h["tees"].keys()
			var default_key = "Blue" if "Blue" in tee_keys else tee_keys[0]
			main_tee_pos = h["tees"][default_key]
			dist_yds = int(round(main_tee_pos.distance_to(h["pin"]) * 1.09361))

		var label_str = "%s (Par %d - %d yds)" % [h["name"], h["par"], dist_yds]
		hole_option_btn.add_item(label_str, i + 1)


func select_view(index: int) -> void:
	current_view_index = index
	hole_option_btn.select(index)
	
	_update_nav_buttons()
	_update_view_display()


func _update_nav_buttons() -> void:
	prev_hole_btn.disabled = (current_view_index <= 0)
	next_hole_btn.disabled = (current_view_index >= hole_data_list.size())


func _on_prev_pressed() -> void:
	if current_view_index > 0:
		select_view(current_view_index - 1)


func _on_next_pressed() -> void:
	if current_view_index < hole_data_list.size():
		select_view(current_view_index + 1)


func _on_hole_option_selected(index: int) -> void:
	select_view(index)


func _on_mode_toggle_pressed() -> void:
	if active_mode == "2D":
		active_mode = "3D"
		mode_toggle_btn.text = "2D Layout"
	else:
		active_mode = "2D"
		mode_toggle_btn.text = "3D View"
	_update_view_display()


func _update_view_display() -> void:
	_update_metadata_panel()

	if active_mode == "2D":
		viewport_container.visible = false
		loading_overlay.visible = false

		var image_filename = "aerial_course.png" if current_view_index == 0 else "aerial_hole_%d.png" % current_view_index
		var image_path = course_dir.path_join(image_filename)

		var tex = _load_texture(image_path)
		if tex != null:
			preview_texture_rect.texture = tex
			preview_texture_rect.visible = true
			if layout_2d_canvas != null:
				layout_2d_canvas.queue_redraw()
			return

		# 2D schematic overlay fallback
		preview_texture_rect.visible = false
		if layout_2d_canvas != null:
			layout_2d_canvas.queue_redraw()
	else:
		# 3D Viewport mode requested
		preview_texture_rect.visible = false
		if loaded_course_node == null:
			_load_3d_course_async()
		else:
			viewport_container.visible = true
			loading_overlay.visible = false
			_update_live_camera_position()
			if layout_2d_canvas != null:
				layout_2d_canvas.queue_redraw()


func _load_3d_course_async() -> void:
	if _is_loading_3d:
		return
		
	if not ResourceLoader.exists(scene_path):
		return

	_is_loading_3d = true
	loading_overlay.visible = true
	viewport_container.visible = false

	ResourceLoader.load_threaded_request(scene_path)
	
	while ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().create_timer(0.05).timeout

	if ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_LOADED:
		var scn = ResourceLoader.load_threaded_get(scene_path) as PackedScene
		if scn != null:
			loaded_course_node = scn.instantiate()
			_clean_preview_course_ui(loaded_course_node)
			sub_viewport.add_child(loaded_course_node)

			if loaded_course_node.has_node("AerialCamera"):
				aerial_camera = loaded_course_node.get_node("AerialCamera") as Camera3D
			else:
				aerial_camera = Camera3D.new()
				aerial_camera.name = "PreviewAerialCam"
				aerial_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				sub_viewport.add_child(aerial_camera)

			viewport_container.visible = true
			_update_live_camera_position()

	loading_overlay.visible = false
	_is_loading_3d = false


func _clean_preview_course_ui(root: Node) -> void:
	if root == null:
		return

	var nodes_to_remove = ["RangeUI", "MapCanvas", "CanvasLayer", "DataPanel", "HUD", "SessionRecorder", "TCPServer"]
	for n_name in nodes_to_remove:
		if root.has_node(n_name):
			var n = root.get_node(n_name)
			n.queue_free()

	for child in root.get_children():
		if child is CanvasLayer:
			child.queue_free()
		elif child is Control and child.name != "PreviewAerialCam":
			child.queue_free()
		elif child.name.begins_with("Player"):
			for p_child in child.get_children():
				if p_child is CanvasLayer or p_child is Control:
					p_child.queue_free()


func _update_live_camera_position() -> void:
	if aerial_camera == null:
		return

	_position_camera_for_view(aerial_camera, current_view_index)
	aerial_camera.make_current()


func _update_metadata_panel() -> void:
	if current_view_index == 0:
		hole_info_label.text = "%s - Course Overview (%d Holes)" % [course_title, hole_data_list.size()]
		tee_info_label.text = "Select a specific hole above to view tee & hole details."
	else:
		var h = hole_data_list[current_view_index - 1]
		var pin_pos = h["pin"]
		var main_dist = 0
		if not h["tees"].is_empty():
			var tee_keys = h["tees"].keys()
			var default_key = "Blue" if "Blue" in tee_keys else tee_keys[0]
			main_dist = int(round(h["tees"][default_key].distance_to(pin_pos) * 1.09361))

		hole_info_label.text = "%s - Par %d (%d yds)" % [h["name"], h["par"], main_dist]

		var tee_strs = []
		for tee_name in h["tees"].keys():
			var t_pos = h["tees"][tee_name]
			var d_yds = int(round(t_pos.distance_to(pin_pos) * 1.09361))
			tee_strs.append("%s: %d yds" % [tee_name, d_yds])

		tee_info_label.text = "Tee Distances: " + ", ".join(tee_strs)


func _on_layout_2d_draw() -> void:
	if layout_2d_canvas == null or hole_data_list.is_empty():
		return

	var rect_size = layout_2d_canvas.size
	if rect_size.x <= 0 or rect_size.y <= 0:
		return

	var center_canvas = rect_size / 2.0

	if current_view_index == 0:
		var min_pos = Vector2(99999, 99999)
		var max_pos = Vector2(-99999, -99999)
		for h in hole_data_list:
			min_pos.x = min(min_pos.x, h["pin"].x)
			min_pos.y = min(min_pos.y, h["pin"].z)
			max_pos.x = max(max_pos.x, h["pin"].x)
			max_pos.y = max(max_pos.y, h["pin"].z)
			for t in h["tees"].values():
				min_pos.x = min(min_pos.x, t.x)
				min_pos.y = min(min_pos.y, t.z)
				max_pos.x = max(max_pos.x, t.x)
				max_pos.y = max(max_pos.y, t.z)

		var world_size = (max_pos - min_pos)
		if world_size.x <= 0 or world_size.y <= 0:
			world_size = Vector2(300, 300)

		var scale_factor = min(rect_size.x / (world_size.x * 1.3), rect_size.y / (world_size.y * 1.3))
		var world_center = (min_pos + max_pos) / 2.0

		for idx in range(hole_data_list.size()):
			var h = hole_data_list[idx]
			var pin_2d = Vector2(h["pin"].x, h["pin"].z)
			var pin_canvas = center_canvas + (pin_2d - world_center) * scale_factor

			layout_2d_canvas.draw_circle(pin_canvas, 12.0, Color(0.2, 0.75, 0.35, 0.6))
			layout_2d_canvas.draw_arc(pin_canvas, 12.0, 0, TAU, 32, Color(0.4, 0.95, 0.55, 0.9), 2.0)
			layout_2d_canvas.draw_circle(pin_canvas, 4.0, Color.RED)

			if not h["tees"].is_empty():
				var default_key = "Blue" if "Blue" in h["tees"] else h["tees"].keys()[0]
				var tee_3d = h["tees"][default_key]
				var tee_2d = Vector2(tee_3d.x, tee_3d.z)
				var tee_canvas = center_canvas + (tee_2d - world_center) * scale_factor

				layout_2d_canvas.draw_line(tee_canvas, pin_canvas, Color(1, 1, 1, 0.4), 1.5)
				layout_2d_canvas.draw_circle(tee_canvas, 5.0, Color(0.2, 0.6, 1.0))

			var font = ThemeDB.fallback_font
			layout_2d_canvas.draw_string(font, pin_canvas + Vector2(10, 5), h["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	else:
		var h = hole_data_list[current_view_index - 1]
		var pin_pos = h["pin"]
		var tee_pos = pin_pos + Vector3(0, 0, 150)
		if not h["tees"].is_empty():
			var tee_keys = h["tees"].keys()
			var default_key = "Blue" if "Blue" in tee_keys else tee_keys[0]
			tee_pos = h["tees"][default_key]

		var dist_m = tee_pos.distance_to(pin_pos)
		var dist_yds = int(round(dist_m * 1.09361))

		var margin_y = rect_size.y * 0.15
		var tee_canvas = Vector2(center_canvas.x, rect_size.y - margin_y)
		var pin_canvas = Vector2(center_canvas.x, margin_y)

		layout_2d_canvas.draw_line(tee_canvas, pin_canvas, Color(0.35, 0.8, 0.95, 0.8), 2.5)

		var font = ThemeDB.fallback_font
		for yard_mark in [100, 200, 300]:
			if yard_mark < dist_yds:
				var ratio = float(yard_mark) / float(dist_yds)
				var arc_center = tee_canvas.lerp(pin_canvas, ratio)
				layout_2d_canvas.draw_line(arc_center + Vector2(-40, 0), arc_center + Vector2(40, 0), Color(1, 1, 1, 0.3), 1.0)
				layout_2d_canvas.draw_string(font, arc_center + Vector2(45, 4), "%d YDS" % yard_mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8, 0.7))

		layout_2d_canvas.draw_circle(pin_canvas, 24.0, Color(0.15, 0.75, 0.3, 0.65))
		layout_2d_canvas.draw_arc(pin_canvas, 24.0, 0, TAU, 32, Color(0.35, 0.95, 0.5, 0.9), 2.5)
		layout_2d_canvas.draw_circle(pin_canvas, 5.0, Color.RED)

		var tee_color_map = {
			"Black": Color(0.1, 0.1, 0.1),
			"Blue": Color(0.2, 0.5, 0.9),
			"White": Color(0.9, 0.9, 0.9),
			"Red": Color(0.9, 0.2, 0.2)
		}

		var t_idx = 0
		for t_name in h["tees"].keys():
			var t_pos = h["tees"][t_name]
			var t_dist_m = t_pos.distance_to(pin_pos)
			var ratio = clamp(1.0 - (t_dist_m / max(dist_m, 1.0)), 0.0, 1.0)
			var t_canvas = tee_canvas.lerp(pin_canvas, ratio) + Vector2((t_idx - 1) * 16, 0)
			var c = tee_color_map.get(t_name, Color.YELLOW)

			layout_2d_canvas.draw_rect(Rect2(t_canvas - Vector2(6, 6), Vector2(12, 12)), c, true)
			layout_2d_canvas.draw_rect(Rect2(t_canvas - Vector2(6, 6), Vector2(12, 12)), Color.BLACK, false, 1.0)
			t_idx += 1

		var mid_canvas = tee_canvas.lerp(pin_canvas, 0.5)
		var badge_str = "%d YARDS" % dist_yds
		layout_2d_canvas.draw_string(font, mid_canvas + Vector2(12, 5), badge_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 0.6))


func _on_zoom_in() -> void:
	current_zoom_size = clamp(current_zoom_size - 25.0, 30.0, 1000.0)
	if aerial_camera != null:
		aerial_camera.size = current_zoom_size
	if layout_2d_canvas != null:
		layout_2d_canvas.queue_redraw()


func _on_zoom_out() -> void:
	current_zoom_size = clamp(current_zoom_size + 25.0, 30.0, 1000.0)
	if aerial_camera != null:
		aerial_camera.size = current_zoom_size
	if layout_2d_canvas != null:
		layout_2d_canvas.queue_redraw()


func _on_zoom_reset() -> void:
	current_zoom_size = base_zoom_size
	if aerial_camera != null:
		aerial_camera.size = current_zoom_size
	if layout_2d_canvas != null:
		layout_2d_canvas.queue_redraw()


func _on_close_pressed() -> void:
	closed.emit()
	queue_free()


func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img = Image.load_from_file(path)
	if img != null:
		return ImageTexture.create_from_image(img)
	return null

