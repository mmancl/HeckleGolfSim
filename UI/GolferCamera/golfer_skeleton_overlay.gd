extends Control

# GolferSkeletonOverlay
# Renders real MediaPipe Pose 33-landmark skeleton detected by the AI model.
# Receives landmark data from the PoseDetectionBridge autoload singleton.
# Computes real biomechanical telemetry (spine angle, shoulder turn, etc.)
# from the actual detected joint positions.

class_name GolferSkeletonOverlay

# Toggle tracking features
var show_skeleton: bool = true
var is_replay_mode: bool = false
var frame_buffer: SwingFrameBuffer = null
var _last_img: Image = null

# Camera & Detection State
var active_camera_detected: bool = false
var human_detected: bool = false
var _target_texture: Texture2D = null

# MediaPipe 13-Landmark Data ({ "pos": Vector2, "visible": bool, "visibility": float })
var landmarks: Dictionary = {
	"nose": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"left_shoulder": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"right_shoulder": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"left_elbow": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"right_elbow": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"left_wrist": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"right_wrist": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"left_hip": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"right_hip": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"left_knee": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"right_knee": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"left_ankle": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
	"right_ankle": { "pos": Vector2.ZERO, "visible": false, "visibility": 0.0 },
}

# ─── Real Measured Pose Telemetry ────────────────────────────────────────────
# These are COMPUTED from actual landmark positions every frame.
var measured_spine_angle: float = 0.0
var measured_shoulder_turn: float = 0.0
var measured_early_extension: float = 0.0
var measured_hip_sway: float = 0.0

# Baseline positions captured at first stable detection (address position)
var _baseline_captured: bool = false
var _baseline_shoulder_width: float = 0.0
var _baseline_hip_mid_y: float = 0.0
var _baseline_hip_mid_x: float = 0.0
var _stable_frame_count: int = 0
const BASELINE_STABILITY_FRAMES: int = 10  # Require 10 stable frames before capturing

# Telemetry validity flag
var has_valid_telemetry: bool = false

# Pause & Progress State
var is_paused: bool = false
var progress: float = 0.0

# Bridge connection
var _bridge_connected: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_connect_to_bridge()


func _connect_to_bridge() -> void:
	if _bridge_connected:
		return
	# Connect to PoseDetectionBridge autoload singleton
	var bridge = _get_bridge()
	if bridge != null:
		if not bridge.pose_detected.is_connected(_on_pose_detected):
			bridge.pose_detected.connect(_on_pose_detected)
		if not bridge.pose_lost.is_connected(_on_pose_lost):
			bridge.pose_lost.connect(_on_pose_lost)
		_bridge_connected = true


func _get_bridge():
	# Access the autoload singleton
	if Engine.has_singleton("PoseDetectionBridge"):
		return Engine.get_singleton("PoseDetectionBridge")
	# Fallback: find it in the scene tree
	var root = get_tree().root if is_inside_tree() else null
	if root != null:
		return root.get_node_or_null("PoseDetectionBridge")
	return null


func _is_modal_active() -> bool:
	if not is_inside_tree():
		return false
	return get_tree().root.find_child("SwingReplayModal", true, false) != null


func _process(_delta: float) -> void:
	if is_replay_mode:
		queue_redraw()
		return

	if _is_modal_active():
		return

	if not _bridge_connected:
		_connect_to_bridge()
	
	# Find the camera texture from parent hierarchy
	var parent_tex_rect = get_parent() as TextureRect
	if parent_tex_rect != null and parent_tex_rect.texture != null:
		_send_frame_to_bridge(parent_tex_rect.texture)
	else:
		var parent_node = get_parent()
		if parent_node != null:
			var cam_rect = parent_node.get_node_or_null("CameraFeedRect") as TextureRect
			if cam_rect != null and cam_rect.texture != null:
				_send_frame_to_bridge(cam_rect.texture)
			elif parent_node.has_node("ReplayFeedRect"):
				var replay_rect = parent_node.get_node_or_null("ReplayFeedRect") as TextureRect
				if replay_rect != null and replay_rect.texture != null:
					_send_frame_to_bridge(replay_rect.texture)
	
	queue_redraw()


