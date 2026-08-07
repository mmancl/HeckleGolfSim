extends Node3D

# Preloaded assets
var PlayerScene = preload("res://Player/player.tscn")

# Minigame state variables
var player = null
var selected_island_index = 0 # Default target is 50 yds
var user_aim_offset_deg = 0.0

# Camera follow state
var last_camera_offset = Vector3.ZERO
var camera_following = false
var is_dragging = false

# Stats structure: dictionary key is island index, val is dictionary with Attempts and Hits
var island_stats = {}
var total_greens_hit = 0

# Island configurations: 4 greens at 50, 100, 150, 200 yards
var island_distances_yards = [50, 100, 150, 200]

# Fan layout: 50y left, 100y right, 150y far left, 200y far right
# Angles from straight ahead (positive = left, negative = right)
var island_angles_deg = [35.0, -25.0, 45.0, -35.0]

var island_positions = [] # Computed world positions
var island_data = [] # Detailed procedural shape and layout data per island
var island_buttons = []

# UI elements
var target_info_lbl = null
var attempts_lbl = null
var hits_lbl = null
var accuracy_lbl = null
var total_hits_lbl = null

var power_slider = null
var power_val_lbl = null
var vla_slider = null
var vla_val_lbl = null
var aim_slider = null
var aim_val_lbl = null
var banner_lbl = null

# Materials
var green_mat: StandardMaterial3D
var fringe_mat: StandardMaterial3D
var sand_mat: StandardMaterial3D
var mulch_mat: StandardMaterial3D
var wall_mat: StandardMaterial3D
var cap_mat: StandardMaterial3D
var dock_mat: StandardMaterial3D

func _ready() -> void:
	name = "ChippingPractice"
	
	# 1. Compute island world positions from distance + angle fan layout
	for i in range(island_distances_yards.size()):
		island_stats[i] = {"Attempts": 0, "Hits": 0}
		var dist_meters = island_distances_yards[i] * 0.9144 # yards to meters
		var angle_rad = deg_to_rad(island_angles_deg[i])
		var x = dist_meters * cos(angle_rad)
		var z = dist_meters * sin(angle_rad)
		island_positions.append(Vector3(x, 0.0, z))
	
	# 2. Init Materials
	_init_materials()
	
	# 3. Environment Setup
	_setup_environment()
	
	# 4. Setup Water Hazard Pool
	_setup_water_hazard()
	
	# 5. Setup Tee Box (player standing area)
	_setup_tee_box()
	
	# 6. Setup 4 Floating Golf Course Island Greens
	_setup_islands()
	
	# 7. Setup Player
	_setup_player()
	
	# 8. Setup GUI
	_setup_ui()
	
	# Select default target
	_select_target_island(selected_island_index)
	
	if has_node("/root/LaunchMonitorManager"):
		var launch_monitor = get_node("/root/LaunchMonitorManager")
		if not launch_monitor.hit_ball.is_connected(_on_launch_monitor_hit_ball):
			launch_monitor.hit_ball.connect(_on_launch_monitor_hit_ball)

# ========================================
# MATERIAL INITIALIZATION
# ========================================

func _init_materials() -> void:
	# Putting Green surface
	green_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-green/albedo.png"):
		green_mat.albedo_texture = load("res://Courses/Environments/grass-green/albedo.png")
		green_mat.albedo_color = Color(0.9, 1.0, 0.9)
		green_mat.uv1_scale = Vector3(0.12, 0.12, 0.12)
	else:
		green_mat.albedo_color = Color(0.16, 0.65, 0.22)
	green_mat.roughness = 0.88
	
	# Rough grass surround for floating island platform
	fringe_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-rough/albedo.png"):
		fringe_mat.albedo_texture = load("res://Courses/Environments/grass-rough/albedo.png")
		if ResourceLoader.exists("res://Courses/Environments/grass-rough/normal.png"):
			fringe_mat.normal_enabled = true
			fringe_mat.normal_texture = load("res://Courses/Environments/grass-rough/normal.png")
		fringe_mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
	elif ResourceLoader.exists("res://Courses/Environments/grass-green/albedo.png"):
		fringe_mat.albedo_texture = load("res://Courses/Environments/grass-green/albedo.png")
		fringe_mat.albedo_color = Color(0.28, 0.52, 0.22) # Darker rough green tint
		fringe_mat.uv1_scale = Vector3(0.15, 0.15, 0.15)
	else:
		fringe_mat.albedo_color = Color(0.12, 0.42, 0.14)
	fringe_mat.roughness = 0.95
	
	# Sand trap / bunker
	sand_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/sand-bunker/albedo.png"):
		sand_mat.albedo_texture = load("res://Courses/Environments/sand-bunker/albedo.png")
		sand_mat.albedo_color = Color(1.0, 0.96, 0.82)
		sand_mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
	else:
		sand_mat.albedo_color = Color(0.94, 0.88, 0.70)
	sand_mat.roughness = 0.9
	
	# Red mulch / flowerbed accent zones
	mulch_mat = StandardMaterial3D.new()
	mulch_mat.albedo_color = Color(0.38, 0.16, 0.11)
	mulch_mat.roughness = 0.95
	
	# Wood retaining wall logs/planks with real bark/wood texture
	wall_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/tree-bark/albedo.png"):
		wall_mat.albedo_texture = load("res://Courses/Environments/tree-bark/albedo.png")
		if ResourceLoader.exists("res://Courses/Environments/tree-bark/normal.png"):
			wall_mat.normal_enabled = true
			wall_mat.normal_texture = load("res://Courses/Environments/tree-bark/normal.png")
		if ResourceLoader.exists("res://Courses/Environments/tree-bark/roughness.png"):
			wall_mat.roughness_texture = load("res://Courses/Environments/tree-bark/roughness.png")
		wall_mat.uv1_scale = Vector3(0.3, 0.3, 0.3)
		wall_mat.uv1_triplanar = true
	else:
		wall_mat.albedo_color = Color(0.26, 0.18, 0.11)
	wall_mat.roughness = 0.85
	
	# Dark wood cap trim
	cap_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/tree-bark/albedo.png"):
		cap_mat.albedo_texture = load("res://Courses/Environments/tree-bark/albedo.png")
		cap_mat.albedo_color = Color(0.5, 0.4, 0.35)
		cap_mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
	else:
		cap_mat.albedo_color = Color(0.18, 0.12, 0.07)
	cap_mat.roughness = 0.8
	
	# Wooden dock
	dock_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/tree-bark/albedo.png"):
		dock_mat.albedo_texture = load("res://Courses/Environments/tree-bark/albedo.png")
		dock_mat.albedo_color = Color(0.7, 0.6, 0.5)
		dock_mat.uv1_scale = Vector3(0.4, 0.4, 0.4)
	else:
		dock_mat.albedo_color = Color(0.42, 0.32, 0.21)
	dock_mat.roughness = 0.85

