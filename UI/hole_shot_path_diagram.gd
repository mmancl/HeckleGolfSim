extends Control

var _positions: Array[Vector3] = []
var _distances: Array[int] = []
var _green_position := Vector3.ZERO
var _hole_tee_positions: Array[Vector3] = []
var _shared_shot_positions: Array[Vector3] = []
var _cart_paths: Array[PackedVector2Array] = []
var _satellite_texture: Texture2D
var _satellite_bounds: Array = []
var _tee_position := Vector2.ZERO
var _forward := Vector2.UP
var _right := Vector2.RIGHT
var _scale := 1.0
var _tee_screen_position := Vector2.ZERO
var _center_side := 0.0
var _min_forward := 0.0
var _max_forward := 1.0
var _half_width := 1.0
var _plot := Rect2()


func set_shot_path(positions: Array[Vector3], distances: Array[int], green_position: Vector3, satellite_texture: Texture2D = null, satellite_bounds: Array = [], hole_tee_positions: Array[Vector3] = [], shared_shot_positions: Array[Vector3] = [], cart_paths: Array[PackedVector2Array] = []) -> void:
	_positions = positions.duplicate()
	_distances = distances.duplicate()
	_green_position = green_position
	_hole_tee_positions = hole_tee_positions.duplicate()
	_shared_shot_positions = shared_shot_positions.duplicate()
	_cart_paths = cart_paths.duplicate()
	_satellite_texture = satellite_texture
	_satellite_bounds = satellite_bounds.duplicate()
	queue_redraw()


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(260, 260)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	clip_contents = true
	queue_redraw()


func _draw() -> void:
	if size.x <= 2.0 or size.y <= 2.0:
		return
	_plot = Rect2(Vector2.ZERO, size)
	_calculate_view()
	var has_satellite_bounds := _satellite_bounds_are_valid()
	if _satellite_texture != null and has_satellite_bounds:
		_draw_satellite_background()
		draw_rect(_plot, Color(0.02, 0.04, 0.03, 0.18), true)
	else:
		draw_rect(_plot, Color(0.08, 0.20, 0.14, 1.0), true)
		if _satellite_texture != null:
			var font := get_theme_default_font()
			if font != null:
				draw_string(font, Vector2(8.0, 20.0), "Re-download course for aligned map", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	for cart_path in _cart_paths:
		if cart_path.size() < 2:
			continue
		var mapped_cart_path := PackedVector2Array()
		for point in cart_path:
			mapped_cart_path.append(_map_world_position(point))
		draw_polyline(mapped_cart_path, Color.WHITE, 4.0, true)
		draw_polyline(mapped_cart_path, Color.BLACK, 2.5, true)
	if _positions.size() < 2:
		return

	var path_positions := _get_path_positions()
	var mapped_positions: Array[Vector2] = []
	for position in path_positions:
		mapped_positions.append(_map_position(position))

	const MIN_DISPLAY_YARDS := 20
	for i in range(mapped_positions.size() - 1):
		var start := mapped_positions[i]
		var finish := mapped_positions[i + 1]
		var segment_yards := _distances[i] if i < _distances.size() else MIN_DISPLAY_YARDS
		if segment_yards < MIN_DISPLAY_YARDS:
			continue
		draw_line(start, finish, Color(0.02, 0.03, 0.03, 0.95), 7.0, true)
		draw_line(start, finish, Color.WHITE, 4.0, true)
		_draw_distance_label(start, finish, segment_yards, i)
		draw_circle(finish, 5.0, Color(0.02, 0.03, 0.03, 0.95))
		draw_circle(finish, 3.2, Color(1.0, 0.85, 0.38))
	draw_circle(mapped_positions[0], 5.0, Color(0.02, 0.03, 0.03, 0.95))
	draw_circle(mapped_positions[0], 3.2, Color(1.0, 0.85, 0.38))
	var green_point := _map_position(_green_position)
	draw_line(green_point + Vector2(0, 7), green_point + Vector2(0, -8), Color(0.02, 0.03, 0.03), 5.0, true)
	draw_line(green_point + Vector2(0, 7), green_point + Vector2(0, -8), Color(0.95, 0.16, 0.12), 3.0, true)
	draw_colored_polygon(PackedVector2Array([
		green_point + Vector2(0, -8),
		green_point + Vector2(15, -4),
		green_point + Vector2(0, 0)
	]), Color(0.95, 0.16, 0.12))


func _get_path_positions() -> Array[Vector3]:
	var path_positions := _positions.duplicate()
	if not path_positions.is_empty() and not path_positions.back().is_equal_approx(_green_position):
		path_positions.append(_green_position)
	return path_positions


static func _to_vector3(val: Variant) -> Variant:
	if typeof(val) == TYPE_VECTOR3:
		return val
	if typeof(val) == TYPE_ARRAY and val.size() >= 3:
		return Vector3(float(val[0]), float(val[1]), float(val[2]))
	return null


static func get_positions_from_shot_stats(shot_stats: Array, fallback_positions: Array[Vector3], world_to_local: Transform3D = Transform3D.IDENTITY) -> Array[Vector3]:
	if shot_stats.is_empty() or typeof(shot_stats[0]) != TYPE_DICTIONARY:
		return fallback_positions.duplicate()
	var first_start = _to_vector3(shot_stats[0].get("start_pos"))
	if first_start == null:
		return fallback_positions.duplicate()
	var positions: Array[Vector3] = [world_to_local * first_start]
	for shot in shot_stats:
		if typeof(shot) != TYPE_DICTIONARY:
			return fallback_positions.duplicate()
		var end_p = _to_vector3(shot.get("end_pos"))
		if end_p == null:
			return fallback_positions.duplicate()
		positions.append(world_to_local * end_p)
	return positions


func _calculate_view() -> void:
	var view_tee := _hole_tee_positions[0] if not _hole_tee_positions.is_empty() else (_positions[0] if not _positions.is_empty() else Vector3.ZERO)
	var view_tee_distance_squared := Vector2(view_tee.x - _green_position.x, view_tee.z - _green_position.z).length_squared()
	for tee_position in _hole_tee_positions:
		var tee_distance_squared := Vector2(tee_position.x - _green_position.x, tee_position.z - _green_position.z).length_squared()
		if tee_distance_squared > view_tee_distance_squared:
			view_tee = tee_position
			view_tee_distance_squared = tee_distance_squared
	_tee_position = Vector2(view_tee.x, view_tee.z)
	var green := Vector2(_green_position.x, _green_position.z)
	var tee_to_green := green - _tee_position
	_forward = tee_to_green.normalized() if tee_to_green.length_squared() > 0.001 else Vector2.UP
	_right = Vector2(-_forward.y, _forward.x)

	var min_side := 0.0
	var max_side := 0.0
	_min_forward = 0.0
	_max_forward = tee_to_green.dot(_forward)
	var view_positions := _hole_tee_positions.duplicate()
	view_positions.append(_green_position)
	view_positions.append_array(_shared_shot_positions)
	for position in view_positions:
		var offset := Vector2(position.x, position.z) - _tee_position
		var side := offset.dot(_right)
		var forward_distance := offset.dot(_forward)
		min_side = minf(min_side, side)
		max_side = maxf(max_side, side)
		_min_forward = minf(_min_forward, forward_distance)
		_max_forward = maxf(_max_forward, forward_distance)
	_center_side = (min_side + max_side) * 0.5
	var hole_length := maxf(_max_forward - _min_forward, 1.0)
	var forward_padding := maxf(hole_length * 0.05, 8.0)
	var side_padding := maxf(maxf((max_side - min_side) * 0.10, hole_length * 0.07), 12.0)
	_min_forward -= forward_padding
	_max_forward += forward_padding
	_half_width = maxf((max_side - min_side) * 0.5 + side_padding, 12.0)

	var margin := Vector2(10.0, 14.0)
	_plot = Rect2(margin, size - margin * 2.0)
	var world_width := _half_width * 2.0
	var world_height := _max_forward - _min_forward
	_scale = minf(_plot.size.x / world_width, _plot.size.y / maxf(world_height, 1.0))
	var available_world_height := _plot.size.y / _scale
	if world_height < available_world_height:
		_min_forward = _max_forward - available_world_height
	_tee_screen_position = Vector2(
		_plot.position.x + _plot.size.x * 0.5,
		_plot.end.y + _min_forward * _scale
	)


func _draw_satellite_background() -> void:
	var min_x := float(_satellite_bounds[0])
	var min_z := float(_satellite_bounds[1])
	var max_x := float(_satellite_bounds[2])
	var max_z := float(_satellite_bounds[3])
	draw_polygon(
		PackedVector2Array([
			_map_world_position(Vector2(min_x, min_z)),
			_map_world_position(Vector2(max_x, min_z)),
			_map_world_position(Vector2(max_x, max_z)),
			_map_world_position(Vector2(min_x, max_z))
		]),
		PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]),
		PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]),
		_satellite_texture
	)


