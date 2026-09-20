class_name PuttingCameraWidget
extends Control

## Self-contained Putting Camera Widget with live video feed, overlay,
## state machine, 90-degree rotation support, and camera setup dialog.
## Designed for use in Putting Practice minigames, Driving Range, and Course Play.

signal putt_detected(putt_data: Dictionary)
signal visibility_changed_custom(is_visible: bool)

var _panel: PanelContainer = null
var _camera_feed_rect: TextureRect = null
var _overlay: PuttingCameraOverlay = null
var _state_machine: PuttingCameraStateMachine = null
var _camera_rotate_btn: Button = null
var _camera_flip_btn: Button = null
var _camera_minimize_btn: Button = null
var _camera_restore_pill: Button = null
var _overlay_status_vbox: VBoxContainer = null
var _feed_status_label: Label = null

var _http_req: HTTPRequest = null
var _is_active: bool = false
var _is_minimized: bool = false
var _phone_stream_failed_count: int = 0
var _is_requesting_frame: bool = false
var _stream_established: bool = false
var _alt_endpoint_idx: int = 0
var _current_camera_feed_index: int = 0

var camera_rotation_deg: int:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			return int(GlobalSettings.range_settings.putting_camera_rotation.value)
		return _local_rotation_deg
	set(val):
		_local_rotation_deg = val % 360
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.putting_camera_rotation.set_value(_local_rotation_deg)
			GlobalSettings.save_settings()

var _local_rotation_deg: int = 0

var _phone_cam_url: String:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			return GlobalSettings.range_settings.phone_cam_url.value
		return ""
	set(val):
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.phone_cam_url.set_value(val)
			GlobalSettings.save_settings()

var _use_phone_stream: bool:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			return GlobalSettings.range_settings.use_phone_stream.value
		return false
	set(val):
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.use_phone_stream.set_value(val)
			GlobalSettings.save_settings()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()

	# Connect to PoseDetectionBridge signals if available
	var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else (get_node_or_null("/root/PoseDetectionBridge") if is_inside_tree() else null)
	if bridge != null:
		if bridge.has_signal("desktop_frame_received") and not bridge.desktop_frame_received.is_connected(_on_desktop_frame_received):
			bridge.desktop_frame_received.connect(_on_desktop_frame_received)
		if bridge.has_signal("desktop_cameras_updated") and not bridge.desktop_cameras_updated.is_connected(_on_desktop_cameras_updated):
			bridge.desktop_cameras_updated.connect(_on_desktop_cameras_updated)

	if CameraServer.has_signal("camera_feed_added"):
		CameraServer.connect("camera_feed_added", func(_id):
			if _is_active and not _use_phone_stream:
				_update_camera_feed(true)
		)


func _exit_tree() -> void:
	set_camera_active(false)


