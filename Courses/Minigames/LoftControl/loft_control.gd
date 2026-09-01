extends Node3D

# Preloaded assets
var PlayerScene = preload("res://Player/player.tscn")

# Minigame state
var player = null
var attempts_count: int = 0
var broken_count: int = 0
var shot_counter: int = 0
var shot_reset_token: int = 0
var last_shot_data: Dictionary = {}
var is_victory: bool = false
var viewing_wall_cam: bool = false

# Camera tracking
var camera: Camera3D = null
var last_camera_offset := Vector3(-6.0, 2.5, 0.0)
var camera_following: bool = false
var prev_ball_pos := Vector3.ZERO

# Wall constants (75 yards = 225 feet = 68.58 meters)
const WALL_DIST_X: float = 68.58
const GRID_ROWS: int = 3
const GRID_COLS: int = 3

# SQUARE Glass Panes: 8.5m x 8.5m each
const PANE_SIZE: float = 8.5
const PANE_DEPTH: float = 0.15

# Grid coordinates:
# Columns (Z axis): Left = -9.3m, Mid = 0.0m, Right = +9.3m (8.5m square each + 0.8m beam)
# Rows (Y axis): Top = 24.6m, Mid = 15.3m, Bot = 6.0m (8.5m square each + 0.8m beam)
const COL_Z_CENTERS = [-9.3, 0.0, 9.3]
const ROW_Y_CENTERS = [24.6, 15.3, 6.0]

const PANE_NAMES = [
	"Top Left",    "Top Middle",    "Top Right",
	"Middle Left", "Middle Middle", "Middle Right",
	"Bottom Left", "Bottom Middle", "Bottom Right"
]

const PANE_DESCS = [
	"High Loft · 75 FT",   "High Loft · 75 FT",   "High Loft · 75 FT",
	"Mid Trajectory · 45 FT", "Center Target · 45 FT", "Mid Trajectory · 45 FT",
	"Low Stinger · 18 FT", "Low Stinger · 18 FT", "Low Stinger · 18 FT"
]

const PANE_COLORS = [
	Color(0.25, 0.95, 1.0), Color(0.25, 0.95, 1.0), Color(0.25, 0.95, 1.0), # Top Row: Neon Cyan
	Color(1.0, 0.90, 0.25), Color(1.0, 0.90, 0.25), Color(1.0, 0.90, 0.25), # Mid Row: Golden Yellow
	Color(0.35, 1.0, 0.55), Color(0.35, 1.0, 0.55), Color(0.35, 1.0, 0.55)  # Bot Row: Bright Lime
]

# State per pane (0 to 8)
var panes_broken: Array[bool] = [false, false, false, false, false, false, false, false, false]
var pane_nodes: Array[Node3D] = []
var pane_mesh_instances: Array[MeshInstance3D] = []
var pane_areas: Array[Area3D] = []
var hud_matrix_buttons: Array[Button] = []

# Materials
var glass_mat_intact: StandardMaterial3D
var glass_mat_broken_rim: StandardMaterial3D
var frame_mat_steel: StandardMaterial3D
var frame_mat_concrete: StandardMaterial3D
var turf_mat: StandardMaterial3D
var fairway_mat: StandardMaterial3D

# UI References
var hud_layer: CanvasLayer = null
var hud_control: Control = null
var panes_cleared_lbl: Label = null
var attempts_lbl: Label = null
var accuracy_lbl: Label = null
var last_shot_lbl: Label = null
var music_toggle_btn: Button = null
var cam_toggle_btn: Button = null
var _settings_layer: CanvasLayer = null

# Audio
var sfx_shatter_player: AudioStreamPlayer = null
var sfx_frame_player: AudioStreamPlayer = null
var sfx_applause_player: AudioStreamPlayer = null
var _shatter_stream: AudioStreamWAV = null


func _ready() -> void:
	name = "LoftControl"
	
	# 1. Initialize Audio Streams
	_init_audio_streams()
	
	# 2. Initialize Materials
	_init_materials()
	
	# 3. Setup Environment (Sky, Light, Camera)
	_setup_environment()
	
	# 4. Setup Range Turf, Fairway, Distance Markers (25, 50, 75 yds)
	_setup_range_ground()
	
	# 5. Setup 75-Yard Target Wall & 3x3 SQUARE Glass Grid
	_setup_glass_wall_and_panes()
	
	# 6. Setup Player
	_setup_player()
	
	# 7. Setup UI & HUD
	_setup_ui()
	
	# Connect club selector
	if has_node("/root/EventBus"):
		var eb = get_node("/root/EventBus")
		if eb.has_signal("club_selected"):
			eb.club_selected.emit("Sw") # Default to Sand Wedge for 75 yards
	
	# Connect Launch Monitor
	if has_node("/root/LaunchMonitorManager"):
		var launch_monitor = get_node("/root/LaunchMonitorManager")
		if not launch_monitor.hit_ball.is_connected(_on_launch_monitor_hit_ball):
			launch_monitor.hit_ball.connect(_on_launch_monitor_hit_ball)
			
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


# ==============================================================================
# AUDIO GENERATION & SETUP
# ==============================================================================

