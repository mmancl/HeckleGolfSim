class_name ApprovalsModal
extends Control

## Modal dialog for primary users to manage incoming link requests from host simulators
## and view or revoke active delegates who can sync their stats.

signal modal_closed()

var link_service: LinkService = null
var auth_node: Node = null

var panel: PanelContainer = null
var verification_banner: PanelContainer = null
var verify_status_label: Label = null
var send_verify_btn: Button = null
var refresh_verify_btn: Button = null
var scroll_container: ScrollContainer = null
var pending_vbox: VBoxContainer = null
var delegates_vbox: VBoxContainer = null
var close_btn: Button = null
var _row_action_buttons: Array[Control] = []


func setup(p_link_service: LinkService = null, p_auth_node: Node = null) -> void:
	if p_link_service != null:
		link_service = p_link_service
	else:
		link_service = LinkService.new()
	auth_node = p_auth_node


func _ready() -> void:
	name = "ApprovalsModal"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	z_index = 60
	mouse_filter = Control.MOUSE_FILTER_STOP

	if link_service == null:
		link_service = LinkService.new()
	if auth_node == null:
		auth_node = get_node_or_null("/root/CloudAuth")

	_build_ui()

	if has_node("/root/UIFocusGuard"):
		get_node("/root/UIFocusGuard").push_lock(self)

	_refresh_all()


func _build_ui() -> void:
	# Dimmer background
	var dimmer := ColorRect.new()
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dimmer.grow_vertical = Control.GROW_DIRECTION_BOTH
	dimmer.color = Color(0.0, 0.0, 0.0, 0.7)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 520)
	ThemeManager.apply_modal_style(panel, 14)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	margin.add_child(main_vbox)

	# Header row
	var header_hbox := HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	var title := Label.new()
	title.text = "🔑 Approvals & Shared Access"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	header_hbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Manage simulator PCs and friends who have permission to sync your stats and club averages."
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(subtitle)

	# Verification banner (shown if email is unverified)
	verification_banner = PanelContainer.new()
	verification_banner.name = "VerificationBanner"
	var v_style := StyleBoxFlat.new()
	v_style.bg_color = Color(0.35, 0.22, 0.05, 0.9)
	v_style.border_color = Color(0.95, 0.75, 0.2, 1.0)
	v_style.set_border_width_all(1)
	v_style.set_corner_radius_all(6)
	v_style.content_margin_left = 14
	v_style.content_margin_right = 14
	v_style.content_margin_top = 10
	v_style.content_margin_bottom = 10
	verification_banner.add_theme_stylebox_override("panel", v_style)
	main_vbox.add_child(verification_banner)

	var banner_vbox := VBoxContainer.new()
	banner_vbox.add_theme_constant_override("separation", 8)
	verification_banner.add_child(banner_vbox)

	var warn_lbl := Label.new()
	warn_lbl.text = "⚠️ Email Verification Required: To protect your account from spoofing, please verify your email before approving access requests."
	warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warn_lbl.add_theme_font_size_override("font_size", 13)
	warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	banner_vbox.add_child(warn_lbl)

	verify_status_label = Label.new()
	verify_status_label.text = ""
	verify_status_label.add_theme_font_size_override("font_size", 12)
	verify_status_label.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
	banner_vbox.add_child(verify_status_label)

	var v_btns := HBoxContainer.new()
	v_btns.add_theme_constant_override("separation", 10)
	banner_vbox.add_child(v_btns)

	send_verify_btn = Button.new()
	send_verify_btn.name = "SendVerificationBtn"
	send_verify_btn.text = "Send Verification Email"
	send_verify_btn.custom_minimum_size = Vector2(190, 36)
	send_verify_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_primary_button_style(send_verify_btn, 4)
	send_verify_btn.pressed.connect(_on_send_verification_pressed)
	v_btns.add_child(send_verify_btn)

	refresh_verify_btn = Button.new()
	refresh_verify_btn.name = "RefreshVerificationBtn"
	refresh_verify_btn.text = "I've Verified — Refresh"
	refresh_verify_btn.custom_minimum_size = Vector2(180, 36)
	refresh_verify_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_secondary_button_style(refresh_verify_btn, 4)
	refresh_verify_btn.pressed.connect(_on_refresh_verification_pressed)
	v_btns.add_child(refresh_verify_btn)

	# ScrollContainer for lists
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ApprovalsScrollContainer"
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.follow_focus = true
	main_vbox.add_child(scroll_container)

	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 18)
	scroll_container.add_child(scroll_vbox)

	# Section 1: Pending Requests
	var pending_header := Label.new()
	pending_header.text = "PENDING REQUESTS TO ACCESS YOUR STATS"
	pending_header.add_theme_font_size_override("font_size", 14)
	pending_header.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	scroll_vbox.add_child(pending_header)

	pending_vbox = VBoxContainer.new()
	pending_vbox.name = "PendingRequestsVBox"
	pending_vbox.add_theme_constant_override("separation", 8)
	scroll_vbox.add_child(pending_vbox)

	# Divider
	var div := ColorRect.new()
	div.custom_minimum_size = Vector2(0, 1)
	div.color = Color(0.3, 0.4, 0.5, 0.4)
	scroll_vbox.add_child(div)

	# Section 2: Active Delegates
	var delegates_header := Label.new()
	delegates_header.text = "FRIENDS & SIMULATORS APPROVED TO SYNC YOUR STATS"
	delegates_header.add_theme_font_size_override("font_size", 14)
	delegates_header.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	scroll_vbox.add_child(delegates_header)

	delegates_vbox = VBoxContainer.new()
	delegates_vbox.name = "ActiveDelegatesVBox"
	delegates_vbox.add_theme_constant_override("separation", 8)
	scroll_vbox.add_child(delegates_vbox)

	# Bottom Close button
	var bottom_hbox := HBoxContainer.new()
	bottom_hbox.alignment = BoxContainer.ALIGNMENT_END
	main_vbox.add_child(bottom_hbox)

	close_btn = Button.new()
	close_btn.name = "CloseApprovalsModalBtn"
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(110, 40)
	close_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_secondary_button_style(close_btn, 6)
	close_btn.pressed.connect(close)
	bottom_hbox.add_child(close_btn)


