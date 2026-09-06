class_name ThemeManager
extends Node

# --- Heckle Golf Simulator Design System Tokens ---

# Palette Colors
const COLOR_BG_OVERLAY = Color(0.05, 0.08, 0.11, 0.88)
const COLOR_GLASS_PANEL = Color(0.07, 0.11, 0.16, 0.85)
const COLOR_GLASS_BORDER = Color(0.24, 0.44, 0.65, 0.4)

const COLOR_PRIMARY_NORMAL = Color(0.14, 0.52, 0.28)
const COLOR_PRIMARY_HOVER = Color(0.18, 0.65, 0.35)
const COLOR_PRIMARY_PRESSED = Color(0.10, 0.42, 0.22)

const COLOR_SECONDARY_NORMAL = Color(0.18, 0.34, 0.50)
const COLOR_SECONDARY_HOVER = Color(0.24, 0.44, 0.65)
const COLOR_SECONDARY_PRESSED = Color(0.14, 0.26, 0.38)

const COLOR_NAV_NORMAL = Color(0.13, 0.17, 0.23, 0.85)
const COLOR_NAV_HOVER = Color(0.20, 0.27, 0.36, 0.95)
const COLOR_NAV_PRESSED = Color(0.09, 0.12, 0.16, 0.95)

const COLOR_DANGER_NORMAL = Color(0.65, 0.20, 0.20)
const COLOR_DANGER_HOVER = Color(0.80, 0.26, 0.26)
const COLOR_DANGER_PRESSED = Color(0.50, 0.15, 0.15)

const COLOR_INPUT_BG = Color(0.08, 0.12, 0.17, 0.90)
const COLOR_INPUT_BORDER = Color(0.24, 0.44, 0.65, 0.5)

const COLOR_TEXT_WHITE = Color(0.96, 0.98, 1.0)
const COLOR_TEXT_MUTED = Color(0.70, 0.76, 0.84)
const COLOR_TEXT_DIM = Color(0.50, 0.56, 0.64)

# High-contrast, mobile-readable semantic text tokens
const COLOR_TEXT_GOLD = Color(1.0, 0.85, 0.38)       # Warm rich gold for scorecard totals, winner highlights
const COLOR_TEXT_WARNING = Color(1.0, 0.82, 0.32)    # High-contrast warm amber for warnings / alerts
const COLOR_TEXT_DANGER = Color(1.0, 0.42, 0.42)     # High-luminance coral red (clearly readable on dark backgrounds)
const COLOR_TEXT_SUCCESS = Color(0.35, 0.95, 0.55)   # Vibrant mint green for under-par and ready states
const COLOR_TEXT_ACCENT = Color(0.35, 0.82, 1.0)     # Crisp vivid cyan for section titles and headers

# --- Helper Methods for Button Styling ---

static func apply_primary_button_style(btn: Button, corner_radius: int = 8) -> void:
	_apply_button_styles(
		btn,
		_create_stylebox(COLOR_PRIMARY_NORMAL, COLOR_PRIMARY_NORMAL.lightened(0.2), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_PRIMARY_HOVER, Color(1, 1, 1, 0.3), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_PRIMARY_PRESSED, Color(1, 1, 1, 0.2), corner_radius, 1, 18, 12, 18, 12),
		COLOR_TEXT_WHITE
	)

static func apply_secondary_button_style(btn: Button, corner_radius: int = 8) -> void:
	_apply_button_styles(
		btn,
		_create_stylebox(COLOR_SECONDARY_NORMAL, COLOR_SECONDARY_NORMAL.lightened(0.2), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_SECONDARY_HOVER, Color(1, 1, 1, 0.3), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_SECONDARY_PRESSED, Color(1, 1, 1, 0.2), corner_radius, 1, 18, 12, 18, 12),
		COLOR_TEXT_WHITE
	)

static func apply_nav_button_style(btn: Button, corner_radius: int = 8) -> void:
	_apply_button_styles(
		btn,
		_create_stylebox(COLOR_NAV_NORMAL, Color(1, 1, 1, 0.15), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_NAV_HOVER, Color(1, 1, 1, 0.30), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_NAV_PRESSED, Color(1, 1, 1, 0.10), corner_radius, 1, 18, 12, 18, 12),
		COLOR_TEXT_WHITE
	)

