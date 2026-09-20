class_name StatsCustomizationModal
extends CanvasLayer

signal modal_closed

var _stats_count_label: Label = null
var _warning_banner: PanelContainer = null
var _warning_label: Label = null
var _checkboxes_by_stat_id: Dictionary = {}
var _check_button_list: Array[CheckButton] = []
var _close_btn: Button = null
var _reset_btn: Button = null
var _done_btn: Button = null

func _init() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_build_ui()
	call_deferred("_grab_initial_focus")

func _grab_initial_focus() -> void:
	if not _check_button_list.is_empty() and is_instance_valid(_check_button_list[0]):
		_check_button_list[0].grab_focus()
	elif _close_btn != null and is_instance_valid(_close_btn):
		_close_btn.grab_focus()

func _build_ui() -> void:
	# Fullscreen dark translucent backdrop
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.04, 0.06, 0.09, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close()
	)
	add_child(backdrop)

	# Center wrapper
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# Modal Dialog Panel
	var modal_panel := PanelContainer.new()
	modal_panel.name = "ModalPanel"
	modal_panel.custom_minimum_size = Vector2(780, 680)
	modal_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ThemeManager.apply_modal_style(modal_panel, 14)
	center.add_child(modal_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_panel.add_child(main_vbox)

	# Top Header Bar: Title + Close Button
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 12)

	var title_lbl := Label.new()
	title_lbl.text = "🎯 Customize Displayed Statistics"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(40, 40)
	close_btn.tooltip_text = "Close (Esc)"
	ThemeManager.apply_nav_button_style(close_btn, 8)
	close_btn.pressed.connect(close)
	header_hbox.add_child(close_btn)

	main_vbox.add_child(header_hbox)

	# Header Info & Active Count Card
	var info_card := PanelContainer.new()
	ThemeManager.apply_card_panel_style(info_card, true, 8, 14, 10, 14, 10)
	
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 6)

	var info_top_hbox := HBoxContainer.new()
	info_top_hbox.add_theme_constant_override("separation", 12)

	var info_desc := Label.new()
	info_desc.text = "Select up to %d metrics to display on screen during play. The Add/Remove button is always shown as the last stat box (bottom right when %d stats are active)." % [StatDefinitions.MAX_DISPLAYED_STATS, StatDefinitions.MAX_DISPLAYED_STATS]
	info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_desc.add_theme_font_size_override("font_size", 14)
	info_desc.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	info_top_hbox.add_child(info_desc)

	_stats_count_label = Label.new()
	_stats_count_label.add_theme_font_size_override("font_size", 17)
	info_top_hbox.add_child(_stats_count_label)
	info_vbox.add_child(info_top_hbox)

	# Warning banner when limit reached
	_warning_banner = PanelContainer.new()
	_warning_banner.visible = false
	var warn_style := StyleBoxFlat.new()
	warn_style.bg_color = Color(0.40, 0.15, 0.15, 0.85)
	warn_style.border_color = Color(0.95, 0.40, 0.40, 0.90)
	warn_style.border_width_left = 1
	warn_style.border_width_top = 1
	warn_style.border_width_right = 1
	warn_style.border_width_bottom = 1
	warn_style.corner_radius_top_left = 6
	warn_style.corner_radius_top_right = 6
	warn_style.corner_radius_bottom_right = 6
	warn_style.corner_radius_bottom_left = 6
	warn_style.content_margin_left = 12
	warn_style.content_margin_top = 6
	warn_style.content_margin_right = 12
	warn_style.content_margin_bottom = 6
	_warning_banner.add_theme_stylebox_override("panel", warn_style)

	_warning_label = Label.new()
	_warning_label.text = "⚠️ Maximum limit of %d stats reached. Disable an enabled stat before adding another." % StatDefinitions.MAX_DISPLAYED_STATS
	_warning_label.add_theme_font_size_override("font_size", 14)
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.9))
	_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warning_banner.add_child(_warning_label)
	info_vbox.add_child(_warning_banner)

	info_card.add_child(info_vbox)
	main_vbox.add_child(info_card)

	_update_count_label()

	# Scrollable stats list
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	ThemeManager.apply_scroll_container_style(scroll, 20)

	var stats_list_vbox := VBoxContainer.new()
	stats_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_list_vbox.add_theme_constant_override("separation", 12)

	var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true

	_check_button_list.clear()

	var categories = ["Ball Flight", "Club Delivery", "Trajectory"]
	for cat in categories:
		var cat_lbl := Label.new()
		cat_lbl.text = cat.to_upper() + " METRICS"
		cat_lbl.add_theme_font_size_override("font_size", 16)
		cat_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		stats_list_vbox.add_child(cat_lbl)

		for stat in StatDefinitions.STATS:
			if stat.get("category", "") != cat:
				continue
			var card := _create_stat_card(stat, is_imperial)
			stats_list_vbox.add_child(card)

		var sep := HSeparator.new()
		stats_list_vbox.add_child(sep)

	scroll.add_child(stats_list_vbox)
	main_vbox.add_child(scroll)

	# Footer Actions: Reset to Defaults + Done Button
	var footer_hbox := HBoxContainer.new()
	footer_hbox.add_theme_constant_override("separation", 12)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(160, 44)
	ThemeManager.apply_nav_button_style(reset_btn, 8)
	reset_btn.pressed.connect(_on_reset_to_defaults_pressed)
	footer_hbox.add_child(reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hbox.add_child(spacer)

	var done_btn := Button.new()
	done_btn.text = "Done"
	done_btn.custom_minimum_size = Vector2(130, 44)
	ThemeManager.apply_primary_button_style(done_btn, 8)
	done_btn.pressed.connect(close)
	footer_hbox.add_child(done_btn)

	main_vbox.add_child(footer_hbox)

	_close_btn = close_btn
	_reset_btn = reset_btn
	_done_btn = done_btn

	if not _check_button_list.is_empty():
		_close_btn.focus_neighbor_bottom = _close_btn.get_path_to(_check_button_list[0])
		for i in range(_check_button_list.size()):
			var cb = _check_button_list[i]
			if i == 0:
				cb.focus_neighbor_top = cb.get_path_to(_close_btn)
			else:
				cb.focus_neighbor_top = cb.get_path_to(_check_button_list[i - 1])
			if i < _check_button_list.size() - 1:
				cb.focus_neighbor_bottom = cb.get_path_to(_check_button_list[i + 1])
			else:
				cb.focus_neighbor_bottom = cb.get_path_to(_done_btn)
		
		_reset_btn.focus_neighbor_top = _reset_btn.get_path_to(_check_button_list.back())
		_done_btn.focus_neighbor_top = _done_btn.get_path_to(_check_button_list.back())

	_reset_btn.focus_neighbor_right = _reset_btn.get_path_to(_done_btn)
	_reset_btn.focus_neighbor_left = _reset_btn.get_path_to(_reset_btn)
	_done_btn.focus_neighbor_left = _done_btn.get_path_to(_reset_btn)
	_done_btn.focus_neighbor_right = _done_btn.get_path_to(_done_btn)


func _create_stat_card(stat: Dictionary, is_imperial: bool) -> PanelContainer:
	var card := PanelContainer.new()
	ThemeManager.apply_card_panel_style(card, false, 8, 14, 8, 14, 8)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 3)

	var title_hbox := HBoxContainer.new()
	title_hbox.add_theme_constant_override("separation", 10)

	var title_lbl := Label.new()
	title_lbl.text = str(stat.get("name", ""))
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WHITE)
	title_hbox.add_child(title_lbl)

	var u_str = str(stat.get("units_imperial" if is_imperial else "units_metric", ""))
	var short_badge := Label.new()
	short_badge.text = "[Tile: %s | %s]" % [str(stat.get("short_label", "")), u_str]
	short_badge.add_theme_font_size_override("font_size", 13)
	short_badge.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DIM)
	title_hbox.add_child(short_badge)

	text_vbox.add_child(title_hbox)

	var desc_lbl := Label.new()
	desc_lbl.text = str(stat.get("description", ""))
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	text_vbox.add_child(desc_lbl)

	hbox.add_child(text_vbox)

	var check_btn := CheckButton.new()
	check_btn.custom_minimum_size = Vector2(68, 44)
	check_btn.focus_mode = Control.FOCUS_ALL

	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(0.15, 0.25, 0.35, 0.6)
	focus_style.border_color = Color(0.35, 0.82, 1.0, 0.95)
	focus_style.border_width_left = 2
	focus_style.border_width_top = 2
	focus_style.border_width_right = 2
	focus_style.border_width_bottom = 2
	focus_style.corner_radius_top_left = 6
	focus_style.corner_radius_top_right = 6
	focus_style.corner_radius_bottom_left = 6
	focus_style.corner_radius_bottom_right = 6
	check_btn.add_theme_stylebox_override("focus", focus_style)

	var stat_id := str(stat.get("id", ""))
	var active_stats: Array = GlobalSettings.range_settings.displayed_stats.value if has_node("/root/GlobalSettings") else StatDefinitions.DEFAULT_ENABLED_STAT_IDS
	check_btn.set_pressed_no_signal(active_stats.has(stat_id))
	_checkboxes_by_stat_id[stat_id] = check_btn
	_check_button_list.append(check_btn)

	check_btn.toggled.connect(func(toggled_on: bool):
		_on_stat_toggled(stat_id, toggled_on, check_btn)
	)

	check_btn.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_left") and check_btn.button_pressed:
			check_btn.button_pressed = false
			get_viewport().set_input_as_handled()
		elif ev.is_action_pressed("ui_right") and not check_btn.button_pressed:
			check_btn.button_pressed = true
			get_viewport().set_input_as_handled()
	)

	hbox.add_child(check_btn)
	card.add_child(hbox)
	return card

