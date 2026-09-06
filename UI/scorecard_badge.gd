# scorecard_badge.gd
# Custom Control for displaying golfer lingo scorecard badges:
# - Circles for under par (1=birdie, 2=eagle, 3=albatross/better)
# - Squares for over par (1=bogey, 2=double bogey, 3=triple bogey)
# - Scores 4 or more over par and even par have no shape
class_name ScorecardBadge
extends Control

enum ShapeType {
	NONE,
	CIRCLE,
	SQUARE
}

var shape_type: ShapeType = ShapeType.NONE
var shape_count: int = 0
var stroke_color: Color = Color.WHITE
var fill_color: Color = Color.TRANSPARENT
var font_color: Color = Color.WHITE
var score_text: String = ""
var font_size: int = 16

var _label: Label = null

func _init() -> void:
	custom_minimum_size = Vector2(32, 32)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup_label()

func _setup_label() -> void:
	if _label == null:
		_label = Label.new()
		_label.name = "ScoreLabel"
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		_label.add_theme_constant_override("outline_size", 2)
		add_child(_label)

func configure(text: String, p_shape_type: ShapeType, p_shape_count: int, p_stroke_color: Color, p_font_color: Color = Color.WHITE, p_font_size: int = 16) -> void:
	_setup_label()
	score_text = text
	shape_type = p_shape_type
	shape_count = clamp(p_shape_count, 0, 3)
	stroke_color = p_stroke_color
	font_color = p_font_color
	font_size = p_font_size
	
	if shape_type != ShapeType.NONE and shape_count > 0:
		fill_color = Color(stroke_color.r, stroke_color.g, stroke_color.b, 0.12)
	else:
		fill_color = Color.TRANSPARENT

	_label.text = score_text
	_label.add_theme_color_override("font_color", font_color)
	_label.add_theme_font_size_override("font_size", font_size)
	queue_redraw()

func _draw() -> void:
	if shape_type == ShapeType.NONE or shape_count <= 0:
		return

	var center = size * 0.5

	match shape_type:
		ShapeType.CIRCLE:
			_draw_circles(center)
		ShapeType.SQUARE:
			_draw_squares(center)

func _draw_circles(center: Vector2) -> void:
	match shape_count:
		1:
			var r = 12.5
			if fill_color.a > 0.0:
				draw_circle(center, r, fill_color)
			draw_arc(center, r, 0.0, TAU, 36, stroke_color, 1.8, true)
		2:
			var r_in = 10.5
			var r_out = 13.5
			if fill_color.a > 0.0:
				draw_circle(center, r_in, fill_color)
			draw_arc(center, r_in, 0.0, TAU, 36, stroke_color, 1.5, true)
			draw_arc(center, r_out, 0.0, TAU, 36, stroke_color, 1.5, true)
		3:
			var r_in = 9.0
			var r_mid = 11.8
			var r_out = 14.5
			if fill_color.a > 0.0:
				draw_circle(center, r_in, fill_color)
			draw_arc(center, r_in, 0.0, TAU, 36, stroke_color, 1.4, true)
			draw_arc(center, r_mid, 0.0, TAU, 36, stroke_color, 1.4, true)
			draw_arc(center, r_out, 0.0, TAU, 36, stroke_color, 1.4, true)

func _draw_squares(center: Vector2) -> void:
	match shape_count:
		1:
			var h = 12.0
			if fill_color.a > 0.0:
				draw_rect(Rect2(center - Vector2(h, h), Vector2(h * 2.0, h * 2.0)), fill_color, true)
			_draw_square_outline(center, h, 1.8)
		2:
			var h_in = 10.0
			var h_out = 13.0
			if fill_color.a > 0.0:
				draw_rect(Rect2(center - Vector2(h_in, h_in), Vector2(h_in * 2.0, h_in * 2.0)), fill_color, true)
			_draw_square_outline(center, h_in, 1.5)
			_draw_square_outline(center, h_out, 1.5)
		3:
			var h_in = 8.5
			var h_mid = 11.2
			var h_out = 14.0
			if fill_color.a > 0.0:
				draw_rect(Rect2(center - Vector2(h_in, h_in), Vector2(h_in * 2.0, h_in * 2.0)), fill_color, true)
			_draw_square_outline(center, h_in, 1.4)
			_draw_square_outline(center, h_mid, 1.4)
			_draw_square_outline(center, h_out, 1.4)

