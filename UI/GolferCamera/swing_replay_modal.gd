extends PanelContainer

# SwingReplayModal
# Nearly full-screen modal replaying the golfer's swing in slow motion in a loop
# with skeleton tracking lines and prioritized swing fix recommendations.

class_name SwingReplayModal

signal closed()

# Nodes
var _skeleton_overlay: GolferSkeletonOverlay = null
var _play_pause_btn: Button = null
var _speed_025_btn: Button = null
var _speed_05_btn: Button = null
var _speed_10_btn: Button = null
var _scrub_slider: HSlider = null
var _time_lbl: Label = null
var _rec_vbox: VBoxContainer = null
var _replay_feed_rect: TextureRect = null

# Playback State
var is_playing: bool = true
var replay_speed: float = 0.5 # Default 0.5x slow motion
var current_time: float = 0.0
var total_duration: float = 2.5 # 2.5 second swing loop

var shot_data: Dictionary = {}
var recommendations: Array[Dictionary] = []
var _recorded_frames: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Center in viewport & cover 90%
	var vp_size = get_viewport_rect().size
	var modal_w = clamp(vp_size.x * 0.90, 850, 1400)
	var modal_h = clamp(vp_size.y * 0.90, 550, 900)
	
	size = Vector2(modal_w, modal_h)
	custom_minimum_size = size
	position = (vp_size - size) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_close_button_pressed()
			get_viewport().set_input_as_handled()


func setup_modal(data: Dictionary, frames: Array[Dictionary] = []) -> void:
	shot_data = data.duplicate()
	_recorded_frames = frames.duplicate()
	if not _recorded_frames.is_empty():
		total_duration = max(1.0, _recorded_frames.size() * 0.066)
	_build_ui()

