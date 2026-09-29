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
var _align_slider: HSlider = null

enum PickerMode { NONE, PICK_BALL, PICK_BACKGROUND }

var _picker_mode: PickerMode = PickerMode.NONE
var _color_profile: PuttingColorProfile = null
var _last_feed_image: Image = null

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

var putting_min_speed_mph: float:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			if GlobalSettings.range_settings != null and GlobalSettings.range_settings.settings.has("putting_min_speed_mph"):
				return float(GlobalSettings.range_settings.putting_min_speed_mph.value)
		return 1.5
	set(val):
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.putting_min_speed_mph.set_value(val)
			GlobalSettings.save_settings()
		if _state_machine != null:
			_state_machine.min_putt_speed_mph = val

var putting_max_speed_mph: float:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			if GlobalSettings.range_settings != null and GlobalSettings.range_settings.settings.has("putting_max_speed_mph"):
				return float(GlobalSettings.range_settings.putting_max_speed_mph.value)
		return 20.0
	set(val):
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.putting_max_speed_mph.set_value(val)
			GlobalSettings.save_settings()
		if _state_machine != null:
			_state_machine.max_putt_speed_mph = val

var putting_mishit_filter_enabled: bool:
	get:
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			if GlobalSettings.range_settings != null and GlobalSettings.range_settings.settings.has("putting_mishit_filter_enabled"):
				return bool(GlobalSettings.range_settings.putting_mishit_filter_enabled.value)
		return true
	set(val):
		if is_inside_tree() and has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.putting_mishit_filter_enabled.set_value(val)
			GlobalSettings.save_settings()
		if _state_machine != null:
			_state_machine.mishit_filter_enabled = val


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_profile = PuttingColorProfile.new()
	_color_profile.load_from_settings()

	_build_ui()

	if _state_machine != null and _state_machine.detector != null:
		_state_machine.detector.color_profile = _color_profile
	_sync_overlay_color_swatches()

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
	_panel.position = Vector2(20, 20)
	_panel.custom_minimum_size = Vector2(320, 325)
	_panel.size = Vector2(320, 325)
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
	main_vbox.add_theme_constant_override("separation", 4)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(main_vbox)

	# 2. Header Bar
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 4)

	var title = Label.new()
	title.text = "🎯 PUTTING CAM"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var is_mob: bool = MobilePerformance.is_mobile()

	# Setup Button
	var setup_btn = Button.new()
	setup_btn.text = "⚙️"
	setup_btn.tooltip_text = "Camera Setup (Connect Phone WiFi Stream or select Webcam)"
	setup_btn.custom_minimum_size = Vector2(44, 44) if is_mob else Vector2(36, 32)
	_apply_btn_style(setup_btn, Color(0.2, 0.45, 0.65, 0.9))
	setup_btn.pressed.connect(_open_camera_setup_dialog)
	header.add_child(setup_btn)

	# Color Picker / Profile Button
	var color_pick_btn = Button.new()
	color_pick_btn.name = "ColorPickButton"
	color_pick_btn.text = "🎨"
	color_pick_btn.tooltip_text = "Pick Ball or Mat/Background Color from Video Feed"
	color_pick_btn.custom_minimum_size = Vector2(44, 44) if is_mob else Vector2(36, 32)
	_apply_btn_style(color_pick_btn, Color(0.48, 0.28, 0.58, 0.9))
	color_pick_btn.pressed.connect(_open_color_picker_menu)
	header.add_child(color_pick_btn)

	# Rotate 90° Button
	_camera_rotate_btn = Button.new()
	_camera_rotate_btn.name = "RotateButton"
	_update_rotate_button_text()
	_camera_rotate_btn.custom_minimum_size = Vector2(68, 44) if is_mob else Vector2(56, 32)
	_camera_rotate_btn.add_theme_font_size_override("font_size", 14 if is_mob else 12)
	_apply_btn_style(_camera_rotate_btn, Color(0.25, 0.50, 0.40, 0.9))
	_camera_rotate_btn.pressed.connect(rotate_camera_90)
	header.add_child(_camera_rotate_btn)

	# Flip/Source Button
	_camera_flip_btn = Button.new()
	_camera_flip_btn.text = "🔄"
	_camera_flip_btn.tooltip_text = "Cycle through local camera inputs"
	_camera_flip_btn.custom_minimum_size = Vector2(44, 44) if is_mob else Vector2(36, 32)
	_apply_btn_style(_camera_flip_btn, Color(0.2, 0.4, 0.6, 0.9))
	_camera_flip_btn.pressed.connect(_on_flip_camera_pressed)
	header.add_child(_camera_flip_btn)

	# Minimize Button
	_camera_minimize_btn = Button.new()
	_camera_minimize_btn.text = "🗕"
	_camera_minimize_btn.tooltip_text = "Minimize Putting Cam (Keeps tracking in background)"
	_camera_minimize_btn.custom_minimum_size = Vector2(44, 44) if is_mob else Vector2(32, 32)
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
	_camera_feed_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	_camera_feed_rect.gui_input.connect(_on_feed_gui_input)
	feed_container.add_child(_camera_feed_rect)

	# 4. Putting Camera Overlay
	_overlay = PuttingCameraOverlay.new()
	_overlay.name = "PuttingCameraOverlay"
	_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_overlay.gui_input.connect(_on_overlay_gui_input)
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

	# Track Line Alignment Controls (avoids camera stand obstruction)
	var align_container = PanelContainer.new()
	align_container.name = "TrackLineAlignContainer"
	var align_style = StyleBoxFlat.new()
	align_style.bg_color = Color(0.06, 0.08, 0.11, 0.9)
	align_style.corner_radius_bottom_left = 8
	align_style.corner_radius_bottom_right = 8
	align_style.corner_radius_top_left = 8
	align_style.corner_radius_top_right = 8
	align_style.content_margin_left = 6
	align_style.content_margin_top = 2
	align_style.content_margin_right = 6
	align_style.content_margin_bottom = 2
	align_container.add_theme_stylebox_override("panel", align_style)

	var align_hbox = HBoxContainer.new()
	align_hbox.add_theme_constant_override("separation", 6 if is_mob else 4)
	align_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var line_lbl = Label.new()
	line_lbl.text = "🎯 Line:"
	line_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 11)
	line_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	align_hbox.add_child(line_lbl)

	var left_btn = Button.new()
	left_btn.text = "◀"
	left_btn.tooltip_text = "Move Ball Circle & Track Line Left"
	left_btn.custom_minimum_size = Vector2(42, 44) if is_mob else Vector2(30, 28)
	left_btn.add_theme_font_size_override("font_size", 18 if is_mob else 14)
	_apply_btn_style(left_btn, Color(0.2, 0.35, 0.45, 0.85))
	left_btn.pressed.connect(func():
		if _overlay != null:
			_overlay.set_circle_x(_overlay.circle_center.x - 0.03, true)
	)
	align_hbox.add_child(left_btn)

	_align_slider = HSlider.new()
	_align_slider.name = "TrackLineSlider"
	_align_slider.min_value = 0.15
	_align_slider.max_value = 0.85
	_align_slider.step = 0.01
	_align_slider.value = _overlay.circle_center.x
	_align_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_align_slider.custom_minimum_size = Vector2(70, 48 if is_mob else 36)
	_align_slider.tooltip_text = "Move Track Line left or right (avoids camera stand obstruction)"
	ThemeManager.apply_slider_style(_align_slider, 48 if is_mob else 36, 70)
	_align_slider.value_changed.connect(func(val: float):
		if _overlay != null:
			_overlay.set_circle_x(val, true)
	)
	align_hbox.add_child(_align_slider)

	var right_btn = Button.new()
	right_btn.text = "▶"
	right_btn.tooltip_text = "Move Ball Circle & Track Line Right"
	right_btn.custom_minimum_size = Vector2(42, 44) if is_mob else Vector2(30, 28)
	right_btn.add_theme_font_size_override("font_size", 18 if is_mob else 14)
	_apply_btn_style(right_btn, Color(0.2, 0.35, 0.45, 0.85))
	right_btn.pressed.connect(func():
		if _overlay != null:
			_overlay.set_circle_x(_overlay.circle_center.x + 0.03, true)
	)
	align_hbox.add_child(right_btn)

	var center_btn = Button.new()
	center_btn.text = "Center"
	center_btn.tooltip_text = "Reset Track Line to Center (50%)"
	center_btn.custom_minimum_size = Vector2(60, 44) if is_mob else Vector2(50, 28)
	center_btn.add_theme_font_size_override("font_size", 13 if is_mob else 11)
	_apply_btn_style(center_btn, Color(0.25, 0.4, 0.35, 0.85))
	center_btn.pressed.connect(func():
		if _overlay != null:
			_overlay.reset_circle_x()
	)
	align_hbox.add_child(center_btn)

	align_container.add_child(align_hbox)
	main_vbox.add_child(align_container)

	_overlay.circle_position_changed.connect(func(new_pos: Vector2):
		if _align_slider != null:
			_align_slider.set_value_no_signal(new_pos.x)
	)

	# 6. State Machine
	_state_machine = PuttingCameraStateMachine.new()
	_state_machine.name = "PuttingCameraStateMachine"
	_state_machine.overlay = _overlay
	add_child(_state_machine)
	_state_machine.putt_detected.connect(_on_putt_detected)
	_state_machine.putt_rejected.connect(_on_putt_rejected)

	# 7. Floating Restore Pill (when minimized)
	_camera_restore_pill = Button.new()
	_camera_restore_pill.name = "CameraRestorePill"
	_camera_restore_pill.text = "🎯 Putting Cam [REC] 🗖"
	_camera_restore_pill.tooltip_text = "Putting Cam is tracking in background. Click to expand preview."
	_camera_restore_pill.visible = false
	_camera_restore_pill.position = Vector2(20, 20)
	_camera_restore_pill.custom_minimum_size = Vector2(210, 48) if is_mob else Vector2(190, 44)
	_camera_restore_pill.add_theme_font_size_override("font_size", 15 if is_mob else 13)
	_apply_btn_style(_camera_restore_pill, Color(0.18, 0.40, 0.30, 0.9))
	_camera_restore_pill.pressed.connect(restore)
	add_child(_camera_restore_pill)


