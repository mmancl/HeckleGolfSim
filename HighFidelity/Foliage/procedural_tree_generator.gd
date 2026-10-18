extends RefCounted
class_name ProceduralTreeGenerator

## ProceduralTreeGenerator
## 1. Converts thousands of individual Tree_*, Bush_*, and Rock_* StaticBody3D/MeshInstance3D nodes
##    into spatial-chunked MultiMeshInstance3D batches with Lush Summer Parkland INSTANCE_CUSTOM
##    chlorophyll variation and consolidated Jolt compound collision bodies.
## 2. Generates procedural volumetric summer leaf cluster sub-canopies & shoreline reed meshes.

const CHUNK_SIZE_M: float = 160.0

## Lush Summer Parkland species color palette (RGB multiplier + alpha wind seed)
## Matches Warwick Hills summer foliage: emerald oaks, sunlit olive/lime crowns,
## weeping willows near water, silver birches, and deep forest pines.
static func get_lush_summer_instance_color(world_pos: Vector3, near_water: bool = false) -> Color:
	var h1 := fposmod(sin(world_pos.x * 12.9898 + world_pos.z * 78.233) * 43758.5453, 1.0)
	var h2 := fposmod(sin(world_pos.x * 39.346 + world_pos.z * 11.135) * 24634.6345, 1.0)
	var wind_seed := clampf(0.05 + h2 * 0.94, 0.05, 0.99)

	if near_water and h1 < 0.55:
		# Shoreline Weeping Willow / Lush Water-Edge Olive-Lime
		var willow := Color(0.88, 1.08, 0.78).lerp(Color(0.96, 1.12, 0.82), h2)
		return Color(willow.r, willow.g, willow.b, wind_seed)

	if h1 < 0.50:
		# Rich Summer Emerald Oak (50%)
		var oak := Color(0.80, 0.98, 0.76).lerp(Color(0.88, 1.04, 0.82), h2)
		return Color(oak.r, oak.g, oak.b, wind_seed)
	elif h1 < 0.75:
		# Sunlit Olive / Warm Lime Deciduous Crown (25%)
		var olive := Color(0.94, 1.05, 0.75).lerp(Color(1.02, 1.08, 0.80), h2)
		return Color(olive.r, olive.g, olive.b, wind_seed)
	elif h1 < 0.85:
		# Parkland Weeping Willow / Bright Summer Maple (10%)
		var maple := Color(0.86, 1.06, 0.78).lerp(Color(0.92, 1.10, 0.84), h2)
		return Color(maple.r, maple.g, maple.b, wind_seed)
	elif h1 < 0.93:
		# Silver Birch Bright Summer Canopy (8%)
		var birch := Color(0.90, 1.04, 0.84).lerp(Color(0.98, 1.07, 0.88), h2)
		return Color(birch.r, birch.g, birch.b, wind_seed)
	else:
		# Deep Forest Pine / Spruce (7%)
		var pine := Color(0.66, 0.86, 0.68).lerp(Color(0.74, 0.92, 0.74), h2)
		return Color(pine.r, pine.g, pine.b, wind_seed)


