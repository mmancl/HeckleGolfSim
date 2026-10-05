extends Node

## Manages screen offset (full physical camera truck shift) for players hitting off-center in simulator bays.
## Shifts camera and look target laterally at address so that straight aim aligns with the player's physical hitting strip.
## Smoothly centers the camera during ball flight and returns smoothly to the offset at address.

signal offset_changed(target: float)

const MAX_LATERAL_OFFSET_METERS := 6.0 # Maximum physical shift across golf bay (in meters, ~19.7 ft)
const TO_CENTER_DURATION := 0.6
const TO_OFFSET_DURATION := 1.0

var _camera: Node = null # PhantomCamera3D or Camera3D
var _current: float = 0.0 # Currently applied animated offset factor (-1.0 to 1.0)
var _applied_displacement: Vector3 = Vector3.ZERO
var _last_shifted_pos: Vector3 = Vector3.INF
var _in_flight: bool = false
var _suppressed: bool = false
var _is_putter_active: bool = false
var _tween: Tween = null


func _ready() -> void:
	if has_node("/root/GlobalSettings"):
		var rs = GlobalSettings.range_settings
		if rs != null:
			rs.screen_offset_enabled.setting_changed.connect(_on_setting_changed)
			rs.screen_offset_value.setting_changed.connect(_on_setting_changed)
			if "screen_offset_putter_value" in rs:
				rs.screen_offset_putter_value.setting_changed.connect(_on_setting_changed)
	if has_node("/root/SceneManager"):
		var sm = get_node("/root/SceneManager")
		if sm != null and sm.has_signal("scene_changed"):
			sm.connect("scene_changed", _on_scene_changed)


func _process(_delta: float) -> void:
	if _camera != null and is_instance_valid(_camera):
		_apply(_current)


func register_camera(cam: Node) -> void:
	if _camera != null and is_instance_valid(_camera) and _camera != cam:
		_reset_camera(_camera)
	if _camera != cam:
		_is_putter_active = false
	_camera = cam
	_in_flight = false
	_suppressed = false
	_applied_displacement = Vector3.ZERO
	_last_shifted_pos = Vector3.INF
	_ensure_perspective(_camera)
	_current = 0.0
	_apply(_current)


func unregister_camera(cam: Node) -> void:
	if _camera == cam:
		if is_instance_valid(_camera):
			_reset_camera(_camera)
		_camera = null
		_current = 0.0
		_applied_displacement = Vector3.ZERO
		_last_shifted_pos = Vector3.INF
		_in_flight = false
		_suppressed = false
		if _tween != null and _tween.is_valid():
			_tween.kill()


func _on_scene_changed() -> void:
	if _camera != null and is_instance_valid(_camera):
		var cur_scene = get_tree().current_scene if get_tree() != null else null
		if cur_scene != null and (cur_scene == _camera or cur_scene.is_ancestor_of(_camera)):
			# Camera was registered by the newly loaded scene during its _ready()
			_ensure_perspective(_camera)
			_apply(get_target())
			return
		_reset_camera(_camera)
	_camera = null
	_current = 0.0
	_applied_displacement = Vector3.ZERO
	_last_shifted_pos = Vector3.INF
	_in_flight = false
	_suppressed = false
	_is_putter_active = false
	if _tween != null and _tween.is_valid():
		_tween.kill()


func set_putter_active(active: bool) -> void:
	if _is_putter_active == active:
		return
	_is_putter_active = active
	offset_changed.emit(get_target())
	if not _in_flight and not _suppressed:
		_animate_to(get_target(), 0.35)


func is_putter_active() -> bool:
	return _is_putter_active


func get_target() -> float:
	if not has_node("/root/GlobalSettings"):
		return 0.0
	var rs = GlobalSettings.range_settings
	if rs == null or not rs.screen_offset_enabled.value or _in_flight or _suppressed:
		return 0.0
	if _is_putter_active and "screen_offset_putter_value" in rs:
		return clampf(float(rs.screen_offset_putter_value.value), -1.0, 1.0)
	return clampf(float(rs.screen_offset_value.value), -1.0, 1.0)


## Returns the currently applied physical lateral offset in meters
func get_current_offset_meters() -> float:
	return _current * MAX_LATERAL_OFFSET_METERS


## Returns the physical displacement vector for a given camera transform or aim yaw
func get_displacement_vector(right_dir: Vector3) -> Vector3:
	return right_dir.normalized() * get_current_offset_meters()


func on_shot_started() -> void:
	_in_flight = true
	_animate_to(0.0, TO_CENTER_DURATION)


func on_ready_for_shot(duration: float = TO_OFFSET_DURATION, immediate: bool = false) -> void:
	_in_flight = false
	var target = get_target()
	if immediate or duration <= 0.0:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_current = target
		_apply(_current)
	else:
		_animate_to(target, duration)


func set_suppressed(v: bool) -> void:
	if _suppressed == v:
		return
	_suppressed = v
	if _suppressed:
		_animate_to(0.0, 0.35)
	else:
		_animate_to(get_target(), 0.5)