func _build_ui() -> void:
	# 1. Main Camera Panel
	_panel = PanelContainer.new()
	_panel.name = "PuttingCameraPanel"
	_panel.visible = false
	_panel.position = Vector2(30, 130)
	_panel.custom_minimum_size = Vector2(330, 520)
	_panel.size = Vector2(330, 520)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.2, 0.5, 0.7, 0.8)
	panel_style.content_margin_left = 8
	panel_style.content_margin_top = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 6)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(main_vbox)

	# 2. Header Bar
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 6)

	var title = Label.new()
	title.text = "🎯 PUTTING CAM"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Setup Button
	var setup_btn = Button.new()
	setup_btn.text = "⚙️"
	setup_btn.tooltip_text = "Camera Setup (Connect Phone WiFi Stream or select Webcam)"
	setup_btn.custom_minimum_size = Vector2(40, 36)
	_apply_btn_style(setup_btn, Color(0.2, 0.45, 0.65, 0.9))
	setup_btn.pressed.connect(_open_camera_setup_dialog)
	header.add_child(setup_btn)

	# Rotate 90° Button
	_camera_rotate_btn = Button.new()
	_camera_rotate_btn.name = "RotateButton"
	_update_rotate_button_text()
	_camera_rotate_btn.custom_minimum_size = Vector2(64, 36)
	_apply_btn_style(_camera_rotate_btn, Color(0.25, 0.50, 0.40, 0.9))
	_camera_rotate_btn.pressed.connect(rotate_camera_90)
	header.add_child(_camera_rotate_btn)

	# Flip/Source Button
	_camera_flip_btn = Button.new()
	_camera_flip_btn.text = "🔄"
	_camera_flip_btn.tooltip_text = "Cycle through local camera inputs"
	_camera_flip_btn.custom_minimum_size = Vector2(40, 36)
	_apply_btn_style(_camera_flip_btn, Color(0.2, 0.4, 0.6, 0.9))
	_camera_flip_btn.pressed.connect(_on_flip_camera_pressed)
	header.add_child(_camera_flip_btn)

	# Minimize Button
	_camera_minimize_btn = Button.new()
	_camera_minimize_btn.text = "🗕"
	_camera_minimize_btn.tooltip_text = "Minimize Putting Cam (Keeps tracking in background)"
	_camera_minimize_btn.custom_minimum_size = Vector2(36, 36)
	_apply_btn_style(_camera_minimize_btn, Color(0.25, 0.35, 0.45, 0.9))
	_camera_minimize_btn.pressed.connect(minimize)
	header.add_child(_camera_minimize_btn)

	main_vbox.add_child(header)

	# 3. Video Feed Container
	var feed_container = PanelContainer.new()
	feed_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var inner_style = StyleBoxFlat.new()
	inner_style.bg_color = Color(0.04, 0.05, 0.07, 0.95)
	inner_style.corner_radius_top_left = 8
	inner_style.corner_radius_top_right = 8
	inner_style.corner_radius_bottom_left = 8
	inner_style.corner_radius_bottom_right = 8
	feed_container.add_theme_stylebox_override("panel", inner_style)

	_camera_feed_rect = TextureRect.new()
	_camera_feed_rect.name = "CameraFeedRect"
	_camera_feed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_feed_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_camera_feed_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_camera_feed_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_container.add_child(_camera_feed_rect)

	# 4. Putting Camera Overlay
	_overlay = PuttingCameraOverlay.new()
	_overlay.name = "PuttingCameraOverlay"
	_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_container.add_child(_overlay)

	# 5. Status Overlay for Searching/Errors
	_overlay_status_vbox = VBoxContainer.new()
	_overlay_status_vbox.name = "OverlayStatusVBox"
	_overlay_status_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_overlay_status_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay_status_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overlay_status_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_feed_status_label = Label.new()
	_feed_status_label.name = "FeedStatusLabel"
	_feed_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feed_status_label.add_theme_font_size_override("font_size", 13)
	_feed_status_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	_overlay_status_vbox.add_child(_feed_status_label)
	feed_container.add_child(_overlay_status_vbox)

	main_vbox.add_child(feed_container)

	# 6. State Machine
	_state_machine = PuttingCameraStateMachine.new()
	_state_machine.name = "PuttingCameraStateMachine"
	_state_machine.overlay = _overlay
	add_child(_state_machine)
	_state_machine.putt_detected.connect(_on_putt_detected)

	# 7. Floating Restore Pill (when minimized)
	_camera_restore_pill = Button.new()
	_camera_restore_pill.name = "CameraRestorePill"
	_camera_restore_pill.text = "🎯 Putting Cam [REC] 🗖"
	_camera_restore_pill.tooltip_text = "Putting Cam is tracking in background. Click to expand preview."
	_camera_restore_pill.visible = false
	_camera_restore_pill.position = Vector2(30, 130)
	_camera_restore_pill.custom_minimum_size = Vector2(190, 44)
	_apply_btn_style(_camera_restore_pill, Color(0.18, 0.40, 0.30, 0.9))
	_camera_restore_pill.pressed.connect(restore)
	add_child(_camera_restore_pill)


func _update_rotate_button_text() -> void:
	if _camera_rotate_btn != null:
		var deg = camera_rotation_deg
		_camera_rotate_btn.text = "🔁 %d°" % deg
		_camera_rotate_btn.tooltip_text = "Rotate Camera Feed 90° (Current: %d°). Align feed with putting roll direction." % deg


## Rotates the incoming video feed and ball detection by 90 degrees clockwise
func rotate_camera_90() -> void:
	camera_rotation_deg = (camera_rotation_deg + 90) % 360
	_update_rotate_button_text()
	if _state_machine != null:
		_state_machine.reset()
	print("[PuttingCamWidget] Camera rotation set to: %d°" % camera_rotation_deg)


