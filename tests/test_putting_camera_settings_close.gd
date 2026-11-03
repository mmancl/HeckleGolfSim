extends SceneTree

func _initialize() -> void:
	print("==================================================")
	print("Running Putting Camera Settings Close Tests")
	print("==================================================")

	# --- Test 1: PuttingCameraWidget setup dialog close mechanics ---
	print("\n--- Test 1: PuttingCameraWidget setup dialog close mechanics ---")
	var widget_class = load("res://UI/PuttingCamera/putting_camera_widget.gd")
	assert(widget_class != null, "PuttingCameraWidget class must load")

	var widget = widget_class.new()
	root.add_child(widget)
	widget._ready()

	# 1A. Header close button ("✕")
	widget._open_camera_setup_dialog()
	var dialog = widget._find_active_camera_setup_dialog()
	assert(dialog != null, "CameraSetupDialog must be created and open")

	var header_close = dialog.find_child("HeaderCloseButton", true, false) as Button
	assert(header_close != null, "HeaderCloseButton must exist in CameraSetupDialog")
	assert(header_close.text == "✕", "HeaderCloseButton text must be '✕'")

	header_close.pressed.emit()
	assert(widget._find_active_camera_setup_dialog() == null, "Clicking HeaderCloseButton must close dialog")
	print("PASS: HeaderCloseButton closes CameraSetupDialog in PuttingCameraWidget.")

	# 1B. Closing/minimizing camera closes setup dialog
	widget.set_camera_active(true)
	widget._open_camera_setup_dialog()
	assert(widget._find_active_camera_setup_dialog() != null, "Dialog should be open")
	widget.minimize()
	assert(widget._find_active_camera_setup_dialog() == null, "Minimizing putting camera must close setup dialog")
	print("PASS: Minimizing putting camera closes setup dialog.")

	widget.restore()
	widget._open_camera_setup_dialog()
	assert(widget._find_active_camera_setup_dialog() != null, "Dialog should be open")
	widget.set_camera_active(false)
	assert(widget._find_active_camera_setup_dialog() == null, "Disabling putting camera must close setup dialog")
	print("PASS: Disabling putting camera closes setup dialog.")

	# 1C. ESC key / ui_cancel closes setup dialog
	widget.set_camera_active(true)
	widget._open_camera_setup_dialog()
	assert(widget._find_active_camera_setup_dialog() != null, "Dialog should be open")
	var esc_ev = InputEventKey.new()
	esc_ev.pressed = true
	esc_ev.keycode = KEY_ESCAPE
	widget._unhandled_input(esc_ev)
	assert(widget._find_active_camera_setup_dialog() == null, "Pressing ESC must close setup dialog")
	print("PASS: Pressing ESC closes setup dialog in PuttingCameraWidget.")

	widget._close_camera_setup_dialog()
	widget.queue_free()

	# --- Test 2: RangeUI setup dialog close mechanics ---
	print("\n--- Test 2: RangeUI setup dialog close mechanics ---")
	var range_ui_scene = load("res://UI/range_ui.tscn")
	assert(range_ui_scene != null, "range_ui.tscn must load")
	var range_ui = range_ui_scene.instantiate()
	root.add_child(range_ui)

	# 2A. Header close button in RangeUI setup dialog
	range_ui.open_camera_setup(true)
	var r_dialog = range_ui._get_active_camera_setup_dialog()
	assert(r_dialog != null, "CameraSetupDialog must be created and open in RangeUI")

	var r_header_close = r_dialog.find_child("HeaderCloseButton", true, false) as Button
	assert(r_header_close != null, "HeaderCloseButton must exist in RangeUI CameraSetupDialog")
	assert(r_header_close.text == "✕", "HeaderCloseButton text must be '✕'")

	r_header_close.pressed.emit()
	assert(range_ui._get_active_camera_setup_dialog() == null, "Clicking HeaderCloseButton must close dialog in RangeUI")
	print("PASS: HeaderCloseButton closes CameraSetupDialog in RangeUI.")

	# 2B. Minimizing putting camera in RangeUI closes setup dialog
	range_ui.set_putting_camera_visible(true)
	range_ui.open_camera_setup(true)
	assert(range_ui._get_active_camera_setup_dialog() != null, "Dialog should be open")
	range_ui.minimize_putting_camera()
	assert(range_ui._get_active_camera_setup_dialog() == null, "minimize_putting_camera must close setup dialog")
	print("PASS: minimize_putting_camera closes setup dialog in RangeUI.")

	# 2C. Closing putting camera in RangeUI closes setup dialog
	range_ui.restore_putting_camera()
	range_ui.open_camera_setup(true)
	assert(range_ui._get_active_camera_setup_dialog() != null, "Dialog should be open")
	range_ui.set_putting_camera_visible(false)
	assert(range_ui._get_active_camera_setup_dialog() == null, "set_putting_camera_visible(false) must close setup dialog")
	print("PASS: set_putting_camera_visible(false) closes setup dialog in RangeUI.")

	# 2D. ESC key closes setup dialog in RangeUI
	range_ui.set_putting_camera_visible(true)
	range_ui.open_camera_setup(true)
	assert(range_ui._get_active_camera_setup_dialog() != null, "Dialog should be open")
	range_ui._unhandled_input(esc_ev)
	assert(range_ui._get_active_camera_setup_dialog() == null, "Pressing ESC must close setup dialog in RangeUI")
	print("PASS: Pressing ESC closes setup dialog in RangeUI.")

	range_ui._close_camera_setup_dialog()
	range_ui.queue_free()

	print("\n==================================================")
	print("ALL PUTTING CAMERA SETTINGS CLOSE TESTS PASSED! 🎉")
	print("==================================================")
	quit(0)
