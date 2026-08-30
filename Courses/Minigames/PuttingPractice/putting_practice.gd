extends Node3D

# Preloaded assets
var PlayerScene = preload("res://Player/player.tscn")

# Minigame state variables
var player = null
var selected_hole_index = 0
var last_putt_start_pos = Vector3.ZERO
var last_putt_target_hole = Vector3.ZERO
var show_green_grid: bool = false

# Stats counters
var stats_attempts = 0
var stats_within_10 = 0
var stats_within_5 = 0
var stats_made = 0
var stats_attempts_25_plus = 0

# Camera follow state
var last_camera_offset = Vector3.ZERO
var camera_following = false
var is_dragging = false

# Green grid sampling bounds: covering kidney bean green span (approx. 48m x 48m)
var green_min_x = -24.0
var green_max_x = 24.0
var green_min_z = -24.0
var green_max_z = 24.0

# Hole configurations (5, 10, 15, 20, 25, 30, 40, 50 feet from starting spot)
var hole_data = [
	{"dist_ft": 5, "angle_deg": -45.0, "desc": "Short Warmup"},
	{"dist_ft": 10, "angle_deg": 135.0, "desc": "Pressure Putt"},
	{"dist_ft": 15, "angle_deg": -120.0, "desc": "Mid-Short Break"},
	{"dist_ft": 20, "angle_deg": 30.0, "desc": "Mid Downhill"},
	{"dist_ft": 25, "angle_deg": -75.0, "desc": "Mid-Long Ridge"},
	{"dist_ft": 30, "angle_deg": 105.0, "desc": "Long Slope"},
	{"dist_ft": 40, "angle_deg": -105.0, "desc": "Lag Cross-Slope"},
	{"dist_ft": 50, "angle_deg": 50.0, "desc": "Long Distance Lag"},
]
var holes = []
var hole_buttons = []
var shot_counter: int = 0

# UI elements
var attempts_val_lbl = null
var within_10_val_lbl = null
var within_5_val_lbl = null
var made_val_lbl = null
var dist_25_val_lbl = null
var banner_lbl = null
var grid_toggle_btn = null
var music_toggle_btn = null
var hud_layer: CanvasLayer = null
var hud_control: Control = null
var _settings_layer: CanvasLayer = null

func _ready() -> void:
	name = "PuttingPractice"
	
	# 1. Environment Setup
	_setup_environment()
	
	# 2. Generate Kidney-Bean Green & Rough Terrain
	_generate_green_and_rough_terrain()
	_generate_green_grid_and_heatmap()
	
	# 3. Generate Surrounding Environment (Trees & Bushes)
	_generate_trees()
	
	# 4. Setup Player
	_setup_player()
	
	# 5. Setup Target Holes
	_setup_holes()
	
	# 6. Setup GUI
	_setup_ui()
	
	# Select first hole by default
	_select_hole(0)
	
	if has_node("/root/EventBus"):
		var eb = get_node("/root/EventBus")
		if eb.has_signal("club_selected"):
			eb.club_selected.emit("Pt")
	
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

# ----------------- ENVIRONMENT SETUP -----------------

func _setup_environment() -> void:
	# Add DirectionalLight3D
	var sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(-60)).rotated(Vector3.UP, deg_to_rad(45))
	sun.shadow_enabled = true
	add_child(sun)
	
	# WorldEnvironment with a simple sky
	var world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.65, 0.85) # Sky blue
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	
	world_env.environment = env
	add_child(world_env)
	
	# Create Camera3D
	var camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	add_child(camera)
	if has_node("/root/TensionManager"):
		TensionManager.register_camera(camera, 55.0)

# ----------------- PROCEDURAL TERRAIN -----------------

func get_height(x: float, z: float) -> float:
	var z_clamped = clamp(z, green_min_z, green_max_z)
	var base_slope = - (z_clamped / 15.24) * 0.15
	var undulation = 0.035 * sin(x * 0.35) + 0.03 * cos(z * 0.28 + 0.6) + 0.015 * sin(x * 0.22 - z * 0.25)
	var dist_from_center = Vector2(x, z).length()
	var outer_mound = 0.0
	if dist_from_center > 21.0:
		var factor = (dist_from_center - 21.0) * 0.05
		outer_mound = sin(x * 0.15 + z * 0.15) * 0.15 * factor
		
	return base_slope + undulation + outer_mound

func get_green_radius(angle: float) -> float:
	var r = 18.0
	# North-South elongation
	r += 3.5 * sin(angle - 0.1)
	# Dual lobe structure
	r -= 2.0 * cos(2.0 * (angle - 0.1))
	# Southeast bulge for 50 ft hole
	r += 2.5 * exp(- pow(angle - 0.87, 2) / 0.8)
	# West side kidney notch
	var notch_angle = angle - 2.8 if angle > 0 else angle + 2.8
	var notch = 3.5 * exp(- (notch_angle * notch_angle) / 0.6)
	r -= notch
	return r

func is_inside_green(x: float, z: float) -> bool:
	var rel = Vector2(x, z)
	var dist = rel.length()
	if dist < 0.001:
		return true
	return dist <= get_green_radius(rel.angle())

