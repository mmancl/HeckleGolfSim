# ==============================================================================
# HeckleGolfSim - Teebox Marker & Divot Caddy Builder
# Procedurally generates:
# - Circular spherical tee markers with the color(s) of the tees at each teebox,
#   giving players clear visual feedback that they are hitting from where they wanted
#   (matching the spherical tee markers in the reference photo).
# - A green golf course divot sand caddy / bucket with rounded contours, arched base,
#   and a sculpted domed lid (matching the Par Aide divot caddy in the reference photo),
#   placed on the right side of the right colored tee marker.
# - Quality-adaptive materials: muted, grounded tones on Low graphics to prevent
#   excessive vibrancy, while preserving glossy vibrant finishes on Medium and High.
# ==============================================================================
class_name TeeboxMarkerBuilder
extends RefCounted

# Standard vibrant tee color definitions (used on Medium & High graphics)
const TEE_COLOR_MAP_VIBRANT: Dictionary = {
	"black": Color(0.12, 0.12, 0.14),
	"blue": Color(0.14, 0.44, 0.90),
	"white": Color(0.95, 0.95, 0.96),
	"red": Color(0.88, 0.16, 0.16),
	"gold": Color(0.92, 0.75, 0.14),
	"yellow": Color(0.95, 0.82, 0.15),
	"orange": Color(0.98, 0.52, 0.10),
	"green": Color(0.18, 0.68, 0.25),
	"silver": Color(0.75, 0.76, 0.78),
	"grey": Color(0.75, 0.76, 0.78),
	"gray": Color(0.75, 0.76, 0.78),
	"purple": Color(0.60, 0.22, 0.80)
}

# Muted, grounded tee color definitions (used on Low graphics to avoid oversaturation)
const TEE_COLOR_MAP_MUTED: Dictionary = {
	"black": Color(0.16, 0.16, 0.17),
	"blue": Color(0.18, 0.35, 0.62),
	"white": Color(0.82, 0.82, 0.83),
	"red": Color(0.62, 0.18, 0.18),
	"gold": Color(0.68, 0.54, 0.18),
	"yellow": Color(0.72, 0.60, 0.18),
	"orange": Color(0.74, 0.40, 0.15),
	"green": Color(0.18, 0.44, 0.22),
	"silver": Color(0.65, 0.66, 0.68),
	"grey": Color(0.65, 0.66, 0.68),
	"gray": Color(0.65, 0.66, 0.68),
	"purple": Color(0.48, 0.22, 0.62)
}

# Backward compatibility alias
const TEE_COLOR_MAP: Dictionary = TEE_COLOR_MAP_VIBRANT

# Circular marker dimensions (standard ~5-inch golf tee marker spheres)
const SPHERE_RADIUS: float = 0.065     # ~13 cm diameter sphere
const TEEBOX_HALF_WIDTH: float = 1.65  # Half-span between left & right markers (3.3m total span)
const BUCKET_RIGHT_OFFSET: float = 0.52 # Offset to the right of the right colored marker

# Divot Box / Chest Dimensions (matches green recycled plastic divot chest in reference photo)
const DIVOT_BOX_WIDTH: float = 0.42       # Side-to-side width (~16.5 in)
const DIVOT_BOX_DEPTH: float = 0.32       # Front-to-back depth (~12.5 in)
const DIVOT_BOX_HEIGHT: float = 0.34      # Total height from feet to top of lid (~13.4 in)

# Backward compatibility aliases
const CADDY_WIDTH: float = DIVOT_BOX_WIDTH
const CADDY_DEPTH: float = DIVOT_BOX_DEPTH
const CADDY_HEIGHT: float = DIVOT_BOX_HEIGHT


## Helper to detect if Low graphics quality is currently active
static func is_low_quality() -> bool:
	if Engine.has_singleton("GlobalSettings"):
		var gs = Engine.get_singleton("GlobalSettings")
		if gs != null and gs.has_method("get_graphics_quality"):
			return gs.get_graphics_quality() == "Low"
	var main_loop = Engine.get_main_loop()
	if main_loop is SceneTree and main_loop.root != null and main_loop.root.has_node("GlobalSettings"):
		var gs_node = main_loop.root.get_node("GlobalSettings")
		if gs_node != null and gs_node.has_method("get_graphics_quality"):
			return gs_node.get_graphics_quality() == "Low"
	return false


