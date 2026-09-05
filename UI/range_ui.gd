extends MarginContainer

signal rec_button_pressed
signal set_session(dir: String, player_name: String)

signal hit_shot(data)
signal manage_players_requested
signal skip_flight_requested


var _avg_carry: Label
var _avg_speed: Label
var _avg_spin: Label
var _avg_offline: Label
var _avg_target_diff: Label
var _prev_shot_popup: Panel
var _prev_shot_data_label: Label
var _last_shot_data: Dictionary = {}
var _averages_panel: PanelContainer = null
var _right_panel: VBoxContainer = null
var _home_btn: Button = null
var _exit_confirm_dialog: Control = null
var _hide_helpers_btn: Button = null
var _stats_btn: Button = null
var _map_btn: Button = null
var _skip_btn: Button = null
var _golfer_cam_panel: PanelContainer = null
var _camera_feed_rect: TextureRect = null
var _current_camera_feed_index: int = 0
var _camera_flip_btn: Button = null
var _phone_cam_url: String:
	get:
		return GlobalSettings.range_settings.phone_cam_url.value
	set(val):
		GlobalSettings.range_settings.phone_cam_url.set_value(val)
var _use_phone_stream: bool:
	get:
		return GlobalSettings.range_settings.use_phone_stream.value
	set(val):
		GlobalSettings.range_settings.use_phone_stream.set_value(val)