## Helper to generate unique procedural kidney bean polygon shapes with rotation orientation
func _generate_kidney_bean_polygon(base_radius: float, notch: float, lobe: float, rot_deg: float, center_offset: Vector2 = Vector2.ZERO, num_pts: int = 48) -> PackedVector2Array:
	var pts = PackedVector2Array()
	var rot_rad = deg_to_rad(rot_deg)
	var cos_r = cos(rot_rad)
	var sin_r = sin(rot_rad)
	
	for i in range(num_pts):
		var t = float(i) / float(num_pts) * TAU
		# Parametric kidney bean radius formula
		var r = base_radius * (1.0 - notch * cos(t)) * (1.0 + lobe * sin(2.0 * t))
		var x_raw = r * cos(t)
		var y_raw = r * sin(t)
		
		# Rotate to give each island a distinct orientation
		var rx = x_raw * cos_r - y_raw * sin_r
		var ry = x_raw * sin_r + y_raw * cos_r
		pts.append(center_offset + Vector2(rx, ry))
		
	return pts

# ========================================
# ENVIRONMENT SETUP
# ========================================

func _setup_environment() -> void:
	var sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(-52)).rotated(Vector3.UP, deg_to_rad(35))
	sun.shadow_enabled = true
	sun.light_energy = 1.25
	add_child(sun)
	
	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.52, 0.86)
	sky_mat.sky_horizon_color = Color(0.58, 0.76, 0.92)
	sky_mat.ground_bottom_color = Color(0.15, 0.28, 0.20)
	sky_mat.ground_horizon_color = Color(0.58, 0.76, 0.92)
	sky_mat.sun_angle_max = 35.0
	sky.sky_material = sky_mat
	env.sky = sky
	
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	
	env.fog_enabled = true
	env.fog_light_color = Color(0.65, 0.78, 0.88)
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.3
	
	world_env.environment = env
	add_child(world_env)
	
	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)

# ========================================
# WATER HAZARD
# ========================================

func _setup_water_hazard() -> void:
	var water = StaticBody3D.new()
	water.name = "WaterPlane"
	water.set_meta("is_water", true)
	add_child(water)
	
	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(600.0, 0.2, 600.0)
	col_shape.shape = box_shape
	col_shape.position = Vector3(60.0, -0.6, 0.0)
	water.add_child(col_shape)
	
	var mesh_inst = MeshInstance3D.new()
	var plane_mesh = QuadMesh.new()
	plane_mesh.size = Vector2(600.0, 600.0)
	mesh_inst.mesh = plane_mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.24, 0.44, 0.88)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.06
	mat.metallic = 0.8
	mat.emission_enabled = true
	mat.emission = Color(0.02, 0.09, 0.16)
	mat.emission_energy_multiplier = 0.35
	mesh_inst.material_override = mat
	
	mesh_inst.rotation = Vector3(-PI / 2, 0.0, 0.0)
	mesh_inst.position = Vector3(60.0, -0.5, 0.0)
	water.add_child(mesh_inst)

# ========================================
# TEE BOX
# ========================================

func _setup_tee_box() -> void:
	var tee = StaticBody3D.new()
	tee.name = "TeeBox"
	tee.set_meta("surface_type", 3) # TEE
	add_child(tee)
	
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(5.0, 0.5, 5.0)
	col.shape = box
	col.position = Vector3(0.0, -0.25, 0.0)
	tee.add_child(col)
	
	var base_mesh_inst = MeshInstance3D.new()
	var base_mesh = BoxMesh.new()
	base_mesh.size = Vector3(5.5, 0.5, 5.5)
	base_mesh_inst.mesh = base_mesh
	base_mesh_inst.material_override = wall_mat
	base_mesh_inst.position = Vector3(0.0, -0.25, 0.0)
	tee.add_child(base_mesh_inst)
	
	var turf_inst = MeshInstance3D.new()
	var turf_mesh = BoxMesh.new()
	turf_mesh.size = Vector3(5.0, 0.06, 5.0)
	turf_inst.mesh = turf_mesh
	turf_inst.material_override = green_mat
	turf_inst.position = Vector3(0.0, 0.03, 0.0)
	tee.add_child(turf_inst)

# ========================================
# PROCEDURAL FLOATING GOLF ISLAND GENERATION
# ========================================

func _setup_islands() -> void:
	island_data.clear()
	
	for i in range(island_positions.size()):
		var pos = island_positions[i]
		var dist_yds = island_distances_yards[i]
		
		# Generate procedural 2D geometry layouts for this island
		var data = _generate_island_layout(i)
		island_data.append(data)
		
		# Build 3D island node with meshes, collision bodies, trees, dock, flag
		var island_node = _build_floating_island_node(i, pos, dist_yds, data)
		add_child(island_node)

