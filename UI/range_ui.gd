extends MarginContainer

signal rec_button_pressed
signal set_session(dir: String, player_name: String)

signal hit_shot(data)
signal manage_players_requested
signal skip_flight_requested
signal stats_visibility_changed(is_visible: bool)
signal golfer_cam_modal_state_changed(is_open: bool)
signal golfer_cam_enabled_changed(is_enabled: bool)
signal putting_cam_enabled_changed(is_enabled: bool)
signal player_profile_changed(player_name: String)


var _avg_carry: Label
var _avg_speed: Label
var _avg_spin: Label
var _avg_offline: Label
var _avg_target_diff: Label
var _prev_shot_popup: Panel
var _prev_shot_data_label: Label
var _last_shot_data: Dictionary = {}
var _averages_panel: PanelContainer = null
var _profile_option: OptionButton = null
var _prev_shot_btn: Button = null
var _detached_window: Window = null
var _detached_modal: Control = null
var _right_panel: VBoxContainer = null
var _home_btn: Button = null
var _exit_confirm_dialog: Control = null
var _hide_helpers_btn: Button = null
var _stats_btn: Button = null
var _map_btn: Button = null
var _skip_btn: Button = null
var _announcer_btn: Button = null
var _tension_btn: Button = null
var _dist_btn: Button = null
var _golfer_cam_btn: Button = null
var _putting_cam_btn: Button = null
var _shot_analysis_btn: Button = null
var _golfer_cam_panel: PanelContainer = null
var _camera_feed_rect: TextureRect = null
var _current_camera_feed_index: int = 0
var _camera_flip_btn: Button = null
var _camera_minimize_btn: Button = null
var _camera_restore_pill: Button = null
var _is_golfer_cam_enabled: bool = false
var _is_golfer_cam_minimized: bool = false
var _is_putting_cam_enabled: bool = false
var _is_putting_cam_minimized: bool = false
var _current_selected_club: String = ""
var _putting_overlay: Control = null
var _putting_state_machine: Node = null
var _camera_rotate_btn: Button = null
var _camera_rotation_deg: int:
	get:
		if has_node("/root/GlobalSettings"):
			return int(GlobalSettings.range_settings.putting_camera_rotation.value)
		return 0
	set(val):
		if has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.putting_camera_rotation.set_value(val % 360)
			GlobalSettings.save_settings()
var _stats_were_visible_before_cam: bool = true
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
	if has_node("/root/GlobalSettings") and "range_settings" in GlobalSettings and "shot_analysis_enabled" in GlobalSettings.range_settings:
		GlobalSettings.range_settings.shot_analysis_enabled.setting_changed.connect(func(_val = null):
			_update_prev_shot_analysis_visibility()
		)
	_setup_averages_ui()
	_setup_prev_shot_ui()
	_setup_golfer_camera_ui()
	_setup_profile_selector()
	
	var eb = _get_autoload("EventBus")
	if eb != null and eb.has_signal("club_selected"):
		if not eb.is_connected("club_selected", Callable(self, "_on_club_selected")):
			eb.connect("club_selected", Callable(self, "_on_club_selected"))
	
	if CameraServer.has_signal("camera_feed_added"):
		CameraServer.connect("camera_feed_added", func(_id):
			if (is_golfer_camera_enabled() or _is_putting_cam_enabled) and not _use_phone_stream:
				_update_camera_feed(true)
		)

	var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
	if bridge != null:
		if bridge.has_signal("desktop_frame_received") and not bridge.desktop_frame_received.is_connected(_on_desktop_frame_received):
			bridge.desktop_frame_received.connect(_on_desktop_frame_received)
		if bridge.has_signal("desktop_cameras_updated") and not bridge.desktop_cameras_updated.is_connected(_on_desktop_cameras_updated):
			bridge.desktop_cameras_updated.connect(_on_desktop_cameras_updated)

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
					a.call("SpeakHecklesEnabled")
				else:
					announcer_btn.text = "🎙 Announcer: MUTED"
					apply_material_button_style(announcer_btn, Color(0.5, 0.5, 0.5, 0.85))
					a.call("SpeakHecklesDisabled")
		)
		toggles_container.add_child(announcer_btn)
		_announcer_btn = announcer_btn
		
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
		_tension_btn = tension_btn

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
		_dist_btn = dist_btn
		
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
			if not is_golfer_camera_enabled():
				set_golfer_camera_visible(true)
			elif is_golfer_camera_minimized():
				restore_golfer_camera()
			else:
				set_golfer_camera_visible(false)
		)
		toggles_container.add_child(golfer_cam_btn)
		_golfer_cam_btn = golfer_cam_btn

		# Putting Camera Toggle Button
		var putting_cam_btn = Button.new()
		putting_cam_btn.name = "PuttingCamButton"
		putting_cam_btn.text = "🎯 Putting Cam: OFF"
		putting_cam_btn.tooltip_text = "Toggle Putting Camera (Ball tracking for putt speed & direction)"
		putting_cam_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(putting_cam_btn, Color(0.35, 0.35, 0.35, 0.85))
		putting_cam_btn.pressed.connect(func():
			if not is_putting_camera_enabled():
				set_putting_camera_visible(true)
			elif is_putting_camera_minimized():
				restore_putting_camera()
			else:
				set_putting_camera_visible(false)
		)
		toggles_container.add_child(putting_cam_btn)
		_putting_cam_btn = putting_cam_btn

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
		_shot_analysis_btn = shot_analysis_btn


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

	if has_node("/root/KeybindingManager"):
		KeybindingManager.keybindings_changed.connect(_update_tooltips)
	_update_tooltips()



# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if is_golfer_camera_enabled() or _is_putting_cam_enabled:
		if _camera_feed_rect != null and _camera_feed_rect.texture == null:
			if not _use_phone_stream and CameraServer.get_feed_count() > 0:
				_update_camera_feed(true)


func set_data(data: Dictionary, is_final_rest: bool = false) -> void:
	_last_shot_data = data.duplicate()
	var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true

	var grid = get_node_or_null("GridCanvas")
	if grid != null:
		for child in grid.get_children():
			if child.name == "ClubSelector" or child.name == "AddRemoveButton":
				continue
			var stat_id = child.name
			# During in-flight live updates, only update dynamic flight metrics
			if not is_final_rest and not (stat_id in ["Distance", "Carry", "Offline", "Apex", "DescentAngle", "HangTime"]):
				continue

			var stat_def = StatDefinitions.get_stat_by_id(stat_id)
			if stat_def.is_empty():
				continue

			if is_final_rest and child.has_method("set_units"):
				var u_str: String = str(stat_def.get("units_imperial" if is_imperial else "units_metric", ""))
				child.call("set_units", u_str)

			var val = data.get(stat_id, "---")
			if str(val) == "---" and stat_id == "BallSpeed":
				val = data.get("Speed", "---")
			elif str(val) == "---" and stat_id == "Speed":
				val = data.get("BallSpeed", "---")
			if stat_id == "VLA" or stat_id == "HLA":
				val = _format_angle(val)
			if child.has_method("set_data"):
				child.call("set_data", str(val))

	if is_final_rest:
		var cam_active: bool = is_golfer_camera_enabled()
		var analysis_active: bool = is_shot_analysis_enabled()
		if cam_active or analysis_active:
			var is_suggestions_only: bool = not cam_active and analysis_active
			var recorded_frames: Array[Dictionary] = []
			if not is_suggestions_only:
				if not _saved_swing_frames.is_empty():
					recorded_frames = _saved_swing_frames.duplicate()
				elif _swing_frame_buffer != null:
					recorded_frames = _swing_frame_buffer.get_captured_frames()
			var modal_data = _prepare_modal_shot_data(data)
			var p_name = str(modal_data.get("player", ""))
			if p_name.is_empty():
				p_name = get_selected_player_name()
				modal_data["player"] = p_name

			# 1. Detached window active: update it
			if _detached_modal != null and is_instance_valid(_detached_modal) and _detached_modal.get("is_detached"):
				_detached_modal.update_shot_data(modal_data, recorded_frames, is_suggestions_only)
			# 2. Attached modal active in overlay: update it
			elif has_node("OverlayLayer/SwingReplayModal"):
				var attached_modal = get_node("OverlayLayer/SwingReplayModal")
				if is_instance_valid(attached_modal) and attached_modal.has_method("update_shot_data"):
					attached_modal.update_shot_data(modal_data, recorded_frames, is_suggestions_only)
			# 3. No modal actively open: evaluate launch monitor recommendations and record to player profile
			else:
				var recs = GolfSwingAnalyzer.analyze_launch_monitor(modal_data)
				if not recs.is_empty():
					var mp_mgr = get_node_or_null("/root/MultiplayerManager")
					if mp_mgr != null and mp_mgr.has_method("record_player_swing_issues"):
						mp_mgr.record_player_swing_issues(p_name, recs)
						modal_data["_recommendations_recorded"] = true
						_last_shot_data["_recommendations_recorded"] = true


func _exit_tree() -> void:
	_close_detached_window()


