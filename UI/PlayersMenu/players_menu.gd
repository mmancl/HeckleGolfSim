extends Control

const ClubDeliveryVisuals = preload("res://UI/GolferCamera/club_delivery_visuals.gd")

const CLUB_CATEGORIES = [
	{
		"category": "Drivers & Fairway Woods",
		"clubs": [
			{"code": "Dr", "name": "Driver"},
			{"code": "3w", "name": "3 Wood"},
			{"code": "5w", "name": "5 Wood"}
		]
	},
	{
		"category": "Hybrids",
		"clubs": [
			{"code": "2H", "name": "2 Hybrid"},
			{"code": "3H", "name": "3 Hybrid"},
			{"code": "4H", "name": "4 Hybrid"}
		]
	},
	{
		"category": "Irons",
		"clubs": [
			{"code": "1i", "name": "1 Iron"},
			{"code": "2i", "name": "2 Iron"},
			{"code": "3i", "name": "3 Iron"},
			{"code": "4i", "name": "4 Iron"},
			{"code": "5i", "name": "5 Iron"},
			{"code": "6i", "name": "6 Iron"},
			{"code": "7i", "name": "7 Iron"},
			{"code": "8i", "name": "8 Iron"},
			{"code": "9i", "name": "9 Iron"}
		]
	},
	{
		"category": "Wedges",
		"clubs": [
			{"code": "Pw", "name": "Pitching Wedge"},
			{"code": "Gw", "name": "Gap Wedge"},
			{"code": "Sw", "name": "Sand Wedge"},
			{"code": "Lw", "name": "Lob Wedge"}
		]
	},
	{
		"category": "Putters",
		"clubs": [
			{"code": "Pt", "name": "Putter"}
		]
	}
]

const STANDARD_14_BAG: Array[String] = [
	"Dr", "3w", "5w", "4H", "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"
]

@onready var players_list_vbox = VBoxContainer.new()
@onready var stats_panel = PanelContainer.new()
@onready var new_player_input = LineEdit.new()
@onready var new_player_email_input = LineEdit.new()

@onready var delete_confirm_dialog = ConfirmationDialog.new()
@onready var clear_confirm_dialog = ConfirmationDialog.new()
@onready var clear_club_confirm_dialog = ConfirmationDialog.new()
@onready var alert_dialog = AcceptDialog.new()

@onready var avatar_picker_dialog = ConfirmationDialog.new()
@onready var edit_profile_dialog = ConfirmationDialog.new()

var selected_player_name: String = ""
var pending_club_to_clear: String = ""
var show_only_active_clubs: bool = true
var last_active_tab_index: int = 0

var new_player_avatar_path: String = ""
var avatar_preview_btn: Button = Button.new()
var new_player_tee_opt: OptionButton = OptionButton.new()
var avatar_picker_callback: Callable
var avatar_picker_selected_path: String = ""
var avatar_picker_content: VBoxContainer = VBoxContainer.new()
var avatar_picker_buttons: Array = []

var edit_profile_player_name: String = ""
var edit_profile_email_input: LineEdit = LineEdit.new()
var edit_profile_avatar_path: String = ""
var edit_profile_tee_opt: OptionButton = OptionButton.new()
var edit_profile_content: VBoxContainer = VBoxContainer.new()
var edit_profile_avatar_preview_container: Control = null

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
	
	new_player_input.placeholder_text = "New Player Name"
	new_player_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_player_input.custom_minimum_size = Vector2(0, 50)
	new_player_input.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_input_style(new_player_input)
	new_player_input.text_submitted.connect(func(_t): _on_register_pressed())
	reg_section.add_child(new_player_input)

	new_player_email_input.placeholder_text = "Optional Email Address"
	new_player_email_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_player_email_input.custom_minimum_size = Vector2(0, 50)
	new_player_email_input.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_input_style(new_player_email_input)
	new_player_email_input.text_submitted.connect(func(_t): _on_register_pressed())
	reg_section.add_child(new_player_email_input)

	new_player_tee_opt.clear()
	new_player_tee_opt.add_item("Preferred Tee: None", 0)
	new_player_tee_opt.add_item("Preferred Tee: Blue", 1)
	new_player_tee_opt.add_item("Preferred Tee: Red", 2)
	new_player_tee_opt.add_item("Preferred Tee: White", 3)
	new_player_tee_opt.add_item("Preferred Tee: Black", 4)
	new_player_tee_opt.add_item("Preferred Tee: Gold", 5)
	new_player_tee_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_player_tee_opt.custom_minimum_size = Vector2(0, 50)
	ThemeManager.apply_option_button_style(new_player_tee_opt, 17, Vector2(0, 50))
	reg_section.add_child(new_player_tee_opt)

	var reg_btn_hbox = HBoxContainer.new()
	reg_btn_hbox.add_theme_constant_override("separation", 10)
	reg_section.add_child(reg_btn_hbox)

	avatar_preview_btn.text = "Avatar: None"
	avatar_preview_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar_preview_btn.custom_minimum_size = Vector2(0, 50)
	avatar_preview_btn.add_theme_font_size_override("font_size", 17)
	ThemeManager.apply_secondary_button_style(avatar_preview_btn)
	avatar_preview_btn.pressed.connect(func():
		_open_avatar_picker(new_player_avatar_path, func(chosen):
			new_player_avatar_path = chosen
			_update_new_player_avatar_preview()
		)
	)
	reg_btn_hbox.add_child(avatar_preview_btn)
	
	var register_btn = Button.new()
	register_btn.text = "Register"
	register_btn.custom_minimum_size = Vector2(120, 50)
	register_btn.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_primary_button_style(register_btn)
	register_btn.pressed.connect(_on_register_pressed)
	reg_btn_hbox.add_child(register_btn)
	
	# --- RIGHT COLUMN: Stats & Profile Details ---
	stats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_modal_style(stats_panel)
	content_hbox.add_child(stats_panel)
	
	# Dialog Setup
	delete_confirm_dialog.title = "Delete Player permanently"
	delete_confirm_dialog.dialog_text = "Are you sure you want to permanently delete this player profile? This will also wipe their club averages statistics, and cannot be undone."
	delete_confirm_dialog.min_size = Vector2(480, 180)
	ThemeManager.apply_dialog_style(delete_confirm_dialog)
	delete_confirm_dialog.confirmed.connect(_confirm_delete_player)
	add_child(delete_confirm_dialog)
	
	clear_confirm_dialog.title = "Clear All Ball History"
	clear_confirm_dialog.dialog_text = "Are you sure you want to clear this player's entire ball history across all clubs? This resets all their club average carries, speed, spin, and target diff statistics, and cannot be undone."
	clear_confirm_dialog.min_size = Vector2(500, 180)
	ThemeManager.apply_dialog_style(clear_confirm_dialog)
	clear_confirm_dialog.confirmed.connect(_confirm_clear_history)
	add_child(clear_confirm_dialog)
	
	clear_club_confirm_dialog.title = "Clear Club Shot Data"
	clear_club_confirm_dialog.min_size = Vector2(500, 180)
	ThemeManager.apply_dialog_style(clear_club_confirm_dialog)
	clear_club_confirm_dialog.confirmed.connect(_confirm_clear_club_shot_data)
	add_child(clear_club_confirm_dialog)
	
	alert_dialog.title = "Alert"
	alert_dialog.min_size = Vector2(380, 160)
	ThemeManager.apply_dialog_style(alert_dialog)
	add_child(alert_dialog)

	# Avatar Picker Dialog
	avatar_picker_dialog.title = "Select Player Avatar"
	avatar_picker_dialog.min_size = Vector2(620, 540)
	ThemeManager.apply_dialog_style(avatar_picker_dialog, Vector2(160, 52), 18)
	avatar_picker_dialog.confirmed.connect(_on_avatar_picker_confirmed)
	avatar_picker_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avatar_picker_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar_picker_content.add_theme_constant_override("separation", 12)
	avatar_picker_dialog.add_child(avatar_picker_content)
	add_child(avatar_picker_dialog)
	
	# Edit Profile Dialog
	edit_profile_dialog.title = "Edit Player Profile"
	edit_profile_dialog.min_size = Vector2(580, 500)
	ThemeManager.apply_dialog_style(edit_profile_dialog, Vector2(160, 52), 18)
	edit_profile_dialog.confirmed.connect(_on_edit_profile_confirmed)
	edit_profile_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_profile_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit_profile_content.add_theme_constant_override("separation", 14)
	edit_profile_dialog.add_child(edit_profile_content)
	add_child(edit_profile_dialog)
	
	# Load and render registered list
	_refresh_players_list()
	_render_empty_stats()

