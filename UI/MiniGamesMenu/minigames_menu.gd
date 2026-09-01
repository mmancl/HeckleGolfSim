extends Control

var _music_btn: Button = null

func _ready() -> void:
	name = "MiniGamesMenu"
	
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
	
	# Semi-transparent dark blue-gray overlay
	var glass_panel = ColorRect.new()
	glass_panel.color = Color(0.04, 0.08, 0.12, 0.85)
	glass_panel.anchor_left = 0.0
	glass_panel.anchor_right = 1.0
	glass_panel.anchor_top = 0.0
	glass_panel.anchor_bottom = 1.0
	add_child(glass_panel)
	
	# Top Right Header Strip for Quick Controls (Music Toggle)
	var top_strip = MarginContainer.new()
	top_strip.anchor_left = 0.0
	top_strip.anchor_right = 1.0
	top_strip.anchor_top = 0.0
	top_strip.anchor_bottom = 0.0
	top_strip.offset_left = 30
	top_strip.offset_top = 24
	top_strip.offset_right = -30
	top_strip.offset_bottom = 74
	add_child(top_strip)
	
	var top_hbox = HBoxContainer.new()
	top_hbox.alignment = BoxContainer.ALIGNMENT_END
	top_strip.add_child(top_hbox)
	
	_music_btn = Button.new()
	_music_btn.name = "MusicToggleButton"
	_music_btn.text = ""
	_music_btn.custom_minimum_size = Vector2(44, 44)
	_music_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_music_btn.expand_icon = true
	ThemeManager.apply_nav_button_style(_music_btn, 6)
	_music_btn.pressed.connect(_toggle_music)
	top_hbox.add_child(_music_btn)
	
	# Main layout margin
	var main_margin = MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 60)
	main_margin.add_theme_constant_override("margin_right", 60)
	main_margin.add_theme_constant_override("margin_top", 60)
	main_margin.add_theme_constant_override("margin_bottom", 60)
	main_margin.anchor_left = 0.0
	main_margin.anchor_right = 1.0
	main_margin.anchor_top = 0.0
	main_margin.anchor_bottom = 1.0
	add_child(main_margin)
	
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 40)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_margin.add_child(main_vbox)
	
	# Header
	var title_lbl = Label.new()
	title_lbl.text = "MINI GAMES"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 48)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title_lbl.add_theme_constant_override("outline_size", 4)
	title_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	main_vbox.add_child(title_lbl)
	
	# Subtitle
	var subtitle_lbl = Label.new()
	subtitle_lbl.text = "Select a practice minigame to begin"
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.add_theme_font_size_override("font_size", 20)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	main_vbox.add_child(subtitle_lbl)
	
	# Grid/Container for Minigame Selection Tiles
	var tiles_hbox = HBoxContainer.new()
	tiles_hbox.add_theme_constant_override("separation", 24)
	tiles_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(tiles_hbox)
	
	# --- TILE 1: Putting Practice ---
	var putting_tile = _create_minigame_tile(
		"Putting Practice",
		"Practice your short game on a large, undulating green with 8 target holes (5, 10, 15, 20, 25, 30, 40, 50 ft) and automatic reset after each putt.",
		"res://assets/images/menu/putting.jpg",
		func(): SceneManager.change_scene("res://Courses/Minigames/PuttingPractice/putting_practice.tscn")
	)
	tiles_hbox.add_child(putting_tile)
	
	# --- TILE 2: Chipping Practice ---
	var chipping_tile = _create_minigame_tile(
		"Chipping Practice",
		"Chip onto 7 custom-crafted floating island golf course greens (25, 50, 75, 100, 125, 150, 200 yards) complete with wood retaining walls, sandtraps, and boat docks!",
		"res://assets/images/menu/chipping.jpg",
		func(): SceneManager.change_scene("res://Courses/Minigames/Chipping/chipping.tscn")
	)
	tiles_hbox.add_child(chipping_tile)
	
	# --- TILE 3: Loft Control ---
	var loft_tile = _create_minigame_tile(
		"Loft Control",
		"Shatter a 3x3 grid of glass panes on a target wall 100 yards out! Control your vertical launch angle and elevation to break all 9 panes of glass.",
		"res://assets/images/menu/loft_control.jpg",
		func(): SceneManager.change_scene("res://Courses/Minigames/LoftControl/loft_control.tscn")
	)
	tiles_hbox.add_child(loft_tile)
	
	# --- TILE 4: Shape Practice (Draw & Fade) ---
	var shape_tile = _create_minigame_tile(
		"Shape Practice",
		"Master shot shaping by curving around barrier walls placed every 25 yards. Launch through the open middle gate and draw left or fade right to land on greens from 50 to 300 yards!",
		"res://assets/images/menu/shape_control.jpg",
		func(): SceneManager.change_scene("res://Courses/Minigames/ShapePractice/shape_practice.tscn")
	)
	tiles_hbox.add_child(shape_tile)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer)
	
	# Back Button
	var back_btn = Button.new()
	back_btn.text = "Back to Main Menu"
	back_btn.custom_minimum_size = Vector2(240, 48)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_nav_button_style(back_btn)
	back_btn.pressed.connect(func(): SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn") )
	main_vbox.add_child(back_btn)

	_update_music_button()
	GlobalSettings.range_settings.minigame_music_enabled.setting_changed.connect(func(_val): _update_music_button())


func _toggle_music() -> void:
	var current = GlobalSettings.range_settings.minigame_music_enabled.value
	GlobalSettings.range_settings.minigame_music_enabled.set_value(not current)
	_update_music_button()


func _update_music_button() -> void:
	if _music_btn == null:
		return
	var is_enabled: bool = GlobalSettings.range_settings.minigame_music_enabled.value
	if is_enabled:
		if ResourceLoader.exists("res://assets/images/menu/music_on.svg"):
			_music_btn.icon = load("res://assets/images/menu/music_on.svg")
		_music_btn.tooltip_text = "Music: Playing (Click to mute)"
		ThemeManager.apply_nav_button_style(_music_btn, 6)
	else:
		if ResourceLoader.exists("res://assets/images/menu/music_off.svg"):
			_music_btn.icon = load("res://assets/images/menu/music_off.svg")
		_music_btn.tooltip_text = "Music: Muted (Click to play)"
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.35, 0.18, 0.18, 0.8)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_right = 6
		style.corner_radius_bottom_left = 6
		_music_btn.add_theme_stylebox_override("normal", style)
		_music_btn.add_theme_stylebox_override("hover", style)
		_music_btn.add_theme_stylebox_override("pressed", style)


