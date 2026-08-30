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
var _box_tween: Tween = null
var _box_visible_target := false
var _ready_hold_timer := 0.0

# Sensor & Position state
var _is_ready := false
var _status_text := "Disconnected"
var _visible_mode := true
var _placement_guide_enabled := true
var _current_layout := ScreenLayout.HIDDEN
var _check_timer := 0.0
var _cached_ball: GolfBall = null
var _ball_moving_prev := false
var _last_rendered_ready := false
var _last_rendered_visible := false

var _sensor_pos_x := 0
var _sensor_pos_y := 0
var _sensor_pos_z := 0
var _sensor_ready := false
var _sensor_detected := false
var _has_sensor_data := false
var _last_sensor_pos_x := 0
var _last_sensor_pos_y := 0
var _last_ball_pos := Vector3.ZERO


func _ready() -> void:
	layer = 90
	process_mode = PROCESS_MODE_ALWAYS
	_setup_ui()
	
	if has_node("/root/SceneManager"):
		var scn_mgr = get_node("/root/SceneManager")
		if scn_mgr.has_signal("scene_changed"):
			scn_mgr.scene_changed.connect(_on_scene_changed)
			
	_refresh_layout_and_display(true)


func _process(delta: float) -> void:
	# Check ball state every frame for immediate show/hide response
	var ball = _get_golf_ball()
	var ball_moving = false
	if ball != null and is_instance_valid(ball):
		ball_moving = ball.state != 0 # REST is 0
		var ball_curr_pos: Vector3 = ball.global_position
		if _last_ball_pos != Vector3.ZERO and ball_curr_pos.distance_to(_last_ball_pos) > 0.01:
			# Ball was adjusted / moved in 3D scene
			_ready_hold_timer = 0.0
			if not _box_visible_target and not ball_moving:
				_set_placement_box_visible(true)
		_last_ball_pos = ball_curr_pos

	if ball_moving != _ball_moving_prev:
		_ball_moving_prev = ball_moving
		_update_display(true)

	# Update placement box auto-hide / show logic
	_update_placement_box_state(delta)

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
	_has_sensor_data = false
	_last_ball_pos = Vector3.ZERO
	_last_sensor_pos_x = 0
	_last_sensor_pos_y = 0
	_ready_hold_timer = 0.0
	call_deferred("_refresh_layout_and_display", true)


func set_sensor_position(pos_x: int, pos_y: int, pos_z: int, ready: bool, detected: bool) -> void:
	var pos_changed := _has_sensor_data and (absi(pos_x - _sensor_pos_x) >= 2 or absi(pos_y - _sensor_pos_y) >= 2)
	_sensor_pos_x = pos_x
	_sensor_pos_y = pos_y
	_sensor_pos_z = pos_z
	_sensor_ready = ready
	_sensor_detected = detected
	_has_sensor_data = true

	# If the player is actively moving/adjusting the ball, reset hold timer and ensure full guide visibility
	if pos_changed and detected:
		_ready_hold_timer = 0.0
		if not _box_visible_target:
			_set_placement_box_visible(true)

	if _placement_canvas != null and is_instance_valid(_placement_canvas):
		_placement_canvas.queue_redraw()
	_update_guidance_text()


