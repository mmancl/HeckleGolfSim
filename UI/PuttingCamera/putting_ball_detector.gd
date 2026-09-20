class_name PuttingBallDetector
extends RefCounted

## Geometry and movement thresholds (normalized coordinates)
const MOVEMENT_THRESHOLD_NORM: float = 0.035          # Min distance from anchor to consider ball moved
const REST_FRAMES_REQUIRED: int = 6                   # Consecutive frames at rest (~200ms) to confirm READY
const JITTER_DEADBAND_NORM: float = 0.010             # Ignore sub-pixel noise under this threshold (~1.2px)

## Color & Contrast parameters
const MAX_BALL_SATURATION: float = 0.35               # White ball under warm/cool lights has saturation < 0.35
const MIN_BALL_CONTRAST: float = 0.14                 # Minimum brightness contrast above mat surface
const MIN_PEAK_LUMINANCE: float = 0.44                # Minimum peak brightness for a white ball in indoor lighting

## Blob constraints at downsampled scale
const MIN_BLOB_PIXELS: int = 6                        # Min pixels for ball blob
const MAX_BLOB_PIXELS: int = 400                      # Max pixels (reject whole surfaces/walls/shoes/putters)

## Detection state
var ball_found: bool = false
var ball_center_norm: Vector2 = Vector2.ZERO
var ball_radius_norm: float = 0.0

var _rest_frame_count: int = 0
var _prev_center: Vector2 = Vector2.ZERO
var _smoothed_center: Vector2 = Vector2.ZERO
var _resting_anchor: Vector2 = Vector2.ZERO
var is_tracking: bool = false                         # Set to true when ball has launched