## Generate unique organic 2D shape profiles for each of the 4 islands
func _generate_island_layout(idx: int) -> Dictionary:
	var outer_pts: PackedVector2Array = PackedVector2Array()
	var green_pts: PackedVector2Array = PackedVector2Array()
	var bunker_list: Array[PackedVector2Array] = []
	var mulch_list: Array[PackedVector2Array] = []
	var tree_positions: Array[Vector3] = []
	var dock_pos = Vector3.ZERO
	var dock_angle = 0.0
	var pin_pos = Vector3.ZERO
	var green_bounding_radius = 8.0
	
	match idx:
		0: # 50 YARDS - Smallest Kidney Bean Island Green (Orientation: 15°)
			green_bounding_radius = 9.5
			outer_pts = _generate_kidney_bean_polygon(9.5, 0.18, 0.10, 15.0)
			green_pts = _generate_kidney_bean_polygon(6.5, 0.18, 0.08, 15.0)
			
			# Sand Traps on FRONT approach side (+Y in 2D / +Z in 3D), off-centered left & right
			bunker_list.append(_create_ellipse_polygon(Vector2(-3.8, 3.5), 2.4, 1.5, deg_to_rad(20)))
			bunker_list.append(_create_ellipse_polygon(Vector2(3.5, 3.8), 2.5, 1.6, deg_to_rad(-35)))
			
			# Red mulch bed strictly on BACK side (-Y in 2D / -Z in 3D)
			mulch_list.append(_create_ellipse_polygon(Vector2(0.0, -6.5), 6.0, 2.2, deg_to_rad(0)))
			
			# Trees strictly on BACK side (-Z in 3D)
			tree_positions = [
				Vector3(-4.2, 0.1, -6.0),
				Vector3(-0.8, 0.1, -7.2),
				Vector3(3.5, 0.1, -6.5)
			]
			dock_pos = Vector3(7.0, 0.0, -2.0)
			dock_angle = deg_to_rad(-45)
			pin_pos = Vector3(0.5, 0.05, -0.5)
			
		1: # 100 YARDS - Medium Kidney Bean Green (Orientation: -45°)
			green_bounding_radius = 15.0
			outer_pts = _generate_kidney_bean_polygon(15.0, 0.25, 0.16, -45.0)
			green_pts = _generate_kidney_bean_polygon(10.5, 0.25, 0.14, -45.0)
			
			# Sand Traps on FRONT approach side (+Y in 2D / +Z in 3D), off-centered left & right
			bunker_list.append(_create_ellipse_polygon(Vector2(-5.5, 5.5), 3.5, 2.0, deg_to_rad(-15)))
			bunker_list.append(_create_ellipse_polygon(Vector2(5.0, 6.2), 3.8, 2.2, deg_to_rad(25)))
			
			# Red mulch bed strictly on BACK side (-Y in 2D / -Z in 3D)
			mulch_list.append(_create_ellipse_polygon(Vector2(0.0, -10.0), 9.0, 3.2, deg_to_rad(0)))
			
			# Trees strictly on BACK side (-Z in 3D)
			tree_positions = [
				Vector3(-7.5, 0.1, -9.5),
				Vector3(-3.0, 0.1, -11.0),
				Vector3(2.5, 0.1, -11.5),
				Vector3(7.0, 0.1, -9.8)
			]
			dock_pos = Vector3(-11.0, 0.0, -4.0)
			dock_angle = deg_to_rad(120)
			pin_pos = Vector3(-0.5, 0.05, -1.0)
			
		2: # 150 YARDS - Large Kidney Bean Green (Orientation: 60°)
			green_bounding_radius = 21.0
			outer_pts = _generate_kidney_bean_polygon(21.0, 0.22, 0.20, 60.0)
			green_pts = _generate_kidney_bean_polygon(15.0, 0.22, 0.16, 60.0)
			
			# Sand Traps on FRONT approach side (+Y in 2D / +Z in 3D), off-centered left, right & mid-left
			bunker_list.append(_create_ellipse_polygon(Vector2(-8.5, 8.5), 5.0, 2.6, deg_to_rad(-25)))
			bunker_list.append(_create_ellipse_polygon(Vector2(8.0, 9.5), 5.2, 2.8, deg_to_rad(30)))
			bunker_list.append(_create_ellipse_polygon(Vector2(-2.5, 12.0), 4.0, 2.2, deg_to_rad(10)))
			
			# Red mulch beds strictly on BACK side (-Y in 2D / -Z in 3D)
			mulch_list.append(_create_ellipse_polygon(Vector2(-6.0, -13.5), 7.0, 3.5, deg_to_rad(-20)))
			mulch_list.append(_create_ellipse_polygon(Vector2(6.0, -13.5), 7.0, 3.5, deg_to_rad(20)))
			
			# Trees strictly on BACK side (-Z in 3D)
			tree_positions = [
				Vector3(-11.0, 0.1, -13.0),
				Vector3(-6.0, 0.1, -15.5),
				Vector3(0.0, 0.1, -16.0),
				Vector3(6.0, 0.1, -15.5),
				Vector3(11.0, 0.1, -13.0)
			]
			dock_pos = Vector3(16.0, 0.0, -3.0)
			dock_angle = deg_to_rad(75)
			pin_pos = Vector3(0.0, 0.05, -2.0)
			
		3: # 200 YARDS - Largest Grand Kidney Bean Island Green (Orientation: -75°)
			green_bounding_radius = 28.0
			outer_pts = _generate_kidney_bean_polygon(28.0, 0.30, 0.12, -75.0)
			green_pts = _generate_kidney_bean_polygon(20.0, 0.30, 0.10, -75.0)
			
			# Sand Traps on FRONT approach side (+Y in 2D / +Z in 3D), off-centered across front
			bunker_list.append(_create_ellipse_polygon(Vector2(-12.0, 11.0), 6.0, 3.2, deg_to_rad(-20)))
			bunker_list.append(_create_ellipse_polygon(Vector2(6.5, 14.5), 6.5, 3.5, deg_to_rad(15)))
			bunker_list.append(_create_ellipse_polygon(Vector2(13.5, 10.0), 5.5, 3.0, deg_to_rad(65)))
			
			# Large back pine grove mulch bed strictly on BACK side (-Y in 2D / -Z in 3D)
			mulch_list.append(_create_ellipse_polygon(Vector2(0.0, -18.0), 14.0, 5.0, deg_to_rad(0)))
			
			# Pine grove trees strictly on BACK side (-Z in 3D)
			tree_positions = [
				Vector3(-14.0, 0.1, -16.0),
				Vector3(-9.0, 0.1, -18.5),
				Vector3(-4.0, 0.1, -20.0),
				Vector3(1.0, 0.1, -20.5),
				Vector3(6.0, 0.1, -19.5),
				Vector3(11.0, 0.1, -18.0),
				Vector3(15.0, 0.1, -16.0)
			]
			dock_pos = Vector3(0.0, 0.0, -22.0)
			dock_angle = deg_to_rad(0)
			pin_pos = Vector3(-1.0, 0.05, -2.5)

	return {
		"outer_pts": outer_pts,
		"green_pts": green_pts,
		"bunkers": bunker_list,
		"mulch": mulch_list,
		"trees": tree_positions,
		"dock_pos": dock_pos,
		"dock_angle": dock_angle,
		"pin_pos": pin_pos,
		"green_radius": green_bounding_radius
	}

func _create_ellipse_polygon(center: Vector2, rx: float, ry: float, rot: float, pts_count: int = 24) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array()
	var cos_r = cos(rot)
	var sin_r = sin(rot)
	for i in range(pts_count):
		var t = float(i) / float(pts_count) * TAU
		var ex = rx * cos(t)
		var ey = ry * sin(t)
		var rx_rot = ex * cos_r - ey * sin_r
		var ry_rot = ex * sin_r + ey * cos_r
		poly.append(center + Vector2(rx_rot, ry_rot))
	return poly