func on_ball_hit() -> void:
	if is_golfer_camera_enabled() and _swing_frame_buffer != null:
		_saved_swing_frames.clear()
		# Continue capturing for 1.2s to capture impact and follow-through, then save snapshot
		get_tree().create_timer(1.2).timeout.connect(func():
			if _swing_frame_buffer != null:
				_saved_swing_frames = _swing_frame_buffer.get_captured_frames()
				if _detached_modal != null and is_instance_valid(_detached_modal) and _detached_modal.get("is_detached"):
					if not _last_shot_data.is_empty():
						var cam_active: bool = is_golfer_camera_enabled()
						var analysis_active: bool = is_shot_analysis_enabled()
						var is_suggestions_only: bool = not cam_active and analysis_active
						var modal_data = _prepare_modal_shot_data(_last_shot_data)
						_detached_modal.update_shot_data(modal_data, _saved_swing_frames, is_suggestions_only)
		)


func _prepare_modal_shot_data(data: Dictionary) -> Dictionary:
	var modal_data: Dictionary = data.duplicate()
	var player_node = get_parent().get_node_or_null("Player") if get_parent() != null else null

	if not modal_data.has("player") or str(modal_data["player"]).is_empty():
		var p_name = ""
		if get_parent() != null and get_parent().has_method("_get_current_player_name"):
			p_name = get_parent()._get_current_player_name()
		if p_name.is_empty():
			p_name = get_selected_player_name()
		modal_data["player"] = p_name

	if not modal_data.has("Club") or str(modal_data["Club"]).is_empty():
		var club_sel = find_child("ClubSelector", true, false)
		if club_sel != null and "current_club" in club_sel and club_sel.current_club != null and not club_sel.current_club.text.is_empty():
			modal_data["Club"] = club_sel.current_club.text
		elif get_parent() != null and get_parent().has_method("_get_selected_club"):
			modal_data["Club"] = get_parent()._get_selected_club()
		elif get_parent() != null and get_parent().has_method("_get_current_club"):
			modal_data["Club"] = get_parent()._get_current_club()
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
	return modal_data


func trigger_swing_replay_modal(data: Dictionary) -> void:
	var cam_active: bool = is_golfer_camera_enabled()
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

	# If detached window is already open, focus it and update shot data
	if _detached_window != null and is_instance_valid(_detached_window) and _detached_modal != null and is_instance_valid(_detached_modal):
		_detached_window.grab_focus()
		var is_suggestions_only: bool = not cam_active and analysis_active
		var recorded_frames: Array[Dictionary] = []
		if not is_suggestions_only:
			if not _saved_swing_frames.is_empty():
				recorded_frames = _saved_swing_frames.duplicate()
			elif _swing_frame_buffer != null:
				recorded_frames = _swing_frame_buffer.get_captured_frames()
		var modal_data = _prepare_modal_shot_data(data)
		_detached_modal.update_shot_data(modal_data, recorded_frames, is_suggestions_only)
		return

	# Do not overwrite if attached replay modal is already open
	var existing = $OverlayLayer.get_node_or_null("SwingReplayModal")
	if existing != null:
		return

	var modal_script = load("res://UI/GolferCamera/swing_replay_modal.gd")
	if modal_script != null:
		var modal = modal_script.new()
		modal.name = "SwingReplayModal"
		modal.detach_requested.connect(func(): _detach_swing_replay_modal(modal))
		modal.attach_requested.connect(func(): _attach_swing_replay_modal(modal))

		var recorded_frames: Array[Dictionary] = []
		var is_suggestions_only: bool = not cam_active and analysis_active
		if not is_suggestions_only:
			if not _saved_swing_frames.is_empty():
				recorded_frames = _saved_swing_frames.duplicate()
			elif _swing_frame_buffer != null:
				recorded_frames = _swing_frame_buffer.get_captured_frames()
		
		var modal_data = _prepare_modal_shot_data(data)
		var should_detach = false
		if has_node("/root/GlobalSettings") and GlobalSettings.range_settings.replay_window_detached.value and modal_script.is_detach_supported():
			should_detach = true

		if should_detach:
			modal.setup_modal(modal_data, recorded_frames, is_suggestions_only)
			_detach_swing_replay_modal(modal)
		else:
			$OverlayLayer.add_child(modal)
			modal.setup_modal(modal_data, recorded_frames, is_suggestions_only)


func _detach_swing_replay_modal(modal: Control) -> void:
	var modal_script = load("res://UI/GolferCamera/swing_replay_modal.gd")
	if modal_script == null or not modal_script.is_detach_supported():
		return
	if _detached_window != null and is_instance_valid(_detached_window):
		return

	var p = modal.get_parent()
	if p != null:
		p.remove_child(modal)

	if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		get_tree().root.gui_embed_subwindows = false

	var win = Window.new()
	win.name = "DetachedSwingReplayWindow"
	win.title = "⛳ Heckle Golf Sim - Shot Analysis & Swing Replay"
	win.transient = false
	win.exclusive = false
	win.unresizable = false
	win.borderless = false
	win.always_on_top = false
	win.min_size = Vector2i(760, 520)

	var saved_w = int(GlobalSettings.range_settings.replay_window_width.value) if has_node("/root/GlobalSettings") else 1100
	var saved_h = int(GlobalSettings.range_settings.replay_window_height.value) if has_node("/root/GlobalSettings") else 750
	win.size = Vector2i(maxi(760, saved_w), maxi(520, saved_h))

	var saved_x = int(GlobalSettings.range_settings.replay_window_position_x.value) if has_node("/root/GlobalSettings") else -1
	var saved_y = int(GlobalSettings.range_settings.replay_window_position_y.value) if has_node("/root/GlobalSettings") else -1

	if saved_x >= 0 and saved_y >= 0:
		win.position = Vector2i(saved_x, saved_y)
	else:
		var screen_count = DisplayServer.get_screen_count()
		var cur_screen = DisplayServer.window_get_current_screen()
		var target_screen = 1 if (screen_count > 1 and cur_screen == 0) else (0 if screen_count > 1 else cur_screen)
		var s_rect = DisplayServer.screen_get_usable_rect(target_screen)
		var pos_x = s_rect.position.x + 40
		var pos_y = s_rect.position.y + 40
		win.position = Vector2i(pos_x, pos_y)

	win.close_requested.connect(func():
		_close_detached_window()
	)

	var save_win_rect = func():
		if win != null and is_instance_valid(win) and has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.replay_window_position_x.value = win.position.x
			GlobalSettings.range_settings.replay_window_position_y.value = win.position.y
			GlobalSettings.range_settings.replay_window_width.value = win.size.x
			GlobalSettings.range_settings.replay_window_height.value = win.size.y

	win.focus_exited.connect(save_win_rect)
	win.size_changed.connect(save_win_rect)
	win.size_changed.connect(func():
		if modal != null and is_instance_valid(modal):
			modal._recenter_modal()
	)

	modal.is_detached = true
	_detached_window = win
	_detached_modal = modal

	win.add_child(modal)
	get_tree().root.add_child(win)

	if has_node("/root/GlobalSettings"):
		GlobalSettings.range_settings.replay_window_detached.value = true

	# Emit closed signal so range simulation unblocks immediately without waiting for Next Shot
	modal.emit_signal("closed")

	modal._recenter_modal()
	modal._build_ui()
	modal._update_playback_frame()
	if not modal.get("_is_analysis_complete") and not modal.get("_is_suggestions_only"):
		modal._start_background_wireframe_analysis()
	win.show()
	win.grab_focus()


func _attach_swing_replay_modal(modal: Control) -> void:
	if _detached_window != null and is_instance_valid(_detached_window):
		if has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.replay_window_position_x.value = _detached_window.position.x
			GlobalSettings.range_settings.replay_window_position_y.value = _detached_window.position.y
			GlobalSettings.range_settings.replay_window_width.value = _detached_window.size.x
			GlobalSettings.range_settings.replay_window_height.value = _detached_window.size.y
			GlobalSettings.range_settings.replay_window_detached.value = false

		if modal.get_parent() == _detached_window:
			_detached_window.remove_child(modal)
		_detached_window.queue_free()
		_detached_window = null

	_detached_modal = null
	modal.is_detached = false
	if not modal.is_inside_tree():
		$OverlayLayer.add_child(modal)

	modal._recenter_modal()
	modal._build_ui()
	modal._update_playback_frame()
	if not modal.get("_is_analysis_complete") and not modal.get("_is_suggestions_only"):
		modal._start_background_wireframe_analysis()


func _close_detached_window() -> void:
	if _detached_window != null and is_instance_valid(_detached_window):
		if has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.replay_window_position_x.value = _detached_window.position.x
			GlobalSettings.range_settings.replay_window_position_y.value = _detached_window.position.y
			GlobalSettings.range_settings.replay_window_width.value = _detached_window.size.x
			GlobalSettings.range_settings.replay_window_height.value = _detached_window.size.y
			GlobalSettings.range_settings.replay_window_detached.value = false

		if _detached_modal != null and is_instance_valid(_detached_modal):
			_detached_modal._close_active_video_players()
			_detached_modal.queue_free()
		_detached_window.queue_free()
		_detached_window = null
		_detached_modal = null


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


