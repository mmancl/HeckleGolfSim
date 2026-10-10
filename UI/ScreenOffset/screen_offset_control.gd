class_name ScreenOffsetControl
extends VBoxContainer

## Reusable Screen Offset control widget.
## Contains a toggle button and expandable slider(s) (Left/Right) for lateral address offset.
## In Course Play mode (show_putter_slider = true, is_course_play = true),
## hides recenter button & percent text, and offers dual sliders (General & Putter).

signal offset_toggled(is_on: bool)

var style_button: Callable = Callable()
var is_course_play: bool = false
var show_putter_slider: bool = false

var _toggle_btn: Button = null
var _slider_container: VBoxContainer = null

# General / Standard slider
var _slider: HSlider = null
var _value_label: Label = null
var _center_btn: Button = null
var _general_header: Label = null

# Putter slider (used in Course Play)
var _putter_slider: HSlider = null
var _putter_value_label: Label = null
var _putter_center_btn: Button = null
var _putter_header: Label = null

var _updating_ui: bool = false
var _last_toggle_nudge_time: float = 0.0


func _init() -> void:
	name = "ScreenOffsetControl"
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_build_ui()
	_sync_from_manager()
	if Engine.has_singleton("ScreenOffsetManager") or has_node("/root/ScreenOffsetManager"):
		var som = get_node_or_null("/root/ScreenOffsetManager")
		if som != null and som.has_signal("offset_changed"):
			som.offset_changed.connect(_on_manager_offset_changed)


func _exit_tree() -> void:
	if has_node("/root/ScreenOffsetManager"):
		var som = get_node_or_null("/root/ScreenOffsetManager")
		if som != null and som.has_signal("offset_changed") and som.offset_changed.is_connected(_on_manager_offset_changed):
			som.offset_changed.disconnect(_on_manager_offset_changed)


func _build_ui() -> void:
	# 1. Main Toggle Button
	_toggle_btn = Button.new()
	_toggle_btn.name = "ScreenOffsetToggleButton"
	_toggle_btn.text = "↔ Screen Offset: OFF"
	_toggle_btn.tooltip_text = "Offset address camera for off-center golf bay hitting strips"
	_toggle_btn.custom_minimum_size = Vector2(180, 56)
	_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toggle_btn.pressed.connect(_on_toggle_pressed)
	_toggle_btn.gui_input.connect(_on_toggle_gui_input)
	add_child(_toggle_btn)

	# 2. Slider container (hidden when toggle is OFF)
	_slider_container = VBoxContainer.new()
	_slider_container.name = "SliderContainer"
	_slider_container.add_theme_constant_override("separation", 4)
	_slider_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_slider_container)

	# Optional Header for General Shots (when dual sliders shown)
	if show_putter_slider:
		_general_header = Label.new()
		_general_header.text = "General Offset:"
		_general_header.add_theme_font_size_override("font_size", 13)
		_general_header.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		_slider_container.add_child(_general_header)

	# Standard Slider row with L / Slider / R
	var slider_row = HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 8)
	slider_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slider_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_container.add_child(slider_row)

	var l_lbl = Label.new()
	l_lbl.text = "L"
	l_lbl.add_theme_font_size_override("font_size", 14)
	l_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	slider_row.add_child(l_lbl)

	_slider = HSlider.new()
	_slider.name = "OffsetSlider"
	_slider.min_value = -1.0
	_slider.max_value = 1.0
	_slider.step = 0.05
	_slider.value = 0.0
	_slider.custom_minimum_size = Vector2(120, 44)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.value_changed.connect(_on_slider_value_changed)
	_slider.drag_ended.connect(_on_slider_drag_ended)
	slider_row.add_child(_slider)

	var r_lbl = Label.new()
	r_lbl.text = "R"
	r_lbl.add_theme_font_size_override("font_size", 14)
	r_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	slider_row.add_child(r_lbl)

	# Details row for standard slider
	var info_row = HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 6)
	info_row.alignment = BoxContainer.ALIGNMENT_CENTER
	info_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider_container.add_child(info_row)

	_value_label = Label.new()
	_value_label.text = "Center"
	_value_label.add_theme_font_size_override("font_size", 13)
	_value_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(_value_label)

	_center_btn = Button.new()
	_center_btn.name = "CenterButton"
	_center_btn.text = "⟲ Center"
	_center_btn.custom_minimum_size = Vector2(76, 32)
	_center_btn.add_theme_font_size_override("font_size", 12)
	_center_btn.pressed.connect(_on_center_pressed)
	info_row.add_child(_center_btn)

	# Putter slider (used in Course Play)
	if show_putter_slider:
		_putter_header = Label.new()
		_putter_header.text = "Putter Offset:"
		_putter_header.add_theme_font_size_override("font_size", 13)
		_putter_header.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		_slider_container.add_child(_putter_header)

		var putter_row = HBoxContainer.new()
		putter_row.add_theme_constant_override("separation", 8)
		putter_row.alignment = BoxContainer.ALIGNMENT_CENTER
		putter_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slider_container.add_child(putter_row)

		var p_l_lbl = Label.new()
		p_l_lbl.text = "L"
		p_l_lbl.add_theme_font_size_override("font_size", 14)
		p_l_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		putter_row.add_child(p_l_lbl)

		_putter_slider = HSlider.new()
		_putter_slider.name = "PutterOffsetSlider"
		_putter_slider.min_value = -1.0
		_putter_slider.max_value = 1.0
		_putter_slider.step = 0.05
		_putter_slider.value = 0.0
		_putter_slider.custom_minimum_size = Vector2(120, 44)
		_putter_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_putter_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_putter_slider.value_changed.connect(_on_putter_slider_value_changed)
		_putter_slider.drag_ended.connect(_on_slider_drag_ended)
		putter_row.add_child(_putter_slider)

		var p_r_lbl = Label.new()
		p_r_lbl.text = "R"
		p_r_lbl.add_theme_font_size_override("font_size", 14)
		p_r_lbl.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		putter_row.add_child(p_r_lbl)

		var p_info_row = HBoxContainer.new()
		p_info_row.add_theme_constant_override("separation", 6)
		p_info_row.alignment = BoxContainer.ALIGNMENT_CENTER
		p_info_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slider_container.add_child(p_info_row)

		_putter_value_label = Label.new()
		_putter_value_label.text = "Center"
		_putter_value_label.add_theme_font_size_override("font_size", 13)
		_putter_value_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		_putter_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_info_row.add_child(_putter_value_label)

		_putter_center_btn = Button.new()
		_putter_center_btn.name = "PutterCenterButton"
		_putter_center_btn.text = "⟲ Center"
		_putter_center_btn.custom_minimum_size = Vector2(76, 32)
		_putter_center_btn.add_theme_font_size_override("font_size", 12)
		_putter_center_btn.pressed.connect(_on_putter_center_pressed)
		p_info_row.add_child(_putter_center_btn)