func _refresh_players_list() -> void:
	for child in players_list_vbox.get_children():
		child.queue_free()
		
	var registered = MultiplayerManager.get_registered_players()
	
	if registered.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No players registered yet."
		empty_lbl.add_theme_font_size_override("font_size", 16)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		players_list_vbox.add_child(empty_lbl)
		return
		
	for p in registered:
		var p_name = p.get("name", "Player")
		var p_avatar = p.get("avatar", "")
		var btn = Button.new()
		btn.text = "  " + p_name
		btn.custom_minimum_size = Vector2(0, 48)
		btn.add_theme_font_size_override("font_size", 18)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		if not p_avatar.is_empty() and ResourceLoader.exists(p_avatar):
			btn.icon = load(p_avatar)
			btn.expand_icon = true
		
		var btn_style_normal = StyleBoxFlat.new()
		btn_style_normal.bg_color = Color(0.12, 0.18, 0.12, 0.5)
		btn_style_normal.corner_radius_top_left = 6
		btn_style_normal.corner_radius_top_right = 6
		btn_style_normal.corner_radius_bottom_left = 6
		btn_style_normal.corner_radius_bottom_right = 6
		btn_style_normal.content_margin_left = 12
		btn_style_normal.content_margin_right = 12
		
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
			
	var email_text = new_player_email_input.text.strip_edges()
	var pref_tee = ""
	if new_player_tee_opt != null and new_player_tee_opt.selected > 0:
		var raw_t = new_player_tee_opt.get_item_text(new_player_tee_opt.selected)
		pref_tee = raw_t.replace("Preferred Tee: ", "").strip_edges()
	MultiplayerManager.register_player(name_text, email_text, new_player_avatar_path, [], pref_tee)
	new_player_input.clear()
	new_player_email_input.clear()
	new_player_avatar_path = ""
	new_player_tee_opt.selected = 0
	_update_new_player_avatar_preview()
	_select_player(name_text)

func _update_new_player_avatar_preview() -> void:
	if new_player_avatar_path.is_empty():
		avatar_preview_btn.text = "Avatar: None"
		avatar_preview_btn.icon = null
	else:
		var name_str = ""
		for av in MultiplayerManager.AVAILABLE_AVATARS:
			if av["path"] == new_player_avatar_path:
				name_str = av["name"]
				break
		avatar_preview_btn.text = "Avatar: " + name_str
		if ResourceLoader.exists(new_player_avatar_path):
			avatar_preview_btn.icon = load(new_player_avatar_path)
			avatar_preview_btn.expand_icon = true

func _open_avatar_picker(current_path: String, callback: Callable) -> void:
	avatar_picker_callback = callback
	avatar_picker_selected_path = current_path
	_build_avatar_picker_ui()
	avatar_picker_dialog.popup_centered()

func _on_avatar_picker_confirmed() -> void:
	if avatar_picker_callback.is_valid():
		avatar_picker_callback.call(avatar_picker_selected_path)

func _build_avatar_picker_ui() -> void:
	for child in avatar_picker_content.get_children():
		child.queue_free()
	avatar_picker_buttons.clear()

	var desc_lbl = Label.new()
	desc_lbl.text = "Select an avatar to display in-game instead of your colored initial circle:"
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	avatar_picker_content.add_child(desc_lbl)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 360)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	avatar_picker_content.add_child(scroll)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	# Option 0: No avatar / default initials
	var none_btn = _create_avatar_picker_option("", "Default Initial", null)
	grid.add_child(none_btn)

	# Options 1-10
	for av in MultiplayerManager.AVAILABLE_AVATARS:
		var tex: Texture2D = null
		if ResourceLoader.exists(av["path"]):
			tex = load(av["path"])
		var av_btn = _create_avatar_picker_option(av["path"], av["name"], tex)
		grid.add_child(av_btn)

	_update_avatar_picker_highlights()

func _create_avatar_picker_option(path: String, title: String, tex: Texture2D) -> Button:
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(165, 95)
	btn.focus_mode = Control.FOCUS_NONE
	
	var vb = VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	btn.add_child(vb)

	if tex != null:
		var trect = TextureRect.new()
		trect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		trect.texture = tex
		trect.custom_minimum_size = Vector2(46, 46)
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(trect)
	else:
		var circ = PanelContainer.new()
		circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
		circ.custom_minimum_size = Vector2(44, 44)
		circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var cs = StyleBoxFlat.new()
		cs.bg_color = Color(0.24, 0.46, 0.72)
		cs.corner_radius_top_left = 22
		cs.corner_radius_top_right = 22
		cs.corner_radius_bottom_left = 22
		cs.corner_radius_bottom_right = 22
		circ.add_theme_stylebox_override("panel", cs)
		var clbl = Label.new()
		clbl.text = "ABC"
		clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		clbl.add_theme_font_size_override("font_size", 14)
		circ.add_child(clbl)
		vb.add_child(circ)

	var lbl = Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	vb.add_child(lbl)

	btn.pressed.connect(func():
		avatar_picker_selected_path = path
		_update_avatar_picker_highlights()
	)

	avatar_picker_buttons.append({"btn": btn, "path": path})
	return btn

func _update_avatar_picker_highlights() -> void:
	for entry in avatar_picker_buttons:
		var btn = entry["btn"] as Button
		var path = entry["path"] as String
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		if path == avatar_picker_selected_path:
			style.bg_color = Color(0.18, 0.35, 0.25, 0.9)
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
			style.border_color = Color(0.85, 0.75, 0.2)
		else:
			style.bg_color = Color(0.12, 0.16, 0.2, 0.6)
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			style.border_color = Color(0.25, 0.35, 0.45, 0.5)
		btn.add_theme_stylebox_override("normal", style)
		var style_hover = style.duplicate()
		style_hover.bg_color = style.bg_color.lightened(0.1)
		btn.add_theme_stylebox_override("hover", style_hover)