static func _get_scaled_avatar_texture(avatar_path: String, target_size: Vector2i = Vector2i(28, 28)) -> Texture2D:
	var path_to_load = avatar_path
	if path_to_load.is_empty() or not ResourceLoader.exists(path_to_load):
		path_to_load = "res://assets/images/avatars/avatar_1.svg"
	
	if not ResourceLoader.exists(path_to_load):
		return null
		
	var raw_tex = load(path_to_load)
	if raw_tex == null:
		return null
	var img = raw_tex.get_image()
	if img == null:
		return raw_tex
	var scaled_img = img.duplicate()
	scaled_img.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(scaled_img)

func _setup_profile_selector() -> void:
	if not has_node("HBoxContainer"):
		return
	
	if has_node("HBoxContainer/PlayerName"):
		$HBoxContainer/PlayerName.visible = false
	
	_profile_option = OptionButton.new()
	_profile_option.name = "ProfileOptionButton"
	_profile_option.tooltip_text = "Select Active Player Profile"
	_profile_option.mouse_filter = Control.MOUSE_FILTER_STOP
	_profile_option.expand_icon = true
	_profile_option.add_theme_constant_override("icon_max_width", 28)
	ThemeManager.apply_option_button_style(_profile_option, 18, Vector2(190, 44))
	
	$HBoxContainer.add_child(_profile_option)
	$HBoxContainer.move_child(_profile_option, 0)
	
	_populate_profile_selector()
	_profile_option.item_selected.connect(_on_profile_option_selected)

func _populate_profile_selector(preferred_selection: String = "") -> void:
	if _profile_option == null or not is_instance_valid(_profile_option):
		return
	
	_profile_option.clear()
	
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	var registered = mp_mgr.get_registered_players() if mp_mgr != null else []
	
	if registered.is_empty():
		var def_icon = _get_scaled_avatar_texture("")
		if def_icon != null:
			_profile_option.add_icon_item(def_icon, "Player 1", 0)
		else:
			_profile_option.add_item("Player 1", 0)
	else:
		for i in range(registered.size()):
			var p = registered[i]
			var p_name = str(p.get("name", "Player " + str(i + 1)))
			var p_avatar = str(p.get("avatar", ""))
			var icon_tex = _get_scaled_avatar_texture(p_avatar)
			if icon_tex != null:
				_profile_option.add_icon_item(icon_tex, p_name, i)
			else:
				_profile_option.add_item(p_name, i)
	
	var target_name = preferred_selection
	if target_name.is_empty():
		target_name = mp_mgr.get_default_range_profile_name() if mp_mgr != null else "Player 1"
	
	var sel_idx = 0
	for i in range(_profile_option.item_count):
		if _profile_option.get_item_text(i).to_lower() == target_name.to_lower():
			sel_idx = i
			break
			
	_profile_option.selected = sel_idx
	var active_name = _profile_option.get_item_text(sel_idx)
	if has_node("HBoxContainer/PlayerName"):
		$HBoxContainer/PlayerName.text = active_name
	_update_club_selector_bag(active_name)

func _update_club_selector_bag(player_name: String) -> void:
	var club_sel = find_child("ClubSelector", true, false)
	if club_sel != null and club_sel.has_method("update_bag_for_player"):
		club_sel.update_bag_for_player(player_name)

func _refresh_profile_selector() -> void:
	if _profile_option == null or not is_instance_valid(_profile_option):
		return
	var current_sel = get_selected_player_name()
	_populate_profile_selector(current_sel)

func _on_profile_option_selected(_idx: int) -> void:
	var p_name = get_selected_player_name()
	if has_node("HBoxContainer/PlayerName"):
		$HBoxContainer/PlayerName.text = p_name
	_update_club_selector_bag(p_name)
	emit_signal("player_profile_changed", p_name)

func get_selected_player_name() -> String:
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and not mp_mgr.players.is_empty() and not mp_mgr.hole_ids.is_empty():
		var active_p = mp_mgr.get_active_player()
		if not active_p.is_empty() and not str(active_p.get("name", "")).is_empty():
			return str(active_p.get("name", "Player 1"))
	if _profile_option != null and is_instance_valid(_profile_option) and _profile_option.selected >= 0 and _profile_option.selected < _profile_option.item_count:
		return _profile_option.get_item_text(_profile_option.selected)
	if has_node("HBoxContainer/PlayerName") and not $HBoxContainer/PlayerName.text.is_empty():
		return $HBoxContainer/PlayerName.text
	return "Player 1"

func set_selected_player_name(player_name: String) -> void:
	if _profile_option != null and is_instance_valid(_profile_option):
		for i in range(_profile_option.item_count):
			if _profile_option.get_item_text(i).to_lower() == player_name.to_lower():
				_profile_option.selected = i
				if has_node("HBoxContainer/PlayerName"):
					$HBoxContainer/PlayerName.text = _profile_option.get_item_text(i)
				_update_club_selector_bag(_profile_option.get_item_text(i))
				emit_signal("player_profile_changed", _profile_option.get_item_text(i))
				return
	if has_node("HBoxContainer/PlayerName"):
		$HBoxContainer/PlayerName.text = player_name
	_update_club_selector_bag(player_name)
	emit_signal("player_profile_changed", player_name)


func _on_session_pop_up_dir_selected(dir: String, player_name: String) -> void:
	set_selected_player_name(player_name)
	emit_signal("set_session", dir, player_name)
	pass # Replace with function body.


func _on_session_pop_up_cancelled() -> void:
	# If setup was cancelled, emit the signal to toggle recording state off
	emit_signal("rec_button_pressed")



func _on_session_recorder_set_session(user: String, dir: String) -> void:
	set_selected_player_name(user)
	$SessionPopUp.set_session_data(user, dir)


func _on_shot_injector_inject(data: Variant) -> void:
	emit_signal("hit_shot", data)

func toggle_shot_injector(value) -> void:
	$ShotInjector.visible = value


func _on_toggle_settings_requested() -> void:
	$SettingsLayer.visible = not $SettingsLayer.visible
	if $SettingsLayer.visible:
		var rs = get_node_or_null("SettingsLayer/Container/RangeSettings")
		if rs != null:
			rs.visible = true
			if rs.has_method("_on_settings_opened"):
				rs.call("_on_settings_opened")


func _on_close_settings_requested() -> void:
	$SettingsLayer.visible = false
	var rs = get_node_or_null("SettingsLayer/Container/RangeSettings")
	if rs != null:
		rs.visible = false
	_refresh_profile_selector()


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
	_averages_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	
	_averages_panel.add_child(averages_hbox)

	_prev_shot_btn = Button.new()
	_prev_shot_btn.name = "PrevShotAnalysisButton"
	_prev_shot_btn.text = "Previous Shot Analysis"
	_prev_shot_btn.custom_minimum_size = Vector2(210, 48)
	_prev_shot_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prev_shot_btn.add_theme_font_size_override("font_size", 15)
	apply_material_button_style(_prev_shot_btn, Color(0.25, 0.35, 0.45, 0.85))
	_prev_shot_btn.pressed.connect(_on_prev_shot_analysis_pressed)
	_prev_shot_btn.tooltip_text = "View analysis and recommendations for your previous shot"

	var bottom_bar = HBoxContainer.new()
	bottom_bar.name = "BottomBarContainer"
	bottom_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_bar.add_theme_constant_override("separation", 16)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	bottom_bar.add_child(_averages_panel)
	bottom_bar.add_child(_prev_shot_btn)
	add_child(bottom_bar)

	_update_prev_shot_analysis_visibility()


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
	
	if _avg_carry != null:
		_avg_carry.text = "Avg Carry: %.1f %s" % [carry, u_label]
	if _avg_speed != null:
		_avg_speed.text = "Avg Speed: %.1f %s" % [speed, s_label]
	if _avg_spin != null:
		_avg_spin.text = "Avg Spin: %.0f rpm" % spin
	if _avg_offline != null:
		_avg_offline.text = "Avg Offline: %.1f %s" % [offline, u_label]
	
	if _avg_target_diff != null:
		var sign_char := "+" if target_diff >= 0.0 else ""
		_avg_target_diff.text = "Avg +/- Target: %s%.1f %s" % [sign_char, target_diff, u_label]


func reset_average_stats() -> void:
	if _avg_carry != null:
		_avg_carry.text = "Avg Carry: ---"
	if _avg_speed != null:
		_avg_speed.text = "Avg Speed: ---"
	if _avg_spin != null:
		_avg_spin.text = "Avg Spin: ---"
	if _avg_offline != null:
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


func _update_prev_shot_analysis_visibility() -> void:
	if _prev_shot_btn != null:
		var cam_active: bool = is_golfer_camera_enabled()
		var analysis_active: bool = is_shot_analysis_enabled()
		_prev_shot_btn.visible = cam_active or analysis_active


func _on_prev_shot_analysis_pressed() -> void:
	if _last_shot_data.is_empty():
		return
	trigger_swing_replay_modal(_last_shot_data)


