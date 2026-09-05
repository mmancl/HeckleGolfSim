extends Node3D

var hud_player_name_lbl: Label = null
var hud_player_badge: PanelContainer = null
var hud_player_badge_lbl: Label = null
var hud_player_avatar_rect: TextureRect = null
var hud_overall_score_lbl: Label = null
var hud_hole_num_lbl: Label = null
var hud_shots_rtl: RichTextLabel = null
var _minimap_group: HBoxContainer = null
var _distance_tracker_panel: Container = null
var _back_lbl: Label = null
var _hole_lbl: Label = null
var _front_lbl: Label = null
var _distance_unit_lbl: Label = null

var _last_hud_strokes: int = -1
var _last_hud_player_name: String = ""
var _last_hud_hole_index: int = -1

@onready var hud_scorecard = Panel.new()
@onready var scorecard_grid = GridContainer.new()
var _scorecard_action_btn: Button = null
var _scorecard_countdown_container: HBoxContainer = null
var _scorecard_countdown_lbl: Label = null
var _scorecard_pause_btn: Button = null
var _scorecard_countdown_time_left: float = 0.0
var _scorecard_countdown_active: bool = false
var _scorecard_countdown_paused: bool = false
var _scorecard_view_tab: String = "All"
var _last_scorecard_action_type: String = "toggle"
@onready var hud_manage_players = Panel.new()
@onready var hud_overview = Panel.new()
var _minimap_camera: Camera3D = null
var _minimap_viewport: SubViewport = null
var _minimap_panel: PanelContainer = null
var minimap_zoom: float = 300.0
var _last_was_on_green: bool = false
var _default_non_green_minimap_zoom: float = 300.0
var _teebox_minimap_zoom: float = 300.0
var _last_zoom_zone: int = -1
var _minimap_zoom_dirty: bool = true
var _prev_ball_moving: bool = false
var _minimap_flag_icon: TextureRect = null
var _minimap_ball_icon: TextureRect = null

var _cached_green_verts: PackedVector3Array = PackedVector3Array()
var _cached_green_hole_index: int = -1

var _overlay_node: Control = null
var _player_map_markers: Dictionary = {}
var _cached_player_textures: Dictionary = {}

var range_ui: Control = null
var top_bar: HBoxContainer = null
var right_panel: VBoxContainer = null
var toggles_scroll: ScrollContainer = null
var settings_btn: Button = null
var home_btn: Button = null
var hide_helpers_btn: Button = null
var stats_btn: Button = null
var grid_btn: Button = null
var map_btn: Button = null
var mulligan_btn: Button = null
var forfeit_btn: Button = null
var club_selector_node: Control = null

var course_instance: Node = null
var active_ball: Node = null
var mulligan_confirm_dialog: PanelContainer = null
var forfeit_confirm_dialog: PanelContainer = null
var exit_confirm_dialog: Control = null
var _hud_elements_visible: bool = true

var _was_helpers_visible_before_aerial: bool = false
var _is_aerial_active_practice: bool = false

var gimme_banner: PanelContainer = null
var gimme_title_lbl: Label = null
var gimme_sub_lbl: Label = null
var _gimme_tween: Tween = null
var is_player_turn_ready: bool = true

func is_gimme_banner_active() -> bool:
	return gimme_banner != null and is_instance_valid(gimme_banner) and gimme_banner.visible and gimme_banner.modulate.a > 0.05

