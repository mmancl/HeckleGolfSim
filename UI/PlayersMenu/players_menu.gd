extends Control

@onready var players_list_vbox = VBoxContainer.new()
@onready var stats_panel = PanelContainer.new()
@onready var new_player_input = LineEdit.new()

@onready var delete_confirm_dialog = ConfirmationDialog.new()
@onready var clear_confirm_dialog = ConfirmationDialog.new()
@onready var alert_dialog = AcceptDialog.new()

var selected_player_name: String = ""

func _ready() -> void:
	name = "PlayersMenu"
	
	# Background Cabo Texture
	var bg_texture = TextureRect.new()
	bg_texture.name = "Background"
	bg_texture.texture = load("res://assets/images/menu/cabo_openfairway_bnw.png")
	bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_texture.stretch_mode = TextureRect.STRETCH_SCALE
	bg_texture.anchor_left = 0.0
	bg_texture.anchor_right = 1.0
	bg_texture.anchor_top = 0.0
	bg_texture.anchor_bottom = 1.0
	bg_texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_texture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(bg_texture)
	
	# Semi-transparent dark green overlay
	var glass_panel = ColorRect.new()
	glass_panel.color = Color(0.05, 0.08, 0.05, 0.82)
	glass_panel.anchor_left = 0.0
	glass_panel.anchor_right = 1.0
	glass_panel.anchor_top = 0.0
	glass_panel.anchor_bottom = 1.0
	add_child(glass_panel)
	
	# Main layout margin
	var main_margin = MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 60)
	main_margin.add_theme_constant_override("margin_right", 60)
	main_margin.add_theme_constant_override("margin_top", 40)
	main_margin.add_theme_constant_override("margin_bottom", 40)
	main_margin.anchor_left = 0.0
	main_margin.anchor_right = 1.0
	main_margin.anchor_top = 0.0
	main_margin.anchor_bottom = 1.0
	add_child(main_margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 24)
	main_margin.add_child(main_vbox)
	
	# Header with Title & Back Button
	var header_hbox = HBoxContainer.new()
	main_vbox.add_child(header_hbox)
	
	var title_lbl = Label.new()
	title_lbl.text = "Player Profiles"
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	header_hbox.add_child(title_lbl)
	
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)
	
	var back_btn = Button.new()
	back_btn.text = "Main Menu"
	back_btn.icon = load("res://UI/MainMenu/images/menu.svg")
	back_btn.expand_icon = true
	back_btn.custom_minimum_size = Vector2(160, 48)
	back_btn.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_nav_button_style(back_btn)
	back_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn"))
	header_hbox.add_child(back_btn)
	
	# Horizontal Split for Left (List) and Right (Stats)
	var content_hbox = HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 30)
	main_vbox.add_child(content_hbox)
	
	# --- LEFT COLUMN: Players List & Registration ---
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(360, 0)
	left_vbox.add_theme_constant_override("separation", 16)
	content_hbox.add_child(left_vbox)
	
	var list_title = Label.new()
	list_title.text = "Players Registry"
	list_title.add_theme_font_size_override("font_size", 24)
	list_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	left_vbox.add_child(list_title)
	
	# ScrollContainer for player list
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(scroll, 28)
	left_vbox.add_child(scroll)
	
	players_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_list_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(players_list_vbox)
	
	# Registration HBox at the bottom of the left column
	var reg_section = VBoxContainer.new()
	reg_section.add_theme_constant_override("separation", 8)
	left_vbox.add_child(reg_section)
	
	var reg_lbl = Label.new()
	reg_lbl.text = "Create New Profile"
	reg_lbl.add_theme_font_size_override("font_size", 16)
	reg_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	reg_section.add_child(reg_lbl)
	
	var reg_hbox = HBoxContainer.new()
	reg_hbox.add_theme_constant_override("separation", 10)
	reg_section.add_child(reg_hbox)
	
	new_player_input.placeholder_text = "New Player Name"
	new_player_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_player_input.custom_minimum_size = Vector2(0, 48)
	new_player_input.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_input_style(new_player_input)
	reg_hbox.add_child(new_player_input)
	
	var register_btn = Button.new()
	register_btn.text = "Register"
	register_btn.custom_minimum_size = Vector2(100, 48)
	register_btn.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_primary_button_style(register_btn)
	register_btn.pressed.connect(_on_register_pressed)
	reg_hbox.add_child(register_btn)
	
	# --- RIGHT COLUMN: Stats & Profile Details ---
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_modal_style(stats_panel)
	content_hbox.add_child(stats_panel)
	
	# Dialog Setup
	delete_confirm_dialog.title = "Delete Player permanently"
	delete_confirm_dialog.dialog_text = "Are you sure you want to permanently delete this player profile? This will also wipe their club averages statistics, and cannot be undone."
	delete_confirm_dialog.min_size = Vector2(400, 150)
	delete_confirm_dialog.confirmed.connect(_confirm_delete_player)
	add_child(delete_confirm_dialog)
	
	clear_confirm_dialog.title = "Clear Ball History"
	clear_confirm_dialog.dialog_text = "Are you sure you want to clear this player's ball history? This resets all their club average carries, speed, spin, and target diff statistics, and cannot be undone."
	clear_confirm_dialog.min_size = Vector2(400, 150)
	clear_confirm_dialog.confirmed.connect(_confirm_clear_history)
	add_child(clear_confirm_dialog)
	
	alert_dialog.title = "Alert"
	alert_dialog.min_size = Vector2(300, 120)
	add_child(alert_dialog)
	
	# Load and render registered list
	_refresh_players_list()
	_render_empty_stats()

