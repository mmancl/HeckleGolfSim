extends CanvasLayer

# ReadyIndicatorHUD
# Positioned overlay showing Launch Monitor ball readiness status ONLY during active gameplay,
# featuring a visual Ball Placement Zone Box underneath that guides ball positioning
# and automatically fades away once the ball is placed in the correct target spot.

enum ScreenLayout {
	HIDDEN,                 # Main menu, course selection, setup, history, analytics
	TOP_CENTER_UNDER_AIM,   # Driving Range, Full Course Play (positioned directly under Aim distance pill)
	TOP_LEFT                # Chipping & Putting practice (positioned top-left to clear minigame scoreboard)
}

var _container: MarginContainer
var _main_vbox: VBoxContainer
var _panel: PanelContainer
var _hbox: HBoxContainer
var _dot_panel: Panel
var _status_label: Label
var _sub_label: Label
var _glow_style: StyleBoxFlat
var _tween: Tween = null
var _pulse_tween: Tween = null

# Visual Placement Guide Box nodes
var _placement_panel: PanelContainer
var _placement_canvas: Control
var _placement_glow_style: StyleBoxFlat
var _guide_label: Label

const MAX_SENSING_RANGE_MM := 127.0 # 5.0 inches half-width / half-depth (10" x 10" full area)
const TARGET_ZONE_RANGE_MM := 76.2  # 3.0 inches half-width / half-depth (6" x 6" full zone)

# Sensor & Position state
var _is_ready := false
var _status_text := "Disconnected"
var _visible_mode := true
var _placement_guide_enabled := true
var _current_layout := ScreenLayout.HIDDEN
var _check_timer := 0.0
var _cached_ball: Node = null
var _ball_moving_prev := false
var _shot_active := false
var _rearm_feedback_timer := 0.0
var _last_rendered_ready := false
var _last_rendered_visible := false

var _sensor_pos_x := 0
var _sensor_pos_y := 0
var _sensor_pos_z := 0
var _sensor_ready := false
var _sensor_detected := false
var _has_sensor_data := false
var _sensor_unit_scale := 0.0 # Auto-calibrated scale multiplier to convert raw sensor coordinates to mm
var _displayed_norm_pos := Vector2.ZERO # Smoothly interpolated normalized ball position
var _last_ball_pos := Vector3.ZERO


func _ready() -> void:
	layer = 90
	process_mode = PROCESS_MODE_ALWAYS
	_setup_ui()
	
	if has_node("/root/SceneManager"):
		var scn_mgr = get_node("/root/SceneManager")
		if scn_mgr.has_signal("scene_changed"):
			scn_mgr.scene_changed.connect(_on_scene_changed)

	if has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if lm.has_signal("hit_ball") and not lm.is_connected("hit_ball", _on_lm_hit_ball):
			lm.connect("hit_ball", _on_lm_hit_ball)
			
	_refresh_layout_and_display(true)


func _on_lm_hit_ball(_data: Dictionary) -> void:
	notify_shot_started()


func notify_shot_started() -> void:
	_shot_active = true
	_ball_moving_prev = true
	if visible:
		visible = false
		_stop_pulse_animation()
		_last_rendered_visible = false


func notify_ball_at_rest() -> void:
	_shot_active = false
	_ball_moving_prev = false
	_update_display(false)


func is_ball_in_flight() -> bool:
	if _shot_active:
		var b := _get_golf_ball()
		if b != null and is_instance_valid(b):
			if _is_ball_at_rest(b):
				_shot_active = false
		else:
			var scn := _get_active_scene()
			if scn != null and not _check_scene_shot_active(scn):
				_shot_active = false
		if _shot_active:
			return true

	var ball := _get_golf_ball()
	if ball != null and is_instance_valid(ball):
		if not _is_ball_at_rest(ball):
			return true

	var scene := _get_active_scene()
	if scene != null and is_instance_valid(scene):
		if _check_scene_shot_active(scene):
			return true

	return false


func _is_ball_at_rest(ball: Node) -> bool:
	if ball == null or not is_instance_valid(ball):
		return true

	if "state" in ball and ball.state != 0: # 0 is PhysicsEnums.BallState.REST
		return false

	var vel: Vector3 = ball.velocity if "velocity" in ball else (ball.linear_velocity if "linear_velocity" in ball else Vector3.ZERO)
	if vel.length() > 0.05:
		return false

	if "is_falling_in_hole" in ball and bool(ball.get("is_falling_in_hole")):
		return false

	return true


func _check_scene_shot_active(scene: Node) -> bool:
	if scene == null or not is_instance_valid(scene):
		return false

	if "_shot_active" in scene and bool(scene.get("_shot_active")):
		return true

	if "_shot_transition_active" in scene and bool(scene.get("_shot_transition_active")):
		return true

	if "course_instance" in scene:
		var ci = scene.get("course_instance")
		if ci != null and is_instance_valid(ci):
			if "_shot_active" in ci and bool(ci.get("_shot_active")):
				return true
			if "_shot_transition_active" in ci and bool(ci.get("_shot_transition_active")):
				return true

	var player_node = _find_player_node(scene)
	if player_node != null and is_instance_valid(player_node):
		if player_node.has_method("get_ball_state"):
			var st = player_node.call("get_ball_state")
			if st != null and int(st) != 0:
				return true
		if "track_points" in player_node and bool(player_node.get("track_points")):
			return true
		if "ball" in player_node and player_node.ball != null:
			if not _is_ball_at_rest(player_node.ball):
				return true

	if scene.has_node("course_scene"):
		var cs = scene.get_node("course_scene")
		if cs != null and is_instance_valid(cs):
			if "_shot_active" in cs and bool(cs.get("_shot_active")):
				return true
			if "_shot_transition_active" in cs and bool(cs.get("_shot_transition_active")):
				return true

	return false


