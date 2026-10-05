class_name PuttingCameraOverlay
extends Control

signal circle_position_changed(new_pos: Vector2)

## Configuration — all in normalized coordinates (0.0–1.0 relative to control size)
var circle_center: Vector2 = Vector2(0.5, 0.70)   # Centered horizontally, lower third of frame
var circle_radius_norm: float = 0.16              # ~16% of frame width (comfortable placement zone)
var arrow_length_norm: float = 0.45               # Arrow extends upward toward target

const MIN_CIRCLE_X: float = 0.15
const MAX_CIRCLE_X: float = 0.85

## Interactive Drag State
var is_dragging: bool = false
var is_hovered: bool = false
var _drag_offset_x: float = 0.0

## State (set by PuttingCameraStateMachine)
var current_state: int = 0   # 0=IDLE, 1=READY, 2=TRACKING, 3=EXECUTION
var ball_detected_in_circle: bool = false
var last_ball_position_norm: Vector2 = Vector2.ZERO  # For debug visualization
var last_speed_mph: float = 0.0
var last_offset_deg: float = 0.0

## Color configuration and picker feedback
var picker_active: bool = false
var picker_cursor_pos: Vector2 = Vector2.ZERO
var ball_color_configured: bool = false
var ball_color_swatch: Color = Color.WHITE
var bg_color_configured: bool = false
var bg_color_swatch: Color = Color(0.2, 0.3, 0.2)

## Rejection / Mishit / Low FPS Feedback
var _rejection_message: String = ""
var _rejection_timer: float = 0.0

## Framerate HUD
var fps_display_text: String = ""
var fps_color: Color = Color(0.7, 0.8, 0.9)

