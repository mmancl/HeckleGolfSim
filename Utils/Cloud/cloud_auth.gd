extends Node

## CloudAuth — Autoload singleton for Firebase Authentication, encrypted token persistence,
## and cloud service status monitoring across Windows, macOS, Linux, Android, and iOS.

signal auth_state_changed(is_signed_in: bool, user: Dictionary)
signal google_device_code_received(user_code: String, verification_url: String, expires_in: int)
signal auth_error(code: String, message: String)
signal account_deleted()
signal cloud_service_paused_changed(is_paused: bool, message: String)

const DEFAULT_BUDGET_PAUSE_MESSAGE := "Multiplayer is temporarily paused for the remainder of the month as the developer's monthly budget has been reached, sorry for the inconvenience."
const SAVE_PATH := "user://cloud_auth.dat"
const ENCRYPTION_SALT := "HeckleGolfSim_CloudAuth_Secret_Salt_2026"

const FirestoreClient = preload("res://Utils/Cloud/firestore_client.gd")
const RtdbClient = preload("res://Utils/Cloud/rtdb_client.gd")

# Shared clients instantiated and owned by CloudAuth
var firestore: FirestoreClient
var rtdb: RtdbClient

var _api_key: String = ""
var _project_id: String = ""
var _database_url: String = ""
var _google_device_client_id: String = ""
var _google_desktop_client_id: String = ""

# Auth state
var _current_user: Dictionary = {}
var _id_token: String = ""
var _refresh_token: String = ""
var _token_expiry_unix: float = 0.0

# Deduplication state for get_valid_id_token
var _is_refreshing: bool = false
signal _token_refresh_completed(token: String)
var token_refresh_override: Callable = Callable()

# Budget circuit breaker status
var _is_paused: bool = false
var _pause_message: String = ""

# Google OAuth Device flow polling
var _google_poll_active: bool = false


func _init() -> void:
	_load_config()
	firestore = FirestoreClient.new(self)
	rtdb = RtdbClient.new(self, _database_url)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_session()
	# Check circuit breaker status on startup (silently, does not block startup)
	call_deferred("check_cloud_service_status")