func toggle_prev_shot_analysis() -> void:
	# 1. If attached SwingReplayModal is open, close it
	var modal = $OverlayLayer.get_node_or_null("SwingReplayModal")
	if modal != null and is_instance_valid(modal):
		if modal.has_method("_on_close_button_pressed"):
			modal.call("_on_close_button_pressed")
		else:
			modal.queue_free()
		return

	# 2. If detached window modal is open, close it
	if _detached_window != null and is_instance_valid(_detached_window):
		_close_detached_window()
		return

	# 3. If prev shot popup panel is visible, hide it
	if _prev_shot_popup != null and is_instance_valid(_prev_shot_popup) and _prev_shot_popup.visible:
		_prev_shot_popup.visible = false
		return

	# 4. Otherwise, open previous shot analysis
	if _last_shot_data.is_empty():
		if _prev_shot_popup != null:
			if _prev_shot_data_label != null:
				_prev_shot_data_label.text = "No shot data recorded yet.\nTake a swing on the range or course to view your swing replay, club delivery visuals, and AI flaw analysis."
			_prev_shot_popup.visible = true
		return
	
	trigger_swing_replay_modal(_last_shot_data)


func is_stats_visible() -> bool:
	var dist_panel = get_node_or_null("GridCanvas/Distance")
	return dist_panel.visible if dist_panel != null else true


func set_stats_visible(show_stats: bool) -> void:
	var grid = get_node_or_null("GridCanvas")
	if grid != null:
		for child in grid.get_children():
			if child.name != "ClubSelector":
				child.visible = show_stats
	if _averages_panel != null:
		_averages_panel.visible = show_stats
	if _stats_btn != null and is_instance_valid(_stats_btn):
		if show_stats:
			apply_circular_button_style(_stats_btn, Color(0.24, 0.46, 0.72, 0.85))
		else:
			apply_circular_button_style(_stats_btn, Color(0.15, 0.15, 0.15, 0.85))
	stats_visibility_changed.emit(show_stats)


func toggle_stats_visibility() -> void:
	set_stats_visible(not is_stats_visible())


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

	var style_focus = style_normal.duplicate()
	style_focus.border_color = Color(0.35, 0.82, 1.0, 0.95)
	style_focus.border_width_left = 3
	style_focus.border_width_top = 3
	style_focus.border_width_right = 3
	style_focus.border_width_bottom = 3

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	btn.add_theme_stylebox_override("focus", style_focus)
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

	var style_focus = style_normal.duplicate()
	style_focus.border_color = Color(0.35, 0.82, 1.0, 0.95)
	style_focus.border_width_left = 3
	style_focus.border_width_top = 3
	style_focus.border_width_right = 3
	style_focus.border_width_bottom = 3

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", style_focus)


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
	if has_node("/root/AnnouncerEngine"):
		get_node("/root/AnnouncerEngine").call("SpeakHomeButtonHeckle")

	if _exit_confirm_dialog != null:
		_exit_confirm_dialog.visible = true
		var no_b = _exit_confirm_dialog.find_child("NoButton", true, false) as Button
		if no_b != null:
			no_b.call_deferred("grab_focus")
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

	exit_yes_btn.focus_neighbor_right = exit_yes_btn.get_path_to(exit_no_btn)
	exit_yes_btn.focus_neighbor_left = exit_yes_btn.get_path_to(exit_no_btn)
	exit_no_btn.focus_neighbor_left = exit_no_btn.get_path_to(exit_yes_btn)
	exit_no_btn.focus_neighbor_right = exit_no_btn.get_path_to(exit_yes_btn)

	exit_content_vbox.add_child(exit_btn_hbox)
	exit_panel.add_child(exit_content_vbox)
	_exit_confirm_dialog.add_child(exit_panel)
	$OverlayLayer.add_child(_exit_confirm_dialog)

	exit_no_btn.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if _exit_confirm_dialog != null and is_instance_valid(_exit_confirm_dialog) and _exit_confirm_dialog.visible:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
			_exit_confirm_dialog.visible = false
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or \
		   event.is_action_pressed("aim_left") or event.is_action_pressed("aim_right"):
			var cur_f = get_viewport().gui_get_focus_owner()
			var no_btn = _exit_confirm_dialog.find_child("NoButton", true, false) as Button
			var yes_btn = _exit_confirm_dialog.find_child("YesButton", true, false) as Button
			if cur_f == yes_btn and no_btn != null:
				no_btn.grab_focus()
			elif yes_btn != null:
				yes_btn.grab_focus()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)):
			var cur_f = get_viewport().gui_get_focus_owner()
			var yes_btn = _exit_confirm_dialog.find_child("YesButton", true, false) as Button
			var no_btn = _exit_confirm_dialog.find_child("NoButton", true, false) as Button
			if cur_f == yes_btn:
				yes_btn.emit_signal("pressed")
			elif no_btn != null:
				no_btn.emit_signal("pressed")
			else:
				_exit_confirm_dialog.visible = false
			get_viewport().set_input_as_handled()
			return


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
	_golfer_cam_panel.custom_minimum_size = Vector2(380, 590)
	_golfer_cam_panel.size = Vector2(380, 590)
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
	header.add_theme_constant_override("separation", 6)
	
	var title = Label.new()
	title.name = "PanelTitleLabel"
	title.text = "📹 GOLFER CAM"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	header.add_child(title)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	# Setup, Rotate & Flip Camera Buttons
	var header_setup_btn = Button.new()
	header_setup_btn.name = "HeaderSetupButton"
	header_setup_btn.text = "⚙️ Setup"
	header_setup_btn.custom_minimum_size = Vector2(80, 48)
	apply_material_button_style(header_setup_btn, Color(0.2, 0.45, 0.65, 0.9))
	header_setup_btn.pressed.connect(_open_camera_setup_dialog)
	header.add_child(header_setup_btn)

	_camera_rotate_btn = Button.new()
	_camera_rotate_btn.name = "RotateCameraButton"
	_camera_rotate_btn.custom_minimum_size = Vector2(74, 48)
	_update_camera_rotate_button_text()
	apply_material_button_style(_camera_rotate_btn, Color(0.2, 0.48, 0.4, 0.9))
	_camera_rotate_btn.pressed.connect(_on_rotate_camera_pressed)
	header.add_child(_camera_rotate_btn)

	_camera_flip_btn = Button.new()
	_camera_flip_btn.name = "FlipCameraButton"
	_camera_flip_btn.text = "🔄 Flip"
	_camera_flip_btn.custom_minimum_size = Vector2(74, 48)
	apply_material_button_style(_camera_flip_btn, Color(0.2, 0.4, 0.6, 0.9))
	_camera_flip_btn.pressed.connect(_on_flip_camera_pressed)
	header.add_child(_camera_flip_btn)
	
	var status_dot = Label.new()
	status_dot.text = "🔴 LIVE"
	status_dot.add_theme_font_size_override("font_size", 14)
	status_dot.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
	header.add_child(status_dot)

	_camera_minimize_btn = Button.new()
	_camera_minimize_btn.name = "MinimizeCameraButton"
	_camera_minimize_btn.text = "🗕"
	_camera_minimize_btn.tooltip_text = "Minimize Camera (Keeps running in background)"
	_camera_minimize_btn.custom_minimum_size = Vector2(44, 48)
	apply_material_button_style(_camera_minimize_btn, Color(0.25, 0.35, 0.45, 0.9))
	_camera_minimize_btn.pressed.connect(minimize_camera)
	header.add_child(_camera_minimize_btn)
	
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

	# Floating restore pill (visible only when camera is minimized & recording)
	_camera_restore_pill = Button.new()
	_camera_restore_pill.name = "CameraRestorePill"
	_camera_restore_pill.text = "📹 Golfer Cam [REC] 🗖"
	_camera_restore_pill.tooltip_text = "Golfer Cam is recording in background. Click to expand preview."
	_camera_restore_pill.visible = false
	_camera_restore_pill.custom_minimum_size = Vector2(180, 42)
	_camera_restore_pill.anchor_left = 0.0
	_camera_restore_pill.anchor_right = 0.0
	_camera_restore_pill.anchor_top = 1.0
	_camera_restore_pill.anchor_bottom = 1.0
	_camera_restore_pill.offset_left = 30
	_camera_restore_pill.offset_top = -160
	_camera_restore_pill.offset_right = 210
	_camera_restore_pill.offset_bottom = -118
	_camera_restore_pill.add_theme_font_size_override("font_size", 13)
	
	var pill_style = StyleBoxFlat.new()
	pill_style.bg_color = Color(0.12, 0.45, 0.4, 0.9)
	pill_style.corner_radius_top_left = 10
	pill_style.corner_radius_top_right = 10
	pill_style.corner_radius_bottom_left = 10
	pill_style.corner_radius_bottom_right = 10
	pill_style.content_margin_left = 10
	pill_style.content_margin_right = 10
	pill_style.content_margin_top = 8
	pill_style.content_margin_bottom = 8
	pill_style.border_width_left = 1
	pill_style.border_width_top = 1
	pill_style.border_width_right = 1
	pill_style.border_width_bottom = 1
	pill_style.border_color = Color(0.2, 0.75, 0.65, 0.8)
	_camera_restore_pill.add_theme_stylebox_override("normal", pill_style)
	
	var pill_hover = pill_style.duplicate()
	pill_hover.bg_color = Color(0.16, 0.55, 0.48, 0.95)
	_camera_restore_pill.add_theme_stylebox_override("hover", pill_hover)
	
	var pill_pressed = pill_style.duplicate()
	pill_pressed.bg_color = Color(0.08, 0.35, 0.3, 0.95)
	_camera_restore_pill.add_theme_stylebox_override("pressed", pill_pressed)
	
	_camera_restore_pill.pressed.connect(restore_camera)
	$OverlayLayer.add_child(_camera_restore_pill)


