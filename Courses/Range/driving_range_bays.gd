# ==============================================================================
# HeckleGolfSim - Natural Outdoor Driving Range Hitting Bay System
# Procedural natural outdoor driving range setup featuring:
# - 3 visible hitting lanes directly on the natural grass (center + left + right)
# - Low-profile commercial turf hitting mats resting directly on the turf
# - Sleek aerodynamic bay dividers with burnt-orange livery and charcoal trim
# - Classic wire range ball baskets overflowing with 3D white golf balls
# - Molded rubber ball trays beside each mat with neat rows of golf balls
# - Modern tubular club stands behind each lane
# - Completely open natural outdoor setting (no concrete tiles, no poles, no roof)
# ==============================================================================
class_name DrivingRangeBays
extends Node3D

# Configuration Constants: 3 hitting lanes (left, center/player, right)
const NUM_BAYS: int = 3
const BAY_SPACING: float = 3.4 # Meters between lane centers (~11.2 feet)
const CENTER_BAY_INDEX: int = 1 # Index 1 is center bay (z = 0.0)

# Colors matching HeckleGolfSim & reference photo
const COLOR_TURF := Color(0.26, 0.64, 0.22)
const COLOR_RUBBER_BASE := Color(0.12, 0.12, 0.13)
const COLOR_RUBBER_TRAY := Color(0.10, 0.10, 0.11)
const COLOR_TEE_RUBBER := Color(0.92, 0.78, 0.20)
const COLOR_DIVIDER_ORANGE := Color(0.90, 0.42, 0.14)
const COLOR_DIVIDER_TRIM := Color(0.13, 0.14, 0.16)
const COLOR_BASKET_GREEN := Color(0.15, 0.48, 0.22)
const COLOR_BASKET_HANDLE := Color(0.80, 0.80, 0.82)
const COLOR_GOLF_BALL := Color(0.98, 0.98, 0.99)
const COLOR_STEEL_STRUCTURE := Color(0.15, 0.16, 0.18)


static func create_bay_setup() -> Node3D:
	var root := Node3D.new()
	root.name = "DrivingRangeBaySetup"
	
	# 1. Hitting bays directly on the grass (3 lanes: left, center, right)
	var bays_container := Node3D.new()
	bays_container.name = "HittingBays"
	root.add_child(bays_container)
	
	# Bay numbers matching reference photo style: Bay 44 (left), Bay 45 (center/player), Bay 46 (right)
	var bay_numbers := [44, 45, 46]
	
	for i in range(NUM_BAYS):
		var bay_idx_rel = i - CENTER_BAY_INDEX # -1 (left), 0 (center), +1 (right)
		var bay_z = bay_idx_rel * BAY_SPACING
		var is_player_bay = (bay_idx_rel == 0)
		var bay_num = bay_numbers[i]
		
		var bay_node := _build_single_bay(bay_z, is_player_bay, bay_num)
		bay_node.name = "Bay_%d" % bay_num
		bays_container.add_child(bay_node)
	
	# 2. Bay divider partitions (4 dividers enclosing the 3 lanes)
	var dividers_container := Node3D.new()
	dividers_container.name = "Dividers"
	root.add_child(dividers_container)
	
	for d in range(NUM_BAYS + 1):
		# Dividers sit midway between bay centers
		var div_z = (d - CENTER_BAY_INDEX - 0.5) * BAY_SPACING
		var divider_node := _build_divider(div_z)
		divider_node.name = "Divider_%d" % d
		dividers_container.add_child(divider_node)
	
	return root


# ==============================================================================
# Individual Hitting Lane Setup (Directly on Grass)
# ==============================================================================
static func _build_single_bay(bay_z: float, is_player_bay: bool, bay_num: int) -> Node3D:
	var bay := Node3D.new()
	bay.position = Vector3(0.0, 0.0, bay_z)
	
	# A. Turf Hitting Mat resting directly on the grass
	var mat_node := _build_hitting_mat(is_player_bay)
	bay.add_child(mat_node)
	
	# B. Rubber Ball Tray on the grass beside the mat
	var tray_node := _build_ball_tray()
	tray_node.position = Vector3(0.05, 0.0, 0.88)
	bay.add_child(tray_node)
	
	# C. Wire Driving Range Basket full of golf balls (prominent beside the lane)
	var basket_node := _build_range_basket()
	basket_node.position = Vector3(-0.35, 0.0, 1.25)
	bay.add_child(basket_node)
	
	# D. Bag Stand / Club Rest behind the lane
	var stand_node := _build_bag_stand()
	stand_node.position = Vector3(-1.8, 0.0, -1.15)
	bay.add_child(stand_node)
	
	# If this is an adjacent lane (not the player's active lane), place an idle ball on the mat
	if not is_player_bay:
		var idle_ball := _create_golf_ball_mesh()
		idle_ball.name = "IdleBall"
		idle_ball.position = Vector3(0.0, 0.024 + 0.021335, 0.0)
		bay.add_child(idle_ball)
	
	return bay


