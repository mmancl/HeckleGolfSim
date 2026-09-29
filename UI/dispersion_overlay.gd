extends Control

# Top-Down Driving Range Shot Dispersion & Landing View
# Shows ball landing / total distance positions down the range with distance arcs,
# center target line, club grouping dispersion ellipse, and color-coded landing dots.

const PANEL_WIDTH := 216.0
const PANEL_HEIGHT := 236.0

const ARC_COLORS: Array[Color] = [
	Color(0.0, 0.9, 1.0),   # Cyan
	Color(1.0, 0.85, 0.0),  # Yellow
	Color(1.0, 0.25, 0.25), # Red
	Color(0.4, 1.0, 0.2),   # Lime
	Color(1.0, 0.55, 0.0),  # Orange
	Color(0.85, 0.3, 1.0),  # Magenta
	Color(1.0, 1.0, 1.0),   # White
	Color(0.2, 1.0, 0.65),  # Mint
]

var _shots: Array[Dictionary] = []
var _club_name: String = ""

func _init() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_PASS

func update_data(shots: Array[Dictionary], club_name: String) -> void:
	_shots = shots
	_club_name = club_name
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20 or h < 20:
		return

	# 1. Background Panel (Modern dark translucent card matching minimap theme)
	var bg_rect := Rect2(Vector2.ZERO, size)
	draw_rect(bg_rect, Color(0.08, 0.10, 0.14, 0.85), true)
	draw_rect(bg_rect, Color(0.35, 0.55, 0.8, 0.6), false, 1.5)

	var font = ThemeDB.fallback_font

	# 2. Header
	var title_text = _club_name.to_upper() if not _club_name.is_empty() else "RANGE DISPERSION"
	if font:
		draw_string(font, Vector2(10, 18), title_text, HORIZONTAL_ALIGNMENT_LEFT, int(w - 70), 12, Color(0.9, 0.95, 1.0, 0.95))
		var count_text = "%d SHOTS" % _shots.size() if not _shots.is_empty() else "0 SHOTS"
		draw_string(font, Vector2(w - 65, 18), count_text, HORIZONTAL_ALIGNMENT_RIGHT, 55, 10, Color(0.65, 0.8, 0.95, 0.85))

	if _shots.is_empty():
		if font:
			draw_string(font, Vector2(10, h * 0.5), "Hit shots on the range to\nsee landing positions & dispersion.", HORIZONTAL_ALIGNMENT_CENTER, int(w - 20), 10, Color(0.6, 0.65, 0.7, 0.75))
		return

	# 3. Determine Dynamic Range Distance Scale & Offline Spread
	var max_dist_meters := 30.0
	var max_offline_meters := 0.0

	for shot in _shots:
		var d = absf(float(shot.get("TotalDistance", shot.get("CarryDistance", 0.0))))
		var s = _extract_offline_meters(shot)
		if absf(s) < 120.0:
			max_offline_meters = maxf(max_offline_meters, absf(s))
		max_dist_meters = maxf(max_dist_meters, d)

	# Convert to yards for driving range arcs
	var max_dist_yds = max_dist_meters * 1.09361
	var max_offline_yds = max_offline_meters * 1.09361

	# Round max distance up to nearest nice interval (e.g. 100, 150, 200, 250, 300, 350)
	var max_scale_yds = maxf(ceil((max_dist_yds * 1.15) / 50.0) * 50.0, 100.0)
	# Scale offline width: dynamically fit the actual landing spread with a sensible minimum
	# If players hit tight shots (0-5 yds), zoom in to +/- 15 yds so lateral deviation is clearly visible!
	var max_scale_offline_yds = maxf(max_offline_yds * 1.4, 15.0)

	var plot_top := 28.0
	var plot_bottom := h - 16.0
	var plot_left := 16.0
	var plot_right := w - 16.0
	var center_x := (plot_left + plot_right) * 0.5
	var plot_height := plot_bottom - plot_top

	# 4. Driving Range Center Target Line (vertical zero offline line)
	draw_line(Vector2(center_x, plot_top), Vector2(center_x, plot_bottom), Color(1.0, 1.0, 1.0, 0.3), 1.0)

	# 5. Concentric Distance Arcs / Range Rings (Top-down perspective)
	# Draw concentric arcs anchored below the bottom (like looking out from the tee box)
	var tee_origin_y := plot_bottom + (plot_height * 0.15)
	var arc_step := 50.0
	if max_scale_yds > 250.0:
		arc_step = 50.0
	elif max_scale_yds <= 100.0:
		arc_step = 25.0

	var d_yds := arc_step
	while d_yds <= max_scale_yds:
		var frac = d_yds / max_scale_yds
		var arc_y = tee_origin_y - (frac * (tee_origin_y - plot_top))
		var radius = tee_origin_y - arc_y

		# Draw curved arc across the range width
		_draw_range_arc(Vector2(center_x, tee_origin_y), radius, Color(0.8, 0.85, 0.9, 0.35), 1.2)

		# Distance label on the arc at center
		if font and arc_y >= plot_top + 4.0:
			var arc_lbl = "%d" % int(d_yds)
			draw_string(font, Vector2(center_x + 3, arc_y - 3), arc_lbl, HORIZONTAL_ALIGNMENT_LEFT, 36, 9, Color(0.85, 0.9, 1.0, 0.85))

		d_yds += arc_step

	# 6. Calculate Mean & Dispersion Ellipse for Club Grouping
	var points_screen: Array[Vector2] = []
	var sum_x := 0.0
	var sum_y := 0.0

	for shot in _shots:
		var total_yds = float(shot.get("TotalDistance", shot.get("CarryDistance", 0.0))) * 1.09361
		var off_yds = _extract_offline_meters(shot) * 1.09361

		var screen_x = remap(off_yds, -max_scale_offline_yds, max_scale_offline_yds, plot_left, plot_right)
		var frac_y = clampf(total_yds / max_scale_yds, 0.0, 1.05)
		var screen_y = tee_origin_y - (frac_y * (tee_origin_y - plot_top))

		var pt = Vector2(clampf(screen_x, plot_left, plot_right), clampf(screen_y, plot_top, plot_bottom))
		points_screen.append(pt)
		sum_x += pt.x
		sum_y += pt.y

	# Draw Dispersion Grouping Ellipse if we have 3 or more shots
	if points_screen.size() >= 3:
		var mean_pt = Vector2(sum_x / points_screen.size(), sum_y / points_screen.size())
		var var_x := 0.0
		var var_y := 0.0
		for pt in points_screen:
			var dx = pt.x - mean_pt.x
			var dy = pt.y - mean_pt.y
			var_x += dx * dx
			var_y += dy * dy
		var std_x = sqrt(var_x / points_screen.size())
		var std_y = sqrt(var_y / points_screen.size())

		# Grouping ellipse covering ~1.8 standard deviations (matching reference image)
		var rx = maxf(std_x * 1.8, 14.0)
		var ry = maxf(std_y * 1.8, 16.0)

		# Draw dispersion ellipse with translucent fill and vibrant border
		var ellipse_col = Color(0.2, 0.85, 0.45, 0.75) # Vibrant green grouping ring
		_draw_ellipse(mean_pt, rx, ry, ellipse_col, 1.5)
		_draw_ellipse_fill(mean_pt, rx, ry, Color(ellipse_col.r, ellipse_col.g, ellipse_col.b, 0.08))

	# 7. Draw Ball Landing Points (dots with halos matching tracer colors)
	for i in points_screen.size():
		var pt = points_screen[i]
		var is_latest = (i == points_screen.size() - 1)
		var col = ARC_COLORS[i % ARC_COLORS.size()]

		if is_latest:
			# High-visibility pulsing halo on the newest landing point
			draw_circle(pt, 8.0, Color(col.r, col.g, col.b, 0.35))
			draw_circle(pt, 5.0, col)
			draw_circle(pt, 2.5, Color.WHITE)
		else:
			# Shaded landing dot with soft outer ring
			draw_circle(pt, 4.5, Color(col.r, col.g, col.b, 0.25))
			draw_circle(pt, 3.0, col)