## Analyze a single Image frame and detect the golf ball.
## Returns a Dictionary: { "found": bool, "center": Vector2, "radius": float, "moved": bool, "at_rest": bool }
func detect_ball(image: Image, circle_center_norm: Vector2, circle_radius_norm: float) -> Dictionary:
	if image == null or image.get_width() < 10 or image.get_height() < 10:
		return {"found": false, "center": Vector2.ZERO, "radius": 0.0, "moved": false, "at_rest": false}

	var orig_w: int = image.get_width()
	var orig_h: int = image.get_height()

	# Downsample preserving exact aspect ratio (no non-uniform squashing/distortion)
	var max_dim: float = 128.0
	var scale: float = minf(max_dim / float(orig_w), max_dim / float(orig_h))
	var target_w: int = clampi(int(float(orig_w) * scale), 16, 128)
	var target_h: int = clampi(int(float(orig_h) * scale), 16, 128)

	var scaled_img: Image
	if orig_w != target_w or orig_h != target_h:
		scaled_img = image.duplicate()
		scaled_img.resize(target_w, target_h, Image.INTERPOLATE_BILINEAR)
	else:
		scaled_img = image

	var w: int = scaled_img.get_width()
	var h: int = scaled_img.get_height()

	# 1. Determine Search Region (ROI)
	# When looking for the ball in IDLE/READY, search the placement circle and forward departure zone
	# When tracking, cover the entire forward putting corridor
	var roi_min_x: int
	var roi_max_x: int
	var roi_min_y: int
	var roi_max_y: int

	if is_tracking:
		if _prev_center != Vector2.ZERO:
			# Follow the ball forward: do NOT scan behind the ball's last known position!
			roi_min_x = clampi(int((_prev_center.x - 0.28) * float(w)), 0, w - 1)
			roi_max_x = clampi(int((_prev_center.x + 0.28) * float(w)), 0, w - 1)
			roi_min_y = 0
			roi_max_y = clampi(int((_prev_center.y + 0.03) * float(h)), 0, h - 1)
		else:
			roi_min_x = clampi(int((circle_center_norm.x - 0.35) * float(w)), 0, w - 1)
			roi_max_x = clampi(int((circle_center_norm.x + 0.35) * float(w)), 0, w - 1)
			roi_min_y = 0
			roi_max_y = clampi(int((circle_center_norm.y + 0.05) * float(h)), 0, h - 1)
	else:
		var search_r = maxf(circle_radius_norm * 2.2, 0.28)
		roi_min_x = clampi(int((circle_center_norm.x - search_r) * float(w)), 0, w - 1)
		roi_max_x = clampi(int((circle_center_norm.x + search_r) * float(w)), 0, w - 1)
		# Allow forward search up to y=0.0 so departure is captured immediately
		roi_min_y = clampi(int((circle_center_norm.y - search_r * 2.2) * float(h)), 0, h - 1)
		roi_max_y = clampi(int((circle_center_norm.y + search_r * 1.2) * float(h)), 0, h - 1)

	if roi_max_x <= roi_min_x or roi_max_y <= roi_min_y:
		roi_min_x = 0; roi_max_x = w - 1; roi_min_y = 0; roi_max_y = h - 1

	# 2. Adaptive Contrast Analysis of the Mat & Potential Ball in the ROI
	var sum_lum: float = 0.0
	var max_lum: float = 0.0
	var roi_pixel_count: int = 0

	for y in range(roi_min_y, roi_max_y + 1):
		for x in range(roi_min_x, roi_max_x + 1):
			var c: Color = scaled_img.get_pixel(x, y)
			var lum: float = (c.r + c.g + c.b) / 3.0
			sum_lum += lum
			if lum > max_lum:
				max_lum = lum
			roi_pixel_count += 1

	if roi_pixel_count == 0:
		return _not_found()

	var avg_mat_lum: float = sum_lum / float(roi_pixel_count)
	var contrast: float = max_lum - avg_mat_lum

	# If there is no bright object contrasting against the surface, no ball is present
	var min_contrast = 0.10 if is_tracking else MIN_BALL_CONTRAST
	var min_peak = 0.38 if is_tracking else MIN_PEAK_LUMINANCE
	if contrast < min_contrast or max_lum < min_peak:
		return _not_found()

	# Adaptive brightness threshold: ball sits above the mat brightness
	var ball_lum_threshold: float = avg_mat_lum + contrast * (0.45 if is_tracking else 0.52)
	ball_lum_threshold = clampf(ball_lum_threshold, 0.42, 0.95)

	# 3. Label White Candidate Pixels in the ROI
	var white_grid: PackedByteArray = PackedByteArray()
	white_grid.resize(w * h)

	for y in range(roi_min_y, roi_max_y + 1):
		var row_offset: int = y * w
		for x in range(roi_min_x, roi_max_x + 1):
			var c: Color = scaled_img.get_pixel(x, y)
			var lum: float = (c.r + c.g + c.b) / 3.0
			if lum < ball_lum_threshold:
				continue

			var max_c: float = maxf(c.r, maxf(c.g, c.b))
			var min_c: float = minf(c.r, minf(c.g, c.b))
			var sat: float = (max_c - min_c) / max_c if max_c > 0.01 else 0.0

			# White ball has low saturation (rejects green turf, yellow, blue, red)
			if sat <= MAX_BALL_SATURATION:
				white_grid[row_offset + x] = 1

	# 4. Connected Component (Blob) Clustering
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(w * h)
	var blobs: Array[Dictionary] = []

	var queue: PackedInt32Array = PackedInt32Array()
	queue.resize(w * h)

	for y in range(roi_min_y, roi_max_y + 1):
		var row_offset: int = y * w
		for x in range(roi_min_x, roi_max_x + 1):
			var idx: int = row_offset + x
			if white_grid[idx] == 0 or visited[idx] == 1:
				continue

			# Flood fill blob
			var q_head: int = 0
			var q_tail: int = 0
			queue[q_tail] = idx
			q_tail += 1
			visited[idx] = 1

			var b_sum_x: float = 0.0
			var b_sum_y: float = 0.0
			var b_min_x: int = x
			var b_max_x: int = x
			var b_min_y: int = y
			var b_max_y: int = y
			var b_count: int = 0

			while q_head < q_tail:
				var cur_idx: int = queue[q_head]
				q_head += 1

				var cx: int = cur_idx % w
				var cy: int = cur_idx / w

				b_sum_x += float(cx)
				b_sum_y += float(cy)
				b_count += 1

				if cx < b_min_x: b_min_x = cx
				if cx > b_max_x: b_max_x = cx
				if cy < b_min_y: b_min_y = cy
				if cy > b_max_y: b_max_y = cy

				# Neighbors
				if cx > roi_min_x:
					var left = cur_idx - 1
					if white_grid[left] == 1 and visited[left] == 0:
						visited[left] = 1; queue[q_tail] = left; q_tail += 1
				if cx < roi_max_x:
					var right = cur_idx + 1
					if white_grid[right] == 1 and visited[right] == 0:
						visited[right] = 1; queue[q_tail] = right; q_tail += 1
				if cy > roi_min_y:
					var up = cur_idx - w
					if white_grid[up] == 1 and visited[up] == 0:
						visited[up] = 1; queue[q_tail] = up; q_tail += 1
				if cy < roi_max_y:
					var down = cur_idx + w
					if white_grid[down] == 1 and visited[down] == 0:
						visited[down] = 1; queue[q_tail] = down; q_tail += 1

			# Size filter
			if b_count < MIN_BLOB_PIXELS or b_count > MAX_BLOB_PIXELS:
				continue

			var bw: int = b_max_x - b_min_x + 1
			var bh: int = b_max_y - b_min_y + 1

			var min_dim: float = minf(float(bw), float(bh))
			var max_dim_b: float = maxf(float(bw), float(bh))
			var roundness: float = min_dim / max_dim_b

			# Motion-blur tolerance: allow elongated streaks when in motion
			var min_aspect = 0.25 if is_tracking else 0.48
			if roundness < min_aspect:
				continue

			# Fill factor check (solidity)
			var fill: float = float(b_count) / float(bw * bh)
			var min_fill = 0.22 if is_tracking else 0.38
			if fill < min_fill:
				continue

			var blob_cx: float = b_sum_x / float(b_count)
			var blob_cy: float = b_sum_y / float(b_count)

			# 3D Spherical Profile Check (only enforced when ball is stationary / entering READY)
			if not is_tracking:
				var core_x: int = clampi(int(round(blob_cx)), 0, w - 1)
				var core_y: int = clampi(int(round(blob_cy)), 0, h - 1)
				var core_c: Color = scaled_img.get_pixel(core_x, core_y)
				var core_lum: float = (core_c.r + core_c.g + core_c.b) / 3.0

				var border_lum_sum: float = 0.0
				var test_pts = [
					Vector2i(b_min_x, int(blob_cy)),
					Vector2i(b_max_x, int(blob_cy)),
					Vector2i(int(blob_cx), b_min_y),
					Vector2i(int(blob_cx), b_max_y)
				]
				for tp in test_pts:
					var pc: Color = scaled_img.get_pixel(clampi(tp.x, 0, w - 1), clampi(tp.y, 0, h - 1))
					border_lum_sum += (pc.r + pc.g + pc.b) / 3.0
				var border_lum_avg: float = border_lum_sum / 4.0

				var radial_gradient: float = core_lum - border_lum_avg
				# Flat reflections / tape markings are rejected
				if radial_gradient < -0.06:
					continue

			blobs.append({
				"count": b_count,
				"center": Vector2(blob_cx / float(w), blob_cy / float(h)),
				"radius": sqrt(float(b_count) / PI) / float(w),
				"roundness": roundness,
				"fill": fill,
			})

	# 5. Candidate Evaluation
	if blobs.is_empty():
		return _not_found()

	var target_anchor: Vector2
	if is_tracking and _prev_center != Vector2.ZERO:
		target_anchor = _prev_center
	else:
		target_anchor = circle_center_norm

	var best_blob: Dictionary = {}
	var best_score: float = -9999.0

	for b in blobs:
		var c_norm: Vector2 = b["center"]
		var dist_to_target: float = c_norm.distance_to(target_anchor)
		var proximity_score: float = 1.0 / (1.0 + dist_to_target * 5.0)
		var size_score: float = clampf(float(b["count"]) / 120.0, 0.2, 1.0)
		var round_score: float = float(b["roundness"])

		var score: float = proximity_score * 4.0 + round_score * 2.0 + size_score

		# Extra weight if inside the target placement circle (when looking for ball)
		if not is_tracking and is_ball_in_circle(c_norm, circle_center_norm, circle_radius_norm):
			score += 3.0

		# Extra weight for forward progress when tracking
		if is_tracking and c_norm.y < target_anchor.y:
			score += 2.0

		if score > best_score:
			best_score = score
			best_blob = b

	var raw_center: Vector2 = best_blob["center"]
	var approx_radius: float = best_blob["radius"]

	# 6. Anti-Jitter Smoothing with Deadband
	if _smoothed_center == Vector2.ZERO or not ball_found:
		_smoothed_center = raw_center
		_resting_anchor = raw_center
		_rest_frame_count = 0
	else:
		var jitter_dist: float = raw_center.distance_to(_smoothed_center)
		if jitter_dist < JITTER_DEADBAND_NORM:
			# Sub-pixel noise: freeze position to prevent shaking/jumping
			_smoothed_center = _smoothed_center.lerp(raw_center, 0.05)
		elif jitter_dist < MOVEMENT_THRESHOLD_NORM:
			# Minor position adjustment
			_smoothed_center = _smoothed_center.lerp(raw_center, 0.25)
		else:
			# True movement: track smoothly
			_smoothed_center = _smoothed_center.lerp(raw_center, 0.85)

	ball_found = true
	ball_center_norm = _smoothed_center
	ball_radius_norm = approx_radius

	# 7. Movement & Rest Analysis
	var moved: bool = false
	var dist_from_anchor: float = ball_center_norm.distance_to(_resting_anchor)

	if dist_from_anchor > MOVEMENT_THRESHOLD_NORM:
		moved = true
		_rest_frame_count = 0
		_resting_anchor = ball_center_norm
	else:
		_resting_anchor = _resting_anchor.lerp(ball_center_norm, 0.08)
		# Only count towards at_rest if the ball is inside the designated target circle!
		if is_ball_in_circle(ball_center_norm, circle_center_norm, circle_radius_norm):
			_rest_frame_count += 1
		else:
			_rest_frame_count = 0

	_prev_center = ball_center_norm

	return {
		"found": true,
		"center": ball_center_norm,
		"radius": approx_radius,
		"moved": moved,
		"at_rest": _rest_frame_count >= REST_FRAMES_REQUIRED,
	}


func _not_found() -> Dictionary:
	ball_found = false
	_rest_frame_count = 0
	return {
		"found": false,
		"center": Vector2.ZERO,
		"radius": 0.0,
		"moved": false,
		"at_rest": false,
	}


## Check if ball center is inside the target circle overlay
func is_ball_in_circle(ball_center: Vector2, circle_center: Vector2, circle_radius: float) -> bool:
	return ball_center.distance_to(circle_center) <= circle_radius


## Calculate lateral offset in pixels/normalized units relative to the midline arrow
func calculate_lateral_offset(ball_center: Vector2, midline_x: float) -> float:
	return ball_center.x - midline_x


func reset() -> void:
	ball_found = false
	ball_center_norm = Vector2.ZERO
	ball_radius_norm = 0.0
	_rest_frame_count = 0
	_prev_center = Vector2.ZERO
	_smoothed_center = Vector2.ZERO
	_resting_anchor = Vector2.ZERO
	is_tracking = false
