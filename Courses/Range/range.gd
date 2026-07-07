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
	"BackSpin": "---",
	"SideSpin": "---",
	"TotalSpin": "---",
	"SpinAxis": "---"
}
var raw_ball_data: Dictionary = {}
var last_display: Dictionary = {}
var is_aerial_view: bool = false
var is_driving_range: bool = false
var aim_target_pos: Vector3 = Vector3(150.0, 0.0, 0.0) # Default target down the range
var aim_line: MeshInstance3D = null

# Dynamic Course Play active hole variables
var current_hole_location: Vector3 = Vector3.ZERO
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
var course_data_dict: Dictionary = {}
var _shot_active: bool = false
var is_sky_view_active: bool = false
var _last_travel_yaw: float = 0.0
var _user_custom_club: String = ""
var _is_updating_auto_club: bool = false


# Visual effects references
var vignette_layer: CanvasLayer = null
var vignette_rect: ColorRect = null
var camera_attributes: CameraAttributesPractical = null


func get_height(x: float, z: float) -> float:
	if is_driving_range:
		return 0.0
	var h = sin(x * 0.01) * cos(z * 0.01) * 1.5 + sin(x * 0.03 + z * 0.02) * 0.5 + cos(x * 0.07 - z * 0.05) * 0.125
	return h


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
		
		# Generate procedural Simplex noise texture for volumetric turf details
		var noise = FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		noise.frequency = 0.4
		
		var noise_tex = NoiseTexture2D.new()
		noise_tex.noise = noise
		noise_tex.seamless = true
		
		mat.set_shader_parameter("noise_texture", noise_tex)
		mat.set_shader_parameter("layers", 16)
		mat.set_shader_parameter("depth_scale", 0.12) # medium rough/meadow height
		mat.set_shader_parameter("depth_strength", 0.4)
		mat.set_shader_parameter("grass_color_tint", Color(0.9, 0.9, 0.9))
		mat.set_shader_parameter("roughness", 0.8)
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
	is_driving_range = (name == "Range" or scene_file_path.contains("range.tscn"))
	if is_driving_range:
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null:
			mp_mgr.players.clear()
		_generate_ground_terrain()
	# Initialize Camera3DResource on PhantomCamera3D for dynamic fov/far changes
	if has_node("PhantomCamera3D"):
		var pcam = $PhantomCamera3D
		if pcam.camera_3d_resource == null:
			var res_script = load("res://addons/phantom_camera/scripts/resources/camera_3d_resource.gd")
			if res_script:
				pcam.camera_3d_resource = res_script.new()

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
			
	# Visual effects setup
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
	if ("/root/LaunchMonitorManager"):
		var launch_monitor = get_node("/root/LaunchMonitorManager")
		if not launch_monitor.hit_ball.is_connected(_on_launch_monitor_hit_ball):
			launch_monitor.hit_ball.connect(_on_launch_monitor_hit_ball)
	var is_practice_mode_primed: bool = GlobalSettings.practice_mode_primed
	if is_practice_mode_primed:
		practice_mode_active = true
		GlobalSettings.practice_mode_primed = false
	if has_node("Camera3D"):
		$Camera3D.cull_mask = $Camera3D.cull_mask & ~2
	if has_node("PhantomCamera3D"):
		$PhantomCamera3D.cull_mask = $PhantomCamera3D.cull_mask & ~2

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
		aerial_cam.size = 300.0
		aerial_cam.position = Vector3(0, 150, 0)
		aerial_cam.rotation = Vector3(-PI/2, 0, 0) # Look straight down
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
	add_child(canvas)

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
	badge.offset_left = -120
	badge.offset_top = 20
	badge.offset_right = 120
	badge.offset_bottom = 60
	canvas.add_child(badge)

	# Create AimDistanceLabel (path remains MapCanvas/AimDistanceLabel!)
	var aim_lbl = Label.new()
	aim_lbl.name = "AimDistanceLabel"
	aim_lbl.text = "Aim Distance: ---"
	aim_lbl.add_theme_font_size_override("font_size", 18)
	aim_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	aim_lbl.anchor_left = 0.5
	aim_lbl.anchor_right = 0.5
	aim_lbl.offset_left = -120
	aim_lbl.offset_top = 20
	aim_lbl.offset_right = 120
	aim_lbl.offset_bottom = 60
	aim_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	aim_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	aim_lbl.visible = true
	canvas.add_child(aim_lbl)

	# Create labels inside MapCanvas
	var hole_lbl = Label.new()
	hole_lbl.name = "HoleInfoLabel"
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
					load_practice_hole(0)
					set_practice_mode(true)
				else:
					var hole_info_data = course_data_dict.get("Hole Info", {})
					var hole_keys = hole_info_data.keys()
					hole_keys.sort()
					if not hole_keys.is_empty():
						var first_hole = hole_info_data[hole_keys[0]]
						var tee_boxes = first_hole.get("Tee Boxes", {})
						var tee_pos = tee_boxes.get("Blue")
						if tee_pos == null:
							for k in tee_boxes.keys():
								tee_pos = tee_boxes[k]
								break
						if tee_pos != null:
							var spawn_pos = Vector3(tee_pos[0], get_height(tee_pos[0], tee_pos[1]) + 0.02, tee_pos[1])
							practice_start_pos = spawn_pos
							if has_node("Player") and $Player.ball != null:
								$Player.ball.spawn_position = spawn_pos
								$Player.ball.reset()
								
							# Default aim towards green/pin of Hole 1
							var hole_loc = first_hole.get("Hole Location")
							var par = first_hole.get("Par", 4)
							var hole_name = first_hole.get("Name", "Hole 1")
							
							current_hole_name = hole_name
							current_hole_par = par
							
							if hole_loc != null:
								current_hole_location = Vector3(hole_loc[0], get_height(hole_loc[0], hole_loc[1]), hole_loc[1])
								aim_target_pos = current_hole_location
								update_dof_focus()
								if has_node("AimMarker"):
									$AimMarker.global_position = aim_target_pos
								
								var diff = aim_target_pos - spawn_pos
								var angle_rad = atan2(diff.z, diff.x)
								if has_node("Player") and $Player.ball != null:
									$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
									
								var dist_m = spawn_pos.distance_to(aim_target_pos)
								var dist_yards = int(dist_m * 1.09361)
								current_hole_tee_dist_yards = dist_yards
								hole_lbl.text = "%s | Par %d | %d Yards | Ball: %d Yards to Pin" % [hole_name, par, dist_yards, dist_yards]
								aim_lbl.text = "Aim: %d Yards" % dist_yards
								
								# Immediately rotate/position player cameras to face the hole on startup
								var yaw_rad = -angle_rad
								var local_offset = get_camera_local_offset().rotated(Vector3.UP, yaw_rad)
								var cam_pos = clamp_camera_position(spawn_pos + local_offset)
								if has_node("PhantomCamera3D"):
									$PhantomCamera3D.global_position = cam_pos
									$PhantomCamera3D.look_at(aim_target_pos + Vector3.UP * 0.5)
								if has_node("Camera3D"):
									$Camera3D.global_position = cam_pos
									$Camera3D.look_at(aim_target_pos + Vector3.UP * 0.5)
									
								# Spawn 3D FlagPin at hole center dynamically
								_spawn_flag_pin()
								
							print("[CoursePlay] Player positioned at Hole 1 Tee: ", spawn_pos, " | Aiming at green: ", aim_target_pos)

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
			
	if range_ui != null and range_ui.has_signal("set_session"):
		if not range_ui.is_connected("set_session", Callable(self, "_on_player_changed")):
			range_ui.connect("set_session", Callable(self, "_on_player_changed"))
			
	_update_averages()