func _satellite_bounds_are_valid() -> bool:
	return has_valid_satellite_bounds(_satellite_bounds)


static func has_valid_satellite_bounds(bounds: Array) -> bool:
	if bounds.size() < 4:
		return false
	for coordinate in bounds.slice(0, 4):
		if (typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT) or not is_finite(float(coordinate)):
			return false
	return float(bounds[2]) > float(bounds[0]) and float(bounds[3]) > float(bounds[1])


func _map_world_position(world_position: Vector2) -> Vector2:
	var offset := world_position - _tee_position
	return _screen_position(offset.dot(_right), offset.dot(_forward))


func _screen_position(side: float, forward_distance: float) -> Vector2:
	return _tee_screen_position + Vector2((side - _center_side) * _scale, -forward_distance * _scale)


func _map_position(position: Vector3) -> Vector2:
	var offset := Vector2(position.x, position.z) - _tee_position
	return _screen_position(offset.dot(_right), offset.dot(_forward))


func _draw_distance_label(start: Vector2, finish: Vector2, distance_yards: int, shot_index: int) -> void:
	var font := get_theme_default_font()
	if font == null:
		return
	var text := "%d yds" % distance_yards
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	var label_size := Vector2(text_size.x + 12.0, 22.0)
	var segment := finish - start
	var offset := segment.orthogonal().normalized() * (18.0 if shot_index % 2 == 0 else -18.0)
	var label_position := (start + finish) * 0.5 + offset - label_size * 0.5
	label_position.x = clampf(label_position.x, _plot.position.x + 2.0, maxf(_plot.position.x + 2.0, _plot.end.x - label_size.x - 2.0))
	label_position.y = clampf(label_position.y, _plot.position.y + 2.0, maxf(_plot.position.y + 2.0, _plot.end.y - label_size.y - 2.0))
	var label_rect := Rect2(label_position, label_size)
	draw_rect(label_rect, Color.WHITE, true)
	draw_rect(label_rect, Color(0.03, 0.04, 0.05), false, 1.0)
	draw_string(font, label_position + Vector2(6.0, 16.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.03, 0.04, 0.05))
