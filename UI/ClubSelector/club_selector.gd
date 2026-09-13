extends PanelContainer

var clubs := ["Dr", "3w", "5w", "2H", "3H", "4H", "1i", "2i", "3i", "4i", "5i", "6i", "7i", "8i", "9i", "Pw", "Gw", "Sw", "Lw", "Pt"]
var current_club: Button = null
var club_button: Button = null
var grid_container: GridContainer = null

# Sizing constants
const DEFAULT_TOGGLE_WIDTH: float = 256.0
const DEFAULT_TOGGLE_HEIGHT: float = 56.0
const CLUB_BUTTON_SIZE: Vector2 = Vector2(84, 84)
const CLUB_BUTTON_FONT_SIZE: int = 22
const GRID_COLUMNS: int = 4
const GRID_H_SEPARATION: int = 8
const GRID_V_SEPARATION: int = 8
const GRID_OFFSET_TOP: float = 6.0

# Theme colors
const BUTTON_BG_NORMAL = Color(0.10, 0.14, 0.18, 0.85)
const BUTTON_BG_HOVER = Color(0.18, 0.34, 0.50, 0.85)
const BUTTON_BG_PRESSED = Color(0.24, 0.44, 0.65, 0.85)
const BUTTON_BG_SELECTED = Color(0.14, 0.52, 0.28, 0.90)
const BUTTON_BORDER = Color(1.0, 1.0, 1.0, 0.3)
const BUTTON_FONT_SELECTED = Color.WHITE
const DISPLAY_BG_NORMAL = Color(0.14, 0.52, 0.28, 0.90)
const DISPLAY_BG_HOVER = Color(0.18, 0.65, 0.35, 0.95)
const DISPLAY_BORDER = Color(1.0, 1.0, 1.0, 0.3)

func _get_grid_width() -> float:
	return float(GRID_COLUMNS * CLUB_BUTTON_SIZE.x + (GRID_COLUMNS - 1) * GRID_H_SEPARATION)

func _get_grid_height() -> float:
	var rows = int(ceil(float(clubs.size()) / float(GRID_COLUMNS)))
	return float(rows * CLUB_BUTTON_SIZE.y + (rows - 1) * GRID_V_SEPARATION)

func _ready() -> void:
	grid_container = $MarginContainer/VBoxContainer/DropdownWrapper/GridContainer
	
	# Hide title label and strip margins
	var vbox = $MarginContainer/VBoxContainer
	var title = vbox.get_node_or_null("Title")
	if title != null:
		title.visible = false
	var margin = $MarginContainer
	if margin != null:
		margin.add_theme_constant_override("margin_left", 0)
		margin.add_theme_constant_override("margin_right", 0)
		margin.add_theme_constant_override("margin_top", 0)
		margin.add_theme_constant_override("margin_bottom", 0)
		
	if grid_container != null:
		grid_container.columns = GRID_COLUMNS
		grid_container.add_theme_constant_override("h_separation", GRID_H_SEPARATION)
		grid_container.add_theme_constant_override("v_separation", GRID_V_SEPARATION)
		grid_container.offset_top = GRID_OFFSET_TOP
		grid_container.offset_bottom = _get_grid_height() + GRID_OFFSET_TOP

	_create_club_display_button()
	_create_club_buttons()
	current_club = grid_container.get_child(0)
	_on_club_button_pressed(current_club)


func _input(event: InputEvent) -> void:
	if not grid_container.visible: # This handles the click off so it does not toggle from outside btn
		return
	var global_mouse_pos = get_global_mouse_position()
	var selector_rect = get_global_rect()
	var grid_rect = grid_container.get_global_rect()
	var is_over_selector = selector_rect.has_point(global_mouse_pos) or grid_rect.has_point(global_mouse_pos)

	if event is InputEventMouseButton:
		if not is_over_selector:
			if event.pressed:
				_toggle_grid_visibility()
			get_tree().root.set_input_as_handled()

func _create_club_display_button() -> void:
	club_button = Button.new()
	club_button.text = "🏌 Club: " + clubs[0]
	club_button.custom_minimum_size = Vector2(DEFAULT_TOGGLE_WIDTH, DEFAULT_TOGGLE_HEIGHT)
	club_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	club_button.theme = _create_display_button_theme()
	club_button.pressed.connect(_on_display_button_pressed)

	$MarginContainer/VBoxContainer.add_child(club_button)
	$MarginContainer/VBoxContainer.move_child(club_button, 1)


func _create_club_buttons() -> void:
	var button_theme = _create_club_button_theme()
	for i in range(clubs.size()):
		var button = Button.new()
		button.text = clubs[i]
		button.custom_minimum_size = CLUB_BUTTON_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.theme = button_theme
		button.pressed.connect(_on_club_button_pressed.bindv([button]))
		grid_container.add_child(button)


