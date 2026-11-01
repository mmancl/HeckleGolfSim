class_name AccountModal
extends Control

## Cloud Account & Authentication Dialog.
## Provides Google Sign-In, Email/Password sign-up/in, token management,
## leaderboard opt-in toggle, budget pause banner, and 100% controller navigation.

const BudgetPausedBanner = preload("res://UI/Account/budget_paused_banner.gd")

signal closed

@onready var dimmer_panel: Panel = $DimmerPanel
@onready var modal_card: PanelContainer = $CenterContainer/ModalCard
@onready var banner: BudgetPausedBanner = $CenterContainer/ModalCard/MarginContainer/VBox/BudgetPausedBanner
@onready var title_label: Label = $CenterContainer/ModalCard/MarginContainer/VBox/Header/TitleLabel
@onready var close_x_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/Header/CloseXButton

# Signed-out controls
@onready var signed_out_container: VBoxContainer = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer
@onready var google_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/GoogleButton
@onready var google_device_panel: PanelContainer = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/GoogleDevicePanel
@onready var google_code_label: Label = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/GoogleDevicePanel/VBox/CodeLabel
@onready var google_copy_open_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/GoogleDevicePanel/VBox/CopyOpenButton
@onready var google_cancel_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/GoogleDevicePanel/VBox/CancelButton
@onready var google_status_label: Label = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/GoogleDevicePanel/VBox/StatusLabel

@onready var tab_signin_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/TabContainer/SignInTabButton
@onready var tab_signup_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/TabContainer/SignUpTabButton

@onready var email_input: LineEdit = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/FormContainer/EmailInput
@onready var password_input: LineEdit = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/FormContainer/PasswordInput
@onready var display_name_container: VBoxContainer = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/FormContainer/DisplayNameContainer
@onready var display_name_input: LineEdit = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/FormContainer/DisplayNameContainer/DisplayNameInput
@onready var submit_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/FormContainer/SubmitButton
@onready var forgot_password_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/FormContainer/ForgotPasswordButton
@onready var auth_status_label: Label = $CenterContainer/ModalCard/MarginContainer/VBox/SignedOutContainer/AuthStatusLabel

# Signed-in controls
@onready var signed_in_container: VBoxContainer = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer
@onready var user_display_name_label: Label = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer/ProfileCard/VBox/DisplayNameLabel
@onready var user_email_label: Label = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer/ProfileCard/VBox/EmailLabel
@onready var provider_label: Label = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer/ProfileCard/VBox/ProviderLabel
@onready var resend_verification_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer/ResendVerificationButton
@onready var leaderboard_opt_in_toggle: CheckButton = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer/LeaderboardOptInToggle
@onready var sign_out_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer/SignOutButton
@onready var delete_account_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/SignedInContainer/DeleteAccountButton

# Footer
@onready var footer_close_button: Button = $CenterContainer/ModalCard/MarginContainer/VBox/Footer/CloseButton

var _is_signup_mode: bool = false
var _google_verification_url: String = "https://www.google.com/device"
var _active_google_code: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_styles()
	_connect_signals()
	_refresh_view()

	# Register modal lock with UIFocusGuard if present
	var ufg = _get_ui_focus_guard()
	if ufg != null and ufg.has_method("push_lock"):
		ufg.push_lock(self)

	call_deferred("_update_controller_focus_navigation")
	call_deferred("_focus_default_control")


func _exit_tree() -> void:
	var ufg = _get_ui_focus_guard()
	if ufg != null and ufg.has_method("pop_lock"):
		ufg.pop_lock(self)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("ui_cancel"):
		# Guard against closing dialog if user presses Backspace while editing a LineEdit
		if event is InputEventKey and (event.keycode == KEY_BACKSPACE or event.physical_keycode == KEY_BACKSPACE):
			return
		var focus_owner = get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit:
			# If user is in LineEdit, pressing escape or B cancels out of input first
			pass
		_on_close_pressed()
		get_viewport().set_input_as_handled()


# ── SETUP & STYLES ───────────────────────────────────────────────────────

func _setup_styles() -> void:
	# High-visibility gold/cyan focus border
	var focus_box := StyleBoxFlat.new()
	focus_box.bg_color = Color(0, 0, 0, 0)
	focus_box.border_color = Color(0.95, 0.76, 0.22, 1.0)
	focus_box.set_border_width_all(3)
	focus_box.set_corner_radius_all(8)

	var focusable_controls: Array[Control] = [
		close_x_button, google_button, google_copy_open_button, google_cancel_button,
		tab_signin_button, tab_signup_button, email_input, password_input,
		display_name_input, submit_button, forgot_password_button,
		resend_verification_button, leaderboard_opt_in_toggle, sign_out_button,
		delete_account_button, footer_close_button
	]
	for c in focusable_controls:
		if c != null:
			c.focus_mode = Control.FOCUS_ALL
			c.add_theme_stylebox_override("focus", focus_box)

	_apply_standard_google_button_style()


