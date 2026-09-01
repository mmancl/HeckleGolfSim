extends Node3D

# Preloaded player scene
var PlayerScene = preload("res://Player/player.tscn")

# Minigame state
var player = null
var selected_target_index: int = 2 # Default: 150 YD Draw (index 2)
var selected_side: String = "draw" # "draw" (left) or "fade" (right)

# Distances in yards
var target_distances_yards: Array[int] = [50, 100, 150, 200, 250, 300]

# Wall distances in yards
var wall_distances_yards: Array[int] = [25, 50, 75, 100, 125, 150, 175, 200, 225, 250, 275]

# Data structures:
# 12 targets: indices 0..5 are DRAW (Left, -Z), indices 6..11 are FADE (Right, +Z)
var target_positions: Array[Vector3] = []
var target_data: Array[Dictionary] = []
var target_stats: Dictionary = {}
var total_greens_hit: int = 0

# Wall data
var wall_nodes: Array[StaticBody3D] = []

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
var _settings_layer: CanvasLayer = null

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
	
	# 6. Target Greens (12 total: 6 Left Draw, 6 Right Fade)
	_setup_target_greens()
	
	# 7. Obstacle Barrier Walls (every 25 yards)
	_setup_barrier_walls()
	
	# 8. Setup Player
	_setup_player()
	
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
# TARGET DATA INITIALIZATION
# ========================================

func _init_target_data() -> void:
	target_positions.clear()
	target_data.clear()
	target_stats.clear()
	
	var YARD_TO_M = 0.9144
	var angle_deg = 15.5 # Lateral angle off center axis
	var angle_rad = deg_to_rad(angle_deg)
	
	# 6 DRAW targets (indices 0..5, Left / -Z)
	for i in range(target_distances_yards.size()):
		var dist_yd = target_distances_yards[i]
		var dist_m = dist_yd * YARD_TO_M
		var x = dist_m * cos(angle_rad)
		var z = -dist_m * sin(angle_rad) # Negative Z is Left (Draw)
		var pos = Vector3(x, 0.0, z)
		target_positions.append(pos)
		
		# Radius scales from 5.5m at 50 yd up to 13.0m at 300 yd
		var green_radius = 5.5 + float(i) * 1.5
		
		target_data.append({
			"index": i,
			"side": "draw",
			"side_label": "Draw (Left)",
			"dist_yd": dist_yd,
			"dist_m": dist_m,
			"pos": pos,
			"green_radius": green_radius,
			"color": Color(0.15, 0.75, 1.0) # Bright Cyan-Blue for Draw
		})
		target_stats[i] = {"Attempts": 0, "Hits": 0}
		
	# 6 FADE targets (indices 6..11, Right / +Z)
	for i in range(target_distances_yards.size()):
		var dist_yd = target_distances_yards[i]
		var dist_m = dist_yd * YARD_TO_M
		var x = dist_m * cos(angle_rad)
		var z = dist_m * sin(angle_rad) # Positive Z is Right (Fade)
		var pos = Vector3(x, 0.0, z)
		target_positions.append(pos)
		
		var green_radius = 5.5 + float(i) * 1.5
		var global_idx = 6 + i
		
		target_data.append({
			"index": global_idx,
			"side": "fade",
			"side_label": "Fade (Right)",
			"dist_yd": dist_yd,
			"dist_m": dist_m,
			"pos": pos,
			"green_radius": green_radius,
			"color": Color(1.0, 0.55, 0.15) # Warm Amber-Orange for Fade
		})
		target_stats[global_idx] = {"Attempts": 0, "Hits": 0}

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
	# Directional Sun Light
	var sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(-48)).rotated(Vector3.UP, deg_to_rad(30))
	sun.shadow_enabled = true
	sun.light_energy = 1.2
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
	camera.global_position = default_cam_pos
	camera.look_at(default_look_target)
	add_child(camera)
	
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
# TARGET GREENS GENERATION
# ========================================

func _setup_target_greens() -> void:
	for i in range(target_data.size()):
		var data = target_data[i]
		var green_node = _build_target_green_node(data)
		add_child(green_node)

