class_name TouchScrollHelper
extends Node

## Helper node that provides touch swipe/drag scrolling and kinetic momentum
## to Godot ScrollContainers on touchscreens, mobile devices, and desktop.

var _scroll_container: ScrollContainer = null
var _touch_active: bool = false
var _touch_index: int = -1
var _touch_start_pos: Vector2 = Vector2.ZERO
var _last_touch_pos: Vector2 = Vector2.ZERO
var _start_scroll_v: int = 0
var _start_scroll_h: int = 0
var _is_dragging: bool = false
var _velocity: Vector2 = Vector2.ZERO
var _last_time: int = 0

const DRAG_THRESHOLD: float = 8.0
const FRICTION: float = 8.0


static func attach_to(scroll: ScrollContainer) -> TouchScrollHelper:
	if scroll == null:
		return null
	var existing = scroll.get_node_or_null("TouchScrollHelper")
	if existing != null and existing is TouchScrollHelper:
		return existing
	var helper = TouchScrollHelper.new()
	helper.name = "TouchScrollHelper"
	scroll.add_child(helper)
	return helper


func _ready() -> void:
	_scroll_container = get_parent() as ScrollContainer


func _input(event: InputEvent) -> void:
	if _scroll_container == null or not _scroll_container.is_inside_tree() or not _scroll_container.is_visible_in_tree():
		_reset_touch()
		return

	if event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if not _touch_active and _is_pos_inside_container(event.position):
			_begin_touch(event.position, event.index)
	else:
		if _touch_active and _touch_index == event.index:
			_end_touch()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if _touch_active and _touch_index == event.index:
		_process_drag(event.position)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _touch_active and _is_pos_inside_container(event.position):
				_begin_touch(event.position, -1)
		else:
			if _touch_active and _touch_index == -1:
				_end_touch()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _touch_active and _touch_index == -1:
		_process_drag(event.position)


func _is_pos_inside_container(pos: Vector2) -> bool:
	if _scroll_container == null:
		return false
	var rect = _scroll_container.get_global_rect()
	return rect.has_point(pos)


func _begin_touch(pos: Vector2, index: int) -> void:
	_touch_active = true
	_touch_index = index
	_touch_start_pos = pos
	_last_touch_pos = pos
	_start_scroll_v = _scroll_container.scroll_vertical
	_start_scroll_h = _scroll_container.scroll_horizontal
	_is_dragging = false
	_velocity = Vector2.ZERO
	_last_time = Time.get_ticks_msec()


func _process_drag(pos: Vector2) -> void:
	var total_diff = pos - _touch_start_pos
	if not _is_dragging:
		if total_diff.length() >= DRAG_THRESHOLD:
			_is_dragging = true
			_last_touch_pos = pos
			_last_time = Time.get_ticks_msec()

	if _is_dragging:
		var now = Time.get_ticks_msec()
		var dt = max(0.001, float(now - _last_time) / 1000.0)
		var frame_delta = pos - _last_touch_pos
		_velocity.y = lerp(_velocity.y, -frame_delta.y / dt, 0.45)
		_velocity.x = lerp(_velocity.x, -frame_delta.x / dt, 0.45)
		_last_touch_pos = pos
		_last_time = now
		_apply_scroll(_start_scroll_h - int(total_diff.x), _start_scroll_v - int(total_diff.y))
		get_viewport().set_input_as_handled()


func _end_touch() -> void:
	_touch_active = false
	_touch_index = -1
	if _is_dragging:
		get_viewport().set_input_as_handled()
		_is_dragging = false


func _reset_touch() -> void:
	_touch_active = false
	_touch_index = -1
	_is_dragging = false
	_velocity = Vector2.ZERO


func _apply_scroll(new_h: int, new_v: int) -> void:
	if _scroll_container == null:
		return
	if _scroll_container.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_scroll_container.scroll_vertical = int(clamp(new_v, 0, _get_max_scroll_v()))
	if _scroll_container.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_scroll_container.scroll_horizontal = int(clamp(new_h, 0, _get_max_scroll_h()))


func _get_max_scroll_v() -> int:
	if _scroll_container == null:
		return 0
	var v_bar = _scroll_container.get_v_scroll_bar()
	if v_bar != null:
		return int(max(0.0, v_bar.max_value - v_bar.page))
	return 0


func _get_max_scroll_h() -> int:
	if _scroll_container == null:
		return 0
	var h_bar = _scroll_container.get_h_scroll_bar()
	if h_bar != null:
		return int(max(0.0, h_bar.max_value - h_bar.page))
	return 0


func _process(delta: float) -> void:
	if not _touch_active and _velocity.length() > 8.0:
		if _scroll_container == null or not _scroll_container.is_inside_tree() or not _scroll_container.is_visible_in_tree():
			_velocity = Vector2.ZERO
			return
		
		var max_v = _get_max_scroll_v()
		var max_h = _get_max_scroll_h()
		
		var current_v = _scroll_container.scroll_vertical
		var current_h = _scroll_container.scroll_horizontal
		
		var target_v = clamp(current_v + _velocity.y * delta, 0.0, float(max_v))
		var target_h = clamp(current_h + _velocity.x * delta, 0.0, float(max_h))
		
		if target_v <= 0.0 or target_v >= float(max_v):
			_velocity.y = 0.0
		if target_h <= 0.0 or target_h >= float(max_h):
			_velocity.x = 0.0
			
		_scroll_container.scroll_vertical = int(target_v)
		_scroll_container.scroll_horizontal = int(target_h)
		
		_velocity = _velocity.lerp(Vector2.ZERO, FRICTION * delta)
		if _velocity.length() < 8.0:
			_velocity = Vector2.ZERO