func _on_stat_toggled(stat_id: String, toggled_on: bool, btn: CheckButton) -> void:
	if not has_node("/root/GlobalSettings"):
		return
	var active_stats: Array = GlobalSettings.range_settings.displayed_stats.value.duplicate()
	if toggled_on:
		if active_stats.size() >= StatDefinitions.MAX_DISPLAYED_STATS:
			btn.set_pressed_no_signal(false)
			if _warning_banner != null:
				_warning_banner.visible = true
			return
		if not active_stats.has(stat_id):
			active_stats.append(stat_id)
	else:
		active_stats.erase(stat_id)

	if _warning_banner != null:
		_warning_banner.visible = false

	GlobalSettings.range_settings.displayed_stats.set_value(active_stats)
	GlobalSettings.save_settings()
	_update_count_label()

func _update_count_label() -> void:
	if _stats_count_label == null or not has_node("/root/GlobalSettings"):
		return
	var active_count: int = GlobalSettings.range_settings.displayed_stats.value.size()
	var max_count := StatDefinitions.MAX_DISPLAYED_STATS
	_stats_count_label.text = "Active: %d / %d (Max %d)" % [active_count, max_count, max_count]
	if active_count >= max_count:
		_stats_count_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_GOLD)
	else:
		_stats_count_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_SUCCESS)

func _on_reset_to_defaults_pressed() -> void:
	if not has_node("/root/GlobalSettings"):
		return
	var default_stats = StatDefinitions.DEFAULT_ENABLED_STAT_IDS.duplicate()
	GlobalSettings.range_settings.displayed_stats.set_value(default_stats)
	GlobalSettings.save_settings()
	if _warning_banner != null:
		_warning_banner.visible = false
	_update_count_label()

	for stat_id in _checkboxes_by_stat_id:
		var cb: CheckButton = _checkboxes_by_stat_id[stat_id]
		if is_instance_valid(cb):
			cb.set_pressed_no_signal(default_stats.has(stat_id))

func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree() or not visible:
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	modal_closed.emit()
	queue_free()