func _build_ui() -> void:
	# Clear existing children if any
	for c in get_children():
		c.queue_free()
		
	# Glassmorphic Modal Container Style
	var modal_style = StyleBoxFlat.new()
	modal_style.bg_color = Color(0.06, 0.08, 0.12, 0.96) # Dark obsidian
	modal_style.corner_radius_top_left = 16
	modal_style.corner_radius_top_right = 16
	modal_style.corner_radius_bottom_left = 16
	modal_style.corner_radius_bottom_right = 16
	modal_style.border_width_left = 2
	modal_style.border_width_top = 2
	modal_style.border_width_right = 2
	modal_style.border_width_bottom = 2
	modal_style.border_color = Color(0.2, 0.6, 0.8, 0.8)
	modal_style.shadow_color = Color(0, 0, 0, 0.6)
	modal_style.shadow_size = 20
	modal_style.content_margin_left = 16
	modal_style.content_margin_top = 16
	modal_style.content_margin_right = 16
	modal_style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", modal_style)

	var main_hbox = HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 16)
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# =========================================================================
	# LEFT SIDE: SLOW-MOTION VIDEO & SKELETON REPLAY PLAYER
	# =========================================================================
	var left_vbox = VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.size_flags_stretch_ratio = 1.2
	left_vbox.add_theme_constant_override("separation", 10)

	var left_title = Label.new()
	left_title.text = "📹 SLOW-MOTION SWING REPLAY"
	left_title.add_theme_font_size_override("font_size", 16)
	left_title.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	left_vbox.add_child(left_title)

	var video_panel = PanelContainer.new()
	video_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	video_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	video_panel.custom_minimum_size = Vector2(400, 360)

	var vid_style = StyleBoxFlat.new()
	vid_style.bg_color = Color(0.02, 0.03, 0.05, 1.0)
	vid_style.corner_radius_top_left = 10
	vid_style.corner_radius_top_right = 10
	vid_style.corner_radius_bottom_left = 10
	vid_style.corner_radius_bottom_right = 10
	vid_style.border_width_left = 1
	vid_style.border_width_top = 1
	vid_style.border_width_right = 1
	vid_style.border_width_bottom = 1
	vid_style.border_color = Color(0.15, 0.35, 0.5)
	video_panel.add_theme_stylebox_override("panel", vid_style)

	var feed_rect = TextureRect.new()
	feed_rect.name = "ReplayFeedRect"
	feed_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	feed_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	feed_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_replay_feed_rect = feed_rect
	
	if _recorded_frames.is_empty():
		if CameraServer.get_feed_count() > 0:
			var feed = CameraServer.get_feed(0)
			if feed != null and feed.feed_is_active:
				var cam_tex = CameraTexture.new()
				cam_tex.camera_feed_id = feed.get_id()
				cam_tex.camera_is_active = true
				feed_rect.texture = cam_tex
	video_panel.add_child(feed_rect)

	# Stick Skeleton Overlay & Human Pose Detection
	_skeleton_overlay = GolferSkeletonOverlay.new()
	_skeleton_overlay.name = "GolferSkeletonOverlay"
	_skeleton_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skeleton_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skeleton_overlay.is_replay_mode = not _recorded_frames.is_empty()
	video_panel.add_child(_skeleton_overlay)

	# Defer analysis so the skeleton overlay has time to receive real pose data
	# from the bridge or recorded frame telemetry before we generate recommendations.
	_run_deferred_analysis()

	left_vbox.add_child(video_panel)

	# Checkpoint Jump Buttons
	var check_hbox = HBoxContainer.new()
	check_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	check_hbox.add_theme_constant_override("separation", 6)
	
	var check_lbl = Label.new()
	check_lbl.text = "Checkpoints:"
	check_lbl.add_theme_font_size_override("font_size", 12)
	check_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	check_hbox.add_child(check_lbl)

	var check_points = [
		["Address", 0.0],
		["Top (P4)", 0.35],
		["Impact (P7)", 0.65],
		["Finish", 1.0]
	]
	for cp in check_points:
		var cp_btn = Button.new()
		cp_btn.text = cp[0]
		cp_btn.custom_minimum_size = Vector2(85, 28)
		_apply_btn_style(cp_btn, Color(0.18, 0.25, 0.35))
		var prog_val: float = cp[1]
		cp_btn.pressed.connect(func():
			_set_paused_state(true)
			current_time = prog_val * total_duration
			_update_playback_frame()
		)
		check_hbox.add_child(cp_btn)
	left_vbox.add_child(check_hbox)

	# Controls Bar
	var ctrl_vbox = VBoxContainer.new()
	ctrl_vbox.add_theme_constant_override("separation", 6)

	var scrub_hbox = HBoxContainer.new()
	scrub_hbox.add_theme_constant_override("separation", 8)
	
	_scrub_slider = HSlider.new()
	_scrub_slider.min_value = 0.0
	_scrub_slider.max_value = total_duration
	_scrub_slider.step = 0.02
	_scrub_slider.value = 0.0
	_scrub_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub_slider.value_changed.connect(func(val):
		current_time = val
		_update_playback_frame()
	)
	scrub_hbox.add_child(_scrub_slider)

	_time_lbl = Label.new()
	_time_lbl.text = "0.0s / 2.5s"
	_time_lbl.custom_minimum_size = Vector2(80, 0)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_lbl.add_theme_font_size_override("font_size", 12)
	_time_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	scrub_hbox.add_child(_time_lbl)
	ctrl_vbox.add_child(scrub_hbox)

	var act_hbox = HBoxContainer.new()
	act_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	act_hbox.add_theme_constant_override("separation", 8)

	_play_pause_btn = Button.new()
	_play_pause_btn.text = "⏸ PAUSE"
	_play_pause_btn.custom_minimum_size = Vector2(95, 36)
	_apply_btn_style(_play_pause_btn, Color(0.2, 0.5, 0.4))
	_play_pause_btn.pressed.connect(func():
		_set_paused_state(is_playing)
	)
	act_hbox.add_child(_play_pause_btn)

	var step_back = Button.new()
	step_back.text = "⏮ -1 Frame"
	step_back.custom_minimum_size = Vector2(90, 36)
	_apply_btn_style(step_back, Color(0.2, 0.25, 0.35))
	step_back.pressed.connect(func():
		_set_paused_state(true)
		current_time = clamp(current_time - 0.05, 0.0, total_duration)
		_update_playback_frame()
	)
	act_hbox.add_child(step_back)

	var step_fwd = Button.new()
	step_fwd.text = "+1 Frame ⏭"
	step_fwd.custom_minimum_size = Vector2(90, 36)
	_apply_btn_style(step_fwd, Color(0.2, 0.25, 0.35))
	step_fwd.pressed.connect(func():
		_set_paused_state(true)
		current_time = clamp(current_time + 0.05, 0.0, total_duration)
		_update_playback_frame()
	)
	act_hbox.add_child(step_fwd)

	_speed_025_btn = Button.new()
	_speed_025_btn.text = "0.25x"
	_speed_025_btn.custom_minimum_size = Vector2(55, 36)
	_apply_btn_style(_speed_025_btn, Color(0.2, 0.25, 0.35))
	_speed_025_btn.pressed.connect(func(): _set_replay_speed(0.25))
	act_hbox.add_child(_speed_025_btn)

	_speed_05_btn = Button.new()
	_speed_05_btn.text = "0.5x"
	_speed_05_btn.custom_minimum_size = Vector2(55, 36)
	_apply_btn_style(_speed_05_btn, Color(0.15, 0.5, 0.6))
	_speed_05_btn.pressed.connect(func(): _set_replay_speed(0.5))
	act_hbox.add_child(_speed_05_btn)

	_speed_10_btn = Button.new()
	_speed_10_btn.text = "1.0x"
	_speed_10_btn.custom_minimum_size = Vector2(55, 36)
	_apply_btn_style(_speed_10_btn, Color(0.2, 0.25, 0.35))
	_speed_10_btn.pressed.connect(func(): _set_replay_speed(1.0))
	act_hbox.add_child(_speed_10_btn)

	var skel_toggle_btn = Button.new()
	skel_toggle_btn.text = "🦴 Skeleton: ON"
	skel_toggle_btn.custom_minimum_size = Vector2(110, 36)
	_apply_btn_style(skel_toggle_btn, Color(0.15, 0.45, 0.45))
	skel_toggle_btn.pressed.connect(func():
		if _skeleton_overlay != null:
			_skeleton_overlay.show_skeleton = not _skeleton_overlay.show_skeleton
			skel_toggle_btn.text = "🦴 Skeleton: ON" if _skeleton_overlay.show_skeleton else "🦴 Skeleton: OFF"
			_apply_btn_style(skel_toggle_btn, Color(0.15, 0.45, 0.45) if _skeleton_overlay.show_skeleton else Color(0.25, 0.25, 0.3))
	)
	act_hbox.add_child(skel_toggle_btn)

	ctrl_vbox.add_child(act_hbox)
	left_vbox.add_child(ctrl_vbox)

	main_hbox.add_child(left_vbox)

	# =========================================================================
	# RIGHT SIDE: SWING ANALYSIS & PRIORITIZED RECOMMENDATIONS
	# =========================================================================
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.size_flags_stretch_ratio = 1.0
	right_vbox.add_theme_constant_override("separation", 10)

	var r_header = HBoxContainer.new()
	r_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var r_title = Label.new()
	r_title.text = "🎯 RECOMMENDED FIXES (PRIORITIZED)"
	r_title.add_theme_font_size_override("font_size", 16)
	r_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	r_header.add_child(r_title)

	var r_spacer = Control.new()
	r_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r_header.add_child(r_spacer)

	var close_btn = Button.new()
	close_btn.name = "ResumePracticeButton"
	close_btn.text = "✖ RESUME PRACTICE"
	close_btn.custom_minimum_size = Vector2(160, 38)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_btn_style(close_btn, Color(0.75, 0.2, 0.2))
	close_btn.pressed.connect(_on_close_button_pressed)
	r_header.add_child(close_btn)
	right_vbox.add_child(r_header)

	# Shot Telemetry Bar
	var telem_panel = PanelContainer.new()
	telem_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var telem_style = StyleBoxFlat.new()
	telem_style.bg_color = Color(0.1, 0.14, 0.2)
	telem_style.corner_radius_top_left = 8
	telem_style.corner_radius_top_right = 8
	telem_style.corner_radius_bottom_left = 8
	telem_style.corner_radius_bottom_right = 8
	telem_style.content_margin_left = 10
	telem_style.content_margin_top = 8
	telem_style.content_margin_right = 10
	telem_style.content_margin_bottom = 8
	telem_panel.add_theme_stylebox_override("panel", telem_style)

	var telem_lbl = Label.new()
	var club_str = str(shot_data.get("Club", "Driver"))
	var dist_val = float(shot_data.get("Carry", shot_data.get("CarryDistance", shot_data.get("TotalDistance", 220))))
	var speed_val = float(shot_data.get("Speed", 140.0))
	var axis_val = float(shot_data.get("SpinAxis", 0.0))
	var vla_val = float(shot_data.get("VLA", 14.2))
	
	telem_lbl.text = "Club: %s  |  Carry: %.0f yds  |  Speed: %.1f mph  |  Spin Axis: %+.1f°  |  VLA: %.1f°" % [
		club_str, dist_val, speed_val, axis_val, vla_val
	]
	telem_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	telem_lbl.add_theme_font_size_override("font_size", 12)
	telem_lbl.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	telem_panel.add_child(telem_lbl)
	right_vbox.add_child(telem_panel)

	# Scrollable Recommendation Cards Container
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeManager.apply_scroll_container_style(scroll, 28)

	_rec_vbox = VBoxContainer.new()
	_rec_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_vbox.add_theme_constant_override("separation", 12)

	for rec in recommendations:
		var card = _create_recommendation_card(rec)
		_rec_vbox.add_child(card)

	scroll.add_child(_rec_vbox)
	right_vbox.add_child(scroll)

	main_hbox.add_child(right_vbox)
	add_child(main_hbox)