static func apply_icon_button_style(btn: Button, corner_radius: int = 8, padding: int = 12) -> void:
	_apply_button_styles(
		btn,
		_create_stylebox(COLOR_NAV_NORMAL, Color(1, 1, 1, 0.15), corner_radius, 1, padding, padding, padding, padding),
		_create_stylebox(COLOR_NAV_HOVER, Color(1, 1, 1, 0.30), corner_radius, 1, padding, padding, padding, padding),
		_create_stylebox(COLOR_NAV_PRESSED, Color(1, 1, 1, 0.10), corner_radius, 1, padding, padding, padding, padding),
		COLOR_TEXT_WHITE
	)

static func apply_danger_button_style(btn: Button, corner_radius: int = 8) -> void:
	_apply_button_styles(
		btn,
		_create_stylebox(COLOR_DANGER_NORMAL, COLOR_DANGER_NORMAL.lightened(0.2), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_DANGER_HOVER, Color(1, 1, 1, 0.3), corner_radius, 1, 18, 12, 18, 12),
		_create_stylebox(COLOR_DANGER_PRESSED, Color(1, 1, 1, 0.2), corner_radius, 1, 18, 12, 18, 12),
		COLOR_TEXT_WHITE
	)

static func apply_card_panel_style(panel: Control, is_highlighted: bool = false, corner_radius: int = 12, m_left: int = 16, m_top: int = 16, m_right: int = 16, m_bottom: int = 16) -> void:
	var bg = COLOR_GLASS_PANEL if not is_highlighted else Color(0.10, 0.16, 0.24, 0.90)
	var border = COLOR_GLASS_BORDER if not is_highlighted else Color(0.35, 0.65, 0.95, 0.6)
	var style = _create_stylebox(bg, border, corner_radius, 1, m_left, m_top, m_right, m_bottom)
	if panel is PanelContainer or panel is Panel:
		panel.add_theme_stylebox_override("panel", style)

static func apply_data_panel_style(panel: Control, is_highlighted: bool = false) -> void:
	var bg = COLOR_GLASS_PANEL if not is_highlighted else Color(0.10, 0.16, 0.24, 0.90)
	var border = COLOR_GLASS_BORDER if not is_highlighted else Color(0.35, 0.65, 0.95, 0.6)
	var style = _create_stylebox(bg, border, 8, 1, 8, 4, 8, 4)
	if panel is PanelContainer or panel is Panel:
		panel.add_theme_stylebox_override("panel", style)

static func apply_modal_style(panel: Control, corner_radius: int = 12) -> void:
	var style = _create_stylebox(COLOR_GLASS_PANEL, COLOR_GLASS_BORDER, corner_radius, 1, 20, 20, 20, 20)
	style.shadow_color = Color(0, 0, 0, 0.6)
	style.shadow_size = 16
	if panel is PanelContainer or panel is Panel:
		panel.add_theme_stylebox_override("panel", style)

static func apply_input_style(control: Control, corner_radius: int = 6) -> void:
	var normal_style = _create_stylebox(COLOR_INPUT_BG, COLOR_INPUT_BORDER, corner_radius, 1, 12, 10, 12, 10)
	var focus_style = _create_stylebox(COLOR_INPUT_BG, COLOR_SECONDARY_HOVER, corner_radius, 2, 12, 10, 12, 10)
	if control is LineEdit:
		control.add_theme_stylebox_override("normal", normal_style)
		control.add_theme_stylebox_override("focus", focus_style)
		control.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
		control.add_theme_color_override("placeholder_color", COLOR_TEXT_DIM)
		if control.custom_minimum_size.y < 48:
			control.custom_minimum_size.y = 48

