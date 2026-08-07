extends Node3D

var hud_player_name_lbl: Label = null
var hud_player_badge: PanelContainer = null
var hud_player_badge_lbl: Label = null
var hud_overall_score_lbl: Label = null
var hud_hole_num_lbl: Label = null
var hud_shots_rtl: RichTextLabel = null
var _minimap_group: HBoxContainer = null
var _distance_tracker_panel: Container = null
var _back_lbl: Label = null
var _hole_lbl: Label = null
var _front_lbl: Label = null

var _last_hud_strokes: int = -1
var _last_hud_player_name: String = ""
var _last_hud_hole_index: int = -1

@onready var hud_scorecard = Panel.new()
@onready var scorecard_grid = GridContainer.new()
@onready var hud_manage_players = Panel.new()
@onready var hud_overview = Panel.new()
var _minimap_camera: Camera3D = null
var _minimap_panel: PanelContainer = null
var minimap_zoom: float = 300.0
var _last_was_on_green: bool = false
var _default_non_green_minimap_zoom: float = 300.0

var _overlay_node: Control = null
var _player_map_markers: Dictionary = {}
var _cached_player_textures: Dictionary = {}

var range_ui: Control = null
var top_bar: HBoxContainer = null
var right_panel: VBoxContainer = null
var settings_btn: Button = null

var course_instance: Node = null
var active_ball: Node = null
var mulligan_confirm_dialog: PanelContainer = null

func _ready() -> void:
	MultiplayerManager.active_player_changed.connect(_on_active_player_changed)
	MultiplayerManager.hole_completed.connect(_on_hole_completed)
	MultiplayerManager.game_over.connect(_on_game_over)
	
	if get_parent() != null and get_parent() != get_tree().get_root() and get_parent().name != "CourseManager":
		course_instance = get_parent()
	else:
		var current_scene = get_tree().current_scene
		if current_scene != null and current_scene.name == "CourseManager":
			var course_nodes = current_scene.get_children()
			if not course_nodes.is_empty():
				course_instance = course_nodes[0]
			
	if course_instance != null:
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			active_ball = player_node.get("ball")

	_setup_hud()

	# Start first player's turn
	_on_active_player_changed(MultiplayerManager.get_active_player())