func _ready() -> void:
	MultiplayerManager.active_player_changed.connect(_on_active_player_changed)
	MultiplayerManager.hole_completed.connect(_on_hole_completed)
	MultiplayerManager.game_over.connect(_on_game_over)
	MultiplayerManager.gimme_awarded.connect(_on_gimme_awarded)
	
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

	# Forfeit Confirm Dialog (Concede Hole when at 10+ strokes)
	forfeit_confirm_dialog = PanelContainer.new()
	forfeit_confirm_dialog.name = "ForfeitConfirmDialog"
	forfeit_confirm_dialog.visible = false
	forfeit_confirm_dialog.anchor_left = 0.5
	forfeit_confirm_dialog.anchor_right = 0.5
	forfeit_confirm_dialog.anchor_top = 0.5
	forfeit_confirm_dialog.anchor_bottom = 0.5
	forfeit_confirm_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	forfeit_confirm_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	forfeit_confirm_dialog.offset_left = -220
	forfeit_confirm_dialog.offset_right = 220
	forfeit_confirm_dialog.offset_top = -100
	forfeit_confirm_dialog.offset_bottom = 100

	var forfeit_dialog_style = StyleBoxFlat.new()
	forfeit_dialog_style.bg_color = Color(0.08, 0.08, 0.08, 0.95)
	forfeit_dialog_style.border_width_left = 2
	forfeit_dialog_style.border_width_top = 2
	forfeit_dialog_style.border_width_right = 2
	forfeit_dialog_style.border_width_bottom = 2
	forfeit_dialog_style.border_color = Color(0.65, 0.25, 0.25, 0.8)
	forfeit_dialog_style.corner_radius_top_left = 12
	forfeit_dialog_style.corner_radius_top_right = 12
	forfeit_dialog_style.corner_radius_bottom_left = 12
	forfeit_dialog_style.corner_radius_bottom_right = 12
	forfeit_dialog_style.content_margin_left = 24
	forfeit_dialog_style.content_margin_right = 24
	forfeit_dialog_style.content_margin_top = 20
	forfeit_dialog_style.content_margin_bottom = 20
	forfeit_dialog_style.shadow_color = Color(0, 0, 0, 0.7)
	forfeit_dialog_style.shadow_size = 10
	forfeit_confirm_dialog.add_theme_stylebox_override("panel", forfeit_dialog_style)
	canvas.add_child(forfeit_confirm_dialog)

	# Exit Match Confirm Dialog (Prompt when Home button is pressed)
	exit_confirm_dialog = Control.new()
	exit_confirm_dialog.name = "ExitConfirmDialog"
	exit_confirm_dialog.visible = false
	exit_confirm_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	exit_confirm_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	exit_confirm_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	exit_confirm_dialog.mouse_filter = Control.MOUSE_FILTER_STOP

	var exit_backdrop = ColorRect.new()
	exit_backdrop.name = "Backdrop"
	exit_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	exit_backdrop.grow_horizontal = Control.GROW_DIRECTION_BOTH
	exit_backdrop.grow_vertical = Control.GROW_DIRECTION_BOTH
	exit_backdrop.color = Color(0.0, 0.0, 0.0, 0.65)
	exit_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			exit_confirm_dialog.visible = false
	)
	exit_confirm_dialog.add_child(exit_backdrop)

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
		exit_confirm_dialog.visible = false
		MultiplayerManager.players.clear()
		MultiplayerManager.practice_mode_active = false
		SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
	)
	exit_btn_hbox.add_child(exit_yes_btn)

	var exit_no_btn = Button.new()
	exit_no_btn.name = "NoButton"
	exit_no_btn.text = "No"
	exit_no_btn.custom_minimum_size = Vector2(140, 50)
	apply_material_button_style(exit_no_btn, Color(0.24, 0.46, 0.72, 0.85))
	exit_no_btn.pressed.connect(func():
		exit_confirm_dialog.visible = false
	)
	exit_btn_hbox.add_child(exit_no_btn)

	exit_content_vbox.add_child(exit_btn_hbox)
	exit_panel.add_child(exit_content_vbox)
	exit_confirm_dialog.add_child(exit_panel)
	canvas.add_child(exit_confirm_dialog)
	
	# Gimme Awarded Banner
	gimme_banner = PanelContainer.new()
	gimme_banner.name = "GimmeBanner"
	gimme_banner.visible = false
	gimme_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gimme_banner.anchor_left = 0.5
	gimme_banner.anchor_right = 0.5
	gimme_banner.anchor_top = 0.18
	gimme_banner.anchor_bottom = 0.18
	gimme_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	gimme_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	gimme_banner.custom_minimum_size = Vector2(380, 110)
	
	var gimme_style = StyleBoxFlat.new()
	gimme_style.bg_color = Color(0.08, 0.14, 0.10, 0.92) # Rich deep emerald/slate background
	gimme_style.border_width_left = 3
	gimme_style.border_width_top = 3
	gimme_style.border_width_right = 3
	gimme_style.border_width_bottom = 3
	gimme_style.border_color = Color(1.0, 0.85, 0.38, 0.95) # Radiant gold border
	gimme_style.corner_radius_top_left = 16
	gimme_style.corner_radius_top_right = 16
	gimme_style.corner_radius_bottom_right = 16
	gimme_style.corner_radius_bottom_left = 16
	gimme_style.content_margin_left = 32
	gimme_style.content_margin_right = 32
	gimme_style.content_margin_top = 16
	gimme_style.content_margin_bottom = 16
	gimme_style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	gimme_style.shadow_size = 12
	gimme_banner.add_theme_stylebox_override("panel", gimme_style)
	
	var g_vbox = VBoxContainer.new()
	g_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	g_vbox.add_theme_constant_override("separation", 2)
	gimme_banner.add_child(g_vbox)
	
	gimme_title_lbl = Label.new()
	gimme_title_lbl.name = "GimmeTitleLabel"
	gimme_title_lbl.text = "GIMME +1"
	gimme_title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gimme_title_lbl.add_theme_font_size_override("font_size", 34)
	gimme_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	gimme_title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	gimme_title_lbl.add_theme_constant_override("outline_size", 6)
	g_vbox.add_child(gimme_title_lbl)
	
	gimme_sub_lbl = Label.new()
	gimme_sub_lbl.name = "GimmeSubLabel"
	gimme_sub_lbl.text = "Player Holed Out"
	gimme_sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gimme_sub_lbl.add_theme_font_size_override("font_size", 18)
	gimme_sub_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9))
	gimme_sub_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	gimme_sub_lbl.add_theme_constant_override("outline_size", 4)
	g_vbox.add_child(gimme_sub_lbl)
	
	canvas.add_child(gimme_banner)
	
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
	
	hud_player_avatar_rect = TextureRect.new()
	hud_player_avatar_rect.custom_minimum_size = Vector2(26, 26)
	hud_player_avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_player_avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hud_player_avatar_rect.visible = false
	hud_player_badge.add_child(hud_player_avatar_rect)
	
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
	settings_btn.pressed.connect(func():
		if range_ui != null:
			range_ui.call("_on_toggle_settings_requested")
	)
	canvas.add_child(settings_btn)

	# Home / Main Menu Button (Icon Only) - positioned between Settings and HideHelpers
	home_btn = Button.new()
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
	home_btn.pressed.connect(func():
		if MultiplayerManager.is_finished:
			SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
		elif exit_confirm_dialog != null:
			if forfeit_confirm_dialog != null:
				forfeit_confirm_dialog.visible = false
			if mulligan_confirm_dialog != null:
				mulligan_confirm_dialog.visible = false
			exit_confirm_dialog.visible = true
	)
	canvas.add_child(home_btn)

	# Hide/Show Helpers Button (Icon Only) - positioned to the left of Home Button
	hide_helpers_btn = Button.new()
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
	canvas.add_child(hide_helpers_btn)

	# RightPanel vertical stack - starts below ClubSelector
	right_panel = VBoxContainer.new()
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
	canvas.add_child(right_panel)

	# ScrollContainer keeps buttons visible on short screens - hidden by default!
	toggles_scroll = ScrollContainer.new()
	toggles_scroll.name = "TogglesScroll"
	toggles_scroll.visible = false
	toggles_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	toggles_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toggles_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ThemeManager.apply_scroll_container_style(toggles_scroll, 28)
	
	var toggles_container = VBoxContainer.new()
	toggles_container.name = "TogglesContainer"
	toggles_container.add_theme_constant_override("separation", 12)
	toggles_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	hide_helpers_btn.pressed.connect(func():
		var new_vis = not toggles_scroll.visible
		_set_helpers_visible(new_vis)
	)
	
	toggles_scroll.add_child(toggles_container)
	right_panel.add_child(toggles_scroll)

	# Announcer Mute/Unmute Toggle Button
	var announcer_btn = Button.new()
	announcer_btn.name = "AnnouncerToggleButton"
	var announcer_node = get_node_or_null("/root/AnnouncerEngine")
	var is_announcer_on = announcer_node.get("AnnouncerCoursePlay") if announcer_node != null else true
	announcer_btn.text = "🎙 Announcer: ON" if is_announcer_on else "🎙 Announcer: MUTED"
	announcer_btn.tooltip_text = "Toggle Announcer Commentary"
	announcer_btn.custom_minimum_size = Vector2(180, 56)
	var initial_ann_color = Color(0.2, 0.6, 0.3, 0.85) if is_announcer_on else Color(0.5, 0.5, 0.5, 0.85)
	apply_material_button_style(announcer_btn, initial_ann_color)
	announcer_btn.pressed.connect(func():
		var a = get_node_or_null("/root/AnnouncerEngine")
		if a != null:
			var current_val = a.get("AnnouncerCoursePlay") as bool
			var new_val = not current_val
			a.set("AnnouncerCoursePlay", new_val)
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

	# Shot Analysis Toggle Button
	var shot_analysis_btn = Button.new()
	shot_analysis_btn.name = "ShotAnalysisButton"
	var is_shot_analysis_on = GlobalSettings.range_settings.shot_analysis_enabled.value if has_node("/root/GlobalSettings") else false
	shot_analysis_btn.text = "📊 Shot Analysis: ON" if is_shot_analysis_on else "📊 Shot Analysis: OFF"
	shot_analysis_btn.tooltip_text = "Toggle Shot Suggestions & Flaw Analysis"
	shot_analysis_btn.custom_minimum_size = Vector2(180, 56)
	var initial_analysis_color = Color(0.15, 0.55, 0.75, 0.85) if is_shot_analysis_on else Color(0.25, 0.35, 0.45, 0.85)
	apply_material_button_style(shot_analysis_btn, initial_analysis_color)
	shot_analysis_btn.pressed.connect(func():
		if has_node("/root/GlobalSettings"):
			var new_val = not GlobalSettings.range_settings.shot_analysis_enabled.value
			GlobalSettings.range_settings.shot_analysis_enabled.value = new_val
			GlobalSettings.save_settings()
			if range_ui != null and range_ui.has_method("set_shot_analysis_enabled"):
				range_ui.call("set_shot_analysis_enabled", new_val)
			if new_val:
				shot_analysis_btn.text = "📊 Shot Analysis: ON"
				apply_material_button_style(shot_analysis_btn, Color(0.15, 0.55, 0.75, 0.85))
			else:
				shot_analysis_btn.text = "📊 Shot Analysis: OFF"
				apply_material_button_style(shot_analysis_btn, Color(0.25, 0.35, 0.45, 0.85))
	)
	toggles_container.add_child(shot_analysis_btn)

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
		scorecard_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(scorecard_btn, Color(0.72, 0.56, 0.24, 0.85)) # Gold color
		scorecard_btn.pressed.connect(_on_scorecard_toggle_pressed)
		toggles_container.add_child(scorecard_btn)

		# Manage Players Toggle Button
		var players_btn = Button.new()
		players_btn.name = "ManagePlayersButton"
		players_btn.text = "👥 Players"
		players_btn.custom_minimum_size = Vector2(180, 56)
		apply_material_button_style(players_btn, Color(0.25, 0.55, 0.35, 0.85)) # Green-ish
		players_btn.pressed.connect(_on_manage_players_toggle_pressed)
		toggles_container.add_child(players_btn)

	# If in practice mode, create practice buttons (initially hidden, shown only in map view)
	if MultiplayerManager.practice_mode_active and not GlobalSettings.is_chipping_minigame:
		var place_btn = Button.new()
		place_btn.name = "PlaceBallButton"
		place_btn.text = "📍 Place Ball: OFF"
		place_btn.custom_minimum_size = Vector2(210, 64)
		place_btn.add_theme_font_size_override("font_size", 20)
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
		prev_btn.custom_minimum_size = Vector2(210, 64)
		prev_btn.add_theme_font_size_override("font_size", 20)
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
		next_btn.custom_minimum_size = Vector2(210, 64)
		next_btn.add_theme_font_size_override("font_size", 20)
		apply_material_button_style(next_btn, Color(0.4, 0.4, 0.4, 0.85))
		next_btn.pressed.connect(func():
			if course_instance != null and course_instance.has_method("next_practice_hole"):
				course_instance.call("next_practice_hole")
		)
		next_btn.visible = false
		toggles_container.add_child(next_btn)
		
		# Move them to the top of toggles_container so they are ordered nicely
		var top_idx = announcer_btn.get_index()
		toggles_container.move_child(place_btn, top_idx + 1)
		toggles_container.move_child(prev_btn, top_idx + 2)
		toggles_container.move_child(next_btn, top_idx + 3)
	
	# Reparent ClubSelector to canvas directly underneath SettingsButton and HideHelpersButton
	if range_ui != null:
		var club_sel = range_ui.get_node_or_null("GridCanvas/ClubSelector")
		if club_sel == null:
			club_sel = range_ui.get_node_or_null("OverlayLayer/ClubSelector")
			if club_sel == null:
				club_sel = range_ui.get_node_or_null("RightPanel/TogglesScroll/TogglesContainer/ClubSelector")
				if club_sel == null:
					club_sel = range_ui.get_node_or_null("RightPanel/TogglesContainer/ClubSelector")
					if club_sel == null:
						club_sel = range_ui.get_node_or_null("RightPanel/ClubSelector")
		if club_sel != null:
			club_sel.reparent(canvas)
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
			club_selector_node = club_sel

	# Stats Button (Icon Only) - Bottom-Left Corner
	stats_btn = Button.new()
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
		if range_ui != null:
			range_ui.call("toggle_stats_visibility")
			if range_ui.call("is_stats_visible"):
				apply_circular_button_style(stats_btn, Color(0.24, 0.46, 0.72, 0.85))
			else:
				apply_circular_button_style(stats_btn, Color(0.15, 0.15, 0.15, 0.85))
	)
	canvas.add_child(stats_btn)

	# Slope Grid Toggle Button (Icon Only) - Bottom-Left, right of Stats button
	grid_btn = Button.new()
	grid_btn.name = "GreenGridToggleButton"
	grid_btn.text = ""
	grid_btn.tooltip_text = "Toggle Slope Grid (Show/Hide)"
	if ResourceLoader.exists("res://assets/images/icons/slope_grid.svg"):
		grid_btn.icon = load("res://assets/images/icons/slope_grid.svg")
	grid_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid_btn.custom_minimum_size = Vector2(64, 64)
	apply_circular_button_style(grid_btn, Color(0.15, 0.15, 0.15, 0.85)) # Gray (off) by default
	grid_btn.anchor_left = 0.0
	grid_btn.anchor_right = 0.0
	grid_btn.anchor_top = 1.0
	grid_btn.anchor_bottom = 1.0
	grid_btn.offset_left = 126   # 94 (stats right) + 32px gap
	grid_btn.offset_top = -88
	grid_btn.offset_right = 190 # 126 + 64 button width
	grid_btn.offset_bottom = -24
	grid_btn.pressed.connect(func():
		if course_instance != null and course_instance.get("show_green_grid") != null:
			var current_grid = course_instance.get("show_green_grid") as bool
			course_instance.set("show_green_grid", not current_grid)
	)
	canvas.add_child(grid_btn)

	# Map Toggle Button (Icon Only) - Bottom-Right Corner
	map_btn = Button.new()
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
		if course_instance and course_instance.has_method("_on_map_button_pressed"):
			course_instance.call("_on_map_button_pressed")
	)
	canvas.add_child(map_btn)

	# Mulligan Button (Icon Only) - Bottom-Right next to Map button
	mulligan_btn = Button.new()
	mulligan_btn.name = "MulliganButton"
	mulligan_btn.text = ""
	mulligan_btn.tooltip_text = "Mulligan (Undo Shot)"
	if ResourceLoader.exists("res://assets/images/icons/mulligan.svg"):
		mulligan_btn.icon = load("res://assets/images/icons/mulligan.svg")
	mulligan_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mulligan_btn.custom_minimum_size = Vector2(64, 64)
	apply_circular_button_style(mulligan_btn, Color(0.24, 0.46, 0.72, 0.85))
	mulligan_btn.anchor_left = 1.0
	mulligan_btn.anchor_right = 1.0
	mulligan_btn.anchor_top = 1.0
	mulligan_btn.anchor_bottom = 1.0
	mulligan_btn.offset_left = -190  # -126 - 64 button width
	mulligan_btn.offset_top = -88
	mulligan_btn.offset_right = -126 # -94 (map left) - 32px gap
	mulligan_btn.offset_bottom = -24
	mulligan_btn.pressed.connect(_on_mulligan_pressed)
	mulligan_btn.visible = is_match_play
	canvas.add_child(mulligan_btn)

	# Forfeit / White Flag Button (Icon Only) - Bottom-Right next to Mulligan button
	forfeit_btn = Button.new()
	forfeit_btn.name = "ForfeitButton"
	forfeit_btn.text = ""
	forfeit_btn.tooltip_text = "White Flag (Concede Hole)"
	if ResourceLoader.exists("res://assets/images/icons/white_flag.svg"):
		var icon_tex = load("res://assets/images/icons/white_flag.svg")
		if icon_tex != null:
			forfeit_btn.icon = icon_tex
	if forfeit_btn.icon == null:
		forfeit_btn.text = "🏳"
		forfeit_btn.add_theme_font_size_override("font_size", 28)
	forfeit_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forfeit_btn.custom_minimum_size = Vector2(64, 64)
	apply_circular_button_style(forfeit_btn, Color(0.68, 0.22, 0.22, 0.88))
	forfeit_btn.anchor_left = 1.0
	forfeit_btn.anchor_right = 1.0
	forfeit_btn.anchor_top = 1.0
	forfeit_btn.anchor_bottom = 1.0
	forfeit_btn.offset_left = -286  # -222 - 64 button width
	forfeit_btn.offset_top = -88
	forfeit_btn.offset_right = -222 # -190 (mulligan left) - 32px gap
	forfeit_btn.offset_bottom = -24
	forfeit_btn.pressed.connect(_on_forfeit_pressed)
	forfeit_btn.visible = false
	canvas.add_child(forfeit_btn)
	
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
	dt_vbox.add_theme_constant_override("separation", 8) # stack vertically
	_distance_tracker_panel.add_child(dt_vbox)
	
	var back_green_label = Label.new()
	back_green_label.name = "BackGreenLabel"
	back_green_label.text = "---"
	back_green_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_green_label.add_theme_font_size_override("font_size", 22)
	back_green_label.add_theme_color_override("font_color", Color.WHITE)
	back_green_label.add_theme_color_override("font_outline_color", Color.BLACK)
	back_green_label.add_theme_constant_override("outline_size", 4)
	_back_lbl = back_green_label
	dt_vbox.add_child(back_green_label)
	
	var mid_hbox = HBoxContainer.new()
	mid_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	mid_hbox.add_theme_constant_override("separation", 4)
	dt_vbox.add_child(mid_hbox)
	
	var flag_label = Label.new()
	flag_label.text = "⚑"
	flag_label.add_theme_font_size_override("font_size", 24)
	flag_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.22)) # Golden amber flag
	flag_label.add_theme_color_override("font_outline_color", Color.BLACK)
	flag_label.add_theme_constant_override("outline_size", 4)
	mid_hbox.add_child(flag_label)
	
	var hole_label = Label.new()
	hole_label.name = "HoleLabel"
	hole_label.text = "---"
	hole_label.add_theme_font_size_override("font_size", 26)
	hole_label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.22)) # Golden amber / Accent
	hole_label.add_theme_color_override("font_outline_color", Color.BLACK)
	hole_label.add_theme_constant_override("outline_size", 4)
	_hole_lbl = hole_label
	mid_hbox.add_child(hole_label)
	
	var front_green_label = Label.new()
	front_green_label.name = "FrontGreenLabel"
	front_green_label.text = "---"
	front_green_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	front_green_label.add_theme_font_size_override("font_size", 22)
	front_green_label.add_theme_color_override("font_color", Color.WHITE)
	front_green_label.add_theme_color_override("font_outline_color", Color.BLACK)
	front_green_label.add_theme_constant_override("outline_size", 4)
	_front_lbl = front_green_label
	dt_vbox.add_child(front_green_label)

	var unit_label = Label.new()
	unit_label.name = "UnitLabel"
	unit_label.text = "YDS"
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_label.add_theme_font_size_override("font_size", 13)
	unit_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	unit_label.add_theme_color_override("font_outline_color", Color.BLACK)
	unit_label.add_theme_constant_override("outline_size", 3)
	_distance_unit_lbl = unit_label
	dt_vbox.add_child(unit_label)
	
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
	minimap_camera.cull_mask = minimap_camera.cull_mask & ~4
	
	viewport.add_child(minimap_camera)
	minimap_container.add_child(viewport)
	minimap_panel.add_child(minimap_container)
	
	# Make the camera current inside the SubViewport
	minimap_camera.make_current()
	
	_minimap_camera = minimap_camera
	_minimap_viewport = viewport
	_minimap_panel = minimap_panel
	
	# Add Zoom buttons to Minimap Panel
	var zoom_overlay = Control.new()
	zoom_overlay.name = "ZoomOverlay"
	zoom_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	minimap_panel.add_child(zoom_overlay)

	# Flag Marker on Minimap Overlay (shows at hole location on green heatmap)
	var flag_icon = TextureRect.new()
	flag_icon.name = "MinimapFlagMarker"
	flag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag_icon.custom_minimum_size = Vector2(32, 36)
	flag_icon.size = Vector2(32, 36)
	flag_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flag_icon.texture = _get_minimap_flag_texture()
	flag_icon.visible = false
	zoom_overlay.add_child(flag_icon)
	_minimap_flag_icon = flag_icon

	# Ball Marker on Minimap Overlay (shows at player's ball location on green heatmap)
	var ball_icon = TextureRect.new()
	ball_icon.name = "MinimapBallMarker"
	ball_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ball_icon.custom_minimum_size = Vector2(24, 24)
	ball_icon.size = Vector2(24, 24)
	ball_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ball_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ball_icon.texture = _get_minimap_ball_texture()
	ball_icon.visible = false
	zoom_overlay.add_child(ball_icon)
	_minimap_ball_icon = ball_icon

	var zoom_vbox = VBoxContainer.new()
	zoom_vbox.name = "ZoomVBox"
	zoom_vbox.anchor_left = 1.0
	zoom_vbox.anchor_right = 1.0
	zoom_vbox.anchor_top = 0.0
	zoom_vbox.anchor_bottom = 0.0
	zoom_vbox.offset_left = -48
	zoom_vbox.offset_top = 8
	zoom_vbox.offset_right = -8
	zoom_vbox.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	zoom_vbox.add_theme_constant_override("separation", 6)
	zoom_overlay.add_child(zoom_vbox)

	var zoom_in_btn = Button.new()
	zoom_in_btn.name = "ZoomInButton"
	zoom_in_btn.text = "+"
	zoom_in_btn.custom_minimum_size = Vector2(40, 40)
	apply_zoom_button_style(zoom_in_btn, Color(0.15, 0.15, 0.15, 0.85))
	zoom_in_btn.pressed.connect(func():
		minimap_zoom = clamp(minimap_zoom - 25.0, 50.0, 500.0)
		if _last_zoom_zone == 0:
			_teebox_minimap_zoom = minimap_zoom
			_default_non_green_minimap_zoom = minimap_zoom
		_update_minimap()
	)
	zoom_vbox.add_child(zoom_in_btn)

	var zoom_out_btn = Button.new()
	zoom_out_btn.name = "ZoomOutButton"
	zoom_out_btn.text = "-"
	zoom_out_btn.custom_minimum_size = Vector2(40, 40)
	apply_zoom_button_style(zoom_out_btn, Color(0.15, 0.15, 0.15, 0.85))
	zoom_out_btn.pressed.connect(func():
		minimap_zoom = clamp(minimap_zoom + 25.0, 50.0, 500.0)
		if _last_zoom_zone == 0:
			_teebox_minimap_zoom = minimap_zoom
			_default_non_green_minimap_zoom = minimap_zoom
		_update_minimap()
	)
	zoom_vbox.add_child(zoom_out_btn)
	
	# Scorecard Panel
	hud_scorecard.name = "ScorecardPanel"
	hud_scorecard.visible = false
	hud_scorecard.anchor_left = 0.02
	hud_scorecard.anchor_right = 0.98
	hud_scorecard.anchor_top = 0.03
	hud_scorecard.anchor_bottom = 0.97
	hud_scorecard.offset_left = 0
	hud_scorecard.offset_right = 0
	hud_scorecard.offset_top = 0
	hud_scorecard.offset_bottom = 0
	hud_scorecard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_scorecard.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.06, 0.09, 0.14, 0.96)
	card_style.border_width_left = 2
	card_style.border_width_top = 2
	card_style.border_width_right = 2
	card_style.border_width_bottom = 2
	card_style.border_color = Color(0.72, 0.56, 0.24, 0.85) # Gold border
	card_style.corner_radius_top_left = 16
	card_style.corner_radius_top_right = 16
	card_style.corner_radius_bottom_left = 16
	card_style.corner_radius_bottom_right = 16
	card_style.content_margin_left = 16
	card_style.content_margin_right = 16
	card_style.content_margin_top = 16
	card_style.content_margin_bottom = 16
	hud_scorecard.add_theme_stylebox_override("panel", card_style)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_scorecard.add_child(vbox)
	
	var sc_title = Label.new()
	sc_title.name = "TitleLabel"
	sc_title.text = "Scorecard"
	sc_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sc_title.add_theme_font_size_override("font_size", 30)
	sc_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
	sc_title.add_theme_color_override("font_outline_color", Color.BLACK)
	sc_title.add_theme_constant_override("outline_size", 4)
	vbox.add_child(sc_title)
	
	var scroll = ScrollContainer.new()
	scroll.name = "ScorecardScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	ThemeManager.apply_scroll_container_style(scroll, 28)
	vbox.add_child(scroll)
	
	scorecard_grid.name = "ScorecardGrid"
	scorecard_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scorecard_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scorecard_grid.add_theme_constant_override("h_separation", 2)
	scorecard_grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(scorecard_grid)
	
	var actions_row = HBoxContainer.new()
	actions_row.name = "ScorecardActionsRow"
	actions_row.alignment = BoxContainer.ALIGNMENT_CENTER
	actions_row.add_theme_constant_override("separation", 18)
	actions_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(actions_row)

	var action_btn = Button.new()
	action_btn.name = "ScorecardActionBtn"
	action_btn.text = "Next Hole"
	action_btn.custom_minimum_size = Vector2(180, 56)
	action_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apply_material_button_style(action_btn, Color(0.24, 0.46, 0.72, 0.85))
	actions_row.add_child(action_btn)
	_scorecard_action_btn = action_btn

	_scorecard_countdown_container = HBoxContainer.new()
	_scorecard_countdown_container.name = "ScorecardCountdownContainer"
	_scorecard_countdown_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_scorecard_countdown_container.add_theme_constant_override("separation", 12)
	_scorecard_countdown_container.visible = false
	actions_row.add_child(_scorecard_countdown_container)

	_scorecard_countdown_lbl = Label.new()
	_scorecard_countdown_lbl.name = "ScorecardCountdownLabel"
	_scorecard_countdown_lbl.text = "Next hole in 5s..."
	_scorecard_countdown_lbl.custom_minimum_size = Vector2(180, 0)
	_scorecard_countdown_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scorecard_countdown_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scorecard_countdown_lbl.add_theme_font_size_override("font_size", 20)
	_scorecard_countdown_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 1.0))
	_scorecard_countdown_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_scorecard_countdown_lbl.add_theme_constant_override("outline_size", 3)
	_scorecard_countdown_container.add_child(_scorecard_countdown_lbl)

	_scorecard_pause_btn = Button.new()
	_scorecard_pause_btn.name = "ScorecardPauseBtn"
	_scorecard_pause_btn.text = "⏸ Pause"
	_scorecard_pause_btn.custom_minimum_size = Vector2(130, 56)
	apply_material_button_style(_scorecard_pause_btn, Color(0.35, 0.38, 0.45, 0.85))
	_scorecard_pause_btn.pressed.connect(_on_scorecard_pause_toggled)
	_scorecard_countdown_container.add_child(_scorecard_pause_btn)
	
	margin.add_child(hud_scorecard)


	# Manage Players Panel
	hud_manage_players.name = "ManagePlayersPanel"
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
	ThemeManager.apply_scroll_container_style(m_scroll, 28)
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
	m_add_btn.custom_minimum_size = Vector2(130, 48)
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
	m_close_btn.custom_minimum_size = Vector2(160, 48)
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
	hud_overview.anchor_left = 0.03
	hud_overview.anchor_right = 0.97
	hud_overview.anchor_top = 0.04
	hud_overview.anchor_bottom = 0.96
	hud_overview.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_overview.grow_vertical = Control.GROW_DIRECTION_BOTH
	hud_overview.offset_left = 0
	hud_overview.offset_right = 0
	hud_overview.offset_top = 0
	hud_overview.offset_bottom = 0
	
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


