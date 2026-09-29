class_name VirtualKeyboard
extends CanvasLayer

signal text_submitted(text: String)
signal text_changed(text: String)
signal closed
signal closing

const LAYER_PRIORITY := 140

# Target control being edited (LineEdit or TextEdit)
var _target_control: Control = null
var _original_text: String = ""
var _current_text: String = ""
var _cursor_pos: int = 0
var _max_length: int = 0
var _is_secret: bool = false
var _is_open: bool = false
var _is_closing: bool = false

# Layout modes
var _shift_active: bool = false
var _caps_lock: bool = false
var _symbols_active: bool = false

# UI Nodes
var _backdrop: ColorRect = null
var _main_panel: PanelContainer = null
var _title_label: Label = null
var _preview_label: Label = null
var _caret_label: Label = null
var _char_count_label: Label = null
var _keys_vbox: VBoxContainer = null
var _legend_label: RichTextLabel = null
var _shift_btn: Button = null
var _symbols_btn: Button = null

# Animation & Caret Blink
var _caret_timer: float = 0.0
var _caret_visible: bool = true
var _anim_tween: Tween = null

# Key button storage for fast layout switching & focus grid
var _all_key_buttons: Array[Button] = []
var _key_row_containers: Array[HBoxContainer] = []
var _central_key_button: Button = null

# Button styles
var _key_normal_style: StyleBoxFlat = null
var _key_focus_style: StyleBoxFlat = null
var _key_hover_style: StyleBoxFlat = null
var _key_pressed_style: StyleBoxFlat = null
var _action_normal_style: StyleBoxFlat = null
var _action_focus_style: StyleBoxFlat = null


func _init() -> void:
	layer = LAYER_PRIORITY
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	_init_styles()
	_build_ui()
	visible = false


func _process(delta: float) -> void:
	if not _is_open or _is_closing:
		return

	# Handle blinking caret
	_caret_timer += delta
	if _caret_timer >= 0.5:
		_caret_timer = 0.0
		_caret_visible = not _caret_visible
		if _caret_label != null:
			_caret_label.visible = _caret_visible

	# Safety: if target control was deleted or hidden while open, close cleanly
	if _target_control != null and not is_instance_valid(_target_control):
		close(false)


func _init_styles() -> void:
	# Standard key normal
	_key_normal_style = StyleBoxFlat.new()
	_key_normal_style.bg_color = Color(0.12, 0.17, 0.23, 0.95)
	_key_normal_style.set_border_width_all(1)
	_key_normal_style.border_color = Color(0.24, 0.44, 0.65, 0.5)
	_key_normal_style.set_corner_radius_all(8)
	_key_normal_style.set_content_margin_all(8)

	# High-contrast glowing focus box for controller navigation
	_key_focus_style = StyleBoxFlat.new()
	_key_focus_style.bg_color = Color(0.18, 0.45, 0.72, 1.0)
	_key_focus_style.set_border_width_all(3)
	_key_focus_style.border_color = Color(0.40, 0.90, 1.0, 1.0)
	_key_focus_style.set_corner_radius_all(8)
	_key_focus_style.set_content_margin_all(8)
	_key_focus_style.shadow_color = Color(0.2, 0.7, 1.0, 0.6)
	_key_focus_style.shadow_size = 6

	# Key hover
	_key_hover_style = StyleBoxFlat.new()
	_key_hover_style.bg_color = Color(0.18, 0.26, 0.36, 0.95)
	_key_hover_style.set_border_width_all(1)
	_key_hover_style.border_color = Color(0.35, 0.65, 0.95, 0.8)
	_key_hover_style.set_corner_radius_all(8)
	_key_hover_style.set_content_margin_all(8)

	# Key pressed
	_key_pressed_style = StyleBoxFlat.new()
	_key_pressed_style.bg_color = Color(0.10, 0.55, 0.30, 1.0)
	_key_pressed_style.set_border_width_all(2)
	_key_pressed_style.border_color = Color(0.4, 1.0, 0.6, 1.0)
	_key_pressed_style.set_corner_radius_all(8)
	_key_pressed_style.set_content_margin_all(8)