func _setup_hud() -> void:
	range_ui = null
	if course_instance != null:
		range_ui = course_instance.get_node_or_null("RangeUI")
		if range_ui != null:
			var r_top_bar = range_ui.get_node_or_null("HBoxContainer")
			if r_top_bar != null:
				r_top_bar.visible = false
			if range_ui.has_signal("manage_players_requested") and not range_ui.manage_players_requested.is_connected(_on_manage_players_toggle_pressed):
				range_ui.manage_players_requested.connect(_on_manage_players_toggle_pressed)

	var canvas = CanvasLayer.new()
	canvas.layer = 15 # Render on top of VignetteLayer (layer 10)
	add_child(canvas)
	
	_overlay_node = MultiplayerBallOverlay.new(self)
	canvas.add_child(_overlay_node)
	
	mulligan_confirm_dialog = PanelContainer.new()
	mulligan_confirm_dialog.name = "MulliganConfirmDialog"
	mulligan_confirm_dialog.visible = false
	
	mulligan_confirm_dialog.anchor_left = 0.5
	mulligan_confirm_dialog.anchor_right = 0.5
	mulligan_confirm_dialog.anchor_top = 0.5
	mulligan_confirm_dialog.anchor_bottom = 0.5
	mulligan_confirm_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mulligan_confirm_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	mulligan_confirm_dialog.offset_left = -220
	mulligan_confirm_dialog.offset_right = 220
	mulligan_confirm_dialog.offset_top = -100
	mulligan_confirm_dialog.offset_bottom = 100
	
	var dialog_style = StyleBoxFlat.new()
	dialog_style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	dialog_style.border_width_left = 2
	dialog_style.border_width_top = 2
	dialog_style.border_width_right = 2
	dialog_style.border_width_bottom = 2
	dialog_style.border_color = Color(0.25, 0.25, 0.25, 0.8)
	dialog_style.corner_radius_top_left = 12
	dialog_style.corner_radius_top_right = 12
	dialog_style.corner_radius_bottom_left = 12
	dialog_style.corner_radius_bottom_right = 12
	dialog_style.content_margin_left = 24
	dialog_style.content_margin_top = 24
	dialog_style.content_margin_right = 24
	dialog_style.content_margin_bottom = 24
	mulligan_confirm_dialog.add_theme_stylebox_override("panel", dialog_style)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 20)
	
	var title_lbl = Label.new()
	title_lbl.text = "Confirm Mulligan"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.24, 0.46, 0.72, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 4)
	content_vbox.add_child(title_lbl)
	
	var msg_lbl = Label.new()
	msg_lbl.text = "Are you sure you want to take a mulligan?\nThis will undo your last shot."
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.add_theme_font_size_override("font_size", 20)
	msg_lbl.add_theme_color_override("font_color", Color.WHITE)
	msg_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_lbl.add_theme_constant_override("outline_size", 4)
	content_vbox.add_child(msg_lbl)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 24)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var confirm_btn = Button.new()
	confirm_btn.text = "Yes, Undo"
	confirm_btn.custom_minimum_size = Vector2(140, 50)
	apply_material_button_style(confirm_btn, Color(0.24, 0.46, 0.72, 0.85))
	confirm_btn.pressed.connect(func():
		mulligan_confirm_dialog.visible = false
		_on_mulligan_confirmed()
	)
	btn_hbox.add_child(confirm_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 50)
	apply_material_button_style(cancel_btn, Color(0.56, 0.22, 0.22, 0.85))
	cancel_btn.pressed.connect(func():
		mulligan_confirm_dialog.visible = false
	)
	btn_hbox.add_child(cancel_btn)
	
	content_vbox.add_child(btn_hbox)
	mulligan_confirm_dialog.add_child(content_vbox)
	canvas.add_child(mulligan_confirm_dialog)
	
	var margin = MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 90) # Leave room for settings button
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(margin)
	
	top_bar = HBoxContainer.new()
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(top_bar)
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.08, 0.8) # Transparent gray matching data/stats panels
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.25, 0.25, 0.25, 0.8) # Sleek border matching stats panel
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_bottom = 6.0
	
	# --- Top-Left Unified HUD Widget Construction ---
	var hud_widget = VBoxContainer.new()
	hud_widget.name = "TopLeftHUDWidget"
	hud_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_widget.custom_minimum_size = Vector2(380, 80)
	hud_widget.add_theme_constant_override("separation", 0)
	top_bar.add_child(hud_widget)
	
	# Row 1: Player Name (Left) | Overall Score (Right)
	var row1 = HBoxContainer.new()
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_theme_constant_override("separation", 0)
	hud_widget.add_child(row1)
	
	# Player Name Panel
	var player_name_panel = PanelContainer.new()
	player_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_name_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p_name_style = StyleBoxFlat.new()
	p_name_style.bg_color = Color(0.36, 0.39, 0.44) # Slate gray (#5c6470)
	p_name_style.corner_radius_top_left = 12
	p_name_style.corner_radius_top_right = 0
	p_name_style.corner_radius_bottom_right = 0
	p_name_style.corner_radius_bottom_left = 0
	p_name_style.border_width_bottom = 1
	p_name_style.border_color = Color(0.25, 0.27, 0.31)
	p_name_style.content_margin_left = 16.0
	p_name_style.content_margin_top = 8.0
	p_name_style.content_margin_right = 16.0
	p_name_style.content_margin_bottom = 8.0
	player_name_panel.add_theme_stylebox_override("panel", p_name_style)
	
	var p_hbox = HBoxContainer.new()
	p_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p_hbox.add_theme_constant_override("separation", 10)
	p_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_name_panel.add_child(p_hbox)
	
	hud_player_badge = PanelContainer.new()
	hud_player_badge.custom_minimum_size = Vector2(26, 26)
	hud_player_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = Color(0.5, 0.5, 0.5)
	badge_style.corner_radius_top_left = 13
	badge_style.corner_radius_top_right = 13
	badge_style.corner_radius_bottom_left = 13
	badge_style.corner_radius_bottom_right = 13
	badge_style.content_margin_left = 4
	badge_style.content_margin_right = 4
	badge_style.content_margin_top = 2
	badge_style.content_margin_bottom = 2
	hud_player_badge.add_theme_stylebox_override("panel", badge_style)
	p_hbox.add_child(hud_player_badge)
	
	hud_player_badge_lbl = Label.new()
	hud_player_badge_lbl.text = "P"
	hud_player_badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_player_badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hud_player_badge_lbl.add_theme_font_size_override("font_size", 13)
	hud_player_badge_lbl.add_theme_color_override("font_color", Color.WHITE)
	hud_player_badge_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_player_badge_lbl.add_theme_constant_override("outline_size", 3)
	hud_player_badge.add_child(hud_player_badge_lbl)
	
	hud_player_name_lbl = Label.new()
	hud_player_name_lbl.name = "PlayerNameLabel"
	hud_player_name_lbl.text = "Sterling Kohel"
	hud_player_name_lbl.add_theme_font_size_override("font_size", 24)
	hud_player_name_lbl.add_theme_color_override("font_color", Color.WHITE)
	hud_player_name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_player_name_lbl.add_theme_constant_override("outline_size", 4)
	p_hbox.add_child(hud_player_name_lbl)
	row1.add_child(player_name_panel)
	
	# Overall Score Panel
	var overall_score_panel = PanelContainer.new()
	overall_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overall_score_panel.custom_minimum_size = Vector2(90, 0)
	var o_score_style = StyleBoxFlat.new()
	o_score_style.bg_color = Color(0.1, 0.1, 0.1) # Black (#1a1a1a)
	o_score_style.corner_radius_top_left = 0
	o_score_style.corner_radius_top_right = 12
	o_score_style.corner_radius_bottom_right = 0
	o_score_style.corner_radius_bottom_left = 0
	o_score_style.border_width_bottom = 1
	o_score_style.border_color = Color(0.06, 0.06, 0.06)
	o_score_style.content_margin_left = 12.0
	o_score_style.content_margin_top = 8.0
	o_score_style.content_margin_right = 12.0
	o_score_style.content_margin_bottom = 8.0
	overall_score_panel.add_theme_stylebox_override("panel", o_score_style)
	
	hud_overall_score_lbl = Label.new()
	hud_overall_score_lbl.name = "OverallScoreLabel"
	hud_overall_score_lbl.text = "+11"
	hud_overall_score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_overall_score_lbl.add_theme_font_size_override("font_size", 26)
	hud_overall_score_lbl.add_theme_color_override("font_color", Color.WHITE)
	hud_overall_score_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	hud_overall_score_lbl.add_theme_constant_override("outline_size", 4)
	overall_score_panel.add_child(hud_overall_score_lbl)
	row1.add_child(overall_score_panel)
	
	# Row 2: Hole Number (Left) | Shots & Par Tracker (Right)
	var row2 = HBoxContainer.new()
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row2.add_theme_constant_override("separation", 0)
	hud_widget.add_child(row2)
	
	# Hole Number Panel
	var hole_num_panel = PanelContainer.new()
	hole_num_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hole_num_panel.custom_minimum_size = Vector2(70, 0) # Narrow white box
	var h_num_style = StyleBoxFlat.new()
	h_num_style.bg_color = Color.WHITE
	h_num_style.corner_radius_top_left = 0
	h_num_style.corner_radius_top_right = 0
	h_num_style.corner_radius_bottom_right = 0
	h_num_style.corner_radius_bottom_left = 12
	h_num_style.content_margin_left = 12.0
	h_num_style.content_margin_top = 6.0
	h_num_style.content_margin_right = 12.0
	h_num_style.content_margin_bottom = 6.0
	hole_num_panel.add_theme_stylebox_override("panel", h_num_style)
	
	hud_hole_num_lbl = Label.new()
	hud_hole_num_lbl.name = "HoleNumLabel"
	hud_hole_num_lbl.text = "8"
	hud_hole_num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_hole_num_lbl.add_theme_font_size_override("font_size", 26)
	hud_hole_num_lbl.add_theme_color_override("font_color", Color.BLACK) # Black text
	hole_num_panel.add_child(hud_hole_num_lbl)
	row2.add_child(hole_num_panel)
	
	# Shots Panel
	var shots_panel = PanelContainer.new()
	shots_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shots_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var shots_style = StyleBoxFlat.new()
	shots_style.bg_color = Color(0.18, 0.20, 0.23) # Dark slate-gray (#2d323b)
	shots_style.corner_radius_top_left = 0
	shots_style.corner_radius_top_right = 0
	shots_style.corner_radius_bottom_right = 12
	shots_style.corner_radius_bottom_left = 0
	shots_style.content_margin_left = 16.0
	shots_style.content_margin_top = 8.0
	shots_style.content_margin_right = 16.0
	shots_style.content_margin_bottom = 8.0
	shots_panel.add_theme_stylebox_override("panel", shots_style)
	
	hud_shots_rtl = RichTextLabel.new()
	hud_shots_rtl.name = "ShotsRichTextLabel"
	hud_shots_rtl.bbcode_enabled = true
	hud_shots_rtl.scroll_active = false
	hud_shots_rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
	hud_shots_rtl.custom_minimum_size = Vector2(0, 36)
	hud_shots_rtl.add_theme_font_size_override("normal_font_size", 22)
	hud_shots_rtl.add_theme_font_size_override("bold_font_size", 22)
	hud_shots_rtl.add_theme_font_size_override("bold_italics_font_size", 22)
	hud_shots_rtl.add_theme_font_size_override("italics_font_size", 22)
	hud_shots_rtl.add_theme_color_override("default_color", Color.WHITE)
	shots_panel.add_child(hud_shots_rtl)
	row2.add_child(shots_panel)

	# Settings Button (Icon Only) - Top-Right Corner, enlarged for touch
	settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.icon = load("res://Utils/Settings/Gear.png")
	settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.custom_minimum_size = Vector2(56, 56)
	apply_circular_button_style(settings_btn, Color(0.15, 0.15, 0.15, 0.85))
	settings_btn.anchor_left = 1.0
	settings_btn.anchor_right = 1.0
	settings_btn.offset_left = -86
	settings_btn.offset_top = 24
	settings_btn.offset_right = -30
	settings_btn.offset_bottom = 80
	settings_btn.pressed.connect(func():
		if range_ui != null:
			range_ui.call("_on_toggle_settings_requested")
	)
	canvas.add_child(settings_btn)

	# RightPanel vertical stack - starts below the settings cog button
	right_panel = VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_top = 0.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -220
	right_panel.offset_top = 96
	right_panel.offset_right = -24
	right_panel.offset_bottom = -24
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_panel.add_theme_constant_override("separation", 12)
	canvas.add_child(right_panel)

	# Hide Toggles Button - tall touch target
	var hide_toggles_btn = Button.new()
	hide_toggles_btn.name = "HideTogglesButton"
	hide_toggles_btn.text = "👁 Hide Toggles"
	hide_toggles_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(hide_toggles_btn, Color(0.2, 0.2, 0.2, 0.85))
	
	# ScrollContainer keeps buttons visible on short screens
	var toggles_scroll = ScrollContainer.new()
	toggles_scroll.name = "TogglesScroll"
	toggles_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	toggles_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toggles_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	
	var toggles_container = VBoxContainer.new()
	toggles_container.name = "TogglesContainer"
	toggles_container.add_theme_constant_override("separation", 12)
	toggles_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	hide_toggles_btn.pressed.connect(func():
		toggles_scroll.visible = not toggles_scroll.visible
		if toggles_scroll.visible:
			hide_toggles_btn.text = "👁 Hide Toggles"
		else:
			hide_toggles_btn.text = "👁 Show Toggles"
	)
	
	toggles_scroll.add_child(toggles_container)
	right_panel.add_child(hide_toggles_btn)
	right_panel.add_child(toggles_scroll)

	# Main Menu Button
	var menu_btn = Button.new()
	menu_btn.name = "MainMenuButton"
	menu_btn.text = "⌂ Main Menu"
	menu_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(menu_btn, Color(0.56, 0.22, 0.22, 0.85))
	menu_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
	toggles_container.add_child(menu_btn)

	# Distance Menu setup
	var distance_menu_script = load("res://UI/distance_menu.gd")
	var dist_menu = distance_menu_script.new()
	dist_menu.name = "DistanceMenu"
	dist_menu.visible = false
	dist_menu.inject_shot.connect(func(data):
		var player_node = course_instance.get_node_or_null("Player") if course_instance != null else null
		if player_node != null:
			course_instance.call("_on_range_ui_hit_shot", data)
			player_node.call("_on_range_ui_hit_shot", data)
	)
	
	# Distance Menu Button
	var dist_btn = Button.new()
	dist_btn.name = "HitDistanceButton"
	dist_btn.text = "🎯 Hit Distance"
	dist_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(dist_btn, Color(0.6, 0.2, 0.6, 0.85))
	dist_btn.pressed.connect(func():
		if dist_menu:
			dist_menu.visible = not dist_menu.visible
			if dist_menu.visible:
				dist_menu.current_ball_node = active_ball
				if course_instance != null and "aim_target_pos" in course_instance:
					dist_menu.aim_target_node = course_instance.get("aim_target_pos")
	)
	toggles_container.add_child(dist_btn)
	toggles_container.add_child(dist_menu)

	# Stats Toggle Button
	var stats_btn = Button.new()
	stats_btn.name = "StatsButton"
	stats_btn.text = "📊 Hide Stats"
	stats_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(stats_btn, Color(0.24, 0.46, 0.72, 0.85)) # Blue
	stats_btn.pressed.connect(func():
		if range_ui != null:
			range_ui.call("toggle_stats_visibility")
			if range_ui.call("is_stats_visible"):
				stats_btn.text = "📊 Hide Stats"
			else:
				stats_btn.text = "📊 Show Stats"
	)
	toggles_container.add_child(stats_btn)

	# Golfer Cam Toggle Button
	var golfer_cam_btn = Button.new()
	golfer_cam_btn.name = "GolferCamButton"
	golfer_cam_btn.text = "📹 Golfer Cam: OFF"
	golfer_cam_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(golfer_cam_btn, Color(0.2, 0.45, 0.45, 0.85))
	golfer_cam_btn.pressed.connect(func():
		if range_ui != null and range_ui.has_method("set_golfer_camera_visible"):
			var is_vis = not range_ui.call("is_golfer_camera_visible")
			range_ui.call("set_golfer_camera_visible", is_vis)
			if is_vis:
				golfer_cam_btn.text = "📹 Golfer Cam: ON"
				apply_material_button_style(golfer_cam_btn, Color(0.15, 0.6, 0.5, 0.85))
			else:
				golfer_cam_btn.text = "📹 Golfer Cam: OFF"
				apply_material_button_style(golfer_cam_btn, Color(0.2, 0.45, 0.45, 0.85))
	)
	toggles_container.add_child(golfer_cam_btn)

	# Sky View Toggle Button
	var sky_view_btn = Button.new()
	sky_view_btn.name = "SkyViewButton"
	sky_view_btn.text = "☁ Sky View"
	sky_view_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(sky_view_btn, Color(0.4, 0.6, 0.8, 0.85)) # Light blue
	sky_view_btn.pressed.connect(func():
		if course_instance and course_instance.has_method("toggle_sky_view"):
			course_instance.call("toggle_sky_view")
			var is_sky = course_instance.get("is_sky_view_active")
			if is_sky:
				apply_material_button_style(sky_view_btn, Color(0.2, 0.8, 0.9, 0.85))
			else:
				apply_material_button_style(sky_view_btn, Color(0.4, 0.6, 0.8, 0.85))
	)
	toggles_container.add_child(sky_view_btn)

	var is_match_play = not MultiplayerManager.players.is_empty() and not MultiplayerManager.practice_mode_active

	if is_match_play:
		# Scorecard Toggle Button
		var scorecard_btn = Button.new()
		scorecard_btn.name = "ScorecardToggleButton"
		scorecard_btn.text = "📋 Scorecard"
		scorecard_btn.custom_minimum_size = Vector2(180, 40)
		apply_material_button_style(scorecard_btn, Color(0.72, 0.56, 0.24, 0.85)) # Gold color
		scorecard_btn.pressed.connect(_on_scorecard_toggle_pressed)
		toggles_container.add_child(scorecard_btn)

		# Manage Players Toggle Button
		var players_btn = Button.new()
		players_btn.name = "ManagePlayersButton"
		players_btn.text = "👥 Players"
		players_btn.custom_minimum_size = Vector2(180, 40)
		apply_material_button_style(players_btn, Color(0.25, 0.55, 0.35, 0.85)) # Green-ish
		players_btn.pressed.connect(_on_manage_players_toggle_pressed)
		toggles_container.add_child(players_btn)

		# Mulligan Button
		var mulligan_btn = Button.new()
		mulligan_btn.name = "MulliganButton"
		mulligan_btn.text = "↺ Mulligan"
		mulligan_btn.custom_minimum_size = Vector2(180, 40)
		apply_material_button_style(mulligan_btn, Color(0.24, 0.46, 0.72, 0.85))
		mulligan_btn.pressed.connect(_on_mulligan_pressed)
		toggles_container.add_child(mulligan_btn)

	# Map Toggle Button
	var map_btn = Button.new()
	map_btn.name = "MapButton"
	map_btn.text = "🗺 Toggle Map View"
	map_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(map_btn, Color(0.18, 0.45, 0.25, 0.85)) # Forest green
	map_btn.pressed.connect(func():
		if course_instance and course_instance.has_method("_on_map_button_pressed"):
			course_instance.call("_on_map_button_pressed")
	)
	toggles_container.add_child(map_btn)

	# Green Grid Toggle Button
	var grid_btn = Button.new()
	grid_btn.name = "GreenGridToggleButton"
	grid_btn.text = "📊 Slope Grid: OFF"
	grid_btn.custom_minimum_size = Vector2(180, 56)
	apply_material_button_style(grid_btn, Color(0.5, 0.5, 0.5, 0.85)) # Gray by default
	grid_btn.pressed.connect(func():
		if course_instance != null and course_instance.get("show_green_grid") != null:
			var current_grid = course_instance.get("show_green_grid") as bool
			course_instance.set("show_green_grid", not current_grid)
	)
	toggles_container.add_child(grid_btn)

	# If in practice mode, create practice buttons (initially hidden, shown only in map view)
	if MultiplayerManager.practice_mode_active and not GlobalSettings.is_chipping_minigame:
		var place_btn = Button.new()
		place_btn.name = "PlaceBallButton"
		place_btn.text = "📍 Place Ball: OFF"
		place_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(place_btn, Color(0.5, 0.5, 0.5, 0.85)) # Gray by default
		place_btn.pressed.connect(func():
			if course_instance != null:
				var current_mode = course_instance.get("place_ball_mode")
				var new_mode = not current_mode
				course_instance.set("place_ball_mode", new_mode)
				if new_mode:
					place_btn.text = "📍 Place Ball: ON"
					apply_material_button_style(place_btn, Color(0.2, 0.6, 0.3, 0.85)) # Green when ON
				else:
					place_btn.text = "📍 Place Ball: OFF"
					apply_material_button_style(place_btn, Color(0.5, 0.5, 0.5, 0.85))
		)
		place_btn.visible = false # Hidden initially
		toggles_container.add_child(place_btn)
		
		var prev_btn = Button.new()
		prev_btn.name = "PrevHoleButton"
		prev_btn.text = "❮ Previous Hole"
		prev_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(prev_btn, Color(0.4, 0.4, 0.4, 0.85))
		prev_btn.pressed.connect(func():
			if course_instance != null and course_instance.has_method("prev_practice_hole"):
				course_instance.call("prev_practice_hole")
		)
		prev_btn.visible = false
		toggles_container.add_child(prev_btn)
		
		var next_btn = Button.new()
		next_btn.name = "NextHoleButton"
		next_btn.text = "❯ Next Hole"
		next_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(next_btn, Color(0.4, 0.4, 0.4, 0.85))
		next_btn.pressed.connect(func():
			if course_instance != null and course_instance.has_method("next_practice_hole"):
				course_instance.call("next_practice_hole")
		)
		next_btn.visible = false
		toggles_container.add_child(next_btn)
		
		# Move them after MainMenuButton so they are ordered nicely
		var menu_idx = menu_btn.get_index()
		toggles_container.move_child(place_btn, menu_idx + 1)
		toggles_container.move_child(prev_btn, menu_idx + 2)
		toggles_container.move_child(next_btn, menu_idx + 3)
	
	# Reparent ClubSelector to right panel directly under HitDistanceButton / DistanceMenu
	if range_ui != null:
		var club_sel = range_ui.get_node_or_null("GridCanvas/ClubSelector")
		if club_sel == null:
			club_sel = range_ui.get_node_or_null("RightPanel/TogglesScroll/TogglesContainer/ClubSelector")
			if club_sel == null:
				club_sel = range_ui.get_node_or_null("RightPanel/TogglesContainer/ClubSelector")
			if club_sel == null:
				club_sel = range_ui.get_node_or_null("RightPanel/ClubSelector")
		if club_sel != null:
			club_sel.reparent(toggles_container)
			club_sel.custom_minimum_size = Vector2(180, 56)
			club_sel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			var dist_menu_node = toggles_container.get_node_or_null("DistanceMenu")
			if dist_menu_node != null:
				toggles_container.move_child(club_sel, dist_menu_node.get_index() + 1)
			else:
				var dist_btn_node = toggles_container.get_node_or_null("HitDistanceButton")
				if dist_btn_node != null:
					toggles_container.move_child(club_sel, dist_btn_node.get_index() + 1)
	
	# --- Minimap Viewport Construction ---
	# HBoxContainer grouping minimap and distance tracker side by side
	_minimap_group = HBoxContainer.new()
	_minimap_group.name = "MinimapGroup"
	_minimap_group.position = Vector2(30, 160)
	_minimap_group.add_theme_constant_override("separation", 8)
	_minimap_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(_minimap_group)
	
	var minimap_panel = PanelContainer.new()
	minimap_panel.name = "MinimapPanel"
	var sc_style = StyleBoxFlat.new()
	sc_style.bg_color = Color(0.08, 0.08, 0.08, 0.7)
	sc_style.border_width_left = 2
	sc_style.border_width_top = 2
	sc_style.border_width_right = 2
	sc_style.border_width_bottom = 2
	sc_style.border_color = Color(0.8, 0.8, 0.8, 0.8)
	sc_style.corner_radius_top_left = 12
	sc_style.corner_radius_top_right = 12
	sc_style.corner_radius_bottom_left = 12
	sc_style.corner_radius_bottom_right = 12
	minimap_panel.add_theme_stylebox_override("panel", sc_style)
	minimap_panel.custom_minimum_size = Vector2(184, 184)
	minimap_panel.size = Vector2(184, 184)
	_minimap_group.add_child(minimap_panel)
	
	# --- Distance Tracker Panel ---
	_distance_tracker_panel = PanelContainer.new()
	_distance_tracker_panel.name = "DistanceTrackerPanel"
	var dt_style = StyleBoxFlat.new()
	dt_style.bg_color = Color(0.08, 0.08, 0.08, 0.7)
	dt_style.border_width_left = 2
	dt_style.border_width_top = 2
	dt_style.border_width_right = 2
	dt_style.border_width_bottom = 2
	dt_style.border_color = Color(0.8, 0.8, 0.8, 0.8)
	dt_style.corner_radius_top_left = 12
	dt_style.corner_radius_top_right = 12
	dt_style.corner_radius_bottom_left = 12
	dt_style.corner_radius_bottom_right = 12
	dt_style.content_margin_left = 12
	dt_style.content_margin_right = 12
	dt_style.content_margin_top = 10
	dt_style.content_margin_bottom = 10
	_distance_tracker_panel.add_theme_stylebox_override("panel", dt_style)
	_distance_tracker_panel.custom_minimum_size = Vector2(80, 184)
	_distance_tracker_panel.size = Vector2(80, 184)
	_minimap_group.add_child(_distance_tracker_panel)
	
	var dt_vbox = VBoxContainer.new()
	dt_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dt_vbox.add_theme_constant_override("separation", 14) # stack vertically
	_distance_tracker_panel.add_child(dt_vbox)
	
	var front_green_label = Label.new()
	front_green_label.name = "FrontGreenLabel"
	front_green_label.text = "---"
	front_green_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	front_green_label.add_theme_font_size_override("font_size", 24)
	front_green_label.add_theme_color_override("font_color", Color.WHITE)
	front_green_label.add_theme_color_override("font_outline_color", Color.BLACK)
	front_green_label.add_theme_constant_override("outline_size", 4)
	_front_lbl = front_green_label
	dt_vbox.add_child(front_green_label)
	
	var mid_hbox = HBoxContainer.new()
	mid_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	mid_hbox.add_theme_constant_override("separation", 4)
	dt_vbox.add_child(mid_hbox)
	
	var flag_label = Label.new()
	flag_label.text = "⚑"
	flag_label.add_theme_font_size_override("font_size", 26)
	flag_label.add_theme_color_override("font_color", Color(0.9, 0.45, 0.1)) # Orange flag
	flag_label.add_theme_color_override("font_outline_color", Color.BLACK)
	flag_label.add_theme_constant_override("outline_size", 4)
	mid_hbox.add_child(flag_label)
	
	var hole_label = Label.new()
	hole_label.name = "HoleLabel"
	hole_label.text = "---"
	hole_label.add_theme_font_size_override("font_size", 28)
	hole_label.add_theme_color_override("font_color", Color(0.9, 0.45, 0.1)) # Orange/Accent
	hole_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hole_label.add_theme_constant_override("outline_size", 4)
	_hole_lbl = hole_label
	mid_hbox.add_child(hole_label)
	
	var back_green_label = Label.new()
	back_green_label.name = "BackGreenLabel"
	back_green_label.text = "---"
	back_green_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_green_label.add_theme_font_size_override("font_size", 24)
	back_green_label.add_theme_color_override("font_color", Color.WHITE)
	back_green_label.add_theme_color_override("font_outline_color", Color.BLACK)
	back_green_label.add_theme_constant_override("outline_size", 4)
	_back_lbl = back_green_label
	dt_vbox.add_child(back_green_label)
	
	var minimap_container = SubViewportContainer.new()
	minimap_container.custom_minimum_size = Vector2(180, 180)
	minimap_container.size = Vector2(180, 180)
	
	var viewport = SubViewport.new()
	viewport.size = Vector2(180, 180)
	viewport.own_world_3d = false
	viewport.transparent_bg = false
	
	var minimap_camera = Camera3D.new()
	minimap_camera.name = "MinimapCamera"
	minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_camera.size = minimap_zoom
	minimap_camera.position = Vector3(0, 150, 0)
	minimap_camera.rotation = Vector3(-PI/2, 0, 0) # Look straight down
	
	viewport.add_child(minimap_camera)
	minimap_container.add_child(viewport)
	minimap_panel.add_child(minimap_container)
	
	# Make the camera current inside the SubViewport
	minimap_camera.make_current()
	
	_minimap_camera = minimap_camera
	_minimap_panel = minimap_panel
	
	# Add Zoom buttons to Minimap Panel
	var zoom_overlay = Control.new()
	zoom_overlay.name = "ZoomOverlay"
	zoom_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_panel.add_child(zoom_overlay)

	var zoom_vbox = VBoxContainer.new()
	zoom_vbox.name = "ZoomVBox"
	zoom_vbox.anchor_left = 1.0
	zoom_vbox.anchor_right = 1.0
	zoom_vbox.anchor_top = 0.0
	zoom_vbox.anchor_bottom = 0.0
	zoom_vbox.offset_left = -36
	zoom_vbox.offset_top = 8
	zoom_vbox.offset_right = -8
	zoom_vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom_vbox.add_theme_constant_override("separation", 6)
	zoom_overlay.add_child(zoom_vbox)

	var zoom_in_btn = Button.new()
	zoom_in_btn.name = "ZoomInButton"
	zoom_in_btn.text = "+"
	zoom_in_btn.custom_minimum_size = Vector2(28, 28)
	apply_zoom_button_style(zoom_in_btn, Color(0.15, 0.15, 0.15, 0.85))
	zoom_in_btn.pressed.connect(func():
		minimap_zoom = clamp(minimap_zoom - 25.0, 50.0, 500.0)
		if not _last_was_on_green:
			_default_non_green_minimap_zoom = minimap_zoom
		_update_minimap()
	)
	zoom_vbox.add_child(zoom_in_btn)

	var zoom_out_btn = Button.new()
	zoom_out_btn.name = "ZoomOutButton"
	zoom_out_btn.text = "-"
	zoom_out_btn.custom_minimum_size = Vector2(28, 28)
	apply_zoom_button_style(zoom_out_btn, Color(0.15, 0.15, 0.15, 0.85))
	zoom_out_btn.pressed.connect(func():
		minimap_zoom = clamp(minimap_zoom + 25.0, 50.0, 500.0)
		if not _last_was_on_green:
			_default_non_green_minimap_zoom = minimap_zoom
		_update_minimap()
	)
	zoom_vbox.add_child(zoom_out_btn)
	
	# Scorecard Panel
	hud_scorecard.visible = false
	hud_scorecard.anchor_left = 0.5
	hud_scorecard.anchor_right = 0.5
	hud_scorecard.anchor_top = 0.5
	hud_scorecard.anchor_bottom = 0.5
	hud_scorecard.offset_left = -700
	hud_scorecard.offset_right = 700
	hud_scorecard.offset_top = -280
	hud_scorecard.offset_bottom = 280
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.1, 0.15, 0.95)
	card_style.border_width_left = 2
	card_style.border_width_top = 2
	card_style.border_width_right = 2
	card_style.border_width_bottom = 2
	card_style.border_color = Color(0.72, 0.56, 0.24, 0.8) # Gold border
	card_style.corner_radius_top_left = 16
	card_style.corner_radius_top_right = 16
	card_style.corner_radius_bottom_left = 16
	card_style.corner_radius_bottom_right = 16
	card_style.content_margin_left = 24
	card_style.content_margin_right = 24
	card_style.content_margin_top = 20
	card_style.content_margin_bottom = 20
	hud_scorecard.add_theme_stylebox_override("panel", card_style)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 20)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_scorecard.add_child(vbox)
	
	var sc_title = Label.new()
	sc_title.text = "Scorecard"
	sc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc_title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(sc_title)
	
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	var center_container = CenterContainer.new()
	center_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center_container)
	
	scorecard_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scorecard_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_container.add_child(scorecard_grid)
	
	var action_btn = Button.new()
	action_btn.name = "ScorecardActionBtn"
	action_btn.text = "Next Hole"
	action_btn.custom_minimum_size = Vector2(180, 56)
	action_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apply_material_button_style(action_btn, Color(0.24, 0.46, 0.72, 0.85))
	vbox.add_child(action_btn)
	
	margin.add_child(hud_scorecard)


	# Manage Players Panel
	hud_manage_players.visible = false
	hud_manage_players.anchor_left = 0.5
	hud_manage_players.anchor_right = 0.5
	hud_manage_players.anchor_top = 0.5
	hud_manage_players.anchor_bottom = 0.5
	hud_manage_players.offset_left = -300
	hud_manage_players.offset_right = 300
	hud_manage_players.offset_top = -250
	hud_manage_players.offset_bottom = 250
	
	var manage_style = StyleBoxFlat.new()
	manage_style.bg_color = Color(0.08, 0.1, 0.15, 0.95)
	manage_style.border_width_left = 2
	manage_style.border_width_top = 2
	manage_style.border_width_right = 2
	manage_style.border_width_bottom = 2
	manage_style.border_color = Color(0.25, 0.55, 0.35, 0.8) # Green border
	manage_style.corner_radius_top_left = 16
	manage_style.corner_radius_top_right = 16
	manage_style.corner_radius_bottom_left = 16
	manage_style.corner_radius_bottom_right = 16
	manage_style.content_margin_left = 24
	manage_style.content_margin_right = 24
	manage_style.content_margin_top = 20
	manage_style.content_margin_bottom = 20
	hud_manage_players.add_theme_stylebox_override("panel", manage_style)
	
	var m_vbox = VBoxContainer.new()
	m_vbox.name = "VBoxContainer"
	m_vbox.add_theme_constant_override("separation", 15)
	m_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_manage_players.add_child(m_vbox)
	
	var m_title = Label.new()
	m_title.text = "Manage Players"
	m_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m_title.add_theme_font_size_override("font_size", 24)
	m_vbox.add_child(m_title)
	
	# ScrollContainer for player list
	var m_scroll = ScrollContainer.new()
	m_scroll.name = "ScrollContainer"
	m_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	m_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	m_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	m_vbox.add_child(m_scroll)
	
	var m_list = VBoxContainer.new()
	m_list.name = "PlayerList"
	m_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m_scroll.add_child(m_list)
	
	# Add New Player Section
	var add_section = VBoxContainer.new()
	add_section.name = "AddSection"
	add_section.add_theme_constant_override("separation", 8)
	m_vbox.add_child(add_section)
	
	var add_title = Label.new()
	add_title.text = "Add New Player"
	add_title.add_theme_font_size_override("font_size", 14)
	add_section.add_child(add_title)
	
	var add_row = HBoxContainer.new()
	add_row.name = "AddRow"
	add_row.add_theme_constant_override("separation", 10)
	add_section.add_child(add_row)
	
	var m_player_select_opt = OptionButton.new()
	m_player_select_opt.name = "PlayerSelectOpt"
	m_player_select_opt.custom_minimum_size = Vector2(160, 0)
	add_row.add_child(m_player_select_opt)
	
	var m_name_input = LineEdit.new()
	m_name_input.name = "NameInput"
	m_name_input.placeholder_text = "Player Name"
	m_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(m_name_input)
	
	m_player_select_opt.item_selected.connect(func(index):
		if index == 0:
			m_name_input.visible = true
		else:
			m_name_input.visible = false
	)
	
	var m_tee_opt = OptionButton.new()
	m_tee_opt.name = "TeeOpt"
	m_tee_opt.add_item("Blue", 0)
	m_tee_opt.add_item("Red", 1)
	m_tee_opt.add_item("White", 2)
	m_tee_opt.add_item("Black", 3)
	add_row.add_child(m_tee_opt)
	
	var m_add_btn = Button.new()
	m_add_btn.name = "AddBtn"
	m_add_btn.text = "Add Player"
	apply_material_button_style(m_add_btn, Color(0.24, 0.46, 0.72, 0.85))
	add_row.add_child(m_add_btn)
	
	m_add_btn.pressed.connect(func():
		var name_input = hud_manage_players.get_node("VBoxContainer/AddSection/AddRow/NameInput") as LineEdit
		var tee_opt = hud_manage_players.get_node("VBoxContainer/AddSection/AddRow/TeeOpt") as OptionButton
		var select_opt = hud_manage_players.get_node("VBoxContainer/AddSection/AddRow/PlayerSelectOpt") as OptionButton
		
		var p_name = ""
		if select_opt.selected == 0:
			p_name = name_input.text.strip_edges()
			if p_name.is_empty():
				p_name = "Player " + str(MultiplayerManager.players.size() + 1)
		else:
			p_name = select_opt.get_item_text(select_opt.selected)
			
		var tee_color = tee_opt.get_item_text(tee_opt.selected)
		
		MultiplayerManager.add_new_player(p_name, tee_color)
		
		# Register player globally so they persist
		MultiplayerManager.register_player(p_name)
		
		name_input.clear()
		_refresh_manage_players_dropdown()
		_populate_manage_players()
		_populate_scorecard("toggle")
	)
	
	# Close button
	var m_close_btn = Button.new()
	m_close_btn.name = "CloseBtn"
	m_close_btn.text = "Close"
	m_close_btn.custom_minimum_size = Vector2(120, 35)
	m_close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apply_material_button_style(m_close_btn, Color(0.56, 0.22, 0.22, 0.85))
	m_vbox.add_child(m_close_btn)
	
	m_close_btn.pressed.connect(func():
		hud_manage_players.visible = false
		_set_other_elements_visible(true)
	)
	
	margin.add_child(hud_manage_players)

	# Overview Panel (Game Over)
	hud_overview.name = "HUDOverview"
	hud_overview.visible = false
	hud_overview.anchor_left = 0.5
	hud_overview.anchor_right = 0.5
	hud_overview.anchor_top = 0.5
	hud_overview.anchor_bottom = 0.5
	hud_overview.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_overview.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud_overview.offset_left = -400
	hud_overview.offset_right = 400
	hud_overview.offset_top = -300
	hud_overview.offset_bottom = 300
	
	var overview_style = StyleBoxFlat.new()
	overview_style.bg_color = Color(0.08, 0.1, 0.15, 0.95)
	overview_style.border_width_left = 3
	overview_style.border_width_top = 3
	overview_style.border_width_right = 3
	overview_style.border_width_bottom = 3
	overview_style.border_color = Color(0.24, 0.46, 0.72, 0.85) # Sleek blue border
	overview_style.corner_radius_top_left = 16
	overview_style.corner_radius_top_right = 16
	overview_style.corner_radius_bottom_left = 16
	overview_style.corner_radius_bottom_right = 16
	overview_style.content_margin_left = 30
	overview_style.content_margin_right = 30
	overview_style.content_margin_top = 24
	overview_style.content_margin_bottom = 24
	hud_overview.add_theme_stylebox_override("panel", overview_style)
	margin.add_child(hud_overview)