var practice_mode_active: bool = false
var practice_start_pos: Vector3 = Vector3(0.0, 0.02, 0.0)
var current_practice_hole_index: int = 0
var place_ball_mode: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset"):
		_reset_display_data()
		$RangeUI.set_data(display_data)

	# Keyboard shortcuts for map toggle
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M:
			_on_map_button_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and is_aerial_view:
			_on_map_button_pressed()
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			is_mouse_down_on_map = true
			is_dragging_map = false
			map_drag_start_pos = event.position
			total_map_drag_dist = 0.0
			if is_aerial_view:
				get_viewport().set_input_as_handled()
		else:
			if is_mouse_down_on_map:
				is_mouse_down_on_map = false
				var was_dragging = is_dragging_map
				is_dragging_map = false
				if is_aerial_view:
					get_viewport().set_input_as_handled()
				if not was_dragging:
					if is_aerial_view:
						if practice_mode_active and place_ball_mode and event.button_index == MOUSE_BUTTON_LEFT:
							_perform_practice_teleport(event.position)
						else:
							_perform_map_click_aim(event.position)
					else:
						_perform_map_click_aim(event.position)
	elif event is InputEventMouseMotion and is_mouse_down_on_map:
		var drag_dist = event.relative.length()
		total_map_drag_dist += drag_dist
		if total_map_drag_dist > 5.0 or is_dragging_map:
			is_dragging_map = true
			if is_aerial_view:
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
			# Set aim target
			aim_target_pos = clicked_point
			aim_target_pos.y = get_height(clicked_point.x, clicked_point.z)
			update_dof_focus()
			if has_node("AimMarker"):
				$AimMarker.global_position = aim_target_pos
			
			# Calculate angle from ball to clicked target point
			var ball_pos = $Player.ball.global_position
			var diff = clicked_point - ball_pos
			var angle_rad = atan2(diff.z, diff.x)
			
			# Set aim offset in player's ball (so physical shots align to this angle!)
			$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
			print("[Aim] Aim target set to: ", clicked_point, " | Yaw offset: ", $Player.ball.aim_yaw_offset_deg)
			
			if has_node("MapCanvas/AimDistanceLabel"):
				var dist_yards = int(ball_pos.distance_to(aim_target_pos) * 1.09361)
				$MapCanvas/AimDistanceLabel.text = "Aim: %d Yards" % dist_yards
			update_auto_club(true)

			# Immediately position/rotate the PhantomCamera3D and Camera3D to face the target!
			var local_offset = get_camera_local_offset().rotated(Vector3.UP, -angle_rad)
			var cam_pos = clamp_camera_position(ball_pos + local_offset)
			if has_node("PhantomCamera3D"):
				$PhantomCamera3D.global_position = cam_pos
				$PhantomCamera3D.look_at(aim_target_pos + Vector3.UP * 0.5)
			if has_node("Camera3D"):
				$Camera3D.global_position = cam_pos
				$Camera3D.look_at(aim_target_pos + Vector3.UP * 0.5)


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
			clicked_point.y = get_height(clicked_point.x, clicked_point.z) + 0.02
			practice_start_pos = clicked_point
			$Player.ball.spawn_position = clicked_point
			$Player.ball.reset()
			print("[PracticeMode] Ball spawned at: ", clicked_point)
			
			# Automatically aim at the pin and position the camera behind the ball
			if not current_hole_location.is_zero_approx():
				aim_target_pos = current_hole_location
				update_dof_focus()
				if has_node("AimMarker"):
					$AimMarker.global_position = aim_target_pos
					
				var diff = current_hole_location - clicked_point
				var angle_rad = atan2(diff.z, diff.x)
				$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
				
				if has_node("MapCanvas/AimDistanceLabel"):
					$MapCanvas/AimDistanceLabel.text = "Aim: %d Yards" % int(clicked_point.distance_to(current_hole_location) * 1.09361)
					
				_update_hole_info_label(true)
				
				if not is_aerial_view:
					var yaw_rad = -angle_rad
					var local_offset = get_camera_local_offset().rotated(Vector3.UP, yaw_rad)
					var cam_pos = clamp_camera_position(clicked_point + local_offset)
					if has_node("PhantomCamera3D"):
						$PhantomCamera3D.global_position = cam_pos
						$PhantomCamera3D.look_at(current_hole_location + Vector3.UP * 0.5)
					if has_node("Camera3D"):
						$Camera3D.global_position = cam_pos
						$Camera3D.look_at(current_hole_location + Vector3.UP * 0.5)