func _build_ui() -> void:
	# 1. Dark translucent backdrop
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0.03, 0.05, 0.08, 0.65)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close(false)
	)
	add_child(_backdrop)

	# 2. Main Keyboard Panel (anchored at bottom-center)
	_main_panel = PanelContainer.new()
	_main_panel.name = "VirtualKeyboardPanel"
	_main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_main_panel.custom_minimum_size = Vector2(1060, 440)
	_main_panel.anchor_left = 0.5
	_main_panel.anchor_right = 0.5
	_main_panel.anchor_top = 1.0
	_main_panel.anchor_bottom = 1.0
	_main_panel.offset_left = -530
	_main_panel.offset_right = 530
	_main_panel.offset_top = -455
	_main_panel.offset_bottom = -15

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.10, 0.15, 0.96)
	panel_style.border_color = Color(0.24, 0.44, 0.65, 0.7)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel_style.set_content_margin_all(16)
	panel_style.shadow_color = Color(0, 0, 0, 0.7)
	panel_style.shadow_size = 18
	_main_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_main_panel)

	# 3. Main vertical stack
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_main_panel.add_child(main_vbox)

	# 3a. Header row: Title + Char count
	var header_hbox = HBoxContainer.new()
	header_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_title_label = Label.new()
	_title_label.text = "⌨ VIRTUAL KEYBOARD"
	_title_label.add_theme_font_size_override("font_size", 16)
	_title_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_ACCENT)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(_title_label)

	_char_count_label = Label.new()
	_char_count_label.text = ""
	_char_count_label.add_theme_font_size_override("font_size", 14)
	_char_count_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	_char_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_hbox.add_child(_char_count_label)
	main_vbox.add_child(header_hbox)

	# 3b. Text Input Preview Box
	var preview_panel = PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(0, 52)
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var prev_style = StyleBoxFlat.new()
	prev_style.bg_color = Color(0.04, 0.07, 0.10, 0.95)
	prev_style.set_border_width_all(1)
	prev_style.border_color = Color(0.24, 0.44, 0.65, 0.6)
	prev_style.set_corner_radius_all(8)
	prev_style.content_margin_left = 16
	prev_style.content_margin_right = 16
	prev_style.content_margin_top = 8
	prev_style.content_margin_bottom = 8
	preview_panel.add_theme_stylebox_override("panel", prev_style)

	var preview_hbox = HBoxContainer.new()
	preview_hbox.add_theme_constant_override("separation", 2)
	preview_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_preview_label = Label.new()
	_preview_label.text = ""
	_preview_label.add_theme_font_size_override("font_size", 22)
	_preview_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	_preview_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_hbox.add_child(_preview_label)

	_caret_label = Label.new()
	_caret_label.text = "|"
	_caret_label.add_theme_font_size_override("font_size", 24)
	_caret_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_ACCENT)
	_caret_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_hbox.add_child(_caret_label)

	preview_panel.add_child(preview_hbox)
	main_vbox.add_child(preview_panel)

	# 3c. Keyboard Keys Container
	_keys_vbox = VBoxContainer.new()
	_keys_vbox.add_theme_constant_override("separation", 6)
	_keys_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keys_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_keys_vbox)

	_build_keyboard_rows()

	# 3d. Controller Legend Footer
	var legend_panel = PanelContainer.new()
	var leg_style = StyleBoxFlat.new()
	leg_style.bg_color = Color(0.04, 0.06, 0.09, 0.85)
	leg_style.set_corner_radius_all(6)
	leg_style.content_margin_left = 12
	leg_style.content_margin_right = 12
	leg_style.content_margin_top = 4
	leg_style.content_margin_bottom = 4
	legend_panel.add_theme_stylebox_override("panel", leg_style)

	_legend_label = RichTextLabel.new()
	_legend_label.bbcode_enabled = true
	_legend_label.fit_content = true
	_legend_label.scroll_active = false
	_legend_label.text = "[center][color=#64b5f6]Ⓑ[/color] Close   [color=#81c784]Ⓐ[/color] Select   [color=#e57373]Ⓧ[/color] Backspace   [color=#ffd54f]Ⓨ[/color] Space   [color=#81c784]Start[/color] Done   [color=#b0bec5]LB/RB[/color] Cursor   [color=#b0bec5]LT/RT[/color] Shift/Symbols[/center]"
	legend_panel.add_child(_legend_label)
	main_vbox.add_child(legend_panel)


