extends SceneTree

# Targeted test for Stats Customization Modal layout, responsive sizing, and scroll margin
var _tested := false

func _initialize() -> void:
	print("=== Running Stats Customization Modal Scrollbar & Layout Tests ===")
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	var modal_script = load("res://UI/stats_customization_modal.gd")
	assert(modal_script != null, "stats_customization_modal.gd must load")

	var modal = modal_script.new()
	root.add_child(modal)

	for f in range(3):
		await process_frame

	var modal_panel = modal.find_child("ModalPanel", true, false) as PanelContainer
	assert(modal_panel != null, "ModalPanel must exist")
	assert(modal_panel.custom_minimum_size.x >= 520.0, "Modal min width should be at least 520px")
	assert(modal_panel.custom_minimum_size.y >= 440.0, "Modal min height should be at least 440px")

	var scroll = modal._scroll
	assert(scroll != null, "ScrollContainer must exist in modal")
	var scroll_margin: MarginContainer = null
	for child in scroll.get_children():
		if child is MarginContainer:
			scroll_margin = child
			break
	assert(scroll_margin != null, "ScrollContainer must contain MarginContainer")

	var is_mob: bool = MobilePerformance.is_mobile()
	var expected_margin_right = 68 if is_mob else 32
	var actual_margin_right = scroll_margin.get_theme_constant("margin_right")
	assert(actual_margin_right == expected_margin_right, "MarginContainer right margin must be %d, got %d" % [expected_margin_right, actual_margin_right])

	var v_bar = scroll.get_v_scroll_bar()
	assert(v_bar != null, "ScrollContainer must have a VScrollBar")

	# Check that check buttons are present
	assert(modal._check_button_list.size() > 0, "Check buttons must be populated")
	var first_check = modal._check_button_list[0]
	assert(first_check != null, "First check button must be valid")

	# Verify right margin is greater than scrollbar width to guarantee no overlap
	var v_bar_width = v_bar.custom_minimum_size.x
	assert(actual_margin_right >= v_bar_width, "Scroll content right margin (%d) must be greater than or equal to scrollbar width (%f)" % [actual_margin_right, v_bar_width])

	print("  PASS: Modal responsive sizing verified: %s" % str(modal_panel.custom_minimum_size))
	print("  PASS: Scroll margin padding verified (%d px right margin >= %f px scrollbar width)." % [actual_margin_right, v_bar_width])

	modal.close()
	await process_frame

	print("\n=======================================================")
	print("ALL STATS CUSTOMIZATION MODAL TESTS PASSED! 🎉")
	print("=======================================================\n")
	quit(0)
