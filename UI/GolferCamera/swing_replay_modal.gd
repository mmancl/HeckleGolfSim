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
var _recorded_frames: Array = []
var _is_suggestions_only: bool = false

# Deferred Background Analysis State
var _is_analysis_complete: bool = false
var _analysis_cancelled: bool = false
var _analysis_loading_panel: PanelContainer = null
var _analysis_progress_bar: ProgressBar = null
var _analysis_status_lbl: Label = null
var _analysis_sub_lbl: Label = null
var _skel_toggle_btn: Button = null

# Mobile layout state
var _mobile_tab_btn_video: Button = null
var _mobile_tab_btn_recs: Button = null
var _left_vbox: VBoxContainer = null
var _right_vbox: VBoxContainer = null
var _mobile_active_tab: int = 1 # 0: Video, 1: Fixes & Analysis


func _is_mobile_view() -> bool:
	var vp_size = get_viewport_rect().size
	return vp_size.x < 850 or vp_size.y > vp_size.x or OS.has_feature("mobile")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	_recenter_modal()
	if get_viewport() != null and not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)


func _on_viewport_resized() -> void:
	_recenter_modal()


func _recenter_modal() -> void:
	var vp_size = get_viewport_rect().size
	var is_mob = _is_mobile_view()
	var modal_w: float
	var modal_h: float
	if is_mob:
		modal_w = clamp(vp_size.x * 0.98, 320, 850)
		modal_h = clamp(vp_size.y * 0.97, 420, 1000)
	elif _is_suggestions_only:
		modal_w = clamp(vp_size.x * 0.65, 540, 920)
		modal_h = clamp(vp_size.y * 0.88, 500, 900)
	else:
		modal_w = clamp(vp_size.x * 0.92, 800, 1400)
		modal_h = clamp(vp_size.y * 0.90, 520, 920)
	
	size = Vector2(modal_w, modal_h)
	custom_minimum_size = size
	position = (vp_size - size) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_close_button_pressed()
			get_viewport().set_input_as_handled()


func setup_modal(data: Dictionary, frames: Array = [], suggestions_only: bool = false) -> void:
	shot_data = data.duplicate()
	_is_suggestions_only = suggestions_only
	_recorded_frames = [] if suggestions_only else frames.duplicate()
	if not _recorded_frames.is_empty():
		total_duration = max(1.0, _recorded_frames.size() * 0.066)
	_is_analysis_complete = suggestions_only
	_analysis_cancelled = false

	# PHASE 1: Immediate Launch Monitor analysis so user gets instant real suggestions
	recommendations = GolfSwingAnalyzer.analyze_launch_monitor(shot_data)

	_recenter_modal()
	_build_ui()
	if not _is_suggestions_only:
		_start_background_wireframe_analysis()
	else:
		_record_swing_recommendations()

