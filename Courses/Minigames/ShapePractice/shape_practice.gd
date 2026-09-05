extends Node3D

# Preloaded player scene
var PlayerScene = preload("res://Player/player.tscn")

# Minigame state
var player = null
var selected_target_index: int = 2 # Default: 150 YD Draw (index 2)
var selected_side: String = "draw" # "draw" (left) or "fade" (right)

# Distances in yards
var target_distances_yards: Array[int] = [50, 100, 150, 200, 250, 300]

# Barrier Wall distances in yards (framing each 50yd target: e.g. 50yd target sits between 25yd & 75yd walls)
var wall_distances_yards: Array[int] = [25, 75, 125, 175, 225, 275, 325]

# Unit conversion constants
const YARD_TO_M: float = 0.9144
const FEET_TO_M: float = 0.3048
const TEN_FEET_M: float = 3.048 # 10.0 * 0.3048 (Threshold distance past wall start)

# Data structures:
# 12 targets: indices 0..5 are DRAW (Left, -Z), indices 6..11 are FADE (Right, +Z)
var target_positions: Array[Vector3] = []
var target_data: Array[Dictionary] = []
var target_stats: Dictionary = {}
var total_greens_hit: int = 0

# Wall data & quick lookup
var wall_nodes: Array[StaticBody3D] = []
var walls_by_side_and_dist: Dictionary = {"draw": {}, "fade": {}}

# Shot & Auto-Reset state tracking
var shot_reset_token: int = 0
var is_shot_in_progress: bool = false
var is_resetting: bool = false
var sfx_wall_player: AudioStreamPlayer = null

# 3D Visual Indicators
var target_zone_ground: MeshInstance3D = null
var target_zone_marker_3d: Label3D = null

# Camera state
var last_camera_offset: Vector3 = Vector3.ZERO
var camera_following: bool = false
var default_cam_pos: Vector3 = Vector3(-4.5, 2.2, 0.0)
var default_look_target: Vector3 = Vector3(35.0, 1.0, 0.0)

# UI element references
var hud_layer: CanvasLayer = null
var hud_control: Control = null
var target_title_lbl: Label = null
var attempts_lbl: Label = null
var hits_lbl: Label = null
var accuracy_lbl: Label = null
var total_hits_lbl: Label = null
var banner_lbl: Label = null
var draw_tab_btn: Button = null
var fade_tab_btn: Button = null
var target_buttons: Array[Button] = []
var music_toggle_btn: Button = null
var stats_btn: Button = null
var grid_canvas: Control = null
var _settings_layer: CanvasLayer = null
var raw_ball_data: Dictionary = {}
var display_data: Dictionary = {}

# On-screen Target Zone Indicator HUD references
var zone_indicator_panel: PanelContainer = null
var zone_target_lbl: Label = null
var zone_bounds_lbl: Label = null
var zone_lane_graphic_lbl: Label = null
var zone_instruction_lbl: Label = null

# Materials
var green_mat: StandardMaterial3D
var fringe_mat: StandardMaterial3D
var fairway_mat: StandardMaterial3D
var rough_mat: StandardMaterial3D
var wall_wood_mat: StandardMaterial3D
var wall_stone_mat: StandardMaterial3D
var cap_mat: StandardMaterial3D
var tee_turf_mat: StandardMaterial3D

func _ready() -> void:
	name = "ShapePractice"
	
	# 1. Initialize target data & stats
	_init_target_data()
	
	# 2. Materials
	_init_materials()
	
	# 3. Lighting & Environment
	_setup_environment()
	
	# 4. Ground Fairway & Hazards
	_setup_ground()
	
	# 5. Tee Box
	_setup_tee_box()
	
	# 6. Target Landing Zones (12 total: 6 Left Draw, 6 Right Fade)
	_setup_target_greens()
	
	# 7. Obstacle Barrier Walls (25, 75, 125, 175, 225, 275, 325 yards)
	_setup_barrier_walls()
	
	# 7b. 3D Target Zone Highlighting Visuals
	_setup_target_zone_visuals()
	
	# 8. Setup Player
	_setup_player()
	
	# 8b. Setup Wall Impact SFX Player
	_setup_sfx()
	
	# 9. Setup UI HUD
	_setup_ui()
	
	# 10. Select default target (150 YD Draw)
	_select_target(2)
	
	# 11. Connect Launch Monitor signals
	if has_node("/root/EventBus"):
		var eb = get_node("/root/EventBus")
		if eb.has_signal("club_selected"):
			eb.club_selected.emit("7i")
	
	if has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if not lm.hit_ball.is_connected(_on_launch_monitor_hit_ball):
			lm.hit_ball.connect(_on_launch_monitor_hit_ball)
			
	var tcp_server = get_node_or_null("TCPServer")
	if tcp_server == null:
		var tcp_script = load("res://addons/launch_monitors/common/tcp_server/TcpServer.cs")
		if tcp_script != null:
			tcp_server = tcp_script.new()
			tcp_server.name = "TCPServer"
			add_child(tcp_server)
	if tcp_server != null and tcp_server.has_signal("HitBall"):
		if not tcp_server.HitBall.is_connected(_on_launch_monitor_hit_ball):
			tcp_server.HitBall.connect(_on_launch_monitor_hit_ball)

# ========================================
# GEOMETRY & TARGET DATA INITIALIZATION
# ========================================

func get_gate_half_width(dist_yd: float) -> float:
	return 4.2 + (dist_yd / 275.0) * 2.5

func get_wall_extent(dist_yd: float) -> float:
	return 32.0 + (dist_yd / 275.0) * 60.0

func _init_target_data() -> void:
	target_positions.clear()
	target_data.clear()
	target_stats.clear()
	
	# 6 DRAW targets (indices 0..5, Left / -Z)
	for i in range(target_distances_yards.size()):
		var dist_yd = target_distances_yards[i]
		var front_wall_yd = dist_yd - 25
		var back_wall_yd = dist_yd + 25
		var dist_m = dist_yd * YARD_TO_M
		var front_x = front_wall_yd * YARD_TO_M
		var back_x = back_wall_yd * YARD_TO_M
		var gate_half_w = get_gate_half_width(float(dist_yd))
		var wall_ext = get_wall_extent(float(dist_yd))
		var inner_z_m = gate_half_w + TEN_FEET_M
		var center_z_m = (inner_z_m + wall_ext) * 0.5
		
		var draw_pos = Vector3(dist_m, 0.0, -center_z_m)
		target_positions.append(draw_pos)
		
		target_data.append({
			"index": i,
			"side": "draw",
			"side_label": "Draw (Left)",
			"dist_yd": dist_yd,
			"dist_m": dist_m,
			"front_wall_yd": front_wall_yd,
			"back_wall_yd": back_wall_yd,
			"front_x": front_x,
			"back_x": back_x,
			"gate_half_w": gate_half_w,
			"inner_z_m": inner_z_m,
			"wall_ext": wall_ext,
			"pos": draw_pos,
			"color": Color(0.15, 0.75, 1.0) # Bright Cyan-Blue for Draw
		})
		target_stats[i] = {"Attempts": 0, "Hits": 0}
		
	# 6 FADE targets (indices 6..11, Right / +Z)
	for i in range(target_distances_yards.size()):
		var dist_yd = target_distances_yards[i]
		var front_wall_yd = dist_yd - 25
		var back_wall_yd = dist_yd + 25
		var dist_m = dist_yd * YARD_TO_M
		var front_x = front_wall_yd * YARD_TO_M
		var back_x = back_wall_yd * YARD_TO_M
		var gate_half_w = get_gate_half_width(float(dist_yd))
		var wall_ext = get_wall_extent(float(dist_yd))
		var inner_z_m = gate_half_w + TEN_FEET_M
		var center_z_m = (inner_z_m + wall_ext) * 0.5
		var global_idx = 6 + i
		
		var fade_pos = Vector3(dist_m, 0.0, center_z_m)
		target_positions.append(fade_pos)
		
		target_data.append({
			"index": global_idx,
			"side": "fade",
			"side_label": "Fade (Right)",
			"dist_yd": dist_yd,
			"dist_m": dist_m,
			"front_wall_yd": front_wall_yd,
			"back_wall_yd": back_wall_yd,
			"front_x": front_x,
			"back_x": back_x,
			"gate_half_w": gate_half_w,
			"inner_z_m": inner_z_m,
			"wall_ext": wall_ext,
			"pos": fade_pos,
			"color": Color(1.0, 0.55, 0.15) # Warm Amber-Orange for Fade
		})
		target_stats[global_idx] = {"Attempts": 0, "Hits": 0}

func check_shot_in_zone(pos: Vector3, target_idx: int) -> Dictionary:
	var data = target_data[target_idx]
	var dist_yd = data["dist_yd"]
	var front_wall_yd = data["front_wall_yd"]
	var back_wall_yd = data["back_wall_yd"]
	var front_x = data["front_x"]
	var back_x = data["back_x"]
	var side = data["side"]
	
	var ball_x = pos.x
	var ball_z = pos.z
	var ball_x_yd = ball_x / YARD_TO_M
	
	# Clearway edge (where barrier wall begins) at the ball's X position
	var gate_half_w = get_gate_half_width(ball_x_yd)
	var min_lateral_z = gate_half_w + TEN_FEET_M
	
	# Lateral depth: how many meters/feet past where the wall starts (past gate_half_w)
	var lateral_depth_m = abs(ball_z) - gate_half_w
	var lateral_depth_ft = lateral_depth_m / FEET_TO_M
	
	var in_x_range = (ball_x >= front_x and ball_x <= back_x)
	var on_correct_side = (side == "draw" and ball_z < -gate_half_w) or (side == "fade" and ball_z > gate_half_w)
	var past_10ft_thresh = (abs(ball_z) >= min_lateral_z)
	
	# Is inside the active target zone?
	var is_hit = in_x_range and on_correct_side and past_10ft_thresh
	
	return {
		"is_hit": is_hit,
		"in_x_range": in_x_range,
		"on_correct_side": on_correct_side,
		"past_10ft_thresh": past_10ft_thresh,
		"lateral_depth_ft": lateral_depth_ft,
		"lateral_depth_m": lateral_depth_m,
		"gate_half_w": gate_half_w,
		"min_lateral_z": min_lateral_z,
		"ball_x_yd": ball_x_yd,
		"dist_yd": dist_yd,
		"front_wall_yd": front_wall_yd,
		"back_wall_yd": back_wall_yd,
		"side": side
	}