func _send_frame_to_bridge(tex: Texture2D) -> void:
	if tex == null:
		_target_texture = null
		active_camera_detected = false
		return
	
	_target_texture = tex
	active_camera_detected = true
	
	var bridge = _get_bridge()
	if bridge == null or not bridge.is_ready():
		return
	
	# Extract image from texture
	var img: Image = null
	if tex.has_method("get_image"):
		img = tex.get_image()
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			if img.get_format() != Image.FORMAT_RGBA8 and img.get_format() != Image.FORMAT_RGB8:
				img.convert(Image.FORMAT_RGBA8)
	
	# Fallback: capture from viewport if texture extraction fails (e.g. Android OES camera textures)
	if (img == null or img.is_empty()) and is_inside_tree():
		var vp = get_viewport()
		if vp != null:
			var vp_tex = vp.get_texture()
			if vp_tex != null:
				var full_img = vp_tex.get_image()
				if full_img != null and not full_img.is_empty():
					if full_img.is_compressed():
						full_img.decompress()
					if full_img.get_format() != Image.FORMAT_RGBA8 and full_img.get_format() != Image.FORMAT_RGB8:
						full_img.convert(Image.FORMAT_RGBA8)
					full_img.flip_y()
					var glob_rect = get_global_rect()
					var vp_sz = vp.get_visible_rect().size
					if glob_rect.size.x > 10 and glob_rect.size.y > 10:
						var crop_x = clamp(int(glob_rect.position.x), 0, int(vp_sz.x - 10))
						var crop_y = clamp(int(glob_rect.position.y), 0, int(vp_sz.y - 10))
						var crop_w = clamp(int(glob_rect.size.x), 10, int(vp_sz.x - crop_x))
						var crop_h = clamp(int(glob_rect.size.y), 10, int(vp_sz.y - crop_y))
						img = full_img.get_region(Rect2i(crop_x, crop_y, crop_w, crop_h))
	
	if img != null and not img.is_empty():
		_last_img = img
		bridge.process_frame(img)


func set_camera_texture(tex: Texture2D) -> void:
	# Keep this method for compatibility — the automatic _process() pipeline handles everything
	_target_texture = tex
	active_camera_detected = (tex != null)


func set_frame_progress(prog: float) -> void:
	progress = clamp(prog, 0.0, 1.0)
	queue_redraw()


func reset_baseline() -> void:
	"""Reset the baseline address position. Call when golfer re-addresses the ball."""
	_baseline_captured = false
	_stable_frame_count = 0
	_baseline_shoulder_width = 0.0
	_baseline_hip_mid_y = 0.0
	_baseline_hip_mid_x = 0.0
	has_valid_telemetry = false


# ─── Pose Detection Callbacks ───────────────────────────────────────────────

func _on_pose_detected(raw_landmarks: Dictionary) -> void:
	if not is_replay_mode and _is_modal_active():
		return
	human_detected = true
	
	# Update landmark positions from the bridge data
	for k in raw_landmarks.keys():
		if landmarks.has(k):
			var lm_item: Dictionary = raw_landmarks[k]
			var vis: float = float(lm_item.get("visibility", 1.0 if lm_item.has("x") else 0.0))
			landmarks[k]["visible"] = (vis >= 0.25)
			landmarks[k]["visibility"] = vis
			landmarks[k]["pos"] = Vector2(float(lm_item.get("x", 0.0)), float(lm_item.get("y", 0.0)))
	
	# Compute real biomechanical telemetry from landmarks
	_compute_telemetry()
	
	# Push frame to buffer if recording
	if frame_buffer != null and _last_img != null and not is_replay_mode:
		frame_buffer.push_frame(_last_img, raw_landmarks)


func _on_pose_lost() -> void:
	human_detected = false
	_reset_landmark_visibility()


func _reset_landmark_visibility() -> void:
	for k in landmarks.keys():
		landmarks[k]["visible"] = false
		landmarks[k]["visibility"] = 0.0


# ─── Real Biomechanical Telemetry Computation ────────────────────────────────