func _build_ui() -> void:
	# Clear existing children if any
	for c in get_children():
		c.queue_free()
		
	var is_mob = _is_mobile_view()

	# Glassmorphic Modal Container Style
	var modal_style = StyleBoxFlat.new()
	modal_style.bg_color = Color(0.06, 0.08, 0.12, 0.96) # Dark obsidian
	modal_style.corner_radius_top_left = 14 if is_mob else 16
	modal_style.corner_radius_top_right = 14 if is_mob else 16
	modal_style.corner_radius_bottom_left = 14 if is_mob else 16
	modal_style.corner_radius_bottom_right = 14 if is_mob else 16
	modal_style.border_width_left = 2
	modal_style.border_width_top = 2
	modal_style.border_width_right = 2
	modal_style.border_width_bottom = 2
	modal_style.border_color = Color(0.2, 0.6, 0.8, 0.8)
	modal_style.shadow_color = Color(0, 0, 0, 0.6)
	modal_style.shadow_size = 16 if is_mob else 20
	modal_style.content_margin_left = 10 if is_mob else 16
	modal_style.content_margin_top = 10 if is_mob else 16
	modal_style.content_margin_right = 10 if is_mob else 16
	modal_style.content_margin_bottom = 10 if is_mob else 16
	add_theme_stylebox_override("panel", modal_style)

	if _is_suggestions_only:
		_build_suggestions_only_ui()
		return

	var is_match = false
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty() and not mp_mgr.practice_mode_active:
		is_match = true

	var outer_vbox: VBoxContainer = null
	if is_mob:
		outer_vbox = VBoxContainer.new()
		outer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		outer_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer_vbox.add_theme_constant_override("separation", 8)

		# Mobile Top Header Bar: Title + Touch-friendly Resume/Next button
		var top_bar = HBoxContainer.new()
		top_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var m_title = Label.new()
		m_title.text = "🎯 SHOT ANALYSIS"
		m_title.add_theme_font_size_override("font_size", 18)
		m_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		top_bar.add_child(m_title)
		
		var m_spacer = Control.new()
		m_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top_bar.add_child(m_spacer)
		
		var m_close_btn = Button.new()
		m_close_btn.name = "ResumePracticeButton"
		m_close_btn.text = "✖ NEXT" if is_match else "✖ RESUME"
		m_close_btn.custom_minimum_size = Vector2(110, 42)
		m_close_btn.add_theme_font_size_override("font_size", 15)
		_apply_btn_style(m_close_btn, Color(0.75, 0.2, 0.2))
		m_close_btn.pressed.connect(_on_close_button_pressed)
		top_bar.add_child(m_close_btn)
		outer_vbox.add_child(top_bar)

		# Mobile Tab Selector: [ 🎯 Fixes & Telemetry ] [ 📹 Video Replay ]
		var tab_bar = HBoxContainer.new()
		tab_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_bar.add_theme_constant_override("separation", 8)

		_mobile_tab_btn_recs = Button.new()
		_mobile_tab_btn_recs.text = "🎯 Fixes & Data (%d)" % recommendations.size()
		_mobile_tab_btn_recs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mobile_tab_btn_recs.custom_minimum_size = Vector2(0, 46)
		_mobile_tab_btn_recs.add_theme_font_size_override("font_size", 16)
		_mobile_tab_btn_recs.pressed.connect(func(): _show_mobile_tab(1))
		tab_bar.add_child(_mobile_tab_btn_recs)

		_mobile_tab_btn_video = Button.new()
		_mobile_tab_btn_video.text = "📹 Video Replay"
		_mobile_tab_btn_video.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mobile_tab_btn_video.custom_minimum_size = Vector2(0, 46)
		_mobile_tab_btn_video.add_theme_font_size_override("font_size", 16)
		_mobile_tab_btn_video.pressed.connect(func(): _show_mobile_tab(0))
		tab_bar.add_child(_mobile_tab_btn_video)

		outer_vbox.add_child(tab_bar)

	# =========================================================================
	# LEFT SIDE: SLOW-MOTION VIDEO & SKELETON REPLAY PLAYER
	# =========================================================================
	_left_vbox = VBoxContainer.new()
	_left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_left_vbox.size_flags_stretch_ratio = 1.2
	_left_vbox.add_theme_constant_override("separation", 8 if is_mob else 10)

	if not is_mob:
		var left_title = Label.new()
		left_title.text = "📹 SLOW-MOTION SWING REPLAY"
		left_title.add_theme_font_size_override("font_size", 18)
		left_title.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		_left_vbox.add_child(left_title)

	var video_panel = PanelContainer.new()
	video_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	video_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	video_panel.custom_minimum_size = Vector2(280, 220) if is_mob else Vector2(400, 360)

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
		if OS.has_feature("mobile") and CameraServer.get_feed_count() > 0:
			var feed = CameraServer.get_feed(0)
			if feed != null and feed.feed_is_active:
				var data_type = feed.get_datatype()
				if data_type == CameraFeed.FEED_YCBCR or data_type == CameraFeed.FEED_YCBCR_SEP:
					var y_tex = CameraTexture.new()
					y_tex.camera_feed_id = feed.get_id()
					y_tex.which_feed = CameraServer.FEED_Y_IMAGE
					y_tex.camera_is_active = true

					var cbcr_tex = CameraTexture.new()
					cbcr_tex.camera_feed_id = feed.get_id()
					cbcr_tex.which_feed = CameraServer.FEED_CBCR_IMAGE
					cbcr_tex.camera_is_active = true

					var shader = Shader.new()
					shader.code = """
shader_type canvas_item;

uniform sampler2D y_tex : hint_default_black;
uniform sampler2D cbcr_tex : hint_default_black;

void fragment() {
	float y = texture(y_tex, UV).r;
	vec2 cbcr = texture(cbcr_tex, UV).rg;

	float cb = cbcr.r - 0.5;
	float cr = cbcr.g - 0.5;

	float r = y + 1.402 * cr;
	float g = y - 0.344136 * cb - 0.714136 * cr;
	float b = y + 1.772 * cb;

	COLOR = vec4(clamp(vec3(r, g, b), 0.0, 1.0), 1.0);
}
"""
					var mat = ShaderMaterial.new()
					mat.shader = shader
					mat.set_shader_parameter("y_tex", y_tex)
					mat.set_shader_parameter("cbcr_tex", cbcr_tex)

					feed_rect.material = mat
					feed_rect.texture = y_tex
				else:
					feed_rect.material = null
					var cam_tex = CameraTexture.new()
					cam_tex.camera_feed_id = feed.get_id()
					cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
					cam_tex.camera_is_active = true
					feed_rect.texture = cam_tex

	video_panel.add_child(feed_rect)

	# Stick Skeleton Overlay & Human Pose Detection
	_skeleton_overlay = GolferSkeletonOverlay.new()
	_skeleton_overlay.name = "GolferSkeletonOverlay"
	_skeleton_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skeleton_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skeleton_overlay.is_replay_mode = not _recorded_frames.is_empty()
	_skeleton_overlay.show_skeleton = _is_analysis_complete
	video_panel.add_child(_skeleton_overlay)

	_left_vbox.add_child(video_panel)

	# Checkpoint Jump Buttons - Wrapped in HFlowContainer so buttons fit on narrow screens
	var check_flow = HFlowContainer.new()
	check_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_flow.add_theme_constant_override("h_separation", 6)
	check_flow.add_theme_constant_override("v_separation", 4)
	
	var check_lbl = Label.new()
	check_lbl.text = "Checkpoints:"
	check_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 14)
	check_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	check_flow.add_child(check_lbl)

	var check_points = [
		["Address", 0.0],
		["Top (P4)", 0.35],
		["Impact (P7)", 0.65],
		["Finish", 1.0]
	]
	for cp in check_points:
		var cp_btn = Button.new()
		cp_btn.text = cp[0]
		cp_btn.custom_minimum_size = Vector2(85, 36) if is_mob else Vector2(90, 32)
		cp_btn.add_theme_font_size_override("font_size", 13 if is_mob else 14)
		_apply_btn_style(cp_btn, Color(0.18, 0.25, 0.35))
		var prog_val: float = cp[1]
		cp_btn.pressed.connect(func():
			_set_paused_state(true)
			current_time = prog_val * total_duration
			_update_playback_frame()
		)
		check_flow.add_child(cp_btn)
	_left_vbox.add_child(check_flow)

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
	_time_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 14)
	_time_lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	scrub_hbox.add_child(_time_lbl)
	ctrl_vbox.add_child(scrub_hbox)

	# Playback & speed controls wrapped in HFlowContainer for mobile
	var act_flow = HFlowContainer.new()
	act_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	act_flow.add_theme_constant_override("h_separation", 6)
	act_flow.add_theme_constant_override("v_separation", 6)

	_play_pause_btn = Button.new()
	_play_pause_btn.text = "⏸ PAUSE"
	_play_pause_btn.custom_minimum_size = Vector2(100, 40)
	_play_pause_btn.add_theme_font_size_override("font_size", 14)
	_apply_btn_style(_play_pause_btn, Color(0.2, 0.5, 0.4))
	_play_pause_btn.pressed.connect(func():
		_set_paused_state(is_playing)
	)
	act_flow.add_child(_play_pause_btn)

	var step_back = Button.new()
	step_back.text = "⏮ -1"
	step_back.custom_minimum_size = Vector2(75, 40)
	step_back.add_theme_font_size_override("font_size", 14)
	_apply_btn_style(step_back, Color(0.2, 0.25, 0.35))
	step_back.pressed.connect(func():
		_set_paused_state(true)
		current_time = clamp(current_time - 0.05, 0.0, total_duration)
		_update_playback_frame()
	)
	act_flow.add_child(step_back)

	var step_fwd = Button.new()
	step_fwd.text = "+1 ⏭"
	step_fwd.custom_minimum_size = Vector2(75, 40)
	step_fwd.add_theme_font_size_override("font_size", 14)
	_apply_btn_style(step_fwd, Color(0.2, 0.25, 0.35))
	step_fwd.pressed.connect(func():
		_set_paused_state(true)
		current_time = clamp(current_time + 0.05, 0.0, total_duration)
		_update_playback_frame()
	)
	act_flow.add_child(step_fwd)

	_speed_025_btn = Button.new()
	_speed_025_btn.text = "0.25x"
	_speed_025_btn.custom_minimum_size = Vector2(55, 40)
	_speed_025_btn.add_theme_font_size_override("font_size", 14)
	_apply_btn_style(_speed_025_btn, Color(0.2, 0.25, 0.35))
	_speed_025_btn.pressed.connect(func(): _set_replay_speed(0.25))
	act_flow.add_child(_speed_025_btn)

	_speed_05_btn = Button.new()
	_speed_05_btn.text = "0.5x"
	_speed_05_btn.custom_minimum_size = Vector2(55, 40)
	_speed_05_btn.add_theme_font_size_override("font_size", 14)
	_apply_btn_style(_speed_05_btn, Color(0.15, 0.5, 0.6))
	_speed_05_btn.pressed.connect(func(): _set_replay_speed(0.5))
	act_flow.add_child(_speed_05_btn)

	_speed_10_btn = Button.new()
	_speed_10_btn.text = "1.0x"
	_speed_10_btn.custom_minimum_size = Vector2(55, 40)
	_speed_10_btn.add_theme_font_size_override("font_size", 14)
	_apply_btn_style(_speed_10_btn, Color(0.2, 0.25, 0.35))
	_speed_10_btn.pressed.connect(func(): _set_replay_speed(1.0))
	act_flow.add_child(_speed_10_btn)

	_skel_toggle_btn = Button.new()
	_skel_toggle_btn.text = "🦴 Skeleton: PENDING" if not _is_analysis_complete else ("🦴 Skeleton: ON" if _skeleton_overlay.show_skeleton else "🦴 Skeleton: OFF")
	_skel_toggle_btn.disabled = not _is_analysis_complete
	_skel_toggle_btn.custom_minimum_size = Vector2(140, 40)
	_skel_toggle_btn.add_theme_font_size_override("font_size", 13)
	_apply_btn_style(_skel_toggle_btn, Color(0.25, 0.25, 0.3) if not _is_analysis_complete else (Color(0.15, 0.45, 0.45) if _skeleton_overlay.show_skeleton else Color(0.25, 0.25, 0.3)))
	_skel_toggle_btn.pressed.connect(func():
		if _skeleton_overlay != null and _is_analysis_complete:
			_skeleton_overlay.show_skeleton = not _skeleton_overlay.show_skeleton
			_skel_toggle_btn.text = "🦴 Skeleton: ON" if _skeleton_overlay.show_skeleton else "🦴 Skeleton: OFF"
			_apply_btn_style(_skel_toggle_btn, Color(0.15, 0.45, 0.45) if _skeleton_overlay.show_skeleton else Color(0.25, 0.25, 0.3))
			_update_playback_frame()
	)
	act_flow.add_child(_skel_toggle_btn)

	ctrl_vbox.add_child(act_flow)
	_left_vbox.add_child(ctrl_vbox)

	# =========================================================================
	# RIGHT SIDE: SWING ANALYSIS & PRIORITIZED RECOMMENDATIONS
	# =========================================================================
	_right_vbox = VBoxContainer.new()
	_right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right_vbox.size_flags_stretch_ratio = 1.0
	_right_vbox.add_theme_constant_override("separation", 8 if is_mob else 10)

	if not is_mob:
		var r_header = HBoxContainer.new()
		r_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var r_title = Label.new()
		r_title.text = "🎯 RECOMMENDED FIXES (PRIORITIZED)"
		r_title.add_theme_font_size_override("font_size", 18)
		r_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		r_header.add_child(r_title)

		var r_spacer = Control.new()
		r_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_header.add_child(r_spacer)

		var close_btn = Button.new()
		close_btn.name = "ResumePracticeButton"
		close_btn.text = "✖ NEXT SHOT" if is_match else "✖ RESUME PRACTICE"
		close_btn.custom_minimum_size = Vector2(175, 42)
		close_btn.add_theme_font_size_override("font_size", 15)
		close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_apply_btn_style(close_btn, Color(0.75, 0.2, 0.2))
		close_btn.pressed.connect(_on_close_button_pressed)
		r_header.add_child(close_btn)
		_right_vbox.add_child(r_header)

	# Shot Telemetry Bar (Mobile Responsive Chips)
	var telem_panel = _create_telemetry_panel()
	_right_vbox.add_child(telem_panel)

	# Loading / Analysis Progress Panel (shown until background wireframe analysis completes)
	if not _is_analysis_complete:
		var load_panel = PanelContainer.new()
		load_panel.name = "AnalysisLoadingPanel"
		load_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var load_style = StyleBoxFlat.new()
		load_style.bg_color = Color(0.08, 0.12, 0.18, 0.95)
		load_style.corner_radius_top_left = 10
		load_style.corner_radius_top_right = 10
		load_style.corner_radius_bottom_left = 10
		load_style.corner_radius_bottom_right = 10
		load_style.border_width_left = 2
		load_style.border_width_top = 2
		load_style.border_width_right = 2
		load_style.border_width_bottom = 2
		load_style.border_color = Color(0.2, 0.6, 0.85, 0.8)
		load_style.content_margin_left = 12 if is_mob else 16
		load_style.content_margin_top = 10 if is_mob else 16
		load_style.content_margin_right = 12 if is_mob else 16
		load_style.content_margin_bottom = 10 if is_mob else 16
		load_panel.add_theme_stylebox_override("panel", load_style)

		var l_vbox = VBoxContainer.new()
		l_vbox.add_theme_constant_override("separation", 6 if is_mob else 10)

		var l_title = Label.new()
		l_title.text = "🦴 SKELETON WIREFRAME ANALYSIS IN PROGRESS"
		l_title.add_theme_font_size_override("font_size", 14 if is_mob else 15)
		l_title.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		l_vbox.add_child(l_title)

		_analysis_status_lbl = Label.new()
		_analysis_status_lbl.text = "Tracking body joint kinematics & rotation in background..."
		_analysis_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_analysis_status_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 14)
		_analysis_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.6))
		l_vbox.add_child(_analysis_status_lbl)

		_analysis_progress_bar = ProgressBar.new()
		_analysis_progress_bar.min_value = 0.0
		_analysis_progress_bar.max_value = 100.0
		_analysis_progress_bar.value = 0.0
		_analysis_progress_bar.custom_minimum_size = Vector2(0, 24)
		_analysis_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_analysis_progress_bar.show_percentage = true

		var bar_bg = StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.04, 0.06, 0.1, 1.0)
		bar_bg.corner_radius_top_left = 6
		bar_bg.corner_radius_top_right = 6
		bar_bg.corner_radius_bottom_left = 6
		bar_bg.corner_radius_bottom_right = 6
		_analysis_progress_bar.add_theme_stylebox_override("background", bar_bg)

		var bar_fill = StyleBoxFlat.new()
		bar_fill.bg_color = Color(0.15, 0.65, 0.85, 1.0)
		bar_fill.corner_radius_top_left = 6
		bar_fill.corner_radius_top_right = 6
		bar_fill.corner_radius_bottom_left = 6
		bar_fill.corner_radius_bottom_right = 6
		_analysis_progress_bar.add_theme_stylebox_override("fill", bar_fill)
		l_vbox.add_child(_analysis_progress_bar)

		_analysis_sub_lbl = Label.new()
		_analysis_sub_lbl.text = "Launch monitor insights are shown below. Once full skeleton calculation completes, shoulder/hip squareness and rotation will be analyzed."
		_analysis_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_analysis_sub_lbl.add_theme_font_size_override("font_size", 12 if is_mob else 13)
		_analysis_sub_lbl.add_theme_color_override("font_color", Color(0.65, 0.75, 0.85))
		l_vbox.add_child(_analysis_sub_lbl)

		load_panel.add_child(l_vbox)
		_analysis_loading_panel = load_panel
		_right_vbox.add_child(load_panel)

	# Scrollable Recommendation Cards Container
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeManager.apply_scroll_container_style(scroll, 28)

	_rec_vbox = VBoxContainer.new()
	_rec_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_vbox.add_theme_constant_override("separation", 10 if is_mob else 12)

	if recommendations.is_empty():
		var empty_card = _create_empty_card()
		_rec_vbox.add_child(empty_card)
	else:
		for rec in recommendations:
			var card = _create_recommendation_card(rec)
			_rec_vbox.add_child(card)

	scroll.add_child(_rec_vbox)
	_right_vbox.add_child(scroll)

	if is_mob:
		outer_vbox.add_child(_left_vbox)
		outer_vbox.add_child(_right_vbox)
		add_child(outer_vbox)
		_show_mobile_tab(_mobile_active_tab)
	else:
		var main_hbox = HBoxContainer.new()
		main_hbox.add_theme_constant_override("separation", 16)
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		main_hbox.add_child(_left_vbox)
		main_hbox.add_child(_right_vbox)
		add_child(main_hbox)