func _find_player_node(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if "ball" in node:
		return node
	if node.has_node("Player"):
		return node.get_node("Player")
	if "player" in node and node.get("player") is Node:
		return node.get("player")
	for child in node.get_children():
		if "ball" in child:
			return child
		if child.name == "Player":
			return child
	return null


func _process(delta: float) -> void:
	var in_flight := is_ball_in_flight()

	if in_flight != _ball_moving_prev:
		_ball_moving_prev = in_flight
		if in_flight:
			_shot_active = true
		else:
			_shot_active = false
		_update_display(true)

	if in_flight:
		if visible:
			visible = false
			_stop_pulse_animation()
			_last_rendered_visible = false
		return

	var target_norm_pos := _get_normalized_ball_position()
	# Smoothly interpolate displayed position so ball moves fluidly without discrete quadrant jumping
	_displayed_norm_pos = _displayed_norm_pos.lerp(target_norm_pos, clampf(delta * 18.0, 0.0, 1.0))
	if _placement_canvas != null and is_instance_valid(_placement_canvas) and _placement_panel != null and _placement_panel.visible:
		_placement_canvas.queue_redraw()

	if _rearm_feedback_timer > 0.0:
		_rearm_feedback_timer = maxf(0.0, _rearm_feedback_timer - delta)
		if _rearm_feedback_timer == 0.0:
			_update_display(true)

	_check_timer += delta
	if _check_timer >= 0.05:
		_check_timer = 0.0
		var layout := _detect_current_gameplay_screen()
		if layout != _current_layout:
			_apply_layout(layout)
		_update_display(false)


func _on_scene_changed() -> void:
	_cached_ball = null
	_ball_moving_prev = false
	_shot_active = false
	_has_sensor_data = false
	_sensor_unit_scale = 0.0
	_displayed_norm_pos = Vector2.ZERO
	_last_ball_pos = Vector3.ZERO
	call_deferred("_refresh_layout_and_display", true)


func set_sensor_position(pos_x: int, pos_y: int, pos_z: int, ready: bool, detected: bool) -> void:
	_sensor_pos_x = pos_x
	_sensor_pos_y = pos_y
	_sensor_pos_z = pos_z
	_sensor_ready = ready
	_sensor_detected = detected
	_has_sensor_data = true

	if is_ball_in_flight():
		return

	if _placement_canvas != null and is_instance_valid(_placement_canvas):
		_placement_canvas.queue_redraw()
	_update_guidance_text()


func set_placement_guide_enabled(enabled: bool) -> void:
	_placement_guide_enabled = enabled
	if _placement_panel != null and is_instance_valid(_placement_panel):
		_placement_panel.visible = enabled
	_update_display(false)


func _setup_ui() -> void:
	_container = MarginContainer.new()
	_container.name = "ReadyHUDContainer"
	_container.anchors_preset = Control.PRESET_CENTER_TOP
	_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_container.grow_vertical = Control.GROW_DIRECTION_END
	_container.add_theme_constant_override("margin_top", 78)
	add_child(_container)

	_main_vbox = VBoxContainer.new()
	_main_vbox.name = "ReadyHUDVBox"
	_main_vbox.add_theme_constant_override("separation", 6)
	_container.add_child(_main_vbox)

	# Top Status Badge Pill (interactive: click/tap to re-arm/wake launch monitor)
	_panel = PanelContainer.new()
	_panel.name = "StatusBadge"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_panel.tooltip_text = "Click to re-arm / wake launch monitor (or press 'R')"
	_panel.gui_input.connect(_on_status_badge_gui_input)
	_main_vbox.add_child(_panel)

	_glow_style = StyleBoxFlat.new()
	_glow_style.corner_radius_top_left = 18
	_glow_style.corner_radius_top_right = 18
	_glow_style.corner_radius_bottom_left = 18
	_glow_style.corner_radius_bottom_right = 18
	_glow_style.bg_color = Color(0.06, 0.12, 0.09, 0.88)
	_glow_style.border_width_left = 2
	_glow_style.border_width_top = 2
	_glow_style.border_width_right = 2
	_glow_style.border_width_bottom = 2
	_glow_style.border_color = Color(0.18, 0.8, 0.44, 0.8)
	_glow_style.content_margin_left = 16
	_glow_style.content_margin_right = 18
	_glow_style.content_margin_top = 8
	_glow_style.content_margin_bottom = 8
	_glow_style.shadow_color = Color(0, 0, 0, 0.35)
	_glow_style.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", _glow_style)

	_hbox = HBoxContainer.new()
	_hbox.add_theme_constant_override("separation", 10)
	_panel.add_child(_hbox)

	# LED Dot Container
	var dot_center = CenterContainer.new()
	dot_center.custom_minimum_size = Vector2(16, 16)
	_hbox.add_child(dot_center)

	_dot_panel = Panel.new()
	_dot_panel.custom_minimum_size = Vector2(12, 12)
	var dot_style = StyleBoxFlat.new()
	dot_style.corner_radius_top_left = 6
	dot_style.corner_radius_top_right = 6
	dot_style.corner_radius_bottom_left = 6
	dot_style.corner_radius_bottom_right = 6
	dot_style.bg_color = Color(0.18, 0.8, 0.44)
	_dot_panel.add_theme_stylebox_override("panel", dot_style)
	dot_center.add_child(_dot_panel)

	var text_vbox = VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", -2)
	_hbox.add_child(text_vbox)

	_status_label = Label.new()
	_status_label.text = "BALL READY"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(1, 1, 1))
	text_vbox.add_child(_status_label)

	_sub_label = Label.new()
	_sub_label.text = "READY TO HIT"
	_sub_label.add_theme_font_size_override("font_size", 12)
	_sub_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.75))
	text_vbox.add_child(_sub_label)

	# Setup Visual Ball Placement Box UI directly under the ready badge
	_setup_placement_box_ui()