static func apply_scrollbar_style(scrollbar: ScrollBar, width: int = 28) -> void:
	if scrollbar == null:
		return
	if scrollbar is VScrollBar:
		scrollbar.custom_minimum_size = Vector2(width, 0)
	else:
		scrollbar.custom_minimum_size = Vector2(0, width)
	
	var track_style = _create_stylebox(Color(0.04, 0.07, 0.11, 0.65), Color(0.24, 0.44, 0.65, 0.3), 8, 1, 3, 3, 3, 3)
	var grabber_normal = _create_stylebox(COLOR_SECONDARY_HOVER, Color(0.40, 0.65, 0.90, 0.5), 8, 1, 2, 2, 2, 2)
	var grabber_hover = _create_stylebox(Color(0.35, 0.65, 0.95, 0.95), Color(0.70, 0.88, 1.0, 0.8), 8, 1, 2, 2, 2, 2)
	var grabber_pressed = _create_stylebox(COLOR_PRIMARY_HOVER, Color(0.80, 1.0, 0.80, 0.9), 8, 1, 2, 2, 2, 2)

	scrollbar.add_theme_stylebox_override("scroll", track_style)
	scrollbar.add_theme_stylebox_override("scroll_focus", track_style)
	scrollbar.add_theme_stylebox_override("grabber", grabber_normal)
	scrollbar.add_theme_stylebox_override("grabber_highlight", grabber_hover)
	scrollbar.add_theme_stylebox_override("grabber_pressed", grabber_pressed)

static func apply_scroll_container_style(scroll: ScrollContainer, width: int = 28) -> void:
	if scroll == null:
		return
	var v_bar = scroll.get_v_scroll_bar()
	if v_bar != null:
		apply_scrollbar_style(v_bar, width)
	var h_bar = scroll.get_h_scroll_bar()
	if h_bar != null:
		apply_scrollbar_style(h_bar, width)
	TouchScrollHelper.attach_to(scroll)

static func _apply_button_styles(btn: Button, style_normal: StyleBoxFlat, style_hover: StyleBoxFlat, style_pressed: StyleBoxFlat, text_color: Color) -> void:
	btn.add_theme_stylebox_override("normal", style_normal)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("focus", style_hover)
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color)
	btn.add_theme_color_override("font_pressed_color", text_color)
	if btn.custom_minimum_size.y < 48:
		btn.custom_minimum_size.y = 48
	if not btn.has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", 16)
	elif btn.get_theme_font_size("font_size") < 15:
		btn.add_theme_font_size_override("font_size", 16)