func _show_mobile_tab(tab_idx: int) -> void:
	_mobile_active_tab = tab_idx
	if _left_vbox != null:
		_left_vbox.visible = (tab_idx == 0)
	if _right_vbox != null:
		_right_vbox.visible = (tab_idx == 1)
	if _mobile_tab_btn_video != null and _mobile_tab_btn_recs != null:
		if tab_idx == 0:
			_apply_btn_style(_mobile_tab_btn_video, Color(0.2, 0.55, 0.8))
			_apply_btn_style(_mobile_tab_btn_recs, Color(0.12, 0.16, 0.22))
		else:
			_apply_btn_style(_mobile_tab_btn_video, Color(0.12, 0.16, 0.22))
			_apply_btn_style(_mobile_tab_btn_recs, Color(0.2, 0.55, 0.8))


func _build_suggestions_only_ui() -> void:
	var is_mob = _is_mobile_view()
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10 if is_mob else 14)

	# Header with Title and Close Button
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var title = Label.new()
	title.text = "🎯 RECOMMENDED FIXES"
	title.add_theme_font_size_override("font_size", 18 if is_mob else 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	header.add_child(title)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var is_match = false
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty() and not mp_mgr.practice_mode_active:
		is_match = true

	var close_btn = Button.new()
	close_btn.name = "ResumePracticeButton"
	close_btn.text = "✖ NEXT SHOT" if is_match else "✖ RESUME PRACTICE"
	close_btn.custom_minimum_size = Vector2(140 if is_mob else 180, 44)
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_btn_style(close_btn, Color(0.75, 0.2, 0.2))
	close_btn.pressed.connect(_on_close_button_pressed)
	header.add_child(close_btn)
	vbox.add_child(header)

	# Shot Telemetry Bar (Mobile Responsive Chips)
	var telem_panel = _create_telemetry_panel()
	vbox.add_child(telem_panel)

	# Informational Note Banner for Video Shot Analysis
	var note_panel = PanelContainer.new()
	note_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note_style = StyleBoxFlat.new()
	note_style.bg_color = Color(0.06, 0.12, 0.18, 0.95)
	note_style.corner_radius_top_left = 8
	note_style.corner_radius_top_right = 8
	note_style.corner_radius_bottom_left = 8
	note_style.corner_radius_bottom_right = 8
	note_style.border_width_left = 3
	note_style.border_width_top = 1
	note_style.border_width_right = 1
	note_style.border_width_bottom = 1
	note_style.border_color = Color(0.2, 0.65, 0.85, 0.85)
	note_style.content_margin_left = 12 if is_mob else 16
	note_style.content_margin_top = 10 if is_mob else 12
	note_style.content_margin_right = 12 if is_mob else 16
	note_style.content_margin_bottom = 10 if is_mob else 12
	note_panel.add_theme_stylebox_override("panel", note_style)

	var note_hbox = HBoxContainer.new()
	note_hbox.add_theme_constant_override("separation", 10)

	var note_icon = Label.new()
	note_icon.text = "📹"
	note_icon.add_theme_font_size_override("font_size", 22 if is_mob else 24)
	note_hbox.add_child(note_icon)

	var note_lbl = Label.new()
	note_lbl.text = "Golfer Cam is OFF. Enable it in the camera menu for slow-mo replay and AI skeleton tracking."
	note_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 14)
	note_lbl.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	note_hbox.add_child(note_lbl)

	note_panel.add_child(note_hbox)
	vbox.add_child(note_panel)

	# Scrollable Recommendation Cards Container
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeManager.apply_scroll_container_style(scroll, 28)

	_rec_vbox = VBoxContainer.new()
	_rec_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_vbox.add_theme_constant_override("separation", 12 if is_mob else 14)

	if recommendations.is_empty():
		var empty_card = _create_empty_card()
		_rec_vbox.add_child(empty_card)
	else:
		for rec in recommendations:
			var card = _create_recommendation_card(rec)
			_rec_vbox.add_child(card)

	scroll.add_child(_rec_vbox)
	vbox.add_child(scroll)

	add_child(vbox)