var _http_req: HTTPRequest = null
var _phone_cam_poll_timer: Timer = null
var _swing_frame_buffer: SwingFrameBuffer = null
var _saved_swing_frames: Array[Dictionary] = []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if has_node("OverlayLayer"):
		$OverlayLayer.layer = 100
	if has_node("SettingsLayer"):
		$SettingsLayer.layer = 105
	GlobalSettings.range_settings.shot_injector_enabled.setting_changed.connect(toggle_shot_injector)
	_setup_averages_ui()
	_setup_prev_shot_ui()
	_setup_golfer_camera_ui()
	
	if CameraServer.has_signal("camera_feed_added"):
		CameraServer.connect("camera_feed_added", func(_id):
			if is_golfer_camera_visible() and not _use_phone_stream:
				_update_camera_feed(true)
		)

	var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	if bridge != null:
		if bridge.has_signal("desktop_frame_received") and not bridge.desktop_frame_received.is_connected(_on_desktop_frame_received):
			bridge.desktop_frame_received.connect(_on_desktop_frame_received)

	$SessionPopUp.cancelled.connect(_on_session_pop_up_cancelled)

	var range_settings = get_node_or_null("SettingsLayer/Container/RangeSettings")
	if range_settings != null:
		if range_settings.has_signal("manage_players_requested"):
			range_settings.manage_players_requested.connect(func():
				emit_signal("manage_players_requested")
			)
	
	var is_course_play = true
	var parent = get_parent()
	if parent:
		var parent_name = parent.name.to_lower()
		var parent_path = parent.scene_file_path.to_lower()
		var parent_is_range = (parent_name == "range" or parent_path.contains("range.tscn"))
		if parent_is_range:
			is_course_play = false

	# Hide default SettingsButton from HBoxContainer
	var default_settings_btn = $HBoxContainer/SettingsButton
	if default_settings_btn != null:
		default_settings_btn.visible = false

	# Setup HBoxContainer mouse filters to prevent blocking settings clicks
	$HBoxContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HBoxContainer/PlayerName.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$HBoxContainer/PlayerName.add_theme_color_override("font_color", Color.WHITE)
	$HBoxContainer/PlayerName.add_theme_color_override("font_outline_color", Color.BLACK)
	$HBoxContainer/PlayerName.add_theme_constant_override("outline_size", 6)

	if not is_course_play:
		# Dynamically create Settings Button in the top-right corner, enlarged for touch
		var settings_btn = Button.new()
		settings_btn.name = "SettingsButton"
		settings_btn.text = ""
		settings_btn.tooltip_text = "Settings"
		settings_btn.icon = load("res://Utils/Settings/Gear.png")
		settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		settings_btn.custom_minimum_size = Vector2(64, 64)
		apply_circular_button_style(settings_btn, Color(0.15, 0.15, 0.15, 0.85))
		settings_btn.anchor_left = 1.0
		settings_btn.anchor_right = 1.0
		settings_btn.offset_left = -88
		settings_btn.offset_top = 20
		settings_btn.offset_right = -24
		settings_btn.offset_bottom = 84
		settings_btn.pressed.connect(_on_toggle_settings_requested)
		$OverlayLayer.add_child(settings_btn)

		# Home / Main Menu Button (Icon Only) - positioned between Settings and HideHelpers
		var home_btn = Button.new()
		home_btn.name = "HomeButton"
		home_btn.text = ""
		home_btn.tooltip_text = "Main Menu"
		if ResourceLoader.exists("res://assets/images/icons/home.svg"):
			home_btn.icon = load("res://assets/images/icons/home.svg")
		home_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		home_btn.custom_minimum_size = Vector2(64, 64)
		apply_circular_button_style(home_btn, Color(0.15, 0.15, 0.15, 0.85))
		home_btn.anchor_left = 1.0
		home_btn.anchor_right = 1.0
		home_btn.offset_left = -184
		home_btn.offset_top = 20
		home_btn.offset_right = -120
		home_btn.offset_bottom = 84
		home_btn.pressed.connect(_on_home_button_pressed)
		$OverlayLayer.add_child(home_btn)
		_home_btn = home_btn

		# Hide/Show Helpers Button (Icon Only) - positioned to the left of Home Button
		var hide_helpers_btn = Button.new()
		hide_helpers_btn.name = "HideHelpersButton"
		hide_helpers_btn.text = ""
		hide_helpers_btn.tooltip_text = "Toggle Helpers (Show/Hide)"
		if ResourceLoader.exists("res://assets/images/icons/helpers.svg"):
			hide_helpers_btn.icon = load("res://assets/images/icons/helpers.svg")
		hide_helpers_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hide_helpers_btn.custom_minimum_size = Vector2(64, 64)
		apply_circular_button_style(hide_helpers_btn, Color(0.15, 0.15, 0.15, 0.85))
		hide_helpers_btn.anchor_left = 1.0
		hide_helpers_btn.anchor_right = 1.0
		hide_helpers_btn.offset_left = -280
		hide_helpers_btn.offset_top = 20
		hide_helpers_btn.offset_right = -216
		hide_helpers_btn.offset_bottom = 84
		$OverlayLayer.add_child(hide_helpers_btn)
		_hide_helpers_btn = hide_helpers_btn

		# Dynamically create vertical RightPanel anchored to full screen height for scrolling - starts below ClubSelector
		var right_panel = VBoxContainer.new()
		right_panel.name = "RightPanel"
		right_panel.anchor_left = 1.0
		right_panel.anchor_right = 1.0
		right_panel.anchor_top = 0.0
		right_panel.anchor_bottom = 1.0
		right_panel.offset_left = -280
		right_panel.offset_top = 166
		right_panel.offset_right = -24
		right_panel.offset_bottom = -96
		right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right_panel.add_theme_constant_override("separation", 12)
		$OverlayLayer.add_child(right_panel)
		_right_panel = right_panel

		# ScrollContainer so buttons are always reachable on short screens - hidden by default!
		var toggles_scroll = ScrollContainer.new()
		toggles_scroll.name = "TogglesScroll"
		toggles_scroll.visible = false
		toggles_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		toggles_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		toggles_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		
		var toggles_container = VBoxContainer.new()
		toggles_container.name = "TogglesContainer"
		toggles_container.add_theme_constant_override("separation", 12)
		toggles_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		hide_helpers_btn.pressed.connect(func():
			toggles_scroll.visible = not toggles_scroll.visible
			if toggles_scroll.visible:
				apply_circular_button_style(hide_helpers_btn, Color(0.25, 0.45, 0.7, 0.9))
			else:
				apply_circular_button_style(hide_helpers_btn, Color(0.15, 0.15, 0.15, 0.85))
		)
		
		toggles_scroll.add_child(toggles_container)
		right_panel.add_child(toggles_scroll)

		# Announcer Mute/Unmute Toggle Button
		var announcer_btn = Button.new()
		announcer_btn.name = "AnnouncerToggleButton"
		var announcer_node = get_node_or_null("/root/AnnouncerEngine")
		var is_announcer_on = announcer_node.get("AnnouncerRange") if announcer_node != null else false
		announcer_btn.text = "🎙 Announcer: ON" if is_announcer_on else "🎙 Announcer: MUTED"
		announcer_btn.tooltip_text = "Toggle Announcer Commentary"
		announcer_btn.custom_minimum_size = Vector2(180, 56)
		var initial_ann_color = Color(0.2, 0.6, 0.3, 0.85) if is_announcer_on else Color(0.5, 0.5, 0.5, 0.85)
		apply_material_button_style(announcer_btn, initial_ann_color)
		announcer_btn.pressed.connect(func():
			var a = get_node_or_null("/root/AnnouncerEngine")
			if a != null:
				var current_val = a.get("AnnouncerRange") as bool
				var new_val = not current_val
				a.set("AnnouncerRange", new_val)
				GlobalSettings.save_settings()
				if new_val:
					announcer_btn.text = "🎙 Announcer: ON"
					apply_material_button_style(announcer_btn, Color(0.2, 0.6, 0.3, 0.85))
				else:
					announcer_btn.text = "🎙 Announcer: MUTED"
					apply_material_button_style(announcer_btn, Color(0.5, 0.5, 0.5, 0.85))
		)
		toggles_container.add_child(announcer_btn)
		
		# Suspense Heartbeat & Tunnel Vision Toggle Button
		var tension_btn = Button.new()
		tension_btn.name = "SuspenseToggleButton"
		var is_tension_on = GlobalSettings.range_settings.tension_effects_enabled.value if has_node("/root/GlobalSettings") else true
		tension_btn.text = "💓 Suspense: ON" if is_tension_on else "💓 Suspense: OFF"
		tension_btn.tooltip_text = "Toggle Suspense Heartbeat & Tunnel Vision in Course Play"
		tension_btn.custom_minimum_size = Vector2(180, 56)
		var initial_tension_color = Color(0.75, 0.2, 0.3, 0.85) if is_tension_on else Color(0.5, 0.5, 0.5, 0.85)
		apply_material_button_style(tension_btn, initial_tension_color)
		tension_btn.pressed.connect(func():
			if has_node("/root/GlobalSettings"):
				var new_val = not GlobalSettings.range_settings.tension_effects_enabled.value
				GlobalSettings.range_settings.tension_effects_enabled.value = new_val
				GlobalSettings.save_settings()
				if not new_val and has_node("/root/TensionManager"):
					TensionManager.stop_tension()
				if new_val:
					tension_btn.text = "💓 Suspense: ON"
					apply_material_button_style(tension_btn, Color(0.75, 0.2, 0.3, 0.85))
				else:
					tension_btn.text = "💓 Suspense: OFF"
					apply_material_button_style(tension_btn, Color(0.5, 0.5, 0.5, 0.85))
		)
		toggles_container.add_child(tension_btn)

		# Distance Menu Button
		var dist_btn = Button.new()
		dist_btn.name = "HitDistanceButton"
		dist_btn.text = "🎯 Hit Distance"
		dist_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(dist_btn, Color(0.6, 0.2, 0.6, 0.85))
		dist_btn.pressed.connect(func():
			var menu = null
			if _right_panel != null:
				menu = _right_panel.get_node_or_null("TogglesScroll/TogglesContainer/DistanceMenu")
				if not menu:
					menu = _right_panel.get_node_or_null("TogglesContainer/DistanceMenu")
			if not menu:
				menu = get_node_or_null("DistanceMenu")
			if menu:
				menu.visible = not menu.visible
				if menu.visible:
					var p = get_parent()
					if p and p.has_node("Player"):
						menu.current_ball_node = p.get_node("Player").get("ball")
					if p and "aim_target_pos" in p:
						menu.aim_target_node = p.get("aim_target_pos")
		)
		toggles_container.add_child(dist_btn)
		
		var distance_menu_script = load("res://UI/distance_menu.gd")
		var dist_menu = distance_menu_script.new()
		dist_menu.name = "DistanceMenu"
		dist_menu.visible = false
		dist_menu.inject_shot.connect(_on_shot_injector_inject)
		toggles_container.add_child(dist_menu)

		# Golfer Cam Toggle Button
		var golfer_cam_btn = Button.new()
		golfer_cam_btn.name = "GolferCamButton"
		golfer_cam_btn.text = "📹 Golfer Cam: OFF"
		golfer_cam_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(golfer_cam_btn, Color(0.2, 0.45, 0.45, 0.85))
		golfer_cam_btn.pressed.connect(func():
			var is_vis = not is_golfer_camera_visible()
			set_golfer_camera_visible(is_vis)
			if is_vis:
				golfer_cam_btn.text = "📹 Golfer Cam: ON"
				apply_material_button_style(golfer_cam_btn, Color(0.15, 0.6, 0.5, 0.85))
			else:
				golfer_cam_btn.text = "📹 Golfer Cam: OFF"
				apply_material_button_style(golfer_cam_btn, Color(0.2, 0.45, 0.45, 0.85))
		)
		toggles_container.add_child(golfer_cam_btn)

		# Shot Analysis Toggle Button
		var shot_analysis_btn = Button.new()
		shot_analysis_btn.name = "ShotAnalysisButton"
		var is_analysis_on = is_shot_analysis_enabled()
		shot_analysis_btn.text = "📊 Shot Analysis: ON" if is_analysis_on else "📊 Shot Analysis: OFF"
		shot_analysis_btn.tooltip_text = "Toggle Shot Suggestions & Flaw Analysis"
		shot_analysis_btn.custom_minimum_size = Vector2(180, 56)
		var initial_analysis_color = Color(0.15, 0.55, 0.75, 0.85) if is_analysis_on else Color(0.25, 0.35, 0.45, 0.85)
		apply_material_button_style(shot_analysis_btn, initial_analysis_color)
		shot_analysis_btn.pressed.connect(func():
			var new_val = not is_shot_analysis_enabled()
			set_shot_analysis_enabled(new_val)
			if has_node("/root/GlobalSettings"):
				GlobalSettings.save_settings()
			if new_val:
				shot_analysis_btn.text = "📊 Shot Analysis: ON"
				apply_material_button_style(shot_analysis_btn, Color(0.15, 0.55, 0.75, 0.85))
			else:
				shot_analysis_btn.text = "📊 Shot Analysis: OFF"
				apply_material_button_style(shot_analysis_btn, Color(0.25, 0.35, 0.45, 0.85))
		)
		toggles_container.add_child(shot_analysis_btn)

		# Position ClubSelector directly underneath SettingsButton and HideHelpersButton
		var club_sel = get_node_or_null("GridCanvas/ClubSelector")
		if club_sel != null:
			club_sel.reparent($OverlayLayer)
			club_sel.anchor_left = 1.0
			club_sel.anchor_right = 1.0
			club_sel.anchor_top = 0.0
			club_sel.anchor_bottom = 0.0
			club_sel.offset_left = -280
			club_sel.offset_top = 96
			club_sel.offset_right = -24
			club_sel.offset_bottom = 152
			club_sel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			club_sel.custom_minimum_size = Vector2(256, 56)
			club_sel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())

		# Dedicated Stats Button (Icon Only) - Bottom-Left Corner
		var stats_btn = Button.new()
		stats_btn.name = "StatsButton"
		stats_btn.text = ""
		stats_btn.tooltip_text = "Toggle Stats (Show/Hide)"
		if ResourceLoader.exists("res://assets/images/icons/stats.svg"):
			stats_btn.icon = load("res://assets/images/icons/stats.svg")
		stats_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_btn.custom_minimum_size = Vector2(64, 64)
		apply_circular_button_style(stats_btn, Color(0.24, 0.46, 0.72, 0.85)) # Blue
		stats_btn.anchor_left = 0.0
		stats_btn.anchor_right = 0.0
		stats_btn.anchor_top = 1.0
		stats_btn.anchor_bottom = 1.0
		stats_btn.offset_left = 30
		stats_btn.offset_top = -88
		stats_btn.offset_right = 94
		stats_btn.offset_bottom = -24
		stats_btn.pressed.connect(func():
			toggle_stats_visibility()
			if is_stats_visible():
				apply_circular_button_style(stats_btn, Color(0.24, 0.46, 0.72, 0.85))
			else:
				apply_circular_button_style(stats_btn, Color(0.15, 0.15, 0.15, 0.85))
		)
		$OverlayLayer.add_child(stats_btn)
		_stats_btn = stats_btn

		# Dedicated Map Toggle Button (Icon Only) - Bottom-Right Corner
		var map_btn = Button.new()
		map_btn.name = "MapButton"
		map_btn.text = ""
		map_btn.tooltip_text = "Toggle Map View"
		if ResourceLoader.exists("res://assets/images/icons/golf_course.svg"):
			map_btn.icon = load("res://assets/images/icons/golf_course.svg")
		map_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		map_btn.custom_minimum_size = Vector2(64, 64)
		apply_circular_button_style(map_btn, Color(0.18, 0.45, 0.25, 0.85)) # Forest green
		map_btn.anchor_left = 1.0
		map_btn.anchor_right = 1.0
		map_btn.anchor_top = 1.0
		map_btn.anchor_bottom = 1.0
		map_btn.offset_left = -94
		map_btn.offset_top = -88
		map_btn.offset_right = -30
		map_btn.offset_bottom = -24
		map_btn.pressed.connect(func():
			var p = get_parent()
			if p and p.has_method("_on_map_button_pressed"):
				p.call("_on_map_button_pressed")
		)
		$OverlayLayer.add_child(map_btn)
		_map_btn = map_btn
	else:
		$HBoxContainer.visible = false

	# Dynamically create Skip button in the top-middle of the screen
	_skip_btn = Button.new()
	_skip_btn.name = "SkipFlightButton"
	_skip_btn.text = "Skip"
	_skip_btn.custom_minimum_size = Vector2(160, 50)
	_skip_btn.visible = false
	apply_material_button_style(_skip_btn, Color(0.24, 0.46, 0.72, 0.85)) # Action blue
	
	# Position in the top middle of the screen
	_skip_btn.anchor_left = 0.5
	_skip_btn.anchor_right = 0.5
	_skip_btn.anchor_top = 0.0
	_skip_btn.anchor_bottom = 0.0
	# Center it horizontally using offsets, place below the 20-60 y-range badge:
	_skip_btn.offset_left = -80
	_skip_btn.offset_right = 80
	_skip_btn.offset_top = 70
	_skip_btn.offset_bottom = 120
	_skip_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skip_btn.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	_skip_btn.pressed.connect(func():
		emit_signal("skip_flight_requested")
	)
	$OverlayLayer.add_child(_skip_btn)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if is_golfer_camera_visible():
		if _camera_feed_rect != null and _camera_feed_rect.texture == null:
			if not _use_phone_stream and CameraServer.get_feed_count() > 0:
				_update_camera_feed(true)