## Creates a procedural clumped 3D shoreline reed / marsh grass mesh for pond banks.
static func create_shoreline_reed_cluster_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var num_stalks := 14

	for i in range(num_stalks):
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(0.0, 0.55)
		var base := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var stalk_dir := rng.randf_range(0.0, TAU)
		var lean := rng.randf_range(0.08, 0.28)
		var h := rng.randf_range(0.65, 1.25)
		var w := rng.randf_range(0.032, 0.052)

		var fwd := Vector3(cos(stalk_dir), 0.0, sin(stalk_dir))
		var right := Vector3(-fwd.z, 0.0, fwd.x) * (w * 0.5)

		var p0 := base
		var p1 := base + Vector3(0.0, h * 0.5, 0.0) + fwd * (lean * 0.4)
		var p2 := base + Vector3(0.0, h, 0.0) + fwd * lean

		var n := (-fwd + Vector3(0.0, 0.65, 0.0)).normalized()

		# Lower segment
		st.set_normal(n)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(p0 - right)
		st.set_normal(n)
		st.set_uv(Vector2(1.0, 1.0))
		st.add_vertex(p0 + right)
		st.set_normal(n)
		st.set_uv(Vector2(0.85, 0.5))
		st.add_vertex(p1 + right * 0.7)

		st.set_normal(n)
		st.set_uv(Vector2(0.0, 1.0))
		st.add_vertex(p0 - right)
		st.set_normal(n)
		st.set_uv(Vector2(0.85, 0.5))
		st.add_vertex(p1 + right * 0.7)
		st.set_normal(n)
		st.set_uv(Vector2(0.15, 0.5))
		st.add_vertex(p1 - right * 0.7)

		# Upper segment tapering to tip
		st.set_normal(n)
		st.set_uv(Vector2(0.15, 0.5))
		st.add_vertex(p1 - right * 0.7)
		st.set_normal(n)
		st.set_uv(Vector2(0.85, 0.5))
		st.add_vertex(p1 + right * 0.7)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.0))
		st.add_vertex(p2)

	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	if ResourceLoader.exists("res://Courses/Environments/shaders/grass_blades_high.gdshader"):
		mat.shader = load("res://Courses/Environments/shaders/grass_blades_high.gdshader") as Shader
		mat.set_shader_parameter("root_color", Color(0.16, 0.28, 0.12))
		mat.set_shader_parameter("tip_color", Color(0.42, 0.58, 0.26))
		mat.set_shader_parameter("dry_tip_color", Color(0.62, 0.54, 0.32))
		mat.set_shader_parameter("dry_tip_ratio", 0.35)
		mat.set_shader_parameter("max_render_distance", 160.0)
		mat.set_shader_parameter("fade_start_distance", 115.0)
	mesh.surface_set_material(0, mat)
	return mesh