func _generate_green_and_rough_terrain() -> void:
	var st_green = SurfaceTool.new()
	st_green.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat_green = StandardMaterial3D.new()
	mat_green.albedo_texture = load("res://Courses/Environments/grass-green/albedo.png")
	mat_green.roughness = 0.95
	mat_green.specular = 0.1
	st_green.set_material(mat_green)
	
	var st_rough = SurfaceTool.new()
	st_rough.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mat_rough = StandardMaterial3D.new()
	mat_rough.albedo_texture = load("res://Courses/Environments/grass-rough/albedo.png")
	mat_rough.roughness = 0.95
	mat_rough.specular = 0.05
	st_rough.set_material(mat_rough)
	
	var min_grid = -24.0
	var max_grid = 24.0
	var subdiv = 120 # 0.4m grid resolution for ultra-smooth kidney bean boundary
	var step = (max_grid - min_grid) / float(subdiv)
	
	var add_poly = func(st: SurfaceTool, poly_pts: Array, uv_scale: float):
		if poly_pts.size() < 3:
			return
		var p0 = poly_pts[0]
		for i in range(1, poly_pts.size() - 1):
			var p1 = poly_pts[i]
			var p2 = poly_pts[i + 1]
			
			var v0 = Vector3(p0.x, get_height(p0.x, p0.y), p0.y)
			var v1 = Vector3(p1.x, get_height(p1.x, p1.y), p1.y)
			var v2 = Vector3(p2.x, get_height(p2.x, p2.y), p2.y)
			
			st.set_uv(Vector2(v0.x, v0.z) * uv_scale)
			st.add_vertex(v0)
			st.set_uv(Vector2(v1.x, v1.z) * uv_scale)
			st.add_vertex(v1)
			st.set_uv(Vector2(v2.x, v2.z) * uv_scale)
			st.add_vertex(v2)
			
	for iz in range(subdiv):
		for ix in range(subdiv):
			var x0 = min_grid + ix * step
			var x1 = x0 + step
			var z0 = min_grid + iz * step
			var z1 = z0 + step
			
			var corners = [
				Vector2(x0, z0),
				Vector2(x1, z0),
				Vector2(x1, z1),
				Vector2(x0, z1)
			]
			
			var val = []
			for c in corners:
				var dist = c.length()
				var r_bound = get_green_radius(c.angle()) if dist >= 0.001 else 15.0
				val.append(r_bound - dist)
				
			var g_pts = []
			var r_pts = []
			
			for i in range(4):
				var curr_c = corners[i]
				var curr_v = val[i]
				var next_i = (i + 1) % 4
				var next_c = corners[next_i]
				var next_v = val[next_i]
				
				if curr_v >= 0.0:
					g_pts.append(curr_c)
				else:
					r_pts.append(curr_c)
					
				if (curr_v > 0.0 and next_v < 0.0) or (curr_v < 0.0 and next_v > 0.0):
					var t = curr_v / (curr_v - next_v)
					var inter = curr_c.lerp(next_c, t)
					g_pts.append(inter)
					r_pts.append(inter)
					
			add_poly.call(st_green, g_pts, 0.3)
			add_poly.call(st_rough, r_pts, 0.25)
			
	# Surrounding outer rough terrain out to 90x90m (-45 to +45)
	var outer_sections = [
		{"min_x": -45.0, "max_x": 45.0, "min_z": -45.0, "max_z": min_grid, "div_x": 30, "div_z": 15},
		{"min_x": -45.0, "max_x": 45.0, "min_z": max_grid, "max_z": 45.0, "div_x": 30, "div_z": 15},
		{"min_x": -45.0, "max_x": min_grid, "min_z": min_grid, "max_z": max_grid, "div_x": 15, "div_z": 30},
		{"min_x": max_grid, "max_x": 45.0, "min_z": min_grid, "max_z": max_grid, "div_x": 15, "div_z": 30},
	]
	
	for sec in outer_sections:
		var cell_w = (sec["max_x"] - sec["min_x"]) / sec["div_x"]
		var cell_d = (sec["max_z"] - sec["min_z"]) / sec["div_z"]
		
		for z in range(sec["div_z"]):
			for x in range(sec["div_x"]):
				var x0 = sec["min_x"] + x * cell_w
				var x1 = x0 + cell_w
				var z0 = sec["min_z"] + z * cell_d
				var z1 = z0 + cell_d
				
				var p00 = Vector3(x0, get_height(x0, z0), z0)
				var p10 = Vector3(x1, get_height(x1, z0), z0)
				var p01 = Vector3(x0, get_height(x0, z1), z1)
				var p11 = Vector3(x1, get_height(x1, z1), z1)
				
				st_rough.set_uv(Vector2(x0, z0) * 0.25)
				st_rough.add_vertex(p00)
				st_rough.set_uv(Vector2(x1, z0) * 0.25)
				st_rough.add_vertex(p10)
				st_rough.set_uv(Vector2(x0, z1) * 0.25)
				st_rough.add_vertex(p01)
				
				st_rough.set_uv(Vector2(x1, z0) * 0.25)
				st_rough.add_vertex(p10)
				st_rough.set_uv(Vector2(x1, z1) * 0.25)
				st_rough.add_vertex(p11)
				st_rough.set_uv(Vector2(x0, z1) * 0.25)
				st_rough.add_vertex(p01)
				
	st_green.generate_normals()
	var mesh_green = st_green.commit()
	var mi_green = MeshInstance3D.new()
	mi_green.mesh = mesh_green
	mi_green.name = "PuttingGreenMesh"
	add_child(mi_green)
	
	var sb_green = StaticBody3D.new()
	sb_green.name = "PuttingGreen"
	sb_green.set_meta("surface_type", 4) # GREEN
	mi_green.add_child(sb_green)
	
	var cs_green = CollisionShape3D.new()
	cs_green.shape = mesh_green.create_trimesh_shape()
	sb_green.add_child(cs_green)
	
	st_rough.generate_normals()
	var mesh_rough = st_rough.commit()
	var mi_rough = MeshInstance3D.new()
	mi_rough.mesh = mesh_rough
	mi_rough.name = "PuttingRoughMesh"
	add_child(mi_rough)
	
	var sb_rough = StaticBody3D.new()
	sb_rough.name = "PuttingRough"
	sb_rough.set_meta("surface_type", 2) # ROUGH
	mi_rough.add_child(sb_rough)
	
	var cs_rough = CollisionShape3D.new()
	cs_rough.shape = mesh_rough.create_trimesh_shape()
	sb_rough.add_child(cs_rough)