func _setup_placement_box_ui() -> void:
	_placement_panel = PanelContainer.new()
	_placement_panel.name = "BallPlacementGuideBox"
	_placement_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placement_panel.custom_minimum_size = Vector2(210, 140)

	_placement_glow_style = StyleBoxFlat.new()
	_placement_glow_style.corner_radius_top_left = 14
	_placement_glow_style.corner_radius_top_right = 14
	_placement_glow_style.corner_radius_bottom_left = 14
	_placement_glow_style.corner_radius_bottom_right = 14
	_placement_glow_style.bg_color = Color(0.05, 0.08, 0.12, 0.92)
	_placement_glow_style.border_width_left = 2
	_placement_glow_style.border_width_top = 2
	_placement_glow_style.border_width_right = 2
	_placement_glow_style.border_width_bottom = 2
	_placement_glow_style.border_color = Color(0.2, 0.6, 0.9, 0.7)
	_placement_glow_style.content_margin_left = 8
	_placement_glow_style.content_margin_right = 8
	_placement_glow_style.content_margin_top = 8
	_placement_glow_style.content_margin_bottom = 8
	_placement_glow_style.shadow_color = Color(0, 0, 0, 0.4)
	_placement_glow_style.shadow_size = 10
	_placement_panel.add_theme_stylebox_override("panel", _placement_glow_style)

	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 4)
	_placement_panel.add_child(inner_vbox)

	# Header text
	var header = Label.new()
	header.text = "BALL PLACEMENT ZONE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.65, 0.8, 0.95))
	inner_vbox.add_child(header)

	# Custom Canvas for zone rectangle & ball dot
	_placement_canvas = Control.new()
	_placement_canvas.custom_minimum_size = Vector2(194, 94)
	_placement_canvas.draw.connect(_on_placement_canvas_draw)
	inner_vbox.add_child(_placement_canvas)

	# Guidance label
	_guide_label = Label.new()
	_guide_label.text = "PLACE BALL IN TARGET ZONE"
	_guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guide_label.add_theme_font_size_override("font_size", 12)
	_guide_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
	inner_vbox.add_child(_guide_label)

	_main_vbox.add_child(_placement_panel)
	_placement_panel.visible = _placement_guide_enabled
	_placement_panel.modulate.a = 1.0


func _on_placement_canvas_draw() -> void:
	if _placement_canvas == null or not is_instance_valid(_placement_canvas):
		return

	var size := _placement_canvas.size
	var center := size / 2.0
	var font := ThemeDB.fallback_font

	# 1. Background Grid & Outer Sensing Boundaries
	var outer_margin_x := 18.0
	var outer_margin_y := 12.0
	var outer_rect := Rect2(
		Vector2(outer_margin_x, outer_margin_y),
		Vector2(size.x - (outer_margin_x * 2.0), size.y - (outer_margin_y * 2.0))
	)
	_placement_canvas.draw_rect(outer_rect, Color(0.08, 0.12, 0.18, 0.6), true)
	_placement_canvas.draw_rect(outer_rect, Color(0.22, 0.32, 0.45, 0.5), false, 1.0)

	# 2. Directional Indicators around outer box (Player perspective facing monitor)
	var label_color := Color(0.55, 0.7, 0.85, 0.65)
	if font != null:
		# Top: Away (toward monitor)
		_placement_canvas.draw_string(font, Vector2(center.x - 28, outer_rect.position.y - 3), "▲ AWAY", HORIZONTAL_ALIGNMENT_CENTER, 56, 10, label_color)
		# Bottom: Closer (toward player)
		_placement_canvas.draw_string(font, Vector2(center.x - 32, outer_rect.end.y + 10), "▼ CLOSER", HORIZONTAL_ALIGNMENT_CENTER, 64, 10, label_color)
		# Left: Player's Left
		_placement_canvas.draw_string(font, Vector2(1, center.y + 3), "◀ L", HORIZONTAL_ALIGNMENT_LEFT, 16, 10, label_color)
		# Right: Player's Right / Target
		_placement_canvas.draw_string(font, Vector2(size.x - 17, center.y + 3), "R ▶", HORIZONTAL_ALIGNMENT_RIGHT, 16, 10, label_color)

	# 3. Optimal Allowed Target Zone Box (±3.0 inches / ±76.2mm inside ±5.0 inches / ±127.0mm outer sensing zone = 60% ratio)
	var target_zone_ratio := TARGET_ZONE_RANGE_MM / MAX_SENSING_RANGE_MM # 0.60
	var zone_w := outer_rect.size.x * target_zone_ratio
	var zone_h := outer_rect.size.y * target_zone_ratio
	var zone_rect := Rect2(center - Vector2(zone_w / 2.0, zone_h / 2.0), Vector2(zone_w, zone_h))

	# Color zone box according to current status
	var zone_color := Color(0.2, 0.9, 0.45, 0.85) if _is_ready else Color(0.95, 0.65, 0.15, 0.8)
	var zone_bg := Color(0.08, 0.28, 0.16, 0.35) if _is_ready else Color(0.3, 0.2, 0.05, 0.3)
	_placement_canvas.draw_rect(zone_rect, zone_bg, true)
	_placement_canvas.draw_rect(zone_rect, zone_color, false, 1.5)

	# 4. Crosshairs
	_placement_canvas.draw_line(Vector2(center.x, outer_rect.position.y + 3), Vector2(center.x, outer_rect.end.y - 3), Color(1, 1, 1, 0.18), 1.0)
	_placement_canvas.draw_line(Vector2(outer_rect.position.x + 3, center.y), Vector2(outer_rect.end.x - 3, center.y), Color(1, 1, 1, 0.18), 1.0)

	# 5. Target Zone Center Reticle
	_placement_canvas.draw_circle(center, 2.0, Color(1, 1, 1, 0.4))

	# 6. Get Ball Offset Position - continuous & proportional to real-world offset
	var norm_x: float = _displayed_norm_pos.x
	var norm_y: float = _displayed_norm_pos.y

	var max_offset_x := (outer_rect.size.x / 2.0) - 7.0
	var max_offset_y := (outer_rect.size.y / 2.0) - 7.0
	var ball_center := center + Vector2(norm_x * max_offset_x, norm_y * max_offset_y)

	# Clamp inside outer bounding box
	ball_center.x = clampf(ball_center.x, outer_rect.position.x + 6, outer_rect.end.x - 6)
	ball_center.y = clampf(ball_center.y, outer_rect.position.y + 6, outer_rect.end.y - 6)

	# If hardware reports no ball detected, draw a pulsing searching target indicator instead of a phantom ball
	if _has_sensor_data and not _sensor_detected:
		var pulse := (sin(Time.get_ticks_msec() / 150.0) + 1.0) * 0.5
		var search_ring_color := Color(0.9, 0.7, 0.2, 0.3 + (pulse * 0.4))
		_placement_canvas.draw_arc(center, 10.0 + (pulse * 3.0), 0, TAU, 24, search_ring_color, 1.5)
		_placement_canvas.draw_circle(center, 3.0, Color(0.9, 0.7, 0.2, 0.5))
		return

	# Ball color coding: green when ready, amber when in zone/approaching, red when outside target zone
	var ball_glow_color := Color(0.2, 0.95, 0.45, 0.6)
	if not _is_ready:
		if absf(norm_x) > target_zone_ratio or absf(norm_y) > target_zone_ratio:
			ball_glow_color = Color(0.95, 0.25, 0.2, 0.75) # Red when outside target zone
		else:
			ball_glow_color = Color(0.95, 0.7, 0.15, 0.7) # Amber when inside target zone settling

	# Draw Ball Outer Glow & Shadow
	_placement_canvas.draw_circle(ball_center + Vector2(1, 2), 8.0, Color(0, 0, 0, 0.35))
	_placement_canvas.draw_circle(ball_center, 9.0, ball_glow_color)

	# Draw Golf Ball Body
	_placement_canvas.draw_circle(ball_center, 6.0, Color(0.96, 0.98, 1.0))
	_placement_canvas.draw_arc(ball_center, 6.0, 0, TAU, 16, Color(0.3, 0.3, 0.3, 0.6), 1.0)
	_placement_canvas.draw_circle(ball_center + Vector2(-1.5, -1.5), 2.0, Color(1, 1, 1, 0.9)) # Specular highlight