func set_panel_position(pos: Vector2) -> void:
	if _panel != null:
		_panel.position = pos
	if _camera_restore_pill != null:
		_camera_restore_pill.position = pos


func get_panel_position() -> Vector2:
	return _panel.position if _panel != null else Vector2.ZERO


func set_panel_size(sz: Vector2) -> void:
	if _panel != null:
		_panel.custom_minimum_size = sz
		_panel.size = sz


func get_panel_size() -> Vector2:
	return _panel.size if _panel != null else Vector2.ZERO


func _open_color_picker_menu() -> void:
	var menu = PopupMenu.new()
	menu.name = "ColorPickerMenu"
	menu.add_item("🏐 Pick Ball Color (Click Ball on Feed)", 0)
	menu.add_item("🟩 Pick Mat/Background Color (Click Mat)", 1)
	menu.add_separator()
	menu.add_item("🔄 Reset to Auto-Detect (Default)", 2)
	menu.id_pressed.connect(func(id: int):
		match id:
			0:
				_picker_mode = PickerMode.PICK_BALL
				if _overlay != null:
					_overlay.picker_active = true
				_show_picker_instructions("👉 CLICK ON THE BALL in the video feed below")
			1:
				_picker_mode = PickerMode.PICK_BACKGROUND
				if _overlay != null:
					_overlay.picker_active = true
				_show_picker_instructions("👉 CLICK ON THE MAT/BACKGROUND in the video feed below")
			2:
				if _color_profile != null:
					_color_profile.ball_configured = false
					_color_profile.bg_configured = false
					_color_profile.save_to_settings()
				_update_color_profile()
				_show_picker_instructions("Reset to auto-detect ball mode")
		menu.queue_free()
	)
	add_child(menu)
	ThemeManager.style_popup_menu(menu, 18 if MobilePerformance.is_mobile() else 15)
	menu.popup_centered()


