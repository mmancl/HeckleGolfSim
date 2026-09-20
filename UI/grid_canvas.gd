extends Control

var golfer_camera_active: bool = false:
	set(val):
		golfer_camera_active = val
		_update_camera_shift()

const CELL_SIZE = Vector2(100, 64)
const DATA_PANEL_SCENE = preload("res://UI/data_panel.tscn")

func set_golfer_camera_active(active: bool) -> void:
	golfer_camera_active = active

func _update_camera_shift() -> void:
	if golfer_camera_active:
		position.x = 350.0
	else:
		position.x = 0.0

func _ready():
	sync_data_panels()
	
	if has_node("/root/GlobalSettings"):
		GlobalSettings.range_settings.range_units.setting_changed.connect(func(_v): update_units())
		GlobalSettings.range_settings.displayed_stats.setting_changed.connect(func(_v):
			sync_data_panels()
		)

func sync_data_panels():
	var active_ids: Array = GlobalSettings.range_settings.displayed_stats.value if has_node("/root/GlobalSettings") else StatDefinitions.DEFAULT_ENABLED_STAT_IDS
	var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true
	
	# First, hide and move away all existing panels not in active_ids
	for child in get_children():
		if child.name == "ClubSelector" or child.name == "AddRemoveButton":
			continue
		if not active_ids.has(child.name) and not (child.name == "Speed" and active_ids.has("BallSpeed")) and not (child.name == "BallSpeed" and active_ids.has("Speed")):
			child.visible = false
			child.position = Vector2(-1000, -1000)

	var dist_panel = get_node_or_null("Distance")
	var stats_currently_visible: bool = dist_panel.visible if dist_panel != null else true

	# Now place each active stat strictly in its sequential static slot (0 to N-1)
	for i in range(active_ids.size()):
		var stat_id = str(active_ids[i])
		var panel = get_node_or_null(stat_id)
		if panel == null:
			# Check aliases
			if stat_id == "Offline" and has_node("Side"):
				panel = get_node("Side")
				panel.name = "Offline"
			elif stat_id == "BallSpeed" and has_node("Speed"):
				panel = get_node("Speed")
				panel.name = "BallSpeed"
			elif stat_id == "Speed" and has_node("BallSpeed"):
				panel = get_node("BallSpeed")
				panel.name = "Speed"
			else:
				panel = DATA_PANEL_SCENE.instantiate()
				panel.name = stat_id
				add_child(panel)

		var stat = StatDefinitions.get_stat_by_id(stat_id)
		if not stat.is_empty():
			if panel.has_method("set_label"):
				panel.call("set_label", str(stat.get("short_label", stat_id)))
			var u_str = str(stat.get("units_imperial" if is_imperial else "units_metric", ""))
			if panel.has_method("set_units"):
				panel.call("set_units", u_str)
		
		panel.custom_minimum_size = CELL_SIZE
		panel.size = CELL_SIZE
		panel.position = get_slot_position(i)
		panel.visible = stats_currently_visible

	# Always place the Add/Remove button in the slot immediately following the last stat box
	var add_remove_btn: Button = get_node_or_null("AddRemoveButton")
	if add_remove_btn == null:
		add_remove_btn = _create_add_remove_button()
	else:
		_setup_add_remove_button(add_remove_btn)

	add_remove_btn.custom_minimum_size = CELL_SIZE
	add_remove_btn.size = CELL_SIZE
	add_remove_btn.position = get_slot_position(active_ids.size())
	add_remove_btn.visible = stats_currently_visible

static func get_slot_position(index: int) -> Vector2:
	var row := int(index / 2)
	var col := int(index % 2)
	var x := 0.0 if col == 0 else 106.0
	var y := 360.0 + row * 70.0
	return Vector2(x, y)

func _create_add_remove_button() -> Button:
	var btn := Button.new()
	btn.name = "AddRemoveButton"
	add_child(btn)
	_setup_add_remove_button(btn)
	return btn

func _setup_add_remove_button(btn: Button) -> void:
	btn.text = "＋ / －\nAdd/Remove"
	btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.custom_minimum_size = CELL_SIZE
	btn.size = CELL_SIZE
	btn.add_theme_font_size_override("font_size", 13)
	btn.add_theme_constant_override("line_spacing", 0)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "Configure displayed stats (Add/Remove)"
	ThemeManager.apply_add_remove_tile_style(btn)
	if not btn.pressed.is_connected(_on_add_remove_pressed):
		btn.pressed.connect(_on_add_remove_pressed)

func _on_add_remove_pressed() -> void:
	open_stats_modal()

func open_stats_modal() -> void:
	var add_remove_btn = get_node_or_null("AddRemoveButton")
	var existing = get_tree().root.find_child("StatsCustomizationModal", true, false)
	if existing != null and is_instance_valid(existing):
		existing.visible = true
		if existing.has_method("_grab_initial_focus"):
			existing.call_deferred("_grab_initial_focus")
		return
	var modal_script = load("res://UI/stats_customization_modal.gd")
	if modal_script != null:
		var modal = modal_script.new()
		modal.name = "StatsCustomizationModal"
		modal.modal_closed.connect(func():
			if add_remove_btn != null and is_instance_valid(add_remove_btn) and add_remove_btn.is_visible_in_tree():
				add_remove_btn.call_deferred("grab_focus")
		)
		get_tree().root.add_child(modal)

func reset_layout():
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("layout.cfg"):
		dir.remove("layout.cfg")
	sync_data_panels()

func update_units():
	var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true
	for child in get_children():
		if child.name == "ClubSelector" or child.name == "AddRemoveButton":
			continue
		var stat = StatDefinitions.get_stat_by_id(child.name)
		if not stat.is_empty():
			var u_str = str(stat.get("units_imperial" if is_imperial else "units_metric", ""))
			if child.has_method("set_units"):
				child.call("set_units", u_str)
