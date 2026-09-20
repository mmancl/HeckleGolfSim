extends Node3D

var track_points : bool = false
var trail_timer : float = 0.0
var trail_resolution : float = 0.1
var apex := 0
var display_data: Dictionary = {
	"Distance": "---",
	"Carry": "---",
	"Offline": "---",
	"Apex": "---",
	"VLA": "---",
	"HLA": "---",
	"Speed": "---",
	"BallSpeed": "---",
	"ClubSpeed": "---",
	"SmashFactor": "---",
	"BackSpin": "---",
	"SideSpin": "---",
	"TotalSpin": "---",
	"SpinAxis": "---"
}
var raw_ball_data: Dictionary = {}
var last_display: Dictionary = {}
var is_aerial_view: bool = false
var is_driving_range: bool = false
var _elevation_width: int = 0
var _elevation_height: int = 0
var _elevation_left_lon: float = 0.0
var _elevation_right_lon: float = 0.0
var _elevation_top_lat: float = 0.0
var _elevation_bottom_lat: float = 0.0
var _elevation_ref_lat: float = 0.0
var _elevation_ref_lon: float = 0.0
var _elevation_meters_per_lat: float = 111320.0
var _elevation_meters_per_lon: float = 111320.0
var _elevation_offset: float = 0.0
var _elevation_data: PackedFloat32Array = PackedFloat32Array()
var _has_elevation_map: bool = false
var _height_raycast: RayCast3D = null
var aerial_zoom: float = 300.0
var _last_was_on_green: bool = false
var _default_non_green_aerial_zoom: float = 300.0
var _teebox_aerial_zoom: float = 300.0
var _last_zoom_zone: int = -1
var aim_target_pos: Vector3 = Vector3(150.0, 0.0, 0.0) # Default target down the range
var _last_aim_target_pos: Vector3 = Vector3.ZERO
var _last_aim_yaw_offset_deg: float = 0.0
var _aim_is_manual: bool = false
var aim_line: MeshInstance3D = null
var _last_aim_line_start: Vector3 = Vector3.INF
var _last_aim_line_end: Vector3 = Vector3.INF
var current_aim_distance_yards: float = 0.0
var current_aim_elevation_diff_m: float = -9999.0

# Performance and throttling state
var _live_stats_timer: float = 0.0
var _green_grid_timer: float = 0.0
var _zoom_zone_dirty: bool = true
var _cached_surface_nodes_initialized: bool = false
var _cached_green_bodies: Array[Dictionary] = []
var _cached_tee_bodies: Array[Dictionary] = []
var _cached_fairway_bodies: Array[Dictionary] = []

# Dynamic Course Play active hole variables
var show_green_grid: bool = false:
	set(val):
		if show_green_grid != val:
			show_green_grid = val
			_update_green_grid_visibility()
			if has_node("MapCanvas/AerialZoomVBox/GridToggleButton"):
				var btn = $MapCanvas/AerialZoomVBox/GridToggleButton
				var btn_color = Color(0.2, 0.6, 0.3, 0.85) if show_green_grid else Color(0.15, 0.15, 0.15, 0.85)
				apply_circular_button_style(btn, btn_color)
var current_hole_location: Vector3 = Vector3.ZERO:
	set(val):
		if current_hole_location != val:
			current_hole_location = val
			call_deferred("_generate_green_grid_and_heatmap")
var cup_radius: float = 0.108
var current_hole_name: String = "Hole 1"
var current_hole_par: int = 4
var current_hole_tee_dist_yards: int = 0
var shot_count: int = 0

# Map dragging state variables
var is_dragging_map: bool = false
var map_drag_start_pos: Vector2 = Vector2.ZERO
var total_map_drag_dist: float = 0.0
var aerial_cam_user_offset: Vector3 = Vector3.ZERO
var is_mouse_down_on_map: bool = false
var _touch_points: Dictionary = {}
var _last_pinch_distance: float = -1.0
# Continuous screen-half aiming state variables
var is_screen_aiming: bool = false
var screen_aim_direction: float = 0.0
var screen_aim_speed_deg: float = 17.5
var course_data_dict: Dictionary = {}
var _shot_active: bool = false
var is_sky_view_active: bool = false
var _last_travel_yaw: float = 0.0
var _user_custom_club: String = ""
var _is_updating_auto_club: bool = false
var _skip_requested := false
var _putt_close_view_triggered: bool = false
var _chip_close_view_triggered: bool = false
# Chipping minigame state variables
var chipping_island_positions: Array[Vector3] = []
var chipping_stats := {}
var selected_chipping_target_idx := 1 # Default 100 feet
var chipping_hud: CanvasLayer = null
var chipping_target_lbl: Label = null
var chipping_attempts_lbl: Label = null
var chipping_hits_lbl: Label = null
var chipping_accuracy_lbl: Label = null
var chipping_banner_lbl: Label = null
var chipping_buttons: Array[Button] = []
var chipping_islands: Array[StaticBody3D] = []
var chipping_distances = [50, 100, 150, 200, 250, 300] # in feet
var chipping_lateral_offsets = [-15, 20, -25, 30, -35, 25] # in feet, staggered left/right



# Visual effects references
var vignette_layer: CanvasLayer = null
var vignette_rect: ColorRect = null
var camera_attributes: CameraAttributesPractical = null


func get_height(x: float, z: float) -> float:
	if is_driving_range:
		return 0.0
		
	if _height_raycast != null:
		_height_raycast.global_position = Vector3(x, 1000.0, z)
		_height_raycast.target_position = Vector3(0.0, -2000.0, 0.0)
		var max_passes = 8
		var hit_y: Variant = null
		while max_passes > 0:
			max_passes -= 1
			_height_raycast.force_raycast_update()
			if not _height_raycast.is_colliding():
				break
			var collider = _height_raycast.get_collider()
			if collider and (collider.has_meta("surface_type") or collider.name.contains("Terrain") or collider.name.contains("Rough") or collider.name.contains("green") or collider.name.contains("fairway") or collider.name.contains("tee") or collider.name.contains("bunker")):
				hit_y = _height_raycast.get_collision_point().y
				break
			# Non-terrain collider (e.g. ball, tree branch, player prop): exclude and raycast through it
			_height_raycast.add_exception(collider)
		_height_raycast.clear_exceptions()
		if hit_y != null:
			return hit_y
	elif is_inside_tree() and get_world_3d() != null and get_world_3d().direct_space_state != null:
		var space_state = get_world_3d().direct_space_state
		var ray_origin = Vector3(x, 1000.0, z)
		var ray_end = Vector3(x, -2000.0, z)
		var exclude_rids: Array[RID] = []
		var max_passes = 8
		while max_passes > 0:
			max_passes -= 1
			var query = PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1, exclude_rids)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit = space_state.intersect_ray(query)
			if hit.is_empty():
				break
			var collider = hit.get("collider")
			if collider and (collider.has_meta("surface_type") or collider.name.contains("Terrain") or collider.name.contains("Rough") or collider.name.contains("green") or collider.name.contains("fairway") or collider.name.contains("tee") or collider.name.contains("bunker")):
				return hit["position"].y
			if collider and collider is CollisionObject3D:
				exclude_rids.append(collider.get_rid())
			else:
				break
				
	if _has_elevation_map:
		return sample_elevation(x, z)
		
	# Gradual, natural golf course topography with broad wavelengths (800m - 1500m)
	# producing gentle ~1% grades with at most 1 gradual rise or fall across an entire hole.
	var h = sin(x * 0.0042 + z * 0.0031) * cos(z * 0.0051 - x * 0.0036) * 1.2 + sin(x * 0.0078 - z * 0.0062) * 0.5
	return h


func _load_elevation_map() -> void:
	var scene_dir = scene_file_path.get_base_dir()
	var path = scene_dir.path_join("elevation.dat")
	if not FileAccess.file_exists(path):
		print("[range.gd] Elevation map not found at: ", path)
		return
		
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[range.gd] Failed to open elevation map: ", path)
		return
		
	var version = file.get_32()
	if version != 2:
		print("[range.gd] Unsupported elevation map version: ", version)
		return
		
	_elevation_width = file.get_32()
	_elevation_height = file.get_32()
	_elevation_left_lon = file.get_double()
	_elevation_right_lon = file.get_double()
	_elevation_top_lat = file.get_double()
	_elevation_bottom_lat = file.get_double()
	_elevation_ref_lat = file.get_double()
	_elevation_ref_lon = file.get_double()
	_elevation_meters_per_lat = file.get_double()
	_elevation_meters_per_lon = file.get_double()
	_elevation_offset = file.get_float()
	
	var num_elements = _elevation_width * _elevation_height
	_elevation_data.resize(num_elements)
	var min_val: float = INF
	var max_val: float = -INF
	for i in range(num_elements):
		var v = file.get_float()
		_elevation_data[i] = v
		if v < min_val:
			min_val = v
		if v > max_val:
			max_val = v
		
	# Check if elevation data is completely flat (e.g. failed/deprecated tiles or unpopulated)
	if abs(max_val - min_val) < 0.5:
		print("[range.gd] Elevation map is completely flat (range: %0.2fm). Falling back to procedural elevation." % (max_val - min_val))
		_has_elevation_map = false
		return

	_has_elevation_map = true
	print("[range.gd] Loaded elevation map: %dx%d (range: %0.2fm)" % [_elevation_width, _elevation_height, max_val - min_val])


func sample_elevation(x: float, z: float) -> float:
	var lon = _elevation_ref_lon + x / _elevation_meters_per_lon
	var lat = _elevation_ref_lat - z / _elevation_meters_per_lat
	
	var u = (lon - _elevation_left_lon) / (_elevation_right_lon - _elevation_left_lon)
	
	var y_val = log(tan(lat * PI / 360.0 + PI / 4.0))
	var y_top = log(tan(_elevation_top_lat * PI / 360.0 + PI / 4.0))
	var y_bottom = log(tan(_elevation_bottom_lat * PI / 360.0 + PI / 4.0))
	var v = (y_val - y_top) / (y_bottom - y_top)
	
	u = clamp(u, 0.0, 1.0)
	v = clamp(v, 0.0, 1.0)
	
	var w = _elevation_width
	var h = _elevation_height
	
	var sample_x = u * (w - 1)
	var sample_y = v * (h - 1)
	
	var x0 = clamp(floor(sample_x), 0, w - 1)
	var x1 = clamp(x0 + 1, 0, w - 1)
	var y0 = clamp(floor(sample_y), 0, h - 1)
	var y1 = clamp(y0 + 1, 0, h - 1)
	
	var tx = sample_x - x0
	var ty = sample_y - y0
	
	var h00 = _elevation_data[y0 * w + x0]
	var h10 = _elevation_data[y0 * w + x1]
	var h01 = _elevation_data[y1 * w + x0]
	var h11 = _elevation_data[y1 * w + x1]
	
	var h0 = h00 * (1.0 - tx) + h10 * tx
	var h1 = h01 * (1.0 - tx) + h11 * tx
	var raw_h = h0 * (1.0 - ty) + h1 * ty
	
	return raw_h - _elevation_offset


func _generate_ground_terrain() -> void:
	var min_x := -45.72   # -50 yards
	var max_x := 457.2    # 500 yards
	var min_z := -228.6   # -250 yards
	var max_z := 228.6    # 250 yards
	var subdiv_x := 160
	var subdiv_z := 120
	
	var cell_w := (max_x - min_x) / subdiv_x
	var cell_d := (max_z - min_z) / subdiv_z
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var mat := ShaderMaterial.new()
	var shader = load("res://Courses/Environments/shaders/parallax_turf.gdshader")
	if shader:
		mat.shader = shader
		mat.set_shader_parameter("albedo_tex", load("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_albedo.png"))
		mat.set_shader_parameter("normal_tex", load("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_normal-ogl.png"))
		mat.set_shader_parameter("ao_tex", load("res://Courses/Environments/grassy-meadow1-bl/grassy-meadow1_ao.png"))
		
		# Generate procedural Simplex noise texture for volumetric turf details
		var noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.4
		
		var noise_tex = NoiseTexture2D.new()
		noise_tex.noise = noise
		noise_tex.seamless = true
		
		mat.set_shader_parameter("noise_texture", noise_tex)
		mat.set_shader_parameter("layers", MobilePerformance.get_parallax_layers())
		mat.set_shader_parameter("depth_scale", MobilePerformance.get_parallax_depth_scale())
		mat.set_shader_parameter("depth_strength", 0.4)
		mat.set_shader_parameter("grass_color_tint", Color(0.9, 0.9, 0.9))
		mat.set_shader_parameter("roughness", 0.8)
		mat.set_shader_parameter("normal_depth", 0.85)
	st.set_material(mat)
	
	for z in range(subdiv_z):
		for x in range(subdiv_x):
			var x0 := min_x + x * cell_w
			var x1 := x0 + cell_w
			var z0 := min_z + z * cell_d
			var z1 := z0 + cell_d
			
			var p00 := Vector3(x0, get_height(x0, z0), z0)
			var p10 := Vector3(x1, get_height(x1, z0), z0)
			var p01 := Vector3(x0, get_height(x0, z1), z1)
			var p11 := Vector3(x1, get_height(x1, z1), z1)
			
			var uv00 := Vector2(x0, z0) * 0.05
			var uv10 := Vector2(x1, z0) * 0.05
			var uv01 := Vector2(x0, z1) * 0.05
			var uv11 := Vector2(x1, z1) * 0.05
			
			# Triangle 1
			st.set_uv(uv00)
			st.add_vertex(p00)
			st.set_uv(uv10)
			st.add_vertex(p10)
			st.set_uv(uv01)
			st.add_vertex(p01)
			
			# Triangle 2
			st.set_uv(uv10)
			st.add_vertex(p10)
			st.set_uv(uv11)
			st.add_vertex(p11)
			st.set_uv(uv01)
			st.add_vertex(p01)
			
	st.generate_normals()
	st.generate_tangents()
	
	var mesh := st.commit()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.name = "DynamicGround"
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_instance)
	
	var static_body := StaticBody3D.new()
	static_body.name = "StaticBody3D"
	mesh_instance.add_child(static_body)
	
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = mesh.create_trimesh_shape()
	static_body.add_child(collision_shape)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	is_driving_range = (name == "Range" and (scene_file_path.is_empty() or scene_file_path.ends_with("Range/range.tscn") or scene_file_path.ends_with("Range/range.scn")))
	if is_driving_range:
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null:
			mp_mgr.players.clear()
		_generate_ground_terrain()
	else:
		_load_elevation_map()
		_height_raycast = RayCast3D.new()
		_height_raycast.collision_mask = 1 # Terrain collision layer
		_height_raycast.collide_with_areas = false
		_height_raycast.collide_with_bodies = true
		_height_raycast.enabled = false
		add_child(_height_raycast)
	# Initialize Camera3DResource on PhantomCamera3D for dynamic fov/far changes
	if has_node("PhantomCamera3D"):
		var pcam = $PhantomCamera3D
		if pcam.camera_3d_resource == null:
			var res_script = load("res://addons/phantom_camera/scripts/resources/camera_3d_resource.gd")
			if res_script:
				pcam.camera_3d_resource = res_script.new()

	var pcam_host = find_child("PhantomCameraHost", true, false)
	if pcam_host != null and "interpolation_mode" in pcam_host:
		pcam_host.interpolation_mode = 1 # InterpolationMode.IDLE to smoothly track physics via Godot 4 interpolation

	_init_cached_surface_bodies()

	GlobalSettings.range_settings.camera_follow_mode.setting_changed.connect(set_camera_follow_mode)
	set_camera_follow_mode(GlobalSettings.range_settings.camera_follow_mode.value)
	GlobalSettings.range_settings.camera_height.setting_changed.connect(update_camera_offset)
	GlobalSettings.range_settings.camera_distance.setting_changed.connect(update_camera_offset)
	GlobalSettings.range_settings.camera_fov.setting_changed.connect(update_camera_fov)
	GlobalSettings.range_settings.camera_far.setting_changed.connect(update_camera_far)
	update_camera_offset()
	update_camera_fov(GlobalSettings.range_settings.camera_fov.value)
	update_camera_far(GlobalSettings.range_settings.camera_far.value)
	
	# Disconnect Player's direct connection to RangeUI's hit_shot signal to control execution order
	if has_node("RangeUI") and has_node("Player"):
		if $RangeUI.is_connected("hit_shot", Callable($Player, "_on_range_ui_hit_shot")):
			$RangeUI.disconnect("hit_shot", Callable($Player, "_on_range_ui_hit_shot"))
			
	if has_node("RangeUI"):
		if not $RangeUI.is_connected("hit_shot", Callable(self, "_on_range_ui_hit_shot")):
			$RangeUI.connect("hit_shot", Callable(self, "_on_range_ui_hit_shot"))
		if not $RangeUI.skip_flight_requested.is_connected(_on_skip_flight_requested):
			$RangeUI.skip_flight_requested.connect(_on_skip_flight_requested)
		if $RangeUI.has_signal("player_profile_changed") and not $RangeUI.player_profile_changed.is_connected(_on_player_profile_changed):
			$RangeUI.player_profile_changed.connect(_on_player_profile_changed)
		if has_node("SessionRecorder") and $RangeUI.has_method("get_selected_player_name"):
			$SessionRecorder.username = $RangeUI.get_selected_player_name()
			
	# Visual effects setup
	if has_node("Sky3D"):
		MobilePerformance.optimize_sky3d($Sky3D)
	MobilePerformance.optimize_scene(self)
	var range_quality = "Low" if (GlobalSettings != null and GlobalSettings.is_low_graphics()) else "High"
	MobilePerformance.apply_graphics_quality(self, range_quality)
	setup_depth_of_field()
	setup_vignette()
	setup_atmospheric_fog()
	GlobalSettings.range_settings.dof_enabled.setting_changed.connect(update_dof_enabled)
	GlobalSettings.range_settings.dof_blur_amount.setting_changed.connect(update_dof_blur_amount)
	GlobalSettings.range_settings.vignette_enabled.setting_changed.connect(update_vignette_enabled)
	GlobalSettings.range_settings.vignette_intensity.setting_changed.connect(update_vignette_intensity)
	
	GlobalSettings.range_settings.gimme_range_1_enabled.setting_changed.connect(func(_val): update_gimme_circles())
	GlobalSettings.range_settings.gimme_range_1_distance.setting_changed.connect(func(_val): update_gimme_circles())
	GlobalSettings.range_settings.gimme_range_2_enabled.setting_changed.connect(func(_val): update_gimme_circles())
	GlobalSettings.range_settings.gimme_range_2_distance.setting_changed.connect(func(_val): update_gimme_circles())
	GlobalSettings.range_settings.gimme_range_3_enabled.setting_changed.connect(func(_val): update_gimme_circles())
	GlobalSettings.range_settings.gimme_range_3_distance.setting_changed.connect(func(_val): update_gimme_circles())
	if GlobalSettings.range_settings.settings.has("wind_enabled"):
		GlobalSettings.range_settings.wind_enabled.setting_changed.connect(func(_val): _update_aim_distance_label_text())
	if GlobalSettings.has_signal("wind_changed"):
		GlobalSettings.wind_changed.connect(func(_spd, _dir): _update_aim_distance_label_text())
	GlobalSettings.start_round_wind(false)
	if has_node("/root/LaunchMonitorManager"):
		var launch_monitor = get_node("/root/LaunchMonitorManager")
		if not launch_monitor.hit_ball.is_connected(_on_launch_monitor_hit_ball):
			launch_monitor.hit_ball.connect(_on_launch_monitor_hit_ball)
		if launch_monitor.has_method("set_ready") and not launch_monitor.get("is_ready"):
			launch_monitor.call("set_ready")
	var is_practice_mode_primed: bool = GlobalSettings.practice_mode_primed
	var is_multiplayer_game = has_node("/root/MultiplayerManager") and get_node("/root/MultiplayerManager").players.size() > 1
	if is_practice_mode_primed and not is_multiplayer_game:
		practice_mode_active = true
		GlobalSettings.practice_mode_primed = false
	else:
		practice_mode_active = false
		GlobalSettings.practice_mode_primed = false
	if has_node("Camera3D"):
		$Camera3D.cull_mask = $Camera3D.cull_mask & ~2
	if has_node("PhantomCamera3D"):
		$PhantomCamera3D.cull_mask = $PhantomCamera3D.cull_mask & ~2
	if has_node("AerialCamera"):
		$AerialCamera.cull_mask = $AerialCamera.cull_mask & ~4

	if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
		var play_script = load("res://Courses/CoursePlay/course_play.gd")
		var play_controller = Node3D.new()
		play_controller.set_script(play_script)
		play_controller.name = "MultiplayerController"
		add_child(play_controller)

	# Create Aerial Camera dynamically if it doesn't exist
	if not has_node("AerialCamera"):
		var aerial_cam = Camera3D.new()
		aerial_cam.name = "AerialCamera"
		aerial_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		aerial_cam.size = aerial_zoom
		aerial_cam.position = Vector3(0, 150, 0)
		aerial_cam.rotation = Vector3(-PI/2, 0, 0) # Look straight down
		aerial_cam.cull_mask = aerial_cam.cull_mask & ~4
		add_child(aerial_cam)

	# Create Aim Marker flag/mesh dynamically
	var marker = MeshInstance3D.new()
	marker.name = "AimMarker"
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.2
	cyl.height = 15.0
	marker.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.2) # Neon Red
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2)
	marker.material_override = mat
	marker.layers = 2
	add_child(marker)
	marker.global_position = aim_target_pos
	marker.visible = false # Visible only in map view / minimap

	# Create Player Marker dynamically (Glowing green cylinder)
	var p_marker = MeshInstance3D.new()
	p_marker.name = "PlayerMarker"
	var p_cyl = CylinderMesh.new()
	p_cyl.top_radius = 0.4
	p_cyl.bottom_radius = 0.4
	p_cyl.height = 12.0
	p_marker.mesh = p_cyl
	var p_mat = StandardMaterial3D.new()
	p_mat.albedo_color = Color(0.1, 1.0, 0.1) # Neon Green
	p_mat.emission_enabled = true
	p_mat.emission = Color(0.1, 1.0, 0.1)
	p_marker.material_override = p_mat
	p_marker.layers = 2
	
	# Add static 2D billboard golf ball sprite to player marker for map/aerial view
	var p_sprite = Sprite3D.new()
	p_sprite.name = "MapBallSprite"
	p_sprite.layers = 2
	p_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	p_sprite.no_depth_test = true
	p_sprite.double_sided = true
	p_sprite.pixel_size = 0.04
	p_sprite.position = Vector3(0, 6.0, 0)
	if ResourceLoader.exists("res://assets/images/icons/golf_ball_icon.svg"):
		p_sprite.texture = load("res://assets/images/icons/golf_ball_icon.svg")
	p_marker.add_child(p_sprite)

	add_child(p_marker)
	p_marker.global_position = Vector3.ZERO
	p_marker.visible = false # Visible only in map view / minimap

	# Create Hole Outline Line dynamically
	var outline_inst = MeshInstance3D.new()
	outline_inst.name = "HoleOutline"
	var outline_imm = ImmediateMesh.new()
	outline_inst.mesh = outline_imm
	var outline_mat = StandardMaterial3D.new()
	outline_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5) # Semi-transparent light red
	outline_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline_mat.no_depth_test = true
	outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	outline_inst.material_override = outline_mat
	outline_inst.layers = 2
	add_child(outline_inst)
	outline_inst.visible = false

	# Create Minimap Hole Outline Line dynamically (thicker for minimap viewport)
	var minimap_outline_inst = MeshInstance3D.new()
	minimap_outline_inst.name = "MinimapHoleOutline"
	var minimap_outline_imm = ImmediateMesh.new()
	minimap_outline_inst.mesh = minimap_outline_imm
	var minimap_outline_mat = StandardMaterial3D.new()
	minimap_outline_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5) # Semi-transparent light red
	minimap_outline_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	minimap_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	minimap_outline_mat.no_depth_test = true
	minimap_outline_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	minimap_outline_inst.material_override = minimap_outline_mat
	minimap_outline_inst.layers = 2
	add_child(minimap_outline_inst)
	minimap_outline_inst.visible = false

	# Create Map Canvas Layer to prevent container stretching
	var canvas = CanvasLayer.new()
	canvas.name = "MapCanvas"
	canvas.visible = true
	add_child(canvas)

	# HBoxContainer for zoom buttons in Aerial View (placed top middle below the distance label)
	var zoom_vbox = HBoxContainer.new()
	zoom_vbox.name = "AerialZoomVBox"
	zoom_vbox.visible = is_aerial_view
	zoom_vbox.anchor_left = 0.5
	zoom_vbox.anchor_right = 0.5
	zoom_vbox.anchor_top = 0.0
	zoom_vbox.anchor_bottom = 0.0
	zoom_vbox.offset_left = -115
	zoom_vbox.offset_top = 115
	zoom_vbox.offset_right = 115
	zoom_vbox.offset_bottom = 175
	zoom_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	zoom_vbox.grow_vertical = Control.GROW_DIRECTION_END
	zoom_vbox.add_theme_constant_override("separation", 12)
	canvas.add_child(zoom_vbox)

	var zoom_in_btn = Button.new()
	zoom_in_btn.name = "ZoomInButton"
	zoom_in_btn.text = "+"
	zoom_in_btn.custom_minimum_size = Vector2(56, 56)
	apply_circular_button_style(zoom_in_btn, Color(0.15, 0.15, 0.15, 0.85))
	zoom_in_btn.pressed.connect(func():
		aerial_zoom = clamp(aerial_zoom - 25.0, 50.0, 500.0)
		if _last_zoom_zone == 0:
			_teebox_aerial_zoom = aerial_zoom
			_default_non_green_aerial_zoom = aerial_zoom
	)
	zoom_vbox.add_child(zoom_in_btn)

	var zoom_out_btn = Button.new()
	zoom_out_btn.name = "ZoomOutButton"
	zoom_out_btn.text = "-"
	zoom_out_btn.custom_minimum_size = Vector2(56, 56)
	apply_circular_button_style(zoom_out_btn, Color(0.15, 0.15, 0.15, 0.85))
	zoom_out_btn.pressed.connect(func():
		aerial_zoom = clamp(aerial_zoom + 25.0, 50.0, 500.0)
		if _last_zoom_zone == 0:
			_teebox_aerial_zoom = aerial_zoom
			_default_non_green_aerial_zoom = aerial_zoom
	)
	zoom_vbox.add_child(zoom_out_btn)

	var grid_toggle_btn = Button.new()
	grid_toggle_btn.name = "GridToggleButton"
	grid_toggle_btn.text = "📊"
	grid_toggle_btn.tooltip_text = "Toggle Slope Grid & Heatmap"
	grid_toggle_btn.custom_minimum_size = Vector2(56, 56)
	var btn_color = Color(0.2, 0.6, 0.3, 0.85) if show_green_grid else Color(0.15, 0.15, 0.15, 0.85)
	apply_circular_button_style(grid_toggle_btn, btn_color)
	grid_toggle_btn.pressed.connect(func():
		show_green_grid = not show_green_grid
	)
	zoom_vbox.add_child(grid_toggle_btn)

	# Create Aim Distance Badge background Panel
	var badge = Panel.new()
	badge.name = "AimDistanceBadge"
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.08, 0.08, 0.08, 0.8) # Premium dark translucent
	badge_style.border_width_left = 1
	badge_style.border_width_top = 1
	badge_style.border_width_right = 1
	badge_style.border_width_bottom = 1
	badge_style.border_color = Color(0.3, 0.3, 0.3, 0.8)
	badge_style.corner_radius_top_left = 12
	badge_style.corner_radius_top_right = 12
	badge_style.corner_radius_bottom_left = 12
	badge_style.corner_radius_bottom_right = 12
	badge.add_theme_stylebox_override("panel", badge_style)
	
	badge.anchor_left = 0.5
	badge.anchor_right = 0.5
	badge.offset_left = -260
	badge.offset_top = 20
	badge.offset_right = 260
	badge.offset_bottom = 60
	canvas.add_child(badge)

	# Create AimDistanceLabel (path remains MapCanvas/AimDistanceLabel!)
	var aim_lbl = Label.new()
	aim_lbl.name = "AimDistanceLabel"
	aim_lbl.text = "🎯 Aim: --- | ⛰️ Elevation: 0 Feet | 🟢 Fairway"
	aim_lbl.add_theme_font_size_override("font_size", 18)
	aim_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	aim_lbl.add_theme_constant_override("outline_size", 4)
	aim_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	aim_lbl.anchor_left = 0.5
	aim_lbl.anchor_right = 0.5
	aim_lbl.offset_left = -260
	aim_lbl.offset_top = 20
	aim_lbl.offset_right = 260
	aim_lbl.offset_bottom = 60
	aim_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aim_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	aim_lbl.visible = true
	canvas.add_child(aim_lbl)

	# Create labels inside MapCanvas
	var hole_lbl = Label.new()
	hole_lbl.name = "HoleInfoLabel"
	hole_lbl.visible = is_aerial_view
	hole_lbl.text = "Hole 1 | Par 4 | --- Yards"
	hole_lbl.add_theme_font_size_override("font_size", 20)
	hole_lbl.add_theme_color_override("font_color", Color.WHITE)
	# Position at top center, below the aim badge
	hole_lbl.anchor_left = 0.5
	hole_lbl.anchor_right = 0.5
	hole_lbl.offset_left = -200
	hole_lbl.offset_top = 70
	hole_lbl.offset_bottom = 110
	hole_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	canvas.add_child(hole_lbl)

	# Hide duplicate HoleInfoLabel if in course play mode
	var is_course_play = false
	if has_node("/root/MultiplayerManager"):
		var mp = get_node("/root/MultiplayerManager")
		if not mp.players.is_empty():
			is_course_play = true
	if is_course_play:
		hole_lbl.visible = false

	# Create Aim Line dynamically for drawing aiming direction
	aim_line = MeshInstance3D.new()
	aim_line.name = "AimLine"
	var imm = ImmediateMesh.new()
	aim_line.mesh = imm
	var line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(1.0, 0.2, 0.2) # Neon Red
	line_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	line_mat.no_depth_test = true
	line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	aim_line.material_override = line_mat
	aim_line.layers = 2
	add_child(aim_line)
	aim_line.visible = false

	# Load course.json to position the player at the Tee Box of Hole 1 (if in practice mode)
	var course_json_path = ""
	var course_mgr = get_node_or_null("/root/CourseManager")
	if course_mgr != null and course_mgr.has_method("get_current_config_path"):
		course_json_path = course_mgr.get_current_config_path()
	if course_json_path.is_empty():
		course_json_path = scene_file_path.get_base_dir() + "/course.json"

	if FileAccess.file_exists(course_json_path):
		var file = FileAccess.open(course_json_path, FileAccess.READ)
		if file:
			var json_text = file.get_as_text()
			var json = JSON.new()
			if json.parse(json_text) == OK:
				course_data_dict = json.data
				if practice_mode_active:
					if GlobalSettings.is_chipping_minigame:
						var hole_info_data = course_data_dict.get("Hole Info", {})
						var hole_keys = hole_info_data.keys()
						hole_keys.sort()
						var target_idx = hole_keys.find("Hole 17")
						if target_idx != -1:
							load_practice_hole(target_idx)
						else:
							load_practice_hole(0)
						set_practice_mode(true)
						_setup_chipping_minigame()
					else:
						load_practice_hole(0)
						set_practice_mode(true)
				else:
					var hole_info_data = course_data_dict.get("Hole Info", {})
					var hole_keys = hole_info_data.keys()
					hole_keys.sort()
					if not hole_keys.is_empty():
						var start_hole_id = hole_keys[0]
						var mp_mgr = get_node_or_null("/root/MultiplayerManager")
						if mp_mgr != null and not mp_mgr.players.is_empty() and mp_mgr.current_hole_index < mp_mgr.hole_ids.size():
							start_hole_id = mp_mgr.hole_ids[mp_mgr.current_hole_index]
						
						var first_hole = hole_info_data.get(start_hole_id, hole_info_data[hole_keys[0]])
						var tee_boxes = first_hole.get("Tee Boxes", {})
						var tee_pos = tee_boxes.get("Blue")
						if tee_pos == null:
							for k in tee_boxes.keys():
								tee_pos = tee_boxes[k]
								break
						if tee_pos != null:
							var spawn_pos = Vector3(tee_pos[0], get_height(tee_pos[0], tee_pos[1]) + 0.059435, tee_pos[1])
							practice_start_pos = spawn_pos
							var hole_loc = first_hole.get("Hole Location")
							var par = first_hole.get("Par", 4)
							var hole_name = first_hole.get("Name", "Hole 1")
							current_hole_name = hole_name
							current_hole_par = par
							if hole_loc != null:
								current_hole_location = Vector3(hole_loc[0], get_height(hole_loc[0], hole_loc[1]), hole_loc[1])
								aim_target_pos = current_hole_location
							
							var is_mp = mp_mgr != null and not mp_mgr.players.is_empty()
							if is_mp:
								# Multiplayer controller (course_play.gd) handles positioning, cameras, and HUD.
								# We only need to ensure the flag pin is spawned.
								if hole_loc != null:
									_spawn_flag_pin()
							else:
								if has_node("Player") and $Player.ball != null:
									$Player.ball.spawn_position = spawn_pos
									$Player.ball.reset()
								
								if hole_loc != null:
									current_hole_location = Vector3(hole_loc[0], get_height(hole_loc[0], hole_loc[1]), hole_loc[1])
									var dist_to_pin_yards = int(spawn_pos.distance_to(current_hole_location) * 1.09361)
									current_hole_tee_dist_yards = dist_to_pin_yards
									hole_lbl.text = "%s | Par %d | %d Yards | Ball: %d Yards to Pin" % [hole_name, par, dist_to_pin_yards, dist_to_pin_yards]
									update_auto_club()
									apply_default_aim()
									_spawn_flag_pin()
								
							print("[CoursePlay] Player positioned at %s Tee: " % start_hole_id, spawn_pos, " | Aiming at green: ", aim_target_pos)

	# Programmatically connect dynamic course play signals
	var player_node = get_node_or_null("Player")
	var range_ui = get_node_or_null("RangeUI")
	
	var session_rec = get_node_or_null("SessionRecorder")
	if session_rec == null:
		var rec_script = load("res://SessionRecorder/session_recorder.gd")
		if rec_script != null:
			session_rec = Node.new()
			session_rec.set_script(rec_script)
			session_rec.name = "SessionRecorder"
			add_child(session_rec)
			print("[range.gd] Dynamically created missing SessionRecorder node!")

	var tcp_server = get_node_or_null("TCPServer")
	var old_tcp_server = get_node_or_null("TcpServer")
	if old_tcp_server != null:
		if tcp_server == null:
			tcp_server = old_tcp_server
			tcp_server.name = "TCPServer"
			print("[range.gd] Renamed lowercase TcpServer to TCPServer for compatibility")
		else:
			old_tcp_server.free()
			print("[range.gd] Freed duplicate lowercase TcpServer node to prevent port conflicts!")

	if tcp_server == null:
		var tcp_script = load("res://addons/launch_monitors/common/tcp_server/TcpServer.cs")
		if tcp_script != null:
			tcp_server = tcp_script.new()
			tcp_server.name = "TCPServer"
			add_child(tcp_server)
			print("[range.gd] Dynamically created missing TCPServer node!")
	
	if player_node != null:
		var self_rest_callable = Callable(self, "_on_golf_ball_rest")
		if not player_node.is_connected("rest", self_rest_callable):
			player_node.connect("rest", self_rest_callable)
		if session_rec != null:
			var rec_rest_callable = Callable(session_rec, "_on_golf_ball_rest")
			if not player_node.is_connected("rest", rec_rest_callable):
				player_node.connect("rest", rec_rest_callable)
		var self_hit_callable = Callable(self, "_on_player_manual_hit")
		if player_node.has_signal("manual_hit") and not player_node.is_connected("manual_hit", self_hit_callable):
			player_node.connect("manual_hit", self_hit_callable)
				
	if range_ui != null and session_rec != null:
		if range_ui.has_signal("rec_button_pressed"):
			var toggle_rec_callable = Callable(session_rec, "toggle_recording")
			if not range_ui.is_connected("rec_button_pressed", toggle_rec_callable):
				range_ui.connect("rec_button_pressed", toggle_rec_callable)
		if range_ui.has_signal("set_session"):
			var set_sess_callable = Callable(session_rec, "_on_range_ui_set_session")
			if not range_ui.is_connected("set_session", set_sess_callable):
				range_ui.connect("set_session", set_sess_callable)
			
		if session_rec.has_signal("recording_state"):
			var rec_state_callable = Callable(range_ui, "_on_session_recorder_recording_state")
			if not session_rec.is_connected("recording_state", rec_state_callable):
				session_rec.connect("recording_state", rec_state_callable)
		if session_rec.has_signal("set_session"):
			var ui_set_sess_callable = Callable(range_ui, "_on_session_recorder_set_session")
			if not session_rec.is_connected("set_session", ui_set_sess_callable):
				session_rec.connect("set_session", ui_set_sess_callable)

	# Connect TCPServer signals dynamically for dynamic course play shot injection
	if tcp_server != null:
		if tcp_server.has_signal("HitBall"):
			var hit_ball_callable = Callable(self, "_on_tcp_client_hit_ball")
			if not tcp_server.is_connected("HitBall", hit_ball_callable):
				tcp_server.connect("HitBall", hit_ball_callable)
			
			# Player's connection is bypassed and handled sequentially in _on_tcp_client_hit_ball
			pass
				
		if player_node != null:
			if player_node.has_signal("bad_data"):
				var bad_callable = Callable(tcp_server, "_on_player_bad_data")
				if not player_node.is_connected("bad_data", bad_callable):
					player_node.connect("bad_data", bad_callable)
			if player_node.has_signal("good_data"):
				var good_callable = Callable(tcp_server, "_on_golf_ball_good_data")
				if not player_node.is_connected("good_data", good_callable):
					player_node.connect("good_data", good_callable)
	update_auto_club()
	update_hole_outline()
	if is_driving_range:
		call_deferred("_spawn_driving_range_elements")

	# Player-club stats setup
	if has_node("/root/EventBus"):
		if not get_node("/root/EventBus").is_connected("club_selected", Callable(self, "_on_club_selected")):
			get_node("/root/EventBus").connect("club_selected", Callable(self, "_on_club_selected"))
			
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null:
		if not mp_mgr.active_player_changed.is_connected(Callable(self, "_on_active_player_changed")):
			mp_mgr.active_player_changed.connect(Callable(self, "_on_active_player_changed"))
		if not mp_mgr.hole_completed.is_connected(Callable(self, "_on_hole_completed")):
			mp_mgr.hole_completed.connect(Callable(self, "_on_hole_completed"))
			
	if range_ui != null and range_ui.has_signal("set_session"):
		if not range_ui.is_connected("set_session", Callable(self, "_on_player_changed")):
			range_ui.connect("set_session", Callable(self, "_on_player_changed"))
			
	_update_averages()
	update_current_lie_and_reduction()