func set_data(data: Dictionary, is_final_rest: bool = false) -> void:
	_last_shot_data = data.duplicate()
	var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true

	var grid = get_node_or_null("GridCanvas")
	if grid != null:
		for child in grid.get_children():
			if child.name == "ClubSelector":
				continue
			var stat_id = child.name
			var stat_def = StatDefinitions.get_stat_by_id(stat_id)
			if stat_def.is_empty():
				continue

			var u_str: String = str(stat_def.get("units_imperial" if is_imperial else "units_metric", ""))
			if child.has_method("set_units"):
				child.call("set_units", u_str)

			var val = data.get(stat_id, "---")
			if stat_id == "VLA" or stat_id == "HLA":
				val = _format_angle(val)
			if child.has_method("set_data"):
				child.call("set_data", str(val))
	
	# Only pop up shot analysis / swing replay at the END of the shot when the ball has settled
	if is_final_rest:
		if is_golfer_camera_visible() or is_shot_analysis_enabled():
			trigger_swing_replay_modal(data)


func on_ball_hit() -> void:
	if is_golfer_camera_visible() and _swing_frame_buffer != null:
		# Continue capturing for 1.2s to capture impact and follow-through, then save snapshot
		get_tree().create_timer(1.2).timeout.connect(func():
			if _swing_frame_buffer != null:
				_saved_swing_frames = _swing_frame_buffer.get_captured_frames()
		)


func trigger_swing_replay_modal(data: Dictionary) -> void:
	var cam_active: bool = is_golfer_camera_visible()
	var analysis_active: bool = is_shot_analysis_enabled()
	if not cam_active and not analysis_active:
		return

	# Strictly ensure the shot has completed and the ball has come to a rest
	var p_node = get_parent().get_node_or_null("Player") if get_parent() != null else null
	if p_node != null and p_node.get("ball") != null:
		var ball = p_node.ball
		if "state" in ball and ball.state != PhysicsEnums.BallState.REST:
			return

	# Only display after the ball flight happens and the ball comes to a rest (requires final Distance or Carry)
	var dist_str = str(data.get("Distance", data.get("Carry", data.get("TotalDistance", "---"))))
	var speed_str = str(data.get("Speed", data.get("BallSpeed", "---")))
	if dist_str == "---" or speed_str == "---":
		return
	if float(speed_str) <= 0.0 or float(dist_str) <= 0.0:
		return

	# Do not overwrite if replay modal is already open
	var existing = $OverlayLayer.get_node_or_null("SwingReplayModal")
	if existing != null:
		return

	var modal_script = load("res://UI/GolferCamera/swing_replay_modal.gd")
	if modal_script != null:
		var modal = modal_script.new()
		modal.name = "SwingReplayModal"
		$OverlayLayer.add_child(modal)
		var recorded_frames: Array[Dictionary] = []
		var is_suggestions_only: bool = not cam_active and analysis_active
		if not is_suggestions_only:
			if not _saved_swing_frames.is_empty():
				recorded_frames = _saved_swing_frames.duplicate()
				_saved_swing_frames.clear()
			elif _swing_frame_buffer != null:
				recorded_frames = _swing_frame_buffer.get_captured_frames()
		
		var modal_data: Dictionary = data.duplicate()
		var player_node = get_parent().get_node_or_null("Player") if get_parent() != null else null
		if not modal_data.has("Club") or str(modal_data["Club"]).is_empty():
			var club_sel = find_child("ClubSelector", true, false)
			if club_sel != null and "current_club" in club_sel and club_sel.current_club != null and not club_sel.current_club.text.is_empty():
				modal_data["Club"] = club_sel.current_club.text
			elif get_parent() != null and get_parent().has_method("_get_selected_club"):
				modal_data["Club"] = get_parent()._get_selected_club()
			elif player_node != null:
				if player_node.get("ball") != null and "current_selected_club" in player_node.ball:
					modal_data["Club"] = player_node.ball.current_selected_club

		if not modal_data.has("is_tee") or not modal_data.has("lie_type"):
			if player_node != null and player_node.get("ball") != null and "lie_type" in player_node.ball:
				var ball_lie = str(player_node.ball.lie_type)
				if not modal_data.has("lie_type"):
					modal_data["lie_type"] = ball_lie
				if not modal_data.has("is_tee"):
					modal_data["is_tee"] = (ball_lie.to_lower() == "teebox")
			else:
				if not modal_data.has("is_tee"):
					modal_data["is_tee"] = (str(modal_data.get("lie_type", "")).to_lower() == "teebox")
				if not modal_data.has("lie_type"):
					modal_data["lie_type"] = "teebox" if modal_data.get("is_tee", false) else "fairway"

		modal.setup_modal(modal_data, recorded_frames, is_suggestions_only)
		modal.closed.connect(func():
			_saved_swing_frames.clear()
		)


