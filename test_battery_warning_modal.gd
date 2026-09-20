extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Launch Monitor Battery Warning Modal Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	var lm = root.get_node_or_null("LaunchMonitorManager")
	assert(lm != null, "LaunchMonitorManager autoload must exist in scene tree")

	lm.reset_battery_warning_session()

	# Test 1: Invalid battery levels and safe levels (> 25%)
	print("\n--- Test 1: Invalid & Safe Battery Levels ---")
	lm.trigger_test_battery_warning(-1)
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "No modal should be shown for -1 battery")

	lm.trigger_test_battery_warning(85)
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "No modal should be shown for 85% battery")
	print("  PASS: No modal triggered for safe or invalid battery levels.")

	# Test 2: Reaching 25% triggers warning modal
	print("\n--- Test 2: Battery Reaches 25% ---")
	lm.trigger_test_battery_warning(25)
	await process_frame
	await process_frame

	var modal_25 = root.get_node_or_null("BatteryWarningModal")
	assert(modal_25 != null, "Modal should be instantiated when battery reaches 25%")
	var title_25: Label = modal_25.get_node_or_null("%TitleLabel")
	var msg_25: Label = modal_25.get_node_or_null("%MessageLabel")
	var btn_25: Button = modal_25.get_node_or_null("%ConfirmButton")

	assert(title_25 != null, "Modal must have TitleLabel")
	assert(msg_25 != null, "Modal must have MessageLabel")
	assert(btn_25 != null, "Modal must have ConfirmButton")
	assert(msg_25.text.contains("25%"), "Message should mention 25% battery left")
	print("  PASS: 25% battery warning modal shown with correct title, message, and confirm button.")

	# Test 3: Confirm button closes and frees modal
	print("\n--- Test 3: Confirming and Closing Modal ---")
	var state := {"confirmed": false}
	modal_25.confirmed.connect(func(): state["confirmed"] = true)
	btn_25.pressed.emit()
	await process_frame
	await process_frame

	assert(state["confirmed"], "Clicking ConfirmButton must emit confirmed signal")
	assert(root.get_node_or_null("BatteryWarningModal") == null, "Modal must be freed after confirmation")
	print("  PASS: Confirming dismissed and closed the modal cleanly.")

	# Test 4: 25% modal does NOT repeat during same session
	print("\n--- Test 4: Max Once Per Session for 25% Warning ---")
	lm.trigger_test_battery_warning(24)
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "25% modal should NOT show again in same session")

	lm.trigger_test_battery_warning(20)
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "20% level should NOT show duplicate 25% modal")
	print("  PASS: 25% modal did not repeat.")

	# Test 5: Dropping to 10% triggers critical warning modal
	print("\n--- Test 5: Battery Reaches 10% ---")
	lm.trigger_test_battery_warning(10)
	await process_frame
	await process_frame

	var modal_10 = root.get_node_or_null("BatteryWarningModal")
	assert(modal_10 != null, "Modal should be instantiated when battery reaches 10%")
	var title_10: Label = modal_10.get_node_or_null("%TitleLabel")
	var msg_10: Label = modal_10.get_node_or_null("%MessageLabel")
	var btn_10: Button = modal_10.get_node_or_null("%ConfirmButton")

	assert(title_10 != null and title_10.text.contains("Critical"), "10% modal title must indicate critical battery")
	assert(msg_10 != null and msg_10.text.contains("10%"), "Message should mention 10% battery left")
	assert(btn_10 != null, "Modal must have ConfirmButton")
	print("  PASS: 10% critical battery warning modal shown properly.")

	# Test 6: Confirming 10% modal
	print("\n--- Test 6: Confirming 10% Modal ---")
	btn_10.emit_signal("pressed")
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "10% modal must be freed after confirmation")
	print("  PASS: 10% modal closed after confirmation.")

	# Test 7: 10% modal does NOT repeat during same session
	print("\n--- Test 7: Max Once Per Session for 10% Warning ---")
	lm.trigger_test_battery_warning(8)
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "10% modal should NOT show again in same session")

	lm.trigger_test_battery_warning(5)
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "5% level should NOT show duplicate modal")
	print("  PASS: 10% modal did not repeat.")

	# Test 8: Starting directly at 10% suppresses later 25%
	print("\n--- Test 8: Direct Critical Start Suppresses 25% ---")
	lm.reset_battery_warning_session()
	lm.trigger_test_battery_warning(9)
	await process_frame
	await process_frame

	var direct_crit = root.get_node_or_null("BatteryWarningModal")
	assert(direct_crit != null, "Critical modal should appear for 9% battery")
	direct_crit.get_node_or_null("%ConfirmButton").emit_signal("pressed")
	await process_frame
	await process_frame

	# Now simulate fluctuation to 22%: should NOT trigger 25% warning
	lm.trigger_test_battery_warning(22)
	await process_frame
	await process_frame
	assert(root.get_node_or_null("BatteryWarningModal") == null, "Fluctuation to 22% after critical start must not show 25% modal")
	print("  PASS: Direct critical start properly suppressed subsequent 25% popup.")

	print("\n=== ALL BATTERY WARNING MODAL TESTS PASSED SUCCESSFULLY! ===")
	quit(0)