func _open_edit_profile_dialog(player_name: String) -> void:
	edit_profile_player_name = player_name
	var reg = MultiplayerManager.get_registered_player(player_name)
	edit_profile_email_input.text = reg.get("email", "")
	edit_profile_avatar_path = reg.get("avatar", "")
	
	for child in edit_profile_content.get_children():
		child.queue_free()
		
	var title_lbl = Label.new()
	title_lbl.text = "Profile Settings for " + player_name
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_GOLD)
	edit_profile_content.add_child(title_lbl)
	
	# Email section
	var email_sec = VBoxContainer.new()
	email_sec.add_theme_constant_override("separation", 6)
	edit_profile_content.add_child(email_sec)
	
	var email_title = Label.new()
	email_title.text = "Email Address (auto-populates when clicking email buttons):"
	email_title.add_theme_font_size_override("font_size", 14)
	email_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	email_sec.add_child(email_title)
	
	edit_profile_email_input.placeholder_text = "e.g. golfer@example.com"
	edit_profile_email_input.custom_minimum_size = Vector2(0, 50)
	edit_profile_email_input.add_theme_font_size_override("font_size", 18)
	ThemeManager.apply_input_style(edit_profile_email_input)
	if edit_profile_email_input.get_parent() != null:
		edit_profile_email_input.get_parent().remove_child(edit_profile_email_input)
	email_sec.add_child(edit_profile_email_input)
	
	# Avatar section
	var av_sec = VBoxContainer.new()
	av_sec.add_theme_constant_override("separation", 6)
	edit_profile_content.add_child(av_sec)
	
	var av_title = Label.new()
	av_title.text = "In-Game Avatar (replaces colored letter circle):"
	av_title.add_theme_font_size_override("font_size", 15)
	av_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	av_sec.add_child(av_title)
	
	var av_hbox = HBoxContainer.new()
	av_hbox.add_theme_constant_override("separation", 14)
	av_sec.add_child(av_hbox)
	
	edit_profile_avatar_preview_container = HBoxContainer.new()
	edit_profile_avatar_preview_container.add_theme_constant_override("separation", 10)
	av_hbox.add_child(edit_profile_avatar_preview_container)
	_update_edit_profile_avatar_ui()
	
	var change_av_btn = Button.new()
	change_av_btn.text = "Select Avatar..."
	change_av_btn.custom_minimum_size = Vector2(160, 50)
	change_av_btn.add_theme_font_size_override("font_size", 17)
	ThemeManager.apply_primary_button_style(change_av_btn)
	change_av_btn.pressed.connect(func():
		_open_avatar_picker(edit_profile_avatar_path, func(chosen):
			edit_profile_avatar_path = chosen
			_update_edit_profile_avatar_ui()
		)
	)
	av_hbox.add_child(change_av_btn)
	
	var remove_av_btn = Button.new()
	remove_av_btn.text = "Remove Avatar"
	remove_av_btn.custom_minimum_size = Vector2(150, 50)
	remove_av_btn.add_theme_font_size_override("font_size", 17)
	ThemeManager.apply_secondary_button_style(remove_av_btn)
	remove_av_btn.pressed.connect(func():
		edit_profile_avatar_path = ""
		_update_edit_profile_avatar_ui()
	)
	av_hbox.add_child(remove_av_btn)
	
	# Preferred Tee Section
	var tee_sec = VBoxContainer.new()
	tee_sec.add_theme_constant_override("separation", 6)
	edit_profile_content.add_child(tee_sec)
	
	var tee_title = Label.new()
	tee_title.text = "Preferred Tee Box (auto-selected during match setup):"
	tee_title.add_theme_font_size_override("font_size", 15)
	tee_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	tee_sec.add_child(tee_title)

	edit_profile_tee_opt = OptionButton.new()
	edit_profile_tee_opt.add_item("None (Default)", 0)
	edit_profile_tee_opt.add_item("Blue", 1)
	edit_profile_tee_opt.add_item("Red", 2)
	edit_profile_tee_opt.add_item("White", 3)
	edit_profile_tee_opt.add_item("Black", 4)
	edit_profile_tee_opt.add_item("Gold", 5)
	edit_profile_tee_opt.custom_minimum_size = Vector2(0, 50)
	ThemeManager.apply_option_button_style(edit_profile_tee_opt, 18, Vector2(0, 50))
	edit_profile_tee_opt.selected = 0
	var cur_pref_tee = reg.get("preferred_tee", "")
	for i in range(1, edit_profile_tee_opt.item_count):
		if edit_profile_tee_opt.get_item_text(i).to_lower() == cur_pref_tee.to_lower():
			edit_profile_tee_opt.selected = i
			break
	tee_sec.add_child(edit_profile_tee_opt)

	# Bag Section
	var bag_sec = VBoxContainer.new()
	bag_sec.add_theme_constant_override("separation", 6)
	edit_profile_content.add_child(bag_sec)
	
	var bag_title = Label.new()
	bag_title.text = "Golf Bag Configuration:"
	bag_title.add_theme_font_size_override("font_size", 15)
	bag_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	bag_sec.add_child(bag_title)

	var cur_bag = MultiplayerManager.get_player_bag(player_name)
	var bag_status_str = "Default (All 20 clubs)" if cur_bag.is_empty() else "%d Clubs Configured" % cur_bag.size()
	
	var bag_hbox = HBoxContainer.new()
	bag_hbox.add_theme_constant_override("separation", 14)
	bag_sec.add_child(bag_hbox)

	var bag_status_lbl = Label.new()
	bag_status_lbl.text = "Current: " + bag_status_str
	bag_status_lbl.add_theme_font_size_override("font_size", 16)
	bag_status_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_GOLD)
	bag_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_hbox.add_child(bag_status_lbl)

	var open_bag_btn = Button.new()
	open_bag_btn.text = "🎒 Build Your Bag..."
	open_bag_btn.custom_minimum_size = Vector2(200, 48)
	open_bag_btn.add_theme_font_size_override("font_size", 16)
	ThemeManager.apply_primary_button_style(open_bag_btn, 6)
	open_bag_btn.pressed.connect(func():
		edit_profile_dialog.hide()
		_switch_to_bag_tab()
	)
	bag_hbox.add_child(open_bag_btn)
	
	edit_profile_dialog.popup_centered()

func _switch_to_bag_tab() -> void:
	var tabs_node = stats_panel.find_child("TabContainer", true, false)
	if tabs_node != null and tabs_node is TabContainer:
		for i in range(tabs_node.get_tab_count()):
			if "Bag" in tabs_node.get_tab_title(i):
				tabs_node.current_tab = i
				last_active_tab_index = i
				break

func _update_edit_profile_avatar_ui() -> void:
	if edit_profile_avatar_preview_container == null:
		return
	for child in edit_profile_avatar_preview_container.get_children():
		child.queue_free()
		
	if not edit_profile_avatar_path.is_empty() and ResourceLoader.exists(edit_profile_avatar_path):
		var trect = TextureRect.new()
		trect.texture = load(edit_profile_avatar_path)
		trect.custom_minimum_size = Vector2(48, 48)
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		edit_profile_avatar_preview_container.add_child(trect)
		
		var av_name = "Custom Avatar"
		for av in MultiplayerManager.AVAILABLE_AVATARS:
			if av["path"] == edit_profile_avatar_path:
				av_name = av["name"]
				break
		var name_l = Label.new()
		name_l.text = av_name
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		edit_profile_avatar_preview_container.add_child(name_l)
	else:
		var circ = PanelContainer.new()
		circ.custom_minimum_size = Vector2(48, 48)
		var cs = StyleBoxFlat.new()
		cs.bg_color = Color(0.24, 0.46, 0.72)
		cs.corner_radius_top_left = 24
		cs.corner_radius_top_right = 24
		cs.corner_radius_bottom_left = 24
		cs.corner_radius_bottom_right = 24
		circ.add_theme_stylebox_override("panel", cs)
		var clbl = Label.new()
		clbl.text = edit_profile_player_name.substr(0, 1).to_upper()
		clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		clbl.add_theme_font_size_override("font_size", 22)
		circ.add_child(clbl)
		edit_profile_avatar_preview_container.add_child(circ)
		
		var name_l = Label.new()
		name_l.text = "None (Default Initial)"
		name_l.add_theme_font_size_override("font_size", 16)
		name_l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		edit_profile_avatar_preview_container.add_child(name_l)

func _on_edit_profile_confirmed() -> void:
	if edit_profile_player_name.is_empty():
		return
	var new_email = edit_profile_email_input.text.strip_edges()
	var new_tee = ""
	if edit_profile_tee_opt != null and edit_profile_tee_opt.selected > 0:
		new_tee = edit_profile_tee_opt.get_item_text(edit_profile_tee_opt.selected)
	MultiplayerManager.update_player_profile(edit_profile_player_name, new_email, edit_profile_avatar_path, new_tee)
	_refresh_players_list()
	_render_player_profile(edit_profile_player_name)



func _confirm_delete_player() -> void:
	if not selected_player_name.is_empty():
		MultiplayerManager.delete_player_permanently(selected_player_name)
		selected_player_name = ""
		last_active_tab_index = 0
		_refresh_players_list()
		_render_empty_stats()

func _confirm_clear_history() -> void:
	if not selected_player_name.is_empty():
		MultiplayerManager.clear_player_ball_history(selected_player_name)
		_select_player(selected_player_name)

func _request_clear_club_data(club_name: String, display_name: String, count: int) -> void:
	if selected_player_name.is_empty():
		return
	pending_club_to_clear = club_name
	clear_club_confirm_dialog.dialog_text = "Are you sure you want to clear shot data for %s for %s?\n\nThis will reset all %d recorded shots for this club and cannot be undone." % [display_name, selected_player_name, count]
	clear_club_confirm_dialog.popup_centered()