func _apply_standard_google_button_style() -> void:
	if google_button == null:
		return

	# Standard Google Sign-In light surface style (#FFFFFF, #747775 border, #1F1F1F text)
	var g_normal := StyleBoxFlat.new()
	g_normal.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	g_normal.border_color = Color(0.455, 0.467, 0.459, 1.0) # #747775
	g_normal.set_border_width_all(1)
	g_normal.set_corner_radius_all(4)
	g_normal.content_margin_left = 14
	g_normal.content_margin_right = 14
	g_normal.content_margin_top = 8
	g_normal.content_margin_bottom = 8

	var g_hover := g_normal.duplicate()
	g_hover.bg_color = Color(0.949, 0.949, 0.949, 1.0) # #F2F2F2
	g_hover.border_color = Color(0.35, 0.36, 0.36, 1.0)

	var g_pressed := g_normal.duplicate()
	g_pressed.bg_color = Color(0.910, 0.918, 0.929, 1.0) # #E8EAED
	g_pressed.border_color = Color(0.259, 0.522, 0.957, 1.0) # #4285F4

	var g_focus := g_normal.duplicate()
	g_focus.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	g_focus.border_color = Color(0.259, 0.522, 0.957, 1.0) # #4285F4
	g_focus.set_border_width_all(3)

	google_button.add_theme_stylebox_override("normal", g_normal)
	google_button.add_theme_stylebox_override("hover", g_hover)
	google_button.add_theme_stylebox_override("pressed", g_pressed)
	google_button.add_theme_stylebox_override("focus", g_focus)

	var dark_text := Color(0.122, 0.122, 0.122, 1.0) # #1F1F1F
	google_button.add_theme_color_override("font_color", dark_text)
	google_button.add_theme_color_override("font_hover_color", dark_text)
	google_button.add_theme_color_override("font_pressed_color", dark_text)
	google_button.add_theme_color_override("font_focus_color", dark_text)
	google_button.add_theme_color_override("icon_normal_color", Color.WHITE)
	google_button.add_theme_color_override("icon_hover_color", Color.WHITE)
	google_button.add_theme_color_override("icon_pressed_color", Color.WHITE)
	google_button.add_theme_color_override("icon_focus_color", Color.WHITE)
	google_button.add_theme_constant_override("h_separation", 12)
	google_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	google_button.text = "Sign in with Google"

	var svg_str := '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>'
	var img := Image.new()
	if img.load_svg_from_string(svg_str) == OK:
		google_button.icon = ImageTexture.create_from_image(img)


func _connect_signals() -> void:
	close_x_button.pressed.connect(_on_close_pressed)
	footer_close_button.pressed.connect(_on_close_pressed)

	google_button.pressed.connect(_on_google_sign_in_pressed)
	google_copy_open_button.pressed.connect(_on_google_copy_open_pressed)
	google_cancel_button.pressed.connect(_on_google_cancel_pressed)

	tab_signin_button.pressed.connect(func(): _set_auth_mode(false))
	tab_signup_button.pressed.connect(func(): _set_auth_mode(true))

	submit_button.pressed.connect(_on_submit_pressed)
	forgot_password_button.pressed.connect(_on_forgot_password_pressed)

	resend_verification_button.pressed.connect(_on_resend_verification_pressed)
	leaderboard_opt_in_toggle.toggled.connect(_on_leaderboard_opt_in_toggled)
	sign_out_button.pressed.connect(_on_sign_out_pressed)
	delete_account_button.pressed.connect(_on_delete_account_pressed)

	var auth = _get_cloud_auth()
	if auth != null:
		if not auth.auth_state_changed.is_connected(_on_auth_state_changed):
			auth.auth_state_changed.connect(_on_auth_state_changed)
		if not auth.google_device_code_received.is_connected(_on_google_device_code_received):
			auth.google_device_code_received.connect(_on_google_device_code_received)
		if not auth.auth_error.is_connected(_on_auth_error):
			auth.auth_error.connect(_on_auth_error)


# ── VIEW SWITCHING & RENDERING ───────────────────────────────────────────