func _show_picker_instructions(msg: String) -> void:
	_update_status_overlay(msg, true)
	get_tree().create_timer(3.5).timeout.connect(func():
		if _picker_mode == PickerMode.NONE:
			_update_status_overlay("", false)
	)


func _on_overlay_gui_input(event: InputEvent) -> void:
	if _picker_mode != PickerMode.NONE:
		_on_feed_gui_input(event)


func _on_feed_gui_input(event: InputEvent) -> void:
	if _picker_mode == PickerMode.NONE:
		return

	if event is InputEventMouseMotion and _overlay != null:
		_overlay.picker_cursor_pos = event.position
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if _last_feed_image == null or _camera_feed_rect == null:
		_picker_mode = PickerMode.NONE
		if _overlay != null:
			_overlay.picker_active = false
		return

	var feed_sz = _camera_feed_rect.size
	var img_w = _last_feed_image.get_width()
	var img_h = _last_feed_image.get_height()
	if feed_sz.x <= 1.0 or feed_sz.y <= 1.0 or img_w < 2 or img_h < 2:
		return

	# Account for STRETCH_KEEP_ASPECT_COVERED
	var scale_x = float(img_w) / feed_sz.x
	var scale_y = float(img_h) / feed_sz.y
	var scale_factor = minf(scale_x, scale_y) # covered scale

	var visible_w = feed_sz.x * scale_factor
	var visible_h = feed_sz.y * scale_factor
	var offset_x = (float(img_w) - visible_w) * 0.5
	var offset_y = (float(img_h) - visible_h) * 0.5

	var click_pos = event.position
	var img_x = int(offset_x + click_pos.x * scale_factor)
	var img_y = int(offset_y + click_pos.y * scale_factor)

	img_x = clampi(img_x, 0, img_w - 1)
	img_y = clampi(img_y, 0, img_h - 1)

	# Sample 7x7 patch around click point
	var h_list: Array[float] = []
	var s_list: Array[float] = []
	var v_list: Array[float] = []

	var patch_r: int = 3
	for py in range(maxi(0, img_y - patch_r), mini(img_h, img_y + patch_r + 1)):
		for px in range(maxi(0, img_x - patch_r), mini(img_w, img_x + patch_r + 1)):
			var c: Color = _last_feed_image.get_pixel(px, py)
			var hsv: Vector3 = PuttingBallDetector._rgb_to_hsv(c)
			h_list.append(hsv.x)
			s_list.append(hsv.y)
			v_list.append(hsv.z)

	if h_list.size() > 0 and _color_profile != null:
		h_list.sort()
		s_list.sort()
		v_list.sort()
		var mid: int = h_list.size() / 2
		var sampled_hsv = Vector3(h_list[mid], s_list[mid], v_list[mid])

		match _picker_mode:
			PickerMode.PICK_BALL:
				_color_profile.ball_hsv = sampled_hsv
				_color_profile.ball_configured = true
				_show_picker_instructions("✅ Ball Color Set (H: %.0f°, S: %.2f, V: %.2f)" % [sampled_hsv.x, sampled_hsv.y, sampled_hsv.z])
			PickerMode.PICK_BACKGROUND:
				_color_profile.bg_hsv = sampled_hsv
				_color_profile.bg_configured = true
				_show_picker_instructions("✅ Mat Color Set (H: %.0f°, S: %.2f, V: %.2f)" % [sampled_hsv.x, sampled_hsv.y, sampled_hsv.z])

		_color_profile.save_to_settings()
		_update_color_profile()

	_picker_mode = PickerMode.NONE
	if _overlay != null:
		_overlay.picker_active = false