## Converts individual Tree_*, Bush_*, and Rock_* nodes in `scene_root` into spatial-chunked
## MultiMeshInstance3D nodes and consolidated Jolt compound collision bodies.
## Safe to run both at runtime and during persistent `.tscn` migration in CourseGraphicsUpgrader.
static func convert_scene_foliage_to_multimesh(scene_root: Node, persist_for_save: bool = false) -> Dictionary:
	var stats := {
		"trees_converted": 0,
		"bushes_converted": 0,
		"rocks_converted": 0,
		"chunks_created": 0
	}
	if scene_root == null:
		return stats

	# Avoid double-conversion if already converted
	if scene_root.get_node_or_null("MultiMeshFoliageContainer") != null:
		return stats

	var tree_nodes: Array[Node3D] = []
	var bush_nodes: Array[Node3D] = []
	var rock_nodes: Array[Node3D] = []
	var water_positions: Array[Vector2] = []

	# Search scene root plus any Hole* containers (custom multi-hole courses)
	var search_roots: Array[Node] = [scene_root]
	for child in scene_root.get_children():
		if child is Node3D and child.name.begins_with("Hole"):
			search_roots.append(child)
	for search_root in search_roots:
		for child in search_root.get_children():
			if not (child is Node3D):
				continue
			var cname := child.name
			if cname.begins_with("Tree_"):
				tree_nodes.append(child as Node3D)
			elif cname.begins_with("Bush_"):
				bush_nodes.append(child as Node3D)
			elif cname.begins_with("Rock_"):
				rock_nodes.append(child as Node3D)
			elif cname.to_lower().begins_with("water") and child is MeshInstance3D:
				var mi := child as MeshInstance3D
				if mi.mesh != null:
					var aabb := mi.mesh.get_aabb()
					var center := mi.transform * aabb.get_center()
					water_positions.append(Vector2(center.x, center.z))

	if tree_nodes.is_empty() and bush_nodes.is_empty() and rock_nodes.is_empty():
		return stats

	var mm_container := Node3D.new()
	mm_container.name = "MultiMeshFoliageContainer"
	scene_root.add_child(mm_container)
	if persist_for_save:
		mm_container.owner = scene_root

	var static_col_body := StaticBody3D.new()
	static_col_body.name = "ConsolidatedFoliageCollision"
	static_col_body.collision_layer = 1
	static_col_body.collision_mask = 0
	static_col_body.set_meta("is_tree", true)
	scene_root.add_child(static_col_body)
	if persist_for_save:
		static_col_body.owner = scene_root

	var canopy_area := Area3D.new()
	canopy_area.name = "ConsolidatedCanopyArea"
	canopy_area.collision_layer = 1
	canopy_area.collision_mask = 0
	canopy_area.monitoring = false
	canopy_area.monitorable = true
	canopy_area.set_meta("is_canopy", true)
	canopy_area.add_to_group("tree_canopy", true)
	scene_root.add_child(canopy_area)
	if persist_for_save:
		canopy_area.owner = scene_root

	# Shared collision shapes (eliminates thousands of duplicate shape allocations!)
	var shared_trunk_shape := CapsuleShape3D.new()
	shared_trunk_shape.radius = 0.15
	shared_trunk_shape.height = 1.0

	var shared_canopy_shape := SphereShape3D.new()
	shared_canopy_shape.radius = 2.0

	var shared_rock_shape := SphereShape3D.new()
	shared_rock_shape.radius = 0.55

	# Compact metadata array of [x, y, z, scale_x, scale_y, scale_z, rot_y, mesh_idx] for CustomCourseBuilder
	var tree_meta_records: PackedFloat32Array = PackedFloat32Array()

	# Group visual instances by (category_mesh_key, chunk_x, chunk_z)
	var chunk_buckets: Dictionary = {}
	var mesh_lookup: Dictionary = {}
	var category_lookup: Dictionary = {}

	# 1. Process Trees
	for t_node in tree_nodes:
		var mi := _find_first_mesh_instance(t_node)
		if mi == null or mi.mesh == null:
			continue
		var global_xf := t_node.transform * mi.transform
		var pos := t_node.position

		var m_path := mi.mesh.resource_path
		if m_path.is_empty():
			m_path = "tree_mesh_" + str(mi.mesh.get_rid().get_id())
		var key := "Tree__" + m_path
		if not mesh_lookup.has(key):
			mesh_lookup[key] = _duplicate_mesh_with_materials(mi)
			category_lookup[key] = "Tree"

		var cx := int(floor(pos.x / CHUNK_SIZE_M))
		var cz := int(floor(pos.z / CHUNK_SIZE_M))
		var bucket_key := "%s__%d_%d" % [key, cx, cz]
		if not chunk_buckets.has(bucket_key):
			chunk_buckets[bucket_key] = {
				"mesh_key": key,
				"transforms": [],
				"colors": []
			}

		var near_water := false
		var pos2d := Vector2(pos.x, pos.z)
		for wp in water_positions:
			if pos2d.distance_squared_to(wp) < 2500.0: # Within 50m of pond center
				near_water = true
				break

		chunk_buckets[bucket_key]["transforms"].append(global_xf)
		chunk_buckets[bucket_key]["colors"].append(get_lush_summer_instance_color(pos, near_water))

		# Add trunk collider to consolidated StaticBody3D
		var trunk_col := CollisionShape3D.new()
		trunk_col.shape = shared_trunk_shape
		trunk_col.position = pos + Vector3(0.0, 0.5 * t_node.scale.y, 0.0)
		trunk_col.scale = t_node.scale
		static_col_body.add_child(trunk_col)
		if persist_for_save:
			trunk_col.owner = scene_root

		# Add canopy collider to consolidated Area3D
		var canopy_col := CollisionShape3D.new()
		canopy_col.shape = shared_canopy_shape
		canopy_col.position = pos + Vector3(0.0, 3.2 * t_node.scale.y, 0.0)
		canopy_col.scale = t_node.scale
		canopy_area.add_child(canopy_col)
		if persist_for_save:
			canopy_col.owner = scene_root

		# Record metadata for CustomCourseBuilder hole extraction
		var m_idx := 0
		if m_path.contains("tree-02"):
			m_idx = 1
		elif m_path.contains("tree-03"):
			m_idx = 2
		tree_meta_records.append(pos.x)
		tree_meta_records.append(pos.y)
		tree_meta_records.append(pos.z)
		tree_meta_records.append(t_node.scale.x)
		tree_meta_records.append(t_node.scale.y)
		tree_meta_records.append(t_node.scale.z)
		tree_meta_records.append(t_node.rotation.y)
		tree_meta_records.append(float(m_idx))

		t_node.get_parent().remove_child(t_node)
		t_node.free()
		stats["trees_converted"] += 1

	# 2. Process Bushes (Visual MultiMesh only — removing 2,400 tiny bush physics bodies saves massive CPU/Jolt broadphase time)
	for b_node in bush_nodes:
		var mi := _find_first_mesh_instance(b_node)
		if mi == null or mi.mesh == null:
			continue
		var global_xf := b_node.transform * mi.transform
		var pos := b_node.position

		var m_path := mi.mesh.resource_path
		if m_path.is_empty():
			m_path = "bush_mesh_" + str(mi.mesh.get_rid().get_id())
		var key := "Bush__" + m_path
		if not mesh_lookup.has(key):
			mesh_lookup[key] = _duplicate_mesh_with_materials(mi)
			category_lookup[key] = "Bush"

		var cx := int(floor(pos.x / CHUNK_SIZE_M))
		var cz := int(floor(pos.z / CHUNK_SIZE_M))
		var bucket_key := "%s__%d_%d" % [key, cx, cz]
		if not chunk_buckets.has(bucket_key):
			chunk_buckets[bucket_key] = {
				"mesh_key": key,
				"transforms": [],
				"colors": []
			}

		chunk_buckets[bucket_key]["transforms"].append(global_xf)
		chunk_buckets[bucket_key]["colors"].append(get_lush_summer_instance_color(pos, false))

		b_node.get_parent().remove_child(b_node)
		b_node.free()
		stats["bushes_converted"] += 1

	# 3. Process Water-Perimeter Rocks
	for r_node in rock_nodes:
		var mi := _find_first_mesh_instance(r_node)
		if mi == null or mi.mesh == null:
			continue
		var global_xf := r_node.transform * mi.transform
		var pos := r_node.position

		var m_path := mi.mesh.resource_path
		if m_path.is_empty():
			m_path = "rock_mesh_" + str(mi.mesh.get_rid().get_id())
		var key := "Rock__" + m_path
		if not mesh_lookup.has(key):
			mesh_lookup[key] = _duplicate_mesh_with_materials(mi)
			category_lookup[key] = "Rock"

		var cx := int(floor(pos.x / CHUNK_SIZE_M))
		var cz := int(floor(pos.z / CHUNK_SIZE_M))
		var bucket_key := "%s__%d_%d" % [key, cx, cz]
		if not chunk_buckets.has(bucket_key):
			chunk_buckets[bucket_key] = {
				"mesh_key": key,
				"transforms": [],
				"colors": []
			}

		chunk_buckets[bucket_key]["transforms"].append(global_xf)
		chunk_buckets[bucket_key]["colors"].append(Color(1.0, 1.0, 1.0, 1.0))

		var rock_col := CollisionShape3D.new()
		rock_col.shape = shared_rock_shape
		rock_col.transform = global_xf
		static_col_body.add_child(rock_col)
		if persist_for_save:
			rock_col.owner = scene_root

		r_node.get_parent().remove_child(r_node)
		r_node.free()
		stats["rocks_converted"] += 1

	# 4. Instantiate Spatial MultiMeshInstance3D Chunks
	var chunk_idx := 0
	for bucket_key in chunk_buckets.keys():
		var bucket: Dictionary = chunk_buckets[bucket_key]
		var xforms: Array = bucket["transforms"]
		var cols: Array = bucket["colors"]
		var count := xforms.size()
		if count == 0:
			continue

		var m_key: String = bucket["mesh_key"]
		var cat: String = category_lookup.get(m_key, "Tree")
		var base_mesh: Mesh = mesh_lookup[m_key]

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = base_mesh.duplicate() as Mesh
		mm.instance_count = count

		for i in range(count):
			mm.set_instance_transform(i, xforms[i])
			mm.set_instance_custom_data(i, cols[i])

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%sChunk_%d" % [cat, chunk_idx]
		mmi.multimesh = mm

		if cat == "Tree":
			mmi.visibility_range_end = 500.0
			mmi.visibility_range_end_margin = 35.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elif cat == "Bush":
			mmi.visibility_range_end = 220.0
			mmi.visibility_range_end_margin = 25.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mmi.visibility_range_end = 240.0
			mmi.visibility_range_end_margin = 20.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		mm_container.add_child(mmi)
		if persist_for_save:
			mmi.owner = scene_root
		chunk_idx += 1

	mm_container.set_meta("tree_records", tree_meta_records)
	stats["chunks_created"] = chunk_idx
	return stats


static func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_first_mesh_instance(child)
		if found != null:
			return found
	return null


static func _duplicate_mesh_with_materials(mi: MeshInstance3D) -> Mesh:
	var dup := mi.mesh.duplicate() as Mesh
	for s in range(dup.get_surface_count()):
		var override_m := mi.get_surface_override_material(s)
		if override_m != null:
			dup.surface_set_material(s, override_m)
	return dup