func _on_tcp_client_hit_ball(data: Dictionary) -> void:
	if has_node("Player"):
		$Player._on_tcp_client_hit_ball(data)
		
	raw_ball_data = data.duplicate()
	_update_ball_display()
	_on_shot_initiated()

	# Re-enable camera follow if the setting is on
	if GlobalSettings.range_settings.camera_follow_mode.value:
		call_deferred("set_camera_follow_mode", true)


func _on_launch_monitor_hit_ball(data: Dictionary) -> void:
	_on_tcp_client_hit_ball(data)


func _process(_delta: float) -> void:
	# Refresh UI during flight/rollout so carry/apex update live; distance updates only at rest.
	var player = $Player
	if player.get_ball_state() != PhysicsEnums.BallState.REST:
		_update_ball_display()
		
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
		
		var dist = ball_pos.distance_to(hole_pos)
		var target_size = clamp(dist * 1.43, 100.0, 400.0)
		$AerialCamera.size = target_size
		
		# Orientation: local up (Y column of basis) points from ball to hole, local -Z points straight down
		var right_vec = dir_3d.cross(Vector3.UP).normalized()
		var up_vec = dir_3d
		var back_vec = Vector3.UP
		$AerialCamera.global_transform.basis = Basis(right_vec, up_vec, back_vec)
		
		# Position: offset towards the hole by 0.35 * target_size so ball is on the south side
		var base_pos = ball_pos + dir_3d * (0.35 * target_size)
		$AerialCamera.global_position = Vector3(base_pos.x, 150.0, base_pos.z) + aerial_cam_user_offset

	# Draw/update the aim line connecting the player's ball to the aim marker
	if aim_line and $Player and $Player.ball:
		var imm: ImmediateMesh = aim_line.mesh
		imm.clear_surfaces()
		
		var has_minimap = not MultiplayerManager.players.is_empty()
		var ball_at_rest = $Player.get_ball_state() == PhysicsEnums.BallState.REST
		# Draw the line when the map is active or when the minimap is active and ball is at rest
		if is_aerial_view or (has_minimap and ball_at_rest):
			aim_line.visible = true
			imm.surface_begin(Mesh.PRIMITIVE_LINES)
			var start_pt = $Player.ball.global_position + Vector3(0, 0.2, 0)
			var end_pt = aim_target_pos + Vector3(0, 0.2, 0)
			
			imm.surface_add_vertex(start_pt)
			imm.surface_add_vertex(end_pt)
			imm.surface_end()
		else:
			aim_line.visible = false

	# Update player marker position and aim distance display dynamically
	if has_node("PlayerMarker") and $Player and $Player.ball:
		$PlayerMarker.global_position = $Player.ball.global_position
		
		var has_minimap = not MultiplayerManager.players.is_empty()
		$PlayerMarker.visible = is_aerial_view or has_minimap
		if has_node("AimMarker"):
			$AimMarker.visible = is_aerial_view or has_minimap
		if has_node("PinMarker"):
			$PinMarker.visible = is_aerial_view or has_minimap
		
		if is_aerial_view:
			var dist_to_target = $Player.ball.global_position.distance_to(aim_target_pos) * 1.09361
			if has_node("MapCanvas/AimDistanceLabel"):
				$MapCanvas/AimDistanceLabel.text = "Aim: %d Yards" % round(dist_to_target)


var shot_history: Array[Dictionary] = []


