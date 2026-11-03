extends Control

## Online Multiplayer Menu (res://UI/OnlineMultiplayer/multiplayer_menu.gd)
## Hosts, joins by 6-char code, browses public lobbies, verifies course fingerprint,
## downloads missing courses, and coordinates lobby readiness.
## See docs/multiplayer/07_ONLINE_LOBBY_HOST_JOIN.md.

const CourseFingerprintScript = preload("res://Utils/Cloud/course_fingerprint.gd")
const BudgetPausedBannerScript = preload("res://UI/Account/budget_paused_banner.gd")

@onready var back_button: Button = %BackButton
@onready var user_status_label: Label = %UserStatusLabel
@onready var account_button: Button = %AccountButton
@onready var budget_banner: PanelContainer = %BudgetBanner
@onready var tab_bar: HBoxContainer = %TabBar
@onready var tab_host_button: Button = %TabHostButton
@onready var tab_join_code_button: Button = %TabJoinCodeButton
@onready var tab_browser_button: Button = %TabBrowserButton

@onready var host_view: VBoxContainer = %HostView
@onready var course_dropdown: OptionButton = %CourseDropdown
@onready var length_option: OptionButton = %LengthOption
@onready var mode_option: OptionButton = %ModeOption
@onready var turn_order_option: OptionButton = %TurnOrderOption
@onready var wind_option: OptionButton = %WindOption
@onready var green_speed_option: OptionButton = %GreenSpeedOption
@onready var visibility_option: OptionButton = %VisibilityOption
@onready var host_golfer_dropdown: OptionButton = %HostGolferDropdown
@onready var host_golfer_tee: OptionButton = %HostGolferTee
@onready var host_create_button: Button = %HostCreateButton
@onready var host_status_label: Label = %HostStatusLabel

@onready var join_code_view: VBoxContainer = %JoinCodeView
@onready var join_code_input: LineEdit = %JoinCodeInput
@onready var paste_code_button: Button = %PasteCodeButton
@onready var join_golfer_dropdown: OptionButton = %JoinGolferDropdown
@onready var join_golfer_tee: OptionButton = %JoinGolferTee
@onready var join_code_submit_button: Button = %JoinCodeSubmitButton
@onready var join_status_label: Label = %JoinStatusLabel

@onready var browser_view: VBoxContainer = %BrowserView
@onready var refresh_browser_button: Button = %RefreshBrowserButton
@onready var browser_scroll: ScrollContainer = %BrowserScroll
@onready var browser_list: VBoxContainer = %BrowserList
@onready var no_lobbies_label: Label = %NoLobbiesLabel

@onready var lobby_room_view: VBoxContainer = %LobbyRoomView
@onready var room_code_label: Label = %RoomCodeLabel
@onready var copy_code_button: Button = %CopyCodeButton
@onready var room_details_label: Label = %RoomDetailsLabel
@onready var course_install_banner: PanelContainer = %CourseInstallBanner
@onready var course_install_label: Label = %CourseInstallLabel
@onready var download_course_button: Button = %DownloadCourseButton
@onready var golfers_container: VBoxContainer = %GolfersContainer
@onready var leave_lobby_button: Button = %LeaveLobbyButton
@onready var ready_toggle_button: Button = %ReadyToggleButton
@onready var start_match_button: Button = %StartMatchButton
@onready var confirm_leave_dialog: ConfirmationDialog = %ConfirmLeaveDialog

var _active_tab: String = "host" # "host" | "join_code" | "browser" | "room"
var _available_courses: Array[Dictionary] = []
var _registered_players: Array[Dictionary] = []
var _missing_course_info: Dictionary = {}
var _is_downloading_course: bool = false
var _pending_spectate_match_id: String = ""
var _session_cache: Node = null