func _generate_trees() -> void:
	var tree_paths = [
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-1-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-2-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-3-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-01-4-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-1-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-2-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-3-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-02-4-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-1-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-2-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-3-staticbody.tscn",
		"res://addons/shapespark-low-poly-exterior-plants/bodies/tree-03-4-staticbody.tscn"
	]
	
	var trees_folder = Node3D.new()
	trees_folder.name = "TreesFolder"
	add_child(trees_folder)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	
	var total_trees = 40
	var spawned = 0
	var attempts = 0
	
	while spawned < total_trees and attempts < 250:
		attempts += 1
		var angle = rng.randf_range(0.0, TAU)
		var min_tree_dist = max(get_green_radius(angle) + 2.0, 20.0)
		var dist = rng.randf_range(min_tree_dist, 44.0)
		
		var tx = cos(angle) * dist
		var tz = sin(angle) * dist
		var ty = get_height(tx, tz)
		
		var path_idx = rng.randi_range(0, tree_paths.size() - 1)
		var scene = load(tree_paths[path_idx])
		if scene:
			var tree_inst = scene.instantiate()
			tree_inst.name = "Tree_%d" % spawned
			tree_inst.position = Vector3(tx, ty, tz)
			
			var s = rng.randf_range(2.2, 4.2)
			tree_inst.scale = Vector3(s, s, s)
			tree_inst.rotation = Vector3(0.0, rng.randf_range(0.0, TAU), 0.0)
			
			trees_folder.add_child(tree_inst)
			spawned += 1

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

# ----------------- SLOPE GRID & HEATMAP SYSTEM -----------------

