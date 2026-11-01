class_name LinkGuestModal
extends Control

## Compact dialog for sending link requests to a guest player's cloud account,
## with 10-second auto-polling and controller navigation.

const POLL_INTERVAL := 10.0
const MAX_POLL_TICKS := 60 # 10 minutes

signal link_completed(player_name: String, cloud_uid: String)
signal modal_closed()

var player_name: String = ""
var default_email: String = ""
var link_service: LinkService = null

var _poll_ticks: int = 0
var _poll_timer: Timer = null

var panel: PanelContainer = null
var title_label: Label = null
var instructions_label: Label = null
var email_input: LineEdit = null
var status_label: Label = null
var send_btn: Button = null
var check_btn: Button = null
var close_btn: Button = null
var _interactive_controls: Array[Control] = []


func setup(p_player_name: String, p_default_email: String = "", p_link_service: LinkService = null) -> void:
	player_name = p_player_name
	default_email = p_default_email
	if p_link_service != null:
		link_service = p_link_service
	else:
		link_service = LinkService.new()


func _ready() -> void:
	name = "LinkGuestModal"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_STOP

	if link_service == null:
		link_service = LinkService.new()

	_build_ui()

	if has_node("/root/UIFocusGuard"):
		get_node("/root/UIFocusGuard").push_lock(self)

	call_deferred("_setup_controller_focus")


func _build_ui() -> void:
	# Dimmer background
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dimmer.grow_vertical = Control.GROW_DIRECTION_BOTH
	dimmer.color = Color(0.0, 0.0, 0.0, 0.65)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 360)
	ThemeManager.apply_modal_style(panel, 14)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	# Title
	title_label = Label.new()
	title_label.text = "🔗 Link Guest Cloud Account"
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	vbox.add_child(title_label)

	# Subtitle / instructions
	instructions_label = Label.new()
	instructions_label.text = "Link '%s' to a visiting friend's Heckle Golf account.\nThey can tee off immediately — shots recorded today will automatically merge once approved." % player_name
	instructions_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions_label.add_theme_font_size_override("font_size", 14)
	instructions_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	vbox.add_child(instructions_label)

	# Email row
	var email_box := VBoxContainer.new()
	email_box.add_theme_constant_override("separation", 6)
	vbox.add_child(email_box)

	var email_lbl := Label.new()
	email_lbl.text = "Friend's Cloud Account Email:"
	email_lbl.add_theme_font_size_override("font_size", 14)
	email_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	email_box.add_child(email_lbl)

	email_input = LineEdit.new()
	email_input.name = "GuestEmailInput"
	email_input.placeholder_text = "friend@gmail.com"
	email_input.text = default_email
	email_input.custom_minimum_size = Vector2(0, 42)
	email_input.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_input_style(email_input)
	email_input.gui_input.connect(func(ev: InputEvent):
		if has_node("/root/VirtualKeyboardManager"):
			var vkm = get_node("/root/VirtualKeyboardManager")
			if vkm.is_controller_mode_active():
				if (ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_A) or ev.is_action_pressed("ui_accept"):
					vkm.open_for(email_input, true)
	)
	email_input.text_submitted.connect(func(_t): _on_send_pressed())
	email_box.add_child(email_input)

	# Status feedback label
	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	vbox.add_child(status_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Action buttons
	var btn_hbox := HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 12)
	btn_hbox.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_hbox)

	check_btn = Button.new()
	check_btn.name = "CheckStatusNowBtn"
	check_btn.text = "🔍 Check Approval Now"
	check_btn.custom_minimum_size = Vector2(190, 40)
	check_btn.focus_mode = Control.FOCUS_ALL
	check_btn.visible = false
	ThemeManager.apply_primary_button_style(check_btn, 6)
	check_btn.pressed.connect(_check_status_now)
	btn_hbox.add_child(check_btn)

	send_btn = Button.new()
	send_btn.name = "SendRequestBtn"
	send_btn.text = "Send Link Request"
	send_btn.custom_minimum_size = Vector2(160, 40)
	send_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_primary_button_style(send_btn, 6)
	send_btn.pressed.connect(_on_send_pressed)
	btn_hbox.add_child(send_btn)

	close_btn = Button.new()
	close_btn.name = "CloseModalBtn"
	close_btn.text = "Cancel"
	close_btn.custom_minimum_size = Vector2(100, 40)
	close_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_secondary_button_style(close_btn, 6)
	close_btn.pressed.connect(close)
	btn_hbox.add_child(close_btn)

	# Auto-polling timer
	_poll_timer = Timer.new()
	_poll_timer.wait_time = POLL_INTERVAL
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_on_poll_timer_tick)
	add_child(_poll_timer)