func _build_target_green_node(data: Dictionary) -> StaticBody3D:
	var idx = data["index"]
	var pos = data["pos"]
	var radius = data["green_radius"]
	var dist_yd = data["dist_yd"]
	var side = data["side"]
	var theme_color = data["color"]
	
	var green_body = StaticBody3D.new()
	green_body.name = "TargetGreen_%d" % idx
	green_body.set_meta("surface_type", 4) # GREEN (4)
	green_body.set_meta("target_index", idx)
	green_body.position = pos
	
	# 1. Putting Green Surface Mesh & Collision
	var green_mesh_inst = MeshInstance3D.new()
	var cyl_mesh = CylinderMesh.new()
	cyl_mesh.top_radius = radius
	cyl_mesh.bottom_radius = radius * 1.02
	cyl_mesh.height = 0.06
	cyl_mesh.radial_segments = 36
	green_mesh_inst.mesh = cyl_mesh
	green_mesh_inst.material_override = green_mat
	green_mesh_inst.position = Vector3(0.0, 0.03, 0.0)
	green_body.add_child(green_mesh_inst)
	
	var green_col = CollisionShape3D.new()
	var cyl_col_shape = CylinderShape3D.new()
	cyl_col_shape.radius = radius
	cyl_col_shape.height = 0.1
	green_col.shape = cyl_col_shape
	green_col.position = Vector3(0.0, 0.03, 0.0)
	green_body.add_child(green_col)
	
	# 2. Fringe / Rough Collar Ring around the green
	var collar_mesh_inst = MeshInstance3D.new()
	var collar_cyl = CylinderMesh.new()
	collar_cyl.top_radius = radius + 2.0
	collar_cyl.bottom_radius = radius + 2.2
	collar_cyl.height = 0.04
	collar_cyl.radial_segments = 36
	collar_mesh_inst.mesh = collar_cyl
	collar_mesh_inst.material_override = fringe_mat
	collar_mesh_inst.position = Vector3(0.0, 0.015, 0.0)
	green_body.add_child(collar_mesh_inst)
	
	# 3. Cup / Hole Mesh (Dark Center Cylinder)
	var cup_mesh_inst = MeshInstance3D.new()
	var cup_cyl = CylinderMesh.new()
	cup_cyl.top_radius = 0.12
	cup_cyl.bottom_radius = 0.12
	cup_cyl.height = 0.15
	cup_cyl.radial_segments = 16
	cup_mesh_inst.mesh = cup_cyl
	var cup_mat = StandardMaterial3D.new()
	cup_mat.albedo_color = Color(0.04, 0.04, 0.04)
	cup_mat.roughness = 0.95
	cup_mesh_inst.material_override = cup_mat
	cup_mesh_inst.position = Vector3(0.0, 0.0, 0.0)
	green_body.add_child(cup_mesh_inst)
	
	# 4. Flagpole & Flag
	var pin_node = Node3D.new()
	pin_node.name = "FlagPin"
	pin_node.position = Vector3(0.0, 0.05, 0.0)
	green_body.add_child(pin_node)
	
	var pole = MeshInstance3D.new()
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.02
	pole_mesh.bottom_radius = 0.02
	pole_mesh.height = 2.4
	pole.mesh = pole_mesh
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color.WHITE
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, 1.2, 0.0)
	pin_node.add_child(pole)
	
	var flag = MeshInstance3D.new()
	var flag_mesh = PrismMesh.new()
	flag_mesh.size = Vector3(0.48, 0.34, 0.02)
	flag.mesh = flag_mesh
	var flag_m = StandardMaterial3D.new()
	flag_m.albedo_color = theme_color
	flag_m.emission_enabled = true
	flag_m.emission = theme_color
	flag_m.emission_energy_multiplier = 0.7
	flag.material_override = flag_m
	flag.position = Vector3(0.24, 2.2, 0.0)
	flag.rotation = Vector3(0.0, 0.0, -PI / 2)
	pin_node.add_child(flag)
	
	# 5. Distance & Side Label (Billboarded in 3D)
	var label = Label3D.new()
	var side_code = "DRAW" if side == "draw" else "FADE"
	label.text = "%d YDS\n(%s)" % [dist_yd, side_code]
	label.font_size = 46
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 10
	label.modulate = Color.WHITE
	label.outline_modulate = Color(0, 0, 0, 0.95)
	label.position = Vector3(0.0, 3.2, 0.0)
	pin_node.add_child(label)
	
	return green_body

