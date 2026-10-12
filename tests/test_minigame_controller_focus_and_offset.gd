extends SceneTree

# Targeted verification for minigame controller focus visibility and ScreenOffset launcher exit

var _tested := false


func _initialize() -> void:
	print("--- Running test_minigame_controller_focus_and_offset.gd ---")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	var test_canvas = CanvasLayer.new()
	root.add_child(test_canvas)

	# ---------------------------------------------------------
	# 1. Verify ScreenOffsetControl minigame launcher and exit
	# ---------------------------------------------------------
	print("\n[1] Testing ScreenOffsetControl minigame launcher...")
	var host = Control.new()
	test_canvas.add_child(host)
	var ctrl_hbox = HBoxContainer.new()
	host.add_child(ctrl_hbox)

	var dummy_style_fn = func(btn: Button, n_col: Color, h_col: Color):
		btn.add_theme_color_override("font_color", Color.WHITE)

	var so_script = load("res://UI/ScreenOffset/screen_offset_control.gd")
	var launcher_btn: Button = so_script.create_minigame_launcher(host, ctrl_hbox, dummy_style_fn)
	assert(launcher_btn != null, "Launcher button must be created")
	assert(ctrl_hbox.get_children().has(launcher_btn), "Launcher button must be in ctrl_hbox")

	var popup_panel = host.get_node_or_null("ScreenOffsetPopupPanel")
	assert(popup_panel != null, "ScreenOffsetPopupPanel must exist in host")
	assert(not popup_panel.visible, "Popup panel must start hidden")

	# Find close button and so_ctrl inside popup
	var close_btn: Button = null
	var so_ctrl: ScreenOffsetControl = null
	for child in popup_panel.find_children("*", "Button", true, false):
		if child.name == "ScreenOffsetCloseButton":
			close_btn = child
	for child in popup_panel.find_children("*", "VBoxContainer", true, false):
		if child is ScreenOffsetControl:
			so_ctrl = child

	assert(close_btn != null, "Header close button 'ScreenOffsetCloseButton' must exist")
	assert(so_ctrl != null, "ScreenOffsetControl must exist inside popup")

	# Verify slider focus style
	var slider: HSlider = so_ctrl._slider
	assert(slider != null, "Slider must exist in ScreenOffsetControl")
	assert(slider.has_theme_stylebox_override("focus"), "Slider must have focus stylebox override")
	var slider_focus_sb = slider.get_theme_stylebox("focus")
	assert(slider_focus_sb is StyleBoxFlat, "Slider focus must be StyleBoxFlat")
	assert(is_equal_approx(slider_focus_sb.border_color.r, 0.35) and is_equal_approx(slider_focus_sb.border_color.g, 0.82), "Slider focus border must be cyan")

	# Test opening popup via launcher button
	launcher_btn.emit_signal("pressed")
	assert(popup_panel.visible, "Popup must be visible after launcher button pressed")
	assert(launcher_btn.text.contains("▲"), "Launcher text should reflect open state")

	# Verify external focus wiring
	var bottom_focusable = so_ctrl.get_bottom_focusable()
	assert(bottom_focusable != null, "get_bottom_focusable must return a control")
	assert(not bottom_focusable.focus_neighbor_bottom.is_empty(), "Bottom focusable must have focus_neighbor_bottom set")
	assert(bottom_focusable.focus_neighbor_bottom == launcher_btn.get_path(), "Bottom focusable must navigate down to launcher button")

	# Test B/Escape cancel event on so_ctrl
	so_ctrl.emit_signal("cancel_pressed")
	assert(not popup_panel.visible, "Cancel signal must close popup panel")
	assert(launcher_btn.text == "↔ Offset", "Launcher text must revert to closed state")

	# Test reopening and closing via Close button
	launcher_btn.emit_signal("pressed")
	assert(popup_panel.visible, "Popup must reopen")
	close_btn.emit_signal("pressed")
	assert(not popup_panel.visible, "Close button must close popup panel")
	print("  PASS: ScreenOffset launcher navigation & exit successfully verified.")

	# ---------------------------------------------------------
	# 2. Verify Button Focus Styles in Minigames
	# ---------------------------------------------------------
	print("\n[2] Testing button focus styles across minigames...")
	var minigame_scripts = [
		"res://Courses/Minigames/Chipping/chipping.gd",
		"res://Courses/Minigames/PuttingPractice/putting_practice.gd",
		"res://Courses/Minigames/ClosestToPin/closest_to_pin.gd",
		"res://Courses/Minigames/LoftControl/loft_control.gd",
		"res://Courses/Minigames/ShapePractice/shape_practice.gd"
	]

	for script_path in minigame_scripts:
		var script = load(script_path)
		assert(script != null, "Script must load: %s" % script_path)
		var instance = Node3D.new()
		instance.set_script(script)

		var test_btn = Button.new()
		instance.call("_apply_btn_style", test_btn, Color(0.1, 0.2, 0.3), Color(0.2, 0.3, 0.4))

		assert(test_btn.has_theme_stylebox_override("focus"), "Button must have focus style override: %s" % script_path)
		var focus_sb = test_btn.get_theme_stylebox("focus")
		var normal_sb = test_btn.get_theme_stylebox("normal")
		assert(focus_sb != normal_sb, "Focus stylebox must NOT equal normal stylebox: %s" % script_path)
		assert(focus_sb is StyleBoxFlat, "Focus stylebox must be StyleBoxFlat: %s" % script_path)
		assert(focus_sb.border_width_left == 3, "Focus border width must be 3: %s" % script_path)
		assert(is_equal_approx(focus_sb.border_color.r, 0.35) and is_equal_approx(focus_sb.border_color.g, 0.82), "Focus border must be cyan: %s" % script_path)

		var test_circ_btn = Button.new()
		instance.call("_apply_circular_button_style", test_circ_btn, Color(0.2, 0.4, 0.6))
		assert(test_circ_btn.has_theme_stylebox_override("focus"), "Circular button must have focus override: %s" % script_path)
		var circ_focus_sb = test_circ_btn.get_theme_stylebox("focus")
		var circ_normal_sb = test_circ_btn.get_theme_stylebox("normal")
		assert(circ_focus_sb != circ_normal_sb, "Circular focus stylebox must NOT equal normal stylebox: %s" % script_path)
		assert(circ_focus_sb.border_width_left == 3, "Circular focus border width must be 3: %s" % script_path)

		if instance.has_method("_apply_matrix_btn_style"):
			var test_mat_btn = Button.new()
			instance.set("panes_broken", [false, false, false, false, false, false, false, false, false])
			instance.set("tic_tac_toe_mode", false)
			instance.call("_apply_matrix_btn_style", test_mat_btn, 0)
			assert(test_mat_btn.has_theme_stylebox_override("focus"), "Matrix button must have focus override: %s" % script_path)
			var mat_focus_sb = test_mat_btn.get_theme_stylebox("focus")
			var mat_normal_sb = test_mat_btn.get_theme_stylebox("normal")
			assert(mat_focus_sb != mat_normal_sb, "Matrix focus stylebox must NOT equal normal stylebox")
			assert(mat_focus_sb.border_width_left == 3, "Matrix focus border width must be 3")
			test_mat_btn.free()

		test_btn.free()
		test_circ_btn.free()
		instance.free()
		print("  PASS: Button focus styling verified for %s" % script_path.get_file())

	print("\nALL CONTROLLER FOCUS & OFFSET EXIT TESTS PASSED SUCCESSFULLY! 🎉")
	quit(0)