func _create_telemetry_panel() -> PanelContainer:
	var telem_panel = PanelContainer.new()
	telem_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_mob = _is_mobile_view()
	var telem_style = StyleBoxFlat.new()
	telem_style.bg_color = Color(0.08, 0.11, 0.16, 0.95)
	telem_style.corner_radius_top_left = 8
	telem_style.corner_radius_top_right = 8
	telem_style.corner_radius_bottom_left = 8
	telem_style.corner_radius_bottom_right = 8
	telem_style.border_width_left = 1
	telem_style.border_width_top = 1
	telem_style.border_width_right = 1
	telem_style.border_width_bottom = 1
	telem_style.border_color = Color(0.18, 0.32, 0.45, 0.8)
	telem_style.content_margin_left = 10 if is_mob else 12
	telem_style.content_margin_top = 8 if is_mob else 10
	telem_style.content_margin_right = 10 if is_mob else 12
	telem_style.content_margin_bottom = 8 if is_mob else 10
	telem_panel.add_theme_stylebox_override("panel", telem_style)

	var flow = HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8 if is_mob else 10)
	flow.add_theme_constant_override("v_separation", 8)

	var raw_club = shot_data.get("Club", shot_data.get("club", "Driver"))
	var club_name = GolfSwingAnalyzer.get_club_display_name(str(raw_club))
	var is_tee = bool(shot_data.get("is_tee", false))
	var lie_str = "Tee" if is_tee else "Fairway"
	if shot_data.has("lie_type") and str(shot_data["lie_type"]) != "":
		var lt = str(shot_data["lie_type"]).to_lower()
		if lt == "rough":
			lie_str = "Rough"
		elif lt == "sand" or lt == "bunker":
			lie_str = "Bunker"
		elif lt == "tee":
			lie_str = "Tee"

	var dist_val = float(shot_data.get("Carry", shot_data.get("CarryDistance", shot_data.get("TotalDistance", 220))))
	var speed_val = float(shot_data.get("Speed", shot_data.get("BallSpeed", 140.0)))
	var axis_val = float(shot_data.get("SpinAxis", 0.0))
	var vla_val = float(shot_data.get("VLA", 14.2))
	var smash_val = shot_data.get("SmashFactor", "")
	var aoa_val = shot_data.get("AttackAngle", shot_data.get("AngleOfAttack", ""))

	# Club & Lie Badge
	flow.add_child(_create_stat_card("CLUB & LIE", "%s (%s)" % [club_name, lie_str], Color(0.4, 0.85, 1.0)))
	# Carry
	flow.add_child(_create_stat_card("CARRY", "%.0f yds" % dist_val, Color(0.35, 0.95, 0.6)))
	# Ball Speed
	flow.add_child(_create_stat_card("BALL SPEED", "%.1f mph" % speed_val, Color(1.0, 0.85, 0.3)))
	# Spin Axis
	var axis_col = Color(0.4, 0.9, 1.0) if abs(axis_val) <= 4.0 else (Color(1.0, 0.7, 0.3) if abs(axis_val) <= 9.0 else Color(1.0, 0.4, 0.4))
	flow.add_child(_create_stat_card("SPIN AXIS", "%+.1f°" % axis_val, axis_col))
	# VLA (Launch Angle)
	flow.add_child(_create_stat_card("LAUNCH (VLA)", "%.1f°" % vla_val, Color(0.85, 0.75, 1.0)))
	# Smash Factor
	if str(smash_val) != "" and str(smash_val) != "---":
		var sf = float(smash_val)
		var sf_col = Color(0.35, 0.95, 0.6) if sf >= 1.45 else (Color(1.0, 0.8, 0.3) if sf >= 1.35 else Color(1.0, 0.4, 0.4))
		flow.add_child(_create_stat_card("SMASH", str(smash_val), sf_col))
	# AoA
	if str(aoa_val) != "" and str(aoa_val) != "---":
		flow.add_child(_create_stat_card("AOA", "%s°" % str(aoa_val), Color(0.7, 0.85, 1.0)))

	telem_panel.add_child(flow)
	return telem_panel