func _load_config() -> void:
	if FileAccess.file_exists("res://Resources/firebase_config.json"):
		var f := FileAccess.open("res://Resources/firebase_config.json", FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				_api_key = parsed.get("apiKey", "")
				_project_id = parsed.get("projectId", "")
				_database_url = parsed.get("databaseURL", "")
				_google_device_client_id = parsed.get("googleDeviceClientId", "")
				_google_desktop_client_id = parsed.get("googleDesktopClientId", "")

	if _database_url.is_empty() and not _project_id.is_empty():
		_database_url = "https://%s-default-rtdb.firebaseio.com" % _project_id


# ── PUBLIC GETTERS ───────────────────────────────────────────────────────

func is_signed_in() -> bool:
	return not _current_user.is_empty() and not _current_user.get("is_anonymous", false)


func is_authenticated_any() -> bool:
	return not _current_user.is_empty() and not _id_token.is_empty()


func get_uid() -> String:
	return str(_current_user.get("uid", ""))


func get_email() -> String:
	return str(_current_user.get("email", ""))


func get_display_name() -> String:
	return str(_current_user.get("display_name", ""))


func is_email_verified() -> bool:
	return bool(_current_user.get("email_verified", false))


func is_anonymous() -> bool:
	return bool(_current_user.get("is_anonymous", false))


func get_user_dictionary() -> Dictionary:
	return _current_user.duplicate()


func get_valid_id_token() -> String:
	if _id_token.is_empty():
		return ""

	var now := Time.get_unix_time_from_system()
	# If more than 5 minutes (300 seconds) remain before expiry, current token is valid
	if (now + 300.0) < _token_expiry_unix:
		return _id_token

	if _refresh_token.is_empty():
		return _id_token

	# Deduplicate concurrent refresh calls
	if _is_refreshing:
		return await _token_refresh_completed

	_is_refreshing = true
	var refreshed_token := await _do_token_refresh()
	_is_refreshing = false
	_token_refresh_completed.emit(refreshed_token)
	return refreshed_token


# ── BUDGET CIRCUIT-BREAKER ───────────────────────────────────────────────

func is_cloud_service_paused() -> bool:
	return _is_paused


func get_cloud_pause_message() -> String:
	if not _pause_message.is_empty():
		return _pause_message
	return DEFAULT_BUDGET_PAUSE_MESSAGE


func set_cloud_service_paused(paused: bool, message: String = "") -> void:
	var msg := message if not message.is_empty() else DEFAULT_BUDGET_PAUSE_MESSAGE
	if _is_paused != paused or _pause_message != msg:
		_is_paused = paused
		_pause_message = msg if paused else ""
		cloud_service_paused_changed.emit(_is_paused, _pause_message)


func check_cloud_service_status() -> Dictionary:
	var status_doc := await firestore.get_doc("system/status", false)
	var paused := false
	var msg := DEFAULT_BUDGET_PAUSE_MESSAGE

	if status_doc.get("ok", false):
		var data: Dictionary = status_doc.get("data", {})
		paused = bool(data.get("paused", false))
		if data.has("message") and not str(data["message"]).is_empty():
			msg = str(data["message"])
	elif rtdb != null:
		var rtdb_status := await rtdb.get_path("system/status")
		if rtdb_status.get("ok", false) and rtdb_status.get("data") is Dictionary:
			var data: Dictionary = rtdb_status["data"]
			paused = bool(data.get("paused", false))
			if data.has("message") and not str(data["message"]).is_empty():
				msg = str(data["message"])

	set_cloud_service_paused(paused, msg)
	return {
		"paused": _is_paused,
		"message": _pause_message
	}


# ── AUTHENTICATION ACTIONS ───────────────────────────────────────────────

func sign_up_email(email: String, password: String, display_name: String) -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % _api_key
	var body := JSON.stringify({
		"email": email.strip_edges(),
		"password": password,
		"returnSecureToken": true
	})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200 and parsed is Dictionary:
		_id_token = parsed.get("idToken", "")
		_refresh_token = parsed.get("refreshToken", "")
		var expires_in: int = int(parsed.get("expiresIn", "3600"))
		_token_expiry_unix = Time.get_unix_time_from_system() + expires_in

		var uid: String = parsed.get("localId", "")
		_current_user = {
			"uid": uid,
			"email": parsed.get("email", email.strip_edges()),
			"display_name": display_name.strip_edges(),
			"email_verified": false,
			"is_anonymous": false,
			"provider_id": "password"
		}

		# Update display name in Firebase Auth profile if provided
		if not display_name.strip_edges().is_empty():
			await _update_profile_display_name(display_name.strip_edges())

		# Initialize user record in Firestore with leaderboard_opt_in = true (Owner Decision D6)
		await _init_user_cloud_record(uid, _current_user["email"], _current_user["display_name"])

		_save_session()
		auth_state_changed.emit(true, _current_user)
		return {"ok": true, "user": _current_user, "error": ""}

	var err_msg := _extract_firebase_error(parsed, resp.get("error", "Sign up failed"))
	auth_error.emit("SIGN_UP_FAILED", err_msg)
	return {"ok": false, "user": {}, "error": err_msg}


func sign_in_email(email: String, password: String) -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s" % _api_key
	var body := JSON.stringify({
		"email": email.strip_edges(),
		"password": password,
		"returnSecureToken": true
	})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200 and parsed is Dictionary:
		_id_token = parsed.get("idToken", "")
		_refresh_token = parsed.get("refreshToken", "")
		var expires_in: int = int(parsed.get("expiresIn", "3600"))
		_token_expiry_unix = Time.get_unix_time_from_system() + expires_in

		var uid: String = parsed.get("localId", "")
		_current_user = {
			"uid": uid,
			"email": parsed.get("email", email.strip_edges()),
			"display_name": parsed.get("displayName", ""),
			"email_verified": bool(parsed.get("emailVerified", false)),
			"is_anonymous": false,
			"provider_id": "password"
		}

		_save_session()
		auth_state_changed.emit(true, _current_user)
		return {"ok": true, "user": _current_user, "error": ""}

	var err_msg := _extract_firebase_error(parsed, resp.get("error", "Sign in failed"))
	auth_error.emit("SIGN_IN_FAILED", err_msg)
	return {"ok": false, "user": {}, "error": err_msg}


func send_password_reset(email: String) -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=%s" % _api_key
	var body := JSON.stringify({
		"requestType": "PASSWORD_RESET",
		"email": email.strip_edges()
	})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200:
		return {"ok": true, "user": {}, "error": ""}

	var err_msg := _extract_firebase_error(parsed, resp.get("error", "Password reset failed"))
	auth_error.emit("PASSWORD_RESET_FAILED", err_msg)
	return {"ok": false, "user": {}, "error": err_msg}


func send_email_verification() -> Dictionary:
	var token := await get_valid_id_token()
	if token.is_empty():
		return {"ok": false, "user": {}, "error": "Not authenticated"}

	var url := "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=%s" % _api_key
	var body := JSON.stringify({
		"requestType": "VERIFY_EMAIL",
		"idToken": token
	})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200:
		return {"ok": true, "user": _current_user, "error": ""}

	var err_msg := _extract_firebase_error(parsed, resp.get("error", "Email verification failed"))
	auth_error.emit("VERIFY_EMAIL_FAILED", err_msg)
	return {"ok": false, "user": {}, "error": err_msg}


func reload_user_profile() -> Dictionary:
	var token := await get_valid_id_token()
	if token.is_empty():
		return {"ok": false, "user": {}, "error": "Not authenticated"}

	var url := "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=%s" % _api_key
	var body := JSON.stringify({"idToken": token})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200 and parsed is Dictionary and parsed.has("users") and parsed["users"] is Array and parsed["users"].size() > 0:
		var u: Dictionary = parsed["users"][0]
		_current_user["email"] = u.get("email", _current_user.get("email", ""))
		_current_user["display_name"] = u.get("displayName", _current_user.get("display_name", ""))
		_current_user["email_verified"] = bool(u.get("emailVerified", false))
		_save_session()
		auth_state_changed.emit(is_signed_in(), _current_user)
		return {"ok": true, "user": _current_user, "error": ""}

	var err_msg := _extract_firebase_error(parsed, resp.get("error", "Failed to reload user profile"))
	return {"ok": false, "user": _current_user, "error": err_msg}


# ── GOOGLE SIGN-IN (UNIVERSAL DEVICE / WEB PORTAL FLOW) ──────────────────

var _google_loopback_server: TCPServer = null


func start_google_sign_in() -> Dictionary:
	cancel_google_sign_in()

	var client_id := _google_device_client_id
	if not client_id.is_empty():
		var code_url := "https://oauth2.googleapis.com/device/code"
		var req_body := "client_id=%s&scope=openid%%20email%%20profile" % client_id.uri_encode()
		var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])

		var resp := await make_http_request(code_url, HTTPClient.METHOD_POST, headers, req_body)
		var status: int = resp.get("status", 0)
		var parsed = JSON.parse_string(resp.get("body", "{}"))

		if status == 200 and parsed is Dictionary and parsed.has("device_code"):
			var device_code: String = parsed.get("device_code", "")
			var user_code: String = parsed.get("user_code", "")
			var verification_url: String = parsed.get("verification_url", parsed.get("verification_uri", "https://www.google.com/device"))
			var expires_in: int = int(parsed.get("expires_in", 1800))
			var poll_interval: float = float(parsed.get("interval", 5))

			google_device_code_received.emit(user_code, verification_url, expires_in)

			_google_poll_active = true
			return await _poll_google_device_token(client_id, device_code, poll_interval, expires_in)

	return await _start_web_portal_google_sign_in()