func _refresh_players_list() -> void:
	# Clear list
	for child in players_list_vbox.get_children():
		child.queue_free()
		
	var registered = MultiplayerManager.get_registered_players()
	
	if registered.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No players registered yet."
		empty_lbl.add_theme_font_size_override("font_size", 18)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		players_list_vbox.add_child(empty_lbl)
		return
		
	for p in registered:
		var p_name = p.get("name", "Player")
		var btn = Button.new()
		btn.text = p_name
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 20)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		# Styling player button
		var btn_style_normal = StyleBoxFlat.new()
		btn_style_normal.bg_color = Color(0.12, 0.18, 0.12, 0.5)
		btn_style_normal.corner_radius_top_left = 6
		btn_style_normal.corner_radius_top_right = 6
		btn_style_normal.corner_radius_bottom_left = 6
		btn_style_normal.corner_radius_bottom_right = 6
		btn_style_normal.content_margin_left = 16
		
		var btn_style_hover = btn_style_normal.duplicate()
		btn_style_hover.bg_color = Color(0.24, 0.46, 0.72, 0.6)
		
		var btn_style_pressed = btn_style_normal.duplicate()
		btn_style_pressed.bg_color = Color(0.24, 0.46, 0.72, 0.8)
		
		btn.add_theme_stylebox_override("normal", btn_style_normal)
		btn.add_theme_stylebox_override("hover", btn_style_hover)
		btn.add_theme_stylebox_override("pressed", btn_style_pressed)
		
		if p_name == selected_player_name:
			var btn_style_selected = btn_style_normal.duplicate()
			btn_style_selected.bg_color = Color(0.24, 0.46, 0.72, 0.7)
			btn_style_selected.border_width_left = 4
			btn_style_selected.border_color = Color(0.85, 0.65, 0.15)
			btn.add_theme_stylebox_override("normal", btn_style_selected)
			
		btn.pressed.connect(func(): _select_player(p_name))
		players_list_vbox.add_child(btn)

func _select_player(player_name: String) -> void:
	selected_player_name = player_name
	_refresh_players_list()
	_render_player_profile(player_name)

func _on_register_pressed() -> void:
	var name_text = new_player_input.text.strip_edges()
	if name_text.is_empty():
		alert_dialog.dialog_text = "Please enter a valid player name."
		alert_dialog.popup_centered()
		return
		
	var registered = MultiplayerManager.get_registered_players()
	for p in registered:
		if p.get("name", "").to_lower() == name_text.to_lower():
			alert_dialog.dialog_text = "A player with this name already exists."
			alert_dialog.popup_centered()
			return
			
	MultiplayerManager.register_player(name_text)
	new_player_input.clear()
	_select_player(name_text)