func _refresh_view() -> void:
	var auth = _get_cloud_auth()
	var signed_in: bool = auth != null and auth.is_signed_in()

	signed_out_container.visible = not signed_in
	signed_in_container.visible = signed_in
	google_device_panel.visible = false

	# Google Sign-In button must be enabled and visible on all platforms (Windows, macOS, Linux, Android, iOS)
	google_button.visible = not signed_in

	if signed_in:
		user_display_name_label.text = auth.get_display_name() if not auth.get_display_name().is_empty() else "Golfer"
		user_email_label.text = auth.get_email()
		provider_label.text = "Account Provider: %s" % str(auth.get_user_dictionary().get("provider_id", "Email/Password"))
		resend_verification_button.visible = not auth.is_email_verified()
		# Load current leaderboard opt-in status (defaults to true)
		_load_user_leaderboard_setting()
	else:
		_set_auth_mode(_is_signup_mode)

	_update_controller_focus_navigation()


func _set_auth_mode(is_signup: bool) -> void:
	_is_signup_mode = is_signup
	display_name_container.visible = is_signup
	submit_button.text = "Create Account" if is_signup else "Sign In"
	forgot_password_button.visible = not is_signup
	auth_status_label.text = ""

	if is_signup:
		tab_signup_button.add_theme_color_override("font_color", Color(0.95, 0.76, 0.22, 1.0))
		tab_signin_button.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
	else:
		tab_signin_button.add_theme_color_override("font_color", Color(0.95, 0.76, 0.22, 1.0))
		tab_signup_button.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))

	_update_controller_focus_navigation()


func _load_user_leaderboard_setting() -> void:
	var auth = _get_cloud_auth()
	if auth == null or not auth.is_signed_in():
		return
	var uid: String = auth.get_uid()
	var doc: Dictionary = await auth.firestore.get_doc("users/%s" % uid, false)
	if doc.get("ok", false) and doc.get("data") is Dictionary:
		var data: Dictionary = doc["data"]
		leaderboard_opt_in_toggle.set_pressed_no_signal(bool(data.get("leaderboard_opt_in", true)))
	else:
		# Owner Decision D6: leaderboard_opt_in = true by default
		leaderboard_opt_in_toggle.set_pressed_no_signal(true)


# ── CONTROLLER / GAMEPAD FOCUS MANAGEMENT ────────────────────────────────

func _update_controller_focus_navigation() -> void:
	var active_controls: Array[Control] = []

	var auth = _get_cloud_auth()
	var signed_in: bool = auth != null and auth.is_signed_in()

	active_controls.append(close_x_button)

	if not signed_in:
		if google_device_panel.visible:
			active_controls.append(google_copy_open_button)
			active_controls.append(google_cancel_button)
		else:
			active_controls.append(google_button)
			active_controls.append(tab_signin_button)
			active_controls.append(tab_signup_button)
			active_controls.append(email_input)
			active_controls.append(password_input)
			if _is_signup_mode:
				active_controls.append(display_name_input)
			active_controls.append(submit_button)
			if not _is_signup_mode:
				active_controls.append(forgot_password_button)
	else:
		if resend_verification_button.visible:
			active_controls.append(resend_verification_button)
		active_controls.append(leaderboard_opt_in_toggle)
		active_controls.append(sign_out_button)
		active_controls.append(delete_account_button)

	active_controls.append(footer_close_button)

	var n := active_controls.size()
	for i in range(n):
		var cur := active_controls[i]
		var prev := active_controls[(i - 1 + n) % n]
		var next := active_controls[(i + 1) % n]

		cur.focus_neighbor_top = cur.get_path_to(prev)
		cur.focus_neighbor_bottom = cur.get_path_to(next)
		cur.focus_neighbor_left = cur.get_path_to(prev)
		cur.focus_neighbor_right = cur.get_path_to(next)

	# Refine horizontal navigation between signin and signup tabs
	if not signed_in and not google_device_panel.visible:
		tab_signin_button.focus_neighbor_right = tab_signin_button.get_path_to(tab_signup_button)
		tab_signup_button.focus_neighbor_left = tab_signup_button.get_path_to(tab_signin_button)


func _focus_default_control() -> void:
	var auth = _get_cloud_auth()
	if auth != null and auth.is_signed_in():
		leaderboard_opt_in_toggle.grab_focus()
	else:
		google_button.grab_focus()


# ── ACTION HANDLERS ──────────────────────────────────────────────────────