func _confirm_clear_club_shot_data() -> void:
	if not selected_player_name.is_empty() and not pending_club_to_clear.is_empty():
		MultiplayerManager.clear_player_club_shot_data(selected_player_name, pending_club_to_clear)
		pending_club_to_clear = ""
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
	
	# Header with Player Avatar, Name, Email, and Edit Button
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	main_layout.add_child(header_hbox)
	
	var reg_p = MultiplayerManager.get_registered_player(player_name)
	var p_avatar = reg_p.get("avatar", "")
	var p_email = reg_p.get("email", "")

	if not p_avatar.is_empty() and ResourceLoader.exists(p_avatar):
		var av_rect = TextureRect.new()
		av_rect.texture = load(p_avatar)
		av_rect.custom_minimum_size = Vector2(56, 56)
		av_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		header_hbox.add_child(av_rect)
	else:
		var circ = PanelContainer.new()
		circ.custom_minimum_size = Vector2(56, 56)
		circ.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cs = StyleBoxFlat.new()
		cs.bg_color = Color(0.24, 0.46, 0.72)
		cs.corner_radius_top_left = 28
		cs.corner_radius_top_right = 28
		cs.corner_radius_bottom_left = 28
		cs.corner_radius_bottom_right = 28
		circ.add_theme_stylebox_override("panel", cs)
		var clbl = Label.new()
		clbl.text = player_name.substr(0, 1).to_upper()
		clbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		clbl.add_theme_font_size_override("font_size", 28)
		clbl.add_theme_color_override("font_color", Color.WHITE)
		circ.add_child(clbl)
		header_hbox.add_child(circ)

	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vbox.add_theme_constant_override("separation", 2)
	header_hbox.add_child(info_vbox)

	var name_lbl = Label.new()
	name_lbl.text = player_name
	name_lbl.add_theme_font_size_override("font_size", 32)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	info_vbox.add_child(name_lbl)

	var email_lbl = Label.new()
	if not p_email.is_empty():
		email_lbl.text = "✉ " + p_email
		email_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	else:
		email_lbl.text = "✉ No email set (click Edit Profile to add)"
		email_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	email_lbl.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(email_lbl)

	var p_tee = reg_p.get("preferred_tee", "")
	var tee_lbl = Label.new()
	if not p_tee.is_empty():
		tee_lbl.text = "⛳ Preferred Tee: " + p_tee
		var t_color = Color(0.8, 0.9, 1.0)
		match p_tee.to_lower():
			"blue": t_color = Color(0.4, 0.7, 1.0)
			"red": t_color = Color(1.0, 0.45, 0.45)
			"white": t_color = Color(0.95, 0.95, 0.95)
			"black": t_color = Color(0.7, 0.7, 0.7)
			"gold": t_color = Color(1.0, 0.85, 0.3)
		tee_lbl.add_theme_color_override("font_color", t_color)
	else:
		tee_lbl.text = "⛳ Preferred Tee: None"
		tee_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	tee_lbl.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(tee_lbl)

	var edit_profile_btn = Button.new()
	edit_profile_btn.text = "✏️ Edit Profile"
	edit_profile_btn.custom_minimum_size = Vector2(160, 50)
	edit_profile_btn.add_theme_font_size_override("font_size", 17)
	ThemeManager.apply_secondary_button_style(edit_profile_btn, 6)
	edit_profile_btn.pressed.connect(func(): _open_edit_profile_dialog(player_name))
	header_hbox.add_child(edit_profile_btn)

	var build_bag_btn = Button.new()
	build_bag_btn.text = "🎒 Build Bag"
	build_bag_btn.custom_minimum_size = Vector2(160, 50)
	build_bag_btn.add_theme_font_size_override("font_size", 17)
	ThemeManager.apply_primary_button_style(build_bag_btn, 6)
	header_hbox.add_child(build_bag_btn)
	
	# Divider
	var divider = ColorRect.new()
	divider.custom_minimum_size = Vector2(0, 2)
	divider.color = Color(0.3, 0.4, 0.5, 0.4)
	main_layout.add_child(divider)
	
	# TabContainer for Stats and Achievements
	var tabs = TabContainer.new()
	tabs.name = "TabContainer"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 16)
	main_layout.add_child(tabs)

	build_bag_btn.pressed.connect(func():
		for i in range(tabs.get_tab_count()):
			if "Bag" in tabs.get_tab_title(i):
				tabs.current_tab = i
				last_active_tab_index = i
				break
	)
	
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
		val_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
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
	add_stat_box.call("Preferred Tee", p_tee if not p_tee.is_empty() else "None")
	
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
			
	# --- TAB 2: Club Distances & Shot History ---
	var club_vbox = _build_club_distances_tab(player_name)
	tabs.add_child(club_vbox)

	# --- TAB 3: Build Your Bag ---
	var bag_vbox = _build_bag_tab(player_name)
	tabs.add_child(bag_vbox)

	# --- TAB 4: Achievements Gallery ---
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
	ach_summary_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
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
		
		var ach_info_vbox = VBoxContainer.new()
		ach_info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ach_info_vbox.add_theme_constant_override("separation", 2)
		card_hbox.add_child(ach_info_vbox)
		
		var title_l = Label.new()
		title_l.text = ach.get("title", "Achievement")
		title_l.add_theme_font_size_override("font_size", 15)
		if is_unlocked:
			title_l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
		else:
			title_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		ach_info_vbox.add_child(title_l)
		
		var desc_l = Label.new()
		desc_l.text = ach.get("description", "")
		desc_l.add_theme_font_size_override("font_size", 12)
		desc_l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7) if is_unlocked else Color(0.45, 0.45, 0.45))
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ach_info_vbox.add_child(desc_l)
		
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
		ach_info_vbox.add_child(status_l)
		
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
		empty_swing_lbl.text = "No swing recommendations recorded yet.\nTurn on Shot Analysis and/or Golfer Camera during Driving Range, Course Play, or Practice to track swing fixes!"
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
		at_hdr.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
		swing_content_vbox.add_child(at_hdr)

		var at_grid = GridContainer.new()
		at_grid.columns = 2
		at_grid.add_theme_constant_override("h_separation", 16)
		at_grid.add_theme_constant_override("v_separation", 10)
		swing_content_vbox.add_child(at_grid)

		for issue in all_time_issues:
			var card = _create_issue_card(issue, int(all_time_issues[issue]), "All Time")
			at_grid.add_child(card)

	if last_active_tab_index >= 0 and last_active_tab_index < tabs.get_tab_count():
		tabs.current_tab = last_active_tab_index
	tabs.tab_changed.connect(func(tab_idx: int): last_active_tab_index = tab_idx)

	# Actions row at the bottom of the right stats panel
	var actions_hbox = HBoxContainer.new()
	actions_hbox.add_theme_constant_override("separation", 16)
	main_layout.add_child(actions_hbox)
	
	var spacer_act = Control.new()
	spacer_act.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_hbox.add_child(spacer_act)

	var email_report_btn = Button.new()
	email_report_btn.text = "✉ Email Profile Report"
	email_report_btn.custom_minimum_size = Vector2(210, 52)
	email_report_btn.add_theme_font_size_override("font_size", 16)
	ThemeManager.apply_primary_button_style(email_report_btn, 6)
	email_report_btn.pressed.connect(func(): _email_player_profile_report(player_name))
	actions_hbox.add_child(email_report_btn)
	
	var clear_btn = Button.new()
	clear_btn.text = "🧹 Clear All Ball History"
	clear_btn.custom_minimum_size = Vector2(210, 52)
	clear_btn.add_theme_font_size_override("font_size", 16)
	ThemeManager.apply_secondary_button_style(clear_btn, 6)
	clear_btn.pressed.connect(func(): clear_confirm_dialog.popup_centered())
	actions_hbox.add_child(clear_btn)
	
	var delete_btn = Button.new()
	delete_btn.text = "❌ Delete Profile permanently"
	delete_btn.custom_minimum_size = Vector2(250, 52)
	delete_btn.add_theme_font_size_override("font_size", 16)
	ThemeManager.apply_danger_button_style(delete_btn, 6)
	delete_btn.pressed.connect(func(): delete_confirm_dialog.popup_centered())
	actions_hbox.add_child(delete_btn)

func _exit_tree() -> void:
	InAppVideoPlayer.stop_all_players()

func _create_issue_card(issue_name: String, count: int, period_label: String) -> PanelContainer:
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(260, 64)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "Click to view swing explanation, causes, and drill guide for %s" % issue_name
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0.1, 0.14, 0.18, 0.85)
	normal_style.corner_radius_top_left = 8
	normal_style.corner_radius_top_right = 8
	normal_style.corner_radius_bottom_left = 8
	normal_style.corner_radius_bottom_right = 8
	normal_style.content_margin_left = 12
	normal_style.content_margin_top = 8
	normal_style.content_margin_right = 12
	normal_style.content_margin_bottom = 8
	normal_style.border_width_left = 3
	normal_style.border_color = Color(0.3, 0.7, 0.9, 0.7)
	
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0.15, 0.22, 0.28, 0.95)
	hover_style.border_color = Color(0.4, 0.85, 1.0, 1.0)
	hover_style.border_width_left = 4
	
	card.add_theme_stylebox_override("panel", normal_style)
	
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", hover_style))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", normal_style))
	
	var hbox = HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hbox)
	
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)
	
	var name_lbl = Label.new()
	name_lbl.text = issue_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)
	
	var sub_lbl = Label.new()
	sub_lbl.text = period_label + " • 🔍 Click for drill & fix"
	sub_lbl.add_theme_font_size_override("font_size", 12)
	sub_lbl.add_theme_color_override("font_color", Color(0.3, 0.75, 1.0))
	sub_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sub_lbl)
	
	var cnt_lbl = Label.new()
	cnt_lbl.text = str(count)
	cnt_lbl.add_theme_font_size_override("font_size", 24)
	cnt_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	cnt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(cnt_lbl)
	
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_show_issue_detail_modal(issue_name)
	)
	
	return card