# ==============================================================================
# Hitting Mat (Low-Profile Beveled Foundation + Dense Synthetic Turf Insert)
# ==============================================================================
static func _build_hitting_mat(is_player_bay: bool) -> Node3D:
	var node := Node3D.new()
	node.name = "HittingMat"
	
	var mat_len := 1.70  # Along X (-1.25 to +0.45, ball sits at x = 0.0)
	var mat_wid := 1.40  # Along Z (-0.70 to +0.70, ball sits at z = 0.0)
	var mat_center_x := -0.40
	
	# Heavy-duty charcoal rubber foundation tray resting directly on grass
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(mat_len, 0.018, mat_wid)
	
	var base_inst := MeshInstance3D.new()
	base_inst.name = "RubberBase"
	base_inst.mesh = base_mesh
	base_inst.position = Vector3(mat_center_x, 0.009, 0.0)
	
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = COLOR_RUBBER_BASE
	base_mat.roughness = 0.85
	base_inst.material_override = base_mat
	node.add_child(base_inst)
	
	# Vibrant synthetic turf insert
	var turf_mesh := BoxMesh.new()
	turf_mesh.size = Vector3(mat_len - 0.06, 0.008, mat_wid - 0.06)
	
	var turf_inst := MeshInstance3D.new()
	turf_inst.name = "TurfInsert"
	turf_inst.mesh = turf_mesh
	turf_inst.position = Vector3(mat_center_x, 0.020, 0.0)
	
	var turf_mat := StandardMaterial3D.new()
	turf_mat.albedo_color = COLOR_TURF
	turf_mat.roughness = 0.85
	turf_mat.metallic_specular = 0.15
	if ResourceLoader.exists("res://Courses/Environments/grass-fairway/normal.png"):
		turf_mat.normal_enabled = true
		turf_mat.normal_texture = load("res://Courses/Environments/grass-fairway/normal.png")
		turf_mat.normal_scale = 0.8
		turf_mat.uv1_scale = Vector3(6.0, 6.0, 6.0)
	turf_inst.material_override = turf_mat
	node.add_child(turf_inst)
	
	# Rubber tee grommet at x = 0, z = 0 (where the ball is addressed)
	var tee_grommet := MeshInstance3D.new()
	tee_grommet.name = "TeeGrommet"
	var grommet_cyl := CylinderMesh.new()
	grommet_cyl.top_radius = 0.018
	grommet_cyl.bottom_radius = 0.022
	grommet_cyl.height = 0.008
	tee_grommet.mesh = grommet_cyl
	tee_grommet.position = Vector3(0.0, 0.022, 0.0)
	
	var grommet_mat := StandardMaterial3D.new()
	grommet_mat.albedo_color = COLOR_TEE_RUBBER
	grommet_mat.roughness = 0.60
	tee_grommet.material_override = grommet_mat
	node.add_child(tee_grommet)
	
	# Solid collision body for authentic surface interaction
	var static_body := StaticBody3D.new()
	static_body.name = "TeeMatCollider"
	static_body.set_meta("surface_type", 0) # PhysicsEnums.SurfaceType.FAIRWAY
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(mat_len, 0.020, mat_wid)
	col_shape.shape = box_shape
	col_shape.position = Vector3(mat_center_x, 0.010, 0.0)
	static_body.add_child(col_shape)
	node.add_child(static_body)
	
	return node