var practice_mode_active: bool = false
var practice_start_pos: Vector3 = Vector3(0.0, 0.02, 0.0)
var current_practice_hole_index: int = 0
var place_ball_mode: bool = false


func is_any_dialog_open() -> bool:
	if has_node("RangeUI") and $RangeUI.has_node("SettingsLayer") and $RangeUI.get_node("SettingsLayer").visible:
		return true
	var cp = get_node_or_null("MultiplayerController")
	if cp != null and cp.has_method("is_any_dialog_open") and cp.call("is_any_dialog_open"):
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if is_any_dialog_open():
		return

	if event.is_action_pressed("reset"):
		_reset_display_data()
		$RangeUI.set_data(display_data)
		if has_node("RangeUI") and $RangeUI.has_method("on_next_shot_started"):
			$RangeUI.on_next_shot_started()

	# Keyboard shortcuts & controller button bindings
	if ((event is InputEventKey and not event.echo) or event is InputEventJoypadButton) and event.is_pressed():
		if event.is_action_pressed("aerial_aim"):
			_on_map_button_pressed()
			get_viewport().set_input_as_handled()
			return
		elif ((event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE) or (event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B)) and is_aerial_view:
			_on_map_button_pressed()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("green_grid"):
			show_green_grid = not show_green_grid
			var course_play_node = get_node_or_null("MultiplayerController")
			if course_play_node != null and "grid_btn" in course_play_node:
				var g_btn = course_play_node.grid_btn
				if g_btn != null and is_instance_valid(g_btn):
					var col = Color(0.2, 0.65, 0.35, 0.95) if show_green_grid else Color(0.15, 0.15, 0.15, 0.85)
					course_play_node.call("apply_circular_button_style", g_btn, col)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("toggle_stats"):
			if has_node("RangeUI"):
				$RangeUI.toggle_stats_visibility()
				var course_play_node = get_node_or_null("MultiplayerController")
				if course_play_node != null and "stats_btn" in course_play_node:
					var s_btn = course_play_node.stats_btn
					if s_btn != null and is_instance_valid(s_btn):
						var is_vis = $RangeUI.is_stats_visible()
						var col = Color(0.24, 0.46, 0.72, 0.85) if is_vis else Color(0.15, 0.15, 0.15, 0.85)
						course_play_node.call("apply_circular_button_style", s_btn, col)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("next_club"):
			_cycle_club(true)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("prev_club"):
			_cycle_club(false)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("skip_flight"):
			if has_node("RangeUI"):
				$RangeUI.emit_signal("skip_flight_requested")
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("hit_shot"):
			if has_node("Player"):
				$Player._on_hit_button_pressed()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("toggle_helpers"):
			if has_node("RangeUI") and $RangeUI.get("_hide_helpers_btn") != null:
				var h_btn = $RangeUI.get("_hide_helpers_btn") as Button
				if h_btn != null and is_instance_valid(h_btn):
					h_btn.emit_signal("pressed")
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("announcer_toggle"):
			_toggle_announcer_mute()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("suspense_toggle"):
			_toggle_suspense()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("golfer_cam_toggle"):
			if has_node("RangeUI"):
				var r_ui = $RangeUI
				if not r_ui.is_golfer_camera_enabled():
					r_ui.set_golfer_camera_visible(true)
				elif r_ui.is_golfer_camera_minimized():
					r_ui.restore_golfer_camera()
				else:
					r_ui.set_golfer_camera_visible(false)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("putting_cam_toggle"):
			if has_node("RangeUI"):
				var r_ui = $RangeUI
				if not r_ui.is_putting_camera_enabled():
					r_ui.set_putting_camera_visible(true)
				elif r_ui.is_putting_camera_minimized():
					r_ui.restore_putting_camera()
				else:
					r_ui.set_putting_camera_visible(false)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("shot_analysis_toggle"):
			if has_node("RangeUI"):
				var new_v = not $RangeUI.is_shot_analysis_enabled()
				$RangeUI.set_shot_analysis_enabled(new_v)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("distance_menu_toggle"):
			_toggle_distance_menu()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("aim_left"):
			_apply_aim_step(-1.5, 0.0)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("aim_right"):
			_apply_aim_step(1.5, 0.0)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("aim_forward"):
			_apply_aim_step(0.0, 2.0)
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed("aim_backward"):
			_apply_aim_step(0.0, -2.0)
			get_viewport().set_input_as_handled()
			return
		else:
			var handled_stat = _check_stat_toggle_input(event)
			if handled_stat:
				get_viewport().set_input_as_handled()
				return

	# Multi-touch tracking for screen touches and drags
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_points[event.index] = event.position
		else:
			_touch_points.erase(event.index)
			if _touch_points.size() < 2:
				_last_pinch_distance = -1.0

	elif event is InputEventScreenDrag:
		_touch_points[event.index] = event.position

	# Handle native OS magnify gestures (touchpads / Android gestures)
	if event is InputEventMagnifyGesture and is_aerial_view:
		var factor: float = event.factor
		if factor > 0.0:
			aerial_zoom = clamp(aerial_zoom / factor, 50.0, 500.0)
			if _last_zoom_zone == 0:
				_teebox_aerial_zoom = aerial_zoom
				_default_non_green_aerial_zoom = aerial_zoom
			get_viewport().set_input_as_handled()
			return

	# Handle 2-finger pinch zoom in aerial view
	if is_aerial_view and _touch_points.size() >= 2:
		var touch_indices = _touch_points.keys()
		var p0: Vector2 = _touch_points[touch_indices[0]]
		var p1: Vector2 = _touch_points[touch_indices[1]]
		var current_dist: float = p0.distance_to(p1)

		if _last_pinch_distance > 0.0:
			var dist_delta: float = current_dist - _last_pinch_distance
			var pinch_sensitivity: float = 0.5
			aerial_zoom = clamp(aerial_zoom - dist_delta * pinch_sensitivity, 50.0, 500.0)
			if _last_zoom_zone == 0:
				_teebox_aerial_zoom = aerial_zoom
				_default_non_green_aerial_zoom = aerial_zoom

		_last_pinch_distance = current_dist
		is_mouse_down_on_map = false
		is_dragging_map = false
		get_viewport().set_input_as_handled()
		return

	# Handle mouse wheel zoom in aerial view
	if event is InputEventMouseButton and is_aerial_view and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			aerial_zoom = clamp(aerial_zoom - 25.0, 50.0, 500.0)
			if _last_zoom_zone == 0:
				_teebox_aerial_zoom = aerial_zoom
				_default_non_green_aerial_zoom = aerial_zoom
			get_viewport().set_input_as_handled()
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			aerial_zoom = clamp(aerial_zoom + 25.0, 50.0, 500.0)
			if _last_zoom_zone == 0:
				_teebox_aerial_zoom = aerial_zoom
				_default_non_green_aerial_zoom = aerial_zoom
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			if GlobalSettings.is_chipping_minigame and event.button_index == MOUSE_BUTTON_LEFT:
				var camera = get_viewport().get_camera_3d()
				if camera != null:
					var ray_start = camera.project_ray_origin(event.position)
					var ray_dir = camera.project_ray_normal(event.position)
					var ray_end = ray_start + ray_dir * 1000.0
					var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
					var hit = get_world_3d().direct_space_state.intersect_ray(query)
					if not hit.is_empty():
						var clicked_point = hit["position"]
						var closest_idx = -1
						var min_dist = 9999.0
						for i in range(chipping_island_positions.size()):
							var d = clicked_point.distance_to(chipping_island_positions[i])
							if d < min_dist:
								min_dist = d
								closest_idx = i
						if min_dist <= 8.0:
							_select_chipping_target(closest_idx)
							get_viewport().set_input_as_handled()
							return

			if is_aerial_view:
				is_mouse_down_on_map = true
				is_dragging_map = false
				map_drag_start_pos = event.position
				total_map_drag_dist = 0.0
				get_viewport().set_input_as_handled()
			else:
				var ball_at_rest = true
				if $Player and $Player.ball:
					ball_at_rest = ($Player.get_ball_state() == PhysicsEnums.BallState.REST) and not _shot_active
				if ball_at_rest:
					var vp_width = get_viewport().get_visible_rect().size.x
					if event.position.x >= vp_width * 0.5:
						screen_aim_direction = 1.0 # Right half: rotate right
					else:
						screen_aim_direction = -1.0 # Left half: rotate left
					is_screen_aiming = true
		else:
			if is_aerial_view:
				if is_mouse_down_on_map:
					is_mouse_down_on_map = false
					var was_dragging = is_dragging_map
					is_dragging_map = false
					get_viewport().set_input_as_handled()
					if not was_dragging:
						if practice_mode_active and place_ball_mode and event.button_index == MOUSE_BUTTON_LEFT:
							_perform_practice_teleport(event.position)
						else:
							_perform_map_click_aim(event.position)
			else:
				is_screen_aiming = false
				screen_aim_direction = 0.0

	elif event is InputEventMouseMotion:
		if is_aerial_view and is_mouse_down_on_map:
			var drag_dist = event.relative.length()
			total_map_drag_dist += drag_dist
			if total_map_drag_dist > 5.0 or is_dragging_map:
				is_dragging_map = true
				if has_node("AerialCamera") and $Player and $Player.ball:
					var scale_factor = $AerialCamera.size / get_viewport().get_visible_rect().size.y
					var tx = -event.relative.x * scale_factor
					var ty = event.relative.y * scale_factor
					
					# Get the camera orientation vectors dynamically to match current rotation
					var ball_pos = $Player.ball.global_position
					var hole_pos = current_hole_location
					if hole_pos.is_zero_approx():
						hole_pos = Vector3(250.0, ball_pos.y, 0.0)
					var dir_3d = (hole_pos - ball_pos)
					dir_3d.y = 0
					if dir_3d.is_zero_approx():
						dir_3d = Vector3(0, 0, -1)
					else:
						dir_3d = dir_3d.normalized()
					
					var right_vec = dir_3d.cross(Vector3.UP).normalized()
					var up_vec = dir_3d
					
					aerial_cam_user_offset += right_vec * tx + up_vec * ty
				get_viewport().set_input_as_handled()
		elif is_screen_aiming and not is_aerial_view:
			var vp_width = get_viewport().get_visible_rect().size.x
			if event.position.x >= vp_width * 0.5:
				screen_aim_direction = 1.0
			else:
				screen_aim_direction = -1.0


func set_aim_target(target_pos: Vector3, update_club: bool = true) -> void:
	_aim_is_manual = true
	aim_target_pos = target_pos
	aim_target_pos.y = get_height(target_pos.x, target_pos.z)
	update_dof_focus()
	if has_node("AimMarker"):
		$AimMarker.global_position = aim_target_pos
	
	if has_node("Player") and $Player.ball != null:
		var ball_pos = $Player.ball.global_position
		var diff = aim_target_pos - ball_pos
		var angle_rad = atan2(diff.z, diff.x)
		$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
		
		if has_node("MapCanvas/AimDistanceLabel"):
			var dist_yards = int(ball_pos.distance_to(aim_target_pos) * 1.09361)
			set_aim_distance(dist_yards)
			
		if update_club:
			update_auto_club(true)
			
		var is_on_green = is_ball_on_green()
		var cam_pos = get_address_camera_position(ball_pos, -angle_rad, is_on_green)
		var target_look = get_camera_target_look(aim_target_pos, ball_pos, is_on_green)
		if has_node("PhantomCamera3D"):
			$PhantomCamera3D.follow_mode = PhantomCamera3D.FollowMode.NONE
			$PhantomCamera3D.look_at_mode = PhantomCamera3D.LookAtMode.NONE
			$PhantomCamera3D.global_position = cam_pos
			$PhantomCamera3D.look_at(target_look)
			if $PhantomCamera3D.camera_3d_resource != null:
				$PhantomCamera3D.camera_3d_resource.fov = GlobalSettings.range_settings.camera_fov.value
		if has_node("Camera3D"):
			$Camera3D.global_position = cam_pos
			$Camera3D.look_at(target_look)
			$Camera3D.fov = GlobalSettings.range_settings.camera_fov.value


func _perform_map_click_aim(mouse_pos: Vector2) -> void:
	var camera = get_viewport().get_camera_3d()
	if camera != null:
		var ray_start = camera.project_ray_origin(mouse_pos)
		var ray_dir = camera.project_ray_normal(mouse_pos)
		var ray_end = ray_start + ray_dir * 1000.0
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if $Player and $Player.ball:
			query.exclude = [$Player.ball.get_rid()]
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var clicked_point = hit["position"]
			set_aim_target(clicked_point, true)
			print("[Aim] Aim target set to: ", clicked_point, " | Yaw offset: ", $Player.ball.aim_yaw_offset_deg)


func _perform_practice_teleport(mouse_pos: Vector2) -> void:
	var camera = get_viewport().get_camera_3d()
	if camera != null:
		var ray_start = camera.project_ray_origin(mouse_pos)
		var ray_dir = camera.project_ray_normal(mouse_pos)
		var ray_end = ray_start + ray_dir * 1000.0
		var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		if $Player and $Player.ball:
			query.exclude = [$Player.ball.get_rid()]
		var hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			var clicked_point = hit["position"]
			clicked_point.y = get_height(clicked_point.x, clicked_point.z) + GolfBall.GROUND_CENTER_HEIGHT + GolfBall.GROUND_SNAP_OFFSET
			practice_start_pos = clicked_point
			$Player.ball.spawn_position = clicked_point
			$Player.ball.global_position = clicked_point
			$Player.ball.reset()
			print("[PracticeMode] Ball spawned at: ", clicked_point)
			
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				var active_player = mp_mgr.get_active_player()
				if not active_player.is_empty():
					active_player["position"] = clicked_point
			
			_user_custom_club = ""
			update_current_lie_and_reduction()
			
			# Automatically aim at the pin/fairway and position the camera behind the ball
			if not current_hole_location.is_zero_approx():
				_update_hole_info_label(true)
				update_auto_club()
				apply_default_aim()


func _process_screen_aiming(delta: float) -> void:
	if not ($Player and $Player.ball):
		return
	if screen_aim_direction == 0.0:
		return

	var ball_pos = $Player.ball.global_position
	var diff = aim_target_pos - ball_pos
	var dist_xz = Vector2(diff.x, diff.z).length()
	if dist_xz < 0.5:
		if not current_hole_location.is_zero_approx() and ball_pos.distance_to(current_hole_location) > 0.5:
			var hole_diff = current_hole_location - ball_pos
			dist_xz = Vector2(hole_diff.x, hole_diff.z).length()
		else:
			dist_xz = 50.0

	var current_angle = atan2(diff.z, diff.x)
	var d_angle = deg_to_rad(screen_aim_speed_deg) * delta * screen_aim_direction
	var new_angle = current_angle + d_angle

	var new_diff_x = cos(new_angle) * dist_xz
	var new_diff_z = sin(new_angle) * dist_xz

	aim_target_pos = ball_pos + Vector3(new_diff_x, 0.0, new_diff_z)
	aim_target_pos.y = get_height(aim_target_pos.x, aim_target_pos.z)
	_aim_is_manual = true

	$Player.ball.aim_yaw_offset_deg = rad_to_deg(-new_angle)

	if has_node("AimMarker"):
		$AimMarker.global_position = aim_target_pos

	if has_node("MapCanvas/AimDistanceLabel"):
		var dist_yards = int(ball_pos.distance_to(aim_target_pos) * 1.09361)
		set_aim_distance(dist_yards)

	update_auto_club(false)
	update_dof_focus()

	var is_on_green = is_ball_on_green()
	var cam_pos = get_address_camera_position(ball_pos, -new_angle, is_on_green)
	var target_look = get_camera_target_look(aim_target_pos, ball_pos, is_on_green)
	if has_node("PhantomCamera3D"):
		$PhantomCamera3D.global_position = cam_pos
		$PhantomCamera3D.look_at(target_look)
	if has_node("Camera3D"):
		$Camera3D.global_position = cam_pos
		$Camera3D.look_at(target_look)


func _process_keyboard_aiming(delta: float) -> void:
	if not ($Player and $Player.ball) or _shot_active:
		return
	if is_any_dialog_open():
		return

	var turn_input: float = 0.0
	if Input.is_action_pressed("aim_left"):
		turn_input -= 1.0
	if Input.is_action_pressed("aim_right"):
		turn_input += 1.0

	var dist_input: float = 0.0
	if Input.is_action_pressed("aim_forward"):
		dist_input += 1.0
	if Input.is_action_pressed("aim_backward"):
		dist_input -= 1.0

	if turn_input == 0.0 and dist_input == 0.0:
		return

	var ball_pos = $Player.ball.global_position
	var diff = aim_target_pos - ball_pos
	var dist_xz = Vector2(diff.x, diff.z).length()
	if dist_xz < 0.5:
		if not current_hole_location.is_zero_approx() and ball_pos.distance_to(current_hole_location) > 0.5:
			var hole_diff = current_hole_location - ball_pos
			dist_xz = Vector2(hole_diff.x, hole_diff.z).length()
		else:
			dist_xz = 50.0

	var current_angle = atan2(diff.z, diff.x)
	if turn_input != 0.0:
		var d_angle = deg_to_rad(screen_aim_speed_deg) * delta * turn_input
		current_angle += d_angle

	if dist_input != 0.0:
		var d_dist = 40.0 * delta * dist_input
		dist_xz = clamp(dist_xz + d_dist, 5.0, 650.0)

	var new_diff_x = cos(current_angle) * dist_xz
	var new_diff_z = sin(current_angle) * dist_xz

	aim_target_pos = ball_pos + Vector3(new_diff_x, 0.0, new_diff_z)
	aim_target_pos.y = get_height(aim_target_pos.x, aim_target_pos.z)
	_aim_is_manual = true

	$Player.ball.aim_yaw_offset_deg = rad_to_deg(-current_angle)

	if has_node("AimMarker"):
		$AimMarker.global_position = aim_target_pos

	var dist_yards = int(ball_pos.distance_to(aim_target_pos) * 1.09361)
	if has_node("MapCanvas/AimDistanceLabel"):
		set_aim_distance(dist_yards)

	update_auto_club(false)
	update_dof_focus()

	if not is_aerial_view:
		var is_on_green = is_ball_on_green()
		var cam_pos = get_address_camera_position(ball_pos, -current_angle, is_on_green)
		var target_look = get_camera_target_look(aim_target_pos, ball_pos, is_on_green)
		if has_node("PhantomCamera3D"):
			$PhantomCamera3D.global_position = cam_pos
			$PhantomCamera3D.look_at(target_look)
		if has_node("Camera3D"):
			$Camera3D.global_position = cam_pos
			$Camera3D.look_at(target_look)