func _confirm_delete_player() -> void:
	if not selected_player_name.is_empty():
		MultiplayerManager.delete_player_permanently(selected_player_name)
		selected_player_name = ""
		_refresh_players_list()
		_render_empty_stats()

func _confirm_clear_history() -> void:
	if not selected_player_name.is_empty():
		MultiplayerManager.clear_player_ball_history(selected_player_name)
		_select_player(selected_player_name)

func _render_empty_stats() -> void:
	for child in stats_panel.get_children():
		child.queue_free()
		
	var center = CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_panel.add_child(center)
	
	var lbl = Label.new()
	lbl.text = "Select a player from the registry to view stats & manage profiles."
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	center.add_child(lbl)

func _render_player_profile(player_name: String) -> void:
	for child in stats_panel.get_children():
		child.queue_free()
		
	var stats = _calculate_player_stats(player_name)
	
	var main_layout = VBoxContainer.new()
	main_layout.add_theme_constant_override("separation", 14)
	main_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_panel.add_child(main_layout)
	
	# Header with Player Name
	var header_hbox = HBoxContainer.new()
	main_layout.add_child(header_hbox)
	
	var name_lbl = Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 34)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	header_hbox.add_child(name_lbl)
	
	# Divider
	var divider = ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 2)
	divider.color = Color(0.3, 0.4, 0.5, 0.4)
	main_layout.add_child(divider)
	
	# TabContainer for Stats and Achievements
	var tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 16)
	main_layout.add_child(tabs)
	
	# --- TAB 1: Career Overview ---
	var overview_vbox = VBoxContainer.new()
	overview_vbox.name = "📊 Overview & Records"
	overview_vbox.add_theme_constant_override("separation", 16)
	overview_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(overview_vbox)
	
	# Stats Grid Layout
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 36)
	grid.add_theme_constant_override("v_separation", 14)
	overview_vbox.add_child(grid)
	
	var add_stat_box = func(label_text: String, value_text: String):
		var vbox = VBoxContainer.new()
		
		var val_lbl = Label.new()
		val_lbl.text = value_text
		val_lbl.add_theme_font_size_override("font_size", 26)
		val_lbl.add_theme_color_override("font_color", Color(0.85, 0.65, 0.15))
		vbox.add_child(val_lbl)
		
		var lbl = Label.new()
		lbl.text = label_text
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vbox.add_child(lbl)
		
		grid.add_child(vbox)
		
	add_stat_box.call("Total Matches Played", str(stats["matches_played"]))
	add_stat_box.call("Multiplayer Wins", str(stats["wins"]))
	add_stat_box.call("Multiplayer Losses", str(stats["losses"]))
	add_stat_box.call("Multiplayer Ties", str(stats["ties"]))
	add_stat_box.call("Single Player Completed", str(stats["single_player_completed"]))
	
	var avg_par_str = "---"
	if stats["avg_to_par_valid"]:
		var val = stats["avg_to_par"]
		if val > 0:
			avg_par_str = "+%.1f" % val
		elif val < 0:
			avg_par_str = "%.1f" % val
		else:
			avg_par_str = "Even (E)"
	add_stat_box.call("Avg +/- Par per Round", avg_par_str)
	
	var drive_str = "---"
	if stats["longest_drive"] > 0:
		drive_str = "%.1f yds" % stats["longest_drive"]
	add_stat_box.call("Longest Drive", drive_str)
	
	var records_lbl = Label.new()
	records_lbl.text = "Best completed scores per course:"
	records_lbl.add_theme_font_size_override("font_size", 18)
	records_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	overview_vbox.add_child(records_lbl)
	
	var records_scroll = ScrollContainer.new()
	records_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(records_scroll, 28)
	overview_vbox.add_child(records_scroll)
	
	var records_vbox = VBoxContainer.new()
	records_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	records_scroll.add_child(records_vbox)
	
	var best_courses_dict = stats["best_courses"]
	if best_courses_dict.is_empty():
		var no_records = Label.new()
		no_records.text = "No completed course matches recorded yet."
		no_records.add_theme_font_size_override("font_size", 15)
		no_records.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		records_vbox.add_child(no_records)
	else:
		for course_name in best_courses_dict:
			var record_data = best_courses_dict[course_name]
			var record_lbl = Label.new()
			record_lbl.text = "  ⛳  %s:  %s" % [course_name, record_data["str"]]
			record_lbl.add_theme_font_size_override("font_size", 17)
			record_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
			records_vbox.add_child(record_lbl)
			
	# --- TAB 2: Achievements Gallery ---
	var ach_vbox = VBoxContainer.new()
	ach_vbox.name = "🏆 Achievements"
	ach_vbox.add_theme_constant_override("separation", 12)
	ach_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(ach_vbox)
	
	var all_ach = AchievementManager.get_all_achievements()
	var unlocked_map = AchievementManager.get_unlocked_achievements(player_name)
	var unlocked_count = unlocked_map.size()
	var total_count = all_ach.size()
	var percent = int((float(unlocked_count) / float(total_count)) * 100.0) if total_count > 0 else 0
	
	var ach_summary_lbl = Label.new()
	ach_summary_lbl.text = "Unlocked: %d / %d (%d%%)" % [unlocked_count, total_count, percent]
	ach_summary_lbl.add_theme_font_size_override("font_size", 18)
	ach_summary_lbl.add_theme_color_override("font_color", Color(0.95, 0.76, 0.2))
	ach_vbox.add_child(ach_summary_lbl)
	
	var ach_scroll = ScrollContainer.new()
	ach_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(ach_scroll, 28)
	ach_vbox.add_child(ach_scroll)
	
	var ach_grid = GridContainer.new()
	ach_grid.columns = 2
	ach_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ach_grid.add_theme_constant_override("h_separation", 14)
	ach_grid.add_theme_constant_override("v_separation", 12)
	ach_scroll.add_child(ach_grid)
	
	for ach in all_ach:
		var ach_id = ach.get("id", "")
		var is_unlocked = unlocked_map.has(ach_id)
		
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(280, 80)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var card_style = StyleBoxFlat.new()
		card_style.corner_radius_top_left = 8
		card_style.corner_radius_top_right = 8
		card_style.corner_radius_bottom_left = 8
		card_style.corner_radius_bottom_right = 8
		card_style.content_margin_left = 10
		card_style.content_margin_top = 8
		card_style.content_margin_right = 10
		card_style.content_margin_bottom = 8
		
		if is_unlocked:
			card_style.bg_color = Color(0.12, 0.2, 0.12, 0.85)
			card_style.border_width_left = 2
			card_style.border_width_top = 2
			card_style.border_width_right = 2
			card_style.border_width_bottom = 2
			card_style.border_color = Color(0.95, 0.76, 0.2, 0.9)
		else:
			card_style.bg_color = Color(0.06, 0.08, 0.06, 0.45)
			card_style.border_width_left = 1
			card_style.border_width_top = 1
			card_style.border_width_right = 1
			card_style.border_width_bottom = 1
			card_style.border_color = Color(0.2, 0.25, 0.2, 0.4)
			
		card.add_theme_stylebox_override("panel", card_style)
		
		var card_hbox = HBoxContainer.new()
		card_hbox.add_theme_constant_override("separation", 10)
		card.add_child(card_hbox)
		
		var icon_rect = TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(52, 52)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		var b_path = ach.get("badge_path", "")
		if ResourceLoader.exists(b_path):
			icon_rect.texture = load(b_path)
			
		if not is_unlocked:
			icon_rect.modulate = Color(0.35, 0.35, 0.35, 0.45)
			
		card_hbox.add_child(icon_rect)
		
		var info_vbox = VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 2)
		card_hbox.add_child(info_vbox)
		
		var title_l = Label.new()
		title_l.text = ach.get("title", "Achievement")
		title_l.add_theme_font_size_override("font_size", 15)
		if is_unlocked:
			title_l.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
		else:
			title_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		info_vbox.add_child(title_l)
		
		var desc_l = Label.new()
		desc_l.text = ach.get("description", "")
		desc_l.add_theme_font_size_override("font_size", 12)
		desc_l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7) if is_unlocked else Color(0.45, 0.45, 0.45))
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_vbox.add_child(desc_l)
		
		var status_l = Label.new()
		if is_unlocked:
			var unix_t = unlocked_map[ach_id].get("unlocked_at", 0)
			var date_str = Time.get_date_string_from_unix_time(int(unix_t)) if unix_t > 0 else ""
			status_l.text = "✓ Unlocked %s" % date_str if not date_str.is_empty() else "✓ Unlocked"
			status_l.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		else:
			status_l.text = "🔒 Locked"
			status_l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		status_l.add_theme_font_size_override("font_size", 11)
		info_vbox.add_child(status_l)
		
		ach_grid.add_child(card)
		
	# --- TAB 3: Video Swing Recommendations ---
	var swing_vbox = VBoxContainer.new()
	swing_vbox.name = "🎯 Swing Recommendations"
	swing_vbox.add_theme_constant_override("separation", 14)
	swing_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swing_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(swing_vbox)

	var p_issues = MultiplayerManager.get_player_swing_issues(player_name)
	var all_time_issues: Dictionary = p_issues.get("all_time", {})
	var monthly_issues: Dictionary = p_issues.get("monthly", {})
	var date_dict = Time.get_date_dict_from_system()
	var current_month_key = "%04d-%02d" % [date_dict.year, date_dict.month]
	var current_month_name = MultiplayerManager.get_month_display_name(current_month_key)

	var swing_scroll = ScrollContainer.new()
	swing_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(swing_scroll, 28)
	swing_vbox.add_child(swing_scroll)

	var swing_content_vbox = VBoxContainer.new()
	swing_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swing_content_vbox.add_theme_constant_override("separation", 16)
	swing_scroll.add_child(swing_content_vbox)

	if all_time_issues.is_empty():
		var empty_swing_lbl = Label.new()
		empty_swing_lbl.text = "No video swing recommendations recorded yet.\nTurn on Golfer Camera video during Driving Range, Course Play, or Practice to track swing fixes!"
		empty_swing_lbl.add_theme_font_size_override("font_size", 16)
		empty_swing_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		swing_content_vbox.add_child(empty_swing_lbl)
	else:
		# Monthly section
		var cur_month_data: Dictionary = monthly_issues.get(current_month_key, {})
		var month_hdr = Label.new()
		month_hdr.text = "📅 Current Month Running Totals (%s)" % current_month_name
		month_hdr.add_theme_font_size_override("font_size", 18)
		month_hdr.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		swing_content_vbox.add_child(month_hdr)

		if cur_month_data.is_empty():
			var no_m = Label.new()
			no_m.text = "No swing recommendations recorded for %s." % current_month_name
			no_m.add_theme_font_size_override("font_size", 14)
			no_m.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			swing_content_vbox.add_child(no_m)
		else:
			var m_grid = GridContainer.new()
			m_grid.columns = 2
			m_grid.add_theme_constant_override("h_separation", 16)
			m_grid.add_theme_constant_override("v_separation", 10)
			swing_content_vbox.add_child(m_grid)

			for issue in cur_month_data:
				var card = _create_issue_card(issue, int(cur_month_data[issue]), "This Month")
				m_grid.add_child(card)

		# All-Time Section
		var at_hdr = Label.new()
		at_hdr.text = "🏆 All-Time Running Totals"
		at_hdr.add_theme_font_size_override("font_size", 18)
		at_hdr.add_theme_color_override("font_color", Color(0.95, 0.76, 0.2))
		swing_content_vbox.add_child(at_hdr)

		var at_grid = GridContainer.new()
		at_grid.columns = 2
		at_grid.add_theme_constant_override("h_separation", 16)
		at_grid.add_theme_constant_override("v_separation", 10)
		swing_content_vbox.add_child(at_grid)

		for issue in all_time_issues:
			var card = _create_issue_card(issue, int(all_time_issues[issue]), "All Time")
			at_grid.add_child(card)

	# Actions row at the bottom of the right stats panel
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 16)
	main_layout.add_child(actions_hbox)
	
	var spacer_act = Control.new()
	spacer_act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_hbox.add_child(spacer_act)

	var email_report_btn = Button.new()
	email_report_btn.text = "✉ Email Profile Report"
	email_report_btn.custom_minimum_size = Vector2(200, 48)
	email_report_btn.add_theme_font_size_override("font_size", 15)
	ThemeManager.apply_primary_button_style(email_report_btn, 6)
	email_report_btn.pressed.connect(func(): _email_player_profile_report(player_name))
	actions_hbox.add_child(email_report_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "🧹 Clear Ball History"
	clear_btn.custom_minimum_size = Vector2(200, 48)
	clear_btn.add_theme_font_size_override("font_size", 15)
	ThemeManager.apply_secondary_button_style(clear_btn, 6)
	clear_btn.pressed.connect(func(): clear_confirm_dialog.popup_centered())
	actions_hbox.add_child(clear_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "❌ Delete Profile permanently"
	delete_btn.custom_minimum_size = Vector2(240, 48)
	delete_btn.add_theme_font_size_override("font_size", 15)
	ThemeManager.apply_danger_button_style(delete_btn, 6)
	delete_btn.pressed.connect(func(): delete_confirm_dialog.popup_centered())
	actions_hbox.add_child(delete_btn)

func _create_issue_card(issue_name: String, count: int, period_label: String) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(260, 60)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var card_style = StyleBoxFlat.new()
	card_style.bg_color = Color(0.1, 0.14, 0.18, 0.8)
	card_style.corner_radius_top_left = 8
	card_style.corner_radius_top_right = 8
	card_style.corner_radius_bottom_left = 8
	card_style.corner_radius_bottom_right = 8
	card_style.content_margin_left = 12
	card_style.content_margin_top = 8
	card_style.content_margin_right = 12
	card_style.content_margin_bottom = 8
	card_style.border_width_left = 2
	card_style.border_color = Color(0.3, 0.7, 0.9, 0.6)
	card.add_theme_stylebox_override("panel", card_style)
	
	var hbox = HBoxContainer.new()
	card.add_child(hbox)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = issue_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(name_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = period_label
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(sub_lbl)
	
	var cnt_lbl = Label.new()
	cnt_lbl.text = str(count)
	cnt_lbl.add_theme_font_size_override("font_size", 24)
	cnt_lbl.add_theme_color_override("font_color", Color(0.85, 0.65, 0.15))
	hbox.add_child(cnt_lbl)
	
	return card

func _email_player_profile_report(player_name: String) -> void:
	var subject = "Heckle Golf Simulator - Player Profile & Swing Report: " + player_name
	var stats = MultiplayerManager.calculate_player_stats(player_name)
	
	var body = "PLAYER PROFILE REPORT: %s\n" % player_name
	body += "=============================================\n"
	body += "Total Matches Played: %d\n" % stats.get("matches_played", 0)
	body += "Multiplayer Wins: %d | Losses: %d | Ties: %d\n" % [stats.get("wins", 0), stats.get("losses", 0), stats.get("ties", 0)]
	body += "Single Player Completed: %d\n" % stats.get("single_player_completed", 0)
	if stats.get("longest_drive", 0.0) > 0:
		body += "Longest Drive: %.1f yds\n" % stats["longest_drive"]
	body += "\n"
	
	body += MultiplayerManager.format_player_swing_issues_summary(player_name)
	
	var mailto_url = "mailto:?subject=" + subject.uri_encode() + "&body=" + body.uri_encode()
	OS.shell_open(mailto_url)

func _calculate_player_stats(player_name: String) -> Dictionary:
	return MultiplayerManager.calculate_player_stats(player_name)