# ========================================
# MATERIALS INITIALIZATION
# ========================================

func _init_materials() -> void:
	# Putting Green turf
	green_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-green/albedo.png"):
		green_mat.albedo_texture = load("res://Courses/Environments/grass-green/albedo.png")
		green_mat.albedo_color = Color(0.92, 1.0, 0.92)
		if ResourceLoader.exists("res://Courses/Environments/grass-green/normal.png"):
			green_mat.normal_enabled = true
			green_mat.normal_texture = load("res://Courses/Environments/grass-green/normal.png")
		green_mat.uv1_scale = Vector3(0.18, 0.18, 0.18)
	else:
		green_mat.albedo_color = Color(0.16, 0.65, 0.22)
	green_mat.roughness = 0.82
	
	# Fringe / Collar turf
	fringe_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
		fringe_mat.albedo_texture = load("res://Courses/Environments/grass-rough/albedo.png")
		fringe_mat.uv1_scale = Vector3(0.16, 0.16, 0.16)
	elif ResourceLoader.exists("res://Courses/Environments/grass-green/albedo.png"):
		fringe_mat.albedo_texture = load("res://Courses/Environments/grass-green/albedo.png")
		fringe_mat.albedo_color = Color(0.32, 0.55, 0.25)
		fringe_mat.uv1_scale = Vector3(0.16, 0.16, 0.16)
	else:
		fringe_mat.albedo_color = Color(0.14, 0.48, 0.18)
	fringe_mat.roughness = 0.92
	
	# Fairway ground
	fairway_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-fairway/albedo.png"):
		fairway_mat.albedo_texture = load("res://Courses/Environments/grass-fairway/albedo.png")
		if ResourceLoader.exists("res://Courses/Environments/grass-fairway/normal.png"):
			fairway_mat.normal_enabled = true
			fairway_mat.normal_texture = load("res://Courses/Environments/grass-fairway/normal.png")
		fairway_mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
	else:
		fairway_mat.albedo_color = Color(0.20, 0.52, 0.24)
	fairway_mat.roughness = 0.88
	
	# Rough outer ground
	rough_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
		rough_mat.albedo_texture = load("res://Courses/Environments/grass-rough/albedo.png")
		rough_mat.uv1_scale = Vector3(0.05, 0.05, 0.05)
	else:
		rough_mat.albedo_color = Color(0.12, 0.38, 0.14)
	rough_mat.roughness = 0.95
	
	# Wall timber / wood
	wall_wood_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/tree-bark/albedo.png"):
		wall_wood_mat.albedo_texture = load("res://Courses/Environments/tree-bark/albedo.png")
		wall_wood_mat.albedo_color = Color(0.65, 0.52, 0.42)
		wall_wood_mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
		wall_wood_mat.uv1_triplanar = true
	else:
		wall_wood_mat.albedo_color = Color(0.35, 0.24, 0.15)
	wall_wood_mat.roughness = 0.85
	
	# Wall stone / concrete panels
	wall_stone_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/dry-rocky-ground-bl/dry-rocky-ground_albedo.png"):
		wall_stone_mat.albedo_texture = load("res://Courses/Environments/dry-rocky-ground-bl/dry-rocky-ground_albedo.png")
		wall_stone_mat.albedo_color = Color(0.6, 0.65, 0.7)
		wall_stone_mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
		wall_stone_mat.uv1_triplanar = true
	else:
		wall_stone_mat.albedo_color = Color(0.30, 0.35, 0.40)
	wall_stone_mat.roughness = 0.80
	
	# Top trim / Cap
	cap_mat = StandardMaterial3D.new()
	cap_mat.albedo_color = Color(0.18, 0.14, 0.10)
	cap_mat.roughness = 0.75
	
	# Tee box turf
	tee_turf_mat = StandardMaterial3D.new()
	tee_turf_mat.albedo_color = Color(0.15, 0.58, 0.22)
	tee_turf_mat.roughness = 0.80

# ========================================
# ENVIRONMENT & LIGHTING
# ========================================

func _setup_environment() -> void:
	var is_mobile := MobilePerformance.is_mobile()

	# Directional Sun Light
	var sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(-48)).rotated(Vector3.UP, deg_to_rad(30))
	sun.shadow_enabled = true
	sun.light_energy = 1.2
	if is_mobile:
		sun.directional_shadow_max_distance = 200.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_split_1 = 0.1
	else:
		sun.directional_shadow_max_distance = 500.0
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_split_1 = 0.05
		sun.directional_shadow_split_2 = 0.15
		sun.directional_shadow_split_3 = 0.40
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 2.0
	add_child(sun)
	
	# World Environment
	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	
	var sky = Sky.new()
	if is_mobile:
		sky.process_mode = Sky.PROCESS_MODE_QUALITY
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.54, 0.88)
	sky_mat.sky_horizon_color = Color(0.60, 0.78, 0.94)
	sky_mat.ground_bottom_color = Color(0.14, 0.28, 0.18)
	sky_mat.ground_horizon_color = Color(0.60, 0.78, 0.94)
	sky_mat.sun_angle_max = 30.0
	sky.sky_material = sky_mat
	env.sky = sky
	
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.50
	env.ambient_light_sky_contribution = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 5.0
	env.tonemap_exposure = 1.0
	if is_mobile:
		env.ssao_enabled = false
	else:
		env.ssao_enabled = true
		env.ssao_radius = 2.0
		env.ssao_intensity = 1.2
		env.ssao_power = 1.5
		env.ssao_detail = 0.2
		env.ssao_horizon = 0.06
		env.ssao_ao_channel_affect = 0.5
	
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.78, 0.88)
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.25
	
	world_env.environment = env
	add_child(world_env)
	
	# Camera 3D
	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)
	camera.global_position = default_cam_pos
	camera.look_at(default_look_target)
	
	if has_node("/root/TensionManager"):
		TensionManager.register_camera(camera, 58.0)

# ========================================
# GROUND & FAIRWAY SETUP
# ========================================

func _setup_ground() -> void:
	# Main Fairway & Range Ground StaticBody3D
	var ground = StaticBody3D.new()
	ground.name = "GroundFairway"
	ground.set_meta("surface_type", 0) # FAIRWAY (0)
	add_child(ground)
	
	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(450.0, 1.0, 300.0)
	col_shape.shape = box_shape
	col_shape.position = Vector3(180.0, -0.5, 0.0)
	ground.add_child(col_shape)
	
	var mesh_inst = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(450.0, 300.0)
	mesh_inst.mesh = plane_mesh
	mesh_inst.material_override = fairway_mat
	mesh_inst.position = Vector3(180.0, 0.0, 0.0)
	ground.add_child(mesh_inst)

# ========================================
# TEE BOX
# ========================================

func _setup_tee_box() -> void:
	var tee = StaticBody3D.new()
	tee.name = "TeeBox"
	tee.set_meta("surface_type", 3) # TEE (3)
	add_child(tee)
	
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(6.0, 0.4, 6.0)
	col.shape = box
	col.position = Vector3(0.0, -0.2, 0.0)
	tee.add_child(col)
	
	# Base border
	var base_mesh_inst = MeshInstance3D.new()
	var base_mesh = BoxMesh.new()
	base_mesh.size = Vector3(6.4, 0.38, 6.4)
	base_mesh_inst.mesh = base_mesh
	base_mesh_inst.material_override = wall_wood_mat
	base_mesh_inst.position = Vector3(0.0, -0.2, 0.0)
	tee.add_child(base_mesh_inst)
	
	# Turf surface
	var turf_inst = MeshInstance3D.new()
	var turf_mesh = BoxMesh.new()
	turf_mesh.size = Vector3(6.0, 0.04, 6.0)
	turf_inst.mesh = turf_mesh
	turf_inst.material_override = tee_turf_mat
	turf_inst.position = Vector3(0.0, 0.02, 0.0)
	tee.add_child(turf_inst)
	
	# Tee markers (White Spheres)
	for side_z in [-1.5, 1.5]:
		var marker = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = 0.08
		sphere_mesh.height = 0.16
		marker.mesh = sphere_mesh
		var marker_mat = StandardMaterial3D.new()
		marker_mat.albedo_color = Color.WHITE
		marker.material_override = marker_mat
		marker.position = Vector3(0.0, 0.1, side_z)
		tee.add_child(marker)

# ========================================
# TARGET LANDING ZONES GENERATION
# ========================================

func _setup_target_greens() -> void:
	for i in range(target_data.size()):
		var data = target_data[i]
		var zone_node = _build_target_zone_node(data)
		add_child(zone_node)