func _apply_aim_step(turn_deg: float, dist_m: float) -> void:
	if not ($Player and $Player.ball) or _shot_active:
		return
	var ball_pos = $Player.ball.global_position
	var diff = aim_target_pos - ball_pos
	var dist_xz = Vector2(diff.x, diff.z).length()
	if dist_xz < 0.5:
		dist_xz = 50.0

	var current_angle = atan2(diff.z, diff.x)
	if turn_deg != 0.0:
		current_angle += deg_to_rad(turn_deg)
	if dist_m != 0.0:
		dist_xz = clamp(dist_xz + dist_m, 5.0, 650.0)

	var new_diff_x = cos(current_angle) * dist_xz
	var new_diff_z = sin(current_angle) * dist_xz

	aim_target_pos = ball_pos + Vector3(new_diff_x, 0.0, new_diff_z)
	aim_target_pos.y = get_height(aim_target_pos.x, aim_target_pos.z)
	_aim_is_manual = true

	$Player.ball.aim_yaw_offset_deg = rad_to_deg(-current_angle)

	if has_node("AimMarker"):
		$AimMarker.global_position = aim_target_pos

	var dist_yards = int(ball_pos.distance_to(aim_target_pos) * 1.09361)
	if has_node("MapCanvas/AimDistanceLabel"):
		set_aim_distance(dist_yards)

	update_auto_club(false)
	update_dof_focus()

	if not is_aerial_view:
		var is_on_green = is_ball_on_green()
		var cam_pos = get_address_camera_position(ball_pos, -current_angle, is_on_green)
		var target_look = get_camera_target_look(aim_target_pos, ball_pos, is_on_green)
		if has_node("PhantomCamera3D"):
			$PhantomCamera3D.global_position = cam_pos
			$PhantomCamera3D.look_at(target_look)
		if has_node("Camera3D"):
			$Camera3D.global_position = cam_pos
			$Camera3D.look_at(target_look)


func _cycle_club(longer: bool) -> void:
	var club_sel = get_club_selector()
	if club_sel != null and is_instance_valid(club_sel):
		if longer:
			club_sel.call("select_next_club")
		else:
			club_sel.call("select_prev_club")


func _check_stat_toggle_input(event: InputEvent) -> bool:
	for stat in StatDefinitions.STATS:
		var stat_id = str(stat.get("id", ""))
		var act = "stat_toggle_" + stat_id
		if event.is_action_pressed(act):
			KeybindingManager.toggle_stat(stat_id)
			return true
	return false


func _toggle_announcer_mute() -> void:
	var a = get_node_or_null("/root/AnnouncerEngine")
	if a != null:
		var cur = a.get("AnnouncerRange") as bool
		var new_val = not cur
		a.set("AnnouncerRange", new_val)
		GlobalSettings.save_settings()
		if has_node("RangeUI"):
			$RangeUI.call("update_announcer_button_state")
		if new_val:
			a.call("SpeakHecklesEnabled")
		else:
			a.call("SpeakHecklesDisabled")


func _toggle_suspense() -> void:
	if has_node("/root/GlobalSettings"):
		var cur = GlobalSettings.range_settings.tension_effects_enabled.value
		GlobalSettings.range_settings.tension_effects_enabled.value = not cur
		GlobalSettings.save_settings()
		if cur and has_node("/root/TensionManager"):
			TensionManager.stop_tension()
		if has_node("RangeUI"):
			$RangeUI.call("update_suspense_button_state")


func _toggle_distance_menu() -> void:
	if has_node("RangeUI"):
		$RangeUI.call("toggle_distance_menu")


func _on_tcp_client_hit_ball(data: Dictionary) -> void:
	var speed: float = float(data.get("BallSpeed", data.get("Speed", 0.0)))
	var shot_type = str(data.get("ShotType", "")).to_lower()
	if speed <= 0.1 or shot_type == "practice":
		print("[Range] Practice swing or 0 ball speed ignored.")
		return
	FoamBallBoost.apply_boost(data)
	if has_node("Player"):
		$Player._on_tcp_client_hit_ball(data)
		
	raw_ball_data = data.duplicate()
	_update_ball_display(false)
	_on_shot_initiated()

	# Re-enable camera follow if the setting is on
	if GlobalSettings.range_settings.camera_follow_mode.value:
		call_deferred("set_camera_follow_mode", true)


func _on_launch_monitor_hit_ball(data: Dictionary) -> void:
	_on_tcp_client_hit_ball(data)


func _process(delta: float) -> void:
	# Live stats update during ball flight and rollout (~10 Hz on mobile, ~20 Hz on desktop)
	if has_node("Player") and $Player.ball != null and ($Player.get_ball_state() != PhysicsEnums.BallState.REST or _shot_active):
		_live_stats_timer += delta
		var stats_interval = 0.10 if MobilePerformance.is_mobile() else 0.05
		if _live_stats_timer >= stats_interval:
			_live_stats_timer = 0.0
			_update_ball_display(false)

	# Throttled green grid visibility check
	if show_green_grid:
		_green_grid_timer += delta
		if _green_grid_timer >= 0.2:
			_green_grid_timer = 0.0
			_update_green_grid_visibility()
	else:
		var grid_node = get_node_or_null("GreenGridMesh")
		if grid_node != null and grid_node.visible:
			_update_green_grid_visibility()

	# Continuous screen aiming when holding mouse on left/right half of screen in normal view
	if is_screen_aiming and not is_aerial_view and not _shot_active:
		_process_screen_aiming(delta)

	# Continuous keyboard aiming using arrow keys
	if not _shot_active:
		_process_keyboard_aiming(delta)
	
	# Check for shot zoom zone transition (Tee box vs Midway vs Green) only when dirty
	var ball_at_rest = not _shot_active
	if has_node("Player") and $Player.ball != null:
		ball_at_rest = ball_at_rest and ($Player.get_ball_state() == PhysicsEnums.BallState.REST)
	if ball_at_rest and _zoom_zone_dirty:
		_zoom_zone_dirty = false
		var current_zone = get_current_zoom_zone()
		if current_zone != _last_zoom_zone:
			aerial_zoom = get_zoom_for_zone(current_zone)
			if has_node("AerialCamera"):
				$AerialCamera.size = aerial_zoom
			_last_zoom_zone = current_zone
			_last_was_on_green = (current_zone == 2)

	# Putt & Chip camera suspense zoom & heartbeat tension (Course Play only)
	if has_node("/root/TensionManager") and TensionManager.is_course_play_active():
		if has_node("Player") and ($Player.get_ball_state() != PhysicsEnums.BallState.REST or _shot_active) and $Player.ball != null:
			var ball_node = $Player.ball
			var target_pos = current_hole_location
			
			if not target_pos.is_zero_approx():
				var is_sand = ball_node.is_in_sand or (ball_node.get("shot_was_in_sand") == true) or (ball_node.lie_type == "sand")
				var start_p = ball_node.spawn_position
				if ball_node.get("shot_start_pos_global") != null and not (ball_node.shot_start_pos_global as Vector3).is_zero_approx():
					start_p = ball_node.shot_start_pos_global
				elif ball_node.get("shot_start_pos") != null and not (ball_node.shot_start_pos as Vector3).is_zero_approx():
					start_p = ball_node.shot_start_pos
				
				if TensionManager.is_shot_eligible_for_suspense(start_p, target_pos, ball_node.is_putt, is_sand):
					var ball_pos_2d = Vector2(ball_node.global_position.x, ball_node.global_position.z)
					var hole_pos_2d = Vector2(target_pos.x, target_pos.z)
					var dist_to_target = ball_pos_2d.distance_to(hole_pos_2d)
					
					if ball_node.is_putt:
						_putt_close_view_triggered = TensionManager.is_active()
						if (_putt_close_view_triggered or TensionManager.is_active()) and has_node("PhantomCamera3D") and $PhantomCamera3D.follow_mode == PhantomCamera3D.FollowMode.SIMPLE:
							var target_offset = Vector3(-3.5, 0.8, 0).rotated(Vector3.UP, _last_travel_yaw)
							$PhantomCamera3D.follow_offset = $PhantomCamera3D.follow_offset.lerp(target_offset, delta * 4.0)
					else:
						_chip_close_view_triggered = TensionManager.is_active()
						if (_chip_close_view_triggered or TensionManager.is_active()) and has_node("PhantomCamera3D") and $PhantomCamera3D.follow_mode == PhantomCamera3D.FollowMode.SIMPLE:
							var target_offset = Vector3(-6.0, 1.4, 0).rotated(Vector3.UP, _last_travel_yaw)
							$PhantomCamera3D.follow_offset = $PhantomCamera3D.follow_offset.lerp(target_offset, delta * 4.0)
		
	if GlobalSettings.range_settings.dof_enabled.value:
		update_dof_focus()
		
	# Keep aerial camera centered, zoomed, and oriented between player and hole
	if is_aerial_view and has_node("AerialCamera") and $Player and $Player.ball:
		var ball_pos = $Player.ball.global_position
		var hole_pos = current_hole_location
		if hole_pos.is_zero_approx():
			hole_pos = Vector3(250.0, ball_pos.y, 0.0)
		var dir_3d = (hole_pos - ball_pos)
		dir_3d.y = 0
		if dir_3d.is_zero_approx():
			dir_3d = Vector3(0, 0, -1)
		else:
			dir_3d = dir_3d.normalized()
		
		$AerialCamera.size = aerial_zoom
		
		# Orientation: local up (Y column of basis) points from ball to hole, local -Z points straight down
		var right_vec = dir_3d.cross(Vector3.UP).normalized()
		var up_vec = dir_3d
		var back_vec = Vector3.UP
		$AerialCamera.global_transform.basis = Basis(right_vec, up_vec, back_vec)
		
		# Position: offset towards the hole by 0.35 * aerial_zoom so ball is on the south side
		var base_pos = ball_pos + dir_3d * (0.35 * aerial_zoom)
		$AerialCamera.global_position = Vector3(base_pos.x, 150.0, base_pos.z) + aerial_cam_user_offset

	# Draw/update the aim line connecting the player's ball to the aim marker
	if aim_line and $Player and $Player.ball:
		var has_minimap = not MultiplayerManager.players.is_empty()
		ball_at_rest = $Player.get_ball_state() == PhysicsEnums.BallState.REST
		var should_show_aim_line = is_aerial_view or (has_minimap and ball_at_rest)
		var imm: ImmediateMesh = aim_line.mesh
		# Draw the line when the map is active or when the minimap is active and ball is at rest
		if should_show_aim_line:
			var start_pt = $Player.ball.global_position + Vector3(0, 0.2, 0)
			var end_pt = aim_target_pos + Vector3(0, 0.2, 0)
			if not aim_line.visible or not start_pt.is_equal_approx(_last_aim_line_start) or not end_pt.is_equal_approx(_last_aim_line_end):
				_last_aim_line_start = start_pt
				_last_aim_line_end = end_pt
				aim_line.visible = true
				imm.clear_surfaces()
				imm.surface_begin(Mesh.PRIMITIVE_LINES)
				imm.surface_add_vertex(start_pt)
				imm.surface_add_vertex(end_pt)
				imm.surface_end()
		elif aim_line.visible:
			aim_line.visible = false
			imm.clear_surfaces()
			_last_aim_line_start = Vector3.INF
			_last_aim_line_end = Vector3.INF

	# Update player marker position and aim distance display dynamically
	if has_node("PlayerMarker") and $Player and $Player.ball:
		$PlayerMarker.global_position = $Player.ball.global_position
		
		var has_minimap = not MultiplayerManager.players.is_empty() or (has_node("/root/TensionManager") and TensionManager.is_course_play_active())
		$PlayerMarker.visible = is_aerial_view or has_minimap
		if has_node("AimMarker"):
			$AimMarker.visible = is_aerial_view or has_minimap
		if has_node("PinMarker"):
			$PinMarker.visible = is_aerial_view or has_minimap
		
		# Update distance to target only when at rest or in aerial view
		ball_at_rest = $Player.get_ball_state() == PhysicsEnums.BallState.REST
		if is_aerial_view or ball_at_rest:
			var dist_to_target = $Player.ball.global_position.distance_to(aim_target_pos) * 1.09361
			if has_node("MapCanvas/AimDistanceLabel"):
				set_aim_distance(round(dist_to_target))


var shot_history: Array[Dictionary] = []
var _shot_sequence_id: int = 0
var _shot_transition_active: bool = false

func is_shot_transition_active() -> bool:
	return _shot_transition_active

func cancel_pending_shot_transition() -> void:
	_shot_sequence_id += 1
	_shot_transition_active = false

func _on_golf_ball_rest(_ball_data) -> void:
	_shot_sequence_id += 1
	var this_shot_seq = _shot_sequence_id
	_shot_active = false
	_shot_transition_active = true
	_zoom_zone_dirty = true
	if has_node("/root/LaunchMonitorManager"):
		get_node("/root/LaunchMonitorManager").call("notify_ball_at_rest")
	is_screen_aiming = false
	screen_aim_direction = 0.0
	_putt_close_view_triggered = false
	_chip_close_view_triggered = false
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	raw_ball_data = _ball_data.duplicate()
	_update_ball_display(true)
	
	# Add valid shots to history to compute average stats
	if raw_ball_data.get("Speed", 0.0) > 0.0:
		if GlobalSettings.is_chipping_minigame:
			var final_pos = $Player.ball.global_position
			var target_pos = chipping_island_positions[selected_chipping_target_idx]
			var dist_to_target = Vector2(final_pos.x, final_pos.z).distance_to(Vector2(target_pos.x, target_pos.z))
			
			var is_hit = false
			if not $Player.ball.is_in_water and dist_to_target <= 3.81:
				is_hit = true
				chipping_stats[selected_chipping_target_idx]["Hits"] += 1
				GlobalSettings.play_golf_clap()
				_show_chipping_banner("GREEN HIT! Fantastic shot!")
			else:
				if $Player.ball.is_in_water:
					_show_chipping_banner("SPLASH! Landed in the water hazard.")
				else:
					_show_chipping_banner("Missed target. Distance: %.1f ft" % (dist_to_target * 3.28084))
					
			chipping_stats[selected_chipping_target_idx]["Attempts"] += 1
			_update_chipping_hud()
		
		var p_name = _get_current_player_name()
		var club_name = _get_current_club()
		raw_ball_data["player"] = p_name
		raw_ball_data["club"] = club_name
		shot_history.append(raw_ball_data.duplicate())
		
		# Only defer to MultiplayerManager.record_shot if in an active multiplayer course match with hole ids
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		var is_course_match = mp_mgr != null and not mp_mgr.players.is_empty() and not mp_mgr.hole_ids.is_empty() and not is_driving_range and not practice_mode_active
		if not is_course_match:
			var prev_longest_drive = -1.0
			if mp_mgr != null and not p_name.is_empty():
				prev_longest_drive = mp_mgr.get_player_longest_drive(p_name)
			_record_global_shot(p_name, club_name, raw_ball_data)
			if has_node("/root/AchievementManager") and not practice_mode_active:
				var total_yds = (raw_ball_data.get("TotalDistance", 0.0) as float) * 1.09361
				get_node("/root/AchievementManager").check_shot_achievements(p_name, club_name, total_yds, prev_longest_drive)
		_update_averages()

	# Announce shot
	var is_dynamic_course = not current_hole_location.is_zero_approx()
	var ball_pos: Vector3 = $Player.ball.global_position

	var ball = $Player.ball
	var landed_in_water = ball.is_in_water
	var landed_in_sand = ball.is_in_sand

	if ball.is_in_water:
		print("[range.gd] Ball landed in water hazard!")
		var recovery_pos: Vector3 = ball_pos
		var return_to_teebox: bool = ball.shot_was_from_teebox and not ball.shot_hit_other_ground

		if return_to_teebox:
			print("[range.gd] Water hazard directly from teebox without hitting other ground. Re-teeing from tee box!")
			if not ball.shot_start_pos_global.is_zero_approx():
				recovery_pos = ball.shot_start_pos_global
			elif $Player != null and not $Player._last_starting_pos.is_zero_approx():
				recovery_pos = $Player._last_starting_pos
			elif not practice_start_pos.is_zero_approx():
				recovery_pos = practice_start_pos

			ball.lie_type = "teebox"
			ball.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
			if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
				var mp_mgr = get_node("/root/MultiplayerManager")
				var active_player = mp_mgr.get_active_player()
				if active_player != null:
					active_player["lie_type"] = "teebox"
					active_player["position"] = recovery_pos
					active_player["last_starting_pos"] = recovery_pos
		else:
			# 1. Find closest point on water polygon boundary
			var found_drop_point = false
			var water_col = ball.water_collider
			var poly_points = []
			if water_col != null:
				if water_col.has_meta("water_points"):
					poly_points = water_col.get_meta("water_points")
				elif water_col.get_parent() != null and water_col.get_parent().has_meta("water_points"):
					poly_points = water_col.get_parent().get_meta("water_points")

			if poly_points.size() > 0:
				var ball_pos_2d = Vector2(ball_pos.x, ball_pos.z)
				var closest_pt_2d = get_closest_point_on_polygon(ball_pos_2d, poly_points)
				var away_dir = (closest_pt_2d - ball_pos_2d).normalized()
				if away_dir.is_zero_approx():
					if not ball.shot_start_pos_global.is_zero_approx():
						var start_2d = Vector2(ball.shot_start_pos_global.x, ball.shot_start_pos_global.z)
						away_dir = (start_2d - closest_pt_2d).normalized()
					if away_dir.is_zero_approx():
						var pin_pos_2d = Vector2(current_hole_location.x, current_hole_location.z)
						away_dir = (closest_pt_2d - pin_pos_2d).normalized()
					if away_dir.is_zero_approx():
						away_dir = Vector2.UP

				# Standard golf penalty relief: 2 club lengths (~2.5 meters / ~8.2 feet) away from hazard boundary
				var drop_dist = 2.5
				var rec_pos_2d = closest_pt_2d + away_dir * drop_dist

				# Ensure relief point is outside water polygon
				var packed_poly = PackedVector2Array(poly_points)
				if Geometry2D.is_point_in_polygon(rec_pos_2d, packed_poly):
					# Try reversing away_dir if initial vector pushed inward
					var alt_pos = closest_pt_2d - away_dir * drop_dist
					if not Geometry2D.is_point_in_polygon(alt_pos, packed_poly):
						rec_pos_2d = alt_pos
					elif not ball.shot_start_pos_global.is_zero_approx():
						var start_dir = (Vector2(ball.shot_start_pos_global.x, ball.shot_start_pos_global.z) - closest_pt_2d).normalized()
						var start_pos = closest_pt_2d + start_dir * drop_dist
						if not Geometry2D.is_point_in_polygon(start_pos, packed_poly):
							rec_pos_2d = start_pos

				var h = get_height(rec_pos_2d.x, rec_pos_2d.y)
				recovery_pos = Vector3(rec_pos_2d.x, h + GolfBall.GROUND_CENTER_HEIGHT + GolfBall.GROUND_SNAP_OFFSET, rec_pos_2d.y)
				found_drop_point = true
			if not found_drop_point:
				if not ball.shot_start_pos_global.is_zero_approx():
					recovery_pos = ball.shot_start_pos_global
				elif $Player != null and not $Player._last_starting_pos.is_zero_approx():
					recovery_pos = $Player._last_starting_pos
				elif not practice_start_pos.is_zero_approx():
					recovery_pos = practice_start_pos
			
			ball.lie_type = "rough"
			ball.set_surface(PhysicsEnums.SurfaceType.ROUGH)
			if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
				var mp_mgr = get_node("/root/MultiplayerManager")
				var active_player = mp_mgr.get_active_player()
				if active_player != null:
					active_player["lie_type"] = "rough"
					active_player["position"] = recovery_pos
					active_player["last_starting_pos"] = recovery_pos
		
		# 2. Update ball position and spawn position
		ball.global_position = recovery_pos
		if not practice_mode_active:
			ball.spawn_position = recovery_pos
		ball_pos = recovery_pos
		
		# 3. Add penalty stroke to active player
		if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
			var mp_mgr = get_node("/root/MultiplayerManager")
			var active_player = mp_mgr.get_active_player()
			if not mp_mgr.game_mode in ["Scramble", "2v2 Scramble"]:
				active_player["strokes"] += 1
				active_player["total_strokes"] += 1
				print("[range.gd] Water hazard penalty applied: +1 stroke to %s" % active_player["name"])
			else:
				print("[range.gd] Scramble water hazard: marked penalty on shot, team stroke deferred")
			active_player["last_shot_penalty"] = 1
		else:
			shot_count += 1
			print("[range.gd] Water hazard penalty applied: +1 shot count (now %d)" % shot_count)
	else:
		if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
			var mp_mgr = get_node("/root/MultiplayerManager")
			var active_player = mp_mgr.get_active_player()
			if active_player != null:
				active_player["last_shot_penalty"] = 0

	if is_dynamic_course and not practice_mode_active:
		$Player.ball.spawn_position = ball_pos

	update_current_lie_and_reduction()

	if has_node("/root/AnnouncerEngine") and not raw_ball_data.is_empty():
		var announcer = get_node("/root/AnnouncerEngine")
		var pin_dist := 999.0
		var target_pin = current_hole_location if is_dynamic_course else Vector3(150.0, ball_pos.y, 0.0)
		pin_dist = ball_pos.distance_to(target_pin) * 1.09361 # yards
		var hit_tree: bool = ball.hit_tree_this_shot if "hit_tree_this_shot" in ball else false
		announcer.call("EvaluateShot", raw_ball_data, $Player.ball.surface_type, pin_dist, landed_in_sand, landed_in_water, hit_tree)

	# Record multiplayer shot
	if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
		get_node("/root/MultiplayerManager").record_shot(ball_pos, raw_ball_data)

	if is_dynamic_course:
		if practice_mode_active:
			var saved_club = _get_current_club()
			var saved_target = aim_target_pos
			var saved_yaw = _last_aim_yaw_offset_deg
			
			if not _skip_requested:
				var reset_delay = GlobalSettings.range_settings.ball_reset_timer.value
				if reset_delay > 0.0:
					await get_tree().create_timer(reset_delay).timeout
				if this_shot_seq != _shot_sequence_id:
					_shot_transition_active = false
					return
			
			var active_modal = get_tree().root.find_child("SwingReplayModal", true, false)
			if active_modal != null and is_instance_valid(active_modal) and active_modal.is_inside_tree() and not active_modal.get("is_detached"):
				await active_modal.closed
				if this_shot_seq != _shot_sequence_id:
					_shot_transition_active = false
					return
			
			if GlobalSettings.range_settings.auto_ball_reset.value:
				_reset_display_data()
				if has_node("RangeUI"):
					$RangeUI.set_data(display_data)
			
			# Ensure ball position and spawn position are restored to practice_start_pos
			$Player.ball.spawn_position = practice_start_pos
			$Player.ball.global_position = practice_start_pos
			
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				var active_player = mp_mgr.get_active_player()
				if not active_player.is_empty():
					active_player["position"] = practice_start_pos
					active_player["last_aim_target_pos"] = saved_target
					active_player["last_aim_yaw_offset_deg"] = saved_yaw
			
			aim_target_pos = saved_target
			if has_node("AimMarker"):
				$AimMarker.global_position = aim_target_pos
			
			if GlobalSettings.range_settings.camera_follow_mode.value:
				$Player.ball.aim_yaw_offset_deg = saved_yaw
				await reset_camera_to_start()
			else:
				$Player.reset_ball()
				$Player.ball.aim_yaw_offset_deg = saved_yaw
			
			# Recalculate lie for the practice starting position
			update_current_lie_and_reduction()
			
			# Restore aim yaw, aim distance and camera look
			$Player.ball.aim_yaw_offset_deg = saved_yaw
			if has_node("MapCanvas/AimDistanceLabel"):
				set_aim_distance(int(practice_start_pos.distance_to(aim_target_pos) * 1.09361))
				
			var yaw_rad = deg_to_rad(saved_yaw)
			var is_on_green = is_ball_on_green()
			var cam_pos = get_address_camera_position(practice_start_pos, yaw_rad, is_on_green)
			var target_look = get_camera_target_look(aim_target_pos, practice_start_pos, is_on_green)
			if has_node("PhantomCamera3D"):
				$PhantomCamera3D.global_position = cam_pos
				$PhantomCamera3D.look_at(target_look)
			if has_node("Camera3D"):
				$Camera3D.global_position = cam_pos
				$Camera3D.look_at(target_look)
				
			# Retain the exact club used on the previous shot
			_user_custom_club = saved_club
			var club_sel = get_club_selector()
			if club_sel != null and club_sel.has_method("select_club_by_name"):
				_is_updating_auto_club = true
				club_sel.select_club_by_name(saved_club)
				_is_updating_auto_club = false
			
			_update_hole_info_label(true)
			if has_node("RangeUI"):
				$RangeUI.hide_skip_button()
				if $RangeUI.has_method("on_next_shot_started"):
					$RangeUI.on_next_shot_started()
			_skip_requested = false
			_shot_transition_active = false
			return
		else:
			# Wait for the ball reset delay so the player can watch the ball finish rolling
			if not _skip_requested:
				var reset_delay = GlobalSettings.range_settings.ball_reset_timer.value
				if reset_delay > 0.0:
					await get_tree().create_timer(reset_delay).timeout
				if this_shot_seq != _shot_sequence_id:
					_shot_transition_active = false
					return
			
			# Reset ball physics state and clear tracers
			$Player.reset_ball()
			
			var active_modal = get_tree().root.find_child("SwingReplayModal", true, false)
			if active_modal != null and is_instance_valid(active_modal) and active_modal.is_inside_tree() and not active_modal.get("is_detached"):
				await active_modal.closed
				if this_shot_seq != _shot_sequence_id:
					_shot_transition_active = false
					return

			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				if mp_mgr.last_gimme_strokes > 0:
					var gimme_extra_wait = maxf(0.0, 1.2 - GlobalSettings.range_settings.ball_reset_timer.value)
					if gimme_extra_wait > 0.0:
						await get_tree().create_timer(gimme_extra_wait).timeout
						if this_shot_seq != _shot_sequence_id:
							_shot_transition_active = false
							return
					mp_mgr.last_gimme_strokes = 0
				
				if has_node("RangeUI"):
					$RangeUI.hide_skip_button()
					if $RangeUI.has_method("on_next_shot_started"):
						$RangeUI.on_next_shot_started()
				_skip_requested = false
				
				mp_mgr.select_next_player()
				_shot_transition_active = false
				return

			# Update labels (single player fallback)
			_update_hole_info_label(true)
			
			# Automatically reset player's aim target to default aim (hole if reachable, else fairway center)
			set_camera_follow_mode(false)
			_user_custom_club = ""
			update_auto_club()
			apply_default_aim()
			
			print("[CoursePlay] Ball at rest. Spawn position updated. Ready for next shot.")
			
			if has_node("RangeUI"):
				$RangeUI.hide_skip_button()
				if $RangeUI.has_method("on_next_shot_started"):
					$RangeUI.on_next_shot_started()
			_skip_requested = false
			_shot_transition_active = false
			return


	# Return camera/ball to starting position for driving range
	var saved_club = _get_current_club()
	var saved_target = aim_target_pos
	var saved_yaw = _last_aim_yaw_offset_deg if _last_aim_yaw_offset_deg != 0.0 else ($Player.ball.aim_yaw_offset_deg if ($Player and $Player.ball) else 0.0)
	var saved_aim_is_manual = _aim_is_manual

	if not _skip_requested:
		var reset_delay = GlobalSettings.range_settings.ball_reset_timer.value
		if reset_delay > 0.0:
			await get_tree().create_timer(reset_delay).timeout
		if this_shot_seq != _shot_sequence_id:
			_shot_transition_active = false
			return
	
	var active_range_modal = get_tree().root.find_child("SwingReplayModal", true, false)
	if active_range_modal != null and is_instance_valid(active_range_modal) and active_range_modal.is_inside_tree() and not active_range_modal.get("is_detached"):
		await active_range_modal.closed
		if this_shot_seq != _shot_sequence_id:
			_shot_transition_active = false
			return
	
	if GlobalSettings.range_settings.auto_ball_reset.value:
		_reset_display_data()
		$RangeUI.set_data(display_data)
		
	aim_target_pos = saved_target
	_aim_is_manual = saved_aim_is_manual
	if has_node("AimMarker"):
		$AimMarker.global_position = aim_target_pos

	if GlobalSettings.range_settings.camera_follow_mode.value:
		$Player.ball.aim_yaw_offset_deg = saved_yaw
		await reset_camera_to_start()
	else:
		$Player.reset_ball()
		$Player.ball.aim_yaw_offset_deg = saved_yaw
		update_camera_offset()
		
	# Retain the exact club used on the previous shot
	_user_custom_club = saved_club
	var club_sel = get_club_selector()
	if club_sel != null and club_sel.has_method("select_club_by_name"):
		_is_updating_auto_club = true
		club_sel.select_club_by_name(saved_club)
		_is_updating_auto_club = false

	# Restore aim distance label
	if has_node("MapCanvas/AimDistanceLabel"):
		set_aim_distance(int($Player.ball.global_position.distance_to(aim_target_pos) * 1.09361))

	if has_node("RangeUI"):
		$RangeUI.hide_skip_button()
		if $RangeUI.has_method("on_next_shot_started"):
			$RangeUI.on_next_shot_started()
	_skip_requested = false
	_shot_transition_active = false
	return