func _get_current_green_vertices() -> PackedVector3Array:
	if course_instance != null and course_instance.has_method("get_current_green_vertices"):
		return course_instance.get_current_green_vertices()
	var pin_pos = course_instance.get("current_hole_location") if course_instance != null else null
	if GlobalSettings.is_chipping_minigame and course_instance != null and course_instance.get("aim_target_pos") != null:
		pin_pos = course_instance.get("aim_target_pos")
	if pin_pos == null and course_instance != null:
		pin_pos = course_instance.get("aim_target_pos")
	if pin_pos == null or course_instance == null:
		return PackedVector3Array()
		
	# Find the green static body closest to the pin
	var closest_green: StaticBody3D = null
	var min_dist_to_pin = 999999.0
	
	var stack = [course_instance]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node is StaticBody3D and node.name.begins_with("green_Static_"):
			var centroid = Vector3.ZERO
			var vertex_count = 0
			for child in node.get_children():
				if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
					var verts = child.shape.data
					if verts.size() > 0:
						for v in verts:
							centroid += node.global_transform * v
						vertex_count += verts.size()
			if vertex_count > 0:
				centroid /= vertex_count
				var dist = centroid.distance_to(pin_pos)
				if dist < min_dist_to_pin:
					min_dist_to_pin = dist
					closest_green = node
			else:
				var dist = node.global_position.distance_to(pin_pos)
				if dist < min_dist_to_pin:
					min_dist_to_pin = dist
					closest_green = node
		
		for child in node.get_children():
			stack.append(child)
			
	if closest_green == null:
		return PackedVector3Array()
		
	# Gather all global vertices from the closest green
	var global_verts = PackedVector3Array()
	for child in closest_green.get_children():
		if child is CollisionShape3D and child.shape is ConcavePolygonShape3D:
			var verts = child.shape.data
			for v in verts:
				global_verts.append(closest_green.global_transform * v)
				
	return global_verts


