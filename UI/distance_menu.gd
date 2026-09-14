extends PanelContainer

signal inject_shot(data)

var _vbox: VBoxContainer
var _close_btn: Button
var aim_target_node = null
var current_ball_node = null

var _include_club_data_cb: CheckBox = null
var _face_angle_spin: SpinBox = null
var _club_path_spin: SpinBox = null
var _impact_h_spin: SpinBox = null
var _impact_v_spin: SpinBox = null

# Approximate table for distances (yards) to physics payload
var _calibration_table = [
	{ "distance": 10.0, "speed": 20.0, "vla": 40.0, "spin": 2000.0 },
	{ "distance": 50.0, "speed": 50.0, "vla": 32.0, "spin": 5000.0 },
	{ "distance": 100.0, "speed": 82.0, "vla": 26.0, "spin": 6500.0 },
	{ "distance": 150.0, "speed": 105.0, "vla": 20.0, "spin": 6000.0 },
	{ "distance": 200.0, "speed": 128.0, "vla": 15.0, "spin": 4500.0 },
	{ "distance": 250.0, "speed": 148.0, "vla": 13.0, "spin": 3000.0 },
	{ "distance": 300.0, "speed": 165.0, "vla": 12.0, "spin": 2500.0 },
	{ "distance": 350.0, "speed": 185.0, "vla": 11.5, "spin": 2200.0 }
]

var _club_data = {
	"Dr": { "vla": 11.5, "spin": 2500.0, "speed_mult": 0.92 },
	"3w": { "vla": 14.0, "spin": 3200.0, "speed_mult": 0.97 },
	"5w": { "vla": 16.5, "spin": 3800.0, "speed_mult": 1.02 },
	"2H": { "vla": 18.0, "spin": 4000.0, "speed_mult": 1.05 },
	"3H": { "vla": 20.0, "spin": 4300.0, "speed_mult": 1.08 },
	"4H": { "vla": 22.0, "spin": 4600.0, "speed_mult": 1.11 },
	"1i": { "vla": 15.0, "spin": 4000.0, "speed_mult": 1.0 },
	"2i": { "vla": 17.0, "spin": 4400.0, "speed_mult": 1.04 },
	"3i": { "vla": 19.5, "spin": 4800.0, "speed_mult": 1.08 },
	"4i": { "vla": 22.0, "spin": 5200.0, "speed_mult": 1.12 },
	"5i": { "vla": 25.0, "spin": 5600.0, "speed_mult": 1.16 },
	"6i": { "vla": 28.0, "spin": 6000.0, "speed_mult": 1.20 },
	"7i": { "vla": 31.5, "spin": 6500.0, "speed_mult": 1.25 },
	"8i": { "vla": 35.5, "spin": 7000.0, "speed_mult": 1.31 },
	"9i": { "vla": 40.0, "spin": 7500.0, "speed_mult": 1.38 },
	"Pw": { "vla": 44.0, "spin": 8000.0, "speed_mult": 1.46 },
	"Gw": { "vla": 48.0, "spin": 8500.0, "speed_mult": 1.55 },
	"Sw": { "vla": 52.0, "spin": 9000.0, "speed_mult": 1.66 },
	"Lw": { "vla": 56.0, "spin": 9500.0, "speed_mult": 1.80 },
	"Pt": { "vla": 0.0, "spin": 50.0, "speed_mult": 1.0 }
}