func _update_averages(target_club: String = "") -> void:
	var p_name = _get_current_player_name()
	var club_name = target_club if not target_club.is_empty() else _get_current_club()
	
	var global_stats = _load_global_stats()
	var shots = []
	if global_stats.has(p_name) and global_stats[p_name].has(club_name):
		shots = global_stats[p_name][club_name]
		
	if shots.is_empty():
		if has_node("RangeUI"):
			$RangeUI.call("reset_average_stats")
		return
		
	var sum_carry := 0.0
	var sum_speed := 0.0
	var sum_spin := 0.0
	var sum_offline := 0.0
	var sum_target_diff := 0.0
	var valid_target_diff_count := 0
	
	for shot in shots:
		sum_carry += float(shot.get("CarryDistance", 0.0))
		sum_speed += float(shot.get("Speed", 0.0))
		sum_spin += float(shot.get("TotalSpin", 0.0))
		var s_dist = absf(float(shot.get("SideDistance", 0.0)))
		var t_dist = absf(float(shot.get("TotalDistance", shot.get("CarryDistance", 0.0))))
		if s_dist > 100.0 or (t_dist > 15.0 and s_dist > t_dist * 1.2):
			s_dist = 0.0
		sum_offline += s_dist
		
		var target_dist = float(shot.get("TargetDistance", 0.0))
		var total_dist = float(shot.get("TotalDistance", 0.0))
		if target_dist > 0.0:
			sum_target_diff += (total_dist - target_dist)
			valid_target_diff_count += 1
			
	var count = shots.size()
	var avg_data = {
		"Carry": sum_carry / count,
		"Speed": sum_speed / count,
		"Spin": sum_spin / count,
		"Offline": sum_offline / count,
		"TargetDiff": sum_target_diff / valid_target_diff_count if valid_target_diff_count > 0 else 0.0
	}
	
	if has_node("RangeUI"):
		$RangeUI.call("update_average_stats", avg_data)

	# No auto reset: leave final numbers visible

func set_camera_follow_mode(value) -> void:
	var camera = get_node_or_null("PhantomCamera3D")
	if camera == null:
		return

	if value and has_node("Player") and $Player.ball != null and _shot_active:
		camera.follow_mode = PhantomCamera3D.FollowMode.SIMPLE
		var player = $Player
		var target_node = player.get_camera_target() if player.has_method("get_camera_target") else player.ball
		camera.follow_target = target_node
		
		# Ensure PhantomCameraHost runs in IDLE mode (_process) to follow the interpolated target smoothly
		var pcam_host = get_node_or_null("Camera3D/PhantomCameraHost")
		if pcam_host != null:
			pcam_host.interpolation_mode = 1  # InterpolationMode.IDLE
		var cam_3d = get_node_or_null("Camera3D")
		if cam_3d != null:
			cam_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

		# Keep camera follow aligned with the player's aim angle down the fairway/range
		# Using aim_yaw_offset_deg prevents the follow camera from jumping sideways/off-center due to HLA
		var yaw_rad = deg_to_rad(player.ball.aim_yaw_offset_deg)
		_last_travel_yaw = yaw_rad
		
		# Rigid follow locked to physics ball (Godot built-in 3D physics interpolation handles camera and ball in unison)
		camera.follow_damping = false
		
		# Check if putting to determine camera configuration
		if player.ball.is_putt:
			update_camera_fov(GlobalSettings.range_settings.camera_fov.value)
			
			# Check if already within 5 feet (1.524m) of the hole
			var dist_to_hole = 999.0
			if not current_hole_location.is_zero_approx():
				var ball_pos_2d = Vector2(player.ball.global_position.x, player.ball.global_position.z)
				var hole_pos_2d = Vector2(current_hole_location.x, current_hole_location.z)
				dist_to_hole = ball_pos_2d.distance_to(hole_pos_2d)
			
			_putt_close_view_triggered = (dist_to_hole <= TensionManager.PUTT_THRESHOLD_METERS)
			var cam_dist = 3.5 if _putt_close_view_triggered else 5.0
			var cam_height = 0.8 if _putt_close_view_triggered else 1.2
			var local_offset = Vector3(-cam_dist, cam_height, 0).rotated(Vector3.UP, yaw_rad)
			camera.follow_offset = local_offset
		else:
			_putt_close_view_triggered = false
			# Standard FOV for ball flight view (follows user's camera FOV setting)
			update_camera_fov(GlobalSettings.range_settings.camera_fov.value)
			
			# Follow behind the ball looking basically straight at it while framing the course ahead
			var cam_dist = 10.0
			var cam_height = 1.4
			var local_offset = Vector3(-cam_dist, cam_height, 0).rotated(Vector3.UP, yaw_rad)
			camera.follow_offset = local_offset
		
		# Rotate camera to look directly at the ball with slight elevation for better course framing
		camera.look_at_mode = PhantomCamera3D.LookAtMode.SIMPLE
		camera.look_at_target = target_node
		camera.look_at_offset = Vector3(0.0, 0.25, 0.0)
		camera.look_at_damping = false
	else:
		_putt_close_view_triggered = false
		_chip_close_view_triggered = false
		if has_node("/root/TensionManager"):
			TensionManager.stop_tension()
		camera.follow_mode = PhantomCamera3D.FollowMode.NONE
		camera.look_at_mode = PhantomCamera3D.LookAtMode.NONE
		camera.look_at_offset = Vector3.ZERO
		camera.look_at_damping = false
		update_camera_fov(GlobalSettings.range_settings.camera_fov.value)

func reset_camera_to_start() -> void:
	_shot_active = false
	_putt_close_view_triggered = false
	_chip_close_view_triggered = false
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	var camera = $PhantomCamera3D

	# Disable follow mode and restore default view settings/FOV
	set_camera_follow_mode(false)

	# Calculate offset behind the ball in the direction we are aiming
	var saved_yaw = $Player.ball.aim_yaw_offset_deg
	var yaw_rad = deg_to_rad(saved_yaw)
	var is_on_green = is_ball_on_green()
	var start_pos = get_address_camera_position($Player.ball.spawn_position, yaw_rad, is_on_green)
	var target_look = get_camera_target_look(aim_target_pos, $Player.ball.spawn_position, is_on_green)

	if _skip_requested:
		camera.global_position = start_pos
		camera.look_at_from_position(start_pos, target_look)
		if has_node("Camera3D"):
			$Camera3D.global_position = start_pos
			$Camera3D.look_at(target_look)
	else:
		# Tween camera back to starting position
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(camera, "global_position", start_pos, 1.5)

		# Rotate camera to face the aim target
		camera.look_at_from_position(start_pos, target_look)
		if has_node("Camera3D"):
			$Camera3D.global_position = start_pos
			$Camera3D.look_at(target_look)

		await tween.finished

	# Reset ball to starting position
	var player = $Player
	if player != null:
		player.reset_ball()
		player.ball.aim_yaw_offset_deg = saved_yaw


func _on_skip_flight_requested() -> void:
	_skip_requested = true
	if has_node("Player"):
		$Player.skip_to_rest()



func _on_range_ui_hit_shot(data: Dictionary) -> void:
	if has_node("Player"):
		$Player._on_range_ui_hit_shot(data)
		
	# For local injected shots, prime the display immediately with the static payload data.
	raw_ball_data = data.duplicate()
	_update_ball_display(false)
	_on_shot_initiated()

	# Re-enable camera follow if the setting is on
	if GlobalSettings.range_settings.camera_follow_mode.value:
		call_deferred("set_camera_follow_mode", true)


func _on_player_manual_hit() -> void:
	if has_node("Player"):
		raw_ball_data = $Player.shot_data.duplicate()
	_update_ball_display(false)
	_on_shot_initiated()
	# Re-enable camera follow if the setting is on
	if GlobalSettings.range_settings.camera_follow_mode.value:
		call_deferred("set_camera_follow_mode", true)



func _reset_display_data() -> void:
	raw_ball_data.clear()
	last_display.clear()
	display_data["Distance"] = "---"
	display_data["Carry"] = "---"
	display_data["Offline"] = "---"
	display_data["Apex"] = "---"
	display_data["VLA"] = "---"
	display_data["HLA"] = "---"
	display_data["Speed"] = "---"
	display_data["BackSpin"] = "---"
	display_data["SideSpin"] = "---"
	display_data["TotalSpin"] = "---"
	display_data["SpinAxis"] = "---"


func _update_ball_display(is_final_rest: bool = true) -> void:
	var player = $Player
	display_data = ShotFormatter.format_ball_display(raw_ball_data, player, GlobalSettings.range_settings.range_units.value, is_final_rest, display_data)
	last_display = display_data.duplicate()
	$RangeUI.set_data(display_data, is_final_rest)


func set_practice_mode(enabled: bool) -> void:
	practice_mode_active = enabled
	practice_start_pos = $Player.ball.position


func _on_range_ui_reset_practice_clicked() -> void:
	$Player.ball.spawn_position = practice_start_pos
	$Player.ball.global_position = practice_start_pos
	$Player.ball.reset()
	reset_zoom_to_default()
	update_current_lie_and_reduction()
	_update_hole_info_label(true)
	if has_node("RangeUI") and $RangeUI.has_method("on_next_shot_started"):
		$RangeUI.on_next_shot_started()


func load_practice_hole(idx: int) -> void:
	if course_data_dict.is_empty():
		return
	var hole_info_data = course_data_dict.get("Hole Info", {})
	var hole_keys = hole_info_data.keys()
	hole_keys.sort()
	if hole_keys.is_empty():
		return
	
	# Clamp or wrap index
	if idx < 0:
		idx = hole_keys.size() - 1
	elif idx >= hole_keys.size():
		idx = 0
	current_practice_hole_index = idx
	
	var hole_key = hole_keys[idx]
	var hole_data = hole_info_data[hole_key]
	
	var tee_boxes = hole_data.get("Tee Boxes", {})
	var tee_pos = tee_boxes.get("Blue")
	if tee_pos == null:
		for k in tee_boxes.keys():
			tee_pos = tee_boxes[k]
			break
			
	if tee_pos != null:
		var spawn_pos = Vector3(tee_pos[0], get_height(tee_pos[0], tee_pos[1]) + 0.059435, tee_pos[1])
		practice_start_pos = spawn_pos
		if has_node("Player") and $Player.ball != null:
			$Player.ball.spawn_position = spawn_pos
			$Player.ball.global_position = spawn_pos
			$Player.reset_ball()
			
		var hole_loc = hole_data.get("Hole Location")
		var par = hole_data.get("Par", 4)
		var hole_name = hole_data.get("Name", hole_key)
		
		current_hole_name = hole_name
		current_hole_par = par
		shot_count = 0
		_user_custom_club = ""
		_aim_is_manual = false
		reset_zoom_to_default()
		update_current_lie_and_reduction()
		
		if hole_loc != null:
			current_hole_location = Vector3(hole_loc[0], get_height(hole_loc[0], hole_loc[1]), hole_loc[1])
			
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				mp_mgr.current_hole_index = idx
				var active_player = mp_mgr.get_active_player()
				if not active_player.is_empty():
					active_player["position"] = spawn_pos
					active_player["strokes"] = 0
					active_player["shot_history"].clear()
					mp_mgr.emit_signal("active_player_changed", active_player)

			current_hole_tee_dist_yards = int(spawn_pos.distance_to(current_hole_location) * 1.09361)
			_update_hole_info_label(true)
			update_auto_club()
			apply_default_aim()
			_spawn_flag_pin()
			update_hole_outline()
			
		print("[PracticeMode] Loaded hole ", idx, " (", hole_name, ")")


func next_practice_hole() -> void:
	if GlobalSettings.is_chipping_minigame:
		return
	load_practice_hole(current_practice_hole_index + 1)


func prev_practice_hole() -> void:
	if GlobalSettings.is_chipping_minigame:
		return
	load_practice_hole(current_practice_hole_index - 1)


func _on_map_button_pressed() -> void:
	is_aerial_view = !is_aerial_view
	is_screen_aiming = false
	screen_aim_direction = 0.0
	_touch_points.clear()
	_last_pinch_distance = -1.0
	is_mouse_down_on_map = false
	is_dragging_map = false
	
	if has_node("MapCanvas"):
		$MapCanvas.visible = true
		if $MapCanvas.has_node("AerialZoomVBox"):
			$MapCanvas/AerialZoomVBox.visible = is_aerial_view
		if $MapCanvas.has_node("HoleInfoLabel"):
			var is_course_play = false
			if has_node("/root/MultiplayerManager"):
				var mp = get_node("/root/MultiplayerManager")
				if not mp.players.is_empty():
					is_course_play = true
			$MapCanvas/HoleInfoLabel.visible = is_aerial_view and not is_course_play
	
	# Update map button text and practice UI visibility in children and current scene
	for child in get_children():
		if child.has_method("update_map_button_text"):
			child.call("update_map_button_text", is_aerial_view)
		if child.has_method("update_practice_ui_visibility"):
			child.call("update_practice_ui_visibility", is_aerial_view)
			
	var current_scene = get_tree().current_scene
	if current_scene != null:
		for child in current_scene.get_children():
			if child.has_method("update_map_button_text"):
				child.call("update_map_button_text", is_aerial_view)
			if child.has_method("update_practice_ui_visibility"):
				child.call("update_practice_ui_visibility", is_aerial_view)
		
	# Toggle markers and distance label visibility
	var has_minimap = not MultiplayerManager.players.is_empty() or (has_node("/root/TensionManager") and TensionManager.is_course_play_active())
	if has_node("PlayerMarker"):
		$PlayerMarker.visible = is_aerial_view or has_minimap
	if has_node("AimMarker"):
		$AimMarker.visible = is_aerial_view or has_minimap
	if aim_line != null:
		var ball_at_rest = $Player and $Player.get_ball_state() == PhysicsEnums.BallState.REST
		aim_line.visible = is_aerial_view or (has_minimap and ball_at_rest)
	if has_node("MapCanvas/AimDistanceLabel"):
		$MapCanvas/AimDistanceLabel.visible = true
	if has_node("PinMarker"):
		$PinMarker.visible = is_aerial_view or has_minimap

	if is_aerial_view:
		# Reset camera user drag offset
		aerial_cam_user_offset = Vector3.ZERO
		var current_zone = get_current_zoom_zone()
		aerial_zoom = get_zoom_for_zone(current_zone)
		_last_zoom_zone = current_zone
		_last_was_on_green = (current_zone == 2)
		
		# Position aerial camera high above the ball and align it immediately
		if has_node("AerialCamera") and $Player and $Player.ball:
			var ball_pos = $Player.ball.global_position
			var hole_pos = current_hole_location
			if hole_pos.is_zero_approx():
				hole_pos = Vector3(250.0, ball_pos.y, 0.0)
			var dir_3d = (hole_pos - ball_pos)
			dir_3d.y = 0
			if dir_3d.is_zero_approx():
				dir_3d = Vector3(0, 0, -1)
			else:
				dir_3d = dir_3d.normalized()
			
			$AerialCamera.size = aerial_zoom
			
			# Orientation
			var right_vec = dir_3d.cross(Vector3.UP).normalized()
			var up_vec = dir_3d
			var back_vec = Vector3.UP
			$AerialCamera.global_transform.basis = Basis(right_vec, up_vec, back_vec)
			
			# Position
			var base_pos = ball_pos + dir_3d * (0.35 * aerial_zoom)
			$AerialCamera.global_position = Vector3(base_pos.x, 150.0, base_pos.z)
			$AerialCamera.make_current()
			
		update_hole_outline()
		print("[Map] Switched to Aerial View")
	else:
		# Switch back to the main camera
		if has_node("Camera3D"):
			$Camera3D.make_current()
		update_hole_outline()
		update_camera_offset()
		print("[Map] Switched to Player View")


func _spawn_flag_pin() -> void:
	if current_hole_location.is_zero_approx():
		return
		
	if has_node("PinMarker"):
		get_node("PinMarker").queue_free()
	if has_node("FlagPin"):
		get_node("FlagPin").queue_free()
		
	# Create Pin Marker for aerial map view (glowing orange/yellow cylinder)
	var pin_marker = MeshInstance3D.new()
	pin_marker.name = "PinMarker"
	var pin_cyl = CylinderMesh.new()
	pin_cyl.top_radius = 0.4
	pin_cyl.bottom_radius = 0.4
	pin_cyl.height = 12.0
	pin_marker.mesh = pin_cyl
	var pin_mat = StandardMaterial3D.new()
	pin_mat.albedo_color = Color(1.0, 0.6, 0.1) # Neon Orange
	pin_mat.emission_enabled = true
	pin_mat.emission = Color(1.0, 0.6, 0.1)
	pin_marker.material_override = pin_mat
	pin_marker.layers = 2
	
	# Add static 2D billboard golf flag sprite to pin marker for map/aerial view
	var pin_sprite = Sprite3D.new()
	pin_sprite.name = "MapFlagSprite"
	pin_sprite.layers = 2
	pin_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	pin_sprite.no_depth_test = true
	pin_sprite.double_sided = true
	pin_sprite.pixel_size = 0.04
	pin_sprite.position = Vector3(0, 6.0, 0)
	if ResourceLoader.exists("res://assets/images/icons/golf_pin_flag.svg"):
		pin_sprite.texture = load("res://assets/images/icons/golf_pin_flag.svg")
	pin_marker.add_child(pin_sprite)

	add_child(pin_marker)
	pin_marker.global_position = current_hole_location
	var has_minimap = not MultiplayerManager.players.is_empty() or (has_node("/root/TensionManager") and TensionManager.is_course_play_active())
	pin_marker.visible = is_aerial_view or has_minimap
	
	# Create 3D flag pin at hole location (visible in 3D game view)
	var pin = Node3D.new()
	pin.name = "FlagPin"
	add_child(pin)
	pin.global_position = current_hole_location
	
	# Flagpole: thin cylinder
	var pole = MeshInstance3D.new()
	pole.name = "Pole"
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.03
	pole_mesh.bottom_radius = 0.03
	pole_mesh.height = 3.0
	pole.mesh = pole_mesh
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color.WHITE
	pole.material_override = pole_mat
	pole.position = Vector3(0, 1.5, 0)
	pin.add_child(pole)
	
	# Flag: small red prism/box mesh
	var flag = MeshInstance3D.new()
	flag.name = "Flag"
	var flag_mesh = PrismMesh.new()
	flag_mesh.size = Vector3(0.5, 0.4, 0.02)
	flag.mesh = flag_mesh
	var flag_mat = StandardMaterial3D.new()
	flag_mat.albedo_color = Color(1.0, 0.1, 0.1) # Bright red
	flag_mat.emission_enabled = true
	flag_mat.emission = Color(1.0, 0.1, 0.1)
	flag.material_override = flag_mat
	flag.position = Vector3(0.25, 2.8, 0)
	flag.rotation = Vector3(0, 0, -PI/2)
	pin.add_child(flag)
	
	# Cup / hole circle on ground: realistic golf cup (white cup liner/rim with dark interior)
	var cup_white = MeshInstance3D.new()
	cup_white.name = "CupWhite"
	var white_mesh = CylinderMesh.new()
	white_mesh.top_radius = cup_radius
	white_mesh.bottom_radius = cup_radius
	white_mesh.height = 0.003
	cup_white.mesh = white_mesh
	var white_mat = StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.95, 0.95, 0.95)
	white_mat.roughness = 0.5
	cup_white.material_override = white_mat
	cup_white.position = Vector3(0, 0.0012, 0)
	pin.add_child(cup_white)

	var cup = MeshInstance3D.new()
	cup.name = "Cup"
	var cup_mesh = CylinderMesh.new()
	cup_mesh.top_radius = 0.095
	cup_mesh.bottom_radius = 0.095
	cup_mesh.height = 0.0035
	cup.mesh = cup_mesh
	var cup_mat = StandardMaterial3D.new()
	cup_mat.albedo_color = Color(0.12, 0.12, 0.12)
	cup_mat.roughness = 1.0
	cup.material_override = cup_mat
	cup.position = Vector3(0, 0.0016, 0)
	pin.add_child(cup)
	
	print("[CoursePlay] FlagPin and PinMarker spawned at: ", current_hole_location)
	update_gimme_circles()


func _on_shot_initiated() -> void:
	_skip_requested = false
	_shot_active = true
	_shot_transition_active = false
	_zoom_zone_dirty = true
	if has_node("/root/LaunchMonitorManager"):
		get_node("/root/LaunchMonitorManager").call("notify_shot_started")
	is_screen_aiming = false
	screen_aim_direction = 0.0
	_last_aim_target_pos = aim_target_pos
	_last_aim_yaw_offset_deg = $Player.ball.aim_yaw_offset_deg if ($Player and $Player.ball) else 0.0
	_putt_close_view_triggered = false
	_chip_close_view_triggered = false
	if has_node("/root/TensionManager"):
		TensionManager.reset_for_new_shot()

	if has_node("RangeUI"):
		$RangeUI.show_skip_button()
		if $RangeUI.has_method("on_ball_hit"):
			$RangeUI.on_ball_hit()

	# Early Trajectory Prediction for Suspense (Course Play only)
	if has_node("/root/TensionManager") and TensionManager.is_course_play_active() and not current_hole_location.is_zero_approx() and has_node("Player") and $Player.ball != null:
		var ball_node = $Player.ball
		var is_putt = ball_node.is_putt
		var is_sand = ball_node.is_in_sand or (ball_node.get("shot_was_in_sand") == true) or (ball_node.lie_type == "sand")
		var start_p = ball_node.global_position
		if TensionManager.is_shot_eligible_for_suspense(start_p, current_hole_location, is_putt, is_sand):
			var prediction = TensionManager.predict_shot_outcome(start_p, ball_node.velocity, is_putt, current_hole_location, is_sand)
			if prediction.get("will_enter_zone", false):
				var ending_dist = prediction.get("ending_dist", prediction.get("min_dist", 0.0))
				var delay_to_apex = prediction.get("delay_to_apex", 0.25)
				print("[TensionManager] Early suspense predicted for Course Play shot! Mode: %s, Delay to apex: %.2fs, Ending Dist: %.2fm. Scheduling heartbeat." % [
					prediction.get("mode", "putt"), delay_to_apex, ending_dist
				])
				TensionManager.schedule_apex_tension(prediction.get("mode", "putt"), delay_to_apex, ending_dist)

	if current_hole_location.is_zero_approx():
		return
	shot_count += 1
	print("[CoursePlay] Shot initiated. Count: ", shot_count)
	_update_hole_info_label(false)


func _update_hole_info_label(ball_is_at_rest: bool) -> void:
	if current_hole_location.is_zero_approx():
		return
	if not has_node("MapCanvas/HoleInfoLabel"):
		return
		
	var on_green = is_ball_on_green()
	if not on_green and has_node("Player") and $Player.ball != null:
		var ball_lie = str($Player.ball.get("lie_type")).to_lower()
		var p_lie = str($Player.get("current_lie_type")).to_lower()
		if ball_lie == "green" or p_lie == "green":
			on_green = true
	if not on_green and has_node("/root/MultiplayerManager"):
		var mp = get_node("/root/MultiplayerManager")
		if not mp.players.is_empty():
			var ap = mp.get_active_player()
			if ap.get("lie_type", "").to_lower() == "green":
				on_green = true

	var dist_m = 0.0
	if ball_is_at_rest:
		dist_m = $Player.ball.global_position.distance_to(current_hole_location)
	else:
		dist_m = $Player.ball.spawn_position.distance_to(current_hole_location)
		
	if on_green:
		var dist_feet = int(round(dist_m * 3.28084))
		$MapCanvas/HoleInfoLabel.text = "%s | Par %d | %d Yards | Shots: %d | Ball: %d Feet to Pin" % [
			current_hole_name, current_hole_par, current_hole_tee_dist_yards, shot_count, dist_feet
		]
	else:
		var dist_yards = int(dist_m * 1.09361)
		$MapCanvas/HoleInfoLabel.text = "%s | Par %d | %d Yards | Shots: %d | Ball: %d Yards to Pin" % [
			current_hole_name, current_hole_par, current_hole_tee_dist_yards, shot_count, dist_yards
		]
	update_auto_club()


func update_hole_outline() -> void:
	if not has_node("HoleOutline") or not has_node("MinimapHoleOutline"):
		return
		
	var outline_node = $HoleOutline
	var minimap_outline_node = $MinimapHoleOutline
	var imm: ImmediateMesh = outline_node.mesh
	var m_imm: ImmediateMesh = minimap_outline_node.mesh
	imm.clear_surfaces()
	m_imm.clear_surfaces()
	
	var has_minimap = not MultiplayerManager.players.is_empty() or (has_node("/root/TensionManager") and TensionManager.is_course_play_active())
	
	# Determine visibilities
	outline_node.visible = is_aerial_view
	minimap_outline_node.visible = not is_aerial_view and has_minimap
	
	if not (outline_node.visible or minimap_outline_node.visible):
		return
		
	# Determine the path
	var path_pts: Array[Vector3] = []
	
	# Get the current hole info from config (if loaded)
	var has_path := false
	var active_hole = get_active_hole_config()
	if not active_hole.is_empty():
		var path_arr = active_hole.get("Hole Path")
		if path_arr != null and path_arr.size() > 0:
			has_path = true
			for pt in path_arr:
				path_pts.append(Vector3(pt[0], get_height(pt[0], pt[1]), pt[1]))
				
	# Fallback if no path is configured
	if not has_path:
		# Use player's starting/ball spawn position and current_hole_location
		var start_pt = $Player.ball.spawn_position if ($Player and $Player.ball) else Vector3.ZERO
		var tee_pos = start_pt
		if not active_hole.is_empty():
			var tee_boxes = active_hole.get("Tee Boxes", {})
			var active_player = null
			if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
				active_player = MultiplayerManager.get_active_player()
				
			var tee_color = active_player.get("tee", "Blue") if active_player != null else "Blue"
			var tee_coord = tee_boxes.get(tee_color)
			if tee_coord != null:
				tee_pos = Vector3(tee_coord[0], get_height(tee_coord[0], tee_coord[1]), tee_coord[1])
				
		path_pts.append(tee_pos)
		var hole_pos = current_hole_location
		if hole_pos.is_zero_approx():
			hole_pos = Vector3(450.0, tee_pos.y, 0.0)
		path_pts.append(hole_pos)
		
	# Generate geometry for outline (regular thickness for map view)
	var outer_vertices = get_path_buffer_polygon(path_pts, 25.0)
	var inner_vertices = get_path_buffer_polygon(path_pts, 23.5)
	
	if outer_vertices.size() > 1 and inner_vertices.size() == outer_vertices.size():
		imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(outer_vertices.size() - 1):
			var o1 = outer_vertices[j]
			var i1 = inner_vertices[j]
			var o2 = outer_vertices[j+1]
			var i2 = inner_vertices[j+1]
			
			# Triangle 1
			imm.surface_add_vertex(o1)
			imm.surface_add_vertex(i1)
			imm.surface_add_vertex(o2)
			
			# Triangle 2
			imm.surface_add_vertex(i1)
			imm.surface_add_vertex(i2)
			imm.surface_add_vertex(o2)
		imm.surface_end()
		
	# Generate geometry for minimap outline (thicker)
	var m_outer_vertices = get_path_buffer_polygon(path_pts, 27.5)
	var m_inner_vertices = get_path_buffer_polygon(path_pts, 22.5)
	
	if m_outer_vertices.size() > 1 and m_inner_vertices.size() == m_outer_vertices.size():
		m_imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(m_outer_vertices.size() - 1):
			var o1 = m_outer_vertices[j]
			var i1 = m_inner_vertices[j]
			var o2 = m_outer_vertices[j+1]
			var i2 = m_inner_vertices[j+1]
			
			# Triangle 1
			m_imm.surface_add_vertex(o1)
			m_imm.surface_add_vertex(i1)
			m_imm.surface_add_vertex(o2)
			
			# Triangle 2
			m_imm.surface_add_vertex(i1)
			m_imm.surface_add_vertex(i2)
			m_imm.surface_add_vertex(o2)
		m_imm.surface_end()


func get_path_buffer_polygon(path_list: Array, radius: float) -> Array[Vector3]:
	if path_list.size() < 2:
		return []
		
	var left_side: Array[Vector3] = []
	var right_side: Array[Vector3] = []
	
	for i in range(path_list.size()):
		var pt = path_list[i]
		var p_xz = Vector2(pt.x, pt.z)
		
		# Compute direction vector at this point
		var dir := Vector2.ZERO
		if i == 0:
			var next_xz = Vector2(path_list[i+1].x, path_list[i+1].z)
			dir = (next_xz - p_xz).normalized()
		elif i == path_list.size() - 1:
			var prev_xz = Vector2(path_list[i-1].x, path_list[i-1].z)
			dir = (p_xz - prev_xz).normalized()
		else:
			var prev_xz = Vector2(path_list[i-1].x, path_list[i-1].z)
			var next_xz = Vector2(path_list[i+1].x, path_list[i+1].z)
			var dir1 = (p_xz - prev_xz).normalized()
			var dir2 = (next_xz - p_xz).normalized()
			dir = (dir1 + dir2).normalized()
			
		# Normal vector (rotate dir by 90 degrees counter-clockwise)
		var normal = Vector2(-dir.y, dir.x)
		
		# Generate left and right offset points
		var left_xz = p_xz + normal * radius
		var right_xz = p_xz - normal * radius
		
		# Get height
		var left_y = get_height(left_xz.x, left_xz.y) + 0.3
		var right_y = get_height(right_xz.x, right_xz.y) + 0.3
		
		left_side.append(Vector3(left_xz.x, left_y, left_xz.y))
		right_side.append(Vector3(right_xz.x, right_y, right_xz.y))
		
	# Combine into a single closed loop polygon
	var loop: Array[Vector3] = []
	loop.append_array(left_side)
	
	# Reverse right_side so the loop goes back smoothly
	right_side.reverse()
	loop.append_array(right_side)
	
	# Close the loop
	loop.append(left_side[0])
	
	return loop