func _get_session() -> Node:
	if _session_cache != null and is_instance_valid(_session_cache):
		return _session_cache
	if has_node("/root/OnlineSession"):
		_session_cache = get_node("/root/OnlineSession")
		return _session_cache
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null and loop.root.has_node("OnlineSession"):
		_session_cache = loop.root.get_node("OnlineSession")
		return _session_cache
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Hook up button signals
	back_button.pressed.connect(_on_back_pressed)
	account_button.pressed.connect(_on_account_pressed)
	tab_host_button.pressed.connect(func(): _switch_tab("host"))
	tab_join_code_button.pressed.connect(func(): _switch_tab("join_code"))
	tab_browser_button.pressed.connect(func(): _switch_tab("browser"))
	host_create_button.pressed.connect(_on_host_create_pressed)
	paste_code_button.pressed.connect(_on_paste_code_pressed)
	join_code_submit_button.pressed.connect(_on_join_code_submit_pressed)
	refresh_browser_button.pressed.connect(_on_refresh_browser_pressed)
	copy_code_button.pressed.connect(_on_copy_code_pressed)
	download_course_button.pressed.connect(_on_download_course_pressed)
	ready_toggle_button.pressed.connect(_on_ready_toggle_pressed)
	start_match_button.pressed.connect(_on_start_match_pressed)
	leave_lobby_button.pressed.connect(_on_leave_lobby_pressed)
	confirm_leave_dialog.confirmed.connect(_confirm_leave_lobby)

	join_code_input.text_changed.connect(func(t: String):
		join_code_input.text = t.to_upper().strip_edges()
	)

	# Connect OnlineSession signals
	var sess := _get_session()
	if sess != null:
		sess.lobby_updated.connect(_on_lobby_updated)
		sess.public_lobbies_loaded.connect(_on_public_lobbies_loaded)
		sess.lobby_error.connect(_on_lobby_error)
		sess.course_install_required.connect(_on_course_install_required)
		sess.match_started.connect(_on_match_started)
		sess.lobby_closed.connect(_on_lobby_closed)

	# Connect CloudAuth
	if has_node("/root/CloudAuth"):
		var ca = get_node("/root/CloudAuth")
		if ca.has_signal("cloud_service_paused_changed"):
			ca.cloud_service_paused_changed.connect(_on_cloud_service_paused_changed)
		if ca.has_signal("auth_state_changed"):
			ca.auth_state_changed.connect(_on_cloud_auth_state_changed)

	_apply_styles()
	_populate_dropdowns()
	_update_user_status()
	_check_budget_pause()

	TouchScrollHelper.attach_to(browser_scroll)

	_switch_tab("host")
	_update_controller_focus_navigation()
	tab_host_button.call_deferred("grab_focus")


func _apply_styles() -> void:
	ThemeManager.apply_nav_button_style(back_button, 6)
	ThemeManager.apply_nav_button_style(account_button, 6)
	ThemeManager.apply_primary_button_style(host_create_button, 8)
	ThemeManager.apply_primary_button_style(join_code_submit_button, 8)
	ThemeManager.apply_primary_button_style(start_match_button, 8)
	ThemeManager.apply_nav_button_style(paste_code_button, 6)
	ThemeManager.apply_nav_button_style(refresh_browser_button, 6)
	ThemeManager.apply_nav_button_style(copy_code_button, 6)
	ThemeManager.apply_secondary_button_style(ready_toggle_button, 8)
	ThemeManager.apply_danger_button_style(leave_lobby_button, 8)
	ThemeManager.apply_primary_button_style(download_course_button, 6)

	ThemeManager.apply_input_style(join_code_input)

	for opt in [
		course_dropdown,
		length_option,
		mode_option,
		turn_order_option,
		wind_option,
		green_speed_option,
		visibility_option,
		host_golfer_dropdown,
		host_golfer_tee,
		join_golfer_dropdown,
		join_golfer_tee
	]:
		if opt != null:
			ThemeManager.apply_option_button_style(opt)


func _get_user_account_display_name(ca: Object) -> String:
	if ca == null:
		return ""
	var dname: String = str(ca.get_display_name()).strip_edges()
	if not dname.is_empty():
		return dname
	var email: String = str(ca.get_email()).strip_edges()
	if not email.is_empty():
		return email.split("@")[0]
	var uid: String = str(ca.get_uid()).strip_edges()
	if not uid.is_empty():
		return uid.substr(0, 8)
	return ""


func _update_user_status() -> void:
	if has_node("/root/CloudAuth"):
		var ca = get_node("/root/CloudAuth")
		if ca.is_signed_in():
			var name_str := _get_user_account_display_name(ca)
			if name_str.is_empty():
				name_str = "Golfer"
			user_status_label.text = "Account: %s" % name_str
		elif ca.is_authenticated_any():
			var name_str := _get_user_account_display_name(ca)
			if name_str.is_empty():
				user_status_label.text = "Account: Anonymous"
			else:
				user_status_label.text = "Account: Anonymous (%s)" % name_str
		else:
			user_status_label.text = "Account: Not signed in"


func _on_cloud_auth_state_changed(_is_signed_in: bool, _user: Dictionary) -> void:
	_update_user_status()


func _on_account_pressed() -> void:
	if find_child("AccountModal", true, false) != null:
		return
	var modal_scene = load("res://UI/Account/account_modal.tscn")
	if modal_scene == null:
		return
	var modal = modal_scene.instantiate()
	modal.name = "AccountModal"
	if modal.has_signal("closed"):
		modal.closed.connect(func():
			_update_user_status()
			if account_button != null and is_instance_valid(account_button):
				account_button.call_deferred("grab_focus")
		)
	add_child(modal)


