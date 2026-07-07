extends Node3D

@onready var hud_player_name = Label.new()
@onready var hud_hole_name = Label.new()
@onready var hud_scorecard = Panel.new()
@onready var scorecard_grid = GridContainer.new()
@onready var hud_manage_players = Panel.new()
var _minimap_camera: Camera3D = null
var _minimap_panel: PanelContainer = null

var range_ui: Control = null
var top_bar: HBoxContainer = null
var right_panel: VBoxContainer = null
var settings_btn: Button = null

var course_instance: Node = null
var active_ball: Node = null

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
			if range_ui.has_signal("manage_players_requested"):
				range_ui.manage_players_requested.connect(_on_manage_players_toggle_pressed)

	var canvas = CanvasLayer.new()
	canvas.layer = 15 # Render on top of VignetteLayer (layer 10)
	add_child(canvas)
	
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
	
	hud_player_name.text = "Active Player: ---"
	hud_player_name.add_theme_font_size_override("font_size", 28)
	top_bar.add_child(hud_player_name)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)
	
	hud_hole_name.text = "Hole 1"
	hud_hole_name.add_theme_font_size_override("font_size", 28)
	top_bar.add_child(hud_hole_name)

	# Settings Button (Icon Only) - Top-Right Corner
	settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.icon = load("res://Utils/Settings/Gear.png")
	settings_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_btn.custom_minimum_size = Vector2(44, 44)
	apply_circular_button_style(settings_btn, Color(0.15, 0.15, 0.15, 0.85))
	settings_btn.anchor_left = 1.0
	settings_btn.anchor_right = 1.0
	settings_btn.offset_left = -74
	settings_btn.offset_top = 30
	settings_btn.offset_right = -30
	settings_btn.offset_bottom = 74
	settings_btn.pressed.connect(func():
		if range_ui != null:
			range_ui.call("_on_toggle_settings_requested")
	)
	canvas.add_child(settings_btn)

	# RightPanel vertical stack
	right_panel = VBoxContainer.new()
	right_panel.name = "RightPanel"
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.offset_left = -210
	right_panel.offset_top = 90
	right_panel.offset_right = -30
	right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_panel.add_theme_constant_override("separation", 12)
	canvas.add_child(right_panel)

	# Hide Toggles Button
	var hide_toggles_btn = Button.new()
	hide_toggles_btn.name = "HideTogglesButton"
	hide_toggles_btn.text = "👁 Hide Toggles"
	hide_toggles_btn.custom_minimum_size = Vector2(180, 40)
	apply_material_button_style(hide_toggles_btn, Color(0.2, 0.2, 0.2, 0.85))
	
	var toggles_container = VBoxContainer.new()
	toggles_container.name = "TogglesContainer"
	toggles_container.add_theme_constant_override("separation", 12)
	
	hide_toggles_btn.pressed.connect(func():
		toggles_container.visible = not toggles_container.visible
		if toggles_container.visible:
			hide_toggles_btn.text = "👁 Hide Toggles"
		else:
			hide_toggles_btn.text = "👁 Show Toggles"
	)
	
	right_panel.add_child(hide_toggles_btn)
	right_panel.add_child(toggles_container)

	# Main Menu Button
	var menu_btn = Button.new()
	menu_btn.name = "MainMenuButton"
	menu_btn.text = "⌂ Main Menu"
	menu_btn.custom_minimum_size = Vector2(180, 40)
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
	dist_btn.custom_minimum_size = Vector2(180, 40)
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
	stats_btn.custom_minimum_size = Vector2(180, 40)
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

	# Sky View Toggle Button
	var sky_view_btn = Button.new()
	sky_view_btn.name = "SkyViewButton"
	sky_view_btn.text = "☁ Sky View"
	sky_view_btn.custom_minimum_size = Vector2(180, 40)
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
	map_btn.custom_minimum_size = Vector2(180, 40)
	apply_material_button_style(map_btn, Color(0.18, 0.45, 0.25, 0.85)) # Forest green
	map_btn.pressed.connect(func():
		if course_instance and course_instance.has_method("_on_map_button_pressed"):
			course_instance.call("_on_map_button_pressed")
	)
	toggles_container.add_child(map_btn)

	# If in practice mode, create practice buttons (initially hidden, shown only in map view)
	if MultiplayerManager.practice_mode_active:
		var place_btn = Button.new()
		place_btn.name = "PlaceBallButton"
		place_btn.text = "📍 Place Ball: OFF"
		place_btn.custom_minimum_size = Vector2(180, 40)
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
		prev_btn.text = "⏮ Previous Hole"
		prev_btn.custom_minimum_size = Vector2(180, 40)
		apply_material_button_style(prev_btn, Color(0.4, 0.4, 0.4, 0.85))
		prev_btn.pressed.connect(func():
			if course_instance != null and course_instance.has_method("prev_practice_hole"):
				course_instance.call("prev_practice_hole")
		)
		prev_btn.visible = false
		toggles_container.add_child(prev_btn)
		
		var next_btn = Button.new()
		next_btn.name = "NextHoleButton"
		next_btn.text = "⏭ Next Hole"
		next_btn.custom_minimum_size = Vector2(180, 40)
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
	
	# Reparent ClubSelector to the bottom of right panel
	if range_ui != null:
		var club_sel = range_ui.get_node_or_null("GridCanvas/ClubSelector")
		if club_sel == null:
			club_sel = range_ui.get_node_or_null("RightPanel/TogglesContainer/ClubSelector")
			if club_sel == null:
				club_sel = range_ui.get_node_or_null("RightPanel/ClubSelector")
		if club_sel != null:
			club_sel.reparent(toggles_container)
			club_sel.custom_minimum_size = Vector2(180, 40)
			club_sel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	
	# --- Minimap Viewport Construction ---
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
	minimap_panel.position = Vector2(30, 95)
	
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
	minimap_camera.size = 150.0
	minimap_camera.position = Vector3(0, 150, 0)
	minimap_camera.rotation = Vector3(-PI/2, 0, 0) # Look straight down
	
	viewport.add_child(minimap_camera)
	minimap_container.add_child(viewport)
	minimap_panel.add_child(minimap_container)
	canvas.add_child(minimap_panel)
	
	# Make the camera current inside the SubViewport
	minimap_camera.make_current()
	
	_minimap_camera = minimap_camera
	_minimap_panel = minimap_panel
	
	# Scorecard Panel
	hud_scorecard.visible = false
	hud_scorecard.anchor_left = 0.5
	hud_scorecard.anchor_right = 0.5
	hud_scorecard.anchor_top = 0.5
	hud_scorecard.anchor_bottom = 0.5
	hud_scorecard.offset_left = -650
	hud_scorecard.offset_right = 650
	hud_scorecard.offset_top = -250
	hud_scorecard.offset_bottom = 250
	
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
	action_btn.custom_minimum_size = Vector2(150, 45)
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
	
	var m_name_input = LineEdit.new()
	m_name_input.name = "NameInput"
	m_name_input.placeholder_text = "Player Name"
	m_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(m_name_input)
	
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
		var p_name = name_input.text.strip_edges()
		if p_name.is_empty():
			p_name = "Player " + str(MultiplayerManager.players.size() + 1)
		var tee_color = tee_opt.get_item_text(tee_opt.selected)
		
		MultiplayerManager.add_new_player(p_name, tee_color)
		
		name_input.clear()
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