func _create_minigame_tile(title: String, desc: String, icon_path: String, on_click: Callable) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(330, 320)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.clip_contents = true
	ThemeManager.apply_card_panel_style(panel, false, 12)
	panel.mouse_entered.connect(func(): ThemeManager.apply_card_panel_style(panel, true, 12))
	panel.mouse_exited.connect(func(): ThemeManager.apply_card_panel_style(panel, false, 12))
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)
	
	# Graphic texture
	var tex = TextureRect.new()
	tex.custom_minimum_size = Vector2(0, 100)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tex.clip_contents = true
	if ResourceLoader.exists(icon_path):
		tex.texture = load(icon_path)
	elif FileAccess.file_exists(icon_path):
		var img = Image.load_from_file(icon_path)
		if img != null:
			tex.texture = ImageTexture.create_from_image(img)
	
	vbox.add_child(tex)
	
	var name_lbl = Label.new()
	name_lbl.text = title
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	
	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_lbl)
	
	var play_btn = Button.new()
	play_btn.text = "PLAY"
	play_btn.custom_minimum_size = Vector2(0, 44)
	ThemeManager.apply_primary_button_style(play_btn)
	play_btn.pressed.connect(on_click)
	vbox.add_child(play_btn)
	
	return panel


func _apply_premium_button_style(btn: Button, normal_color: Color, hover_color: Color):
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = normal_color
	style_normal.corner_radius_top_left = 6
	style_normal.corner_radius_top_right = 6
	style_normal.corner_radius_bottom_right = 6
	style_normal.corner_radius_bottom_left = 6
	style_normal.border_width_left = 1
	style_normal.border_width_top = 1
	style_normal.border_width_right = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(1, 1, 1, 0.15)
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = hover_color
	style_hover.corner_radius_top_left = 6
	style_hover.corner_radius_top_right = 6
	style_hover.corner_radius_bottom_right = 6
	style_hover.corner_radius_bottom_left = 6
	style_hover.border_width_left = 1
	style_hover.border_width_top = 1
	style_hover.border_width_right = 1
	style_hover.border_width_bottom = 1
	style_hover.border_color = Color(1, 1, 1, 0.3)
	
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_hover)
	btn.add_theme_stylebox_override("focus", style_normal)
	btn.add_theme_color_override("font_color", Color.WHITE)