func _raw_sensor_to_mm(raw_val: float) -> float:
	if raw_val == 0.0:
		return 0.0

	var abs_val := absf(raw_val)
	# Determine and adapt the unit scale multiplier based on value magnitude:
	# 1) Hundredths of mm (e.g. 2540 = 25.4 mm = 1.0 inch)
	if abs_val > 1500.0:
		_sensor_unit_scale = 0.01
	# 2) Tenths of mm (e.g. 254 = 25.4 mm = 1.0 inch)
	elif abs_val > 150.0 and (_sensor_unit_scale == 0.0 or _sensor_unit_scale > 0.1):
		_sensor_unit_scale = 0.1
	# 3) Millimeters (e.g. 25.4 = 1.0 inch)
	elif abs_val > 5.0 and (_sensor_unit_scale == 0.0 or _sensor_unit_scale > 1.0):
		_sensor_unit_scale = 1.0
	# Default to 1.0 (millimeters) if uncalibrated
	elif _sensor_unit_scale == 0.0:
		_sensor_unit_scale = 1.0

	return raw_val * _sensor_unit_scale


func _get_normalized_ball_position() -> Vector2:
	if _has_sensor_data:
		if not _sensor_detected:
			return Vector2.ZERO
		# Convert raw hardware sensor coordinates to physical millimeters:
		# PositionX: lateral offset in mm (0 center, ±76.2mm inside target zone)
		# PositionY: depth offset in mm (0 center, ±76.2mm inside target zone)
		# Player perspective: Left/Right is X axis, Away/Closer is Y axis
		var mm_x := _raw_sensor_to_mm(float(_sensor_pos_x))
		var mm_y := _raw_sensor_to_mm(float(_sensor_pos_y))

		# Proportional normalized coordinates (-1.0 to 1.0 across full 5" sensing boundary)
		# 1 inch (25.4mm) -> 0.20 offset, 2 inches (50.8mm) -> 0.40 offset, 3 inches (76.2mm) -> 0.60 offset
		var nx := clampf(mm_x / MAX_SENSING_RANGE_MM, -1.0, 1.0)
		# ny < 0 is Away (top of screen) and ny > 0 is Closer (bottom of screen)
		var ny := clampf(-mm_y / MAX_SENSING_RANGE_MM, -1.0, 1.0)
		return Vector2(nx, ny)

	# Fallback in-game ball offset when hardware sensor packet is not active
	var ball := _get_golf_ball()
	if ball != null and is_instance_valid(ball):
		# In Godot 3D world:
		# +X is target direction (Player's Right)
		# -X is behind tee (Player's Left)
		# +Z is toward screen/LM (Away from player)
		# -Z is toward player's stance (Closer to player)
		var vel: Vector3 = ball.velocity if "velocity" in ball else (ball.linear_velocity if "linear_velocity" in ball else Vector3.ZERO)
		var speed: float = vel.length()
		if speed > 0.05:
			# Dynamic offset visualization during ball movement
			var h_vel := Vector2(vel.x, vel.z).normalized()
			return Vector2(clampf(h_vel.x * 0.75, -1.0, 1.0), clampf(-h_vel.y * 0.75, -1.0, 1.0))

		var spawn_pos: Vector3 = ball.spawn_position if "spawn_position" in ball else Vector3.ZERO
		var rel_pos: Vector3 = ball.global_position - spawn_pos
		# 0.127 meters in Godot 3D = 127mm = 5.0 inches max sensing half-range
		if rel_pos.length() > 0.001:
			var nx := clampf(rel_pos.x / 0.127, -1.0, 1.0)
			var ny := clampf(-rel_pos.z / 0.127, -1.0, 1.0)
			return Vector2(nx, ny)

	return Vector2.ZERO