func _on_golf_ball_rest(_ball_data) -> void:
	_shot_active = false
	raw_ball_data = _ball_data.duplicate()
	_update_ball_display()
	
	# Add valid shots to history to compute average stats
	if raw_ball_data.get("Speed", 0.0) > 0.0:
		var p_name = _get_current_player_name()
		var club_name = _get_current_club()
		raw_ball_data["player"] = p_name
		raw_ball_data["club"] = club_name
		shot_history.append(raw_ball_data.duplicate())
		_record_global_shot(p_name, club_name, raw_ball_data)
		_update_averages()

	# Announce shot
	var is_dynamic_course = not current_hole_location.is_zero_approx()
	var ball_pos: Vector3 = $Player.ball.global_position

	var ball = $Player.ball
	if ball.is_in_water:
		print("[range.gd] Ball landed in water hazard!")
		# 1. Find closest point on water polygon boundary
		var water_col = ball.water_collider
		var recovery_pos: Vector3 = ball_pos
		if water_col != null and water_col.has_meta("water_points"):
			var poly_points = water_col.get_meta("water_points")
			if poly_points.size() > 0:
				var ball_pos_2d = Vector2(ball_pos.x, ball_pos.z)
				var closest_pt_2d = get_closest_point_on_polygon(ball_pos_2d, poly_points)
				var away_dir = (closest_pt_2d - ball_pos_2d).normalized()
				if away_dir.is_zero_approx():
					var pin_pos_2d = Vector2(current_hole_location.x, current_hole_location.z)
					away_dir = (ball_pos_2d - pin_pos_2d).normalized()
					if away_dir.is_zero_approx():
						away_dir = Vector2.UP
				
				var rec_pos_2d = closest_pt_2d + away_dir * 0.3048 # 1 ft away
				var h = get_height(rec_pos_2d.x, rec_pos_2d.y)
				recovery_pos = Vector3(rec_pos_2d.x, h + 0.02, rec_pos_2d.y)
		
		# 2. Update ball position and spawn position
		ball.global_position = recovery_pos
		ball.spawn_position = recovery_pos
		ball.position = recovery_pos
		ball_pos = recovery_pos
		
		# 3. Add penalty stroke to active player
		if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
			var mp_mgr = get_node("/root/MultiplayerManager")
			var active_player = mp_mgr.get_active_player()
			active_player["strokes"] += 1
			active_player["total_strokes"] += 1
			active_player["last_shot_penalty"] = 1
			print("[range.gd] Water hazard penalty applied: +1 stroke to %s" % active_player["name"])

	if is_dynamic_course and not practice_mode_active:
		$Player.ball.spawn_position = ball_pos

	if has_node("/root/AnnouncerEngine") and not raw_ball_data.is_empty():
		var announcer = get_node("/root/AnnouncerEngine")
		var pin_dist := 999.0
		var target_pin = current_hole_location if is_dynamic_course else Vector3(150.0, ball_pos.y, 0.0)
		pin_dist = ball_pos.distance_to(target_pin) * 1.09361 # yards
		announcer.call("EvaluateShot", raw_ball_data, $Player.ball.surface_type, pin_dist)

	# Record multiplayer shot
	if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
		get_node("/root/MultiplayerManager").record_shot($Player.ball.position, raw_ball_data)

	if is_dynamic_course:
		if practice_mode_active:
			var reset_delay = GlobalSettings.range_settings.ball_reset_timer.value
			await get_tree().create_timer(reset_delay).timeout
			
			if GlobalSettings.range_settings.auto_ball_reset.value:
				_reset_display_data()
				if has_node("RangeUI"):
					$RangeUI.set_data(display_data)
				
			var saved_yaw = $Player.ball.aim_yaw_offset_deg
			
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				var active_player = mp_mgr.get_active_player()
				if not active_player.is_empty():
					active_player["position"] = practice_start_pos
			
			if GlobalSettings.range_settings.camera_follow_mode.value:
				reset_camera_to_start()
			else:
				$Player.reset_ball()
				$Player.ball.aim_yaw_offset_deg = saved_yaw
				
			_update_hole_info_label(true)
			return
		else:
			# Wait for the ball reset delay so the player can watch the ball finish rolling
			var reset_delay = GlobalSettings.range_settings.ball_reset_timer.value
			await get_tree().create_timer(reset_delay).timeout
			
			# Reset ball physics state and clear tracers
			$Player.reset_ball()
			
			# Update labels
			_update_hole_info_label(true)
			
			# Automatically reset player's aim target to the green center (the pin)
			aim_target_pos = current_hole_location
			update_dof_focus()
			if has_node("AimMarker"):
				$AimMarker.global_position = aim_target_pos
				
			# Calculate angle from new ball position to pin
			var diff = current_hole_location - ball_pos
			var angle_rad = atan2(diff.z, diff.x)
			$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
			
			# Update aim distance display
			if has_node("MapCanvas/AimDistanceLabel"):
				$MapCanvas/AimDistanceLabel.text = "Aim: %d Yards" % int(ball_pos.distance_to(current_hole_location) * 1.09361)
	
			# Position camera behind the ball facing the pin
			var yaw_rad = -angle_rad
			var local_offset = get_camera_local_offset().rotated(Vector3.UP, yaw_rad)
			var start_pos = clamp_camera_position(ball_pos + local_offset)
			
			# Position cameras
			if has_node("PhantomCamera3D"):
				$PhantomCamera3D.global_position = start_pos
				$PhantomCamera3D.look_at(current_hole_location + Vector3.UP * 0.5)
			if has_node("Camera3D"):
				$Camera3D.global_position = start_pos
				$Camera3D.look_at(current_hole_location + Vector3.UP * 0.5)
	
			# Make sure follow mode is disabled so camera stays behind the ball
			set_camera_follow_mode(false)
			
			_user_custom_club = ""
			update_auto_club()
			print("[CoursePlay] Ball at rest. Spawn position updated. Ready for next shot.")
			
			var mp_mgr = get_node_or_null("/root/MultiplayerManager")
			if mp_mgr != null and not mp_mgr.players.is_empty():
				mp_mgr.select_next_player()
				
			return


	# Return camera/ball to starting position for driving range
	var reset_delay = GlobalSettings.range_settings.ball_reset_timer.value
	await get_tree().create_timer(reset_delay).timeout
	
	if GlobalSettings.range_settings.auto_ball_reset.value:
		_reset_display_data()
		$RangeUI.set_data(display_data)
		
	var saved_yaw = $Player.ball.aim_yaw_offset_deg
	
	if GlobalSettings.range_settings.camera_follow_mode.value:
		reset_camera_to_start()
	else:
		$Player.reset_ball()
		$Player.ball.aim_yaw_offset_deg = saved_yaw
		
	_user_custom_club = ""
	update_auto_club()
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
		sum_offline += absf(float(shot.get("SideDistance", 0.0)))
		
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
	var camera = $PhantomCamera3D
	if camera == null:
		return

	if value and has_node("Player") and $Player.ball != null and _shot_active:
		camera.follow_mode = PhantomCamera3D.FollowMode.SIMPLE
		var player = $Player
		camera.follow_target = player.ball
		
		# Rotate offset behind the ball in the direction the ball is travelling from the start position
		var yaw_rad = -atan2(player.ball.shot_dir.z, player.ball.shot_dir.x)
		_last_travel_yaw = yaw_rad
		
		# Check if putting to determine camera configuration
		if player.ball.is_putt:
			# For putts, keep the camera as the player camera view just following the ball,
			# instead of switching to the sky view logic.
			update_camera_fov(GlobalSettings.range_settings.camera_fov.value)
			var cam_dist = GlobalSettings.range_settings.camera_distance.value
			var cam_height = GlobalSettings.range_settings.camera_height.value
			var local_offset = Vector3(-cam_dist, cam_height, 0).rotated(Vector3.UP, yaw_rad)
			camera.follow_offset = local_offset
		else:
			# Set to sky view FOV during follow mode
			update_camera_fov(30.0)
			
			# Follow mode always uses sky view settings: distance 50, height 15
			var cam_dist = 50.0
			var cam_height = 15.0
			var local_offset = Vector3(-cam_dist, cam_height, 0).rotated(Vector3.UP, yaw_rad)
			camera.follow_offset = local_offset
		
		# Rotate camera to look directly at the ball
		camera.look_at_mode = PhantomCamera3D.LookAtMode.SIMPLE
		camera.look_at_target = player.ball
	else:
		camera.follow_mode = PhantomCamera3D.FollowMode.NONE
		camera.look_at_mode = PhantomCamera3D.LookAtMode.NONE
		update_camera_fov(GlobalSettings.range_settings.camera_fov.value)