func _generate_green_grid_and_heatmap() -> void:
	for n_name in ["GreenHeatmapMesh", "GreenGridMesh", "GreenDotsMesh"]:
		var node = get_node_or_null(n_name)
		if node:
			remove_child(node)
			node.queue_free()
			
	var spacing = 1.0 # 1 meter cell grid
	var ix_start = int(floor(green_min_x / spacing))
	var ix_end = int(ceil(green_max_x / spacing)) - 1
	var iz_start = int(floor(green_min_z / spacing))
	var iz_end = int(ceil(green_max_z / spacing)) - 1
	
	var min_y = 99999.0
	var max_y = -99999.0
	
	# Sample height range for heatmap normalization
	for iz in range(iz_start, iz_end + 1):
		for ix in range(ix_start, ix_end + 1):
			var gx = (ix + 0.5) * spacing
			var gz = (iz + 0.5) * spacing
			var hy = get_height(gx, gz)
			if hy < min_y: min_y = hy
			if hy > max_y: max_y = hy
			
	if max_y - min_y < 0.001:
		max_y = min_y + 1.0
		
	var st_heatmap = SurfaceTool.new()
	st_heatmap.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var st_grid = SurfaceTool.new()
	st_grid.begin(Mesh.PRIMITIVE_LINES)
	
	var heatmap_y_offset = 0.005
	var grid_y_offset = 0.012
	var dot_y_offset = 0.022
	
	var height_cache = {}
	var get_cached_height = func(gx: float, gz: float) -> float:
		var key = Vector2(gx, gz)
		if not height_cache.has(key):
			height_cache[key] = get_height(gx, gz)
		return height_cache[key]
		
	for iz in range(iz_start, iz_end + 1):
		for ix in range(ix_start, ix_end + 1):
			var x0 = ix * spacing
			var x1 = (ix + 1) * spacing
			var z0 = iz * spacing
			var z1 = (iz + 1) * spacing
			
			var center_x = (x0 + x1) * 0.5
			var center_z = (z0 + z1) * 0.5
			if not is_inside_green(center_x, center_z):
				continue
				
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
			
			# Heatmap Tri 1
			st_heatmap.set_color(col00)
			st_heatmap.add_vertex(h00)
			st_heatmap.set_color(col10)
			st_heatmap.add_vertex(h10)
			st_heatmap.set_color(col11)
			st_heatmap.add_vertex(h11)
			
			# Heatmap Tri 2
			st_heatmap.set_color(col00)
			st_heatmap.add_vertex(h00)
			st_heatmap.set_color(col11)
			st_heatmap.add_vertex(h11)
			st_heatmap.set_color(col01)
			st_heatmap.add_vertex(h01)
			
			# Grid Lines
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
			
	# Collect edges for slope flow arrows
	var h_edges = {}
	var v_edges = {}
	for iz in range(iz_start, iz_end + 1):
		for ix in range(ix_start, ix_end + 1):
			if is_inside_green((ix + 0.5) * spacing, (iz + 0.5) * spacing):
				h_edges[Vector2i(ix, iz)] = true
				h_edges[Vector2i(ix, iz + 1)] = true
				v_edges[Vector2i(ix, iz)] = true
				v_edges[Vector2i(ix + 1, iz)] = true
			
	var dots_data = []
	
	# Horizontal edges (slope arrows)
	for edge in h_edges.keys():
		var x0 = edge.x * spacing
		var z0 = edge.y * spacing
		var x1 = (edge.x + 1) * spacing
		var z1 = edge.y * spacing
		
		if not is_inside_green(x0, z0) or not is_inside_green(x1, z1):
			continue
		
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
				
	# Vertical edges (slope arrows)
	for edge in v_edges.keys():
		var x0 = edge.x * spacing
		var z0 = edge.y * spacing
		var x1 = edge.x * spacing
		var z1 = (edge.y + 1) * spacing
		
		if not is_inside_green(x0, z0) or not is_inside_green(x1, z1):
			continue
		
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
				
	# Commit Heatmap Mesh (hidden by default to match regular course play)
	var heatmap_mesh = st_heatmap.commit()
	var heatmap_mi = MeshInstance3D.new()
	heatmap_mi.name = "GreenHeatmapMesh"
	heatmap_mi.mesh = heatmap_mesh
	var mat_hm = StandardMaterial3D.new()
	mat_hm.vertex_color_use_as_albedo = true
	mat_hm.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat_hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	heatmap_mi.material_override = mat_hm
	heatmap_mi.visible = false
	add_child(heatmap_mi)
	
	# Commit Grid Mesh
	var grid_mesh = st_grid.commit()
	var grid_mi = MeshInstance3D.new()
	grid_mi.name = "GreenGridMesh"
	grid_mi.mesh = grid_mesh
	var mat_g = StandardMaterial3D.new()
	mat_g.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	mat_g.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat_g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_mi.material_override = mat_g
	grid_mi.visible = show_green_grid
	add_child(grid_mi)
	
	# Commit Moving Slope Arrows MultiMesh
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
	
	// Speed scales dynamically with slope so steeper slopes flow faster, but subtle slopes remain clearly active
	float move_speed = 0.4 + clamp(slope_val * 35.0, 0.0, 2.6);
	float progress = fract(TIME * move_speed * time_scale + phase_offset + segment_phase);
	
	vec4 world_offset = vec4(displacement * progress, 0.0);
	vec4 local_offset = inverse(MODEL_MATRIX) * world_offset;
	VERTEX += local_offset.xyz;
	
	float fade = sin(progress * 3.14159265);
	
	// Dynamic color transition based on slope severity (0.2% to 3.6%+)
	float t = clamp(slope_val * 28.0, 0.0, 1.0);
	
	vec3 col;
	if (t < 0.2) {
		// 0% - 0.7% slope: Sky Blue -> Cyan
		col = mix(vec3(0.1, 0.6, 1.0), vec3(0.0, 0.95, 0.9), t / 0.2);
	} else if (t < 0.4) {
		// 0.7% - 1.4% slope: Cyan -> Lime Green
		col = mix(vec3(0.0, 0.95, 0.9), vec3(0.2, 0.95, 0.2), (t - 0.2) / 0.2);
	} else if (t < 0.6) {
		// 1.4% - 2.1% slope: Lime Green -> Bright Yellow
		col = mix(vec3(0.2, 0.95, 0.2), vec3(1.0, 0.95, 0.0), (t - 0.4) / 0.2);
	} else if (t < 0.8) {
		// 2.1% - 2.8% slope: Bright Yellow -> Vivid Orange
		col = mix(vec3(1.0, 0.95, 0.0), vec3(1.0, 0.5, 0.0), (t - 0.6) / 0.2);
	} else {
		// 2.8% - 3.6%+ slope: Vivid Orange -> Hot Crimson / Red
		col = mix(vec3(1.0, 0.5, 0.0), vec3(1.0, 0.08, 0.15), (t - 0.8) / 0.2);
	}
	
	v_color = vec4(col, fade * 0.95);
}

