extends PanelContainer
@export var label: String = "Label"
@export var data: String = "---"
@export var units: String = "units"

const DEFAULT_DATA_FONT_SIZE: int = 22
const DEFAULT_LABEL_FONT_SIZE: int = 14

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	clip_contents = true
	ThemeManager.apply_data_panel_style(self)
	set_label(label)
	set_data(data)
	set_units(units)


func set_label(l: String):
	label = l
	if has_node("VBoxContainer/Label"):
		$VBoxContainer/Label.text = l
		_adjust_label_font_size(l)


func _adjust_label_font_size(val: String) -> void:
	if not has_node("VBoxContainer/Label"):
		return
	var label_lbl: Label = $VBoxContainer/Label
	var target_size: int = DEFAULT_LABEL_FONT_SIZE
	var str_len: int = val.length()

	if str_len >= 16:
		target_size = 10
	elif str_len >= 13:
		target_size = 11
	elif str_len >= 10:
		target_size = 12
	else:
		target_size = DEFAULT_LABEL_FONT_SIZE

	var font = label_lbl.get_theme_font("font")
	if font != null:
		var available_width: float = size.x - 12.0 if size.x > 30.0 else 88.0
		while target_size > 8:
			var text_w: float = font.get_string_size(val, HORIZONTAL_ALIGNMENT_CENTER, -1, target_size).x
			if text_w <= available_width:
				break
			target_size -= 1

	label_lbl.add_theme_font_size_override("font_size", target_size)


func set_data(value: String):
	data = value
	if has_node("VBoxContainer/Data"):
		var data_lbl: Label = $VBoxContainer/Data
		data_lbl.text = value
		_adjust_data_font_size(value)


func _adjust_data_font_size(val: String) -> void:
	if not has_node("VBoxContainer/Data"):
		return
	var data_lbl: Label = $VBoxContainer/Data
	var target_size: int = DEFAULT_DATA_FONT_SIZE
	var str_len: int = val.length()

	if str_len >= 10:
		target_size = 13
	elif str_len >= 8:
		target_size = 16
	elif str_len >= 6:
		target_size = 18
	else:
		target_size = DEFAULT_DATA_FONT_SIZE

	var font = data_lbl.get_theme_font("font")
	if font != null:
		var available_width: float = size.x - 16.0 if size.x > 30.0 else 84.0
		while target_size > 10:
			var text_w: float = font.get_string_size(val, HORIZONTAL_ALIGNMENT_CENTER, -1, target_size).x
			if text_w <= available_width:
				break
			target_size -= 1

	data_lbl.add_theme_font_size_override("font_size", target_size)


func set_units(u: String):
	if units == u and has_node("VBoxContainer/Units") and $VBoxContainer/Units.text == u:
		return
	units = u
	if has_node("VBoxContainer/Units"):
		$VBoxContainer/Units.text = units