func reset_camera_to_start() -> void:
	_shot_active = false
	var camera = $PhantomCamera3D

	# Disable follow mode and restore default view settings/FOV
	set_camera_follow_mode(false)

	# Calculate offset behind the ball in the direction we are aiming
	var saved_yaw = $Player.ball.aim_yaw_offset_deg
	var yaw_rad = deg_to_rad(-saved_yaw)
	var local_offset = get_camera_local_offset().rotated(Vector3.UP, yaw_rad)
	var start_pos = clamp_camera_position($Player.ball.spawn_position + local_offset)

	# Tween camera back to starting position
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(camera, "global_position", start_pos, 1.5)

	# Rotate camera to face the aim target
	camera.look_at_from_position(start_pos, aim_target_pos + Vector3.UP * 0.5)

	await tween.finished

	# Reset ball to starting position
	var player = $Player
	if player != null:
		player.reset_ball()
		player.ball.aim_yaw_offset_deg = saved_yaw


func _on_range_ui_hit_shot(data: Dictionary) -> void:
	if has_node("Player"):
		$Player._on_range_ui_hit_shot(data)
		
	# For local injected shots, prime the display immediately with the payload data.
	raw_ball_data = data.duplicate()
	_update_ball_display()
	_on_shot_initiated()

	# Re-enable camera follow if the setting is on
	if GlobalSettings.range_settings.camera_follow_mode.value:
		call_deferred("set_camera_follow_mode", true)


func _on_player_manual_hit() -> void:
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


func _update_ball_display() -> void:
	# Show distance continuously (updates during flight/rollout, final at rest)
	var player = $Player
	var show_distance: bool = true
	display_data = ShotFormatter.format_ball_display(raw_ball_data, player, GlobalSettings.range_settings.range_units.value, show_distance, display_data)
	last_display = display_data.duplicate()
	$RangeUI.set_data(display_data)


func set_practice_mode(enabled: bool) -> void:
	practice_mode_active = enabled
	practice_start_pos = $Player.ball.position


func _on_range_ui_reset_practice_clicked() -> void:
	$Player.ball.spawn_position = practice_start_pos
	$Player.ball.reset()


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
		var spawn_pos = Vector3(tee_pos[0], get_height(tee_pos[0], tee_pos[1]) + 0.02, tee_pos[1])
		practice_start_pos = spawn_pos
		if has_node("Player") and $Player.ball != null:
			$Player.ball.spawn_position = spawn_pos
			$Player.reset_ball()
			
		var hole_loc = hole_data.get("Hole Location")
		var par = hole_data.get("Par", 4)
		var hole_name = hole_data.get("Name", hole_key)
		
		current_hole_name = hole_name
		current_hole_par = par
		shot_count = 0
		
		if hole_loc != null:
			current_hole_location = Vector3(hole_loc[0], get_height(hole_loc[0], hole_loc[1]), hole_loc[1])
			aim_target_pos = current_hole_location
		
		# Update MultiplayerManager if active
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty():
			mp_mgr.current_hole_index = idx
			var active_player = mp_mgr.get_active_player()
			if not active_player.is_empty():
				active_player["position"] = spawn_pos
				active_player["strokes"] = 0
				active_player["shot_history"].clear()
				# Emit active_player_changed so course_play HUD updates hole and score
				mp_mgr.emit_signal("active_player_changed", active_player)
		
		if hole_loc != null:
			update_dof_focus()
			if has_node("AimMarker"):
				$AimMarker.global_position = aim_target_pos
				
			var diff = aim_target_pos - spawn_pos
			var angle_rad = atan2(diff.z, diff.x)
			if has_node("Player") and $Player.ball != null:
				$Player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
				
			var dist_m = spawn_pos.distance_to(aim_target_pos)
			var dist_yards = int(dist_m * 1.09361)
			current_hole_tee_dist_yards = dist_yards
			
			_update_hole_info_label(true)
			if has_node("MapCanvas/AimDistanceLabel"):
				$MapCanvas/AimDistanceLabel.text = "Aim: %d Yards" % dist_yards
				
			# Rotate/position cameras to face the hole
			var yaw_rad = -angle_rad
			var local_offset = get_camera_local_offset().rotated(Vector3.UP, yaw_rad)
			var cam_pos = clamp_camera_position(spawn_pos + local_offset)
			if has_node("PhantomCamera3D"):
				$PhantomCamera3D.global_position = cam_pos
				$PhantomCamera3D.look_at(aim_target_pos + Vector3.UP * 0.5)
			if has_node("Camera3D"):
				$Camera3D.global_position = cam_pos
				$Camera3D.look_at(aim_target_pos + Vector3.UP * 0.5)
				
			# Spawn 3D FlagPin at hole center dynamically
			_spawn_flag_pin()
			
			# Force update outline
			update_hole_outline()
			
		print("[PracticeMode] Loaded hole ", idx, " (", hole_name, ")")


func next_practice_hole() -> void:
	load_practice_hole(current_practice_hole_index + 1)


func prev_practice_hole() -> void:
	load_practice_hole(current_practice_hole_index - 1)