void fragment() {
	ALBEDO = v_color.rgb;
	ALPHA = v_color.a;
}
"""
	
	var mat_dots = ShaderMaterial.new()
	mat_dots.shader = shader
	dots_mi.material_override = mat_dots
	dots_mi.visible = show_green_grid
	add_child(dots_mi)

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
	color.a = 0.45
	return color

func _toggle_green_grid() -> void:
	show_green_grid = not show_green_grid
	_update_green_grid_visibility()
	_update_grid_button_state()

func _update_green_grid_visibility() -> void:
	var heatmap_node = get_node_or_null("GreenHeatmapMesh")
	var grid_node = get_node_or_null("GreenGridMesh")
	var dots_node = get_node_or_null("GreenDotsMesh")
	
	if heatmap_node:
		heatmap_node.visible = false
	if grid_node:
		grid_node.visible = show_green_grid
	if dots_node:
		dots_node.visible = show_green_grid

func _update_grid_button_state() -> void:
	if grid_toggle_btn:
		if show_green_grid:
			grid_toggle_btn.text = "📊 Grid: ON"
			_apply_btn_style(grid_toggle_btn, Color(0.18, 0.48, 0.28), Color(0.24, 0.60, 0.36))
		else:
			grid_toggle_btn.text = "📊 Grid: OFF"
			_apply_btn_style(grid_toggle_btn, Color(0.25, 0.25, 0.25), Color(0.35, 0.35, 0.35))

# ----------------- PLAYER SETUP -----------------

func _setup_player() -> void:
	player = PlayerScene.instantiate()
	add_child(player)
	var start_pos = Vector3(0.0, get_height(0.0, 0.0) + 0.02, 0.0)
	player.global_position = start_pos
	
	# Disable default process update
	player.set_process(false)
	
	# Connect to ball rest signal to handle scoring
	player.rest.connect(_on_ball_rest)
	
	# Initialize spawn position
	player.ball.spawn_position = start_pos
	player.ball.reset()

# ----------------- TARGET HOLES -----------------

func _setup_holes() -> void:
	holes.clear()
	for i in range(hole_data.size()):
		var data = hole_data[i]
		var dist_m = data["dist_ft"] * 0.3048
		var rad = deg_to_rad(data["angle_deg"])
		var h_x = dist_m * cos(rad)
		var h_z = dist_m * sin(rad)
		var h_y = get_height(h_x, h_z)
		var hole_pos = Vector3(h_x, h_y, h_z)
		holes.append(hole_pos)
		
		# Spawn realistic golf cup (white cup liner/rim with dark interior bottom) matching course play
		var cup_root = Node3D.new()
		cup_root.name = "CupMarker_%d" % i
		cup_root.position = hole_pos
		
		# White cup rim/liner
		var cup_white = MeshInstance3D.new()
		cup_white.name = "CupWhite"
		var white_mesh = CylinderMesh.new()
		white_mesh.top_radius = 0.108
		white_mesh.bottom_radius = 0.108
		white_mesh.height = 0.003
		cup_white.mesh = white_mesh
		
		var white_mat = StandardMaterial3D.new()
		white_mat.albedo_color = Color(0.95, 0.95, 0.95)
		white_mat.roughness = 0.5
		cup_white.material_override = white_mat
		cup_white.position = Vector3(0.0, 0.0015, 0.0)
		cup_root.add_child(cup_white)
		
		# Dark inner hole depth
		var cup_dark = MeshInstance3D.new()
		cup_dark.name = "CupDark"
		var dark_mesh = CylinderMesh.new()
		dark_mesh.top_radius = 0.095
		dark_mesh.bottom_radius = 0.095
		dark_mesh.height = 0.0035
		cup_dark.mesh = dark_mesh
		
		var dark_mat = StandardMaterial3D.new()
		dark_mat.albedo_color = Color(0.1, 0.1, 0.1)
		dark_mat.roughness = 1.0
		cup_dark.material_override = dark_mat
		cup_dark.position = Vector3(0.0, 0.002, 0.0)
		cup_root.add_child(cup_dark)
		
		add_child(cup_root)

func _select_hole(index: int) -> void:
	if index < 0 or index >= holes.size():
		return
	selected_hole_index = index
		
	# Draw/Reposition flagpole
	_spawn_flagpole(holes[index])
	
	# Always reset ball to starting position aiming towards the selected hole
	_reset_ball_position()
	
	_show_banner("Target Hole %d (%d ft) Selected! Hit with Launch Monitor." % [index + 1, hole_data[index]["dist_ft"]])
	
	# Update active button visuals & distances
	_update_hole_button_labels()

func _update_hole_button_labels() -> void:
	for i in range(holes.size()):
		if i < hole_buttons.size():
			var dist_ft = hole_data[i]["dist_ft"]
			if i == selected_hole_index:
				hole_buttons[i].text = "Hole %d (%d ft) ▶" % [i + 1, dist_ft]
				hole_buttons[i].add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
			else:
				hole_buttons[i].text = "Hole %d (%d ft)" % [i + 1, dist_ft]
				hole_buttons[i].remove_theme_color_override("font_color")

func _spawn_flagpole(pos: Vector3) -> void:
	if has_node("FlagPin"):
		get_node("FlagPin").queue_free()
		
	var pin = Node3D.new()
	pin.name = "FlagPin"
	add_child(pin)
	pin.global_position = pos
	
	# Pole
	var pole = MeshInstance3D.new()
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.02
	pole_mesh.bottom_radius = 0.02
	pole_mesh.height = 2.0
	pole.mesh = pole_mesh
	
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color.WHITE
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, 1.0, 0.0)
	pin.add_child(pole)
	
	# Flag
	var flag = MeshInstance3D.new()
	var flag_mesh = PrismMesh.new()
	flag_mesh.size = Vector3(0.4, 0.3, 0.02)
	flag.mesh = flag_mesh
	
	var flag_mat = StandardMaterial3D.new()
	flag_mat.albedo_color = Color(1.0, 0.1, 0.1) # Bright red
	flag_mat.emission_enabled = true
	flag_mat.emission = Color(1.0, 0.1, 0.1)
	flag.material_override = flag_mat
	flag.position = Vector3(0.2, 1.85, 0.0)
	flag.rotation = Vector3(0.0, 0.0, -PI/2)
	pin.add_child(flag)
	
	# Glow/Selection Ring
	var ring = MeshInstance3D.new()
	var ring_mesh = CylinderMesh.new()
	ring_mesh.top_radius = 0.5
	ring_mesh.bottom_radius = 0.5
	ring_mesh.height = 0.001
	ring.mesh = ring_mesh
	
	var ring_mat = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.0, 0.8, 1.0, 0.5) # Translucent cyan
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_mat
	ring.position = Vector3(0.0, 0.0005, 0.0)
	pin.add_child(ring)

# ----------------- BALL TELEPORTATION & DYNAMIC AIMING -----------------

func _reset_ball_position() -> void:
	var start_pos = Vector3(0.0, get_height(0.0, 0.0) + 0.02, 0.0)
	_teleport_ball(start_pos)

func _teleport_ball(pos: Vector3) -> void:
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	pos.y = get_height(pos.x, pos.z) + 0.02
	player.global_position = pos
	player.ball.spawn_position = pos
	player.ball.reset()
	
	last_putt_start_pos = pos
	if selected_hole_index >= 0 and selected_hole_index < holes.size():
		last_putt_target_hole = holes[selected_hole_index]
	
	# Clear tracers
	player.reset_ball()
	
	# Recompute camera and orientation
	_update_aim_and_camera()
	_update_hole_button_labels()

func _update_aim_and_camera() -> void:
	if selected_hole_index < 0 or selected_hole_index >= holes.size():
		return
		
	var target_hole = holes[selected_hole_index]
	var ball_pos = player.ball.global_position
	
	var diff = target_hole - ball_pos
	var angle_rad = atan2(diff.z, diff.x)
	
	# Apply aim yaw offset to player ball
	player.ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
	
	# Position camera behind the ball along the target line (higher elevation & angled down)
	var back_dir = Vector3(-cos(angle_rad), 0.0, -sin(angle_rad)).normalized()
	var cam_pos = ball_pos + back_dir * 3.5 + Vector3.UP * 2.2
	
	$Camera3D.global_position = cam_pos
	$Camera3D.look_at(ball_pos + back_dir * -2.0)
	
	# Store relative camera offset for smooth flight following
	last_camera_offset = cam_pos - ball_pos

# ----------------- INPUT & HIT SIMULATION -----------------

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
				var ray_end = ray_start + ray_dir * 1000.0
				var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
				var hit = get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty():
					var clicked_point = hit["position"]
					var closest_idx = -1
					var min_dist = 9999.0
					for i in range(holes.size()):
						var d = clicked_point.distance_to(holes[i])
						if d < min_dist:
							min_dist = d
							closest_idx = i
							
					# Selection within 4 meters of any hole
					if closest_idx >= 0 and min_dist <= 4.0:
						_select_hole(closest_idx)
						
	# Keyboard R (reset), G (grid), H/Space (test hit)
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			_reset_ball_position()
		elif event.keycode == KEY_G:
			_toggle_green_grid()
		elif event.keycode == KEY_H or event.keycode == KEY_SPACE:
			if player and player.ball and player.ball.state == PhysicsEnums.BallState.REST:
				var target_dist_ft = hole_data[selected_hole_index]["dist_ft"]
				var sim_speed = sqrt(target_dist_ft) * 1.85
				var test_data = {
					"Speed": sim_speed,
					"VLA": 0.0,
					"HLA": 0.0,
					"SpinAxis": 0.0,
					"TotalSpin": 0.0,
					"BackSpin": 0.0,
					"SideSpin": 0.0,
					"ShotType": "putt",
					"club": "Pt"
				}
				_on_launch_monitor_hit_ball(test_data)

func _on_launch_monitor_hit_ball(data: Dictionary) -> void:
	if player == null or player.ball == null:
		return
	if player.ball.state != PhysicsEnums.BallState.REST:
		return # Ignore if putt in progress

	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()

	shot_counter += 1
	last_putt_start_pos = player.ball.global_position
	if selected_hole_index >= 0 and selected_hole_index < holes.size():
		last_putt_target_hole = holes[selected_hole_index]

	# Connect to the player's launch monitor shot handler
	player._on_tcp_client_hit_ball(data)

	# Early Trajectory Prediction for Suspense
	if has_node("/root/TensionManager") and not last_putt_target_hole.is_zero_approx():
		var prediction = TensionManager.predict_shot_outcome(player.ball.global_position, player.ball.velocity, true, last_putt_target_hole)
		if prediction.get("will_enter_zone", false):
			print("[PuttingPractice] Early suspense predicted for putt! Scheduling heartbeat.")
			TensionManager.schedule_early_tension("putt", 0.35)

	# Show the banner
	var speed_mph = data.get("Speed", 0.0)
	_show_banner("Putt Hit (Launch Monitor)! Speed: %.1f mph" % speed_mph)

# ----------------- DYNAMIC CUP-ENTRY & CAMERA FOLLOW -----------------

func _physics_process(delta: float) -> void:
	# Camera Smooth Follow & Tension
	if player and player.ball:
		var ball_state = player.ball.state
		if ball_state == PhysicsEnums.BallState.FLIGHT or ball_state == PhysicsEnums.BallState.ROLLOUT:
			camera_following = true
			var ball_pos = player.ball.global_position
			var target_cam_pos = ball_pos + last_camera_offset

			# Live distance check to hole
			if not last_putt_target_hole.is_zero_approx():
				var dist_to_hole = Vector2(ball_pos.x, ball_pos.z).distance_to(Vector2(last_putt_target_hole.x, last_putt_target_hole.z))
				if dist_to_hole <= 1.524: # 5 feet in meters
					if has_node("/root/TensionManager") and not TensionManager.is_active():
						TensionManager.start_tension("putt")

			# If tension active, tighten camera closer to ball and cup
			if has_node("/root/TensionManager") and TensionManager.is_active() and not last_putt_target_hole.is_zero_approx():
				var diff_to_hole = (last_putt_target_hole - ball_pos)
				diff_to_hole.y = 0.0
				var back_dir = -diff_to_hole.normalized() if not diff_to_hole.is_zero_approx() else Vector3.BACK
				var close_offset = back_dir * 2.2 + Vector3.UP * 1.1
				target_cam_pos = ball_pos + close_offset

			$Camera3D.global_position = $Camera3D.global_position.lerp(target_cam_pos, delta * 8.0)
			$Camera3D.look_at(ball_pos)
		else:
			if camera_following:
				camera_following = false
				if has_node("/root/TensionManager"):
					TensionManager.stop_tension()
				_update_aim_and_camera()
				_update_hole_button_labels()

func _on_ball_rest(_shot_data: Dictionary) -> void:
	if has_node("/root/TensionManager"):
		TensionManager.stop_tension()
	var final_pos = player.ball.global_position
	var target_hole = last_putt_target_hole
	
	var start_dist_feet = last_putt_start_pos.distance_to(target_hole) * 3.28084
	var end_dist_feet = final_pos.distance_to(target_hole) * 3.28084
	var end_dist_meters = final_pos.distance_to(target_hole)
	
	# 1. Attempts
	stats_attempts += 1
	
	# 2. 25+ Foot Putt
	if start_dist_feet >= 24.5:
		stats_attempts_25_plus += 1
		
	# 3. Made into hole
	var made = false
	if end_dist_meters < 0.13:
		made = true
		stats_made += 1
		GlobalSettings.play_golf_clap()
		_show_banner("HOLED OUT! AMAZING PUTT! (%.0f ft)" % start_dist_feet)
	else:
		_show_banner("Ended %.1f ft from cup (Target: %.0f ft)" % [end_dist_feet, start_dist_feet])
		
	# 4. Within 5 feet
	if end_dist_feet <= 5.0 or made:
		stats_within_5 += 1
		
	# 5. Within 10 feet
	if end_dist_feet <= 10.0 or made:
		stats_within_10 += 1
		
	# Update Stats Labels & Button Labels
	_update_hud()
	_update_hole_button_labels()
	
	# Always reset player back to the starting spot after hitting
	var current_shot_id = shot_counter
	await get_tree().create_timer(2.5).timeout
	if is_inside_tree() and player != null and player.ball != null:
		if shot_counter == current_shot_id and player.ball.state == PhysicsEnums.BallState.REST:
			_reset_ball_position()

# ----------------- GUI SETUP -----------------

func _setup_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "HUDLayer"
	hud_layer.layer = 1
	add_child(hud_layer)
	
	# Main HUD Control Node
	hud_control = Control.new()
	hud_control.name = "Control"
	hud_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_control.anchor_right = 1.0
	hud_control.anchor_bottom = 1.0
	hud_control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_control.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud_control)
	
	# --- TOP SCOREBOARD PANEL ---
	var score_panel = PanelContainer.new()
	score_panel.custom_minimum_size = Vector2(800, 90)
	score_panel.anchor_left = 0.5
	score_panel.anchor_right = 0.5
	score_panel.anchor_top = 0.0
	score_panel.anchor_bottom = 0.0
	score_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	score_panel.offset_left = -400
	score_panel.offset_right = 400
	score_panel.offset_top = 20
	score_panel.offset_bottom = 110
	hud_control.add_child(score_panel)
	
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
	score_panel.add_theme_stylebox_override("panel", glass_style)
	
	var score_margin = MarginContainer.new()
	score_margin.add_theme_constant_override("margin_left", 20)
	score_margin.add_theme_constant_override("margin_right", 20)
	score_panel.add_child(score_margin)
	
	var score_hbox = HBoxContainer.new()
	score_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	score_margin.add_child(score_hbox)
	
	attempts_val_lbl = _create_stat_column(score_hbox, "ATTEMPTS")
	dist_25_val_lbl = _create_stat_column(score_hbox, "25+ FT PUTTS")
	within_10_val_lbl = _create_stat_column(score_hbox, "WITHIN 10 FT")
	within_5_val_lbl = _create_stat_column(score_hbox, "WITHIN 5 FT")
	made_val_lbl = _create_stat_column(score_hbox, "MADE PUTTS")
	
	# --- LEFT FLOATING TARGET SELECTION PANEL ---
	var target_panel = PanelContainer.new()
	target_panel.custom_minimum_size = Vector2(210, 390)
	target_panel.anchor_left = 0.0
	target_panel.anchor_top = 0.5
	target_panel.anchor_bottom = 0.5
	target_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	target_panel.offset_left = 20
	target_panel.offset_top = -195
	target_panel.offset_bottom = 195
	hud_control.add_child(target_panel)
	target_panel.add_theme_stylebox_override("panel", glass_style)
	
	var target_margin = MarginContainer.new()
	target_margin.add_theme_constant_override("margin_left", 12)
	target_margin.add_theme_constant_override("margin_right", 12)
	target_margin.add_theme_constant_override("margin_top", 12)
	target_margin.add_theme_constant_override("margin_bottom", 12)
	target_panel.add_child(target_margin)
	
	var target_vbox = VBoxContainer.new()
	target_vbox.add_theme_constant_override("separation", 6)
	target_margin.add_child(target_vbox)
	
	var t_title = Label.new()
	t_title.text = "SELECT HOLE"
	t_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t_title.add_theme_font_size_override("font_size", 13)
	t_title.add_theme_color_override("font_color", Color(0.0, 0.8, 1.0))
	target_vbox.add_child(t_title)
	
	# Create 8 hole buttons
	hole_buttons.clear()
	for i in range(holes.size()):
		var btn = Button.new()
		btn.text = "Hole %d (%d ft)" % [i + 1, hole_data[i]["dist_ft"]]
		btn.custom_minimum_size = Vector2(0, 32)
		btn.add_theme_font_size_override("font_size", 12)
		_apply_btn_style(btn, Color(0.12, 0.20, 0.28), Color(0.18, 0.30, 0.42))
		btn.pressed.connect(func(idx=i): _select_hole(idx))
		target_vbox.add_child(btn)
		hole_buttons.append(btn)
		
	# --- BANNER TEXT (Center-ish screen) ---
	banner_lbl = Label.new()
	banner_lbl.text = "Select a target hole (5-50 ft) | Hit putt on Launch Monitor | R: Reset | G: Grid"
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.anchor_left = 0.5
	banner_lbl.anchor_right = 0.5
	banner_lbl.anchor_top = 0.25
	banner_lbl.anchor_bottom = 0.25
	banner_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_lbl.add_theme_font_size_override("font_size", 20)
	banner_lbl.add_theme_color_override("font_color", Color(1, 1, 0.5, 1.0))
	banner_lbl.add_theme_constant_override("outline_size", 3)
	banner_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hud_control.add_child(banner_lbl)
	
	# --- BOTTOM CONTROLS PANEL ---
	var ctrl_panel = PanelContainer.new()
	ctrl_panel.custom_minimum_size = Vector2(460, 70)
	ctrl_panel.anchor_left = 0.5
	ctrl_panel.anchor_right = 0.5
	ctrl_panel.anchor_top = 1.0
	ctrl_panel.anchor_bottom = 1.0
	ctrl_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ctrl_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ctrl_panel.offset_left = -230
	ctrl_panel.offset_right = 230
	ctrl_panel.offset_top = -90
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
	
	# 1. Slope Grid Toggle Button
	grid_toggle_btn = Button.new()
	grid_toggle_btn.name = "GridToggleButton"
	grid_toggle_btn.text = "📊 Grid: OFF"
	grid_toggle_btn.custom_minimum_size = Vector2(110, 44)
	_apply_btn_style(grid_toggle_btn, Color(0.25, 0.25, 0.25), Color(0.35, 0.35, 0.35))
	grid_toggle_btn.pressed.connect(_toggle_green_grid)
	ctrl_hbox.add_child(grid_toggle_btn)
	
	# 2. Reset Button
	var reset_btn = Button.new()
	reset_btn.text = "RESET (R)"
	reset_btn.custom_minimum_size = Vector2(100, 44)
	_apply_btn_style(reset_btn, Color(0.48, 0.28, 0.18), Color(0.32, 0.18, 0.12))
	reset_btn.pressed.connect(_reset_ball_position)
	ctrl_hbox.add_child(reset_btn)

	# 3. Music Toggle Button
	music_toggle_btn = Button.new()
	music_toggle_btn.name = "MusicToggleButton"
	music_toggle_btn.text = ""
	music_toggle_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	music_toggle_btn.expand_icon = true
	music_toggle_btn.custom_minimum_size = Vector2(44, 44)
	music_toggle_btn.pressed.connect(_toggle_music)
	ctrl_hbox.add_child(music_toggle_btn)
	
	# 4. Settings Button
	var settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.icon = load("res://Utils/Settings/Gear.png")
	settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.custom_minimum_size = Vector2(44, 44)
	_apply_btn_style(settings_btn, Color(0.18, 0.34, 0.50), Color(0.24, 0.44, 0.65))
	settings_btn.pressed.connect(_on_settings_pressed)
	ctrl_hbox.add_child(settings_btn)

	# 5. Exit Button
	var exit_btn = Button.new()
	exit_btn.text = "EXIT"
	exit_btn.custom_minimum_size = Vector2(80, 44)
	_apply_btn_style(exit_btn, Color(0.36, 0.16, 0.16), Color(0.24, 0.12, 0.12))
	exit_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
	ctrl_hbox.add_child(exit_btn)
	
	# Update initial states
	_update_hud()
	_update_grid_button_state()
	_update_music_button_state()
	GlobalSettings.range_settings.minigame_music_enabled.setting_changed.connect(func(_val): _update_music_button_state())

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

func _create_stat_column(parent: HBoxContainer, title: String) -> Label:
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
	val_lbl.text = "0"
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 28)
	val_lbl.add_theme_color_override("font_color", Color.WHITE)
	val_lbl.add_theme_constant_override("outline_size", 2)
	val_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	col.add_child(val_lbl)
	
	return val_lbl

func _update_hud() -> void:
	if attempts_val_lbl:
		attempts_val_lbl.text = str(stats_attempts)
	if dist_25_val_lbl:
		dist_25_val_lbl.text = str(stats_attempts_25_plus)
	if within_10_val_lbl:
		within_10_val_lbl.text = str(stats_within_10)
	if within_5_val_lbl:
		within_5_val_lbl.text = str(stats_within_5)
	if made_val_lbl:
		made_val_lbl.text = str(stats_made)

func _show_banner(text: String) -> void:
	if banner_lbl:
		banner_lbl.text = text

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

func _on_settings_pressed() -> void:
	if _settings_layer != null and is_instance_valid(_settings_layer):
		return

	var settings_scene = load("res://UI/Settings/RangeSettings/range_settings.tscn")
	if settings_scene == null:
		return

	# Hide gameplay HUD visuals (score tracker, target hole buttons, banner, controls)
	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.visible = false

	_settings_layer = CanvasLayer.new()
	_settings_layer.name = "SettingsLayer"
	_settings_layer.layer = 105
	add_child(_settings_layer)

	# Full-screen dimmed backdrop that blocks clicks from leaking through
	var backdrop = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.02, 0.04, 0.07, 0.75)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_layer.add_child(backdrop)

	var margin_container = MarginContainer.new()
	margin_container.name = "MarginContainer"
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.anchor_right = 1.0
	margin_container.anchor_bottom = 1.0
	margin_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin_container.grow_vertical = Control.GROW_DIRECTION_BOTH
	margin_container.add_theme_constant_override("margin_left", 36)
	margin_container.add_theme_constant_override("margin_right", 36)
	margin_container.add_theme_constant_override("margin_top", 24)
	margin_container.add_theme_constant_override("margin_bottom", 24)
	margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	# Restore gameplay HUD visuals
	if hud_layer != null and is_instance_valid(hud_layer):
		hud_layer.visible = true