func _format_angle(value) -> String:
	# Accept both numeric values and placeholder strings (e.g., "---" after reset).
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return "%3.1f" % value
	return str(value)


func _on_rec_button_pressed() -> void:
	emit_signal("rec_button_pressed")


func _on_session_recorder_recording_state(value: bool) -> void:
	var rec_btn = get_node_or_null("HBoxContainer/RecButton")
	if value:
		if rec_btn != null:
			rec_btn.text = "🔴 REC: On"
			apply_material_button_style(rec_btn, Color(0.6, 0.15, 0.15, 0.85))
			rec_btn.tooltip_text = "Stop Recording Range Session"
		$SessionPopUp.open()
	else:
		if rec_btn != null:
			rec_btn.text = "REC: Off"
			apply_material_button_style(rec_btn, Color(0.2, 0.2, 0.2, 0.7))
			rec_btn.tooltip_text = "Start Recording Range Session"


func _on_session_pop_up_dir_selected(dir: String, player_name: String) -> void:
	$HBoxContainer/PlayerName.text = player_name
	emit_signal("set_session", dir, player_name)
	pass # Replace with function body.


func _on_session_pop_up_cancelled() -> void:
	# If setup was cancelled, emit the signal to toggle recording state off
	emit_signal("rec_button_pressed")



func _on_session_recorder_set_session(user: String, dir: String) -> void:
	$HBoxContainer/PlayerName.text = user
	$SessionPopUp.set_session_data(user, dir)


func _on_shot_injector_inject(data: Variant) -> void:
	emit_signal("hit_shot", data)

func toggle_shot_injector(value) -> void:
	$ShotInjector.visible = value


func _on_toggle_settings_requested() -> void:
	$SettingsLayer.visible = not $SettingsLayer.visible


func _on_close_settings_requested() -> void:
	$SettingsLayer.visible = false


func set_total_distance(text: String) -> void:
		$OverlayLayer/TotalDistanceOverlay.text = text
		$OverlayLayer/TotalDistanceOverlay.visible = true


func clear_total_distance() -> void:
		$OverlayLayer/TotalDistanceOverlay.visible = false
		$OverlayLayer/TotalDistanceOverlay.text = "Total Distance --"


func _setup_averages_ui() -> void:
	var averages_hbox = HBoxContainer.new()
	averages_hbox.name = "AveragesBar"
	averages_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	averages_hbox.add_theme_constant_override("separation", 20)
	
	_averages_panel = PanelContainer.new()
	_averages_panel.name = "AveragesPanel"
	_averages_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_averages_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	_averages_panel.custom_minimum_size = Vector2(0, 52)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.12, 0.15, 0.18, 0.85)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_color = Color(1.0, 1.0, 1.0, 0.15)
	panel_style.border_width_left = 1
	panel_style.border_width_right = 1
	panel_style.border_width_top = 1
	panel_style.border_width_bottom = 1
	panel_style.content_margin_left = 22
	panel_style.content_margin_right = 22
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	_averages_panel.add_theme_stylebox_override("panel", panel_style)
	
	_avg_carry = Label.new()
	_avg_carry.text = "Avg Carry: ---"
	_avg_carry.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avg_carry.add_theme_font_size_override("font_size", 15)
	averages_hbox.add_child(_avg_carry)
	
	_avg_speed = Label.new()
	_avg_speed.text = "Avg Speed: ---"
	_avg_speed.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avg_speed.add_theme_font_size_override("font_size", 15)
	averages_hbox.add_child(_avg_speed)
	
	_avg_spin = Label.new()
	_avg_spin.text = "Avg Spin: ---"
	_avg_spin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avg_spin.add_theme_font_size_override("font_size", 15)
	averages_hbox.add_child(_avg_spin)
	
	_avg_offline = Label.new()
	_avg_offline.text = "Avg Offline: ---"
	_avg_offline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avg_offline.add_theme_font_size_override("font_size", 15)
	averages_hbox.add_child(_avg_offline)
	
	_avg_target_diff = Label.new()
	_avg_target_diff.text = "Avg +/- Target: ---"
	_avg_target_diff.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avg_target_diff.add_theme_font_size_override("font_size", 15)
	averages_hbox.add_child(_avg_target_diff)
	
	var view_prev_btn = Button.new()
	view_prev_btn.text = "View Previous Shot"
	view_prev_btn.custom_minimum_size = Vector2(180, 48)
	view_prev_btn.add_theme_font_size_override("font_size", 15)
	apply_material_button_style(view_prev_btn, Color(0.25, 0.35, 0.45, 0.85))
	view_prev_btn.pressed.connect(_on_view_prev_shot_pressed)
	averages_hbox.add_child(view_prev_btn)
	
	_averages_panel.add_child(averages_hbox)
	add_child(_averages_panel)


func update_average_stats(avg_data: Dictionary) -> void:
	var u_label := "yds" if GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL else "m"
	var s_label := "mph" if GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL else "m/s"
	
	var carry = float(avg_data.get("Carry", 0.0))
	var speed = float(avg_data.get("Speed", 0.0))
	var spin = float(avg_data.get("Spin", 0.0))
	var offline = float(avg_data.get("Offline", 0.0))
	var target_diff = float(avg_data.get("TargetDiff", 0.0))
	
	if GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL:
		carry *= 1.09361
		offline *= 1.09361
		target_diff *= 1.09361
	else:
		speed *= 0.44704
	
	_avg_carry.text = "Avg Carry: %.1f %s" % [carry, u_label]
	_avg_speed.text = "Avg Speed: %.1f %s" % [speed, s_label]
	_avg_spin.text = "Avg Spin: %.0f rpm" % spin
	_avg_offline.text = "Avg Offline: %.1f %s" % [offline, u_label]
	
	if _avg_target_diff != null:
		var sign_char := "+" if target_diff >= 0.0 else ""
		_avg_target_diff.text = "Avg +/- Target: %s%.1f %s" % [sign_char, target_diff, u_label]


func reset_average_stats() -> void:
	_avg_carry.text = "Avg Carry: ---"
	_avg_speed.text = "Avg Speed: ---"
	_avg_spin.text = "Avg Spin: ---"
	_avg_offline.text = "Avg Offline: ---"
	if _avg_target_diff != null:
		_avg_target_diff.text = "Avg +/- Target: ---"


func _setup_prev_shot_ui() -> void:
	_prev_shot_popup = Panel.new()
	_prev_shot_popup.name = "PrevShotPopup"
	_prev_shot_popup.visible = false
	_prev_shot_popup.custom_minimum_size = Vector2(460, 420)
	_prev_shot_popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prev_shot_popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ThemeManager.apply_modal_style(_prev_shot_popup, 12)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16
	vbox.offset_top = 16
	vbox.offset_right = -16
	vbox.offset_bottom = -16
	
	var title = Label.new()
	title.text = "📊 Previous Shot Details"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(scroll, 24)
	
	_prev_shot_data_label = Label.new()
	_prev_shot_data_label.text = "No shot data recorded."
	_prev_shot_data_label.add_theme_font_size_override("font_size", 16)
	_prev_shot_data_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	_prev_shot_data_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prev_shot_data_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(_prev_shot_data_label)
	vbox.add_child(scroll)
	
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(140, 48)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ThemeManager.apply_primary_button_style(close_btn, 8)
	close_btn.pressed.connect(func(): _prev_shot_popup.visible = false)
	vbox.add_child(close_btn)
	
	_prev_shot_popup.add_child(vbox)
	add_child(_prev_shot_popup)


func _on_view_prev_shot_pressed() -> void:
	if _last_shot_data.is_empty():
		_prev_shot_data_label.text = "No shot recorded in this session yet."
	else:
		var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true
		var stats: Array[String] = []
		for stat_def in StatDefinitions.STATS:
			var id_str: String = str(stat_def.get("id", ""))
			if _last_shot_data.has(id_str):
				var name_str: String = str(stat_def.get("name", id_str))
				var u_str: String = str(stat_def.get("units_imperial" if is_imperial else "units_metric", ""))
				var val = _last_shot_data.get(id_str)
				if u_str != "" and u_str != "ratio":
					stats.append("• %s: %s %s" % [name_str, str(val), u_str])
				else:
					stats.append("• %s: %s" % [name_str, str(val)])
		
		if stats.is_empty():
			_prev_shot_data_label.text = "No shot recorded in this session yet."
		else:
			_prev_shot_data_label.text = "\n".join(stats)
	
	_prev_shot_popup.visible = true