var _hud_elements_suppressed: bool = false


func set_hud_elements_visible(is_vis: bool) -> void:
	_hud_elements_suppressed = not is_vis
	_update_restore_pill_visibility()
	if _golfer_cam_panel != null and is_instance_valid(_golfer_cam_panel):
		if not is_vis:
			_golfer_cam_panel.visible = false
		else:
			_golfer_cam_panel.visible = is_camera_modal_open()
	if _stats_btn != null and is_instance_valid(_stats_btn):
		_stats_btn.visible = is_vis
	if _map_btn != null and is_instance_valid(_map_btn):
		_map_btn.visible = is_vis


func _update_restore_pill_visibility() -> void:
	if _camera_restore_pill != null and is_instance_valid(_camera_restore_pill):
		_camera_restore_pill.visible = (_is_golfer_cam_minimized or _is_putting_cam_minimized) and not _hud_elements_suppressed


func _get_autoload(autoload_name: String) -> Node:
	if is_inside_tree() and has_node("/root/" + autoload_name):
		return get_node("/root/" + autoload_name)
	var loop = Engine.get_main_loop() as SceneTree
	if loop != null and loop.root != null:
		return loop.root.get_node_or_null(autoload_name)
	return null


func _get_current_club() -> String:
	if not _current_selected_club.is_empty():
		return _current_selected_club
	var gs = _get_autoload("GlobalSettings")
	if gs != null and "current_selected_club" in gs and not str(gs.current_selected_club).is_empty():
		return str(gs.current_selected_club)
	return _current_selected_club


func set_current_club(club_name: String) -> void:
	_on_club_selected(club_name)


func _is_putter_selected() -> bool:
	var club = _get_current_club().strip_edges().to_lower()
	return club == "pt" or club.contains("putt")


func _should_camera_feed_be_active() -> bool:
	if is_golfer_camera_enabled():
		return true
	if _is_putting_cam_enabled:
		return _is_putter_selected()
	return false


func _sync_camera_feed_consumption() -> void:
	var should_be_active = _should_camera_feed_be_active()
	if _use_phone_stream:
		if should_be_active:
			if not _is_requesting_frame and not _phone_cam_url.is_empty():
				_request_next_phone_frame()
	else:
		var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else (get_node_or_null("/root/PoseDetectionBridge") if is_inside_tree() else null)
		if should_be_active:
			if bridge != null and bridge.has_method("resume_desktop_camera"):
				bridge.resume_desktop_camera()
			CameraServer.set_monitoring_feeds(true)
			var feeds = CameraServer.feeds()
			if _current_camera_feed_index >= 0 and _current_camera_feed_index < feeds.size():
				var feed = feeds[_current_camera_feed_index]
				if feed != null:
					feed.feed_is_active = true
		else:
			if bridge != null and bridge.has_method("pause_desktop_camera"):
				bridge.pause_desktop_camera()
			if CameraServer.is_monitoring_feeds():
				var feeds = CameraServer.feeds()
				for feed in feeds:
					if feed != null:
						feed.feed_is_active = false
			CameraServer.set_monitoring_feeds(false)


func _on_club_selected(club_name: String) -> void:
	_current_selected_club = club_name
	if not _is_putting_cam_enabled:
		return
	if _is_putter_selected():
		if _is_putting_cam_minimized:
			restore_putting_camera()
		_sync_camera_feed_consumption()
	else:
		if not _is_putting_cam_minimized:
			minimize_putting_camera()
		_sync_camera_feed_consumption()


func is_camera_modal_open() -> bool:
	var cam_active = (_is_golfer_cam_enabled and not _is_golfer_cam_minimized) or (_is_putting_cam_enabled and not _is_putting_cam_minimized)
	return cam_active and _golfer_cam_panel != null and _golfer_cam_panel.visible


func is_golfer_camera_modal_open() -> bool:
	return is_camera_modal_open()


func is_putting_camera_modal_open() -> bool:
	return is_camera_modal_open() and _is_putting_cam_enabled


func is_golfer_camera_enabled() -> bool:
	return _is_golfer_cam_enabled


func is_golfer_camera_minimized() -> bool:
	return _is_golfer_cam_minimized


func is_golfer_camera_visible() -> bool:
	return _golfer_cam_panel.visible if _golfer_cam_panel != null else false


func is_putting_camera_enabled() -> bool:
	return _is_putting_cam_enabled


func is_putting_camera_minimized() -> bool:
	return _is_putting_cam_minimized


func is_putting_camera_visible() -> bool:
	return _is_putting_cam_enabled and not _is_putting_cam_minimized and _golfer_cam_panel != null and _golfer_cam_panel.visible


func minimize_camera() -> void:
	if _is_putting_cam_enabled:
		minimize_putting_camera()
	elif _is_golfer_cam_enabled:
		minimize_golfer_camera()


func restore_camera() -> void:
	if _is_putting_cam_enabled:
		restore_putting_camera()
	elif _is_golfer_cam_enabled:
		restore_golfer_camera()


func minimize_golfer_camera() -> void:
	if not _is_golfer_cam_enabled:
		return
	_is_golfer_cam_minimized = true
	if _golfer_cam_panel != null:
		_golfer_cam_panel.visible = false
	if _camera_restore_pill != null and is_instance_valid(_camera_restore_pill):
		_camera_restore_pill.text = "📹 Golfer Cam [REC] 🗖"
		_camera_restore_pill.tooltip_text = "Golfer Cam is recording in background. Click to expand preview."
	_update_restore_pill_visibility()
	_update_golfer_cam_button_state()
	_update_button_shifts()
	golfer_cam_modal_state_changed.emit(false)


func restore_golfer_camera() -> void:
	if not _is_golfer_cam_enabled:
		set_golfer_camera_visible(true)
		return
	_is_golfer_cam_minimized = false
	if _golfer_cam_panel != null:
		_golfer_cam_panel.visible = not _hud_elements_suppressed
	_update_restore_pill_visibility()
	_update_golfer_cam_button_state()
	_update_button_shifts()
	golfer_cam_modal_state_changed.emit(true)


func minimize_putting_camera() -> void:
	if not _is_putting_cam_enabled:
		return
	_is_putting_cam_minimized = true
	if _golfer_cam_panel != null:
		_golfer_cam_panel.visible = false
	if _camera_restore_pill != null and is_instance_valid(_camera_restore_pill):
		_camera_restore_pill.text = "🎯 Putting Cam [REC] 🗖"
		_camera_restore_pill.tooltip_text = "Putting Cam is tracking in background. Click to expand preview."
	_update_restore_pill_visibility()
	_update_putting_cam_button_state()
	_update_button_shifts()
	golfer_cam_modal_state_changed.emit(false)


func restore_putting_camera() -> void:
	if not _is_putting_cam_enabled:
		set_putting_camera_visible(true)
		return
	_is_putting_cam_minimized = false
	if _golfer_cam_panel != null:
		_golfer_cam_panel.visible = not _hud_elements_suppressed
	_update_restore_pill_visibility()
	_update_putting_cam_button_state()
	_update_button_shifts()
	golfer_cam_modal_state_changed.emit(true)


func _update_golfer_cam_button_state() -> void:
	if _golfer_cam_btn != null and is_instance_valid(_golfer_cam_btn):
		if not _is_golfer_cam_enabled:
			_golfer_cam_btn.text = "📹 Golfer Cam: OFF"
			apply_material_button_style(_golfer_cam_btn, Color(0.2, 0.45, 0.45, 0.85))
		elif _is_golfer_cam_minimized:
			_golfer_cam_btn.text = "📹 Golfer Cam: MIN [REC]"
			apply_material_button_style(_golfer_cam_btn, Color(0.2, 0.55, 0.7, 0.85))
		else:
			_golfer_cam_btn.text = "📹 Golfer Cam: ON"
			apply_material_button_style(_golfer_cam_btn, Color(0.15, 0.6, 0.5, 0.85))


func _update_putting_cam_button_state() -> void:
	if _putting_cam_btn != null and is_instance_valid(_putting_cam_btn):
		if not _is_putting_cam_enabled:
			_putting_cam_btn.text = "🎯 Putting Cam: OFF"
			apply_material_button_style(_putting_cam_btn, Color(0.35, 0.35, 0.35, 0.85))
		elif _is_putting_cam_minimized:
			_putting_cam_btn.text = "🎯 Putting Cam: MIN [REC]"
			apply_material_button_style(_putting_cam_btn, Color(0.2, 0.55, 0.5, 0.85))
		else:
			_putting_cam_btn.text = "🎯 Putting Cam: ON"
			apply_material_button_style(_putting_cam_btn, Color(0.15, 0.6, 0.3, 0.85))


func _update_button_shifts() -> void:
	var modal_open = is_camera_modal_open()
	if _stats_btn != null and is_instance_valid(_stats_btn):
		if modal_open:
			_stats_btn.offset_left = 495
			_stats_btn.offset_right = 559
		else:
			_stats_btn.offset_left = 30
			_stats_btn.offset_right = 94

	var grid = get_node_or_null("GridCanvas")
	if grid != null:
		if grid.has_method("set_golfer_camera_active"):
			grid.call("set_golfer_camera_active", modal_open)
		else:
			grid.position.x = 350.0 if modal_open else 0.0