# ==============================================================================
# Rubber Range Ball Tray (Beside the Mat on Grass)
# ==============================================================================
static func _build_ball_tray() -> Node3D:
	var node := Node3D.new()
	node.name = "BallTray"
	
	var tray_len := 0.60
	var tray_wid := 0.35
	var tray_h := 0.042
	
	# Molded tray base
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(tray_len, tray_h, tray_wid)
	var base_inst := MeshInstance3D.new()
	base_inst.name = "TrayBody"
	base_inst.mesh = base_mesh
	base_inst.position = Vector3(0.0, tray_h * 0.5, 0.0)
	
	var tray_mat := StandardMaterial3D.new()
	tray_mat.albedo_color = COLOR_RUBBER_TRAY
	tray_mat.roughness = 0.82
	base_inst.material_override = tray_mat
	node.add_child(base_inst)
	
	# Inner recessed tray channel
	var inner_mesh := BoxMesh.new()
	inner_mesh.size = Vector3(tray_len - 0.05, 0.020, tray_wid - 0.05)
	var inner_inst := MeshInstance3D.new()
	inner_inst.name = "TrayHollow"
	inner_inst.mesh = inner_mesh
	inner_inst.position = Vector3(0.0, tray_h * 0.5 + 0.012, 0.0)
	var inner_mat := StandardMaterial3D.new()
	inner_mat.albedo_color = COLOR_RUBBER_TRAY.darkened(0.2)
	inner_mat.roughness = 0.90
	inner_inst.material_override = inner_mat
	node.add_child(inner_inst)
	
	# Exit ramp lip opening toward the mat (-Z)
	var ramp_mesh := BoxMesh.new()
	ramp_mesh.size = Vector3(0.18, 0.014, 0.06)
	var ramp_inst := MeshInstance3D.new()
	ramp_inst.name = "ExitChute"
	ramp_inst.mesh = ramp_mesh
	ramp_inst.position = Vector3(0.0, 0.010, -tray_wid * 0.5 - 0.02)
	ramp_inst.material_override = tray_mat
	node.add_child(ramp_inst)
	
	# Rows of white golf balls in the tray (3 rows of 5 balls = 15 balls)
	var ball_mat := _get_golf_ball_material()
	var ball_radius := 0.024
	var ball_sphere := SphereMesh.new()
	ball_sphere.radius = ball_radius
	ball_sphere.height = ball_radius * 2.0
	ball_sphere.radial_segments = 12
	ball_sphere.rings = 6
	
	var start_x := -0.22
	var step_x := 0.11
	var start_z := -0.10
	var step_z := 0.10
	
	var balls_container := Node3D.new()
	balls_container.name = "TrayBalls"
	node.add_child(balls_container)
	
	for rz in range(3):
		for rx in range(5):
			var b := MeshInstance3D.new()
			b.mesh = ball_sphere
			b.material_override = ball_mat
			b.position = Vector3(start_x + rx * step_x, tray_h + ball_radius * 0.5, start_z + rz * step_z)
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			balls_container.add_child(b)
			
	return node


