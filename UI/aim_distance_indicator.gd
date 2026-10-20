class_name AimDistanceIndicator
extends CanvasLayer

## AimDistanceIndicator
## Displays a 3D ground target reticle, vertical guideline, and floating distance card
## when aiming with D-pad or arrow keys, exactly like PGA Tour games.
## Remains visible while aiming, persists briefly after aiming stops, and smoothly fades out.

const HOLD_DURATION: float = 1.2
const FADE_DURATION: float = 0.5

var _course: Node = null
var _overlay_control: Control = null
var _card_panel: PanelContainer = null
var _icon_label: Label = null
var _distance_label: Label = null
var _unit_label: Label = null
var _elev_label: Label = null

var _ground_reticle_3d: MeshInstance3D = null
var _ground_reticle_material: StandardMaterial3D = null

var _is_aiming: bool = false
var _alpha: float = 0.0
var _hold_timer: float = 0.0
var _fade_timer: float = 0.0

var _screen_ground_pos: Vector2 = Vector2.ZERO
var _screen_card_bottom: Vector2 = Vector2.ZERO


func _init() -> void:
	layer = 14
	visible = false


func initialize(course_node: Node) -> void:
	_course = course_node
	_setup_ui()
	_setup_3d_reticle()


func _setup_ui() -> void:
	_overlay_control = Control.new()
	_overlay_control.name = "AimIndicatorOverlay"
	_overlay_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_control.draw.connect(_on_overlay_draw)
	add_child(_overlay_control)

	_card_panel = PanelContainer.new()
	_card_panel.name = "DistanceCard"
	_card_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.16, 0.92)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.22, 0.82, 1.0, 0.85)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	_card_panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 6)
	_card_panel.add_child(hbox)

	_icon_label = Label.new()
	_icon_label.text = "🎯"
	_icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_label.add_theme_font_size_override("font_size", 15)
	hbox.add_child(_icon_label)

	_distance_label = Label.new()
	_distance_label.text = "---"
	_distance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_distance_label.add_theme_font_size_override("font_size", 20)
	_distance_label.add_theme_color_override("font_color", Color.WHITE)
	_distance_label.add_theme_constant_override("outline_size", 2)
	_distance_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hbox.add_child(_distance_label)

	_unit_label = Label.new()
	_unit_label.text = "YDS"
	_unit_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_unit_label.add_theme_font_size_override("font_size", 12)
	_unit_label.add_theme_color_override("font_color", Color(0.35, 0.85, 1.0))
	_unit_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hbox.add_child(_unit_label)

	_elev_label = Label.new()
	_elev_label.text = ""
	_elev_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_elev_label.add_theme_font_size_override("font_size", 11)
	_elev_label.add_theme_color_override("font_color", Color(0.85, 0.90, 0.98))
	_elev_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_elev_label.visible = false
	hbox.add_child(_elev_label)

	_overlay_control.add_child(_card_panel)


func _setup_3d_reticle() -> void:
	if _course == null or not is_instance_valid(_course):
		return

	_ground_reticle_3d = MeshInstance3D.new()
	_ground_reticle_3d.name = "AimGroundReticle"

	var torus = TorusMesh.new()
	torus.inner_radius = 0.90
	torus.outer_radius = 1.15
	torus.rings = 36
	torus.ring_segments = 6
	_ground_reticle_3d.mesh = torus

	_ground_reticle_material = StandardMaterial3D.new()
	_ground_reticle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ground_reticle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ground_reticle_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ground_reticle_material.no_depth_test = true
	_ground_reticle_material.render_priority = 2
	_ground_reticle_material.albedo_color = Color(0.2, 0.85, 1.0, 0.0)
	_ground_reticle_3d.material_override = _ground_reticle_material

	_ground_reticle_3d.visible = false
	_course.add_child(_ground_reticle_3d)


func notify_aiming() -> void:
	_is_aiming = true
	_alpha = 1.0
	_hold_timer = HOLD_DURATION
	_fade_timer = FADE_DURATION
	visible = true


func notify_aiming_stopped() -> void:
	_is_aiming = false


func dismiss_immediate() -> void:
	_is_aiming = false
	_alpha = 0.0
	_hold_timer = 0.0
	_fade_timer = 0.0
	visible = false
	if _ground_reticle_3d != null and is_instance_valid(_ground_reticle_3d):
		_ground_reticle_3d.visible = false
	if _overlay_control != null and is_instance_valid(_overlay_control):
		_overlay_control.queue_redraw()


func is_indicator_active() -> bool:
	return _alpha > 0.001