func _check_budget_pause() -> void:
	var paused := false
	if has_node("/root/CloudAuth"):
		paused = get_node("/root/CloudAuth").is_cloud_service_paused()

	host_create_button.disabled = paused
	join_code_submit_button.disabled = paused
	refresh_browser_button.disabled = paused


func _on_cloud_service_paused_changed(is_paused: bool, _message: String) -> void:
	_check_budget_pause()
	var sess := _get_session()
	if is_paused and sess != null and sess.is_online_match:
		_show_status("Multiplayer service has been paused.", true)


# ── TAB & VIEW MANAGEMENT ───────────────────────────────────────────────

func _switch_tab(tab_name: String) -> void:
	_active_tab = tab_name

	# Clear status text whenever changing tabs to avoid error bleed across views
	if host_status_label != null:
		host_status_label.text = ""
	if join_status_label != null:
		join_status_label.text = ""

	tab_host_button.disabled = (tab_name == "host")
	tab_join_code_button.disabled = (tab_name == "join_code")
	tab_browser_button.disabled = (tab_name == "browser")

	host_view.visible = (tab_name == "host")
	join_code_view.visible = (tab_name == "join_code")
	browser_view.visible = (tab_name == "browser")
	lobby_room_view.visible = (tab_name == "room")
	tab_bar.visible = (tab_name != "room")

	if tab_name == "browser":
		_on_refresh_browser_pressed()

	_update_controller_focus_navigation()


func _populate_dropdowns() -> void:
	# Course lengths
	length_option.clear()
	for l in ["Full 18", "Front 9", "Back 9"]:
		length_option.add_item(l)

	# Allowed online game modes (H17: Hide Scramble and 2v2 Scramble)
	mode_option.clear()
	for m in ["Standard", "Skins", "Closest to Pin"]:
		mode_option.add_item(m)

	# Turn order
	turn_order_option.clear()
	for o in ["Stay Up", "Classic", "Full Hole"]:
		turn_order_option.add_item(o)

	# Wind options
	wind_option.clear()
	for w in ["Calm / Off", "Light (3-7 mph)", "Moderate (8-14 mph)", "Breezy (15-20 mph)", "Windy (20+ mph)"]:
		wind_option.add_item(w)
	wind_option.select(1)

	# Green speeds
	green_speed_option.clear()
	for s in ["Slow", "Normal", "Fast", "Tour"]:
		green_speed_option.add_item(s)
	green_speed_option.select(1)

	# Visibility
	visibility_option.clear()
	visibility_option.add_item("Public")
	visibility_option.add_item("Private")

	# Tees
	for tee_opt in [host_golfer_tee, join_golfer_tee]:
		tee_opt.clear()
		for t in ["Black", "Blue", "White", "Red", "Gold"]:
			tee_opt.add_item(t)
		tee_opt.select(1) # Blue

	# Players
	_populate_players()

	# Courses
	_populate_courses()


func _populate_players() -> void:
	host_golfer_dropdown.clear()
	join_golfer_dropdown.clear()

	_registered_players.clear()
	var mp_mgr = get_node_or_null("/root/MultiplayerManager")
	if mp_mgr != null and mp_mgr.has_method("get_registered_players"):
		for p_entry in mp_mgr.get_registered_players():
			if p_entry is Dictionary:
				_registered_players.append(p_entry)

	if _registered_players.is_empty():
		_registered_players.append({
			"name": "Player 1",
			"preferred_tee": "Blue",
			"avatar": "",
			"handedness": 0,
			"ball_graphic": "single_line"
		})

	for p in _registered_players:
		var p_name: String = p.get("name", "Player")
		host_golfer_dropdown.add_item(p_name)
		join_golfer_dropdown.add_item(p_name)

	host_golfer_dropdown.select(0)
	join_golfer_dropdown.select(0)


func _populate_courses() -> void:
	course_dropdown.clear()
	_available_courses.clear()

	var search_dirs := [
		"user://courses",
		"res://Courses/UserCourses",
		"res://Courses/Cached"
	]

	for base_dir in search_dirs:
		if not DirAccess.dir_exists_absolute(base_dir):
			continue
		var subdirs := DirAccess.get_directories_at(base_dir)
		for s in subdirs:
			if s.begins_with("."):
				continue
			var cfg_path: String = base_dir.path_join(str(s)).path_join("course.json")
			if not FileAccess.file_exists(cfg_path):
				continue
			var inspected := CourseFingerprintScript.inspect_course_config(cfg_path)
			if inspected.get("ok", false):
				_available_courses.append(inspected)

	for i in range(_available_courses.size()):
		var c = _available_courses[i]
		var title: String = c.get("title", "Unknown")
		var is_custom: bool = c.get("is_custom", false)
		if is_custom:
			title += " (Custom - Local Only)"
		course_dropdown.add_item(title, i)
		if is_custom:
			course_dropdown.set_item_disabled(i, true)
			course_dropdown.set_item_tooltip(i, "Custom local courses cannot be hosted online yet because remote players cannot download them from the course catalog.")