func _get_cached_green_vertices() -> PackedVector3Array:
	var hole_idx = MultiplayerManager.current_hole_index
	if hole_idx != _cached_green_hole_index or _cached_green_verts.is_empty():
		_cached_green_verts = _get_current_green_vertices()
		_cached_green_hole_index = hole_idx
	return _cached_green_verts


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
	elif mode == "Closest to Pin":
		var p_pts = _get_player_points(player)
		name_text += " (%d pts)" % p_pts

	hud_player_name_lbl.text = name_text
	if hud_player_badge != null and hud_player_badge_lbl != null:
		var p_name = player.get("name", "Player")
		var avatar_path = player.get("avatar", "")
		if avatar_path.is_empty():
			avatar_path = MultiplayerManager.get_player_avatar(p_name)
		
		var has_avatar = not avatar_path.is_empty() and ResourceLoader.exists(avatar_path)
		if has_avatar and hud_player_avatar_rect != null:
			hud_player_avatar_rect.texture = load(avatar_path)
			hud_player_avatar_rect.visible = true
			hud_player_badge_lbl.visible = false
			var clear_style = StyleBoxEmpty.new()
			hud_player_badge.add_theme_stylebox_override("panel", clear_style)
		else:
			if hud_player_avatar_rect != null:
				hud_player_avatar_rect.visible = false
			hud_player_badge_lbl.visible = true
			var p_color = MultiplayerManager.get_player_color(player)
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
			hud_player_badge_lbl.text = p_name.substr(0, 1).to_upper()
	
	# 2. Update overall score relative to par, Skins count, or Closest to Pin points
	var overall_score_str = "E"
	if mode == "Skins":
		var p_skins = MultiplayerManager.skins_won.get(player.get("name", ""), 0)
		overall_score_str = "%d S" % p_skins
		if MultiplayerManager.carryover_skins > 0:
			overall_score_str += " (C%d)" % MultiplayerManager.carryover_skins
	elif mode == "Closest to Pin":
		var p_pts = _get_player_points(player)
		overall_score_str = "%d pts" % p_pts
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
	var hole_idx = clamp(MultiplayerManager.current_hole_index, 0, max(0, MultiplayerManager.hole_ids.size() - 1))
	var hole_num = hole_idx + 1
	hud_hole_num_lbl.text = str(hole_num)
	
	# 4. Update shots and current hole par diff
	if MultiplayerManager.hole_ids.is_empty():
		return
	var hole_id = MultiplayerManager.hole_ids[hole_idx]
	var active_hole = MultiplayerManager.hole_info.get(hole_id, {})
	var hole_par = active_hole.get("Par", 4)
	var strokes = player.get("strokes", 0)
	var current_shot = strokes + 1
	
	# Build shots list BBCode
	var shot_bbcodes = []
	if mode == "Closest to Pin":
		if strokes == 0:
			shot_bbcodes.append("[u][b]Shot 1 of 1[/b][/u]")
		else:
			shot_bbcodes.append("[color=#55ff55]Shot Taken[/color]")
	else:
		for i in range(1, hole_par + 1):
			if i == current_shot:
				shot_bbcodes.append("[u][b]%d[/b][/u]" % i)
			else:
				shot_bbcodes.append("[color=#8c939d]%d[/color]" % i)
	var shots_str = "   ".join(shot_bbcodes)
	
	# Current hole par tracker (strokes - par)
	var hole_diff = strokes - hole_par
	var diff_str = ""
	if mode == "Closest to Pin":
		diff_str = "[color=#f0c040]Closest to Pin[/color]"
	elif hole_diff > 0:
		diff_str = "[color=#ff5555]+%d[/color]" % hole_diff
	elif hole_diff < 0:
		diff_str = "[color=#55ff55]%d[/color]" % hole_diff
	else:
		diff_str = "[color=#ffffff]E[/color]"
		
	hud_shots_rtl.text = "%s     ( %s )" % [shots_str, diff_str]


func _on_active_player_changed(player: Dictionary) -> void:
	if player.is_empty() or MultiplayerManager.hole_ids.is_empty():
		return
		
	_clear_map_markers()
		
	var hole_idx = clamp(MultiplayerManager.current_hole_index, 0, MultiplayerManager.hole_ids.size() - 1)
	var hole_id = MultiplayerManager.hole_ids[hole_idx]
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
				course_instance.get_node("PinMarker").visible = true
			
			var flag_pin = course_instance.get_node_or_null("FlagPin")
			if flag_pin != null:
				flag_pin.global_position = course_instance.current_hole_location
				
		# Update tee-off distance
		if player.get("strokes", 0) == 0 and course_instance != null and course_instance.has_method("get_height"):
			var is_driver = MultiplayerManager.current_club.to_lower() in ["dr", "driver", "1w"]
			var offset_y = 0.059435 if is_driver else (GolfBall.GROUND_CENTER_HEIGHT + GolfBall.GROUND_SNAP_OFFSET)
			player["position"].y = course_instance.get_height(player["position"].x, player["position"].z) + offset_y
		var spawn_pos = player["position"]
		course_instance.current_hole_tee_dist_yards = int(spawn_pos.distance_to(course_instance.current_hole_location) * 1.09361)
		
		# Reset camera user offset when moving to a new hole or if starting hole
		if player["strokes"] == 0:
			course_instance.aerial_cam_user_offset = Vector3.ZERO
			reset_zoom_to_default()
		else:
			_last_zoom_zone = -1
			
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
			active_ball.lie_type = player.get("lie_type", "teebox")
			active_ball.reset()
			
			# Recalculate lie immediately after teleporting/resetting
			if course_instance != null and course_instance.has_method("update_current_lie_and_reduction"):
				course_instance.call("update_current_lie_and_reduction")
			var player_node_ref = course_instance.get_node_or_null("Player") if course_instance != null else null
			if player_node_ref != null:
				player_node_ref.current_lie_type = active_ball.lie_type
			
			if course_instance != null and course_instance.has_method("update_auto_club"):
				course_instance.call("update_auto_club", true)
			
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
					course_instance.aim_target_pos = pin_pos
					if course_instance.has_node("AimMarker"):
						course_instance.get_node("AimMarker").global_position = pin_pos
					if course_instance.has_method("set_aim_distance"):
						course_instance.call("set_aim_distance", int(ball_pos.distance_to(pin_pos) * 1.09361))
					
					# Position the camera behind the ball facing the pin
					if camera != null:
						camera.follow_mode = PhantomCamera3D.FollowMode.NONE
						camera.look_at_mode = PhantomCamera3D.LookAtMode.NONE
						var is_on_green = false
						if active_ball != null:
							var lie = str(active_ball.get("lie_type")).to_lower()
							is_on_green = (lie == "green")
							if not is_on_green and course_instance != null and course_instance.has_method("is_ball_on_green"):
								is_on_green = course_instance.call("is_ball_on_green")
						var cam_dist = GlobalSettings.range_settings.camera_distance.value
						var cam_height = GlobalSettings.range_settings.camera_height.value
						var local_offset = Vector3(-1.05, 0.6, 0) if is_on_green else Vector3(-cam_dist, cam_height, 0)
						if course_instance.has_method("get_camera_local_offset"):
							local_offset = course_instance.call("get_camera_local_offset", is_on_green)
						var rotated_offset = local_offset.rotated(Vector3.UP, -angle_rad)
						var cam_pos = ball_pos + rotated_offset
						if course_instance.has_method("clamp_camera_position"):
							cam_pos = course_instance.call("clamp_camera_position", cam_pos)
						camera.global_position = cam_pos
						
						var target_look: Vector3
						if course_instance.has_method("get_camera_target_look"):
							target_look = course_instance.call("get_camera_target_look", pin_pos, ball_pos, is_on_green)
						elif is_on_green:
							var dist = ball_pos.distance_to(pin_pos)
							var look_dist = clamp(dist * 0.4, 2.0, 6.0)
							if dist < 2.0:
								look_dist = dist
							var fraction = clamp(look_dist / max(dist, 0.001), 0.0, 1.0)
							target_look = ball_pos.lerp(pin_pos, fraction)
						else:
							var dist = ball_pos.distance_to(pin_pos)
							if dist < 45.0:
								target_look = pin_pos + Vector3.UP * 0.35
							else:
								var aim_dir = (pin_pos - ball_pos).normalized()
								if aim_dir.is_zero_approx():
									aim_dir = Vector3.RIGHT.rotated(Vector3.UP, deg_to_rad(active_ball.aim_yaw_offset_deg))
								target_look = ball_pos + aim_dir * 50.0 + Vector3.UP * 1.0
						camera.look_at(target_look)
						if camera.camera_3d_resource != null:
							camera.camera_3d_resource.fov = GlobalSettings.range_settings.camera_fov.value
						
						var cam3d = course_instance.get_node_or_null("Camera3D")
						if cam3d != null:
							cam3d.global_position = cam_pos
							cam3d.look_at(target_look)
							cam3d.fov = GlobalSettings.range_settings.camera_fov.value
			
		# Clear tracer trails so the player has a clean view for their next shot
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			player_node.call("reset_shot_data")
			player_node.call("clear_tracers")

		if course_instance != null and course_instance.has_method("update_auto_club"):
			course_instance.call("update_auto_club", true)

	if not player.get("holed_out", false):
		is_player_turn_ready = true