func _create_stat_card(title: String, val: String, val_color: Color = Color.WHITE) -> PanelContainer:
	var card = PanelContainer.new()
	var is_mob = _is_mobile_view()
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.04, 0.07, 0.11, 0.92)
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.border_width_left = 1
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.2, 0.35, 0.5, 0.8)
	card_style.content_margin_left = 10 if is_mob else 12
	card_style.content_margin_top = 6 if is_mob else 8
	card_style.content_margin_right = 10 if is_mob else 12
	card_style.content_margin_bottom = 6 if is_mob else 8
	card.add_theme_stylebox_override("panel", card_style)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)

	var t_lbl = Label.new()
	t_lbl.text = title.to_upper()
	t_lbl.add_theme_font_size_override("font_size", 11 if is_mob else 12)
	t_lbl.add_theme_color_override("font_color", Color(0.7, 0.82, 0.92))
	vb.add_child(t_lbl)

	var v_lbl = Label.new()
	v_lbl.text = val
	v_lbl.add_theme_font_size_override("font_size", 16 if is_mob else 17)
	v_lbl.add_theme_color_override("font_color", val_color)
	vb.add_child(v_lbl)

	card.add_child(vb)
	return card


func _create_empty_card() -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_mob = _is_mobile_view()
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.06, 0.14, 0.1, 0.95)
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_left = 10
	card_style.corner_radius_bottom_right = 10
	card_style.border_width_left = 3
	card_style.border_width_top = 1
	card_style.border_width_right = 1
	card_style.border_width_bottom = 1
	card_style.border_color = Color(0.2, 0.8, 0.4, 0.8)
	card_style.content_margin_left = 16
	card_style.content_margin_top = 14
	card_style.content_margin_right = 16
	card_style.content_margin_bottom = 14
	card.add_theme_stylebox_override("panel", card_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title = Label.new()
	title.text = "⛳ Solid Strike! No Major Swing Flaws Detected"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 16 if is_mob else 18)
	title.add_theme_color_override("font_color", Color(0.4, 0.95, 0.6))
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = "All launch monitor metrics (Smash Factor, Spin Axis, Launch Window) were within optimal benchmark ranges. Keep grooving this swing pattern!"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13 if is_mob else 14)
	desc.add_theme_color_override("font_color", Color(0.8, 0.9, 0.85))
	vbox.add_child(desc)

	card.add_child(vbox)
	return card