## Get Godot Color for a tee name, adapted for current graphics setting
static func get_tee_color(tee_name: String, is_low: bool = false) -> Color:
	var key = tee_name.strip_edges().to_lower()
	var map = TEE_COLOR_MAP_MUTED if is_low else TEE_COLOR_MAP_VIBRANT
	if map.has(key):
		return map[key]
	var fallback = Color(0.18, 0.35, 0.62) if is_low else Color(0.14, 0.44, 0.90)
	var col = Color.from_string(tee_name, fallback)
	if is_low:
		col = col.lerp(Color(0.4, 0.4, 0.4), 0.25)
	return col


## Creates a circular/spherical golf tee marker matching the reference image
static func create_circle_marker(tee_name: String, radius: float = SPHERE_RADIUS, is_low: Variant = null) -> Node3D:
	var use_low = is_low_quality() if is_low == null else bool(is_low)
	var root := Node3D.new()
	root.name = "CircleMarker_" + tee_name.capitalize()
	root.set_meta("tee_color_name", tee_name)
	root.set_meta("is_tee_marker", true)
	root.set_meta("is_circle_marker", true)
	
	var tee_col = get_tee_color(tee_name, use_low)
	
	# 1. Main Colored Sphere
	var sphere_mesh := MeshInstance3D.new()
	sphere_mesh.name = "MarkerSphere"
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere_mesh.mesh = sphere
	
	var sphere_mat := StandardMaterial3D.new()
	sphere_mat.albedo_color = tee_col
	# On low graphics: higher roughness and non-metallic to eliminate harsh blown-out specular highlights
	sphere_mat.roughness = 0.50 if use_low else 0.26
	sphere_mat.metallic = 0.0 if use_low else 0.06
	sphere_mesh.material_override = sphere_mat
	root.add_child(sphere_mesh)
	
	# 2. Base Collar / Pedestal Ring
	var collar_mesh := MeshInstance3D.new()
	collar_mesh.name = "BaseCollar"
	var collar_cyl := CylinderMesh.new()
	collar_cyl.top_radius = 0.022
	collar_cyl.bottom_radius = 0.026
	collar_cyl.height = 0.012
	collar_mesh.mesh = collar_cyl
	
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.20, 0.22, 0.24) if use_low else Color(0.22, 0.24, 0.26)
	metal_mat.metallic = 0.4 if use_low else 0.85
	metal_mat.roughness = 0.5 if use_low else 0.32
	collar_mesh.material_override = metal_mat
	collar_mesh.position = Vector3(0, -radius + 0.004, 0)
	root.add_child(collar_mesh)
	
	# 3. Ground Anchor Spike extending down into turf
	var spike_mesh := MeshInstance3D.new()
	spike_mesh.name = "GroundSpike"
	var spike_cyl := CylinderMesh.new()
	spike_cyl.top_radius = 0.006
	spike_cyl.bottom_radius = 0.002
	spike_cyl.height = 0.06
	spike_mesh.mesh = spike_cyl
	spike_mesh.material_override = metal_mat
	spike_mesh.position = Vector3(0, -radius - 0.028, 0)
	root.add_child(spike_mesh)
	
	# 4. Obstacle collider
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.set_meta("is_obstacle", true)
	body.collision_layer = 1
	body.collision_mask = 0
	
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = radius
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	
	return root


## Legacy compatibility wrapper
static func create_wood_block(tee_name: String, _block_size: Vector3 = Vector3.ZERO) -> Node3D:
	return create_circle_marker(tee_name)