func _build_keyboard_rows() -> void:
	for child in _keys_vbox.get_children():
		child.queue_free()

	_all_key_buttons.clear()
	_key_row_containers.clear()
	_central_key_button = null

	# Row definitions
	# Row 0: Numbers & key IP/URL separators
	var r0_keys: Array = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "_", ".", ":"]
	# Row 1: QWERTY top row
	var r1_keys: Array = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
	# Row 2: QWERTY home row
	var r2_keys: Array = ["a", "s", "d", "f", "g", "h", "j", "k", "l", "@"]
	# Row 3: Shift + bottom row + slash + Backspace
	var r3_letters: Array = ["z", "x", "c", "v", "b", "n", "m", "/"]

	# --- Row 0 ---
	var r0_hbox = _create_row_container()
	for k in r0_keys:
		var btn = _create_key_button(k, k, Vector2(58, 46))
		r0_hbox.add_child(btn)
	_keys_vbox.add_child(r0_hbox)

	# --- Row 1 ---
	var r1_hbox = _create_row_container()
	for k in r1_keys:
		var btn = _create_key_button(k, k, Vector2(74, 46))
		r1_hbox.add_child(btn)
	_keys_vbox.add_child(r1_hbox)

	# --- Row 2 ---
	var r2_hbox = _create_row_container()
	for k in r2_keys:
		var btn = _create_key_button(k, k, Vector2(74, 46))
		if k == "g" or k == "h":
			_central_key_button = btn
		r2_hbox.add_child(btn)
	_keys_vbox.add_child(r2_hbox)

	# --- Row 3 ---
	var r3_hbox = _create_row_container()
	_shift_btn = _create_action_button("⇧ Shift", Callable(self, "_on_shift_pressed"), Vector2(105, 46))
	r3_hbox.add_child(_shift_btn)
	for k in r3_letters:
		var btn = _create_key_button(k, k, Vector2(74, 46))
		r3_hbox.add_child(btn)
	var backspace_btn = _create_action_button("⌫ Back", Callable(self, "_on_backspace_pressed"), Vector2(105, 46))
	ThemeManager.apply_danger_button_style(backspace_btn, 8)
	_apply_focus_override(backspace_btn)
	r3_hbox.add_child(backspace_btn)
	_keys_vbox.add_child(r3_hbox)

	# --- Row 4: Utility & Actions ---
	var r4_hbox = _create_row_container()
	_symbols_btn = _create_action_button("?123", Callable(self, "_on_symbols_pressed"), Vector2(90, 48))
	r4_hbox.add_child(_symbols_btn)

	var cursor_left_btn = _create_action_button("◀ Left", func(): _move_cursor(-1), Vector2(85, 48))
	r4_hbox.add_child(cursor_left_btn)

	var cursor_right_btn = _create_action_button("Right ▶", func(): _move_cursor(1), Vector2(85, 48))
	r4_hbox.add_child(cursor_right_btn)

	var space_btn = _create_action_button("Space", Callable(self, "_on_space_pressed"), Vector2(240, 48))
	space_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r4_hbox.add_child(space_btn)

	var clear_btn = _create_action_button("Clear", Callable(self, "_on_clear_pressed"), Vector2(85, 48))
	ThemeManager.apply_nav_button_style(clear_btn, 8)
	_apply_focus_override(clear_btn)
	r4_hbox.add_child(clear_btn)

	var done_btn = _create_action_button("✔ Done", Callable(self, "_on_done_pressed"), Vector2(120, 48))
	ThemeManager.apply_primary_button_style(done_btn, 8)
	_apply_focus_override(done_btn)
	r4_hbox.add_child(done_btn)

	var cancel_btn = _create_action_button("✖ Cancel", Callable(self, "_on_cancel_pressed"), Vector2(100, 48))
	ThemeManager.apply_nav_button_style(cancel_btn, 8)
	_apply_focus_override(cancel_btn)
	r4_hbox.add_child(cancel_btn)

	_keys_vbox.add_child(r4_hbox)

	call_deferred("_setup_focus_grid")