func _draw_square_outline(center: Vector2, half_size: float, line_width: float) -> void:
	var tl = center + Vector2(-half_size, -half_size)
	var tr = center + Vector2(half_size, -half_size)
	var br = center + Vector2(half_size, half_size)
	var bl = center + Vector2(-half_size, half_size)
	var pts = PackedVector2Array([tl, tr, br, bl, tl])
	draw_polyline(pts, stroke_color, line_width, true)

# Static helper to evaluate score relation to par and return shape/color specs
static func evaluate_score_style(score_str: String, par: int, is_ctp: bool = false) -> Dictionary:
	var result = {
		"shape_type": ShapeType.NONE,
		"shape_count": 0,
		"stroke_color": Color.WHITE,
		"font_color": Color.WHITE,
		"clean_score": score_str,
		"suffix": ""
	}

	if is_ctp or score_str.is_empty() or score_str == "-" or score_str == "*":
		if is_ctp and score_str == "1":
			result["clean_score"] = "1"
			result["suffix"] = " ⛳"
			result["font_color"] = Color(1.0, 0.85, 0.35)
		elif is_ctp:
			result["font_color"] = Color(0.65, 0.65, 0.65)
		return result

	# Separate score value and any trailing suffix (e.g. "*", " 🏆", " (C)")
	var text = score_str.strip_edges()
	var clean_num_str = ""
	var suffix = ""

	# Check for skins or other suffix with space
	var space_pos = text.find(" ")
	if space_pos != -1:
		clean_num_str = text.substr(0, space_pos)
		suffix = text.substr(space_pos)
	else:
		clean_num_str = text

	if clean_num_str.ends_with("*"):
		# In-progress hole: no shapes, keep "*" as suffix
		var base = clean_num_str.rstrip("*")
		result["clean_score"] = base
		result["suffix"] = "*" + suffix
		result["font_color"] = Color(0.85, 0.85, 0.85)
		return result

	if not clean_num_str.is_valid_int():
		result["clean_score"] = score_str
		return result

	var score_val = int(clean_num_str)
	var diff = score_val - par

	result["clean_score"] = str(score_val)
	result["suffix"] = suffix

	if diff < 0:
		# Under Par: Circles (Birdie=-1, Eagle=-2, Albatross/better=-3 capped at 3)
		result["shape_type"] = ShapeType.CIRCLE
		result["shape_count"] = clamp(-diff, 1, 3)
		result["stroke_color"] = Color(0.28, 0.90, 0.52) # Vivid Birdie Green
		result["font_color"] = Color(0.35, 0.95, 0.55)
	elif diff == 0:
		# Par: Clean, no shape
		result["shape_type"] = ShapeType.NONE
		result["shape_count"] = 0
		result["font_color"] = Color.WHITE
	elif diff > 0:
		# Over Par: Squares (Bogey=+1, Double Bogey=+2, Triple Bogey=+3)
		# 4 or more over: No shape!
		result["font_color"] = Color(1.0, 0.42, 0.42) # Bogey Coral Red
		if diff <= 3:
			result["shape_type"] = ShapeType.SQUARE
			result["shape_count"] = diff
			result["stroke_color"] = Color(1.0, 0.42, 0.42)
		else:
			result["shape_type"] = ShapeType.NONE
			result["shape_count"] = 0

	return result

# Factory helper to construct a cell container (HBox with ScorecardBadge + optional suffix)
static func create_score_widget(score_str: String, par: int, is_ctp: bool = false, font_size: int = 16) -> Control:
	var style_info = evaluate_score_style(score_str, par, is_ctp)
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 2)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_FILL
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var badge = new()
	badge.configure(
		style_info["clean_score"],
		style_info["shape_type"],
		style_info["shape_count"],
		style_info["stroke_color"],
		style_info["font_color"],
		font_size
	)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(badge)

	var suffix_str = str(style_info["suffix"])
	if not suffix_str.is_empty():
		var s_lbl = Label.new()
		s_lbl.text = suffix_str
		s_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		s_lbl.add_theme_font_size_override("font_size", max(11, font_size - 4))
		s_lbl.add_theme_color_override("font_color", style_info["font_color"])
		s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(s_lbl)

	return hbox