func _init_audio_streams() -> void:
	# Generate procedural crisp glass shatter WAV stream
	_shatter_stream = _create_procedural_glass_shatter_stream()
	
	sfx_shatter_player = AudioStreamPlayer.new()
	sfx_shatter_player.name = "GlassShatterPlayer"
	sfx_shatter_player.stream = _shatter_stream
	sfx_shatter_player.volume_db = 0.0
	add_child(sfx_shatter_player)
	
	sfx_frame_player = AudioStreamPlayer.new()
	sfx_frame_player.name = "FrameHitPlayer"
	if ResourceLoader.exists("res://assets/audio/sfx/tree_hit.ogg"):
		sfx_frame_player.stream = load("res://assets/audio/sfx/tree_hit.ogg")
	elif ResourceLoader.exists("res://assets/audio/sfx/ball_hit_tree.mp3"):
		sfx_frame_player.stream = load("res://assets/audio/sfx/ball_hit_tree.mp3")
	sfx_frame_player.volume_db = 2.0
	add_child(sfx_frame_player)
	
	sfx_applause_player = AudioStreamPlayer.new()
	sfx_applause_player.name = "ApplausePlayer"
	if ResourceLoader.exists("res://assets/audio/golf_clap.mp3"):
		sfx_applause_player.stream = load("res://assets/audio/golf_clap.mp3")
	sfx_applause_player.volume_db = 3.0
	add_child(sfx_applause_player)


func _create_procedural_glass_shatter_stream() -> AudioStreamWAV:
	var sample_rate = 44100
	var duration = 0.75 # seconds
	var total_samples = int(sample_rate * duration)
	var byte_array = PackedByteArray()
	byte_array.resize(total_samples * 2) # 16-bit mono
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 98765
	
	for i in range(total_samples):
		var t = float(i) / float(sample_rate)
		
		# 1. Initial sharp crack / shockwave (exponential fast burst)
		var crack = rng.randf_range(-1.0, 1.0) * exp(-t * 85.0) * 0.95
		
		# 2. Crystalline resonant frequencies of glass shards shattering
		var f1 = sin(TAU * 2650.0 * t) * exp(-t * 14.0)
		var f2 = sin(TAU * 3820.0 * t + 0.5) * exp(-t * 18.0)
		var f3 = sin(TAU * 5140.0 * t + 1.2) * exp(-t * 24.0)
		var f4 = sin(TAU * 7200.0 * t + 2.1) * exp(-t * 30.0)
		var f5 = sin(TAU * 1250.0 * t) * exp(-t * 8.0)
		var crystal_ring = (f1 * 0.28 + f2 * 0.22 + f3 * 0.18 + f4 * 0.14 + f5 * 0.25)
		
		# 3. Cascading shards tinkling and falling
		var shard_tinkle = 0.0
		if t > 0.03:
			var noise = rng.randf_range(-1.0, 1.0)
			shard_tinkle = noise * exp(-(t - 0.03) * 6.5) * sin(TAU * (3000.0 + 1500.0 * sin(t * 40.0)) * t) * 0.35
			
		var mixed = clampf(crack + crystal_ring + shard_tinkle, -1.0, 1.0)
		var sample_16 = int(mixed * 32767.0)
		
		# Little-endian 16-bit integer encoding
		byte_array.encode_s16(i * 2, sample_16)
		
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	stream.data = byte_array
	return stream


# ==============================================================================
# MATERIALS SETUP
# ==============================================================================

func _init_materials() -> void:
	# Intact Glass: Semi-transparent tinted cyan/blue with crisp specular reflections
	glass_mat_intact = StandardMaterial3D.new()
	glass_mat_intact.albedo_color = Color(0.22, 0.60, 0.85, 0.38)
	glass_mat_intact.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat_intact.roughness = 0.06
	glass_mat_intact.metallic = 0.88
	glass_mat_intact.emission_enabled = true
	glass_mat_intact.emission = Color(0.10, 0.42, 0.65)
	glass_mat_intact.emission_energy_multiplier = 0.25
	glass_mat_intact.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	# Broken Glass Edge Rim: Glowing green fractured remnant frame
	glass_mat_broken_rim = StandardMaterial3D.new()
	glass_mat_broken_rim.albedo_color = Color(0.2, 0.85, 0.35, 0.65)
	glass_mat_broken_rim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat_broken_rim.roughness = 0.3
	glass_mat_broken_rim.emission_enabled = true
	glass_mat_broken_rim.emission = Color(0.2, 0.9, 0.4)
	glass_mat_broken_rim.emission_energy_multiplier = 0.6
	
	# Structural Steel Truss Frame: Gunmetal gray with metallic sheen
	frame_mat_steel = StandardMaterial3D.new()
	frame_mat_steel.albedo_color = Color(0.16, 0.20, 0.26)
	frame_mat_steel.metallic = 0.92
	frame_mat_steel.roughness = 0.35
	
	# Concrete Base Pillars
	frame_mat_concrete = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/dry-rocky-ground-bl/dry-rocky-ground_albedo.png"):
		frame_mat_concrete.albedo_texture = load("res://Courses/Environments/dry-rocky-ground-bl/dry-rocky-ground_albedo.png")
		frame_mat_concrete.uv1_scale = Vector3(0.3, 0.3, 0.3)
	else:
		frame_mat_concrete.albedo_color = Color(0.35, 0.38, 0.42)
	frame_mat_concrete.roughness = 0.9
	
	# Tee box green turf
	turf_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-green/albedo.png"):
		turf_mat.albedo_texture = load("res://Courses/Environments/grass-green/albedo.png")
		turf_mat.uv1_scale = Vector3(0.2, 0.2, 0.2)
	else:
		turf_mat.albedo_color = Color(0.18, 0.65, 0.24)
	turf_mat.roughness = 0.9
	
	# Fairway grass
	fairway_mat = StandardMaterial3D.new()
	if ResourceLoader.exists("res://Courses/Environments/grass-fairway/albedo.png"):
		fairway_mat.albedo_texture = load("res://Courses/Environments/grass-fairway/albedo.png")
		fairway_mat.uv1_scale = Vector3(0.08, 0.08, 0.08)
	else:
		fairway_mat.albedo_color = Color(0.22, 0.58, 0.26)
	fairway_mat.roughness = 0.92