# ========================================
# OBSTACLE BARRIER WALLS SETUP
# ========================================

func _setup_barrier_walls() -> void:
	wall_nodes.clear()
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
	
	# Top Cap Trim Beam
	var cap_inst = MeshInstance3D.new()
	var cap_mesh = BoxMesh.new()
	cap_mesh.size = Vector3(size.x * 1.3, 0.4, size.z * 1.01)
	cap_inst.mesh = cap_mesh
	cap_inst.material_override = cap_mat
	cap_inst.position = Vector3(0.0, size.y / 2.0 + 0.2, 0.0)
	wall.add_child(cap_inst)
	
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
	
	return wall

# ========================================
# TARGET SELECTION & HIGHLIGHT
# ========================================

func _select_target(index: int) -> void:
	if index < 0 or index >= target_data.size():
		return
		
	selected_target_index = index
	var cur_data = target_data[index]
	selected_side = cur_data["side"]
	
	# Update glowing target ring on target greens
	for i in range(target_data.size()):
		var green_node = get_node_or_null("TargetGreen_%d" % i)
		if green_node:
			var old_ring = green_node.get_node_or_null("TargetRing")
			if old_ring:
				old_ring.queue_free()
				
			if i == index:
				var ring_radius = target_data[i]["green_radius"]
				var ring = MeshInstance3D.new()
				ring.name = "TargetRing"
				var ring_mesh = TorusMesh.new()
				ring_mesh.inner_radius = ring_radius + 0.2
				ring_mesh.outer_radius = ring_radius + 0.85
				ring_mesh.rings = 40
				ring_mesh.ring_segments = 12
				ring.mesh = ring_mesh
				
				var ring_mat = StandardMaterial3D.new()
				var c = cur_data["color"]
				ring_mat.albedo_color = Color(c.r, c.g, c.b, 0.8)
				ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ring_mat.emission_enabled = true
				ring_mat.emission = c
				ring_mat.emission_energy_multiplier = 1.0
				ring.material_override = ring_mat
				ring.position = Vector3(0.0, 0.08, 0.0)
				green_node.add_child(ring)
				
	_update_selector_buttons()
	_update_hud()
	_reset_ball_position()
	
	var curve_dir = "left" if cur_data["side"] == "draw" else "right"
	_show_banner("🎯 Target: %d YD %s — Launch through center gate and shape %s onto green!" % [
		cur_data["dist_yd"],
		cur_data["side"].to_upper(),
		curve_dir
	])

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
					if closest_idx != -1 and min_dist <= target_data[closest_idx]["green_radius"] + 8.0:
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

# ========================================
# LAUNCH MONITOR & HIT PROCESSING
# ========================================

func _on_launch_monitor_hit_ball(data: Dictionary) -> void:
	if player == null or player.ball == null:
		return
	if player.ball.state != PhysicsEnums.BallState.REST:
		return # Ignore if shot already in flight

	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()

	player._on_tcp_client_hit_ball(data)

	var speed_mph = data.get("Speed", 0.0)
	var vla = data.get("VLA", 0.0)
	var hla = data.get("HLA", 0.0)
	_show_banner("Shot Launched! Speed: %.1f mph | Launch: %.1f° | HLA: %.1f°" % [speed_mph, vla, hla])

# ========================================
# CAMERA FOLLOW & FLIGHT TICK
# ========================================

func _physics_process(delta: float) -> void:
	if player and player.ball:
		var ball_state = player.ball.state
		if ball_state == PhysicsEnums.BallState.FLIGHT or ball_state == PhysicsEnums.BallState.ROLLOUT:
			camera_following = true
			var ball_pos = player.ball.global_position
			var target_cam_pos = ball_pos + last_camera_offset
			$Camera3D.global_position = $Camera3D.global_position.lerp(target_cam_pos, delta * 7.0)
			$Camera3D.look_at(ball_pos + Vector3.UP * 0.2)
		else:
			if camera_following:
				camera_following = false
				if has_node("/root/TensionManager"):
					TensionManager.stop_tension()

# ========================================
# BALL REST & SCORING
# ========================================