func _process(delta: float) -> void:
	if _is_suggestions_only:
		return
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
			_replay_feed_rect.material = null
			_replay_feed_rect.texture = ImageTexture.create_from_image(img)
			
		var lms: Dictionary = frame_data.get("landmarks", {})
		if _skeleton_overlay != null:
			if _is_analysis_complete and _skeleton_overlay.show_skeleton and not lms.is_empty():
				_skeleton_overlay._on_pose_detected(lms)
			else:
				_skeleton_overlay._on_pose_lost()
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


func _start_background_wireframe_analysis() -> void:
	if not is_inside_tree():
		await ready

	if _recorded_frames.is_empty():
		await get_tree().create_timer(0.4).timeout
		if not _analysis_cancelled and is_inside_tree():
			_on_analysis_finished()
		return

	# Sample wireframe keyframes every 250ms (0.25 seconds) = 4 per second
	var sample_interval: float = 0.25
	var num_frames: int = _recorded_frames.size()

	var sample_times: Array[float] = []
	var t: float = 0.0
	while t <= total_duration:
		sample_times.append(t)
		t += sample_interval
	if sample_times.is_empty() or abs(sample_times.back() - total_duration) > 0.05:
		sample_times.append(total_duration)

	var keyframe_indices: Array[int] = []
	for st in sample_times:
		var idx: int = clamp(int(round((st / total_duration) * (num_frames - 1))), 0, num_frames - 1)
		if not idx in keyframe_indices:
			keyframe_indices.append(idx)
	keyframe_indices.sort()

	var total_keyframes: int = keyframe_indices.size()
	var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")

	for i in range(total_keyframes):
		if _analysis_cancelled or not is_inside_tree():
			return

		var k_idx: int = keyframe_indices[i]
		var frame_data: Dictionary = _recorded_frames[k_idx]
		var img: Image = frame_data.get("image")

		# Update progress UI
		var pct: float = (float(i) / float(max(1, total_keyframes))) * 100.0
		if _analysis_progress_bar != null and is_instance_valid(_analysis_progress_bar):
			_analysis_progress_bar.value = pct
		if _analysis_status_lbl != null and is_instance_valid(_analysis_status_lbl):
			_analysis_status_lbl.text = "Analyzing skeleton kinematics... (%d of %d wireframes)" % [i + 1, total_keyframes]

		var landmarks: Dictionary = {}
		if bridge != null and bridge.has_method("detect_pose_for_image_async") and img != null and not img.is_empty():
			landmarks = await bridge.detect_pose_for_image_async(img)

		if _analysis_cancelled or not is_inside_tree():
			return

		frame_data["landmarks"] = landmarks
		frame_data["is_keyframe"] = true

		# Yield one frame so rendering loop and video playback stay buttery smooth
		await get_tree().process_frame

	if _analysis_cancelled or not is_inside_tree():
		return

	if _analysis_progress_bar != null and is_instance_valid(_analysis_progress_bar):
		_analysis_progress_bar.value = 100.0
	if _analysis_status_lbl != null and is_instance_valid(_analysis_status_lbl):
		_analysis_status_lbl.text = "Analysis complete! Correlating skeleton kinematics with ball flight..."

	# Smoothly interpolate intermediate frames between keyframes
	_interpolate_landmarks_between_keyframes(keyframe_indices)

	# Finalize analysis and switch replay loop to include wireframe skeleton & recommendations
	_on_analysis_finished()