## Helper to apply rotation to an Image
func apply_image_rotation(img: Image) -> Image:
	if img == null:
		return null
	var deg = camera_rotation_deg
	match deg:
		90:
			img.rotate_90(CLOCKWISE)
		180:
			img.rotate_180()
		270:
			img.rotate_90(COUNTERCLOCKWISE)
		_:
			pass
	return img


func set_camera_active(active: bool) -> void:
	_is_active = active
	if active:
		_is_minimized = false
		_panel.visible = true
		_camera_restore_pill.visible = false
		_state_machine.reset()
		_update_camera_feed(true)
	else:
		_panel.visible = false
		_camera_restore_pill.visible = false
		_update_camera_feed(false)
		_state_machine.reset()
	visibility_changed_custom.emit(active)


func is_camera_active() -> bool:
	return _is_active


func is_camera_minimized() -> bool:
	return _is_minimized


func minimize() -> void:
	if not _is_active:
		return
	_is_minimized = true
	_panel.visible = false
	_camera_restore_pill.visible = true
	visibility_changed_custom.emit(false)


func restore() -> void:
	if not _is_active:
		set_camera_active(true)
		return
	_is_minimized = false
	_panel.visible = true
	_camera_restore_pill.visible = false
	visibility_changed_custom.emit(true)


func on_next_shot_started() -> void:
	if _state_machine != null and _state_machine.current_state == PuttingCameraStateMachine.State.EXECUTION:
		_state_machine._transition_to(PuttingCameraStateMachine.State.IDLE)


func _on_putt_detected(speed_mph: float, hla_deg: float) -> void:
	var putt_data: Dictionary = {
		"Speed": speed_mph,
		"BallSpeed": speed_mph,
		"VLA": 0.0,
		"HLA": hla_deg,
		"TotalSpin": 0.0,
		"SpinAxis": 0.0,
		"BackSpin": 0.0,
		"SideSpin": 0.0,
		"Club": "Pt",
		"ShotType": "putt",
		"Source": "PuttingCamera",
	}
	print("[PuttingCamWidget] Dispatching putt: %s" % str(putt_data))
	putt_detected.emit(putt_data)


func _update_camera_feed(active: bool) -> void:
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else (get_node_or_null("/root/PoseDetectionBridge") if is_inside_tree() else null)

	if not active:
		if pose_bridge != null and pose_bridge.has_method("pause_desktop_camera"):
			pose_bridge.pause_desktop_camera()
		if CameraServer.is_monitoring_feeds():
			var feeds = CameraServer.feeds()
			for feed in feeds:
				if feed != null:
					feed.feed_is_active = false
		CameraServer.set_monitoring_feeds(false)
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = null
		_update_status_overlay("PUTTING CAMERA FEED\n[ Click ⚙️ Setup to connect ]", true)
		return

	if pose_bridge != null and pose_bridge.has_method("resume_desktop_camera"):
		pose_bridge.resume_desktop_camera()

	CameraServer.set_monitoring_feeds(true)

	if _use_phone_stream and not _phone_cam_url.is_empty():
		_start_phone_camera_stream(_phone_cam_url)
		return

	var feeds = CameraServer.feeds()
	if feeds.size() > 0:
		_activate_camera_feed_index(clamp(_current_camera_feed_index, 0, feeds.size() - 1))
	elif pose_bridge != null and "desktop_cameras" in pose_bridge and pose_bridge.desktop_cameras.size() > 0:
		var sel_idx = clamp(_current_camera_feed_index, 0, pose_bridge.desktop_cameras.size() - 1)
		pose_bridge.select_desktop_camera(sel_idx)
		_update_status_overlay("", false)
	else:
		_update_status_overlay("SEARCHING FOR WEBCAMS...\n[ Click ⚙️ Setup for phone stream ]", true)
		if pose_bridge != null and pose_bridge.has_method("fetch_desktop_cameras"):
			pose_bridge.fetch_desktop_cameras()


func _activate_camera_feed_index(index: int) -> void:
	var feeds = CameraServer.feeds()
	if index < 0 or index >= feeds.size():
		var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
		if pose_bridge != null and "desktop_cameras" in pose_bridge and index >= 0 and index < pose_bridge.desktop_cameras.size():
			pose_bridge.select_desktop_camera(index)
			_update_status_overlay("", false)
			return
		_update_status_overlay("NO LOCAL WEBCAM DETECTED\n[ Click ⚙️ Setup for Phone Stream ]", true)
		return

	var feed = feeds[index]
	if feed != null:
		feed.feed_is_active = true
		var cam_tex = CameraTexture.new()
		cam_tex.camera_feed_id = feed.get_id()
		cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
		cam_tex.camera_is_active = true
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = cam_tex
		_update_status_overlay("", false)