func _draw_range_arc(center: Vector2, radius: float, color: Color, width: float) -> void:
	# Draw arc between -24 deg and +24 deg from vertical (up = -PI/2)
	var base_angle := -PI * 0.5
	var spread := 0.42 # ~24 degrees
	var segments := 24
	var prev_pt := Vector2.ZERO

	for i in range(segments + 1):
		var t = float(i) / float(segments)
		var angle = base_angle - spread + (t * spread * 2.0)
		var curr_pt = center + Vector2(cos(angle), sin(angle)) * radius
		if i > 0:
			draw_line(prev_pt, curr_pt, color, width, true)
		prev_pt = curr_pt

func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color, width: float) -> void:
	var segments := 32
	var prev_pt := Vector2.ZERO
	for i in range(segments + 1):
		var angle = (float(i) / float(segments)) * TAU
		var pt = center + Vector2(cos(angle) * rx, sin(angle) * ry)
		if i > 0:
			draw_line(prev_pt, pt, color, width, true)
		prev_pt = pt

func _draw_ellipse_fill(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var segments := 24
	var poly = PackedVector2Array()
	for i in range(segments):
		var angle = (float(i) / float(segments)) * TAU
		poly.append(center + Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(poly, color)


func _extract_offline_meters(shot: Dictionary) -> float:
	# 1. Prefer explicit SideDistance if non-zero
	var s_val = float(shot.get("SideDistance", 0.0))
	if absf(s_val) > 0.001:
		return s_val

	# 2. Extract from tracer points lateral displacement if available
	if shot.has("tracer_points"):
		var pts: Array = shot["tracer_points"]
		if pts.size() >= 2:
			var start_pt: Vector3 = pts[0]
			var end_pt: Vector3 = pts[-1]
			var lateral = end_pt.z - start_pt.z
			if absf(lateral) > 0.001:
				return lateral

	# 3. Fallback: estimate from Horizontal Launch Angle (HLA) and distance
	var hla = float(shot.get("HLA", 0.0))
	if absf(hla) > 0.01:
		var dist = float(shot.get("TotalDistance", shot.get("CarryDistance", 0.0)))
		if dist > 1.0:
			return dist * sin(deg_to_rad(hla))

	return 0.0