func _show_issue_detail_modal(issue_name: String) -> void:
	var existing = get_node_or_null("IssueDetailModal")
	if existing != null:
		InAppVideoPlayer.stop_all_players()
		existing.queue_free()
	
	var info = GolfSwingAnalyzer.get_issue_info(issue_name)
	var modal = _create_issue_detail_modal(info)
	add_child(modal)

func _create_issue_detail_modal(info: Dictionary) -> Control:
	var vp_size = get_viewport_rect().size
	var root = Control.new()
	root.name = "IssueDetailModal"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.z_index = 50
	
	var dismiss_modal = func():
		InAppVideoPlayer.stop_all_players()
		root.queue_free()
	
	root.tree_exiting.connect(func():
		InAppVideoPlayer.stop_all_players()
	)
	
	# Backdrop dimmer
	var dimmer = ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.0, 0.0, 0.0, 0.75)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			dismiss_modal.call()
	)
	root.add_child(dimmer)
	
	# Centered Modal Panel
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	
	var is_mob: bool = (vp_size.x < 850 or vp_size.y > vp_size.x or OS.has_feature("mobile"))
	var has_video: bool = not str(info.get("video_url", "")).is_empty()
	var panel_w = clamp(vp_size.x * 0.94, 320, 840) if is_mob else (clamp(vp_size.x * 0.72, 700, 920) if has_video else clamp(vp_size.x * 0.62, 500, 850))
	var panel_h = clamp(vp_size.y * 0.90, 360, 820) if is_mob else (clamp(vp_size.y * 0.88, 560, 780) if has_video else clamp(vp_size.y * 0.70, 400, 680))
	
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(panel_w, panel_h)
	ThemeManager.apply_modal_style(panel, 14)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	
	var outer_vbox = VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(outer_vbox)
	
	# Header
	var header = HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var title_vbox = VBoxContainer.new()
	title_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var title_lbl = Label.new()
	title_lbl.text = "🎯 " + str(info.get("title", "Swing Flaw Diagnostic"))
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	title_vbox.add_child(title_lbl)
	
	var sub_lbl = Label.new()
	var sev = str(info.get("severity", "HIGH"))
	var cat = str(info.get("category", "SWING MECHANICS"))
	sub_lbl.text = "Category: %s  •  Priority: %s" % [cat, sev]
	sub_lbl.add_theme_font_size_override("font_size", 14)
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.88, 0.98))
	title_vbox.add_child(sub_lbl)
	
	header.add_child(title_vbox)
	
	var close_btn = Button.new()
	close_btn.text = "✖"
	close_btn.custom_minimum_size = Vector2(46, 46)
	close_btn.add_theme_font_size_override("font_size", 22)
	ThemeManager.apply_danger_button_style(close_btn, 6)
	close_btn.pressed.connect(dismiss_modal)
	header.add_child(close_btn)
	
	outer_vbox.add_child(header)
	
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	outer_vbox.add_child(sep)
	
	# Scrollable content
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ThemeManager.apply_scroll_container_style(scroll, 28)
	outer_vbox.add_child(scroll)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(content_vbox)
	
	# Section 1: Biomechanics / Setup Cause
	var cam_flaw = str(info.get("camera_flaw", ""))
	if not cam_flaw.is_empty():
		var cam_panel = PanelContainer.new()
		var cam_style = StyleBoxFlat.new()
		cam_style.bg_color = Color(0.05, 0.09, 0.14, 0.95)
		cam_style.corner_radius_top_left = 8
		cam_style.corner_radius_top_right = 8
		cam_style.corner_radius_bottom_left = 8
		cam_style.corner_radius_bottom_right = 8
		cam_style.border_width_left = 4
		cam_style.border_color = Color(0.35, 0.85, 1.0, 0.9)
		cam_style.content_margin_left = 16
		cam_style.content_margin_top = 12
		cam_style.content_margin_right = 16
		cam_style.content_margin_bottom = 12
		cam_panel.add_theme_stylebox_override("panel", cam_style)
		
		var c_vbox = VBoxContainer.new()
		c_vbox.add_theme_constant_override("separation", 6)
		var c_hdr = Label.new()
		c_hdr.text = "🔍 What Causes It (Biomechanics & Delivery)"
		c_hdr.add_theme_font_size_override("font_size", 17)
		c_hdr.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
		c_vbox.add_child(c_hdr)
		
		var c_lbl = Label.new()
		c_lbl.text = cam_flaw
		c_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c_lbl.add_theme_font_size_override("font_size", 15)
		c_lbl.add_theme_color_override("font_color", Color(0.88, 0.94, 1.0))
		c_vbox.add_child(c_lbl)
		
		cam_panel.add_child(c_vbox)
		content_vbox.add_child(cam_panel)
	
	# Section 2: Launch Impact / Flight Consequence
	var launch_effect = str(info.get("launch_effect", ""))
	if not launch_effect.is_empty():
		var eff_panel = PanelContainer.new()
		var eff_style = StyleBoxFlat.new()
		eff_style.bg_color = Color(0.10, 0.08, 0.05, 0.95)
		eff_style.corner_radius_top_left = 8
		eff_style.corner_radius_top_right = 8
		eff_style.corner_radius_bottom_left = 8
		eff_style.corner_radius_bottom_right = 8
		eff_style.border_width_left = 4
		eff_style.border_color = Color(1.0, 0.85, 0.40, 0.9)
		eff_style.content_margin_left = 16
		eff_style.content_margin_top = 12
		eff_style.content_margin_right = 16
		eff_style.content_margin_bottom = 12
		eff_panel.add_theme_stylebox_override("panel", eff_style)
		
		var e_vbox = VBoxContainer.new()
		e_vbox.add_theme_constant_override("separation", 6)
		var e_hdr = Label.new()
		e_hdr.text = "⚡ Launch Symptom & Distance Effect"
		e_hdr.add_theme_font_size_override("font_size", 17)
		e_hdr.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55))
		e_vbox.add_child(e_hdr)
		
		var e_lbl = Label.new()
		e_lbl.text = launch_effect
		e_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e_lbl.add_theme_font_size_override("font_size", 15)
		e_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.80))
		e_vbox.add_child(e_lbl)
		
		eff_panel.add_child(e_vbox)
		content_vbox.add_child(eff_panel)
	
	# Section 3: How to Fix
	var fix_instruction = str(info.get("fix_instruction", ""))
	if not fix_instruction.is_empty():
		var fix_panel = PanelContainer.new()
		var fix_style = StyleBoxFlat.new()
		fix_style.bg_color = Color(0.04, 0.11, 0.08, 0.95)
		fix_style.corner_radius_top_left = 8
		fix_style.corner_radius_top_right = 8
		fix_style.corner_radius_bottom_left = 8
		fix_style.corner_radius_bottom_right = 8
		fix_style.border_width_left = 4
		fix_style.border_color = Color(0.35, 1.0, 0.65, 0.9)
		fix_style.content_margin_left = 16
		fix_style.content_margin_top = 12
		fix_style.content_margin_right = 16
		fix_style.content_margin_bottom = 12
		fix_panel.add_theme_stylebox_override("panel", fix_style)
		
		var f_vbox = VBoxContainer.new()
		f_vbox.add_theme_constant_override("separation", 6)
		var f_hdr = Label.new()
		f_hdr.text = "💡 How to Fix It (Swing Cue)"
		f_hdr.add_theme_font_size_override("font_size", 17)
		f_hdr.add_theme_color_override("font_color", Color(0.40, 1.0, 0.68))
		f_vbox.add_child(f_hdr)
		
		var f_lbl = Label.new()
		f_lbl.text = fix_instruction
		f_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f_lbl.add_theme_font_size_override("font_size", 15)
		f_lbl.add_theme_color_override("font_color", Color(0.88, 0.98, 0.90))
		f_vbox.add_child(f_lbl)
		
		fix_panel.add_child(f_vbox)
		content_vbox.add_child(fix_panel)
	
	# Section 4: Practice Drill
	var drill_str = str(info.get("drill", ""))
	if not drill_str.is_empty():
		var drill_panel = PanelContainer.new()
		var drill_style = StyleBoxFlat.new()
		drill_style.bg_color = Color(0.10, 0.06, 0.17, 0.95)
		drill_style.corner_radius_top_left = 8
		drill_style.corner_radius_top_right = 8
		drill_style.corner_radius_bottom_left = 8
		drill_style.corner_radius_bottom_right = 8
		drill_style.border_width_left = 4
		drill_style.border_color = Color(0.80, 0.55, 1.0, 0.95)
		drill_style.content_margin_left = 16
		drill_style.content_margin_top = 14
		drill_style.content_margin_right = 16
		drill_style.content_margin_bottom = 14
		drill_panel.add_theme_stylebox_override("panel", drill_style)
		
		var d_vbox = VBoxContainer.new()
		d_vbox.add_theme_constant_override("separation", 8)
		var d_hdr = Label.new()
		d_hdr.text = "🏋️ Prescribed Practice Drill"
		d_hdr.add_theme_font_size_override("font_size", 17)
		d_hdr.add_theme_color_override("font_color", Color(0.92, 0.82, 1.0))
		d_vbox.add_child(d_hdr)
		
		var d_lbl = Label.new()
		d_lbl.text = drill_str
		d_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d_lbl.add_theme_font_size_override("font_size", 15)
		d_lbl.add_theme_color_override("font_color", Color(0.96, 0.90, 1.0))
		d_vbox.add_child(d_lbl)
		
		drill_panel.add_child(d_vbox)
		content_vbox.add_child(drill_panel)
	
	# Section 5: Video Tutorial
	var video_url = str(info.get("video_url", ""))
	if not video_url.is_empty():
		var video_vbox = VBoxContainer.new()
		video_vbox.add_theme_constant_override("separation", 8)
		
		var v_hdr = Label.new()
		v_hdr.text = "▶ Video Drill Tutorial"
		v_hdr.add_theme_font_size_override("font_size", 17)
		v_hdr.add_theme_color_override("font_color", Color(1.0, 0.65, 0.65))
		video_vbox.add_child(v_hdr)
		
		var player = InAppVideoPlayer.new()
		player.setup(
			video_url,
			str(info.get("video_title", "HackMotion Video Drill Tutorial")),
			drill_str,
			str(info.get("category", "")),
			is_mob
		)
		video_vbox.add_child(player)
		content_vbox.add_child(video_vbox)
	
	# Footer
	var footer_btn = Button.new()
	footer_btn.text = "Close"
	footer_btn.custom_minimum_size = Vector2(160, 46)
	footer_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	footer_btn.add_theme_font_size_override("font_size", 16)
	ThemeManager.apply_secondary_button_style(footer_btn, 6)
	footer_btn.pressed.connect(dismiss_modal)
	outer_vbox.add_child(footer_btn)
	
	return root

