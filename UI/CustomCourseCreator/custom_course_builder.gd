class_name CustomCourseBuilder
extends RefCounted

const ROUGH_BUFFER_M: float = 15.24 # 50 feet in meters

## Builds and saves a custom course by splicing 3D nodes from ONLY the selected holes.
## Returns a Dictionary with "title", "config_path", and "scene_path".
static func build_custom_course(title: String, selected_holes: Array[Dictionary]) -> Dictionary:
	if title.strip_edges().is_empty() or selected_holes.is_empty():
		push_error("[CustomCourseBuilder] Invalid title or empty hole list.")
		return {}

	var safe_name = title.strip_edges().to_lower()
	for c in [" ", "/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		safe_name = safe_name.replace(c, "_")
	
	var dir_name = "custom_" + safe_name + "_" + str(Time.get_ticks_msec())
	var course_dir = "user://courses/" + dir_name
	
	var err = DirAccess.make_dir_recursive_absolute(course_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("[CustomCourseBuilder] Could not create directory: " + course_dir)
		return {}

	var config_path = course_dir.path_join("course.json")
	var scene_path = course_dir.path_join("course.tscn")

	var new_hole_info: Dictionary = {}
	var current_x_offset: float = 0.0

	# 1. Build Hole Info metadata & copy aerial preview images
	for i in range(selected_holes.size()):
		var entry = selected_holes[i]
		var source_config_path: String = entry.get("source_config_path", "")
		var source_hole_key: String = entry.get("hole_key", "Hole 1")
		var source_hole_data: Dictionary = entry.get("hole_data", {})
		var source_dir = source_config_path.get_base_dir()

		var hole_number_str = "Hole " + str(i + 1)
		var par_val = source_hole_data.get("Par", 4)

		# Extract source pin & main tee position to calculate hole length & direction
		var orig_pin = source_hole_data.get("Hole Location", [300.0, 0.0])
		var pin_vec = Vector2(float(orig_pin[0]), float(orig_pin[1]))

		var orig_tees = source_hole_data.get("Tee Boxes", {})
		var default_tee_key = "Blue" if "Blue" in orig_tees else (orig_tees.keys()[0] if not orig_tees.is_empty() else "")
		var tee_vec = Vector2.ZERO
		if not default_tee_key.is_empty():
			var t_arr = orig_tees[default_tee_key]
			tee_vec = Vector2(float(t_arr[0]), float(t_arr[1]))

		var hole_length = max(pin_vec.distance_to(tee_vec), 60.0)
		var hole_dir = (pin_vec - tee_vec).normalized()
		if hole_dir.is_zero_approx():
			hole_dir = Vector2(1, 0)

		# Straight-line positions along X
		var new_pin = Vector2(current_x_offset + hole_length, 0.0)

		var new_tee_boxes: Dictionary = {}
		if typeof(orig_tees) == TYPE_DICTIONARY and not orig_tees.is_empty():
			for tee_color in orig_tees.keys():
				var t_arr = orig_tees[tee_color]
				var t_vec = Vector2(float(t_arr[0]), float(t_arr[1]))
				var rel = t_vec - tee_vec
				var dist_along = rel.dot(hole_dir)
				var dist_perp = rel.cross(hole_dir)
				new_tee_boxes[tee_color] = [current_x_offset + dist_along, dist_perp]
		else:
			new_tee_boxes["Blue"] = [current_x_offset, 0.0]
			new_tee_boxes["White"] = [current_x_offset + 15.0, 0.0]
			new_tee_boxes["Red"] = [current_x_offset + 30.0, 0.0]

		new_hole_info[hole_number_str] = {
			"Par": par_val,
			"Hole Location": [new_pin.x, new_pin.y],
			"Tee Boxes": new_tee_boxes,
			"Source": entry.get("source_title", "Course") + " - " + source_hole_key
		}

		# Preserve original dogleg HolePath if present
		var orig_path = source_hole_data.get("HolePath", [])
		if typeof(orig_path) == TYPE_ARRAY and orig_path.size() >= 2:
			var new_path: Array = []
			for pt in orig_path:
				var p_vec = Vector2(float(pt[0]), float(pt[1]))
				var rel2d = p_vec - tee_vec
				var rel3d = Vector3(rel2d.x, 0.0, rel2d.y)
				var rot3d = rel3d.rotated(Vector3.UP, -atan2(hole_dir.y, hole_dir.x))
				new_path.append([current_x_offset + rot3d.x, rot3d.z])
			new_hole_info[hole_number_str]["HolePath"] = new_path

		# Copy aerial preview image if present
		var source_hole_idx = int(str(source_hole_key).replace("Hole", "").strip_edges())
		var src_img_path = source_dir.path_join("aerial_hole_%d.png" % source_hole_idx)
		if FileAccess.file_exists(src_img_path):
			var dest_img_path = course_dir.path_join("aerial_hole_%d.png" % (i + 1))
			DirAccess.copy_absolute(src_img_path, dest_img_path)

		# Next hole starts right next to current hole (50ft buffer end + 5m gap + 50ft buffer start)
		current_x_offset += hole_length + (ROUGH_BUFFER_M * 2.0) + 5.0

	# 2. Serialize course.json
	var course_json_dict = {
		"scene_path": "course.tscn",
		"Title": title.strip_edges(),
		"is_custom": true,
		"Course Info": {
			"Tee Colors": ["Black", "Blue", "White", "Red"],
			"Texture Indices": {
				"Green": [0],
				"Fairway": [1],
				"Rough": [2],
				"Sand": [3],
				"Water": [4],
				"Penalty": [5]
			}
		},
		"Hole Info": new_hole_info
	}

	var json_file = FileAccess.open(config_path, FileAccess.WRITE)
	if json_file != null:
		json_file.store_string(JSON.stringify(course_json_dict, "\t"))
		json_file.close()

	# 3. Create 3D course.tscn scene by splicing ONLY the selected 3D hole nodes
	_build_and_save_course_scene(scene_path, new_hole_info, selected_holes)

	return {
		"title": title.strip_edges(),
		"scene_path": scene_path,
		"config_path": config_path,
		"is_custom": true
	}


static func _build_and_save_course_scene(scene_path: String, new_hole_info: Dictionary, selected_holes: Array[Dictionary]) -> void:
	var root = Node3D.new()
	root.name = "Range"
	root.set_script(load("res://Courses/Range/range.gd"))

	# Player
	var player_scene = load("res://Player/player.tscn")
	if player_scene != null:
		var player_inst = player_scene.instantiate()
		player_inst.name = "Player"
		root.add_child(player_inst)
		player_inst.owner = root

	# RangeUI
	var ui_scene = load("res://UI/range_ui.tscn")
	if ui_scene != null:
		var ui_inst = ui_scene.instantiate()
		ui_inst.name = "RangeUI"
		root.add_child(ui_inst)
		ui_inst.owner = root

	# Sky / Environment
	var sky_env = WorldEnvironment.new()
	sky_env.name = "Sky3D"
	sky_env.set_script(load("res://addons/sky_3d/src/Sky3D.gd"))
	root.add_child(sky_env)
	sky_env.owner = root

	var sun = DirectionalLight3D.new()
	sun.name = "SunLight"
	sun.rotation_degrees = Vector3(-45, 45, 0)
	sun.shadow_enabled = true
	sky_env.add_child(sun)
	sun.owner = root

	# PhantomCamera3D & Camera3D for Range camera follow systems
	var pcam = Node3D.new()
	pcam.name = "PhantomCamera3D"
	var pcam_script = load("res://addons/phantom_camera/scripts/phantom_camera/phantom_camera_3d.gd")
	if pcam_script != null:
		pcam.set_script(pcam_script)
	root.add_child(pcam)
	pcam.owner = root

	var cam3d = Camera3D.new()
	cam3d.name = "Camera3D"
	cam3d.fov = 55.0
	cam3d.far = 400.0
	root.add_child(cam3d)
	cam3d.owner = root

	var pcam_host = Node.new()
	pcam_host.name = "PhantomCameraHost"
	var pcam_host_script = load("res://addons/phantom_camera/scripts/phantom_camera_host/phantom_camera_host.gd")
	if pcam_host_script != null:
		pcam_host.set_script(pcam_host_script)
	cam3d.add_child(pcam_host)
	pcam_host.owner = root

	# Materials for terrain and pads
	var rough_mat = StandardMaterial3D.new()
	rough_mat.albedo_color = Color(0.18, 0.38, 0.15) # Deep rough green
	rough_mat.roughness = 0.9

	var fairway_mat = StandardMaterial3D.new()
	fairway_mat.albedo_color = Color(0.25, 0.58, 0.22)
	fairway_mat.roughness = 0.5

	var green_mat = StandardMaterial3D.new()
	green_mat.albedo_color = Color(0.20, 0.72, 0.32)
	green_mat.roughness = 0.3

	var tee_mat = StandardMaterial3D.new()
	tee_mat.albedo_color = Color(0.30, 0.60, 0.30)
	tee_mat.roughness = 0.4

	# System node names to skip duplicating from source scenes
	var ignored_names: Array[String] = [
		"Player", "RangeUI", "Sky3D", "SunLight", "MoonLight", "Skydome", "TimeOfDay",
		"Camera3D", "PhantomCamera3D", "SessionRecorder", "TCPServer", "YardMarkers", "CenterLine",
		"RoughMesh_Base", "RoughStatic_Base", "PreviewAerialCam"
	]

	# Process each selected hole
	var hole_keys = new_hole_info.keys()
	for i in range(selected_holes.size()):
		var h_key = hole_keys[i]
		var h_data = new_hole_info[h_key]

		var entry = selected_holes[i]
		var source_config_path: String = entry.get("source_config_path", "")
		var source_dir = source_config_path.get_base_dir()
		var source_scene_path = source_dir.path_join("course.tscn")
		if not FileAccess.file_exists(source_scene_path):
			source_scene_path = source_dir.path_join("course.scn")

		var source_hole_key: String = entry.get("hole_key", "Hole 1")
		var source_hole_data: Dictionary = entry.get("hole_data", {})

		# Load all hole data from source course config JSON to allow precise spatial isolation
		var all_source_holes: Dictionary = {}
		if FileAccess.file_exists(source_config_path):
			var src_cfg_file = FileAccess.open(source_config_path, FileAccess.READ)
			if src_cfg_file != null:
				var parsed = JSON.parse_string(src_cfg_file.get_as_text())
				if typeof(parsed) == TYPE_DICTIONARY:
					all_source_holes = parsed.get("Hole Info", {})

		var orig_pin = source_hole_data.get("Hole Location", [300.0, 0.0])
		var src_pin_vec = Vector3(float(orig_pin[0]), 0.0, float(orig_pin[1]))

		var orig_tees = source_hole_data.get("Tee Boxes", {})
		var default_tee_key = "Blue" if "Blue" in orig_tees else (orig_tees.keys()[0] if not orig_tees.is_empty() else "")
		var src_tee_vec = Vector3.ZERO
		if not default_tee_key.is_empty():
			var t_arr = orig_tees[default_tee_key]
			src_tee_vec = Vector3(float(t_arr[0]), 0.0, float(t_arr[1]))

		var src_dir = (src_pin_vec - src_tee_vec)
		src_dir.y = 0
		var src_length = max(src_dir.length(), 60.0)
		var src_angle = atan2(src_dir.z, src_dir.x) if not src_dir.is_zero_approx() else 0.0

		var target_pin_arr = h_data.get("Hole Location", [300.0, 0.0])
		var target_pin_pos = Vector3(float(target_pin_arr[0]), 0.0, float(target_pin_arr[1]))

		var tees_dict = h_data.get("Tee Boxes", {})
		var blue_arr = tees_dict.get("Blue", [0.0, 0.0])
		var target_tee_pos = Vector3(float(blue_arr[0]), 0.0, float(blue_arr[1]))

		var hole_node = Node3D.new()
		hole_node.name = str(h_key).replace(" ", "")
		root.add_child(hole_node)
		hole_node.owner = root

		var spliced_count = 0

		# 1. EXTRACT AND TRANSFORM EXCLUSIVE 3D MESHES/COLLIDERS FROM SOURCE OSM SCENE
		if ResourceLoader.exists(source_scene_path):
			var scn = load(source_scene_path) as PackedScene
			if scn != null:
				var src_inst = scn.instantiate()
				spliced_count = _collect_hole_nodes_smart(
					src_inst, source_hole_key, source_hole_data, all_source_holes,
					src_tee_vec, src_dir, src_angle, target_tee_pos, hole_node, root, ignored_names
				)
				src_inst.free()

		# 2. CONTINUOUS 50FT ROUGH BUFFER TERRAIN FOR THIS HOLE
		var x_min = min(target_tee_pos.x, target_pin_pos.x) - ROUGH_BUFFER_M # 50 ft behind tee
		var x_max = max(target_tee_pos.x, target_pin_pos.x) + ROUGH_BUFFER_M # 50 ft past pin
		var z_min = -35.0 - ROUGH_BUFFER_M # 50 ft extra shank room on Z-left
		var z_max = 35.0 + ROUGH_BUFFER_M  # 50 ft extra shank room on Z-right

		var rough_mesh = PlaneMesh.new()
		var width = x_max - x_min
		var depth = z_max - z_min
		rough_mesh.size = Vector2(width, depth)
		
		var rough_inst = MeshInstance3D.new()
		rough_inst.name = "RoughMesh_Buffer"
		rough_inst.mesh = rough_mesh
		rough_inst.material_override = rough_mat
		rough_inst.position = Vector3((x_min + x_max) / 2.0, -0.05, (z_min + z_max) / 2.0)
		hole_node.add_child(rough_inst)
		rough_inst.owner = root

		var rough_static = StaticBody3D.new()
		rough_static.name = "RoughStatic_Buffer"
		rough_static.set_meta("surface_type", 2) # SurfaceType.ROUGH
		rough_static.position = rough_inst.position

		var rough_col = CollisionShape3D.new()
		var rough_box = BoxShape3D.new()
		rough_box.size = Vector3(width, 0.1, depth)
		rough_col.shape = rough_box
		rough_static.add_child(rough_col)
		hole_node.add_child(rough_static)
		rough_static.owner = root
		rough_col.owner = root

		# 3. PROCEDURAL TERRAIN PADS (If source hole had no 3D surface meshes)
		if spliced_count == 0:
			# Fairway
			var fw_length = max(target_pin_pos.x - target_tee_pos.x - 15.0, 20.0)
			var fw_mesh = PlaneMesh.new()
			fw_mesh.size = Vector2(fw_length, 24.0)

			var fw_inst = MeshInstance3D.new()
			fw_inst.name = "FairwayMesh"
			fw_inst.mesh = fw_mesh
			fw_inst.material_override = fairway_mat
			fw_inst.position = Vector3(target_tee_pos.x + fw_length / 2.0, 0.0, 0.0)
			hole_node.add_child(fw_inst)
			fw_inst.owner = root

			var fw_static = StaticBody3D.new()
			fw_static.name = "FairwayStatic"
			fw_static.set_meta("surface_type", 0) # SurfaceType.FAIRWAY
			fw_static.position = fw_inst.position

			var fw_col = CollisionShape3D.new()
			var fw_box = BoxShape3D.new()
			fw_box.size = Vector3(fw_length, 0.1, 24.0)
			fw_col.shape = fw_box
			fw_static.add_child(fw_col)
			hole_node.add_child(fw_static)
			fw_static.owner = root
			fw_col.owner = root

			# Green
			var green_mesh = CylinderMesh.new()
			green_mesh.top_radius = 12.0
			green_mesh.bottom_radius = 12.0
			green_mesh.height = 0.06

			var green_inst = MeshInstance3D.new()
			green_inst.name = "GreenMesh"
			green_inst.mesh = green_mesh
			green_inst.material_override = green_mat
			green_inst.position = Vector3(target_pin_pos.x, 0.01, target_pin_pos.z)
			hole_node.add_child(green_inst)
			green_inst.owner = root

			var green_static = StaticBody3D.new()
			green_static.name = "GreenStatic"
			green_static.set_meta("surface_type", 4) # SurfaceType.GREEN
			green_static.position = green_inst.position

			var green_col = CollisionShape3D.new()
			var green_cylinder = CylinderShape3D.new()
			green_cylinder.radius = 12.0
			green_cylinder.height = 0.1
			green_col.shape = green_cylinder
			green_static.add_child(green_col)
			hole_node.add_child(green_static)
			green_static.owner = root
			green_col.owner = root

		# Always ensure Tee Pads and Flag Pin exist
		for tee_color in tees_dict.keys():
			var t_arr = tees_dict[tee_color]
			var t_pos = Vector3(float(t_arr[0]), 0.02, float(t_arr[1]))

			var tee_mesh = PlaneMesh.new()
			tee_mesh.size = Vector2(4.0, 4.0)

			var tee_inst = MeshInstance3D.new()
			tee_inst.name = "TeePad_" + tee_color
			tee_inst.mesh = tee_mesh
			tee_inst.material_override = tee_mat
			tee_inst.position = t_pos
			hole_node.add_child(tee_inst)
			tee_inst.owner = root

			var tee_static = StaticBody3D.new()
			tee_static.name = "TeeStatic_" + tee_color
			tee_static.set_meta("surface_type", 3) # SurfaceType.TEE
			tee_static.position = t_pos

			var tee_col = CollisionShape3D.new()
			var tee_box = BoxShape3D.new()
			tee_box.size = Vector3(4.0, 0.1, 4.0)
			tee_col.shape = tee_box
			tee_static.add_child(tee_col)
			hole_node.add_child(tee_static)
			tee_static.owner = root
			tee_col.owner = root

		# Flag Pin
		var flag_node = Node3D.new()
		flag_node.name = "PinFlag"
		flag_node.position = Vector3(target_pin_pos.x, 0.0, target_pin_pos.z)

		var pole = MeshInstance3D.new()
		pole.name = "Pole"
		var pole_mesh = CylinderMesh.new()
		pole_mesh.top_radius = 0.03
		pole_mesh.bottom_radius = 0.03
		pole_mesh.height = 2.4
		pole.mesh = pole_mesh
		pole.position = Vector3(0, 1.2, 0)
		flag_node.add_child(pole)
		pole.owner = root

		var flag = MeshInstance3D.new()
		flag.name = "Flag"
		var flag_mesh = PrismMesh.new()
		flag_mesh.size = Vector3(0.5, 0.4, 0.02)
		flag.mesh = flag_mesh
		flag.position = Vector3(0.25, 2.1, 0)
		flag.rotation_degrees = Vector3(0, 0, -90)
		var flag_mat = StandardMaterial3D.new()
		flag_mat.albedo_color = Color.RED
		flag.material_override = flag_mat
		flag_node.add_child(flag)
		flag.owner = root

		hole_node.add_child(flag_node)
		flag_node.owner = root

	# Save PackedScene to disk
	var packed = PackedScene.new()
	var pack_err = packed.pack(root)
	if pack_err != OK:
		push_error("[CustomCourseBuilder] Failed to pack custom course root node. Error: " + str(pack_err))
	else:
		var save_err = ResourceSaver.save(packed, scene_path)
		if save_err != OK:
			push_error("[CustomCourseBuilder] Failed to save custom course scene to: " + scene_path + ". Error: " + str(save_err))
		else:
			print("[CustomCourseBuilder] Successfully created custom 3D course scene at: " + scene_path)


static func _collect_hole_nodes_smart(
	src_inst: Node,
	source_hole_key: String,
	source_hole_data: Dictionary,
	all_source_holes: Dictionary,
	src_tee_vec: Vector3,
	src_dir: Vector3,
	src_angle: float,
	target_tee_pos: Vector3,
	hole_node: Node3D,
	root: Node3D,
	ignored_names: Array[String]
) -> int:
	var spliced_count = 0
	var candidate_nodes: Array[Node3D] = []
	_find_candidate_3d_nodes(src_inst, candidate_nodes, ignored_names)

	var target_num_str = source_hole_key.to_lower().replace("hole", "").strip_edges()

	for node in candidate_nodes:
		var name_lower = node.name.to_lower()
		var is_match = false

		# 1. Check explicit hole name match
		if name_lower.contains("hole"):
			if name_lower.contains(source_hole_key.to_lower()) or (not target_num_str.is_empty() and (name_lower.contains("hole_" + target_num_str) or name_lower.contains("hole" + target_num_str))):
				is_match = true
			else:
				continue

		# 2. Check spatial corridor match if not explicitly matched
		if not is_match:
			var node_pos = node.global_position
			var dist_target = _get_distance_to_hole_info(node_pos, source_hole_data)

			# Must be within 55 meters of this hole's corridor
			if dist_target <= 55.0:
				var is_closest = true
				for other_key in all_source_holes.keys():
					if other_key == source_hole_key:
						continue
					var other_data = all_source_holes[other_key]
					var dist_other = _get_distance_to_hole_info(node_pos, other_data)
					if dist_other < dist_target - 0.5:
						is_closest = false
						break
				if is_closest:
					is_match = true

		if is_match:
			var dup = node.duplicate()
			var rel_vec = node.global_position - src_tee_vec
			var rot_vec = rel_vec.rotated(Vector3.UP, -src_angle)
			dup.position = target_tee_pos + rot_vec
			dup.rotation.y = node.rotation.y - src_angle

			hole_node.add_child(dup)
			_set_owner_recursive(dup, root)
			spliced_count += 1

	return spliced_count


static func _find_candidate_3d_nodes(node: Node, candidates: Array[Node3D], ignored_names: Array[String]) -> void:
	if ignored_names.has(node.name):
		return

	var name_lower = node.name.to_lower()
	var is_global_container = (name_lower == "range" or name_lower == "world" or name_lower == "terrain" or name_lower == "ground" or name_lower == "course" or name_lower == "root" or name_lower.begins_with("groundmesh") or name_lower == "yardmarkers" or name_lower == "centerline")
	if is_global_container:
		for child in node.get_children():
			_find_candidate_3d_nodes(child, candidates, ignored_names)
		return

	if node is Node3D:
		if node is MeshInstance3D or node is StaticBody3D or node is Decal or node is MultiMeshInstance3D or node is CSGShape3D or name_lower.contains("hole") or name_lower.contains("tree") or name_lower.contains("bush") or name_lower.contains("bunker") or name_lower.contains("water") or name_lower.contains("fairway") or name_lower.contains("green") or name_lower.contains("pin") or name_lower.contains("flag"):
			candidates.append(node as Node3D)
			return

	for child in node.get_children():
		_find_candidate_3d_nodes(child, candidates, ignored_names)


static func _get_distance_to_hole_info(node_pos: Vector3, h_data: Dictionary) -> float:
	var p2d = Vector2(node_pos.x, node_pos.z)
	var path_arr = h_data.get("HolePath", [])
	if typeof(path_arr) == TYPE_ARRAY and path_arr.size() >= 2:
		var min_dist = 999999.0
		for i in range(path_arr.size() - 1):
			var a = Vector2(float(path_arr[i][0]), float(path_arr[i][1]))
			var b = Vector2(float(path_arr[i + 1][0]), float(path_arr[i + 1][1]))
			var d = _dist_to_segment_2d(p2d, a, b)
			if d < min_dist:
				min_dist = d
		return min_dist

	var orig_pin = h_data.get("Hole Location", [300.0, 0.0])
	var pin_vec = Vector2(float(orig_pin[0]), float(orig_pin[1]))

	var orig_tees = h_data.get("Tee Boxes", {})
	var tee_vec = Vector2.ZERO
	if typeof(orig_tees) == TYPE_DICTIONARY and not orig_tees.is_empty():
		var default_key = "Blue" if "Blue" in orig_tees else orig_tees.keys()[0]
		var t_arr = orig_tees[default_key]
		tee_vec = Vector2(float(t_arr[0]), float(t_arr[1]))

	return _dist_to_segment_2d(p2d, tee_vec, pin_vec)


static func _dist_to_segment_2d(pt: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	if ab.is_zero_approx():
		return pt.distance_to(a)
	var t = clamp((pt - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	var proj = a + ab * t
	return pt.distance_to(proj)


static func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	if node != new_owner and node.get_parent() != null:
		node.owner = new_owner
	for child in node.get_children():
		_set_owner_recursive(child, new_owner)
