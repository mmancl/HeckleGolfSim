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
	label = l
	$VBoxContainer/Label.text = l


func set_data(value: String):
	data = value
	$VBoxContainer/Data.text = value


func set_units(u: String):
	units = u
	$VBoxContainer/Units.text = units