func _update_top_hud(player: Dictionary) -> void:
	if hud_player_name_lbl == null or MultiplayerManager.hole_ids.is_empty():
		return
		
	# 1. Update player name and active player badge
	var mode = MultiplayerManager.game_mode
	var name_text = player.get("name", "Player")
	if mode == "Scramble":
		name_text += " (Scramble)"
	elif mode == "2v2 Scramble":
		var team = player.get("team", "")
		if not team.is_empty():
			name_text += " (%s)" % team
		else:
			name_text += " (2v2)"
	elif mode == "Skins":
		var p_skins = MultiplayerManager.skins_won.get(player.get("name", ""), 0)
		name_text += " (%d Skins)" % p_skins

	hud_player_name_lbl.text = name_text
	if hud_player_badge != null and hud_player_badge_lbl != null:
		var p_color = MultiplayerManager.get_player_color(player)
		var style = hud_player_badge.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.bg_color = p_color
		else:
			var new_style = StyleBoxFlat.new()
			new_style.bg_color = p_color
			new_style.corner_radius_top_left = 13
			new_style.corner_radius_top_right = 13
			new_style.corner_radius_bottom_left = 13
			new_style.corner_radius_bottom_right = 13
			new_style.content_margin_left = 4
			new_style.content_margin_right = 4
			new_style.content_margin_top = 2
			new_style.content_margin_bottom = 2
			hud_player_badge.add_theme_stylebox_override("panel", new_style)
		hud_player_badge_lbl.text = player.get("name", "Player").substr(0, 1).to_upper()
	
	# 2. Update overall score relative to par or Skins count
	var overall_score_str = "E"
	if mode == "Skins":
		var p_skins = MultiplayerManager.skins_won.get(player.get("name", ""), 0)
		overall_score_str = "%d S" % p_skins
		if MultiplayerManager.carryover_skins > 0:
			overall_score_str += " (C%d)" % MultiplayerManager.carryover_skins
	else:
		var total_diff: int = 0
		var completed_any = false
		for h_id in MultiplayerManager.hole_ids:
			var score = player["hole_scores"].get(h_id)
			if score != null and score > 0:
				var par = int(MultiplayerManager.hole_info.get(h_id, {}).get("Par", 4))
				total_diff += int(score) - par
				completed_any = true
		if completed_any:
			if total_diff > 0:
				overall_score_str = "+" + str(total_diff)
			elif total_diff < 0:
				overall_score_str = str(total_diff)
	hud_overall_score_lbl.text = overall_score_str
	
	# 3. Update hole number
	var hole_num = MultiplayerManager.current_hole_index + 1
	hud_hole_num_lbl.text = str(hole_num)
	
	# 4. Update shots and current hole par diff
	var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index]
	var active_hole = MultiplayerManager.hole_info.get(hole_id, {})
	var hole_par = active_hole.get("Par", 4)
	var strokes = player.get("strokes", 0)
	var current_shot = strokes + 1
	
	# Build shots list BBCode
	var shot_bbcodes = []
	for i in range(1, hole_par + 1):
		if i == current_shot:
			shot_bbcodes.append("[u][b]%d[/b][/u]" % i)
		else:
			shot_bbcodes.append("[color=#8c939d]%d[/color]" % i)
	var shots_str = "   ".join(shot_bbcodes)
	
	# Current hole par tracker (strokes - par)
	var hole_diff = strokes - hole_par
	var diff_str = ""
	if hole_diff > 0:
		diff_str = "[color=#ff5555]+%d[/color]" % hole_diff
	elif hole_diff < 0:
		diff_str = "[color=#55ff55]%d[/color]" % hole_diff
	else:
		diff_str = "[color=#ffffff]E[/color]"
		
	hud_shots_rtl.text = "%s     ( %s )" % [shots_str, diff_str]


func _on_active_player_changed(player: Dictionary) -> void:
	if player.is_empty():
		return
		
	_clear_map_markers()
		
	var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index]
	var active_hole = MultiplayerManager.hole_info.get(hole_id, {})
	_update_top_hud(player)

	
	if course_instance != null:
		course_instance.current_hole_name = active_hole.get("Name", hole_id)
		course_instance.current_hole_par = active_hole.get("Par", 4)
		var hole_loc = active_hole.get("Hole Location")
		if hole_loc != null:
			course_instance.current_hole_location = Vector3(hole_loc[0], course_instance.get_height(hole_loc[0], hole_loc[1]), hole_loc[1])
			# Reset aim target to current hole pin
			course_instance.aim_target_pos = course_instance.current_hole_location
			
			if course_instance.has_node("AimMarker"):
				course_instance.get_node("AimMarker").global_position = course_instance.current_hole_location
			if course_instance.has_node("PinMarker"):
				course_instance.get_node("PinMarker").global_position = course_instance.current_hole_location
				course_instance.get_node("PinMarker").visible = course_instance.is_aerial_view
			
			var flag_pin = course_instance.get_node_or_null("FlagPin")
			if flag_pin != null:
				flag_pin.global_position = course_instance.current_hole_location
				
		# Update tee-off distance
		if player.get("strokes", 0) == 0 and course_instance != null and course_instance.has_method("get_height"):
			player["position"].y = course_instance.get_height(player["position"].x, player["position"].z) + 0.02
		var spawn_pos = player["position"]
		course_instance.current_hole_tee_dist_yards = int(spawn_pos.distance_to(course_instance.current_hole_location) * 1.09361)
		
		# Reset camera user offset when moving to a new hole or if starting hole
		if player["strokes"] == 0:
			course_instance.aerial_cam_user_offset = Vector3.ZERO
			
		# Update labels
		course_instance.call("_update_hole_info_label", player["strokes"] > 0)
		
		# Update outline
		course_instance.call("update_hole_outline")

	if active_ball != null:
		var is_practice = course_instance != null and course_instance.get("practice_mode_active")
		var should_initialize = true
		if is_practice and player.get("strokes", 0) > 0:
			should_initialize = false
			
		if should_initialize:
			# Teleport the ball to this player's current resting position
			active_ball.spawn_position = player["position"]
			active_ball.reset()
			
			# Recalculate lie immediately after teleporting/resetting
			if course_instance != null and course_instance.has_method("update_current_lie_and_reduction"):
				course_instance.call("update_current_lie_and_reduction")
			
			# Move camera target to focus on the active ball
			var camera = course_instance.get_node_or_null("PhantomCamera3D")
			if camera != null:
				camera.follow_target = active_ball
				
			# Automatically aim at the pin and position/rotate the camera behind the ball
			if course_instance != null:
				var pin_pos = course_instance.get("current_hole_location")
				if GlobalSettings.is_chipping_minigame and course_instance.get("aim_target_pos") != null:
					pin_pos = course_instance.get("aim_target_pos")
				if pin_pos != null and not pin_pos.is_zero_approx():
					var ball_pos = active_ball.global_position
					var diff = pin_pos - ball_pos
					var angle_rad = atan2(diff.z, diff.x)
					active_ball.aim_yaw_offset_deg = rad_to_deg(-angle_rad)
					
					# Position the camera behind the ball facing the pin
					if camera != null:
						camera.follow_mode = PhantomCamera3D.FollowMode.NONE
						camera.look_at_mode = PhantomCamera3D.LookAtMode.NONE
						var local_offset = Vector3(-2, 1.6, 0)
						if course_instance.has_method("get_camera_local_offset"):
							local_offset = course_instance.call("get_camera_local_offset")
						var rotated_offset = local_offset.rotated(Vector3.UP, -angle_rad)
						var cam_pos = ball_pos + rotated_offset
						if course_instance.has_method("clamp_camera_position"):
							cam_pos = course_instance.call("clamp_camera_position", cam_pos)
						camera.global_position = cam_pos
						var is_on_green = (active_ball.get("lie_type") == "green" or active_ball.get("surface_type") == PhysicsEnums.SurfaceType.GREEN)
						var target_look = (pin_pos + ball_pos) * 0.5 if is_on_green else pin_pos + Vector3.UP * 0.5
						camera.look_at(target_look)
						
						var cam3d = course_instance.get_node_or_null("Camera3D")
						if cam3d != null:
							cam3d.global_position = cam_pos
							cam3d.look_at(target_look)
			
		# Redraw active player's tracer trails if any
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			player_node.call("reset_shot_data")
			# Re-draw the player's last shot tracer line
			var last_pts = player.get("last_shot_tracer_points", [])
			if not last_pts.is_empty():
				player_node.call("create_new_tracer")
				var tracer = player_node.get("current_tracer")
				if tracer != null and "points" in tracer:
					tracer.points = last_pts.duplicate()
			elif not player["shot_history"].is_empty():
				player_node.call("create_new_tracer")
				var tracer = player_node.get("current_tracer")
				if tracer != null:
					for pt in player["shot_history"]:
						tracer.call("add_point", pt)




func _on_mulligan_pressed() -> void:
	if mulligan_confirm_dialog == null:
		return
		
	# Clear existing children of the dialog
	for child in mulligan_confirm_dialog.get_children():
		mulligan_confirm_dialog.remove_child(child)
		child.queue_free()
		
	# Build the dialog content dynamically
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 16)
	
	var active_player = MultiplayerManager.get_active_player()
	if active_player.is_empty():
		return
		
	var player_node = course_instance.get_node_or_null("Player") if course_instance != null else null
	var last_start_pos = player_node.get("_last_starting_pos") if player_node != null else Vector3.ZERO
	var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index] if not MultiplayerManager.hole_ids.is_empty() else "Hole 1"
	
	var matching_mulligans = []
	if active_player.has("mulligan_history") and typeof(active_player["mulligan_history"]) == TYPE_DICTIONARY:
		if active_player["mulligan_history"].has(hole_id) and typeof(active_player["mulligan_history"][hole_id]) == TYPE_ARRAY:
			for entry in active_player["mulligan_history"][hole_id]:
				if entry.has("start_pos") and typeof(entry["start_pos"]) == TYPE_VECTOR3:
					# Match starting positions within 0.5 meters
					if entry["start_pos"].distance_to(last_start_pos) < 0.5:
						matching_mulligans.append(entry)
						
	# Setup title
	var title_lbl = Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.24, 0.46, 0.72, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 4)
	content_vbox.add_child(title_lbl)
	
	var msg_lbl = Label.new()
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.add_theme_font_size_override("font_size", 16)
	msg_lbl.add_theme_color_override("font_color", Color.WHITE)
	msg_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_lbl.add_theme_constant_override("outline_size", 4)
	content_vbox.add_child(msg_lbl)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_vbox.add_child(scroll)
	
	var list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 10)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)
	
	if matching_mulligans.is_empty():
		# Standard confirmation flow
		title_lbl.text = "Confirm Mulligan"
		msg_lbl.text = "Are you sure you want to take a mulligan?\nThis will undo your last shot."
		scroll.visible = false
		
		var btn_hbox = HBoxContainer.new()
		btn_hbox.add_theme_constant_override("separation", 24)
		btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var confirm_btn = Button.new()
		confirm_btn.text = "Yes, Undo"
		confirm_btn.custom_minimum_size = Vector2(140, 45)
		apply_material_button_style(confirm_btn, Color(0.24, 0.46, 0.72, 0.85))
		confirm_btn.pressed.connect(func():
			mulligan_confirm_dialog.visible = false
			_on_mulligan_confirmed()
		)
		btn_hbox.add_child(confirm_btn)
		
		var cancel_btn = Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.custom_minimum_size = Vector2(140, 45)
		apply_material_button_style(cancel_btn, Color(0.56, 0.22, 0.22, 0.85))
		cancel_btn.pressed.connect(func():
			mulligan_confirm_dialog.visible = false
		)
		btn_hbox.add_child(cancel_btn)
		
		content_vbox.add_child(btn_hbox)
	else:
		# Selection flow
		title_lbl.text = "Mulligan Selection"
		msg_lbl.text = "Select an option for your mulligan from this spot:"
		
		var new_mulligan_btn = Button.new()
		new_mulligan_btn.text = "Take Another Mulligan (New Shot)"
		new_mulligan_btn.custom_minimum_size = Vector2(380, 45)
		apply_material_button_style(new_mulligan_btn, Color(0.24, 0.62, 0.36, 0.85))
		new_mulligan_btn.pressed.connect(func():
			mulligan_confirm_dialog.visible = false
			_on_mulligan_confirmed()
		)
		list_vbox.add_child(new_mulligan_btn)
		
		var sep_lbl = Label.new()
		sep_lbl.text = "--- Keep a Previous Shot ---"
		sep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sep_lbl.add_theme_font_size_override("font_size", 14)
		sep_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		list_vbox.add_child(sep_lbl)
		
		for i in range(matching_mulligans.size()):
			var entry = matching_mulligans[i]
			var stats = entry.get("shot_stats", {})
			var club = entry.get("club", "Dr")
			var dist = stats.get("total_yds", 0.0)
			var lie = entry.get("lie_type", "fairway")
			
			var btn_text = "Restore Shot %d: %s | %.0f yds (%s)" % [i + 1, club, dist, lie.capitalize()]
			var opt_btn = Button.new()
			opt_btn.text = btn_text
			opt_btn.custom_minimum_size = Vector2(380, 40)
			apply_material_button_style(opt_btn, Color(0.24, 0.46, 0.72, 0.85))
			opt_btn.pressed.connect(func():
				mulligan_confirm_dialog.visible = false
				_on_previous_mulligan_selected(entry)
			)
			list_vbox.add_child(opt_btn)
			
		var cancel_btn = Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.custom_minimum_size = Vector2(380, 40)
		apply_material_button_style(cancel_btn, Color(0.56, 0.22, 0.22, 0.85))
		cancel_btn.pressed.connect(func():
			mulligan_confirm_dialog.visible = false
		)
		list_vbox.add_child(cancel_btn)
		
	mulligan_confirm_dialog.add_child(content_vbox)
	
	if matching_mulligans.is_empty():
		mulligan_confirm_dialog.offset_top = -100
		mulligan_confirm_dialog.offset_bottom = 100
	else:
		mulligan_confirm_dialog.offset_top = -180
		mulligan_confirm_dialog.offset_bottom = 180
		
	mulligan_confirm_dialog.visible = true