# ==============================================================================
# ENVIRONMENT SETUP
# ==============================================================================

func _setup_environment() -> void:
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
	
	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	
	var env = Environment.new()
	env.background_mode = Environment.BG_SKY
	
	var sky = Sky.new()
	var sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.48, 0.82)
	sky_mat.sky_horizon_color = Color(0.55, 0.74, 0.90)
	sky_mat.ground_bottom_color = Color(0.16, 0.28, 0.18)
	sky_mat.ground_horizon_color = Color(0.55, 0.74, 0.90)
	sky_mat.sun_angle_max = 35.0
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
	env.fog_density = 0.0010
	
	world_env.environment = env
	add_child(world_env)
	
	# Main Camera
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)
	if has_node("/root/TensionManager"):
		TensionManager.register_camera(camera, 55.0)
		
	_update_camera_to_tee()


func _update_camera_to_tee() -> void:
	if camera == null:
		return
	viewing_wall_cam = false
	var ball_pos = player.ball.global_position if player and player.ball else Vector3(0.0, 0.05, 0.0)
	camera.global_position = ball_pos + Vector3(-5.5, 2.4, 0.0)
	camera.look_at(Vector3(WALL_DIST_X, 15.0, 0.0))
	last_camera_offset = camera.global_position - ball_pos


func _update_camera_to_wall_cam() -> void:
	if camera == null:
		return
	viewing_wall_cam = true
	camera.global_position = Vector3(WALL_DIST_X - 22.0, 15.0, -16.0)
	camera.look_at(Vector3(WALL_DIST_X, 15.0, 0.0))


func _toggle_camera_view() -> void:
	if viewing_wall_cam:
		_update_camera_to_tee()
		if cam_toggle_btn:
			cam_toggle_btn.text = "🎥 Wall Cam (C)"
	else:
		_update_camera_to_wall_cam()
		if cam_toggle_btn:
			cam_toggle_btn.text = "🏌️ Tee Cam (C)"


# ==============================================================================
# RANGE TERRAIN & DISTANCE MARKERS
# ==============================================================================

func _setup_range_ground() -> void:
	# 1. Main Range Fairway Ground (extends 400m past tee so balls never fall off)
	var ground = StaticBody3D.new()
	ground.name = "RangeFairwayGround"
	ground.set_meta("surface_type", 1) # FAIRWAY
	add_child(ground)
	
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(450.0, 1.0, 160.0)
	col.shape = box
	col.position = Vector3(180.0, -0.5, 0.0)
	ground.add_child(col)
	
	var ground_mesh = MeshInstance3D.new()
	var plane_mesh = BoxMesh.new()
	plane_mesh.size = Vector3(450.0, 1.0, 160.0)
	ground_mesh.mesh = plane_mesh
	ground_mesh.material_override = fairway_mat
	ground_mesh.position = Vector3(180.0, -0.5, 0.0)
	ground.add_child(ground_mesh)
	
	# 2. Tee Box Platform
	var tee = StaticBody3D.new()
	tee.name = "TeeBox"
	tee.set_meta("surface_type", 3) # TEE
	add_child(tee)
	
	var tee_col = CollisionShape3D.new()
	var tee_box_shape = BoxShape3D.new()
	tee_box_shape.size = Vector3(6.0, 0.2, 6.0)
	tee_col.shape = tee_box_shape
	tee_col.position = Vector3(0.0, -0.1, 0.0)
	tee.add_child(tee_col)
	
	var tee_mesh_inst = MeshInstance3D.new()
	var tee_mesh = BoxMesh.new()
	tee_mesh.size = Vector3(6.0, 0.2, 6.0)
	tee_mesh_inst.mesh = tee_mesh
	tee_mesh_inst.material_override = turf_mat
	tee_mesh_inst.position = Vector3(0.0, -0.1, 0.0)
	tee.add_child(tee_mesh_inst)
	
	# 3. Clean Fairway Distance Stripe Lines (25, 50, 75 Yards) - Purely visual clean grass lines
	var distances_yards = [25, 50, 75]
	for yard in distances_yards:
		var dist_m = yard * 0.9144
		_create_yardage_stripe(dist_m)


func _create_yardage_stripe(dist_x: float) -> void:
	var marker_node = Node3D.new()
	marker_node.name = "Stripe_%.1fm" % dist_x
	marker_node.position = Vector3(dist_x, 0.0, 0.0)
	add_child(marker_node)
	
	# Striped lawn yardage line across fairway
	var line_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.02, 46.0)
	line_mesh.mesh = box
	var line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	line_mat.roughness = 0.9
	line_mesh.material_override = line_mat
	line_mesh.position = Vector3(0.0, 0.01, 0.0)
	marker_node.add_child(line_mesh)


# ==============================================================================
# 75-YARD WALL & 3x3 CLEAN SQUARE GLASS GRID GENERATION (NO 3D TEXT)
# ==============================================================================