func _start_web_portal_google_sign_in() -> Dictionary:
	var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var user_code := ""
	for _i in range(6):
		user_code += alphabet[randi() % alphabet.length()]

	var port := 0
	_google_loopback_server = TCPServer.new()
	if _google_loopback_server.listen(0, "127.0.0.1") == OK:
		port = _google_loopback_server.get_local_port()
	else:
		_google_loopback_server = null

	var host_domain := ("%s.web.app" % _project_id) if not _project_id.is_empty() else "heckle-golf-sim.web.app"
	var verification_url := "https://%s/portal.html?device_code=%s" % [host_domain, user_code]
	if port > 0:
		verification_url += "&port=%d" % port
	verification_url += "&auto_google=1#stats-signin"

	var expires_in := 600
	google_device_code_received.emit(user_code, verification_url, expires_in)

	if DisplayServer.get_name() != "headless":
		OS.shell_open(verification_url)

	_google_poll_active = true
	return await _poll_web_portal_google_token(user_code, expires_in)


func cancel_google_sign_in() -> void:
	_google_poll_active = false
	if _google_loopback_server != null:
		_google_loopback_server.stop()
		_google_loopback_server = null


func _poll_web_portal_google_token(user_code: String, max_seconds: int) -> Dictionary:
	var elapsed := 0.0
	var rtdb_timer := 0.0
	var step := 0.25

	while _google_poll_active and elapsed < max_seconds:
		await get_tree().create_timer(step).timeout
		elapsed += step
		rtdb_timer += step
		if not _google_poll_active:
			return {"ok": false, "user": {}, "error": "Google sign in cancelled"}

		# 1. Check localhost loopback TCPServer for immediate same-device callback
		var loop_token := _check_loopback_server_for_token(user_code)
		if not loop_token.is_empty():
			cancel_google_sign_in()
			var ex_res := await _exchange_google_token_with_firebase(loop_token)
			_cleanup_rtdb_handoff(user_code)
			return ex_res

		# 2. Poll Firebase RTDB handoff path every 2.5 seconds (cross-device / mobile / fallback)
		if rtdb_timer >= 2.5 and not _database_url.is_empty():
			rtdb_timer = 0.0
			var handoff_url := "%s/auth_handoff/%s.json" % [_database_url.trim_suffix("/"), user_code]
			var resp := await make_http_request(handoff_url, HTTPClient.METHOD_GET, PackedStringArray(["Accept: application/json"]))
			if resp.get("status", 0) == 200:
				var parsed = JSON.parse_string(resp.get("body", "null"))
				if parsed is Dictionary and parsed.has("google_id_token"):
					var g_token: String = str(parsed.get("google_id_token", ""))
					if not g_token.is_empty():
						cancel_google_sign_in()
						var ex_res := await _exchange_google_token_with_firebase(g_token)
						await _cleanup_rtdb_handoff(user_code)
						return ex_res

	cancel_google_sign_in()
	return {"ok": false, "user": {}, "error": "Google sign in timed out"}


