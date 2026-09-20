class_name BatteryWarningModal
extends CanvasLayer

signal confirmed

@onready var modal_panel: PanelContainer = %ModalPanel
@onready var icon_label: Label = %IconLabel
@onready var title_label: Label = %TitleLabel
@onready var message_label: Label = %MessageLabel
@onready var confirm_button: Button = %ConfirmButton

var battery_percentage: int = 25


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	layer = 150
	if modal_panel != null:
		ThemeManager.apply_modal_style(modal_panel, 14)
	_update_ui()
	if confirm_button != null:
		confirm_button.pressed.connect(_on_confirm_pressed)
		confirm_button.grab_focus.call_deferred()


func set_battery_level(level: int) -> void:
	battery_percentage = level
	if is_inside_tree():
		_update_ui()


func _update_ui() -> void:
	if confirm_button == null or title_label == null or message_label == null:
		return

	if battery_percentage <= 10:
		if icon_label != null:
			icon_label.text = "🪫"
		title_label.text = "Critical Battery Warning"
		title_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DANGER)
		message_label.text = "Warning: Launch monitor battery is critically low at %d%% left!\nPlease connect your device to a charger immediately." % battery_percentage
		ThemeManager.apply_danger_button_style(confirm_button, 8)
	else:
		if icon_label != null:
			icon_label.text = "⚠️"
		title_label.text = "Battery Warning"
		title_label.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_WARNING)
		message_label.text = "Warning: Launch monitor battery has %d%% left.\nPlease prepare to recharge your device soon." % battery_percentage
		ThemeManager.apply_primary_button_style(confirm_button, 8)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		_on_confirm_pressed()
		get_viewport().set_input_as_handled()


func _on_confirm_pressed() -> void:
	confirmed.emit()
	queue_free()