func _on_mulligan_confirmed() -> void:
	var player_node = course_instance.get_node_or_null("Player")
	if player_node != null:
		var active_player = MultiplayerManager.get_active_player()
		var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index] if not MultiplayerManager.hole_ids.is_empty() else "Hole 1"
		var last_start_pos = player_node.get("_last_starting_pos")
		var current_ball_pos = active_player.get("position", Vector3.ZERO)
		
		# Capture current shot details
		var current_stats = {}
		if active_player.has("shot_stats") and typeof(active_player["shot_stats"]) == TYPE_DICTIONARY and active_player["shot_stats"].has(hole_id) and not active_player["shot_stats"][hole_id].is_empty():
			current_stats = active_player["shot_stats"][hole_id].back()
			
		var course_shot_data = {}
		if course_instance != null and "shot_history" in course_instance and not course_instance.shot_history.is_empty():
			course_shot_data = course_instance.shot_history.back()
			
		var tracer_pts = []
		var tracers_list = player_node.get("tracers")
		if tracers_list != null and not tracers_list.is_empty():
			var last_t = tracers_list.back()
			if is_instance_valid(last_t) and "points" in last_t:
				tracer_pts = last_t.points.duplicate()
				
		var shot_entry = {
			"start_pos": last_start_pos,
			"end_pos": current_ball_pos,
			"club": current_stats.get("club", MultiplayerManager.current_club),
			"lie_type": active_player.get("lie_type", "fairway"),
			"shot_reduction": active_player.get("shot_reduction", 0.0),
			"last_shot_penalty": active_player.get("last_shot_penalty", 0),
			"shot_stats": current_stats,
			"course_shot_data": course_shot_data,
			"tracer_points": tracer_pts
		}
		
		if not active_player.has("mulligan_history") or typeof(active_player["mulligan_history"]) != TYPE_DICTIONARY:
			active_player["mulligan_history"] = {}
		if not active_player["mulligan_history"].has(hole_id):
			active_player["mulligan_history"][hole_id] = []
		active_player["mulligan_history"][hole_id].append(shot_entry)
		
		# Reset detailed tracer points for active shot since we just mulliganed it
		active_player["last_shot_tracer_points"] = []
		
		player_node.call("mulligan")
		if course_instance.has_method("remove_last_shot"):
			course_instance.call("remove_last_shot")
		
		# Update MultiplayerManager data
		active_player["position"] = player_node.get("_last_starting_pos")
		var penalty = active_player.get("last_shot_penalty", 0)
		var strokes_to_remove = 1 + penalty
		active_player["strokes"] = max(0, active_player["strokes"] - strokes_to_remove)
		active_player["total_strokes"] = max(0, active_player["total_strokes"] - strokes_to_remove)
		active_player["last_shot_penalty"] = 0
		if not active_player["shot_history"].is_empty():
			active_player["shot_history"].pop_back()
			
		if not MultiplayerManager.hole_ids.is_empty():
			active_player["hole_scores"][hole_id] = active_player["strokes"]
			if active_player.has("shot_stats"):
				if typeof(active_player["shot_stats"]) == TYPE_DICTIONARY:
					if active_player["shot_stats"].has(hole_id) and not active_player["shot_stats"][hole_id].is_empty():
						active_player["shot_stats"][hole_id].pop_back()
				elif typeof(active_player["shot_stats"]) == TYPE_ARRAY and not active_player["shot_stats"].is_empty():
					active_player["shot_stats"].pop_back()
			
		if course_instance != null and course_instance.has_method("update_current_lie_and_reduction"):
			course_instance.call("update_current_lie_and_reduction")
			
		_on_active_player_changed(active_player)
		MultiplayerManager.save_current_match()


func _on_previous_mulligan_selected(prev_shot: Dictionary) -> void:
	var player_node = course_instance.get_node_or_null("Player")
	if player_node != null:
		var active_player = MultiplayerManager.get_active_player()
		var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index] if not MultiplayerManager.hole_ids.is_empty() else "Hole 1"
		
		# 1. Capture current shot and put it in mulligan history
		var last_start_pos = player_node.get("_last_starting_pos")
		var current_ball_pos = active_player.get("position", Vector3.ZERO)
		var current_stats = {}
		if active_player.has("shot_stats") and typeof(active_player["shot_stats"]) == TYPE_DICTIONARY and active_player["shot_stats"].has(hole_id) and not active_player["shot_stats"][hole_id].is_empty():
			current_stats = active_player["shot_stats"][hole_id].back()
			
		var course_shot_data = {}
		if course_instance != null and "shot_history" in course_instance and not course_instance.shot_history.is_empty():
			course_shot_data = course_instance.shot_history.back()
			
		var tracer_pts = []
		var tracers_list = player_node.get("tracers")
		if tracers_list != null and not tracers_list.is_empty():
			var last_t = tracers_list.back()
			if is_instance_valid(last_t) and "points" in last_t:
				tracer_pts = last_t.points.duplicate()
				
		var current_shot_entry = {
			"start_pos": last_start_pos,
			"end_pos": current_ball_pos,
			"club": current_stats.get("club", MultiplayerManager.current_club),
			"lie_type": active_player.get("lie_type", "fairway"),
			"shot_reduction": active_player.get("shot_reduction", 0.0),
			"last_shot_penalty": active_player.get("last_shot_penalty", 0),
			"shot_stats": current_stats,
			"course_shot_data": course_shot_data,
			"tracer_points": tracer_pts
		}
		
		if not active_player.has("mulligan_history") or typeof(active_player["mulligan_history"]) != TYPE_DICTIONARY:
			active_player["mulligan_history"] = {}
		if not active_player["mulligan_history"].has(hole_id):
			active_player["mulligan_history"][hole_id] = []
		active_player["mulligan_history"][hole_id].append(current_shot_entry)
		
		# Remove the selected previous shot from mulligan history
		var hist_list = active_player["mulligan_history"][hole_id]
		hist_list.erase(prev_shot)
		
		# 2. Undo current shot
		player_node.call("mulligan")
		if course_instance.has_method("remove_last_shot"):
			course_instance.call("remove_last_shot")
			
		var penalty = active_player.get("last_shot_penalty", 0)
		var strokes_to_remove = 1 + penalty
		active_player["strokes"] = max(0, active_player["strokes"] - strokes_to_remove)
		active_player["total_strokes"] = max(0, active_player["total_strokes"] - strokes_to_remove)
		active_player["last_shot_penalty"] = 0
		if not active_player["shot_history"].is_empty():
			active_player["shot_history"].pop_back()
		if active_player.has("shot_stats") and typeof(active_player["shot_stats"]) == TYPE_DICTIONARY:
			if active_player["shot_stats"].has(hole_id) and not active_player["shot_stats"][hole_id].is_empty():
				active_player["shot_stats"][hole_id].pop_back()
		
		# 3. Apply the selected previous shot
		var prev_penalty = prev_shot.get("last_shot_penalty", 0)
		var strokes_to_add = 1 + prev_penalty
		active_player["strokes"] += strokes_to_add
		active_player["total_strokes"] += strokes_to_add
		active_player["last_shot_penalty"] = prev_penalty
		
		active_player["position"] = prev_shot["end_pos"]
		active_player["shot_history"].append(prev_shot["end_pos"])
		
		if not active_player.has("shot_stats"):
			active_player["shot_stats"] = {}
		if not active_player["shot_stats"].has(hole_id):
			active_player["shot_stats"][hole_id] = []
		active_player["shot_stats"][hole_id].append(prev_shot["shot_stats"])
		
		active_player["lie_type"] = prev_shot.get("lie_type", "fairway")
		active_player["shot_reduction"] = prev_shot.get("shot_reduction", 0.0)
		
		# Restore detailed tracer points
		active_player["last_shot_tracer_points"] = prev_shot.get("tracer_points", []).duplicate()
		
		if not MultiplayerManager.hole_ids.is_empty():
			active_player["hole_scores"][hole_id] = active_player["strokes"]
			
		# Teleport player and ball
		player_node.set("_last_starting_pos", prev_shot["start_pos"])
		var ball = player_node.get("ball")
		if ball != null:
			ball.global_position = prev_shot["end_pos"]
			ball.spawn_position = prev_shot["end_pos"]
			ball.call_deferred("reset")
			
		# Re-add to course_instance's shot_history
		if course_instance != null and "shot_history" in course_instance:
			course_instance.shot_history.append(prev_shot["course_shot_data"])
			var p_name = prev_shot["course_shot_data"].get("player", "")
			var club_name = prev_shot["course_shot_data"].get("club", "")
			if not p_name.is_empty() and not club_name.is_empty():
				if course_instance.has_method("_record_global_shot"):
					course_instance.call("_record_global_shot", p_name, club_name, prev_shot["course_shot_data"])
			if course_instance.has_method("_update_averages"):
				course_instance.call("_update_averages")
				
		_on_active_player_changed(active_player)
		MultiplayerManager.save_current_match()


func _on_hole_completed(scores: Array) -> void:
	_populate_scorecard("hole_completed")
	hud_scorecard.visible = true
	_set_other_elements_visible(false)


func _on_game_over(scores: Array) -> void:
	MultiplayerManager.is_finished = true
	MultiplayerManager.save_current_match()
	_populate_overview()
	hud_overview.visible = true
	_set_other_elements_visible(false)
	GlobalSettings.play_golf_clap()


func _process(_delta: float) -> void:
	if course_instance != null and course_instance.get("show_green_grid") != null:
		_update_grid_button_state(course_instance.get("show_green_grid") as bool)
		
	_update_minimap()
	
	# Update top HUD if data changed (safety fallback for practice mode/penalties)
	var active_player = MultiplayerManager.get_active_player()
	if not active_player.is_empty():
		var strokes = active_player.get("strokes", 0)
		var name_str = active_player.get("name", "")
		var hole_idx = MultiplayerManager.current_hole_index
		if strokes != _last_hud_strokes or name_str != _last_hud_player_name or hole_idx != _last_hud_hole_index:
			_last_hud_strokes = strokes
			_last_hud_player_name = name_str
			_last_hud_hole_index = hole_idx
			_update_top_hud(active_player)
			
	# Manage 2D overlays and 3D map markers for multiplayer ball tracking
	if _overlay_node != null:
		_overlay_node.queue_redraw()
		
	if MultiplayerManager.players.size() > 1 and not MultiplayerManager.is_finished:
		var show_markers = true
		if hud_scorecard.visible or hud_manage_players.visible:
			show_markers = false
			
		for i in range(MultiplayerManager.players.size()):
			var p = MultiplayerManager.players[i]
			var is_marker_valid = show_markers and not p.get("holed_out", false) and p.get("active", true)
			
			var ball_pos = Vector3.ZERO
			if i == MultiplayerManager.active_player_index and active_ball != null:
				ball_pos = active_ball.global_position
			else:
				ball_pos = p.get("position", Vector3.ZERO)
				
			if is_marker_valid and not ball_pos.is_zero_approx():
				var marker = _player_map_markers.get(i)
				if marker == null or not is_instance_valid(marker):
					var letter = p["name"].substr(0, 1).to_upper()
					var color = MultiplayerManager.get_player_color(p)
					marker = _create_player_map_marker(p, letter, color)
					add_child(marker)
					_player_map_markers[i] = marker
				marker.global_position = ball_pos
				marker.visible = true
			else:
				var marker = _player_map_markers.get(i)
				if marker != null and is_instance_valid(marker):
					marker.visible = false
	else:
		_clear_map_markers()


func _update_minimap() -> void:
	if _minimap_camera == null or course_instance == null or _minimap_panel == null:
		return
		
	# Check if scorecard or players HUD is open
	if hud_scorecard.visible or hud_manage_players.visible or hud_overview.visible:
		if _minimap_group != null:
			_minimap_group.visible = false
		return
		
	# Check if the course is in full-screen aerial view
	var is_aerial = course_instance.get("is_aerial_view") as bool if course_instance.get("is_aerial_view") != null else false
	
	# The box shouldn't show at all when the full-screen aerial view is active
	if _minimap_group != null:
		_minimap_group.visible = not is_aerial
	
	if is_aerial:
		return # No need to calculate if it's hidden
		
	var ball = active_ball
	if ball == null:
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			ball = player_node.get("ball")
			
	if ball == null:
		return
		
	# Check for on-green state transition
	var is_on_green = (ball.get("lie_type") == "green" or ball.get("surface_type") == PhysicsEnums.SurfaceType.GREEN)
	if is_on_green != _last_was_on_green:
		if is_on_green:
			var green_zoom = 60.0
			if course_instance != null and course_instance.has_method("get_green_zoom_size"):
				green_zoom = course_instance.get_green_zoom_size()
			minimap_zoom = green_zoom
		else:
			minimap_zoom = _default_non_green_minimap_zoom
		
		# Auto-toggle green slope grid
		if course_instance != null and course_instance.get("show_green_grid") != null:
			course_instance.set("show_green_grid", is_on_green)
			
		_last_was_on_green = is_on_green
		
	var ball_pos = ball.global_position
	var pin_pos = course_instance.get("current_hole_location")
	if GlobalSettings.is_chipping_minigame and course_instance.get("aim_target_pos") != null:
		pin_pos = course_instance.get("aim_target_pos")
	if pin_pos == null:
		pin_pos = course_instance.get("aim_target_pos")
		
	var yaw_rad = 0.0
	var aim_yaw = ball.get("aim_yaw_offset_deg")
	if aim_yaw != null:
		yaw_rad = deg_to_rad(-aim_yaw)
	elif pin_pos != null:
		var diff = pin_pos - ball_pos
		yaw_rad = atan2(diff.z, diff.x)
	else:
		yaw_rad = -PI/2
		
	var dir_3d = Vector3(cos(yaw_rad), 0, sin(yaw_rad)).normalized()
	var dist = 150.0
	if pin_pos != null:
		dist = ball_pos.distance_to(pin_pos)
		
	_minimap_camera.size = minimap_zoom
	
	# Orientation - aligns camera exactly to face the player's aiming direction
	var right_vec = dir_3d.cross(Vector3.UP).normalized()
	var up_vec = dir_3d
	var back_vec = Vector3.UP
	_minimap_camera.transform.basis = Basis(right_vec, up_vec, back_vec)
	
	# Position - exact base position alignment as full aerial view
	var base_pos = ball_pos + dir_3d * (0.35 * minimap_zoom)
	_minimap_camera.position = Vector3(base_pos.x, 150.0, base_pos.z)

	# --- Update Distance Tracker Panel ---
	if _distance_tracker_panel != null and _back_lbl != null and _hole_lbl != null and _front_lbl != null:
		if pin_pos != null:
			var ball_pos_2d = Vector2(ball_pos.x, ball_pos.z)
			var pin_pos_2d = Vector2(pin_pos.x, pin_pos.z)
			
			# Get direction from ball to pin on XZ plane
			var pin_dir_2d = (pin_pos_2d - ball_pos_2d).normalized()
			if pin_dir_2d.length_squared() < 0.001:
				pin_dir_2d = Vector2(dir_3d.x, dir_3d.z).normalized()
			
			# Get green vertices
			var global_verts = _get_current_green_vertices()
			if global_verts.is_empty():
				# Fallback: create a circle of 24 points around pin_pos with a 15-yard (13.7m) radius
				var radius = 13.7
				for i in range(24):
					var angle = i * PI * 2.0 / 24.0
					global_verts.append(pin_pos + Vector3(cos(angle) * radius, 0, sin(angle) * radius))
					
			var min_proj_dist = 999999.0
			var max_proj_dist = -999999.0
			
			for v in global_verts:
				var v_2d = Vector2(v.x, v.z)
				var proj = (v_2d - ball_pos_2d).dot(pin_dir_2d)
				if proj < min_proj_dist:
					min_proj_dist = proj
				if proj > max_proj_dist:
					max_proj_dist = proj
					
			# Distance to hole
			var dist_hole = ball_pos.distance_to(pin_pos)
			
			# Display as yards
			var dist_back_yds = int(max_proj_dist * 1.09361)
			var dist_hole_yds = int(dist_hole * 1.09361)
			var dist_front_yds = int(min_proj_dist * 1.09361)
			
			# Clamp front distance to be at least 0
			if dist_front_yds < 0:
				dist_front_yds = 0
				
			_back_lbl.text = str(dist_back_yds)
			_hole_lbl.text = str(dist_hole_yds)
			_front_lbl.text = str(dist_front_yds)
		else:
			_back_lbl.text = "---"
			_hole_lbl.text = "---"
			_front_lbl.text = "---"