func _interpolate_landmarks_between_keyframes(keyframe_indices: Array[int]) -> void:
	if keyframe_indices.is_empty() or _recorded_frames.is_empty():
		return

	var total_frames: int = _recorded_frames.size()

	# Propagate first keyframe to any preceding frames
	var first_k = keyframe_indices[0]
	var first_lms: Dictionary = _recorded_frames[first_k].get("landmarks", {})
	for f in range(0, first_k):
		_recorded_frames[f]["landmarks"] = first_lms.duplicate(true)

	# Interpolate between consecutive keyframes
	for i in range(keyframe_indices.size() - 1):
		var idx_a = keyframe_indices[i]
		var idx_b = keyframe_indices[i + 1]
		var lms_a: Dictionary = _recorded_frames[idx_a].get("landmarks", {})
		var lms_b: Dictionary = _recorded_frames[idx_b].get("landmarks", {})
		var span: int = idx_b - idx_a
		if span <= 1:
			continue

		for k in range(idx_a + 1, idx_b):
			var ratio: float = float(k - idx_a) / float(span)
			var interp_lms: Dictionary = {}

			var all_keys: Array = []
			for key in lms_a.keys():
				if not key in all_keys:
					all_keys.append(key)
			for key in lms_b.keys():
				if not key in all_keys:
					all_keys.append(key)

			for key in all_keys:
				var has_a = lms_a.has(key)
				var has_b = lms_b.has(key)
				if has_a and has_b:
					var a_x = float(lms_a[key].get("x", 0.0))
					var a_y = float(lms_a[key].get("y", 0.0))
					var a_z = float(lms_a[key].get("z", 0.0))
					var a_vis = float(lms_a[key].get("visibility", 1.0))
					var b_x = float(lms_b[key].get("x", 0.0))
					var b_y = float(lms_b[key].get("y", 0.0))
					var b_z = float(lms_b[key].get("z", 0.0))
					var b_vis = float(lms_b[key].get("visibility", 1.0))
					var mean_vis = lerp(a_vis, b_vis, ratio)
					interp_lms[key] = {
						"x": lerp(a_x, b_x, ratio),
						"y": lerp(a_y, b_y, ratio),
						"z": lerp(a_z, b_z, ratio),
						"visibility": mean_vis,
						"visible": mean_vis >= 0.25
					}
				elif has_a and ratio < 0.5:
					interp_lms[key] = lms_a[key].duplicate(true)
				elif has_b and ratio >= 0.5:
					interp_lms[key] = lms_b[key].duplicate(true)

			_recorded_frames[k]["landmarks"] = interp_lms

	# Propagate last keyframe to any succeeding frames
	var last_k = keyframe_indices.back()
	var last_lms: Dictionary = _recorded_frames[last_k].get("landmarks", {})
	for f in range(last_k + 1, total_frames):
		_recorded_frames[f]["landmarks"] = last_lms.duplicate(true)


func _on_analysis_finished() -> void:
	_is_analysis_complete = true

	# Remove loading progress panel
	if _analysis_loading_panel != null and is_instance_valid(_analysis_loading_panel):
		_analysis_loading_panel.queue_free()
		_analysis_loading_panel = null

	# Enable skeleton overlay
	if _skeleton_overlay != null:
		_skeleton_overlay.show_skeleton = true

	# Update skeleton toggle button
	if _skel_toggle_btn != null and is_instance_valid(_skel_toggle_btn):
		_skel_toggle_btn.disabled = false
		_skel_toggle_btn.text = "🦴 Skeleton: ON"
		_apply_btn_style(_skel_toggle_btn, Color(0.15, 0.45, 0.45))

	# Compute deep skeleton sequence analysis across all frames
	var fallback_telemetry := _get_combined_telemetry()
	var skeleton_analysis: Dictionary = GolfSwingAnalyzer.analyze_skeleton_sequence(_recorded_frames, fallback_telemetry)
	recommendations = GolfSwingAnalyzer.analyze_shot_unified(shot_data, skeleton_analysis)
	_refresh_recommendation_cards()
	_record_swing_recommendations()

	# Immediately update display with wireframe skeleton
	_update_playback_frame()


func _record_swing_recommendations() -> void:
	if recommendations.is_empty():
		return
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and mp_mgr.has_method("get_active_player"):
		var active_player = mp_mgr.get_active_player()
		var player_name = active_player.get("name", "Player 1") if not active_player.is_empty() else "Player 1"
		if mp_mgr.has_method("record_player_swing_issues"):
			mp_mgr.record_player_swing_issues(player_name, recommendations)