func _process(delta: float) -> void:
	if is_playing:
		current_time += delta * replay_speed
		if current_time >= total_duration:
			current_time = 0.0
		_update_playback_frame()

func _set_paused_state(paused: bool) -> void:
	is_playing = not paused
	if _skeleton_overlay != null:
		_skeleton_overlay.is_paused = paused
	if _play_pause_btn != null:
		_play_pause_btn.text = "▶ PLAY" if paused else "⏸ PAUSE"
		_apply_btn_style(_play_pause_btn, Color(0.15, 0.45, 0.6) if paused else Color(0.2, 0.5, 0.4))

func _update_playback_frame() -> void:
	if _scrub_slider != null:
		_scrub_slider.set_value_no_signal(current_time)
	if _time_lbl != null:
		_time_lbl.text = "%.2fs / %.1fs" % [current_time, total_duration]

	if not _recorded_frames.is_empty():
		var frame_idx: int = clamp(int((current_time / total_duration) * (_recorded_frames.size() - 1)), 0, _recorded_frames.size() - 1)
		var frame_data: Dictionary = _recorded_frames[frame_idx]
		
		var img: Image = frame_data.get("image")
		if img != null and not img.is_empty() and _replay_feed_rect != null:
			_replay_feed_rect.texture = ImageTexture.create_from_image(img)
			
		var lms: Dictionary = frame_data.get("landmarks", {})
		if _skeleton_overlay != null:
			_skeleton_overlay._on_pose_detected(lms)
	elif _skeleton_overlay != null:
		var prog = current_time / total_duration
		_skeleton_overlay.set_frame_progress(prog)