func get_all_holes_config() -> Dictionary:
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.hole_info.is_empty():
		return mp_mgr.hole_info
	if not course_data_dict.is_empty() and course_data_dict.has("Hole Info"):
		return course_data_dict["Hole Info"]
	return {}


func get_active_hole_config() -> Dictionary:
	var all_holes = get_all_holes_config()
	if all_holes.is_empty():
		return {}

	# 1. Match by current_hole_location proximity (most reliable across all game modes)
	if not current_hole_location.is_zero_approx():
		var cur_2d = Vector2(current_hole_location.x, current_hole_location.z)
		var best_key = ""
		var best_dist := 10.0 # within 10 meters of pin
		for k in all_holes.keys():
			var h = all_holes[k]
			var h_loc = h.get("Hole Location")
			if h_loc != null and typeof(h_loc) == TYPE_ARRAY and h_loc.size() >= 2:
				var pin_2d = Vector2(float(h_loc[0]), float(h_loc[1]))
				var d = cur_2d.distance_to(pin_2d)
				if d < best_dist:
					best_dist = d
					best_key = k
		if best_key != "":
			return all_holes[best_key]

	# 2. Match by current_hole_name
	if current_hole_name != "":
		if all_holes.has(current_hole_name):
			return all_holes[current_hole_name]
		for k in all_holes.keys():
			if all_holes[k].get("Name", "") == current_hole_name:
				return all_holes[k]

	# 3. Match by MultiplayerManager.current_hole_index
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.hole_ids.is_empty():
		var hole_idx = clamp(mp_mgr.current_hole_index, 0, mp_mgr.hole_ids.size() - 1)
		var hole_id = mp_mgr.hole_ids[hole_idx]
		if all_holes.has(hole_id):
			return all_holes[hole_id]

	# 4. Match by current_practice_hole_index
	var hole_keys = all_holes.keys()
	hole_keys.sort()
	if current_practice_hole_index >= 0 and current_practice_hole_index < hole_keys.size():
		return all_holes[hole_keys[current_practice_hole_index]]

	return all_holes[hole_keys[0]]


func toggle_sky_view() -> void:
	is_sky_view_active = !is_sky_view_active
	update_camera_offset()
	if is_sky_view_active:
		update_camera_fov(30.0)
	else:
		update_camera_fov(GlobalSettings.range_settings.camera_fov.value)


func is_ball_on_green() -> bool:
	if has_node("Player") and $Player.ball != null:
		var ball = $Player.ball
		var lie = str(ball.get("lie_type")).to_lower()
		var p_lie = str($Player.get("current_lie_type")).to_lower()
		
		# If explicitly on teebox or in sand, definitely not on green
		if lie == "teebox" or p_lie == "teebox" or lie == "sand" or p_lie == "sand" or ball.is_in_sand:
			return false
			
		if lie == "green" or p_lie == "green":
			return true
			
		if has_node("/root/MultiplayerManager"):
			var mp = get_node("/root/MultiplayerManager")
			if not mp.players.is_empty():
				var ap = mp.get_active_player()
				if ap.get("lie_type", "").to_lower() == "green":
					return true

		# Geometric check is ground truth if course mesh is present
		if has_method("get_distance_to_nearest_green"):
			var d_green = get_distance_to_nearest_green(ball.global_position)
			if d_green <= 0.001:
				return true
	return false


func is_ball_on_fringe() -> bool:
	if has_node("Player") and $Player.ball != null:
		var ball = $Player.ball
		var lie = str(ball.get("lie_type")).to_lower()
		var p_lie = str($Player.get("current_lie_type")).to_lower()
		if lie == "teebox" or p_lie == "teebox" or lie == "sand" or p_lie == "sand" or ball.is_in_sand:
			return false
		if lie == "fringe" or p_lie == "fringe":
			return true
		if has_node("/root/MultiplayerManager"):
			var mp = get_node("/root/MultiplayerManager")
			if not mp.players.is_empty():
				var ap = mp.get_active_player()
				if ap.get("lie_type", "").to_lower() == "fringe":
					return true
		if has_method("get_distance_to_nearest_green"):
			var d_green: float = get_distance_to_nearest_green(ball.global_position)
			return (d_green > 0.001 and d_green <= 2.5)
	return false


func get_camera_target_look(target_pos: Vector3, origin_pos: Vector3, is_on_green: bool = false) -> Vector3:
	var is_putting = is_on_green or is_ball_on_fringe() or (_get_current_club().to_lower() in ["pt", "putt", "putter"])
	if is_putting:
		if not target_pos.is_zero_approx():
			var dist = origin_pos.distance_to(target_pos)
			if dist > 0.01:
				var look_dist = clamp(dist * 0.4, 2.0, 6.0)
				if dist < 2.0:
					look_dist = dist
				var fraction = clamp(look_dist / dist, 0.0, 1.0)
				return origin_pos.lerp(target_pos, fraction)
			return (target_pos + origin_pos) * 0.5
		else:
			var aim_dir = Vector3.RIGHT
			if has_node("Player") and $Player.ball != null:
				var yaw_rad = deg_to_rad($Player.ball.aim_yaw_offset_deg)
				aim_dir = Vector3.RIGHT.rotated(Vector3.UP, yaw_rad)
			return origin_pos + aim_dir * 3.5

	var dist = origin_pos.distance_to(target_pos) if not target_pos.is_zero_approx() else 50.0
	var aim_dir = (target_pos - origin_pos).normalized() if not target_pos.is_zero_approx() else Vector3.ZERO
	if aim_dir.is_zero_approx():
		aim_dir = Vector3.RIGHT
		if has_node("Player") and $Player.ball != null:
			var yaw_rad = deg_to_rad($Player.ball.aim_yaw_offset_deg)
			aim_dir = Vector3.RIGHT.rotated(Vector3.UP, yaw_rad)

	# Smoothly calculate target look point:
	# For full shots and approach shots, look at comfortable eye level (+1.0m above terrain).
	# For short shots (< 50m), look directly toward target position (+1.0m eye-level).
	# For longer shots (>= 50m), look down the aim direction towards 50m with appropriate eye-level elevation.
	var look_dist = clampf(dist, 10.0, 50.0)
	var t = clampf(look_dist / maxf(dist, 0.001), 0.0, 1.0)
	var base_look_pos = origin_pos.lerp(target_pos, t) if not target_pos.is_zero_approx() else (origin_pos + aim_dir * 50.0)
	return base_look_pos + Vector3.UP * 1.0


func get_camera_local_offset(override_is_on_green: Variant = null) -> Vector3:
	var is_on_green = false
	if override_is_on_green != null:
		is_on_green = bool(override_is_on_green)
	else:
		is_on_green = is_ball_on_green() or is_ball_on_fringe() or (_get_current_club().to_lower() in ["pt", "putt", "putter"])
		
	if is_on_green:
		return Vector3(-1.05, 0.6, 0)
		
	var cam_dist = 50.0 if is_sky_view_active else GlobalSettings.range_settings.camera_distance.value
	var cam_height = 15.0 if is_sky_view_active else GlobalSettings.range_settings.camera_height.value
	return Vector3(-cam_dist, cam_height, 0)


func is_ball_in_sand(pos: Variant = null) -> bool:
	if has_node("Player") and $Player.ball != null:
		var b = $Player.ball
		if b.is_in_sand or (b.get("shot_was_in_sand") == true) or str(b.get("lie_type")).to_lower() in ["sand", "bunker"]:
			return true
	if has_node("/root/MultiplayerManager"):
		var mp = get_node("/root/MultiplayerManager")
		if not mp.players.is_empty():
			var ap = mp.get_active_player()
			if str(ap.get("lie_type", "")).to_lower() in ["sand", "bunker"]:
				return true
	if pos != null and _height_raycast != null:
		_height_raycast.global_position = Vector3(pos.x, 1000.0, pos.z)
		_height_raycast.target_position = Vector3(0.0, -2000.0, 0.0)
		_height_raycast.force_raycast_update()
		if _height_raycast.is_colliding():
			var collider = _height_raycast.get_collider()
			if collider:
				var cname = collider.name.to_lower()
				if (collider.has_meta("is_sand") and bool(collider.get_meta("is_sand"))) or \
					cname.contains("bunker") or cname.contains("sand") or \
					(collider.has_meta("surface_type") and int(collider.get_meta("surface_type")) == PhysicsEnums.SurfaceType.BUNKER):
					return true
	return false


func get_address_camera_position(ball_pos: Vector3, rot_y: float, override_is_on_green: Variant = null) -> Vector3:
	var is_on_green = false
	if override_is_on_green != null:
		is_on_green = bool(override_is_on_green)
	else:
		is_on_green = is_ball_on_green() or is_ball_on_fringe() or (_get_current_club().to_lower() in ["pt", "putt", "putter"])
	
	if is_on_green:
		var green_offset = Vector3(-1.05, 0.6, 0.0).rotated(Vector3.UP, rot_y)
		return clamp_camera_position(ball_pos + green_offset)
		
	if is_sky_view_active:
		var sky_offset = Vector3(-50.0, 15.0, 0.0).rotated(Vector3.UP, rot_y)
		return clamp_camera_position(ball_pos + sky_offset)
	
	var default_dist = GlobalSettings.range_settings.camera_distance.value
	var default_height = GlobalSettings.range_settings.camera_height.value
	var back_dir = Vector3(-1.0, 0.0, 0.0).rotated(Vector3.UP, rot_y)
	
	var default_cam_pos = ball_pos + back_dir * default_dist + Vector3.UP * default_height
	var clamped_default = clamp_camera_position(default_cam_pos)
	
	# If on flat driving range, terrain height is always 0.0 and no bunker/hill exists
	if is_driving_range:
		return clamped_default

	var is_sand = is_ball_in_sand(ball_pos)
	var terrain_at_default = get_height(clamped_default.x, clamped_default.z)
	var elev_diff = terrain_at_default - ball_pos.y

	# Check terrain line-of-sight obstruction between ball and default camera
	var is_occluded = false
	var ray_start = ball_pos + Vector3.UP * 0.15
	for i in range(1, 12):
		var t = float(i) / 12.0
		var pt = ray_start.lerp(clamped_default, t)
		var h = get_height(pt.x, pt.z)
		if h > pt.y + 0.04:
			is_occluded = true
			break

	if not is_occluded and is_inside_tree():
		var world3d = get_world_3d()
		if world3d != null and world3d.direct_space_state != null:
			var query = PhysicsRayQueryParameters3D.create(ray_start, clamped_default, 1)
			var hit = world3d.direct_space_state.intersect_ray(query)
			if not hit.is_empty():
				is_occluded = true

	# Evaluate if ball is in a deep sandtrap or at the bottom of a steep hill
	var is_deep_sand = is_sand and (elev_diff > 0.35 or is_occluded)
	var is_bottom_of_hill = elev_diff > 1.1 or is_occluded

	# Standard camera for all normal scenarios
	if not is_deep_sand and not is_bottom_of_hill:
		return clamped_default

	# Dynamic camera: zoom in / move closer to the ball so the player is grounded near the ball
	# rather than perched atop the hill/lip, keeping the ball in clear unobstructed view.
	var candidate_distances = [4.2, 3.8, 3.5, 3.2, 2.9, 2.6, 2.3]
	var best_pos = clamped_default
	var found_clear_candidate = false

	for dist in candidate_distances:
		var target_height = clamp(dist * 0.38, 1.1, 1.65)
		var cand_pos = ball_pos + back_dir * dist + Vector3.UP * target_height
		var clamped_cand = clamp_camera_position(cand_pos, 0.35)

		# Ground elevation rise under camera at this distance
		var ground_rise = get_height(clamped_cand.x, clamped_cand.z) - ball_pos.y
		if ground_rise > 0.65:
			# Too far up the hill/lip face, keep searching closer to the ball
			continue

		var cand_occluded = false
		for s in range(1, 6):
			var st = float(s) / 6.0
			var spt = ray_start.lerp(clamped_cand, st)
			if get_height(spt.x, spt.z) > spt.y + 0.04:
				cand_occluded = true
				break

		if not cand_occluded and is_inside_tree():
			var world3d = get_world_3d()
			if world3d != null and world3d.direct_space_state != null:
				var q = PhysicsRayQueryParameters3D.create(ray_start, clamped_cand, 1)
				var h = world3d.direct_space_state.intersect_ray(q)
				if not h.is_empty():
					cand_occluded = true

		if not cand_occluded:
			best_pos = clamped_cand
			found_clear_candidate = true
			break

	if not found_clear_candidate:
		var fallback_pos = ball_pos + back_dir * 2.3 + Vector3.UP * 1.15
		best_pos = clamp_camera_position(fallback_pos, 0.35)

	return best_pos


func update_camera_offset(_val = null) -> void:
	var offset = get_camera_local_offset()
	if has_node("PhantomCamera3D"):
		$PhantomCamera3D.follow_offset = offset
		
	# If ball is available and we are not in follow mode, position manually
	if has_node("Player") and $Player.ball != null:
		if has_node("PhantomCamera3D") and $PhantomCamera3D.follow_mode == PhantomCamera3D.FollowMode.NONE:
			var yaw_rad = deg_to_rad($Player.ball.aim_yaw_offset_deg)
			var is_on_green = is_ball_on_green()
			var cam_pos = get_address_camera_position($Player.ball.global_position, yaw_rad, is_on_green)
			$PhantomCamera3D.global_position = cam_pos
			var target_look = get_camera_target_look(aim_target_pos, $Player.ball.global_position, is_on_green)
			$PhantomCamera3D.look_at(target_look)
			if has_node("Camera3D"):
				$Camera3D.global_position = cam_pos
				$Camera3D.look_at(target_look)


func update_camera_fov(value: float) -> void:
	var fov_val = 30.0 if is_sky_view_active else value
	if has_node("PhantomCamera3D") and $PhantomCamera3D.camera_3d_resource != null:
		$PhantomCamera3D.camera_3d_resource.fov = fov_val
	if has_node("Camera3D"):
		$Camera3D.fov = fov_val


func update_camera_far(value: float) -> void:
	if MobilePerformance.is_mobile():
		value = minf(value, 400.0)
	if has_node("PhantomCamera3D") and $PhantomCamera3D.camera_3d_resource != null:
		$PhantomCamera3D.camera_3d_resource.far = value
	if has_node("Camera3D"):
		$Camera3D.far = value


# ============================================================
# Visual Effects: Depth of Field, Vignette, Atmospheric Fog
# ============================================================

func setup_depth_of_field() -> void:
	# Get the CameraAttributesPractical from the WorldEnvironment (Sky3D)
	var sky3d = get_node_or_null("Sky3D")
	if sky3d and sky3d is WorldEnvironment:
		camera_attributes = sky3d.camera_attributes as CameraAttributesPractical
	if camera_attributes == null:
		# Fallback: create one and assign it
		camera_attributes = CameraAttributesPractical.new()
		if sky3d and sky3d is WorldEnvironment:
			sky3d.camera_attributes = camera_attributes
	
	if has_node("Camera3D"):
		$Camera3D.attributes = camera_attributes
	
	var dof_on = GlobalSettings.range_settings.dof_enabled.value
	var blur_amt = GlobalSettings.range_settings.dof_blur_amount.value
	
	camera_attributes.dof_blur_far_enabled = dof_on
	camera_attributes.dof_blur_far_distance = 150.0
	camera_attributes.dof_blur_far_transition = 100.0
	camera_attributes.dof_blur_amount = blur_amt
	update_dof_focus()
	print("[VisualFX] DOF initialized: enabled=%s, blur=%.3f" % [str(dof_on), blur_amt])


func update_dof_focus() -> void:
	if camera_attributes == null:
		return
	if not GlobalSettings.range_settings.dof_enabled.value:
		return
	
	var focus_dist: float = 150.0
	var ball_pos = Vector3.ZERO
	var spawn_pos = Vector3.ZERO
	var ball_node = null
	
	if has_node("Player") and $Player.ball != null:
		ball_node = $Player.ball
		ball_pos = ball_node.global_position
		spawn_pos = ball_node.spawn_position
		
	# If the ball has moved away from its spawn position (e.g. hit or in flight),
	# we focus the camera on the ball. Otherwise, focus on the aim target.
	var is_ball_active = ball_node != null and ball_pos.distance_to(spawn_pos) > 0.1
	
	if is_ball_active:
		if has_node("Camera3D"):
			focus_dist = $Camera3D.global_position.distance_to(ball_pos)
		else:
			focus_dist = ball_pos.distance_to(aim_target_pos)
	else:
		focus_dist = ball_pos.distance_to(aim_target_pos)
		
	# Clamp to reasonable range
	focus_dist = clamp(focus_dist, 10.0, 500.0)
	camera_attributes.dof_blur_far_distance = focus_dist
	# Transition scales with distance — farther targets get softer transitions
	camera_attributes.dof_blur_far_transition = focus_dist * 0.6


func update_dof_enabled(value) -> void:
	if camera_attributes == null:
		return
	camera_attributes.dof_blur_far_enabled = value
	if value:
		update_dof_focus()


func update_dof_blur_amount(value) -> void:
	if camera_attributes == null:
		return
	camera_attributes.dof_blur_amount = value


func setup_vignette() -> void:
	var vignette_on = GlobalSettings.range_settings.vignette_enabled.value
	var vignette_str = GlobalSettings.range_settings.vignette_intensity.value
	
	# Create a CanvasLayer for the full-screen vignette overlay
	vignette_layer = CanvasLayer.new()
	vignette_layer.name = "VignetteLayer"
	vignette_layer.layer = -1  # Above game, below UI
	add_child(vignette_layer)
	
	# Create full-screen ColorRect
	vignette_rect = ColorRect.new()
	vignette_rect.name = "VignetteRect"
	vignette_rect.anchors_preset = Control.PRESET_FULL_RECT
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Load and apply the vignette shader
	var shader = load("res://Courses/Environments/shaders/vignette.gdshader")
	if shader:
		var mat = ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("intensity", vignette_str)
		mat.set_shader_parameter("radius", 0.35)
		mat.set_shader_parameter("softness", 0.45)
		mat.set_shader_parameter("contrast", 2.0)
		mat.set_shader_parameter("horizontal_weight", 1.6)
		mat.set_shader_parameter("vertical_weight", 0.85)
		mat.set_shader_parameter("edge_desaturation", 0.3)
		vignette_rect.material = mat
		print("[VisualFX] Vignette shader loaded: enabled=%s, intensity=%.2f" % [str(vignette_on), vignette_str])
	else:
		print("[VisualFX] WARNING: Could not load vignette shader")
	
	vignette_layer.add_child(vignette_rect)
	vignette_layer.visible = vignette_on


func update_vignette_enabled(value) -> void:
	if vignette_layer:
		vignette_layer.visible = value


func update_vignette_intensity(value) -> void:
	if vignette_rect and vignette_rect.material:
		vignette_rect.material.set_shader_parameter("intensity", value)


func setup_atmospheric_fog() -> void:
	# Tune the Sky3D atmospheric fog for golf-appropriate distances
	var skydome = get_node_or_null("Sky3D/Skydome")
	if skydome == null:
		print("[VisualFX] No Skydome found, skipping fog tuning")
		return
	if is_driving_range or MobilePerformance.is_mobile():
		# Clear fog and clouds for driving range / mobile devices for maximum performance and visibility
		skydome.fog_density = 0.0
		skydome.clouds_visible = false
		skydome.clouds_cumulus_visible = false
		print("[VisualFX] Fog and clouds disabled for %s" % ("mobile platform" if MobilePerformance.is_mobile() else "maximum range visibility"))
	else:
		# Restore original sky settings for dynamic courses on desktop
		skydome.fog_density = 0.001
		skydome.fog_end = 600.0
		skydome.fog_start = 0.0
		skydome.clouds_visible = true
		skydome.clouds_cumulus_visible = true


func clamp_camera_position(pos: Vector3, min_clearance: float = 0.35) -> Vector3:
	var terrain_h = get_height(pos.x, pos.z)
	if pos.y < terrain_h + min_clearance:
		pos.y = terrain_h + min_clearance
	return pos


var _cached_circle_textures := {}

func _get_circle_texture(color: Color) -> ImageTexture:
	var color_key = color.to_html()
	if _cached_circle_textures.has(color_key):
		return _cached_circle_textures[color_key]
		
	var size := 512
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2.0
	var outer_radius := size / 2.0 - 4.0
	var inner_radius := size / 2.0 - 16.0 # thickness of the circle line
	
	for y in range(size):
		for x in range(size):
			var dx := x - center
			var dy := y - center
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= outer_radius and dist >= inner_radius:
				var alpha := 1.0
				if dist > outer_radius - 2.0:
					alpha = (outer_radius - dist) / 2.0
				elif dist < inner_radius + 2.0:
					alpha = (dist - inner_radius) / 2.0
				img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				
	var tex := ImageTexture.create_from_image(img)
	_cached_circle_textures[color_key] = tex
	return tex


func update_gimme_circles() -> void:
	# Find FlagPin node
	var pin = get_node_or_null("FlagPin")
	if pin == null:
		return
		
	# Gimme +1 Stroke Circle
	var enabled_1 = GlobalSettings.range_settings.gimme_range_1_enabled.value
	var dist_1_feet = GlobalSettings.range_settings.gimme_range_1_distance.value
	var dist_1_meters = dist_1_feet * 0.3048
	
	var decal_1 = pin.get_node_or_null("GimmeCircle1")
	if enabled_1:
		if decal_1 == null:
			decal_1 = Decal.new()
			decal_1.name = "GimmeCircle1"
			decal_1.texture_albedo = _get_circle_texture(Color(0.0, 0.8, 1.0, 1.0)) # Cyan
			decal_1.modulate = Color(0.0, 0.8, 1.0, 0.7)
			decal_1.size = Vector3(dist_1_meters * 2.0, 20.0, dist_1_meters * 2.0)
			decal_1.position = Vector3(0, 0, 0)
			pin.add_child(decal_1)
		else:
			decal_1.size = Vector3(dist_1_meters * 2.0, 20.0, dist_1_meters * 2.0)
			decal_1.visible = true
	else:
		if decal_1 != null:
			decal_1.visible = false
			
	# Gimme +2 Strokes Circle
	var enabled_2 = GlobalSettings.range_settings.gimme_range_2_enabled.value
	var dist_2_feet = GlobalSettings.range_settings.gimme_range_2_distance.value
	var dist_2_meters = dist_2_feet * 0.3048
	
	var decal_2 = pin.get_node_or_null("GimmeCircle2")
	if enabled_2:
		if decal_2 == null:
			decal_2 = Decal.new()
			decal_2.name = "GimmeCircle2"
			decal_2.texture_albedo = _get_circle_texture(Color(1.0, 0.8, 0.0, 1.0)) # Orange-Yellow
			decal_2.modulate = Color(1.0, 0.8, 0.0, 0.7)
			decal_2.size = Vector3(dist_2_meters * 2.0, 20.0, dist_2_meters * 2.0)
			decal_2.position = Vector3(0, 0, 0)
			pin.add_child(decal_2)
		else:
			decal_2.size = Vector3(dist_2_meters * 2.0, 20.0, dist_2_meters * 2.0)
			decal_2.visible = true
	else:
		if decal_2 != null:
			decal_2.visible = false

	# Gimme +3 Strokes Circle
	var enabled_3 = GlobalSettings.range_settings.gimme_range_3_enabled.value
	var dist_3_feet = GlobalSettings.range_settings.gimme_range_3_distance.value
	var dist_3_meters = dist_3_feet * 0.3048
	
	var decal_3 = pin.get_node_or_null("GimmeCircle3")
	if enabled_3:
		if decal_3 == null:
			decal_3 = Decal.new()
			decal_3.name = "GimmeCircle3"
			decal_3.texture_albedo = _get_circle_texture(Color(1.0, 0.35, 0.35, 1.0)) # Coral / Red
			decal_3.modulate = Color(1.0, 0.35, 0.35, 0.7)
			decal_3.size = Vector3(dist_3_meters * 2.0, 20.0, dist_3_meters * 2.0)
			decal_3.position = Vector3(0, 0, 0)
			pin.add_child(decal_3)
		else:
			decal_3.size = Vector3(dist_3_meters * 2.0, 20.0, dist_3_meters * 2.0)
			decal_3.visible = true
	else:
		if decal_3 != null:
			decal_3.visible = false


func get_closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab = b - a
	var ap = p - a
	var ab_len_sq = ab.length_squared()
	if ab_len_sq < 0.00001:
		return a
	var t = ap.dot(ab) / ab_len_sq
	t = clamp(t, 0.0, 1.0)
	return a + t * ab

func get_closest_point_on_polygon(p: Vector2, poly) -> Vector2:
	var closest_pt := Vector2.ZERO
	var min_dist_sq := INF
	var n = poly.size()
	if n == 0:
		return p
	for i in range(n):
		var a = poly[i]
		var b = poly[(i + 1) % n]
		var seg_pt = get_closest_point_on_segment(p, a, b)
		var dist_sq = p.distance_squared_to(seg_pt)
		if dist_sq < min_dist_sq:
			min_dist_sq = dist_sq
			closest_pt = seg_pt
	return closest_pt


func get_club_selector() -> Node:
	return _find_node_by_name(self, "ClubSelector")


func _find_node_by_name(root: Node, name_to_find: String) -> Node:
	if root.name == name_to_find:
		return root
	for child in root.get_children():
		var found = _find_node_by_name(child, name_to_find)
		if found:
			return found
	return null


func get_default_club() -> String:
	if current_hole_location.is_zero_approx() and (aim_target_pos == null or aim_target_pos.is_zero_approx()):
		return "Dr"
	if not has_node("Player") or $Player.ball == null:
		return "Dr"
		
	var ball_pos = $Player.ball.global_position
	# If aiming has been manually adjusted, use distance to aim_target_pos.
	# Otherwise, choose club based on actual distance to the hole!
	var dist_m = ball_pos.distance_to(aim_target_pos) if _aim_is_manual else ball_pos.distance_to(current_hole_location)
	var dist_yards = int(dist_m * 1.09361)
	
	# Determine if ball is on the green
	var is_on_green = is_ball_on_green()
	if not is_on_green:
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty():
			var active_p = mp_mgr.get_active_player()
			if not active_p.is_empty() and active_p.get("lie_type") == "green":
				is_on_green = true
	
	# Determine if we are in the teebox
	var is_in_teebox = false
	if not is_on_green and not practice_mode_active:
		is_in_teebox = ($Player.ball.get("lie_type") == "teebox" or $Player.get("current_lie_type") == "teebox")
		if not is_in_teebox:
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				var active_p = mp_mgr.get_active_player()
				if not active_p.is_empty():
					is_in_teebox = (active_p.get("strokes", 0) == 0)
			else:
				is_in_teebox = (shot_count == 0)
	
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	var p_name = _get_current_player_name()
	var is_fringe = is_ball_on_fringe()
	if mp_mgr != null and mp_mgr.has_method("get_suggested_club"):
		return mp_mgr.get_suggested_club(p_name, float(dist_yards), is_in_teebox, is_on_green, is_fringe)
	else:
		# Fallback if MultiplayerManager is unavailable
		if is_on_green or (is_fringe and dist_yards <= 35):
			return "Pt"
		elif is_in_teebox and dist_yards > 200:
			return "Dr"
		elif dist_yards >= 225:
			return "3w"
		elif dist_yards >= 210:
			return "5w"
		elif dist_yards >= 195:
			return "4i"
		elif dist_yards >= 180:
			return "5i"
		elif dist_yards >= 160:
			return "6i"
		elif dist_yards >= 140:
			return "7i"
		elif dist_yards >= 130:
			return "8i"
		elif dist_yards >= 120:
			return "9i"
		elif dist_yards >= 100:
			return "Pw"
		else:
			return "Sw"


func is_default_club_putter() -> bool:
	return get_default_club().to_lower() in ["pt", "putt", "putter"]


func update_auto_club(force_auto: bool = false) -> String:
	if _shot_active:
		return ""
	if current_hole_location.is_zero_approx() and (aim_target_pos == null or aim_target_pos.is_zero_approx()):
		return ""
	if not has_node("Player") or $Player.ball == null:
		return ""
		
	var selected_club = ""
	
	if _user_custom_club != "" and not force_auto:
		selected_club = _user_custom_club
	else:
		selected_club = get_default_club()

	# Auto-toggle green slope grid when putter is the default selected club (green or fringe)
	if _user_custom_club == "" or force_auto:
		show_green_grid = (selected_club.to_lower() in ["pt", "putt", "putter"])

	# Find ClubSelector UI node and select club
	var club_sel = get_club_selector()
	if club_sel != null and club_sel.has_method("select_club_by_name"):
		_is_updating_auto_club = true
		club_sel.select_club_by_name(selected_club)
		_is_updating_auto_club = false

	# If aim has not been manually customized, set default aim for the selected club
	if not _aim_is_manual:
		apply_default_aim(selected_club)

	return selected_club