func _process(delta: float) -> void:
	if _course == null or not is_instance_valid(_course):
		return

	# If shot is active or ball is moving or in aerial view or dialog open, dismiss
	if _should_suppress_indicator():
		dismiss_immediate()
		return

	# Autodetect aiming input if not explicitly called
	if _is_raw_aim_input_pressed():
		_is_aiming = true

	# Lifecycle state update
	if _is_aiming:
		_alpha = 1.0
		_hold_timer = HOLD_DURATION
		_fade_timer = FADE_DURATION
	elif _hold_timer > 0.0:
		_hold_timer -= delta
		if _hold_timer < 0.0:
			_fade_timer += _hold_timer
			_hold_timer = 0.0
			_alpha = clamp(_fade_timer / FADE_DURATION, 0.0, 1.0)
		else:
			_alpha = 1.0
	elif _fade_timer > 0.0:
		_fade_timer -= delta
		_alpha = clamp(_fade_timer / FADE_DURATION, 0.0, 1.0)
	else:
		_alpha = 0.0

	if _alpha <= 0.001:
		visible = false
		if _ground_reticle_3d != null and is_instance_valid(_ground_reticle_3d):
			_ground_reticle_3d.visible = false
		return

	visible = true

	var aim_target_pos = _course.get("aim_target_pos") as Vector3
	if aim_target_pos == null or aim_target_pos.is_zero_approx():
		visible = false
		if _ground_reticle_3d != null and is_instance_valid(_ground_reticle_3d):
			_ground_reticle_3d.visible = false
		return

	# Update 3D ground reticle position and alpha
	if _ground_reticle_3d != null and is_instance_valid(_ground_reticle_3d) and _ground_reticle_3d.is_inside_tree():
		_ground_reticle_3d.global_position = aim_target_pos + Vector3(0, 0.04, 0)
		_ground_reticle_3d.visible = true
		if _ground_reticle_material != null:
			_ground_reticle_material.albedo_color = Color(0.2, 0.85, 1.0, _alpha * 0.75)

	# Get active 3D camera
	var vp = get_viewport()
	if vp == null:
		_overlay_control.visible = false
		return
	var camera = vp.get_camera_3d()
	if camera == null or not is_instance_valid(camera) or camera.is_position_behind(aim_target_pos):
		_overlay_control.visible = false
		return

	_overlay_control.visible = true
	_screen_ground_pos = camera.unproject_position(aim_target_pos)

	var v_rect = _overlay_control.get_viewport_rect()
	if not v_rect.has_point(_screen_ground_pos) and \
	   (_screen_ground_pos.x < -150 or _screen_ground_pos.x > v_rect.size.x + 150 or \
		_screen_ground_pos.y < -150 or _screen_ground_pos.y > v_rect.size.y + 150):
		_overlay_control.visible = false
		return

	# Calculate distance and dynamic guideline height
	var ball_pos = Vector3.ZERO
	if _course.has_node("Player") and _course.get_node("Player").get("ball") != null:
		var ball_node = _course.get_node("Player").get("ball")
		if ball_node != null and is_instance_valid(ball_node):
			ball_pos = ball_node.global_position

	var dist_m = ball_pos.distance_to(aim_target_pos) if not ball_pos.is_zero_approx() else 50.0
	var cam_dist = camera.global_position.distance_to(aim_target_pos)
	var world_stem_h = clamp(cam_dist * 0.038, 1.8, 8.5)
	var elevated_world_pos = aim_target_pos + Vector3(0, world_stem_h, 0)
	var p_elevated = camera.unproject_position(elevated_world_pos)
	var stem_px = clamp(_screen_ground_pos.y - p_elevated.y, 48.0, 130.0)

	_update_card_content(ball_pos, aim_target_pos, dist_m)

	# Position card
	var card_size = _card_panel.size
	if card_size.x <= 0:
		card_size = _card_panel.get_combined_minimum_size()

	var card_x = clamp(_screen_ground_pos.x - card_size.x * 0.5, 12.0, v_rect.size.x - card_size.x - 12.0)
	var target_bottom_y = _screen_ground_pos.y - stem_px
	var card_y = clamp(target_bottom_y - card_size.y, 18.0, v_rect.size.y - card_size.y - 18.0)

	_card_panel.position = Vector2(card_x, card_y)
	_card_panel.modulate.a = _alpha

	_screen_card_bottom = Vector2(card_x + card_size.x * 0.5, card_y + card_size.y)
	_overlay_control.queue_redraw()