func _set_replay_speed(spd: float) -> void:
	replay_speed = spd
	_apply_btn_style(_speed_025_btn, Color(0.15, 0.5, 0.6) if spd == 0.25 else Color(0.2, 0.25, 0.35))
	_apply_btn_style(_speed_05_btn, Color(0.15, 0.5, 0.6) if spd == 0.5 else Color(0.2, 0.25, 0.35))
	_apply_btn_style(_speed_10_btn, Color(0.15, 0.5, 0.6) if spd == 1.0 else Color(0.2, 0.25, 0.35))

func _get_combined_telemetry() -> Dictionary:
	if _recorded_frames.is_empty():
		return _skeleton_overlay.get_measured_telemetry() if _skeleton_overlay != null else {}

	var max_turn: float = 0.0
	var min_spine: float = 90.0
	var max_ext: float = 0.0
	var max_sway: float = 0.0
	var base_width: float = 0.0
	var base_hip_y: float = 0.0
	var base_hip_x: float = 0.0
	var valid_count: int = 0

	for frame_data in _recorded_frames:
		var lms: Dictionary = frame_data.get("landmarks", {})
		if not (lms.has("left_shoulder") and lms.has("right_shoulder") and lms.has("left_hip") and lms.has("right_hip")):
			continue

		var ls_pos = Vector2(float(lms["left_shoulder"].get("x", 0)), float(lms["left_shoulder"].get("y", 0)))
		var rs_pos = Vector2(float(lms["right_shoulder"].get("x", 0)), float(lms["right_shoulder"].get("y", 0)))
		var lh_pos = Vector2(float(lms["left_hip"].get("x", 0)), float(lms["left_hip"].get("y", 0)))
		var rh_pos = Vector2(float(lms["right_hip"].get("x", 0)), float(lms["right_hip"].get("y", 0)))

		var s_mid = (ls_pos + rs_pos) * 0.5
		var h_mid = (lh_pos + rh_pos) * 0.5
		var width = ls_pos.distance_to(rs_pos)
		var torso = s_mid.distance_to(h_mid)

		if valid_count == 0:
			base_width = width
			base_hip_y = h_mid.y
			base_hip_x = h_mid.x

		valid_count += 1

		# Spine angle
		var spine_vec = s_mid - h_mid
		var spine_angle = rad_to_deg(atan2(abs(spine_vec.x), -spine_vec.y))
		min_spine = min(min_spine, spine_angle)

		# Shoulder turn
		if base_width > 0.001:
			var w_ratio = clamp(width / base_width, 0.0, 1.0)
			var turn = rad_to_deg(acos(w_ratio))
			max_turn = max(max_turn, turn)

		# Early extension & sway
		if torso > 0.01:
			var ext = ((base_hip_y - h_mid.y) / torso) * 10.0
			max_ext = max(max_ext, ext)
			var sway = ((h_mid.x - base_hip_x) / torso) * 10.0
			max_sway = max(max_sway, abs(sway))

	if valid_count < 3:
		return _skeleton_overlay.get_measured_telemetry() if _skeleton_overlay != null else {}

	return {
		"spine_angle": min_spine,
		"shoulder_turn": max_turn,
		"early_extension": max_ext,
		"hip_sway": max_sway,
		"has_valid_telemetry": true
	}