func _on_map_button_pressed() -> void:
	is_aerial_view = !is_aerial_view
	
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
	var has_minimap = not MultiplayerManager.players.is_empty()
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
			
			var dist = ball_pos.distance_to(hole_pos)
			var target_size = clamp(dist * 1.43, 100.0, 400.0)
			$AerialCamera.size = target_size
			
			# Orientation
			var right_vec = dir_3d.cross(Vector3.UP).normalized()
			var up_vec = dir_3d
			var back_vec = Vector3.UP
			$AerialCamera.global_transform.basis = Basis(right_vec, up_vec, back_vec)
			
			# Position
			var base_pos = ball_pos + dir_3d * (0.35 * target_size)
			$AerialCamera.global_position = Vector3(base_pos.x, 150.0, base_pos.z)
			$AerialCamera.make_current()
			
		update_hole_outline()
		print("[Map] Switched to Aerial View")
	else:
		# Switch back to the main camera
		if has_node("Camera3D"):
			$Camera3D.make_current()
		update_hole_outline()
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
	add_child(pin_marker)
	pin_marker.global_position = current_hole_location
	var has_minimap = not MultiplayerManager.players.is_empty()
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
	
	# Cup / hole circle on ground: small flat white cylinder
	var cup = MeshInstance3D.new()
	cup.name = "Cup"
	var cup_mesh = CylinderMesh.new()
	cup_mesh.top_radius = 0.0762 # 6in diameter / 2 = 3in = 0.0762m
	cup_mesh.bottom_radius = 0.0762
	cup_mesh.height = 0.002
	cup.mesh = cup_mesh
	var cup_mat = StandardMaterial3D.new()
	cup_mat.albedo_color = Color.WHITE
	cup_mat.roughness = 1.0
	cup.material_override = cup_mat
	cup.position = Vector3(0, 0.001, 0)
	pin.add_child(cup)
	
	print("[CoursePlay] FlagPin and PinMarker spawned at: ", current_hole_location)
	update_gimme_circles()


func _on_shot_initiated() -> void:
	_shot_active = true
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
		
	var dist_yards: int = 0
	if ball_is_at_rest:
		var dist_m = $Player.ball.global_position.distance_to(current_hole_location)
		dist_yards = int(dist_m * 1.09361)
	else:
		var dist_m = $Player.ball.spawn_position.distance_to(current_hole_location)
		dist_yards = int(dist_m * 1.09361)
		
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
	
	var has_minimap = not MultiplayerManager.players.is_empty()
	
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
	var outer_vertices = get_path_buffer_polygon(path_pts, 35.0)
	var inner_vertices = get_path_buffer_polygon(path_pts, 33.5)
	
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
	var m_outer_vertices = get_path_buffer_polygon(path_pts, 37.5)
	var m_inner_vertices = get_path_buffer_polygon(path_pts, 32.5)
	
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


func get_active_hole_config() -> Dictionary:
	if has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty():
		var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index]
		return MultiplayerManager.hole_info.get(hole_id, {})
		
	if not course_data_dict.is_empty():
		var hole_info_data = course_data_dict.get("Hole Info", {})
		var hole_keys = hole_info_data.keys()
		hole_keys.sort()
		if not hole_keys.is_empty():
			return hole_info_data.get(hole_keys[0], {})
			
	return {}


func toggle_sky_view() -> void:
	is_sky_view_active = !is_sky_view_active
	update_camera_offset()
	if is_sky_view_active:
		update_camera_fov(30.0)
	else:
		update_camera_fov(GlobalSettings.range_settings.camera_fov.value)


func get_camera_local_offset() -> Vector3:
	var cam_dist = 50.0 if is_sky_view_active else GlobalSettings.range_settings.camera_distance.value
	var cam_height = 15.0 if is_sky_view_active else GlobalSettings.range_settings.camera_height.value
	return Vector3(-cam_dist, cam_height, 0)


func update_camera_offset(_val = null) -> void:
	var offset = get_camera_local_offset()
	if has_node("PhantomCamera3D"):
		$PhantomCamera3D.follow_offset = offset
		
	# If ball is available and we are not in follow mode, position manually
	if has_node("Player") and $Player.ball != null:
		if has_node("PhantomCamera3D") and $PhantomCamera3D.follow_mode == PhantomCamera3D.FollowMode.NONE:
			var yaw_rad = deg_to_rad(-$Player.ball.aim_yaw_offset_deg)
			var local_offset = offset.rotated(Vector3.UP, yaw_rad)
			var cam_pos = clamp_camera_position($Player.ball.global_position + local_offset)
			$PhantomCamera3D.global_position = cam_pos
			$PhantomCamera3D.look_at(aim_target_pos + Vector3.UP * 0.5)
			if has_node("Camera3D"):
				$Camera3D.global_position = cam_pos
				$Camera3D.look_at(aim_target_pos + Vector3.UP * 0.5)


func update_camera_fov(value: float) -> void:
	var fov_val = 30.0 if is_sky_view_active else value
	if has_node("PhantomCamera3D") and $PhantomCamera3D.camera_3d_resource != null:
		$PhantomCamera3D.camera_3d_resource.fov = fov_val
	if has_node("Camera3D"):
		$Camera3D.fov = fov_val


func update_camera_far(value: float) -> void:
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
	if is_driving_range:
		# Clear fog and clouds for driving range to make the ball easy to see
		skydome.fog_density = 0.0
		skydome.clouds_visible = false
		skydome.clouds_cumulus_visible = false
		print("[VisualFX] Fog and clouds disabled for maximum range visibility")
	else:
		# Restore original sky settings for dynamic courses
		skydome.fog_density = 0.001
		skydome.fog_end = 600.0
		skydome.fog_start = 0.0
		skydome.clouds_visible = true
		skydome.clouds_cumulus_visible = true


func clamp_camera_position(pos: Vector3) -> Vector3:
	var terrain_h = get_height(pos.x, pos.z)
	if pos.y < terrain_h + 1.0:
		pos.y = terrain_h + 1.0
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
	var dist_1_yards = GlobalSettings.range_settings.gimme_range_1_distance.value
	var dist_1_meters = dist_1_yards * 0.9144
	
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
	var dist_2_yards = GlobalSettings.range_settings.gimme_range_2_distance.value
	var dist_2_meters = dist_2_yards * 0.9144
	
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