func is_stats_visible() -> bool:
	var dist_panel = get_node_or_null("GridCanvas/Distance")
	return dist_panel.visible if dist_panel != null else true


func toggle_stats_visibility() -> void:
	var show_stats = not is_stats_visible()
	var grid = get_node_or_null("GridCanvas")
	if grid != null:
		for child in grid.get_children():
			if child.name != "ClubSelector":
				child.visible = show_stats
	if _averages_panel != null:
		_averages_panel.visible = show_stats


func apply_material_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8
	style_normal.border_width_left = 1
	style_normal.border_width_top = 1
	style_normal.border_width_right = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = bg_color.lightened(0.2)
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 12
	style_normal.content_margin_bottom = 12

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)
	style_hover.border_color = Color(1, 1, 1, 0.3)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)
	style_pressed.border_color = Color(1, 1, 1, 0.2)

	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.2, 0.2, 0.2, 0.4)
	style_disabled.border_color = Color(0.3, 0.3, 0.3, 0.3)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", 16)
	if btn.custom_minimum_size.y < 48:
		btn.custom_minimum_size.y = 48


func apply_circular_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 28 # Half of 56 height
	style_normal.corner_radius_top_right = 28
	style_normal.corner_radius_bottom_left = 28
	style_normal.corner_radius_bottom_right = 28
	style_normal.content_margin_left = 8
	style_normal.content_margin_right = 8
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)


func _on_home_button_pressed() -> void:
	var is_practice = false
	if has_node("/root/MultiplayerManager") and get_node("/root/MultiplayerManager").practice_mode_active:
		is_practice = true
	var parent = get_parent()
	if parent != null and parent.get("practice_mode_active") == true:
		is_practice = true
	var has_players = has_node("/root/MultiplayerManager") and not get_node("/root/MultiplayerManager").players.is_empty()

	if is_practice or has_players:
		_show_exit_confirm_dialog()
	else:
		SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")


func _show_exit_confirm_dialog() -> void:
	if _exit_confirm_dialog != null:
		_exit_confirm_dialog.visible = true
		return

	_exit_confirm_dialog = Control.new()
	_exit_confirm_dialog.name = "ExitConfirmDialog"
	_exit_confirm_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_exit_confirm_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_exit_confirm_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_exit_confirm_dialog.mouse_filter = Control.MOUSE_FILTER_STOP

	var exit_backdrop = ColorRect.new()
	exit_backdrop.name = "Backdrop"
	exit_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	exit_backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	exit_backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	exit_backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	exit_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_exit_confirm_dialog.visible = false
	)
	_exit_confirm_dialog.add_child(exit_backdrop)

	var exit_panel = PanelContainer.new()
	exit_panel.name = "ExitDialogPanel"
	exit_panel.anchor_left = 0.5
	exit_panel.anchor_right = 0.5
	exit_panel.anchor_top = 0.5
	exit_panel.anchor_bottom = 0.5
	exit_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	exit_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	exit_panel.offset_left = -250
	exit_panel.offset_right = 250
	exit_panel.offset_top = -115
	exit_panel.offset_bottom = 115

	var exit_style = StyleBoxFlat.new()
	exit_style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	exit_style.border_width_left = 2
	exit_style.border_width_top = 2
	exit_style.border_width_right = 2
	exit_style.border_width_bottom = 2
	exit_style.border_color = Color(0.35, 0.35, 0.35, 0.8)
	exit_style.corner_radius_top_left = 12
	exit_style.corner_radius_top_right = 12
	exit_style.corner_radius_bottom_left = 12
	exit_style.corner_radius_bottom_right = 12
	exit_style.content_margin_left = 28
	exit_style.content_margin_top = 24
	exit_style.content_margin_right = 28
	exit_style.content_margin_bottom = 24
	exit_panel.add_theme_stylebox_override("panel", exit_style)

	var exit_content_vbox = VBoxContainer.new()
	exit_content_vbox.add_theme_constant_override("separation", 20)

	var exit_title_lbl = Label.new()
	exit_title_lbl.text = "Exit Match"
	exit_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_title_lbl.add_theme_font_size_override("font_size", 28)
	exit_title_lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.4, 1.0))
	exit_title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	exit_title_lbl.add_theme_constant_override("outline_size", 4)
	exit_content_vbox.add_child(exit_title_lbl)

	var exit_msg_lbl = Label.new()
	exit_msg_lbl.text = "Are you sure you want to stop the match and return to the home screen?"
	exit_msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_msg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	exit_msg_lbl.custom_minimum_size = Vector2(400, 0)
	exit_msg_lbl.add_theme_font_size_override("font_size", 20)
	exit_msg_lbl.add_theme_color_override("font_color", Color.WHITE)
	exit_msg_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	exit_msg_lbl.add_theme_constant_override("outline_size", 4)
	exit_content_vbox.add_child(exit_msg_lbl)

	var exit_btn_hbox = HBoxContainer.new()
	exit_btn_hbox.add_theme_constant_override("separation", 24)
	exit_btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var exit_yes_btn = Button.new()
	exit_yes_btn.name = "YesButton"
	exit_yes_btn.text = "Yes"
	exit_yes_btn.custom_minimum_size = Vector2(140, 50)
	apply_material_button_style(exit_yes_btn, Color(0.65, 0.22, 0.22, 0.85))
	exit_yes_btn.pressed.connect(func():
		_exit_confirm_dialog.visible = false
		if has_node("/root/MultiplayerManager"):
			var mp = get_node("/root/MultiplayerManager")
			mp.players.clear()
			mp.practice_mode_active = false
		SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
	)
	exit_btn_hbox.add_child(exit_yes_btn)

	var exit_no_btn = Button.new()
	exit_no_btn.name = "NoButton"
	exit_no_btn.text = "No"
	exit_no_btn.custom_minimum_size = Vector2(140, 50)
	apply_material_button_style(exit_no_btn, Color(0.24, 0.46, 0.72, 0.85))
	exit_no_btn.pressed.connect(func():
		_exit_confirm_dialog.visible = false
	)
	exit_btn_hbox.add_child(exit_no_btn)

	exit_content_vbox.add_child(exit_btn_hbox)
	exit_panel.add_child(exit_content_vbox)
	_exit_confirm_dialog.add_child(exit_panel)
	$OverlayLayer.add_child(_exit_confirm_dialog)


func update_map_button_text(is_aerial: bool) -> void:
	var target_btn = _map_btn
	if target_btn == null and has_node("OverlayLayer/MapButton"):
		target_btn = $OverlayLayer/MapButton
	if target_btn != null:
		target_btn.text = ""
		if is_aerial:
			target_btn.tooltip_text = "Return to Player"
			apply_circular_button_style(target_btn, Color(0.2, 0.7, 0.35, 0.95))
		else:
			target_btn.tooltip_text = "Toggle Map View"
			apply_circular_button_style(target_btn, Color(0.18, 0.45, 0.25, 0.85))


func show_skip_button() -> void:
	if _skip_btn != null:
		_skip_btn.visible = true
		$OverlayLayer/TotalDistanceOverlay.visible = false


func hide_skip_button() -> void:
	if _skip_btn != null:
		_skip_btn.visible = false