func set_placement_guide_enabled(enabled: bool) -> void:
	_placement_guide_enabled = enabled
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

	# Top Status Badge Pill
	_panel = PanelContainer.new()
	_panel.name = "StatusBadge"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_sub_label.add_theme_font_size_override("font_size", 10)
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
	header.add_theme_font_size_override("font_size", 9)
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
	_guide_label.add_theme_font_size_override("font_size", 10)
	_guide_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	inner_vbox.add_child(_guide_label)

	_main_vbox.add_child(_placement_panel)
	_placement_panel.visible = false
	_placement_panel.modulate.a = 0.0


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
		_placement_canvas.draw_string(font, Vector2(center.x - 28, outer_rect.position.y - 3), "▲ AWAY", HORIZONTAL_ALIGNMENT_CENTER, 56, 8, label_color)
		# Bottom: Closer (toward player)
		_placement_canvas.draw_string(font, Vector2(center.x - 32, outer_rect.end.y + 10), "▼ CLOSER", HORIZONTAL_ALIGNMENT_CENTER, 64, 8, label_color)
		# Left: Player's Left
		_placement_canvas.draw_string(font, Vector2(1, center.y + 3), "◀ L", HORIZONTAL_ALIGNMENT_LEFT, 16, 8, label_color)
		# Right: Player's Right / Target
		_placement_canvas.draw_string(font, Vector2(size.x - 17, center.y + 3), "R ▶", HORIZONTAL_ALIGNMENT_RIGHT, 16, 8, label_color)

	# 3. Optimal Allowed Target Zone Box (e.g. ±60mm lateral X, ±80mm depth Y equivalent)
	var zone_w := outer_rect.size.x * 0.52
	var zone_h := outer_rect.size.y * 0.55
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

	# 6. Get Ball Offset Position
	var norm_pos := _get_normalized_ball_position()
	var norm_x: float = norm_pos.x
	var norm_y: float = norm_pos.y

	var max_offset_x := (outer_rect.size.x / 2.0) - 7.0
	var max_offset_y := (outer_rect.size.y / 2.0) - 7.0
	var ball_center := center + Vector2(norm_x * max_offset_x, norm_y * max_offset_y)

	# Clamp inside outer bounding box
	ball_center.x = clampf(ball_center.x, outer_rect.position.x + 5, outer_rect.end.x - 5)
	ball_center.y = clampf(ball_center.y, outer_rect.position.y + 5, outer_rect.end.y - 5)

	# Ball color coding
	var ball_glow_color := Color(0.2, 0.95, 0.45, 0.6)
	if not _is_ready:
		if absf(norm_x) > 0.75 or absf(norm_y) > 0.75:
			ball_glow_color = Color(0.95, 0.25, 0.2, 0.7) # Red when far outside
		else:
			ball_glow_color = Color(0.95, 0.7, 0.15, 0.7) # Amber when near edge

	# Draw Ball Outer Glow & Shadow
	_placement_canvas.draw_circle(ball_center + Vector2(1, 2), 8.0, Color(0, 0, 0, 0.35))
	_placement_canvas.draw_circle(ball_center, 9.0, ball_glow_color)

	# Draw Golf Ball Body
	_placement_canvas.draw_circle(ball_center, 6.0, Color(0.96, 0.98, 1.0))
	_placement_canvas.draw_arc(ball_center, 6.0, 0, TAU, 16, Color(0.3, 0.3, 0.3, 0.6), 1.0)
	_placement_canvas.draw_circle(ball_center + Vector2(-1.5, -1.5), 2.0, Color(1, 1, 1, 0.9)) # Specular highlight


func _get_normalized_ball_position() -> Vector2:
	if _has_sensor_data:
		# Square hardware sensor coordinates:
		# PositionX: lateral offset in mm (0 center, ±60mm inside target zone)
		# PositionY: depth offset in mm (0 center, ±80mm inside target zone)
		# Player perspective: Left/Right is X axis, Away/Closer is Y axis
		var nx := float(_sensor_pos_x) / 140.0
		# ny < 0 is Away (top of screen) and ny > 0 is Closer (bottom of screen)
		var ny := -float(_sensor_pos_y) / 160.0
		return Vector2(clampf(nx, -1.0, 1.0), clampf(ny, -1.0, 1.0))

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
		if rel_pos.length() > 0.01:
			var nx := clampf(rel_pos.x / 0.15, -1.0, 1.0)
			var ny := clampf(-rel_pos.z / 0.15, -1.0, 1.0)
			return Vector2(nx, ny)

	if _is_ready:
		return Vector2.ZERO
	return Vector2(0.35, 0.45) # Default offset guidance when waiting for ball placement


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
		_guide_label.add_theme_color_override("font_color", Color(0.95, 0.7, 0.3))
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
	if norm.x < -0.2:
		hints.append("Move Right →")
	elif norm.x > 0.2:
		hints.append("← Move Left")

	if norm.y < -0.2:
		hints.append("↓ Move Closer")
	elif norm.y > 0.2:
		hints.append("Move Away ↑")

	if hints.size() > 0:
		_guide_label.text = " & ".join(hints).to_upper()
		_guide_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
		if _placement_glow_style:
			_placement_glow_style.border_color = Color(0.9, 0.65, 0.2, 0.7)
			_placement_glow_style.bg_color = Color(0.12, 0.09, 0.05, 0.9)
	else:
		_guide_label.text = "CENTERING BALL IN ZONE..."
		_guide_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.6))