func _update_color_profile() -> void:
	if _color_profile != null:
		_color_profile.load_from_settings()
		if _state_machine != null and _state_machine.detector != null:
			_state_machine.detector.color_profile = _color_profile
			_state_machine.reset()
	_sync_overlay_color_swatches()


func _sync_overlay_color_swatches() -> void:
	if _overlay == null or _color_profile == null:
		return

	_overlay.ball_color_configured = _color_profile.ball_configured
	if _color_profile.ball_configured:
		_overlay.ball_color_swatch = Color.from_hsv(_color_profile.ball_hsv.x / 360.0, _color_profile.ball_hsv.y, _color_profile.ball_hsv.z)

	_overlay.bg_color_configured = _color_profile.bg_configured
	if _color_profile.bg_configured:
		_overlay.bg_color_swatch = Color.from_hsv(_color_profile.bg_hsv.x / 360.0, _color_profile.bg_hsv.y, _color_profile.bg_hsv.z)


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


func _on_putt_rejected(reason: String, speed_mph: float) -> void:
	print("[PuttingCamWidget] Putt rejected (%s): %.1f mph — not registered as hit" % [reason, speed_mph])


func _stop_local_camera_stream() -> void:
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else (get_node_or_null("/root/PoseDetectionBridge") if is_inside_tree() else null)
	if pose_bridge != null:
		if pose_bridge.has_method("stop_desktop_camera"):
			pose_bridge.stop_desktop_camera()
		if pose_bridge.has_method("stop_android_camera"):
			pose_bridge.stop_android_camera()
	if CameraServer.is_monitoring_feeds():
		for feed in CameraServer.feeds():
			if feed != null:
				feed.feed_is_active = false
		CameraServer.set_monitoring_feeds(false)
	else:
		for feed in CameraServer.feeds():
			if feed != null:
				feed.feed_is_active = false


func _stop_phone_camera_stream() -> void:
	_is_requesting_frame = false
	if _http_req != null and _http_req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http_req.cancel_request()


func _update_camera_feed(active: bool) -> void:
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else (get_node_or_null("/root/PoseDetectionBridge") if is_inside_tree() else null)

	if not active:
		_stop_local_camera_stream()
		_stop_phone_camera_stream()
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = null
		_update_status_overlay("PUTTING CAMERA FEED\n[ Click ⚙️ Setup to connect ]", true)
		return

	# If using phone/WiFi stream, stop all local/device cameras immediately
	if _use_phone_stream:
		_stop_local_camera_stream()
		if not _phone_cam_url.is_empty():
			_start_phone_camera_stream(_phone_cam_url)
		else:
			if _camera_feed_rect != null:
				_camera_feed_rect.texture = null
			_update_status_overlay("NO PHONE STREAM URL\n[ Click ⚙️ Setup for Phone Stream ]", true)
		return

	# Stop any phone stream polling before starting local camera
	_stop_phone_camera_stream()

	# If desktop or Android camera is already actively streaming, maintain it
	if pose_bridge != null and pose_bridge.has_method("is_desktop_camera_active") and pose_bridge.is_desktop_camera_active():
		_update_status_overlay("", false)
		return

	var is_android: bool = OS.has_feature("android") or OS.get_name() == "Android"

	# Request permission on mobile OS if needed
	if is_android or OS.has_feature("ios"):
		var permissions: Variant = OS.call("get_granted_permissions") if OS.has_method("get_granted_permissions") else []
		var has_cam_perm: bool = false
		if permissions is PackedStringArray or permissions is Array:
			has_cam_perm = "android.permission.CAMERA" in permissions
		if not has_cam_perm:
			if OS.has_method("request_permission"):
				OS.call("request_permission", "android.permission.CAMERA")
			elif OS.has_method("request_permissions"):
				OS.call("request_permissions")
			_update_status_overlay("CAMERA PERMISSION REQUIRED\n[ Please grant camera permission when prompted ]", true)
			if _camera_feed_rect != null:
				_camera_feed_rect.texture = null
			get_tree().create_timer(1.5).timeout.connect(func():
				if _is_active:
					_update_camera_feed(true)
			)
			return

	if _use_phone_stream and not _phone_cam_url.is_empty():
		_start_phone_camera_stream(_phone_cam_url)
		return

	if is_android:
		# On Android, route through PoseDetectionBridge which uses MediaPipe Camera2
		if CameraServer.is_monitoring_feeds():
			for f in CameraServer.feeds():
				if f != null:
					f.feed_is_active = false
			CameraServer.set_monitoring_feeds(false)
		if pose_bridge != null and pose_bridge.has_method("select_desktop_camera"):
			pose_bridge.select_desktop_camera(_current_camera_feed_index)
			_update_status_overlay("", false)
		return

	CameraServer.set_monitoring_feeds(true)

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
	if _use_phone_stream:
		_stop_local_camera_stream()
		return
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
	_last_feed_image = rotated_img

	if _camera_feed_rect != null:
		_camera_feed_rect.texture = ImageTexture.create_from_image(rotated_img)
	_update_status_overlay("", false)

	if _state_machine != null:
		_state_machine.process_frame(rotated_img)