func _setup_glass_wall_and_panes() -> void:
	var wall_root = Node3D.new()
	wall_root.name = "LoftTargetWall"
	wall_root.position = Vector3(WALL_DIST_X, 0.0, 0.0)
	add_child(wall_root)
	
	pane_nodes.clear()
	pane_mesh_instances.clear()
	pane_areas.clear()
	
	# Total width: 3 columns x 8.5m + 4 mullions/pillars x 0.8m = 28.7m wide (Z from -14.4 to +14.4)
	# Total height: 3 rows x 8.5m + 4 mullions/beams x 0.8m = 28.7m tall (Y from 0.8 to 29.5)
	
	# 1. Structural Concrete Foundation Pillars (Solid bounce StaticBody3D)
	var left_pillar = _create_concrete_pillar(Vector3(0.0, 15.0, -14.4), Vector3(1.6, 30.0, 1.6))
	wall_root.add_child(left_pillar)
	
	var right_pillar = _create_concrete_pillar(Vector3(0.0, 15.0, 14.4), Vector3(1.6, 30.0, 1.6))
	wall_root.add_child(right_pillar)
	
	# Top & Bottom Concrete Header Beams
	var bot_beam = _create_concrete_pillar(Vector3(0.0, 0.8, 0.0), Vector3(1.6, 1.6, 30.0))
	wall_root.add_child(bot_beam)
	
	var top_beam = _create_concrete_pillar(Vector3(0.0, 29.5, 0.0), Vector3(1.6, 1.6, 30.0))
	wall_root.add_child(top_beam)
	
	# 2. Steel Divider Mullions between 3x3 square cells (Solid bounce StaticBody3D)
	# Vertical mullions (at Z = -4.65m and Z = +4.65m)
	for vz in [-4.65, 4.65]:
		var v_mullion = _create_steel_beam(Vector3(0.0, 15.0, vz), Vector3(0.6, 28.0, 0.6))
		wall_root.add_child(v_mullion)
		
	# Horizontal mullions (between rows at Y = 10.65m and Y = 19.95m)
	for hy in [10.65, 19.95]:
		var h_mullion = _create_steel_beam(Vector3(0.0, hy, 0.0), Vector3(0.6, 0.6, 28.0))
		wall_root.add_child(h_mullion)
		
	# 3. Rear Support Buttress Trusses (Angled steel struts extending behind wall)
	for z_truss in [-14.0, -4.65, 4.65, 14.0]:
		var strut = _create_steel_beam(Vector3(8.0, 10.0, z_truss), Vector3(0.4, 0.4, 0.4))
		wall_root.add_child(strut)
		
	# 4. Generate 9 Clean SQUARE Glass Panes in 3x3 Grid (No text, pure glass with neon rim + Area3D trigger)
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var idx = row * GRID_COLS + col
			var py = ROW_Y_CENTERS[row]
			var pz = COL_Z_CENTERS[col]
			
			var pane_node = _create_glass_pane_node(idx, py, pz)
			wall_root.add_child(pane_node)
			pane_nodes.append(pane_node)


func _create_glass_pane_node(idx: int, py: float, pz: float) -> Node3D:
	var pane_root = Node3D.new()
	pane_root.name = "GlassPane_%d" % idx
	pane_root.position = Vector3(0.0, py, pz)
	
	# Clean SQUARE Glass Visual Mesh (PANE_SIZE x PANE_SIZE)
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "GlassMesh"
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(PANE_DEPTH, PANE_SIZE - 0.2, PANE_SIZE - 0.2)
	mesh_inst.mesh = box_mesh
	mesh_inst.material_override = glass_mat_intact
	pane_root.add_child(mesh_inst)
	pane_mesh_instances.append(mesh_inst)
	
	# Surrounding Glowing Neon Frame Border
	var border_inst = MeshInstance3D.new()
	border_inst.name = "GlassBorderGlow"
	var border_mesh = BoxMesh.new()
	border_mesh.size = Vector3(PANE_DEPTH + 0.05, PANE_SIZE, PANE_SIZE)
	border_inst.mesh = border_mesh
	var border_mat = StandardMaterial3D.new()
	border_mat.albedo_color = Color(PANE_COLORS[idx].r, PANE_COLORS[idx].g, PANE_COLORS[idx].b, 0.25)
	border_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	border_mat.emission_enabled = true
	border_mat.emission = PANE_COLORS[idx]
	border_mat.emission_energy_multiplier = 0.5
	border_inst.material_override = border_mat
	pane_root.add_child(border_inst)
	
	# Area3D Trigger Volume sized inside the cell bounds
	var area = Area3D.new()
	area.name = "PaneArea_%d" % idx
	area.set_meta("pane_index", idx)
	area.monitoring = true
	area.monitorable = true
	
	var col_shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(1.5, PANE_SIZE - 0.4, PANE_SIZE - 0.4)
	col_shape.shape = box_shape
	area.add_child(col_shape)
	
	area.body_entered.connect(_on_pane_body_entered.bind(idx))
	
	pane_root.add_child(area)
	pane_areas.append(area)
	
	return pane_root


func _create_concrete_pillar(pos: Vector3, size: Vector3) -> StaticBody3D:
	var sb = StaticBody3D.new()
	sb.position = pos
	sb.set_meta("surface_type", 2) # Solid bounce
	
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	col.shape = box
	sb.add_child(col)
	
	var mi = MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = frame_mat_concrete
	sb.add_child(mi)
	return sb


func _create_steel_beam(pos: Vector3, size: Vector3) -> StaticBody3D:
	var sb = StaticBody3D.new()
	sb.position = pos
	sb.set_meta("surface_type", 2) # Solid bounce
	
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	col.shape = box
	sb.add_child(col)
	
	var mi = MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = frame_mat_steel
	sb.add_child(mi)
	return sb


# ==============================================================================
# PLAYER SETUP
# ==============================================================================

func _setup_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	var start_pos = Vector3(0.0, 0.05, 0.0)
	player.global_position = start_pos
	
	player.set_process(false)
	player.rest.connect(_on_ball_rest)
	
	player.ball.spawn_position = start_pos
	player.ball.reset()
	prev_ball_pos = start_pos


