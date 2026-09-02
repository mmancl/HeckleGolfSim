extends Node

signal scene_changed

var current_scene = null
var _loading_screen: CanvasLayer = null


func _ready() -> void:
	MobilePerformance.apply_global_render_settings(get_tree())


func change_scene(path):
	call_deferred("_deferred_change_scene", path)


func _deferred_change_scene(scene_path) -> void:
	var packed := load(str(scene_path)) as PackedScene
	if packed == null:
		push_error("Could not load scene: %s" % scene_path)
		return

	var next_scene := packed.instantiate()
	if next_scene == null:
		push_error("Could not instantiate scene: %s" % scene_path)
		return

	if current_scene != null:
		get_tree().get_root().remove_child(current_scene)
		current_scene.queue_free()

	current_scene = next_scene
	get_tree().get_root().add_child(current_scene)
	get_tree().current_scene = next_scene
	scene_changed.emit()


func load_course(scene_path: String, config_path: String) -> void:
	_show_loading_screen()
	# Yield 2 frames to ensure the loading screen overlay is drawn and blocks input
	await get_tree().process_frame
	await get_tree().process_frame
	
	change_scene("res://Utils/CourseManager.tscn")
	await scene_changed
	await current_scene.initialize(scene_path, config_path)
	
	# Yield one more frame to ensure the new scene is drawn before hiding the overlay
	await get_tree().process_frame
	_hide_loading_screen()


func close_scene():
	call_deferred("_deferred_close_scene")


func _deferred_close_scene():
	if current_scene != null:
		get_tree().get_root().remove_child(current_scene)
		current_scene.queue_free()
		current_scene = null


func reload_scene():
	if current_scene == null:
		return
	var path: String = str(current_scene.scene_file_path)
	var packed := load(path) as PackedScene
	if packed == null:
		push_error("Could not reload scene: " + path)
		return

	var next_scene := packed.instantiate()
	if next_scene == null:
		push_error("Could not instantiate reloaded scene: " + path)
		return

	get_tree().get_root().remove_child(current_scene)
	current_scene.queue_free()
	current_scene = next_scene
	get_tree().get_root().add_child(current_scene)
	scene_changed.emit()


func _show_loading_screen() -> void:
	if _loading_screen != null:
		return
	
	_loading_screen = CanvasLayer.new()
	_loading_screen.layer = 100
	
	var control = Control.new()
	control.anchors_preset = Control.PRESET_FULL_RECT
	control.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_screen.add_child(control)
	
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.12, 0.16, 0.85) # Sleek premium dark color with transparency
	bg.anchors_preset = Control.PRESET_FULL_RECT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.add_child(bg)
	
	var center = CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	control.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 24)
	center.add_child(vbox)
	
	var spinner_script = load("res://UI/LoadingSpinner.gd")
	if spinner_script != null:
		var spinner = spinner_script.new()
		spinner.custom_minimum_size = Vector2(80, 80)
		spinner.radius = 30.0
		spinner.thickness = 6.0
		spinner.color = Color(0.24, 0.46, 0.72, 1.0)
		spinner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(spinner)
	
	var label = Label.new()
	label.text = "Loading Course..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.9, 0.93, 0.96))
	vbox.add_child(label)
	
	get_tree().get_root().add_child(_loading_screen)


func _hide_loading_screen() -> void:
	if _loading_screen != null:
		_loading_screen.queue_free()
		_loading_screen = null
