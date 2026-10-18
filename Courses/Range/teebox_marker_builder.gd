# ==============================================================================
# HeckleGolfSim - Teebox Marker & Divot Bucket Builder
# Procedurally generates:
# - Little wood blocks with the color(s) of the tees at each teebox, giving
#   players clear visual feedback that they are hitting from where they wanted.
# - A little green bucket (holding sand for golf divots) placed on the right
#   side of the right colored block.
# ==============================================================================
class_name TeeboxMarkerBuilder
extends RefCounted

# Standard tee color definitions
const TEE_COLOR_MAP: Dictionary = {
	"black": Color(0.12, 0.12, 0.14),
	"blue": Color(0.18, 0.48, 0.92),
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

# Standard dimensions
const BLOCK_WIDTH: float = 0.11     # Width perpendicular to fairway (~4.3 in)
const BLOCK_HEIGHT: float = 0.09    # Height (~3.5 in)
const BLOCK_LENGTH: float = 0.28    # Length along fairway line (~11 in)
const TEEBOX_HALF_WIDTH: float = 1.65 # Half-span between left & right markers (3.3m total span)
const BUCKET_RIGHT_OFFSET: float = 0.48 # Offset to the right of the right colored block

# Bucket dimensions
const BUCKET_TOP_RADIUS: float = 0.125
const BUCKET_BOTTOM_RADIUS: float = 0.095
const BUCKET_HEIGHT: float = 0.24


## Get Godot Color for a tee name
static func get_tee_color(tee_name: String) -> Color:
	var key = tee_name.strip_edges().to_lower()
	if TEE_COLOR_MAP.has(key):
		return TEE_COLOR_MAP[key]
	return Color.from_string(tee_name, Color(0.18, 0.48, 0.92))


## Creates a painted wooden block tee marker with natural wood end-caps
static func create_wood_block(tee_name: String, block_size: Vector3 = Vector3(BLOCK_WIDTH, BLOCK_HEIGHT, BLOCK_LENGTH)) -> Node3D:
	var root := Node3D.new()
	root.name = "WoodBlock_" + tee_name.capitalize()
	root.set_meta("tee_color_name", tee_name)
	
	var tee_col = get_tee_color(tee_name)
	
	# 1. Main painted wooden block
	var main_mesh := MeshInstance3D.new()
	main_mesh.name = "MainBlock"
	var box := BoxMesh.new()
	box.size = block_size
	main_mesh.mesh = box
	
	var block_mat := StandardMaterial3D.new()
	block_mat.albedo_color = tee_col
	block_mat.roughness = 0.58
	main_mesh.material_override = block_mat
	root.add_child(main_mesh)
	
	# 2. Natural wood end-caps at front (+Z) and back (-Z)
	var wood_cap_mat := StandardMaterial3D.new()
	wood_cap_mat.albedo_color = Color(0.56, 0.40, 0.24) # Warm natural pine/cedar core
	wood_cap_mat.roughness = 0.82
	
	var cap_size := Vector3(block_size.x * 0.90, block_size.y * 0.90, 0.006)
	
	var front_cap := MeshInstance3D.new()
	front_cap.name = "FrontEndCap"
	var cap_mesh := BoxMesh.new()
	cap_mesh.size = cap_size
	front_cap.mesh = cap_mesh
	front_cap.material_override = wood_cap_mat
	front_cap.position = Vector3(0, 0, block_size.z * 0.5 + 0.001)
	root.add_child(front_cap)
	
	var back_cap := MeshInstance3D.new()
	back_cap.name = "BackEndCap"
	back_cap.mesh = cap_mesh
	back_cap.material_override = wood_cap_mat
	back_cap.position = Vector3(0, 0, -block_size.z * 0.5 - 0.001)
	root.add_child(back_cap)
	
	# 3. Ground ground pins underneath so the block sits anchored into turf
	var pin_mat := StandardMaterial3D.new()
	pin_mat.albedo_color = Color(0.18, 0.18, 0.18)
	pin_mat.metallic = 0.8
	
	var pin_mesh := CylinderMesh.new()
	pin_mesh.top_radius = 0.005
	pin_mesh.bottom_radius = 0.005
	pin_mesh.height = 0.04
	
	for z_off in [-0.08, 0.08]:
		var g_pin := MeshInstance3D.new()
		g_pin.mesh = pin_mesh
		g_pin.material_override = pin_mat
		g_pin.position = Vector3(0, -block_size.y * 0.5 - 0.015, z_off)
		root.add_child(g_pin)
		
	# 4. Obstacle collider
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.set_meta("is_obstacle", true)
	body.collision_layer = 1
	body.collision_mask = 0
	
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = block_size
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	
	return root


## Creates a green golf course divot sand bucket with sand fill, top rim, and scoop handle
static func create_divot_bucket() -> Node3D:
	var root := Node3D.new()
	root.name = "DivotBucket"
	root.set_meta("is_divot_bucket", true)
	
	# 1. Bucket body (tapered cylinder in hunter golf green)
	var body_mesh := MeshInstance3D.new()
	body_mesh.name = "BucketBody"
	var cyl := CylinderMesh.new()
	cyl.top_radius = BUCKET_TOP_RADIUS
	cyl.bottom_radius = BUCKET_BOTTOM_RADIUS
	cyl.height = BUCKET_HEIGHT
	body_mesh.mesh = cyl
	
	var bucket_mat := StandardMaterial3D.new()
	bucket_mat.albedo_color = Color(0.12, 0.38, 0.18) # Classic hunter golf green
	bucket_mat.roughness = 0.38
	body_mesh.material_override = bucket_mat
	root.add_child(body_mesh)
	
	# 2. Reinforced top rim lip
	var rim_mesh := MeshInstance3D.new()
	rim_mesh.name = "TopRim"
	var rim_cyl := CylinderMesh.new()
	rim_cyl.top_radius = BUCKET_TOP_RADIUS + 0.007
	rim_cyl.bottom_radius = BUCKET_TOP_RADIUS + 0.005
	rim_cyl.height = 0.024
	rim_mesh.mesh = rim_cyl
	
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.10, 0.33, 0.15) # Slightly darker green lip
	rim_mat.roughness = 0.35
	rim_mesh.material_override = rim_mat
	rim_mesh.position = Vector3(0, BUCKET_HEIGHT * 0.5 - 0.012, 0)
	root.add_child(rim_mesh)
	
	# 3. Bottom base ring
	var base_mesh := MeshInstance3D.new()
	base_mesh.name = "BaseRing"
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = BUCKET_BOTTOM_RADIUS + 0.005
	base_cyl.bottom_radius = BUCKET_BOTTOM_RADIUS + 0.002
	base_cyl.height = 0.016
	base_mesh.mesh = base_cyl
	base_mesh.material_override = rim_mat
	base_mesh.position = Vector3(0, -BUCKET_HEIGHT * 0.5 + 0.008, 0)
	root.add_child(base_mesh)
	
	# 4. Divot sand fill inside bucket
	var sand_mesh := MeshInstance3D.new()
	sand_mesh.name = "DivotSand"
	var sand_cyl := CylinderMesh.new()
	sand_cyl.top_radius = BUCKET_TOP_RADIUS - 0.008
	sand_cyl.bottom_radius = BUCKET_TOP_RADIUS - 0.012
	sand_cyl.height = 0.035
	sand_mesh.mesh = sand_cyl
	
	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.82, 0.74, 0.58) # Warm golf sand
	sand_mat.roughness = 0.95
	sand_mesh.material_override = sand_mat
	sand_mesh.position = Vector3(0, BUCKET_HEIGHT * 0.5 - 0.035, 0)
	root.add_child(sand_mesh)
	
	# 5. Divot scoop handle sticking out of the sand
	var scoop_mesh := MeshInstance3D.new()
	scoop_mesh.name = "ScoopHandle"
	var scoop_cyl := CylinderMesh.new()
	scoop_cyl.top_radius = 0.009
	scoop_cyl.bottom_radius = 0.008
	scoop_cyl.height = 0.12
	scoop_mesh.mesh = scoop_cyl
	
	var scoop_mat := StandardMaterial3D.new()
	scoop_mat.albedo_color = Color(0.14, 0.18, 0.14)
	scoop_mat.roughness = 0.4
	scoop_mesh.material_override = scoop_mat
	scoop_mesh.position = Vector3(0.025, BUCKET_HEIGHT * 0.5 + 0.025, 0.01)
	scoop_mesh.rotation = Vector3(0.15, 0.0, -0.32) # Jaunty tilt
	root.add_child(scoop_mesh)
	
	var knob_mesh := MeshInstance3D.new()
	knob_mesh.name = "ScoopKnob"
	var sphere := SphereMesh.new()
	sphere.radius = 0.014
	sphere.height = 0.028
	knob_mesh.mesh = sphere
	knob_mesh.material_override = scoop_mat
	knob_mesh.position = Vector3(0, 0.06, 0)
	scoop_mesh.add_child(knob_mesh)
	
	# 6. Wire bail handle over top of bucket
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.78, 0.78, 0.80)
	wire_mat.metallic = 0.92
	wire_mat.roughness = 0.22
	
	var handle_mesh := MeshInstance3D.new()
	handle_mesh.name = "BailHandle"
	var torus := TorusMesh.new()
	torus.inner_radius = BUCKET_TOP_RADIUS - 0.002
	torus.outer_radius = BUCKET_TOP_RADIUS + 0.006
	handle_mesh.mesh = torus
	handle_mesh.material_override = wire_mat
	handle_mesh.position = Vector3(0, BUCKET_HEIGHT * 0.5 + 0.01, 0)
	handle_mesh.rotation = Vector3(0.35, 0, 0)
	root.add_child(handle_mesh)
	
	# 7. Obstacle collider
	var body := StaticBody3D.new()
	body.name = "Collider"
	body.set_meta("is_obstacle", true)
	body.collision_layer = 1
	body.collision_mask = 0
	
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = BUCKET_TOP_RADIUS
	shape.height = BUCKET_HEIGHT
	col.shape = shape
	body.add_child(col)
	root.add_child(body)
	
	return root