func _build_target_zone_node(data: Dictionary) -> StaticBody3D:
	var idx = data["index"]
	var dist_yd = data["dist_yd"]
	var front_wall_yd = data["front_wall_yd"]
	var back_wall_yd = data["back_wall_yd"]
	var front_x = data["front_x"]
	var back_x = data["back_x"]
	var x_len = back_x - front_x
	var x_center = (front_x + back_x) * 0.5
	var side = data["side"]
	var theme_color = data["color"]
	
	var inner_z = data["inner_z_m"]
	var wall_ext = data["wall_ext"]
	var z_width = wall_ext - inner_z
	var z_center = (inner_z + wall_ext) * 0.5 * (-1.0 if side == "draw" else 1.0)
	
	var zone_body = StaticBody3D.new()
	zone_body.name = "TargetGreen_%d" % idx
	zone_body.set_meta("surface_type", 4) # GREEN (4)
	zone_body.set_meta("target_index", idx)
	
	# 1. Designated Landing Zone Fairway/Turf Mesh
	var turf_inst = MeshInstance3D.new()
	var turf_box = BoxMesh.new()
	turf_box.size = Vector3(x_len, 0.04, z_width)
	turf_inst.mesh = turf_box
	turf_inst.material_override = green_mat
	turf_inst.position = Vector3(x_center, 0.02, z_center)
	zone_body.add_child(turf_inst)
	
	# 2. Solid Collision Shape for physics / ball rolling
	var turf_col = CollisionShape3D.new()
	var col_box = BoxShape3D.new()
	col_box.size = Vector3(x_len, 0.1, z_width)
	turf_col.shape = col_box
	turf_col.position = Vector3(x_center, 0.02, z_center)
	zone_body.add_child(turf_col)
	
	# 3. Inner 10-ft Clearway Boundary Line (painted strip at inner_z indicating the start of the score zone)
	var line_inst = MeshInstance3D.new()
	var line_box = BoxMesh.new()
	line_box.size = Vector3(x_len, 0.045, 0.35)
	line_inst.mesh = line_box
	var line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
	line_mat.emission_enabled = true
	line_mat.emission = Color(1.0, 1.0, 1.0)
	line_mat.emission_energy_multiplier = 0.5
	line_inst.material_override = line_mat
	var line_z = inner_z * (-1.0 if side == "draw" else 1.0)
	line_inst.position = Vector3(x_center, 0.025, line_z)
	zone_body.add_child(line_inst)
	
	# 4. Target Zone Pin & Flag in center of zone
	var pin_node = Node3D.new()
	pin_node.name = "FlagPin"
	pin_node.position = Vector3(x_center, 0.02, z_center)
	zone_body.add_child(pin_node)
	
	var pole = MeshInstance3D.new()
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.04
	pole_mesh.bottom_radius = 0.04
	pole_mesh.height = 3.6
	pole.mesh = pole_mesh
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color.WHITE
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, 1.8, 0.0)
	pin_node.add_child(pole)
	
	var flag = MeshInstance3D.new()
	var flag_mesh = PrismMesh.new()
	flag_mesh.size = Vector3(0.8, 0.5, 0.04)
	flag.mesh = flag_mesh
	var flag_m = StandardMaterial3D.new()
	flag_m.albedo_color = theme_color
	flag_m.emission_enabled = true
	flag_m.emission = theme_color
	flag_m.emission_energy_multiplier = 1.0
	flag.material_override = flag_m
	flag.position = Vector3(0.4, 3.3, 0.0)
	flag.rotation = Vector3(0.0, 0.0, -PI / 2)
	pin_node.add_child(flag)
	
	# 5. Distance & Zone Label (Billboarded in 3D)
	var label = Label3D.new()
	var side_code = "DRAW" if side == "draw" else "FADE"
	label.text = "%d YDS\n(%s ZONE)\n[%d-%d YD WALLS]" % [dist_yd, side_code, front_wall_yd, back_wall_yd]
	label.font_size = 42
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 10
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0, 0, 0, 0.95)
	label.position = Vector3(0.0, 4.8, 0.0)
	pin_node.add_child(label)
	
	return zone_body

# ========================================
# OBSTACLE BARRIER WALLS SETUP
# ========================================

func _setup_barrier_walls() -> void:
	wall_nodes.clear()
	walls_by_side_and_dist = {"draw": {}, "fade": {}}
	var YARD_TO_M = 0.9144
	
	for w_idx in range(wall_distances_yards.size()):
		var dist_yd = wall_distances_yards[w_idx]
		var x_pos = dist_yd * YARD_TO_M
		
		# Open center gate corridor width (between -gate_half_w and +gate_half_w)
		# Starts around 8.0m wide up close and expands moderately with distance
		var gate_half_w = 4.2 + (float(dist_yd) / 275.0) * 2.5
		
		# Wall extends laterally across the sector to block direct line of sight to greens
		# Target greens are at angle ~15.5 deg (z = dist_m * sin(15.5) = x * tan(15.5) approx 0.28 * x)
		var wall_extent = 32.0 + (float(dist_yd) / 275.0) * 60.0
		var wall_length = wall_extent - gate_half_w
		var wall_center_z_offset = gate_half_w + (wall_length / 2.0)
		
		var wall_height = 13.0
		var wall_thickness = 1.2
		
		# --- LEFT WALL (Draw Side, -Z) ---
		var left_wall = _create_single_barrier_wall(
			"BarrierWall_Left_%d" % dist_yd,
			Vector3(x_pos, wall_height / 2.0, -wall_center_z_offset),
			Vector3(wall_thickness, wall_height, wall_length),
			dist_yd,
			"draw"
		)
		add_child(left_wall)
		wall_nodes.append(left_wall)
		walls_by_side_and_dist["draw"][dist_yd] = left_wall
		
		# --- RIGHT WALL (Fade Side, +Z) ---
		var right_wall = _create_single_barrier_wall(
			"BarrierWall_Right_%d" % dist_yd,
			Vector3(x_pos, wall_height / 2.0, wall_center_z_offset),
			Vector3(wall_thickness, wall_height, wall_length),
			dist_yd,
			"fade"
		)
		add_child(right_wall)
		wall_nodes.append(right_wall)
		walls_by_side_and_dist["fade"][dist_yd] = right_wall

func _create_single_barrier_wall(w_name: String, pos: Vector3, size: Vector3, dist_yd: int, side: String) -> StaticBody3D:
	var wall = StaticBody3D.new()
	wall.name = w_name
	wall.position = pos
	wall.set_meta("is_barrier_wall", true)
	wall.set_meta("wall_dist_yd", dist_yd)
	wall.set_meta("side", side)
	
	# Solid Collision
	var col = CollisionShape3D.new()
	var box_col = BoxShape3D.new()
	box_col.size = size
	col.shape = box_col
	wall.add_child(col)
	
	# Main Wall Mesh (Stone / Timber panel)
	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = wall_stone_mat
	wall.add_child(mesh_inst)
	wall.set_meta("mesh_inst", mesh_inst)
	
	# Top Cap Trim Beam
	var cap_inst = MeshInstance3D.new()
	var cap_mesh = BoxMesh.new()
	cap_mesh.size = Vector3(size.x * 1.3, 0.4, size.z * 1.01)
	cap_inst.mesh = cap_mesh
	cap_inst.material_override = cap_mat
	cap_inst.position = Vector3(0.0, size.y / 2.0 + 0.2, 0.0)
	wall.add_child(cap_inst)
	wall.set_meta("cap_inst", cap_inst)
	wall.set_meta("default_cap_mat", cap_mat)
	
	# Neon/Glow inner gate post indicator (highlights the open middle window edge)
	var post_z = -(size.z / 2.0) if side == "fade" else (size.z / 2.0)
	var post_inst = MeshInstance3D.new()
	var post_mesh = CylinderMesh.new()
	post_mesh.top_radius = 0.18
	post_mesh.bottom_radius = 0.18
	post_mesh.height = size.y + 0.8
	post_inst.mesh = post_mesh
	
	var post_mat = StandardMaterial3D.new()
	var glow_color = Color(0.15, 0.8, 1.0) if side == "draw" else Color(1.0, 0.6, 0.15)
	post_mat.albedo_color = glow_color
	post_mat.emission_enabled = true
	post_mat.emission = glow_color
	post_mat.emission_energy_multiplier = 0.9
	post_inst.material_override = post_mat
	post_inst.position = Vector3(0.0, 0.4, post_z)
	wall.add_child(post_inst)
	wall.set_meta("post_inst", post_inst)
	wall.set_meta("default_post_mat", post_mat)

	# Vertical Sky Beacon above gate edge (illuminates on active bounding walls)
	var beacon_inst = MeshInstance3D.new()
	var cyl_beacon = CylinderMesh.new()
	cyl_beacon.top_radius = 0.28
	cyl_beacon.bottom_radius = 0.38
	cyl_beacon.height = 36.0
	beacon_inst.mesh = cyl_beacon
	beacon_inst.position = Vector3(0.0, size.y + 18.0, post_z)
	beacon_inst.visible = false
	wall.add_child(beacon_inst)
	wall.set_meta("beacon_inst", beacon_inst)
	
	# Front Wall Distance Marker Sign
	var sign_lbl = Label3D.new()
	sign_lbl.text = "⛔ %d YDS" % dist_yd
	sign_lbl.font_size = 40
	sign_lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign_lbl.rotation.y = deg_to_rad(-90) # Face towards tee box (-X)
	sign_lbl.modulate = Color(1.0, 0.9, 0.6)
	sign_lbl.outline_size = 8
	sign_lbl.outline_modulate = Color(0, 0, 0, 0.9)
	# Position sign on front face facing tee
	sign_lbl.position = Vector3(-size.x / 2.0 - 0.05, 1.5, post_z + (1.6 if side == "fade" else -1.6))
	wall.add_child(sign_lbl)
	wall.set_meta("sign_lbl", sign_lbl)
	
	# Impact Detection Area for reliable obstacle collision handling
	var area = Area3D.new()
	area.name = "ImpactArea"
	var area_col = CollisionShape3D.new()
	var area_box = BoxShape3D.new()
	area_box.size = size + Vector3(0.6, 0.6, 0.6)
	area_col.shape = area_box
	area.add_child(area_col)
	area.body_entered.connect(func(body):
		if player and body == player.ball:
			_on_barrier_wall_hit(dist_yd, side)
	)
	wall.add_child(area)
	
	return wall

