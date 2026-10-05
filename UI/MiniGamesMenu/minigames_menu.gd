extends Control

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
	
	# Main layout margin
	var main_margin = MarginContainer.new()
	main_margin.add_theme_constant_override("margin_left", 32)
	main_margin.add_theme_constant_override("margin_right", 32)
	main_margin.add_theme_constant_override("margin_top", 40)
	main_margin.add_theme_constant_override("margin_bottom", 40)
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
	tiles_hbox.add_theme_constant_override("separation", 16)
	tiles_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(tiles_hbox)
	
	# --- TILE 1: Putting Practice ---
	var putting_tile = _create_minigame_tile(
		"Putting Practice",
		"Practice your short game on a large, undulating green with 8 target holes (5, 10, 15, 20, 25, 30, 40, 50 ft). Includes single-player & turn-based multiplayer putting race (2+ players)!",
		"res://assets/images/menu/putting.jpg",
		func(): SceneManager.change_scene("res://Courses/Minigames/PuttingPractice/putting_practice.tscn")
	)
	tiles_hbox.add_child(putting_tile)
	
	# --- TILE 2: Chipping Practice ---
	var chipping_tile = _create_minigame_tile(
		"Chipping Practice",
		"Chip onto 7 custom floating island greens (25 to 200 yds) with retaining walls, sandtraps, and docks. Includes single-player & turn-based multiplayer island battle (2+ players)!",
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
		"Master shot shaping by curving around barrier walls placed every 25 yards. Launch through the open middle gate and draw left or fade right to land in wall target zones (50 to 300 yards). Includes single-player & turn-based multiplayer shape challenge (2+ players)!",
		"res://assets/images/menu/shape_control.jpg",
		func(): SceneManager.change_scene("res://Courses/Minigames/ShapePractice/shape_practice.tscn")
	)
	tiles_hbox.add_child(shape_tile)
	
	# --- TILE 5: Closest to Pin ---
	var ctp_tile = _create_minigame_tile(
		"Closest to Pin",
		"Land closest to the flag! A target randomly appears between 50–200 yards with concentric scoring rings (5 pts to 1 pt). Running distance totals & multiplayer support (2+ players)!",
		"res://assets/images/menu/closest_to_pin.jpg",
		func(): SceneManager.change_scene("res://Courses/Minigames/ClosestToPin/closest_to_pin.tscn")
	)
	tiles_hbox.add_child(ctp_tile)
	
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

	call_deferred("_grab_initial_focus")


func _grab_initial_focus() -> void:
	if not is_visible_in_tree():
		return
	if has_node("/root/KeybindingManager"):
		var km = get_node("/root/KeybindingManager")
		km.focus_first_control(self)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		SceneManager.change_scene("res://UI/MainMenu/main_menu.tscn")
		get_viewport().set_input_as_handled()


func _create_minigame_tile(title: String, desc: String, icon_path: String, on_click: Callable) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(295, 350)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true
	ThemeManager.apply_card_panel_style(panel, false, 12)
	panel.mouse_entered.connect(func(): ThemeManager.apply_card_panel_style(panel, true, 12))
	panel.mouse_exited.connect(func(): ThemeManager.apply_card_panel_style(panel, false, 12))
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	
	# Graphic texture
	var tex = TextureRect.new()
	tex.custom_minimum_size = Vector2(0, 105)
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
	name_lbl.add_theme_font_size_override("font_size", 21)
	name_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_lbl)
	
	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(desc_lbl)
	
	var play_btn = Button.new()
	play_btn.text = "PLAY"
	play_btn.custom_minimum_size = Vector2(0, 42)
	ThemeManager.apply_primary_button_style(play_btn)
	play_btn.pressed.connect(on_click)
	vbox.add_child(play_btn)
	
	return panel