func _setup_golfer_camera_ui() -> void:
	_golfer_cam_panel = PanelContainer.new()
	_golfer_cam_panel.name = "GolferCameraPanel"
	_golfer_cam_panel.visible = false
	_golfer_cam_panel.position = Vector2(30, 352)
	_golfer_cam_panel.custom_minimum_size = Vector2(332, 588)
	_golfer_cam_panel.size = Vector2(332, 588)
	_golfer_cam_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Glassmorphic card styling
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.2, 0.5, 0.7, 0.8)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 10
	_golfer_cam_panel.add_theme_stylebox_override("panel", panel_style)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Header bar
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 8)
	
	var title = Label.new()
	title.text = "📹 GOLFER CAM"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header.add_child(title)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Setup & Flip Camera Buttons
	var header_setup_btn = Button.new()
	header_setup_btn.name = "HeaderSetupButton"
	header_setup_btn.text = "⚙️ Setup"
	header_setup_btn.custom_minimum_size = Vector2(88, 48)
	apply_material_button_style(header_setup_btn, Color(0.2, 0.45, 0.65, 0.9))
	header_setup_btn.pressed.connect(_open_camera_setup_dialog)
	header.add_child(header_setup_btn)

	_camera_flip_btn = Button.new()
	_camera_flip_btn.name = "FlipCameraButton"
	_camera_flip_btn.text = "🔄 Flip"
	_camera_flip_btn.custom_minimum_size = Vector2(80, 48)
	apply_material_button_style(_camera_flip_btn, Color(0.2, 0.4, 0.6, 0.9))
	_camera_flip_btn.pressed.connect(_on_flip_camera_pressed)
	header.add_child(_camera_flip_btn)
	
	var status_dot = Label.new()
	status_dot.text = "🔴 LIVE"
	status_dot.add_theme_font_size_override("font_size", 14)
	status_dot.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
	header.add_child(status_dot)
	
	main_vbox.add_child(header)

	# Feed Container (Viewport / Texture)
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

	# Stick Skeleton & Golf Club Path Overlay
	if _swing_frame_buffer == null:
		_swing_frame_buffer = SwingFrameBuffer.new()
		_swing_frame_buffer.name = "SwingFrameBuffer"
		add_child(_swing_frame_buffer)

	var skel_overlay_script = load("res://UI/GolferCamera/golfer_skeleton_overlay.gd")
	if skel_overlay_script != null:
		var live_skel = skel_overlay_script.new()
		live_skel.name = "LiveGolferSkeletonOverlay"
		live_skel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		live_skel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		live_skel.frame_buffer = _swing_frame_buffer
		feed_container.add_child(live_skel)

	# Overlay UI for Disconnected Feed Status
	var overlay_vbox = VBoxContainer.new()
	overlay_vbox.name = "OverlayStatusVBox"
	overlay_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overlay_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	overlay_vbox.mouse_filter = Control.MOUSE_FILTER_PASS

	var feed_label = Label.new()
	feed_label.name = "FeedStatusLabel"
	feed_label.text = "GOLFER CAMERA FEED\n[ Click ⚙️ Setup to connect ]"
	feed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	feed_label.add_theme_font_size_override("font_size", 14)
	feed_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.85))
	overlay_vbox.add_child(feed_label)

	var setup_btn = Button.new()
	setup_btn.name = "SetupCameraButton"
	setup_btn.text = "⚙️ Connect Camera"
	setup_btn.custom_minimum_size = Vector2(160, 38)
	setup_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apply_material_button_style(setup_btn, Color(0.2, 0.45, 0.65, 0.9))
	setup_btn.pressed.connect(_open_camera_setup_dialog)
	overlay_vbox.add_child(setup_btn)

	feed_container.add_child(overlay_vbox)
	main_vbox.add_child(feed_container)

	# Footer info
	var footer = Label.new()
	footer.text = "Position camera behind ball facing target line"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	main_vbox.add_child(footer)

	_golfer_cam_panel.add_child(main_vbox)
	$OverlayLayer.add_child(_golfer_cam_panel)


func set_golfer_camera_visible(enabled: bool) -> void:
	if _golfer_cam_panel != null:
		_golfer_cam_panel.visible = enabled
		_update_camera_feed(enabled)
	
	var grid = get_node_or_null("GridCanvas")
	if grid != null:
		if grid.has_method("set_golfer_camera_active"):
			grid.call("set_golfer_camera_active", enabled)
		else:
			grid.position.x = 350.0 if enabled else 0.0


func is_golfer_camera_visible() -> bool:
	return _golfer_cam_panel.visible if _golfer_cam_panel != null else false


func is_shot_analysis_enabled() -> bool:
	if has_node("/root/GlobalSettings"):
		return GlobalSettings.range_settings.shot_analysis_enabled.value
	return false


func set_shot_analysis_enabled(enabled: bool) -> void:
	if has_node("/root/GlobalSettings"):
		GlobalSettings.range_settings.shot_analysis_enabled.value = enabled
	var btn = find_child("ShotAnalysisButton", true, false)
	if btn is Button:
		btn.text = "📊 Shot Analysis: ON" if enabled else "📊 Shot Analysis: OFF"
		apply_material_button_style(btn, Color(0.15, 0.55, 0.75, 0.85) if enabled else Color(0.25, 0.35, 0.45, 0.85))



func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if is_golfer_camera_visible() and not _use_phone_stream:
			_update_camera_feed(true)


func _on_desktop_frame_received(_img: Image, tex: Texture2D, _landmarks: Dictionary) -> void:
	if is_golfer_camera_visible() and not _use_phone_stream:
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = tex
		_update_status_overlay("", false)


func _update_camera_feed(active: bool) -> void:
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	if pose_bridge != null and pose_bridge.has_method("stop_desktop_camera"):
		pose_bridge.stop_desktop_camera()

	if not active:
		CameraServer.set_monitoring_feeds(false)
		var feeds = CameraServer.feeds()
		for feed in feeds:
			if feed != null:
				feed.feed_is_active = false
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = null
		_update_status_overlay("GOLFER CAMERA FEED\n[ Click ⚙️ Setup to connect ]", true)
		return

	# Request permission on mobile OS if needed
	if OS.has_feature("android") or OS.has_feature("ios"):
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
			# Re-check after user grants permission
			get_tree().create_timer(1.5).timeout.connect(func():
				if is_golfer_camera_visible():
					_update_camera_feed(true)
			)
			return

	CameraServer.set_monitoring_feeds(true)

	if _use_phone_stream and not _phone_cam_url.is_empty():
		_start_phone_camera_stream(_phone_cam_url)
		return

	var feeds = CameraServer.feeds()
	var count = feeds.size()

	if count > 0:
		var selected_index = _find_default_camera_index(feeds)
		_current_camera_feed_index = selected_index
		_activate_camera_feed_index(selected_index)
	elif pose_bridge != null and "desktop_cameras" in pose_bridge and pose_bridge.desktop_cameras.size() > 0:
		var sel_idx = clamp(_current_camera_feed_index, 0, pose_bridge.desktop_cameras.size() - 1)
		_current_camera_feed_index = sel_idx
		pose_bridge.select_desktop_camera(sel_idx)
		_update_status_overlay("", false)
	else:
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = null
		_update_status_overlay("SEARCHING FOR WEBCAMS...\n[ Click ⚙️ Connect Camera for setup ]", true)
		if pose_bridge != null and pose_bridge.has_method("fetch_desktop_cameras"):
			pose_bridge.fetch_desktop_cameras()
		# Schedule asynchronous re-scan
		get_tree().create_timer(0.6).timeout.connect(func():
			if is_golfer_camera_visible() and not _use_phone_stream:
				var rescan_feeds = CameraServer.feeds()
				if rescan_feeds.size() > 0:
					var sel_idx = _find_default_camera_index(rescan_feeds)
					_current_camera_feed_index = sel_idx
					_activate_camera_feed_index(sel_idx)
				elif pose_bridge != null and "desktop_cameras" in pose_bridge and pose_bridge.desktop_cameras.size() > 0:
					var sel_idx = clamp(_current_camera_feed_index, 0, pose_bridge.desktop_cameras.size() - 1)
					_current_camera_feed_index = sel_idx
					pose_bridge.select_desktop_camera(sel_idx)
					_update_status_overlay("", false)
				elif _phone_cam_url.is_empty():
					_update_status_overlay("NO LOCAL WEBCAM DETECTED\n[ Click ⚙️ Connect Camera for Phone WiFi Stream ]", true)
		)