# ==============================================================================
# INPUT & HIT SIMULATION
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_settings()
			get_viewport().set_input_as_handled()
		return
		
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_reset_game()
		elif event.keycode == KEY_C:
			_toggle_camera_view()


func _on_launch_monitor_hit_ball(data: Dictionary) -> void:
	if player == null or player.ball == null:
		return
	if player.ball.state != PhysicsEnums.BallState.REST:
		return
		
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
		
	shot_counter += 1
	attempts_count += 1
	shot_reset_token += 1
	var this_shot = shot_reset_token
	prev_ball_pos = player.ball.global_position
	
	# If currently on wall cam, switch back to tee follow cam on shot hit
	if viewing_wall_cam:
		_update_camera_to_tee()
		
	player._on_tcp_client_hit_ball(data)
	_update_hud()
	
	# Maximum safety timeout: automatically resets ball to tee after 5.0 seconds if not already reset
	_schedule_auto_reset(this_shot, 5.0)


func _schedule_auto_reset(shot_id: int, delay_sec: float) -> void:
	await get_tree().create_timer(delay_sec).timeout
	if is_inside_tree() and shot_reset_token == shot_id:
		_reset_ball_only()


# ==============================================================================
# PHYSICS PROCESS & CONTINUOUS WALL INTERSECTION TRACKING
# ==============================================================================

func _physics_process(delta: float) -> void:
	if player == null or player.ball == null:
		return
		
	var ball = player.ball
	var ball_state = ball.state
	var curr_pos = ball.global_position
	
	# Smooth Camera Follow
	if ball_state == PhysicsEnums.BallState.FLIGHT or ball_state == PhysicsEnums.BallState.ROLLOUT:
		camera_following = true
		
		# If within 25m of the 75-yard wall, frame both ball and target wall
		var target_cam_pos: Vector3
		if curr_pos.x > (WALL_DIST_X - 25.0):
			# Wide suspense angle framing wall and impact
			target_cam_pos = Vector3(curr_pos.x - 7.0, max(curr_pos.y + 2.5, 4.5), curr_pos.z * 0.5)
			camera.global_position = camera.global_position.lerp(target_cam_pos, delta * 6.0)
			camera.look_at(Vector3(WALL_DIST_X, 15.0, 0.0))
		else:
			target_cam_pos = curr_pos + last_camera_offset
			camera.global_position = camera.global_position.lerp(target_cam_pos, delta * 8.0)
			camera.look_at(curr_pos + Vector3(10.0, 0.0, 0.0))
			
		# CONTINUOUS COLLISION DETECTION AT X = 68.58m (75 YARDS)
		# Checks if line segment between previous ball position and current ball position intersects the wall plane
		if (prev_ball_pos.x < WALL_DIST_X and curr_pos.x >= (WALL_DIST_X - 1.0)) or (prev_ball_pos.x <= (WALL_DIST_X + 1.0) and curr_pos.x >= (WALL_DIST_X - 1.0) and absf(curr_pos.x - WALL_DIST_X) < 2.0):
			_check_wall_intersection(prev_ball_pos, curr_pos, ball.velocity)
			
	else:
		if camera_following:
			camera_following = false
			if not viewing_wall_cam:
				_update_camera_to_tee()
				
	prev_ball_pos = curr_pos


func _on_pane_body_entered(body: Node3D, pane_idx: int) -> void:
	if player == null or player.ball == null:
		return
		
	# ONLY the player's golf ball can break the glass!
	var is_ball = (body == player.ball or body == player or (body is CharacterBody3D and body.name.to_lower().contains("ball")))
	if not is_ball:
		return
		
	if not panes_broken[pane_idx]:
		var impact_pos = player.ball.global_position
		impact_pos.x = WALL_DIST_X
		var vel = player.ball.velocity
		_shatter_pane(pane_idx, impact_pos, vel)


func _check_wall_intersection(p0: Vector3, p1: Vector3, vel: Vector3) -> void:
	var dx = p1.x - p0.x
	var impact_y: float
	var impact_z: float
	
	if absf(dx) > 0.0001:
		var t = clampf((WALL_DIST_X - p0.x) / dx, 0.0, 1.0)
		impact_y = lerp(p0.y, p1.y, t)
		impact_z = lerp(p0.z, p1.z, t)
	else:
		impact_y = p1.y
		impact_z = p1.z
		
	var impact_pos = Vector3(WALL_DIST_X, impact_y, impact_z)
	
	# Determine if impact hits any of the 3x3 square panes
	var hit_pane_idx = -1
	var half_size = PANE_SIZE / 2.0
	
	for row in range(GRID_ROWS):
		var r_center_y = ROW_Y_CENTERS[row]
		if impact_y >= (r_center_y - half_size) and impact_y <= (r_center_y + half_size):
			for col in range(GRID_COLS):
				var c_center_z = COL_Z_CENTERS[col]
				if impact_z >= (c_center_z - half_size) and impact_z <= (c_center_z + half_size):
					hit_pane_idx = row * GRID_COLS + col
					break
			if hit_pane_idx != -1:
				break
				
	last_shot_data = {
		"Apex": player.apex if "apex" in player else impact_y,
		"LaunchAngle": impact_y,
		"TargetHit": PANE_NAMES[hit_pane_idx] if hit_pane_idx != -1 else "Frame / Miss",
		"ImpactPos": impact_pos
	}
	
	if hit_pane_idx != -1:
		if not panes_broken[hit_pane_idx]:
			# SHATTER UNBROKEN GLASS PANE!
			_shatter_pane(hit_pane_idx, impact_pos, vel)
	else:
		# Check if hit solid outer frame or missed completely
		if impact_y >= 0.0 and impact_y <= 31.0 and absf(impact_z) <= 15.0:
			_on_frame_hit(impact_pos)


