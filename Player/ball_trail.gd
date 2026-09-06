extends MeshInstance3D

const MIN_ANCHOR_DISTANCE : float = 1.25
const MIN_ANCHOR_DISTANCE_SQ : float = 1.5625  # 1.25 * 1.25
const MAX_POINTS : int = 600

var points : Array = []
var color : Color = Color(0.6, 0.0, 0.0, 1.0)  # Darker red
var dark_red : Color = Color(0.6, 0.0, 0.0, 1.0)
var orange : Color = Color(1.0, 0.4, 0.0, 1.0)
var yellow : Color = Color(1.0, 0.9, 0.0, 1.0)
var line_width : float = 0.08
var material : StandardMaterial3D = StandardMaterial3D.new()

var _mesh_dirty: bool = false
var peak_index : int = 0
var max_peak_y : float = -999999.0
var is_active : bool = false


func _ready():
	mesh = ArrayMesh.new()
	material_override = material

	# Setup material with subtle glow using vertex colors
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_receive_shadows = true
	material.no_depth_test = false


func _process(_delta: float) -> void:
	if _mesh_dirty:
		draw()
		_mesh_dirty = false


func setColor(a):
	color = a
	dark_red = a
	_mesh_dirty = true


func draw():
	var arr_mesh := mesh as ArrayMesh
	if arr_mesh == null:
		return
	arr_mesh.clear_surfaces()
	if points.size() >= 2:
		create_ribbon_mesh()


func _get_point_color(i: int, total_points: int, peak_idx: int) -> Color:
	var point_color : Color
	if i <= peak_idx:
		var factor := 0.0
		if peak_idx > 0:
			factor = float(i) / float(peak_idx)
		if factor <= 0.5:
			point_color = dark_red
		else:
			var sub_factor := (factor - 0.5) / 0.5
			point_color = dark_red.lerp(orange, sub_factor)
	else:
		var factor := 0.0
		var denom := float(total_points - 1 - peak_idx)
		if denom > 0.0:
			factor = float(i - peak_idx) / denom
		if factor <= 0.5:
			var sub_factor := factor / 0.5
			point_color = orange.lerp(yellow, sub_factor)
		else:
			point_color = yellow

	var alpha : float = 1.0
	# Softly fade the first few points at the tee box, keeping the leading tip at the ball 100% solid
	if i < 3 and total_points > 6:
		alpha = float(i + 1) / 4.0

	return Color(point_color.r * 1.5, point_color.g * 1.5, point_color.b * 1.5, alpha)