func set_golfer_camera_visible(enabled: bool) -> void:
	if enabled:
		# MUTUAL EXCLUSIVITY: Disable Putting Camera if it's active
		if is_putting_camera_enabled():
			set_putting_camera_visible(false)

		_is_golfer_cam_enabled = true
		_is_golfer_cam_minimized = false
		_stats_were_visible_before_cam = is_stats_visible()
		if is_stats_visible():
			set_stats_visible(false)
	else:
		_is_golfer_cam_enabled = false
		_is_golfer_cam_minimized = false
		if _stats_were_visible_before_cam and not is_stats_visible():
			set_stats_visible(true)

	if _golfer_cam_panel != null:
		_golfer_cam_panel.visible = enabled and not _hud_elements_suppressed
		_update_camera_feed(enabled)
	
	_update_restore_pill_visibility()
	_update_golfer_cam_button_state()
	_update_button_shifts()
	golfer_cam_enabled_changed.emit(_is_golfer_cam_enabled)
	golfer_cam_modal_state_changed.emit(is_camera_modal_open())
	_update_prev_shot_analysis_visibility()


func set_putting_camera_visible(enabled: bool) -> void:
	if enabled:
		# MUTUAL EXCLUSIVITY: Disable Golfer Camera if it's active
		if is_golfer_camera_enabled():
			set_golfer_camera_visible(false)

		_is_putting_cam_enabled = true
		_stats_were_visible_before_cam = is_stats_visible()
		if is_stats_visible():
			set_stats_visible(false)

		var is_putt = _is_putter_selected()
		_is_putting_cam_minimized = not is_putt
		_show_putting_camera_overlay(true)
		_update_camera_feed(true)

		if not is_putt:
			minimize_putting_camera()
		else:
			if _golfer_cam_panel != null:
				_golfer_cam_panel.visible = not _hud_elements_suppressed
			_update_restore_pill_visibility()
			_update_putting_cam_button_state()
			_update_button_shifts()
			golfer_cam_modal_state_changed.emit(is_camera_modal_open())
		_sync_camera_feed_consumption()
	else:
		_is_putting_cam_enabled = false
		_is_putting_cam_minimized = false
		_show_putting_camera_overlay(false)
		if _stats_were_visible_before_cam and not is_stats_visible():
			set_stats_visible(true)

		# Only stop camera feed if golfer cam is also off
		if not is_golfer_camera_enabled():
			_update_camera_feed(false)
		_sync_camera_feed_consumption()

		_update_restore_pill_visibility()
		_update_putting_cam_button_state()
		_update_button_shifts()
		golfer_cam_modal_state_changed.emit(false)

	putting_cam_enabled_changed.emit(_is_putting_cam_enabled)
	if is_inside_tree() and has_node("/root/GlobalSettings"):
		GlobalSettings.range_settings.putting_camera_enabled.set_value(_is_putting_cam_enabled)
		GlobalSettings.save_settings()


func _show_putting_camera_overlay(enabled: bool) -> void:
	if enabled:
		if _golfer_cam_panel != null and not _is_putting_cam_minimized:
			_golfer_cam_panel.visible = not _hud_elements_suppressed

		var skel = _golfer_cam_panel.find_child("LiveGolferSkeletonOverlay", true, false) if _golfer_cam_panel != null else null
		if skel != null:
			skel.visible = false

		if _putting_overlay == null:
			var overlay_script = load("res://UI/PuttingCamera/putting_camera_overlay.gd")
			if overlay_script != null:
				_putting_overlay = overlay_script.new()
				_putting_overlay.name = "PuttingCameraOverlay"
				_putting_overlay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_putting_overlay.size_flags_vertical = Control.SIZE_EXPAND_FILL

		if _golfer_cam_panel != null:
			var feed_rect = _golfer_cam_panel.find_child("CameraFeedRect", true, false)
			if feed_rect != null:
				var parent = feed_rect.get_parent()
				if _putting_overlay.get_parent() != parent:
					if _putting_overlay.get_parent() != null:
						_putting_overlay.get_parent().remove_child(_putting_overlay)
					parent.add_child(_putting_overlay)

		if _putting_overlay != null:
			_putting_overlay.visible = true

		if _putting_state_machine == null:
			var sm_script = load("res://UI/PuttingCamera/putting_camera_state_machine.gd")
			if sm_script != null:
				_putting_state_machine = sm_script.new()
				_putting_state_machine.name = "PuttingCameraStateMachine"
				add_child(_putting_state_machine)
				_putting_state_machine.putt_detected.connect(_on_putt_detected)

		if _putting_state_machine != null:
			_putting_state_machine.overlay = _putting_overlay
			_putting_state_machine.reset()
			_apply_putting_camera_fps()

		if _golfer_cam_panel != null:
			var title_label = _golfer_cam_panel.find_child("PanelTitleLabel", true, false)
			if title_label is Label:
				title_label.text = "🎯 PUTTING CAM"
			if _camera_minimize_btn != null:
				_camera_minimize_btn.tooltip_text = "Minimize Putting Cam (Keeps tracking in background)"
	else:
		if _putting_overlay != null:
			_putting_overlay.visible = false
		if _putting_state_machine != null:
			_putting_state_machine.reset()

		var skel = _golfer_cam_panel.find_child("LiveGolferSkeletonOverlay", true, false) if _golfer_cam_panel != null else null
		if skel != null:
			skel.visible = true

		if _golfer_cam_panel != null:
			var title_label = _golfer_cam_panel.find_child("PanelTitleLabel", true, false)
			if title_label is Label:
				title_label.text = "📹 GOLFER CAM"
			if _camera_minimize_btn != null:
				_camera_minimize_btn.tooltip_text = "Minimize Golfer Cam (Keeps recording in background)"
			if not is_golfer_camera_enabled():
				_golfer_cam_panel.visible = false


func _apply_putting_camera_fps() -> void:
	if _putting_state_machine == null:
		return

	var has_gs = is_inside_tree() and has_node("/root/GlobalSettings")
	var fps_mode: String = GlobalSettings.range_settings.putting_camera_fps_mode.value if has_gs else "Auto"
	var fps: float = 30.0

	match fps_mode:
		"Auto":
			fps = _detect_camera_fps()
		"30":
			fps = 30.0
		"60":
			fps = 60.0
		"120":
			fps = 120.0
		"Custom":
			fps = float(GlobalSettings.range_settings.putting_camera_fps.value) if has_gs else 30.0
		_:
			fps = 30.0

	_putting_state_machine.set_fps(fps)
	print("[PuttingCam] Active FPS set to: %.1f (%s mode)" % [fps, fps_mode])


func _detect_camera_fps() -> float:
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else (get_node_or_null("/root/PoseDetectionBridge") if is_inside_tree() else null)
	if pose_bridge != null and "FRAME_INTERVAL" in pose_bridge:
		var interval: float = float(pose_bridge.FRAME_INTERVAL)
		if interval > 0.001:
			return 1.0 / interval

	var feeds = CameraServer.feeds()
	if feeds.size() > 0:
		return 30.0

	return 30.0


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
	print("[PuttingCam] Dispatching putt: %s" % str(putt_data))
	emit_signal("hit_shot", putt_data)


func on_next_shot_started() -> void:
	if _putting_state_machine != null and _putting_state_machine.current_state == PuttingCameraStateMachine.State.EXECUTION:
		_putting_state_machine._transition_to(PuttingCameraStateMachine.State.IDLE)


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
	_update_prev_shot_analysis_visibility()



func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		if (is_golfer_camera_enabled() or _is_putting_cam_enabled) and not _use_phone_stream:
			var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
			var is_desk_active = bridge != null and bridge.has_method("is_desktop_camera_active") and bridge.is_desktop_camera_active()
			if not is_desk_active:
				_update_camera_feed(true)


func _on_desktop_cameras_updated(cams: Array) -> void:
	if (is_golfer_camera_enabled() or _is_putting_cam_enabled) and not _use_phone_stream:
		if _camera_feed_rect != null and _camera_feed_rect.texture == null and cams.size() > 0:
			var bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else get_node_or_null("/root/PoseDetectionBridge")
			if bridge != null and bridge.has_method("select_desktop_camera"):
				var sel_idx = clamp(_current_camera_feed_index, 0, cams.size() - 1)
				_current_camera_feed_index = sel_idx
				if _camera_feed_rect != null:
					_camera_feed_rect.material = null
				bridge.select_desktop_camera(sel_idx)
				_update_status_overlay("", false)


func _update_camera_rotate_button_text() -> void:
	if _camera_rotate_btn != null and is_instance_valid(_camera_rotate_btn):
		_camera_rotate_btn.text = "🔁 %d°" % _camera_rotation_deg
		_camera_rotate_btn.tooltip_text = "Rotate Camera Feed 90° (Current: %d°). Align feed with putting roll direction." % _camera_rotation_deg