func _on_toggle_pressed() -> void:
	if not has_node("/root/GlobalSettings"):
		return
	var current_on = GlobalSettings.range_settings.screen_offset_enabled.value
	var new_on = not current_on
	if has_node("/root/ScreenOffsetManager"):
		get_node("/root/ScreenOffsetManager").set_enabled(new_on)
	else:
		GlobalSettings.range_settings.screen_offset_enabled.value = new_on
		GlobalSettings.save_settings()
	_sync_from_manager()


func _on_toggle_gui_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var is_left: bool = event.is_action_pressed("ui_left") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_DPAD_LEFT)
	var is_right: bool = event.is_action_pressed("ui_right") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_DPAD_RIGHT)
	if not is_left and not is_right and event is InputEventJoypadMotion and abs(event.axis_value) >= 0.5 and event.axis == JOY_AXIS_LEFT_X:
		var now := Time.get_ticks_msec() / 1000.0
		if (now - _last_toggle_nudge_time) >= 0.2:
			_last_toggle_nudge_time = now
			is_left = event.axis_value < 0.0
			is_right = event.axis_value > 0.0

	if is_left or is_right:
		var rs = GlobalSettings.range_settings if has_node("/root/GlobalSettings") else null
		if rs != null:
			if not rs.screen_offset_enabled.value:
				if has_node("/root/ScreenOffsetManager"):
					get_node("/root/ScreenOffsetManager").set_enabled(true)
				else:
					rs.screen_offset_enabled.value = true
					GlobalSettings.save_settings()
				_sync_from_manager()
			var delta := -0.05 if is_left else 0.05
			var cur_val: float = _slider.value if _slider != null else rs.screen_offset_value.value
			var new_val = clampf(cur_val + delta, -1.0, 1.0)
			if _slider != null:
				_slider.value = new_val
			_on_slider_value_changed(new_val)
			if has_node("/root/GlobalSettings"):
				GlobalSettings.save_settings()
			get_viewport().set_input_as_handled()