func _check_loopback_server_for_token(expected_code: String) -> String:
	if _google_loopback_server == null or not _google_loopback_server.is_connection_available():
		return ""
	var peer: StreamPeerTCP = _google_loopback_server.take_connection()
	if peer == null:
		return ""
	peer.poll()
	var avail := peer.get_available_bytes()
	if avail <= 0:
		return ""
	var req_text := peer.get_utf8_string(avail)
	var first_line := req_text.split("\r\n")[0] if req_text.contains("\r\n") else req_text.split("\n")[0]
	var parts := first_line.split(" ")
	var token := ""
	if parts.size() >= 2:
		var path_query := parts[1]
		var q_idx := path_query.find("?")
		if q_idx != -1:
			var query := path_query.substr(q_idx + 1)
			var code_param := ""
			for kv in query.split("&"):
				var pair := kv.split("=")
				if pair.size() == 2:
					var k := pair[0].uri_decode()
					var v := pair[1].uri_decode()
					if k == "id_token":
						token = v
					elif k == "code":
						code_param = v.to_upper()
			if not code_param.is_empty() and code_param != expected_code:
				token = ""

	var html_body := "<html><body style='background:#0a0f1e;color:#f1f5f9;font-family:sans-serif;text-align:center;padding:48px;'><h2 style='color:#22c55e;'>Signed in to Heckle Golf Simulator!</h2><p>You can close this tab and return to the game.</p></body></html>"
	var http_resp := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [html_body.to_utf8_buffer().size(), html_body]
	peer.put_data(http_resp.to_utf8_buffer())
	peer.disconnect_from_host()
	return token


func _cleanup_rtdb_handoff(user_code: String) -> void:
	if rtdb != null and is_authenticated_any():
		await rtdb.delete_path("auth_handoff/" + user_code)


func _poll_google_device_token(client_id: String, device_code: String, interval: float, max_seconds: int) -> Dictionary:
	var token_url := "https://oauth2.googleapis.com/token"
	var elapsed := 0.0

	while _google_poll_active and elapsed < max_seconds:
		await get_tree().create_timer(interval).timeout
		elapsed += interval
		if not _google_poll_active:
			return {"ok": false, "user": {}, "error": "Google sign in cancelled"}

		var post_body := "client_id=%s&device_code=%s&grant_type=urn:ietf:params:oauth:grant-type:device_code" % [
			client_id.uri_encode(),
			device_code.uri_encode()
		]
		var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])

		var resp := await make_http_request(token_url, HTTPClient.METHOD_POST, headers, post_body)
		var status: int = resp.get("status", 0)
		var parsed = JSON.parse_string(resp.get("body", "{}"))

		if status == 200 and parsed is Dictionary and parsed.has("id_token"):
			var google_id_token: String = parsed["id_token"]
			_google_poll_active = false
			return await _exchange_google_token_with_firebase(google_id_token)

		if parsed is Dictionary and parsed.has("error"):
			var err: String = parsed["error"]
			if err == "authorization_pending":
				continue
			elif err == "slow_down":
				interval += 5.0
				continue
			elif err == "access_denied":
				_google_poll_active = false
				auth_error.emit("GOOGLE_DENIED", "Google authorization access denied")
				return {"ok": false, "user": {}, "error": "Google sign in denied"}
			elif err == "expired_token":
				_google_poll_active = false
				auth_error.emit("GOOGLE_EXPIRED", "Google device code expired")
				return {"ok": false, "user": {}, "error": "Google device code expired"}

	_google_poll_active = false
	return {"ok": false, "user": {}, "error": "Google sign in timed out"}