func _on_mulligan_pressed() -> void:
	if forfeit_confirm_dialog != null:
		forfeit_confirm_dialog.visible = false
	if mulligan_confirm_dialog == null:
		return
		
	# Clear existing children of the dialog
	for child in mulligan_confirm_dialog.get_children():
		mulligan_confirm_dialog.remove_child(child)
		child.queue_free()
		
	# Build the dialog content dynamically
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 16)
	
	var target_idx = MultiplayerManager.get_mulligan_target_player_index()
	if target_idx < 0 or target_idx >= MultiplayerManager.players.size():
		return
	var target_player = MultiplayerManager.players[target_idx]
	if target_player.is_empty():
		return
		
	var player_node = course_instance.get_node_or_null("Player") if course_instance != null else null
	var last_start_pos = Vector3.ZERO
	if not MultiplayerManager.last_shot_info.is_empty() and MultiplayerManager.last_shot_info.has("start_pos"):
		last_start_pos = MultiplayerManager.last_shot_info["start_pos"]
	elif target_player.has("last_starting_pos") and typeof(target_player["last_starting_pos"]) == TYPE_VECTOR3 and not target_player["last_starting_pos"].is_zero_approx():
		last_start_pos = target_player["last_starting_pos"]
	elif player_node != null and player_node.get("_last_starting_pos") != null:
		last_start_pos = player_node.get("_last_starting_pos")
		
	var hole_idx = clamp(MultiplayerManager.current_hole_index, 0, MultiplayerManager.hole_ids.size() - 1) if not MultiplayerManager.hole_ids.is_empty() else 0
	var hole_id = MultiplayerManager.hole_ids[hole_idx] if not MultiplayerManager.hole_ids.is_empty() else "Hole 1"
	
	var matching_mulligans = []
	if target_player.has("mulligan_history") and typeof(target_player["mulligan_history"]) == TYPE_DICTIONARY:
		if target_player["mulligan_history"].has(hole_id) and typeof(target_player["mulligan_history"][hole_id]) == TYPE_ARRAY:
			for entry in target_player["mulligan_history"][hole_id]:
				if entry.has("start_pos") and typeof(entry["start_pos"]) == TYPE_VECTOR3:
					# Match starting positions within 0.5 meters
					if entry["start_pos"].distance_to(last_start_pos) < 0.5:
						matching_mulligans.append(entry)
						
	var is_multi = MultiplayerManager.players.size() > 1
	var p_name = target_player.get("name", "Player")

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
	ThemeManager.apply_scroll_container_style(scroll, 28)
	content_vbox.add_child(scroll)
	
	var list_vbox = VBoxContainer.new()
	list_vbox.add_theme_constant_override("separation", 10)
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_vbox)
	
	if matching_mulligans.is_empty():
		# Standard confirmation flow
		title_lbl.text = "Confirm Mulligan" if not is_multi else "Confirm Mulligan: %s" % p_name
		msg_lbl.text = "Are you sure you want to take a mulligan?\nThis will undo your last shot." if not is_multi else "Are you sure you want to take a mulligan for %s?\nThis will undo their last shot." % p_name
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
		title_lbl.text = "Mulligan Selection" if not is_multi else "Mulligan Selection: %s" % p_name
		msg_lbl.text = "Select an option for your mulligan from this spot:" if not is_multi else "Select an option for %s's mulligan from this spot:" % p_name
		
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
	if course_instance != null and course_instance.has_method("cancel_pending_shot_transition"):
		course_instance.call("cancel_pending_shot_transition")

	var player_node = course_instance.get_node_or_null("Player")
	if player_node != null:
		var target_idx = MultiplayerManager.get_mulligan_target_player_index()
		if target_idx < 0 or target_idx >= MultiplayerManager.players.size():
			return
		var target_player = MultiplayerManager.players[target_idx]
		if target_player.is_empty():
			return

		var hole_idx = clamp(MultiplayerManager.current_hole_index, 0, MultiplayerManager.hole_ids.size() - 1) if not MultiplayerManager.hole_ids.is_empty() else 0
		var hole_id = MultiplayerManager.hole_ids[hole_idx] if not MultiplayerManager.hole_ids.is_empty() else "Hole 1"
		
		# Determine starting pos and details of the shot being undone
		var last_start_pos = Vector3.ZERO
		var current_ball_pos = target_player.get("position", Vector3.ZERO)
		var last_aim_target = Vector3.ZERO
		var last_aim_yaw = 0.0
		var shot_club = MultiplayerManager.current_club
		var shot_lie = target_player.get("lie_type", "fairway")
		var shot_reduction = target_player.get("shot_reduction", 0.0)
		var shot_penalty = target_player.get("last_shot_penalty", 0)
		var tracer_pts = []
		var current_stats = {}

		if not MultiplayerManager.last_shot_info.is_empty() and MultiplayerManager.last_shot_info.get("player_index", -1) == target_idx:
			var info = MultiplayerManager.last_shot_info
			last_start_pos = info.get("start_pos", Vector3.ZERO)
			current_ball_pos = info.get("end_pos", current_ball_pos)
			last_aim_target = info.get("aim_target_pos", Vector3.ZERO)
			last_aim_yaw = info.get("aim_yaw_offset_deg", 0.0)
			shot_club = info.get("club", shot_club)
			shot_lie = info.get("lie_type", shot_lie)
			shot_reduction = info.get("shot_reduction", shot_reduction)
			shot_penalty = info.get("last_shot_penalty", shot_penalty)
			tracer_pts = info.get("tracer_points", [])
			current_stats = info.get("stat_entry", {})
		else:
			if target_player.has("last_starting_pos") and typeof(target_player["last_starting_pos"]) == TYPE_VECTOR3 and not target_player["last_starting_pos"].is_zero_approx():
				last_start_pos = target_player["last_starting_pos"]
			elif player_node.get("_last_starting_pos") != null:
				last_start_pos = player_node.get("_last_starting_pos")
			last_aim_target = target_player.get("last_aim_target_pos", Vector3.ZERO)
			last_aim_yaw = target_player.get("last_aim_yaw_offset_deg", 0.0)
			if target_player.has("shot_stats") and typeof(target_player["shot_stats"]) == TYPE_DICTIONARY and target_player["shot_stats"].has(hole_id) and not target_player["shot_stats"][hole_id].is_empty():
				current_stats = target_player["shot_stats"][hole_id].back()
			var tracers_list = player_node.get("tracers")
			if tracers_list != null and not tracers_list.is_empty():
				var last_t = tracers_list.back()
				if is_instance_valid(last_t) and "points" in last_t:
					tracer_pts = last_t.points.duplicate()
			
		var course_shot_data = {}
		if course_instance != null and "shot_history" in course_instance and not course_instance.shot_history.is_empty():
			course_shot_data = course_instance.shot_history.back()
			
		var shot_entry = {
			"start_pos": last_start_pos,
			"end_pos": current_ball_pos,
			"club": shot_club,
			"lie_type": shot_lie,
			"shot_reduction": shot_reduction,
			"last_shot_penalty": shot_penalty,
			"shot_stats": current_stats,
			"course_shot_data": course_shot_data,
			"tracer_points": tracer_pts,
			"aim_target_pos": last_aim_target,
			"aim_yaw_offset_deg": last_aim_yaw
		}
		
		if not target_player.has("mulligan_history") or typeof(target_player["mulligan_history"]) != TYPE_DICTIONARY:
			target_player["mulligan_history"] = {}
		if not target_player["mulligan_history"].has(hole_id):
			target_player["mulligan_history"][hole_id] = []
		target_player["mulligan_history"][hole_id].append(shot_entry)
		
		# Reset detailed tracer points for target shot since we just mulliganed it
		target_player["last_shot_tracer_points"] = []
		
		player_node.call("mulligan")
		player_node.set("_last_starting_pos", last_start_pos)
		
		if range_ui != null and range_ui.has_method("on_next_shot_started"):
			range_ui.call("on_next_shot_started")
		if course_instance.has_method("remove_last_shot"):
			course_instance.call("remove_last_shot")
		
		# Update target player data in MultiplayerManager
		target_player["position"] = last_start_pos
		var penalty = shot_penalty
		var strokes_to_remove = 1 + penalty
		target_player["strokes"] = max(0, target_player["strokes"] - strokes_to_remove)
		target_player["total_strokes"] = max(0, target_player["total_strokes"] - strokes_to_remove)
		target_player["last_shot_penalty"] = 0
		target_player["last_shot_distance_yards"] = -1.0
		target_player["holed_out"] = false
		if not target_player["shot_history"].is_empty():
			target_player["shot_history"].pop_back()
			
		if not MultiplayerManager.hole_ids.is_empty():
			target_player["hole_scores"][hole_id] = target_player["strokes"]
			if target_player.has("shot_stats"):
				if typeof(target_player["shot_stats"]) == TYPE_DICTIONARY:
					if target_player["shot_stats"].has(hole_id) and not target_player["shot_stats"][hole_id].is_empty():
						target_player["shot_stats"][hole_id].pop_back()
				elif typeof(target_player["shot_stats"]) == TYPE_ARRAY and not target_player["shot_stats"].is_empty():
					target_player["shot_stats"].pop_back()
			
		# Clear last shot tracking now that it has been mulliganed
		MultiplayerManager.clear_last_shot()

		# Revert active player turn to target player so they can take their redo
		MultiplayerManager.active_player_index = target_idx
		MultiplayerManager.emit_signal("active_player_changed", target_player)

		if course_instance != null and course_instance.has_method("update_current_lie_and_reduction"):
			course_instance.call("update_current_lie_and_reduction")
			
		# Retain previous shot's aim target and camera look
		if last_aim_target != null and last_aim_target != Vector3.ZERO:
			if course_instance != null and course_instance.has_method("set_aim_target"):
				course_instance.call("set_aim_target", last_aim_target, true)
			if player_node != null:
				player_node.set("_last_aim_target_pos", last_aim_target)
				player_node.set("_last_aim_yaw_offset_deg", last_aim_yaw)
			target_player["last_aim_target_pos"] = last_aim_target
			target_player["last_aim_yaw_offset_deg"] = last_aim_yaw
			
		MultiplayerManager.save_current_match()


func _on_previous_mulligan_selected(prev_shot: Dictionary) -> void:
	if course_instance != null and course_instance.has_method("cancel_pending_shot_transition"):
		course_instance.call("cancel_pending_shot_transition")

	var player_node = course_instance.get_node_or_null("Player")
	if player_node != null:
		var target_idx = MultiplayerManager.get_mulligan_target_player_index()
		if target_idx < 0 or target_idx >= MultiplayerManager.players.size():
			return
		var target_player = MultiplayerManager.players[target_idx]
		if target_player.is_empty():
			return
		var hole_idx = clamp(MultiplayerManager.current_hole_index, 0, MultiplayerManager.hole_ids.size() - 1) if not MultiplayerManager.hole_ids.is_empty() else 0
		var hole_id = MultiplayerManager.hole_ids[hole_idx] if not MultiplayerManager.hole_ids.is_empty() else "Hole 1"
		
		# 1. Capture current shot and put it in mulligan history
		var last_start_pos = player_node.get("_last_starting_pos")
		var current_ball_pos = target_player.get("position", Vector3.ZERO)
		var last_aim_target = player_node.get("_last_aim_target_pos")
		if last_aim_target == null or last_aim_target == Vector3.ZERO:
			if target_player.has("last_aim_target_pos") and typeof(target_player["last_aim_target_pos"]) == TYPE_VECTOR3:
				last_aim_target = target_player["last_aim_target_pos"]
			elif course_instance != null and "aim_target_pos" in course_instance:
				last_aim_target = course_instance.aim_target_pos
		var last_aim_yaw = player_node.get("_last_aim_yaw_offset_deg")
		if last_aim_yaw == null:
			last_aim_yaw = target_player.get("last_aim_yaw_offset_deg", 0.0)
			
		var current_stats = {}
		if target_player.has("shot_stats") and typeof(target_player["shot_stats"]) == TYPE_DICTIONARY and target_player["shot_stats"].has(hole_id) and not target_player["shot_stats"][hole_id].is_empty():
			current_stats = target_player["shot_stats"][hole_id].back()
			
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
			"lie_type": target_player.get("lie_type", "fairway"),
			"shot_reduction": target_player.get("shot_reduction", 0.0),
			"last_shot_penalty": target_player.get("last_shot_penalty", 0),
			"shot_stats": current_stats,
			"course_shot_data": course_shot_data,
			"tracer_points": tracer_pts,
			"aim_target_pos": last_aim_target,
			"aim_yaw_offset_deg": last_aim_yaw
		}
		
		if not target_player.has("mulligan_history") or typeof(target_player["mulligan_history"]) != TYPE_DICTIONARY:
			target_player["mulligan_history"] = {}
		if not target_player["mulligan_history"].has(hole_id):
			target_player["mulligan_history"][hole_id] = []
		target_player["mulligan_history"][hole_id].append(current_shot_entry)
		
		# Remove the selected previous shot from mulligan history
		var hist_list = target_player["mulligan_history"][hole_id]
		hist_list.erase(prev_shot)
		
		# 2. Undo current shot
		player_node.call("mulligan")
		if course_instance.has_method("remove_last_shot"):
			course_instance.call("remove_last_shot")
			
		var penalty = target_player.get("last_shot_penalty", 0)
		var strokes_to_remove = 1 + penalty
		target_player["strokes"] = max(0, target_player["strokes"] - strokes_to_remove)
		target_player["total_strokes"] = max(0, target_player["total_strokes"] - strokes_to_remove)
		target_player["last_shot_penalty"] = 0
		if not target_player["shot_history"].is_empty():
			target_player["shot_history"].pop_back()
		if target_player.has("shot_stats") and typeof(target_player["shot_stats"]) == TYPE_DICTIONARY:
			if target_player["shot_stats"].has(hole_id) and not target_player["shot_stats"][hole_id].is_empty():
				target_player["shot_stats"][hole_id].pop_back()
		
		# 3. Apply the selected previous shot
		var prev_penalty = prev_shot.get("last_shot_penalty", 0)
		var strokes_to_add = 1 + prev_penalty
		target_player["strokes"] += strokes_to_add
		target_player["total_strokes"] += strokes_to_add
		target_player["last_shot_penalty"] = prev_penalty
		target_player["last_shot_distance_yards"] = -1.0
		
		target_player["position"] = prev_shot["end_pos"]
		target_player["shot_history"].append(prev_shot["end_pos"])
		
		if not target_player.has("shot_stats"):
			target_player["shot_stats"] = {}
		if not target_player["shot_stats"].has(hole_id):
			target_player["shot_stats"][hole_id] = []
		target_player["shot_stats"][hole_id].append(prev_shot["shot_stats"])
		
		target_player["lie_type"] = prev_shot.get("lie_type", "fairway")
		target_player["shot_reduction"] = prev_shot.get("shot_reduction", 0.0)
		
		# Restore detailed tracer points
		target_player["last_shot_tracer_points"] = prev_shot.get("tracer_points", []).duplicate()
		
		if not MultiplayerManager.hole_ids.is_empty():
			target_player["hole_scores"][hole_id] = target_player["strokes"]
			
		# Teleport player and ball
		player_node.set("_last_starting_pos", prev_shot["start_pos"])
		var ball = player_node.get("ball")
		if ball != null:
			ball.global_position = prev_shot["end_pos"]
			ball.spawn_position = prev_shot["end_pos"]
			ball.reset()
			
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
				
		MultiplayerManager.clear_last_shot()
		MultiplayerManager.active_player_index = target_idx
		MultiplayerManager.emit_signal("active_player_changed", target_player)
		MultiplayerManager.save_current_match()