func _on_slider_value_changed(val: float) -> void:
	if _updating_ui:
		return
	if is_zero_approx(val) or absf(val) < 0.01:
		val = 0.0
		if _slider != null:
			_slider.set_value_no_signal(0.0)
	_update_value_label(val)
	if has_node("/root/ScreenOffsetManager"):
		var som = get_node("/root/ScreenOffsetManager")
		if not show_putter_slider and som.is_putter_active():
			som.set_putter_value(val, true)
		else:
			som.set_value(val, true)


func _on_putter_slider_value_changed(val: float) -> void:
	if _updating_ui:
		return
	if is_zero_approx(val) or absf(val) < 0.01:
		val = 0.0
		if _putter_slider != null:
			_putter_slider.set_value_no_signal(0.0)
	_update_putter_value_label(val)
	if has_node("/root/ScreenOffsetManager"):
		get_node("/root/ScreenOffsetManager").set_putter_value(val, true)


func _on_slider_drag_ended(_val_changed: bool) -> void:
	if has_node("/root/GlobalSettings"):
		GlobalSettings.save_settings()


func _on_center_pressed() -> void:
	if _slider != null:
		_slider.value = 0.0
	_update_value_label(0.0)
	if has_node("/root/ScreenOffsetManager"):
		var som = get_node("/root/ScreenOffsetManager")
		if not show_putter_slider and som.is_putter_active():
			som.set_putter_value(0.0, false)
		else:
			som.set_value(0.0, false)
	elif has_node("/root/GlobalSettings"):
		GlobalSettings.range_settings.screen_offset_value.value = 0.0
		GlobalSettings.save_settings()


func _on_putter_center_pressed() -> void:
	if _putter_slider != null:
		_putter_slider.value = 0.0
	_update_putter_value_label(0.0)
	if has_node("/root/ScreenOffsetManager"):
		get_node("/root/ScreenOffsetManager").set_putter_value(0.0, false)
	elif has_node("/root/GlobalSettings"):
		var rs = GlobalSettings.range_settings
		if "screen_offset_putter_value" in rs:
			rs.screen_offset_putter_value.value = 0.0
		GlobalSettings.save_settings()


func _on_manager_offset_changed(_val: float) -> void:
	_sync_from_manager()


func _sync_from_manager() -> void:
	if not is_inside_tree():
		return
	if not has_node("/root/GlobalSettings"):
		return
	_updating_ui = true
	var rs = GlobalSettings.range_settings
	var is_on: bool = rs.screen_offset_enabled.value
	var val: float = rs.screen_offset_value.value
	var p_val: float = rs.screen_offset_putter_value.value if "screen_offset_putter_value" in rs else 0.0
	var som = get_node_or_null("/root/ScreenOffsetManager") if has_node("/root/ScreenOffsetManager") else null
	var putter_mode: bool = (som != null and som.is_putter_active())

	if _toggle_btn != null:
		_toggle_btn.text = "↔ Screen Offset: ON" if is_on else "↔ Screen Offset: OFF"
		if style_button.is_valid():
			style_button.call(_toggle_btn, is_on)

	if _slider_container != null:
		_slider_container.visible = is_on

	var displayed_val: float = p_val if (not show_putter_slider and putter_mode) else val
	if _slider != null:
		_slider.value = displayed_val

	if _putter_slider != null:
		_putter_slider.value = p_val

	_update_value_label(displayed_val)
	_update_putter_value_label(p_val)
	_updating_ui = false

	# Wire internal focus navigation
	if is_on and _slider != null and _toggle_btn != null:
		_toggle_btn.focus_neighbor_bottom = _slider.get_path()
		_slider.focus_neighbor_top = _toggle_btn.get_path()
		if _center_btn != null:
			_slider.focus_neighbor_bottom = _center_btn.get_path()
			_center_btn.focus_neighbor_top = _slider.get_path()
			if _putter_slider != null:
				_center_btn.focus_neighbor_bottom = _putter_slider.get_path()
				_putter_slider.focus_neighbor_top = _center_btn.get_path()
				if _putter_center_btn != null:
					_putter_slider.focus_neighbor_bottom = _putter_center_btn.get_path()
					_putter_center_btn.focus_neighbor_top = _putter_slider.get_path()
		elif _putter_slider != null:
			_slider.focus_neighbor_bottom = _putter_slider.get_path()
			_putter_slider.focus_neighbor_top = _slider.get_path()
			if _putter_center_btn != null:
				_putter_slider.focus_neighbor_bottom = _putter_center_btn.get_path()
				_putter_center_btn.focus_neighbor_top = _putter_slider.get_path()

	emit_signal("offset_toggled", is_on)


