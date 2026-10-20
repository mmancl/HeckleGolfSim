class_name FlagBuilder
extends RefCounted

## FlagBuilder
## Static factory and helper for creating and managing golf pin flags, flagpoles,
## and realistic wind-waving cloth flags across all courses and minigames.

const GOLF_FLAG_SCRIPT := "res://Courses/Range/golf_flag.gd"


## Builds a standard regulation golf hole pin with pole, collider, realistic flag, and cup rim
static func build_flag_pin(
	pin: Node3D,
	pole_height: float = 3.0,
	flag_color: Color = Color(0.95, 0.12, 0.12),
	cup_radius: float = 0.054,
	quality: String = ""
) -> Node3D:
	if pin == null:
		pin = Node3D.new()
	pin.name = "FlagPin"

	# 1. Flagpole (slender tournament fiberglass cylinder)
	var pole = pin.get_node_or_null("Pole") as MeshInstance3D
	if pole == null:
		pole = MeshInstance3D.new()
		pole.name = "Pole"
		pin.add_child(pole)
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.012
	pole_mesh.bottom_radius = 0.012
	pole_mesh.height = pole_height
	pole.mesh = pole_mesh
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color.WHITE
	pole_mat.roughness = 0.25 # Clean glossy tournament finish
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, pole_height * 0.5, 0.0)

	# 2. Flagpole 3D collider (typical collision, disabled when putting)
	var flag_body = pin.get_node_or_null("FlagstickCollider") as StaticBody3D
	if flag_body == null:
		flag_body = StaticBody3D.new()
		flag_body.name = "FlagstickCollider"
		pin.add_child(flag_body)
	flag_body.set_meta("is_flagstick", true)
	flag_body.set_meta("is_obstacle", true)
	flag_body.collision_layer = 1
	flag_body.collision_mask = 0

	var col_shape = flag_body.get_node_or_null("CollisionShape") as CollisionShape3D
	if col_shape == null:
		col_shape = CollisionShape3D.new()
		col_shape.name = "CollisionShape"
		flag_body.add_child(col_shape)
	var cyl = CylinderShape3D.new()
	cyl.radius = 0.012
	cyl.height = pole_height
	col_shape.shape = cyl
	col_shape.position = Vector3(0.0, pole_height * 0.5, 0.0)

	# 3. Dynamic Golf Flag (MeshInstance3D with GolfFlag script)
	var flag = pin.get_node_or_null("Flag") as MeshInstance3D
	if flag == null:
		flag = MeshInstance3D.new()
		flag.name = "Flag"
		flag.set_meta("is_golf_flag", true)
		if ResourceLoader.exists(GOLF_FLAG_SCRIPT):
			flag.set_script(load(GOLF_FLAG_SCRIPT))
		pin.add_child(flag)
	elif flag.get_script() == null and ResourceLoader.exists(GOLF_FLAG_SCRIPT):
		flag.set_meta("is_golf_flag", true)
		flag.set_script(load(GOLF_FLAG_SCRIPT))
	flag.set_meta("is_golf_flag", true)

	flag.set("pole_height", pole_height)
	flag.set("flag_color", flag_color)
	flag.position = Vector3(0.0, pole_height - 0.22, 0.0)

	if not quality.is_empty() and flag.has_method("update_quality"):
		flag.update_quality(quality)

	# 4. Hardware Finial & Swivel Collars
	var is_low = (quality == "Low")
	var finial = pin.get_node_or_null("Finial") as MeshInstance3D
	if finial == null:
		finial = MeshInstance3D.new()
		finial.name = "Finial"
		var s_mesh = SphereMesh.new()
		s_mesh.radius = 0.020
		s_mesh.height = 0.040
		finial.mesh = s_mesh
		var finial_mat = StandardMaterial3D.new()
		finial_mat.albedo_color = Color(0.88, 0.74, 0.28) # Polished brass
		finial_mat.metallic = 0.90
		finial_mat.roughness = 0.22
		finial.material_override = finial_mat
		pin.add_child(finial)
	finial.position = Vector3(0.0, pole_height + 0.015, 0.0)
	finial.visible = not is_low

	var top_collar = pin.get_node_or_null("TopCollar") as MeshInstance3D
	if top_collar == null:
		top_collar = _create_collar("TopCollar")
		pin.add_child(top_collar)
	top_collar.position = Vector3(0.0, flag.position.y + (0.36 * 0.44), 0.0)
	top_collar.visible = not is_low

	var bot_collar = pin.get_node_or_null("BottomCollar") as MeshInstance3D
	if bot_collar == null:
		bot_collar = _create_collar("BottomCollar")
		pin.add_child(bot_collar)
	bot_collar.position = Vector3(0.0, flag.position.y - (0.36 * 0.44), 0.0)
	bot_collar.visible = not is_low

	# 5. Realistic Cup Liner & Inner Cup (if cup_radius > 0)
	if cup_radius > 0.0:
		var cup_white = pin.get_node_or_null("CupWhite") as MeshInstance3D
		if cup_white == null:
			cup_white = MeshInstance3D.new()
			cup_white.name = "CupWhite"
			pin.add_child(cup_white)
		var white_mesh = CylinderMesh.new()
		white_mesh.top_radius = cup_radius
		white_mesh.bottom_radius = cup_radius
		white_mesh.height = 0.003
		cup_white.mesh = white_mesh
		var white_mat = StandardMaterial3D.new()
		white_mat.albedo_color = Color(0.95, 0.95, 0.95)
		white_mat.roughness = 0.5
		cup_white.material_override = white_mat
		cup_white.position = Vector3(0.0, 0.0012, 0.0)

		var cup_dark = pin.get_node_or_null("Cup") as MeshInstance3D
		if cup_dark == null:
			cup_dark = MeshInstance3D.new()
			cup_dark.name = "Cup"
			pin.add_child(cup_dark)
		var cup_mesh = CylinderMesh.new()
		cup_mesh.top_radius = 0.048
		cup_mesh.bottom_radius = 0.048
		cup_mesh.height = 0.0035
		cup_dark.mesh = cup_mesh
		var cup_mat = StandardMaterial3D.new()
		cup_mat.albedo_color = Color(0.12, 0.12, 0.12)
		cup_mat.roughness = 1.0
		cup_dark.material_override = cup_mat
		cup_dark.position = Vector3(0.0, 0.0016, 0.0)

	return pin