func _spawn_driving_range_elements() -> void:
	# Hide old center line and yard markers
	if has_node("CenterLine"):
		$CenterLine.visible = false
	if has_node("YardMarkers"):
		for child in $YardMarkers.get_children():
			child.queue_free()

	_spawn_boundary_walls()
	_spawn_center_target_line()
	
	# Spawn boards and lines at 50, 100, 150, 200, 250, 300, 350 yards
	var yardages = [50.0, 100.0, 150.0, 200.0, 250.0, 300.0, 350.0]
	for yards in yardages:
		_spawn_ground_line(yards)
		
		# Determine staggered Z position for each board so all signs have 100% unobstructed direct sightlines from the tee
		var stagger_yd := 0.0
		match int(yards):
			50: stagger_yd = -18.0   # Left: Moved out wider (-19.8°)
			100: stagger_yd = 28.0   # Right: Moved out wider (+15.6°)
			150: stagger_yd = -24.0  # Left (-9.1°)
			200: stagger_yd = 30.0   # Right (+8.5°)
			250: stagger_yd = -22.0  # Left (-5.0°)
			300: stagger_yd = 26.0   # Right (+5.0°)
			350: stagger_yd = 0.0    # Center (0.0°): Placed directly in the middle down the line
			_: stagger_yd = 0.0
		var stagger_m = stagger_yd * 0.9144
		_spawn_distance_board(yards, stagger_m)


func _spawn_center_target_line() -> void:
	if has_node("RangeCenterTargetLine"):
		var old_line = get_node("RangeCenterTargetLine")
		if old_line:
			old_line.queue_free()
		
	var line_width_m: float = 0.1524 # 6 inches wide (6 * 0.0254m)
	var range_length_m: float = 457.2 # 500 yards (full distance of driving range)
	
	var line = MeshInstance3D.new()
	line.name = "RangeCenterTargetLine"
	var plane = PlaneMesh.new()
	plane.size = Vector2(range_length_m, line_width_m)
	line.mesh = plane
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.15, 0.15, 0.95) # High-contrast vivid red
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = mat
	line.layers = 3 # Visible in 3D player camera (layer 1) and aerial map view (layer 2)
	
	add_child(line)
	# Center of the line in X is half of range length, starting straight from ball tee (x=0) to x=457.2
	line.global_position = Vector3(range_length_m / 2.0, 0.015, 0.0)


func _spawn_boundary_walls() -> void:
	# Corners: min_x = -45.72, max_x = 457.2, min_z = -228.6, max_z = 228.6
	var wall_height := 1.5
	var wall_thickness := 0.2
	var wall_color := Color(0.15, 0.15, 0.15) # Premium dark gray
	
	# Left wall (at z = -228.6)
	_spawn_wall(Vector3(-45.72, 0, -228.6), Vector3(457.2, 0, -228.6), wall_height, wall_thickness, wall_color)
	# Right wall (at z = 228.6)
	_spawn_wall(Vector3(-45.72, 0, 228.6), Vector3(457.2, 0, 228.6), wall_height, wall_thickness, wall_color)
	# Far wall (at x = 457.2)
	_spawn_wall(Vector3(457.2, 0, -228.6), Vector3(457.2, 0, 228.6), wall_height, wall_thickness, wall_color)
	# Back wall (at x = -45.72)
	_spawn_wall(Vector3(-45.72, 0, -228.6), Vector3(-45.72, 0, 228.6), wall_height, wall_thickness, wall_color)


func _spawn_wall(start: Vector3, end: Vector3, height: float, thickness: float, color: Color) -> void:
	var wall = MeshInstance3D.new()
	var box = BoxMesh.new()
	var dist = start.distance_to(end)
	var dir = (end - start).normalized()
	box.size = Vector3(thickness, height, dist)
	wall.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	wall.material_override = mat
	
	add_child(wall)
	wall.global_position = (start + end) / 2.0 + Vector3(0, height / 2.0, 0)
	
	var angle = atan2(dir.x, dir.z)
	wall.rotation.y = angle
	
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = box.size
	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	wall.add_child(static_body)


func _spawn_distance_board(yards: float, z_pos: float) -> void:
	var x_pos = yards * 0.9144
	
	# Distance-based scaling so farther boards remain prominent, clear, and easy to read from the tee
	var dist_ratio: float = clamp((yards - 50.0) / 450.0, 0.0, 1.0)
	var scale_factor: float = 1.0 + dist_ratio * 1.8 # Scales from 1.0x at 50y to 2.8x at 500y
	
	var base_w: float = 8.0
	var base_h: float = 4.8
	var board_width: float = base_w * scale_factor
	var board_height: float = base_h * scale_factor
	
	var ground_clearance: float = clamp(0.8 * scale_factor, 0.8, 2.0)
	var center_y: float = ground_clearance + (board_height / 2.0)
	var base_pos: Vector3 = Vector3(x_pos, 0.0, z_pos)
	
	# 1. Outer dark frame / backing panel (sits behind the white face and borders it cleanly)
	var frame_border: float = 0.45 * scale_factor
	var frame_thickness: float = 0.12 * scale_factor
	var frame = MeshInstance3D.new()
	var frame_mesh = BoxMesh.new()
	frame_mesh.size = Vector3(frame_thickness, board_height + frame_border, board_width + frame_border)
	frame.mesh = frame_mesh
	
	var frame_mat = StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.1, 0.12, 0.14) # Deep dark frame
	frame_mat.roughness = 0.6
	frame_mat.cull_mode = BaseMaterial3D.CULL_BACK
	frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	frame_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	frame.material_override = frame_mat
	add_child(frame)
	frame.global_position = base_pos + Vector3(frame_thickness / 2.0, center_y, 0.0)
	
	# 2. White front board face (mounted flush against the front of the frame at x <= 0)
	var board_thickness: float = 0.08 * scale_factor
	var board = MeshInstance3D.new()
	var board_mesh = BoxMesh.new()
	board_mesh.size = Vector3(board_thickness, board_height, board_width)
	board.mesh = board_mesh
	
	var board_mat = StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.98, 0.98, 0.98) # Bright clean white face
	board_mat.roughness = 0.4
	board_mat.cull_mode = BaseMaterial3D.CULL_BACK
	board_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	board_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	board.material_override = board_mat
	add_child(board)
	board.global_position = base_pos + Vector3(-board_thickness / 2.0, center_y, 0.0)
	
	# 3. Two sturdy posts (poles) behind the backing frame
	var pole_height: float = center_y + board_height * 0.45
	var pole_thickness: float = 0.22 * scale_factor
	var pole_z_offset: float = board_width * 0.36
	var pole_x: float = frame_thickness + (pole_thickness / 2.0)
	
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.15, 0.1) # Dark stained wood
	pole_mat.roughness = 0.8
	pole_mat.cull_mode = BaseMaterial3D.CULL_BACK
	pole_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	pole_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	
	var pole1 = MeshInstance3D.new()
	var pole_mesh = BoxMesh.new()
	pole_mesh.size = Vector3(pole_thickness, pole_height, pole_thickness)
	pole1.mesh = pole_mesh
	pole1.material_override = pole_mat
	add_child(pole1)
	pole1.global_position = base_pos + Vector3(pole_x, pole_height / 2.0, -pole_z_offset)
	
	var pole2 = MeshInstance3D.new()
	pole2.mesh = pole_mesh
	pole2.material_override = pole_mat
	add_child(pole2)
	pole2.global_position = base_pos + Vector3(pole_x, pole_height / 2.0, pole_z_offset)
	
	# Static collision shape for the board
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3((frame_thickness + board_thickness + pole_thickness), pole_height, board_width + frame_border)
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, (pole_height / 2.0) - center_y, 0.0)
	static_body.add_child(collision_shape)
	board.add_child(static_body)
	
	# Try loading bold font if available
	var board_font = null
	if ResourceLoader.exists("res://addons/phantom_camera/fonts/Nunito-Black.ttf"):
		board_font = load("res://addons/phantom_camera/fonts/Nunito-Black.ttf")
	
	var text_color = Color(0.04, 0.04, 0.06)
	var text_pixel_size = (board_height * 0.78) / 360.0
	
	# 4. Front Label3D (facing negative X, towards player)
	var label = Label3D.new()
	label.text = "%d\nYDS" % int(yards)
	if board_font != null:
		label.font = board_font
	label.font_size = 180
	label.line_spacing = -10.0
	label.pixel_size = text_pixel_size
	label.modulate = text_color
	label.outline_modulate = text_color
	label.outline_size = 12
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label.render_priority = 1
	label.no_depth_test = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	board.add_child(label)
	label.position = Vector3(-(board_thickness / 2.0) - 0.015 * scale_factor, 0.0, 0.0)
	label.rotation_degrees = Vector3(0.0, -90.0, 0.0)
	
	# 5. Back Label3D (facing positive X)
	var label_back = Label3D.new()
	label_back.text = "%d\nYDS" % int(yards)
	if board_font != null:
		label_back.font = board_font
	label_back.font_size = 180
	label_back.line_spacing = -10.0
	label_back.pixel_size = text_pixel_size
	label_back.modulate = text_color
	label_back.outline_modulate = text_color
	label_back.outline_size = 12
	label_back.shaded = false
	label_back.double_sided = false
	label_back.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	label_back.render_priority = 1
	label_back.no_depth_test = false
	label_back.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	label_back.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_back.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(label_back)
	label_back.position = Vector3((frame_thickness / 2.0) + 0.015 * scale_factor, 0.0, 0.0)
	label_back.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	
	# 6. Flat board for aerial / minimap views (layer 2)
	var flat_w: float = 24.0 * (1.0 + dist_ratio * 0.8)
	var flat_h: float = 12.0 * (1.0 + dist_ratio * 0.8)
	var flat_frame = MeshInstance3D.new()
	var flat_frame_mesh = PlaneMesh.new()
	flat_frame_mesh.size = Vector2(flat_h + 1.2, flat_w + 1.2)
	flat_frame.mesh = flat_frame_mesh
	
	var flat_frame_mat = StandardMaterial3D.new()
	flat_frame_mat.albedo_color = Color(0.1, 0.12, 0.14)
	flat_frame_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	flat_frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flat_frame.material_override = flat_frame_mat
	flat_frame.layers = 2
	add_child(flat_frame)
	flat_frame.global_position = base_pos + Vector3(0.0, 0.08, 0.0)
	
	var flat_board = MeshInstance3D.new()
	var flat_mesh = PlaneMesh.new()
	flat_mesh.size = Vector2(flat_h, flat_w)
	flat_board.mesh = flat_mesh
	
	var flat_mat = StandardMaterial3D.new()
	flat_mat.albedo_color = Color(0.98, 0.98, 0.98)
	flat_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	flat_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flat_board.material_override = flat_mat
	flat_board.layers = 2
	add_child(flat_board)
	flat_board.global_position = base_pos + Vector3(0.0, 0.09, 0.0)
	
	var flat_label = Label3D.new()
	flat_label.text = "%d YDS" % int(yards)
	if board_font != null:
		flat_label.font = board_font
	flat_label.font_size = 200
	flat_label.modulate = text_color
	flat_label.outline_modulate = text_color
	flat_label.outline_size = 12
	flat_label.double_sided = false
	flat_label.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	flat_label.pixel_size = (flat_w * 0.8) / 750.0
	flat_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	flat_label.layers = 2
	flat_board.add_child(flat_label)
	flat_label.position = Vector3(0.0, 0.01, 0.0)
	flat_label.rotation_degrees = Vector3(-90.0, -90.0, 0.0)


func _spawn_ground_line(yards: float) -> void:
	var x_pos = yards * 0.9144
	var dist_ratio: float = clamp((yards - 50.0) / 450.0, 0.0, 1.0)
	var line_thickness: float = 0.5 + dist_ratio * 0.4
	var line = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(line_thickness, 457.2)
	line.mesh = plane
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = mat
	
	add_child(line)
	line.global_position = Vector3(x_pos, 0.01, 0.0)


func _on_player_profile_changed(player_name: String) -> void:
	var session_rec = get_node_or_null("SessionRecorder")
	if session_rec != null and not player_name.is_empty():
		session_rec.username = player_name
	_update_averages()


func _get_current_player_name() -> String:
	if not is_driving_range:
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty() and not mp_mgr.hole_ids.is_empty():
			var active_player = mp_mgr.get_active_player()
			if not active_player.is_empty() and not str(active_player.get("name", "")).is_empty():
				return str(active_player.get("name", "Player 1"))
	if has_node("RangeUI"):
		var r_ui = get_node("RangeUI")
		if r_ui.has_method("get_selected_player_name"):
			var sel_name = r_ui.get_selected_player_name()
			if not sel_name.is_empty():
				return sel_name
	if has_node("RangeUI/HBoxContainer/PlayerName"):
		var pn = $RangeUI/HBoxContainer/PlayerName.text
		if not pn.is_empty():
			return pn
	var session_rec = get_node_or_null("SessionRecorder")
	if session_rec != null and not session_rec.username.is_empty() and session_rec.username != "Player1":
		return session_rec.username
	return "Player 1"


func _get_current_club() -> String:
	if not _user_custom_club.is_empty():
		return _user_custom_club
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.current_club.is_empty():
		return mp_mgr.current_club
	var club_sel = get_club_selector()
	if club_sel != null and "current_club" in club_sel and club_sel.current_club != null and not club_sel.current_club.text.is_empty():
		return club_sel.current_club.text
	var session_rec = get_node_or_null("SessionRecorder")
	if session_rec != null and not session_rec.current_club.is_empty():
		return session_rec.current_club
	if has_node("Player") and $Player.ball != null and not $Player.ball.current_selected_club.is_empty():
		return $Player.ball.current_selected_club
	return "Dr"


func _on_club_selected(club_name: String) -> void:
	_update_averages(club_name)
	if not _is_updating_auto_club:
		_user_custom_club = club_name
	if has_node("Player") and $Player.ball != null and $Player.ball.has_method("_on_club_selected"):
		$Player.ball._on_club_selected(club_name)
	if not _shot_active and not is_aerial_view:
		if not _is_updating_auto_club and not _aim_is_manual and not current_hole_location.is_zero_approx():
			apply_default_aim(club_name)
		else:
			update_camera_offset()


func _on_active_player_changed(_player: Dictionary) -> void:
	# If MultiplayerController (course_play.gd) is present, it handles ball positioning, resetting, lie detection, aim angle, and camera setup.
	var is_course_play = has_node("MultiplayerController") or get_node_or_null("MultiplayerController") != null or (get_parent() != null and get_parent().name == "CoursePlay")
	if is_course_play:
		_aim_is_manual = false
		if not practice_mode_active:
			_user_custom_club = ""
		_update_averages()
		return

	_aim_is_manual = false
	if not practice_mode_active:
		_user_custom_club = ""
	var is_tee = (_player.get("strokes", 0) == 0)
	if is_tee:
		reset_zoom_to_default()
	_update_averages()
	update_auto_club(is_tee)

	if has_node("Player") and $Player.ball != null and not _player.is_empty():
		var p_pos = _player.get("position", Vector3.ZERO)
		if typeof(p_pos) == TYPE_VECTOR3 and not (p_pos as Vector3).is_zero_approx():
			$Player.ball.spawn_position = p_pos
			$Player.ball.lie_type = _player.get("lie_type", "teebox" if is_tee else "fairway")
			$Player.reset_ball()
			if $Player.get("_last_starting_pos") != null:
				$Player._last_starting_pos = _player.get("last_starting_pos", p_pos)
			update_current_lie_and_reduction()

			apply_default_aim()


func _on_player_changed(_dir: String, _player_name: String) -> void:
	if not practice_mode_active:
		_user_custom_club = ""
	_update_averages()
	update_auto_club(true)


func _load_global_stats() -> Dictionary:
	return get_node("/root/MultiplayerManager").load_global_club_stats()


func _save_global_stats(stats: Dictionary) -> void:
	get_node("/root/MultiplayerManager").save_global_club_stats(stats)


func _record_global_shot(player_name: String, club_name: String, raw_shot: Dictionary) -> void:
	get_node("/root/MultiplayerManager").record_global_shot(player_name, club_name, raw_shot)


func _remove_last_global_shot(player_name: String, club_name: String) -> void:
	get_node("/root/MultiplayerManager").remove_last_global_shot(player_name, club_name)


func remove_last_shot() -> void:
	if not shot_history.is_empty():
		var last_shot = shot_history.pop_back()
		var p_name = last_shot.get("player", "")
		var club_name = last_shot.get("club", "")
		if not p_name.is_empty() and not club_name.is_empty():
			_remove_last_global_shot(p_name, club_name)
		_update_averages()