func _update_guidance_text() -> void:
	if _guide_label == null or not is_instance_valid(_guide_label):
		return

	if _is_ready:
		_guide_label.text = "✓ BALL IN TARGET ZONE"
		_guide_label.add_theme_color_override("font_color", Color(0.3, 0.95, 0.5))
		if _placement_glow_style:
			_placement_glow_style.border_color = Color(0.2, 0.9, 0.45, 0.8)
			_placement_glow_style.bg_color = Color(0.05, 0.14, 0.08, 0.92)
		return

	if _has_sensor_data and not _sensor_detected:
		_guide_label.text = "PLACE BALL ON MAT"
		_guide_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
		if _placement_glow_style:
			_placement_glow_style.border_color = Color(0.9, 0.65, 0.2, 0.7)
			_placement_glow_style.bg_color = Color(0.12, 0.09, 0.05, 0.9)
		return

	var norm := _get_normalized_ball_position()
	var hints: Array[String] = []

	# Player perspective when standing facing monitor:
	# norm.x < 0 -> ball is to player's Left -> move right toward center
	# norm.x > 0 -> ball is to player's Right -> move left toward center
	# norm.y < 0 -> ball is Away (toward monitor) -> move closer toward player
	# norm.y > 0 -> ball is Closer (toward player's feet) -> move away toward monitor
	if norm.x < -0.15:
		hints.append("Move Right →")
	elif norm.x > 0.15:
		hints.append("← Move Left")

	if norm.y < -0.15:
		hints.append("↓ Move Closer")
	elif norm.y > 0.15:
		hints.append("Move Away ↑")

	if hints.size() > 0:
		_guide_label.text = " & ".join(hints).to_upper()
		_guide_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
		if _placement_glow_style:
			_placement_glow_style.border_color = Color(0.9, 0.65, 0.2, 0.7)
			_placement_glow_style.bg_color = Color(0.12, 0.09, 0.05, 0.9)
	else:
		_guide_label.text = "CENTERING BALL IN ZONE..."
		_guide_label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))


func set_ready_status(is_ready: bool, status: String, enabled: bool = true) -> void:
	_visible_mode = enabled
	_is_ready = is_ready
	_status_text = status
	_refresh_layout_and_display(false)


func _refresh_layout_and_display(instant: bool = false) -> void:
	var layout := _detect_current_gameplay_screen()
	_apply_layout(layout)
	_update_display(instant)


func _get_active_scene() -> Node:
	if has_node("/root/SceneManager"):
		var scn_mgr = get_node("/root/SceneManager")
		var scn = scn_mgr.get("current_scene") as Node
		if scn != null and is_instance_valid(scn):
			return scn
	var tree := get_tree()
	if tree != null:
		return tree.current_scene
	return null


func _detect_current_gameplay_screen() -> ScreenLayout:
	var scene := _get_active_scene()
	if scene == null:
		return ScreenLayout.HIDDEN

	# Check if current screen is a non-gameplay menu/selection screen
	if _is_menu_screen(scene):
		return ScreenLayout.HIDDEN

	var scene_name := str(scene.name).to_lower()
	var script: Script = scene.get_script()
	var script_path := str(script.resource_path).to_lower() if script != null else ""
	var file_path := str(scene.scene_file_path).to_lower() if "scene_file_path" in scene else ""

	var full_id := (scene_name + " " + script_path + " " + file_path).to_lower()

	# Chipping Minigame, Putting Practice, Shape Practice, Loft Control -> TOP_LEFT
	if full_id.contains("chipping") or scene_name.contains("chipping") \
		or full_id.contains("putting") or scene_name.contains("putting") \
		or full_id.contains("shape") or scene_name.contains("shape") \
		or full_id.contains("loft") or scene_name.contains("loft"):
		return ScreenLayout.TOP_LEFT

	# Driving Range, Course Play, CourseManager, and all loaded course scenes -> TOP_CENTER_UNDER_AIM
	return ScreenLayout.TOP_CENTER_UNDER_AIM


func _is_menu_screen(scene: Node) -> bool:
	if scene == null:
		return true

	var scene_name := str(scene.name).to_lower()
	var script: Script = scene.get_script()
	var script_path := str(script.resource_path).to_lower() if script != null else ""
	var file_path := str(scene.scene_file_path).to_lower() if "scene_file_path" in scene else ""

	var full_id := (scene_name + " " + script_path + " " + file_path).to_lower()

	# Explicit list of menu / selection / setup / analytics / creator screens
	if full_id.contains("main_menu") or full_id.contains("mainmenu") \
		or full_id.contains("course_selector") or full_id.contains("courseselector") \
		or full_id.contains("course_play_setup") or full_id.contains("courseplaysetup") \
		or full_id.contains("minigames_menu") or full_id.contains("minigamesmenu") \
		or full_id.contains("players_menu") or full_id.contains("playersmenu") \
		or full_id.contains("analytics") or full_id.contains("history") \
		or full_id.contains("custom_course_creator") or full_id.contains("osm_download") \
		or full_id.contains("course_preview"):
		return true

	return false