func _create_row_container() -> HBoxContainer:
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 6)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key_row_containers.append(hbox)
	return hbox


func _create_key_button(display_char: String, char_val: String, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.text = display_char
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 20)
	btn.focus_mode = Control.FOCUS_ALL

	_apply_standard_key_styles(btn)
	btn.pressed.connect(func(): _insert_char(btn.text))
	btn.set_meta("base_char", char_val)
	_all_key_buttons.append(btn)
	return btn


func _create_action_button(label: String, callback: Callable, min_size: Vector2) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = min_size
	btn.add_theme_font_size_override("font_size", 16)
	btn.focus_mode = Control.FOCUS_ALL

	_apply_standard_key_styles(btn)
	btn.pressed.connect(callback)
	return btn


func _apply_standard_key_styles(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", _key_normal_style)
	btn.add_theme_stylebox_override("focus", _key_focus_style)
	btn.add_theme_stylebox_override("hover", _key_hover_style)
	btn.add_theme_stylebox_override("pressed", _key_pressed_style)
	btn.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	btn.add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0))


func _apply_focus_override(btn: Button) -> void:
	btn.add_theme_stylebox_override("focus", _key_focus_style)


func _setup_focus_grid() -> void:
	# Configure nearest-neighbor links between keys across rows for rock-solid D-Pad navigation
	for row_idx in range(_key_row_containers.size()):
		var cur_row = _key_row_containers[row_idx]
		var cur_children: Array = []
		for ch in cur_row.get_children():
			if ch is Button and ch.visible:
				cur_children.append(ch)

		if cur_children.is_empty():
			continue

		for col_idx in range(cur_children.size()):
			var btn: Button = cur_children[col_idx]

			# Left neighbor (wrap around row)
			var prev_col = col_idx - 1 if col_idx > 0 else cur_children.size() - 1
			btn.focus_neighbor_left = cur_children[prev_col].get_path()

			# Right neighbor (wrap around row)
			var next_col = col_idx + 1 if col_idx < cur_children.size() - 1 else 0
			btn.focus_neighbor_right = cur_children[next_col].get_path()

			# Up neighbor (find closest button in row above)
			if row_idx > 0:
				var up_row = _key_row_containers[row_idx - 1]
				var closest_up = _find_closest_button_in_row(btn, up_row)
				if closest_up != null:
					btn.focus_neighbor_top = closest_up.get_path()

			# Down neighbor (find closest button in row below)
			if row_idx < _key_row_containers.size() - 1:
				var down_row = _key_row_containers[row_idx + 1]
				var closest_down = _find_closest_button_in_row(btn, down_row)
				if closest_down != null:
					btn.focus_neighbor_bottom = closest_down.get_path()


func _find_closest_button_in_row(source_btn: Button, target_row: HBoxContainer) -> Button:
	var src_center_x = source_btn.global_position.x + source_btn.size.x * 0.5
	var best_btn: Button = null
	var best_dist := 999999.0

	for ch in target_row.get_children():
		if ch is Button and ch.visible:
			var target_center_x = ch.global_position.x + ch.size.x * 0.5
			var dist = abs(src_center_x - target_center_x)
			if dist < best_dist:
				best_dist = dist
				best_btn = ch

	return best_btn


# ── KEYBOARD STATE & LAYOUT MODES ──────────────────────────────────────

func _update_key_labels() -> void:
	if _shift_btn != null:
		_shift_btn.text = "⇧ SHIFT" if (_shift_active or _caps_lock) else "⇧ Shift"
		if _shift_active or _caps_lock:
			_shift_btn.add_theme_stylebox_override("normal", _key_focus_style)
		else:
			_shift_btn.add_theme_stylebox_override("normal", _key_normal_style)

	if _symbols_btn != null:
		_symbols_btn.text = "ABC" if _symbols_active else "?123"

	# Symbols layout mapping
	var symbol_map = {
		"q": "!", "w": "@", "e": "#", "r": "$", "t": "%", "y": "^", "u": "&", "i": "*", "o": "(", "p": ")",
		"a": "[", "s": "]", "d": "{", "f": "}", "g": "<", "h": ">", "j": "|", "k": "\\", "l": "\"", "@": "'",
		"z": "~", "x": "`", "c": "+", "v": "=", "b": "?", "n": ";", "m": ",", "/": "/"
	}

	for btn in _all_key_buttons:
		if not btn.has_meta("base_char"):
			continue
		var base_char = str(btn.get_meta("base_char"))

		# Number row stays mostly numbers
		if base_char in ["1","2","3","4","5","6","7","8","9","0","-","_",".",":"]:
			if _symbols_active and base_char == "-":
				btn.text = "+"
			elif _symbols_active and base_char == "_":
				btn.text = "="
			else:
				btn.text = base_char
			continue

		if _symbols_active:
			btn.text = symbol_map.get(base_char, base_char)
		elif _shift_active or _caps_lock:
			btn.text = base_char.to_upper()
		else:
			btn.text = base_char.to_lower()