func _setup_target_zone_visuals() -> void:
	# Ground highlight marking the landing sector between bounding walls
	target_zone_ground = MeshInstance3D.new()
	target_zone_ground.name = "TargetZoneGroundHighlight"
	var p_mesh = BoxMesh.new()
	p_mesh.size = Vector3(45.72, 0.05, 32.0)
	target_zone_ground.mesh = p_mesh
	
	var z_mat = StandardMaterial3D.new()
	z_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	z_mat.albedo_color = Color(0.15, 0.75, 1.0, 0.22)
	z_mat.emission_enabled = true
	z_mat.emission = Color(0.15, 0.75, 1.0)
	z_mat.emission_energy_multiplier = 0.6
	target_zone_ground.material_override = z_mat
	target_zone_ground.position = Vector3(137.16, 0.02, -36.6)
	add_child(target_zone_ground)

	# Floating 3D Zone Beacon/Billboard above green
	target_zone_marker_3d = Label3D.new()
	target_zone_marker_3d.name = "TargetZoneMarker3D"
	target_zone_marker_3d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target_zone_marker_3d.font_size = 46
	target_zone_marker_3d.outline_size = 12
	target_zone_marker_3d.outline_modulate = Color(0, 0, 0, 0.95)
	target_zone_marker_3d.modulate = Color(0.15, 0.85, 1.0)
	target_zone_marker_3d.position = Vector3(137.16, 5.8, -36.6)
	add_child(target_zone_marker_3d)

func _setup_sfx() -> void:
	sfx_wall_player = AudioStreamPlayer.new()
	sfx_wall_player.name = "WallHitSFX"
	if ResourceLoader.exists("res://assets/audio/sfx/tree_hit.ogg"):
		sfx_wall_player.stream = load("res://assets/audio/sfx/tree_hit.ogg")
	elif ResourceLoader.exists("res://assets/audio/sfx/ball_hit_tree.mp3"):
		sfx_wall_player.stream = load("res://assets/audio/sfx/ball_hit_tree.mp3")
	elif ResourceLoader.exists("res://assets/audio/sfx/rough_thump.ogg"):
		sfx_wall_player.stream = load("res://assets/audio/sfx/rough_thump.ogg")
	add_child(sfx_wall_player)

# ========================================
# TARGET SELECTION & HIGHLIGHT
# ========================================

func _select_target(index: int) -> void:
	if index < 0 or index >= target_data.size():
		return
		
	selected_target_index = index
	var cur_data = target_data[index]
	selected_side = cur_data["side"]
	
	_update_wall_and_zone_highlights()
	_update_selector_buttons()
	_update_hud()
	_reset_ball_position()

func _update_wall_and_zone_highlights() -> void:
	var cur_data = target_data[selected_target_index]
	var dist_yd = cur_data["dist_yd"]
	var front_wall_yd = cur_data["front_wall_yd"]
	var back_wall_yd = cur_data["back_wall_yd"]
	var side = cur_data["side"]
	var c = cur_data["color"]
	var front_x = cur_data["front_x"]
	var back_x = cur_data["back_x"]
	var x_len = back_x - front_x
	var x_center = (front_x + back_x) * 0.5
	var inner_z = cur_data["inner_z_m"]
	var wall_ext = cur_data["wall_ext"]
	var z_width = wall_ext - inner_z
	var z_center = (inner_z + wall_ext) * 0.5 * (-1.0 if side == "draw" else 1.0)
	
	# Full Wall Material for Front Bounding Wall (Full wall face glows vividly)
	var front_wall_mat = StandardMaterial3D.new()
	front_wall_mat.albedo_color = Color(c.r * 0.75 + 0.15, c.g * 0.75 + 0.15, c.b * 0.75 + 0.15)
	front_wall_mat.emission_enabled = true
	front_wall_mat.emission = c
	front_wall_mat.emission_energy_multiplier = 0.95
	front_wall_mat.roughness = 0.35
	
	# Full Wall Material for Back Bounding Wall
	var back_wall_mat = StandardMaterial3D.new()
	back_wall_mat.albedo_color = Color(c.r * 0.6 + 0.12, c.g * 0.6 + 0.12, c.b * 0.6 + 0.12)
	back_wall_mat.emission_enabled = true
	back_wall_mat.emission = c
	back_wall_mat.emission_energy_multiplier = 0.75
	back_wall_mat.roughness = 0.35
	
	# Top Cap Materials
	var front_cap_mat = StandardMaterial3D.new()
	front_cap_mat.albedo_color = c
	front_cap_mat.emission_enabled = true
	front_cap_mat.emission = c
	front_cap_mat.emission_energy_multiplier = 2.2
	
	var back_cap_mat = StandardMaterial3D.new()
	back_cap_mat.albedo_color = Color(c.r * 0.85, c.g * 0.85, c.b * 0.85)
	back_cap_mat.emission_enabled = true
	back_cap_mat.emission = c
	back_cap_mat.emission_energy_multiplier = 1.6

	# Vertical Sky Beacon Material
	var beacon_mat = StandardMaterial3D.new()
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.albedo_color = Color(c.r, c.g, c.b, 0.75)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = c
	beacon_mat.emission_energy_multiplier = 3.2
	
	for w in wall_nodes:
		if not is_instance_valid(w):
			continue
		var w_side = w.get_meta("side", "")
		var w_dist = w.get_meta("wall_dist_yd", 0)
		var mesh_inst: MeshInstance3D = w.get_meta("mesh_inst", null)
		var cap_inst: MeshInstance3D = w.get_meta("cap_inst", null)
		var post_inst: MeshInstance3D = w.get_meta("post_inst", null)
		var beacon_inst: MeshInstance3D = w.get_meta("beacon_inst", null)
		var sign_lbl: Label3D = w.get_meta("sign_lbl", null)
		var def_cap: StandardMaterial3D = w.get_meta("default_cap_mat", cap_mat)
		var def_post: StandardMaterial3D = w.get_meta("default_post_mat", null)
		
		if w_side == side and w_dist == front_wall_yd:
			# Active Front Barrier Wall - FULL WALL HIGHLIGHT
			if mesh_inst:
				mesh_inst.material_override = front_wall_mat
			if cap_inst:
				cap_inst.material_override = front_cap_mat
			if beacon_inst:
				beacon_inst.material_override = beacon_mat
				beacon_inst.visible = true
			if sign_lbl:
				sign_lbl.text = "ENTRY ➔ [%d YD ZONE]" % dist_yd
				sign_lbl.modulate = Color(1.0, 1.0, 0.25)
				sign_lbl.font_size = 54
				sign_lbl.outline_size = 12
			if post_inst:
				var p_mat = StandardMaterial3D.new()
				p_mat.albedo_color = c
				p_mat.emission_enabled = true
				p_mat.emission = c
				p_mat.emission_energy_multiplier = 2.5
				post_inst.material_override = p_mat
		elif w_side == side and w_dist == back_wall_yd:
			# Active Back Barrier Wall - FULL WALL HIGHLIGHT
			if mesh_inst:
				mesh_inst.material_override = back_wall_mat
			if cap_inst:
				cap_inst.material_override = back_cap_mat
			if beacon_inst:
				beacon_inst.material_override = beacon_mat
				beacon_inst.visible = true
			if sign_lbl:
				sign_lbl.text = "[%d YD ZONE] ⛔ BACK WALL" % dist_yd
				sign_lbl.modulate = Color(1.0, 0.45, 0.3)
				sign_lbl.font_size = 54
				sign_lbl.outline_size = 12
			if post_inst:
				var p_mat = StandardMaterial3D.new()
				p_mat.albedo_color = c
				p_mat.emission_enabled = true
				p_mat.emission = c
				p_mat.emission_energy_multiplier = 1.8
				post_inst.material_override = p_mat
		else:
			# Standard / Non-bounding Wall
			if mesh_inst:
				mesh_inst.material_override = wall_stone_mat
			if cap_inst:
				cap_inst.material_override = def_cap
			if beacon_inst:
				beacon_inst.visible = false
			if sign_lbl:
				sign_lbl.text = "⛔ %d YDS" % w_dist
				sign_lbl.modulate = Color(1.0, 0.9, 0.6)
				sign_lbl.font_size = 40
				sign_lbl.outline_size = 8
			if post_inst and def_post:
				post_inst.material_override = def_post

	# 3D Landing Zone Ground Highlight
	if target_zone_ground:
		var b_mesh = BoxMesh.new()
		b_mesh.size = Vector3(x_len, 0.06, z_width)
		target_zone_ground.mesh = b_mesh
		target_zone_ground.position = Vector3(x_center, 0.03, z_center)
		
		var zg_mat = StandardMaterial3D.new()
		zg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		zg_mat.albedo_color = Color(c.r, c.g, c.b, 0.35)
		zg_mat.emission_enabled = true
		zg_mat.emission = c
		zg_mat.emission_energy_multiplier = 1.0
		target_zone_ground.material_override = zg_mat
		target_zone_ground.visible = true

	# 3D Floating Zone Beacon above target zone
	if target_zone_marker_3d:
		target_zone_marker_3d.position = Vector3(x_center, 6.2, z_center)
		var shape_str = "DRAW" if side == "draw" else "FADE"
		target_zone_marker_3d.text = "▼ %d YD %s TARGET ZONE ▼\n(HIT BETWEEN %d & %d YD WALLS — ≥10 FT IN FROM CLEARWAY)" % [
			dist_yd, shape_str, front_wall_yd, back_wall_yd
		]
		target_zone_marker_3d.modulate = c
		target_zone_marker_3d.visible = true