func _on_desktop_cameras_updated(cams: Array) -> void:
	if _is_active and not _use_phone_stream and cams.size() > 0:
		var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
		if bridge != null and bridge.has_method("select_desktop_camera"):
			var sel_idx = clamp(_current_camera_feed_index, 0, cams.size() - 1)
			bridge.select_desktop_camera(sel_idx)
			_update_status_overlay("", false)


func _on_desktop_frame_received(_img: Image, tex: Texture2D, _landmarks: Dictionary) -> void:
	if not _is_active or _use_phone_stream or _img == null:
		return

	# Apply rotation to the frame
	var rotated_img: Image = _img.duplicate()
	apply_image_rotation(rotated_img)

	if _camera_feed_rect != null:
		_camera_feed_rect.texture = ImageTexture.create_from_image(rotated_img)
	_update_status_overlay("", false)

	if _state_machine != null:
		_state_machine.process_frame(rotated_img)


func _on_flip_camera_pressed() -> void:
	if _use_phone_stream:
		_use_phone_stream = false

	var feeds = CameraServer.feeds()
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	var desk_cams: Array = pose_bridge.desktop_cameras if (pose_bridge != null and "desktop_cameras" in pose_bridge) else []
	var total_count = max(feeds.size(), desk_cams.size())

	if total_count > 1:
		_current_camera_feed_index = (_current_camera_feed_index + 1) % total_count
		_activate_camera_feed_index(_current_camera_feed_index)
	else:
		_open_camera_setup_dialog()


func _start_phone_camera_stream(url_str: String) -> void:
	_phone_cam_url = _normalize_phone_url(url_str)
	if _phone_cam_url.is_empty():
		_update_status_overlay("INVALID PHONE STREAM URL\n[ Enter IP e.g. 192.168.1.100:8080 ]", true)
		return

	_stream_established = false
	_phone_stream_failed_count = 0
	_alt_endpoint_idx = 0
	_update_status_overlay("CONNECTING TO PHONE STREAM...\n" + _phone_cam_url, true)

	if _http_req == null:
		_http_req = HTTPRequest.new()
		_http_req.name = "PhoneCameraHTTPRequest"
		_http_req.timeout = 3.0
		_http_req.request_completed.connect(_on_phone_cam_frame_received)
		add_child(_http_req)

	_is_requesting_frame = false
	_request_next_phone_frame()


func _request_next_phone_frame() -> void:
	if not _is_active or _phone_cam_url.is_empty() or _http_req == null or _is_requesting_frame:
		return

	_is_requesting_frame = true
	var headers = PackedStringArray([
		"User-Agent: HeckleGolfSim/1.0",
		"Accept: image/jpeg, image/*, */*",
		"Connection: keep-alive"
	])
	var err = _http_req.request(_phone_cam_url, headers)
	if err != OK:
		_is_requesting_frame = false
		_handle_phone_stream_error(-1, 0, "HTTP Request dispatch error: %d" % err)


func _on_phone_cam_frame_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_requesting_frame = false

	var success = (result == HTTPRequest.RESULT_SUCCESS and response_code == 200 and body.size() > 0)
	if success:
		var img = Image.new()
		var err = img.load_jpg_from_buffer(body)
		if err != OK:
			err = img.load_png_from_buffer(body)
		if err == OK:
			_phone_stream_failed_count = 0
			_stream_established = true

			# Rotate frame according to user setting
			apply_image_rotation(img)

			var tex = ImageTexture.create_from_image(img)
			if _camera_feed_rect != null:
				_camera_feed_rect.texture = tex
			_update_status_overlay("", false)

			if _state_machine != null:
				_state_machine.process_frame(img)
		else:
			_try_fallback_endpoint_or_error(result, response_code, "Invalid image encoding received")
	else:
		_try_fallback_endpoint_or_error(result, response_code, "")

	if _is_active and not _phone_cam_url.is_empty():
		var delay = 0.005 if _phone_stream_failed_count == 0 else clamp(0.4 * _phone_stream_failed_count, 0.4, 2.0)
		get_tree().create_timer(delay).timeout.connect(_request_next_phone_frame)