func _on_ball_rest(_shot_data: Dictionary) -> void:
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
		
	var final_pos = player.ball.global_position
	var cur_data = target_data[selected_target_index]
	var target_pos = cur_data["pos"]
	var green_radius = cur_data["green_radius"]
	
	var dist_m = Vector2(final_pos.x, final_pos.z).distance_to(Vector2(target_pos.x, target_pos.z))
	var dist_yds = dist_m * 1.09361
	
	target_stats[selected_target_index]["Attempts"] += 1
	
	# Did we land on the selected green?
	if dist_m <= green_radius:
		target_stats[selected_target_index]["Hits"] += 1
		total_greens_hit += 1
		GlobalSettings.play_golf_clap()
		_show_banner("🟢 GREEN HIT! Magnificent %s shape onto the %d YD green! (%d total greens hit)" % [
			cur_data["side"].to_upper(),
			cur_data["dist_yd"],
			total_greens_hit
		])
	else:
		# Check if landed on another green
		var landed_other = false
		for i in range(target_data.size()):
			if i == selected_target_index:
				continue
			var d_other = Vector2(final_pos.x, final_pos.z).distance_to(Vector2(target_data[i]["pos"].x, target_data[i]["pos"].z))
			if d_other <= target_data[i]["green_radius"]:
				landed_other = true
				_show_banner("Landed on the %d YD %s green — but you were targeting %d YD %s!" % [
					target_data[i]["dist_yd"],
					target_data[i]["side"].to_upper(),
					cur_data["dist_yd"],
					cur_data["side"].to_upper()
				])
				break
		if not landed_other:
			_show_banner("Missed target green. Distance to pin: %.1f yds (Shape more %s through center gate!)" % [
				dist_yds,
				cur_data["side"].to_upper()
			])
			
	_update_selector_buttons()
	_update_hud()
	
	# Auto reset after 3.5 seconds
	await get_tree().create_timer(3.5).timeout
	_reset_ball_position()

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
	target_title_lbl.text = "150 YD DRAW"
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
	att_sub.add_theme_font_size_override("font_size", 12)
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
	h_sub.add_theme_font_size_override("font_size", 12)
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
	acc_sub.add_theme_font_size_override("font_size", 12)
	acc_sub.add_theme_color_override("font_color", Color(0.95, 0.75, 0.15))
	acc_col.add_child(acc_sub)
	accuracy_lbl = Label.new()
	accuracy_lbl.text = "0%"
	accuracy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	accuracy_lbl.add_theme_font_size_override("font_size", 26)
	accuracy_lbl.add_theme_color_override("font_color", Color.WHITE)
	acc_col.add_child(accuracy_lbl)
	
	# Total Greens Hit column
	var tot_col = VBoxContainer.new()
	tot_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tot_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(tot_col)
	var tot_sub = Label.new()
	tot_sub.text = "TOTAL GREENS"
	tot_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tot_sub.add_theme_font_size_override("font_size", 12)
	tot_sub.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	tot_col.add_child(tot_sub)
	total_hits_lbl = Label.new()
	total_hits_lbl.text = "0"
	total_hits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_hits_lbl.add_theme_font_size_override("font_size", 26)
	total_hits_lbl.add_theme_color_override("font_color", Color.WHITE)
	tot_col.add_child(total_hits_lbl)
	
	# --- 2. LEFT TARGET SELECTOR PANEL ---
	var sel_panel = PanelContainer.new()
	sel_panel.custom_minimum_size = Vector2(230, 440)
	sel_panel.anchor_left = 0.0
	sel_panel.anchor_top = 0.5
	sel_panel.anchor_bottom = 0.5
	sel_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	sel_panel.offset_left = 24
	sel_panel.offset_top = -220
	sel_panel.offset_bottom = 220
	sel_panel.add_theme_stylebox_override("panel", glass_style)
	hud_control.add_child(sel_panel)
	
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
	sel_title.add_theme_font_size_override("font_size", 14)
	sel_title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	sel_vbox.add_child(sel_title)
	
	# Side Tabs (DRAW vs FADE)
	var tabs_hbox = HBoxContainer.new()
	tabs_hbox.add_theme_constant_override("separation", 6)
	sel_vbox.add_child(tabs_hbox)
	
	draw_tab_btn = Button.new()
	draw_tab_btn.text = "DRAW ↺"
	draw_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw_tab_btn.custom_minimum_size = Vector2(0, 32)
	draw_tab_btn.pressed.connect(func(): _switch_side("draw"))
	tabs_hbox.add_child(draw_tab_btn)
	
	fade_tab_btn = Button.new()
	fade_tab_btn.text = "FADE ↻"
	fade_tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fade_tab_btn.custom_minimum_size = Vector2(0, 32)
	fade_tab_btn.pressed.connect(func(): _switch_side("fade"))
	tabs_hbox.add_child(fade_tab_btn)
	
	# Distance Buttons (6 for active side)
	target_buttons.clear()
	for i in range(target_distances_yards.size()):
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 38)
		btn.add_theme_font_size_override("font_size", 13)
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
	tip_lbl.add_theme_font_size_override("font_size", 11)
	tip_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	sel_vbox.add_child(tip_lbl)
	
	# --- 3. DYNAMIC BANNER ---
	banner_lbl = Label.new()
	banner_lbl.text = "Select a target green and launch your shot through the center corridor!"
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.anchor_left = 0.5
	banner_lbl.anchor_right = 0.5
	banner_lbl.anchor_top = 0.22
	banner_lbl.anchor_bottom = 0.22
	banner_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_lbl.add_theme_font_size_override("font_size", 22)
	banner_lbl.add_theme_color_override("font_color", Color(1, 1, 0.5, 1.0))
	banner_lbl.add_theme_constant_override("outline_size", 4)
	banner_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hud_control.add_child(banner_lbl)
	
	# --- 4. BOTTOM CONTROLS PANEL ---
	var ctrl_panel = PanelContainer.new()
	ctrl_panel.custom_minimum_size = Vector2(360, 68)
	ctrl_panel.anchor_left = 0.5
	ctrl_panel.anchor_right = 0.5
	ctrl_panel.anchor_top = 1.0
	ctrl_panel.anchor_bottom = 1.0
	ctrl_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctrl_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ctrl_panel.offset_left = -180
	ctrl_panel.offset_right = 180
	ctrl_panel.offset_top = -88
	ctrl_panel.offset_bottom = -20
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
	reset_btn.custom_minimum_size = Vector2(100, 42)
	_apply_btn_style(reset_btn, Color(0.48, 0.28, 0.18), Color(0.32, 0.18, 0.12))
	reset_btn.pressed.connect(_reset_ball_position)
	ctrl_hbox.add_child(reset_btn)
	
	music_toggle_btn = Button.new()
	music_toggle_btn.name = "MusicToggleButton"
	music_toggle_btn.text = ""
	music_toggle_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_toggle_btn.expand_icon = true
	music_toggle_btn.custom_minimum_size = Vector2(42, 42)
	music_toggle_btn.pressed.connect(_toggle_music)
	ctrl_hbox.add_child(music_toggle_btn)
	
	var settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.icon = load("res://Utils/Settings/Gear.png")
	settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.custom_minimum_size = Vector2(42, 42)
	_apply_btn_style(settings_btn, Color(0.18, 0.34, 0.50), Color(0.24, 0.44, 0.65))
	settings_btn.pressed.connect(_on_settings_pressed)
	ctrl_hbox.add_child(settings_btn)
	
	var exit_btn = Button.new()
	exit_btn.text = "EXIT"
	exit_btn.custom_minimum_size = Vector2(80, 42)
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
		var stats = target_stats.get(target_idx, {"Attempts": 0, "Hits": 0})
		var hits = stats["Hits"]
		var att = stats["Attempts"]
		
		if target_idx == selected_target_index:
			btn.text = "▶ %d YD  (%d/%d)" % [dist_yd, hits, att]
			var active_color = Color(0.2, 0.85, 1.0) if selected_side == "draw" else Color(1.0, 0.7, 0.2)
			btn.add_theme_color_override("font_color", active_color)
			_apply_btn_style(btn, Color(0.20, 0.32, 0.46), Color(0.28, 0.42, 0.58))
		else:
			btn.text = "  %d YD  (%d/%d)" % [dist_yd, hits, att]
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
	
	target_title_lbl.text = "%d YD %s" % [cur_data["dist_yd"], cur_data["side"].to_upper()]
	target_title_lbl.add_theme_color_override("font_color", cur_data["color"])
	
	attempts_lbl.text = str(att)
	hits_lbl.text = str(hits)
	accuracy_lbl.text = "%.0f%%" % acc
	total_hits_lbl.text = str(total_greens_hit)

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