## Build complete 3D Floating Island Node
func _build_floating_island_node(idx: int, pos: Vector3, dist_yds: int, data: Dictionary) -> StaticBody3D:
	var island = StaticBody3D.new()
	island.name = "GreenIsland_%d" % idx
	island.set_meta("surface_type", 4) # Default surface GREEN
	island.global_position = pos
	
	# Rotate island slightly so main features face player
	var dir_to_tee = -pos.normalized()
	var rot_y = atan2(dir_to_tee.x, dir_to_tee.z)
	island.rotation.y = rot_y
	
	var outer_poly: PackedVector2Array = data["outer_pts"]
	var green_poly: PackedVector2Array = data["green_pts"]
	var bunkers: Array[PackedVector2Array] = data["bunkers"]
	var mulch_beds: Array[PackedVector2Array] = data["mulch"]
	var tree_positions: Array[Vector3] = data["trees"]
	
	# 1. Wood Retaining Wall, Bottom Cap Rim & Continuous Pilings
	var wall_mesh = _build_retaining_wall_mesh(outer_poly, 0.0, -1.4, wall_mat, cap_mat)
	if wall_mesh:
		var wall_inst = MeshInstance3D.new()
		wall_inst.mesh = wall_mesh
		wall_inst.name = "WoodRetainingWall"
		island.add_child(wall_inst)
		
	# Retaining wall physics collision shape
	var wall_col_shape = ConcavePolygonShape3D.new()
	wall_col_shape.set_faces(_build_wall_collision_faces(outer_poly, 0.0, -1.4))
	var wall_col = CollisionShape3D.new()
	wall_col.shape = wall_col_shape
	island.add_child(wall_col)
	
	# Dense wooden log pilings fully surrounding the island perimeter (top level with platform, not protruding)
	_add_island_pilings(island, outer_poly, 0.0, -1.4)
	
	# 2. Rough Grass Surround Platform Mesh & Physics
	var fringe_mesh = _build_flat_polygon_mesh(outer_poly, 0.0, fringe_mat)
	if fringe_mesh:
		var f_inst = MeshInstance3D.new()
		f_inst.mesh = fringe_mesh
		f_inst.name = "RoughSurroundTurf"
		island.add_child(f_inst)
		
	# 3. Red Mulch / Flowerbed Accent Meshes
	for m_idx in range(mulch_beds.size()):
		var m_poly = mulch_beds[m_idx]
		var m_mesh = _build_flat_polygon_mesh(m_poly, 0.02, mulch_mat)
		if m_mesh:
			var m_inst = MeshInstance3D.new()
			m_inst.mesh = m_mesh
			m_inst.name = "RedMulchBed_%d" % m_idx
			island.add_child(m_inst)
			
	# 4. Putting Green Mesh & Main Green Collision Body
	var green_mesh = _build_flat_polygon_mesh(green_poly, 0.03, green_mat)
	if green_mesh:
		var g_inst = MeshInstance3D.new()
		g_inst.mesh = green_mesh
		g_inst.name = "PuttingGreenMesh"
		island.add_child(g_inst)
		
		# Main Green Collision Surface
		var green_body = StaticBody3D.new()
		green_body.name = "GreenBody"
		green_body.set_meta("surface_type", 4) # GREEN
		
		var green_concave = ConcavePolygonShape3D.new()
		green_concave.set_faces(_build_flat_poly_faces(green_poly, 0.03))
		var g_col = CollisionShape3D.new()
		g_col.shape = green_concave
		green_body.add_child(g_col)
		island.add_child(green_body)

	# 5. Sand Trap / Bunker Meshes & Bunker Bodies (rendered at y = 0.048 above green so fully visible)
	for b_idx in range(bunkers.size()):
		var b_poly = bunkers[b_idx]
		# Sand surface clearly visible on top of green/rough
		var b_mesh = _build_flat_polygon_mesh(b_poly, 0.048, sand_mat)
		if b_mesh:
			var b_inst = MeshInstance3D.new()
			b_inst.mesh = b_mesh
			b_inst.name = "SandTrapMesh_%d" % b_idx
			island.add_child(b_inst)
			
			var bunker_body = StaticBody3D.new()
			bunker_body.name = "SandTrapBody_%d" % b_idx
			bunker_body.set_meta("surface_type", 2) # BUNKER
			bunker_body.set_meta("is_sand", true)
			
			var b_concave = ConcavePolygonShape3D.new()
			b_concave.set_faces(_build_flat_poly_faces(b_poly, 0.048))
			var b_col = CollisionShape3D.new()
			b_col.shape = b_concave
			bunker_body.add_child(b_col)
			island.add_child(bunker_body)

	# 6. Evergreen / Pine Trees Placement
	_plant_trees_on_island(island, tree_positions)
	
	# 7. Wooden Boat Landing Dock / Gangplank
	var dock_node = _build_boat_dock(data["dock_pos"], data["dock_angle"])
	island.add_child(dock_node)
	
	# 8. Flagpole & Distance Label
	var flag_colors = [
		Color(1.0, 0.2, 0.2),   # Red for 50 yds
		Color(0.9, 0.75, 0.0),  # Gold for 100 yds
		Color(0.2, 0.6, 1.0),   # Blue for 150 yds
		Color(0.9, 0.3, 0.8),   # Purple for 200 yds
	]
	
	var pin_pos = data["pin_pos"]
	var flag_node = Node3D.new()
	flag_node.name = "Flag_%d" % idx
	flag_node.position = pin_pos + Vector3(0.0, 0.04, 0.0)
	island.add_child(flag_node)
	
	var pole = MeshInstance3D.new()
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.018
	pole_mesh.bottom_radius = 0.018
	pole_mesh.height = 2.2
	pole.mesh = pole_mesh
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color.WHITE
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, 1.1, 0.0)
	flag_node.add_child(pole)
	
	var flag = MeshInstance3D.new()
	var flag_mesh_p = PrismMesh.new()
	flag_mesh_p.size = Vector3(0.42, 0.30, 0.01)
	flag.mesh = flag_mesh_p
	var flag_m = StandardMaterial3D.new()
	flag_m.albedo_color = flag_colors[idx]
	flag_m.emission_enabled = true
	flag_m.emission = flag_colors[idx]
	flag_m.emission_energy_multiplier = 0.6
	flag.material_override = flag_m
	flag.position = Vector3(0.21, 2.05, 0.0)
	flag.rotation = Vector3(0.0, 0.0, -PI / 2)
	flag_node.add_child(flag)
	
	var label_node = Label3D.new()
	label_node.text = "%d YDS" % dist_yds
	label_node.font_size = 50
	label_node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label_node.outline_size = 12
	label_node.modulate = Color.WHITE
	label_node.outline_modulate = Color(0, 0, 0, 0.9)
	label_node.position = Vector3(0.0, 2.8, 0.0)
	flag_node.add_child(label_node)

	return island

# ========================================
# PROCEDURAL MESH BUILDERS
# ========================================

func _build_flat_polygon_mesh(poly_2d: PackedVector2Array, y_pos: float, mat: Material) -> ArrayMesh:
	if poly_2d.size() < 3:
		return null
		
	var indices = Geometry2D.triangulate_polygon(poly_2d)
	if indices.size() == 0:
		return null
		
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	
	for idx in indices:
		var p = poly_2d[idx]
		st.set_uv(Vector2(p.x * 0.2, p.y * 0.2))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(p.x, y_pos, p.y))
		
	return st.commit()

func _build_flat_poly_faces(poly_2d: PackedVector2Array, y_pos: float) -> PackedVector3Array:
	var faces = PackedVector3Array()
	if poly_2d.size() < 3:
		return faces
		
	var indices = Geometry2D.triangulate_polygon(poly_2d)
	for idx in indices:
		var p = poly_2d[idx]
		faces.append(Vector3(p.x, y_pos, p.y))
	return faces

