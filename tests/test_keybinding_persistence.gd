extends SceneTree

var _tested := false


func _initialize() -> void:
	print("=== Running Keybinding Persistence Tests ===")
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _tested:
		return
	_tested = true
	_run_tests()


func _run_tests() -> void:
	var km = root.get_node_or_null("KeybindingManager")
	assert(km != null, "KeybindingManager autoload must exist")
	var gs = root.get_node_or_null("GlobalSettings")
	assert(gs != null, "GlobalSettings autoload must exist")

	var orig_mulligan_key = km.get_action_keycode("mulligan")
	var orig_mulligan_joy = km.get_action_joy_button("mulligan")

	print("\n--- Test 1: Rebind action in KeybindingManager and save ---")
	km.rebind_key("mulligan", KEY_K)
	km.rebind_joy_button("mulligan", JOY_BUTTON_X)
	assert(km.get_action_keycode("mulligan") == KEY_K, "Action keycode should be KEY_K")
	assert(km.get_action_joy_button("mulligan") == JOY_BUTTON_X, "Action joy button should be JOY_BUTTON_X")

	var cfg = ConfigFile.new()
	var err = cfg.load("user://global_settings.cfg")
	assert(err == OK, "global_settings.cfg must exist and load successfully")
	assert(cfg.has_section("keybindings"), "cfg must contain keybindings section")
	assert(cfg.has_section("controller_bindings"), "cfg must contain controller_bindings section")
	assert(cfg.get_value("keybindings", "mulligan") == int(KEY_K), "Saved keybinding for mulligan must be KEY_K")
	assert(cfg.get_value("controller_bindings", "mulligan") == int(JOY_BUTTON_X), "Saved controller binding for mulligan must be JOY_BUTTON_X")
	print("  PASS: KeybindingManager correctly saved keybindings to disk.")

	print("\n--- Test 2: GlobalSettings.save_settings() must preserve keybindings ---")
	# Simulate changing a setting or closing the settings modal
	gs.range_settings.ball_reset_timer.set_value(2.0)
	gs.save_settings()

	var cfg_after_gs = ConfigFile.new()
	err = cfg_after_gs.load("user://global_settings.cfg")
	assert(err == OK, "global_settings.cfg must load after GlobalSettings.save_settings()")
	assert(cfg_after_gs.has_section("range_settings"), "cfg must contain range_settings section")
	assert(cfg_after_gs.has_section("keybindings"), "cfg MUST preserve keybindings section after save_settings!")
	assert(cfg_after_gs.has_section("controller_bindings"), "cfg MUST preserve controller_bindings section after save_settings!")
	assert(cfg_after_gs.get_value("keybindings", "mulligan") == int(KEY_K), "Keybinding for mulligan must still be KEY_K after save_settings")
	assert(cfg_after_gs.get_value("controller_bindings", "mulligan") == int(JOY_BUTTON_X), "Controller binding for mulligan must still be JOY_BUTTON_X after save_settings")
	print("  PASS: GlobalSettings.save_settings() preserves keybindings on disk.")

	print("\n--- Test 3: KeybindingManager.load_keybindings() applies to InputMap ---")
	km.load_keybindings()
	assert(km.get_action_keycode("mulligan") == KEY_K, "Reloaded keycode must be KEY_K")
	var found_k_event = false
	for ev in InputMap.action_get_events("mulligan"):
		if ev is InputEventKey and (ev.keycode == KEY_K or ev.physical_keycode == KEY_K):
			found_k_event = true
			break
	assert(found_k_event, "InputMap must contain key event for KEY_K after load_keybindings()")
	print("  PASS: InputMap has updated events after load_keybindings().")

	print("\n--- Test 4: Reset to defaults restore original bindings ---")
	km.rebind_key("mulligan", orig_mulligan_key)
	km.rebind_joy_button("mulligan", orig_mulligan_joy)
	gs.save_settings()
	print("  PASS: Original keybindings restored.")

	print("\n=== ALL KEYBINDING PERSISTENCE TESTS PASSED ===")
	quit(0)