## Creates the green golf course divot sand storage box / chest made of recycled plastic lumber
## with 4 corner post legs, vertical slat panels, and an overhanging horizontal slatted lid
## matching the reference photo.
static func create_divot_bucket(is_low: Variant = null) -> Node3D:
	var use_low = is_low_quality() if is_low == null else bool(is_low)
	var root := Node3D.new()
	root.name = "DivotBucket"
	root.set_meta("is_divot_bucket", true)
	root.set_meta("is_divot_box", true)
	root.set_meta("is_divot_caddy", true)
	
	# Materials:
	# Medium / High: Rich recycled-plastic composite green with subtle sheen
	# Low Graphics: Grounded, muted matte green with higher roughness and zero metallic to avoid glow
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.13, 0.21, 0.15) if use_low else Color(0.11, 0.26, 0.14)
	post_mat.roughness = 0.75 if use_low else 0.62
	post_mat.metallic = 0.0
	
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.14, 0.23, 0.16) if use_low else Color(0.12, 0.28, 0.15)
	box_mat.roughness = 0.75 if use_low else 0.60
	box_mat.metallic = 0.0
	
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.15, 0.24, 0.17) if use_low else Color(0.14, 0.30, 0.17)
	lid_mat.roughness = 0.75 if use_low else 0.58
	lid_mat.metallic = 0.0
	
	var groove_mat := StandardMaterial3D.new()
	groove_mat.albedo_color = Color(0.07, 0.12, 0.08) if use_low else Color(0.05, 0.11, 0.06)
	groove_mat.roughness = 0.85 if use_low else 0.70
	groove_mat.metallic = 0.0
	
	var hinge_mat := StandardMaterial3D.new()
	hinge_mat.albedo_color = Color(0.10, 0.12, 0.10)
	hinge_mat.metallic = 0.15 if use_low else 0.65
	hinge_mat.roughness = 0.65 if use_low else 0.35
	
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.11, 0.18, 0.12) if use_low else Color(0.09, 0.20, 0.11)
	handle_mat.roughness = 0.75 if use_low else 0.50
	handle_mat.metallic = 0.0
	
	# Store materials dict in metadata for instantaneous dynamic graphics updates
	root.set_meta("box_materials", {
		"post": post_mat,
		"box": box_mat,
		"lid": lid_mat,
		"groove": groove_mat,
		"hinge": hinge_mat,
		"handle": handle_mat
	})
	
	# -------------------------------------------------------------------------
	# 1. Four Corner Post Legs (forming feet on the turf, rising to just under lid)
	# -------------------------------------------------------------------------
	var posts_container := Node3D.new()
	posts_container.name = "CornerPosts"
	root.add_child(posts_container)
	
	var post_w := 0.042
	var post_d := 0.042
	var post_h := 0.320 # Height of corner posts from y = -0.17 to y = +0.15
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(post_w, post_h, post_d)
	
	var post_x := (DIVOT_BOX_WIDTH - post_w) * 0.5  # 0.189
	var post_z := (DIVOT_BOX_DEPTH - post_d) * 0.5  # 0.139
	var post_y := -0.010 # Center Y: from -0.17 to +0.15
	
	var post_fl := MeshInstance3D.new()
	post_fl.name = "Post_FL"
	post_fl.mesh = post_mesh
	post_fl.material_override = post_mat
	post_fl.position = Vector3(-post_x, post_y, post_z)
	posts_container.add_child(post_fl)
	
	var post_fr := MeshInstance3D.new()
	post_fr.name = "Post_FR"
	post_fr.mesh = post_mesh
	post_fr.material_override = post_mat
	post_fr.position = Vector3(post_x, post_y, post_z)
	posts_container.add_child(post_fr)
	
	var post_bl := MeshInstance3D.new()
	post_bl.name = "Post_BL"
	post_bl.mesh = post_mesh
	post_bl.material_override = post_mat
	post_bl.position = Vector3(-post_x, post_y, -post_z)
	posts_container.add_child(post_bl)
	
	var post_br := MeshInstance3D.new()
	post_br.name = "Post_BR"
	post_br.mesh = post_mesh
	post_br.material_override = post_mat
	post_br.position = Vector3(post_x, post_y, -post_z)
	posts_container.add_child(post_br)
	
	# -------------------------------------------------------------------------
	# 2. Main Box Body (Panels framed between posts, elevated 2.4cm above turf)
	# -------------------------------------------------------------------------
	var main_box := Node3D.new()
	main_box.name = "MainBox"
	root.add_child(main_box)
	
	var body_w := DIVOT_BOX_WIDTH - (post_w * 0.9)  # 0.382
	var body_d := DIVOT_BOX_DEPTH - (post_d * 0.9)  # 0.282
	var body_h := 0.296 # from y = -0.146 to +0.150
	var body_y := 0.002
	
	var core_mesh := BoxMesh.new()
	core_mesh.size = Vector3(body_w, body_h, body_d)
	var box_core := MeshInstance3D.new()
	box_core.name = "BoxCore"
	box_core.mesh = core_mesh
	box_core.material_override = box_mat
	box_core.position = Vector3(0, body_y, 0)
	main_box.add_child(box_core)
	
	# Vertical slat grooves on Front Face (5 planks separated by 4 grooves)
	var front_grooves := Node3D.new()
	front_grooves.name = "FrontGrooves"
	main_box.add_child(front_grooves)
	
	var fg_mesh := BoxMesh.new()
	fg_mesh.size = Vector3(0.0035, body_h - 0.004, 0.003)
	var fg_z := (body_d * 0.5) + 0.001
	for gx in [-0.114, -0.038, 0.038, 0.114]:
		var g_inst := MeshInstance3D.new()
		g_inst.mesh = fg_mesh
		g_inst.material_override = groove_mat
		g_inst.position = Vector3(gx, body_y, fg_z)
		front_grooves.add_child(g_inst)
		
	# Vertical slat grooves on Back Face
	var back_grooves := Node3D.new()
	back_grooves.name = "BackGrooves"
	main_box.add_child(back_grooves)
	for gx in [-0.114, -0.038, 0.038, 0.114]:
		var g_inst := MeshInstance3D.new()
		g_inst.mesh = fg_mesh
		g_inst.material_override = groove_mat
		g_inst.position = Vector3(gx, body_y, -fg_z)
		back_grooves.add_child(g_inst)
		
	# Vertical slat grooves on Side Faces (3 planks separated by 2 grooves)
	var side_grooves := Node3D.new()
	side_grooves.name = "SideGrooves"
	main_box.add_child(side_grooves)
	
	var sg_mesh := BoxMesh.new()
	sg_mesh.size = Vector3(0.003, body_h - 0.004, 0.0035)
	var sg_x := (body_w * 0.5) + 0.001
	for gz in [-0.047, 0.047]:
		for sx in [-sg_x, sg_x]:
			var sg_inst := MeshInstance3D.new()
			sg_inst.mesh = sg_mesh
			sg_inst.material_override = groove_mat
			sg_inst.position = Vector3(sx, body_y, gz)
			side_grooves.add_child(sg_inst)
			
	# Subtle top and bottom frame rails
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(body_w + 0.004, 0.016, body_d + 0.004)
	
	var top_rail := MeshInstance3D.new()
	top_rail.name = "TopRail"
	top_rail.mesh = rail_mesh
	top_rail.material_override = post_mat
	top_rail.position = Vector3(0, body_y + (body_h * 0.5) - 0.008, 0)
	main_box.add_child(top_rail)
	
	var bot_rail := MeshInstance3D.new()
	bot_rail.name = "BottomRail"
	bot_rail.mesh = rail_mesh
	bot_rail.material_override = post_mat
	bot_rail.position = Vector3(0, body_y - (body_h * 0.5) + 0.008, 0)
	main_box.add_child(bot_rail)
	
	# -------------------------------------------------------------------------
	# 3. Overhanging Slatted Top Lid
	# -------------------------------------------------------------------------
	var lid_container := Node3D.new()
	lid_container.name = "SlattedLid"
	root.add_child(lid_container)
	
	var lid_w := DIVOT_BOX_WIDTH + 0.024 # 0.444 (slight overhang)
	var lid_d := DIVOT_BOX_DEPTH + 0.024 # 0.344 (slight overhang)
	var lid_h := 0.022
	var lid_y := 0.150 + (lid_h * 0.5)   # 0.161
	
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(lid_w, lid_h, lid_d)
	var lid_base := MeshInstance3D.new()
	lid_base.name = "LidBase"
	lid_base.mesh = lid_mesh
	lid_base.material_override = lid_mat
	lid_base.position = Vector3(0, lid_y, 0)
	lid_container.add_child(lid_base)
	
	# Horizontal slat grooves on top of lid (4 planks divided by 3 grooves)
	var lid_grooves := Node3D.new()
	lid_grooves.name = "LidGrooves"
	lid_container.add_child(lid_grooves)
	
	var lg_mesh := BoxMesh.new()
	lg_mesh.size = Vector3(lid_w - 0.004, 0.002, 0.0035)
	var lg_y := lid_y + (lid_h * 0.5) + 0.0005
	for lz in [-0.085, 0.0, 0.085]:
		var lg_inst := MeshInstance3D.new()
		lg_inst.mesh = lg_mesh
		lg_inst.material_override = groove_mat
		lg_inst.position = Vector3(0, lg_y, lz)
		lid_grooves.add_child(lg_inst)
		
	# Front lid lift handle
	var handle := MeshInstance3D.new()
	handle.name = "LidHandle"
	var hand_mesh := BoxMesh.new()
	hand_mesh.size = Vector3(0.082, 0.014, 0.022)
	handle.mesh = hand_mesh
	handle.material_override = handle_mat
	handle.position = Vector3(0, lid_y - 0.002, (lid_d * 0.5) + 0.009)
	lid_container.add_child(handle)
	
	# -------------------------------------------------------------------------
	# 4. Rear Hinges
	# -------------------------------------------------------------------------
	var hinges_container := Node3D.new()
	hinges_container.name = "Hinges"
	root.add_child(hinges_container)
	
	var hinge_mesh := BoxMesh.new()
	hinge_mesh.size = Vector3(0.038, 0.018, 0.012)
	var hinge_z := -((lid_d * 0.5) - 0.002)
	for hx in [-0.12, 0.12]:
		var h_inst := MeshInstance3D.new()
		h_inst.mesh = hinge_mesh
		h_inst.material_override = hinge_mat
		h_inst.position = Vector3(hx, 0.150, hinge_z)
		hinges_container.add_child(h_inst)
		
	# -------------------------------------------------------------------------
	# 5. Obstacle Collider
	# -------------------------------------------------------------------------
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.set_meta("is_obstacle", true)
	body.collision_layer = 1
	body.collision_mask = 0
	
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(lid_w, DIVOT_BOX_HEIGHT, lid_d)
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	
	return root