func _switch_side(side: String) -> void:
	if side == selected_side:
		return
	selected_side = side
	var dist_offset = selected_target_index % 6
	var new_idx = dist_offset if side == "draw" else (6 + dist_offset)
	_select_target(new_idx)

# ========================================
# PLAYER & AIMING
# ========================================

func _setup_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	player.global_position = Vector3(0.0, 0.05, 0.0)
	
	player.set_process(false)
	player.rest.connect(_on_ball_rest)
	
	player.ball.spawn_position = player.global_position
	player.ball.reset()

func _reset_ball_position() -> void:
	shot_reset_token += 1
	is_shot_in_progress = false
	is_resetting = false

	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	if player and player.ball:
		player.global_position = Vector3(0.0, 0.05, 0.0)
		player.ball.spawn_position = player.global_position
		player.ball.reset()
		player.reset_ball()
		
		# Set aim straight down the open middle corridor (+X axis)
		player.ball.aim_yaw_offset_deg = 0.0
		
	# Reset camera behind tee looking straight down fairway
	var cam = $Camera3D
	if cam:
		cam.global_position = default_cam_pos
		cam.look_at(default_look_target)
	last_camera_offset = default_cam_pos - Vector3(0.0, 0.05, 0.0)
	camera_following = false

	var cur_data = target_data[selected_target_index]
	var front = cur_data["front_wall_yd"]
	var back = cur_data["back_wall_yd"]
	var curve_dir = "left" if cur_data["side"] == "draw" else "right"
	_show_banner("🎯 Target: %d YD %s Zone — Launch through center gate, shape %s ≥10 ft into %d-%d YD wall zone!" % [
		cur_data["dist_yd"],
		cur_data["side"].to_upper(),
		curve_dir,
		front,
		back
	])

# ========================================
# INPUT HANDLING
# ========================================

func _unhandled_input(event: InputEvent) -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_settings()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var camera = $Camera3D
			if camera != null:
				var ray_start = camera.project_ray_origin(event.position)
				var ray_dir = camera.project_ray_normal(event.position)
				var ray_end = ray_start + ray_dir * 2000.0
				var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
				var hit = get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty():
					var clicked_pos = hit["position"]
					var closest_idx = -1
					var min_dist = 9999.0
					for i in range(target_positions.size()):
						var d = clicked_pos.distance_to(target_positions[i])
						if d < min_dist:
							min_dist = d
							closest_idx = i
					if closest_idx != -1 and min_dist <= 30.0:
						_select_target(closest_idx)

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_reset_ball_position()
		elif event.keycode == KEY_TAB:
			_switch_side("fade" if selected_side == "draw" else "draw")
		elif event.keycode == KEY_D or event.keycode == KEY_LEFT:
			_switch_side("draw")
		elif event.keycode == KEY_F or event.keycode == KEY_RIGHT:
			_switch_side("fade")
		elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
			var dist_idx = event.keycode - KEY_1
			var target_idx = dist_idx if selected_side == "draw" else (6 + dist_idx)
			_select_target(target_idx)
		elif event.keycode == KEY_SPACE or event.keycode == KEY_H:
			_trigger_test_shot()

# ========================================
# LAUNCH MONITOR & HIT PROCESSING
# ========================================

func _on_launch_monitor_hit_ball(data: Dictionary) -> void:
	if player == null or player.ball == null:
		return
	if is_shot_in_progress:
		return # Ignore if shot already in flight

	is_shot_in_progress = true
	is_resetting = false
	shot_reset_token += 1
	var this_shot = shot_reset_token

	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()

	player._on_tcp_client_hit_ball(data)
	raw_ball_data = data.duplicate()
	_update_stats_display(false)

	var speed_mph = data.get("Speed", 0.0)
	var cur_data = target_data[selected_target_index]
	var front = cur_data["front_wall_yd"]
	var back = cur_data["back_wall_yd"]
	_show_banner("Shot Launched! Speed: %.1f mph | Shape ≥10 ft into the %d-%d YD wall zone!" % [speed_mph, front, back])

	# Safety fallback: auto-reset after 6.5s if shot gets lost or rolls indefinitely
	_schedule_auto_reset(this_shot, 6.5, "Safety Timeout")

func _on_barrier_wall_hit(dist_yd: int, side: String) -> void:
	if not is_shot_in_progress or is_resetting:
		return
	is_resetting = true
	var this_shot = shot_reset_token

	if sfx_wall_player and not sfx_wall_player.playing:
		sfx_wall_player.pitch_scale = randf_range(0.92, 1.08)
		sfx_wall_player.play()

	target_stats[selected_target_index]["Attempts"] += 1
	_update_hud()
	_update_selector_buttons()

	_show_banner("⛔ WALL HIT! Ball struck the %d YD %s Wall! Resetting to tee in 1.8s..." % [dist_yd, side.to_upper()])
	_schedule_auto_reset(this_shot, 1.8, "Wall Hit")

# ========================================
# CAMERA FOLLOW & FLIGHT TICK
# ========================================

func _physics_process(delta: float) -> void:
	if player and player.ball:
		var ball = player.ball
		var ball_state = ball.state
		if ball_state == PhysicsEnums.BallState.FLIGHT or ball_state == PhysicsEnums.BallState.ROLLOUT:
			camera_following = true
			var ball_pos = ball.global_position
			var target_cam_pos = ball_pos + last_camera_offset
			$Camera3D.global_position = $Camera3D.global_position.lerp(target_cam_pos, delta * 7.0)
			$Camera3D.look_at(ball_pos + Vector3.UP * 0.2)
			
			# Out of bounds check
			if ball_pos.y < -2.5 and not is_resetting:
				is_resetting = true
				_show_banner("⚠️ Out of bounds! Resetting to tee...")
				_schedule_auto_reset(shot_reset_token, 1.5, "Out of bounds")
		else:
			if camera_following:
				camera_following = false
				if has_node("/root/TensionManager"):
					TensionManager.stop_tension()

# ========================================
# BALL REST & SCORING
# ========================================

func _on_ball_rest(_shot_data: Dictionary) -> void:
	raw_ball_data = _shot_data.duplicate()
	_update_stats_display(true)
	if not is_shot_in_progress or is_resetting:
		return
	is_resetting = true
	var this_shot = shot_reset_token

	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
		
	var final_pos = player.ball.global_position
	var cur_data = target_data[selected_target_index]
	var res = check_shot_in_zone(final_pos, selected_target_index)
	
	target_stats[selected_target_index]["Attempts"] += 1
	
	if res["is_hit"]:
		target_stats[selected_target_index]["Hits"] += 1
		total_greens_hit += 1
		GlobalSettings.play_golf_clap()
		_show_banner("🎯 ZONE HIT! Excellent %s shape! Landed %.0f yds out, %.1f ft inside the %d-%d YD wall zone! (%d total hits)" % [
			cur_data["side"].to_upper(),
			res["ball_x_yd"],
			res["lateral_depth_ft"],
			res["front_wall_yd"],
			res["back_wall_yd"],
			total_greens_hit
		])
	else:
		# Check if shot qualified in another zone
		var other_hit_idx = -1
		for i in range(target_data.size()):
			if i == selected_target_index:
				continue
			var other_res = check_shot_in_zone(final_pos, i)
			if other_res["is_hit"]:
				other_hit_idx = i
				break
				
		if other_hit_idx != -1:
			var other_data = target_data[other_hit_idx]
			_show_banner("Landed in the %d YD %s zone — but you were targeting %d YD! Resetting..." % [
				other_data["dist_yd"],
				other_data["side"].to_upper(),
				cur_data["dist_yd"]
			])
		elif res["in_x_range"] and res["on_correct_side"] and not res["past_10ft_thresh"]:
			_show_banner("Didn't shape enough! Ball was only %.1f ft past wall start (needs ≥ 10 ft in from clearway). Resetting..." % [
				max(0.0, res["lateral_depth_ft"])
			])
		elif abs(final_pos.z) <= res["gate_half_w"]:
			_show_banner("Ball stayed in center clearway! Must curve %s at least 10 ft past wall start into the %d-%d YD zone." % [
				cur_data["side"].to_upper(),
				cur_data["front_wall_yd"],
				cur_data["back_wall_yd"]
			])
		elif res["ball_x_yd"] < cur_data["front_wall_yd"]:
			_show_banner("Shot short! Ball reached %.0f yds (Target zone is %d-%d yds). Resetting..." % [
				res["ball_x_yd"],
				cur_data["front_wall_yd"],
				cur_data["back_wall_yd"]
			])
		elif res["ball_x_yd"] > cur_data["back_wall_yd"]:
			_show_banner("Shot long! Ball went %.0f yds (Target zone is %d-%d yds). Resetting..." % [
				res["ball_x_yd"],
				cur_data["front_wall_yd"],
				cur_data["back_wall_yd"]
			])
		else:
			_show_banner("Missed target zone (%.0f yds, %.1f ft lateral). Must shape between %d & %d YD walls (≥10 ft in)!" % [
				res["ball_x_yd"],
				res["lateral_depth_ft"],
				cur_data["front_wall_yd"],
				cur_data["back_wall_yd"]
			])
			
	_update_selector_buttons()
	_update_hud()
	
	# Auto reset after 2.4 seconds
	_schedule_auto_reset(this_shot, 2.4, "Ball Rest")

