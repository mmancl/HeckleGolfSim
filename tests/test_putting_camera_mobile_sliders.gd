extends SceneTree

func _initialize() -> void:
	print("==================================================")
	print("Running Putting Camera & Mobile Sliders Tests")
	print("==================================================")

	# --- Test 1: ThemeManager Slider Styling & Grabber Icons ---
	print("\n--- Test 1: ThemeManager Slider Styling & Grabber Icons ---")
	var tm = load("res://UI/theme/theme_manager.gd")
	if tm == null:
		push_error("Failed to load ThemeManager")
		quit(1)
		return
	
	var grab_mob = tm.get_slider_grabber_icon("normal", true)
	var grab_desk = tm.get_slider_grabber_icon("normal", false)
	assert(grab_mob != null, "Mobile grabber icon must not be null")
	assert(grab_desk != null, "Desktop grabber icon must not be null")
	assert(grab_mob.get_size() == Vector2(36, 36), "Mobile grabber icon must be 36x36, got %s" % str(grab_mob.get_size()))
	assert(grab_desk.get_size() == Vector2(28, 28), "Desktop grabber icon must be 28x28, got %s" % str(grab_desk.get_size()))
	print("PASS: Grabber textures generated with touch-friendly dimensions (36x36 mobile, 28x28 desktop).")

	var test_slider = HSlider.new()
	tm.apply_slider_style(test_slider)
	assert(test_slider.has_theme_icon_override("grabber"), "Slider must have grabber override")
	assert(test_slider.has_theme_icon_override("grabber_highlight"), "Slider must have grabber_highlight override")
	assert(test_slider.has_theme_stylebox_override("slider"), "Slider must have track stylebox override")
	assert(test_slider.has_theme_stylebox_override("grabber_area"), "Slider must have grabber_area stylebox override")
	assert(test_slider.custom_minimum_size.y >= 36, "Slider min height must be >= 36, got %f" % test_slider.custom_minimum_size.y)
	print("PASS: ThemeManager.apply_slider_style correctly equips sliders with modern theme items and touch dimensions.")

	# --- Test 2: TouchScrollHelper Slider Passthrough ---
	print("\n--- Test 2: TouchScrollHelper Slider Passthrough ---")
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 400)
	scroll.size = Vector2(400, 400)
	var helper = TouchScrollHelper.attach_to(scroll)
	root.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	scroll.add_child(vbox)
	var child_slider = HSlider.new()
	child_slider.custom_minimum_size = Vector2(300, 48)
	child_slider.size = Vector2(300, 48)
	vbox.add_child(child_slider)
	
	var pos_on_slider = child_slider.global_position + Vector2(20, 20)
	assert(TouchScrollHelper._is_pos_on_slider(scroll, pos_on_slider), "Helper must detect touch on child slider")
	assert(not helper._is_pos_inside_container(pos_on_slider), "Helper must not intercept touches on slider")
	print("PASS: TouchScrollHelper allows sliders to handle touch input natively without scroll conflicts.")
	scroll.queue_free()

	# --- Test 3: PuttingCameraWidget UI & Track Line Slider ---
	print("\n--- Test 3: Putting Camera Track Line Slider ---")
	var widget_class = load("res://UI/PuttingCamera/putting_camera_widget.gd")
	assert(widget_class != null, "PuttingCameraWidget class must load")
	
	var widget = widget_class.new()
	root.add_child(widget)
	widget._ready()
	
	var align_slider: HSlider = widget.find_child("TrackLineSlider", true, false) as HSlider
	assert(align_slider != null, "TrackLineSlider must exist in PuttingCameraWidget")
	assert(align_slider.custom_minimum_size.y >= 36, "TrackLineSlider min height must be >= 36, got %f" % align_slider.custom_minimum_size.y)
	assert(align_slider.has_theme_icon_override("grabber"), "TrackLineSlider must have custom touch grabber icon")
	print("PASS: Track Line slider is sized appropriately with touch grabber icon (min height: %.0f)." % align_slider.custom_minimum_size.y)

	# --- Test 4: Putting Camera Setup Dialog Sliders ---
	print("\n--- Test 4: Putting Camera Setup Dialog Sliders ---")
	widget._open_camera_setup_dialog()
	
	var setup_dialog = root.find_child("CameraSetupDialog", true, false)
	assert(setup_dialog != null, "CameraSetupDialog must be created and open in root")
	
	var found_sliders: Array[HSlider] = []
	for child in setup_dialog.find_children("*", "HSlider", true, false):
		if child is HSlider:
			found_sliders.append(child as HSlider)
			
	print("Found %d sliders in setup dialog." % found_sliders.size())
	assert(found_sliders.size() >= 3, "Setup dialog must contain at least 3 sliders (tolerance, min speed, max speed)")
	
	for s in found_sliders:
		assert(s.custom_minimum_size.y >= 36, "Setup dialog slider height must be >= 36, got %f" % s.custom_minimum_size.y)
		assert(s.has_theme_icon_override("grabber"), "Setup dialog slider must have touch grabber icon applied")
		# Test adjusting slider
		var old_val = s.value
		s.value = clamp(s.value + s.step, s.min_value, s.max_value)
		assert(s.value != old_val or s.value == s.max_value, "Slider value should update smoothly")
	print("PASS: All putting camera settings sliders are properly styled with mobile-friendly heights and grabbers.")

	# --- Test 5: Putting Camera Setup Dialog Scrollbar Clearance ---
	print("\n--- Test 5: Putting Camera Setup Dialog Scrollbar Clearance ---")
	var scroll_node: ScrollContainer = null
	for c in setup_dialog.find_children("*", "ScrollContainer", true, false):
		if c is ScrollContainer:
			scroll_node = c as ScrollContainer
			break
	assert(scroll_node != null, "Setup dialog must contain a ScrollContainer")
	print("Found ScrollContainer: ", scroll_node.name)
	for c in scroll_node.get_children():
		print("  child: ", c.name, " class: ", c.get_class())
	
	var scroll_margin: MarginContainer = null
	for c in scroll_node.get_children():
		if c is MarginContainer:
			scroll_margin = c as MarginContainer
			break
	assert(scroll_margin != null, "ScrollContainer must contain a MarginContainer to prevent scrollbar overlap")
	var right_margin: int = scroll_margin.get_theme_constant("margin_right")
	assert(right_margin >= 32, "MarginContainer right margin must be >= 32 to clear scrollbar, got %d" % right_margin)
	print("PASS: ScrollContainer contains MarginContainer with %dpx right margin, ensuring vertical scrollbar does not cover controls." % right_margin)

	# Cleanup dialog and widget
	setup_dialog.queue_free()
	widget.queue_free()

	print("\n==================================================")
	print("ALL PUTTING CAMERA MOBILE SLIDER TESTS PASSED!")
	print("==================================================")
	quit(0)