# ── HOST FLOW ────────────────────────────────────────────────────────────

func _on_host_create_pressed() -> void:
	if _available_courses.is_empty():
		_show_status("No valid courses installed.", true)
		return

	var sel_course_idx := course_dropdown.get_selected_id()
	if sel_course_idx < 0 or sel_course_idx >= _available_courses.size():
		_show_status("Please select a course to host.", true)
		return

	var course_data = _available_courses[sel_course_idx]
	if course_data.get("is_custom", false):
		_show_status("Custom courses cannot be hosted online.", true)
		return

	var settings := {
		"course_length": length_option.get_item_text(length_option.selected),
		"game_mode": mode_option.get_item_text(mode_option.selected),
		"turn_order_mode": turn_order_option.get_item_text(turn_order_option.selected),
		"green_speed": green_speed_option.get_item_text(green_speed_option.selected),
		"pin_seed": randi()
	}

	# Wind mapping
	var wind_idx := wind_option.selected
	var wind_speed := 0.0
	match wind_idx:
		1: wind_speed = 5.0
		2: wind_speed = 10.0
		3: wind_speed = 17.0
		4: wind_speed = 24.0
	settings["wind_speed_mph"] = wind_speed
	settings["wind_dir_rad"] = randf() * TAU

	var visibility := "public" if visibility_option.selected == 0 else "private"

	var local_golfers: Array[Dictionary] = [_get_selected_golfer(host_golfer_dropdown, host_golfer_tee)]

	host_create_button.disabled = true
	_show_status("Creating lobby...", false)

	var sess := _get_session()
	if sess == null:
		_show_status("Online session not initialized.", true)
		host_create_button.disabled = false
		return

	var res = await sess.create_lobby(
		course_data.get("config_path", ""),
		settings,
		visibility,
		local_golfers
	)

	host_create_button.disabled = false
	if res.get("ok", false):
		_switch_tab("room")
		_on_lobby_updated(sess.match_meta, sess.match_devices, sess.match_golfers)
	else:
		_show_status(res.get("error", "Failed to create lobby"), true)


func _get_selected_golfer(dropdown: OptionButton, tee_opt: OptionButton) -> Dictionary:
	var sel_idx := dropdown.selected
	var base_profile: Dictionary = _registered_players[sel_idx] if sel_idx < _registered_players.size() else {}
	var golfer := base_profile.duplicate()
	golfer["name"] = dropdown.get_item_text(sel_idx)
	golfer["tee"] = tee_opt.get_item_text(tee_opt.selected)
	return golfer


# ── JOIN BY CODE FLOW ────────────────────────────────────────────────────

func _on_paste_code_pressed() -> void:
	var clip := DisplayServer.clipboard_get().strip_edges().to_upper()
	if not clip.is_empty():
		join_code_input.text = clip.substr(0, 6)


func _on_join_code_submit_pressed() -> void:
	var code := join_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		_show_status("Please enter a valid 6-character code.", true)
		return

	var local_golfers: Array[Dictionary] = [_get_selected_golfer(join_golfer_dropdown, join_golfer_tee)]

	join_code_submit_button.disabled = true
	_show_status("Joining match...", false)

	var sess := _get_session()
	if sess == null:
		_show_status("Online session not initialized.", true)
		join_code_submit_button.disabled = false
		return

	var res = await sess.join_by_code(code, local_golfers)
	join_code_submit_button.disabled = false

	if res.get("ok", false):
		_switch_tab("room")
		_on_lobby_updated(sess.match_meta, sess.match_devices, sess.match_golfers)
	else:
		_show_status(res.get("error", "Failed to join lobby."), true)


# ── PUBLIC BROWSER FLOW ──────────────────────────────────────────────────

func _on_refresh_browser_pressed() -> void:
	refresh_browser_button.disabled = true
	_clear_browser_list()
	no_lobbies_label.visible = true
	no_lobbies_label.text = "Fetching public matches..."

	var sess := _get_session()
	if sess != null:
		await sess.fetch_public_lobbies()
	refresh_browser_button.disabled = false