func _update_value_label(val: float) -> void:
	if _value_label == null:
		return
	if absf(val) < 0.02:
		_value_label.text = "Center"
	elif val < 0.0:
		_value_label.text = "Left %d%%" % int(round(absf(val) * 100.0))
	else:
		_value_label.text = "Right %d%%" % int(round(val * 100.0))


func _update_putter_value_label(val: float) -> void:
	if _putter_value_label == null:
		return
	if absf(val) < 0.02:
		_putter_value_label.text = "Center"
	elif val < 0.0:
		_putter_value_label.text = "Left %d%%" % int(round(absf(val) * 100.0))
	else:
		_putter_value_label.text = "Right %d%%" % int(round(val * 100.0))


func get_focusables() -> Array[Control]:
	var result: Array[Control] = []
	if _toggle_btn != null and _toggle_btn.visible:
		result.append(_toggle_btn)
	if _slider_container != null and _slider_container.visible:
		if _slider != null and _slider.visible:
			result.append(_slider)
		if _center_btn != null and _center_btn.visible:
			result.append(_center_btn)
		if _putter_slider != null and _putter_slider.visible:
			result.append(_putter_slider)
		if _putter_center_btn != null and _putter_center_btn.visible:
			result.append(_putter_center_btn)
	return result


## Static helper for Minigames: creates a compact launcher button and a popup panel containing ScreenOffsetControl
static func create_minigame_launcher(host: Node, ctrl_hbox: HBoxContainer, apply_style_fn: Callable) -> Button:
	var launcher_btn = Button.new()
	launcher_btn.name = "ScreenOffsetLauncherButton"
	launcher_btn.text = "↔ Offset"
	launcher_btn.custom_minimum_size = Vector2(100, 52)
	launcher_btn.add_theme_font_size_override("font_size", 15)
	if apply_style_fn.is_valid():
		apply_style_fn.call(launcher_btn, Color(0.20, 0.25, 0.35), Color(0.28, 0.35, 0.48))

	# Find canvas or root control to attach floating popup panel
	var parent_canvas: Node = host
	for ch in host.get_children():
		if ch is CanvasLayer:
			parent_canvas = ch
			break

	var popup_panel = PanelContainer.new()
	popup_panel.name = "ScreenOffsetPopupPanel"
	popup_panel.visible = false
	popup_panel.custom_minimum_size = Vector2(240, 140)
	
	# Style the popup container
	var sbox = StyleBoxFlat.new()
	sbox.bg_color = Color(0.12, 0.15, 0.20, 0.95)
	sbox.border_width_left = 1
	sbox.border_width_top = 1
	sbox.border_width_right = 1
	sbox.border_width_bottom = 1
	sbox.border_color = Color(0.4, 0.6, 0.9, 0.4)
	sbox.corner_radius_top_left = 8
	sbox.corner_radius_top_right = 8
	sbox.corner_radius_bottom_right = 8
	sbox.corner_radius_bottom_left = 8
	popup_panel.add_theme_stylebox_override("panel", sbox)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	popup_panel.add_child(margin)

	var so_script = load("res://UI/ScreenOffset/screen_offset_control.gd") as GDScript
	var so_ctrl = so_script.new()
	so_ctrl.style_button = func(btn: Button, is_on: bool):
		if apply_style_fn.is_valid():
			if is_on:
				apply_style_fn.call(btn, Color(0.18, 0.45, 0.65), Color(0.25, 0.58, 0.82))
			else:
				apply_style_fn.call(btn, Color(0.20, 0.25, 0.35), Color(0.28, 0.35, 0.48))
	margin.add_child(so_ctrl)

	parent_canvas.add_child(popup_panel)

	# Position popup above launcher button when shown
	launcher_btn.pressed.connect(func():
		# Do not open if settings layer is open
		var sl = host.get("_settings_layer")
		if sl != null and is_instance_valid(sl):
			return
		popup_panel.visible = not popup_panel.visible
		if popup_panel.visible:
			var btn_rect = launcher_btn.get_global_rect()
			popup_panel.position = Vector2(
				clampf(btn_rect.position.x - 70, 10, host.get_viewport().get_visible_rect().size.x - 260),
				btn_rect.position.y - 150
			)
			launcher_btn.text = "↔ Offset: ▲"
		else:
			launcher_btn.text = "↔ Offset"
	)

	ctrl_hbox.add_child(launcher_btn)
	return launcher_btn