func _on_forfeit_pressed() -> void:
	if mulligan_confirm_dialog != null:
		mulligan_confirm_dialog.visible = false
	if exit_confirm_dialog != null:
		exit_confirm_dialog.visible = false
	if forfeit_confirm_dialog == null:
		return
		
	# Clear existing children of the dialog
	for child in forfeit_confirm_dialog.get_children():
		forfeit_confirm_dialog.remove_child(child)
		child.queue_free()
		
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 16)
	
	var active_p = MultiplayerManager.get_active_player()
	if active_p.is_empty():
		return
		
	var p_name = active_p.get("name", "Player")
	var strokes = active_p.get("strokes", 0)
	var is_multi = MultiplayerManager.players.size() > 1
	
	var title_lbl = Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", Color(0.92, 0.35, 0.35, 1.0))
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 4)
	title_lbl.text = "Concede Hole? 🏳️" if not is_multi else "Concede Hole: %s 🏳️" % p_name
	content_vbox.add_child(title_lbl)
	
	var msg_lbl = Label.new()
	msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_lbl.add_theme_font_size_override("font_size", 16)
	msg_lbl.add_theme_color_override("font_color", Color.WHITE)
	msg_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	msg_lbl.add_theme_constant_override("outline_size", 4)
	if not is_multi:
		msg_lbl.text = "Count this hole as in at %d strokes?\nYou will not need to hit on this hole anymore." % strokes
	else:
		msg_lbl.text = "Count this hole as in for %s at %d strokes?\nThey will not need to hit on this hole anymore." % [p_name, strokes]
	content_vbox.add_child(msg_lbl)
	
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 24)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	
	var confirm_btn = Button.new()
	confirm_btn.text = "Yes, Concede Hole"
	confirm_btn.custom_minimum_size = Vector2(160, 45)
	apply_material_button_style(confirm_btn, Color(0.68, 0.22, 0.22, 0.85))
	confirm_btn.pressed.connect(func():
		forfeit_confirm_dialog.visible = false
		_on_forfeit_confirmed()
	)
	btn_hbox.add_child(confirm_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 45)
	apply_material_button_style(cancel_btn, Color(0.35, 0.35, 0.38, 0.85))
	cancel_btn.pressed.connect(func():
		forfeit_confirm_dialog.visible = false
	)
	btn_hbox.add_child(cancel_btn)
	
	content_vbox.add_child(btn_hbox)
	forfeit_confirm_dialog.add_child(content_vbox)
	forfeit_confirm_dialog.visible = true


func _on_forfeit_confirmed() -> void:
	if course_instance != null and course_instance.has_method("cancel_pending_shot_transition"):
		course_instance.call("cancel_pending_shot_transition")
	MultiplayerManager.concede_hole()


