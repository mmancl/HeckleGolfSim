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
		if child.name == "ClubSelector":
			continue
		if not active_ids.has(child.name):
			child.visible = false
			child.position = Vector2(-1000, -1000)

	# Now place each active stat strictly in its sequential static slot (0 to N-1)
	for i in range(active_ids.size()):
		var stat_id = str(active_ids[i])
		var panel = get_node_or_null(stat_id)
		if panel == null:
			# Check alias "Side" for "Offline"
			if stat_id == "Offline" and has_node("Side"):
				panel = get_node("Side")
				panel.name = "Offline"
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
		panel.visible = true

static func get_slot_position(index: int) -> Vector2:
	var col := 0 if index < 6 else 1
	var row := index if index < 6 else (index - 6)
	var x := 0.0 if col == 0 else 106.0
	var y := 360.0 + row * 70.0
	return Vector2(x, y)

func reset_layout():
	var dir = DirAccess.open("user://")
	if dir and dir.file_exists("layout.cfg"):
		dir.remove("layout.cfg")
	sync_data_panels()

func update_units():
	var is_imperial: bool = GlobalSettings.range_settings.range_units.value == PhysicsEnums.Units.IMPERIAL if has_node("/root/GlobalSettings") else true
	for child in get_children():
		if child.name == "ClubSelector":
			continue
		var stat = StatDefinitions.get_stat_by_id(child.name)
		if not stat.is_empty():
			var u_str = str(stat.get("units_imperial" if is_imperial else "units_metric", ""))
			if child.has_method("set_units"):
				child.call("set_units", u_str)