func set_enabled(v: bool) -> void:
	if not has_node("/root/GlobalSettings"):
		return
	GlobalSettings.range_settings.screen_offset_enabled.value = v
	GlobalSettings.save_settings()
	offset_changed.emit(get_target())
	if not _in_flight and not _suppressed:
		_animate_to(get_target(), 0.35)


func set_value(v: float, live: bool = true) -> void:
	if not has_node("/root/GlobalSettings"):
		return
	GlobalSettings.range_settings.screen_offset_value.value = clampf(v, -1.0, 1.0)
	if not live:
		GlobalSettings.save_settings()
	offset_changed.emit(get_target())
	if not _in_flight and not _suppressed and GlobalSettings.range_settings.screen_offset_enabled.value:
		if not _is_putter_active:
			if _tween != null and _tween.is_valid():
				_tween.kill()
			_current = get_target()
			_apply(_current)


func set_putter_value(v: float, live: bool = true) -> void:
	if not has_node("/root/GlobalSettings"):
		return
	var rs = GlobalSettings.range_settings
	if "screen_offset_putter_value" in rs:
		rs.screen_offset_putter_value.value = clampf(v, -1.0, 1.0)
	if not live:
		GlobalSettings.save_settings()
	offset_changed.emit(get_target())
	if not _in_flight and not _suppressed and GlobalSettings.range_settings.screen_offset_enabled.value:
		if _is_putter_active:
			if _tween != null and _tween.is_valid():
				_tween.kill()
			_current = get_target()
			_apply(_current)


func _on_setting_changed(_val = null) -> void:
	offset_changed.emit(get_target())
	if not _in_flight and not _suppressed:
		_animate_to(get_target(), 0.35)


func _animate_to(target: float, duration: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if is_equal_approx(_current, target) or duration <= 0.0:
		_current = target
		_apply(_current)
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(func(val: float):
		_current = val
		_apply(_current)
	, _current, target, duration)


func _apply(s: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return

	# If camera is orthogonal (e.g. 2D minimap or overhead map), ignore
	var pcam = _camera if _camera is PhantomCamera3D else null
	var res = pcam.camera_3d_resource if pcam != null and "camera_3d_resource" in pcam else null
	var cam3d: Camera3D = null
	if pcam == null and _camera is Camera3D:
		cam3d = _camera as Camera3D
	elif pcam != null:
		cam3d = _camera.get_node_or_null("^../Camera3D")
		if cam3d == null:
			var parent = _camera.get_parent()
			if parent != null:
				cam3d = parent.get_node_or_null("Camera3D")

	if res != null and res.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return
	if cam3d != null and cam3d.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return

	# Ensure standard perspective projection (no frustum distortion)
	_ensure_perspective(_camera)

	# Detect if camera position changed externally (e.g. aim re-anchored or reset)
	var cur_pos = _camera.global_position
	if _last_shifted_pos != Vector3.INF and not cur_pos.is_equal_approx(_last_shifted_pos):
		_applied_displacement = Vector3.ZERO

	# Calculate desired lateral displacement along camera's right vector (basis.x)
	var right_dir = _camera.global_transform.basis.x.normalized()
	# Ensure horizontal right vector (ignore slight pitch tilting)
	right_dir.y = 0.0
	if right_dir.is_zero_approx():
		right_dir = _camera.global_transform.basis.x.normalized()
	else:
		right_dir = right_dir.normalized()

	var target_displacement = right_dir * (s * MAX_LATERAL_OFFSET_METERS)
	var delta_shift = target_displacement - _applied_displacement

	if not delta_shift.is_zero_approx():
		_camera.global_position += delta_shift
		if cam3d != null and cam3d != _camera:
			cam3d.global_position += delta_shift
		_applied_displacement = target_displacement

	_last_shifted_pos = _camera.global_position


func _ensure_perspective(cam: Node) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	if cam is PhantomCamera3D and "camera_3d_resource" in cam and cam.camera_3d_resource != null:
		if cam.camera_3d_resource.projection == 2: # FRUSTUM
			cam.camera_3d_resource.projection = 0 # PERSPECTIVE
			cam.camera_3d_resource.frustum_offset = Vector2.ZERO
	if cam is Camera3D:
		if cam.projection == Camera3D.PROJECTION_FRUSTUM:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.frustum_offset = Vector2.ZERO
	var parent = cam.get_parent()
	if parent != null and parent.has_node("Camera3D"):
		var c = parent.get_node("Camera3D") as Camera3D
		if c != null and c.projection == Camera3D.PROJECTION_FRUSTUM:
			c.projection = Camera3D.PROJECTION_PERSPECTIVE
			c.frustum_offset = Vector2.ZERO


func _reset_camera(cam: Node) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	if not _applied_displacement.is_zero_approx():
		cam.global_position -= _applied_displacement
		var parent = cam.get_parent()
		if parent != null and parent.has_node("Camera3D"):
			var c = parent.get_node("Camera3D") as Camera3D
			if c != null and c != cam:
				c.global_position -= _applied_displacement
		_applied_displacement = Vector3.ZERO
	_last_shifted_pos = Vector3.INF
	_ensure_perspective(cam)