# ==============================================================================
# GLASS SHATTERING & IMPACT MECHANICS
# ==============================================================================

func _shatter_pane(idx: int, impact_pos: Vector3, vel: Vector3) -> void:
	if panes_broken[idx]:
		return
		
	panes_broken[idx] = true
	broken_count += 1
	
	# 1. Play shattering sound
	if sfx_shatter_player:
		sfx_shatter_player.pitch_scale = randf_range(0.96, 1.05)
		sfx_shatter_player.play()
		
	# 2. Hide intact glass visual mesh
	if idx < pane_mesh_instances.size() and pane_mesh_instances[idx] != null:
		pane_mesh_instances[idx].visible = false
		
	# 3. Spawn 3D exploding glass shard debris
	_spawn_glass_shards(impact_pos, vel)
	
	# 4. Update HUD Matrix & Scoreboard
	_update_hud()
	
	# 5. Check Victory Condition (All 9 Panes Broken!)
	if broken_count >= 9:
		_trigger_victory()
		
	# Automatically reset ball to tee box after 2.0 seconds
	var this_shot = shot_reset_token
	_schedule_auto_reset(this_shot, 2.0)


func _spawn_glass_shards(impact_pos: Vector3, incoming_vel: Vector3) -> void:
	var shards_root = Node3D.new()
	shards_root.name = "GlassShardsBurst"
	shards_root.position = impact_pos
	add_child(shards_root)
	
	var shard_count = 32
	var shard_meshes: Array[MeshInstance3D] = []
	var shard_velocities: Array[Vector3] = []
	var shard_rot_speeds: Array[Vector3] = []
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var fwd_dir = incoming_vel.normalized() if incoming_vel.length() > 1.0 else Vector3(1.0, 0.0, 0.0)
	
	for i in range(shard_count):
		var sm = MeshInstance3D.new()
		var prism = PrismMesh.new()
		var s_w = rng.randf_range(0.3, 0.7)
		var s_h = rng.randf_range(0.3, 0.8)
		prism.size = Vector3(s_w, s_h, 0.05)
		sm.mesh = prism
		
		var s_mat = StandardMaterial3D.new()
		s_mat.albedo_color = Color(0.4, 0.8, 1.0, 0.75)
		s_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		s_mat.roughness = 0.1
		s_mat.metallic = 0.8
		s_mat.emission_enabled = true
		s_mat.emission = Color(0.2, 0.6, 0.9)
		s_mat.emission_energy_multiplier = 0.5
		sm.material_override = s_mat
		
		# Offset slightly from impact center
		sm.position = Vector3(
			rng.randf_range(-0.1, 0.1),
			rng.randf_range(-1.2, 1.2),
			rng.randf_range(-1.2, 1.2)
		)
		shards_root.add_child(sm)
		shard_meshes.append(sm)
		
		# Velocity: forward push + outward burst
		var burst_dir = (fwd_dir * 0.7 + Vector3(rng.randf_range(-0.3, 0.8), rng.randf_range(-0.5, 0.8), rng.randf_range(-1.0, 1.0))).normalized()
		var speed = rng.randf_range(8.0, 22.0)
		shard_velocities.append(burst_dir * speed)
		shard_rot_speeds.append(Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0)))
		
	# Cleanup shards after animation
	var timer = get_tree().create_timer(2.0)
	timer.timeout.connect(func():
		if is_instance_valid(shards_root):
			shards_root.queue_free()
	)


func _on_frame_hit(impact_pos: Vector3) -> void:
	if sfx_frame_player:
		sfx_frame_player.pitch_scale = randf_range(0.9, 1.1)
		sfx_frame_player.play()
	
	# Automatically reset ball to tee box after 2.0 seconds
	var this_shot = shot_reset_token
	_schedule_auto_reset(this_shot, 2.0)


func _trigger_victory() -> void:
	is_victory = true
	if sfx_applause_player:
		sfx_applause_player.play()
	if GlobalSettings:
		GlobalSettings.play_golf_clap()


func _on_ball_rest(_data: Dictionary) -> void:
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
		
	_update_hud()
	
	# Auto reset ball to tee box after 1.8 seconds
	var this_shot = shot_reset_token
	await get_tree().create_timer(1.8).timeout
	if is_inside_tree() and shot_reset_token == this_shot:
		_reset_ball_only()


# ==============================================================================
# RESET MECHANICS
# ==============================================================================

func _reset_game() -> void:
	is_victory = false
	broken_count = 0
	attempts_count = 0
	
	for i in range(panes_broken.size()):
		panes_broken[i] = false
		
		# Restore visual glass mesh
		if i < pane_mesh_instances.size() and pane_mesh_instances[i] != null:
			pane_mesh_instances[i].visible = true
			
	_reset_ball_only()
	_update_hud()


func _reset_ball_only() -> void:
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	if player and player.ball:
		var start_pos = Vector3(0.0, 0.05, 0.0)
		player.global_position = start_pos
		player.ball.spawn_position = start_pos
		player.ball.reset()
		player.reset_ball()
		player.ball.aim_yaw_offset_deg = 0.0
		prev_ball_pos = start_pos
		if not viewing_wall_cam:
			_update_camera_to_tee()


# ==============================================================================
# UI & HUD CREATION
# ==============================================================================