func _run_deferred_analysis() -> void:
	if not is_inside_tree():
		return
	if not _recorded_frames.is_empty():
		var telemetry := _get_combined_telemetry()
		recommendations = GolfSwingAnalyzer.analyze_shot(shot_data, telemetry)
		_refresh_recommendation_cards()
		_record_swing_recommendations()
	else:
		await get_tree().create_timer(1.0).timeout
		if _skeleton_overlay != null and is_inside_tree():
			var telemetry := _get_combined_telemetry()
			recommendations = GolfSwingAnalyzer.analyze_shot(shot_data, telemetry)
			_refresh_recommendation_cards()
			_record_swing_recommendations()

func _record_swing_recommendations() -> void:
	if recommendations.is_empty():
		return
	var active_player = MultiplayerManager.get_active_player()
	var player_name = active_player.get("name", "Player 1") if not active_player.is_empty() else "Player 1"
	MultiplayerManager.record_player_swing_issues(player_name, recommendations)


func _refresh_recommendation_cards() -> void:
	if _rec_vbox == null:
		return
	for c in _rec_vbox.get_children():
		c.queue_free()
	for rec in recommendations:
		var card = _create_recommendation_card(rec)
		_rec_vbox.add_child(card)


func _on_close_button_pressed() -> void:
	emit_signal("closed")
	var p = get_parent()
	if p != null:
		p.remove_child(self)
	queue_free()