func _create_club_button_theme() -> Theme:
	var button_theme = Theme.new()
	button_theme.set_font_size("font_size", "Button", CLUB_BUTTON_FONT_SIZE)

	var normal_style = _create_button_style(BUTTON_BG_NORMAL)
	button_theme.set_stylebox("normal", "Button", normal_style)

	var hover_style = _create_button_style(BUTTON_BG_HOVER)
	button_theme.set_stylebox("hover", "Button", hover_style)

	var pressed_style = _create_button_style(BUTTON_BG_PRESSED)
	button_theme.set_stylebox("pressed", "Button", pressed_style)

	var focus_style = StyleBoxEmpty.new()
	button_theme.set_stylebox("focus", "Button", focus_style)

	return button_theme


func _create_button_style(bg_color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.border_color = BUTTON_BORDER
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	return style


func _create_display_button_theme() -> Theme:
	var display_theme = Theme.new()
	display_theme.set_font_size("font_size", "Button", 18)

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = DISPLAY_BG_NORMAL
	normal_style.corner_radius_top_left = 20
	normal_style.corner_radius_top_right = 20
	normal_style.corner_radius_bottom_left = 20
	normal_style.corner_radius_bottom_right = 20
	normal_style.content_margin_left = 18
	normal_style.content_margin_right = 18
	normal_style.content_margin_top = 10
	normal_style.content_margin_bottom = 10
	display_theme.set_stylebox("normal", "Button", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = DISPLAY_BG_HOVER
	display_theme.set_stylebox("hover", "Button", hover_style)

	return display_theme


func _toggle_grid_visibility() -> void:
	grid_container.visible = not grid_container.visible
	var wrapper = get_node_or_null("MarginContainer/VBoxContainer/DropdownWrapper")
	var grid_w = _get_grid_width()
	var grid_h = _get_grid_height() + GRID_OFFSET_TOP

	if wrapper != null:
		if grid_container.visible:
			wrapper.custom_minimum_size = Vector2(grid_w, grid_h)
			custom_minimum_size.x = grid_w
			if anchor_left == 1.0 and anchor_right == 1.0:
				offset_left = offset_right - grid_w
		else:
			var current_right = offset_right
			wrapper.custom_minimum_size = Vector2(DEFAULT_TOGGLE_WIDTH, 0)
			custom_minimum_size.x = DEFAULT_TOGGLE_WIDTH
			if anchor_left == 1.0 and anchor_right == 1.0:
				offset_right = current_right
				offset_left = current_right - DEFAULT_TOGGLE_WIDTH


func _on_display_button_pressed() -> void:
	_toggle_grid_visibility()


func _on_club_button_pressed(button: Button) -> void:
	# Deselect the old button
	if current_club:
		_set_button_deselected(current_club)

	# Update the display button
	club_button.text = "🏌 Club: " + button.text

	# Select the new button
	current_club = button
	_set_button_selected(current_club)

	_toggle_grid_visibility()

	EventBus.emit_signal("club_selected", current_club.text)


func _set_button_selected(button: Button) -> void:
	button.add_theme_color_override("font_color", BUTTON_FONT_SELECTED)
	var selected_style = _create_selected_button_style()
	button.add_theme_stylebox_override("normal", selected_style)


func _set_button_deselected(button: Button) -> void:
	button.remove_theme_color_override("font_color")
	button.remove_theme_stylebox_override("normal")


func _create_selected_button_style() -> StyleBoxFlat:
	return _create_button_style(BUTTON_BG_SELECTED)


func select_club_by_name(club_name: String) -> void:
	if not grid_container:
		return
	var target_btn: Button = null
	for child in grid_container.get_children():
		if child is Button and child.text == club_name:
			target_btn = child
			break
	
	if target_btn != null and target_btn != current_club:
		if current_club:
			_set_button_deselected(current_club)
		club_button.text = "🏌 Club: " + target_btn.text
		current_club = target_btn
		_set_button_selected(current_club)
		EventBus.emit_signal("club_selected", current_club.text)


func get_current_club_name() -> String:
	if current_club != null:
		return current_club.text
	return clubs[0] if not clubs.is_empty() else ""


func select_next_club() -> void:
	# Cycles to next longer club (e.g. 5i -> 4i -> 3i -> Dr)
	var cur_name = get_current_club_name()
	var idx = clubs.find(cur_name)
	if idx > 0:
		select_club_by_name(clubs[idx - 1])


func select_prev_club() -> void:
	# Cycles to next shorter club (e.g. 5i -> 6i -> 7i -> Pw)
	var cur_name = get_current_club_name()
	var idx = clubs.find(cur_name)
	if idx >= 0 and idx < clubs.size() - 1:
		select_club_by_name(clubs[idx + 1])


