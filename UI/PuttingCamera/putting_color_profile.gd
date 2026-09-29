class_name PuttingColorProfile
extends RefCounted

## Stores the user's configured ball and background color in HSV space.

var ball_hsv: Vector3 = Vector3(-1, -1, -1)   # H(0-360), S(0-1), V(0-1)
var ball_hue_tolerance: float = 30.0           # Degrees of hue tolerance
var ball_configured: bool = false

var bg_hsv: Vector3 = Vector3(-1, -1, -1)
var bg_configured: bool = false

## Load from settings strings
func load_from_settings() -> void:
	var global_settings = null
	if Engine.has_singleton("GlobalSettings"):
		global_settings = Engine.get_singleton("GlobalSettings")
	elif Engine.get_main_loop() and Engine.get_main_loop().root and Engine.get_main_loop().root.has_node("GlobalSettings"):
		global_settings = Engine.get_main_loop().root.get_node("GlobalSettings")

	if global_settings == null or not ("range_settings" in global_settings):
		return

	var range_settings = global_settings.range_settings
	if "putting_ball_color_hsv" in range_settings:
		var ball_str: String = str(range_settings.putting_ball_color_hsv.value)
		if not ball_str.is_empty():
			var parts = ball_str.split(",")
			if parts.size() == 3:
				ball_hsv = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				ball_configured = true
			else:
				ball_configured = false
		else:
			ball_configured = false

	if "putting_ball_color_tolerance" in range_settings:
		ball_hue_tolerance = float(range_settings.putting_ball_color_tolerance.value)

	if "putting_bg_color_hsv" in range_settings:
		var bg_str: String = str(range_settings.putting_bg_color_hsv.value)
		if not bg_str.is_empty():
			var parts = bg_str.split(",")
			if parts.size() == 3:
				bg_hsv = Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
				bg_configured = true
			else:
				bg_configured = false
		else:
			bg_configured = false

## Save to settings strings
func save_to_settings() -> void:
	var global_settings = null
	if Engine.has_singleton("GlobalSettings"):
		global_settings = Engine.get_singleton("GlobalSettings")
	elif Engine.get_main_loop() and Engine.get_main_loop().root and Engine.get_main_loop().root.has_node("GlobalSettings"):
		global_settings = Engine.get_main_loop().root.get_node("GlobalSettings")

	if global_settings == null or not ("range_settings" in global_settings):
		return

	var range_settings = global_settings.range_settings
	if "putting_ball_color_hsv" in range_settings:
		if ball_configured:
			range_settings.putting_ball_color_hsv.set_value("%.1f,%.3f,%.3f" % [ball_hsv.x, ball_hsv.y, ball_hsv.z])
		else:
			range_settings.putting_ball_color_hsv.set_value("")

	if "putting_ball_color_tolerance" in range_settings:
		range_settings.putting_ball_color_tolerance.set_value(ball_hue_tolerance)

	if "putting_bg_color_hsv" in range_settings:
		if bg_configured:
			range_settings.putting_bg_color_hsv.set_value("%.1f,%.3f,%.3f" % [bg_hsv.x, bg_hsv.y, bg_hsv.z])
		else:
			range_settings.putting_bg_color_hsv.set_value("")

	if global_settings.has_method("save_settings"):
		global_settings.save_settings()

## Check if a given HSV color matches the ball profile
func matches_ball(hsv: Vector3) -> bool:
	if not ball_configured:
		return true  # No filter configured, accept all (fallback mode)
	var hue_diff = minf(absf(hsv.x - ball_hsv.x), 360.0 - absf(hsv.x - ball_hsv.x))
	if hue_diff > ball_hue_tolerance:
		return false
	if absf(hsv.y - ball_hsv.y) > 0.35:
		return false
	if absf(hsv.z - ball_hsv.z) > 0.35:
		return false
	return true

## Check if a given HSV color matches the background profile
func matches_background(hsv: Vector3) -> bool:
	if not bg_configured:
		return true
	var hue_diff = minf(absf(hsv.x - bg_hsv.x), 360.0 - absf(hsv.x - bg_hsv.x))
	return hue_diff < 45.0 and absf(hsv.y - bg_hsv.y) < 0.35 and absf(hsv.z - bg_hsv.z) < 0.35