## Builds a teebox cluster (left and right circular tee markers with tee color(s), plus green divot caddy on the right)
static func build_single_teebox_cluster(
	tee_colors: Array,
	tee_center: Vector3,
	target_pos: Vector3,
	height_callable: Callable = Callable(),
	is_low: Variant = null
) -> Node3D:
	var use_low = is_low_quality() if is_low == null else bool(is_low)
	var cluster := Node3D.new()
	cluster.name = "TeeboxCluster"
	cluster.position = tee_center
	
	# Calculate fairway aim direction in horizontal XZ plane
	var diff_xz := Vector2(target_pos.x - tee_center.x, target_pos.z - tee_center.z)
	var forward_xz := diff_xz.normalized() if diff_xz.length_squared() > 0.01 else Vector2(1.0, 0.0)
	
	var forward_3d := Vector3(forward_xz.x, 0.0, forward_xz.y)
	# Right vector: forward x UP
	var right_3d := forward_3d.cross(Vector3.UP).normalized()
	
	var num_colors = maxi(1, tee_colors.size())
	
	# Build left and right circular markers for each tee color present at this teebox
	for i in range(num_colors):
		var col_name: String = str(tee_colors[i]) if i < tee_colors.size() else "Blue"
		var along_fairway_offset: float = (float(i) - float(num_colors - 1) * 0.5) * 0.36
		
		# --- Left Circular Marker ---
		var left_rel_pos := -right_3d * TEEBOX_HALF_WIDTH + forward_3d * along_fairway_offset
		var left_world_xz := tee_center + left_rel_pos
		var left_ground_y: float = tee_center.y
		if height_callable.is_valid():
			left_ground_y = float(height_callable.call(left_world_xz.x, left_world_xz.z))
		left_rel_pos.y = (left_ground_y - tee_center.y) + SPHERE_RADIUS
		
		var left_marker := create_circle_marker(col_name, SPHERE_RADIUS, use_low)
		left_marker.name = "LeftMarker_" + col_name
		left_marker.position = left_rel_pos
		_orient_node_forward(left_marker, forward_3d)
		cluster.add_child(left_marker)
		
		# --- Right Circular Marker ---
		var right_rel_pos := right_3d * TEEBOX_HALF_WIDTH + forward_3d * along_fairway_offset
		var right_world_xz := tee_center + right_rel_pos
		var right_ground_y: float = tee_center.y
		if height_callable.is_valid():
			right_ground_y = float(height_callable.call(right_world_xz.x, right_world_xz.z))
		right_rel_pos.y = (right_ground_y - tee_center.y) + SPHERE_RADIUS
		
		var right_marker := create_circle_marker(col_name, SPHERE_RADIUS, use_low)
		right_marker.name = "RightMarker_" + col_name
		right_marker.position = right_rel_pos
		_orient_node_forward(right_marker, forward_3d)
		cluster.add_child(right_marker)
		
	# --- Green Divot Caddy / Bucket ---
	# Placed on the right side of the right colored marker
	var bucket_rel_pos := right_3d * (TEEBOX_HALF_WIDTH + BUCKET_RIGHT_OFFSET)
	var bucket_world_xz := tee_center + bucket_rel_pos
	var bucket_ground_y: float = tee_center.y
	if height_callable.is_valid():
		bucket_ground_y = float(height_callable.call(bucket_world_xz.x, bucket_world_xz.z))
	bucket_rel_pos.y = (bucket_ground_y - tee_center.y) + (CADDY_HEIGHT * 0.5)
	
	var divot_bucket := create_divot_bucket(use_low)
	divot_bucket.position = bucket_rel_pos
	_orient_node_forward(divot_bucket, forward_3d)
	cluster.add_child(divot_bucket)
	
	return cluster