func _on_flip_camera_pressed() -> void:
	if _use_phone_stream:
		_stop_phone_camera_stream()
		_use_phone_stream = false

	var is_android: bool = OS.has_feature("android") or OS.get_name() == "Android"
	var feeds = CameraServer.feeds()
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	var desk_cams: Array = pose_bridge.desktop_cameras if (pose_bridge != null and "desktop_cameras" in pose_bridge) else []
	var total_count = max(feeds.size(), desk_cams.size())
	if is_android and total_count < 2:
		total_count = 2

	if total_count > 1:
		_current_camera_feed_index = (_current_camera_feed_index + 1) % total_count
		_update_camera_feed(true)
	elif total_count == 1:
		_current_camera_feed_index = 0
		_update_camera_feed(true)
	else:
		_open_camera_setup_dialog()


func _start_phone_camera_stream(url_str: String) -> void:
	_stop_local_camera_stream()
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
			_last_feed_image = img

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
	var pressed = style.duplicate()
	pressed.bg_color = bg_color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", pressed)
	var focus = hover.duplicate()
	focus.border_color = Color(0.35, 0.82, 1.0, 0.9)
	focus.border_width_left = 2
	focus.border_width_right = 2
	focus.border_width_top = 2
	focus.border_width_bottom = 2
	btn.add_theme_stylebox_override("focus", focus)