## Colors
const COLOR_CIRCLE_WAITING = Color(0.5, 0.5, 0.5, 0.6)
const COLOR_CIRCLE_READY = Color(0.1, 0.9, 0.3, 0.8)
const COLOR_ARROW = Color(1.0, 1.0, 1.0, 0.7)
const COLOR_ARROW_READY = Color(0.1, 0.9, 0.3, 0.7)
const COLOR_STATUS_WAITING = Color(0.7, 0.7, 0.7, 0.9)
const COLOR_STATUS_READY = Color(0.1, 1.0, 0.4, 1.0)
const COLOR_STATUS_TRACKING = Color(1.0, 0.8, 0.2, 1.0)
const COLOR_RESULT = Color(0.3, 0.85, 1.0, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var gs = get_node_or_null("/root/GlobalSettings") if is_inside_tree() else null
	if gs != null and "range_settings" in gs and "putting_camera_circle_x" in gs.range_settings:
		circle_center.x = clampf(float(gs.range_settings.putting_camera_circle_x.value), MIN_CIRCLE_X, MAX_CIRCLE_X)
	# Redraw every frame for smooth animation
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		if not is_dragging and is_hovered:
			is_hovered = false
			mouse_default_cursor_shape = Control.CURSOR_ARROW
			queue_redraw()


func _process(delta: float) -> void:
	if _rejection_timer > 0.0:
		_rejection_timer = maxf(0.0, _rejection_timer - delta)
	queue_redraw()


func _draw() -> void:
	var sz: Vector2 = size
	if sz.x < 1.0 or sz.y < 1.0:
		return

	var center_px: Vector2 = circle_center * sz
	var radius_px: float = circle_radius_norm * sz.x

	# 1. Draw Target Circle
	var circle_color = COLOR_CIRCLE_READY if ball_detected_in_circle else COLOR_CIRCLE_WAITING
	if is_dragging:
		circle_color = Color(0.3, 0.85, 1.0, 0.95)
	draw_arc(center_px, radius_px, 0.0, TAU, 64, circle_color, 2.5, true)
	# Inner crosshair
	draw_line(center_px - Vector2(radius_px * 0.3, 0), center_px + Vector2(radius_px * 0.3, 0), circle_color, 1.0)
	draw_line(center_px - Vector2(0, radius_px * 0.3), center_px + Vector2(0, radius_px * 0.3), circle_color, 1.0)

	# 2. Draw Midline Arrow (from circle center upward = toward target)
	var arrow_color = COLOR_ARROW_READY if ball_detected_in_circle else COLOR_ARROW
	if is_dragging:
		arrow_color = Color(0.3, 0.85, 1.0, 0.95)
	var arrow_start: Vector2 = center_px - Vector2(0, radius_px)
	var arrow_end: Vector2 = center_px - Vector2(0, arrow_length_norm * sz.y)
	draw_line(arrow_start, arrow_end, arrow_color, 2.0, true)
	# Arrowhead
	var head_size: float = 10.0
	draw_line(arrow_end, arrow_end + Vector2(-head_size, head_size), arrow_color, 2.0)
	draw_line(arrow_end, arrow_end + Vector2(head_size, head_size), arrow_color, 2.0)

	# 2b. Drag/Reposition Handles (Left & Right chevrons)
	var handle_color = Color(0.35, 0.90, 1.0, 0.95) if (is_dragging or is_hovered) else Color(1.0, 1.0, 1.0, 0.45)
	var handle_dist = radius_px + 12.0
	var left_hc = center_px - Vector2(handle_dist, 0)
	var right_hc = center_px + Vector2(handle_dist, 0)
	var ah: float = 6.0
	var aw: float = 5.0
	# Left chevron ◀
	draw_line(left_hc + Vector2(aw, -ah), left_hc - Vector2(aw, 0), handle_color, 2.0)
	draw_line(left_hc - Vector2(aw, 0), left_hc + Vector2(aw, ah), handle_color, 2.0)
	# Right chevron ▶
	draw_line(right_hc - Vector2(aw, -ah), right_hc + Vector2(aw, 0), handle_color, 2.0)
	draw_line(right_hc + Vector2(aw, 0), right_hc - Vector2(aw, -ah), handle_color, 2.0)

	var font = ThemeDB.fallback_font
	var font_size: int = 15

	# 2c. Hover or Drag tooltip badge
	if is_dragging or (is_hovered and current_state == 0):
		var pct = int(round(circle_center.x * 100.0))
		var pos_desc = "Center"
		if pct < 48:
			pos_desc = "%d%% Left" % (50 - pct)
		elif pct > 52:
			pos_desc = "%d%% Right" % (pct - 50)
		var hint_text = "◀ Track Line: %s (%d%%) ▶" % [pos_desc, pct] if is_dragging else "◀ Drag to move track line ▶"
		var hint_size = font.get_string_size(hint_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
		var hint_pos = Vector2(center_px.x - hint_size.x / 2.0, center_px.y + radius_px + 16.0)
		if hint_pos.y + hint_size.y > sz.y - 42.0:
			hint_pos.y = center_px.y - radius_px - 20.0
		var hint_rect = Rect2(hint_pos - Vector2(8, 2), hint_size + Vector2(16, 6))
		draw_rect(hint_rect, Color(0.04, 0.07, 0.12, 0.88), true)
		draw_rect(hint_rect, Color(0.3, 0.85, 1.0, 0.8), false, 1.0)
		draw_string(font, hint_pos + Vector2(0, hint_size.y - 2), hint_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.95, 1.0))

	# 3. Draw Mode/Readiness Indicator at the TOP of the feed
	var status_text: String
	var status_color: Color
	match current_state:
		0:  # IDLE
			status_text = "⏳ Place Ball"
			status_color = COLOR_STATUS_WAITING
		1:  # READY
			status_text = "🟢 GREEN READY"
			status_color = COLOR_STATUS_READY
		2:  # TRACKING
			status_text = "📍 Tracking..."
			status_color = COLOR_STATUS_TRACKING
		3:  # EXECUTION
			status_text = "🎯 Ball Tracked"
			status_color = COLOR_RESULT
		_:
			status_text = "⏳ Place Ball"
			status_color = COLOR_STATUS_WAITING

	var status_size: Vector2 = font.get_string_size(status_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var status_pos: Vector2 = Vector2((sz.x - status_size.x) / 2.0 - 12, 14)
	var status_rect: Rect2 = Rect2(status_pos, status_size + Vector2(24, 10))
	draw_rect(status_rect, Color(0.0, 0.0, 0.0, 0.65), true)
	draw_string(font, status_pos + Vector2(12, status_size.y + 2), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, status_color)

	# 3b. Draw FPS Badge in the Top-Right of the feed
	if not fps_display_text.is_empty():
		var fps_font_size: int = 12
		var fps_sz: Vector2 = font.get_string_size(fps_display_text, HORIZONTAL_ALIGNMENT_RIGHT, -1, fps_font_size)
		var fps_pos: Vector2 = Vector2(sz.x - fps_sz.x - 20, 14)
		var fps_rect: Rect2 = Rect2(fps_pos - Vector2(6, 2), fps_sz + Vector2(12, 6))
		draw_rect(fps_rect, Color(0.04, 0.06, 0.10, 0.85), true)
		draw_rect(fps_rect, fps_color * Color(1, 1, 1, 0.7), false, 1.0)
		draw_string(font, fps_pos + Vector2(0, fps_sz.y - 2), fps_display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fps_font_size, fps_color)

	# 4. Draw Speed & Offline Result Stats or Rejection / Mishit Notice at the BOTTOM of the feed
	if _rejection_timer > 0.0 and not _rejection_message.is_empty():
		var rej_size: Vector2 = font.get_string_size(_rejection_message, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var bottom_y: float = sz.y - rej_size.y - 14
		var rej_pos: Vector2 = Vector2((sz.x - rej_size.x) / 2.0 - 14, bottom_y)
		var rej_rect: Rect2 = Rect2(rej_pos, rej_size + Vector2(28, 10))

		# Warm amber/crimson warning pill
		draw_rect(rej_rect, Color(0.24, 0.08, 0.06, 0.94), true)
		draw_rect(rej_rect, Color(1.0, 0.65, 0.15, 0.95), false, 1.5)
		draw_string(font, rej_pos + Vector2(14, rej_size.y + 2), _rejection_message, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.88, 0.45))
	elif last_speed_mph > 0.0:
		var offline_str: String = "0.0°"
		if last_offset_deg > 0.05:
			offline_str = "%.1f° R" % last_offset_deg
		elif last_offset_deg < -0.05:
			offline_str = "%.1f° L" % absf(last_offset_deg)

		var stats_text: String = "⚡ Speed: %.1f mph  |  Offline: %s" % [last_speed_mph, offline_str]
		var stats_size: Vector2 = font.get_string_size(stats_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var bottom_y: float = sz.y - stats_size.y - 14
		var stats_pos: Vector2 = Vector2((sz.x - stats_size.x) / 2.0 - 14, bottom_y)
		var stats_rect: Rect2 = Rect2(stats_pos, stats_size + Vector2(28, 10))

		# Solid dark pill with cyan border
		draw_rect(stats_rect, Color(0.06, 0.10, 0.15, 0.88), true)
		draw_rect(stats_rect, Color(0.3, 0.85, 1.0, 0.7), false, 1.5)
		draw_string(font, stats_pos + Vector2(14, stats_size.y + 2), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, COLOR_RESULT)

	# 5. Debug: draw detected ball position
	if last_ball_position_norm != Vector2.ZERO:
		var ball_px = last_ball_position_norm * sz
		draw_circle(ball_px, 5.0, Color(1.0, 0.3, 0.3, 0.8))

	# 6. Configured Color Swatches (Bottom-Left)
	if ball_color_configured:
		var swatch_pos = Vector2(16, sz.y - 48)
		draw_circle(swatch_pos, 7.0, ball_color_swatch)
		draw_arc(swatch_pos, 7.0, 0.0, TAU, 16, Color.WHITE, 1.2)
		draw_string(font, swatch_pos + Vector2(14, 4), "Ball Color", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.9, 0.95))

	if bg_color_configured:
		var swatch_pos = Vector2(16, sz.y - 28)
		draw_circle(swatch_pos, 7.0, bg_color_swatch)
		draw_arc(swatch_pos, 7.0, 0.0, TAU, 16, Color.WHITE, 1.2)
		draw_string(font, swatch_pos + Vector2(14, 4), "Mat Color", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.9, 0.95))

	# 7. Picker Active Prompt / Reticle
	if picker_active and picker_cursor_pos != Vector2.ZERO:
		draw_arc(picker_cursor_pos, 12.0, 0.0, TAU, 24, Color(1.0, 0.8, 0.2, 0.9), 1.5)
		draw_line(picker_cursor_pos - Vector2(16, 0), picker_cursor_pos + Vector2(16, 0), Color(1.0, 0.8, 0.2, 0.9), 1.0)
		draw_line(picker_cursor_pos - Vector2(0, 16), picker_cursor_pos + Vector2(0, 16), Color(1.0, 0.8, 0.2, 0.9), 1.0)


## Public setters for the state machine to call
func set_state(new_state: int) -> void:
	current_state = new_state


func set_ball_in_circle(in_circle: bool) -> void:
	ball_detected_in_circle = in_circle


func set_ball_position(pos_norm: Vector2) -> void:
	last_ball_position_norm = pos_norm


func set_result(speed_mph: float, offset_deg: float) -> void:
	_rejection_timer = 0.0
	_rejection_message = ""
	last_speed_mph = speed_mph
	last_offset_deg = offset_deg


func show_rejection_notice(msg: String, duration_sec: float = 2.5) -> void:
	_rejection_message = msg
	_rejection_timer = duration_sec
	queue_redraw()


func show_framerate_lock_notice(msg: String, duration_sec: float = 3.0) -> void:
	show_rejection_notice(msg, duration_sec)


func set_fps_metrics(text: String, tier: int = 0) -> void:
	fps_display_text = text
	match tier:
		1: # CRITICAL_LOW
			fps_color = Color(1.0, 0.35, 0.35)
		2: # DEGRADED
			fps_color = Color(1.0, 0.85, 0.25)
		3: # STABLE
			fps_color = Color(0.25, 0.95, 0.5)
		4: # HIGH_PRECISION
			fps_color = Color(0.35, 0.85, 1.0)
		_:
			fps_color = Color(0.7, 0.8, 0.9)
	queue_redraw()


func reset_stats() -> void:
	last_speed_mph = 0.0
	last_offset_deg = 0.0
	_rejection_message = ""
	_rejection_timer = 0.0


## Returns the circle center in pixel coordinates for the given control size
func get_circle_center_px() -> Vector2:
	return circle_center * size


## Returns the midline arrow direction (normalized, pointing toward target)
func get_midline_direction() -> Vector2:
	return Vector2.UP  # Arrow points upward in screen space = toward target


## Sets the horizontal placement of the ball circle and tracking line (clamped between MIN_CIRCLE_X and MAX_CIRCLE_X)
func set_circle_x(val: float, save_to_settings: bool = true) -> void:
	var clamped_x = clampf(val, MIN_CIRCLE_X, MAX_CIRCLE_X)
	if not is_equal_approx(circle_center.x, clamped_x):
		circle_center.x = clamped_x
		circle_position_changed.emit(circle_center)
		if save_to_settings and is_inside_tree():
			var gs = get_node_or_null("/root/GlobalSettings")
			if gs != null and "range_settings" in gs and "putting_camera_circle_x" in gs.range_settings:
				gs.range_settings.putting_camera_circle_x.set_value(clamped_x)
				gs.save_settings()
		queue_redraw()


func get_circle_x() -> float:
	return circle_center.x


func reset_circle_x() -> void:
	set_circle_x(0.50, true)


## Hit test to check if mouse/touch pos is close enough to target circle or midline arrow to initiate drag
func _is_pos_near_target(pos: Vector2) -> bool:
	if size.x < 1.0 or size.y < 1.0:
		return false
	var center_px: Vector2 = circle_center * size
	var radius_px: float = circle_radius_norm * sz_x_compat()
	# Check distance to circle (including handles)
	if pos.distance_to(center_px) <= radius_px + 28.0:
		return true
	# Check distance to vertical arrow line
	var arrow_start_y = center_px.y - radius_px
	var arrow_end_y = center_px.y - arrow_length_norm * size.y
	var min_y = minf(arrow_start_y, arrow_end_y) - 16.0
	var max_y = maxf(arrow_start_y, arrow_end_y) + 16.0
	if pos.y >= min_y and pos.y <= max_y and absf(pos.x - center_px.x) <= 28.0:
		return true
	return false


func sz_x_compat() -> float:
	return size.x


func _gui_input(event: InputEvent) -> void:
	if picker_active:
		return

	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _is_pos_near_target(mb.position):
					is_dragging = true
					_drag_offset_x = circle_center.x - (mb.position.x / maxf(size.x, 1.0))
					queue_redraw()
					accept_event()
			else:
				if is_dragging:
					is_dragging = false
					set_circle_x(circle_center.x, true)
					queue_redraw()
					accept_event()

	elif event is InputEventMouseMotion:
		var mm = event as InputEventMouseMotion
		if is_dragging:
			var target_norm_x = (mm.position.x / maxf(size.x, 1.0)) + _drag_offset_x
			set_circle_x(target_norm_x, false)
			accept_event()
		else:
			var was_hovered = is_hovered
			is_hovered = _is_pos_near_target(mm.position)
			if is_hovered != was_hovered:
				queue_redraw()
			if is_hovered:
				mouse_default_cursor_shape = Control.CURSOR_HSIZE
			else:
				mouse_default_cursor_shape = Control.CURSOR_ARROW

	elif event is InputEventScreenTouch:
		var st = event as InputEventScreenTouch
		if st.pressed:
			if _is_pos_near_target(st.position):
				is_dragging = true
				_drag_offset_x = circle_center.x - (st.position.x / maxf(size.x, 1.0))
				queue_redraw()
				accept_event()
		else:
			if is_dragging:
				is_dragging = false
				set_circle_x(circle_center.x, true)
				queue_redraw()
				accept_event()

	elif event is InputEventScreenDrag:
		var sd = event as InputEventScreenDrag
		if is_dragging:
			var target_norm_x = (sd.position.x / maxf(size.x, 1.0)) + _drag_offset_x
			set_circle_x(target_norm_x, false)
			accept_event()