func _on_public_lobbies_loaded(lobbies: Array[Dictionary]) -> void:
	_clear_browser_list()
	if lobbies.is_empty():
		no_lobbies_label.visible = true
		no_lobbies_label.text = "No active public lobbies found. Host a match to invite other players!"
	else:
		no_lobbies_label.visible = false
		for lobby_item in lobbies:
			_add_browser_lobby_row(lobby_item)

	_update_controller_focus_navigation()


func _clear_browser_list() -> void:
	for c in browser_list.get_children():
		if c != no_lobbies_label:
			c.queue_free()


func _add_browser_lobby_row(lobby_data: Dictionary) -> void:
	var card := PanelContainer.new()
	ThemeManager.apply_card_panel_style(card, false, 8, 12, 10, 12, 10)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	card.add_child(hbox)

	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var status: String = str(lobby_data.get("status", "lobby"))
	var is_in_progress: bool = (status == "in_progress" or status == "active")
	var status_tag: String = "[In Progress]" if is_in_progress else "[In Lobby]"

	var title_lbl := Label.new()
	title_lbl.text = "%s — %s (%s) %s" % [
		lobby_data.get("course_title", "Unknown Course"),
		lobby_data.get("course_length", "Full 18"),
		lobby_data.get("game_mode", "Standard"),
		status_tag
	]
	title_lbl.add_theme_font_size_override("font_size", 15)
	info_vbox.add_child(title_lbl)

	var host_lbl := Label.new()
	var player_cnt: int = int(lobby_data.get("player_count", 1))
	var max_p: int = int(lobby_data.get("max_players", 4))
	host_lbl.text = "Host: %s | Players: %d/%d" % [
		lobby_data.get("host_name", "Host"),
		player_cnt,
		max_p
	]
	host_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
	host_lbl.add_theme_font_size_override("font_size", 13)
	info_vbox.add_child(host_lbl)

	var match_id: String = str(lobby_data.get("match_id", ""))

	if is_in_progress:
		var spectate_btn := Button.new()
		spectate_btn.name = "SpectateBtn"
		spectate_btn.text = "Spectate"
		spectate_btn.custom_minimum_size = Vector2(110, 38)
		ThemeManager.apply_primary_button_style(spectate_btn, 6)
		spectate_btn.pressed.connect(func(): _on_spectate_browser_match(match_id, lobby_data))
		hbox.add_child(spectate_btn)
	else:
		if player_cnt < max_p:
			var join_btn := Button.new()
			join_btn.name = "JoinBtn"
			join_btn.text = "Join"
			join_btn.custom_minimum_size = Vector2(90, 38)
			ThemeManager.apply_primary_button_style(join_btn, 6)
			join_btn.pressed.connect(func(): _on_join_browser_lobby(match_id))
			hbox.add_child(join_btn)

		var spectate_btn := Button.new()
		spectate_btn.name = "SpectateBtn"
		spectate_btn.text = "Spectate"
		spectate_btn.custom_minimum_size = Vector2(90, 38)
		ThemeManager.apply_secondary_button_style(spectate_btn, 6)
		spectate_btn.pressed.connect(func(): _on_spectate_browser_match(match_id, lobby_data))
		hbox.add_child(spectate_btn)

	browser_list.add_child(card)


func _on_join_browser_lobby(match_id: String) -> void:
	var local_golfers: Array[Dictionary] = [_get_selected_golfer(host_golfer_dropdown, host_golfer_tee)]
	_show_status("Joining public match...", false)

	var sess := _get_session()
	if sess == null:
		return

	var res = await sess.join_by_match_id(match_id, local_golfers)
	if res.get("ok", false):
		_switch_tab("room")
		_on_lobby_updated(sess.match_meta, sess.match_devices, sess.match_golfers)
	else:
		_show_status(res.get("error", "Failed to join match."), true)


func _on_spectate_browser_match(match_id: String, _lobby_data: Dictionary = {}) -> void:
	_show_status("Connecting to spectate match...", false)
	var sess := _get_session()
	if sess == null:
		return

	var res = await sess.spectate_match(match_id)
	if res.get("ok", false):
		_show_status("Spectating match!", false)
	elif res.get("need_course", false):
		_pending_spectate_match_id = match_id
		_show_status("Course download required to spectate.", false)
	else:
		_show_status(res.get("error", "Failed to spectate match."), true)


# ── LOBBY ROOM VIEW ──────────────────────────────────────────────────────