func _create_recommendation_card(rec: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var severity: String = str(rec.get("severity", "MEDIUM"))
	var priority_num: int = int(rec.get("priority", 1))
	
	var border_col = Color(1.0, 0.3, 0.3, 0.9) if severity == "CRITICAL" else (Color(1.0, 0.6, 0.2, 0.8) if severity == "HIGH" else Color(0.2, 0.7, 0.9, 0.8))
	var bg_col = Color(0.12, 0.08, 0.1, 0.95) if severity == "CRITICAL" else Color(0.08, 0.11, 0.16, 0.95)

	var card_style = StyleBoxFlat.new()
	card_style.bg_color = bg_col
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_left = 10
	card_style.corner_radius_bottom_right = 10
	card_style.border_width_left = 3
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = border_col
	card_style.content_margin_left = 12
	card_style.content_margin_top = 10
	card_style.content_margin_right = 12
	card_style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", card_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	var head_hbox = HBoxContainer.new()
	
	var badge_lbl = Label.new()
	badge_lbl.text = " #%d [%s PRIORITY] " % [priority_num, severity]
	badge_lbl.add_theme_font_size_override("font_size", 11)
	badge_lbl.add_theme_color_override("font_color", border_col)
	head_hbox.add_child(badge_lbl)

	var cat_lbl = Label.new()
	cat_lbl.text = "• " + str(rec.get("category", "SWING MECHANICS"))
	cat_lbl.add_theme_font_size_override("font_size", 11)
	cat_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	head_hbox.add_child(cat_lbl)
	vbox.add_child(head_hbox)

	var title_lbl = Label.new()
	title_lbl.text = str(rec.get("title", "Swing Flaw"))
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title_lbl)

	var cam_flaw = str(rec.get("camera_flaw", ""))
	if cam_flaw != "":
		var cam_lbl = Label.new()
		cam_lbl.text = "🦴 Camera Telemetry: " + cam_flaw
		cam_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cam_lbl.add_theme_font_size_override("font_size", 12)
		cam_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		vbox.add_child(cam_lbl)

	var launch_effect = str(rec.get("launch_effect", ""))
	if launch_effect != "":
		var launch_lbl = Label.new()
		launch_lbl.text = "⚡ Shot Result: " + launch_effect
		launch_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		launch_lbl.add_theme_font_size_override("font_size", 12)
		launch_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
		vbox.add_child(launch_lbl)

	var comp_panel = PanelContainer.new()
	var comp_style = StyleBoxFlat.new()
	comp_style.bg_color = Color(0.04, 0.06, 0.09, 0.9)
	comp_style.corner_radius_top_left = 6
	comp_style.corner_radius_top_right = 6
	comp_style.corner_radius_bottom_left = 6
	comp_style.corner_radius_bottom_right = 6
	comp_style.content_margin_left = 8
	comp_style.content_margin_top = 4
	comp_style.content_margin_right = 8
	comp_style.content_margin_bottom = 4
	comp_panel.add_theme_stylebox_override("panel", comp_style)

	var comp_lbl = Label.new()
	comp_lbl.text = "📊 Yours: %s   |   %s" % [rec.get("player_val", ""), rec.get("benchmark_val", "")]
	comp_lbl.add_theme_font_size_override("font_size", 11)
	comp_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 0.95))
	comp_panel.add_child(comp_lbl)
	vbox.add_child(comp_panel)

	var fix_lbl = Label.new()
	fix_lbl.text = "💡 How to Fix: " + str(rec.get("fix_instruction", ""))
	fix_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fix_lbl.add_theme_font_size_override("font_size", 12)
	fix_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
	vbox.add_child(fix_lbl)

	var drill_str = str(rec.get("drill", ""))
	if drill_str != "":
		var drill_lbl = Label.new()
		drill_lbl.text = drill_str
		drill_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		drill_lbl.add_theme_font_size_override("font_size", 11)
		drill_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0))
		vbox.add_child(drill_lbl)

	card.add_child(vbox)
	return card

func _apply_btn_style(btn: Button, bg_col: Color) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_col
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4

	var hover_style = style.duplicate()
	hover_style.bg_color = bg_col.lightened(0.15)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = bg_col.darkened(0.15)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