func _schedule_auto_reset(shot_id: int, delay_sec: float, _reason: String = "") -> void:
	await get_tree().create_timer(delay_sec).timeout
	if is_inside_tree() and shot_reset_token == shot_id:
		_reset_ball_position()

func _trigger_test_shot() -> void:
	if is_shot_in_progress or is_resetting:
		return
	var cur_data = target_data[selected_target_index]
	var dist_yd = cur_data["dist_yd"]
	var speed_mph = 55.0 + float(dist_yd) * 0.38
	var spin_sign = -1.0 if cur_data["side"] == "draw" else 1.0
	var test_data = {
		"Speed": speed_mph,
		"VLA": 13.5,
		"HLA": 0.5 * spin_sign,
		"SpinAxis": -18.0 * spin_sign,
		"TotalSpin": 2800.0,
		"BackSpin": 2600.0,
		"SideSpin": -700.0 * spin_sign,
		"Club": "7i"
	}
	_on_launch_monitor_hit_ball(test_data)

# ========================================
# GUI SETUP
# ========================================

func _setup_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	hud_layer.layer = 1
	add_child(hud_layer)
	
	hud_control = Control.new()
	hud_control.name = "Control"
	hud_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_control.anchor_right = 1.0
	hud_control.anchor_bottom = 1.0
	hud_control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_control.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_control)
	
	var glass_style = StyleBoxFlat.new()
	glass_style.bg_color = Color(0.04, 0.08, 0.12, 0.88)
	glass_style.border_width_left = 2
	glass_style.border_width_top = 2
	glass_style.border_width_right = 2
	glass_style.border_width_bottom = 2
	glass_style.border_color = Color(0.24, 0.46, 0.72, 0.5)
	glass_style.corner_radius_top_left = 10
	glass_style.corner_radius_top_right = 10
	glass_style.corner_radius_bottom_right = 10
	glass_style.corner_radius_bottom_left = 10
	
	# --- 1. TOP SCOREBOARD ---
	var score_panel = PanelContainer.new()
	score_panel.custom_minimum_size = Vector2(840, 92)
	score_panel.anchor_left = 0.5
	score_panel.anchor_right = 0.5
	score_panel.anchor_top = 0.0
	score_panel.anchor_bottom = 0.0
	score_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_panel.offset_left = -420
	score_panel.offset_right = 420
	score_panel.offset_top = 20
	score_panel.offset_bottom = 112
	score_panel.add_theme_stylebox_override("panel", glass_style)
	hud_control.add_child(score_panel)
	
	var score_margin = MarginContainer.new()
	score_margin.add_theme_constant_override("margin_left", 20)
	score_margin.add_theme_constant_override("margin_right", 20)
	score_panel.add_child(score_margin)
	
	var score_hbox = HBoxContainer.new()
	score_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	score_margin.add_child(score_hbox)
	
	# Target info column
	var target_col = VBoxContainer.new()
	target_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(target_col)
	var t_sub = Label.new()
	t_sub.text = "ACTIVE TARGET"
	t_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_sub.add_theme_font_size_override("font_size", 12)
	t_sub.add_theme_color_override("font_color", Color(0.15, 0.85, 1.0))
	target_col.add_child(t_sub)
	target_title_lbl = Label.new()
	target_title_lbl.text = "150 YD DRAW ZONE"
	target_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_title_lbl.add_theme_font_size_override("font_size", 24)
	target_title_lbl.add_theme_color_override("font_color", Color.WHITE)
	target_col.add_child(target_title_lbl)
	
	# Attempts column
	var att_col = VBoxContainer.new()
	att_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	att_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(att_col)
	var att_sub = Label.new()
	att_sub.text = "ATTEMPTS"
	att_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	att_sub.add_theme_font_size_override("font_size", 14)
	att_sub.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	att_col.add_child(att_sub)
	attempts_lbl = Label.new()
	attempts_lbl.text = "0"
	attempts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attempts_lbl.add_theme_font_size_override("font_size", 26)
	attempts_lbl.add_theme_color_override("font_color", Color.WHITE)
	att_col.add_child(attempts_lbl)
	
	# Hits column
	var hits_col = VBoxContainer.new()
	hits_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hits_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(hits_col)
	var h_sub = Label.new()
	h_sub.text = "HITS"
	h_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h_sub.add_theme_font_size_override("font_size", 14)
	h_sub.add_theme_color_override("font_color", Color(0.2, 0.85, 0.35))
	hits_col.add_child(h_sub)
	hits_lbl = Label.new()
	hits_lbl.text = "0"
	hits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hits_lbl.add_theme_font_size_override("font_size", 26)
	hits_lbl.add_theme_color_override("font_color", Color.WHITE)
	hits_col.add_child(hits_lbl)
	
	# Accuracy column
	var acc_col = VBoxContainer.new()
	acc_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(acc_col)
	var acc_sub = Label.new()
	acc_sub.text = "ACCURACY"
	acc_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	acc_sub.add_theme_font_size_override("font_size", 14)
	acc_sub.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	acc_col.add_child(acc_sub)
	accuracy_lbl = Label.new()
	accuracy_lbl.text = "0%"
	accuracy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	accuracy_lbl.add_theme_font_size_override("font_size", 26)
	accuracy_lbl.add_theme_color_override("font_color", Color.WHITE)
	acc_col.add_child(accuracy_lbl)
	
	# Total Hits column
	var tot_col = VBoxContainer.new()
	tot_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tot_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(tot_col)
	var tot_sub = Label.new()
	tot_sub.text = "TOTAL HITS"
	tot_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tot_sub.add_theme_font_size_override("font_size", 14)
	tot_sub.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	tot_col.add_child(tot_sub)
	total_hits_lbl = Label.new()
	total_hits_lbl.text = "0"
	total_hits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_hits_lbl.add_theme_font_size_override("font_size", 26)
	total_hits_lbl.add_theme_color_override("font_color", Color.WHITE)
	tot_col.add_child(total_hits_lbl)
	
	# --- 1b. ON-SCREEN TARGET ZONE INDICATOR PANEL ---
	zone_indicator_panel = PanelContainer.new()
	zone_indicator_panel.custom_minimum_size = Vector2(860, 80)
	zone_indicator_panel.anchor_left = 0.5
	zone_indicator_panel.anchor_right = 0.5
	zone_indicator_panel.anchor_top = 0.0
	zone_indicator_panel.anchor_bottom = 0.0
	zone_indicator_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	zone_indicator_panel.offset_left = -430
	zone_indicator_panel.offset_right = 430
	zone_indicator_panel.offset_top = 118
	zone_indicator_panel.offset_bottom = 200
	hud_control.add_child(zone_indicator_panel)
	zone_indicator_panel.add_theme_stylebox_override("panel", glass_style)
	
	var zone_margin = MarginContainer.new()
	zone_margin.add_theme_constant_override("margin_left", 16)
	zone_margin.add_theme_constant_override("margin_right", 16)
	zone_margin.add_theme_constant_override("margin_top", 8)
	zone_margin.add_theme_constant_override("margin_bottom", 8)
	zone_indicator_panel.add_child(zone_margin)
	
	var zone_vbox = VBoxContainer.new()
	zone_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	zone_vbox.add_theme_constant_override("separation", 3)
	zone_margin.add_child(zone_vbox)
	
	var zone_top_hbox = HBoxContainer.new()
	zone_top_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	zone_vbox.add_child(zone_top_hbox)
	
	zone_target_lbl = Label.new()
	zone_target_lbl.text = "🎯 TARGET ZONE: 150 YD DRAW"
	zone_target_lbl.add_theme_font_size_override("font_size", 16)
	zone_target_lbl.add_theme_color_override("font_color", Color(0.15, 0.85, 1.0))
	zone_top_hbox.add_child(zone_target_lbl)
	
	var sep_lbl = Label.new()
	sep_lbl.text = "   |   "
	sep_lbl.add_theme_font_size_override("font_size", 14)
	sep_lbl.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	zone_top_hbox.add_child(sep_lbl)
	
	zone_bounds_lbl = Label.new()
	zone_bounds_lbl.text = "📍 HIT ZONE: 125-175 YD WALLS (≥10 FT IN FROM CLEARWAY)"
	zone_bounds_lbl.add_theme_font_size_override("font_size", 16)
	zone_bounds_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	zone_top_hbox.add_child(zone_bounds_lbl)
	
	zone_lane_graphic_lbl = Label.new()
	zone_lane_graphic_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_lane_graphic_lbl.text = "[ 🚧 WALL 125 YD ]   ━━━ ↺ HOOK LEFT (≥10 FT IN) ━━━▶   [ 🎯 150 YD ZONE ]   ◀━━━   [ 🚧 WALL 175 YD ]"
	zone_lane_graphic_lbl.add_theme_font_size_override("font_size", 14)
	zone_lane_graphic_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	zone_vbox.add_child(zone_lane_graphic_lbl)
	
	zone_instruction_lbl = Label.new()
	zone_instruction_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone_instruction_lbl.text = "Launch through center gate, shape LEFT ≥10 ft past wall start between the 125 & 175 YD walls!"
	zone_instruction_lbl.add_theme_font_size_override("font_size", 14)
	zone_instruction_lbl.add_theme_color_override("font_color", Color(0.65, 0.8, 0.95))
	zone_vbox.add_child(zone_instruction_lbl)
	
	# --- 2. TARGET SELECTOR PANEL (RIGHT SIDE) ---
	var sel_panel = PanelContainer.new()
	sel_panel.custom_minimum_size = Vector2(250, 480)
	sel_panel.anchor_left = 1.0
	sel_panel.anchor_right = 1.0
	sel_panel.anchor_top = 0.5
	sel_panel.anchor_bottom = 0.5
	sel_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sel_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	sel_panel.offset_left = -270
	sel_panel.offset_right = -20
	sel_panel.offset_top = -240
	sel_panel.offset_bottom = 240
	sel_panel.add_theme_stylebox_override("panel", glass_style)
	hud_control.add_child(sel_panel)

	# --- SHOT STATS GRID CANVAS (LEFT SIDE) ---
	var grid_canvas_script = load("res://UI/grid_canvas.gd")
	if grid_canvas_script != null:
		grid_canvas = Control.new()
		grid_canvas.name = "GridCanvas"
		grid_canvas.set_script(grid_canvas_script)
		grid_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud_control.add_child(grid_canvas)

	# --- STATS TOGGLE BUTTON (BOTTOM-LEFT CORNER) ---
	stats_btn = Button.new()
	stats_btn.name = "StatsButton"
	stats_btn.text = ""
	stats_btn.tooltip_text = "Toggle Stats (Show/Hide)"
	if ResourceLoader.exists("res://assets/images/icons/stats.svg"):
		stats_btn.icon = load("res://assets/images/icons/stats.svg")
	stats_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_btn.custom_minimum_size = Vector2(64, 64)
	_apply_circular_button_style(stats_btn, Color(0.24, 0.46, 0.72, 0.85))
	stats_btn.anchor_left = 0.0
	stats_btn.anchor_right = 0.0
	stats_btn.anchor_top = 1.0
	stats_btn.anchor_bottom = 1.0
	stats_btn.offset_left = 30
	stats_btn.offset_top = -88
	stats_btn.offset_right = 94
	stats_btn.offset_bottom = -24
	stats_btn.pressed.connect(func():
		_toggle_stats_visibility()
	)
	hud_control.add_child(stats_btn)
	
	var sel_margin = MarginContainer.new()
	sel_margin.add_theme_constant_override("margin_left", 14)
	sel_margin.add_theme_constant_override("margin_right", 14)
	sel_margin.add_theme_constant_override("margin_top", 14)
	sel_margin.add_theme_constant_override("margin_bottom", 14)
	sel_panel.add_child(sel_margin)
	
	var sel_vbox = VBoxContainer.new()
	sel_vbox.add_theme_constant_override("separation", 8)
	sel_margin.add_child(sel_vbox)
	
	var sel_title = Label.new()
	sel_title.text = "🎯 SHAPE TARGET"
	sel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel_title.add_theme_font_size_override("font_size", 16)
	sel_title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	sel_vbox.add_child(sel_title)
	
	# Side Tabs (DRAW vs FADE)
	var tabs_hbox = HBoxContainer.new()
	tabs_hbox.add_theme_constant_override("separation", 6)
	sel_vbox.add_child(tabs_hbox)
	
	draw_tab_btn = Button.new()
	draw_tab_btn.text = "DRAW ↺"
	draw_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw_tab_btn.custom_minimum_size = Vector2(0, 50)
	draw_tab_btn.add_theme_font_size_override("font_size", 16)
	draw_tab_btn.pressed.connect(func(): _switch_side("draw"))
	tabs_hbox.add_child(draw_tab_btn)
	
	fade_tab_btn = Button.new()
	fade_tab_btn.text = "FADE ↻"
	fade_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fade_tab_btn.custom_minimum_size = Vector2(0, 50)
	fade_tab_btn.add_theme_font_size_override("font_size", 16)
	fade_tab_btn.pressed.connect(func(): _switch_side("fade"))
	tabs_hbox.add_child(fade_tab_btn)
	
	# Distance Buttons (6 for active side)
	target_buttons.clear()
	for i in range(target_distances_yards.size()):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(func(dist_i = i):
			var idx = dist_i if selected_side == "draw" else (6 + dist_i)
			_select_target(idx)
		)
		sel_vbox.add_child(btn)
		target_buttons.append(btn)
		
	# Hotkey tip
	var tip_lbl = Label.new()
	tip_lbl.text = "Tab: Switch Side | 1-6: Distance"
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_lbl.add_theme_font_size_override("font_size", 13)
	tip_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	sel_vbox.add_child(tip_lbl)
	
	# --- 3. DYNAMIC BANNER ---
	banner_lbl = Label.new()
	banner_lbl.text = "Select a target zone and launch your shot through the center corridor!"
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.anchor_left = 0.5
	banner_lbl.anchor_right = 0.5
	banner_lbl.anchor_top = 0.0
	banner_lbl.anchor_bottom = 0.0
	banner_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_lbl.offset_left = -480
	banner_lbl.offset_right = 480
	banner_lbl.offset_top = 210
	banner_lbl.offset_bottom = 244
	banner_lbl.add_theme_font_size_override("font_size", 18)
	banner_lbl.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))
	banner_lbl.add_theme_constant_override("outline_size", 5)
	banner_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	hud_control.add_child(banner_lbl)
	
	# --- 4. BOTTOM CONTROLS PANEL ---
	var ctrl_panel = PanelContainer.new()
	ctrl_panel.custom_minimum_size = Vector2(420, 76)
	ctrl_panel.anchor_left = 0.5
	ctrl_panel.anchor_right = 0.5
	ctrl_panel.anchor_top = 1.0
	ctrl_panel.anchor_bottom = 1.0
	ctrl_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctrl_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ctrl_panel.offset_left = -210
	ctrl_panel.offset_right = 210
	ctrl_panel.offset_top = -94
	ctrl_panel.offset_bottom = -18
	ctrl_panel.add_theme_stylebox_override("panel", glass_style)
	hud_control.add_child(ctrl_panel)
	
	var ctrl_margin = MarginContainer.new()
	ctrl_margin.add_theme_constant_override("margin_left", 16)
	ctrl_margin.add_theme_constant_override("margin_right", 16)
	ctrl_panel.add_child(ctrl_margin)
	
	var ctrl_hbox = HBoxContainer.new()
	ctrl_hbox.add_theme_constant_override("separation", 12)
	ctrl_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_margin.add_child(ctrl_hbox)
	
	var reset_btn = Button.new()
	reset_btn.text = "RESET (R)"
	reset_btn.custom_minimum_size = Vector2(120, 52)
	_apply_btn_style(reset_btn, Color(0.48, 0.28, 0.18), Color(0.32, 0.18, 0.12))
	reset_btn.pressed.connect(_reset_ball_position)
	ctrl_hbox.add_child(reset_btn)
	
	music_toggle_btn = Button.new()
	music_toggle_btn.name = "MusicToggleButton"
	music_toggle_btn.text = ""
	music_toggle_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_toggle_btn.expand_icon = true
	music_toggle_btn.custom_minimum_size = Vector2(52, 52)
	music_toggle_btn.pressed.connect(_toggle_music)
	ctrl_hbox.add_child(music_toggle_btn)
	
	var settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.icon = load("res://Utils/Settings/Gear.png")
	settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.custom_minimum_size = Vector2(52, 52)
	_apply_btn_style(settings_btn, Color(0.18, 0.34, 0.50), Color(0.24, 0.44, 0.65))
	settings_btn.pressed.connect(_on_settings_pressed)
	ctrl_hbox.add_child(settings_btn)
	
	var exit_btn = Button.new()
	exit_btn.text = "EXIT"
	exit_btn.custom_minimum_size = Vector2(96, 52)
	_apply_btn_style(exit_btn, Color(0.36, 0.16, 0.16), Color(0.24, 0.12, 0.12))
	exit_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MiniGamesMenu/minigames_menu.tscn"))
	ctrl_hbox.add_child(exit_btn)
	
	_update_selector_buttons()
	_update_hud()
	_update_music_button_state()
	GlobalSettings.range_settings.minigame_music_enabled.setting_changed.connect(func(_val): _update_music_button_state())