func _build_club_distances_tab(player_name: String) -> VBoxContainer:
	var tab_vbox = VBoxContainer.new()
	tab_vbox.name = "🏌 Club Distances"
	tab_vbox.add_theme_constant_override("separation", 14)
	tab_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true
	var u_label: String = "yds" if is_imperial else "m"
	var s_label: String = "mph" if is_imperial else "m/s"
	var dist_mult: float = 1.09361 if is_imperial else 1.0
	var speed_mult: float = 1.0 if is_imperial else 0.44704

	var avgs = MultiplayerManager.calculate_player_club_averages(player_name)
	var total_shots := 0
	var active_clubs_count := 0
	for clb in avgs:
		total_shots += int(avgs[clb]["shot_count"])
		if avgs[clb]["has_data"]:
			active_clubs_count += 1

	# Top toolbar / summary header
	var toolbar_hbox = HBoxContainer.new()
	toolbar_hbox.add_theme_constant_override("separation", 16)
	tab_vbox.add_child(toolbar_hbox)

	var summary_lbl = Label.new()
	summary_lbl.text = "📊 %d Total Shots Recorded across %d Clubs (Units: %s)" % [
		total_shots,
		active_clubs_count,
		"Yards" if is_imperial else "Meters"
	]
	summary_lbl.add_theme_font_size_override("font_size", 16)
	summary_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_GOLD)
	toolbar_hbox.add_child(summary_lbl)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar_hbox.add_child(spacer)

	var active_filter_cb = CheckBox.new()
	active_filter_cb.text = "Show active clubs only"
	active_filter_cb.button_pressed = show_only_active_clubs
	active_filter_cb.add_theme_font_size_override("font_size", 14)
	active_filter_cb.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	toolbar_hbox.add_child(active_filter_cb)

	# Scroll container for club list
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(scroll, 28)
	tab_vbox.add_child(scroll)

	var list_vbox = VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(list_vbox)

	if total_shots == 0:
		var empty_panel = PanelContainer.new()
		empty_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ep_style = StyleBoxFlat.new()
		ep_style.bg_color = Color(0.08, 0.12, 0.16, 0.5)
		ep_style.corner_radius_top_left = 8
		ep_style.corner_radius_top_right = 8
		ep_style.corner_radius_bottom_left = 8
		ep_style.corner_radius_bottom_right = 8
		ep_style.content_margin_top = 16
		ep_style.content_margin_bottom = 16
		ep_style.content_margin_left = 16
		ep_style.content_margin_right = 16
		empty_panel.add_theme_stylebox_override("panel", ep_style)

		var empty_lbl = Label.new()
		empty_lbl.text = "No club shots recorded yet for this player.\nHit balls in the Driving Range or Course Play to track your distances and club averages!"
		empty_lbl.add_theme_font_size_override("font_size", 15)
		empty_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		empty_panel.add_child(empty_lbl)
		list_vbox.add_child(empty_panel)

	var club_row_nodes: Array[Dictionary] = []

	for clb in avgs:
		var c_data = avgs[clb]
		var shot_cnt: int = c_data["shot_count"]
		var has_shots: bool = (shot_cnt > 0)

		var card = PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 68)

		var card_style = StyleBoxFlat.new()
		card_style.corner_radius_top_left = 8
		card_style.corner_radius_top_right = 8
		card_style.corner_radius_bottom_left = 8
		card_style.corner_radius_bottom_right = 8
		card_style.content_margin_left = 16
		card_style.content_margin_right = 14
		card_style.content_margin_top = 8
		card_style.content_margin_bottom = 8

		if has_shots:
			card_style.bg_color = Color(0.08, 0.13, 0.18, 0.85)
			card_style.border_width_left = 4
			card_style.border_color = Color(0.24, 0.65, 0.38, 0.9)
		else:
			card_style.bg_color = Color(0.06, 0.08, 0.10, 0.45)
			card_style.border_width_left = 1
			card_style.border_color = Color(0.2, 0.25, 0.3, 0.25)
		card.add_theme_stylebox_override("panel", card_style)

		var card_vbox = VBoxContainer.new()
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_vbox.add_theme_constant_override("separation", 8)
		card.add_child(card_vbox)

		var row_hbox = HBoxContainer.new()
		row_hbox.add_theme_constant_override("separation", 14)
		card_vbox.add_child(row_hbox)

		# Column 1: Club Badge & Name
		var name_vbox = VBoxContainer.new()
		name_vbox.custom_minimum_size = Vector2(150, 0)
		name_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		name_vbox.add_theme_constant_override("separation", 1)
		row_hbox.add_child(name_vbox)

		var code_lbl = Label.new()
		code_lbl.text = clb
		code_lbl.add_theme_font_size_override("font_size", 20)
		code_lbl.add_theme_color_override("font_color", Color.WHITE if has_shots else Color(0.5, 0.5, 0.5))
		name_vbox.add_child(code_lbl)

		var full_lbl = Label.new()
		full_lbl.text = c_data["display_name"]
		full_lbl.add_theme_font_size_override("font_size", 12)
		full_lbl.add_theme_color_override("font_color", Color(0.65, 0.72, 0.8) if has_shots else Color(0.4, 0.4, 0.4))
		name_vbox.add_child(full_lbl)

		# Column 2: Shots Taken
		var count_vbox = VBoxContainer.new()
		count_vbox.custom_minimum_size = Vector2(100, 0)
		count_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		count_vbox.add_theme_constant_override("separation", 1)
		row_hbox.add_child(count_vbox)

		var count_val = Label.new()
		count_val.text = "%d shots" % shot_cnt if has_shots else "0 shots"
		count_val.add_theme_font_size_override("font_size", 17)
		count_val.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_ACCENT if has_shots else Color(0.45, 0.45, 0.45))
		count_vbox.add_child(count_val)

		var count_cap = Label.new()
		count_cap.text = "Recorded"
		count_cap.add_theme_font_size_override("font_size", 11)
		count_cap.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
		count_vbox.add_child(count_cap)

		# Column 3: Stats (Total Distance, Carry Distance, Speed, Spin, Offline)
		var stats_hbox = HBoxContainer.new()
		stats_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		stats_hbox.add_theme_constant_override("separation", 18)
		row_hbox.add_child(stats_hbox)

		var add_metric = func(value_str: String, cap_str: String, is_gold: bool = false, min_w: float = 85.0):
			var vb = VBoxContainer.new()
			vb.custom_minimum_size = Vector2(min_w, 0)
			vb.alignment = BoxContainer.ALIGNMENT_CENTER
			vb.add_theme_constant_override("separation", 1)

			var vl = Label.new()
			vl.text = value_str
			vl.add_theme_font_size_override("font_size", 17)
			if has_shots:
				vl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_GOLD if is_gold else Color.WHITE)
			else:
				vl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			vb.add_child(vl)

			var cl = Label.new()
			cl.text = cap_str
			cl.add_theme_font_size_override("font_size", 11)
			cl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
			vb.add_child(cl)
			stats_hbox.add_child(vb)

		var total_str = "%.1f %s" % [c_data["avg_total_m"] * dist_mult, u_label] if has_shots else "---"
		var carry_str = "%.1f %s" % [c_data["avg_carry_m"] * dist_mult, u_label] if has_shots else "---"
		var speed_str = "%.1f %s" % [c_data["avg_speed_mph"] * speed_mult, s_label] if has_shots else "---"
		var spin_str = "%.0f rpm" % c_data["avg_spin_rpm"] if has_shots else "---"
		var off_str = "%.1f %s" % [c_data["avg_offline_m"] * dist_mult, u_label] if has_shots else "---"

		add_metric.call(total_str, "Avg Total", true, 95.0)
		add_metric.call(carry_str, "Avg Carry", false, 95.0)
		add_metric.call(speed_str, "Avg Speed", false, 85.0)
		add_metric.call(spin_str, "Avg Spin", false, 85.0)
		add_metric.call(off_str, "Avg Offline", false, 85.0)

		# Column 4: Expand Visuals & Reset Buttons
		var btn_hbox = HBoxContainer.new()
		btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		btn_hbox.add_theme_constant_override("separation", 6)
		row_hbox.add_child(btn_hbox)

		var expand_btn = Button.new()
		expand_btn.text = "▼ Visuals"
		expand_btn.custom_minimum_size = Vector2(92, 44)
		expand_btn.add_theme_font_size_override("font_size", 13)
		if has_shots:
			ThemeManager.apply_nav_button_style(expand_btn, 6)
		else:
			expand_btn.disabled = true
			expand_btn.modulate = Color(1, 1, 1, 0.3)
		btn_hbox.add_child(expand_btn)

		var reset_btn = Button.new()
		reset_btn.text = "🗑"
		reset_btn.tooltip_text = "Clear Shot Data for this Club"
		reset_btn.custom_minimum_size = Vector2(44, 44)
		reset_btn.add_theme_font_size_override("font_size", 15)

		if has_shots:
			ThemeManager.apply_danger_button_style(reset_btn, 6)
			var cur_clb = clb
			var cur_disp = c_data["display_name"]
			var cur_cnt = shot_cnt
			reset_btn.pressed.connect(func(): _request_clear_club_data(cur_clb, cur_disp, cur_cnt))
		else:
			reset_btn.disabled = true
			reset_btn.modulate = Color(1, 1, 1, 0.3)
		btn_hbox.add_child(reset_btn)

		# Expandable Drawer with 3 Delivery Visuals
		var drawer = PanelContainer.new()
		drawer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		drawer.visible = false
		var drawer_style = StyleBoxFlat.new()
		drawer_style.bg_color = Color(0.04, 0.06, 0.09, 0.75)
		drawer_style.corner_radius_top_left = 6
		drawer_style.corner_radius_top_right = 6
		drawer_style.corner_radius_bottom_left = 6
		drawer_style.corner_radius_bottom_right = 6
		drawer_style.border_width_top = 1
		drawer_style.border_color = Color(0.2, 0.35, 0.5, 0.5)
		drawer_style.content_margin_left = 6
		drawer_style.content_margin_top = 6
		drawer_style.content_margin_right = 6
		drawer_style.content_margin_bottom = 6
		drawer.add_theme_stylebox_override("panel", drawer_style)

		var delivery_panel = ClubDeliveryVisuals.create_panel(c_data, true)
		drawer.add_child(delivery_panel)
		card_vbox.add_child(drawer)

		expand_btn.pressed.connect(func():
			drawer.visible = not drawer.visible
			expand_btn.text = "▲ Hide" if drawer.visible else "▼ Visuals"
		)

		if show_only_active_clubs and not has_shots:
			card.visible = false

		list_vbox.add_child(card)
		club_row_nodes.append({"card": card, "has_shots": has_shots})

	active_filter_cb.toggled.connect(func(pressed: bool):
		show_only_active_clubs = pressed
		for entry in club_row_nodes:
			if pressed:
				entry["card"].visible = entry["has_shots"]
			else:
				entry["card"].visible = true
	)

	return tab_vbox