func _on_lobby_updated(meta: Dictionary, devices: Dictionary, golfers: Dictionary) -> void:
	if _active_tab != "room":
		_switch_tab("room")

	var sess := _get_session()
	var cur_code: String = sess.current_join_code if sess != null else ""
	room_code_label.text = cur_code if not cur_code.is_empty() else "—"

	var course: Dictionary = meta.get("course", {})
	var settings: Dictionary = meta.get("settings", {})
	room_details_label.text = "%s | %s | %s" % [
		course.get("title", "Course"),
		settings.get("course_length", "Full 18"),
		settings.get("game_mode", "Standard")
	]

	# Update Start Match button state
	var my_uid: String = sess._get_my_uid() if sess != null else ""
	var is_host: bool = sess.is_host if sess != null else false
	start_match_button.visible = is_host

	var all_ready := true
	for dev_id in devices.keys():
		var dev = devices[dev_id]
		if not bool(dev.get("course_ready", false)) or not bool(dev.get("ready", false)):
			all_ready = false
			break

	start_match_button.disabled = (golfers.size() < 2 or not all_ready)

	# Update Ready button text
	var my_dev = devices.get(my_uid, {})
	var is_my_device_ready: bool = bool(my_dev.get("ready", false))
	ready_toggle_button.text = "I'm Not Ready" if is_my_device_ready else "Ready Up!"

	# Populate golfers
	_render_room_golfers(golfers, devices)
	_update_controller_focus_navigation()


func _render_room_golfers(golfers: Dictionary, devices: Dictionary) -> void:
	for c in golfers_container.get_children():
		c.queue_free()

	var sorted_slots: Array = golfers.keys()
	sorted_slots.sort_custom(func(a, b):
		return int(golfers[a].get("order", 0)) < int(golfers[b].get("order", 0))
	)

	var sess := _get_session()
	var my_uid: String = sess._get_my_uid() if sess != null else ""
	var is_host: bool = sess.is_host if sess != null else false

	for slot_id in sorted_slots:
		var g = golfers[slot_id]
		var card := PanelContainer.new()
		ThemeManager.apply_card_panel_style(card, false, 8, 12, 8, 12, 8)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 16)
		card.add_child(hbox)

		var name_lbl := Label.new()
		name_lbl.text = "%s. %s (%s Tee)" % [
			str(int(g.get("order", 0)) + 1),
			g.get("name", "Player"),
			g.get("tee", "Blue")
		]
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_lbl)

		var owner_uid: String = g.get("owner_uid", "")
		var dev = devices.get(owner_uid, {})
		var dev_ready: bool = bool(dev.get("ready", false))
		var dev_course_ready: bool = bool(dev.get("course_ready", false))

		var status_lbl := Label.new()
		if not dev_course_ready:
			status_lbl.text = "Missing Course"
			status_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_DANGER)
		elif dev_ready:
			status_lbl.text = "Ready"
			status_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_SUCCESS)
		else:
			status_lbl.text = "Not Ready"
			status_lbl.add_theme_color_override("font_color", ThemeManager.COLOR_TEXT_MUTED)
		hbox.add_child(status_lbl)

		# Host kick button for remote devices
		if is_host and owner_uid != my_uid:
			var kick_btn := Button.new()
			kick_btn.text = "Kick"
			ThemeManager.apply_danger_button_style(kick_btn, 4)
			kick_btn.pressed.connect(func():
				if sess != null:
					sess.kick_device(owner_uid)
			)
			hbox.add_child(kick_btn)

		golfers_container.add_child(card)


func _on_course_install_required(course_info: Dictionary, _reason: String) -> void:
	_missing_course_info = course_info
	course_install_banner.visible = true
	var title: String = course_info.get("title", "Course")
	course_install_label.text = "Course Required: '%s' is not installed or has a different version." % title


func _on_download_course_pressed() -> void:
	if _is_downloading_course:
		return

	_is_downloading_course = true
	download_course_button.disabled = true
	course_install_label.text = "Downloading & Generating 3D Course Geometry..."

	var lat: float = float(_missing_course_info.get("lat", 0.0))
	var lon: float = float(_missing_course_info.get("lon", 0.0))
	var title: String = _missing_course_info.get("title", "")
	var is_cached: bool = bool(_missing_course_info.get("is_cached", false))
	var location: String = _missing_course_info.get("location", "")

	var loader_script = load("res://Courses/OsmMapLoader.cs")
	if loader_script != null:
		var loader = loader_script.new()
		add_child(loader)
		if loader.has_method("DownloadAndGenerateCourse"):
			loader.call("DownloadAndGenerateCourse", lat, lon, title, is_cached, location)
			var success = await loader.CourseGenerated
			loader.queue_free()

			if success:
				var found = CourseFingerprintScript.find_installed_course(_missing_course_info.get("key", ""), lat, lon, title)
				if not found.is_empty():
					var sess := _get_session()
					if sess != null:
						sess.set_local_course_ready(true, found.get("scene_path", ""), found.get("config_path", ""))
					course_install_banner.visible = false
					_show_status("Course installed and ready!", false)
					if not _pending_spectate_match_id.is_empty():
						var target_spec_id := _pending_spectate_match_id
						_pending_spectate_match_id = ""
						_on_spectate_browser_match(target_spec_id)
				else:
					course_install_label.text = "Installed course could not be verified."
			else:
				course_install_label.text = "Course download failed. Please retry."
	else:
		course_install_label.text = "OsmMapLoader script not found."

	_is_downloading_course = false
	download_course_button.disabled = false