## Helper to orient a Node3D along horizontal forward direction
static func _orient_node_forward(node: Node3D, forward_dir: Vector3) -> void:
	if forward_dir.length_squared() > 0.001:
		node.basis = Basis.looking_at(forward_dir, Vector3.UP)


## Updates or builds teebox markers and divot buckets across the course / hole
static func update_course_teebox_markers(
	course_node: Node,
	hole_data: Dictionary,
	active_tee_name: String = "",
	target_pos: Vector3 = Vector3.ZERO,
	height_callable: Callable = Callable(),
	is_low: Variant = null
) -> Node3D:
	if course_node == null:
		return null
		
	# Skip driving range bays (driving range has its own dedicated hitting mats & bays)
	if course_node.get("is_driving_range") == true or (course_node.has_meta("is_driving_range") and course_node.get_meta("is_driving_range") == true):
		return null
		
	# Remove any previous TeeboxMarkers container
	var existing = course_node.get_node_or_null("TeeboxMarkers")
	if existing != null:
		existing.queue_free()
		existing.name = "TeeboxMarkers_Old"
		
	var root_container := Node3D.new()
	root_container.name = "TeeboxMarkers"
	course_node.add_child(root_container)
	
	# Determine target/pin position if not provided
	if target_pos.is_zero_approx():
		if "current_hole_location" in course_node and not (course_node.current_hole_location as Vector3).is_zero_approx():
			target_pos = course_node.current_hole_location
		elif hole_data.has("Hole Location"):
			var hl = hole_data["Hole Location"]
			var hy: float = 0.0
			if height_callable.is_valid():
				hy = float(height_callable.call(float(hl[0]), float(hl[1])))
			target_pos = Vector3(float(hl[0]), hy, float(hl[1]))
		else:
			target_pos = Vector3(200.0, 0.0, 0.0)
			
	var tee_boxes: Dictionary = hole_data.get("Tee Boxes", {})
	
	# Group tees by physical location (tees within 2.0m share the same teebox)
	var teebox_locations: Array[Dictionary] = [] # Array of { "pos_2d": Vector2, "colors": Array[String] }
	
	if typeof(tee_boxes) == TYPE_DICTIONARY and not tee_boxes.is_empty():
		for t_name in tee_boxes.keys():
			var coords = tee_boxes[t_name]
			if coords is Array and coords.size() >= 2:
				var pos_2d := Vector2(float(coords[0]), float(coords[1]))
				var matched_loc: Dictionary = {}
				for loc in teebox_locations:
					if pos_2d.distance_to(loc["pos_2d"]) <= 2.0:
						matched_loc = loc
						break
				if not matched_loc.is_empty():
					if not matched_loc["colors"].has(str(t_name)):
						matched_loc["colors"].append(str(t_name))
				else:
					teebox_locations.append({
						"pos_2d": pos_2d,
						"colors": [str(t_name)]
					})
	
	# Fallback if no tee boxes are defined in JSON (e.g. dynamic minigame or test course)
	if teebox_locations.is_empty():
		var default_col = active_tee_name if not active_tee_name.is_empty() else "Blue"
		var fallback_pos_2d := Vector2.ZERO
		if course_node.has_node("Player"):
			var p_node = course_node.get_node("Player")
			if p_node.get("ball") != null:
				var b_pos: Vector3 = p_node.ball.spawn_position
				fallback_pos_2d = Vector2(b_pos.x, b_pos.z)
		teebox_locations.append({
			"pos_2d": fallback_pos_2d,
			"colors": [default_col]
		})
		
	# Build marker cluster for each unique teebox location
	for loc in teebox_locations:
		var p2d: Vector2 = loc["pos_2d"]
		
		# If this teebox position is inside fairway boundaries (e.g. kids stakes in the middle of fairway),
		# do not generate the sand bucket or colored tee box markers.
		if course_node != null:
			if course_node.has_method("is_point_in_fairway") and bool(course_node.call("is_point_in_fairway", p2d)):
				continue
			elif course_node.has_method("get_distance_to_nearest_fairway"):
				var ground_y_probe: float = 0.0
				if height_callable.is_valid():
					ground_y_probe = float(height_callable.call(p2d.x, p2d.y))
				elif "get_height" in course_node and course_node.has_method("get_height"):
					ground_y_probe = float(course_node.call("get_height", p2d.x, p2d.y))
				var dist_fw: float = float(course_node.call("get_distance_to_nearest_fairway", Vector3(p2d.x, ground_y_probe, p2d.y)))
				if dist_fw <= 0.001:
					continue

		var ground_y: float = 0.0
		if height_callable.is_valid():
			ground_y = float(height_callable.call(p2d.x, p2d.y))
		elif "get_height" in course_node and course_node.has_method("get_height"):
			ground_y = float(course_node.call("get_height", p2d.x, p2d.y))
			
		var tee_center := Vector3(p2d.x, ground_y, p2d.y)
		var cluster := build_single_teebox_cluster(loc["colors"], tee_center, target_pos, height_callable, is_low)
		root_container.add_child(cluster)
		
	return root_container