func _exchange_google_token_with_firebase(google_id_token: String) -> Dictionary:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=%s" % _api_key
	var body := JSON.stringify({
		"postBody": "id_token=%s&providerId=google.com" % google_id_token,
		"requestUri": "http://localhost",
		"returnIdpCredential": true,
		"returnSecureToken": true
	})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200 and parsed is Dictionary:
		_id_token = parsed.get("idToken", "")
		_refresh_token = parsed.get("refreshToken", "")
		var expires_in: int = int(parsed.get("expiresIn", "3600"))
		_token_expiry_unix = Time.get_unix_time_from_system() + expires_in

		var uid: String = parsed.get("localId", "")
		_current_user = {
			"uid": uid,
			"email": parsed.get("email", ""),
			"display_name": parsed.get("displayName", ""),
			"email_verified": bool(parsed.get("emailVerified", true)),
			"is_anonymous": false,
			"provider_id": "google.com"
		}

		await _init_user_cloud_record(uid, _current_user["email"], _current_user["display_name"])
		_save_session()
		auth_state_changed.emit(true, _current_user)
		return {"ok": true, "user": _current_user, "error": ""}

	var err_msg := _extract_firebase_error(parsed, resp.get("error", "Failed to complete Google Sign In"))
	auth_error.emit("GOOGLE_SIGN_IN_FAILED", err_msg)
	return {"ok": false, "user": {}, "error": err_msg}


# ── ANONYMOUS AUTHENTICATION ─────────────────────────────────────────────

func ensure_anonymous_session() -> Dictionary:
	if is_authenticated_any():
		return {"ok": true, "user": _current_user, "error": ""}

	var url := "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % _api_key
	var body := JSON.stringify({"returnSecureToken": true})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200 and parsed is Dictionary:
		_id_token = parsed.get("idToken", "")
		_refresh_token = parsed.get("refreshToken", "")
		var expires_in: int = int(parsed.get("expiresIn", "3600"))
		_token_expiry_unix = Time.get_unix_time_from_system() + expires_in

		var uid: String = parsed.get("localId", "")
		_current_user = {
			"uid": uid,
			"email": "",
			"display_name": "Guest",
			"email_verified": false,
			"is_anonymous": true,
			"provider_id": "anonymous"
		}

		_save_session()
		auth_state_changed.emit(false, _current_user)
		return {"ok": true, "user": _current_user, "error": ""}

	var err_msg := _extract_firebase_error(parsed, resp.get("error", "Anonymous sign in failed"))
	if err_msg.contains("ADMIN_ONLY_OPERATION") or err_msg.contains("disabled"):
		err_msg = "Please sign in to host or join online multiplayer matches."
	auth_error.emit("ANONYMOUS_FAILED", err_msg)
	return {"ok": false, "user": {}, "error": err_msg}


# ── SIGN OUT & ACCOUNT DELETION ──────────────────────────────────────────

func sign_out() -> void:
	cancel_google_sign_in()
	_current_user = {}
	_id_token = ""
	_refresh_token = ""
	_token_expiry_unix = 0.0
	_delete_session_file()
	auth_state_changed.emit(false, {})


func delete_account_and_cloud_data(reauth_password: String = "") -> Dictionary:
	if not is_authenticated_any():
		return {"ok": false, "user": {}, "error": "Not authenticated"}

	var uid := get_uid()
	var email := get_email()

	# If re-auth password provided and was email/password user, re-authenticate first
	if not reauth_password.is_empty() and not email.is_empty():
		var reauth = await sign_in_email(email, reauth_password)
		if not reauth.get("ok", false):
			return {"ok": false, "user": {}, "error": "Re-authentication failed: " + reauth.get("error", "")}

	var token := await get_valid_id_token()

	# Clean up Firestore documents
	if not uid.is_empty():
		await firestore.delete_doc("users/%s" % uid)
		await firestore.delete_doc("public_profiles/%s" % uid)

	# Delete from Firebase Auth
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:delete?key=%s" % _api_key
	var body := JSON.stringify({"idToken": token})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)

	sign_out()
	account_deleted.emit()

	if status == 200:
		return {"ok": true, "user": {}, "error": ""}

	return {"ok": true, "user": {}, "error": "Account deleted locally, remote cleanup completed"}