func _on_ready_toggle_pressed() -> void:
	var sess := _get_session()
	if sess != null:
		sess.set_local_device_ready(!sess.is_local_device_ready)


func _on_start_match_pressed() -> void:
	start_match_button.disabled = true
	var sess := _get_session()
	if sess == null:
		return
	var res = await sess.start_online_match()
	if not res.get("ok", false):
		start_match_button.disabled = false
		_show_status(res.get("error", "Failed to start match."), true)


func _on_copy_code_pressed() -> void:
	var sess := _get_session()
	var code: String = sess.current_join_code if sess != null else ""
	if not code.is_empty():
		DisplayServer.clipboard_set(code)
		copy_code_button.text = "Copied!"
		get_tree().create_timer(1.5).timeout.connect(func():
			if is_instance_valid(copy_code_button):
				copy_code_button.text = "Copy Code"
		)


func _on_leave_lobby_pressed() -> void:
	var sess := _get_session()
	if sess != null and sess.is_host and sess.match_meta.get("status", "") == "lobby":
		confirm_leave_dialog.popup_centered()
	else:
		_confirm_leave_lobby()


func _confirm_leave_lobby() -> void:
	var sess := _get_session()
	if sess != null:
		sess.leave_lobby()
	course_install_banner.visible = false
	_switch_tab("host")


func _on_lobby_closed(reason: String) -> void:
	course_install_banner.visible = false
	if _active_tab == "room":
		_switch_tab("host")
		_show_status("Lobby closed: %s" % reason, false)


func _on_match_started(match_id: String, _meta: Dictionary, _golfers: Array[Dictionary]) -> void:
	print("[OnlineMultiplayerMenu] Online match %s started! Transitioning to runtime..." % match_id)
	# Package 09 (OnlineMatchController) configures MultiplayerManager and loads course


func _on_lobby_error(code: String, message: String) -> void:
	_show_status("[%s] %s" % [code, message], true)


func _show_status(msg: String, is_error: bool) -> void:
	var color := ThemeManager.COLOR_TEXT_DANGER if is_error else ThemeManager.COLOR_TEXT_SUCCESS
	if _active_tab == "host":
		if host_status_label != null:
			host_status_label.text = msg
			host_status_label.add_theme_color_override("font_color", color)
	elif _active_tab == "join_code":
		if join_status_label != null:
			join_status_label.text = msg
			join_status_label.add_theme_color_override("font_color", color)
	elif _active_tab == "browser":
		if no_lobbies_label != null and is_error:
			no_lobbies_label.visible = true
			no_lobbies_label.text = msg
	else:
		# Fallback for other tabs / room view
		if host_status_label != null:
			host_status_label.text = msg
			host_status_label.add_theme_color_override("font_color", color)


func _on_back_pressed() -> void:
	var sess := _get_session()
	if sess != null and sess.is_online_match:
		_on_leave_lobby_pressed()
	else:
		var sm = get_node_or_null("/root/SceneManager")
		if sm != null and sm.has_method("load_main_menu"):
			sm.load_main_menu()
		else:
			get_tree().change_scene_to_file("res://UI/MainMenu/main_menu.tscn")


# ── CONTROLLER FOCUS & KEYBOARD INTERCEPTION ────────────────────────────

func _input(event: InputEvent) -> void:
	# If controller Joypad A pressed on join code input, trigger VirtualKeyboardManager
	if join_code_input.has_focus() and (event is InputEventJoypadButton) and event.pressed and event.button_index == JOY_BUTTON_A:
		if has_node("/root/VirtualKeyboardManager"):
			get_node("/root/VirtualKeyboardManager").open_for(join_code_input, true)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _active_tab == "room":
			_on_leave_lobby_pressed()
		else:
			_on_back_pressed()
		get_viewport().set_input_as_handled()


