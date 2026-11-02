extends SceneTree

var _tested := false

func _initialize():
	print("=== Running Player Profile Header and Overview Verification Tests ===")
	process_frame.connect(_on_frame)

func _on_frame():
	if _tested:
		return
	_tested = true

	var players_menu_scene = load("res://UI/PlayersMenu/players_menu.tscn")
	assert(players_menu_scene != null, "players_menu.tscn must load")
	var players_menu = players_menu_scene.instantiate()
	root.add_child(players_menu)
	await process_frame

	# Select or render a player profile
	players_menu._render_player_profile("TestGolfer")
	await process_frame

	var stats_panel = players_menu.stats_panel
	assert(stats_panel != null, "Stats panel must exist")

	var edit_btn = stats_panel.find_child("EditProfileBtn", true, false) as Button
	assert(edit_btn != null, "EditProfileBtn must exist in header")

	# Check header parent
	var header_hbox = edit_btn.get_parent() as HBoxContainer
	assert(header_hbox != null, "Header hbox must exist")

	# Header contains: avatar, info_vbox (with NameRow containing name_lbl and cloud profile controls), and edit_btn
	var info_vbox = header_hbox.get_node_or_null("VBoxContainer")
	if info_vbox == null:
		for c in header_hbox.get_children():
			if c is VBoxContainer:
				info_vbox = c
				break
	assert(info_vbox != null, "Header info vbox must exist")
	var name_lbl = info_vbox.find_child("Label", true, false) as Label
	if name_lbl == null:
		for c in info_vbox.get_children():
			if c is Label:
				name_lbl = c
				break
			elif c is HBoxContainer:
				for sub_c in c.get_children():
					if sub_c is Label:
						name_lbl = sub_c
						break
	assert(name_lbl != null and name_lbl.text == "TestGolfer", "Header must display player name")

	# Check overview tab contains player details
	var tabs = stats_panel.find_child("TabContainer", true, false) as TabContainer
	assert(tabs != null, "TabContainer must exist")
	var overview = tabs.get_child(0) as VBoxContainer
	assert(overview != null, "Overview tab must exist")

	var details_title_found := false
	for child in overview.get_children():
		if child is PanelContainer:
			var title_lbl = child.find_children("*", "Label", true, false)
			for l in title_lbl:
				if l.text == "Player Details":
					details_title_found = true
					break
	assert(details_title_found, "Overview tab must include Player Details section")
	print("  PASS: Profile header is clean and compact; Player Details section properly placed in Overview tab.")

	players_menu.queue_free()
	quit(0)