func _on_rotate_camera_pressed() -> void:
	_camera_rotation_deg = (_camera_rotation_deg + 90) % 360
	_update_camera_rotate_button_text()
	if _putting_state_machine != null:
		_putting_state_machine.reset()
	print("[RangeUI] Camera rotation set to: %d°" % _camera_rotation_deg)


func _apply_image_rotation(img: Image, rotation_deg: int) -> Image:
	if img == null:
		return null
	match rotation_deg:
		90:
			img.rotate_90(CLOCKWISE)
		180:
			img.rotate_180()
		270:
			img.rotate_90(COUNTERCLOCKWISE)
		_:
			pass
	return img


func _on_desktop_frame_received(_img: Image, tex: Texture2D, _landmarks: Dictionary) -> void:
	if not _should_camera_feed_be_active():
		return

	var active_img: Image = _img
	var active_tex: Texture2D = tex
	if _camera_rotation_deg != 0 and _img != null:
		active_img = _img.duplicate()
		_apply_image_rotation(active_img, _camera_rotation_deg)
		active_tex = ImageTexture.create_from_image(active_img)

	if is_golfer_camera_enabled() and not _use_phone_stream:
		if _camera_feed_rect != null:
			_camera_feed_rect.material = null
			_camera_feed_rect.texture = active_tex
		_update_status_overlay("", false)

	if _is_putting_cam_enabled and not _use_phone_stream:
		if _camera_feed_rect != null:
			_camera_feed_rect.material = null
			_camera_feed_rect.texture = active_tex
		_update_status_overlay("", false)
		if _putting_state_machine != null and active_img != null:
			_putting_state_machine.process_frame(active_img)