func _update_card_content(ball_pos: Vector3, aim_target_pos: Vector3, dist_m: float) -> void:
	var on_green = false
	if _course.has_method("is_ball_on_green"):
		on_green = _course.call("is_ball_on_green")
	elif _course.has_method("is_putting_view"):
		on_green = _course.call("is_putting_view")

	var is_imperial := true
	if is_inside_tree() and has_node("/root/GlobalSettings"):
		var gs = get_node("/root/GlobalSettings")
		if gs.get("range_settings") != null and gs.range_settings.get("range_units") != null:
			is_imperial = (gs.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL)

	var dist_val: int = 0
	var unit_str: String = ""

	if on_green:
		dist_val = int(round(dist_m * 3.28084))
		unit_str = "FT"
	else:
		if is_imperial:
			dist_val = int(round(dist_m * 1.09361))
			unit_str = "YDS"
		else:
			dist_val = int(round(dist_m))
			unit_str = "M"

	_distance_label.text = str(dist_val)
	_unit_label.text = unit_str

	# Elevation difference
	var elev_diff_m = aim_target_pos.y - ball_pos.y
	if abs(elev_diff_m) >= 0.35:
		_elev_label.visible = true
		if is_imperial:
			var elev_ft = int(round(elev_diff_m * 3.28084))
			if elev_ft > 0:
				_elev_label.text = "▲ %d FT" % elev_ft
				_elev_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
			elif elev_ft < 0:
				_elev_label.text = "▼ %d FT" % abs(elev_ft)
				_elev_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
			else:
				_elev_label.visible = false
		else:
			var elev_m_round = snappedf(elev_diff_m, 0.1)
			if elev_m_round > 0.0:
				_elev_label.text = "▲ %.1f M" % elev_m_round
				_elev_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
			elif elev_m_round < 0.0:
				_elev_label.text = "▼ %.1f M" % abs(elev_m_round)
				_elev_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
			else:
				_elev_label.visible = false
	else:
		_elev_label.visible = false


func _on_overlay_draw() -> void:
	if _alpha <= 0.001 or _screen_ground_pos.is_zero_approx():
		return

	var p_ground = _screen_ground_pos
	var p_card_bottom = _screen_card_bottom

	# 1. Guideline shadow line
	_overlay_control.draw_line(p_ground, p_card_bottom, Color(0.0, 0.0, 0.0, _alpha * 0.45), 4.5, true)
	# 2. Cyan glow guideline
	_overlay_control.draw_line(p_ground, p_card_bottom, Color(0.2, 0.82, 1.0, _alpha * 0.40), 3.0, true)
	# 3. Bright core guideline
	_overlay_control.draw_line(p_ground, p_card_bottom, Color(1.0, 1.0, 1.0, _alpha * 0.95), 1.8, true)

	# 4. Ground reticle shadow
	_overlay_control.draw_arc(p_ground + Vector2(0, 1), 13.0, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, _alpha * 0.40), 3.0)
	# 5. Ground reticle outer ring
	_overlay_control.draw_arc(p_ground, 13.0, 0.0, TAU, 24, Color(0.2, 0.82, 1.0, _alpha * 0.85), 2.0)
	# 6. Ground reticle center pip
	_overlay_control.draw_circle(p_ground, 3.5, Color(1.0, 1.0, 1.0, _alpha * 0.95))

	# 7. Ground reticle 4 crosshair tick marks
	var tick_color = Color(0.2, 0.85, 1.0, _alpha * 0.85)
	_overlay_control.draw_line(p_ground + Vector2(-18, 0), p_ground + Vector2(-10, 0), tick_color, 1.5)
	_overlay_control.draw_line(p_ground + Vector2(10, 0), p_ground + Vector2(18, 0), tick_color, 1.5)
	_overlay_control.draw_line(p_ground + Vector2(0, -18), p_ground + Vector2(0, -10), tick_color, 1.5)
	_overlay_control.draw_line(p_ground + Vector2(0, 10), p_ground + Vector2(0, 18), tick_color, 1.5)


func _should_suppress_indicator() -> bool:
	if _course == null:
		return true

	# Check aerial view
	if _course.get("is_aerial_view") == true:
		return true

	# Check shot active
	if _course.get("_shot_active") == true:
		return true

	# Check ball state
	if _course.has_node("Player") and _course.get_node("Player").get("ball") != null:
		var ball = _course.get_node("Player").get("ball")
		if ball != null and is_instance_valid(ball):
			if ball.get("state") != null and ball.state != PhysicsEnums.BallState.REST:
				return true

	# Check if dialog open
	if _course.has_method("is_any_dialog_open") and _course.call("is_any_dialog_open"):
		return true

	return false


func _is_raw_aim_input_pressed() -> bool:
	if (InputMap.has_action("aim_left") and Input.is_action_pressed("aim_left")) or \
	   (InputMap.has_action("aim_right") and Input.is_action_pressed("aim_right")) or \
	   (InputMap.has_action("aim_forward") and Input.is_action_pressed("aim_forward")) or \
	   (InputMap.has_action("aim_backward") and Input.is_action_pressed("aim_backward")):
		return true

	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT) or \
	   Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN):
		return true

	for joy_id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_LEFT) or \
		   Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_RIGHT) or \
		   Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_UP) or \
		   Input.is_joy_button_pressed(joy_id, JOY_BUTTON_DPAD_DOWN):
			return true

	if _course != null:
		if _course.get("is_screen_aiming") == true or _course.get("_was_screen_aiming") == true:
			return true

	return false


func _exit_tree() -> void:
	if _ground_reticle_3d != null and is_instance_valid(_ground_reticle_3d):
		_ground_reticle_3d.queue_free()
		_ground_reticle_3d = null