func _update_status_overlay(msg: String, is_visible: bool) -> void:
	if _golfer_cam_panel == null:
		return
	var status_vbox = _golfer_cam_panel.find_child("OverlayStatusVBox", true, false)
	if status_vbox != null:
		status_vbox.visible = is_visible
	var label = _golfer_cam_panel.find_child("FeedStatusLabel", true, false)
	if label != null and not msg.is_empty():
		label.text = msg


func _find_default_camera_index(feeds: Array = []) -> int:
	if feeds.is_empty():
		feeds = CameraServer.feeds()
	for i in range(feeds.size()):
		var feed = feeds[i]
		if feed != null and feed.get_position() == CameraFeed.FEED_BACK:
			return i
	return 0


func _activate_camera_feed_index(index: int) -> void:
	var feeds = CameraServer.feeds()
	if index < 0 or index >= feeds.size():
		var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
		if pose_bridge != null and "desktop_cameras" in pose_bridge and index >= 0 and index < pose_bridge.desktop_cameras.size():
			pose_bridge.select_desktop_camera(index)
			_update_status_overlay("", false)
			return
		
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = null
		_update_status_overlay("NO LOCAL WEBCAM DETECTED\n[ Click ⚙️ Connect Camera for Phone WiFi Stream ]", true)
		return
	
	var feed = feeds[index]
	if feed != null:
		feed.feed_is_active = true
		var cam_tex = CameraTexture.new()
		cam_tex.camera_feed_id = feed.get_id()
		cam_tex.camera_is_active = true
		if _camera_feed_rect != null:
			_camera_feed_rect.texture = cam_tex
		
		_update_status_overlay("", false)


func _on_flip_camera_pressed() -> void:
	if _use_phone_stream:
		_use_phone_stream = false
	
	var feeds = CameraServer.feeds()
	var count = feeds.size()
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	var desk_cams: Array = pose_bridge.desktop_cameras if (pose_bridge != null and "desktop_cameras" in pose_bridge) else []

	if count > 1:
		if _current_camera_feed_index < count:
			var current_feed = feeds[_current_camera_feed_index]
			if current_feed != null:
				current_feed.feed_is_active = false
		_current_camera_feed_index = (_current_camera_feed_index + 1) % count
		_activate_camera_feed_index(_current_camera_feed_index)
	elif desk_cams.size() > 1:
		_current_camera_feed_index = (_current_camera_feed_index + 1) % desk_cams.size()
		pose_bridge.select_desktop_camera(_current_camera_feed_index)
		_update_status_overlay("", false)
	elif count == 1:
		_activate_camera_feed_index(0)
	elif desk_cams.size() == 1:
		pose_bridge.select_desktop_camera(0)
		_update_status_overlay("", false)
	else:
		_open_camera_setup_dialog()


func _open_camera_setup_dialog() -> void:
	CameraServer.set_monitoring_feeds(true)
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	if pose_bridge != null and pose_bridge.has_method("fetch_desktop_cameras"):
		pose_bridge.fetch_desktop_cameras()

	var existing = $OverlayLayer.get_node_or_null("CameraSetupDialog")
	if existing != null:
		existing.queue_free()

	var popup = PanelContainer.new()
	popup.name = "CameraSetupDialog"
	popup.z_index = 100
	popup.custom_minimum_size = Vector2(500, 440)
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	popup.anchor_left = 0.5
	popup.anchor_top = 0.5
	popup.anchor_right = 0.5
	popup.anchor_bottom = 0.5
	popup.offset_left = -250
	popup.offset_top = -220
	popup.offset_right = 250
	popup.offset_bottom = 220

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 0.96)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
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
	vbox.add_theme_constant_override("separation", 12)

	var title = Label.new()
	title.text = "📷 Golfer Camera Setup"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(title)

	# Section 1: System / Built-in Webcams
	var webcams_label = Label.new()
	webcams_label.text = "1. Local / Built-in Webcams (Scanning...):"
	webcams_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(webcams_label)

	var cam_option = OptionButton.new()
	cam_option.name = "CameraFeedOptionButton"
	cam_option.custom_minimum_size = Vector2(0, 36)
	cam_option.add_item("Scanning for webcams...", 0)
	cam_option.disabled = true
	vbox.add_child(cam_option)

	var populate_feeds = func():
		var feeds = CameraServer.feeds()
		var desk_cams: Array = pose_bridge.desktop_cameras if (pose_bridge != null and "desktop_cameras" in pose_bridge) else []
		var total_count = max(feeds.size(), desk_cams.size())
		
		webcams_label.text = "1. Local / Built-in Webcams (%d detected):" % total_count
		cam_option.clear()
		
		if feeds.size() > 0:
			cam_option.disabled = false
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
			cam_option.disabled = false
			for i in range(desk_cams.size()):
				var cam_info = desk_cams[i]
				var c_name: String = cam_info.get("name", "System Camera %d" % i)
				cam_option.add_item(c_name, i)
			cam_option.select(clamp(_current_camera_feed_index, 0, desk_cams.size() - 1))
		else:
			cam_option.add_item("No local webcams detected", 0)
			cam_option.disabled = true

	# Populate immediately and schedule polling scans
	populate_feeds.call()

	if pose_bridge != null and pose_bridge.has_signal("desktop_cameras_updated"):
		pose_bridge.desktop_cameras_updated.connect(func(_cams):
			populate_feeds.call()
		)

	var scan_timer = Timer.new()
	scan_timer.name = "WebcamScanTimer"
	scan_timer.wait_time = 0.3
	scan_timer.autostart = true
	popup.add_child(scan_timer)
	scan_timer.timeout.connect(populate_feeds)

	var cam_btn_hbox = HBoxContainer.new()
	cam_btn_hbox.add_theme_constant_override("separation", 8)

	var connect_local_btn = Button.new()
	connect_local_btn.text = "📹 Connect Selected Local Camera"
	connect_local_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_local_btn.custom_minimum_size = Vector2(0, 36)
	apply_material_button_style(connect_local_btn, Color(0.24, 0.46, 0.72, 0.9))
	connect_local_btn.pressed.connect(func():
		_use_phone_stream = false
		var sel_idx = cam_option.get_selected_id()
		_current_camera_feed_index = sel_idx
		var feeds = CameraServer.feeds()
		if feeds.size() > 0:
			_activate_camera_feed_index(sel_idx)
		else:
			if pose_bridge != null and pose_bridge.has_method("select_desktop_camera"):
				pose_bridge.select_desktop_camera(sel_idx)
				_update_status_overlay("", false)
		popup.queue_free()
	)
	cam_btn_hbox.add_child(connect_local_btn)

	var rescan_btn = Button.new()
	rescan_btn.text = "🔄 Rescan"
	rescan_btn.custom_minimum_size = Vector2(80, 36)
	apply_material_button_style(rescan_btn, Color(0.3, 0.35, 0.45, 0.9))
	rescan_btn.pressed.connect(func():
		CameraServer.set_monitoring_feeds(true)
		if pose_bridge != null and pose_bridge.has_method("fetch_desktop_cameras"):
			pose_bridge.fetch_desktop_cameras()
		populate_feeds.call()
	)
	cam_btn_hbox.add_child(rescan_btn)
	vbox.add_child(cam_btn_hbox)

	var msg_label = Label.new()
	msg_label.name = "WebcamStatusMsg"
	msg_label.text = ""
	msg_label.add_theme_font_size_override("font_size", 11)
	msg_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	vbox.add_child(msg_label)

	# Section 2: Wireless Phone IP Stream
	var phone_label = Label.new()
	phone_label.text = "2. Phone Camera via WiFi / IP Stream (DroidCam / IP Webcam):"
	phone_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(phone_label)

	var ip_input = LineEdit.new()
	ip_input.placeholder_text = "e.g. 192.168.1.100:8080 or 192.168.1.100:4747"
	ip_input.text = _phone_cam_url
	ip_input.custom_minimum_size = Vector2(0, 36)
	vbox.add_child(ip_input)

	var connect_phone_btn = Button.new()
	connect_phone_btn.text = "📡 Connect Phone Stream"
	connect_phone_btn.custom_minimum_size = Vector2(0, 36)
	apply_material_button_style(connect_phone_btn, Color(0.2, 0.6, 0.4, 0.9))
	connect_phone_btn.pressed.connect(func():
		var local_feeds = CameraServer.feeds()
		for feed in local_feeds:
			if feed != null:
				feed.feed_is_active = false
		if pose_bridge != null and pose_bridge.has_method("stop_desktop_camera"):
			pose_bridge.stop_desktop_camera()
		_use_phone_stream = true
		_start_phone_camera_stream(ip_input.text)
		popup.queue_free()
	)
	vbox.add_child(connect_phone_btn)

	# On Android, show local MediaPipe AI status badge if native plugin is detected
	if Engine.has_singleton("MediaPipePosePlugin"):
		var ai_status_label = Label.new()
		ai_status_label.text = "⚡ On-Device MediaPipe AI Active (100% Mobile GPU Accelerated)"
		ai_status_label.add_theme_font_size_override("font_size", 12)
		ai_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		ai_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(ai_status_label)

	var close_btn = Button.new()
	close_btn.text = "Close Setup"
	close_btn.custom_minimum_size = Vector2(0, 36)
	apply_material_button_style(close_btn, Color(0.4, 0.4, 0.4, 0.8))
	close_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close_btn)

	popup.add_child(vbox)
	$OverlayLayer.add_child(popup)