func _update_camera_feed(active: bool) -> void:
	var pose_bridge = Engine.get_singleton("PoseDetectionBridge") if Engine.has_singleton("PoseDetectionBridge") else (get_node_or_null("/root/PoseDetectionBridge") if is_inside_tree() else null)

	if not active:
		if pose_bridge != null and pose_bridge.has_method("stop_desktop_camera"):
			pose_bridge.stop_desktop_camera()
		if CameraServer.is_monitoring_feeds():
			var feeds = CameraServer.feeds()
			for feed in feeds:
				if feed != null:
					feed.feed_is_active = false
		CameraServer.set_monitoring_feeds(false)
		if _camera_feed_rect != null:
			_camera_feed_rect.material = null
			_camera_feed_rect.texture = null
		_update_status_overlay("GOLFER CAMERA FEED\n[ Click ⚙️ Setup to connect ]", true)
		return

	# If desktop camera is already actively streaming, maintain it without restarting
	if pose_bridge != null and pose_bridge.has_method("is_desktop_camera_active") and pose_bridge.is_desktop_camera_active():
		_update_status_overlay("", false)
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
				_camera_feed_rect.material = null
				_camera_feed_rect.texture = null
			# Re-check after user grants permission
			get_tree().create_timer(1.5).timeout.connect(func():
				if is_golfer_camera_enabled() or _is_putting_cam_enabled:
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
		if _camera_feed_rect != null:
			_camera_feed_rect.material = null
		pose_bridge.select_desktop_camera(sel_idx)
		_update_status_overlay("", false)
	else:
		if _camera_feed_rect != null:
			_camera_feed_rect.material = null
			_camera_feed_rect.texture = null
		_update_status_overlay("SEARCHING FOR WEBCAMS...\n[ Click ⚙️ Connect Camera for setup ]", true)
		if pose_bridge != null and pose_bridge.has_method("fetch_desktop_cameras"):
			pose_bridge.fetch_desktop_cameras()
		# Schedule asynchronous re-scan
		if get_tree() != null:
			get_tree().create_timer(0.6).timeout.connect(func():
				if (is_golfer_camera_enabled() or _is_putting_cam_enabled) and not _use_phone_stream:
					var rescan_feeds = CameraServer.feeds()
					if rescan_feeds.size() > 0:
						var sel_idx = _find_default_camera_index(rescan_feeds)
						_current_camera_feed_index = sel_idx
						_activate_camera_feed_index(sel_idx)
					elif pose_bridge != null and "desktop_cameras" in pose_bridge and pose_bridge.desktop_cameras.size() > 0:
						var sel_idx = clamp(_current_camera_feed_index, 0, pose_bridge.desktop_cameras.size() - 1)
						_current_camera_feed_index = sel_idx
						if _camera_feed_rect != null:
							_camera_feed_rect.material = null
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
	if label is Label and not msg.is_empty():
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
			if _camera_feed_rect != null:
				_camera_feed_rect.material = null
			pose_bridge.select_desktop_camera(index)
			_update_status_overlay("", false)
			return
		
		if _camera_feed_rect != null:
			_camera_feed_rect.material = null
			_camera_feed_rect.texture = null
		_update_status_overlay("NO LOCAL WEBCAM DETECTED\n[ Click ⚙️ Connect Camera for Phone WiFi Stream ]", true)
		return
	
	var feed = feeds[index]
	if feed != null:
		feed.feed_is_active = true
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
uniform mat3 feed_transform;

void fragment() {
	vec2 uv = (feed_transform * vec3(UV, 1.0)).xy;
	float y = texture(y_tex, uv).r;
	vec2 cbcr = texture(cbcr_tex, uv).rg;

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
			mat.set_shader_parameter("feed_transform", feed.get_transform())

			if _camera_feed_rect != null:
				_camera_feed_rect.material = mat
				_camera_feed_rect.texture = y_tex
		else:
			if _camera_feed_rect != null:
				_camera_feed_rect.material = null
				var cam_tex = CameraTexture.new()
				cam_tex.camera_feed_id = feed.get_id()
				cam_tex.which_feed = CameraServer.FEED_RGBA_IMAGE
				cam_tex.camera_is_active = true
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
	popup.custom_minimum_size = Vector2(500, 600)
	popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	popup.anchor_left = 0.5
	popup.anchor_top = 0.5
	popup.anchor_right = 0.5
	popup.anchor_bottom = 0.5
	popup.offset_left = -250
	popup.offset_top = -300
	popup.offset_right = 250
	popup.offset_bottom = 300

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
		if not is_instance_valid(popup) or not is_instance_valid(webcams_label) or not is_instance_valid(cam_option):
			return
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

	var on_cameras_updated = func(_cams):
		if is_instance_valid(popup) and is_instance_valid(webcams_label):
			populate_feeds.call()

	if pose_bridge != null and pose_bridge.has_signal("desktop_cameras_updated"):
		pose_bridge.desktop_cameras_updated.connect(on_cameras_updated)
		popup.tree_exited.connect(func():
			if is_instance_valid(pose_bridge) and pose_bridge.is_connected("desktop_cameras_updated", on_cameras_updated):
				pose_bridge.desktop_cameras_updated.disconnect(on_cameras_updated)
		)

	var scan_timer = Timer.new()
	scan_timer.name = "WebcamScanTimer"
	scan_timer.wait_time = 0.3
	scan_timer.autostart = true
	popup.add_child(scan_timer)
	scan_timer.timeout.connect(func():
		if is_instance_valid(popup) and is_instance_valid(webcams_label):
			populate_feeds.call()
	)

	var cam_btn_hbox = HBoxContainer.new()
	cam_btn_hbox.add_theme_constant_override("separation", 8)

	var connect_local_btn = Button.new()
	connect_local_btn.text = "📹 Connect Selected Local Camera"
	connect_local_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	connect_local_btn.custom_minimum_size = Vector2(0, 36)
	apply_material_button_style(connect_local_btn, Color(0.24, 0.46, 0.72, 0.9))
	connect_local_btn.pressed.connect(func():
		var sel_idx = cam_option.get_selected_id() if is_instance_valid(cam_option) else 0
		popup.queue_free()
		_use_phone_stream = false
		_current_camera_feed_index = sel_idx
		var feeds = CameraServer.feeds()
		if feeds.size() > 0:
			_activate_camera_feed_index(sel_idx)
		else:
			if pose_bridge != null and pose_bridge.has_method("select_desktop_camera"):
				if _camera_feed_rect != null:
					_camera_feed_rect.material = null
				pose_bridge.select_desktop_camera(sel_idx)
				_update_status_overlay("", false)
	)
	cam_btn_hbox.add_child(connect_local_btn)

	var rescan_btn = Button.new()
	rescan_btn.text = "🔄 Rescan"
	rescan_btn.custom_minimum_size = Vector2(80, 36)
	apply_material_button_style(rescan_btn, Color(0.3, 0.35, 0.45, 0.9))
	rescan_btn.pressed.connect(func():
		if not is_instance_valid(popup) or not is_instance_valid(webcams_label):
			return
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
		var url_to_connect = ip_input.text if is_instance_valid(ip_input) else _phone_cam_url
		popup.queue_free()
		var local_feeds = CameraServer.feeds()
		for feed in local_feeds:
			if feed != null:
				feed.feed_is_active = false
		if pose_bridge != null and pose_bridge.has_method("stop_desktop_camera"):
			pose_bridge.stop_desktop_camera()
		_use_phone_stream = true
		_start_phone_camera_stream(url_to_connect)
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

	# Section 3: Putting Camera Framerate
	var fps_sep = HSeparator.new()
	fps_sep.add_theme_constant_override("separation", 8)
	vbox.add_child(fps_sep)

	var fps_label = Label.new()
	fps_label.text = "3. Putting Camera Framerate:"
	fps_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(fps_label)

	var fps_hbox = HBoxContainer.new()
	fps_hbox.add_theme_constant_override("separation", 8)

	var fps_option = OptionButton.new()
	fps_option.name = "FPSOptionButton"
	fps_option.custom_minimum_size = Vector2(140, 36)
	fps_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_option.add_item("Auto-Detect", 0)
	fps_option.add_item("30 FPS", 1)
	fps_option.add_item("60 FPS", 2)
	fps_option.add_item("120 FPS", 3)
	fps_option.add_item("Custom", 4)

	var current_mode: String = GlobalSettings.range_settings.putting_camera_fps_mode.value if has_node("/root/GlobalSettings") else "Auto"
	match current_mode:
		"Auto": fps_option.select(0)
		"30": fps_option.select(1)
		"60": fps_option.select(2)
		"120": fps_option.select(3)
		"Custom": fps_option.select(4)

	var custom_fps_spin = SpinBox.new()
	custom_fps_spin.name = "CustomFPSSpinBox"
	custom_fps_spin.min_value = 15
	custom_fps_spin.max_value = 240
	custom_fps_spin.step = 1
	custom_fps_spin.value = float(GlobalSettings.range_settings.putting_camera_fps.value) if has_node("/root/GlobalSettings") else 30
	custom_fps_spin.custom_minimum_size = Vector2(80, 36)
	custom_fps_spin.visible = (current_mode == "Custom")
	custom_fps_spin.suffix = " Hz"

	fps_option.item_selected.connect(func(idx: int):
		var modes = ["Auto", "30", "60", "120", "Custom"]
		var mode = modes[idx] if idx < modes.size() else "Auto"
		if has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.putting_camera_fps_mode.set_value(mode)
			GlobalSettings.save_settings()
		custom_fps_spin.visible = (mode == "Custom")
		_apply_putting_camera_fps()
	)

	custom_fps_spin.value_changed.connect(func(val: float):
		if has_node("/root/GlobalSettings"):
			GlobalSettings.range_settings.putting_camera_fps.set_value(int(val))
			GlobalSettings.save_settings()
		_apply_putting_camera_fps()
	)

	fps_hbox.add_child(fps_option)
	fps_hbox.add_child(custom_fps_spin)
	vbox.add_child(fps_hbox)

	var fps_note = Label.new()
	fps_note.text = "⚠️ Wi-Fi cams may drop frames. Lock FPS manually for consistent putt speed readings."
	fps_note.add_theme_font_size_override("font_size", 11)
	fps_note.add_theme_color_override("font_color", Color(0.8, 0.65, 0.3))
	fps_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(fps_note)

	# Section 4: Camera Orientation Rotation
	var rot_sep = HSeparator.new()
	rot_sep.add_theme_constant_override("separation", 8)
	vbox.add_child(rot_sep)

	var rot_label = Label.new()
	rot_label.text = "4. Camera Orientation Rotation:"
	rot_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(rot_label)

	var rot_hbox = HBoxContainer.new()
	rot_hbox.add_theme_constant_override("separation", 8)
	for deg in [0, 90, 180, 270]:
		var r_btn = Button.new()
		r_btn.text = "%d°" % deg
		r_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r_btn.custom_minimum_size = Vector2(0, 34)
		apply_material_button_style(r_btn, Color(0.22, 0.45, 0.55, 0.9) if _camera_rotation_deg == deg else Color(0.2, 0.25, 0.32, 0.8))
		r_btn.pressed.connect(func(d=deg):
			_camera_rotation_deg = d
			_update_camera_rotate_button_text()
			if _putting_state_machine != null:
				_putting_state_machine.reset()
			popup.queue_free()
		)
		rot_hbox.add_child(r_btn)
	vbox.add_child(rot_hbox)

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

	# Reset texture and material so uninitialized/broken textures are removed
	if _camera_feed_rect != null:
		_camera_feed_rect.material = null
		if not (_camera_feed_rect.texture is ImageTexture):
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
	if not _should_camera_feed_be_active() or _phone_cam_url.is_empty() or _http_req == null or _is_requesting_frame:
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
			if _camera_rotation_deg != 0:
				_apply_image_rotation(img, _camera_rotation_deg)
			var tex = ImageTexture.create_from_image(img)
			if _camera_feed_rect != null:
				_camera_feed_rect.texture = tex
			_update_status_overlay("", false)
			if _is_putting_cam_enabled and _putting_state_machine != null:
				_putting_state_machine.process_frame(img)
		else:
			_try_fallback_endpoint_or_error(result, response_code, "Invalid image encoding received")
	else:
		_try_fallback_endpoint_or_error(result, response_code, "")

	if _should_camera_feed_be_active() and not _phone_cam_url.is_empty():
		var delay = 0.005 if _phone_stream_failed_count == 0 else clamp(0.4 * _phone_stream_failed_count, 0.4, 2.0)
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
		if _camera_feed_rect != null:
			_camera_feed_rect.material = null
			if not (_camera_feed_rect.texture is ImageTexture):
				_camera_feed_rect.texture = null
		_update_status_overlay("📡 PHONE STREAM DISCONNECTED\n" + err_detail + "\n[ Click ⚙️ Setup to reconfigure ]", true)


func _update_tooltips() -> void:
	if not has_node("/root/KeybindingManager"):
		return
	var km = get_node("/root/KeybindingManager")
	if _stats_btn != null and is_instance_valid(_stats_btn):
		_stats_btn.tooltip_text = "Toggle Stats (Show/Hide) [%s]" % km.get_action_summary_str("toggle_stats")
	if _map_btn != null and is_instance_valid(_map_btn):
		_map_btn.tooltip_text = "Toggle Map View [%s]" % km.get_action_summary_str("aerial_aim")
	if _hide_helpers_btn != null and is_instance_valid(_hide_helpers_btn):
		_hide_helpers_btn.tooltip_text = "Toggle Helpers (Show/Hide) [%s]" % km.get_action_summary_str("toggle_helpers")
	if _skip_btn != null and is_instance_valid(_skip_btn):
		_skip_btn.tooltip_text = "Skip Flight [%s]" % km.get_action_summary_str("skip_flight")
	if _announcer_btn != null and is_instance_valid(_announcer_btn):
		_announcer_btn.tooltip_text = "Toggle Announcer Commentary [%s]" % km.get_action_summary_str("announcer_toggle")
	if _tension_btn != null and is_instance_valid(_tension_btn):
		_tension_btn.tooltip_text = "Toggle Suspense Heartbeat & Tunnel Vision [%s]" % km.get_action_summary_str("suspense_toggle")
	if _golfer_cam_btn != null and is_instance_valid(_golfer_cam_btn):
		_golfer_cam_btn.tooltip_text = "Toggle Golfer Camera [%s]" % km.get_action_summary_str("golfer_cam_toggle")
	if _putting_cam_btn != null and is_instance_valid(_putting_cam_btn):
		_putting_cam_btn.tooltip_text = "Toggle Putting Camera [%s]" % km.get_action_summary_str("putting_cam_toggle")
	if _shot_analysis_btn != null and is_instance_valid(_shot_analysis_btn):
		_shot_analysis_btn.tooltip_text = "Toggle Shot Suggestions & Flaw Analysis [%s]" % km.get_action_summary_str("shot_analysis_toggle")
	if _prev_shot_btn != null and is_instance_valid(_prev_shot_btn):
		_prev_shot_btn.tooltip_text = "View analysis and recommendations for your previous shot [%s]" % km.get_action_summary_str("prev_shot_analysis_toggle")
	if _dist_btn != null and is_instance_valid(_dist_btn):
		_dist_btn.tooltip_text = "Hit Distance Menu [%s]" % km.get_action_summary_str("distance_menu_toggle")


func update_announcer_button_state() -> void:
	if _announcer_btn == null or not is_instance_valid(_announcer_btn):
		return
	var a = get_node_or_null("/root/AnnouncerEngine")
	var is_announcer_on = a.get("AnnouncerRange") if a != null else false
	if is_announcer_on:
		_announcer_btn.text = "🎙 Announcer: ON"
		apply_material_button_style(_announcer_btn, Color(0.2, 0.6, 0.3, 0.85))
	else:
		_announcer_btn.text = "🎙 Announcer: MUTED"
		apply_material_button_style(_announcer_btn, Color(0.5, 0.5, 0.5, 0.85))


func update_suspense_button_state() -> void:
	if _tension_btn == null or not is_instance_valid(_tension_btn):
		return
	var is_tension_on = GlobalSettings.range_settings.tension_effects_enabled.value if has_node("/root/GlobalSettings") else true
	if is_tension_on:
		_tension_btn.text = "💓 Suspense: ON"
		apply_material_button_style(_tension_btn, Color(0.75, 0.2, 0.3, 0.85))
	else:
		_tension_btn.text = "💓 Suspense: OFF"
		apply_material_button_style(_tension_btn, Color(0.5, 0.5, 0.5, 0.85))


func toggle_distance_menu() -> void:
	if _dist_btn != null and is_instance_valid(_dist_btn):
		_dist_btn.emit_signal("pressed")