func _setup_controller_focus() -> void:
	_interactive_controls.clear()
	if send_btn.is_visible_in_tree() and not send_btn.disabled:
		_interactive_controls = [email_input, send_btn, close_btn]
	elif check_btn.is_visible_in_tree():
		_interactive_controls = [check_btn, close_btn]
	else:
		_interactive_controls = [email_input, close_btn]

	if send_btn.visible:
		email_input.focus_neighbor_bottom = send_btn.get_path()
		send_btn.focus_neighbor_top = email_input.get_path()
		send_btn.focus_neighbor_right = close_btn.get_path()
		close_btn.focus_neighbor_left = send_btn.get_path()
		close_btn.focus_neighbor_top = email_input.get_path()
		email_input.call_deferred("grab_focus")
	else:
		check_btn.focus_neighbor_right = close_btn.get_path()
		close_btn.focus_neighbor_left = check_btn.get_path()
		check_btn.call_deferred("grab_focus")


func _on_send_pressed() -> void:
	var target_email := email_input.text.strip_edges()
	if target_email.is_empty():
		status_label.text = "Please enter your friend's account email."
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		return

	send_btn.disabled = true
	send_btn.text = "Sending..."

	var res: Dictionary = await link_service.send_link_request(player_name, target_email)
	if not res.get("ok", false):
		send_btn.disabled = false
		send_btn.text = "Send Link Request"
		status_label.text = "Error: %s" % res.get("error", "Failed to send request")
		status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		return

	# Transition UI to waiting for approval
	send_btn.visible = false
	check_btn.visible = true
	close_btn.text = "Done"
	email_input.editable = false

	instructions_label.text = "Approval request sent to %s!\nHave them sign in at heckle-golf-sim.web.app on their phone (or in-game under Players → Approvals & Shared Access) to approve once.\n\nThey can start playing immediately — shots hit today will be synced automatically when approved." % target_email
	status_label.text = "Waiting for approval... (auto-checking every 10 seconds)"
	status_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))

	_setup_controller_focus()

	# Start auto-poll timer
	_poll_ticks = 0
	_poll_timer.start()


func _on_poll_timer_tick() -> void:
	_poll_ticks += 1
	if _poll_ticks > MAX_POLL_TICKS:
		_poll_timer.stop()
		status_label.text = "Auto-checking timed out after 10 minutes. Use 'Check Approval Now' at any time."
		return
	_check_status_now()


func _check_status_now() -> void:
	if not check_btn.disabled:
		check_btn.text = "Checking..."
		check_btn.disabled = true

	var outgoing := await link_service.check_outgoing_requests()
	check_btn.text = "🔍 Check Approval Now"
	check_btn.disabled = false

	for doc in outgoing:
		if str(doc.get("local_player_name", "")).to_lower() == player_name.to_lower():
			var status: String = str(doc.get("status", "pending"))
			if status == "approved":
				_poll_timer.stop()
				status_label.text = "✓ Approved! Profile is now linked and syncing."
				status_label.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
				check_btn.visible = false
				link_completed.emit(player_name, str(doc.get("target_uid", "")))
				var t := get_tree().create_timer(1.2)
				t.timeout.connect(close)
				return
			elif status == "denied":
				_poll_timer.stop()
				status_label.text = "Link request was denied by the account owner."
				status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
				return
			elif status == "revoked":
				_poll_timer.stop()
				status_label.text = "Link request was revoked."
				status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
				return

	status_label.text = "Still pending approval... Have friend sign in to approve."
	status_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		if event is InputEventKey and (event.keycode == KEY_BACKSPACE or event.physical_keycode == KEY_BACKSPACE):
			return
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit and focus_owner.text.length() > 0 and event is InputEventKey:
			return
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if _poll_timer != null:
		_poll_timer.stop()
	if has_node("/root/UIFocusGuard"):
		get_node("/root/UIFocusGuard").pop_lock(self)
	modal_closed.emit()
	queue_free()