func _compute_telemetry() -> void:
	var ls = landmarks["left_shoulder"]
	var rs = landmarks["right_shoulder"]
	var lh = landmarks["left_hip"]
	var rh = landmarks["right_hip"]
	
	# Need at least shoulders and hips visible for telemetry
	if not (ls["visible"] and rs["visible"] and lh["visible"] and rh["visible"]):
		return
	
	var shoulder_mid: Vector2 = (Vector2(ls["pos"]) + Vector2(rs["pos"])) * 0.5
	var hip_mid: Vector2 = (Vector2(lh["pos"]) + Vector2(rh["pos"])) * 0.5
	var shoulder_width: float = Vector2(ls["pos"]).distance_to(Vector2(rs["pos"]))
	
	# ── Capture baseline (address position) after stable detection ──
	if not _baseline_captured:
		_stable_frame_count += 1
		if _stable_frame_count >= BASELINE_STABILITY_FRAMES:
			_baseline_shoulder_width = shoulder_width
			_baseline_hip_mid_y = hip_mid.y
			_baseline_hip_mid_x = hip_mid.x
			_baseline_captured = true
			print("[SkeletonOverlay] Baseline captured — shoulder width: %.4f" % _baseline_shoulder_width)
		return
	
	has_valid_telemetry = true
	
	# ── 1. Spine Angle ──
	# Angle of the spine (hip_mid → shoulder_mid) relative to vertical.
	# In screen coordinates, Y increases downward.
	# A vertical spine has angle 0°; forward tilt increases the angle.
	var spine_vec: Vector2 = shoulder_mid - hip_mid  # Points from hips upward to shoulders
	# Vertical = (0, -1) in screen space (upward)
	# Use atan2 to get angle from vertical
	var spine_angle_rad: float = atan2(abs(spine_vec.x), -spine_vec.y)
	measured_spine_angle = rad_to_deg(spine_angle_rad)
	
	# ── 2. Shoulder Turn ──
	# Estimate shoulder rotation from perspective foreshortening.
	# When golfer faces camera square: shoulders at max apparent width.
	# When shoulders rotate (backswing): apparent width decreases.
	# Turn angle ≈ acos(current_width / baseline_width)
	if _baseline_shoulder_width > 0.001:
		var width_ratio: float = clamp(shoulder_width / _baseline_shoulder_width, 0.0, 1.0)
		measured_shoulder_turn = rad_to_deg(acos(width_ratio))
	
	# ── 3. Early Extension ──
	# How much the hips have moved toward the ball (upward in screen = smaller Y)
	# relative to the address position. Positive = hips moved forward.
	var hip_forward_shift: float = _baseline_hip_mid_y - hip_mid.y
	# Normalize by body height (shoulder-to-hip distance) for scale independence
	var torso_height: float = shoulder_mid.distance_to(hip_mid)
	if torso_height > 0.01:
		measured_early_extension = (hip_forward_shift / torso_height) * 10.0  # Scale to meaningful range
	
	# ── 4. Hip Sway ──
	# Lateral (horizontal) movement of hip midpoint from baseline.
	var hip_lateral_shift: float = hip_mid.x - _baseline_hip_mid_x
	if torso_height > 0.01:
		measured_hip_sway = (hip_lateral_shift / torso_height) * 10.0


func get_measured_telemetry() -> Dictionary:
	return {
		"spine_angle": measured_spine_angle,
		"shoulder_turn": measured_shoulder_turn,
		"early_extension": measured_early_extension,
		"hip_sway": measured_hip_sway,
		"has_valid_telemetry": has_valid_telemetry,
	}


# ─── Drawing ─────────────────────────────────────────────────────────────────

func _draw() -> void:
	if is_replay_mode:
		if not human_detected:
			return
	else:
		if _is_modal_active():
			return
		if not active_camera_detected or not human_detected or _target_texture == null:
			return
		
	var sz = size
	if sz.x <= 1 or sz.y <= 1:
		return

	var video_rect = Rect2(4, 4, sz.x - 8, sz.y - 8)

	var screen_lm: Dictionary = {}
	for k in landmarks.keys():
		var lm_data = landmarks[k]
		if lm_data.get("visible", false) == true:
			var j_pos = lm_data["pos"]
			var px = clamp(video_rect.position.x + j_pos.x * video_rect.size.x, video_rect.position.x, video_rect.position.x + video_rect.size.x)
			var py = clamp(video_rect.position.y + j_pos.y * video_rect.size.y, video_rect.position.y, video_rect.position.y + video_rect.size.y)
			screen_lm[k] = Vector2(px, py)

	var skeleton_col = Color(0.6, 0.2, 0.8, 0.95) # Purple MediaPipe glow
	var joint_col = Color(0.8, 0.1, 0.3, 0.95)    # Red joint nodes

	if show_skeleton:
		var mediapipe_pairs = [
			["nose", "left_shoulder"],
			["nose", "right_shoulder"],
			["left_shoulder", "right_shoulder"],
			["left_shoulder", "left_elbow"],
			["left_elbow", "left_wrist"],
			["right_shoulder", "right_elbow"],
			["right_elbow", "right_wrist"],
			["left_shoulder", "left_hip"],
			["right_shoulder", "right_hip"],
			["left_hip", "right_hip"],
			["left_hip", "left_knee"],
			["left_knee", "left_ankle"],
			["right_hip", "right_knee"],
			["right_knee", "right_ankle"],
		]
		
		for pair in mediapipe_pairs:
			if screen_lm.has(pair[0]) and screen_lm.has(pair[1]):
				var p1 = screen_lm[pair[0]]
				var p2 = screen_lm[pair[1]]
				draw_line(p1, p2, skeleton_col, 3.5, true)
			
		for k in screen_lm.keys():
			if k == "nose":
				draw_circle(screen_lm[k], 12.0, Color(0.8, 0.1, 0.3, 0.3))
				draw_arc(screen_lm[k], 12.0, 0, TAU, 24, joint_col, 2.5, true)
			else:
				draw_circle(screen_lm[k], 6.0, joint_col)