func _open_camera_setup_dialog() -> void:
	var tree = get_tree() if is_inside_tree() else null
	var parent_canvas: Node = tree.root if tree != null else (get_parent() if get_parent() != null else self)
	var existing = parent_canvas.find_child("CameraSetupDialog", true, false)
	if existing != null:
		existing.queue_free()

	var is_mob: bool = MobilePerformance.is_mobile()
	var vp_size = parent_canvas.get_viewport().get_visible_rect().size if parent_canvas.get_viewport() != null else Vector2(1728, 972)
	var target_w = minf(540.0, vp_size.x * 0.95)
	var target_h = minf(760.0, vp_size.y * 0.94)

	var popup = PanelContainer.new()
	popup.name = "CameraSetupDialog"
	popup.tree_exited.connect(func():
		if _use_phone_stream:
			_stop_local_camera_stream()
	)
	popup.z_index = 200
	popup.custom_minimum_size = Vector2(target_w, target_h)
	popup.anchor_left = 0.5
	popup.anchor_top = 0.5
	popup.anchor_right = 0.5
	popup.anchor_bottom = 0.5
	popup.offset_left = -target_w * 0.5
	popup.offset_top = -target_h * 0.5
	popup.offset_right = target_w * 0.5
	popup.offset_bottom = target_h * 0.5

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

	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 10)
	outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var title = Label.new()
	title.text = "🎯 Putting Camera Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color.WHITE)
	outer_vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeManager.apply_scroll_container_style(scroll)
	outer_vbox.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	# Section 1: Local / Desktop Webcams
	var webcams_lbl = Label.new()
	webcams_lbl.text = "1. Local Webcams:"
	webcams_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	vbox.add_child(webcams_lbl)

	var cam_option = OptionButton.new()
	cam_option.custom_minimum_size = Vector2(0, 46 if is_mob else 36)
	cam_option.add_theme_font_size_override("font_size", 15 if is_mob else 13)
	var is_android: bool = OS.has_feature("android") or OS.get_name() == "Android"
	var feeds = CameraServer.feeds()
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	if pose_bridge != null and pose_bridge.has_method("fetch_desktop_cameras"):
		pose_bridge.fetch_desktop_cameras()
	var desk_cams: Array = pose_bridge.desktop_cameras if (pose_bridge != null and "desktop_cameras" in pose_bridge) else []
	var total_count = max(feeds.size(), desk_cams.size())
	if is_android and total_count < 2:
		total_count = 2

	if is_android:
		cam_option.disabled = false
		cam_option.add_item("Camera 0 (Back Camera)", 0)
		cam_option.add_item("Camera 1 (Front Camera)", 1)
		for i in range(2, total_count):
			cam_option.add_item("Camera %d (Device)" % i, i)
		cam_option.select(clamp(_current_camera_feed_index, 0, cam_option.item_count - 1))
	elif feeds.size() > 0:
		for i in range(feeds.size()):
			var feed = feeds[i]
			var feed_name = "Camera %d" % i
			if feed != null:
				var pos_name = ""
				match feed.get_position():
					CameraFeed.FEED_BACK: pos_name = " (Back)"
					CameraFeed.FEED_FRONT: pos_name = " (Front)"
					_: pos_name = ""
				if not feed.get_name().is_empty():
					feed_name = feed.get_name() + pos_name
				else:
					feed_name = "Camera %d%s" % [i, pos_name]
			cam_option.add_item(feed_name, i)
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

	# Connect item_selected so tapping in dropdown switches camera immediately!
	cam_option.item_selected.connect(func(idx: int):
		_stop_phone_camera_stream()
		_use_phone_stream = false
		_current_camera_feed_index = idx
		_update_camera_feed(true)
	)

	var switch_cam_btn = Button.new()
	switch_cam_btn.text = "Connect Selected Local Camera"
	switch_cam_btn.custom_minimum_size = Vector2(0, 46 if is_mob else 36)
	switch_cam_btn.add_theme_font_size_override("font_size", 15 if is_mob else 13)
	_apply_btn_style(switch_cam_btn, Color(0.2, 0.45, 0.65, 0.9))
	switch_cam_btn.pressed.connect(func():
		_stop_phone_camera_stream()
		_use_phone_stream = false
		var sel_idx = cam_option.get_selected_id() if is_instance_valid(cam_option) else _current_camera_feed_index
		if sel_idx < 0:
			sel_idx = 0
		_current_camera_feed_index = sel_idx
		_update_camera_feed(true)
		popup.queue_free()
	)
	vbox.add_child(switch_cam_btn)

	# Section 2: Phone Wi-Fi Stream
	var sep = HSeparator.new()
	vbox.add_child(sep)

	var phone_lbl = Label.new()
	phone_lbl.text = "2. Phone Wi-Fi Camera Stream (IP Webcam / DroidCam):"
	phone_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	vbox.add_child(phone_lbl)

	var ip_input = LineEdit.new()
	ip_input.name = "PuttingCameraIpInput"
	ip_input.placeholder_text = "e.g. 192.168.1.100:8080"
	ip_input.text = _phone_cam_url
	ip_input.custom_minimum_size = Vector2(0, 48)
	ip_input.add_theme_font_size_override("font_size", 16)
	ThemeManager.apply_input_style(ip_input)
	ip_input.gui_input.connect(func(ev: InputEvent):
		if has_node("/root/VirtualKeyboardManager"):
			var vkm = get_node("/root/VirtualKeyboardManager")
			if vkm.is_controller_mode_active():
				if (ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_A) or ev.is_action_pressed("ui_accept"):
					vkm.open_for(ip_input, true)
					get_viewport().set_input_as_handled()
	)
	var connect_phone_btn = Button.new()

	ip_input.text_submitted.connect(func(_t):
		if is_instance_valid(connect_phone_btn):
			connect_phone_btn.grab_focus()
	)
	vbox.add_child(ip_input)

	connect_phone_btn.text = "Connect Phone Wi-Fi Camera"
	connect_phone_btn.custom_minimum_size = Vector2(0, 46 if is_mob else 36)
	connect_phone_btn.add_theme_font_size_override("font_size", 15 if is_mob else 13)
	_apply_btn_style(connect_phone_btn, Color(0.18, 0.50, 0.32, 0.9))
	connect_phone_btn.pressed.connect(func():
		var url = ip_input.text.strip_edges()
		if not url.is_empty():
			popup.queue_free()
			_stop_local_camera_stream()
			_use_phone_stream = true
			_start_phone_camera_stream(url)
	)
	vbox.add_child(connect_phone_btn)

	# Section 3: Rotation
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var rot_lbl = Label.new()
	rot_lbl.text = "3. Camera Orientation Rotation:"
	rot_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	vbox.add_child(rot_lbl)

	var rot_hbox = HBoxContainer.new()
	rot_hbox.add_theme_constant_override("separation", 8)
	for deg in [0, 90, 180, 270]:
		var r_btn = Button.new()
		r_btn.text = "%d°" % deg
		r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_btn.custom_minimum_size = Vector2(0, 44 if is_mob else 34)
		r_btn.add_theme_font_size_override("font_size", 15 if is_mob else 13)
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

	# Section 4: Ball & Background Color
	var sep3 = HSeparator.new()
	vbox.add_child(sep3)

	var color_lbl = Label.new()
	color_lbl.text = "4. Ball & Background Color Detection:"
	color_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	vbox.add_child(color_lbl)

	var color_info = Label.new()
	if _color_profile != null and _color_profile.ball_configured:
		color_info.text = "Ball: H=%.0f° S=%.0f%% V=%.0f%%" % [
			_color_profile.ball_hsv.x,
			_color_profile.ball_hsv.y * 100.0,
			_color_profile.ball_hsv.z * 100.0
		]
	else:
		color_info.text = "Ball: Auto-detect (white ball default)"
	color_info.add_theme_font_size_override("font_size", 13 if is_mob else 12)
	color_info.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	vbox.add_child(color_info)

	var pick_ball_btn = Button.new()
	pick_ball_btn.text = "🏐 Click to Pick Ball Color from Feed"
	pick_ball_btn.custom_minimum_size = Vector2(0, 46 if is_mob else 36)
	pick_ball_btn.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	_apply_btn_style(pick_ball_btn, Color(0.45, 0.28, 0.55, 0.9))
	pick_ball_btn.pressed.connect(func():
		_picker_mode = PickerMode.PICK_BALL
		if _overlay != null:
			_overlay.picker_active = true
		_show_picker_instructions("👉 CLICK ON THE BALL in the video feed below")
		popup.queue_free()
	)
	vbox.add_child(pick_ball_btn)

	var pick_bg_btn = Button.new()
	pick_bg_btn.text = "🟩 Click to Pick Mat/Background Color"
	pick_bg_btn.custom_minimum_size = Vector2(0, 46 if is_mob else 36)
	pick_bg_btn.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	_apply_btn_style(pick_bg_btn, Color(0.20, 0.45, 0.30, 0.9))
	pick_bg_btn.pressed.connect(func():
		_picker_mode = PickerMode.PICK_BACKGROUND
		if _overlay != null:
			_overlay.picker_active = true
		_show_picker_instructions("👉 CLICK ON THE MAT/BACKGROUND in the video feed below")
		popup.queue_free()
	)
	vbox.add_child(pick_bg_btn)

	var reset_color_btn = Button.new()
	reset_color_btn.text = "🔄 Reset to Auto-Detect Colors"
	reset_color_btn.custom_minimum_size = Vector2(0, 44 if is_mob else 32)
	reset_color_btn.add_theme_font_size_override("font_size", 14 if is_mob else 12)
	_apply_btn_style(reset_color_btn, Color(0.30, 0.35, 0.40, 0.8))
	reset_color_btn.pressed.connect(func():
		if _color_profile != null:
			_color_profile.ball_configured = false
			_color_profile.bg_configured = false
			_color_profile.save_to_settings()
		_update_color_profile()
		popup.queue_free()
	)
	vbox.add_child(reset_color_btn)

	# Tolerance Slider
	var tol_card = VBoxContainer.new()
	tol_card.add_theme_constant_override("separation", 4)

	var tol_header = HBoxContainer.new()
	var tol_label = Label.new()
	tol_label.text = "Color Tolerance:"
	tol_label.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	tol_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	tol_header.add_child(tol_label)

	var tol_spacer = Control.new()
	tol_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tol_header.add_child(tol_spacer)

	var tol_val_lbl = Label.new()
	tol_val_lbl.text = "%.0f°" % (_color_profile.ball_hue_tolerance if _color_profile != null else 30.0)
	tol_val_lbl.add_theme_font_size_override("font_size", 15 if is_mob else 13)
	tol_val_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_ACCENT)
	tol_header.add_child(tol_val_lbl)
	tol_card.add_child(tol_header)

	var tol_slider = HSlider.new()
	tol_slider.min_value = 10.0
	tol_slider.max_value = 90.0
	tol_slider.step = 5.0
	tol_slider.value = _color_profile.ball_hue_tolerance if _color_profile != null else 30.0
	tol_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tol_slider.custom_minimum_size = Vector2(0, 48 if is_mob else 38)
	ThemeManager.apply_slider_style(tol_slider, 48 if is_mob else 38)
	tol_slider.value_changed.connect(func(v: float):
		tol_val_lbl.text = "%.0f°" % v
		if _color_profile != null:
			_color_profile.ball_hue_tolerance = v
			_color_profile.save_to_settings()
			_update_color_profile()
	)
	tol_card.add_child(tol_slider)
	vbox.add_child(tol_card)

	# Section 5: Speed Validation & Mishit Filtering
	var sep4 = HSeparator.new()
	vbox.add_child(sep4)

	var speed_filter_lbl = Label.new()
	speed_filter_lbl.text = "5. Speed Validation & Mishit Filtering:"
	speed_filter_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	vbox.add_child(speed_filter_lbl)

	var mishit_check = CheckButton.new()
	mishit_check.text = "Auto-Reject Mishits & Tracking Glitches"
	mishit_check.button_pressed = putting_mishit_filter_enabled
	mishit_check.custom_minimum_size = Vector2(0, 44 if is_mob else 36)
	mishit_check.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	mishit_check.toggled.connect(func(val: bool):
		putting_mishit_filter_enabled = val
	)
	vbox.add_child(mishit_check)

	# Min Speed Slider (Mishits)
	var min_spd_card = VBoxContainer.new()
	min_spd_card.add_theme_constant_override("separation", 4)

	var min_spd_hdr = HBoxContainer.new()
	var min_spd_lbl = Label.new()
	min_spd_lbl.text = "Min Speed (Mishit Cutoff):"
	min_spd_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	min_spd_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	min_spd_hdr.add_child(min_spd_lbl)

	var min_spd_spacer = Control.new()
	min_spd_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	min_spd_hdr.add_child(min_spd_spacer)

	var min_spd_val_lbl = Label.new()
	min_spd_val_lbl.text = "%.1f mph" % putting_min_speed_mph
	min_spd_val_lbl.add_theme_font_size_override("font_size", 15 if is_mob else 13)
	min_spd_val_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_ACCENT)
	min_spd_hdr.add_child(min_spd_val_lbl)
	min_spd_card.add_child(min_spd_hdr)

	var min_spd_slider = HSlider.new()
	min_spd_slider.min_value = 0.5
	min_spd_slider.max_value = 4.0
	min_spd_slider.step = 0.1
	min_spd_slider.value = putting_min_speed_mph
	min_spd_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	min_spd_slider.custom_minimum_size = Vector2(0, 48 if is_mob else 38)
	ThemeManager.apply_slider_style(min_spd_slider, 48 if is_mob else 38)
	min_spd_slider.value_changed.connect(func(v: float):
		min_spd_val_lbl.text = "%.1f mph" % v
		putting_min_speed_mph = v
	)
	min_spd_card.add_child(min_spd_slider)

	var min_spd_hint = Label.new()
	min_spd_hint.text = "Accidental taps and practice waggles under this speed are ignored."
	min_spd_hint.add_theme_font_size_override("font_size", 12 if is_mob else 11)
	min_spd_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
	min_spd_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	min_spd_card.add_child(min_spd_hint)
	vbox.add_child(min_spd_card)

	# Max Speed Slider (Tracking Glitches)
	var max_spd_card = VBoxContainer.new()
	max_spd_card.add_theme_constant_override("separation", 4)

	var max_spd_hdr = HBoxContainer.new()
	var max_spd_lbl = Label.new()
	max_spd_lbl.text = "Max Speed (Glitch Cutoff):"
	max_spd_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 13)
	max_spd_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	max_spd_hdr.add_child(max_spd_lbl)

	var max_spd_spacer = Control.new()
	max_spd_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_spd_hdr.add_child(max_spd_spacer)

	var max_spd_val_lbl = Label.new()
	max_spd_val_lbl.text = "%.1f mph" % putting_max_speed_mph
	max_spd_val_lbl.add_theme_font_size_override("font_size", 15 if is_mob else 13)
	max_spd_val_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_ACCENT)
	max_spd_hdr.add_child(max_spd_val_lbl)
	max_spd_card.add_child(max_spd_hdr)

	var max_spd_slider = HSlider.new()
	max_spd_slider.min_value = 10.0
	max_spd_slider.max_value = 30.0
	max_spd_slider.step = 0.5
	max_spd_slider.value = putting_max_speed_mph
	max_spd_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_spd_slider.custom_minimum_size = Vector2(0, 48 if is_mob else 38)
	ThemeManager.apply_slider_style(max_spd_slider, 48 if is_mob else 38)
	max_spd_slider.value_changed.connect(func(v: float):
		max_spd_val_lbl.text = "%.1f mph" % v
		putting_max_speed_mph = v
	)
	max_spd_card.add_child(max_spd_slider)

	var max_spd_hint = Label.new()
	max_spd_hint.text = "Speeds exceeding this are ignored as tracking glitches/anomalies."
	max_spd_hint.add_theme_font_size_override("font_size", 12 if is_mob else 11)
	max_spd_hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.75))
	max_spd_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	max_spd_card.add_child(max_spd_hint)
	vbox.add_child(max_spd_card)

	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 48 if is_mob else 38)
	close_btn.add_theme_font_size_override("font_size", 16 if is_mob else 14)
	_apply_btn_style(close_btn, Color(0.35, 0.35, 0.35, 0.8))
	close_btn.pressed.connect(func(): popup.queue_free())
	outer_vbox.add_child(close_btn)

	popup.add_child(outer_vbox)
	parent_canvas.add_child(popup)

	# Focus neighbors & controller auto-focus
	if popup.is_inside_tree():
		if is_instance_valid(switch_cam_btn) and is_instance_valid(ip_input):
			switch_cam_btn.focus_neighbor_bottom = ip_input.get_path()
			ip_input.focus_neighbor_top = switch_cam_btn.get_path()
		if is_instance_valid(ip_input) and is_instance_valid(connect_phone_btn):
			ip_input.focus_neighbor_bottom = connect_phone_btn.get_path()
			connect_phone_btn.focus_neighbor_top = ip_input.get_path()

	if has_node("/root/VirtualKeyboardManager"):
		var vkm = get_node("/root/VirtualKeyboardManager")
		if vkm.is_controller_mode_active():
			feeds = CameraServer.feeds()
			if feeds.is_empty() and desk_cams.is_empty():
				ip_input.call_deferred("grab_focus")
			elif is_instance_valid(cam_option):
				cam_option.call_deferred("grab_focus")