func _is_device_connected() -> bool:
	var st := ""
	var ready := _is_ready

	if has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if lm != null and is_instance_valid(lm):
			ready = ready or lm.is_ready
			st = str(lm.status).to_lower()

	if st == "":
		st = _status_text.to_lower()

	if ready:
		return true

	if (st.contains("connected") and not st.contains("disconnected")) or st == "ready" or st.contains("detecting"):
		return true

	return false


func _is_in_aerial_or_map_view(scene: Node) -> bool:
	if scene == null or not is_instance_valid(scene):
		return false

	# 1. Viewport camera check: if active camera is AerialCamera, aerial view is active
	var vp := get_viewport()
	if vp != null:
		var active_cam := vp.get_camera_3d()
		if active_cam != null and is_instance_valid(active_cam):
			var cam_name := str(active_cam.name).to_lower()
			if cam_name == "aerialcamera" or (cam_name.contains("aerial") and not cam_name.contains("minimap")):
				return true

	# 2. Check scene and all active scene tree nodes recursively
	return _check_aerial_in_subtree(scene)


func _check_aerial_in_subtree(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	# Check aerial properties on any node (e.g. Range, Course, CoursePlay)
	if "is_aerial_view" in node and bool(node.get("is_aerial_view")):
		return true
	if "is_sky_view_active" in node and bool(node.get("is_sky_view_active")):
		return true
	if "_is_aerial_active_practice" in node and bool(node.get("_is_aerial_active_practice")):
		return true

	# Check Camera3D current status
	if node is Camera3D:
		var c_name := str(node.name).to_lower()
		if (c_name == "aerialcamera" or (c_name.contains("aerial") and not c_name.contains("minimap"))) and (node as Camera3D).current:
			return true

	# Check Aerial controls (e.g. AerialZoomVBox inside MapCanvas)
	if node is Control:
		var n_name := str(node.name).to_lower()
		if n_name == "aerialzoomvbox" and _is_node_visible_in_tree(node):
			return true

	for child in node.get_children():
		if _check_aerial_in_subtree(child):
			return true

	return false


func _is_node_visible_in_tree(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is CanvasItem and not (node as CanvasItem).visible:
		return false
	if node is CanvasLayer and not (node as CanvasLayer).visible:
		return false
	if node is Window and not (node as Window).visible:
		return false

	var curr: Node = node
	while curr != null:
		if curr is CanvasItem:
			if not (curr as CanvasItem).visible:
				return false
		elif curr is CanvasLayer:
			if not (curr as CanvasLayer).visible:
				return false
		elif curr is Window:
			if not (curr as Window).visible:
				return false
		curr = curr.get_parent()

	return true


func _is_menu_overlay_open(scene: Node) -> bool:
	if scene == null or not is_instance_valid(scene):
		return false

	return _check_menu_overlay_in_subtree(scene)


func _check_menu_overlay_in_subtree(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	# Ignore self and ready HUD layer
	if node == self or (node is CanvasLayer and str(node.name).to_lower().contains("readyhud")):
		return false

	# Check CoursePlay specific properties
	if "hud_scorecard" in node:
		var sc = node.get("hud_scorecard")
		if sc != null and is_instance_valid(sc) and _is_node_visible_in_tree(sc):
			return true
	if "hud_manage_players" in node:
		var mp = node.get("hud_manage_players")
		if mp != null and is_instance_valid(mp) and _is_node_visible_in_tree(mp):
			return true
	if "hud_overview" in node:
		var ov = node.get("hud_overview")
		if ov != null and is_instance_valid(ov) and _is_node_visible_in_tree(ov):
			return true
	if "mulligan_confirm_dialog" in node:
		var mc = node.get("mulligan_confirm_dialog")
		if mc != null and is_instance_valid(mc) and _is_node_visible_in_tree(mc):
			return true

	# Check Dialogs / Popups / Windows (if visible in tree)
	if (node is Popup or node is AcceptDialog or node is ConfirmationDialog or node is FileDialog) and _is_node_visible_in_tree(node):
		return true

	# Check Settings CanvasLayers (RangeUI.$SettingsLayer, minigames _settings_layer)
	if node is CanvasLayer:
		var cl_name := str(node.name).to_lower()
		if cl_name == "settingslayer" or cl_name == "settingsmodallayer":
			if (node as CanvasLayer).visible:
				return true

	# Check Controls (exclude interactive HUD buttons like MapButton, ScorecardToggleButton, SettingsButton)
	if node is Control and not (node is BaseButton) and _is_node_visible_in_tree(node):
		var n_lower := str(node.name).to_lower()

		# Settings panel (RangeSettings, MinigameSettings)
		if n_lower == "rangesettings" or n_lower == "minigamesettings":
			return true

		# Scorecard panel (hud_scorecard, ScorecardPanel)
		if n_lower == "scorecardpanel" or n_lower == "hudscorecard":
			return true

		# Manage Players panel & Hole Overview & Mulligan dialogs
		if n_lower == "manageplayerspanel" or n_lower == "hudoverview" \
			or n_lower == "holeoverviewpanel" or n_lower == "mulliganconfirmdialog":
			return true

		# Session Recorder PopUp (CenterContainer inside RangeUI)
		if n_lower == "sessionpopup":
			return true

		# Swing Replay & Pause Modals
		if n_lower == "swingreplaymodal" or n_lower == "pausemenu":
			return true

	for child in node.get_children():
		if _check_menu_overlay_in_subtree(child):
			return true

	return false


func _apply_layout(layout: ScreenLayout) -> void:
	_current_layout = layout

	if layout == ScreenLayout.TOP_LEFT:
		_container.anchors_preset = Control.PRESET_TOP_LEFT
		_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_container.grow_horizontal = Control.GROW_DIRECTION_END
		_container.grow_vertical = Control.GROW_DIRECTION_END
		_container.add_theme_constant_override("margin_top", 18)
		_container.add_theme_constant_override("margin_left", 20)
	elif layout == ScreenLayout.TOP_CENTER_UNDER_AIM:
		_container.anchors_preset = Control.PRESET_CENTER_TOP
		_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_container.grow_vertical = Control.GROW_DIRECTION_END
		_container.add_theme_constant_override("margin_top", 78) # Right beneath "Aim: 464 Yards | Tee Box" pill!
		_container.add_theme_constant_override("margin_left", 0)


func _should_indicator_be_visible(scene: Node) -> bool:
	if scene == null:
		return false

	# 1. Hide on non-gameplay screens or if disabled by setting
	if _current_layout == ScreenLayout.HIDDEN or not _visible_mode:
		return false

	# 2. Hide when no launch monitor device is connected
	if not _is_device_connected():
		return false

	# 3. Hide when the game is paused
	var tree := get_tree()
	if tree != null and tree.paused:
		return false

	# 4. Hide when the ball is in flight / moving / shot active / in transition
	if is_ball_in_flight() or _is_shot_transition_active(scene):
		return false

	# 5. Hide when in map/aerial view or sky view (not in hitting spot)
	if _is_in_aerial_or_map_view(scene):
		return false

	# 6. Hide when any menu overlay, settings panel, popup, scorecard, or dialog is open
	if _is_menu_overlay_open(scene):
		return false

	# 7. Hide when an achievement popup notification is actively showing or queued
	if _is_achievement_popup_showing():
		return false

	# 8. Hide when a gimmie banner is actively displaying
	if _is_gimme_banner_showing(scene):
		return false

	# 9. Hide when the current active player is holed out (finished hole) or hole is completed
	if _is_hole_or_player_finished(scene):
		return false

	return true


func _is_shot_transition_active(scene: Node) -> bool:
	if scene == null or not is_instance_valid(scene):
		return false
	if "_shot_transition_active" in scene and bool(scene.get("_shot_transition_active")):
		return true
	if "course_instance" in scene:
		var ci = scene.get("course_instance")
		if ci != null and is_instance_valid(ci) and "_shot_transition_active" in ci and bool(ci.get("_shot_transition_active")):
			return true
	if scene.has_node("course_scene"):
		var cs = scene.get_node("course_scene")
		if cs != null and is_instance_valid(cs) and "_shot_transition_active" in cs and bool(cs.get("_shot_transition_active")):
			return true
	return false


func _is_achievement_popup_showing() -> bool:
	if has_node("/root/AchievementManager"):
		var ach_mgr = get_node("/root/AchievementManager")
		if ach_mgr != null and is_instance_valid(ach_mgr) and ach_mgr.has_method("is_showing_achievement"):
			if ach_mgr.call("is_showing_achievement"):
				return true
	var tree := get_tree()
	if tree != null and tree.root != null:
		var pop = tree.root.find_child("AchievementPopup", true, false)
		if pop != null and is_instance_valid(pop):
			if pop.has_method("is_showing_achievement") and pop.call("is_showing_achievement"):
				return true
			if "popup_control" in pop and pop.popup_control != null and is_instance_valid(pop.popup_control):
				if pop.popup_control.modulate.a > 0.05 and pop.popup_control.offset_top > -160.0:
					return true
	return false


func _is_gimme_banner_showing(scene: Node) -> bool:
	if scene != null and is_instance_valid(scene):
		if scene.has_method("is_gimme_banner_active") and scene.call("is_gimme_banner_active"):
			return true
		if "gimme_banner" in scene:
			var gb = scene.get("gimme_banner")
			if gb != null and is_instance_valid(gb) and gb is CanvasItem:
				if gb.visible and gb.modulate.a > 0.05:
					return true
	var tree := get_tree()
	if tree != null and tree.root != null:
		var banner = tree.root.find_child("GimmeBanner", true, false)
		if banner != null and is_instance_valid(banner) and banner is CanvasItem:
			if banner.visible and banner.modulate.a > 0.05:
				return true
	return false


func _is_hole_or_player_finished(scene: Node) -> bool:
	if has_node("/root/MultiplayerManager"):
		var mp_mgr = get_node("/root/MultiplayerManager")
		if mp_mgr != null and is_instance_valid(mp_mgr):
			if bool(mp_mgr.get("is_finished")):
				return true
			if mp_mgr.has_method("is_active_player_holed_out") and mp_mgr.call("is_active_player_holed_out"):
				return true
			if mp_mgr.has_method("is_current_hole_completed") and mp_mgr.call("is_current_hole_completed"):
				return true
			if not mp_mgr.players.is_empty():
				var active_p = mp_mgr.get_active_player()
				if not active_p.is_empty() and bool(active_p.get("holed_out", false)):
					return true
	if scene != null and is_instance_valid(scene):
		if "is_player_turn_ready" in scene and not bool(scene.get("is_player_turn_ready")):
			return true
	return false


func _update_display(instant: bool = false) -> void:
	var scene := _get_active_scene()
	var should_show := _should_indicator_be_visible(scene)

	if not should_show:
		if visible:
			visible = false
			_stop_pulse_animation()
			_last_rendered_visible = false
		return

	var visibility_just_enabled := not visible
	visible = true
	_panel.modulate.a = 1.0
	if _placement_panel != null and is_instance_valid(_placement_panel):
		_placement_panel.visible = _placement_guide_enabled
		_placement_panel.modulate.a = 1.0

	var ready_state_changed := (_is_ready != _last_rendered_ready) or visibility_just_enabled or not _last_rendered_visible
	_last_rendered_visible = true

	if ready_state_changed:
		_last_rendered_ready = _is_ready
		var dot_style = _dot_panel.get_theme_stylebox("panel") as StyleBoxFlat

		if _is_ready:
			_rearm_feedback_timer = 0.0
			_status_label.text = "BALL READY"
			_sub_label.text = "READY TO HIT"
			_status_label.add_theme_color_override("font_color", Color(0.95, 1.0, 0.95))
			_sub_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
			
			_glow_style.bg_color = Color(0.05, 0.16, 0.09, 0.92)
			_glow_style.border_color = Color(0.2, 0.9, 0.45, 0.9)
			_glow_style.shadow_color = Color(0.1, 0.8, 0.3, 0.35)
			if dot_style:
				dot_style.bg_color = Color(0.2, 0.95, 0.45)
			
			_trigger_pulse_animation()
			if not instant and not visibility_just_enabled:
				_trigger_pop_animation()
		elif _rearm_feedback_timer > 0.0:
			_stop_pulse_animation()
			_show_rearming_feedback()
		else:
			_stop_pulse_animation()
			_status_label.text = "PLACE BALL IN ZONE"
			_sub_label.text = "WAITING FOR BALL"
			_status_label.add_theme_color_override("font_color", Color(0.98, 0.95, 0.9))
			_sub_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
			
			_glow_style.bg_color = Color(0.12, 0.1, 0.05, 0.85)
			_glow_style.border_color = Color(0.9, 0.65, 0.2, 0.7)
			_glow_style.shadow_color = Color(0, 0, 0, 0.3)
			if dot_style:
				dot_style.bg_color = Color(0.95, 0.65, 0.15)

	_update_guidance_text()
	if _placement_canvas != null and is_instance_valid(_placement_canvas):
		_placement_canvas.queue_redraw()


func _on_status_badge_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			trigger_manual_rearm()


func trigger_manual_rearm() -> void:
	if is_ball_in_flight():
		return
	if has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if lm != null and lm.has_method("rearm"):
			lm.call("rearm")
	_rearm_feedback_timer = 1.5
	_last_rendered_ready = false
	_show_rearming_feedback()


func _show_rearming_feedback() -> void:
	_status_label.text = "RE-ARMING MONITOR..."
	_sub_label.text = "CLICK / 'R' TO WAKE"
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	_sub_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
	_glow_style.bg_color = Color(0.14, 0.11, 0.05, 0.92)
	_glow_style.border_color = Color(0.95, 0.7, 0.2, 0.85)
	_glow_style.shadow_color = Color(0.4, 0.3, 0.05, 0.3)
	var dot_style = _dot_panel.get_theme_stylebox("panel") as StyleBoxFlat
	if dot_style:
		dot_style.bg_color = Color(0.95, 0.7, 0.2)
	_trigger_pop_animation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			var scene := _get_active_scene()
			if scene != null and not _is_menu_screen(scene) and not _is_menu_overlay_open(scene) and not is_ball_in_flight():
				var focus_owner = get_viewport().gui_get_focus_owner()
				if focus_owner is LineEdit or focus_owner is TextEdit:
					return
				trigger_manual_rearm()
				get_viewport().set_input_as_handled()


func _trigger_pop_animation() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_panel.pivot_offset = _panel.size / 2.0
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel.scale = Vector2(1.15, 1.15)
	_tween.tween_property(_panel, "scale", Vector2(1.0, 1.0), 0.35)


func _trigger_pulse_animation() -> void:
	if _pulse_tween != null and _pulse_tween.is_running():
		_pulse_tween.kill()
	_pulse_tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_dot_panel, "modulate:a", 0.3, 0.6)
	_pulse_tween.tween_property(_dot_panel, "modulate:a", 1.0, 0.6)


func _stop_pulse_animation() -> void:
	if _pulse_tween != null and _pulse_tween.is_running():
		_pulse_tween.kill()
	_dot_panel.modulate.a = 1.0


func _fade_out() -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_panel, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(func(): visible = false)


func _is_golf_ball(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node is GolfBall:
		return true
	if node.get_script() != null:
		var s_path := str(node.get_script().resource_path)
		if s_path.ends_with("ball.gd"):
			return true
	if "state" in node and ("launch_spin_rpm" in node or "get_downrange_yards" in node or "aim_yaw_offset_deg" in node):
		return true
	return false


func _connect_ball_signals(ball: Node) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	if ball.has_signal("rest") and not ball.is_connected("rest", _on_ball_rest_signal):
		ball.connect("rest", _on_ball_rest_signal)


func _on_ball_rest_signal(_data = null) -> void:
	_shot_active = false
	_ball_moving_prev = false
	_update_display(false)
	if has_node("/root/LaunchMonitorManager"):
		var lm = get_node("/root/LaunchMonitorManager")
		if lm != null and lm.has_method("notify_ball_at_rest"):
			lm.notify_ball_at_rest()


func _find_golf_ball(node: Node) -> Node:
	if node == null or not is_instance_valid(node):
		return null
	if _is_golf_ball(node):
		return node
	if "ball" in node:
		var b = node.get("ball")
		if _is_golf_ball(b):
			return b
	for child in node.get_children():
		var b = _find_golf_ball(child)
		if b != null:
			return b
	return null


func _get_golf_ball() -> Node:
	if _cached_ball != null and is_instance_valid(_cached_ball):
		return _cached_ball

	var scene := _get_active_scene()
	if scene == null or not is_instance_valid(scene):
		return null

	var player = _find_player_node(scene)
	if player != null and is_instance_valid(player) and "ball" in player and player.ball != null:
		if _is_golf_ball(player.ball):
			_cached_ball = player.ball
			_connect_ball_signals(_cached_ball)
			return _cached_ball

	var found = _find_golf_ball(scene)
	if found != null:
		_cached_ball = found
		_connect_ball_signals(_cached_ball)
		return _cached_ball

	var tree := get_tree()
	if tree != null and tree.root != null:
		var b = tree.root.find_child("GolfBall", true, false)
		if b != null and _is_golf_ball(b):
			_cached_ball = b
			_connect_ball_signals(_cached_ball)
			return _cached_ball

	return null