func _distance_to_segment_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq == 0.0:
		return ap.length()
	var t := clampf(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	var projection := a + t * ab
	return p.distance_to(projection)


func _is_point_in_triangle_2d(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var sign_ab = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var sign_bc = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var sign_ca = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	
	var has_neg = (sign_ab < 0) or (sign_bc < 0) or (sign_ca < 0)
	var has_pos = (sign_ab > 0) or (sign_bc > 0) or (sign_ca > 0)
	
	return not (has_neg and has_pos)


func _distance_to_triangle_2d(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	if _is_point_in_triangle_2d(p, a, b, c):
		return 0.0
	var d1 = _distance_to_segment_2d(p, a, b)
	var d2 = _distance_to_segment_2d(p, b, c)
	var d3 = _distance_to_segment_2d(p, c, a)
	return minf(d1, minf(d2, d3))


func _find_nodes_by_prefix(node: Node, prefix: String) -> Array:
	var result := []
	if node.name.begins_with(prefix):
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_nodes_by_prefix(child, prefix))
	return result


func _find_green_nodes(node: Node) -> Array:
	var result := []
	var n_lower = node.name.to_lower()
	if n_lower.begins_with("green_static") or (n_lower.contains("green") and node is StaticBody3D) or (node.has_meta("surface_type") and int(node.get_meta("surface_type")) == 4):
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_green_nodes(child))
	return result


func _init_cached_surface_bodies() -> void:
	if _cached_surface_nodes_initialized:
		return
	_cached_surface_nodes_initialized = true
	_cached_green_bodies.clear()
	_cached_tee_bodies.clear()
	_cached_fairway_bodies.clear()
	
	var all_static_bodies: Array = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is StaticBody3D:
			all_static_bodies.append(n)
		for child in n.get_children():
			stack.append(child)
			
	for body in all_static_bodies:
		var n_lower: String = body.name.to_lower()
		var is_green = n_lower.begins_with("green_static") or n_lower.contains("green") or (body.has_meta("surface_type") and int(body.get_meta("surface_type")) == 4)
		var is_tee = n_lower.begins_with("tee_static") or n_lower.contains("tee")
		var is_fairway = n_lower.begins_with("fairway_static") or n_lower.contains("fairway")
		
		if not is_green and not is_tee and not is_fairway:
			continue
			
		var shapes_data: Array = []
		var min_x := 999999.0
		var max_x := -999999.0
		var min_z := 999999.0
		var max_z := -999999.0
		var trans: Transform3D = body.global_transform
		
		for child in body.get_children():
			if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
				var shape_faces = child.shape.data
				shapes_data.append(shape_faces)
				for i in range(0, shape_faces.size(), 3):
					var a_3d = trans * shape_faces[i]
					min_x = minf(min_x, a_3d.x)
					max_x = maxf(max_x, a_3d.x)
					min_z = minf(min_z, a_3d.z)
					max_z = maxf(max_z, a_3d.z)
					
		if shapes_data.is_empty():
			continue
			
		var center_2d = Vector2((min_x + max_x) * 0.5, (min_z + max_z) * 0.5)
		var half_extent = Vector2((max_x - min_x) * 0.5, (max_z - min_z) * 0.5)
		var radius = half_extent.length()
		
		var entry = {
			"body": body,
			"transform": trans,
			"shapes": shapes_data,
			"center_2d": center_2d,
			"radius": radius
		}
		if is_green:
			_cached_green_bodies.append(entry)
		if is_tee:
			_cached_tee_bodies.append(entry)
		if is_fairway:
			_cached_fairway_bodies.append(entry)


func get_distance_to_nearest_fairway(pos: Vector3) -> float:
	_init_cached_surface_bodies()
	if _cached_fairway_bodies.is_empty():
		return 9999.0
	var pos_2d := Vector2(pos.x, pos.z)
	var min_dist := 9999.0
	for entry in _cached_fairway_bodies:
		var dist_to_center = pos_2d.distance_to(entry.center_2d)
		if dist_to_center - entry.radius >= min_dist:
			continue # Bounding circle early-out
			
		var trans: Transform3D = entry.transform
		for faces in entry.shapes:
			for i in range(0, faces.size(), 3):
				if i + 2 < faces.size():
					var a_3d = trans * faces[i]
					var b_3d = trans * faces[i+1]
					var c_3d = trans * faces[i+2]
					var a = Vector2(a_3d.x, a_3d.z)
					var b = Vector2(b_3d.x, b_3d.z)
					var c = Vector2(c_3d.x, c_3d.z)
					var dist = _distance_to_triangle_2d(pos_2d, a, b, c)
					if dist < min_dist:
						min_dist = dist
						if min_dist <= 0.001:
							return 0.0
	return min_dist


func is_point_in_fairway(pos_2d: Vector2) -> bool:
	_init_cached_surface_bodies()
	if _cached_fairway_bodies.is_empty():
		return false
	for entry in _cached_fairway_bodies:
		var dist_to_center = pos_2d.distance_to(entry.center_2d)
		if dist_to_center > entry.radius + 0.5:
			continue # Bounding circle early-out
			
		var trans: Transform3D = entry.transform
		for faces in entry.shapes:
			for i in range(0, faces.size(), 3):
				if i + 2 < faces.size():
					var a_3d = trans * faces[i]
					var b_3d = trans * faces[i+1]
					var c_3d = trans * faces[i+2]
					var a = Vector2(a_3d.x, a_3d.z)
					var b = Vector2(b_3d.x, b_3d.z)
					var c = Vector2(c_3d.x, c_3d.z)
					if Geometry2D.point_is_inside_triangle(pos_2d, a, b, c):
						return true
					if _distance_to_triangle_2d(pos_2d, a, b, c) <= 0.5:
						return true
	return false


func _project_point_on_polyline(pt: Vector2, polyline: Array[Vector2]) -> Dictionary:
	if polyline.is_empty():
		return {"closest_point": pt, "progress": 0.0}
	if polyline.size() == 1:
		return {"closest_point": polyline[0], "progress": 0.0}
		
	var best_pt = polyline[0]
	var best_dist_sq = INF
	var best_progress = 0.0
	var current_accum = 0.0
	
	for i in range(polyline.size() - 1):
		var p1 = polyline[i]
		var p2 = polyline[i + 1]
		var seg = p2 - p1
		var seg_len = seg.length()
		if seg_len < 0.001:
			continue
		var t = clampf((pt - p1).dot(seg) / (seg_len * seg_len), 0.0, 1.0)
		var proj = p1 + seg * t
		var d_sq = pt.distance_squared_to(proj)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_pt = proj
			best_progress = current_accum + seg_len * t
		current_accum += seg_len
		
	return {"closest_point": best_pt, "progress": best_progress}


func _get_point_on_polyline(polyline: Array[Vector2], target_dist: float) -> Vector2:
	if polyline.is_empty():
		return Vector2.ZERO
	if polyline.size() == 1 or target_dist <= 0.0:
		return polyline[0]
		
	var current_dist = 0.0
	for i in range(polyline.size() - 1):
		var p1 = polyline[i]
		var p2 = polyline[i + 1]
		var seg_len = p1.distance_to(p2)
		if current_dist + seg_len >= target_dist:
			var t = (target_dist - current_dist) / maxf(seg_len, 0.001)
			return p1.lerp(p2, clampf(t, 0.0, 1.0))
		current_dist += seg_len
		
	return polyline.back()


func _get_club_effective_distance_yards(club_name: String) -> float:
	var p_name = _get_current_player_name() if is_inside_tree() else ""
	var mp_mgr = get_node_or_null("/root/MultiplayerManager") if is_inside_tree() else null
	if mp_mgr != null and mp_mgr.has_method("get_club_effective_distance"):
		return float(mp_mgr.get_club_effective_distance(p_name, club_name))
	var default_dist = 140.0
	match club_name.to_lower():
		"dr", "driver", "1w": default_dist = 250.0
		"2w": default_dist = 235.0
		"3w": default_dist = 225.0
		"4w": default_dist = 215.0
		"5w": default_dist = 205.0
		"7w": default_dist = 190.0
		"2h": default_dist = 210.0
		"3h": default_dist = 200.0
		"4h": default_dist = 190.0
		"5h": default_dist = 180.0
		"1i": default_dist = 220.0
		"2i": default_dist = 210.0
		"3i": default_dist = 200.0
		"4i": default_dist = 190.0
		"5i": default_dist = 175.0
		"6i": default_dist = 160.0
		"7i": default_dist = 140.0
		"8i": default_dist = 130.0
		"9i": default_dist = 115.0
		"pw": default_dist = 100.0
		"gw", "aw": default_dist = 90.0
		"sw": default_dist = 80.0
		"lw": default_dist = 65.0
		"pt": default_dist = 10.0
	if mp_mgr != null and "DEFAULT_CLUB_DISTANCES" in mp_mgr:
		default_dist = float(mp_mgr.DEFAULT_CLUB_DISTANCES.get(club_name, default_dist))
	return default_dist


func _dist_to_segment_2d(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var l_sq = ab.length_squared()
	if l_sq < 0.0001:
		return pt.distance_to(a)
	var t = clampf((pt - a).dot(ab) / l_sq, 0.0, 1.0)
	var proj = a + ab * t
	return pt.distance_to(proj)


func _get_distance_to_hole_corridor(pt_2d: Vector2, h_data: Dictionary, ball_2d: Vector2 = Vector2.ZERO, hole_2d: Vector2 = Vector2.ZERO) -> float:
	var path_arr = h_data.get("Hole Path", h_data.get("HolePath", []))
	if typeof(path_arr) == TYPE_ARRAY and path_arr.size() >= 2:
		var min_d := INF
		for i in range(path_arr.size() - 1):
			var a = Vector2(float(path_arr[i][0]), float(path_arr[i][1]))
			var b = Vector2(float(path_arr[i+1][0]), float(path_arr[i+1][1]))
			var d = _dist_to_segment_2d(pt_2d, a, b)
			if d < min_d:
				min_d = d
		return min_d

	var pin_2d := Vector2.ZERO
	var h_loc = h_data.get("Hole Location")
	if h_loc != null and typeof(h_loc) == TYPE_ARRAY and h_loc.size() >= 2:
		pin_2d = Vector2(float(h_loc[0]), float(h_loc[1]))
	elif not hole_2d.is_zero_approx():
		pin_2d = hole_2d

	var tee_2d := Vector2.ZERO
	var tee_boxes = h_data.get("Tee Boxes", {})
	if typeof(tee_boxes) == TYPE_DICTIONARY and not tee_boxes.is_empty():
		var def_key = "Blue" if "Blue" in tee_boxes else tee_boxes.keys()[0]
		var t_arr = tee_boxes[def_key]
		tee_2d = Vector2(float(t_arr[0]), float(t_arr[1]))
	elif not ball_2d.is_zero_approx():
		tee_2d = ball_2d

	if not pin_2d.is_zero_approx() and not tee_2d.is_zero_approx():
		return _dist_to_segment_2d(pt_2d, tee_2d, pin_2d)
	elif not pin_2d.is_zero_approx():
		return pt_2d.distance_to(pin_2d)

	return INF


func _is_point_in_current_hole_corridor(pt_2d: Vector2, active_hole: Dictionary, all_holes: Dictionary, ball_2d: Vector2, hole_2d: Vector2) -> bool:
	var dist_cur = _get_distance_to_hole_corridor(pt_2d, active_hole, ball_2d, hole_2d)
	# Fairway corridor on any normal golf hole is within 45m of the hole path/centerline
	if dist_cur > 45.0:
		return false

	# If multiple holes exist, verify the candidate point is closer to the current hole than other holes
	if all_holes.size() > 1:
		for k in all_holes.keys():
			var other_h = all_holes[k]
			if other_h == active_hole:
				continue
			var dist_other = _get_distance_to_hole_corridor(pt_2d, other_h)
			# If closer to another hole's corridor (with a 5m buffer), it belongs to that other hole
			if dist_other < (dist_cur - 5.0):
				return false

	return true


func _find_fairway_midpoint_at_radius(ball_2d: Vector2, ref_dir: Vector2, radius_m: float, active_hole: Dictionary = {}, all_holes: Dictionary = {}, hole_2d: Vector2 = Vector2.ZERO) -> Vector2:
	_init_cached_surface_bodies()
	if _cached_fairway_bodies.is_empty():
		return Vector2.ZERO

	if active_hole.is_empty():
		active_hole = get_active_hole_config()
	if all_holes.is_empty():
		all_holes = get_all_holes_config()
	if hole_2d.is_zero_approx() and not current_hole_location.is_zero_approx():
		hole_2d = Vector2(current_hole_location.x, current_hole_location.z)

	var scan_max_deg := 35.0
	var step_deg := 1.0
	var inside_intervals: Array[Dictionary] = []
	var cur_start := -999.0
	var cur_end := -999.0

	var d = -scan_max_deg
	while d <= scan_max_deg + 0.01:
		var sample_dir = ref_dir.rotated(deg_to_rad(d))
		var pt_2d = ball_2d + sample_dir * radius_m
		var inside = is_point_in_fairway(pt_2d)
		if inside and not active_hole.is_empty():
			if not _is_point_in_current_hole_corridor(pt_2d, active_hole, all_holes, ball_2d, hole_2d):
				inside = false

		if inside:
			if cur_start < -900.0:
				cur_start = d
			cur_end = d
		else:
			if cur_start > -900.0:
				inside_intervals.append({"start": cur_start, "end": cur_end})
				cur_start = -999.0
				cur_end = -999.0
		d += step_deg

	if cur_start > -900.0:
		inside_intervals.append({"start": cur_start, "end": cur_end})

	if inside_intervals.is_empty():
		return Vector2.ZERO

	# Find the fairway interval whose center is closest to 0° (the reference line)
	var best_interval = inside_intervals[0]
	var best_center_dist = absf((best_interval["start"] + best_interval["end"]) * 0.5)
	for i in range(1, inside_intervals.size()):
		var interval = inside_intervals[i]
		var c_dist = absf((interval["start"] + interval["end"]) * 0.5)
		if c_dist < best_center_dist:
			best_center_dist = c_dist
			best_interval = interval

	var mid_deg = (best_interval["start"] + best_interval["end"]) * 0.5
	var final_dir = ref_dir.rotated(deg_to_rad(mid_deg))
	return ball_2d + final_dir * radius_m


func get_default_aim_target(ball_pos: Vector3, club_name: String = "") -> Vector3:
	if current_hole_location.is_zero_approx():
		return aim_target_pos

	# Putting practice, or ball is on green
	if is_ball_on_green():
		return current_hole_location

	# Resolve active club
	var active_club = club_name
	if active_club.is_empty():
		active_club = _get_current_club()
	if active_club.is_empty():
		var club_sel = get_club_selector()
		if club_sel != null and club_sel.has_method("get_current_club_name"):
			active_club = club_sel.get_current_club_name()

	var hole_dist_m = ball_pos.distance_to(current_hole_location)
	var hole_dist_yards = hole_dist_m * 1.09361

	# If still empty, determine what club would be suggested for the hole distance
	if active_club.is_empty():
		var is_in_teebox = false
		if has_node("Player") and $Player.ball != null:
			is_in_teebox = ($Player.ball.get("lie_type") == "teebox" or $Player.get("current_lie_type") == "teebox" or shot_count == 0)
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		var p_name = _get_current_player_name()
		if mp_mgr != null and mp_mgr.has_method("get_suggested_club"):
			active_club = mp_mgr.get_suggested_club(p_name, hole_dist_yards, is_in_teebox, false, is_ball_on_fringe())
		else:
			active_club = "Dr" if is_in_teebox and hole_dist_yards > 200 else "7i"

	var club_dist_yards = _get_club_effective_distance_yards(active_club)

	# Rule 1: If the selected club can reach or exceed the hole distance, aim directly at the hole
	if club_dist_yards >= (hole_dist_yards - 0.5):
		return current_hole_location

	# Rule 2: If the ball is within approach range of the green (or using a wedge / short approach club),
	# always maintain direct aim toward the green/pin rather than scanning for a fairway corridor off-axis.
	var is_wedge = active_club.to_lower() in ["pw", "gw", "aw", "sw", "lw", "pt"]
	var is_approach_range = hole_dist_yards <= 140.0
	if is_approach_range or (is_wedge and hole_dist_yards <= 180.0):
		return current_hole_location

	# Rule 3: Otherwise, aim at the middle of the current hole's fairway at the distance the selected club can go
	var target_dist_m = club_dist_yards / 1.09361
	if target_dist_m >= hole_dist_m:
		return current_hole_location

	var ball_2d = Vector2(ball_pos.x, ball_pos.z)
	var hole_2d = Vector2(current_hole_location.x, current_hole_location.z)
	var to_hole_dir = (hole_2d - ball_2d).normalized()
	if to_hole_dir.is_zero_approx():
		to_hole_dir = Vector2.RIGHT

	# Check for Hole Path corridor
	var active_hole = get_active_hole_config()
	var all_holes = get_all_holes_config()
	var path_arr = active_hole.get("Hole Path", active_hole.get("HolePath", []))
	var path_pts: Array[Vector2] = []
	var path_target_2d = Vector2.ZERO
	var has_path := false
	if typeof(path_arr) == TYPE_ARRAY and path_arr.size() >= 2:
		for pt in path_arr:
			path_pts.append(Vector2(float(pt[0]), float(pt[1])))
		var proj_info = _project_point_on_polyline(ball_2d, path_pts)
		path_target_2d = _get_point_on_polyline(path_pts, proj_info["progress"] + target_dist_m)
		has_path = true

	var ref_dir = to_hole_dir
	if has_path:
		var dir_along_path = (path_target_2d - ball_2d).normalized()
		if not dir_along_path.is_zero_approx():
			ref_dir = dir_along_path

	# Scan fairway collision mesh around ref_dir to find fairway middle at radius target_dist_m
	var scan_fairway_mid = _find_fairway_midpoint_at_radius(ball_2d, ref_dir, target_dist_m, active_hole, all_holes, hole_2d)
	if scan_fairway_mid != Vector2.ZERO:
		return Vector3(scan_fairway_mid.x, get_height(scan_fairway_mid.x, scan_fairway_mid.y), scan_fairway_mid.y)

	# Fallback 1: Hole Path point
	if has_path and not path_target_2d.is_zero_approx():
		var fallback_dir = (path_target_2d - ball_2d).normalized()
		if fallback_dir.is_zero_approx():
			fallback_dir = ref_dir
		var fallback_2d = ball_2d + fallback_dir * target_dist_m
		return Vector3(fallback_2d.x, get_height(fallback_2d.x, fallback_2d.y), fallback_2d.y)

	# Fallback 2: Straight toward hole at target_dist_m
	var direct_2d = ball_2d + to_hole_dir * target_dist_m
	return Vector3(direct_2d.x, get_height(direct_2d.x, direct_2d.y), direct_2d.y)


func apply_default_aim(club_name: String = "") -> Vector3:
	if not has_node("Player") or $Player.ball == null:
		return aim_target_pos
	if current_hole_location.is_zero_approx():
		return aim_target_pos

	var ball_pos = $Player.ball.global_position
	var target_pos = get_default_aim_target(ball_pos, club_name)

	aim_target_pos = target_pos
	update_dof_focus()
	if has_node("AimMarker"):
		$AimMarker.global_position = aim_target_pos

	var diff = aim_target_pos - ball_pos
	var angle_rad = atan2(diff.z, diff.x)
	$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)

	var dist_m = ball_pos.distance_to(aim_target_pos)
	var dist_yards = int(dist_m * 1.09361)
	set_aim_distance(dist_yards)

	var is_on_green = is_ball_on_green()
	var yaw_rad = -angle_rad
	var cam_pos = get_address_camera_position(ball_pos, yaw_rad, is_on_green)
	var target_look = get_camera_target_look(aim_target_pos, ball_pos, is_on_green)

	if has_node("PhantomCamera3D"):
		$PhantomCamera3D.follow_mode = PhantomCamera3D.FollowMode.NONE
		$PhantomCamera3D.look_at_mode = PhantomCamera3D.LookAtMode.NONE
		$PhantomCamera3D.global_position = cam_pos
		$PhantomCamera3D.look_at(target_look)
		if $PhantomCamera3D.camera_3d_resource != null:
			$PhantomCamera3D.camera_3d_resource.fov = GlobalSettings.range_settings.camera_fov.value
	if has_node("Camera3D"):
		$Camera3D.global_position = cam_pos
		$Camera3D.look_at(target_look)
		$Camera3D.fov = GlobalSettings.range_settings.camera_fov.value

	_aim_is_manual = false
	return aim_target_pos


func get_distance_to_nearest_green(pos: Vector3) -> float:
	_init_cached_surface_bodies()
	if _cached_green_bodies.is_empty():
		return 9999.0
	var pos_2d := Vector2(pos.x, pos.z)
	
	# Fast early-out if current hole pin is defined and ball is far away
	if not current_hole_location.is_zero_approx():
		var dist_to_pin = pos.distance_to(current_hole_location)
		if dist_to_pin > 60.0:
			return dist_to_pin - 25.0
			
	var min_dist := 9999.0
	for entry in _cached_green_bodies:
		var dist_to_center = pos_2d.distance_to(entry.center_2d)
		if dist_to_center - entry.radius >= min_dist:
			continue # Bounding circle early-out
			
		var trans: Transform3D = entry.transform
		for faces in entry.shapes:
			for i in range(0, faces.size(), 3):
				if i + 2 < faces.size():
					var a_3d = trans * faces[i]
					var b_3d = trans * faces[i+1]
					var c_3d = trans * faces[i+2]
					var a = Vector2(a_3d.x, a_3d.z)
					var b = Vector2(b_3d.x, b_3d.z)
					var c = Vector2(c_3d.x, c_3d.z)
					var dist = _distance_to_triangle_2d(pos_2d, a, b, c)
					if dist < min_dist:
						min_dist = dist
						if min_dist <= 0.001:
							return 0.0
	return min_dist


func get_distance_to_nearest_teebox(pos: Vector3) -> float:
	_init_cached_surface_bodies()
	if _cached_tee_bodies.is_empty():
		return 9999.0
	var pos_2d := Vector2(pos.x, pos.z)
	var min_dist := 9999.0
	for entry in _cached_tee_bodies:
		var dist_to_center = pos_2d.distance_to(entry.center_2d)
		if dist_to_center - entry.radius >= min_dist:
			continue # Bounding circle early-out
			
		var trans: Transform3D = entry.transform
		for faces in entry.shapes:
			for i in range(0, faces.size(), 3):
				if i + 2 < faces.size():
					var a_3d = trans * faces[i]
					var b_3d = trans * faces[i+1]
					var c_3d = trans * faces[i+2]
					var a = Vector2(a_3d.x, a_3d.z)
					var b = Vector2(b_3d.x, b_3d.z)
					var c = Vector2(c_3d.x, c_3d.z)
					var dist = _distance_to_triangle_2d(pos_2d, a, b, c)
					if dist < min_dist:
						min_dist = dist
						if min_dist <= 0.001:
							return 0.0
	return min_dist


func update_current_lie_and_reduction() -> void:
	var ball_node = $Player.ball if has_node("Player") else null
	if ball_node == null:
		return
		
	# Force update of ball's surface detection at its current position
	ball_node._update_surface_from_underneath()
	
	var lie_type = ball_node.get("lie_type")
	if lie_type == null:
		lie_type = "fairway"
	var reduction = 0.0
	
	if is_driving_range:
		var dist_to_spawn = ball_node.global_position.distance_to(ball_node.spawn_position) if ball_node != null else 0.0
		if dist_to_spawn < 1.5:
			lie_type = "teebox"
			reduction = 0.0
			ball_node.lie_type = "teebox"
			ball_node.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
		else:
			lie_type = "fairway"
			reduction = 0.0
			ball_node.lie_type = "fairway"
			ball_node.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
	else:
		# Geometric check fallbacks to ensure absolute accuracy for teeboxes, fairways and greens
		if lie_type != "green" and lie_type != "sand":
			# Check if we are actually on a green (strictly inside green triangles)
			if get_distance_to_nearest_green(ball_node.global_position) <= 0.001:
				lie_type = "green"
				ball_node.lie_type = "green"
				ball_node.set_surface(PhysicsEnums.SurfaceType.GREEN)
			# Check if we are on the fringe / collar bordering the green (within 2.5 meters of green edge)
			elif get_distance_to_nearest_green(ball_node.global_position) <= 2.5:
				lie_type = "fringe"
				ball_node.lie_type = "fringe"
				ball_node.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
			# Check if we are actually on a tee box (strictly inside tee box triangles or at teebox position)
			elif ball_node.lie_type == "teebox" or get_distance_to_nearest_teebox(ball_node.global_position) <= 0.5 or (practice_start_pos != Vector3.ZERO and ball_node.global_position.distance_to(practice_start_pos) < 1.5):
				lie_type = "teebox"
				ball_node.lie_type = "teebox"
				ball_node.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)
			# Check if we are actually on a fairway (strictly inside fairway triangles)
			elif get_distance_to_nearest_fairway(ball_node.global_position) <= 0.001:
				lie_type = "fairway"
				ball_node.lie_type = "fairway"
				ball_node.set_surface(PhysicsEnums.SurfaceType.FAIRWAY)

		if lie_type == "green" or lie_type == "fairway" or lie_type == "fringe":
			reduction = 0.0
		elif lie_type == "teebox":
			reduction = 0.0
		elif lie_type == "rough":
			var d_fairway = get_distance_to_nearest_fairway(ball_node.global_position)
			var d_green = get_distance_to_nearest_green(ball_node.global_position)
			var d = minf(d_fairway, d_green)
			# rough penalty is 10-30% based on how far away from fairway/green (up to 50 meters)
			reduction = 0.10 + 0.20 * clampf(d / 50.0, 0.0, 1.0)
		elif lie_type == "sand":
			# sand penalty is 20-40% based on relative apex height (up to 30 meters)
			var shot_height = max(0.0, $Player.apex - $Player._last_starting_pos.y)
			reduction = 0.20 + 0.20 * clampf(shot_height / 30.0, 0.0, 1.0)

	# Update ball tee elevation and tee peg visibility
	if ball_node != null and ball_node.has_method("_update_tee_elevation"):
		ball_node._update_tee_elevation()
			
	# Save it
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty():
		var active_player = mp_mgr.get_active_player()
		active_player["lie_type"] = lie_type
		active_player["shot_reduction"] = reduction
		print("[range.gd] Multiplayer Active. Storing lie penalty for player %s: %s (%.1f%%)" % [active_player["name"], lie_type, reduction * 100.0])
	else:
		print("[range.gd] Single Player Active. Storing lie penalty: %s (%.1f%%)" % [lie_type, reduction * 100.0])

	if has_node("Player"):
		$Player.current_shot_reduction = reduction
		$Player.current_lie_type = lie_type
		
	# Update UI
	_update_aim_distance_label_text()
		
	# If in course play, update HUD
	var mp_ctrl = get_node_or_null("MultiplayerController")
	var parent = get_parent()
	var active_p = mp_mgr.get_active_player() if (mp_mgr != null and not mp_mgr.players.is_empty()) else {}
	if not active_p.is_empty():
		if mp_ctrl != null and mp_ctrl.has_method("_update_top_hud"):
			mp_ctrl.call("_update_top_hud", active_p)
		elif parent != null and parent.has_method("_update_top_hud"):
			parent.call("_update_top_hud", active_p)
		elif parent != null and parent.has_method("_on_active_player_changed"):
			parent.call("_on_active_player_changed", active_p)


func get_aim_elevation_difference() -> float:
	var ball_node = $Player.ball if has_node("Player") else null
	var ball_y := 0.0
	if ball_node != null:
		ball_y = ball_node.global_position.y
	elif practice_start_pos != Vector3.ZERO:
		ball_y = practice_start_pos.y
	else:
		return 0.0

	var target_y := aim_target_pos.y
	if is_zero_approx(target_y) and (abs(aim_target_pos.x) > 0.001 or abs(aim_target_pos.z) > 0.001):
		target_y = get_height(aim_target_pos.x, aim_target_pos.z)

	return target_y - ball_y


func set_aim_distance(dist_yards: float) -> void:
	var elev_diff = get_aim_elevation_difference()
	if abs(current_aim_distance_yards - dist_yards) < 0.05 and abs(current_aim_elevation_diff_m - elev_diff) < 0.1:
		return
	current_aim_distance_yards = dist_yards
	current_aim_elevation_diff_m = elev_diff
	_update_aim_distance_label_text()


func _update_aim_distance_label_text() -> void:
	if not has_node("MapCanvas/AimDistanceLabel"):
		return
		
	var label = $MapCanvas/AimDistanceLabel

	# Determine if ball is on green / putting
	var on_green = is_ball_on_green()
	if not on_green and has_node("Player") and $Player.ball != null:
		var ball_lie = str($Player.ball.get("lie_type")).to_lower()
		var p_lie = str($Player.get("current_lie_type")).to_lower()
		if ball_lie == "green" or p_lie == "green":
			on_green = true
	if not on_green and has_node("/root/MultiplayerManager"):
		var mp = get_node("/root/MultiplayerManager")
		if not mp.players.is_empty():
			var ap = mp.get_active_player()
			if ap.get("lie_type", "").to_lower() == "green":
				on_green = true

	var dist_m = 0.0
	var has_valid_dist = false
	if has_node("Player") and $Player.ball != null and not aim_target_pos.is_zero_approx():
		dist_m = $Player.ball.global_position.distance_to(aim_target_pos)
		has_valid_dist = true

	var is_imperial := true
	if has_node("/root/GlobalSettings"):
		var gs = get_node("/root/GlobalSettings")
		if gs.get("range_settings") != null and gs.range_settings.get("range_units") != null:
			is_imperial = (gs.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL)

	var base_text := ""
	if on_green:
		var dist_ft = int(round(dist_m * 3.28084)) if has_valid_dist else int(round(current_aim_distance_yards * 3.0))
		base_text = "🎯 Aim %d Feet" % dist_ft
	else:
		if is_imperial:
			var dist_yds = int(round(dist_m * 1.09361)) if has_valid_dist else int(round(current_aim_distance_yards))
			base_text = "🎯 Aim %d Yards" % dist_yds
		else:
			var dist_meters = int(round(dist_m)) if has_valid_dist else int(round(current_aim_distance_yards * 0.9144))
			base_text = "🎯 Aim %d Meters" % dist_meters
	
	# Calculate elevation difference between target and ball
	var elev_diff_m = get_aim_elevation_difference()
	current_aim_elevation_diff_m = elev_diff_m
	
	var elev_text := ""
	if is_imperial:
		var elev_ft = elev_diff_m * 3.28084
		var elev_int = int(round(elev_ft))
		if elev_int == 0:
			elev_text = "⛰️ Elevation 0 Feet"
		elif elev_int > 0:
			elev_text = "⛰️ Elevation ▲ %d Feet" % elev_int
		else:
			elev_text = "⛰️ Elevation ▼ %d Feet" % abs(elev_int)
	else:
		var elev_m_rounded = snappedf(elev_diff_m, 0.1)
		if abs(elev_m_rounded) < 0.05:
			elev_text = "⛰️ Elevation 0.0 Meters"
		elif elev_m_rounded > 0.0:
			elev_text = "⛰️ Elevation ▲ %.1f Meters" % elev_m_rounded
		else:
			elev_text = "⛰️ Elevation ▼ %.1f Meters" % abs(elev_m_rounded)

	# Get the active player's reduction/lie or single player's
	var reduction = 0.0
	var lie_type = "fairway"
	
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty():
		var active_player = mp_mgr.get_active_player()
		reduction = active_player.get("shot_reduction", 0.0)
		lie_type = active_player.get("lie_type", "fairway")
	else:
		if has_node("Player"):
			reduction = $Player.current_shot_reduction
			lie_type = $Player.current_lie_type
			
	var emoji := "🟢"
	var name_str := "Fairway"
	match lie_type:
		"green":
			emoji = "⛳"
			name_str = "Green"
		"fringe":
			emoji = "🌱"
			name_str = "Fringe"
		"fairway":
			emoji = "🟢"
			name_str = "Fairway"
		"teebox":
			emoji = "🏌️"
			name_str = "Tee Box"
		"rough":
			emoji = "🌿"
			name_str = "Rough"
		"sand":
			emoji = "🏖️"
			name_str = "Sand"
			
	var lie_text := ""
	if reduction > 0.0:
		lie_text = "%s %s (-%d%%)" % [emoji, name_str, int(reduction * 100.0)]
	else:
		lie_text = "%s %s (0%%)" % [emoji, name_str]

	var wind_text := ""
	var is_wind := false
	var gs = null
	if is_inside_tree() and get_tree().root.has_node("GlobalSettings"):
		gs = get_tree().root.get_node("GlobalSettings")
	elif GlobalSettings != null:
		gs = GlobalSettings

	if gs != null and gs.is_wind_enabled():
		is_wind = true
		var ball_pos := Vector3.ZERO
		if has_node("Player") and $Player.ball != null:
			ball_pos = $Player.ball.global_position if $Player.ball.is_inside_tree() else $Player.ball.position
		elif has_node("Player"):
			ball_pos = $Player.global_position if $Player.is_inside_tree() else $Player.position
		var fallback_fwd := Vector3.RIGHT
		if has_node("Player") and $Player.ball != null and $Player.ball.has_method("get_target_dir"):
			fallback_fwd = $Player.ball.get_target_dir()
		var wind_info: Dictionary = gs.get_relative_wind_arrow_and_angle(ball_pos, aim_target_pos, fallback_fwd)
		var arrow_symbol: String = wind_info.get("arrow", "↑")
		var spd_val: int = int(round(wind_info.get("speed_mph", 0.0)))
		wind_text = "💨 %s Wind %d MPH" % [arrow_symbol, spd_val]

	if is_wind and not wind_text.is_empty():
		label.text = "%s | %s | %s | %s" % [base_text, elev_text, lie_text, wind_text]
	else:
		label.text = "%s | %s | %s" % [base_text, elev_text, lie_text]

	var font: Font = label.get_theme_font("font")
	var font_sz: int = label.get_theme_font_size("font_size")
	if font_sz <= 0:
		font_sz = 18
	var text_w: float = 0.0
	if font != null:
		text_w = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
	if text_w <= 0.0:
		text_w = label.get_minimum_size().x
	if text_w <= 0.0:
		text_w = label.text.length() * 9.5

	var half_w: float = ceil((text_w / 2.0) + 14.0)
	label.offset_left = -half_w
	label.offset_right = half_w
	if has_node("MapCanvas/AimDistanceBadge"):
		$MapCanvas/AimDistanceBadge.offset_left = -half_w
		$MapCanvas/AimDistanceBadge.offset_right = half_w


func apply_circular_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 28 # Half of 56 height
	style_normal.corner_radius_top_right = 28
	style_normal.corner_radius_bottom_left = 28
	style_normal.corner_radius_bottom_right = 28
	style_normal.content_margin_left = 8
	style_normal.content_margin_right = 8
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 24)


func get_current_green_vertices() -> PackedVector3Array:
	var pin_pos = current_hole_location
	if pin_pos.is_zero_approx():
		pin_pos = aim_target_pos
	if pin_pos.is_zero_approx():
		return PackedVector3Array()
		
	var closest_green: StaticBody3D = null
	var min_dist_to_pin = 999999.0
	
	var stack = [self]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is StaticBody3D and node.name.begins_with("green_Static_"):
			var centroid = Vector3.ZERO
			var vertex_count = 0
			for child in node.get_children():
				if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
					var verts = child.shape.data
					if verts.size() > 0:
						for v in verts:
							centroid += node.global_transform * v
						vertex_count += verts.size()
			if vertex_count > 0:
				centroid /= vertex_count
				var dist = centroid.distance_to(pin_pos)
				if dist < min_dist_to_pin:
					min_dist_to_pin = dist
					closest_green = node
			else:
				var dist = node.global_position.distance_to(pin_pos)
				if dist < min_dist_to_pin:
					min_dist_to_pin = dist
					closest_green = node
		
		for child in node.get_children():
			stack.append(child)
			
	if closest_green == null:
		return PackedVector3Array()
		
	var global_verts = PackedVector3Array()
	for child in closest_green.get_children():
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			var verts = child.shape.data
			for v in verts:
				global_verts.append(closest_green.global_transform * v)
				
	return global_verts


func is_ball_in_teebox() -> bool:
	if has_node("Player") and $Player.ball != null:
		var ball = $Player.ball
		var lie = str(ball.get("lie_type")).to_lower()
		var p_lie = str($Player.get("current_lie_type")).to_lower()
		if lie == "teebox" or p_lie == "teebox":
			return true
		if is_driving_range:
			var dist_to_spawn = ball.global_position.distance_to(ball.spawn_position)
			if dist_to_spawn < 1.5:
				return true
		if has_method("get_distance_to_nearest_teebox"):
			var d_tee = get_distance_to_nearest_teebox(ball.global_position)
			if d_tee <= 0.001:
				return true
		if not practice_mode_active:
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				var active_p = mp_mgr.get_active_player()
				if not active_p.is_empty() and active_p.get("strokes", 0) == 0:
					return true
			elif "shot_count" in self and shot_count == 0:
				return true
	return false


func is_ball_close_to_green() -> bool:
	if is_ball_on_green() or is_ball_on_fringe():
		return true
	if has_node("Player") and $Player.ball != null:
		var ball = $Player.ball
		var lie = str(ball.get("lie_type")).to_lower()
		var p_lie = str($Player.get("current_lie_type")).to_lower()
		if lie == "green" or p_lie == "green" or lie == "fringe" or p_lie == "fringe":
			return true
		var target_pos = current_hole_location
		if target_pos.is_zero_approx() and aim_target_pos != null:
			target_pos = aim_target_pos
		if not target_pos.is_zero_approx():
			var dist_to_hole = ball.global_position.distance_to(target_pos)
			if dist_to_hole <= 45.0: # ~50 yards
				return true
			if dist_to_hole > 75.0:
				return false
		if has_method("get_distance_to_nearest_green"):
			var d_green = get_distance_to_nearest_green(ball.global_position)
			if d_green <= 30.0:
				return true
	return false


func get_current_zoom_zone() -> int:
	if is_ball_in_teebox():
		return 0 # TEE_BOX
	elif is_ball_close_to_green():
		return 2 # GREEN
	else:
		return 1 # MIDWAY


func get_zoom_for_zone(zone: int) -> float:
	var green_zoom = get_green_zoom_size()
	var tee_zoom = _teebox_aerial_zoom
	match zone:
		0: # TEE_BOX
			return tee_zoom
		1: # MIDWAY (half way between tee box zoom and green zoom)
			return (tee_zoom + green_zoom) * 0.5
		2: # GREEN
			return green_zoom
		_:
			return tee_zoom


func get_green_zoom_size() -> float:
	return 50.0


func reset_zoom_to_default() -> void:
	aerial_zoom = 300.0
	_teebox_aerial_zoom = 300.0
	_default_non_green_aerial_zoom = 300.0
	_last_zoom_zone = -1
	_last_was_on_green = false
	aerial_cam_user_offset = Vector3.ZERO
	if has_node("AerialCamera"):
		$AerialCamera.size = aerial_zoom
	show_green_grid = false


func _on_hole_completed(_scores: Array = []) -> void:
	reset_zoom_to_default()
	_user_custom_club = ""


# ==========================================
# GREEN SLOPE GRID & ELEVATION HEATMAP LOGIC
# ==========================================

func _get_green_triangles(pin_pos: Vector3) -> Array:
	var closest_green: StaticBody3D = null
	var min_dist_to_pin = 999999.0
	
	var stack = [self]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is StaticBody3D and node.name.begins_with("green_Static_"):
			var centroid = Vector3.ZERO
			var vertex_count = 0
			for child in node.get_children():
				if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
					var verts = child.shape.data
					if verts.size() > 0:
						for v in verts:
							centroid += node.global_transform * v
						vertex_count += verts.size()
			if vertex_count > 0:
				centroid /= vertex_count
				var dist = centroid.distance_to(pin_pos)
				if dist < min_dist_to_pin:
					min_dist_to_pin = dist
					closest_green = node
			else:
				var dist = node.global_position.distance_to(pin_pos)
				if dist < min_dist_to_pin:
					min_dist_to_pin = dist
					closest_green = node
		
		for child in node.get_children():
			stack.append(child)
			
	if closest_green == null:
		return []
		
	var triangles = []
	for child in closest_green.get_children():
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			var verts = child.shape.data
			for i in range(0, verts.size(), 3):
				if i + 2 < verts.size():
					var v0 = closest_green.global_transform * verts[i]
					var v1 = closest_green.global_transform * verts[i+1]
					var v2 = closest_green.global_transform * verts[i+2]
					triangles.append([
						Vector2(v0.x, v0.z),
						Vector2(v1.x, v1.z),
						Vector2(v2.x, v2.z)
					])
	return triangles