# ==============================================================================
# Wire Driving Range Basket Full of Golf Balls
# ==============================================================================
static func _build_range_basket() -> Node3D:
	var node := Node3D.new()
	node.name = "RangeBallBasket"
	
	var top_r := 0.165
	var bot_r := 0.120
	var basket_h := 0.28
	
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = COLOR_BASKET_GREEN
	wire_mat.metallic = 0.35
	wire_mat.roughness = 0.30
	wire_mat.metallic_specular = 0.60
	
	# Top rim hoop
	var top_rim := MeshInstance3D.new()
	top_rim.name = "TopRim"
	var top_torus := TorusMesh.new()
	top_torus.inner_radius = top_r - 0.012
	top_torus.outer_radius = top_r + 0.012
	top_torus.rings = 18
	top_torus.ring_segments = 6
	top_rim.mesh = top_torus
	top_rim.position = Vector3(0.0, basket_h, 0.0)
	top_rim.material_override = wire_mat
	node.add_child(top_rim)
	
	# Bottom base hoop
	var bot_rim := MeshInstance3D.new()
	bot_rim.name = "BottomRim"
	var bot_torus := TorusMesh.new()
	bot_torus.inner_radius = bot_r - 0.010
	bot_torus.outer_radius = bot_r + 0.010
	bot_torus.rings = 18
	bot_torus.ring_segments = 6
	bot_rim.mesh = bot_torus
	bot_rim.position = Vector3(0.0, 0.012, 0.0)
	bot_rim.material_override = wire_mat
	node.add_child(bot_rim)
	
	# Mid reinforcement hoop
	var mid_rim := MeshInstance3D.new()
	mid_rim.name = "MidRim"
	var mid_r = (top_r + bot_r) * 0.5
	var mid_torus := TorusMesh.new()
	mid_torus.inner_radius = mid_r - 0.008
	mid_torus.outer_radius = mid_r + 0.008
	mid_torus.rings = 18
	mid_torus.ring_segments = 6
	mid_rim.mesh = mid_torus
	mid_rim.position = Vector3(0.0, basket_h * 0.52, 0.0)
	mid_rim.material_override = wire_mat
	node.add_child(mid_rim)
	
	# Wire struts (16 vertical cage ribs)
	var num_ribs := 16
	var rib_mesh := CylinderMesh.new()
	rib_mesh.top_radius = 0.0035
	rib_mesh.bottom_radius = 0.0035
	rib_mesh.height = basket_h
	rib_mesh.radial_segments = 4
	
	for i in range(num_ribs):
		var angle = (float(i) / float(num_ribs)) * TAU
		var x_bot = cos(angle) * bot_r
		var z_bot = sin(angle) * bot_r
		var x_top = cos(angle) * top_r
		var z_top = sin(angle) * top_r
		
		var rib := MeshInstance3D.new()
		rib.mesh = rib_mesh
		rib.position = Vector3((x_bot + x_top) * 0.5, basket_h * 0.5, (z_bot + z_top) * 0.5)
		var outward_angle = atan2(top_r - bot_r, basket_h)
		rib.rotation = Vector3(sin(angle) * outward_angle, 0.0, -cos(angle) * outward_angle)
		rib.material_override = wire_mat
		rib.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(rib)
	
	# Wire carry handle arched over the top rim
	var handle := MeshInstance3D.new()
	handle.name = "Handle"
	var handle_torus := TorusMesh.new()
	handle_torus.inner_radius = top_r - 0.008
	handle_torus.outer_radius = top_r + 0.008
	handle_torus.rings = 18
	handle_torus.ring_segments = 4
	handle.mesh = handle_torus
	handle.rotation_degrees = Vector3(60.0, 0.0, 0.0)
	handle.position = Vector3(0.0, basket_h + 0.07, -0.05)
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = COLOR_BASKET_HANDLE
	handle_mat.metallic = 0.85
	handle_mat.roughness = 0.20
	handle.material_override = handle_mat
	node.add_child(handle)
	
	# Realistic heap of 3D Golf Balls filling the basket
	var balls_node := Node3D.new()
	balls_node.name = "BasketBalls"
	node.add_child(balls_node)
	
	var ball_mat := _get_golf_ball_material()
	var b_rad := 0.024
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = b_rad
	ball_mesh.height = b_rad * 2.0
	ball_mesh.radial_segments = 10
	ball_mesh.rings = 6
	
	# Tier 1 (bottom layer - 7 balls)
	var r1 := 0.075
	var y1 := b_rad + 0.02
	for i in range(6):
		var ang = (float(i) / 6.0) * TAU
		_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(cos(ang) * r1, y1, sin(ang) * r1))
	_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(0.0, y1, 0.0))
	
	# Tier 2 (middle layer - 8 balls)
	var r2 := 0.095
	var y2 := y1 + b_rad * 1.6
	for i in range(7):
		var ang = (float(i) / 7.0) * TAU + 0.3
		_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(cos(ang) * r2, y2, sin(ang) * r2))
	_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(0.0, y2, 0.0))
	
	# Tier 3 (upper rim layer - 9 balls)
	var r3 := 0.115
	var y3 := y2 + b_rad * 1.6
	for i in range(8):
		var ang = (float(i) / 8.0) * TAU + 0.15
		_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(cos(ang) * r3, y3, sin(ang) * r3))
	_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(0.0, y3, 0.0))
	
	# Top mound (pyramid mound spilling above the rim - 6 balls)
	var r4 := 0.065
	var y4 := y3 + b_rad * 1.55
	for i in range(5):
		var ang = (float(i) / 5.0) * TAU + 0.5
		_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(cos(ang) * r4, y4, sin(ang) * r4))
	_add_ball_to_basket(balls_node, ball_mesh, ball_mat, Vector3(0.005, y4 + b_rad * 1.4, -0.005))
	
	return node