func _on_gimme_awarded(player: Dictionary, extra_strokes: int) -> void:
	is_player_turn_ready = false
	if gimme_banner == null or gimme_title_lbl == null:
		return
		
	var p_name = player.get("name", "Player")
	gimme_title_lbl.text = "GIMME +%d" % extra_strokes
	if gimme_sub_lbl != null:
		var hole_idx = clamp(MultiplayerManager.current_hole_index, 0, max(0, MultiplayerManager.hole_ids.size() - 1))
		var hole_id = MultiplayerManager.hole_ids[hole_idx] if not MultiplayerManager.hole_ids.is_empty() else ""
		var current_hole = MultiplayerManager.hole_info.get(hole_id, {})
		var par = current_hole.get("Par", 4)
		var strokes = player.get("strokes", 0)
		var hole_diff = strokes - par
		var diff_text = "E"
		if hole_diff > 0:
			diff_text = "+%d" % hole_diff
		elif hole_diff < 0:
			diff_text = "%d" % hole_diff
		gimme_sub_lbl.text = "%s  •  Hole Score: %d (%s)" % [p_name, strokes, diff_text]
		
	if _gimme_tween != null and _gimme_tween.is_valid():
		_gimme_tween.kill()
		
	gimme_banner.visible = true
	gimme_banner.modulate = Color(1, 1, 1, 0)
	gimme_banner.pivot_offset = gimme_banner.size / 2.0
	gimme_banner.scale = Vector2(0.85, 0.85)
	
	_gimme_tween = create_tween()
	_gimme_tween.set_parallel(true)
	_gimme_tween.tween_property(gimme_banner, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_gimme_tween.tween_property(gimme_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Stay for 2 seconds, then smoothly fade out
	_gimme_tween.chain().tween_interval(2.0)
	_gimme_tween.chain().tween_property(gimme_banner, "modulate:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_gimme_tween.tween_callback(func():
		if is_instance_valid(gimme_banner):
			gimme_banner.visible = false
	)


func _on_hole_completed(scores: Array) -> void:
	is_player_turn_ready = false
	reset_zoom_to_default()
	_populate_scorecard("hole_completed")
	hud_scorecard.visible = true
	_set_other_elements_visible(false)


func _on_game_over(scores: Array) -> void:
	is_player_turn_ready = false
	reset_zoom_to_default()
	MultiplayerManager.is_finished = true
	MultiplayerManager.save_current_match()
	_populate_overview()
	hud_overview.visible = true
	_set_other_elements_visible(false)
	GlobalSettings.play_golf_clap()


func _process(_delta: float) -> void:
	# Scorecard countdown handling
	if _scorecard_countdown_active and hud_scorecard.visible:
		if not _scorecard_countdown_paused:
			_scorecard_countdown_time_left -= _delta
			if _scorecard_countdown_time_left <= 0.0:
				_scorecard_countdown_time_left = 0.0
				_on_scorecard_advance()
			else:
				_update_scorecard_countdown_display()
	elif _scorecard_countdown_active and not hud_scorecard.visible:
		_stop_scorecard_countdown()

	var ball = active_ball
	if ball == null and course_instance != null:
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			ball = player_node.get("ball")
			active_ball = ball

	var ball_is_moving: bool = (ball != null and ball.state != PhysicsEnums.BallState.REST)
	if ball_is_moving != _prev_ball_moving:
		_prev_ball_moving = ball_is_moving
		_minimap_zoom_dirty = true

	if mulligan_btn != null and mulligan_btn.visible:
		var can_mull = MultiplayerManager.can_mulligan() and not ball_is_moving and not hud_scorecard.visible and not hud_overview.visible
		mulligan_btn.disabled = not can_mull

	if forfeit_btn != null:
		var is_match_play = not MultiplayerManager.players.is_empty() and not MultiplayerManager.practice_mode_active
		var active_p = MultiplayerManager.get_active_player()
		var p_strokes = active_p.get("strokes", 0) if not active_p.is_empty() else 0
		var p_holed = active_p.get("holed_out", false) if not active_p.is_empty() else true
		var should_show_forfeit = _hud_elements_visible and is_match_play and p_strokes >= 10 and not p_holed
		forfeit_btn.visible = should_show_forfeit
		if should_show_forfeit:
			forfeit_btn.disabled = ball_is_moving or hud_scorecard.visible or hud_overview.visible or (hud_manage_players != null and hud_manage_players.visible)

	if ball_is_moving:
		if forfeit_confirm_dialog != null and forfeit_confirm_dialog.visible:
			forfeit_confirm_dialog.visible = false

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
		if not ball_is_moving or Engine.get_process_frames() % 3 == 0:
			_overlay_node.queue_redraw()
		
	if not ball_is_moving and MultiplayerManager.players.size() > 1 and not MultiplayerManager.is_finished:
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
	elif not ball_is_moving:
		_clear_map_markers()


func is_player_in_teebox() -> bool:
	if course_instance != null and course_instance.has_method("is_ball_in_teebox"):
		return course_instance.call("is_ball_in_teebox")
	var ball = active_ball
	if ball == null and course_instance != null:
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			ball = player_node.get("ball")
	if ball != null:
		var lie_str = str(ball.get("lie_type")).to_lower()
		if lie_str == "teebox":
			return true
	if has_node("/root/MultiplayerManager"):
		var mp_mgr = get_node("/root/MultiplayerManager")
		if not mp_mgr.players.is_empty():
			var ap = mp_mgr.get_active_player()
			if ap.get("lie_type", "").to_lower() == "teebox":
				return true
			if ap.get("strokes", 0) == 0:
				return true
	return false


func is_player_close_to_green() -> bool:
	if course_instance != null and course_instance.has_method("is_ball_close_to_green"):
		return course_instance.call("is_ball_close_to_green")
	var ball = active_ball
	if ball == null and course_instance != null:
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			ball = player_node.get("ball")
	if ball != null:
		var lie_str = str(ball.get("lie_type")).to_lower()
		var club_str = str(ball.get("current_selected_club")).to_lower()
		if lie_str == "green" or lie_str == "fringe" or club_str in ["pt", "putt", "putter"]:
			return true
		if course_instance != null:
			var pin_pos = course_instance.get("current_hole_location")
			if pin_pos != null and not pin_pos.is_zero_approx():
				if ball.global_position.distance_to(pin_pos) <= 45.0:
					return true
	if has_node("/root/MultiplayerManager"):
		var mp_mgr = get_node("/root/MultiplayerManager")
		if not mp_mgr.players.is_empty():
			var ap = mp_mgr.get_active_player()
			if ap.get("lie_type", "").to_lower() in ["green", "fringe"] or mp_mgr.current_club.to_lower() in ["pt", "putt", "putter"]:
				return true
	return false


func get_current_zoom_zone() -> int:
	if is_player_in_teebox():
		return 0 # TEE_BOX
	elif is_player_close_to_green():
		return 2 # GREEN
	else:
		return 1 # MIDWAY


func get_zoom_for_zone(zone: int) -> float:
	var green_zoom = 50.0
	if course_instance != null and course_instance.has_method("get_green_zoom_size"):
		green_zoom = course_instance.get_green_zoom_size()
	var tee_zoom = _teebox_minimap_zoom
	match zone:
		0: # TEE_BOX
			return tee_zoom
		1: # MIDWAY (half way between tee box zoom and green zoom)
			return (tee_zoom + green_zoom) * 0.5
		2: # GREEN
			return green_zoom
		_:
			return tee_zoom


func reset_zoom_to_default() -> void:
	minimap_zoom = 300.0
	_teebox_minimap_zoom = 300.0
	_default_non_green_minimap_zoom = 300.0
	_last_zoom_zone = -1
	_last_was_on_green = false
	if _minimap_camera != null:
		_minimap_camera.size = minimap_zoom
	if course_instance != null:
		if course_instance.has_method("reset_zoom_to_default"):
			course_instance.reset_zoom_to_default()
		else:
			if "aerial_zoom" in course_instance:
				course_instance.aerial_zoom = 300.0
			if "_default_non_green_aerial_zoom" in course_instance:
				course_instance._default_non_green_aerial_zoom = 300.0
			if "_last_was_on_green" in course_instance:
				course_instance._last_was_on_green = false
			if "_last_zoom_zone" in course_instance:
				course_instance._last_zoom_zone = -1
			if "show_green_grid" in course_instance:
				course_instance.show_green_grid = false
			var aerial_cam = course_instance.get_node_or_null("AerialCamera")
			if aerial_cam != null:
				aerial_cam.size = 300.0


func _update_minimap() -> void:
	if _minimap_camera == null or course_instance == null or _minimap_panel == null:
		return
		
	# Check if scorecard or players HUD is open
	if hud_scorecard.visible or hud_manage_players.visible or hud_overview.visible:
		if _minimap_group != null:
			_minimap_group.visible = false
		if _minimap_viewport != null and _minimap_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_minimap_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _minimap_flag_icon != null:
			_minimap_flag_icon.visible = false
		if _minimap_ball_icon != null:
			_minimap_ball_icon.visible = false
		return
		
	# Check if the course is in full-screen aerial view
	var is_aerial = course_instance.get("is_aerial_view") as bool if course_instance.get("is_aerial_view") != null else false
	
	# The box shouldn't show at all when the full-screen aerial view is active
	if _minimap_group != null:
		_minimap_group.visible = not is_aerial
		
	var ball = active_ball
	if ball == null:
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			ball = player_node.get("ball")
			
	if ball == null:
		if _minimap_flag_icon != null:
			_minimap_flag_icon.visible = false
		if _minimap_ball_icon != null:
			_minimap_ball_icon.visible = false
		return

	# Pause minimap SubViewport rendering and calculations during active ball flight to prevent double 3D rendering pass
	if ball.state != PhysicsEnums.BallState.REST:
		if _minimap_viewport != null and _minimap_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_minimap_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _minimap_flag_icon != null:
			_minimap_flag_icon.visible = false
		if _minimap_ball_icon != null:
			_minimap_ball_icon.visible = false
		return

	if _minimap_viewport != null and _minimap_viewport.render_target_update_mode != SubViewport.UPDATE_ALWAYS:
		_minimap_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		
	# Check for shot zoom zone transition (Tee box vs Midway vs Green) only when dirty
	if _minimap_zoom_dirty:
		_minimap_zoom_dirty = false
		var current_zone = get_current_zoom_zone()
		if current_zone != _last_zoom_zone:
			var target_zoom = get_zoom_for_zone(current_zone)
			minimap_zoom = target_zoom
			if course_instance != null and "aerial_zoom" in course_instance:
				course_instance.aerial_zoom = target_zoom
				var aerial_cam = course_instance.get_node_or_null("AerialCamera")
				if aerial_cam != null:
					aerial_cam.size = target_zoom
			
			# Auto-toggle green slope grid when on or close to green
			if course_instance != null and course_instance.get("show_green_grid") != null:
				course_instance.set("show_green_grid", current_zone == 2)
				
			_last_zoom_zone = current_zone
			_last_was_on_green = (current_zone == 2)
	
	if is_aerial:
		if _minimap_flag_icon != null:
			_minimap_flag_icon.visible = false
		if _minimap_ball_icon != null:
			_minimap_ball_icon.visible = false
		return # No need to calculate minimap camera position or distance tracker if hidden
		
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

	# --- Update Flag and Ball Icons on Minimap (when on green and putting / heatmap active) ---
	_update_minimap_flag_marker(pin_pos, _last_zoom_zone, ball)
	_update_minimap_ball_marker(ball_pos, _last_zoom_zone, ball)

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
			var global_verts = _get_cached_green_vertices()
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
			
			# Check if putting / on the green
			var is_on_green = false
			if ball != null:
				var lie = str(ball.get("lie_type")).to_lower()
				is_on_green = (lie == "green")
			if not is_on_green and course_instance != null and course_instance.has_method("is_ball_on_green"):
				is_on_green = course_instance.call("is_ball_on_green")
			if not is_on_green and MultiplayerManager.players.size() > 0:
				var ap = MultiplayerManager.get_active_player()
				if ap.get("lie_type", "").to_lower() == "green":
					is_on_green = true

			if is_on_green:
				# Display as feet when putting on the green
				var dist_back_ft = int(round(max_proj_dist * 3.28084))
				var dist_hole_ft = int(round(dist_hole * 3.28084))
				var dist_front_ft = int(round(min_proj_dist * 3.28084))
				
				if dist_front_ft < 0:
					dist_front_ft = 0
					
				_back_lbl.text = str(dist_back_ft)
				_hole_lbl.text = str(dist_hole_ft)
				_front_lbl.text = str(dist_front_ft)
				if _distance_unit_lbl != null:
					_distance_unit_lbl.text = "FT"
			else:
				# Display as yards when off the green
				var dist_back_yds = int(max_proj_dist * 1.09361)
				var dist_hole_yds = int(dist_hole * 1.09361)
				var dist_front_yds = int(min_proj_dist * 1.09361)
				
				# Clamp front distance to be at least 0
				if dist_front_yds < 0:
					dist_front_yds = 0
					
				_back_lbl.text = str(dist_back_yds)
				_hole_lbl.text = str(dist_hole_yds)
				_front_lbl.text = str(dist_front_yds)
				if _distance_unit_lbl != null:
					_distance_unit_lbl.text = "YDS"
		else:
			_back_lbl.text = "---"
			_hole_lbl.text = "---"
			_front_lbl.text = "---"
			if _distance_unit_lbl != null:
				_distance_unit_lbl.text = ""


const MINIMAP_FLAG_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 36" width="32" height="36">
  <!-- Hole / Cup base ellipse on green surface -->
  <ellipse cx="8" cy="32" rx="5.5" ry="2.5" fill="#111111" stroke="#FFFFFF" stroke-width="1.5"/>
  <!-- Flagpole black outline -->
  <line x1="8" y1="3" x2="8" y2="32" stroke="#000000" stroke-width="3" stroke-linecap="round"/>
  <!-- Flagpole silver/white body -->
  <line x1="8" y1="3" x2="8" y2="32" stroke="#EEEEEE" stroke-width="1.8" stroke-linecap="round"/>
  <!-- Gold finial ball on top -->
  <circle cx="8" cy="3" r="2.2" fill="#FFCA28" stroke="#000000" stroke-width="1"/>
  <!-- Flag black outer border for high contrast -->
  <polygon points="8,3.5 28.5,10.5 8,17.5" fill="#000000"/>
  <!-- Flag white inner border for contrast against red/dark heatmap zones -->
  <polygon points="8,4.5 26.5,10.5 8,16.5" fill="#FFFFFF"/>
  <!-- Vibrant solid red golf flag -->
  <polygon points="8.5,5.8 24.5,10.5 8.5,15.2" fill="#D32F2F"/>
</svg>"""

func _get_minimap_flag_texture() -> Texture2D:
	if ResourceLoader.exists("res://assets/images/icons/golf_pin_flag.svg"):
		var tex = load("res://assets/images/icons/golf_pin_flag.svg")
		if tex != null:
			return tex
	var img = Image.new()
	var err = img.load_svg_from_file("res://assets/images/icons/golf_pin_flag.svg", 2.0)
	if err == OK:
		return ImageTexture.create_from_image(img)
	err = img.load_svg_from_string(MINIMAP_FLAG_SVG, 2.0)
	if err == OK:
		return ImageTexture.create_from_image(img)
	return null

func _update_minimap_flag_marker(pin_pos: Variant, current_zone: int, ball: Node) -> void:
	if _minimap_flag_icon == null or _minimap_camera == null:
		return
		
	if pin_pos == null or (pin_pos is Vector3 and pin_pos.is_zero_approx()):
		_minimap_flag_icon.visible = false
		return
		
	# Check if player is on the green or putting (or green heatmap is active)
	var is_on_green_or_putting = (current_zone == 2)
	if not is_on_green_or_putting and course_instance != null and course_instance.has_method("is_ball_on_green"):
		is_on_green_or_putting = bool(course_instance.call("is_ball_on_green"))
	if not is_on_green_or_putting and ball != null:
		var lie_str = str(ball.get("lie_type")).to_lower()
		var club_str = str(ball.get("current_selected_club")).to_lower()
		if lie_str in ["green", "fringe"] or club_str in ["pt", "putt", "putter"] or ball.get("is_putt") == true:
			is_on_green_or_putting = true
	if not is_on_green_or_putting and has_node("/root/MultiplayerManager"):
		var mp_mgr = get_node("/root/MultiplayerManager")
		if not mp_mgr.players.is_empty():
			var ap = mp_mgr.get_active_player()
			if ap.get("lie_type", "").to_lower() in ["green", "fringe"] or mp_mgr.current_club.to_lower() in ["pt", "putt", "putter"]:
				is_on_green_or_putting = true
				
	# If green heatmap is actively shown, treat as green/putting view
	if not is_on_green_or_putting and course_instance != null and course_instance.get("show_green_grid") == true:
		is_on_green_or_putting = true

	if not is_on_green_or_putting:
		_minimap_flag_icon.visible = false
		return

	# Check if pin position is behind the camera
	if _minimap_camera.is_position_behind(pin_pos):
		_minimap_flag_icon.visible = false
		return
		
	var screen_pos = _minimap_camera.unproject_position(pin_pos)
	# Viewport is 180x180; check if within minimap bounds
	if screen_pos.x >= -12 and screen_pos.x <= 192 and screen_pos.y >= -12 and screen_pos.y <= 192:
		# Anchor at cup ellipse center (8, 32) so cup is on pin location and flag flies above it
		_minimap_flag_icon.position = screen_pos - Vector2(8, 32)
		_minimap_flag_icon.visible = true
	else:
		_minimap_flag_icon.visible = false


const MINIMAP_BALL_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">
  <!-- Soft drop shadow -->
  <circle cx="12" cy="12.5" r="11" fill="#000000" opacity="0.45"/>
  <!-- High contrast dark outer rim -->
  <circle cx="12" cy="12" r="10.5" fill="#FFFFFF" stroke="#111111" stroke-width="1.4"/>
  <!-- 3D shaded golf ball surface -->
  <circle cx="12" cy="12" r="9.5" fill="#F8FAFC"/>
  <!-- Shadow crescent on bottom-right -->
  <path d="M 12 2.5 A 9.5 9.5 0 0 1 21.5 12 A 9.5 9.5 0 0 1 12 21.5 A 9.5 9.5 0 0 0 12 2.5" fill="#B0BEC5" opacity="0.4"/>
  <!-- Soft specular highlight on top-left -->
  <circle cx="9" cy="8.5" r="4.5" fill="#FFFFFF" opacity="0.85"/>
  <!-- Dimple pattern -->
  <g fill="#90A4AE" opacity="0.75">
    <circle cx="12" cy="12" r="1.1"/>
    <circle cx="8.5" cy="11" r="0.95"/>
    <circle cx="15.5" cy="11" r="0.95"/>
    <circle cx="10.5" cy="7.8" r="0.9"/>
    <circle cx="13.5" cy="7.8" r="0.9"/>
    <circle cx="10.5" cy="15.2" r="0.9"/>
    <circle cx="13.5" cy="15.2" r="0.9"/>
    <circle cx="6.5" cy="12" r="0.85"/>
    <circle cx="17.5" cy="12" r="0.85"/>
    <circle cx="12" cy="5.8" r="0.85"/>
    <circle cx="12" cy="17.8" r="0.85"/>
    <circle cx="7.8" cy="8" r="0.8"/>
    <circle cx="16.2" cy="8" r="0.8"/>
    <circle cx="7.8" cy="15" r="0.8"/>
    <circle cx="16.2" cy="15" r="0.8"/>
  </g>
</svg>"""

func _get_minimap_ball_texture() -> Texture2D:
	if ResourceLoader.exists("res://assets/images/icons/golf_ball_icon.svg"):
		var tex = load("res://assets/images/icons/golf_ball_icon.svg")
		if tex != null:
			return tex
	var img = Image.new()
	var err = img.load_svg_from_file("res://assets/images/icons/golf_ball_icon.svg", 2.0)
	if err == OK:
		return ImageTexture.create_from_image(img)
	err = img.load_svg_from_string(MINIMAP_BALL_SVG, 2.0)
	if err == OK:
		return ImageTexture.create_from_image(img)
	return null

func _update_minimap_ball_marker(ball_pos: Vector3, current_zone: int, ball: Node) -> void:
	if _minimap_ball_icon == null or _minimap_camera == null:
		return
		
	if ball == null or ball_pos.is_zero_approx():
		_minimap_ball_icon.visible = false
		return
		
	# Check if player is on the green or putting (or green heatmap is active)
	var is_on_green_or_putting = (current_zone == 2)
	if not is_on_green_or_putting and course_instance != null and course_instance.has_method("is_ball_on_green"):
		is_on_green_or_putting = bool(course_instance.call("is_ball_on_green"))
	if not is_on_green_or_putting and ball != null:
		var lie_str = str(ball.get("lie_type")).to_lower()
		var club_str = str(ball.get("current_selected_club")).to_lower()
		if lie_str in ["green", "fringe"] or club_str in ["pt", "putt", "putter"] or ball.get("is_putt") == true:
			is_on_green_or_putting = true
	if not is_on_green_or_putting and has_node("/root/MultiplayerManager"):
		var mp_mgr = get_node("/root/MultiplayerManager")
		if not mp_mgr.players.is_empty():
			var ap = mp_mgr.get_active_player()
			if ap.get("lie_type", "").to_lower() in ["green", "fringe"] or mp_mgr.current_club.to_lower() in ["pt", "putt", "putter"]:
				is_on_green_or_putting = true
				
	# If green heatmap is actively shown, treat as green/putting view
	if not is_on_green_or_putting and course_instance != null and course_instance.get("show_green_grid") == true:
		is_on_green_or_putting = true

	# Show on green/putting, or in single player / practice mode so ball position is always clearly visible on minimap
	var should_show_ball = is_on_green_or_putting or (MultiplayerManager.players.size() <= 1)
	if not should_show_ball:
		_minimap_ball_icon.visible = false
		return

	# Check if ball position is behind the camera
	if _minimap_camera.is_position_behind(ball_pos):
		_minimap_ball_icon.visible = false
		return
		
	var screen_pos = _minimap_camera.unproject_position(ball_pos)
	# Viewport is 180x180; check if within minimap bounds
	if screen_pos.x >= -12 and screen_pos.x <= 192 and screen_pos.y >= -12 and screen_pos.y <= 192:
		# Anchor at center (12, 12) for 24x24 icon so ball icon is centered at ball position
		_minimap_ball_icon.position = screen_pos - Vector2(12, 12)
		_minimap_ball_icon.visible = true
	else:
		_minimap_ball_icon.visible = false


func apply_material_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 20 # Pill style
	style_normal.corner_radius_top_right = 20
	style_normal.corner_radius_bottom_left = 20
	style_normal.corner_radius_bottom_right = 20
	style_normal.content_margin_left = 18
	style_normal.content_margin_right = 18
	style_normal.content_margin_top = 12
	style_normal.content_margin_bottom = 12

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
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", 16)
	if btn.custom_minimum_size.y < 48:
		btn.custom_minimum_size.y = 48


func apply_circular_button_style(btn: Button, bg_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.corner_radius_top_left = 32 # Half of 64 height
	style_normal.corner_radius_top_right = 32
	style_normal.corner_radius_bottom_left = 32
	style_normal.corner_radius_bottom_right = 32
	style_normal.content_margin_left = 10
	style_normal.content_margin_right = 10
	style_normal.content_margin_top = 10
	style_normal.content_margin_bottom = 10

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = bg_color.lightened(0.15)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = bg_color.darkened(0.15)

	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.2, 0.2, 0.2, 0.4)

	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("disabled", style_disabled)


func update_map_button_text(is_aerial: bool) -> void:
	var target_btn = map_btn
	if target_btn == null:
		for child in get_children():
			if child is CanvasLayer:
				target_btn = child.get_node_or_null("MapButton")
				if target_btn != null:
					break
				
	if target_btn != null:
		target_btn.text = ""
		if is_aerial:
			target_btn.tooltip_text = "Return to Player"
			apply_circular_button_style(target_btn, Color(0.2, 0.7, 0.35, 0.95))
		else:
			target_btn.tooltip_text = "Toggle Map View"
			apply_circular_button_style(target_btn, Color(0.18, 0.45, 0.25, 0.85))


func _set_helpers_visible(is_vis: bool) -> void:
	if toggles_scroll == null and right_panel != null:
		toggles_scroll = right_panel.get_node_or_null("TogglesScroll")
	if toggles_scroll != null:
		toggles_scroll.visible = is_vis
	if hide_helpers_btn != null:
		if is_vis:
			apply_circular_button_style(hide_helpers_btn, Color(0.25, 0.45, 0.7, 0.9))
		else:
			apply_circular_button_style(hide_helpers_btn, Color(0.15, 0.15, 0.15, 0.85))


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

	if MultiplayerManager.practice_mode_active and not GlobalSettings.is_chipping_minigame:
		if is_aerial:
			if not _is_aerial_active_practice:
				_was_helpers_visible_before_aerial = toggles_scroll.visible if toggles_scroll != null else false
				_is_aerial_active_practice = true
			_set_helpers_visible(true)
		else:
			if _is_aerial_active_practice:
				_set_helpers_visible(_was_helpers_visible_before_aerial)
				_is_aerial_active_practice = false


func _on_scorecard_toggle_pressed() -> void:
	if hud_manage_players.visible:
		hud_manage_players.visible = false
	if hud_overview.visible:
		hud_overview.visible = false
	if hud_scorecard.visible:
		_stop_scorecard_countdown()
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
	_last_scorecard_action_type = action_type
	
	# Clear previous cells
	for child in scorecard_grid.get_children():
		child.queue_free()
		
	var num_holes = MultiplayerManager.hole_ids.size()
	if num_holes == 0:
		return

	# Handle Filter Tabs Bar for 18-hole courses
	var vbox = hud_scorecard.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox != null:
		var filter_tabs = vbox.get_node_or_null("FilterTabs") as HBoxContainer
		if num_holes > 9:
			if filter_tabs == null:
				filter_tabs = HBoxContainer.new()
				filter_tabs.name = "FilterTabs"
				filter_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
				filter_tabs.add_theme_constant_override("separation", 12)
				var scroll_node = vbox.get_node_or_null("ScorecardScroll")
				var idx = scroll_node.get_index() if scroll_node != null else 1
				vbox.add_child(filter_tabs)
				vbox.move_child(filter_tabs, idx)
			
			# Re-populate filter buttons
			for child in filter_tabs.get_children():
				child.queue_free()
				
			var tab_options = ["All", "Front 9", "Back 9"]
			for tab_name in tab_options:
				var tab_btn = Button.new()
				tab_btn.text = tab_name
				tab_btn.custom_minimum_size = Vector2(110, 42)
				var is_selected = (_scorecard_view_tab == tab_name)
				var btn_bg = Color(0.24, 0.46, 0.72, 0.95) if is_selected else Color(0.12, 0.16, 0.24, 0.75)
				apply_material_button_style(tab_btn, btn_bg)
				if is_selected:
					tab_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
				tab_btn.pressed.connect(func():
					_scorecard_view_tab = tab_name
					_populate_scorecard(_last_scorecard_action_type)
				)
				filter_tabs.add_child(tab_btn)
		elif filter_tabs != null:
			filter_tabs.visible = false
		
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
			
	# Columns configuration based on selected view tab
	var columns = ["Player"]
	var render_front = (_scorecard_view_tab == "All" or _scorecard_view_tab == "Front 9")
	var render_back = (num_holes > 9 and (_scorecard_view_tab == "All" or _scorecard_view_tab == "Back 9"))
	
	if render_front:
		for i in range(front_holes.size()):
			columns.append(str(i + 1))
		if num_holes > 9 and _scorecard_view_tab == "All":
			columns.append("OUT")
		elif _scorecard_view_tab == "Front 9":
			columns.append("OUT")
			
	if render_back:
		for i in range(back_holes.size()):
			columns.append(str(10 + i))
		columns.append("IN")
		
	if _scorecard_view_tab == "All":
		columns.append("TOT")
		
	scorecard_grid.columns = columns.size()
	
	var header_bg = Color(0.10, 0.14, 0.22, 0.96)
	var active_hole_num = MultiplayerManager.current_hole_index + 1
	
	# Helper for cell creation with crisp, compact styling
	var add_cell = func(text: String, bg: Color, is_header: bool = false, fg: Color = Color.WHITE, font_size: int = 16, is_active: bool = false):
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(48, 38)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_FILL
		
		var style = StyleBoxFlat.new()
		if is_active:
			style.bg_color = bg.lerp(Color(0.20, 0.42, 0.68, 0.95), 0.35)
			style.border_width_left = 1
			style.border_width_top = 1
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.35, 0.72, 1.0, 0.85) # Crisp blue accent border for current active hole
		else:
			style.bg_color = bg
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.3, 0.35, 0.45, 0.35)
			
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
		label.add_theme_font_size_override("font_size", font_size)
		if is_header or is_active:
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			label.add_theme_constant_override("outline_size", 3)
		cell.add_child(label)
		scorecard_grid.add_child(cell)

	# --- 1. HEADER ROW ---
	for col in columns:
		var is_act = (col.is_valid_int() and int(col) == active_hole_num)
		add_cell.call(col, header_bg, true, Color.WHITE, 16, is_act)
		
	# --- 2. DISTANCE ROW ---
	var dist_bg = Color(0.13, 0.18, 0.28, 0.88)
	add_cell.call("Yds (%s)" % tee_color, dist_bg, false, Color(0.8, 0.8, 0.8), 15)
	
	var front_dist_sum = 0
	for i in range(front_holes.size()):
		var hole_id = front_holes[i]
		var dist = _get_hole_distance(hole_id, tee_color)
		front_dist_sum += dist
		if render_front:
			var is_act = ((i + 1) == active_hole_num)
			add_cell.call(str(dist), dist_bg, false, Color(0.85, 0.85, 0.85), 15, is_act)
			
	if render_front and (num_holes > 9 or _scorecard_view_tab == "Front 9"):
		add_cell.call(str(front_dist_sum), dist_bg, false, Color(1.0, 0.85, 0.38), 15)
		
	var back_dist_sum = 0
	if num_holes > 9:
		for i in range(back_holes.size()):
			var hole_id = back_holes[i]
			var dist = _get_hole_distance(hole_id, tee_color)
			back_dist_sum += dist
			if render_back:
				var is_act = ((10 + i) == active_hole_num)
				add_cell.call(str(dist), dist_bg, false, Color(0.85, 0.85, 0.85), 15, is_act)
				
		if render_back:
			add_cell.call(str(back_dist_sum), dist_bg, false, Color(1.0, 0.85, 0.38), 15)
			
	if _scorecard_view_tab == "All":
		var total_dist = front_dist_sum + (back_dist_sum if num_holes > 9 else 0)
		add_cell.call(str(total_dist), dist_bg, false, Color(1.0, 0.85, 0.38), 15)

	# --- 3. PAR ROW ---
	var par_bg = Color(0.16, 0.22, 0.34, 0.88)
	add_cell.call("Par", par_bg, false, Color(0.8, 0.8, 0.8), 15)
	
	var front_par_sum = 0
	for i in range(front_holes.size()):
		var hole_id = front_holes[i]
		var hole = MultiplayerManager.hole_info.get(hole_id, {})
		var par = hole.get("Par", 4)
		front_par_sum += par
		if render_front:
			var is_act = ((i + 1) == active_hole_num)
			add_cell.call(str(par), par_bg, false, Color(0.85, 0.85, 0.85), 15, is_act)
			
	if render_front and (num_holes > 9 or _scorecard_view_tab == "Front 9"):
		add_cell.call(str(front_par_sum), par_bg, false, Color(1.0, 0.85, 0.38), 15)
		
	var back_par_sum = 0
	if num_holes > 9:
		for i in range(back_holes.size()):
			var hole_id = back_holes[i]
			var hole = MultiplayerManager.hole_info.get(hole_id, {})
			var par = hole.get("Par", 4)
			back_par_sum += par
			if render_back:
				var is_act = ((10 + i) == active_hole_num)
				add_cell.call(str(par), par_bg, false, Color(0.85, 0.85, 0.85), 15, is_act)
				
		if render_back:
			add_cell.call(str(back_par_sum), par_bg, false, Color(1.0, 0.85, 0.38), 15)
			
	if _scorecard_view_tab == "All":
		var total_par = front_par_sum + (back_par_sum if num_holes > 9 else 0)
		add_cell.call(str(total_par), par_bg, false, Color(1.0, 0.85, 0.38), 15)

	var sc_title = hud_scorecard.get_node_or_null("VBoxContainer/TitleLabel") as Label
	if sc_title != null:
		sc_title.text = "Scorecard - MODE: %s" % MultiplayerManager.game_mode.to_upper()

	# --- 4. PLAYER ROWS ---
	var current_hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index] if MultiplayerManager.current_hole_index < num_holes else ""
	var is_skins_mode = (MultiplayerManager.game_mode == "Skins")
	var is_ctp_mode = (MultiplayerManager.game_mode == "Closest to Pin")
	
	for p_idx in range(MultiplayerManager.players.size()):
		var p = MultiplayerManager.players[p_idx]
		var row_bg = Color(0.14, 0.16, 0.20, 0.94) if p_idx % 2 == 0 else Color(0.09, 0.11, 0.14, 0.94)
		
		# Name cell
		var name_text = "%s (%s)" % [p["name"], p["tee"]]
		if not p.get("team", "").is_empty() and MultiplayerManager.game_mode == "2v2 Scramble":
			name_text = "%s [%s] (%s)" % [p["name"], p["team"], p["tee"]]
		var name_fg = Color.WHITE
		if not p.get("active", true):
			name_text += " (Out)"
			name_fg = Color(0.6, 0.6, 0.6)
			
		var cell = PanelContainer.new()
		cell.custom_minimum_size = Vector2(200, 38)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.size_flags_vertical = Control.SIZE_FILL
		
		var style = StyleBoxFlat.new()
		style.bg_color = row_bg
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color(0.3, 0.35, 0.45, 0.35)
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		cell.add_theme_stylebox_override("panel", style)
		
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 8)
		cell.add_child(hbox)
		
		# Avatar or Color badge
		var avatar_path = p.get("avatar", "")
		if avatar_path.is_empty():
			avatar_path = MultiplayerManager.get_player_avatar(p.get("name", ""))
		
		if not avatar_path.is_empty() and ResourceLoader.exists(avatar_path):
			var avatar_rect = TextureRect.new()
			avatar_rect.texture = load(avatar_path)
			avatar_rect.custom_minimum_size = Vector2(24, 24)
			avatar_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			avatar_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hbox.add_child(avatar_rect)
		else:
			var badge = PanelContainer.new()
			badge.custom_minimum_size = Vector2(24, 24)
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			
			var badge_style = StyleBoxFlat.new()
			var p_color = MultiplayerManager.get_player_color(p)
			badge_style.bg_color = p_color
			badge_style.corner_radius_top_left = 12
			badge_style.corner_radius_top_right = 12
			badge_style.corner_radius_bottom_left = 12
			badge_style.corner_radius_bottom_right = 12
			badge_style.content_margin_left = 3
			badge_style.content_margin_right = 3
			badge_style.content_margin_top = 1
			badge_style.content_margin_bottom = 1
			badge.add_theme_stylebox_override("panel", badge_style)
			
			var badge_lbl = Label.new()
			badge_lbl.text = p["name"].substr(0, 1).to_upper()
			badge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge_lbl.add_theme_font_size_override("font_size", 12)
			badge_lbl.add_theme_color_override("font_color", Color.WHITE)
			badge_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			badge_lbl.add_theme_constant_override("outline_size", 2)
			badge.add_child(badge_lbl)
			
			hbox.add_child(badge)
		
		var label = Label.new()
		label.text = name_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", name_fg)
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 2)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(label)
		
		var email_btn = Button.new()
		email_btn.text = "✉️"
		email_btn.tooltip_text = "Email shot stats for " + p["name"]
		email_btn.custom_minimum_size = Vector2(30, 30)
		email_btn.focus_mode = Control.FOCUS_NONE
		email_btn.add_theme_font_size_override("font_size", 13)
		
		var btn_style_normal = StyleBoxFlat.new()
		btn_style_normal.bg_color = Color(0.2, 0.4, 0.7, 0.8)
		btn_style_normal.corner_radius_top_left = 6
		btn_style_normal.corner_radius_top_right = 6
		btn_style_normal.corner_radius_bottom_left = 6
		btn_style_normal.corner_radius_bottom_right = 6
		
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
		for i in range(front_holes.size()):
			var hole_id = front_holes[i]
			var display_score = "-"
			var is_current = (hole_id == current_hole_id)
			if is_ctp_mode:
				var s = p["hole_scores"].get(hole_id)
				if s != null:
					display_score = str(s)
					front_score_sum += int(s)
				elif is_current and p.get("active", true) and p["strokes"] > 0:
					display_score = "*"
			elif is_current:
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
			if display_score != "-" and display_score != "*":
				if is_ctp_mode:
					if display_score == "1":
						display_score = "1 ⛳"
						score_fg = Color(1.0, 0.85, 0.35)
					else:
						score_fg = Color(0.6, 0.6, 0.6)
				else:
					var hole = MultiplayerManager.hole_info.get(hole_id, {})
					var par = hole.get("Par", 4)
					var score_val = int(display_score.rstrip("*"))
					if score_val < par:
						score_fg = Color(0.35, 0.95, 0.55)
					elif score_val > par:
						score_fg = Color(1.0, 0.42, 0.42)

					if is_skins_mode:
						var h_res = MultiplayerManager.hole_skins_results.get(hole_id, {})
						if not h_res.is_empty():
							if h_res.get("winner", "") == p["name"]:
								display_score += " 🏆"
								score_fg = Color(1.0, 0.85, 0.35)
							elif h_res.get("winner", "") == "Tie":
								display_score += " (C)"
								
			if render_front:
				var is_act = ((i + 1) == active_hole_num)
				add_cell.call(display_score, row_bg, false, score_fg, 17, is_act)
			
		if render_front and (num_holes > 9 or _scorecard_view_tab == "Front 9"):
			add_cell.call(str(front_score_sum) if front_score_sum > 0 else "-", row_bg, false, Color(1.0, 0.85, 0.38), 17)
			
		# Back 9 scores
		var back_score_sum = 0
		if num_holes > 9:
			for i in range(back_holes.size()):
				var hole_id = back_holes[i]
				var display_score = "-"
				var is_current = (hole_id == current_hole_id)
				if is_ctp_mode:
					var s = p["hole_scores"].get(hole_id)
					if s != null:
						display_score = str(s)
						back_score_sum += int(s)
					elif is_current and p.get("active", true) and p["strokes"] > 0:
						display_score = "*"
				elif is_current:
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
				if display_score != "-" and display_score != "*":
					if is_ctp_mode:
						if display_score == "1":
							display_score = "1 ⛳"
							score_fg = Color(1.0, 0.85, 0.35)
						else:
							score_fg = Color(0.6, 0.6, 0.6)
					else:
						var hole = MultiplayerManager.hole_info.get(hole_id, {})
						var par = hole.get("Par", 4)
						var score_val = int(display_score.rstrip("*"))
						if score_val < par:
							score_fg = Color(0.35, 0.95, 0.55)
						elif score_val > par:
							score_fg = Color(1.0, 0.42, 0.42)
						
						if is_skins_mode:
							var h_res = MultiplayerManager.hole_skins_results.get(hole_id, {})
							if not h_res.is_empty():
								if h_res.get("winner", "") == p["name"]:
									display_score += " 🏆"
									score_fg = Color(1.0, 0.85, 0.35)
								elif h_res.get("winner", "") == "Tie":
									display_score += " (C)"
									
				if render_back:
					var is_act = ((10 + i) == active_hole_num)
					add_cell.call(display_score, row_bg, false, score_fg, 17, is_act)
					
			if render_back:
				add_cell.call(str(back_score_sum) if back_score_sum > 0 else "-", row_bg, false, Color(1.0, 0.85, 0.38), 17)
				
		if _scorecard_view_tab == "All":
			var total_score = front_score_sum + back_score_sum
			var tot_display = str(total_score) if total_score > 0 else "-"
			if is_skins_mode:
				tot_display = "%d Skins (%s)" % [MultiplayerManager.skins_won.get(p["name"], 0), tot_display]
			elif is_ctp_mode:
				tot_display = "%d pts" % total_score
			add_cell.call(tot_display, row_bg, false, Color(1.0, 0.85, 0.38), 17)

	# --- 5. ACTION BUTTON CONFIGURATION ---
	var action_btn = _scorecard_action_btn
	if action_btn == null:
		action_btn = hud_scorecard.find_child("ScorecardActionBtn", true, false) as Button
	if action_btn != null:
		for conn in action_btn.pressed.get_connections():
			action_btn.pressed.disconnect(conn.callable)
		
	if action_type == "toggle":
		_stop_scorecard_countdown()
		if action_btn != null:
			action_btn.text = "Close"
			action_btn.pressed.connect(func():
				_stop_scorecard_countdown()
				hud_scorecard.visible = false
				_set_other_elements_visible(true)
			)
	elif action_type == "hole_completed":
		var is_final_hole = (MultiplayerManager.current_hole_index >= MultiplayerManager.hole_ids.size() - 1)
		if action_btn != null:
			action_btn.text = "Finish Round" if is_final_hole else "Next Hole"
			action_btn.pressed.connect(func():
				_on_scorecard_advance()
			)
		_start_scorecard_countdown(5.0)
	elif action_type == "game_over":
		_stop_scorecard_countdown()
		if action_btn != null:
			action_btn.text = "Main Menu"
			action_btn.pressed.connect(func():
				SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
			)