func _try_fallback_endpoint_or_error(result: int, response_code: int, custom_msg: String) -> void:
	if _stream_established:
		_handle_phone_stream_error(result, response_code, custom_msg)
		return

	var alt_paths = ["/shot.jpg", "/cam/1/frame.jpg", "/oneshot.jpg", "/photo.jpg", "/jpeg"]
	if _alt_endpoint_idx < alt_paths.size() - 1:
		_alt_endpoint_idx += 1
		var current_path = alt_paths[_alt_endpoint_idx]
		var base = _phone_cam_url.get_base_dir()
		if not base.begins_with("http://") and not base.begins_with("https://"):
			base = "http://" + base.trim_prefix("http:/").trim_prefix("http:")
		_phone_cam_url = base + current_path
		return

	_handle_phone_stream_error(result, response_code, custom_msg)


func _handle_phone_stream_error(result: int, response_code: int, custom_msg: String) -> void:
	_phone_stream_failed_count += 1
	var err_detail := ""
	if not custom_msg.is_empty():
		err_detail = custom_msg
	elif result == HTTPRequest.RESULT_CANT_CONNECT:
		err_detail = "Cannot connect to " + _phone_cam_url + "\nCheck phone IP & WiFi"
	elif result == HTTPRequest.RESULT_TIMEOUT:
		err_detail = "Connection timed out"
	elif response_code == 404:
		err_detail = "404 Not Found. Check stream endpoint."
	else:
		err_detail = "Stream error (Result: %d, HTTP %d)" % [result, response_code]

	var max_allowed = 10 if _stream_established else 2
	if _phone_stream_failed_count >= max_allowed:
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = null
		_update_status_overlay("📡 PHONE STREAM DISCONNECTED\n" + err_detail + "\n[ Click ⚙️ Setup to reconfigure ]", true)


func _normalize_phone_url(raw_url: String) -> String:
	var trimmed = raw_url.strip_edges()
	if trimmed.is_empty():
		return ""
	var scheme = "http://"
	if trimmed.begins_with("https://") or trimmed.begins_with("https:/"):
		scheme = "https://"
	var cleaned = trimmed
	for p in ["https://", "https:/", "https:", "http://", "http:/", "http:"]:
		if cleaned.begins_with(p):
			cleaned = cleaned.substr(p.length())
			break
	while cleaned.begins_with("/"):
		cleaned = cleaned.substr(1)
	if cleaned.is_empty():
		return ""
	if cleaned.ends_with("/video") or cleaned.ends_with("/mjpeg") or cleaned.ends_with("/mjpegfeed"):
		cleaned = (cleaned.get_base_dir() + "/cam/1/frame.jpg") if cleaned.contains(":4747") else (cleaned.get_base_dir() + "/shot.jpg")
	var final_url = scheme + cleaned
	var has_ext = final_url.ends_with(".jpg") or final_url.ends_with(".jpeg") or final_url.ends_with(".png")
	var has_path = final_url.contains("/shot.jpg") or final_url.contains("/oneshot.jpg") or final_url.contains("/cam/1/")
	if not has_ext and not has_path:
		if not final_url.ends_with("/"):
			final_url += "/"
		final_url += ("cam/1/frame.jpg" if final_url.contains(":4747") else "shot.jpg")
	return final_url


func _update_status_overlay(msg: String, is_vis: bool) -> void:
	if _overlay_status_vbox != null:
		_overlay_status_vbox.visible = is_vis
	if _feed_status_label != null and not msg.is_empty():
		_feed_status_label.text = msg


func _apply_btn_style(btn: Button, bg_color: Color) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = bg_color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)