static func _add_ball_to_basket(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var b := MeshInstance3D.new()
	b.mesh = mesh
	b.material_override = mat
	b.position = pos
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(b)


# ==============================================================================
# Sleek Aerodynamic Bay Divider (Matching Reference Photo)
# ==============================================================================
static func _build_divider(div_z: float) -> Node3D:
	var node := Node3D.new()
	node.position = Vector3(0.0, 0.0, div_z)
	
	var div_thickness := 0.20 # 20 cm sleek molded divider width
	var half_w := div_thickness * 0.5
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var x_back := -1.60
	var x_crest := -0.60
	var x_front := 0.90
	var y_high := 1.05
	var y_low := 0.38
	var y_base := 0.04
	
	# Left Side (+Z relative to divider center)
	_add_quad(st, 
		Vector3(x_back, y_base, half_w), Vector3(x_crest, y_base, half_w),
		Vector3(x_back, y_high, half_w), Vector3(x_crest, y_high, half_w),
		Vector3.BACK)
	
	_add_quad(st,
		Vector3(x_crest, y_base, half_w), Vector3(x_front, y_base, half_w),
		Vector3(x_crest, y_high, half_w), Vector3(x_front, y_low, half_w),
		Vector3.BACK)
	
	# Right Side (-Z relative to divider center)
	_add_quad(st,
		Vector3(x_crest, y_base, -half_w), Vector3(x_back, y_base, -half_w),
		Vector3(x_crest, y_high, -half_w), Vector3(x_back, y_high, -half_w),
		Vector3.FORWARD)
	
	_add_quad(st,
		Vector3(x_front, y_base, -half_w), Vector3(x_crest, y_base, -half_w),
		Vector3(x_front, y_low, -half_w), Vector3(x_crest, y_high, -half_w),
		Vector3.FORWARD)
	
	# Back End Wall (facing -X)
	_add_quad(st,
		Vector3(x_back, y_base, -half_w), Vector3(x_back, y_base, half_w),
		Vector3(x_back, y_high, -half_w), Vector3(x_back, y_high, half_w),
		Vector3.LEFT)
	
	# Front End Wall (facing +X)
	_add_quad(st,
		Vector3(x_front, y_base, half_w), Vector3(x_front, y_base, -half_w),
		Vector3(x_front, y_low, half_w), Vector3(x_front, y_low, -half_w),
		Vector3.RIGHT)
	
	# Top Ridge (Back flat crest)
	_add_quad(st,
		Vector3(x_back, y_high, half_w), Vector3(x_crest, y_high, half_w),
		Vector3(x_back, y_high, -half_w), Vector3(x_crest, y_high, -half_w),
		Vector3.UP)
	
	# Top Ridge (Front sloped ramp)
	var slope_normal := Vector3(y_high - y_low, x_front - x_crest, 0.0).normalized()
	_add_quad(st,
		Vector3(x_crest, y_high, half_w), Vector3(x_front, y_low, half_w),
		Vector3(x_crest, y_high, -half_w), Vector3(x_front, y_low, -half_w),
		slope_normal)
	
	st.generate_normals()
	st.generate_tangents()
	
	var div_body_mesh := st.commit()
	var div_body_inst := MeshInstance3D.new()
	div_body_inst.name = "DividerBody"
	div_body_inst.mesh = div_body_mesh
	
	var orange_mat := StandardMaterial3D.new()
	orange_mat.albedo_color = COLOR_DIVIDER_ORANGE
	orange_mat.metallic = 0.20
	orange_mat.roughness = 0.32
	orange_mat.metallic_specular = 0.70
	div_body_inst.material_override = orange_mat
	node.add_child(div_body_inst)
	
	# Dark Charcoal Base Mounting Runner resting on grass
	var base_rail_mesh := BoxMesh.new()
	base_rail_mesh.size = Vector3(2.55, 0.055, div_thickness + 0.08)
	var base_rail_inst := MeshInstance3D.new()
	base_rail_inst.name = "BaseMount"
	base_rail_inst.mesh = base_rail_mesh
	base_rail_inst.position = Vector3((x_back + x_front) * 0.5, 0.027, 0.0)
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = COLOR_DIVIDER_TRIM
	trim_mat.roughness = 0.85
	base_rail_inst.material_override = trim_mat
	node.add_child(base_rail_inst)
	
	# Top bumper cap rail running along the crest and slope
	var cap_mat := StandardMaterial3D.new()
	cap_mat.albedo_color = COLOR_DIVIDER_TRIM
	cap_mat.roughness = 0.80
	
	# Back cap
	var back_cap_mesh := BoxMesh.new()
	back_cap_mesh.size = Vector3(x_crest - x_back, 0.04, div_thickness + 0.04)
	var back_cap := MeshInstance3D.new()
	back_cap.mesh = back_cap_mesh
	back_cap.position = Vector3((x_back + x_crest) * 0.5, y_high + 0.02, 0.0)
	back_cap.material_override = cap_mat
	node.add_child(back_cap)
	
	# Sloped cap
	var slope_len := Vector2(x_front - x_crest, y_high - y_low).length()
	var slope_angle := atan2(y_high - y_low, x_front - x_crest)
	var sloped_cap_mesh := BoxMesh.new()
	sloped_cap_mesh.size = Vector3(slope_len, 0.04, div_thickness + 0.04)
	var sloped_cap := MeshInstance3D.new()
	sloped_cap.mesh = sloped_cap_mesh
	sloped_cap.position = Vector3((x_crest + x_front) * 0.5, (y_high + y_low) * 0.5 + 0.02, 0.0)
	sloped_cap.rotation_degrees = Vector3(0.0, 0.0, -rad_to_deg(slope_angle))
	sloped_cap.material_override = cap_mat
	node.add_child(sloped_cap)
	
	# Horizontal aerodynamic accent channel on both flanks
	var groove_mat := StandardMaterial3D.new()
	groove_mat.albedo_color = COLOR_DIVIDER_TRIM
	groove_mat.roughness = 0.80
	
	var groove_mesh := BoxMesh.new()
	groove_mesh.size = Vector3(2.40, 0.025, div_thickness + 0.006)
	var groove_inst := MeshInstance3D.new()
	groove_inst.name = "SideGroove"
	groove_inst.mesh = groove_mesh
	groove_inst.position = Vector3((x_back + x_front) * 0.5, 0.30, 0.0)
	groove_inst.material_override = groove_mat
	node.add_child(groove_inst)
	
	# Divider Collision Body (for authentic ricochet/bounce if shanked)
	var div_body := StaticBody3D.new()
	div_body.name = "DividerCollider"
	var div_shape := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = Vector3(2.50, 1.10, div_thickness)
	div_shape.shape = box_col
	div_shape.position = Vector3((x_back + x_front) * 0.5, 0.55, 0.0)
	div_body.add_child(div_shape)
	node.add_child(div_body)
	
	return node


static func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, normal: Vector3) -> void:
	st.set_normal(normal)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(p0)
	st.set_normal(normal)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(p1)
	st.set_normal(normal)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(p2)
	
	st.set_normal(normal)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(p1)
	st.set_normal(normal)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(p3)
	st.set_normal(normal)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(p2)