## Dynamically updates existing teebox markers in scene when graphics quality changes
static func apply_graphics_quality_to_markers(scene_root: Node, is_low: bool) -> void:
	if scene_root == null:
		return
	var markers_container = scene_root.find_child("TeeboxMarkers", true, false)
	if markers_container == null:
		return
		
	for cluster in markers_container.get_children():
		for item in cluster.get_children():
			if item.has_meta("is_tee_marker"):
				var t_name: String = str(item.get_meta("tee_color_name", "Blue"))
				var sphere_node = item.get_node_or_null("MarkerSphere") as MeshInstance3D
				if sphere_node != null and sphere_node.material_override is StandardMaterial3D:
					var mat = sphere_node.material_override as StandardMaterial3D
					mat.albedo_color = get_tee_color(t_name, is_low)
					mat.roughness = 0.50 if is_low else 0.26
					mat.metallic = 0.0 if is_low else 0.06
			elif item.has_meta("is_divot_box") or item.has_meta("is_divot_caddy") or item.has_meta("is_divot_bucket"):
				if item.has_meta("box_materials"):
					var mats: Dictionary = item.get_meta("box_materials")
					if mats.has("post") and mats["post"] is StandardMaterial3D:
						mats["post"].albedo_color = Color(0.13, 0.21, 0.15) if is_low else Color(0.11, 0.26, 0.14)
						mats["post"].roughness = 0.75 if is_low else 0.62
					if mats.has("box") and mats["box"] is StandardMaterial3D:
						mats["box"].albedo_color = Color(0.14, 0.23, 0.16) if is_low else Color(0.12, 0.28, 0.15)
						mats["box"].roughness = 0.75 if is_low else 0.60
					if mats.has("lid") and mats["lid"] is StandardMaterial3D:
						mats["lid"].albedo_color = Color(0.15, 0.24, 0.17) if is_low else Color(0.14, 0.30, 0.17)
						mats["lid"].roughness = 0.75 if is_low else 0.58
					if mats.has("groove") and mats["groove"] is StandardMaterial3D:
						mats["groove"].albedo_color = Color(0.07, 0.12, 0.08) if is_low else Color(0.05, 0.11, 0.06)
						mats["groove"].roughness = 0.85 if is_low else 0.70
					if mats.has("hinge") and mats["hinge"] is StandardMaterial3D:
						mats["hinge"].metallic = 0.15 if is_low else 0.65
						mats["hinge"].roughness = 0.65 if is_low else 0.35
					if mats.has("handle") and mats["handle"] is StandardMaterial3D:
						mats["handle"].albedo_color = Color(0.11, 0.18, 0.12) if is_low else Color(0.09, 0.20, 0.11)
						mats["handle"].roughness = 0.75 if is_low else 0.50