func _update_placement_box_state(delta: float) -> void:
	if _placement_panel == null or not is_instance_valid(_placement_panel):
		return

	var scene := _get_active_scene()
	var device_connected := _is_device_connected()

	# Rule: The box should show when the ball is moved, missing, or outside of target spot.
	# Once the ball is in the correct spot and ready, it slowly fades away over 2 seconds
	# allowing the player ample time to check centering and adjust ball positioning.
	var should_show_box := false

	if visible and device_connected and _placement_guide_enabled:
		if not _is_ready or _ball_moving_prev or (_has_sensor_data and not _sensor_ready):
			should_show_box = true
			_ready_hold_timer = 0.0
		else:
			# Ball is ready & in correct spot: hold briefly then fade out slowly over 2 seconds
			_ready_hold_timer += delta
			if _ready_hold_timer < 0.2:
				should_show_box = true
			else:
				should_show_box = false

	_set_placement_box_visible(should_show_box)


func _set_placement_box_visible(target_visible: bool) -> void:
	if _box_visible_target == target_visible:
		return
	_box_visible_target = target_visible

	if _box_tween != null and _box_tween.is_running():
		_box_tween.kill()

	_box_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	if target_visible:
		_placement_panel.visible = true
		_placement_panel.scale = Vector2(0.95, 0.95)
		_placement_panel.pivot_offset = _placement_panel.size / 2.0
		_box_tween.tween_property(_placement_panel, "modulate:a", 1.0, 0.2)
		_box_tween.tween_property(_placement_panel, "scale", Vector2(1.0, 1.0), 0.2)
	else:
		# Slow 2.0-second fade out so player can see ball position and adjust to center if desired
		_box_tween.tween_property(_placement_panel, "modulate:a", 0.0, 2.0)
		_box_tween.tween_callback(func():
			if not _box_visible_target:
				_placement_panel.visible = false
		)


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

	# Chipping Minigame or Putting Practice -> TOP_LEFT (Avoids 780px-800px top-center scoreboard panel)
	if full_id.contains("chipping") or scene_name.contains("chipping") or full_id.contains("putting") or scene_name.contains("putting"):
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

	# Check active Camera3D in viewport
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if cam != null and is_instance_valid(cam):
			var cam_name := str(cam.name).to_lower()
			if cam_name.contains("aerial") or cam_name.contains("sky") or cam_name.contains("flyover") or cam_name.contains("overview"):
				return true

	# Check properties on scene
	if "is_aerial_view" in scene and bool(scene.get("is_aerial_view")):
		return true
	if "is_sky_view_active" in scene and bool(scene.get("is_sky_view_active")):
		return true

	# Check course_instance on scene (e.g. CoursePlay)
	if "course_instance" in scene:
		var ci = scene.get("course_instance")
		if ci != null and is_instance_valid(ci):
			if "is_aerial_view" in ci and bool(ci.get("is_aerial_view")):
				return true
			if "is_sky_view_active" in ci and bool(ci.get("is_sky_view_active")):
				return true
			if ci.has_node("AerialCamera"):
				var ac = ci.get_node("AerialCamera")
				if ac is Camera3D and (ac as Camera3D).current:
					return true

	# Check AerialCamera in scene
	if scene.has_node("AerialCamera"):
		var ac = scene.get_node("AerialCamera")
		if ac is Camera3D and (ac as Camera3D).current:
			return true

	# Check MapCanvas zoom controls in scene
	if scene.has_node("MapCanvas/AerialZoomVBox"):
		var zoom_box = scene.get_node("MapCanvas/AerialZoomVBox")
		if zoom_box != null and is_instance_valid(zoom_box) and _is_node_visible_in_tree(zoom_box):
			return true

	# Check children for any course instance having aerial or sky view active
	for child in scene.get_children():
		if child != null and is_instance_valid(child):
			if "is_aerial_view" in child and bool(child.get("is_aerial_view")):
				return true
			if "is_sky_view_active" in child and bool(child.get("is_sky_view_active")):
				return true

	return false