func create_ribbon_mesh():
	var arr_mesh := mesh as ArrayMesh
	if arr_mesh == null or points.size() < 2:
		return

	var total_points := points.size()
	var half_width : float = line_width * 0.5
	var prev_right := Vector3.ZERO
	var prev_up := Vector3.ZERO

	var num_verts := total_points * 4
	var num_indices := (total_points - 1) * 12

	var verts := PackedVector3Array()
	verts.resize(num_verts)
	var colors := PackedColorArray()
	colors.resize(num_verts)
	var uvs := PackedVector2Array()
	uvs.resize(num_verts)
	var indices := PackedInt32Array()
	indices.resize(num_indices)

	var idx_ptr := 0

	for i in range(total_points):
		var point : Vector3 = points[i]

		# Tangent / forward direction along path using central difference
		var forward := Vector3.ZERO
		if i < total_points - 1 and i > 0:
			forward = (points[i + 1] - points[i - 1]).normalized()
		elif i < total_points - 1:
			forward = (points[i + 1] - point).normalized()
		elif i > 0:
			forward = (point - points[i - 1]).normalized()
		else:
			forward = Vector3.FORWARD
		if forward.length_squared() < 0.0001:
			forward = Vector3.FORWARD

		# Horizontal perpendicular vector
		var world_up := Vector3.UP
		var right := forward.cross(world_up)
		if right.length_squared() < 0.001:
			right = Vector3.RIGHT if absf(forward.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
		else:
			right = right.normalized()

		if prev_right.length_squared() > 0.01 and right.dot(prev_right) < 0.0:
			right = -right
		prev_right = right

		# Vertical perpendicular vector
		var up := right.cross(forward)
		if up.length_squared() < 0.001:
			up = world_up
		else:
			up = up.normalized()

		if prev_up.length_squared() > 0.01 and up.dot(prev_up) < 0.0:
			up = -up
		prev_up = up

		var t := float(i) / float(total_points - 1)
		var curr_col := _get_point_color(i, total_points, peak_index)

		var base_vert := i * 4
		# 0: Horizontal Left, 1: Horizontal Right, 2: Vertical Bottom, 3: Vertical Top
		verts[base_vert + 0] = point - right * half_width
		verts[base_vert + 1] = point + right * half_width
		verts[base_vert + 2] = point - up * half_width
		verts[base_vert + 3] = point + up * half_width

		colors[base_vert + 0] = curr_col
		colors[base_vert + 1] = curr_col
		colors[base_vert + 2] = curr_col
		colors[base_vert + 3] = curr_col

		uvs[base_vert + 0] = Vector2(0.0, t)
		uvs[base_vert + 1] = Vector2(1.0, t)
		uvs[base_vert + 2] = Vector2(0.0, t)
		uvs[base_vert + 3] = Vector2(1.0, t)

		if i > 0:
			var prev_base := (i - 1) * 4
			var curr_base := base_vert

			# Ribbon 1 (Horizontal)
			indices[idx_ptr + 0] = curr_base + 0
			indices[idx_ptr + 1] = prev_base + 0
			indices[idx_ptr + 2] = prev_base + 1

			indices[idx_ptr + 3] = prev_base + 1
			indices[idx_ptr + 4] = curr_base + 1
			indices[idx_ptr + 5] = curr_base + 0

			# Ribbon 2 (Vertical)
			indices[idx_ptr + 6] = curr_base + 2
			indices[idx_ptr + 7] = prev_base + 2
			indices[idx_ptr + 8] = prev_base + 3

			indices[idx_ptr + 9] = prev_base + 3
			indices[idx_ptr + 10] = curr_base + 3
			indices[idx_ptr + 11] = curr_base + 2

			idx_ptr += 12

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func start_trail(start_pos: Vector3) -> void:
	clear_points()
	points.append(start_pos)
	is_active = true
	max_peak_y = start_pos.y
	peak_index = 0
	_mesh_dirty = false


func update_trail(current_pos: Vector3) -> void:
	if points.is_empty():
		points.append(current_pos)
		max_peak_y = current_pos.y
		peak_index = 0
		return

	if points.size() == 1:
		if points[0].distance_squared_to(current_pos) > 0.0001:
			points.append(current_pos)
			if current_pos.y > max_peak_y:
				max_peak_y = current_pos.y
				peak_index = 1
			_mesh_dirty = true
		return

	# If the ball hasn't moved significantly, avoid unnecessary redraws
	if points[-1].distance_squared_to(current_pos) < 0.00001:
		return

	var last_anchor : Vector3 = points[points.size() - 2]
	if last_anchor.distance_squared_to(current_pos) >= MIN_ANCHOR_DISTANCE_SQ and points.size() < MAX_POINTS:
		points.append(current_pos)
	else:
		points[points.size() - 1] = current_pos

	if current_pos.y > max_peak_y:
		max_peak_y = current_pos.y
		peak_index = points.size() - 1

	_mesh_dirty = true


func finalize_trail() -> void:
	is_active = false
	if _mesh_dirty:
		draw()
		_mesh_dirty = false


func add_point(point: Vector3) -> void:
	update_trail(point)


func clear_points() -> void:
	points.clear()
	peak_index = 0
	max_peak_y = -999999.0
	is_active = false
	if mesh != null:
		var arr_mesh := mesh as ArrayMesh
		if arr_mesh != null:
			arr_mesh.clear_surfaces()
	_mesh_dirty = false



