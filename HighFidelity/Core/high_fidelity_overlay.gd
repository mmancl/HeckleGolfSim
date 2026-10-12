extends CanvasLayer
class_name HighFidelityOverlay

## HighFidelityOverlay
## Diagnostic and telemetry HUD for High graphics mode.
## Displays FPS, frame time, draw calls, and VRAM. Toggle with F3.

var _panel: PanelContainer = null
var _fps_label: Label = null
var _draw_label: Label = null
var _vram_label: Label = null
var _timer: float = 0.0

func _init() -> void:
	layer = 120
	visible = false # Hidden by default, toggled with F3

func _ready() -> void:
	_create_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			visible = not visible

func _process(delta: float) -> void:
	if not visible:
		return
	
	_timer += delta
	if _timer >= 0.25: # Update 4 times per second
		_timer = 0.0
		_update_telemetry()

func _create_ui() -> void:
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_panel.position = Vector2(-280, 16)
	_panel.custom_minimum_size = Vector2(264, 110)
	
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.12, 0.85)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.24, 0.55, 0.82, 0.7)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12.0
	sb.content_margin_top = 10.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	var header = Label.new()
	header.text = "HIGH FIDELITY (Forward+)"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.4, 0.85, 0.95))
	vbox.add_child(header)

	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 12)
	_fps_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9))
	vbox.add_child(_fps_label)

	_draw_label = Label.new()
	_draw_label.add_theme_font_size_override("font_size", 12)
	_draw_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9))
	vbox.add_child(_draw_label)

	_vram_label = Label.new()
	_vram_label.add_theme_font_size_override("font_size", 12)
	_vram_label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9))
	vbox.add_child(_vram_label)

	_update_telemetry()


func _update_telemetry() -> void:
	var fps = Engine.get_frames_per_second()
	var frame_ms = (1.0 / maxf(float(fps), 1.0)) * 1000.0
	var draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var vram_bytes = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var vram_mb = vram_bytes / (1024.0 * 1024.0)

	if _fps_label != null:
		_fps_label.text = "FPS: %d  (%.1f ms)" % [fps, frame_ms]
	if _draw_label != null:
		_draw_label.text = "Draw Calls: %d" % [int(draws)]
	if _vram_label != null:
		_vram_label.text = "VRAM: %.1f MB" % [vram_mb]
