extends PanelContainer
@export var label: String = "Label"
@export var data: String = "---"
@export var units: String = "units"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	ThemeManager.apply_data_panel_style(self)
	set_label(label)
	set_data(data)
	set_units(units)


func set_label(l: String):
	if label == l and has_node("VBoxContainer/Label") and $VBoxContainer/Label.text == l:
		return
	label = l
	if has_node("VBoxContainer/Label"):
		$VBoxContainer/Label.text = l


func set_data(value: String):
	if data == value and has_node("VBoxContainer/Data") and $VBoxContainer/Data.text == value:
		return
	data = value
	if has_node("VBoxContainer/Data"):
		$VBoxContainer/Data.text = value


func set_units(u: String):
	if units == u and has_node("VBoxContainer/Units") and $VBoxContainer/Units.text == u:
		return
	units = u
	if has_node("VBoxContainer/Units"):
		$VBoxContainer/Units.text = units