func _ready() -> void:
	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.24, 0.95)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.72, 0.56, 0.24, 0.8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	add_theme_stylebox_override("panel", style)
	
	custom_minimum_size = Vector2(340, 560)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_vbox)
	
	var title = Label.new()
	title.text = "Hit Specific Distance"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	_vbox.add_child(title)
	
	_add_distance_button("50 Yards", 50.0)
	_add_distance_button("100 Yards", 100.0)
	_add_distance_button("150 Yards", 150.0)
	_add_distance_button("200 Yards", 200.0)
	_add_distance_button("300 Yards", 300.0)
	
	var aim_btn = Button.new()
	aim_btn.text = "🎯 Hit Aim Distance"
	aim_btn.custom_minimum_size = Vector2(260, 44)
	_apply_material_button_style(aim_btn, Color(0.6, 0.2, 0.6, 0.85))
	aim_btn.pressed.connect(_on_hit_aim_distance)
	_vbox.add_child(aim_btn)

	# --- Shot Shape Testing Presets ---
	var shape_sep = HSeparator.new()
	_vbox.add_child(shape_sep)

	var test_title = Label.new()
	test_title.text = "Shot Shape & Heckle Testing"
	test_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	test_title.add_theme_font_size_override("font_size", 14)
	test_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	_vbox.add_child(test_title)

	var fade_btn = Button.new()
	fade_btn.text = "↪️ 100-Yard Fade"
	fade_btn.custom_minimum_size = Vector2(260, 44)
	_apply_material_button_style(fade_btn, Color(0.2, 0.5, 0.65, 0.85))
	fade_btn.pressed.connect(_on_hit_100y_fade)
	_vbox.add_child(fade_btn)

	var slice_btn = Button.new()
	slice_btn.text = "↩️ 100-Yard Slice (Heckle)"
	slice_btn.custom_minimum_size = Vector2(260, 44)
	_apply_material_button_style(slice_btn, Color(0.75, 0.25, 0.2, 0.85))
	slice_btn.pressed.connect(_on_hit_100y_slice)
	_vbox.add_child(slice_btn)

	# --- Club Delivery Stats Controls ---
	var telem_sep = HSeparator.new()
	_vbox.add_child(telem_sep)

	var telem_title = Label.new()
	telem_title.text = "Club Delivery Telemetry"
	telem_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	telem_title.add_theme_font_size_override("font_size", 14)
	telem_title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	_vbox.add_child(telem_title)

	_include_club_data_cb = CheckBox.new()
	_include_club_data_cb.text = "Include Club Data in Shots"
	_include_club_data_cb.button_pressed = true
	_vbox.add_child(_include_club_data_cb)

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_vbox.add_child(grid)

	_face_angle_spin = _create_spinbox_row(grid, "Face Angle:", -15.0, 15.0, 0.5, 0.0, "°")
	_club_path_spin = _create_spinbox_row(grid, "Club Path:", -15.0, 15.0, 0.5, 0.0, "°")
	_impact_h_spin = _create_spinbox_row(grid, "Impact Toe/Heel:", -25.0, 25.0, 1.0, 0.0, "mm")
	_impact_v_spin = _create_spinbox_row(grid, "Impact High/Low:", -20.0, 20.0, 1.0, 0.0, "mm")

	var btn_sep = HSeparator.new()
	_vbox.add_child(btn_sep)
	
	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(260, 44)
	_apply_material_button_style(_close_btn, Color(0.35, 0.35, 0.35, 0.85))
	_close_btn.pressed.connect(func(): visible = false)
	_vbox.add_child(_close_btn)

func _add_distance_button(label: String, distance_yards: float) -> void:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(260, 50)
	_apply_material_button_style(btn, Color(0.24, 0.46, 0.72, 0.85))
	btn.pressed.connect(func(): _inject_shot_for_distance(distance_yards))
	_vbox.add_child(btn)

func _on_hit_aim_distance() -> void:
	if aim_target_node == null or current_ball_node == null:
		print("Distance Menu: Aim target or ball node not set!")
		return
		
	var ball_pos = current_ball_node.global_position
	var target_pos = Vector3.ZERO
	if aim_target_node is Vector3:
		target_pos = aim_target_node
	else:
		target_pos = aim_target_node.global_position
		
	# Calculate flat horizontal distance
	var p1_flat = Vector2(ball_pos.x, ball_pos.z)
	var p2_flat = Vector2(target_pos.x, target_pos.z)
	var horizontal_dist_yards = p1_flat.distance_to(p2_flat) * 1.09361
	
	# Adjust for elevation difference (Godot Y is up, so +Y is uphill)
	var elevation_diff_yards = (target_pos.y - ball_pos.y) * 1.09361
	
	# Effective distance = horizontal distance + elevation difference
	# Uphill shots require more distance, downhill shots require less
	var distance_yards = horizontal_dist_yards + elevation_diff_yards
	if distance_yards < 1.0:
		distance_yards = 1.0
		
	_inject_shot_for_distance(distance_yards)

func _inject_shot_for_distance(distance_yards: float) -> void:
	var payload = _interpolate_payload(distance_yards)
	var selected_club = _get_selected_club()
	
	var data := {}
	
	if selected_club == "Pt":
		# Special handling for putter: no vertical loft, immediate ground rollout
		# Deceleration formula v = sqrt(2 * friction * g * distance_meters)
		# Green rolling friction u_kr is ~0.03. For in-game realism, speed_mph = 1.8 * sqrt(distance_yards)
		var putt_speed = 1.8 * sqrt(distance_yards)
		data = {
			"Speed": clampf(putt_speed, 2.0, 40.0),
			"VLA": 0.0,
			"HLA": 0.0,
			"TotalSpin": 50.0,
			"SpinAxis": 0.0,
			"ShotType": "putt"
		}
	else:
		var speed = payload["speed"]
		var vla = payload["vla"]
		var spin = payload["spin"]
		
		# Bypassing the club-specific overrides so that the calibrated payload
		# parameters are used directly. This guarantees the ball travels the
		# targeted distance accurately regardless of the selected club.
			
		data = {
			"Speed": speed,
			"VLA": vla,
			"HLA": 0.0,
			"TotalSpin": spin,
			"SpinAxis": 0.0
		}

	# Always include club delivery and impact metrics so graphics show up and can be tested
	data["FaceAngle"] = _face_angle_spin.value if _face_angle_spin != null else 0.0
	data["ClubPath"] = _club_path_spin.value if _club_path_spin != null else 0.0
	data["HorizontalFaceImpact"] = _impact_h_spin.value if _impact_h_spin != null else 0.0
	data["VerticalFaceImpact"] = _impact_v_spin.value if _impact_v_spin != null else 0.0
	
	emit_signal("inject_shot", data)
	visible = false