func _refresh_all() -> void:
	var auth := auth_node if auth_node != null else get_node_or_null("/root/CloudAuth")
	var is_verified: bool = (auth != null and auth.has_method("is_email_verified") and auth.is_email_verified())
	verification_banner.visible = not is_verified

	# Clear previous rows
	for child in pending_vbox.get_children():
		child.queue_free()
	for child in delegates_vbox.get_children():
		child.queue_free()

	_row_action_buttons.clear()

	# Fetch pending requests
	var requests: Array[Dictionary] = await link_service.fetch_incoming_link_requests()
	var pending_count := 0
	for req in requests:
		if str(req.get("status", "pending")) == "pending":
			pending_count += 1
			_create_pending_request_row(req, is_verified)

	if pending_count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "No pending access requests."
		empty_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		pending_vbox.add_child(empty_lbl)

	# Fetch active delegates
	var delegates: Array[Dictionary] = await link_service.fetch_active_delegates()
	if delegates.is_empty():
		var empty_del_lbl := Label.new()
		empty_del_lbl.text = "No friends currently approved to sync your stats."
		empty_del_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		empty_del_lbl.add_theme_font_size_override("font_size", 13)
		delegates_vbox.add_child(empty_del_lbl)
	else:
		for del in delegates:
			_create_delegate_row(del)

	call_deferred("_setup_controller_focus")


