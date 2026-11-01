class_name RemoteShotReplayer
extends Node

## Replays remote player shots directly from Point A (start_pos) to Point B (end_pos).
## Non-putter shots fly in a collision-free parabolic arc with zero rollout.
## Putts roll straight along A -> B ignoring green slope and collisions, smoothly decelerating to B.

signal replay_started(shot_event: Dictionary)
signal replay_progress(current_pos: Vector3)
signal replay_finished(shot_event: Dictionary)

var _is_replaying: bool = false
var _current_ball: Node3D = null
var _current_tracer: Node = null
var _current_shot_event: Dictionary = {}
var _current_profile: Dictionary = {}
var _elapsed_s: float = 0.0


# Plays a simple, collision-free trajectory directly from start_pos (A) to end_pos (B) and stops at B.
# Required keys in shot_event:
#   "start": Vector3 or [x, y, z]
#   "end": Vector3 or [x, y, z]
#   "club": String (e.g. "Dr", "7i", "SW", "Pt")
func play_remote_shot(
	ball_node: Node3D,
	shot_event: Dictionary,
	tracer_node: Node = null
) -> void:
	if _is_replaying:
		skip_to_end()

	var start_pos := _parse_vector3(shot_event.get("start", shot_event.get("start_pos", Vector3.ZERO)))
	var end_pos := _parse_vector3(shot_event.get("end", shot_event.get("end_pos", Vector3.ZERO)))
	var club := str(shot_event.get("club", "Dr"))

	_current_ball = ball_node
	_current_tracer = tracer_node
	_current_shot_event = shot_event
	_current_profile = build_trajectory_profile(start_pos, end_pos, club)
	_elapsed_s = 0.0
	_is_replaying = true

	if is_instance_valid(_current_ball):
		if "is_replaying_remote_shot" in _current_ball:
			_current_ball.is_replaying_remote_shot = true
		_set_node_position(_current_ball, start_pos)

	if is_instance_valid(_current_tracer):
		_start_tracer(start_pos)

	replay_started.emit(shot_event)
	replay_progress.emit(start_pos)

	var duration: float = float(_current_profile.get("duration_s", 0.0))
	if duration <= 0.0:
		_finish_replay()


func is_replaying() -> bool:
	return _is_replaying


func skip_to_end() -> void:
	if not _is_replaying:
		return
	_finish_replay()


func _process(delta: float) -> void:
	if not _is_replaying:
		return

	_elapsed_s += delta
	var duration_s: float = float(_current_profile.get("duration_s", 1.0))
	var current_pos: Vector3 = sample_trajectory_at_time(_current_profile, _elapsed_s)

	if is_instance_valid(_current_ball):
		_set_node_position(_current_ball, current_pos)

	if is_instance_valid(_current_tracer):
		_append_tracer_point(current_pos)

	replay_progress.emit(current_pos)

	if _elapsed_s >= duration_s:
		_finish_replay()


func _finish_replay() -> void:
	if not _is_replaying:
		return
	_is_replaying = false

	var end_pos: Vector3 = _current_profile.get("end_pos", Vector3.ZERO)

	if is_instance_valid(_current_ball):
		_set_node_position(_current_ball, end_pos)
		if "is_replaying_remote_shot" in _current_ball:
			_current_ball.is_replaying_remote_shot = false
		if "state" in _current_ball:
			_current_ball.state = PhysicsEnums.BallState.REST

	if is_instance_valid(_current_tracer):
		_finalize_tracer(end_pos)

	var finished_event: Dictionary = _current_shot_event
	_current_ball = null
	_current_tracer = null
	_current_shot_event = {}
	_current_profile = {}

	replay_finished.emit(finished_event)


func _start_tracer(start_pos: Vector3) -> void:
	if _current_tracer.has_method("start_trail"):
		_current_tracer.call("start_trail", start_pos)
	elif _current_tracer.has_method("clear_points"):
		_current_tracer.call("clear_points")
		if _current_tracer.has_method("add_point"):
			_current_tracer.call("add_point", start_pos)
		elif "points" in _current_tracer:
			_current_tracer.points.append(start_pos)
	elif "points" in _current_tracer:
		_current_tracer.points.clear()
		_current_tracer.points.append(start_pos)


func _append_tracer_point(pos: Vector3) -> void:
	if _current_tracer.has_method("update_trail"):
		_current_tracer.call("update_trail", pos)
	elif _current_tracer.has_method("add_point"):
		_current_tracer.call("add_point", pos)
	elif "points" in _current_tracer:
		_current_tracer.points.append(pos)