func _setup_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "LoftHUDLayer"
	hud_layer.layer = 1
	add_child(hud_layer)
	
	hud_control = Control.new()
	hud_control.name = "HUDControl"
	hud_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_control.anchor_right = 1.0
	hud_control.anchor_bottom = 1.0
	hud_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_control)
	
	# Shared Glass Style for HUD Cards
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
	
	# --- 1. TOP SCOREBOARD PANEL ---
	var score_panel = PanelContainer.new()
	score_panel.custom_minimum_size = Vector2(860, 90)
	score_panel.anchor_left = 0.5
	score_panel.anchor_right = 0.5
	score_panel.anchor_top = 0.0
	score_panel.offset_left = -430
	score_panel.offset_right = 430
	score_panel.offset_top = 20
	score_panel.offset_bottom = 110
	hud_control.add_child(score_panel)
	score_panel.add_theme_stylebox_override("panel", glass_style)
	
	var score_margin = MarginContainer.new()
	score_margin.add_theme_constant_override("margin_left", 20)
	score_margin.add_theme_constant_override("margin_right", 20)
	score_panel.add_child(score_margin)
	
	var score_hbox = HBoxContainer.new()
	score_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	score_margin.add_child(score_hbox)
	
	panes_cleared_lbl = _create_stat_column(score_hbox, "PANES CLEARED", "0 / 9")
	panes_cleared_lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	
	attempts_lbl = _create_stat_column(score_hbox, "TOTAL ATTEMPTS", "0")
	accuracy_lbl = _create_stat_column(score_hbox, "ACCURACY", "0.0%")
	last_shot_lbl = _create_stat_column(score_hbox, "LAST TARGET", "None")
	
	# --- 2. LEFT 3x3 LIVE MATRIX HUD CARD ---
	var matrix_panel = PanelContainer.new()
	matrix_panel.custom_minimum_size = Vector2(250, 290)
	matrix_panel.anchor_left = 0.0
	matrix_panel.anchor_top = 0.5
	matrix_panel.anchor_bottom = 0.5
	matrix_panel.offset_left = 24
	matrix_panel.offset_top = -145
	matrix_panel.offset_bottom = 145
	hud_control.add_child(matrix_panel)
	matrix_panel.add_theme_stylebox_override("panel", glass_style)
	
	var matrix_margin = MarginContainer.new()
	matrix_margin.add_theme_constant_override("margin_left", 14)
	matrix_margin.add_theme_constant_override("margin_right", 14)
	matrix_margin.add_theme_constant_override("margin_top", 14)
	matrix_margin.add_theme_constant_override("margin_bottom", 14)
	matrix_panel.add_child(matrix_margin)
	
	var matrix_vbox = VBoxContainer.new()
	matrix_vbox.add_theme_constant_override("separation", 8)
	matrix_margin.add_child(matrix_vbox)
	
	var m_title = Label.new()
	m_title.text = "3x3 GLASS TARGETS"
	m_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m_title.add_theme_font_size_override("font_size", 13)
	m_title.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
	matrix_vbox.add_child(m_title)
	
	# GridContainer with 3 columns for 9 buttons
	var grid_cont = GridContainer.new()
	grid_cont.columns = 3
	grid_cont.add_theme_constant_override("h_separation", 6)
	grid_cont.add_theme_constant_override("v_separation", 6)
	matrix_vbox.add_child(grid_cont)
	
	hud_matrix_buttons.clear()
	var short_names = ["1 TL", "2 TM", "3 TR", "4 ML", "5 MM", "6 MR", "7 BL", "8 BM", "9 BR"]
	for i in range(9):
		var btn = Button.new()
		btn.text = short_names[i]
		btn.custom_minimum_size = Vector2(68, 64)
		btn.add_theme_font_size_override("font_size", 13)
		_apply_matrix_btn_style(btn, false)
		btn.tooltip_text = "[%d] %s (%s)" % [i + 1, PANE_NAMES[i], PANE_DESCS[i]]
		grid_cont.add_child(btn)
		hud_matrix_buttons.append(btn)
		
	# --- 3. BOTTOM CONTROLS PANEL ---
	var ctrl_panel = PanelContainer.new()
	ctrl_panel.custom_minimum_size = Vector2(500, 68)
	ctrl_panel.anchor_left = 0.5
	ctrl_panel.anchor_right = 0.5
	ctrl_panel.anchor_top = 1.0
	ctrl_panel.anchor_bottom = 1.0
	ctrl_panel.offset_left = -250
	ctrl_panel.offset_right = 250
	ctrl_panel.offset_top = -88
	ctrl_panel.offset_bottom = -20
	hud_control.add_child(ctrl_panel)
	ctrl_panel.add_theme_stylebox_override("panel", glass_style)
	
	var ctrl_margin = MarginContainer.new()
	ctrl_margin.add_theme_constant_override("margin_left", 16)
	ctrl_margin.add_theme_constant_override("margin_right", 16)
	ctrl_panel.add_child(ctrl_margin)
	
	var ctrl_hbox = HBoxContainer.new()
	ctrl_hbox.add_theme_constant_override("separation", 14)
	ctrl_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ctrl_margin.add_child(ctrl_hbox)
	
	# 1. Reset Button
	var reset_btn = Button.new()
	reset_btn.text = "🔄 RESET (R)"
	reset_btn.custom_minimum_size = Vector2(130, 42)
	_apply_btn_style(reset_btn, Color(0.55, 0.22, 0.15), Color(0.70, 0.30, 0.20))
	reset_btn.pressed.connect(_reset_game)
	ctrl_hbox.add_child(reset_btn)
	
	# 2. Camera Toggle Button
	cam_toggle_btn = Button.new()
	cam_toggle_btn.text = "🎥 Wall Cam (C)"
	cam_toggle_btn.custom_minimum_size = Vector2(135, 42)
	_apply_btn_style(cam_toggle_btn, Color(0.18, 0.34, 0.50), Color(0.24, 0.44, 0.65))
	cam_toggle_btn.pressed.connect(_toggle_camera_view)
	ctrl_hbox.add_child(cam_toggle_btn)
	
	# 3. Music Toggle Button
	music_toggle_btn = Button.new()
	music_toggle_btn.name = "MusicToggleButton"
	music_toggle_btn.text = ""
	music_toggle_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_toggle_btn.expand_icon = true
	music_toggle_btn.custom_minimum_size = Vector2(42, 42)
	music_toggle_btn.pressed.connect(_toggle_music)
	ctrl_hbox.add_child(music_toggle_btn)
	
	# 4. Settings Button
	var settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.icon = load("res://Utils/Settings/Gear.png")
	settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.custom_minimum_size = Vector2(42, 42)
	_apply_btn_style(settings_btn, Color(0.18, 0.34, 0.50), Color(0.24, 0.44, 0.65))
	settings_btn.pressed.connect(_on_settings_pressed)
	ctrl_hbox.add_child(settings_btn)
	
	# 5. Exit Button
	var exit_btn = Button.new()
	exit_btn.text = "EXIT"
	exit_btn.custom_minimum_size = Vector2(74, 42)
	_apply_btn_style(exit_btn, Color(0.36, 0.16, 0.16), Color(0.48, 0.20, 0.20))
	exit_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MiniGamesMenu/minigames_menu.tscn"))
	ctrl_hbox.add_child(exit_btn)
	
	_update_hud()
	_update_music_button_state()
	GlobalSettings.range_settings.minigame_music_enabled.setting_changed.connect(func(_val): _update_music_button_state())