func _build_retaining_wall_mesh(outer_poly: PackedVector2Array, top_y: float, bot_y: float, wall_m: Material, cap_m: Material) -> ArrayMesh:
	if outer_poly.size() < 3:
		return null
		
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(wall_m)
	
	var n = outer_poly.size()
	var current_u = 0.0
	
	for i in range(n):
		var p0 = outer_poly[i]
		var p1 = outer_poly[(i + 1) % n]
		var seg_len = p0.distance_to(p1)
		var next_u = current_u + seg_len * 0.4
		
		# Taper bottom towards water
		var v_top0 = Vector3(p0.x, top_y, p0.y)
		var v_top1 = Vector3(p1.x, top_y, p1.y)
		var v_bot0 = Vector3(p0.x * 0.94, bot_y, p0.y * 0.94)
		var v_bot1 = Vector3(p1.x * 0.94, bot_y, p1.y * 0.94)
		
		st.set_uv(Vector2(current_u, 0.0))
		st.add_vertex(v_top0)
		st.set_uv(Vector2(next_u, 0.0))
		st.add_vertex(v_top1)
		st.set_uv(Vector2(current_u, 1.0))
		st.add_vertex(v_bot0)
		
		st.set_uv(Vector2(next_u, 0.0))
		st.add_vertex(v_top1)
		st.set_uv(Vector2(next_u, 1.0))
		st.add_vertex(v_bot1)
		st.set_uv(Vector2(current_u, 1.0))
		st.add_vertex(v_bot0)
		
		current_u = next_u
		
	# Bottom underside cap mesh (solid wood hull underneath)
	var bot_poly = PackedVector2Array()
	for i in range(n):
		bot_poly.append(outer_poly[i] * 0.94)
	var bot_indices = Geometry2D.triangulate_polygon(bot_poly)
	for i in range(0, bot_indices.size(), 3):
		if i + 2 < bot_indices.size():
			var pA = bot_poly[bot_indices[i]]
			var pB = bot_poly[bot_indices[i + 1]]
			var pC = bot_poly[bot_indices[i + 2]]
			st.set_normal(Vector3.DOWN)
			st.set_uv(Vector2(pA.x * 0.2, pA.y * 0.2))
			st.add_vertex(Vector3(pA.x, bot_y, pA.y))
			st.set_uv(Vector2(pC.x * 0.2, pC.y * 0.2))
			st.add_vertex(Vector3(pC.x, bot_y, pC.y))
			st.set_uv(Vector2(pB.x * 0.2, pB.y * 0.2))
			st.add_vertex(Vector3(pB.x, bot_y, pB.y))

	st.generate_normals()
	var mesh = st.commit()
	
	# Add dark wood cap rim along perimeter top
	var st_cap = SurfaceTool.new()
	st_cap.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_cap.set_material(cap_m)
	
	for i in range(n):
		var p0 = outer_poly[i]
		var p1 = outer_poly[(i + 1) % n]
		
		var inner0 = p0 * 0.93
		var inner1 = p1 * 0.93
		
		var t0 = Vector3(p0.x, top_y + 0.02, p0.y)
		var t1 = Vector3(p1.x, top_y + 0.02, p1.y)
		var i0 = Vector3(inner0.x, top_y + 0.02, inner0.y)
		var i1 = Vector3(inner1.x, top_y + 0.02, inner1.y)
		
		st_cap.set_normal(Vector3.UP)
		st_cap.add_vertex(t0)
		st_cap.add_vertex(t1)
		st_cap.add_vertex(i0)
		
		st_cap.add_vertex(t1)
		st_cap.add_vertex(i1)
		st_cap.add_vertex(i0)
		
	st_cap.commit(mesh)
	return mesh

func _add_island_pilings(island: Node3D, outer_poly: PackedVector2Array, top_y: float, bot_y: float) -> void:
	var pilings_folder = Node3D.new()
	pilings_folder.name = "WoodenPilings"
	island.add_child(pilings_folder)
	
	var n = outer_poly.size()
	# Top of log pilings is flush with platform (0.0), NOT protruding above green
	var piling_top = 0.0
	var piling_height = (piling_top - bot_y)
	var center_y = (piling_top + bot_y) * 0.5
	
	for i in range(n):
		var p0 = outer_poly[i]
		var p1 = outer_poly[(i + 1) % n]
		
		var post = MeshInstance3D.new()
		var p_mesh = CylinderMesh.new()
		p_mesh.top_radius = 0.25
		p_mesh.bottom_radius = 0.25
		p_mesh.height = piling_height
		post.mesh = p_mesh
		post.material_override = wall_mat
		post.position = Vector3(p0.x * 0.97, center_y, p0.y * 0.97)
		pilings_folder.add_child(post)
		
		# Place intermediate log piling if segment is long
		var dist = p0.distance_to(p1)
		if dist > 0.8:
			var mid_p = (p0 + p1) * 0.5
			var mid_post = MeshInstance3D.new()
			var m_mesh = CylinderMesh.new()
			m_mesh.top_radius = 0.25
			m_mesh.bottom_radius = 0.25
			m_mesh.height = piling_height
			mid_post.mesh = m_mesh
			mid_post.material_override = wall_mat
			mid_post.position = Vector3(mid_p.x * 0.97, center_y, mid_p.y * 0.97)
			pilings_folder.add_child(mid_post)

func _build_wall_collision_faces(outer_poly: PackedVector2Array, top_y: float, bot_y: float) -> PackedVector3Array:
	var faces = PackedVector3Array()
	var n = outer_poly.size()
	for i in range(n):
		var p0 = outer_poly[i]
		var p1 = outer_poly[(i + 1) % n]
		var v_top0 = Vector3(p0.x, top_y, p0.y)
		var v_top1 = Vector3(p1.x, top_y, p1.y)
		var v_bot0 = Vector3(p0.x * 0.94, bot_y, p0.y * 0.94)
		var v_bot1 = Vector3(p1.x * 0.94, bot_y, p1.y * 0.94)
		
		faces.append(v_top0)
		faces.append(v_top1)
		faces.append(v_bot0)
		faces.append(v_top1)
		faces.append(v_bot1)
		faces.append(v_bot0)
	return faces

## Plant evergreen pine trees & shrubs on island edge / mulch
func _plant_trees_on_island(island: Node3D, tree_positions: Array[Vector3]) -> void:
	var tree_paths = [
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-1-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-2-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-1-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-2-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-1-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-2-staticbody.tscn"
	]
	
	var trees_folder = Node3D.new()
	trees_folder.name = "TreesFolder"
	island.add_child(trees_folder)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = island.name.hash()
	
	for t_idx in range(tree_positions.size()):
		var t_pos = tree_positions[t_idx]
		var path = tree_paths[rng.randi() % tree_paths.size()]
		if ResourceLoader.exists(path):
			var scene = load(path)
			if scene:
				var t_inst = scene.instantiate()
				t_inst.name = "IslandTree_%d" % t_idx
				t_inst.position = t_pos
				var scale_val = rng.randf_range(1.2, 1.8)
				t_inst.scale = Vector3(scale_val, scale_val, scale_val)
				t_inst.rotation.y = rng.randf_range(0.0, TAU)
				trees_folder.add_child(t_inst)

## Construct wooden boat landing dock structure
func _build_boat_dock(dock_pos: Vector3, dock_angle: float) -> Node3D:
	var dock_node = Node3D.new()
	dock_node.name = "BoatLandingDock"
	dock_node.position = dock_pos
	dock_node.rotation.y = dock_angle
	
	# Dock main deck platform
	var deck = MeshInstance3D.new()
	var deck_mesh = BoxMesh.new()
	deck_mesh.size = Vector3(2.5, 0.15, 4.0)
	deck.mesh = deck_mesh
	deck.material_override = dock_mat
	deck.position = Vector3(0.0, -0.05, 0.0)
	dock_node.add_child(deck)
	
	# Wooden dock pilings (4 vertical logs)
	var piling_offsets = [
		Vector3(-1.1, -0.4, -1.8),
		Vector3(1.1, -0.4, -1.8),
		Vector3(-1.1, -0.4, 1.8),
		Vector3(1.1, -0.4, 1.8)
	]
	for p_idx in range(piling_offsets.size()):
		var piling = MeshInstance3D.new()
		var p_mesh = CylinderMesh.new()
		p_mesh.top_radius = 0.08
		p_mesh.bottom_radius = 0.08
		p_mesh.height = 1.0
		piling.mesh = p_mesh
		piling.material_override = wall_mat
		piling.position = piling_offsets[p_idx]
		dock_node.add_child(piling)
		
	# Gangway gangplank leading from dock to island edge
	var gangway = MeshInstance3D.new()
	var g_mesh = BoxMesh.new()
	g_mesh.size = Vector3(1.2, 0.1, 2.0)
	gangway.mesh = g_mesh
	gangway.material_override = dock_mat
	gangway.position = Vector3(0.0, 0.02, 2.8)
	gangway.rotation.x = deg_to_rad(-8)
	dock_node.add_child(gangway)
	
	return dock_node