func _build_bag_tab(player_name: String) -> VBoxContainer:
	var tab_vbox = VBoxContainer.new()
	tab_vbox.name = "🎒 Build Bag"
	tab_vbox.add_theme_constant_override("separation", 14)
	tab_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var saved_bag = MultiplayerManager.get_player_bag(player_name)
	var is_using_default = [saved_bag.is_empty()]
	
	# Current active clubs map: club_code -> bool
	var active_map: Dictionary = {}
	for std_code in MultiplayerManager.STANDARD_CLUBS:
		if is_using_default[0]:
			active_map[std_code] = true
		else:
			active_map[std_code] = saved_bag.has(std_code)

	# --- Header panel with title, info, and controls ---
	var header_panel = PanelContainer.new()
	var hp_style = StyleBoxFlat.new()
	hp_style.bg_color = Color(0.08, 0.12, 0.16, 0.7)
	hp_style.corner_radius_top_left = 8
	hp_style.corner_radius_top_right = 8
	hp_style.corner_radius_bottom_left = 8
	hp_style.corner_radius_bottom_right = 8
	hp_style.content_margin_left = 16
	hp_style.content_margin_top = 12
	hp_style.content_margin_right = 16
	hp_style.content_margin_bottom = 12
	header_panel.add_theme_stylebox_override("panel", hp_style)
	tab_vbox.add_child(header_panel)

	var hp_vbox = VBoxContainer.new()
	hp_vbox.add_theme_constant_override("separation", 10)
	header_panel.add_child(hp_vbox)

	var desc_lbl = Label.new()
	desc_lbl.text = "Select what clubs you have in your bag. In Course Play, Driving Range, and Minigames, only your chosen clubs will be available to select.\nIf no custom bag is set (or 'Reset to Default' is selected), all 20 clubs will be available by default."
	desc_lbl.add_theme_font_size_override("font_size", 14)
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	hp_vbox.add_child(desc_lbl)

	# Toolbar: Count label, presets, save button
	var toolbar_hbox = HBoxContainer.new()
	toolbar_hbox.add_theme_constant_override("separation", 10)
	hp_vbox.add_child(toolbar_hbox)

	var count_lbl = Label.new()
	count_lbl.add_theme_font_size_override("font_size", 16)
	count_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_GOLD)
	toolbar_hbox.add_child(count_lbl)

	var toast_lbl = Label.new()
	toast_lbl.text = ""
	toast_lbl.add_theme_font_size_override("font_size", 14)
	toast_lbl.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
	toolbar_hbox.add_child(toast_lbl)

	var spacer_tb = Control.new()
	spacer_tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar_hbox.add_child(spacer_tb)

	var standard_preset_btn = Button.new()
	standard_preset_btn.text = "Standard 14"
	standard_preset_btn.tooltip_text = "Quickly set standard 14-club bag"
	standard_preset_btn.custom_minimum_size = Vector2(130, 42)
	standard_preset_btn.add_theme_font_size_override("font_size", 14)
	ThemeManager.apply_secondary_button_style(standard_preset_btn, 4)
	toolbar_hbox.add_child(standard_preset_btn)

	var select_all_btn = Button.new()
	select_all_btn.text = "Select All"
	select_all_btn.tooltip_text = "Select all 20 clubs"
	select_all_btn.custom_minimum_size = Vector2(110, 42)
	select_all_btn.add_theme_font_size_override("font_size", 14)
	ThemeManager.apply_secondary_button_style(select_all_btn, 4)
	toolbar_hbox.add_child(select_all_btn)

	var clear_all_btn = Button.new()
	clear_all_btn.text = "Clear All"
	clear_all_btn.tooltip_text = "Deselect all clubs"
	clear_all_btn.custom_minimum_size = Vector2(100, 42)
	clear_all_btn.add_theme_font_size_override("font_size", 14)
	ThemeManager.apply_secondary_button_style(clear_all_btn, 4)
	toolbar_hbox.add_child(clear_all_btn)

	var reset_default_btn = Button.new()
	reset_default_btn.text = "Reset to Default"
	reset_default_btn.tooltip_text = "Clear custom bag setting so simulator displays all 20 clubs by default"
	reset_default_btn.custom_minimum_size = Vector2(150, 42)
	reset_default_btn.add_theme_font_size_override("font_size", 14)
	ThemeManager.apply_secondary_button_style(reset_default_btn, 4)
	toolbar_hbox.add_child(reset_default_btn)

	var save_btn = Button.new()
	save_btn.text = "💾 Save Bag"
	save_btn.custom_minimum_size = Vector2(130, 42)
	save_btn.add_theme_font_size_override("font_size", 15)
	ThemeManager.apply_primary_button_style(save_btn, 4)
	toolbar_hbox.add_child(save_btn)

	# --- ScrollContainer with Categorized Club Grids ---
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ThemeManager.apply_scroll_container_style(scroll, 28)
	tab_vbox.add_child(scroll)

	var categories_vbox = VBoxContainer.new()
	categories_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(categories_vbox)

	var club_buttons_ref: Array[Dictionary] = [] # Array of {"code": String, "btn": Button, "status_lbl": Label}

	var update_ui_state = func():
		var active_count = 0
		for c in MultiplayerManager.STANDARD_CLUBS:
			if active_map.get(c, false):
				active_count += 1
				
		if is_using_default[0]:
			count_lbl.text = "⛳ Bag Status: Default (All 20 clubs available)"
		else:
			var suffix = " (Standard Limit: 14)" if active_count == 14 else ""
			count_lbl.text = "⛳ Clubs in Bag: %d of 20%s" % [active_count, suffix]
			
		for item in club_buttons_ref:
			var code = item["code"] as String
			var btn = item["btn"] as Button
			var s_lbl = item["status_lbl"] as Label
			var is_in = active_map.get(code, false)
			
			var style = StyleBoxFlat.new()
			style.corner_radius_top_left = 8
			style.corner_radius_top_right = 8
			style.corner_radius_bottom_left = 8
			style.corner_radius_bottom_right = 8
			style.content_margin_left = 14
			style.content_margin_right = 14
			style.content_margin_top = 8
			style.content_margin_bottom = 8
			
			if is_in:
				style.bg_color = Color(0.12, 0.28, 0.18, 0.85)
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
				style.border_color = Color(0.35, 0.85, 0.45, 0.85)
				s_lbl.text = "✓ In Bag"
				s_lbl.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5))
			else:
				style.bg_color = Color(0.08, 0.11, 0.14, 0.5)
				style.border_width_left = 1
				style.border_width_top = 1
				style.border_width_right = 1
				style.border_width_bottom = 1
				style.border_color = Color(0.2, 0.28, 0.35, 0.4)
				s_lbl.text = "✕ Out"
				s_lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
				
			btn.add_theme_stylebox_override("normal", style)
			var style_hover = style.duplicate()
			style_hover.bg_color = style.bg_color.lightened(0.12)
			btn.add_theme_stylebox_override("hover", style_hover)

	var save_current_bag = func(show_toast: bool = true):
		var bag_to_save: Array[String] = []
		if not is_using_default[0]:
			for c in MultiplayerManager.STANDARD_CLUBS:
				if active_map.get(c, false):
					bag_to_save.append(c)
		MultiplayerManager.set_player_bag(player_name, bag_to_save)
		if show_toast:
			toast_lbl.text = "✓ Bag saved!"
			var t = tab_vbox.get_tree().create_timer(2.5)
			t.timeout.connect(func(): if is_instance_valid(toast_lbl): toast_lbl.text = "")

	for cat in CLUB_CATEGORIES:
		var cat_name = cat["category"] as String
		var cat_clubs = cat["clubs"] as Array
		
		var cat_section = VBoxContainer.new()
		cat_section.add_theme_constant_override("separation", 8)
		categories_vbox.add_child(cat_section)
		
		var cat_title = Label.new()
		cat_title.text = cat_name
		cat_title.add_theme_font_size_override("font_size", 18)
		cat_title.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		cat_section.add_child(cat_title)
		
		var grid = GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 10)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cat_section.add_child(grid)
		
		for club_info in cat_clubs:
			var code = club_info["code"] as String
			var full_name = club_info["name"] as String
			
			var btn = Button.new()
			btn.custom_minimum_size = Vector2(180, 68)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.focus_mode = Control.FOCUS_NONE
			
			var btn_vbox = VBoxContainer.new()
			btn_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			btn_vbox.add_theme_constant_override("separation", 2)
			btn.add_child(btn_vbox)
			
			var top_row = HBoxContainer.new()
			top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn_vbox.add_child(top_row)
			
			var code_lbl = Label.new()
			code_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			code_lbl.text = code
			code_lbl.add_theme_font_size_override("font_size", 20)
			code_lbl.add_theme_color_override("font_color", Color.WHITE)
			top_row.add_child(code_lbl)
			
			var spacer_code = Control.new()
			spacer_code.mouse_filter = Control.MOUSE_FILTER_IGNORE
			spacer_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top_row.add_child(spacer_code)
			
			var s_lbl = Label.new()
			s_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s_lbl.add_theme_font_size_override("font_size", 13)
			top_row.add_child(s_lbl)
			
			var name_lbl = Label.new()
			name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_lbl.text = full_name
			name_lbl.add_theme_font_size_override("font_size", 13)
			name_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
			btn_vbox.add_child(name_lbl)
			
			btn.pressed.connect(func():
				is_using_default[0] = false
				active_map[code] = not active_map.get(code, false)
				update_ui_state.call()
				save_current_bag.call(false)
			)
			
			grid.add_child(btn)
			club_buttons_ref.append({"code": code, "btn": btn, "status_lbl": s_lbl})

	# Presets and action handlers
	standard_preset_btn.pressed.connect(func():
		is_using_default[0] = false
		for c in MultiplayerManager.STANDARD_CLUBS:
			active_map[c] = STANDARD_14_BAG.has(c)
		update_ui_state.call()
		save_current_bag.call(true)
	)

	select_all_btn.pressed.connect(func():
		is_using_default[0] = false
		for c in MultiplayerManager.STANDARD_CLUBS:
			active_map[c] = true
		update_ui_state.call()
		save_current_bag.call(true)
	)

	clear_all_btn.pressed.connect(func():
		is_using_default[0] = false
		for c in MultiplayerManager.STANDARD_CLUBS:
			active_map[c] = false
		update_ui_state.call()
		save_current_bag.call(true)
	)

	reset_default_btn.pressed.connect(func():
		is_using_default[0] = true
		for c in MultiplayerManager.STANDARD_CLUBS:
			active_map[c] = true
		update_ui_state.call()
		save_current_bag.call(true)
	)

	save_btn.pressed.connect(func():
		save_current_bag.call(true)
	)

	update_ui_state.call()
	return tab_vbox

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
	
	body += MultiplayerManager.format_player_club_stats_summary(player_name)
	body += MultiplayerManager.format_player_swing_issues_summary(player_name)
	
	var csv_content = GolfDataExporter.generate_profile_csv(player_name)
	var safe_player = GolfDataExporter.sanitize_filename(player_name)
	var date_slug = Time.get_date_string_from_system().replace("-", "")
	var attachment_basename = "%s_profile_club_stats_%s" % [safe_player, date_slug]

	var to_email = MultiplayerManager.get_player_email(player_name)
	GolfDataExporter.export_and_email(to_email, subject, body, attachment_basename, csv_content)
	print("[PlayersMenu] Opened email client with attached CSV for %s" % player_name)

func _calculate_player_stats(player_name: String) -> Dictionary:
	return MultiplayerManager.calculate_player_stats(player_name)
