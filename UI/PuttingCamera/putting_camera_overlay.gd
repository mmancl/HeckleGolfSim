class_name PuttingCameraOverlay
extends Control

## Configuration — all in normalized coordinates (0.0–1.0 relative to control size)
## Configuration — all in normalized coordinates (0.0–1.0 relative to control size)
var circle_center: Vector2 = Vector2(0.5, 0.70)   # Centered horizontally, lower third of frame
var circle_radius_norm: float = 0.16              # ~16% of frame width (comfortable placement zone)
var arrow_length_norm: float = 0.45               # Arrow extends upward toward target

## State (set by PuttingCameraStateMachine)
var current_state: int = 0   # 0=IDLE, 1=READY, 2=TRACKING, 3=EXECUTION
var ball_detected_in_circle: bool = false
var last_ball_position_norm: Vector2 = Vector2.ZERO  # For debug visualization
var last_speed_mph: float = 0.0
var last_offset_deg: float = 0.0

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
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Redraw every frame for smooth animation
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var sz: Vector2 = size
	if sz.x < 1.0 or sz.y < 1.0:
		return

	var center_px: Vector2 = circle_center * sz
	var radius_px: float = circle_radius_norm * sz.x

	# 1. Draw Target Circle
	var circle_color = COLOR_CIRCLE_READY if ball_detected_in_circle else COLOR_CIRCLE_WAITING
	draw_arc(center_px, radius_px, 0.0, TAU, 64, circle_color, 2.5, true)
	# Inner crosshair
	draw_line(center_px - Vector2(radius_px * 0.3, 0), center_px + Vector2(radius_px * 0.3, 0), circle_color, 1.0)
	draw_line(center_px - Vector2(0, radius_px * 0.3), center_px + Vector2(0, radius_px * 0.3), circle_color, 1.0)

	# 2. Draw Midline Arrow (from circle center upward = toward target)
	var arrow_color = COLOR_ARROW_READY if ball_detected_in_circle else COLOR_ARROW
	var arrow_start: Vector2 = center_px - Vector2(0, radius_px)
	var arrow_end: Vector2 = center_px - Vector2(0, arrow_length_norm * sz.y)
	draw_line(arrow_start, arrow_end, arrow_color, 2.0, true)
	# Arrowhead
	var head_size: float = 10.0
	draw_line(arrow_end, arrow_end + Vector2(-head_size, head_size), arrow_color, 2.0)
	draw_line(arrow_end, arrow_end + Vector2(head_size, head_size), arrow_color, 2.0)

	var font = ThemeDB.fallback_font
	var font_size: int = 15

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

	# 4. Draw Speed & Offline Result Stats at the BOTTOM of the feed (Persists until next hit)
	if last_speed_mph > 0.0:
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


## Public setters for the state machine to call
func set_state(new_state: int) -> void:
	current_state = new_state


func set_ball_in_circle(in_circle: bool) -> void:
	ball_detected_in_circle = in_circle


func set_ball_position(pos_norm: Vector2) -> void:
	last_ball_position_norm = pos_norm


func set_result(speed_mph: float, offset_deg: float) -> void:
	last_speed_mph = speed_mph
	last_offset_deg = offset_deg


func reset_stats() -> void:
	last_speed_mph = 0.0
	last_offset_deg = 0.0


## Returns the circle center in pixel coordinates for the given control size
func get_circle_center_px() -> Vector2:
	return circle_center * size


## Returns the midline arrow direction (normalized, pointing toward target)
func get_midline_direction() -> Vector2:
	return Vector2.UP  # Arrow points upward in screen space = toward target
