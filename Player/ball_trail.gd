extends MeshInstance3D

var points : Array = []
var color : Color = Color(0.6, 0.0, 0.0, 1.0)  # Darker red
var dark_red : Color = Color(0.6, 0.0, 0.0, 1.0)
var orange : Color = Color(1.0, 0.4, 0.0, 1.0)
var yellow : Color = Color(1.0, 0.9, 0.0, 1.0)
var line_width : float = 0.08
var material : StandardMaterial3D = StandardMaterial3D.new()


var _mesh_dirty: bool = true
var _last_camera_pos: Vector3 = Vector3(999999, 999999, 999999)


func _ready():
	mesh = ArrayMesh.new()

	# Setup material with subtle glow using vertex colors
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.disable_receive_shadows = true
	material.no_depth_test = false

func _process(_delta):
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var cam_pos = camera.global_position
		if cam_pos.distance_squared_to(_last_camera_pos) > 0.5:
			_mesh_dirty = true
			_last_camera_pos = cam_pos
	if _mesh_dirty:
		draw()
		_mesh_dirty = false

func setColor(a):
	color = a
	dark_red = a
	_mesh_dirty = true

func draw():
	mesh.clear_surfaces()
	if points.size() >= 2:
		create_ribbon_mesh()

func create_ribbon_mesh():
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	# Find peak (highest Y value)
	var peak_index := 0
	var max_y := -999999.0
	for i in range(points.size()):
		if points[i].y > max_y:
			max_y = points[i].y
			peak_index = i

	# Create ribbon vertices
	for i in range(points.size()):
		var point : Vector3 = points[i]

		# Get direction to camera for billboarding
		var to_camera : Vector3 = (camera.global_position - point).normalized()

		# Get forward direction along the path
		var forward : Vector3 = Vector3.ZERO
		if i < points.size() - 1:
			forward = (points[i + 1] - point).normalized()
		elif i > 0:
			forward = (point - points[i - 1]).normalized()
		else:
			forward = Vector3.FORWARD

		# Create perpendicular vector for ribbon width
		var right : Vector3 = to_camera.cross(forward).normalized()
		if right.length() < 0.01:
			right = Vector3.RIGHT

		# Fade out towards the end
		var alpha : float = 1.0
		var points_from_end : int = points.size() - 1 - i
		if points_from_end < 3:  # Fade out at the end
			alpha = float(points_from_end + 1) / 4.0

		# Create two vertices for this point (left and right of center)
		var half_width : float = line_width * 0.5
		vertices.append(point - right * half_width)
		vertices.append(point + right * half_width)

		var t := float(i) / float(points.size() - 1)
		uvs.append(Vector2(0, t))
		uvs.append(Vector2(1, t))

		# Interpolate color based on peak:
		# - Red for the first 1/2 of the way up.
		# - Red to orange transition for the second 1/2 of the way up.
		# - Orange to yellow transition for the first 1/2 of the way down.
		# - Yellow for the remaining way down.
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
			var denom := float(points.size() - 1 - peak_index)
			if denom > 0.0:
				factor = float(i - peak_index) / denom
			if factor <= 0.5:
				var sub_factor := factor / 0.5
				point_color = orange.lerp(yellow, sub_factor)
			else:
				point_color = yellow

		# Apply brightness scale (mimicking the original 1.5x total multiplier from emission)
		var vertex_color := Color(point_color.r * 1.5, point_color.g * 1.5, point_color.b * 1.5, alpha)
		colors.append(vertex_color)
		colors.append(vertex_color)

		# Create triangles connecting to previous segment
		if i > 0:
			var base := i * 2
			# First triangle
			indices.append(base)
			indices.append(base - 2)
			indices.append(base - 1)
			# Second triangle
			indices.append(base - 1)
			indices.append(base + 1)
			indices.append(base)

	# Create the mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)

func add_point(point: Vector3):
	#points.append(points[-1])
	points.append(point)
	_mesh_dirty = true

func clear_points():
	points = []
	mesh.clear_surfaces()
	_mesh_dirty = false
