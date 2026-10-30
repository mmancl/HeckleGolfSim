extends SceneTree

var _tested := false

func _initialize() -> void:
	process_frame.connect(_on_frame)

func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()

func _run_tests() -> void:
	print("=== Running Settings Modal & Mobile Safety Tests ===")

	print("\n--- Test 1: DebugLogger.get_all_logs_text ---")
	assert(root.has_node("DebugLogger"), "DebugLogger autoload must exist")
	var dl = root.get_node("DebugLogger")
	dl.log_info("Test log entry for verification.")
	var logs_text = dl.get_all_logs_text()
	assert(not logs_text.is_empty(), "get_all_logs_text() must return log entries")
	print("  PASS: Retrieved %d characters of log text." % logs_text.length())

	print("\n--- Test 2: MainMenu Settings Instantiation ---")
	var menu_scene = load("res://UI/MainMenu/main_menu.tscn")
	assert(menu_scene != null, "main_menu.tscn must load")
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	current_scene = menu

	await process_frame
	await process_frame

	menu._on_settings_pressed()
	await process_frame
	await process_frame

	var settings_inst = menu.get_node_or_null("MainMenuSettings")
	assert(settings_inst != null, "MainMenuSettings must exist as child of MainMenu")
	print("  PASS: MainMenuSettings created without crashing.")

	print("\n--- Test 3: Copy Full Log Button & Actions Row Presence ---")
	var dev_tab = settings_inst.get_node_or_null("MarginContainer/VBoxContainer/TabContainer/DeveloperDebug")
	assert(dev_tab != null, "Developer tab must exist")
	var vbox = dev_tab.find_child("DevDebugVBox", true, false)
	assert(vbox != null, "DevDebugVBox must exist")

	var all_buttons = dev_tab.find_children("", "Button", true, false)
	var copy_full_log_btn: Button = null
	for btn in all_buttons:
		if btn.text == "📋 Copy Full Log":
			copy_full_log_btn = btn
			break

	assert(copy_full_log_btn != null, "Copy Full Log button must exist in Developer Debug tab")
	print("  PASS: Found 'Copy Full Log' button.")

	# Trigger copy action
	copy_full_log_btn.emit_signal("pressed")
	print("  PASS: Copy Full Log pressed without error.")

	print("\n=== ALL SETTINGS MODAL & MOBILE SAFETY TESTS PASSED! ===")
	quit(0)