var _phone_stream_failed_count: int = 0
var _is_requesting_frame: bool = false
var _alt_endpoint_idx: int = 0
var _stream_established: bool = false

func _start_phone_camera_stream(url_str: String) -> void:
	_phone_cam_url = _normalize_phone_url(url_str)
	if _phone_cam_url.is_empty():
		_update_status_overlay("INVALID PHONE STREAM URL\n[ Enter IP e.g. 192.168.1.100:8080 ]", true)
		return

	_alt_endpoint_idx = 0
	_stream_established = false
	_phone_stream_failed_count = 0

	# Notify PoseDetectionBridge of host IP for remote MediaPipe AI tracking
	var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_tree().root.get_node_or_null("PoseDetectionBridge")
	if bridge != null and bridge.has_method("set_remote_server_ip"):
		var host_ip = _phone_cam_url.trim_prefix("http://").trim_prefix("https://").trim_prefix("http:/").trim_prefix("https:/").split(":")[0].split("/")[0]
		if not host_ip.is_empty():
			bridge.set_remote_server_ip(host_ip)

	# Reset texture so uninitialized/broken textures are removed
	if _camera_feed_rect != null and not (_camera_feed_rect.texture is ImageTexture):
		_camera_feed_rect.texture = null

	_update_status_overlay("CONNECTING TO PHONE STREAM...\n" + _phone_cam_url, true)

	if _http_req == null:
		_http_req = HTTPRequest.new()
		_http_req.name = "PhoneCameraHTTPRequest"
		_http_req.timeout = 3.0
		_http_req.request_completed.connect(_on_phone_cam_frame_received)
		add_child(_http_req)

	_is_requesting_frame = false
	_request_next_phone_frame()


func _normalize_phone_url(raw_url: String) -> String:
	var trimmed = raw_url.strip_edges()
	if trimmed.is_empty():
		return ""
	
	var scheme = "http://"
	if trimmed.begins_with("https://") or trimmed.begins_with("https:/"):
		scheme = "https://"
	
	# Strip any existing scheme prefix (http://, http:/, http:, https://, https:/, https:)
	var cleaned = trimmed
	if cleaned.begins_with("https://"):
		cleaned = cleaned.substr(8)
	elif cleaned.begins_with("https:/"):
		cleaned = cleaned.substr(7)
	elif cleaned.begins_with("https:"):
		cleaned = cleaned.substr(6)
	elif cleaned.begins_with("http://"):
		cleaned = cleaned.substr(7)
	elif cleaned.begins_with("http:/"):
		cleaned = cleaned.substr(6)
	elif cleaned.begins_with("http:"):
		cleaned = cleaned.substr(5)
	
	while cleaned.begins_with("/"):
		cleaned = cleaned.substr(1)
	
	if cleaned.is_empty():
		return ""
	
	# Replace continuous stream endpoints (/video, /mjpeg, /mjpegfeed) with single-frame snapshot endpoints
	# because HTTPRequest waits for EOF before emitting request_completed
	if cleaned.ends_with("/video") or cleaned.ends_with("/mjpeg") or cleaned.ends_with("/mjpegfeed"):
		if cleaned.contains(":4747"):
			cleaned = cleaned.get_base_dir() + "/cam/1/frame.jpg"
		else:
			cleaned = cleaned.get_base_dir() + "/shot.jpg"
	
	var final_url = scheme + cleaned
	
	var has_extension = final_url.ends_with(".jpg") or final_url.ends_with(".jpeg") or final_url.ends_with(".png")
	var has_known_path = final_url.contains("/shot.jpg") or final_url.contains("/oneshot.jpg") or final_url.contains("/cam/1/") or final_url.contains("/photo.jpg") or final_url.contains("/snapshot")
	
	if not has_extension and not has_known_path:
		if final_url.contains(":4747"):
			if not final_url.ends_with("/"):
				final_url += "/"
			final_url += "cam/1/frame.jpg"
		else:
			if not final_url.ends_with("/"):
				final_url += "/"
			final_url += "shot.jpg"
			
	return final_url


func _request_next_phone_frame() -> void:
	if not is_golfer_camera_visible() or _phone_cam_url.is_empty() or _http_req == null or _is_requesting_frame:
		return

	_is_requesting_frame = true
	var headers = PackedStringArray([
		"User-Agent: HeckleGolfSim/1.0",
		"Accept: image/jpeg, image/*, */*",
		"Connection: close"
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
			var tex = ImageTexture.create_from_image(img)
			if _camera_feed_rect != null:
				_camera_feed_rect.texture = tex
			_update_status_overlay("", false)
		else:
			_try_fallback_endpoint_or_error(result, response_code, "Invalid image encoding received")
	else:
		_try_fallback_endpoint_or_error(result, response_code, "")

	if is_golfer_camera_visible() and not _phone_cam_url.is_empty():
		var delay = 0.033 if _phone_stream_failed_count == 0 else clamp(0.4 * _phone_stream_failed_count, 0.4, 2.0)
		get_tree().create_timer(delay).timeout.connect(_request_next_phone_frame)


func _try_fallback_endpoint_or_error(result: int, response_code: int, custom_msg: String) -> void:
	# If stream was already established, DO NOT mutate URL to alternate endpoints on transient WiFi hiccups!
	if _stream_established:
		_handle_phone_stream_error(result, response_code, custom_msg)
		return

	# Try alternative snapshot endpoints ONLY during initial connection setup
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
		err_detail = "Cannot connect to " + _phone_cam_url + "\nVerify phone IP in app & check phone & laptop are on same WiFi network"
	elif result == HTTPRequest.RESULT_TIMEOUT:
		err_detail = "Connection timed out connecting to " + _phone_cam_url
	elif response_code == 404:
		err_detail = "404 Not Found at " + _phone_cam_url + "\nCheck stream path/port in phone camera app (IP Webcam: 8080, DroidCam: 4747)"
	elif response_code > 0:
		err_detail = "HTTP Error %d from phone camera stream" % response_code
	else:
		err_detail = "Failed to connect to phone stream (Result: %d)" % result

	var max_allowed_failures = 10 if _stream_established else 2
	if _phone_stream_failed_count >= max_allowed_failures:
		if _camera_feed_rect != null and not (_camera_feed_rect.texture is ImageTexture):
			_camera_feed_rect.texture = null
		_update_status_overlay("📡 PHONE STREAM DISCONNECTED\n" + err_detail + "\n[ Click ⚙️ Setup to reconfigure ]", true)