func _update_controller_focus_navigation() -> void:
	# Set up focus neighbors depending on the current active tab
	back_button.focus_neighbor_right = tab_host_button.get_path()

	tab_host_button.focus_neighbor_left = back_button.get_path()
	tab_host_button.focus_neighbor_right = tab_join_code_button.get_path()
	tab_join_code_button.focus_neighbor_left = tab_host_button.get_path()
	tab_join_code_button.focus_neighbor_right = tab_browser_button.get_path()
	tab_browser_button.focus_neighbor_left = tab_join_code_button.get_path()
	tab_browser_button.focus_neighbor_right = account_button.get_path()
	account_button.focus_neighbor_left = tab_browser_button.get_path()

	if _active_tab == "host":
		tab_host_button.focus_neighbor_bottom = course_dropdown.get_path()
		course_dropdown.focus_neighbor_top = tab_host_button.get_path()
		course_dropdown.focus_neighbor_bottom = length_option.get_path()
		length_option.focus_neighbor_top = course_dropdown.get_path()
		length_option.focus_neighbor_bottom = mode_option.get_path()
		mode_option.focus_neighbor_top = length_option.get_path()
		mode_option.focus_neighbor_bottom = turn_order_option.get_path()
		turn_order_option.focus_neighbor_top = mode_option.get_path()
		turn_order_option.focus_neighbor_bottom = wind_option.get_path()
		wind_option.focus_neighbor_top = turn_order_option.get_path()
		wind_option.focus_neighbor_bottom = green_speed_option.get_path()
		green_speed_option.focus_neighbor_top = wind_option.get_path()
		green_speed_option.focus_neighbor_bottom = visibility_option.get_path()
		visibility_option.focus_neighbor_top = green_speed_option.get_path()
		visibility_option.focus_neighbor_bottom = host_golfer_dropdown.get_path()
		host_golfer_dropdown.focus_neighbor_top = visibility_option.get_path()
		host_golfer_dropdown.focus_neighbor_right = host_golfer_tee.get_path()
		host_golfer_tee.focus_neighbor_left = host_golfer_dropdown.get_path()
		host_golfer_dropdown.focus_neighbor_bottom = host_create_button.get_path()
		host_golfer_tee.focus_neighbor_bottom = host_create_button.get_path()
		host_create_button.focus_neighbor_top = host_golfer_dropdown.get_path()

	elif _active_tab == "join_code":
		tab_join_code_button.focus_neighbor_bottom = join_code_input.get_path()
		join_code_input.focus_neighbor_top = tab_join_code_button.get_path()
		join_code_input.focus_neighbor_right = paste_code_button.get_path()
		paste_code_button.focus_neighbor_left = join_code_input.get_path()
		join_code_input.focus_neighbor_bottom = join_golfer_dropdown.get_path()
		paste_code_button.focus_neighbor_bottom = join_golfer_dropdown.get_path()
		join_golfer_dropdown.focus_neighbor_top = join_code_input.get_path()
		join_golfer_dropdown.focus_neighbor_right = join_golfer_tee.get_path()
		join_golfer_tee.focus_neighbor_left = join_golfer_dropdown.get_path()
		join_golfer_dropdown.focus_neighbor_bottom = join_code_submit_button.get_path()
		join_golfer_tee.focus_neighbor_bottom = join_code_submit_button.get_path()
		join_code_submit_button.focus_neighbor_top = join_golfer_dropdown.get_path()

	elif _active_tab == "browser":
		tab_browser_button.focus_neighbor_bottom = refresh_browser_button.get_path()
		refresh_browser_button.focus_neighbor_top = tab_browser_button.get_path()
		var first_btn: Button = null
		for card in browser_list.get_children():
			if card is PanelContainer:
				for c in card.find_children("*", "Button", true, false):
					if c is Button and c.is_visible_in_tree():
						first_btn = c
						break
				if first_btn != null:
					break
		if first_btn != null:
			refresh_browser_button.focus_neighbor_bottom = first_btn.get_path()
			first_btn.focus_neighbor_top = refresh_browser_button.get_path()

	elif _active_tab == "room":
		copy_code_button.focus_neighbor_top = back_button.get_path()
		copy_code_button.focus_neighbor_bottom = ready_toggle_button.get_path()
		if course_install_banner.visible:
			copy_code_button.focus_neighbor_bottom = download_course_button.get_path()
			download_course_button.focus_neighbor_top = copy_code_button.get_path()
			download_course_button.focus_neighbor_bottom = ready_toggle_button.get_path()
		leave_lobby_button.focus_neighbor_right = ready_toggle_button.get_path()
		ready_toggle_button.focus_neighbor_left = leave_lobby_button.get_path()
		ready_toggle_button.focus_neighbor_right = start_match_button.get_path()
		start_match_button.focus_neighbor_left = ready_toggle_button.get_path()