## Helper to create swivel collar on flagpole
static func _create_collar(node_name: String) -> MeshInstance3D:
	var collar = MeshInstance3D.new()
	collar.name = node_name
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.017
	cyl.bottom_radius = 0.017
	cyl.height = 0.018
	collar.mesh = cyl
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.75, 0.78)
	mat.metallic = 0.92
	mat.roughness = 0.28
	collar.material_override = mat
	return collar


## Sets up a flag and pole on an existing node (e.g. for minigames and target pins)
static func setup_target_flag(
	parent_node: Node3D,
	pole_height: float = 2.6,
	flag_color: Color = Color(0.95, 0.12, 0.12),
	flag_width: float = 0.52,
	flag_height: float = 0.36,
	has_collider: bool = true,
	quality: String = ""
) -> MeshInstance3D:
	if parent_node == null:
		return null

	# Flagpole
	var pole = parent_node.get_node_or_null("Pole") as MeshInstance3D
	if pole == null:
		pole = MeshInstance3D.new()
		pole.name = "Pole"
		parent_node.add_child(pole)
	var pole_mesh = CylinderMesh.new()
	pole_mesh.top_radius = 0.015
	pole_mesh.bottom_radius = 0.015
	pole_mesh.height = pole_height
	pole.mesh = pole_mesh
	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color.WHITE
	pole_mat.roughness = 0.25
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, pole_height * 0.5, 0.0)

	# Optional Collider
	if has_collider:
		var flag_body = parent_node.get_node_or_null("FlagstickCollider") as StaticBody3D
		if flag_body == null:
			flag_body = StaticBody3D.new()
			flag_body.name = "FlagstickCollider"
			flag_body.set_meta("is_flagstick", true)
			flag_body.set_meta("is_obstacle", true)
			flag_body.collision_layer = 1
			flag_body.collision_mask = 0
			var col_shape = CollisionShape3D.new()
			col_shape.name = "CollisionShape"
			var cyl = CylinderShape3D.new()
			cyl.radius = 0.018
			cyl.height = pole_height
			col_shape.shape = cyl
			col_shape.position = Vector3(0.0, pole_height * 0.5, 0.0)
			flag_body.add_child(col_shape)
			parent_node.add_child(flag_body)

	# Flag
	var flag = parent_node.get_node_or_null("Flag") as MeshInstance3D
	if flag == null:
		flag = MeshInstance3D.new()
		flag.name = "Flag"
		flag.set_meta("is_golf_flag", true)
		if ResourceLoader.exists(GOLF_FLAG_SCRIPT):
			flag.set_script(load(GOLF_FLAG_SCRIPT))
		parent_node.add_child(flag)
	elif flag.get_script() == null and ResourceLoader.exists(GOLF_FLAG_SCRIPT):
		flag.set_meta("is_golf_flag", true)
		flag.set_script(load(GOLF_FLAG_SCRIPT))
	flag.set_meta("is_golf_flag", true)

	flag.set("pole_height", pole_height)
	flag.set("flag_width", flag_width)
	flag.set("flag_height", flag_height)
	flag.set("flag_color", flag_color)
	flag.position = Vector3(0.0, pole_height - (flag_height * 0.6), 0.0)

	if not quality.is_empty() and flag.has_method("update_quality"):
		flag.update_quality(quality)

	return flag


## Recursively updates all flags in a scene hierarchy when graphics quality changes
static func apply_graphics_quality_to_flags(scene_root: Node, quality: String) -> void:
	if scene_root == null:
		return

	var is_low = (quality == "Low")
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n.has_meta("is_golf_flag") or (n.get_script() != null and str(n.get_script().resource_path).ends_with("golf_flag.gd")):
			if n.has_method("update_quality"):
				n.update_quality(quality)
		var finial = n.get_node_or_null("Finial")
		if finial != null:
			finial.visible = not is_low
		var top_col = n.get_node_or_null("TopCollar")
		if top_col != null:
			top_col.visible = not is_low
		var bot_col = n.get_node_or_null("BottomCollar")
		if bot_col != null:
			bot_col.visible = not is_low

		for child in n.get_children():
			stack.push_back(child)