func apply_material_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 20 # Pill style
	style_normal.corner_radius_top_right = 20
	style_normal.corner_radius_bottom_left = 20
	style_normal.corner_radius_bottom_right = 20
	style_normal.content_margin_left = 16
	style_normal.content_margin_right = 16
	style_normal.content_margin_top = 8
	style_normal.content_margin_bottom = 8

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.3, 0.3, 0.3, 0.5)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


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


func update_map_button_text(is_aerial: bool) -> void:
	var map_btn = null
	for child in get_children():
		if child is CanvasLayer:
			var panel = child.get_node_or_null("RightPanel")
			if panel != null:
				map_btn = panel.get_node_or_null("TogglesScroll/TogglesContainer/MapButton")
				if map_btn == null:
					map_btn = panel.get_node_or_null("TogglesContainer/MapButton")
				if map_btn == null:
					map_btn = panel.get_node_or_null("MapButton")
				break
				
	if map_btn != null:
		if is_aerial:
			map_btn.text = "👤 Return to Player"
		else:
			map_btn.text = "🗺 Toggle Map View"


func update_practice_ui_visibility(is_aerial: bool) -> void:
	for child in get_children():
		if child is CanvasLayer:
			var panel = child.get_node_or_null("RightPanel")
			if panel != null:
				var place_btn = panel.get_node_or_null("TogglesScroll/TogglesContainer/PlaceBallButton")
				var prev_btn = panel.get_node_or_null("TogglesScroll/TogglesContainer/PrevHoleButton")
				var next_btn = panel.get_node_or_null("TogglesScroll/TogglesContainer/NextHoleButton")
				if place_btn == null:
					place_btn = panel.get_node_or_null("TogglesContainer/PlaceBallButton")
					prev_btn = panel.get_node_or_null("TogglesContainer/PrevHoleButton")
					next_btn = panel.get_node_or_null("TogglesContainer/NextHoleButton")
				if place_btn == null:
					place_btn = panel.get_node_or_null("PlaceBallButton")
					prev_btn = panel.get_node_or_null("PrevHoleButton")
					next_btn = panel.get_node_or_null("NextHoleButton")
				if place_btn != null:
					place_btn.visible = is_aerial
				if prev_btn != null:
					prev_btn.visible = is_aerial
				if next_btn != null:
					next_btn.visible = is_aerial


func _on_scorecard_toggle_pressed() -> void:
	if hud_manage_players.visible:
		hud_manage_players.visible = false
	if hud_overview.visible:
		hud_overview.visible = false
	if hud_scorecard.visible:
		hud_scorecard.visible = false
		_set_other_elements_visible(true)
	else:
		_populate_scorecard("toggle")
		hud_scorecard.visible = true
		_set_other_elements_visible(false)


func _get_hole_distance(hole_id: String, tee_color: String) -> int:
	var hole = MultiplayerManager.hole_info.get(hole_id, {})
	var tee_boxes = hole.get("Tee Boxes", {})
	var tee_pos = tee_boxes.get(tee_color)
	if tee_pos == null:
		if not tee_boxes.is_empty():
			tee_pos = tee_boxes.values()[0]
	var hole_loc = hole.get("Hole Location", [0.0, 0.0])
	if tee_pos != null and hole_loc != null:
		var t_vec = Vector2(tee_pos[0], tee_pos[1])
		var h_vec = Vector2(hole_loc[0], hole_loc[1])
		return int(t_vec.distance_to(h_vec) * 1.09361)
	return 0


func _populate_scorecard(action_type: String) -> void:
	# Clear previous cells
	for child in scorecard_grid.get_children():
		child.queue_free()
		
	var num_holes = MultiplayerManager.hole_ids.size()
	if num_holes == 0:
		return
		
	# Determine active tee color for distance row
	var active_player = MultiplayerManager.get_active_player()
	var tee_color = active_player.get("tee", "Blue") if not active_player.is_empty() else "Blue"
	
	# Split into Front 9 and Back 9
	var front_holes = []
	var back_holes = []
	for i in range(num_holes):
		var hole_id = MultiplayerManager.hole_ids[i]
		if i < 9:
			front_holes.append(hole_id)
		else:
			back_holes.append(hole_id)
			
	# Columns: Player | 1..9 | [OUT] | 10..N | [IN] | TOT
	var columns = ["Player"]
	for i in range(front_holes.size()):
		columns.append(str(i + 1))
	if num_holes > 9:
		columns.append("OUT")
		for i in range(back_holes.size()):
			columns.append(str(10 + i))
		columns.append("IN")
	columns.append("TOT")
	
	scorecard_grid.columns = columns.size()
	
	var header_bg = Color(0.12, 0.16, 0.24, 0.95)
	
	# Helper for cell creation
	var add_cell = func(text: String, bg: Color, is_header: bool = false, fg: Color = Color.WHITE):
		var cell = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = bg
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.3, 0.3)
		style.content_margin_left = 6
		style.content_margin_right = 6
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		cell.add_theme_stylebox_override("panel", style)
		
		var label = Label.new()
		label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", fg)
		if is_header:
			label.add_theme_font_size_override("font_size", 13)
		else:
			label.add_theme_font_size_override("font_size", 12)
		cell.add_child(label)
		scorecard_grid.add_child(cell)

	# --- 1. HEADER ROW ---
	for col in columns:
		add_cell.call(col, header_bg, true)
		
	# --- 2. DISTANCE ROW ---
	var dist_bg = Color(0.15, 0.20, 0.30, 0.8)
	add_cell.call("Yds (%s)" % tee_color, dist_bg, false, Color(0.8, 0.8, 0.8))
	
	var front_dist_sum = 0
	for hole_id in front_holes:
		var dist = _get_hole_distance(hole_id, tee_color)
		front_dist_sum += dist
		add_cell.call(str(dist), dist_bg, false, Color(0.8, 0.8, 0.8))
		
	if num_holes > 9:
		add_cell.call(str(front_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9))
		var back_dist_sum = 0
		for hole_id in back_holes:
			var dist = _get_hole_distance(hole_id, tee_color)
			back_dist_sum += dist
			add_cell.call(str(dist), dist_bg, false, Color(0.8, 0.8, 0.8))
		add_cell.call(str(back_dist_sum), dist_bg, false, Color(0.9, 0.9, 0.9))
		add_cell.call(str(front_dist_sum + back_dist_sum), dist_bg, false, Color.YELLOW)
	else:
		add_cell.call(str(front_dist_sum), dist_bg, false, Color.YELLOW)

	# --- 3. PAR ROW ---
	var par_bg = Color(0.18, 0.24, 0.35, 0.8)
	add_cell.call("Par", par_bg, false, Color(0.8, 0.8, 0.8))
	
	var front_par_sum = 0
	for hole_id in front_holes:
		var hole = MultiplayerManager.hole_info.get(hole_id, {})
		var par = hole.get("Par", 4)
		front_par_sum += par
		add_cell.call(str(par), par_bg, false, Color(0.8, 0.8, 0.8))
		
	if num_holes > 9:
		add_cell.call(str(front_par_sum), par_bg, false, Color(0.9, 0.9, 0.9))
		var back_par_sum = 0
		for hole_id in back_holes:
			var hole = MultiplayerManager.hole_info.get(hole_id, {})
			var par = hole.get("Par", 4)
			back_par_sum += par
			add_cell.call(str(par), par_bg, false, Color(0.8, 0.8, 0.8))
		add_cell.call(str(back_par_sum), par_bg, false, Color(0.9, 0.9, 0.9))
		add_cell.call(str(front_par_sum + back_par_sum), par_bg, false, Color.YELLOW)
	else:
		add_cell.call(str(front_par_sum), par_bg, false, Color.YELLOW)

	var sc_title = hud_scorecard.get_node_or_null("VBoxContainer/Label") as Label
	if sc_title != null:
		sc_title.text = "Scorecard - MODE: %s" % MultiplayerManager.game_mode.to_upper()

	# --- 4. PLAYER ROWS ---
	var current_hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index] if MultiplayerManager.current_hole_index < num_holes else ""
	var is_skins_mode = (MultiplayerManager.game_mode == "Skins")
	
	for p_idx in range(MultiplayerManager.players.size()):
		var p = MultiplayerManager.players[p_idx]
		var row_bg = Color(0.1, 0.12, 0.18, 0.9) if p_idx % 2 == 0 else Color(0.06, 0.08, 0.12, 0.9)
		
		# Name cell
		var name_text = "%s (%s)" % [p["name"], p["tee"]]
		if not p.get("team", "").is_empty() and MultiplayerManager.game_mode == "2v2 Scramble":
			name_text = "%s [%s] (%s)" % [p["name"], p["team"], p["tee"]]
		var name_fg = Color.WHITE
		if not p.get("active", true):
			name_text += " (Out)"
			name_fg = Color(0.6, 0.6, 0.6)
			
		# Custom cell containing player name and email button
		var cell = PanelContainer.new()
		var style = StyleBoxFlat.new()
		style.bg_color = row_bg
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.3, 0.3, 0.3)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		cell.add_theme_stylebox_override("panel", style)
		
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 10)
		cell.add_child(hbox)
		
		# Color and letter badge
		var badge = PanelContainer.new()
		badge.custom_minimum_size = Vector2(22, 22)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		var badge_style = StyleBoxFlat.new()
		var p_color = MultiplayerManager.get_player_color(p)
		badge_style.bg_color = p_color
		badge_style.corner_radius_top_left = 11
		badge_style.corner_radius_top_right = 11
		badge_style.corner_radius_bottom_left = 11
		badge_style.corner_radius_bottom_right = 11
		badge_style.content_margin_left = 4
		badge_style.content_margin_right = 4
		badge_style.content_margin_top = 2
		badge_style.content_margin_bottom = 2
		badge.add_theme_stylebox_override("panel", badge_style)
		
		var badge_lbl = Label.new()
		badge_lbl.text = p["name"].substr(0, 1).to_upper()
		badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge_lbl.add_theme_font_size_override("font_size", 11)
		badge_lbl.add_theme_color_override("font_color", Color.WHITE)
		badge_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		badge_lbl.add_theme_constant_override("outline_size", 3)
		badge.add_child(badge_lbl)
		
		hbox.add_child(badge)
		
		var label = Label.new()
		label.text = name_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", name_fg)
		label.add_theme_font_size_override("font_size", 13)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)
		
		var email_btn = Button.new()
		email_btn.text = "✉️"
		email_btn.tooltip_text = "Email shot stats for " + p["name"]
		email_btn.custom_minimum_size = Vector2(32, 24)
		email_btn.focus_mode = Control.FOCUS_NONE
		
		var btn_style_normal = StyleBoxFlat.new()
		btn_style_normal.bg_color = Color(0.2, 0.4, 0.7, 0.8)
		btn_style_normal.corner_radius_top_left = 4
		btn_style_normal.corner_radius_top_right = 4
		btn_style_normal.corner_radius_bottom_left = 4
		btn_style_normal.corner_radius_bottom_right = 4
		
		var btn_style_hover = btn_style_normal.duplicate()
		btn_style_hover.bg_color = Color(0.25, 0.5, 0.85, 0.9)
		
		var btn_style_pressed = btn_style_normal.duplicate()
		btn_style_pressed.bg_color = Color(0.15, 0.3, 0.55, 0.95)
		
		email_btn.add_theme_stylebox_override("normal", btn_style_normal)
		email_btn.add_theme_stylebox_override("hover", btn_style_hover)
		email_btn.add_theme_stylebox_override("pressed", btn_style_pressed)
		
		email_btn.pressed.connect(func():
			_email_player_stats(p)
		)
		hbox.add_child(email_btn)
		
		scorecard_grid.add_child(cell)
		
		# Front 9 scores
		var front_score_sum = 0
		for hole_id in front_holes:
			var display_score = "-"
			var is_current = (hole_id == current_hole_id)
			if is_current:
				if p.get("active", true) and p["strokes"] > 0:
					display_score = str(p["strokes"])
					front_score_sum += p["strokes"]
					if not p["holed_out"]:
						display_score += "*"
			else:
				var s = p["hole_scores"].get(hole_id)
				if s != null:
					display_score = str(s)
					front_score_sum += s
			
			var score_fg = Color.WHITE
			if display_score != "-":
				var hole = MultiplayerManager.hole_info.get(hole_id, {})
				var par = hole.get("Par", 4)
				var score_val = int(display_score.rstrip("*"))
				if score_val < par:
					score_fg = Color(0.5, 1.0, 0.5)
				elif score_val > par:
					score_fg = Color(1.0, 0.5, 0.5)

				if is_skins_mode:
					var h_res = MultiplayerManager.hole_skins_results.get(hole_id, {})
					if not h_res.is_empty():
						if h_res.get("winner", "") == p["name"]:
							display_score += " 🏆"
							score_fg = Color(1.0, 0.85, 0.2)
						elif h_res.get("winner", "") == "Tie":
							display_score += " (C)"
					
			add_cell.call(display_score, row_bg, false, score_fg)
			
		if num_holes > 9:
			add_cell.call(str(front_score_sum) if front_score_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9))
			
			# Back 9 scores
			var back_score_sum = 0
			for hole_id in back_holes:
				var display_score = "-"
				var is_current = (hole_id == current_hole_id)
				if is_current:
					if p.get("active", true) and p["strokes"] > 0:
						display_score = str(p["strokes"])
						back_score_sum += p["strokes"]
						if not p["holed_out"]:
							display_score += "*"
				else:
					var s = p["hole_scores"].get(hole_id)
					if s != null:
						display_score = str(s)
						back_score_sum += s
						
				var score_fg = Color.WHITE
				if display_score != "-":
					var hole = MultiplayerManager.hole_info.get(hole_id, {})
					var par = hole.get("Par", 4)
					var score_val = int(display_score.rstrip("*"))
					if score_val < par:
						score_fg = Color(0.5, 1.0, 0.5)
					elif score_val > par:
						score_fg = Color(1.0, 0.5, 0.5)
					
					if is_skins_mode:
						var h_res = MultiplayerManager.hole_skins_results.get(hole_id, {})
						if not h_res.is_empty():
							if h_res.get("winner", "") == p["name"]:
								display_score += " 🏆"
								score_fg = Color(1.0, 0.85, 0.2)
							elif h_res.get("winner", "") == "Tie":
								display_score += " (C)"
						
				add_cell.call(display_score, row_bg, false, score_fg)
				
			add_cell.call(str(back_score_sum) if back_score_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9))
			
			var total_score = front_score_sum + back_score_sum
			var tot_display = str(total_score) if total_score > 0 else "-"
			if is_skins_mode:
				tot_display = "%d Skins (%s)" % [MultiplayerManager.skins_won.get(p["name"], 0), tot_display]
			add_cell.call(tot_display, row_bg, false, Color.YELLOW)
		else:
			var tot_display = str(front_score_sum) if front_score_sum > 0 else "-"
			if is_skins_mode:
				tot_display = "%d Skins (%s)" % [MultiplayerManager.skins_won.get(p["name"], 0), tot_display]
			add_cell.call(tot_display, row_bg, false, Color.YELLOW)

	# --- 5. ACTION BUTTON CONFIGURATION ---
	var action_btn = hud_scorecard.get_node("VBoxContainer/ScorecardActionBtn") as Button
	for conn in action_btn.pressed.get_connections():
		action_btn.pressed.disconnect(conn.callable)
		
	if action_type == "toggle":
		action_btn.text = "Close"
		action_btn.pressed.connect(func():
			hud_scorecard.visible = false
			_set_other_elements_visible(true)
		)
	elif action_type == "hole_completed":
		action_btn.text = "Next Hole"
		action_btn.pressed.connect(func():
			hud_scorecard.visible = false
			_set_other_elements_visible(true)
			MultiplayerManager.advance_hole()
		)
	elif action_type == "game_over":
		action_btn.text = "Main Menu"
		action_btn.pressed.connect(func():
			SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
		)