# ========================================
# UI UPDATES & STYLING HELPERS
# ========================================

func _update_selector_buttons() -> void:
	if draw_tab_btn == null or fade_tab_btn == null:
		return
		
	if selected_side == "draw":
		_apply_btn_style(draw_tab_btn, Color(0.15, 0.45, 0.75), Color(0.20, 0.55, 0.85))
		_apply_btn_style(fade_tab_btn, Color(0.10, 0.14, 0.20), Color(0.16, 0.22, 0.30))
	else:
		_apply_btn_style(draw_tab_btn, Color(0.10, 0.14, 0.20), Color(0.16, 0.22, 0.30))
		_apply_btn_style(fade_tab_btn, Color(0.75, 0.40, 0.12), Color(0.85, 0.48, 0.18))
		
	var base_idx = 0 if selected_side == "draw" else 6
	for i in range(target_buttons.size()):
		var target_idx = base_idx + i
		var btn = target_buttons[i]
		var dist_yd = target_distances_yards[i]
		var front_wall = dist_yd - 25
		var back_wall = dist_yd + 25
		var stats = target_stats.get(target_idx, {"Attempts": 0, "Hits": 0})
		var hits = stats["Hits"]
		var att = stats["Attempts"]
		
		if target_idx == selected_target_index:
			btn.text = "▶ %d YD (%d-%d YD Zone) [%d/%d]" % [dist_yd, front_wall, back_wall, hits, att]
			var active_color = Color(0.2, 0.85, 1.0) if selected_side == "draw" else Color(1.0, 0.7, 0.2)
			btn.add_theme_color_override("font_color", active_color)
			_apply_btn_style(btn, Color(0.20, 0.32, 0.46), Color(0.28, 0.42, 0.58))
		else:
			btn.text = "  %d YD (%d-%d YD Zone) [%d/%d]" % [dist_yd, front_wall, back_wall, hits, att]
			btn.remove_theme_color_override("font_color")
			_apply_btn_style(btn, Color(0.08, 0.13, 0.18), Color(0.14, 0.22, 0.30))