func _create_stat_column(parent: HBoxContainer, title: String, default_val: String) -> Label:
	var col = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(col)
	
	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	col.add_child(title_lbl)
	
	var val_lbl = Label.new()
	val_lbl.text = default_val
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 26)
	val_lbl.add_theme_color_override("font_color", Color.WHITE)
	val_lbl.add_theme_constant_override("outline_size", 2)
	val_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	col.add_child(val_lbl)
	return val_lbl


func _update_hud() -> void:
	if panes_cleared_lbl:
		panes_cleared_lbl.text = "%d / 9" % broken_count
	if attempts_lbl:
		attempts_lbl.text = str(attempts_count)
	if accuracy_lbl:
		var acc = (float(broken_count) / float(attempts_count) * 100.0) if attempts_count > 0 else 0.0
		accuracy_lbl.text = "%.1f%%" % acc
	if last_shot_lbl and not last_shot_data.is_empty():
		last_shot_lbl.text = str(last_shot_data.get("TargetHit", "None"))
		
	# Update 3x3 Matrix Buttons
	for i in range(hud_matrix_buttons.size()):
		var is_broken = panes_broken[i]
		_apply_matrix_btn_style(hud_matrix_buttons[i], is_broken)


func _apply_matrix_btn_style(btn: Button, is_broken: bool) -> void:
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	
	if is_broken:
		style.bg_color = Color(0.12, 0.45, 0.22, 0.9)
		style.border_color = Color(0.3, 0.9, 0.45)
		btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
		btn.text = "💥"
	else:
		style.bg_color = Color(0.10, 0.22, 0.35, 0.85)
		style.border_color = Color(0.25, 0.65, 0.95, 0.6)
		btn.add_theme_color_override("font_color", Color(0.8, 0.95, 1.0))
		var short_names = ["1 TL", "2 TM", "3 TR", "4 ML", "5 MM", "6 MR", "7 BL", "8 BM", "9 BR"]
		var idx = hud_matrix_buttons.find(btn)
		if idx >= 0 and idx < short_names.size():
			btn.text = short_names[idx]
			
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_stylebox_override("focus", style)


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
	style_normal.border_color = Color(1, 1, 1, 0.2)
	
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
	style_hover.border_color = Color(1, 1, 1, 0.4)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("focus", style_normal)
	btn.add_theme_color_override("font_color", Color.WHITE)


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
		_apply_btn_style(music_toggle_btn, Color(0.18, 0.34, 0.50), Color(0.24, 0.44, 0.65))
	else:
		if ResourceLoader.exists("res://assets/images/menu/music_off.svg"):
			music_toggle_btn.icon = load("res://assets/images/menu/music_off.svg")
		music_toggle_btn.tooltip_text = "Music: Muted (Click to play)"
		_apply_btn_style(music_toggle_btn, Color(0.35, 0.18, 0.18), Color(0.45, 0.25, 0.25))


func _on_settings_pressed() -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		return

	var settings_scene = load("res://UI/Settings/RangeSettings/range_settings.tscn")
	if settings_scene == null:
		return

	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.visible = false

	_settings_layer = CanvasLayer.new()
	_settings_layer.name = "SettingsLayer"
	_settings_layer.layer = 105
	add_child(_settings_layer)

	var backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.02, 0.04, 0.07, 0.75)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_layer.add_child(backdrop)

	var margin_container = MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", 36)
	margin_container.add_theme_constant_override("margin_right", 36)
	margin_container.add_theme_constant_override("margin_top", 24)
	margin_container.add_theme_constant_override("margin_bottom", 24)
	_settings_layer.add_child(margin_container)

	var inst = settings_scene.instantiate()
	inst.name = "MinigameSettings"
	inst.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inst.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_child(inst)

	inst.close_settings_requested.connect(_close_settings)
	if inst.has_signal("manage_players_requested"):
		inst.manage_players_requested.connect(func():
			_close_settings()
			SceneManager.change_scene("res://UI/PlayersMenu/players_menu.tscn")
		)


func _close_settings() -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		_settings_layer.queue_free()
		_settings_layer = null

	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.visible = true