func _set_other_elements_visible(is_visible: bool) -> void:
	if range_ui != null:
		range_ui.visible = is_visible
	if _minimap_group != null:
		var is_aerial = false
		if course_instance != null and course_instance.get("is_aerial_view") != null:
			is_aerial = course_instance.get("is_aerial_view") as bool
		_minimap_group.visible = is_visible and not is_aerial
	if top_bar != null:
		top_bar.visible = is_visible
	if settings_btn != null:
		settings_btn.visible = is_visible
	if right_panel != null:
		right_panel.visible = is_visible


func _on_manage_players_toggle_pressed() -> void:
	if hud_scorecard.visible:
		hud_scorecard.visible = false
	if hud_overview.visible:
		hud_overview.visible = false
	if hud_manage_players.visible:
		hud_manage_players.visible = false
		_set_other_elements_visible(true)
	else:
		_populate_manage_players()
		_refresh_manage_players_dropdown()
		hud_manage_players.visible = true
		_set_other_elements_visible(false)


func _refresh_manage_players_dropdown() -> void:
	var select_opt = hud_manage_players.get_node_or_null("VBoxContainer/AddSection/AddRow/PlayerSelectOpt") as OptionButton
	var name_input = hud_manage_players.get_node_or_null("VBoxContainer/AddSection/AddRow/NameInput") as LineEdit
	if select_opt != null and name_input != null:
		select_opt.clear()
		select_opt.add_item("New Player...", 0)
		var registered = MultiplayerManager.get_registered_players()
		for i in range(registered.size()):
			select_opt.add_item(registered[i].get("name", "Player"), i + 1)
		select_opt.selected = 0
		name_input.visible = true


func _populate_manage_players() -> void:
	var list_node = hud_manage_players.get_node_or_null("VBoxContainer/ScrollContainer/PlayerList") as VBoxContainer
	if list_node == null:
		return
		
	# Clear previous entries
	for child in list_node.get_children():
		child.queue_free()
		
	# Count active players
	var active_count = 0
	for p in MultiplayerManager.players:
		if p.get("active", true):
			active_count += 1
			
	var can_remove = (active_count > 1)
		
	for i in range(MultiplayerManager.players.size()):
		var p = MultiplayerManager.players[i]
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 15)
		
		var name_lbl = Label.new()
		var active_str = "" if p.get("active", true) else " (Out)"
		name_lbl.text = "%s (%s)%s" % [p["name"], p["tee"], active_str]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not p.get("active", true):
			name_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(name_lbl)
		
		var toggle_btn = Button.new()
		toggle_btn.custom_minimum_size = Vector2(100, 30)
		if p.get("active", true):
			toggle_btn.text = "Remove"
			apply_material_button_style(toggle_btn, Color(0.56, 0.22, 0.22, 0.85)) # Red
			toggle_btn.disabled = not can_remove
			toggle_btn.pressed.connect(func():
				MultiplayerManager.toggle_player_active(i, false)
				_populate_manage_players()
				_populate_scorecard("toggle")
			)
		else:
			toggle_btn.text = "Add Back"
			apply_material_button_style(toggle_btn, Color(0.25, 0.55, 0.35, 0.85)) # Green
			toggle_btn.pressed.connect(func():
				MultiplayerManager.toggle_player_active(i, true)
				_populate_manage_players()
				_populate_scorecard("toggle")
			)
		row.add_child(toggle_btn)
		list_node.add_child(row)


func _email_player_stats(p: Dictionary) -> void:
	var player_name = p.get("name", "Player")
	var course_title = MultiplayerManager.course_title
	var total_strokes = p.get("total_strokes", 0)
	
	var subject = "Heckle Golf Simulator - Round Stats for %s on %s" % [player_name, course_title]
	
	var body = "Round Stats for %s\n" % player_name
	body += "Course: %s\n" % course_title
	body += "Tee: %s\n" % p.get("tee", "Blue")
	body += "Total Strokes: %d\n\n" % total_strokes
	body += "Hole-by-Hole Shot Details:\n"
	body += "==================================================\n\n"
	
	for hole_id in MultiplayerManager.hole_ids:
		var hole = MultiplayerManager.hole_info.get(hole_id, {})
		var par = hole.get("Par", 4)
		var tee_color = p.get("tee", "Blue")
		var dist = _get_hole_distance(hole_id, tee_color)
		var score_val = p["hole_scores"].get(hole_id)
		var score_str = str(score_val) if score_val != null else "-"
		
		body += "%s (Par %d, %d Yds)\n" % [hole_id, par, dist]
		body += "Score: %s\n" % score_str
		
		var shots = p.get("shot_stats", {}).get(hole_id, [])
		if shots.is_empty():
			body += "No shot data recorded for this hole.\n"
		else:
			body += "Shots:\n"
			for i in range(shots.size()):
				var shot = shots[i]
				var shot_num = i + 1
				var club = shot.get("club", "Unknown")
				if club == "": club = "Unknown"
				
				var carry = "%.1f yds" % shot.get("carry_yds", 0.0)
				var total = "%.1f yds" % shot.get("total_yds", 0.0)
				var speed = "%.1f mph" % shot.get("speed_mph", 0.0)
				var vla = "%.1f deg" % shot.get("vla_deg", 0.0)
				var hla = "%.1f deg" % shot.get("hla_deg", 0.0)
				var tot_spin = "%d rpm" % int(shot.get("total_spin_rpm", 0.0))
				var back_spin = "%d rpm" % int(shot.get("back_spin_rpm", 0.0))
				var side_spin = "%d rpm" % int(shot.get("side_spin_rpm", 0.0))
				var spin_axis = "%.1f deg" % shot.get("spin_axis_deg", 0.0)
				var apex = "%.1f ft" % shot.get("apex_ft", 0.0)
				
				var offline_val = shot.get("offline_yds", 0.0)
				var offline_dir = "R" if offline_val >= 0 else "L"
				var offline = "%s%.1f yds" % [offline_dir, abs(offline_val)]
				
				body += "  Shot %d (Club: %s):\n" % [shot_num, club]
				body += "    Carry: %s | Total: %s | Speed: %s | Apex: %s | Offline: %s\n" % [carry, total, speed, apex, offline]
				body += "    Launch Angle: %s (HLA: %s) | Spin: %s (Back: %s, Side: %s, Axis: %s)\n" % [vla, hla, tot_spin, back_spin, side_spin, spin_axis]
		
		body += "--------------------------------------------------\n\n"
		
	# Load and append historical averages by club
	var stats_path = "user://player_club_stats.json"
	if FileAccess.file_exists(stats_path):
		var file = FileAccess.open(stats_path, FileAccess.READ)
		if file != null:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
				var player_club_stats = json.data.get(player_name, {})
				if not player_club_stats.is_empty():
					body += "PLAYER CLUB STATISTICS (HISTORICAL AVERAGES):\n"
					body += "=============================================\n"
					body += "%-6s | %-10s | %-10s | %-9s | %-12s | %-14s\n" % ["Club", "Avg Carry", "Avg Speed", "Avg Spin", "Avg Offline", "Avg +/- Target"]
					body += "--------------------------------------------------------------------------------\n"
					
					var club_order = ["Dr", "3w", "5w", "2H", "3H", "4H", "1i", "2i", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"]
					for c in player_club_stats.keys():
						if not club_order.has(c):
							club_order.append(c)
							
					for club in club_order:
						if not player_club_stats.has(club) or player_club_stats[club].is_empty():
							continue
							
						var club_shots = player_club_stats[club]
						var sum_carry := 0.0
						var sum_speed := 0.0
						var sum_spin := 0.0
						var sum_offline := 0.0
						var sum_target_diff := 0.0
						var valid_target_diff_count := 0
						
						for shot in club_shots:
							sum_carry += float(shot.get("CarryDistance", 0.0))
							sum_speed += float(shot.get("Speed", 0.0))
							sum_spin += float(shot.get("TotalSpin", 0.0))
							sum_offline += absf(float(shot.get("SideDistance", 0.0)))
							
							var target_dist = float(shot.get("TargetDistance", 0.0))
							var total_dist = float(shot.get("TotalDistance", 0.0))
							if target_dist > 0.0:
								sum_target_diff += (total_dist - target_dist)
								valid_target_diff_count += 1
								
						var cnt = club_shots.size()
						var avg_carry = sum_carry / cnt
						var avg_speed = sum_speed / cnt
						var avg_spin = sum_spin / cnt
						var avg_offline = sum_offline / cnt
						var avg_target_diff = sum_target_diff / valid_target_diff_count if valid_target_diff_count > 0 else 0.0
						
						# Convert to imperial values for the email scorecard
						var carry_val = avg_carry * 1.09361
						var speed_val = avg_speed
						var spin_val = avg_spin
						var offline_val = avg_offline * 1.09361
						var target_diff_val = avg_target_diff * 1.09361
						
						var carry_str = "%.1f yds" % carry_val
						var speed_str = "%.1f mph" % speed_val
						var spin_str = "%.0f rpm" % spin_val
						var offline_str = "%.1f yds" % offline_val
						var target_diff_sign = "+" if target_diff_val >= 0.0 else ""
						var target_diff_str = "%s%.1f yds" % [target_diff_sign, target_diff_val]
						
						if valid_target_diff_count == 0:
							target_diff_str = "---"
							
						body += "%-6s | %-10s | %-10s | %-9s | %-12s | %-14s\n" % [club, carry_str, speed_str, spin_str, offline_str, target_diff_str]
					body += "\n"
		
	body += MultiplayerManager.format_player_swing_issues_summary(player_name)
	
	var mailto_url = "mailto:?subject=" + subject.uri_encode() + "&body=" + body.uri_encode()
	OS.shell_open(mailto_url)


func _get_player_circle_texture(color: Color) -> ImageTexture:
	var color_key = color.to_html()
	if _cached_player_textures.has(color_key):
		return _cached_player_textures[color_key]
		
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := size / 2.0
	var radius := size / 2.0 - 2.0
	
	for y in range(size):
		for x in range(size):
			var dx := x - center + 0.5
			var dy := y - center + 0.5
			var dist := sqrt(dx * dx + dy * dy)
			if dist <= radius - 10.0:
				img.set_pixel(x, y, color)
			elif dist <= radius - 2.0:
				img.set_pixel(x, y, Color.WHITE)
			elif dist <= radius:
				var alpha = clamp((radius - dist) / 1.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(0, 0, 0, alpha))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				
	var tex := ImageTexture.create_from_image(img)
	_cached_player_textures[color_key] = tex
	return tex


func _create_player_map_marker(player: Dictionary, letter: String, color: Color) -> Node3D:
	var marker = Node3D.new()
	marker.name = "PlayerMapMarker_" + player["name"]
	
	# Cylinder mesh for the vertical line/stem
	var line_mesh = MeshInstance3D.new()
	line_mesh.name = "LineMesh"
	var cyl = CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.08
	cyl.height = 3.0
	line_mesh.mesh = cyl
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	line_mesh.material_override = mat
	line_mesh.layers = 2
	line_mesh.position = Vector3(0, 1.5, 0)
	marker.add_child(line_mesh)
	
	# Sprite3D for the circle background
	var sprite = Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = _get_player_circle_texture(color)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.double_sided = true
	sprite.pixel_size = 0.025 # ~3.2m wide
	sprite.position = Vector3(0, 3.0, 0)
	sprite.layers = 2
	marker.add_child(sprite)
	
	# Label3D for the letter
	var label = Label3D.new()
	label.name = "Label"
	label.text = letter
	label.font_size = 64
	label.modulate = Color.WHITE
	label.outline_modulate = Color.BLACK
	label.outline_size = 14
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.double_sided = true
	label.position = Vector3(0, 0.0, 0.05) # avoid z-fighting
	label.layers = 2
	sprite.add_child(label)
	
	return marker


func _clear_map_markers() -> void:
	for idx in _player_map_markers:
		var marker = _player_map_markers[idx]
		if is_instance_valid(marker):
			marker.queue_free()
	_player_map_markers.clear()


func _get_player_holes_played(p: Dictionary) -> int:
	var count = 0
	for hole_id in MultiplayerManager.hole_ids:
		if p["hole_scores"].get(hole_id) != null:
			count += 1
	return count


func _get_player_overall_diff(p: Dictionary) -> int:
	var player_total_strokes: int = 0
	var total_par_for_player: int = 0
	for hole_id in MultiplayerManager.hole_ids:
		var s = p["hole_scores"].get(hole_id)
		if s != null:
			player_total_strokes += int(s)
			var hole = MultiplayerManager.hole_info.get(hole_id, {})
			var par = int(hole.get("Par", 4))
			total_par_for_player += par
	return player_total_strokes - total_par_for_player


func _get_overall_par_string(p: Dictionary) -> String:
	var diff = _get_player_overall_diff(p)
	if diff > 0:
		return "+" + str(diff)
	elif diff < 0:
		return str(diff)
	else:
		return "E"


func _get_player_furthest_drive(p: Dictionary) -> float:
	var max_drive = 0.0
	var stats = p.get("shot_stats", {})
	for hole_id in stats:
		var shots = stats[hole_id]
		for shot in shots:
			if shot.get("shot_num") == 1:
				var dist = shot.get("total_yds", 0.0)
				if dist > max_drive:
					max_drive = dist
	return max_drive


func _get_player_best_hole(p: Dictionary) -> Dictionary:
	var best_hole_id = ""
	var best_diff = 9999
	var best_score = 0
	
	for hole_id in MultiplayerManager.hole_ids:
		var s = p["hole_scores"].get(hole_id)
		if s != null:
			var hole = MultiplayerManager.hole_info.get(hole_id, {})
			var par = hole.get("Par", 4)
			var diff = s - par
			if diff < best_diff:
				best_diff = diff
				best_hole_id = hole_id
				best_score = s
				
	if best_hole_id == "":
		return {}
	return {
		"hole_id": best_hole_id,
		"diff": best_diff,
		"score": best_score
	}


func _populate_overview() -> void:
	# Clear previous contents of hud_overview
	for child in hud_overview.get_children():
		child.queue_free()
		
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 24)
	hud_overview.add_child(vbox)
	
	# Title
	var title_lbl = Label.new()
	title_lbl.text = "Tournament Results"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.add_theme_color_override("font_color", Color(0.24, 0.46, 0.72, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 6)
	vbox.add_child(title_lbl)
	
	if MultiplayerManager.players.is_empty():
		return
		
	var sorted_players = MultiplayerManager.players.duplicate()
	sorted_players.sort_custom(func(a, b):
		var holes_a = _get_player_holes_played(a)
		var holes_b = _get_player_holes_played(b)
		if holes_a == 0 and holes_b > 0:
			return false
		if holes_b == 0 and holes_a > 0:
			return true
		if holes_a == 0 and holes_b == 0:
			return a["name"] < b["name"]
			
		var diff_a = _get_player_overall_diff(a)
		var diff_b = _get_player_overall_diff(b)
		if diff_a != diff_b:
			return diff_a < diff_b
		return a["name"] < b["name"]
	)
	
	# Winner presentation (First place)
	var winner = sorted_players[0]
	var winner_diff = _get_overall_par_string(winner)
	
	var winner_panel = PanelContainer.new()
	var wp_style = StyleBoxFlat.new()
	wp_style.bg_color = Color(0.12, 0.20, 0.32, 0.8) # Highlighted dark blue
	wp_style.border_width_left = 2
	wp_style.border_width_top = 2
	wp_style.border_width_right = 2
	wp_style.border_width_bottom = 2
	wp_style.border_color = Color.YELLOW # Gold border for winner
	wp_style.corner_radius_top_left = 12
	wp_style.corner_radius_top_right = 12
	wp_style.corner_radius_bottom_left = 12
	wp_style.corner_radius_bottom_right = 12
	wp_style.content_margin_left = 16
	wp_style.content_margin_right = 16
	wp_style.content_margin_top = 16
	wp_style.content_margin_bottom = 16
	winner_panel.add_theme_stylebox_override("panel", wp_style)
	vbox.add_child(winner_panel)
	
	var winner_vbox = VBoxContainer.new()
	winner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	winner_vbox.add_theme_constant_override("separation", 4)
	winner_panel.add_child(winner_vbox)
	
	var winner_title = Label.new()
	winner_title.text = "🏆 WINNER 🏆"
	winner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_title.add_theme_font_size_override("font_size", 24)
	winner_title.add_theme_color_override("font_color", Color.YELLOW)
	winner_title.add_theme_color_override("font_outline_color", Color.BLACK)
	winner_title.add_theme_constant_override("outline_size", 4)
	winner_vbox.add_child(winner_title)
	
	var winner_name_lbl = Label.new()
	winner_name_lbl.text = "%s (%s)" % [winner["name"], winner_diff]
	winner_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_name_lbl.add_theme_font_size_override("font_size", 32)
	winner_name_lbl.add_theme_color_override("font_color", Color.WHITE)
	winner_name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	winner_name_lbl.add_theme_constant_override("outline_size", 4)
	winner_vbox.add_child(winner_name_lbl)
	
	var winner_drive = _get_player_furthest_drive(winner)
	var winner_drive_str = "%.1f yds" % winner_drive if winner_drive > 0.0 else "N/A"
	
	var winner_best = _get_player_best_hole(winner)
	var winner_best_str = "N/A"
	if not winner_best.is_empty():
		var b_diff = winner_best["diff"]
		var b_diff_str = str(b_diff) if b_diff < 0 else ("+" + str(b_diff) if b_diff > 0 else "E")
		winner_best_str = "%s (%s)" % [winner_best["hole_id"], b_diff_str]
		
	var winner_stats_lbl = Label.new()
	winner_stats_lbl.text = "Furthest Drive: %s  |  Best Hole: %s" % [winner_drive_str, winner_best_str]
	winner_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	winner_stats_lbl.add_theme_font_size_override("font_size", 16)
	winner_stats_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	winner_vbox.add_child(winner_stats_lbl)
	
	# Other Players list
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)
	
	var players_list_vbox = VBoxContainer.new()
	players_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_list_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(players_list_vbox)
	
	for i in range(1, sorted_players.size()):
		var p = sorted_players[i]
		var p_diff = _get_overall_par_string(p)
		
		var p_panel = PanelContainer.new()
		var pp_style = StyleBoxFlat.new()
		pp_style.bg_color = Color(0.06, 0.08, 0.12, 0.8) if i % 2 == 1 else Color(0.1, 0.12, 0.18, 0.8)
		pp_style.border_width_bottom = 1
		pp_style.border_color = Color(0.25, 0.25, 0.25, 0.5)
		pp_style.corner_radius_top_left = 6
		pp_style.corner_radius_top_right = 6
		pp_style.corner_radius_bottom_left = 6
		pp_style.corner_radius_bottom_right = 6
		pp_style.content_margin_left = 12
		pp_style.content_margin_right = 12
		pp_style.content_margin_top = 8
		pp_style.content_margin_bottom = 8
		p_panel.add_theme_stylebox_override("panel", pp_style)
		players_list_vbox.add_child(p_panel)
		
		var p_vbox = VBoxContainer.new()
		p_vbox.add_theme_constant_override("separation", 2)
		p_panel.add_child(p_vbox)
		
		var row = HBoxContainer.new()
		p_vbox.add_child(row)
		
		var name_lbl = Label.new()
		name_lbl.text = "%d. %s" % [i + 1, p["name"]]
		name_lbl.add_theme_font_size_override("font_size", 20)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		
		var diff_lbl = Label.new()
		diff_lbl.text = p_diff
		diff_lbl.add_theme_font_size_override("font_size", 20)
		if p_diff.begins_with("-"):
			diff_lbl.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
		elif p_diff.begins_with("+"):
			diff_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
		else:
			diff_lbl.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(diff_lbl)
		
		var p_drive = _get_player_furthest_drive(p)
		var p_drive_str = "%.1f yds" % p_drive if p_drive > 0.0 else "N/A"
		
		var p_best = _get_player_best_hole(p)
		var p_best_str = "N/A"
		if not p_best.is_empty():
			var b_diff = p_best["diff"]
			var b_diff_str = str(b_diff) if b_diff < 0 else ("+" + str(b_diff) if b_diff > 0 else "E")
			p_best_str = "%s (%s)" % [p_best["hole_id"], b_diff_str]
			
		var stats_lbl = Label.new()
		stats_lbl.text = "Furthest Drive: %s  |  Best Hole: %s" % [p_drive_str, p_best_str]
		stats_lbl.add_theme_font_size_override("font_size", 14)
		stats_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		p_vbox.add_child(stats_lbl)
		
	# Return to Menu Button
	var menu_btn = Button.new()
	menu_btn.name = "ReturnToMenuBtn"
	menu_btn.text = "Return to Menu"
	menu_btn.custom_minimum_size = Vector2(200, 50)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apply_material_button_style(menu_btn, Color(0.56, 0.22, 0.22, 0.85))
	menu_btn.pressed.connect(func():
		SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
	)
	vbox.add_child(menu_btn)