func _on_shift_pressed() -> void:
	_shift_active = not _shift_active
	_update_key_labels()


func _on_symbols_pressed() -> void:
	_symbols_active = not _symbols_active
	_update_key_labels()


# ── TEXT EDITING METHODS ───────────────────────────────────────────────

func _insert_char(char_to_insert: String) -> void:
	# Check length limit
	if _max_length > 0 and _current_text.length() >= _max_length:
		return

	_current_text = _current_text.substr(0, _cursor_pos) + char_to_insert + _current_text.substr(_cursor_pos)
	_cursor_pos += char_to_insert.length()

	# Auto reset transient shift
	if _shift_active and not _caps_lock:
		_shift_active = false
		_update_key_labels()

	_sync_to_target()
	_update_preview()


func _on_backspace_pressed() -> void:
	if _cursor_pos > 0 and not _current_text.is_empty():
		_current_text = _current_text.substr(0, _cursor_pos - 1) + _current_text.substr(_cursor_pos)
		_cursor_pos -= 1
		_sync_to_target()
		_update_preview()


func _on_space_pressed() -> void:
	if _max_length > 0 and _current_text.length() >= _max_length:
		return
	_current_text = _current_text.substr(0, _cursor_pos) + " " + _current_text.substr(_cursor_pos)
	_cursor_pos += 1
	_sync_to_target()
	_update_preview()


func _on_clear_pressed() -> void:
	_current_text = ""
	_cursor_pos = 0
	_sync_to_target()
	_update_preview()


func _move_cursor(delta: int) -> void:
	_cursor_pos = clamp(_cursor_pos + delta, 0, _current_text.length())
	_caret_visible = true
	_caret_timer = 0.0
	_sync_target_caret()
	_update_preview()


func _on_done_pressed() -> void:
	_submit_and_close()


func _on_cancel_pressed() -> void:
	close(true)


func _submit_and_close() -> void:
	var target = _target_control
	var submitted_text = _current_text
	if target != null and is_instance_valid(target):
		if target is LineEdit:
			(target as LineEdit).text = submitted_text
		elif target is TextEdit:
			(target as TextEdit).text = submitted_text

	# Close first without restoring focus to the target control, because text_submitted
	# will either advance focus to the next field (e.g. Email or Tee) or keep it on target cleanly.
	close(false, false)

	if target != null and is_instance_valid(target):
		if target is LineEdit:
			(target as LineEdit).text_submitted.emit(submitted_text)

	var vp = get_viewport()
	if vp != null and vp.gui_get_focus_owner() == null and target != null and is_instance_valid(target):
		target.grab_focus()

	text_submitted.emit(submitted_text)


func _sync_to_target() -> void:
	if _target_control != null and is_instance_valid(_target_control):
		if _target_control is LineEdit:
			var le = _target_control as LineEdit
			le.text = _current_text
			le.caret_column = _cursor_pos
			le.emit_signal("text_changed", _current_text)
		elif _target_control is TextEdit:
			var te = _target_control as TextEdit
			te.text = _current_text
			te.emit_signal("text_changed")

	emit_signal("text_changed", _current_text)


func _sync_target_caret() -> void:
	if _target_control != null and is_instance_valid(_target_control):
		if _target_control is LineEdit:
			(_target_control as LineEdit).caret_column = _cursor_pos


