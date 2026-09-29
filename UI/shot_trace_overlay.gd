extends Node3D

# Multi-Arc 3D Overlay for Driving Range
# Renders colored cross-ribbon flight paths of all shots for the selected club during this session.

const ARC_COLORS: Array[Color] = [
	Color(0.0, 0.9, 1.0),   # Cyan
	Color(1.0, 0.85, 0.0),  # Yellow
	Color(1.0, 0.25, 0.25), # Red
	Color(0.4, 1.0, 0.2),   # Lime
	Color(1.0, 0.55, 0.0),  # Orange
	Color(0.85, 0.3, 1.0),  # Magenta
	Color(1.0, 1.0, 1.0),   # White
	Color(0.2, 1.0, 0.65),  # Mint
]
const MAX_DISPLAYED_TRACES := 25
const BallTrailScript = preload("res://Player/ball_trail.gd")

var _trace_nodes: Array[MeshInstance3D] = []
var _is_active: bool = false
var _current_club: String = ""

func is_active() -> bool:
	return _is_active

func activate(shot_history: Array[Dictionary], current_club: String) -> void:
	_is_active = true
	_current_club = current_club
	visible = true
	_rebuild_traces(shot_history)

func deactivate() -> void:
	_is_active = false
	visible = false
	_clear_traces()

func on_club_changed(shot_history: Array[Dictionary], new_club: String) -> void:
	_current_club = new_club
	if _is_active:
		_rebuild_traces(shot_history)

func on_new_shot(shot_data: Dictionary) -> void:
	if not _is_active:
		return
	var shot_club = str(shot_data.get("club", ""))
	if not _is_matching_club(shot_club, _current_club):
		return
	if not shot_data.has("tracer_points"):
		return
	var pts: Array = shot_data["tracer_points"]
	if pts.size() < 2:
		return

	_add_single_trace(pts, _trace_nodes.size())

	while _trace_nodes.size() > MAX_DISPLAYED_TRACES:
		var oldest = _trace_nodes.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	_update_trace_opacities()

func _rebuild_traces(shot_history: Array[Dictionary]) -> void:
	_clear_traces()
	if not _is_active:
		return

	var club_shots: Array[Dictionary] = []
	for shot in shot_history:
		var shot_club = str(shot.get("club", ""))
		if _is_matching_club(shot_club, _current_club) and shot.has("tracer_points"):
			var pts: Array = shot["tracer_points"]
			if pts.size() >= 2:
				club_shots.append(shot)

	if club_shots.size() > MAX_DISPLAYED_TRACES:
		club_shots = club_shots.slice(club_shots.size() - MAX_DISPLAYED_TRACES)

	for i in club_shots.size():
		var pts: Array = club_shots[i]["tracer_points"]
		_add_single_trace(pts, i)

	_update_trace_opacities()

func _add_single_trace(pts: Array, color_idx: int) -> void:
	var trail = MeshInstance3D.new()
	trail.set_script(BallTrailScript)
	add_child(trail)

	var color = ARC_COLORS[color_idx % ARC_COLORS.size()]
	trail.setColor(color)
	trail.points = pts.duplicate()
	trail.line_width = 0.10

	var max_y := -999999.0
	var p_idx := 0
	for i in pts.size():
		var pt = pts[i] as Vector3
		if pt.y > max_y:
			max_y = pt.y
			p_idx = i

	trail.max_peak_y = max_y
	trail.peak_index = p_idx
	trail.draw()

	_trace_nodes.append(trail)

func _update_trace_opacities() -> void:
	var total := _trace_nodes.size()
	for i in total:
		var node = _trace_nodes[i]
		if not is_instance_valid(node):
			continue
		var factor := 1.0
		if total > 1:
			factor = remap(float(i), 0.0, float(total - 1), 0.35, 1.0)
		var base_color = ARC_COLORS[i % ARC_COLORS.size()]
		var mat = node.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(1.0, 1.0, 1.0, factor)

func _clear_traces() -> void:
	for node in _trace_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_trace_nodes.clear()

func _is_matching_club(club_a: String, club_b: String) -> bool:
	if club_a.is_empty() or club_b.is_empty():
		return true
	if club_a == club_b:
		return true
	return club_a.to_lower().strip_edges() == club_b.to_lower().strip_edges()