func _on_active_player_changed(player: Dictionary) -> void:
	if player.is_empty():
		return
		
	var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index]
	var active_hole = MultiplayerManager.hole_info.get(hole_id, {})
	hud_player_name.text = "Player: %s (Strokes: %d)" % [player["name"], player["strokes"]]
	hud_hole_name.text = "Hole: %s (Par %d)" % [hole_id, active_hole.get("Par", 4)]
	
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
			
			# Move camera target to focus on the active ball
			var camera = course_instance.get_node_or_null("PhantomCamera3D")
			if camera != null:
				camera.follow_target = active_ball
				
			# Automatically aim at the pin and position/rotate the camera behind the ball
			if course_instance != null:
				var pin_pos = course_instance.get("current_hole_location")
				if pin_pos != null and not pin_pos.is_zero_approx():
					var ball_pos = active_ball.position
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
						camera.look_at(pin_pos + Vector3.UP * 0.5)
						
						var cam3d = course_instance.get_node_or_null("Camera3D")
						if cam3d != null:
							cam3d.global_position = cam_pos
							cam3d.look_at(pin_pos + Vector3.UP * 0.5)
			
		# Redraw active player's tracer trails if any
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			player_node.call("reset_shot_data")
			# Re-draw the player's last shot tracer line
			if not player["shot_history"].is_empty():
				player_node.call("create_new_tracer")
				var tracer = player_node.get("current_tracer")
				if tracer != null:
					for pt in player["shot_history"]:
						tracer.call("add_point", pt)




func _on_mulligan_pressed() -> void:
	var player_node = course_instance.get_node_or_null("Player")
	if player_node != null:
		player_node.call("mulligan")
		if course_instance.has_method("remove_last_shot"):
			course_instance.call("remove_last_shot")
		
		# Update MultiplayerManager data
		var active_player = MultiplayerManager.get_active_player()
		active_player["position"] = player_node.get("_last_starting_pos")
		var penalty = active_player.get("last_shot_penalty", 0)
		var strokes_to_remove = 1 + penalty
		active_player["strokes"] = max(0, active_player["strokes"] - strokes_to_remove)
		active_player["total_strokes"] = max(0, active_player["total_strokes"] - strokes_to_remove)
		active_player["last_shot_penalty"] = 0
		if not active_player["shot_history"].is_empty():
			active_player["shot_history"].pop_back()
			
		if not MultiplayerManager.hole_ids.is_empty():
			var hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index]
			active_player["hole_scores"][hole_id] = active_player["strokes"]
			if active_player.has("shot_stats"):
				if typeof(active_player["shot_stats"]) == TYPE_DICTIONARY:
					if active_player["shot_stats"].has(hole_id) and not active_player["shot_stats"][hole_id].is_empty():
						active_player["shot_stats"][hole_id].pop_back()
				elif typeof(active_player["shot_stats"]) == TYPE_ARRAY and not active_player["shot_stats"].is_empty():
					active_player["shot_stats"].pop_back()
			
		_on_active_player_changed(active_player)
		MultiplayerManager.save_current_match()