func _update_preview() -> void:
	if _preview_label == null:
		return

	if _current_text.is_empty():
		var placeholder = ""
		if _target_control != null and is_instance_valid(_target_control):
			if _target_control is LineEdit:
				placeholder = (_target_control as LineEdit).placeholder_text
			elif _target_control is TextEdit:
				placeholder = (_target_control as TextEdit).placeholder_text
		if not placeholder.is_empty():
			_preview_label.text = placeholder
			_preview_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
		else:
			_preview_label.text = "Type text here..."
			_preview_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
	else:
		_preview_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
		if _is_secret:
			_preview_label.text = "•".repeat(_current_text.length())
		else:
			_preview_label.text = _current_text

	# Update Char count
	if _char_count_label != null:
		if _max_length > 0:
			_char_count_label.text = "%d / %d" % [_current_text.length(), _max_length]
		else:
			_char_count_label.text = "%d chars" % _current_text.length()


# ── INPUT INTERCEPTION & CONTROLLER SHORTCUTS ──────────────────────────

func _input(event: InputEvent) -> void:
	if not _is_open or _is_closing:
		return

	if not event.is_pressed():
		return

	# Controller Shortcuts
	if event is InputEventJoypadButton:
		var joy = event as InputEventJoypadButton
		match joy.button_index:
			JOY_BUTTON_X:
				# X = Backspace
				_on_backspace_pressed()
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_Y:
				# Y = Space
				_on_space_pressed()
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_START:
				# Start / Menu = Done
				_submit_and_close()
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_B:
				# B = Cancel / Close
				close(true, true)
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_LEFT_SHOULDER:
				# LB = Cursor left
				_move_cursor(-1)
				get_viewport().set_input_as_handled()
				return
			JOY_BUTTON_RIGHT_SHOULDER:
				# RB = Cursor right
				_move_cursor(1)
				get_viewport().set_input_as_handled()
				return

	# Controller Triggers (Axis motion)
	if event is InputEventJoypadMotion:
		var motion = event as InputEventJoypadMotion
		if motion.axis_value > 0.5:
			if motion.axis == JOY_AXIS_TRIGGER_LEFT:
				_on_shift_pressed()
				get_viewport().set_input_as_handled()
				return
			elif motion.axis == JOY_AXIS_TRIGGER_RIGHT:
				_on_symbols_pressed()
				get_viewport().set_input_as_handled()
				return

	# Physical Keyboard support while Virtual Keyboard is open
	if event is InputEventKey and not event.echo:
		var key_ev = event as InputEventKey
		if key_ev.keycode == KEY_BACKSPACE:
			_on_backspace_pressed()
			get_viewport().set_input_as_handled()
			return
		elif key_ev.keycode == KEY_DELETE:
			_delete_forward()
			get_viewport().set_input_as_handled()
			return
		elif key_ev.keycode == KEY_ENTER or key_ev.keycode == KEY_KP_ENTER:
			_submit_and_close()
			get_viewport().set_input_as_handled()
			return
		elif key_ev.keycode == KEY_ESCAPE:
			close(true, true)
			get_viewport().set_input_as_handled()
			return
		elif key_ev.keycode == KEY_LEFT:
			_move_cursor(-1)
			get_viewport().set_input_as_handled()
			return
		elif key_ev.keycode == KEY_RIGHT:
			_move_cursor(1)
			get_viewport().set_input_as_handled()
			return
		elif key_ev.keycode == KEY_SPACE:
			_on_space_pressed()
			get_viewport().set_input_as_handled()
			return
		elif key_ev.unicode != 0 and key_ev.unicode >= 32:
			var ch = char(key_ev.unicode)
			_insert_char(ch)
			get_viewport().set_input_as_handled()
			return


func _delete_forward() -> void:
	if _cursor_pos < _current_text.length():
		_current_text = _current_text.substr(0, _cursor_pos) + _current_text.substr(_cursor_pos + 1)
		_sync_to_target()
		_update_preview()


# ── OPEN & CLOSE LIFECYCLE ─────────────────────────────────────────────