func _refresh_recommendation_cards() -> void:
	if _rec_vbox == null:
		return
	for c in _rec_vbox.get_children():
		c.queue_free()
	if recommendations.is_empty():
		var empty_card = _create_empty_card()
		_rec_vbox.add_child(empty_card)
	else:
		for rec in recommendations:
			var card = _create_recommendation_card(rec)
			_rec_vbox.add_child(card)
	if _mobile_tab_btn_recs != null and is_instance_valid(_mobile_tab_btn_recs):
		_mobile_tab_btn_recs.text = "🎯 Fixes & Data (%d)" % recommendations.size()


func _on_close_button_pressed() -> void:
	_analysis_cancelled = true
	emit_signal("closed")
	var p = get_parent()
	if p != null:
		p.remove_child(self)
	queue_free()

func _create_recommendation_card(rec: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_mob = _is_mobile_view()

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
	card_style.content_margin_left = 10 if is_mob else 12
	card_style.content_margin_top = 8 if is_mob else 10
	card_style.content_margin_right = 10 if is_mob else 12
	card_style.content_margin_bottom = 8 if is_mob else 10
	card.add_theme_stylebox_override("panel", card_style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var head_hbox = HBoxContainer.new()
	head_hbox.add_theme_constant_override("separation", 8)
	
	var badge_lbl = Label.new()
	badge_lbl.text = " #%d [%s PRIORITY] " % [priority_num, severity]
	badge_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 14)
	badge_lbl.add_theme_color_override("font_color", border_col)
	head_hbox.add_child(badge_lbl)

	var cat_lbl = Label.new()
	cat_lbl.text = "• " + str(rec.get("category", "SWING MECHANICS"))
	cat_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 14)
	cat_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	head_hbox.add_child(cat_lbl)
	vbox.add_child(head_hbox)

	var title_lbl = Label.new()
	title_lbl.text = str(rec.get("title", "Swing Flaw"))
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_lbl.add_theme_font_size_override("font_size", 17 if is_mob else 19)
	title_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title_lbl)

	var cam_flaw = str(rec.get("camera_flaw", ""))
	if not _is_suggestions_only and cam_flaw != "":
		var cam_lbl = Label.new()
		cam_lbl.text = "🦴 Camera Telemetry: " + cam_flaw
		cam_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cam_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 15)
		cam_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		vbox.add_child(cam_lbl)

	var launch_effect = str(rec.get("launch_effect", ""))
	if launch_effect != "":
		var launch_lbl = Label.new()
		launch_lbl.text = "⚡ Shot Result: " + launch_effect
		launch_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		launch_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 15)
		launch_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
		vbox.add_child(launch_lbl)

	# Benchmark Comparison Panel (Responsive chip layout)
	var comp_panel = PanelContainer.new()
	var comp_style = StyleBoxFlat.new()
	comp_style.bg_color = Color(0.04, 0.06, 0.09, 0.95)
	comp_style.corner_radius_top_left = 6
	comp_style.corner_radius_top_right = 6
	comp_style.corner_radius_bottom_left = 6
	comp_style.corner_radius_bottom_right = 6
	comp_style.content_margin_left = 12
	comp_style.content_margin_top = 8
	comp_style.content_margin_right = 12
	comp_style.content_margin_bottom = 8
	comp_panel.add_theme_stylebox_override("panel", comp_style)

	var comp_flow = HFlowContainer.new()
	comp_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comp_flow.add_theme_constant_override("h_separation", 16)
	comp_flow.add_theme_constant_override("v_separation", 4)

	var your_lbl = Label.new()
	your_lbl.text = "🔴 YOUR SHOT: %s" % str(rec.get("player_val", "---"))
	your_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 15)
	your_lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.65))
	comp_flow.add_child(your_lbl)

	var target_lbl = Label.new()
	target_lbl.text = "🟢 TARGET: %s" % str(rec.get("benchmark_val", "---"))
	target_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 15)
	target_lbl.add_theme_color_override("font_color", Color(0.5, 0.95, 0.65))
	comp_flow.add_child(target_lbl)

	comp_panel.add_child(comp_flow)
	vbox.add_child(comp_panel)

	var fix_lbl = Label.new()
	fix_lbl.text = "💡 How to Fix: " + str(rec.get("fix_instruction", ""))
	fix_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fix_lbl.add_theme_font_size_override("font_size", 14 if is_mob else 15)
	fix_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
	vbox.add_child(fix_lbl)

	var drill_str = str(rec.get("drill", ""))
	if drill_str != "":
		var drill_panel = PanelContainer.new()
		var drill_style = StyleBoxFlat.new()
		drill_style.bg_color = Color(0.09, 0.06, 0.14, 0.95)
		drill_style.corner_radius_top_left = 6
		drill_style.corner_radius_top_right = 6
		drill_style.corner_radius_bottom_left = 6
		drill_style.corner_radius_bottom_right = 6
		drill_style.border_width_left = 3
		drill_style.border_color = Color(0.7, 0.5, 0.9, 0.9)
		drill_style.content_margin_left = 12
		drill_style.content_margin_top = 8
		drill_style.content_margin_right = 12
		drill_style.content_margin_bottom = 8
		drill_panel.add_theme_stylebox_override("panel", drill_style)

		var drill_lbl = Label.new()
		drill_lbl.text = drill_str
		drill_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		drill_lbl.add_theme_font_size_override("font_size", 13 if is_mob else 14)
		drill_lbl.add_theme_color_override("font_color", Color(0.92, 0.82, 1.0))
		drill_panel.add_child(drill_lbl)
		vbox.add_child(drill_panel)

	card.add_child(vbox)
	return card

func _apply_btn_style(btn: Button, bg_col: Color) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_col
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_top = 6
	style.content_margin_right = 10
	style.content_margin_bottom = 6

	var hover_style = style.duplicate()
	hover_style.bg_color = bg_col.lightened(0.15)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = bg_col.darkened(0.15)

	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", style)
	btn.add_theme_color_override("font_color", Color.WHITE)
