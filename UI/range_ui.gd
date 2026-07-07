extends MarginContainer

signal rec_button_pressed
signal set_session(dir: String, player_name: String)

signal hit_shot(data)
signal manage_players_requested

var _avg_carry: Label
var _avg_speed: Label
var _avg_spin: Label
var _avg_offline: Label
var _avg_target_diff: Label
var _prev_shot_popup: Panel
var _prev_shot_data_label: Label
var _last_shot_data: Dictionary = {}
var _right_panel: VBoxContainer = null


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	GlobalSettings.range_settings.shot_injector_enabled.setting_changed.connect(toggle_shot_injector)
	_setup_averages_ui()
	_setup_prev_shot_ui()
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
	
	# Style the RecButton initially
	var rec_btn = $HBoxContainer/RecButton
	if rec_btn != null:
		rec_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		apply_material_button_style(rec_btn, Color(0.2, 0.2, 0.2, 0.7))

	if not is_course_play:
		# Dynamically create Settings Button in the top-right corner
		var settings_btn = Button.new()
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
		settings_btn.pressed.connect(_on_toggle_settings_requested)
		$OverlayLayer.add_child(settings_btn)

		# Dynamically create vertical RightPanel under settings
		var right_panel = VBoxContainer.new()
		right_panel.name = "RightPanel"
		right_panel.anchor_left = 1.0
		right_panel.anchor_right = 1.0
		right_panel.offset_left = -210
		right_panel.offset_top = 90
		right_panel.offset_right = -30
		right_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right_panel.add_theme_constant_override("separation", 12)
		$OverlayLayer.add_child(right_panel)
		_right_panel = right_panel

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
		apply_material_button_style(menu_btn, Color(0.56, 0.22, 0.22, 0.85)) # Reddish
		menu_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
		toggles_container.add_child(menu_btn)

		# Distance Menu Button
		var dist_btn = Button.new()
		dist_btn.name = "HitDistanceButton"
		dist_btn.text = "🎯 Hit Distance"
		dist_btn.custom_minimum_size = Vector2(180, 40)
		apply_material_button_style(dist_btn, Color(0.6, 0.2, 0.6, 0.85))
		dist_btn.pressed.connect(func():
			var menu = null
			if _right_panel != null:
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

		# Stats Toggle Button
		var stats_btn = Button.new()
		stats_btn.name = "StatsButton"
		stats_btn.text = "📊 Hide Stats"
		stats_btn.custom_minimum_size = Vector2(180, 40)
		apply_material_button_style(stats_btn, Color(0.24, 0.46, 0.72, 0.85)) # Blue
		stats_btn.pressed.connect(func():
			toggle_stats_visibility()
			if is_stats_visible():
				stats_btn.text = "📊 Hide Stats"
			else:
				stats_btn.text = "📊 Show Stats"
		)
		toggles_container.add_child(stats_btn)

		# Map Toggle Button
		var map_btn = Button.new()
		map_btn.name = "MapButton"
		map_btn.text = "🗺 Toggle Map View"
		map_btn.custom_minimum_size = Vector2(180, 40)
		apply_material_button_style(map_btn, Color(0.18, 0.45, 0.25, 0.85)) # Forest green
		map_btn.pressed.connect(func():
			var p = get_parent()
			if p and p.has_method("_on_map_button_pressed"):
				p.call("_on_map_button_pressed")
		)
		toggles_container.add_child(map_btn)

		# Reparent ClubSelector to the bottom of RightPanel
		var club_sel = get_node_or_null("GridCanvas/ClubSelector")
		if club_sel != null:
			club_sel.reparent(toggles_container)
			club_sel.custom_minimum_size = Vector2(180, 40)
			club_sel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	else:
		$HBoxContainer.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass


func set_data(data: Dictionary) -> void:
	_last_shot_data = data.duplicate()
	if GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL:
		$GridCanvas/Distance.set_data(data["Distance"])
		$GridCanvas/Carry.set_data(data["Carry"])
		$GridCanvas/Side.set_data(data["Offline"])
		$GridCanvas/Apex.set_data(data["Apex"])
		$GridCanvas/Speed.set_units("mph")
		$GridCanvas/Speed.set_data(str(data["Speed"]))
		$GridCanvas/BackSpin.set_units("rpm")
		$GridCanvas/BackSpin.set_data(str(data["BackSpin"]))
		$GridCanvas/SideSpin.set_units("rpm")
		$GridCanvas/SideSpin.set_data(str(data["SideSpin"]))
		$GridCanvas/TotalSpin.set_units("rpm")
		$GridCanvas/TotalSpin.set_data(str(data["TotalSpin"]))
		$GridCanvas/SpinAxis.set_units("deg")
		$GridCanvas/SpinAxis.set_data(str(data["SpinAxis"]))
		$GridCanvas/VLA.set_data(_format_angle(data.get("VLA")))
		$GridCanvas/HLA.set_data(_format_angle(data.get("HLA")))
	else:
		$GridCanvas/Distance.set_data(data["Distance"])
		$GridCanvas/Carry.set_data(data["Carry"])
		$GridCanvas/Side.set_data(data["Offline"])
		$GridCanvas/Apex.set_data(data["Apex"])
		$GridCanvas/Speed.set_units("m/s")
		$GridCanvas/Speed.set_data(str(data["Speed"]))
		$GridCanvas/BackSpin.set_units("rpm")
		$GridCanvas/BackSpin.set_data(str(data["BackSpin"]))
		$GridCanvas/SideSpin.set_units("rpm")
		$GridCanvas/SideSpin.set_data(str(data["SideSpin"]))
		$GridCanvas/TotalSpin.set_units("rpm")
		$GridCanvas/TotalSpin.set_data(str(data["TotalSpin"]))
		$GridCanvas/SpinAxis.set_units("deg")
		$GridCanvas/SpinAxis.set_data(str(data["SpinAxis"]))
		$GridCanvas/VLA.set_data(_format_angle(data.get("VLA")))
		$GridCanvas/HLA.set_data(_format_angle(data.get("HLA")))


func _format_angle(value) -> String:
	# Accept both numeric values and placeholder strings (e.g., "---" after reset).
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return "%3.1f" % value
	return str(value)


func _on_rec_button_pressed() -> void:
	emit_signal("rec_button_pressed")


func _on_session_recorder_recording_state(value: bool) -> void:
	if value:
		$HBoxContainer/RecButton.text = "🔴 REC: On"
		apply_material_button_style($HBoxContainer/RecButton, Color(0.6, 0.15, 0.15, 0.85))
		$HBoxContainer/RecButton.tooltip_text = "Stop Recording Range Session"
		$SessionPopUp.open()
	else:
		$HBoxContainer/RecButton.text = "REC: Off"
		apply_material_button_style($HBoxContainer/RecButton, Color(0.2, 0.2, 0.2, 0.7))
		$HBoxContainer/RecButton.tooltip_text = "Start Recording Range Session"


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
	averages_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	averages_hbox.add_theme_constant_override("separation", 20)
	
	var averages_panel = PanelContainer.new()
	averages_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	averages_panel.custom_minimum_size = Vector2(0, 45)
	
	_avg_carry = Label.new()
	_avg_carry.text = "Avg Carry: ---"
	averages_hbox.add_child(_avg_carry)
	
	_avg_speed = Label.new()
	_avg_speed.text = "Avg Speed: ---"
	averages_hbox.add_child(_avg_speed)
	
	_avg_spin = Label.new()
	_avg_spin.text = "Avg Spin: ---"
	averages_hbox.add_child(_avg_spin)
	
	_avg_offline = Label.new()
	_avg_offline.text = "Avg Offline: ---"
	averages_hbox.add_child(_avg_offline)
	
	_avg_target_diff = Label.new()
	_avg_target_diff.text = "Avg +/- Target: ---"
	averages_hbox.add_child(_avg_target_diff)
	
	var view_prev_btn = Button.new()
	view_prev_btn.text = "View Previous Shot"
	view_prev_btn.pressed.connect(_on_view_prev_shot_pressed)
	averages_hbox.add_child(view_prev_btn)
	
	averages_panel.add_child(averages_hbox)
	averages_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	add_child(averages_panel)


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
	_prev_shot_popup.custom_minimum_size = Vector2(400, 300)
	_prev_shot_popup.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prev_shot_popup.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var title = Label.new()
	title.text = "Previous Shot Details"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	_prev_shot_data_label = Label.new()
	_prev_shot_data_label.text = "No shot data recorded."
	vbox.add_child(_prev_shot_data_label)
	
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): _prev_shot_popup.visible = false)
	vbox.add_child(close_btn)
	
	_prev_shot_popup.add_child(vbox)
	add_child(_prev_shot_popup)