func _on_google_sign_in_pressed() -> void:
	var auth = _get_cloud_auth()
	if auth == null:
		return
	auth_status_label.text = "Contacting Google..."
	auth_status_label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.22, 1.0))
	var res: Dictionary = await auth.start_google_sign_in()
	if res.get("ok", false):
		_refresh_view()
	else:
		auth_status_label.text = res.get("error", "Google sign in failed")
		auth_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))


func _on_google_device_code_received(user_code: String, verification_url: String, expires_in: int) -> void:
	_active_google_code = user_code
	_google_verification_url = verification_url
	google_code_label.text = user_code
	google_status_label.text = "Waiting for approval in browser (%ds)..." % expires_in
	google_device_panel.visible = true
	google_button.visible = false
	_update_controller_focus_navigation()
	google_copy_open_button.grab_focus()


func _on_google_copy_open_pressed() -> void:
	if not _active_google_code.is_empty():
		DisplayServer.clipboard_set(_active_google_code)
	OS.shell_open(_google_verification_url)
	google_status_label.text = "Code copied! Approve sign-in in your browser window."


func _on_google_cancel_pressed() -> void:
	var auth = _get_cloud_auth()
	if auth != null:
		auth.cancel_google_sign_in()
	google_device_panel.visible = false
	google_button.visible = true
	_update_controller_focus_navigation()
	google_button.grab_focus()


func _on_submit_pressed() -> void:
	var auth = _get_cloud_auth()
	if auth == null:
		return

	var email := email_input.text.strip_edges()
	var pass_txt := password_input.text
	var dname := display_name_input.text.strip_edges()

	if email.is_empty() or pass_txt.is_empty():
		auth_status_label.text = "Please enter both email and password."
		auth_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
		return

	auth_status_label.text = "Connecting..."
	auth_status_label.add_theme_color_override("font_color", Color(0.95, 0.76, 0.22, 1.0))

	var res: Dictionary
	if _is_signup_mode:
		res = await auth.sign_up_email(email, pass_txt, dname)
	else:
		res = await auth.sign_in_email(email, pass_txt)

	if res.get("ok", false):
		_refresh_view()
	else:
		auth_status_label.text = res.get("error", "Authentication failed")
		auth_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))


func _on_forgot_password_pressed() -> void:
	var auth = _get_cloud_auth()
	if auth == null:
		return
	var email := email_input.text.strip_edges()
	if email.is_empty():
		auth_status_label.text = "Please enter your email address to reset password."
		auth_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
		return

	var res: Dictionary = await auth.send_password_reset(email)
	if res.get("ok", false):
		auth_status_label.text = "Password reset email sent! Check your inbox."
		auth_status_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4, 1.0))
	else:
		auth_status_label.text = res.get("error", "Failed to send reset email")
		auth_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))


func _on_resend_verification_pressed() -> void:
	var auth = _get_cloud_auth()
	if auth == null:
		return
	var res: Dictionary = await auth.send_email_verification()
	if res.get("ok", false):
		resend_verification_button.text = "Verification Email Sent!"
		resend_verification_button.disabled = true


func _on_leaderboard_opt_in_toggled(toggled_on: bool) -> void:
	var auth = _get_cloud_auth()
	if auth == null or not auth.is_signed_in():
		return
	var uid: String = auth.get_uid()

	# Update user record
	await auth.firestore.set_doc("users/%s" % uid, {
		"leaderboard_opt_in": toggled_on,
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}, PackedStringArray(["leaderboard_opt_in", "updated_at"]))

	# If opt-out, delete public_profiles/{uid}
	if not toggled_on:
		await auth.firestore.delete_doc("public_profiles/%s" % uid)


func _on_sign_out_pressed() -> void:
	var auth = _get_cloud_auth()
	if auth != null:
		auth.sign_out()
	_refresh_view()


func _on_delete_account_pressed() -> void:
	var auth = _get_cloud_auth()
	if auth == null:
		return
	# Perform account deletion and data wipe
	var res: Dictionary = await auth.delete_account_and_cloud_data()
	_refresh_view()


func _on_auth_state_changed(_is_signed_in: bool, _user: Dictionary) -> void:
	_refresh_view()


func _on_auth_error(_code: String, message: String) -> void:
	auth_status_label.text = message
	auth_status_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))


func _on_close_pressed() -> void:
	var ufg = _get_ui_focus_guard()
	if ufg != null and ufg.has_method("pop_lock"):
		ufg.pop_lock(self)
	closed.emit()
	queue_free()


func _get_cloud_auth() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("CloudAuth")
	return null


func _get_ui_focus_guard() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("UIFocusGuard")
	return null