func open(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return

	_target_control = target
	_is_closing = false
	_is_open = true

	# Read target properties
	if target is LineEdit:
		var le = target as LineEdit
		_original_text = le.text
		_current_text = le.text
		_cursor_pos = le.caret_column if (le.caret_column > 0 and le.caret_column <= le.text.length()) else le.text.length()
		_max_length = le.max_length
		_is_secret = le.secret
		_derive_context_title(le)
	elif target is TextEdit:
		var te = target as TextEdit
		_original_text = te.text
		_current_text = te.text
		_cursor_pos = te.text.length()
		_max_length = 0
		_is_secret = false
		_title_label.text = "⌨ EDIT TEXT"

	_shift_active = false
	_caps_lock = false
	_symbols_active = false
	_update_key_labels()
	_update_preview()

	# Show UI
	visible = true
	_backdrop.modulate.a = 0.0
	_main_panel.modulate.a = 0.0

	# Animate in: slide up & fade in
	if _anim_tween != null and _anim_tween.is_running():
		_anim_tween.kill()

	_main_panel.offset_top = -400
	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_anim_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.22)
	_anim_tween.tween_property(_main_panel, "modulate:a", 1.0, 0.22)
	_anim_tween.tween_property(_main_panel, "offset_top", -455.0, 0.22)

	# Focus lock via UIFocusGuard
	if has_node("/root/UIFocusGuard"):
		var ufg = get_node("/root/UIFocusGuard")
		ufg.push_lock(self)

	# Focus central key for controller ergonomics
	call_deferred("_grab_initial_key_focus")


func _grab_initial_key_focus() -> void:
	if _central_key_button != null and is_instance_valid(_central_key_button):
		_central_key_button.grab_focus()
	elif not _all_key_buttons.is_empty() and is_instance_valid(_all_key_buttons[0]):
		_all_key_buttons[0].grab_focus()


func _derive_context_title(le: LineEdit) -> void:
	var title = "⌨ VIRTUAL KEYBOARD"

	# Infer context from parent nodes, placeholder, or name
	var p_name = le.name.to_lower()
	var holder = le.placeholder_text.strip_edges()

	if p_name.contains("search") or holder.to_lower().contains("search") or holder.to_lower().contains("course"):
		title = "🔍 SEARCH COURSE (OPENSTREETMAP)"
	elif p_name.contains("name") or holder.to_lower().contains("player"):
		title = "👤 ENTER PLAYER NAME"
	elif p_name.contains("email") or holder.to_lower().contains("email"):
		title = "✉ ENTER EMAIL ADDRESS"
	elif p_name.contains("ip") or holder.contains("192.168") or holder.contains("0.0.0.0"):
		title = "🌐 ENTER CAMERA / NETWORK IP"
	elif p_name.contains("dir") or holder.to_lower().contains("directory"):
		title = "📁 ENTER DIRECTORY PATH"
	elif not holder.is_empty():
		title = "⌨ " + holder.to_upper()

	if _title_label != null:
		_title_label.text = title


func close(restore_original: bool = false, restore_focus: bool = true) -> void:
	if not _is_open or _is_closing:
		return

	_is_closing = true
	_is_open = false
	closing.emit()

	if restore_original and _target_control != null and is_instance_valid(_target_control):
		if _target_control is LineEdit:
			(_target_control as LineEdit).text = _original_text
		elif _target_control is TextEdit:
			(_target_control as TextEdit).text = _original_text

	# Release focus lock
	if has_node("/root/UIFocusGuard"):
		var ufg = get_node("/root/UIFocusGuard")
		if ufg.current_lock_root() == self:
			ufg.pop_lock(restore_focus)

	# Animate out: slide down & fade out
	if _anim_tween != null and _anim_tween.is_running():
		_anim_tween.kill()

	_anim_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_anim_tween.tween_property(_backdrop, "modulate:a", 0.0, 0.16)
	_anim_tween.tween_property(_main_panel, "modulate:a", 0.0, 0.16)
	_anim_tween.tween_property(_main_panel, "offset_top", -400.0, 0.16)
	_anim_tween.finished.connect(func():
		visible = false
		_is_open = false
		_is_closing = false
		emit_signal("closed")
	, CONNECT_ONE_SHOT)


## Called by UIFocusGuard if the lock is popped externally (e.g. ui_cancel)
func _on_focus_lock_popped() -> void:
	if _is_open and not _is_closing:
		close(true, true)


func is_keyboard_open() -> bool:
	return _is_open


func is_closing() -> bool:
	return _is_closing