func _update_hud() -> void:
	if attempts_lbl == null:
		return
	var cur_data = target_data[selected_target_index]
	var stats = target_stats.get(selected_target_index, {"Attempts": 0, "Hits": 0})
	var att = stats["Attempts"]
	var hits = stats["Hits"]
	var acc = (float(hits) / float(att) * 100.0) if att > 0 else 0.0
	
	target_title_lbl.text = "%d YD %s ZONE" % [cur_data["dist_yd"], cur_data["side"].to_upper()]
	target_title_lbl.add_theme_color_override("font_color", cur_data["color"])
	
	attempts_lbl.text = str(att)
	hits_lbl.text = str(hits)
	accuracy_lbl.text = "%.0f%%" % acc
	total_hits_lbl.text = str(total_greens_hit)
	
	_update_zone_hud()

func _update_zone_hud() -> void:
	if zone_target_lbl == null:
		return
	var cur_data = target_data[selected_target_index]
	var dist_yd = cur_data["dist_yd"]
	var front_wall = cur_data["front_wall_yd"]
	var back_wall = cur_data["back_wall_yd"]
	var side = cur_data["side"]
	var side_upper = side.to_upper()
	var color = cur_data["color"]
	
	var shape_arrow = "↺ HOOK LEFT" if side == "draw" else "↻ SLICE RIGHT"
	var zone_icon = "🎯"
	
	zone_target_lbl.text = "🎯 TARGET ZONE: %d YD %s" % [dist_yd, side_upper]
	zone_target_lbl.add_theme_color_override("font_color", color)
	
	zone_bounds_lbl.text = "📍 HIT ZONE: %d-%d YD WALLS (≥10 FT IN FROM CLEARWAY)" % [front_wall, back_wall]
	
	if zone_indicator_panel:
		var style: StyleBoxFlat = zone_indicator_panel.get_theme_stylebox("panel")
		if style:
			style.border_color = Color(color.r, color.g, color.b, 0.75)
			
	if side == "draw":
		zone_lane_graphic_lbl.text = "[ 🚧 WALL %d YD ]   ━━━ %s (≥10 FT IN) ━━━▶   [ %s %d YD ZONE ]   ◀━━━   [ 🚧 WALL %d YD ]" % [front_wall, shape_arrow, zone_icon, dist_yd, back_wall]
		zone_instruction_lbl.text = "Launch straight through center gate, shape LEFT ≥10 ft past wall start between the %d & %d YD walls!" % [front_wall, back_wall]
	else:
		zone_lane_graphic_lbl.text = "[ 🚧 WALL %d YD ]   ━━━ %s (≥10 FT IN) ━━━▶   [ %s %d YD ZONE ]   ◀━━━   [ 🚧 WALL %d YD ]" % [front_wall, shape_arrow, zone_icon, dist_yd, back_wall]
		zone_instruction_lbl.text = "Launch straight through center gate, shape RIGHT ≥10 ft past wall start between the %d & %d YD walls!" % [front_wall, back_wall]

func _show_banner(text: String) -> void:
	if banner_lbl:
		banner_lbl.text = text

func _toggle_music() -> void:
	var current = GlobalSettings.range_settings.minigame_music_enabled.value
	GlobalSettings.range_settings.minigame_music_enabled.set_value(not current)
	_update_music_button_state()

func _update_music_button_state() -> void:
	if music_toggle_btn == null:
		return
	var is_enabled: bool = GlobalSettings.range_settings.minigame_music_enabled.value
	if is_enabled:
		if ResourceLoader.exists("res://assets/images/menu/music_on.svg"):
			music_toggle_btn.icon = load("res://assets/images/menu/music_on.svg")
		music_toggle_btn.tooltip_text = "Music: Playing (Click to mute)"
		_apply_btn_style(music_toggle_btn, Color(0.14, 0.32, 0.22), Color(0.20, 0.44, 0.30))
	else:
		if ResourceLoader.exists("res://assets/images/menu/music_off.svg"):
			music_toggle_btn.icon = load("res://assets/images/menu/music_off.svg")
		music_toggle_btn.tooltip_text = "Music: Muted (Click to play)"
		_apply_btn_style(music_toggle_btn, Color(0.35, 0.18, 0.18), Color(0.48, 0.24, 0.24))

func _apply_btn_style(btn: Button, norm_color: Color, hov_color: Color) -> void:
	var style_norm = StyleBoxFlat.new()
	style_norm.bg_color = norm_color
	style_norm.corner_radius_top_left = 6
	style_norm.corner_radius_top_right = 6
	style_norm.corner_radius_bottom_right = 6
	style_norm.corner_radius_bottom_left = 6
	style_norm.border_width_left = 1
	style_norm.border_width_top = 1
	style_norm.border_width_right = 1
	style_norm.border_width_bottom = 1
	style_norm.border_color = Color(1, 1, 1, 0.15)
	
	var style_hov = StyleBoxFlat.new()
	style_hov.bg_color = hov_color
	style_hov.corner_radius_top_left = 6
	style_hov.corner_radius_top_right = 6
	style_hov.corner_radius_bottom_right = 6
	style_hov.corner_radius_bottom_left = 6
	style_hov.border_width_left = 1
	style_hov.border_width_top = 1
	style_hov.border_width_right = 1
	style_hov.border_width_bottom = 1
	style_hov.border_color = Color(1, 1, 1, 0.35)
	
	btn.add_theme_stylebox_override("normal", style_norm)
	btn.add_theme_stylebox_override("hover", style_hov)
	btn.add_theme_stylebox_override("pressed", style_hov)
	btn.add_theme_stylebox_override("focus", style_norm)
	btn.add_theme_color_override("font_color", Color.WHITE)
	if btn.custom_minimum_size.y < 48:
		btn.custom_minimum_size.y = 48
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", 16)

func _apply_circular_button_style(btn: Button, bg_color: Color) -> void:
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 32
	style_normal.corner_radius_top_right = 32
	style_normal.corner_radius_bottom_left = 32
	style_normal.corner_radius_bottom_right = 32
	style_normal.border_width_left = 2
	style_normal.border_width_top = 2
	style_normal.border_width_right = 2
	style_normal.border_width_bottom = 2
	style_normal.border_color = bg_color.lightened(0.25)
	
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)
	style_hover.border_color = Color(1.0, 1.0, 1.0, 0.5)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("focus", style_normal)

func is_stats_visible() -> bool:
	if grid_canvas == null:
		return true
	var dist_panel = grid_canvas.get_node_or_null("Distance")
	return dist_panel.visible if dist_panel != null else grid_canvas.visible

func _toggle_stats_visibility() -> void:
	var show_stats = not is_stats_visible()
	if grid_canvas != null:
		for child in grid_canvas.get_children():
			if child.name != "ClubSelector":
				child.visible = show_stats
	if stats_btn != null:
		if show_stats:
			_apply_circular_button_style(stats_btn, Color(0.24, 0.46, 0.72, 0.85))
		else:
			_apply_circular_button_style(stats_btn, Color(0.15, 0.15, 0.15, 0.85))

func _update_stats_display(is_final_rest: bool = true) -> void:
	if grid_canvas == null or player == null:
		return
	var units = GlobalSettings.range_settings.range_units.value if has_node("/root/GlobalSettings") else PhysicsEnums.Units.IMPERIAL
	display_data = ShotFormatter.format_ball_display(raw_ball_data, player, units, is_final_rest, display_data)
	var is_imperial: bool = (units == PhysicsEnums.Units.IMPERIAL)
	
	for child in grid_canvas.get_children():
		if child.name == "ClubSelector":
			continue
		var stat_id = child.name
		var stat_def = StatDefinitions.get_stat_by_id(stat_id)
		if stat_def.is_empty():
			continue
		var u_str: String = str(stat_def.get("units_imperial" if is_imperial else "units_metric", ""))
		if child.has_method("set_units"):
			child.call("set_units", u_str)
		var val = display_data.get(stat_id, "---")
		if stat_id == "VLA" or stat_id == "HLA":
			if val != "---":
				var float_val = float(val)
				val = "%.1f°" % float_val
		if child.has_method("set_data"):
			child.call("set_data", str(val))

# ========================================
# SETTINGS MODAL
# ========================================

func _on_settings_pressed() -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		return
		
	var settings_scene = load("res://Utils/Settings/Settings.tscn")
	if settings_scene:
		var settings_inst = settings_scene.instantiate()
		_settings_layer = CanvasLayer.new()
		_settings_layer.name = "SettingsModalLayer"
		_settings_layer.layer = 100
		_settings_layer.add_child(settings_inst)
		add_child(_settings_layer)
		
		# Hook close button / back
		var close_btn = settings_inst.find_child("CloseButton", true, false)
		if close_btn == null:
			close_btn = settings_inst.find_child("BackButton", true, false)
		if close_btn and close_btn is Button:
			close_btn.pressed.connect(_close_settings)

func _close_settings() -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		_settings_layer.queue_free()
		_settings_layer = null