func _draw_ball_overlays(overlay: Control) -> void:
	if MultiplayerManager.is_finished:
		return
		
	# Skip if scorecard, players list, camera setup dialog, or replay modal is open
	if hud_scorecard.visible or hud_manage_players.visible or hud_overview.visible:
		return
	var root = get_tree().root
	if root.find_child("CameraSetupDialog", true, false) != null or root.find_child("SwingReplayModal", true, false) != null:
		return
		
	var is_aerial = false
	if course_instance != null and course_instance.get("is_aerial_view") != null:
		is_aerial = course_instance.get("is_aerial_view") as bool
	if is_aerial:
		return
		
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return
		
	var font = overlay.get_theme_font("font")
	var font_size = 18
	
	# Determine active player position for dynamic scaling
	var active_player_pos = Vector3.ZERO
	if active_ball != null:
		active_player_pos = active_ball.global_position
	else:
		var p = MultiplayerManager.get_active_player()
		if not p.is_empty():
			active_player_pos = p.get("position", Vector3.ZERO)
			
	# Draw flag/hole icon
	var pin_pos = course_instance.get("current_hole_location") if course_instance != null else null
	if GlobalSettings.is_chipping_minigame and course_instance != null and course_instance.get("aim_target_pos") != null:
		pin_pos = course_instance.get("aim_target_pos")
	if pin_pos != null and not pin_pos.is_zero_approx():
		var is_on_green = false
		if active_ball != null:
			is_on_green = (active_ball.get("lie_type") == "green" or active_ball.get("surface_type") == PhysicsEnums.SurfaceType.GREEN)
		if not is_on_green and not camera.is_position_behind(pin_pos):
			var screen_pos = camera.unproject_position(pin_pos)
			var view_rect = overlay.get_viewport_rect()
			if view_rect.has_point(screen_pos):
				# Calculate dynamic height based on distance
				var dist_m = active_player_pos.distance_to(pin_pos)
				var dist_yards = dist_m * 1.09361
				var height = 0.0
				if dist_yards > 10.0:
					var t = clamp((dist_yards - 10.0) / (80.0 - 10.0), 0.0, 1.0)
					height = t * 2.4
					
				var offset_pos = pin_pos + Vector3(0, height, 0)
				if not camera.is_position_behind(offset_pos):
					var circle_pos = camera.unproject_position(offset_pos)
					
					# Draw stem line if height is significant
					if height > 0.1:
						overlay.draw_line(screen_pos, circle_pos, Color(1.0, 1.0, 1.0, 0.5), 2.0)
					
					# Draw circle shadow
					overlay.draw_circle(circle_pos, 17.0, Color(0.0, 0.0, 0.0, 0.35))
					# Draw circle border
					overlay.draw_circle(circle_pos, 16.0, Color(1.0, 1.0, 1.0, 0.6))
					# Draw circle fill (nice flag red)
					overlay.draw_circle(circle_pos, 14.0, Color(0.85, 0.15, 0.15, 0.65))
					
					# Draw flagpole (translucent white)
					overlay.draw_line(circle_pos + Vector2(-2, 7), circle_pos + Vector2(-2, -7), Color(1.0, 1.0, 1.0, 0.7), 2.0)
					
					# Draw flag banner (translucent white triangle)
					var banner_points = PackedVector2Array([
						circle_pos + Vector2(-2, -7),
						circle_pos + Vector2(6, -3.5),
						circle_pos + Vector2(-2, 0)
					])
					var banner_colors = PackedColorArray([
						Color(1.0, 1.0, 1.0, 0.7),
						Color(1.0, 1.0, 1.0, 0.7),
						Color(1.0, 1.0, 1.0, 0.7)
					])
					overlay.draw_polygon(banner_points, banner_colors)
					
	# Draw other players' balls
	for i in range(MultiplayerManager.players.size()):
		var p = MultiplayerManager.players[i]
		if p.get("holed_out", false) or not p.get("active", true):
			continue
			
		# Do not show circle for the current player
		if i == MultiplayerManager.active_player_index:
			continue
			
		var ball_pos = p.get("position", Vector3.ZERO)
		if ball_pos.is_zero_approx():
			continue
			
		if camera.is_position_behind(ball_pos):
			continue
			
		var screen_pos = camera.unproject_position(ball_pos)
		var view_rect = overlay.get_viewport_rect()
		if not view_rect.has_point(screen_pos):
			continue
			
		# Calculate dynamic height based on distance
		var dist_m = active_player_pos.distance_to(ball_pos)
		var dist_yards = dist_m * 1.09361
		var height = 0.0
		if dist_yards > 10.0:
			var t = clamp((dist_yards - 10.0) / (80.0 - 10.0), 0.0, 1.0)
			height = t * 2.4
			
		var offset_pos = ball_pos + Vector3(0, height, 0)
		if camera.is_position_behind(offset_pos):
			continue
			
		var circle_pos = camera.unproject_position(offset_pos)
		
		# Draw stem line if height is significant
		if height > 0.1:
			overlay.draw_line(screen_pos, circle_pos, Color(1.0, 1.0, 1.0, 0.5), 2.0)
		
		var p_color = MultiplayerManager.get_player_color(p)
		var translucent_color = Color(p_color.r, p_color.g, p_color.b, 0.65)
		
		# Draw circle shadow
		overlay.draw_circle(circle_pos, 17.0, Color(0.0, 0.0, 0.0, 0.35))
		# Draw circle border
		overlay.draw_circle(circle_pos, 16.0, Color(1.0, 1.0, 1.0, 0.6))
		# Draw circle fill
		overlay.draw_circle(circle_pos, 14.0, translucent_color)
		
		var letter = p["name"].substr(0, 1).to_upper()
		var text_pos = Vector2(circle_pos.x - 16, circle_pos.y + font.get_ascent(font_size) * 0.35)
		
		overlay.draw_string_outline(font, text_pos, letter, HORIZONTAL_ALIGNMENT_CENTER, 32.0, font_size, 3, Color(0.0, 0.0, 0.0, 0.5))
		overlay.draw_string(font, text_pos, letter, HORIZONTAL_ALIGNMENT_CENTER, 32.0, font_size, Color(1.0, 1.0, 1.0, 0.7))


func apply_zoom_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 14
	style_normal.corner_radius_top_right = 14
	style_normal.corner_radius_bottom_left = 14
	style_normal.corner_radius_bottom_right = 14
	style_normal.content_margin_left = 2
	style_normal.content_margin_right = 2
	style_normal.content_margin_top = 2
	style_normal.content_margin_bottom = 2

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 16)


func _update_grid_button_state(active: bool) -> void:
	var btn = null
	if has_node("TogglesScroll/TogglesContainer/GreenGridToggleButton"):
		btn = get_node("TogglesScroll/TogglesContainer/GreenGridToggleButton")
	elif has_node("TogglesContainer/GreenGridToggleButton"):
		btn = get_node("TogglesContainer/GreenGridToggleButton")
	elif has_node("GreenGridToggleButton"):
		btn = get_node("GreenGridToggleButton")
		
	if btn != null:
		if active:
			btn.text = "📊 Slope Grid: ON"
			apply_material_button_style(btn, Color(0.2, 0.6, 0.3, 0.85)) # Green when active
		else:
			btn.text = "📊 Slope Grid: OFF"
			apply_material_button_style(btn, Color(0.5, 0.5, 0.5, 0.85)) # Gray when inactive


class MultiplayerBallOverlay extends Control:
	var _controller: Node = null
	
	func _init(controller: Node) -> void:
		_controller = controller
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
	func _draw() -> void:
		if _controller != null and _controller.has_method("_draw_ball_overlays"):
			_controller._draw_ball_overlays(self)