## Builds a teebox cluster (left and right wood blocks with tee color(s), plus divot bucket on the right)
static func build_single_teebox_cluster(
	tee_colors: Array,
	tee_center: Vector3,
	target_pos: Vector3,
	height_callable: Callable = Callable()
) -> Node3D:
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
	
	# Build left and right blocks for each tee color present at this teebox
	for i in range(num_colors):
		var col_name: String = str(tee_colors[i]) if i < tee_colors.size() else "Blue"
		var along_fairway_offset: float = (float(i) - float(num_colors - 1) * 0.5) * 0.36
		
		# --- Left Colored Block ---
		var left_rel_pos := -right_3d * TEEBOX_HALF_WIDTH + forward_3d * along_fairway_offset
		var left_world_xz := tee_center + left_rel_pos
		var left_ground_y: float = tee_center.y
		if height_callable.is_valid():
			left_ground_y = float(height_callable.call(left_world_xz.x, left_world_xz.z))
		left_rel_pos.y = (left_ground_y - tee_center.y) + (BLOCK_HEIGHT * 0.5)
		
		var left_block := create_wood_block(col_name)
		left_block.name = "LeftBlock_" + col_name
		left_block.position = left_rel_pos
		_orient_node_forward(left_block, forward_3d)
		cluster.add_child(left_block)
		
		# --- Right Colored Block ---
		var right_rel_pos := right_3d * TEEBOX_HALF_WIDTH + forward_3d * along_fairway_offset
		var right_world_xz := tee_center + right_rel_pos
		var right_ground_y: float = tee_center.y
		if height_callable.is_valid():
			right_ground_y = float(height_callable.call(right_world_xz.x, right_world_xz.z))
		right_rel_pos.y = (right_ground_y - tee_center.y) + (BLOCK_HEIGHT * 0.5)
		
		var right_block := create_wood_block(col_name)
		right_block.name = "RightBlock_" + col_name
		right_block.position = right_rel_pos
		_orient_node_forward(right_block, forward_3d)
		cluster.add_child(right_block)
		
	# --- Divot Sand Bucket ---
	# Placed on the right side of the right colored block
	var bucket_rel_pos := right_3d * (TEEBOX_HALF_WIDTH + BUCKET_RIGHT_OFFSET)
	var bucket_world_xz := tee_center + bucket_rel_pos
	var bucket_ground_y: float = tee_center.y
	if height_callable.is_valid():
		bucket_ground_y = float(height_callable.call(bucket_world_xz.x, bucket_world_xz.z))
	bucket_rel_pos.y = (bucket_ground_y - tee_center.y) + (BUCKET_HEIGHT * 0.5)
	
	var divot_bucket := create_divot_bucket()
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
	height_callable: Callable = Callable()
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
		var ground_y: float = 0.0
		if height_callable.is_valid():
			ground_y = float(height_callable.call(p2d.x, p2d.y))
		elif "get_height" in course_node and course_node.has_method("get_height"):
			ground_y = float(course_node.call("get_height", p2d.x, p2d.y))
			
		var tee_center := Vector3(p2d.x, ground_y, p2d.y)
		var cluster := build_single_teebox_cluster(loc["colors"], tee_center, target_pos, height_callable)
		root_container.add_child(cluster)
		
	return root_container