func _on_view_prev_shot_pressed() -> void:
	if _last_shot_data.is_empty():
		_prev_shot_data_label.text = "No shot recorded in this session yet."
	else:
		var u_label := "yds" if GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL else "m"
		var s_label := "mph" if GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL else "m/s"
		
		var stats := []
		stats.append("Speed: %s %s" % [str(_last_shot_data.get("Speed", "---")), s_label])
		stats.append("VLA: %s deg" % str(_last_shot_data.get("VLA", "---")))
		stats.append("HLA: %s deg" % str(_last_shot_data.get("HLA", "---")))
		stats.append("Total Spin: %s rpm" % str(_last_shot_data.get("TotalSpin", "---")))
		stats.append("Spin Axis: %s deg" % str(_last_shot_data.get("SpinAxis", "---")))
		stats.append("Carry Distance: %s %s" % [str(_last_shot_data.get("Carry", "---")), u_label])
		stats.append("Total Distance: %s %s" % [str(_last_shot_data.get("Distance", "---")), u_label])
		stats.append("Offline: %s %s" % [str(_last_shot_data.get("Offline", "---")), u_label])
		stats.append("Club Path: %s deg" % str(_last_shot_data.get("ClubPath", "0.0")))
		
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
	style_normal.corner_radius_top_left = 22 # Half of 45 height
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
	if _right_panel != null:
		map_btn = _right_panel.get_node_or_null("TogglesContainer/MapButton")
		if map_btn == null:
			map_btn = _right_panel.get_node_or_null("MapButton")
	if map_btn != null:
		if is_aerial:
			map_btn.text = "👤 Return to Player"
		else:
			map_btn.text = "🗺 Toggle Map View"