func _on_hit_100y_fade() -> void:
	# Randomize open face (+0.8° to +2.4°) and out-to-in path (-3.2° to -1.4°)
	var rand_face = snappedf(randf_range(0.8, 2.4), 0.1)
	var rand_path = snappedf(randf_range(-3.2, -1.4), 0.1)
	var rand_h = snappedf(randf_range(0.5, 3.5), 0.5)
	var rand_v = snappedf(randf_range(-1.5, 1.5), 0.5)
	var rand_axis = snappedf(randf_range(4.5, 8.5), 0.5)

	if _face_angle_spin != null:
		_face_angle_spin.value = rand_face
	if _club_path_spin != null:
		_club_path_spin.value = rand_path
	if _impact_h_spin != null:
		_impact_h_spin.value = rand_h
	if _impact_v_spin != null:
		_impact_v_spin.value = rand_v

	var payload = _interpolate_payload(100.0)
	var data = {
		"Speed": payload["speed"],
		"VLA": payload["vla"],
		"HLA": snappedf(randf_range(-1.8, -0.8), 0.1),
		"TotalSpin": 6500.0,
		"SpinAxis": rand_axis,
		"FaceAngle": rand_face,
		"ClubPath": rand_path,
		"HorizontalFaceImpact": rand_h,
		"VerticalFaceImpact": rand_v
	}
	emit_signal("inject_shot", data)
	visible = false

func _on_hit_100y_slice() -> void:
	# Randomize severely open face (+3.5° to +7.5°) and out-to-in path (-9.5° to -5.0°)
	var rand_face = snappedf(randf_range(3.5, 7.5), 0.1)
	var rand_path = snappedf(randf_range(-9.5, -5.0), 0.1)
	var rand_h = snappedf(randf_range(4.0, 12.0), 0.5) * (1.0 if randf() > 0.4 else -1.0)
	var rand_v = snappedf(randf_range(-4.0, 2.5), 0.5)
	var rand_axis = snappedf(randf_range(18.0, 32.0), 0.5) # Heavy slice tilt to reliably roast

	if _face_angle_spin != null:
		_face_angle_spin.value = rand_face
	if _club_path_spin != null:
		_club_path_spin.value = rand_path
	if _impact_h_spin != null:
		_impact_h_spin.value = rand_h
	if _impact_v_spin != null:
		_impact_v_spin.value = rand_v

	var payload = _interpolate_payload(100.0)
	var data = {
		"Speed": payload["speed"],
		"VLA": payload["vla"],
		"HLA": snappedf(randf_range(-2.5, -1.0), 0.1),
		"TotalSpin": 6800.0,
		"SpinAxis": rand_axis,
		"FaceAngle": rand_face,
		"ClubPath": rand_path,
		"HorizontalFaceImpact": rand_h,
		"VerticalFaceImpact": rand_v
	}
	emit_signal("inject_shot", data)
	visible = false


func _create_spinbox_row(parent: Node, label_text: String, min_v: float, max_v: float, step_v: float, def_v: float, sfx: String) -> SpinBox:
	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.8, 0.88, 0.95))
	parent.add_child(lbl)

	var sb = SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step_v
	sb.value = def_v
	sb.suffix = sfx
	sb.custom_minimum_size = Vector2(90, 32)
	parent.add_child(sb)
	return sb

func _interpolate_payload(distance_yards: float) -> Dictionary:
	var count = _calibration_table.size()
	if distance_yards <= _calibration_table[0]["distance"]:
		return _calibration_table[0].duplicate()
	if distance_yards >= _calibration_table[count - 1]["distance"]:
		return _calibration_table[count - 1].duplicate()
		
	for i in range(count - 1):
		var p1 = _calibration_table[i]
		var p2 = _calibration_table[i+1]
		if distance_yards >= p1["distance"] and distance_yards <= p2["distance"]:
			var t = (distance_yards - p1["distance"]) / (p2["distance"] - p1["distance"])
			return {
				"speed": lerpf(p1["speed"], p2["speed"], t),
				"vla": lerpf(p1["vla"], p2["vla"], t),
				"spin": lerpf(p1["spin"], p2["spin"], t)
			}
			
	return _calibration_table[0].duplicate()

func _apply_material_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 20
	style_normal.corner_radius_top_right = 20
	style_normal.corner_radius_bottom_left = 20
	style_normal.corner_radius_bottom_right = 20
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 16)


func _get_selected_club() -> String:
	var root = get_tree().root
	var club_selector = _find_node_by_name(root, "ClubSelector")
	if club_selector and club_selector.current_club:
		return club_selector.current_club.text
	return "Dr" # fallback


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var found = _find_node_by_name(child, target_name)
		if found:
			return found
	return null

