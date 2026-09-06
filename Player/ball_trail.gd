extends MeshInstance3D

const MIN_ANCHOR_DISTANCE : float = 0.65
const MIN_ANCHOR_DISTANCE_SQ : float = 0.4225  # 0.65 * 0.65
const MAX_POINTS : int = 1500

var points : Array = []
var color : Color = Color(0.6, 0.0, 0.0, 1.0)  # Darker red
var dark_red : Color = Color(0.6, 0.0, 0.0, 1.0)
var orange : Color = Color(1.0, 0.4, 0.0, 1.0)
var yellow : Color = Color(1.0, 0.9, 0.0, 1.0)
var line_width : float = 0.08
var material : StandardMaterial3D = StandardMaterial3D.new()

var _mesh_dirty: bool = true
var peak_index : int = 0
var max_peak_y : float = -999999.0
var is_active : bool = false


func _ready():
	mesh = ImmediateMesh.new()
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
	var imm := mesh as ImmediateMesh
	if imm == null:
		return
	imm.clear_surfaces()
	if points.size() >= 2:
		create_ribbon_mesh()


func _get_point_color(i: int, total_points: int, peak_index: int) -> Color:
	var point_color : Color
	if i <= peak_index:
		var factor := 0.0
		if peak_index > 0:
			factor = float(i) / float(peak_index)
		if factor <= 0.5:
			point_color = dark_red
		else:
			var sub_factor := (factor - 0.5) / 0.5
			point_color = dark_red.lerp(orange, sub_factor)
	else:
		var factor := 0.0
		var denom := float(total_points - 1 - peak_index)
		if denom > 0.0:
			factor = float(i - peak_index) / denom
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
	var imm := mesh as ImmediateMesh
	if imm == null or points.size() < 2:
		return

	var total_points := points.size()
	var half_width : float = line_width * 0.5
	var prev_right := Vector3.ZERO
	var prev_up := Vector3.ZERO

	# Previous frame vertex data for connecting triangle strips
	var prev_h_left := Vector3.ZERO
	var prev_h_right := Vector3.ZERO
	var prev_v_bot := Vector3.ZERO
	var prev_v_top := Vector3.ZERO
	var prev_uv_l := Vector2.ZERO
	var prev_uv_r := Vector2.ZERO
	var prev_col := Color.WHITE

	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)

	for i in range(total_points):
		var point : Vector3 = points[i]

		# Get tangent / forward direction along path using central difference
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
		var curr_uv_l := Vector2(0.0, t)
		var curr_uv_r := Vector2(1.0, t)
		var curr_col := _get_point_color(i, total_points, peak_index)

		var curr_h_left := point - right * half_width
		var curr_h_right := point + right * half_width
		var curr_v_bot := point - up * half_width
		var curr_v_top := point + up * half_width

		if i > 0:
			# Ribbon 1 (Horizontal) - Triangle 1
			imm.surface_set_color(curr_col)
			imm.surface_set_uv(curr_uv_l)
			imm.surface_add_vertex(curr_h_left)

			imm.surface_set_color(prev_col)
			imm.surface_set_uv(prev_uv_l)
			imm.surface_add_vertex(prev_h_left)

			imm.surface_set_color(prev_col)
			imm.surface_set_uv(prev_uv_r)
			imm.surface_add_vertex(prev_h_right)

			# Ribbon 1 (Horizontal) - Triangle 2
			imm.surface_set_color(prev_col)
			imm.surface_set_uv(prev_uv_r)
			imm.surface_add_vertex(prev_h_right)

			imm.surface_set_color(curr_col)
			imm.surface_set_uv(curr_uv_r)
			imm.surface_add_vertex(curr_h_right)

			imm.surface_set_color(curr_col)
			imm.surface_set_uv(curr_uv_l)
			imm.surface_add_vertex(curr_h_left)

			# Ribbon 2 (Vertical) - Triangle 3
			imm.surface_set_color(curr_col)
			imm.surface_set_uv(curr_uv_l)
			imm.surface_add_vertex(curr_v_bot)

			imm.surface_set_color(prev_col)
			imm.surface_set_uv(prev_uv_l)
			imm.surface_add_vertex(prev_v_bot)

			imm.surface_set_color(prev_col)
			imm.surface_set_uv(prev_uv_r)
			imm.surface_add_vertex(prev_v_top)

			# Ribbon 2 (Vertical) - Triangle 4
			imm.surface_set_color(prev_col)
			imm.surface_set_uv(prev_uv_r)
			imm.surface_add_vertex(prev_v_top)

			imm.surface_set_color(curr_col)
			imm.surface_set_uv(curr_uv_r)
			imm.surface_add_vertex(curr_v_top)

			imm.surface_set_color(curr_col)
			imm.surface_set_uv(curr_uv_l)
			imm.surface_add_vertex(curr_v_bot)

		prev_h_left = curr_h_left
		prev_h_right = curr_h_right
		prev_v_bot = curr_v_bot
		prev_v_top = curr_v_top
		prev_uv_l = curr_uv_l
		prev_uv_r = curr_uv_r
		prev_col = curr_col

	imm.surface_end()


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
		var imm := mesh as ImmediateMesh
		if imm != null:
			imm.clear_surfaces()
	_mesh_dirty = false