# ========================================
# TARGET SELECTION & RING
# ========================================

func _select_target_island(index: int) -> void:
	selected_island_index = index
	user_aim_offset_deg = 0.0
	if aim_slider:
		aim_slider.value = 0.0
		
	for i in range(island_positions.size()):
		var island_node = get_node_or_null("GreenIsland_%d" % i)
		if island_node:
			var old_ring = island_node.get_node_or_null("TargetRing")
			if old_ring:
				old_ring.queue_free()
				
			if i == index:
				var ring_radius = island_data[i]["green_radius"]
				var ring = MeshInstance3D.new()
				ring.name = "TargetRing"
				var ring_mesh = TorusMesh.new()
				ring_mesh.inner_radius = ring_radius + 0.2
				ring_mesh.outer_radius = ring_radius + 0.7
				ring_mesh.rings = 36
				ring_mesh.ring_segments = 8
				ring.mesh = ring_mesh
				
				var ring_mat = StandardMaterial3D.new()
				ring_mat.albedo_color = Color(0.0, 0.85, 1.0, 0.7)
				ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				ring_mat.emission_enabled = true
				ring_mat.emission = Color(0.0, 0.7, 1.0)
				ring_mat.emission_energy_multiplier = 0.8
				ring.material_override = ring_mat
				ring.position = Vector3(0.0, 0.06, 0.0)
				island_node.add_child(ring)
				
	var dist_yards = island_distances_yards[index]
	if power_slider:
		var estimated_speed = 18.0 + sqrt(dist_yards) * 2.0
		power_slider.value = clamp(estimated_speed, 15.0, 65.0)
		
	for i in range(island_buttons.size()):
		if i == index:
			island_buttons[i].text = "▶ %d YDS" % island_distances_yards[i]
			island_buttons[i].add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
		else:
			island_buttons[i].text = "  %d YDS" % island_distances_yards[i]
			island_buttons[i].remove_theme_color_override("font_color")
		
	_reset_ball_position()
	_update_hud()
	_show_banner("Target: %d Yards — Aim and chip onto the floating green!" % dist_yards)

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
	player.global_position = Vector3(0.0, 0.05, 0.0)
	player.ball.spawn_position = player.global_position
	player.ball.reset()
	player.reset_ball()
	_update_aim_and_camera()

func _update_aim_and_camera() -> void:
	var target_island_pos = island_positions[selected_island_index]
	var ball_pos = player.ball.global_position
	
	var diff = target_island_pos - ball_pos
	var base_angle_rad = atan2(diff.z, diff.x)
	var final_angle_rad = base_angle_rad + deg_to_rad(user_aim_offset_deg)
	
	player.ball.aim_yaw_offset_deg = rad_to_deg(-final_angle_rad)
	
	var back_dir = Vector3(-cos(final_angle_rad), 0.0, -sin(final_angle_rad)).normalized()
	var cam_pos = ball_pos + back_dir * 4.0 + Vector3.UP * 2.0
	
	$Camera3D.global_position = cam_pos
	$Camera3D.look_at(ball_pos + back_dir * -15.0 + Vector3.UP * 1.0)
	
	last_camera_offset = cam_pos - ball_pos

# ========================================
# INPUT & HIT SIMULATION
# ========================================

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_dragging = true
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
			else:
				is_dragging = false
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var camera = $Camera3D
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
					for i in range(island_positions.size()):
						var d = clicked_point.distance_to(island_positions[i])
						if d < min_dist:
							min_dist = d
							closest_idx = i
					if min_dist <= island_data[closest_idx]["green_radius"] + 4.0:
						_select_target_island(closest_idx)
						
	elif event is InputEventMouseMotion and is_dragging:
		user_aim_offset_deg += event.relative.x * 0.15
		if aim_slider:
			aim_slider.value = clamp(user_aim_offset_deg, aim_slider.min_value, aim_slider.max_value)
		_update_aim_and_camera()
					
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			user_aim_offset_deg += 1.5
			if aim_slider:
				aim_slider.value = clamp(user_aim_offset_deg, aim_slider.min_value, aim_slider.max_value)
			_update_aim_and_camera()
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			user_aim_offset_deg -= 1.5
			if aim_slider:
				aim_slider.value = clamp(user_aim_offset_deg, aim_slider.min_value, aim_slider.max_value)
			_update_aim_and_camera()
		elif event.keycode == KEY_H:
			_perform_chip()
		elif event.keycode == KEY_R:
			_reset_ball_position()

func _perform_chip() -> void:
	if player.ball.state != PhysicsEnums.BallState.REST:
		return
		
	var speed_mph = power_slider.value
	var vla = vla_slider.value
	var hla = user_aim_offset_deg
	
	var data = {
		"Speed": speed_mph,
		"VLA": vla,
		"HLA": hla,
		"TotalSpin": 4000.0,
		"SpinAxis": 0.0,
		"ShotType": "chip"
	}
	
	player.track_points = false
	player.create_new_tracer()
	player.ball.call_deferred("hit_from_data", data)
	player.track_points = true
	player.trail_timer = 0.0
	
	_show_banner("Chipped! Speed: %.1f mph | Loft: %.1f°" % [speed_mph, vla])

func _on_launch_monitor_hit_ball(data: Dictionary) -> void:
	if player == null or player.ball == null:
		return
	if player.ball.state != PhysicsEnums.BallState.REST:
		return # Ignore if shot in progress
		
	# Connect to the player's launch monitor shot handler
	player._on_tcp_client_hit_ball(data)
	
	# Show the banner
	var speed_mph = data.get("Speed", 0.0)
	var vla = data.get("VLA", 0.0)
	_show_banner("Chipped (Launch Monitor)! Speed: %.1f mph | Loft: %.1f°" % [speed_mph, vla])

# ========================================
# CAMERA FOLLOW & REST DETECTION
# ========================================

func _physics_process(delta: float) -> void:
	if player and player.ball:
		var ball_state = player.ball.state
		if ball_state == PhysicsEnums.BallState.FLIGHT or ball_state == PhysicsEnums.BallState.ROLLOUT:
			camera_following = true
			var ball_pos = player.ball.global_position
			var target_cam_pos = ball_pos + last_camera_offset
			$Camera3D.global_position = $Camera3D.global_position.lerp(target_cam_pos, delta * 8.0)
			$Camera3D.look_at(ball_pos + Vector3.UP * 0.1)
		else:
			if camera_following:
				camera_following = false
				_update_aim_and_camera()