# ── TOKEN REFRESH & PERSISTENCE ──────────────────────────────────────────

func _do_token_refresh() -> String:
	if token_refresh_override.is_valid():
		var override_res = await token_refresh_override.call()
		return str(override_res)

	if _refresh_token.is_empty():
		return _id_token

	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % _api_key
	var body := "grant_type=refresh_token&refresh_token=%s" % _refresh_token.uri_encode()
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])

	var resp := await make_http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var parsed = JSON.parse_string(resp.get("body", "{}"))

	if status == 200 and parsed is Dictionary:
		_id_token = parsed.get("id_token", "")
		_refresh_token = parsed.get("refresh_token", _refresh_token)
		var expires_in: int = int(parsed.get("expires_in", "3600"))
		_token_expiry_unix = Time.get_unix_time_from_system() + expires_in
		_save_session()
		return _id_token

	return _id_token


func _save_session() -> void:
	var payload := {
		"user": _current_user,
		"id_token": _id_token,
		"refresh_token": _refresh_token,
		"expiry": _token_expiry_unix
	}
	var json_str := JSON.stringify(payload)
	var key := _get_encryption_key()
	var file := FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.WRITE, key)
	if file != null:
		file.store_string(json_str)
		file.close()


func _load_session() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var key := _get_encryption_key()
	var file := FileAccess.open_encrypted_with_pass(SAVE_PATH, FileAccess.READ, key)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if parsed is Dictionary:
		_current_user = parsed.get("user", {})
		_id_token = parsed.get("id_token", "")
		_refresh_token = parsed.get("refresh_token", "")
		_token_expiry_unix = float(parsed.get("expiry", 0.0))
		auth_state_changed.emit(is_signed_in(), _current_user)


func _delete_session_file() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _get_encryption_key() -> String:
	var uid := OS.get_unique_id()
	if uid.is_empty():
		uid = "HeckleGolfSimulatorDefaultUID"
	return "%s_%s" % [uid, ENCRYPTION_SALT]


# ── CLOUD RECORD HELPERS ─────────────────────────────────────────────────

func _update_profile_display_name(display_name: String) -> void:
	var url := "https://identitytoolkit.googleapis.com/v1/accounts:update?key=%s" % _api_key
	var body := JSON.stringify({
		"idToken": _id_token,
		"displayName": display_name,
		"returnSecureToken": true
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	await make_http_request(url, HTTPClient.METHOD_POST, headers, body)


func _init_user_cloud_record(uid: String, email: String, display_name: String) -> void:
	if uid.is_empty():
		return
	# Leaderboard Opt-In default = true (Owner Decision D6)
	var user_data := {
		"email": email,
		"display_name": display_name,
		"leaderboard_opt_in": true,
		"updated_at": Time.get_datetime_string_from_system(true, true)
	}
	await firestore.set_doc("users/%s" % uid, user_data)


# ── HTTP REQUEST EXECUTION ───────────────────────────────────────────────

func make_http_request(url: String, method: HTTPClient.Method, headers: PackedStringArray, body: String = "") -> Dictionary:
	var hr := HTTPRequest.new()
	add_child(hr)
	var err := hr.request(url, headers, method, body)
	if err != OK:
		hr.queue_free()
		return {"status": 0, "headers": PackedStringArray(), "body": "", "error": "Request failed to start: %d" % err}

	var results = await hr.request_completed
	hr.queue_free()

	var res_status: int = results[1]
	var res_headers: PackedStringArray = results[2]
	var res_body: String = results[3].get_string_from_utf8()
	return {"status": res_status, "headers": res_headers, "body": res_body, "error": ""}


func _extract_firebase_error(parsed: Variant, default_msg: String) -> String:
	if parsed is Dictionary and parsed.has("error"):
		var err = parsed["error"]
		if err is Dictionary and err.has("message"):
			return str(err["message"])
		return str(err)
	return default_msg
