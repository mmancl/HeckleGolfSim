class_name BudgetPausedBanner
extends PanelContainer

## Reusable UI banner displayed when the cloud budget circuit-breaker is active.
## Automatically connects to CloudAuth and updates visibility and friendly messaging.

const DEFAULT_BUDGET_MSG := "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."

@export var show_subtitle: bool = true

var _message_label: Label
var _subtitle_label: Label
var _header_label: Label


func _init() -> void:
	custom_minimum_size = Vector2(0, 60)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visible = false

	# Amber/Gold card stylebox
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.12, 0.04, 0.95)
	style.border_color = Color(0.95, 0.72, 0.18, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "BannerVBox"
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_header_label = Label.new()
	_header_label.name = "HeaderLabel"
	_header_label.text = "☁  MONTHLY CLOUD BUDGET NOTICE"
	_header_label.add_theme_color_override("font_color", Color(0.98, 0.80, 0.25, 1.0))
	_header_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_header_label)

	_message_label = Label.new()
	_message_label.name = "MessageLabel"
	_message_label.text = DEFAULT_BUDGET_MSG
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.88, 1.0))
	_message_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_message_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = "Local single-player, local pass-and-play multiplayer, driving range, and local stats continue to work normally."
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_color_override("font_color", Color(0.80, 0.75, 0.65, 0.90))
	_subtitle_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_subtitle_label)


func _ready() -> void:
	var cloud_auth = _get_cloud_auth()
	if cloud_auth != null:
		if not cloud_auth.cloud_service_paused_changed.is_connected(_on_cloud_service_paused_changed):
			cloud_auth.cloud_service_paused_changed.connect(_on_cloud_service_paused_changed)
		update_status(cloud_auth.is_cloud_service_paused(), cloud_auth.get_cloud_pause_message())


func _get_cloud_auth() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("CloudAuth")
	return null


func _on_cloud_service_paused_changed(is_paused: bool, msg: String) -> void:
	update_status(is_paused, msg)


func update_status(is_paused: bool, msg: String = "") -> void:
	visible = is_paused
	if not msg.is_empty() and _message_label != null:
		_message_label.text = msg
	elif _message_label != null:
		var auth = _get_cloud_auth()
		if auth != null and auth.has_method("get_cloud_pause_message"):
			_message_label.text = auth.get_cloud_pause_message()

	if _subtitle_label != null:
		_subtitle_label.visible = show_subtitle


func get_message() -> String:
	return _message_label.text if _message_label != null else ""


func set_message(txt: String) -> void:
	if _message_label != null:
		_message_label.text = txt