func _is_node_visible_in_tree(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
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

	# Direct property checks on scene (e.g. CoursePlay)
	if "hud_scorecard" in scene:
		var sc = scene.get("hud_scorecard")
		if sc != null and is_instance_valid(sc) and _is_node_visible_in_tree(sc):
			return true
	if "hud_manage_players" in scene:
		var mp = scene.get("hud_manage_players")
		if mp != null and is_instance_valid(mp) and _is_node_visible_in_tree(mp):
			return true
	if "hud_overview" in scene:
		var ov = scene.get("hud_overview")
		if ov != null and is_instance_valid(ov) and _is_node_visible_in_tree(ov):
			return true
	if "mulligan_confirm_dialog" in scene:
		var mc = scene.get("mulligan_confirm_dialog")
		if mc != null and is_instance_valid(mc) and _is_node_visible_in_tree(mc):
			return true

	# Check course_instance on CoursePlay
	if "course_instance" in scene:
		var ci = scene.get("course_instance")
		if ci != null and is_instance_valid(ci):
			if _is_menu_overlay_open(ci):
				return true

	# Check the active scene tree
	if _find_visible_overlay_node(scene):
		return true

	# Check root viewport for popups/dialogs added directly to root
	var tree := get_tree()
	if tree != null and tree.root != null:
		for child in tree.root.get_children():
			if child != scene and child != self and child.name != "LaunchMonitorManager":
				if child is Window and (child as Window).visible:
					return true
				if child is CanvasLayer and (child as CanvasLayer).visible:
					var cl_name := str(child.name).to_lower()
					if cl_name.contains("settings") or cl_name.contains("dialog") or cl_name.contains("modal") or cl_name.contains("menu"):
						return true

	return false


func _find_visible_overlay_node(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false

	if node == self or (node is CanvasLayer and node.name.contains("ReadyHUD")):
		return false

	if node is Window and (node as Window).visible:
		return true

	if node is CanvasLayer:
		var cl = node as CanvasLayer
		if cl.visible:
			var cl_name := str(cl.name).to_lower()
			if cl_name.contains("settings") or cl_name.contains("scorecard") \
				or cl_name.contains("pause") or cl_name.contains("replay") \
				or cl_name.contains("history") or cl_name.contains("analytics") \
				or cl_name.contains("dialog") or cl_name.contains("modal"):
				return true

	if node is Control:
		var ctrl = node as Control
		if _is_node_visible_in_tree(ctrl):
			var n_lower := str(ctrl.name).to_lower()
			var script: Script = ctrl.get_script()
			var s_path := str(script.resource_path).to_lower() if script != null else ""

			if n_lower.contains("rangesettings") or n_lower.contains("minigamesettings") \
				or n_lower.contains("settingslayer") or n_lower.contains("sessionpopup") \
				or n_lower.contains("swingreplay") or n_lower.contains("pausemenu") \
				or n_lower.contains("settingsmodal") or n_lower.contains("optionsmenu") \
				or n_lower.contains("distancemenu") or n_lower.contains("mulligan") \
				or n_lower.contains("scorecard") or n_lower.contains("overview") \
				or n_lower.contains("manage_players") or n_lower.contains("manageplayers") \
				or s_path.contains("range_settings") or s_path.contains("swing_replay") \
				or s_path.contains("session_pop_up") or s_path.contains("distance_menu"):
				return true

	for child in node.get_children():
		if _find_visible_overlay_node(child):
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

	# 4. Hide when the ball is moving
	if _ball_moving_prev:
		return false

	# 5. Hide when in map/aerial view or sky view (not in hitting spot)
	if _is_in_aerial_or_map_view(scene):
		return false

	# 6. Hide when any menu overlay, settings panel, popup, scorecard, or dialog is open
	if _is_menu_overlay_open(scene):
		return false

	return true


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

	var ready_state_changed := (_is_ready != _last_rendered_ready) or visibility_just_enabled or not _last_rendered_visible
	_last_rendered_visible = true

	if ready_state_changed:
		_last_rendered_ready = _is_ready
		var dot_style = _dot_panel.get_theme_stylebox("panel") as StyleBoxFlat

		if _is_ready:
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
		else:
			_stop_pulse_animation()
			_status_label.text = "PLACE BALL IN ZONE"
			_sub_label.text = "WAITING FOR BALL"
			_status_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
			_sub_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
			
			_glow_style.bg_color = Color(0.12, 0.1, 0.05, 0.85)
			_glow_style.border_color = Color(0.9, 0.65, 0.2, 0.7)
			_glow_style.shadow_color = Color(0, 0, 0, 0.3)
			if dot_style:
				dot_style.bg_color = Color(0.95, 0.65, 0.15)

	_update_guidance_text()
	if _placement_canvas != null and is_instance_valid(_placement_canvas):
		_placement_canvas.queue_redraw()


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


func _find_golf_ball(node: Node) -> Node:
	if node == null:
		return null
	if node is GolfBall:
		return node
	# Also check if the node has a "ball" property that is a GolfBall
	if "ball" in node:
		var b = node.get("ball")
		if b is GolfBall:
			return b
	for child in node.get_children():
		var b = _find_golf_ball(child)
		if b != null:
			return b
	return null


func _get_golf_ball() -> GolfBall:
	if _cached_ball != null and is_instance_valid(_cached_ball):
		return _cached_ball
		
	var scene = _get_active_scene()
	if scene != null:
		_cached_ball = _find_golf_ball(scene) as GolfBall
		return _cached_ball
	return null