func _start_scorecard_countdown(seconds: float = 5.0) -> void:
	_scorecard_countdown_time_left = seconds
	_scorecard_countdown_active = true
	_scorecard_countdown_paused = false
	if _scorecard_countdown_container != null:
		_scorecard_countdown_container.visible = true
	if _scorecard_pause_btn != null:
		_scorecard_pause_btn.text = "⏸ Pause"
		apply_material_button_style(_scorecard_pause_btn, Color(0.35, 0.38, 0.45, 0.85))
	if _scorecard_countdown_lbl != null:
		_scorecard_countdown_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 1.0))
	_update_scorecard_countdown_display()


func _stop_scorecard_countdown() -> void:
	_scorecard_countdown_active = false
	_scorecard_countdown_paused = false
	_scorecard_countdown_time_left = 0.0
	if _scorecard_countdown_container != null:
		_scorecard_countdown_container.visible = false


func _on_scorecard_pause_toggled() -> void:
	if not _scorecard_countdown_active:
		return
	_scorecard_countdown_paused = not _scorecard_countdown_paused
	_update_scorecard_pause_ui()


func _update_scorecard_pause_ui() -> void:
	if _scorecard_countdown_paused:
		if _scorecard_pause_btn != null:
			_scorecard_pause_btn.text = "▶ Resume"
			apply_material_button_style(_scorecard_pause_btn, Color(0.22, 0.52, 0.32, 0.85))
		if _scorecard_countdown_lbl != null:
			_scorecard_countdown_lbl.text = "Auto-advance paused"
			_scorecard_countdown_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4, 1.0))
	else:
		if _scorecard_pause_btn != null:
			_scorecard_pause_btn.text = "⏸ Pause"
			apply_material_button_style(_scorecard_pause_btn, Color(0.35, 0.38, 0.45, 0.85))
		if _scorecard_countdown_lbl != null:
			_scorecard_countdown_lbl.add_theme_color_override("font_color", Color(0.9, 0.92, 1.0, 1.0))
		if _scorecard_countdown_time_left < 1.0:
			_scorecard_countdown_time_left = 1.0
		_update_scorecard_countdown_display()