func get_closest_point_on_segment(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab = b - a
	var ap = p - a
	var ab_len_sq = ab.length_squared()
	if ab_len_sq < 0.00001:
		return a
	var t = ap.dot(ab) / ab_len_sq
	t = clamp(t, 0.0, 1.0)
	return a + t * ab

func get_closest_point_on_polygon(p: Vector2, poly: Array) -> Vector2:
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


func update_auto_club(force_auto: bool = false) -> void:
	if _shot_active:
		return
	if current_hole_location.is_zero_approx():
		return
	if not has_node("Player") or $Player.ball == null:
		return
		
	var selected_club = ""
	
	if _user_custom_club != "" and not force_auto:
		selected_club = _user_custom_club
	else:
		var ball_pos = $Player.ball.global_position
		# Remaining distance to the target/aim point in yards
		var dist_m = ball_pos.distance_to(aim_target_pos)
		var dist_yards = int(dist_m * 1.09361)
		
		# Determine if ball is on the green (PhysicsEnums.SurfaceType.GREEN is 4)
		var is_on_green = ($Player.ball.surface_type == PhysicsEnums.SurfaceType.GREEN)
		
		# Determine if we are in the teebox (shot_count/strokes == 0)
		var is_in_teebox = false
		var mp_mgr = get_node_or_null("/root/MultiplayerManager")
		if mp_mgr != null and not mp_mgr.players.is_empty():
			var active_p = mp_mgr.get_active_player()
			if not active_p.is_empty():
				is_in_teebox = (active_p["strokes"] == 0)
		else:
			is_in_teebox = (shot_count == 0)
		
		# Rule 1: Green check
		if is_on_green:
			selected_club = "Pt"
		# Rule 2: Teebox driver check
		elif is_in_teebox and dist_yards > 200:
			selected_club = "Dr"
		# Rule 3: Otherwise select based on distance (never driver)
		else:
			if dist_yards >= 225:
				selected_club = "3w"
			elif dist_yards >= 210: # 210-224
				selected_club = "5w"
			elif dist_yards >= 195: # 195-209
				selected_club = "4i"
			elif dist_yards >= 180: # 180-194
				selected_club = "5i"
			elif dist_yards >= 160: # 160-179
				selected_club = "6i"
			elif dist_yards >= 140: # 140-159
				selected_club = "7i"
			elif dist_yards >= 130: # 130-139
				selected_club = "8i"
			elif dist_yards >= 120: # 120-129
				selected_club = "9i"
			elif dist_yards >= 100: # 100-119
				selected_club = "Pw"
			elif dist_yards >= 20:  # 20-99
				selected_club = "Sw"
			else:                   # 0-19
				selected_club = "Pt"

	# Find ClubSelector UI node and select club
	var club_sel = get_club_selector()
	if club_sel != null and club_sel.has_method("select_club_by_name"):
		_is_updating_auto_club = true
		club_sel.select_club_by_name(selected_club)
		_is_updating_auto_club = false


func _spawn_driving_range_elements() -> void:
	# Hide old center line and yard markers
	if has_node("CenterLine"):
		$CenterLine.visible = false
	if has_node("YardMarkers"):
		for child in $YardMarkers.get_children():
			child.queue_free()

	_spawn_boundary_walls()
	
	# Spawn boards and lines at 50, 100, 150, 200, 250, 300, 350, 400, 450, 500 yards
	var yardages = [50.0, 100.0, 150.0, 200.0, 250.0, 300.0, 350.0, 400.0, 450.0, 500.0]
	for yards in yardages:
		_spawn_ground_line(yards)
		
		# Determine evenly spaced staggered Z position for the single board at this yardage
		var stagger_yd := 0.0
		match int(yards):
			50: stagger_yd = -45.0
			100: stagger_yd = -35.0
			150: stagger_yd = -25.0
			200: stagger_yd = -15.0
			250: stagger_yd = -5.0
			300: stagger_yd = 5.0
			350: stagger_yd = 15.0
			400: stagger_yd = 25.0
			450: stagger_yd = 35.0
			500: stagger_yd = 45.0
			_: stagger_yd = 0.0
		var stagger_m = stagger_yd * 0.9144
		_spawn_distance_board(yards, stagger_m)


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
	var board_height = 2.4
	var board_width = 4.5
	var center_y = 2.2
	
	var base_pos = Vector3(x_pos, 0.0, z_pos)
	
	# 1. Create two posts (poles) - placed behind the white box (positive X is behind from player's view at X=0)
	var pole1 = MeshInstance3D.new()
	var pole1_mesh = BoxMesh.new()
	pole1_mesh.size = Vector3(0.12, 3.4, 0.12)
	pole1.mesh = pole1_mesh
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.15, 0.1) # Dark wood
	pole1.material_override = pole_mat
	add_child(pole1)
	pole1.global_position = base_pos + Vector3(0.16, 1.7, -1.2)
	
	var pole2 = MeshInstance3D.new()
	pole2.mesh = pole1_mesh
	pole2.material_override = pole_mat
	add_child(pole2)
	pole2.global_position = base_pos + Vector3(0.16, 1.7, 1.2)
	
	# 2. Create the white outer board frame (box around the yards board)
	var frame = MeshInstance3D.new()
	var frame_mesh = BoxMesh.new()
	frame_mesh.size = Vector3(0.2, board_height + 0.4, board_width + 0.4)
	frame.mesh = frame_mesh
	
	var frame_mat = StandardMaterial3D.new()
	frame_mat.albedo_color = Color(1.0, 1.0, 1.0) # Pure white
	frame_mat.roughness = 0.5
	frame.material_override = frame_mat
	add_child(frame)
	frame.global_position = base_pos + Vector3(0, center_y, 0)
	
	# 3. Create the inner board panel
	var board = MeshInstance3D.new()
	var board_mesh = BoxMesh.new()
	board_mesh.size = Vector3(0.15, board_height, board_width)
	board.mesh = board_mesh
	
	var board_mat = StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.95, 0.95, 0.9) # Warm cream/white
	board.material_override = board_mat
	add_child(board)
	board.global_position = base_pos + Vector3(0, center_y, 0)
	
	# Add static collision shape to board and poles
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.3, 3.4, board_width + 0.4)
	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	board.add_child(static_body)
	
	# 4. Create Label3D on the board front (facing negative X, towards player)
	var label = Label3D.new()
	label.text = "%d\nYDS" % int(yards)
	label.font_size = 90
	label.modulate = Color(0.05, 0.3, 0.1) # Forest green text
	label.outline_modulate = Color(0.9, 0.9, 0.8)
	label.outline_size = 15
	label.double_sided = true
	label.pixel_size = 0.012
	board.add_child(label)
	label.position = Vector3(-0.11, 0.0, 0.0)
	label.rotation_degrees = Vector3(0, -90, 0)
	
	# 5. Create Label3D on the board back (facing positive X)
	var label_back = Label3D.new()
	label_back.text = "%d\nYDS" % int(yards)
	label_back.font_size = 90
	label_back.modulate = Color(0.05, 0.3, 0.1)
	label_back.outline_modulate = Color(0.9, 0.9, 0.8)
	label_back.outline_size = 15
	label_back.double_sided = true
	label_back.pixel_size = 0.012
	board.add_child(label_back)
	label_back.position = Vector3(0.11, 0.0, 0.0)
	label_back.rotation_degrees = Vector3(0, 90, 0)

	# 6. Create flat board for aerial/minimap views (layer 2)
	var flat_w = 20.0
	var flat_h = 10.0
	var flat_frame = MeshInstance3D.new()
	var flat_frame_mesh = PlaneMesh.new()
	flat_frame_mesh.size = Vector2(flat_h + 1.0, flat_w + 1.0)
	flat_frame.mesh = flat_frame_mesh
	
	var flat_frame_mat = StandardMaterial3D.new()
	flat_frame_mat.albedo_color = Color(1.0, 1.0, 1.0) # Pure white
	flat_frame_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	flat_frame.material_override = flat_frame_mat
	flat_frame.layers = 2
	add_child(flat_frame)
	flat_frame.global_position = base_pos + Vector3(0, 0.08, 0)
	
	var flat_board = MeshInstance3D.new()
	var flat_mesh = PlaneMesh.new()
	flat_mesh.size = Vector2(flat_h, flat_w)
	flat_board.mesh = flat_mesh
	
	var flat_mat = StandardMaterial3D.new()
	flat_mat.albedo_color = Color(0.95, 0.95, 0.9) # Warm cream/white
	flat_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	flat_board.material_override = flat_mat
	flat_board.layers = 2
	add_child(flat_board)
	flat_board.global_position = base_pos + Vector3(0, 0.09, 0)
	
	var flat_label = Label3D.new()
	flat_label.text = "%d YDS" % int(yards)
	flat_label.font_size = 180
	flat_label.modulate = Color(0.05, 0.3, 0.1) # Forest green text
	flat_label.outline_modulate = Color(0.9, 0.9, 0.8)
	flat_label.outline_size = 15
	flat_label.double_sided = false
	flat_label.pixel_size = 0.04
	flat_label.layers = 2
	flat_board.add_child(flat_label)
	flat_label.position = Vector3(0.0, 0.01, 0.0)
	flat_label.rotation_degrees = Vector3(-90, -90, 0)