func _on_ball_rest(_shot_data: Dictionary) -> void:
	var final_pos = player.ball.global_position
	var target_island_pos = island_positions[selected_island_index]
	var target_data = island_data[selected_island_index]
	
	var dist_to_target = Vector2(final_pos.x, final_pos.z).distance_to(Vector2(target_island_pos.x, target_island_pos.z))
	
	island_stats[selected_island_index]["Attempts"] += 1
	
	if player.ball.is_in_water:
		_show_banner("💦 SPLASH! Landed in the water hazard.")
	elif dist_to_target <= target_data["green_radius"]:
		island_stats[selected_island_index]["Hits"] += 1
		total_greens_hit += 1
		GlobalSettings.play_golf_clap()
		_show_banner("🍎 GREEN HIT! Outstanding chip! (%d total greens hit)" % total_greens_hit)
	else:
		var landed_on_other = false
		for i in range(island_positions.size()):
			if i == selected_island_index:
				continue
			var d = Vector2(final_pos.x, final_pos.z).distance_to(Vector2(island_positions[i].x, island_positions[i].z))
			if d <= island_data[i]["green_radius"]:
				landed_on_other = true
				_show_banner("Landed on the %d YDS green — but you were aiming for %d YDS!" % [island_distances_yards[i], island_distances_yards[selected_island_index]])
				break
		if not landed_on_other:
			_show_banner("Missed target green. Distance to center: %.1f yds" % (dist_to_target * 1.09361))
		
	_update_hud()
	
	await get_tree().create_timer(3.0).timeout
	_reset_ball_position()

# ========================================
# GUI SETUP
# ========================================

func _setup_ui() -> void:
	var hud_layer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	add_child(hud_layer)
	
	var control = Control.new()
	control.anchors_preset = Control.PRESET_FULL_RECT
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(control)
	
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
	
	# Scoreboard
	var score_panel = PanelContainer.new()
	score_panel.custom_minimum_size = Vector2(780, 90)
	score_panel.anchor_left = 0.5
	score_panel.anchor_right = 0.5
	score_panel.anchor_top = 0.0
	score_panel.anchor_bottom = 0.0
	score_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_panel.offset_left = -390
	score_panel.offset_right = 390
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
	t_lbl.text = "TARGET"
	t_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_lbl.add_theme_font_size_override("font_size", 12)
	t_lbl.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	target_col.add_child(t_lbl)
	target_info_lbl = Label.new()
	target_info_lbl.text = "50 YDS"
	target_info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target_info_lbl.add_theme_font_size_override("font_size", 28)
	target_info_lbl.add_theme_color_override("font_color", Color.WHITE)
	target_col.add_child(target_info_lbl)
	
	var attempts_col = VBoxContainer.new()
	attempts_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attempts_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(attempts_col)
	var att_lbl = Label.new()
	att_lbl.text = "ATTEMPTS"
	att_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	att_lbl.add_theme_font_size_override("font_size", 12)
	att_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	attempts_col.add_child(att_lbl)
	attempts_lbl = Label.new()
	attempts_lbl.text = "0"
	attempts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attempts_lbl.add_theme_font_size_override("font_size", 28)
	attempts_lbl.add_theme_color_override("font_color", Color.WHITE)
	attempts_col.add_child(attempts_lbl)
	
	var hits_col = VBoxContainer.new()
	hits_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hits_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(hits_col)
	var h_lbl = Label.new()
	h_lbl.text = "HITS"
	h_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h_lbl.add_theme_font_size_override("font_size", 12)
	h_lbl.add_theme_color_override("font_color", Color(0.2, 0.8, 0.3))
	hits_col.add_child(h_lbl)
	hits_lbl = Label.new()
	hits_lbl.text = "0"
	hits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hits_lbl.add_theme_font_size_override("font_size", 28)
	hits_lbl.add_theme_color_override("font_color", Color.WHITE)
	hits_col.add_child(hits_lbl)
	
	var acc_col = VBoxContainer.new()
	acc_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acc_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(acc_col)
	var ac_lbl = Label.new()
	ac_lbl.text = "ACCURACY"
	ac_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ac_lbl.add_theme_font_size_override("font_size", 12)
	ac_lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 0.1))
	acc_col.add_child(ac_lbl)
	accuracy_lbl = Label.new()
	accuracy_lbl.text = "0%"
	accuracy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	accuracy_lbl.add_theme_font_size_override("font_size", 28)
	accuracy_lbl.add_theme_color_override("font_color", Color.WHITE)
	acc_col.add_child(accuracy_lbl)
	
	var total_col = VBoxContainer.new()
	total_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_col.alignment = BoxContainer.ALIGNMENT_CENTER
	score_hbox.add_child(total_col)
	var tot_lbl = Label.new()
	tot_lbl.text = "TOTAL GREENS"
	tot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tot_lbl.add_theme_font_size_override("font_size", 12)
	tot_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	total_col.add_child(tot_lbl)
	total_hits_lbl = Label.new()
	total_hits_lbl.text = "0"
	total_hits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_hits_lbl.add_theme_font_size_override("font_size", 28)
	total_hits_lbl.add_theme_color_override("font_color", Color.WHITE)
	total_col.add_child(total_hits_lbl)
	
	# Target Selection Panel
	var target_panel = PanelContainer.new()
	target_panel.custom_minimum_size = Vector2(170, 240)
	target_panel.anchor_left = 0.0
	target_panel.anchor_top = 0.5
	target_panel.anchor_bottom = 0.5
	target_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	target_panel.offset_left = 20
	target_panel.offset_top = -120
	target_panel.offset_bottom = 120
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
	t_title.text = "🌲 CHOOSE TARGET"
	t_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_title.add_theme_font_size_override("font_size", 13)
	t_title.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	target_vbox.add_child(t_title)
	
	island_buttons.clear()
	for i in range(island_distances_yards.size()):
		var btn = Button.new()
		btn.text = "  %d YDS" % island_distances_yards[i]
		btn.custom_minimum_size = Vector2(0, 36)
		btn.add_theme_font_size_override("font_size", 14)
		_apply_btn_style(btn, Color(0.12, 0.20, 0.28), Color(0.18, 0.30, 0.42))
		btn.pressed.connect(func(idx = i): _select_target_island(idx))
		target_vbox.add_child(btn)
		island_buttons.append(btn)
	
	# Banner
	banner_lbl = Label.new()
	banner_lbl.text = "Select a target floating green and chip away!"
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.anchor_left = 0.5
	banner_lbl.anchor_right = 0.5
	banner_lbl.anchor_top = 0.22
	banner_lbl.anchor_bottom = 0.22
	banner_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_lbl.add_theme_font_size_override("font_size", 22)
	banner_lbl.add_theme_color_override("font_color", Color(1, 1, 0.5, 1.0))
	banner_lbl.add_theme_constant_override("outline_size", 4)
	banner_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	control.add_child(banner_lbl)
	
	# Controls Panel
	var ctrl_panel = PanelContainer.new()
	ctrl_panel.custom_minimum_size = Vector2(960, 110)
	ctrl_panel.anchor_left = 0.5
	ctrl_panel.anchor_right = 0.5
	ctrl_panel.anchor_top = 1.0
	ctrl_panel.anchor_bottom = 1.0
	ctrl_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctrl_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ctrl_panel.offset_left = -480
	ctrl_panel.offset_right = 480
	ctrl_panel.offset_top = -130
	ctrl_panel.offset_bottom = -20
	control.add_child(ctrl_panel)
	ctrl_panel.add_theme_stylebox_override("panel", glass_style)
	
	var ctrl_margin = MarginContainer.new()
	ctrl_margin.add_theme_constant_override("margin_left", 24)
	ctrl_margin.add_theme_constant_override("margin_right", 24)
	ctrl_panel.add_child(ctrl_margin)
	
	var ctrl_hbox = HBoxContainer.new()
	ctrl_hbox.add_theme_constant_override("separation", 18)
	ctrl_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_margin.add_child(ctrl_hbox)
	
	var power_vbox = VBoxContainer.new()
	power_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_hbox.add_child(power_vbox)
	var p_lbl = Label.new()
	p_lbl.text = "Swing Power (Speed)"
	p_lbl.add_theme_font_size_override("font_size", 13)
	power_vbox.add_child(p_lbl)
	var p_slider_hbox = HBoxContainer.new()
	power_vbox.add_child(p_slider_hbox)
	power_slider = HSlider.new()
	power_slider.min_value = 15.0
	power_slider.max_value = 65.0
	power_slider.step = 0.2
	power_slider.value = 25.0
	power_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p_slider_hbox.add_child(power_slider)
	power_val_lbl = Label.new()
	power_val_lbl.text = "25.0 mph"
	power_val_lbl.custom_minimum_size = Vector2(65, 0)
	p_slider_hbox.add_child(power_val_lbl)
	power_slider.value_changed.connect(func(val): power_val_lbl.text = "%.1f mph" % val)
	
	var vla_vbox = VBoxContainer.new()
	vla_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vla_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_hbox.add_child(vla_vbox)
	var v_lbl = Label.new()
	v_lbl.text = "Loft Angle (VLA)"
	v_lbl.add_theme_font_size_override("font_size", 13)
	vla_vbox.add_child(v_lbl)
	var v_slider_hbox = HBoxContainer.new()
	vla_vbox.add_child(v_slider_hbox)
	vla_slider = HSlider.new()
	vla_slider.min_value = 15.0
	vla_slider.max_value = 55.0
	vla_slider.step = 0.5
	vla_slider.value = 32.0
	vla_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_slider_hbox.add_child(vla_slider)
	vla_val_lbl = Label.new()
	vla_val_lbl.text = "32.0°"
	vla_val_lbl.custom_minimum_size = Vector2(45, 0)
	v_slider_hbox.add_child(vla_val_lbl)
	vla_slider.value_changed.connect(func(val): vla_val_lbl.text = "%.1f°" % val)
	
	var aim_vbox = VBoxContainer.new()
	aim_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_hbox.add_child(aim_vbox)
	var aim_lbl = Label.new()
	aim_lbl.text = "Aim Angle Offset"
	aim_lbl.add_theme_font_size_override("font_size", 13)
	aim_vbox.add_child(aim_lbl)
	var aim_slider_hbox = HBoxContainer.new()
	aim_vbox.add_child(aim_slider_hbox)
	aim_slider = HSlider.new()
	aim_slider.min_value = -30.0
	aim_slider.max_value = 30.0
	aim_slider.step = 0.5
	aim_slider.value = 0.0
	aim_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_slider_hbox.add_child(aim_slider)
	aim_val_lbl = Label.new()
	aim_val_lbl.text = "0.0°"
	aim_val_lbl.custom_minimum_size = Vector2(45, 0)
	aim_slider_hbox.add_child(aim_val_lbl)
	aim_slider.value_changed.connect(_on_aim_slider_changed)
	
	var swing_btn = Button.new()
	swing_btn.text = "CHIP (H)"
	swing_btn.custom_minimum_size = Vector2(110, 50)
	_apply_btn_style(swing_btn, Color(0.18, 0.48, 0.28), Color(0.12, 0.32, 0.18))
	swing_btn.pressed.connect(_perform_chip)
	ctrl_hbox.add_child(swing_btn)
	
	var reset_btn = Button.new()
	reset_btn.text = "RESET (R)"
	reset_btn.custom_minimum_size = Vector2(100, 50)
	_apply_btn_style(reset_btn, Color(0.48, 0.28, 0.18), Color(0.32, 0.18, 0.12))
	reset_btn.pressed.connect(_reset_ball_position)
	ctrl_hbox.add_child(reset_btn)
	
	var settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.icon = load("res://Utils/Settings/Gear.png")
	settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.custom_minimum_size = Vector2(50, 50)
	_apply_btn_style(settings_btn, Color(0.18, 0.34, 0.50), Color(0.24, 0.44, 0.65))
	settings_btn.pressed.connect(_on_settings_pressed)
	ctrl_hbox.add_child(settings_btn)

	var exit_btn = Button.new()
	exit_btn.text = "EXIT"
	exit_btn.custom_minimum_size = Vector2(80, 50)
	_apply_btn_style(exit_btn, Color(0.36, 0.16, 0.16), Color(0.24, 0.12, 0.12))
	exit_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
	ctrl_hbox.add_child(exit_btn)
	
	_update_hud()