func _create_pending_request_row(req: Dictionary, is_verified: bool) -> void:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.22, 0.8)
	style.border_color = Color(0.25, 0.35, 0.5, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var name_lbl := Label.new()
	var req_name := str(req.get("requester_name", "Host"))
	var req_email := str(req.get("requester_email", ""))
	name_lbl.text = "%s (%s)" % [req_name, req_email] if not req_email.is_empty() else req_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(name_lbl)

	var approve_btn := Button.new()
	approve_btn.name = "ApproveBtn"
	approve_btn.text = "✓ Approve"
	approve_btn.custom_minimum_size = Vector2(100, 34)
	approve_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_primary_button_style(approve_btn, 4)
	if not is_verified:
		approve_btn.disabled = true
		approve_btn.tooltip_text = "Verify email above to approve access"
	approve_btn.pressed.connect(func():
		approve_btn.disabled = true
		approve_btn.text = "Approving..."
		await link_service.approve_link_request(req)
		_refresh_all()
	)
	hbox.add_child(approve_btn)

	var deny_btn := Button.new()
	deny_btn.name = "DenyBtn"
	deny_btn.text = "✕ Deny"
	deny_btn.custom_minimum_size = Vector2(80, 34)
	deny_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_secondary_button_style(deny_btn, 4)
	deny_btn.pressed.connect(func():
		deny_btn.disabled = true
		await link_service.deny_link_request(req)
		_refresh_all()
	)
	hbox.add_child(deny_btn)

	pending_vbox.add_child(row)
	_row_action_buttons.append(approve_btn)
	_row_action_buttons.append(deny_btn)


func _create_delegate_row(del: Dictionary) -> void:
	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.16, 0.22, 0.8)
	style.border_color = Color(0.25, 0.35, 0.5, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	row.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var name_lbl := Label.new()
	var del_name := str(del.get("delegate_name", ""))
	var del_email := str(del.get("delegate_email", ""))
	var del_uid := str(del.get("delegate_uid", ""))
	if not del_name.is_empty():
		name_lbl.text = "%s (%s)" % [del_name, del_email] if not del_email.is_empty() else del_name
	elif not del_email.is_empty():
		name_lbl.text = del_email
	else:
		name_lbl.text = "Simulator (UID: %s)" % del_uid.substr(0, 8)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(name_lbl)

	var revoke_btn := Button.new()
	revoke_btn.name = "RevokeBtn"
	revoke_btn.text = "Revoke Access"
	revoke_btn.custom_minimum_size = Vector2(130, 34)
	revoke_btn.focus_mode = Control.FOCUS_ALL
	ThemeManager.apply_secondary_button_style(revoke_btn, 4)
	revoke_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	revoke_btn.pressed.connect(func():
		revoke_btn.disabled = true
		revoke_btn.text = "Revoking..."
		await link_service.revoke_delegate(del_uid, str(del.get("request_id", "")))
		_refresh_all()
	)
	hbox.add_child(revoke_btn)

	delegates_vbox.add_child(row)
	_row_action_buttons.append(revoke_btn)


func _setup_controller_focus() -> void:
	var interactive_rows: Array[Control] = []
	if verification_banner.is_visible_in_tree() and send_verify_btn.is_visible_in_tree():
		send_verify_btn.focus_neighbor_right = refresh_verify_btn.get_path()
		refresh_verify_btn.focus_neighbor_left = send_verify_btn.get_path()
		interactive_rows.append(send_verify_btn)

	# Collect all visible, enabled buttons in rows
	var current_row_buttons: Array[Button] = []
	for btn in _row_action_buttons:
		if is_instance_valid(btn) and btn.is_visible_in_tree():
			current_row_buttons.append(btn)

	# Wire horizontal focus pairs (Approve <-> Deny)
	var i := 0
	while i < current_row_buttons.size():
		var b1 = current_row_buttons[i]
		if i + 1 < current_row_buttons.size() and current_row_buttons[i+1].name == "DenyBtn":
			var b2 = current_row_buttons[i+1]
			b1.focus_neighbor_right = b2.get_path()
			b2.focus_neighbor_left = b1.get_path()
			interactive_rows.append(b1)
			i += 2
		else:
			interactive_rows.append(b1)
			i += 1

	interactive_rows.append(close_btn)

	# Wire vertical chains
	for idx in range(interactive_rows.size() - 1):
		var upper: Control = interactive_rows[idx]
		var lower: Control = interactive_rows[idx + 1]
		upper.focus_neighbor_bottom = lower.get_path()
		lower.focus_neighbor_top = upper.get_path()

	# Grab initial focus on first button
	if not interactive_rows.is_empty():
		var first_btn = interactive_rows[0]
		if first_btn is Button and first_btn.disabled and interactive_rows.size() > 1:
			first_btn = interactive_rows[1]
		first_btn.call_deferred("grab_focus")


func _on_send_verification_pressed() -> void:
	var auth := auth_node if auth_node != null else get_node_or_null("/root/CloudAuth")
	if auth != null and auth.has_method("send_email_verification"):
		send_verify_btn.disabled = true
		send_verify_btn.text = "Sending..."
		var res: Dictionary = await auth.send_email_verification()
		if res.get("ok", false):
			verify_status_label.text = "✓ Verification link sent to %s. Check your inbox!" % auth.get_email()
			verify_status_label.add_theme_color_override("font_color", Color(0.35, 0.9, 0.45))
		else:
			verify_status_label.text = "Error: %s" % res.get("error", "Failed to send email")
			verify_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		send_verify_btn.text = "Resend Verification"
		send_verify_btn.disabled = false


func _on_refresh_verification_pressed() -> void:
	var auth := auth_node if auth_node != null else get_node_or_null("/root/CloudAuth")
	if auth != null and auth.has_method("reload_user_profile"):
		refresh_verify_btn.disabled = true
		refresh_verify_btn.text = "Checking..."
		await auth.reload_user_profile()
		refresh_verify_btn.disabled = false
		refresh_verify_btn.text = "I've Verified — Refresh"
		_refresh_all()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	if has_node("/root/UIFocusGuard"):
		get_node("/root/UIFocusGuard").pop_lock(self)
	modal_closed.emit()
	queue_free()