func _is_point_in_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 = (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 = (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 = (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	
	var has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
	var has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
	
	return not (has_neg and has_pos)


func _get_heatmap_color(t: float) -> Color:
	var color: Color
	if t < 0.25:
		color = Color.BLUE.lerp(Color.CYAN, t / 0.25)
	elif t < 0.5:
		color = Color.CYAN.lerp(Color.GREEN, (t - 0.25) / 0.25)
	elif t < 0.75:
		color = Color.GREEN.lerp(Color.YELLOW, (t - 0.5) / 0.25)
	else:
		color = Color.YELLOW.lerp(Color.RED, (t - 0.75) / 0.25)
	color.a = 0.55
	return color


func _create_arrow_mesh() -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half_w = 0.028
	var half_l = 0.036
	var h = 0.003
	
	var t_tip = Vector3(0.0, h, half_l)
	var t_left = Vector3(-half_w, h, -half_l)
	var t_right = Vector3(half_w, h, -half_l)
	
	var b_tip = Vector3(0.0, -h, half_l)
	var b_left = Vector3(-half_w, -h, -half_l)
	var b_right = Vector3(half_w, -h, -half_l)
	
	# Top face
	st.add_vertex(t_tip)
	st.add_vertex(t_left)
	st.add_vertex(t_right)
	
	# Bottom face
	st.add_vertex(b_tip)
	st.add_vertex(b_right)
	st.add_vertex(b_left)
	
	# Left side
	st.add_vertex(t_tip)
	st.add_vertex(b_tip)
	st.add_vertex(b_left)
	st.add_vertex(t_tip)
	st.add_vertex(b_left)
	st.add_vertex(t_left)
	
	# Right side
	st.add_vertex(t_tip)
	st.add_vertex(t_right)
	st.add_vertex(b_right)
	st.add_vertex(t_tip)
	st.add_vertex(b_right)
	st.add_vertex(b_tip)
	
	# Back side
	st.add_vertex(t_left)
	st.add_vertex(b_left)
	st.add_vertex(b_right)
	st.add_vertex(t_left)
	st.add_vertex(b_right)
	st.add_vertex(t_right)
	
	st.generate_normals()
	return st.commit()


func _get_arrow_color(_slope_len: float) -> Color:
	return Color.WHITE


func _is_player_near_green() -> bool:
	return is_ball_close_to_green()


func _update_green_grid_visibility() -> void:
	var heatmap_node = get_node_or_null("GreenHeatmapMesh")
	var grid_node = get_node_or_null("GreenGridMesh")
	var dots_node = get_node_or_null("GreenDotsMesh")
	
	if heatmap_node == null or grid_node == null or dots_node == null:
		return
		
	if not show_green_grid:
		heatmap_node.visible = false
		grid_node.visible = false
		dots_node.visible = false
		return
		
	# GreenHeatmapMesh is assigned to visual layer 2.
	# The 3D player camera has layer 2 culled (cull_mask & ~2), so the 3D ground camera
	# never renders the heatmap. AerialCamera and MinimapCamera include layer 2,
	# so they render the heatmap.
	heatmap_node.visible = true
	
	# GreenGridMesh and GreenDotsMesh are assigned to visual layer 3 (bit 4).
	# AerialCamera and MinimapCamera have layer 3 culled (cull_mask & ~4), so aerial and minimap
	# views only show the heatmap without grid lines or moving directional arrows.
	var is_near = _is_player_near_green()
	grid_node.visible = is_near
	dots_node.visible = is_near



func _generate_green_grid_and_heatmap() -> void:
	for name in ["GreenHeatmapMesh", "GreenGridMesh", "GreenDotsMesh"]:
		var node = get_node_or_null(name)
		if node:
			remove_child(node)
			node.queue_free()
			
	var pin_pos = current_hole_location
	if pin_pos.is_zero_approx():
		pin_pos = aim_target_pos
	if pin_pos.is_zero_approx():
		return
		
	var triangles = _get_green_triangles(pin_pos)
	if triangles.is_empty():
		return
		
	var verts = get_current_green_vertices()
	var min_y = 999999.0
	var max_y = -999999.0
	for v in verts:
		if v.y < min_y: min_y = v.y
		if v.y > max_y: max_y = v.y
		
	if max_y - min_y < 0.001:
		max_y = min_y + 1.0
		
	var spacing = 1.0
	var active_cells = {}
	
	for tri in triangles:
		var tx_min = min(tri[0].x, min(tri[1].x, tri[2].x))
		var tx_max = max(tri[0].x, max(tri[1].x, tri[2].x))
		var tz_min = min(tri[0].y, min(tri[1].y, tri[2].y))
		var tz_max = max(tri[0].y, max(tri[1].y, tri[2].y))
		
		var ix_start = int(floor(tx_min / spacing))
		var ix_end = int(ceil(tx_max / spacing))
		var iz_start = int(floor(tz_min / spacing))
		var iz_end = int(ceil(tz_max / spacing))
		
		for ix in range(ix_start, ix_end + 1):
			for iz in range(iz_start, iz_end + 1):
				var cell_center = Vector2((ix + 0.5) * spacing, (iz + 0.5) * spacing)
				if _is_point_in_triangle(cell_center, tri[0], tri[1], tri[2]):
					active_cells[Vector2i(ix, iz)] = true
					
	if active_cells.is_empty():
		return
		
	var st_heatmap = SurfaceTool.new()
	st_heatmap.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var st_grid = SurfaceTool.new()
	st_grid.begin(Mesh.PRIMITIVE_LINES)
	
	var heatmap_y_offset = 0.02
	var grid_y_offset = 0.03
	
	# Height cache for optimization
	var height_cache = {}
	var get_cached_height = func(gx: float, gz: float) -> float:
		var key = Vector2(gx, gz)
		if not height_cache.has(key):
			height_cache[key] = get_height(gx, gz)
		return height_cache[key]
		
	for cell in active_cells.keys():
		var ix = cell.x
		var iz = cell.y
		
		var x0 = ix * spacing
		var x1 = (ix + 1) * spacing
		var z0 = iz * spacing
		var z1 = (iz + 1) * spacing
		
		var y00 = get_cached_height.call(x0, z0)
		var y10 = get_cached_height.call(x1, z0)
		var y11 = get_cached_height.call(x1, z1)
		var y01 = get_cached_height.call(x0, z1)
		
		var h00 = Vector3(x0, y00 + heatmap_y_offset, z0)
		var h10 = Vector3(x1, y10 + heatmap_y_offset, z0)
		var h11 = Vector3(x1, y11 + heatmap_y_offset, z1)
		var h01 = Vector3(x0, y01 + heatmap_y_offset, z1)
		
		var col00 = _get_heatmap_color(clamp((y00 - min_y) / (max_y - min_y), 0.0, 1.0))
		var col10 = _get_heatmap_color(clamp((y10 - min_y) / (max_y - min_y), 0.0, 1.0))
		var col11 = _get_heatmap_color(clamp((y11 - min_y) / (max_y - min_y), 0.0, 1.0))
		var col01 = _get_heatmap_color(clamp((y01 - min_y) / (max_y - min_y), 0.0, 1.0))
		
		st_heatmap.set_color(col00)
		st_heatmap.add_vertex(h00)
		st_heatmap.set_color(col10)
		st_heatmap.add_vertex(h10)
		st_heatmap.set_color(col11)
		st_heatmap.add_vertex(h11)
		
		st_heatmap.set_color(col00)
		st_heatmap.add_vertex(h00)
		st_heatmap.set_color(col11)
		st_heatmap.add_vertex(h11)
		st_heatmap.set_color(col01)
		st_heatmap.add_vertex(h01)
		
		var g00 = Vector3(x0, y00 + grid_y_offset, z0)
		var g10 = Vector3(x1, y10 + grid_y_offset, z0)
		var g11 = Vector3(x1, y11 + grid_y_offset, z1)
		var g01 = Vector3(x0, y01 + grid_y_offset, z1)
		
		st_grid.add_vertex(g00)
		st_grid.add_vertex(g10)
		st_grid.add_vertex(g10)
		st_grid.add_vertex(g11)
		st_grid.add_vertex(g11)
		st_grid.add_vertex(g01)
		st_grid.add_vertex(g01)
		st_grid.add_vertex(g00)
		
	# Collect unique horizontal and vertical edges to generate slope flow arrows
	var h_edges = {}
	var v_edges = {}
	for cell in active_cells.keys():
		var ix = cell.x
		var iz = cell.y
		h_edges[Vector2i(ix, iz)] = true
		h_edges[Vector2i(ix, iz + 1)] = true
		v_edges[Vector2i(ix, iz)] = true
		v_edges[Vector2i(ix + 1, iz)] = true
		
	var dot_y_offset = 0.035
	var dots_data = [] # Array of dictionaries: {start: Vector3, displacement: Vector3, slope: float}
	
	# Horizontal edges
	for edge in h_edges.keys():
		var x0 = edge.x * spacing
		var z0 = edge.y * spacing
		var x1 = (edge.x + 1) * spacing
		var z1 = edge.y * spacing
		
		var y0 = get_cached_height.call(x0, z0)
		var y1 = get_cached_height.call(x1, z1)
		
		var slope = abs(y0 - y1)
		if slope > 0.0005:
			var start_pos: Vector3
			var end_pos: Vector3
			if y0 > y1:
				start_pos = Vector3(x0, y0 + dot_y_offset, z0)
				end_pos = Vector3(x1, y1 + dot_y_offset, z1)
			else:
				start_pos = Vector3(x1, y1 + dot_y_offset, z1)
				end_pos = Vector3(x0, y0 + dot_y_offset, z0)
				
			var dots_per_segment = 2
			for j in range(dots_per_segment):
				dots_data.append({
					"start": start_pos,
					"displacement": end_pos - start_pos,
					"slope": slope,
					"phase_offset": float(j) / float(dots_per_segment)
				})
			
	# Vertical edges
	for edge in v_edges.keys():
		var x0 = edge.x * spacing
		var z0 = edge.y * spacing
		var x1 = edge.x * spacing
		var z1 = (edge.y + 1) * spacing
		
		var y0 = get_cached_height.call(x0, z0)
		var y1 = get_cached_height.call(x1, z1)
		
		var slope = abs(y0 - y1)
		if slope > 0.0005:
			var start_pos: Vector3
			var end_pos: Vector3
			if y0 > y1:
				start_pos = Vector3(x0, y0 + dot_y_offset, z0)
				end_pos = Vector3(x1, y1 + dot_y_offset, z1)
			else:
				start_pos = Vector3(x1, y1 + dot_y_offset, z1)
				end_pos = Vector3(x0, y0 + dot_y_offset, z0)
				
			var dots_per_segment = 2
			for j in range(dots_per_segment):
				dots_data.append({
					"start": start_pos,
					"displacement": end_pos - start_pos,
					"slope": slope,
					"phase_offset": float(j) / float(dots_per_segment)
				})
			
	var heatmap_mesh = st_heatmap.commit()
	var grid_mesh = st_grid.commit()
	
	var heatmap_mi = MeshInstance3D.new()
	heatmap_mi.name = "GreenHeatmapMesh"
	heatmap_mi.mesh = heatmap_mesh
	var mat_hm = StandardMaterial3D.new()
	mat_hm.vertex_color_use_as_albedo = true
	mat_hm.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	heatmap_mi.material_override = mat_hm
	heatmap_mi.layers = 2
	heatmap_mi.visible = false
	add_child(heatmap_mi)
	
	var grid_mi = MeshInstance3D.new()
	grid_mi.name = "GreenGridMesh"
	grid_mi.mesh = grid_mesh
	var mat_g = StandardMaterial3D.new()
	mat_g.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	mat_g.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mi.material_override = mat_g
	grid_mi.layers = 4
	grid_mi.visible = false
	add_child(grid_mi)
	
	# Instantiate MultiMesh for moving slope arrows
	var dots_mi = MultiMeshInstance3D.new()
	dots_mi.name = "GreenDotsMesh"
	
	var multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.instance_count = dots_data.size()
	multimesh.mesh = _create_arrow_mesh()
	
	for i in range(dots_data.size()):
		var data = dots_data[i]
		var disp = data.displacement
		var fwd = disp.normalized()
		var up = Vector3.UP
		if abs(fwd.dot(up)) > 0.95:
			up = Vector3.FORWARD
		var right = up.cross(fwd).normalized()
		up = fwd.cross(right).normalized()
		var basis = Basis(right, up, fwd)
		var tx = Transform3D(basis, data.start)
		multimesh.set_instance_transform(i, tx)
		
		var custom = Color(disp.x, disp.y, disp.z, data.slope)
		multimesh.set_instance_custom_data(i, custom)
		multimesh.set_instance_color(i, Color(data.phase_offset, 0.0, 0.0, 1.0))
		
	dots_mi.multimesh = multimesh
	
	# Create custom spatial shader for arrows
	var shader = Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float time_scale = 1.0;

varying vec4 v_color;

void vertex() {
	vec3 displacement = INSTANCE_CUSTOM.xyz;
	float slope_val = INSTANCE_CUSTOM.w;
	
	float phase_offset = COLOR.r;
	float segment_phase = float(INSTANCE_ID / 2) * 0.25;
	
	// Speed scales with slope gradient to represent acceleration/speed added to the ball in that direction
	// Nearly flat areas hardly move at all, while steep sections move faster up to a capped maximum
	float move_speed = clamp(slope_val * 11.0, 0.0, 0.75);
	float progress = fract(TIME * move_speed * time_scale + phase_offset + segment_phase);
	
	// Translate vertex in world space along the displacement vector
	vec4 world_offset = vec4(displacement * progress, 0.0);
	vec4 local_offset = inverse(MODEL_MATRIX) * world_offset;
	VERTEX += local_offset.xyz;
	
	// Smooth fade-in / fade-out along the segment
	float fade = sin(progress * 3.14159265);
	
	// White arrows with smooth segment edge fading
	v_color = vec4(vec3(1.0), fade * 0.95);
}

void fragment() {
	ALBEDO = v_color.rgb;
	ALPHA = v_color.a;
}
"""
	
	var mat_dots = ShaderMaterial.new()
	mat_dots.shader = shader
	dots_mi.material_override = mat_dots
	dots_mi.layers = 4
	dots_mi.visible = false
	add_child(dots_mi)
	
	_update_green_grid_visibility()


func _exit_tree() -> void:
	if GlobalSettings.is_chipping_minigame:
		GlobalSettings.is_chipping_minigame = false


func _setup_chipping_minigame() -> void:
	chipping_stats = {}
	chipping_island_positions = []
	chipping_islands = []
	for i in range(chipping_distances.size()):
		chipping_stats[i] = {"Attempts": 0, "Hits": 0}
		
	var hole_info_data = course_data_dict.get("Hole Info", {})
	var hole_data = hole_info_data.get("Hole 17", {})
	if hole_data.is_empty():
		push_error("[Chipping] Hole 17 info not found in course data!")
		return
		
	var tee_coord = hole_data.get("Tee Boxes", {}).get("Blue", [52.162712, 31.829489])
	var pin_coord = hole_data.get("Hole Location", [73.96878, 131.19373])
	
	var tee_pos = Vector3(tee_coord[0], get_height(tee_coord[0], tee_coord[1]), tee_coord[1])
	var pin_pos = Vector3(pin_coord[0], get_height(pin_coord[0], pin_coord[1]), pin_coord[1])
	
	var dir = (pin_pos - tee_pos)
	var dir_norm = dir.normalized()
	var perp = Vector3(-dir_norm.z, 0, dir_norm.x).normalized()
	var green_radius = 3.81
	
	for i in range(chipping_distances.size()):
		var dist_meters = chipping_distances[i] * 0.3048
		var lat_offset_meters = chipping_lateral_offsets[i] * 0.3048
		
		var base_pos = tee_pos + dir_norm * dist_meters
		var island_pos = base_pos + perp * lat_offset_meters
		
		var terrain_h = get_height(island_pos.x, island_pos.z)
		island_pos.y = terrain_h + 0.25
		chipping_island_positions.append(island_pos)
		
		var island = StaticBody3D.new()
		island.name = "ChippingGreenIsland_%d" % i
		island.set_meta("surface_type", 4)
		add_child(island)
		island.global_position = island_pos
		chipping_islands.append(island)
		
		var col_shape = CollisionShape3D.new()
		var cyl_shape = CylinderShape3D.new()
		cyl_shape.radius = green_radius
		cyl_shape.height = 1.0
		col_shape.shape = cyl_shape
		island.add_child(col_shape)
		
		var base_mesh_inst = MeshInstance3D.new()
		var base_mesh = CylinderMesh.new()
		base_mesh.top_radius = green_radius + 0.1
		base_mesh.bottom_radius = green_radius + 0.1
		base_mesh.height = 1.0
		base_mesh_inst.mesh = base_mesh
		
		var base_mat = StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.35, 0.25, 0.15)
		base_mat.roughness = 0.9
		base_mesh_inst.material_override = base_mat
		base_mesh_inst.position = Vector3(0.0, -0.4, 0.0)
		island.add_child(base_mesh_inst)
		
		var turf_mesh_inst = MeshInstance3D.new()
		var turf_mesh = CylinderMesh.new()
		turf_mesh.top_radius = green_radius
		turf_mesh.bottom_radius = green_radius
		turf_mesh.height = 0.08
		turf_mesh_inst.mesh = turf_mesh
		
		var turf_mat = StandardMaterial3D.new()
		turf_mat.albedo_texture = load("res://Courses/Environments/grass-green/albedo.png")
		turf_mat.roughness = 0.95
		turf_mesh_inst.material_override = turf_mat
		turf_mesh_inst.position = Vector3(0.0, 0.1, 0.0)
		island.add_child(turf_mesh_inst)
		
		var flag_node = Node3D.new()
		flag_node.name = "Flag_%d" % i
		island.add_child(flag_node)
		flag_node.position = Vector3(0.0, 0.1, 0.0)
		
		var pole = MeshInstance3D.new()
		var pole_mesh = CylinderMesh.new()
		pole_mesh.top_radius = 0.015
		pole_mesh.bottom_radius = 0.015
		pole_mesh.height = 1.8
		pole.mesh = pole_mesh
		var pole_mat = StandardMaterial3D.new()
		pole_mat.albedo_color = Color.WHITE
		pole.material_override = pole_mat
		pole.position = Vector3(0.0, 0.9, 0.0)
		flag_node.add_child(pole)
		
		var flag = MeshInstance3D.new()
		var flag_mesh = PrismMesh.new()
		flag_mesh.size = Vector3(0.35, 0.25, 0.01)
		flag.mesh = flag_mesh
		var flag_mat = StandardMaterial3D.new()
		flag_mat.albedo_color = Color(0.85, 0.65, 0.0)
		flag_mat.emission_enabled = true
		flag_mat.emission = Color(0.85, 0.65, 0.0)
		flag.material_override = flag_mat
		flag.position = Vector3(0.175, 1.775, 0.0)
		flag.rotation = Vector3(0.0, 0.0, -PI/2)
		flag_node.add_child(flag)
		
		var label_node = Label3D.new()
		label_node.text = "%d FT" % chipping_distances[i]
		label_node.font_size = 36
		label_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label_node.outline_size = 8
		label_node.modulate = Color.WHITE
		label_node.position = Vector3(0.0, 2.2, 0.0)
		flag_node.add_child(label_node)
		
	_select_chipping_target(selected_chipping_target_idx)
	_setup_chipping_hud_ui()


func _select_chipping_target(index: int) -> void:
	selected_chipping_target_idx = index
	for i in range(chipping_islands.size()):
		var island_node = chipping_islands[i]
		if island_node:
			var old_ring = island_node.get_node_or_null("TargetRing")
			if old_ring:
				old_ring.queue_free()
				
			if i == index:
				var ring = MeshInstance3D.new()
				ring.name = "TargetRing"
				var ring_mesh = CylinderMesh.new()
				ring_mesh.top_radius = 3.81
				ring_mesh.bottom_radius = 3.81
				ring_mesh.height = 0.01
				ring.mesh = ring_mesh
				
				var ring_mat = StandardMaterial3D.new()
				ring_mat.albedo_color = Color(0.0, 0.8, 1.0, 0.6)
				ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ring.material_override = ring_mat
				ring.position = Vector3(0.0, 0.15, 0.0)
				island_node.add_child(ring)
				
	var target_pos = chipping_island_positions[index]
	aim_target_pos = target_pos
	if has_node("AimMarker"):
		$AimMarker.global_position = aim_target_pos
		
	if has_node("Player") and $Player.ball != null:
		var diff = aim_target_pos - $Player.ball.spawn_position
		var angle_rad = atan2(diff.z, diff.x)
		$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
		
		var yaw_rad = -angle_rad
		var cam_pos = get_address_camera_position($Player.ball.spawn_position, yaw_rad, false)
		var target_look = get_camera_target_look(aim_target_pos, $Player.ball.spawn_position, false)
		if has_node("PhantomCamera3D"):
			$PhantomCamera3D.global_position = cam_pos
			$PhantomCamera3D.look_at(target_look)
		if has_node("Camera3D"):
			$Camera3D.global_position = cam_pos
			$Camera3D.look_at(target_look)
			
	_update_chipping_hud()
	_show_chipping_banner("Target Island: %d Feet Selected" % chipping_distances[index])


func _setup_chipping_hud_ui() -> void:
	if chipping_hud != null:
		chipping_hud.queue_free()
		chipping_hud = null
		
	chipping_hud = CanvasLayer.new()
	chipping_hud.name = "ChippingHUDLayer"
	chipping_hud.layer = 20
	add_child(chipping_hud)
	
	var control = Control.new()
	control.anchors_preset = Control.PRESET_FULL_RECT
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	chipping_hud.add_child(control)
	
	var glass_style = StyleBoxFlat.new()
	glass_style.bg_color = Color(0.04, 0.08, 0.12, 0.85)
	glass_style.border_width_left = 2
	glass_style.border_width_top = 2
	glass_style.border_width_right = 2
	glass_style.border_width_bottom = 2
	glass_style.border_color = Color(0.24, 0.46, 0.72, 0.5)
	glass_style.corner_radius_top_left = 10
	glass_style.corner_radius_top_right = 10
	glass_style.corner_radius_bottom_right = 10
	glass_style.corner_radius_bottom_left = 10
	
	var score_panel = PanelContainer.new()
	score_panel.custom_minimum_size = Vector2(700, 90)
	score_panel.anchor_left = 0.5
	score_panel.anchor_right = 0.5
	score_panel.anchor_top = 0.0
	score_panel.anchor_bottom = 0.0
	score_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_panel.offset_left = -350
	score_panel.offset_right = 350
	score_panel.offset_top = 20
	score_panel.offset_bottom = 110
	control.add_child(score_panel)
	score_panel.add_theme_stylebox_override("panel", glass_style)
	
	var score_margin = MarginContainer.new()
	score_margin.add_theme_constant_override("margin_left", 20)
	score_margin.add_theme_constant_override("margin_right", 20)
	score_panel.add_child(score_margin)
	
	var score_hbox = HBoxContainer.new()
	score_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	score_margin.add_child(score_hbox)
	
	var target_col = VBoxContainer.new()
	target_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(target_col)
	var t_lbl = Label.new()
	t_lbl.text = "ACTIVE TARGET"
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.add_theme_font_size_override("font_size", 14)
	t_lbl.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
	target_col.add_child(t_lbl)
	chipping_target_lbl = Label.new()
	chipping_target_lbl.text = "100 FT"
	chipping_target_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chipping_target_lbl.add_theme_font_size_override("font_size", 28)
	chipping_target_lbl.add_theme_color_override("font_color", Color.WHITE)
	target_col.add_child(chipping_target_lbl)
	
	var attempts_col = VBoxContainer.new()
	attempts_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attempts_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(attempts_col)
	var att_lbl = Label.new()
	att_lbl.text = "ATTEMPTS"
	att_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	att_lbl.add_theme_font_size_override("font_size", 14)
	att_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	attempts_col.add_child(att_lbl)
	chipping_attempts_lbl = Label.new()
	chipping_attempts_lbl.text = "0"
	chipping_attempts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chipping_attempts_lbl.add_theme_font_size_override("font_size", 28)
	chipping_attempts_lbl.add_theme_color_override("font_color", Color.WHITE)
	attempts_col.add_child(chipping_attempts_lbl)
	
	var hits_col = VBoxContainer.new()
	hits_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hits_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(hits_col)
	var h_lbl = Label.new()
	h_lbl.text = "HITS"
	h_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h_lbl.add_theme_font_size_override("font_size", 14)
	h_lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3))
	hits_col.add_child(h_lbl)
	chipping_hits_lbl = Label.new()
	chipping_hits_lbl.text = "0"
	chipping_hits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chipping_hits_lbl.add_theme_font_size_override("font_size", 28)
	chipping_hits_lbl.add_theme_color_override("font_color", Color.WHITE)
	hits_col.add_child(chipping_hits_lbl)
	
	var acc_col = VBoxContainer.new()
	acc_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(acc_col)
	var ac_lbl = Label.new()
	ac_lbl.text = "ACCURACY"
	ac_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ac_lbl.add_theme_font_size_override("font_size", 14)
	ac_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	acc_col.add_child(ac_lbl)
	chipping_accuracy_lbl = Label.new()
	chipping_accuracy_lbl.text = "0%"
	chipping_accuracy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chipping_accuracy_lbl.add_theme_font_size_override("font_size", 28)
	chipping_accuracy_lbl.add_theme_color_override("font_color", Color.WHITE)
	acc_col.add_child(chipping_accuracy_lbl)
	
	var target_panel = PanelContainer.new()
	target_panel.custom_minimum_size = Vector2(220, 400)
	target_panel.anchor_left = 0.0
	target_panel.anchor_top = 0.5
	target_panel.anchor_bottom = 0.5
	target_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	target_panel.offset_left = 20
	target_panel.offset_top = -200
	target_panel.offset_bottom = 200
	control.add_child(target_panel)
	target_panel.add_theme_stylebox_override("panel", glass_style)
	
	var target_margin = MarginContainer.new()
	target_margin.add_theme_constant_override("margin_left", 12)
	target_margin.add_theme_constant_override("margin_right", 12)
	target_margin.add_theme_constant_override("margin_top", 12)
	target_margin.add_theme_constant_override("margin_bottom", 12)
	target_panel.add_child(target_margin)
	
	var target_vbox = VBoxContainer.new()
	target_vbox.add_theme_constant_override("separation", 10)
	target_margin.add_child(target_vbox)
	
	var t_title = Label.new()
	t_title.text = "CHOOSE TARGET"
	t_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_title.add_theme_font_size_override("font_size", 16)
	t_title.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
	target_vbox.add_child(t_title)
	
	chipping_buttons.clear()
	for i in range(chipping_distances.size()):
		var btn = Button.new()
		btn.text = "Target: %d FT" % chipping_distances[i]
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 16)
		_apply_chipping_btn_style(btn, Color(0.12, 0.20, 0.28), Color(0.18, 0.30, 0.42))
		btn.pressed.connect(func(idx=i): _select_chipping_target(idx))
		target_vbox.add_child(btn)
		chipping_buttons.append(btn)
		
	var exit_btn = Button.new()
	exit_btn.text = "Exit Minigame"
	exit_btn.custom_minimum_size = Vector2(0, 50)
	exit_btn.add_theme_font_size_override("font_size", 16)
	_apply_chipping_btn_style(exit_btn, Color(0.36, 0.16, 0.16), Color(0.5, 0.2, 0.2))
	exit_btn.pressed.connect(func():
		GlobalSettings.is_chipping_minigame = false
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null:
			mp_mgr.players.clear()
			mp_mgr.practice_mode_active = false
		SceneManager.change_scene("res://UI/MiniGamesMenu/minigames_menu.tscn")
	)
	target_vbox.add_child(exit_btn)
	
	chipping_banner_lbl = Label.new()
	chipping_banner_lbl.text = "Aim and hit towards the target island green!"
	chipping_banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chipping_banner_lbl.anchor_left = 0.5
	chipping_banner_lbl.anchor_right = 0.5
	chipping_banner_lbl.anchor_top = 0.25
	chipping_banner_lbl.anchor_bottom = 0.25
	chipping_banner_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chipping_banner_lbl.add_theme_font_size_override("font_size", 20)
	chipping_banner_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	chipping_banner_lbl.add_theme_constant_override("outline_size", 5)
	chipping_banner_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	control.add_child(chipping_banner_lbl)
	
	_update_chipping_hud()


func _apply_chipping_btn_style(btn: Button, norm_color: Color, hov_color: Color) -> void:
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = norm_color
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.border_width_left = 1
	style_normal.border_width_top = 1
	style_normal.border_width_right = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(1, 1, 1, 0.15)
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = hov_color
	style_hover.corner_radius_top_left = 6
	style_hover.corner_radius_top_right = 6
	style_hover.corner_radius_bottom_right = 6
	style_hover.corner_radius_bottom_left = 6
	style_hover.border_width_left = 1
	style_hover.border_width_top = 1
	style_hover.border_width_right = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(1, 1, 1, 0.3)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("focus", style_normal)
	btn.add_theme_color_override("font_color", Color.WHITE)
	if btn.custom_minimum_size.y < 48:
		btn.custom_minimum_size.y = 48
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", 16)


func _update_chipping_hud() -> void:
	if not chipping_stats.has(selected_chipping_target_idx):
		return
	var stats = chipping_stats[selected_chipping_target_idx]
	var att = stats["Attempts"]
	var hits = stats["Hits"]
	var acc = 0
	if att > 0:
		acc = int((float(hits) / float(att)) * 100.0)
		
	if chipping_target_lbl:
		chipping_target_lbl.text = "%d FT" % chipping_distances[selected_chipping_target_idx]
	if chipping_attempts_lbl:
		chipping_attempts_lbl.text = str(att)
	if chipping_hits_lbl:
		chipping_hits_lbl.text = str(hits)
	if chipping_accuracy_lbl:
		chipping_accuracy_lbl.text = "%d%%" % acc
		
	for i in range(chipping_buttons.size()):
		if i == selected_chipping_target_idx:
			chipping_buttons[i].add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
		else:
			chipping_buttons[i].remove_theme_color_override("font_color")


func _show_chipping_banner(text: String) -> void:
	if chipping_banner_lbl:
		chipping_banner_lbl.text = text