static func _create_stylebox(bg: Color, border: Color, corner_radius: int, border_width: int, m_left: int, m_top: int, m_right: int, m_bottom: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.content_margin_left = m_left
	style.content_margin_top = m_top
	style.content_margin_right = m_right
	style.content_margin_bottom = m_bottom
	return style

static var _dialog_close_icon_normal: Texture2D = null
static var _dialog_close_icon_pressed: Texture2D = null

static func get_dialog_close_icon(pressed: bool = false) -> Texture2D:
	if pressed and _dialog_close_icon_pressed != null:
		return _dialog_close_icon_pressed
	if not pressed and _dialog_close_icon_normal != null:
		return _dialog_close_icon_normal

	var size = 32
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var bg_color = Color(0.65, 0.20, 0.20, 0.95) if pressed else Color(0.16, 0.24, 0.34, 0.85)
	var border_color = Color(0.9, 0.4, 0.4, 0.9) if pressed else Color(0.35, 0.55, 0.75, 0.7)
	var x_color = Color(1.0, 1.0, 1.0, 1.0)
	
	# Draw rounded circular badge background
	var center = Vector2(size * 0.5, size * 0.5)
	var radius = size * 0.46
	var radius_sq = radius * radius
	var inner_radius_sq = (radius - 1.5) * (radius - 1.5)
	for y in range(size):
		for x in range(size):
			var dist_sq = (Vector2(x, y) - center).length_squared()
			if dist_sq <= inner_radius_sq:
				img.set_pixel(x, y, bg_color)
			elif dist_sq <= radius_sq:
				img.set_pixel(x, y, border_color)

	# Draw crisp thick 'X'
	for i in range(10, 22):
		for t in range(-1, 2):
			var px1 = i
			var py1 = i + t
			var px2 = size - 1 - i
			var py2 = i + t
			if px1 >= 0 and px1 < size and py1 >= 0 and py1 < size:
				img.set_pixel(px1, py1, x_color)
			if px2 >= 0 and px2 < size and py2 >= 0 and py2 < size:
				img.set_pixel(px2, py2, x_color)

	var tex = ImageTexture.create_from_image(img)
	if pressed:
		_dialog_close_icon_pressed = tex
	else:
		_dialog_close_icon_normal = tex
	return tex

static func apply_option_button_style(opt: OptionButton, font_size: int = 20, min_size: Vector2 = Vector2(180, 52)) -> void:
	if opt == null:
		return
	opt.custom_minimum_size = min_size
	opt.add_theme_font_size_override("font_size", font_size)
	apply_secondary_button_style(opt, 8)

	var popup = opt.get_popup()
	if popup != null:
		style_popup_menu(popup, font_size)

static func style_popup_menu(popup: PopupMenu, font_size: int = 20) -> void:
	if popup == null:
		return
	popup.add_theme_font_size_override("font_size", font_size)
	popup.add_theme_constant_override("v_separation", 14)
	popup.add_theme_constant_override("item_start_padding", 20)
	popup.add_theme_constant_override("item_end_padding", 20)
	popup.add_theme_color_override("font_color", COLOR_TEXT_WHITE)
	popup.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	
	var panel_style = _create_stylebox(COLOR_GLASS_PANEL, COLOR_GLASS_BORDER, 10, 1, 10, 10, 10, 10)
	panel_style.shadow_color = Color(0, 0, 0, 0.6)
	panel_style.shadow_size = 12
	popup.add_theme_stylebox_override("panel", panel_style)
	
	var hover_style = _create_stylebox(COLOR_SECONDARY_HOVER, Color(0.40, 0.65, 0.90, 0.5), 6, 1, 12, 6, 12, 6)
	popup.add_theme_stylebox_override("hover", hover_style)

static func apply_dialog_style(dialog: AcceptDialog, min_button_size: Vector2 = Vector2(150, 52), font_size: int = 18) -> void:
	if dialog == null:
		return
		
	dialog.add_theme_font_size_override("title_font_size", 22)
	dialog.add_theme_color_override("title_color", COLOR_TEXT_WHITE)
	dialog.add_theme_constant_override("title_height", 48)
	dialog.add_theme_constant_override("close_h_offset", 34)
	dialog.add_theme_constant_override("close_v_offset", 24)
	dialog.add_theme_constant_override("buttons_separation", 24)

	var close_normal = get_dialog_close_icon(false)
	var close_pressed = get_dialog_close_icon(true)
	dialog.add_theme_icon_override("close", close_normal)
	dialog.add_theme_icon_override("close_pressed", close_pressed)

	var border_style = _create_stylebox(COLOR_GLASS_PANEL, COLOR_GLASS_BORDER, 12, 1, 16, 16, 16, 16)
	dialog.add_theme_stylebox_override("embedded_border", border_style)
	dialog.add_theme_stylebox_override("panel", border_style)

	var ok_btn = dialog.get_ok_button()
	if ok_btn != null:
		ok_btn.custom_minimum_size = min_button_size
		ok_btn.add_theme_font_size_override("font_size", font_size)
		apply_primary_button_style(ok_btn)

	if dialog is ConfirmationDialog:
		var cancel_btn = (dialog as ConfirmationDialog).get_cancel_button()
		if cancel_btn != null:
			cancel_btn.custom_minimum_size = min_button_size
			cancel_btn.add_theme_font_size_override("font_size", font_size)
			apply_secondary_button_style(cancel_btn)

	var label = dialog.get_label()
	if label != null:
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", COLOR_TEXT_WHITE)

	# Re-enforce sizing on about_to_popup to prevent engine resets
	if not dialog.about_to_popup.is_connected(_on_dialog_about_to_popup):
		dialog.about_to_popup.connect(_on_dialog_about_to_popup.bind(dialog, min_button_size, font_size))

static func _on_dialog_about_to_popup(dialog: AcceptDialog, min_button_size: Vector2, font_size: int) -> void:
	if dialog == null:
		return
	var ok_btn = dialog.get_ok_button()
	if ok_btn != null:
		ok_btn.custom_minimum_size = min_button_size
		ok_btn.add_theme_font_size_override("font_size", font_size)
		apply_primary_button_style(ok_btn)
	if dialog is ConfirmationDialog:
		var cancel_btn = (dialog as ConfirmationDialog).get_cancel_button()
		if cancel_btn != null:
			cancel_btn.custom_minimum_size = min_button_size
			cancel_btn.add_theme_font_size_override("font_size", font_size)
			apply_secondary_button_style(cancel_btn)
	var label = dialog.get_label()
	if label != null:
		label.add_theme_font_size_override("font_size", 18)