# ==============================================================================
# Golf Bag Stand / Club Rest
# ==============================================================================
static func _build_bag_stand() -> Node3D:
	var node := Node3D.new()
	node.name = "BagStand"
	
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = COLOR_STEEL_STRUCTURE
	steel_mat.metallic = 0.80
	steel_mat.roughness = 0.30
	
	# Two angled legs
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.018
	leg_mesh.bottom_radius = 0.018
	leg_mesh.height = 0.80
	leg_mesh.radial_segments = 6
	
	var leg1 := MeshInstance3D.new()
	leg1.mesh = leg_mesh
	leg1.position = Vector3(0.0, 0.38, -0.16)
	leg1.rotation_degrees = Vector3(15.0, 0.0, 0.0)
	leg1.material_override = steel_mat
	node.add_child(leg1)
	
	var leg2 := MeshInstance3D.new()
	leg2.mesh = leg_mesh
	leg2.position = Vector3(0.0, 0.38, 0.16)
	leg2.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
	leg2.material_override = steel_mat
	node.add_child(leg2)
	
	# Top cradle bar
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.08, 0.035, 0.42)
	var bar_inst := MeshInstance3D.new()
	bar_inst.mesh = bar_mesh
	bar_inst.position = Vector3(0.0, 0.76, 0.0)
	bar_inst.material_override = steel_mat
	node.add_child(bar_inst)
	
	# Rubberized cradle hooks
	var hook_mat := StandardMaterial3D.new()
	hook_mat.albedo_color = COLOR_RUBBER_BASE
	hook_mat.roughness = 0.85
	
	for hz in [-0.14, 0.14]:
		var hook := MeshInstance3D.new()
		var h_mesh := BoxMesh.new()
		h_mesh.size = Vector3(0.10, 0.07, 0.03)
		hook.mesh = h_mesh
		hook.position = Vector3(0.035, 0.79, hz)
		hook.material_override = hook_mat
		node.add_child(hook)
		
	return node


# ==============================================================================
# Helper Methods
# ==============================================================================
static func _get_golf_ball_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR_GOLF_BALL
	mat.metallic = 0.04
	mat.roughness = 0.16
	mat.metallic_specular = 0.85
	return mat


static func _create_golf_ball_mesh() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var b_rad := 0.021335
	var sphere := SphereMesh.new()
	sphere.radius = b_rad
	sphere.height = b_rad * 2.0
	sphere.radial_segments = 14
	sphere.rings = 8
	inst.mesh = sphere
	inst.material_override = _get_golf_ball_material()
	return inst