func _spawn_ground_line(yards: float) -> void:
	var x_pos = yards * 0.9144
	var line = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(0.4, 457.2)
	line.mesh = plane
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.95, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	line.material_override = mat
	
	add_child(line)
	line.global_position = Vector3(x_pos, 0.01, 0.0)


func _get_current_player_name() -> String:
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty():
		var active_player = mp_mgr.get_active_player()
		if not active_player.is_empty():
			return active_player.get("name", "Player1")
	var session_rec = get_node_or_null("SessionRecorder")
	if session_rec != null and not session_rec.username.is_empty():
		return session_rec.username
	if has_node("RangeUI/HBoxContainer/PlayerName"):
		return $RangeUI/HBoxContainer/PlayerName.text
	return "Player1"


func _get_current_club() -> String:
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.current_club.is_empty():
		return mp_mgr.current_club
	var session_rec = get_node_or_null("SessionRecorder")
	if session_rec != null and not session_rec.current_club.is_empty():
		return session_rec.current_club
	return "Dr"


func _on_club_selected(club_name: String) -> void:
	_update_averages(club_name)
	if not _is_updating_auto_club:
		_user_custom_club = club_name


func _on_active_player_changed(_player: Dictionary) -> void:
	_user_custom_club = ""
	_update_averages()
	update_auto_club()


func _on_player_changed(_dir: String, _player_name: String) -> void:
	_user_custom_club = ""
	_update_averages()
	update_auto_club()


func _load_global_stats() -> Dictionary:
	var path = "user://player_club_stats.json"
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK:
		if typeof(json.data) == TYPE_DICTIONARY:
			return json.data
	return {}


func _save_global_stats(stats: Dictionary) -> void:
	var path = "user://player_club_stats.json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(stats, "\t"))


func _record_global_shot(player_name: String, club_name: String, raw_shot: Dictionary) -> void:
	if player_name.is_empty() or club_name.is_empty():
		return
	var stats = _load_global_stats()
	if not stats.has(player_name):
		stats[player_name] = {}
	if not stats[player_name].has(club_name):
		stats[player_name][club_name] = []
		
	var entry = {
		"CarryDistance": raw_shot.get("CarryDistance", 0.0),
		"Speed": raw_shot.get("Speed", 0.0),
		"TotalSpin": raw_shot.get("TotalSpin", 0.0),
		"SideDistance": raw_shot.get("SideDistance", 0.0),
		"TargetDistance": raw_shot.get("TargetDistance", 0.0),
		"TotalDistance": raw_shot.get("TotalDistance", 0.0)
	}
	stats[player_name][club_name].append(entry)
	_save_global_stats(stats)


func _remove_last_global_shot(player_name: String, club_name: String) -> void:
	if player_name.is_empty() or club_name.is_empty():
		return
	var stats = _load_global_stats()
	if stats.has(player_name) and stats[player_name].has(club_name):
		if not stats[player_name][club_name].is_empty():
			stats[player_name][club_name].pop_back()
			_save_global_stats(stats)


func remove_last_shot() -> void:
	if not shot_history.is_empty():
		var last_shot = shot_history.pop_back()
		var p_name = last_shot.get("player", "")
		var club_name = last_shot.get("club", "")
		if not p_name.is_empty() and not club_name.is_empty():
			_remove_last_global_shot(p_name, club_name)
		_update_averages()




	