func _update_scorecard_countdown_display() -> void:
	if not _scorecard_countdown_active or _scorecard_countdown_paused:
		return
	var secs = ceili(_scorecard_countdown_time_left)
	if secs < 1:
		secs = 1
	var is_final_hole = (MultiplayerManager.current_hole_index >= MultiplayerManager.hole_ids.size() - 1)
	if _scorecard_countdown_lbl != null:
		if is_final_hole:
			_scorecard_countdown_lbl.text = "Finishing round in %ds..." % secs
		else:
			_scorecard_countdown_lbl.text = "Next hole in %ds..." % secs


func _on_scorecard_advance() -> void:
	_stop_scorecard_countdown()
	hud_scorecard.visible = false
	_set_other_elements_visible(true)
	reset_zoom_to_default()
	MultiplayerManager.advance_hole()


func _set_other_elements_visible(is_visible: bool) -> void:
	_hud_elements_visible = is_visible
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
	if home_btn != null:
		home_btn.visible = is_visible
	if hide_helpers_btn != null:
		hide_helpers_btn.visible = is_visible
	if right_panel != null:
		right_panel.visible = is_visible
	if stats_btn != null:
		stats_btn.visible = is_visible
	if grid_btn != null:
		grid_btn.visible = is_visible
	if map_btn != null:
		map_btn.visible = is_visible
	if mulligan_btn != null:
		var is_match_play = not MultiplayerManager.players.is_empty() and not MultiplayerManager.practice_mode_active
		mulligan_btn.visible = is_visible and is_match_play
	if forfeit_btn != null:
		var is_match_play = not MultiplayerManager.players.is_empty() and not MultiplayerManager.practice_mode_active
		var active_p = MultiplayerManager.get_active_player()
		var p_strokes = active_p.get("strokes", 0) if not active_p.is_empty() else 0
		var p_holed = active_p.get("holed_out", false) if not active_p.is_empty() else true
		forfeit_btn.visible = is_visible and is_match_play and p_strokes >= 10 and not p_holed
	if not is_visible and forfeit_confirm_dialog != null and forfeit_confirm_dialog.visible:
		forfeit_confirm_dialog.visible = false
	if club_selector_node != null:
		club_selector_node.visible = is_visible


func _on_manage_players_toggle_pressed() -> void:
	if forfeit_confirm_dialog != null and forfeit_confirm_dialog.visible:
		forfeit_confirm_dialog.visible = false
	if hud_scorecard.visible:
		_stop_scorecard_countdown()
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
		toggle_btn.custom_minimum_size = Vector2(110, 44)
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
	var tee_color = p.get("tee", "Blue")
	var date_str = Time.get_date_string_from_system() + " " + Time.get_time_string_from_system().substr(0, 5)
	
	var subject = "Heckle Golf Simulator - Round Stats for %s on %s" % [player_name, course_title]
	
	var pars = {}
	var distances = {}
	for hole_id in MultiplayerManager.hole_ids:
		var hole = MultiplayerManager.hole_info.get(hole_id, {})
		pars[hole_id] = hole.get("Par", 4)
		distances[hole_id] = { tee_color: _get_hole_distance(hole_id, tee_color) }

	var match_data = {
		"course_title": course_title,
		"formatted_date": date_str,
		"pars": pars,
		"distances": distances,
		"hole_ids": MultiplayerManager.hole_ids
	}

	# Build clean email summary
	var body = "Round Stats for %s\n" % player_name
	body += "Course: %s\n" % course_title
	body += "Tee: %s\n" % tee_color
	body += "Date: %s\n" % date_str
	body += "Total Strokes: %d\n\n" % total_strokes
	body += "Hole-by-Hole Scores:\n"
	body += "==================================================\n"
	
	for hole_id in MultiplayerManager.hole_ids:
		var par = pars.get(hole_id, 4)
		var dist = _get_hole_distance(hole_id, tee_color)
		var score_val = p["hole_scores"].get(hole_id)
		var score_str = str(score_val) if score_val != null else "-"
		body += "%s (Par %d, %d Yds) - Score: %s\n" % [hole_id, par, dist, score_str]
	body += "\n"

	# Generate golf data CSV
	var csv_content = GolfDataExporter.generate_round_csv(p, match_data)
	var safe_player = GolfDataExporter.sanitize_filename(player_name)
	var safe_course = GolfDataExporter.sanitize_filename(course_title)
	var safe_date = GolfDataExporter.sanitize_filename(date_str)
	var attachment_basename = "%s_%s_%s_golf_data" % [safe_player, safe_course, safe_date]
		
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
	
	var to_email = p.get("email", "")
	if to_email.is_empty():
		to_email = MultiplayerManager.get_player_email(player_name)

	GolfDataExporter.export_and_email(to_email, subject, body, attachment_basename, csv_content)
	print("[CoursePlay] Opened email client with attached CSV for %s" % player_name)


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
	
	# Sprite3D for the circle background or avatar
	var sprite = Sprite3D.new()
	sprite.name = "Sprite"
	
	var avatar_path = player.get("avatar", "")
	if avatar_path.is_empty():
		avatar_path = MultiplayerManager.get_player_avatar(player.get("name", ""))
	var has_avatar = not avatar_path.is_empty() and ResourceLoader.exists(avatar_path)
	
	if has_avatar:
		sprite.texture = load(avatar_path)
	else:
		sprite.texture = _get_player_circle_texture(color)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.no_depth_test = true
	sprite.double_sided = true
	sprite.pixel_size = 0.025 # ~3.2m wide
	sprite.position = Vector3(0, 3.0, 0)
	sprite.layers = 2
	marker.add_child(sprite)
	
	# Label3D for the letter (only when not using custom avatar)
	var label = Label3D.new()
	label.name = "Label"
	label.text = "" if has_avatar else letter
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


func _get_player_points(p: Dictionary) -> int:
	var total_pts: int = 0
	for hole_id in MultiplayerManager.hole_ids:
		var s = p["hole_scores"].get(hole_id)
		if s != null:
			total_pts += int(s)
	return total_pts


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
		
	var is_ctp = (MultiplayerManager.game_mode == "Closest to Pin")
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
			
		if is_ctp:
			var pts_a = _get_player_points(a)
			var pts_b = _get_player_points(b)
			if pts_a != pts_b:
				return pts_a > pts_b # HIGHEST SCORE WINS!
			return a["name"] < b["name"]

		var diff_a = _get_player_overall_diff(a)
		var diff_b = _get_player_overall_diff(b)
		if diff_a != diff_b:
			return diff_a < diff_b
		return a["name"] < b["name"]
	)
	
	# Winner presentation (First place)
	var winner = sorted_players[0]
	var winner_diff = ("%d pts" % _get_player_points(winner)) if is_ctp else _get_overall_par_string(winner)
	
	var winner_panel = PanelContainer.new()
	var wp_style = StyleBoxFlat.new()
	wp_style.bg_color = Color(0.12, 0.20, 0.32, 0.8) # Highlighted dark blue
	wp_style.border_width_left = 2
	wp_style.border_width_top = 2
	wp_style.border_width_right = 2
	wp_style.border_width_bottom = 2
	wp_style.border_color = Color(1.0, 0.85, 0.38) # Gold border for winner
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
	winner_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
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
	if is_ctp:
		winner_stats_lbl.text = "Total Points: %d  |  Furthest Drive: %s" % [_get_player_points(winner), winner_drive_str]
	else:
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
	ThemeManager.apply_scroll_container_style(scroll, 28)
	vbox.add_child(scroll)
	
	var players_list_vbox = VBoxContainer.new()
	players_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_list_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(players_list_vbox)
	
	for i in range(1, sorted_players.size()):
		var p = sorted_players[i]
		var p_diff = ("%d pts" % _get_player_points(p)) if is_ctp else _get_overall_par_string(p)
		
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
		if is_ctp:
			diff_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.38))
		elif p_diff.begins_with("-"):
			diff_lbl.add_theme_color_override("font_color", Color(0.35, 0.95, 0.55))
		elif p_diff.begins_with("+"):
			diff_lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
		else:
			diff_lbl.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(diff_lbl)
		
		var p_drive = _get_player_furthest_drive(p)
		var p_drive_str = "%.1f yds" % p_drive if p_drive > 0.0 else "N/A"
		
		var stats_lbl = Label.new()
		if is_ctp:
			stats_lbl.text = "Total Points: %d  |  Furthest Drive: %s" % [_get_player_points(p), p_drive_str]
		else:
			var p_best = _get_player_best_hole(p)
			var p_best_str = "N/A"
			if not p_best.is_empty():
				var b_diff = p_best["diff"]
				var b_diff_str = str(b_diff) if b_diff < 0 else ("+" + str(b_diff) if b_diff > 0 else "E")
				p_best_str = "%s (%s)" % [p_best["hole_id"], b_diff_str]
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
		
	# Skip if scorecard, players list, camera setup dialog, replay modal, exit confirm dialog, or forfeit dialog is open
	if hud_scorecard.visible or hud_manage_players.visible or hud_overview.visible or (exit_confirm_dialog != null and exit_confirm_dialog.visible) or (forfeit_confirm_dialog != null and forfeit_confirm_dialog.visible):
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
			is_on_green = (active_ball.get("lie_type") == "green")
		var dist_m = active_player_pos.distance_to(pin_pos)
		var dist_feet = dist_m * 3.28084
		if not is_on_green and dist_feet >= 50.0 and not camera.is_position_behind(pin_pos):
			var screen_pos = camera.unproject_position(pin_pos)
			var view_rect = overlay.get_viewport_rect()
			if view_rect.has_point(screen_pos):
				# Calculate dynamic height based on distance
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
					
	# Don't show player ball icons when you are within 50 feet of the hole
	if pin_pos != null and not pin_pos.is_zero_approx():
		var dist_to_hole_m = active_player_pos.distance_to(pin_pos)
		var dist_to_hole_feet = dist_to_hole_m * 3.28084
		if dist_to_hole_feet < 50.0:
			return

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
			
		# Don't show player ball icons anywhere if they are within 20 feet of you
		var dist_m = active_player_pos.distance_to(ball_pos)
		var dist_feet = dist_m * 3.28084
		if dist_feet < 20.0:
			continue
			
		if camera.is_position_behind(ball_pos):
			continue
			
		var screen_pos = camera.unproject_position(ball_pos)
		var view_rect = overlay.get_viewport_rect()
		if not view_rect.has_point(screen_pos):
			continue
			
		# Calculate dynamic height based on distance
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
		
		var avatar_path = p.get("avatar", "")
		if avatar_path.is_empty():
			avatar_path = MultiplayerManager.get_player_avatar(p.get("name", ""))
		var has_avatar = not avatar_path.is_empty() and ResourceLoader.exists(avatar_path)

		# Draw circle shadow
		overlay.draw_circle(circle_pos, 17.0, Color(0.0, 0.0, 0.0, 0.35))

		if has_avatar:
			var tex = load(avatar_path) as Texture2D
			if tex != null:
				overlay.draw_texture_rect(tex, Rect2(circle_pos - Vector2(16, 16), Vector2(32, 32)), false)
		else:
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
	style_normal.corner_radius_top_left = 20
	style_normal.corner_radius_top_right = 20
	style_normal.corner_radius_bottom_left = 20
	style_normal.corner_radius_bottom_right = 20
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
	btn.add_theme_font_size_override("font_size", 20)


func _update_grid_button_state(active: bool) -> void:
	if grid_btn == null:
		return
	if active:
		apply_circular_button_style(grid_btn, Color(0.2, 0.6, 0.3, 0.85)) # Green when active
	else:
		apply_circular_button_style(grid_btn, Color(0.15, 0.15, 0.15, 0.85)) # Gray when inactive


class MultiplayerBallOverlay extends Control:
	var _controller: Node = null
	
	func _init(controller: Node) -> void:
		_controller = controller
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		
	func _draw() -> void:
		if _controller != null and _controller.has_method("_draw_ball_overlays"):
			_controller._draw_ball_overlays(self)