func _on_hole_completed(scores: Array) -> void:
	_populate_scorecard("hole_completed")
	hud_scorecard.visible = true
	_set_other_elements_visible(false)


func _on_game_over(scores: Array) -> void:
	MultiplayerManager.is_finished = true
	MultiplayerManager.save_current_match()
	_populate_scorecard("game_over")
	hud_scorecard.visible = true
	_set_other_elements_visible(false)


func _process(_delta: float) -> void:
	_update_minimap()


func _update_minimap() -> void:
	if _minimap_camera == null or course_instance == null or _minimap_panel == null:
		return
		
	# Check if scorecard or players HUD is open
	if hud_scorecard.visible or hud_manage_players.visible:
		_minimap_panel.visible = false
		return
		
	# Check if the course is in full-screen aerial view
	var is_aerial = course_instance.get("is_aerial_view") as bool if course_instance.get("is_aerial_view") != null else false
	
	# The box shouldn't show at all when the full-screen aerial view is active
	_minimap_panel.visible = not is_aerial
	
	if is_aerial:
		return # No need to calculate if it's hidden
		
	var ball = active_ball
	if ball == null:
		var player_node = course_instance.get_node_or_null("Player")
		if player_node != null:
			ball = player_node.get("ball")
			
	if ball == null:
		return
		
	var ball_pos = ball.global_position
	var pin_pos = course_instance.get("current_hole_location")
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
		
	var target_size = clamp(dist * 1.43, 60.0, 450.0)
	_minimap_camera.size = target_size
	
	# Orientation - aligns camera exactly to face the player's aiming direction
	var right_vec = dir_3d.cross(Vector3.UP).normalized()
	var up_vec = dir_3d
	var back_vec = Vector3.UP
	_minimap_camera.transform.basis = Basis(right_vec, up_vec, back_vec)
	
	# Position - exact base position alignment as full aerial view
	var base_pos = ball_pos + dir_3d * (0.35 * target_size)
	_minimap_camera.position = Vector3(base_pos.x, 150.0, base_pos.z)


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
	style_normal.corner_radius_top_left = 22 # Half of 44 height
	style_normal.corner_radius_top_right = 22
	style_normal.corner_radius_bottom_left = 22
	style_normal.corner_radius_bottom_right = 22
	style_normal.content_margin_left = 6
	style_normal.content_margin_right = 6
	style_normal.content_margin_top = 6
	style_normal.content_margin_bottom = 6

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
				var place_btn = panel.get_node_or_null("TogglesContainer/PlaceBallButton")
				var prev_btn = panel.get_node_or_null("TogglesContainer/PrevHoleButton")
				var next_btn = panel.get_node_or_null("TogglesContainer/NextHoleButton")
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

	# --- 4. PLAYER ROWS ---
	var current_hole_id = MultiplayerManager.hole_ids[MultiplayerManager.current_hole_index] if MultiplayerManager.current_hole_index < num_holes else ""
	
	for p_idx in range(MultiplayerManager.players.size()):
		var p = MultiplayerManager.players[p_idx]
		var row_bg = Color(0.1, 0.12, 0.18, 0.9) if p_idx % 2 == 0 else Color(0.06, 0.08, 0.12, 0.9)
		
		# Name cell
		var name_text = "%s (%s)" % [p["name"], p["tee"]]
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
						
				add_cell.call(display_score, row_bg, false, score_fg)
				
			add_cell.call(str(back_score_sum) if back_score_sum > 0 else "-", row_bg, false, Color(0.9, 0.9, 0.9))
			
			var total_score = front_score_sum + back_score_sum
			add_cell.call(str(total_score) if total_score > 0 else "-", row_bg, false, Color.YELLOW)
		else:
			add_cell.call(str(front_score_sum) if front_score_sum > 0 else "-", row_bg, false, Color.YELLOW)

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
	if _minimap_panel != null:
		var is_aerial = false
		if course_instance != null and course_instance.get("is_aerial_view") != null:
			is_aerial = course_instance.get("is_aerial_view") as bool
		_minimap_panel.visible = is_visible and not is_aerial
	if top_bar != null:
		top_bar.visible = is_visible
	if settings_btn != null:
		settings_btn.visible = is_visible
	if right_panel != null:
		right_panel.visible = is_visible


func _on_manage_players_toggle_pressed() -> void:
	if hud_scorecard.visible:
		hud_scorecard.visible = false
	if hud_manage_players.visible:
		hud_manage_players.visible = false
		_set_other_elements_visible(true)
	else:
		_populate_manage_players()
		hud_manage_players.visible = true
		_set_other_elements_visible(false)


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
		
	var mailto_url = "mailto:?subject=" + subject.uri_encode() + "&body=" + body.uri_encode()
	OS.shell_open(mailto_url)