func _open_camera_setup_dialog() -> void:
	var parent_canvas = get_tree().root
	var existing = parent_canvas.find_child("CameraSetupDialog", true, false)
	if existing != null:
		existing.queue_free()

	var popup = PanelContainer.new()
	popup.name = "CameraSetupDialog"
	popup.z_index = 200
	popup.custom_minimum_size = Vector2(480, 520)
	popup.anchor_left = 0.5
	popup.anchor_top = 0.5
	popup.anchor_right = 0.5
	popup.anchor_bottom = 0.5
	popup.offset_left = -240
	popup.offset_top = -260
	popup.offset_right = 240
	popup.offset_bottom = 260

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.16, 0.98)
	style.corner_radius_top_left = 14
	style.corner_radius_top_right = 14
	style.corner_radius_bottom_left = 14
	style.corner_radius_bottom_right = 14
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.3, 0.6, 0.8, 0.9)
	style.content_margin_left = 20
	style.content_margin_top = 20
	style.content_margin_right = 20
	style.content_margin_bottom = 20
	popup.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var title = Label.new()
	title.text = "🎯 Putting Camera Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	# Section 1: Local / Desktop Webcams
	var webcams_lbl = Label.new()
	webcams_lbl.text = "1. Local Webcams:"
	webcams_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(webcams_lbl)

	var cam_option = OptionButton.new()
	cam_option.custom_minimum_size = Vector2(0, 36)
	var feeds = CameraServer.feeds()
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	var desk_cams: Array = pose_bridge.desktop_cameras if (pose_bridge != null and "desktop_cameras" in pose_bridge) else []

	if feeds.size() > 0:
		for i in range(feeds.size()):
			cam_option.add_item("Camera %d" % i, i)
		cam_option.select(clamp(_current_camera_feed_index, 0, feeds.size() - 1))
	elif desk_cams.size() > 0:
		for i in range(desk_cams.size()):
			var c_name: String = desk_cams[i].get("name", "System Camera %d" % i)
			cam_option.add_item(c_name, i)
		cam_option.select(clamp(_current_camera_feed_index, 0, desk_cams.size() - 1))
	else:
		cam_option.add_item("No local webcams detected", 0)
		cam_option.disabled = true
	vbox.add_child(cam_option)

	var switch_cam_btn = Button.new()
	switch_cam_btn.text = "Connect Selected Local Camera"
	switch_cam_btn.custom_minimum_size = Vector2(0, 34)
	_apply_btn_style(switch_cam_btn, Color(0.2, 0.45, 0.65, 0.9))
	switch_cam_btn.pressed.connect(func():
		_use_phone_stream = false
		_current_camera_feed_index = cam_option.selected
		_update_camera_feed(true)
		popup.queue_free()
	)
	vbox.add_child(switch_cam_btn)

	# Section 2: Phone Wi-Fi Stream
	var sep = HSeparator.new()
	vbox.add_child(sep)

	var phone_lbl = Label.new()
	phone_lbl.text = "2. Phone Wi-Fi Camera Stream (IP Webcam / DroidCam):"
	phone_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(phone_lbl)

	var ip_input = LineEdit.new()
	ip_input.placeholder_text = "e.g. 192.168.1.100:8080"
	ip_input.text = _phone_cam_url
	ip_input.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(ip_input)

	var connect_phone_btn = Button.new()
	connect_phone_btn.text = "Connect Phone Wi-Fi Camera"
	connect_phone_btn.custom_minimum_size = Vector2(0, 34)
	_apply_btn_style(connect_phone_btn, Color(0.18, 0.50, 0.32, 0.9))
	connect_phone_btn.pressed.connect(func():
		var url = ip_input.text.strip_edges()
		if not url.is_empty():
			_use_phone_stream = true
			_start_phone_camera_stream(url)
			popup.queue_free()
	)
	vbox.add_child(connect_phone_btn)

	# Section 3: Rotation
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var rot_lbl = Label.new()
	rot_lbl.text = "3. Camera Orientation Rotation:"
	rot_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(rot_lbl)

	var rot_hbox = HBoxContainer.new()
	rot_hbox.add_theme_constant_override("separation", 8)
	for deg in [0, 90, 180, 270]:
		var r_btn = Button.new()
		r_btn.text = "%d°" % deg
		r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_btn.custom_minimum_size = Vector2(0, 32)
		_apply_btn_style(r_btn, Color(0.22, 0.38, 0.52) if camera_rotation_deg == deg else Color(0.18, 0.22, 0.28))
		r_btn.pressed.connect(func(d=deg):
			camera_rotation_deg = d
			_update_rotate_button_text()
			if _state_machine != null:
				_state_machine.reset()
			popup.queue_free()
		)
		rot_hbox.add_child(r_btn)
	vbox.add_child(rot_hbox)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 34)
	_apply_btn_style(close_btn, Color(0.35, 0.35, 0.35, 0.8))
	close_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close_btn)

	popup.add_child(vbox)
	parent_canvas.add_child(popup)