# ========================================
# UI HELPERS
# ========================================

func _apply_btn_style(btn: Button, norm_color: Color, hov_color: Color) -> void:
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

func _on_aim_slider_changed(val: float) -> void:
	aim_val_lbl.text = "%+.1f°" % val
	user_aim_offset_deg = val
	_update_aim_and_camera()

func _update_hud() -> void:
	if selected_island_index < 0:
		return
	var stats = island_stats[selected_island_index]
	var att = stats["Attempts"]
	var hits = stats["Hits"]
	var acc = 0
	if att > 0:
		acc = int((float(hits) / float(att)) * 100.0)
		
	if target_info_lbl:
		target_info_lbl.text = "%d YDS" % island_distances_yards[selected_island_index]
	if attempts_lbl:
		attempts_lbl.text = str(att)
	if hits_lbl:
		hits_lbl.text = str(hits)
	if accuracy_lbl:
		accuracy_lbl.text = "%d%%" % acc
	if total_hits_lbl:
		total_hits_lbl.text = str(total_greens_hit)

func _show_banner(text: String) -> void:
	if banner_lbl:
		banner_lbl.text = text

func _on_settings_pressed() -> void:
	var settings_scene = load("res://UI/Settings/RangeSettings/range_settings.tscn")
	if settings_scene != null:
		var inst = settings_scene.instantiate()
		inst.name = "MinigameSettings"
		inst.set_anchors_preset(Control.PRESET_CENTER)
		inst.grow_horizontal = Control.GROW_DIRECTION_BOTH
		inst.grow_vertical = Control.GROW_DIRECTION_BOTH
		inst.close_settings_requested.connect(func(): inst.queue_free())
		
		var hud = get_node_or_null("HUDLayer/Control")
		if hud != null:
			hud.add_child(inst)
		else:
			add_child(inst)