func _finalize_tracer(end_pos: Vector3) -> void:
	if _current_tracer.has_method("finalize_trail"):
		_current_tracer.call("finalize_trail")
	elif _current_tracer.has_method("add_point"):
		_current_tracer.call("add_point", end_pos)
		if _current_tracer.has_method("draw"):
			_current_tracer.call("draw")
	elif "points" in _current_tracer:
		_current_tracer.points.append(end_pos)


static func _set_node_position(node: Node3D, pos: Vector3) -> void:
	if node.is_inside_tree():
		node.global_position = pos
	else:
		node.position = pos


static func _parse_vector3(val) -> Vector3:
	if val is Vector3:
		return val
	if val is Array or val is PackedFloat32Array or val is PackedFloat64Array:
		if val.size() >= 3:
			return Vector3(float(val[0]), float(val[1]), float(val[2]))
	return Vector3.ZERO


# Pure helper (exposed static for unit testing without a 3D scene)
static func build_trajectory_profile(start_pos: Vector3, end_pos: Vector3, club: String) -> Dictionary:
	var D: float = Vector2(start_pos.x, start_pos.z).distance_to(Vector2(end_pos.x, end_pos.z))
	var c := club.strip_edges().to_lower()
	var is_putt: bool = (c == "pt" or c == "putter" or c == "putt")

	var avg_speed_mps: float = 30.0
	var peak_height_m: float = 0.0
	var duration_s: float = 0.8
	var roll_s: float = 0.0

	if is_putt:
		avg_speed_mps = 3.5
		peak_height_m = 0.0
		duration_s = clampf(D / avg_speed_mps, 0.6, 4.0)
		roll_s = 0.0
	else:
		if c in ["dr", "driver", "1w", "2w", "3w", "4w", "5w", "7w", "9w"] or c.begins_with("dr") or (c.ends_with("w") and not c in ["pw", "gw", "sw", "lw", "aw"]):
			avg_speed_mps = 42.0
			peak_height_m = clampf(D * 0.14, 3.0, 34.0)
		elif c in ["2h", "3h", "4h", "5h", "6h", "1i", "2i", "3i", "4i", "5i"]:
			avg_speed_mps = 36.0
			peak_height_m = clampf(D * 0.18, 3.0, 32.0)
		elif c in ["6i", "7i", "8i", "9i", "pw", "10i"]:
			avg_speed_mps = 30.0
			peak_height_m = clampf(D * 0.22, 2.5, 30.0)
		elif c in ["gw", "sw", "lw", "aw", "wedge", "lob"]:
			avg_speed_mps = 22.0
			peak_height_m = clampf(D * 0.28, 1.5, 26.0)
		else:
			avg_speed_mps = 30.0
			peak_height_m = clampf(D * 0.22, 2.5, 30.0)

		duration_s = clampf(D / avg_speed_mps, 0.8, 5.5)
		roll_s = 0.0

	return {
		"start": start_pos,
		"start_pos": start_pos,
		"end": end_pos,
		"end_pos": end_pos,
		"club": club,
		"is_putt": is_putt,
		"horizontal_distance": D,
		"avg_speed_mps": avg_speed_mps,
		"peak_height_m": peak_height_m,
		"duration_s": duration_s,
		"roll_s": roll_s
	}


static func sample_trajectory_at_time(profile: Dictionary, elapsed_s: float) -> Vector3:
	var start_pos: Vector3 = profile.get("start_pos", profile.get("start", Vector3.ZERO))
	var end_pos: Vector3 = profile.get("end_pos", profile.get("end", Vector3.ZERO))
	var duration_s: float = float(profile.get("duration_s", 1.0))
	var is_putt: bool = bool(profile.get("is_putt", false))
	var peak_height_m: float = float(profile.get("peak_height_m", 0.0))

	if elapsed_s <= 0.0:
		return start_pos
	if duration_s <= 0.00001 or elapsed_s >= duration_s:
		return end_pos

	var u: float = clampf(elapsed_s / duration_s, 0.0, 1.0)
	if is_putt:
		# Smooth ease-out deceleration: w = 1.0 - (1.0 - u) * (1.0 - u)
		var w: float = 1.0 - (1.0 - u) * (1.0 - u)
		return start_pos.lerp(end_pos, w)
	else:
		var base_pos: Vector3 = start_pos.lerp(end_pos, u)
		var arc_y: float = 4.0 * peak_height_m * u * (1.0 - u)
		return Vector3(base_pos.x, base_pos.y + arc_y, base_pos.z)
