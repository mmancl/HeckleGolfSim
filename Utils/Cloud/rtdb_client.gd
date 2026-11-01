class_name RtdbClient
extends RefCounted

## Pure-GDScript Firebase Realtime Database REST client.
## Wraps {databaseURL}/{path}.json?auth={idToken}.

const RtdbStream = preload("res://Utils/Cloud/rtdb_stream.gd")

var database_url: String = ""
var project_id: String = ""
var auth_node: Node = null


func _init(p_auth_node: Node = null, p_database_url: String = "") -> void:
	auth_node = p_auth_node
	database_url = p_database_url
	_load_config()


func _load_config() -> void:
	if not database_url.is_empty():
		return
	if FileAccess.file_exists("res://Resources/firebase_config.json"):
		var f := FileAccess.open("res://Resources/firebase_config.json", FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				project_id = parsed.get("projectId", "")
				database_url = parsed.get("databaseURL", "")
	if database_url.is_empty() and not project_id.is_empty():
		database_url = "https://%s-default-rtdb.firebaseio.com" % project_id


# ── REST API OPERATIONS ──────────────────────────────────────────────────

func get_path(path: String, query_params: Dictionary = {}, with_etag: bool = false) -> Dictionary:
	var url := _build_url(path, query_params)
	var headers := PackedStringArray(["Accept: application/json"])
	if with_etag:
		headers.append("X-Firebase-ETag: true")

	var token := await _get_auth_token()
	if not token.is_empty():
		url += ("&" if url.contains("?") else "?") + "auth=" + token

	var resp := await _http_request(url, HTTPClient.METHOD_GET, headers)
	var status: int = resp.get("status", 0)
	var etag := _extract_etag(resp.get("headers", PackedStringArray()))

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "null"))
		return {
			"ok": true,
			"status": 200,
			"data": parsed,
			"etag": etag,
			"error": "",
			"budget_paused": false
		}

	var err_resp = await _handle_error_response(resp)
	err_resp["etag"] = etag
	return err_resp


func put_path(path: String, data: Variant, if_match_etag: String = "") -> Dictionary:
	var url := _build_url(path)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	if not if_match_etag.is_empty():
		if if_match_etag == "null_etag":
			headers.append("if-match: null")
		else:
			headers.append("if-match: %s" % if_match_etag)

	var token := await _get_auth_token()
	if not token.is_empty():
		url += ("&" if url.contains("?") else "?") + "auth=" + token

	var body := JSON.stringify(data)
	var resp := await _http_request(url, HTTPClient.METHOD_PUT, headers, body)
	var status: int = resp.get("status", 0)
	var etag := _extract_etag(resp.get("headers", PackedStringArray()))

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "null"))
		return {
			"ok": true,
			"status": 200,
			"data": parsed,
			"etag": etag,
			"error": "",
			"budget_paused": false
		}

	var err_resp = await _handle_error_response(resp)
	err_resp["etag"] = etag
	return err_resp


func patch_path(path: String, data: Dictionary) -> Dictionary:
	var url := _build_url(path)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	var token := await _get_auth_token()
	if not token.is_empty():
		url += ("&" if url.contains("?") else "?") + "auth=" + token

	var body := JSON.stringify(data)
	var resp := await _http_request(url, HTTPClient.METHOD_PATCH, headers, body)
	var status: int = resp.get("status", 0)
	var etag := _extract_etag(resp.get("headers", PackedStringArray()))

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "null"))
		return {
			"ok": true,
			"status": 200,
			"data": parsed,
			"etag": etag,
			"error": "",
			"budget_paused": false
		}

	var err_resp = await _handle_error_response(resp)
	err_resp["etag"] = etag
	return err_resp


func post_path(path: String, data: Variant) -> Dictionary:
	var url := _build_url(path)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	var token := await _get_auth_token()
	if not token.is_empty():
		url += ("&" if url.contains("?") else "?") + "auth=" + token

	var body := JSON.stringify(data)
	var resp := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)
	var etag := _extract_etag(resp.get("headers", PackedStringArray()))

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "{}"))
		return {
			"ok": true,
			"status": 200,
			"data": parsed,
			"etag": etag,
			"error": "",
			"budget_paused": false
		}

	var err_resp = await _handle_error_response(resp)
	err_resp["etag"] = etag
	return err_resp


func delete_path(path: String) -> Dictionary:
	var url := _build_url(path)
	var headers := PackedStringArray(["Accept: application/json"])

	var token := await _get_auth_token()
	if not token.is_empty():
		url += ("&" if url.contains("?") else "?") + "auth=" + token

	var resp := await _http_request(url, HTTPClient.METHOD_DELETE, headers)
	var status: int = resp.get("status", 0)
	var etag := _extract_etag(resp.get("headers", PackedStringArray()))

	if status == 200 or status == 204:
		return {
			"ok": true,
			"status": status,
			"data": null,
			"etag": etag,
			"error": "",
			"budget_paused": false
		}

	var err_resp = await _handle_error_response(resp)
	err_resp["etag"] = etag
	return err_resp


func open_stream(path: String) -> RtdbStream:
	var stream := RtdbStream.new()
	var url := _build_url(path)
	# Stream started asynchronously once token is retrieved
	_start_stream_async(stream, url)
	return stream


func _start_stream_async(stream: RtdbStream, url: String) -> void:
	var token := await _get_auth_token()
	stream.start(url, token)


# ── INTERNAL HELPERS ─────────────────────────────────────────────────────

func _build_url(path: String, query_params: Dictionary = {}) -> String:
	var clean_path := path.strip_edges().trim_prefix("/").trim_suffix("/")
	var url := "%s/%s.json" % [database_url.trim_suffix("/"), clean_path]
	if query_params.size() > 0:
		var parts: Array[String] = []
		for k in query_params:
			parts.append("%s=%s" % [str(k).uri_encode(), str(query_params[k]).uri_encode()])
		url += "?" + "&".join(parts)
	return url


func _get_auth_token() -> String:
	var auth := _resolve_auth()
	if auth != null and auth.has_method("get_valid_id_token"):
		return await auth.get_valid_id_token()
	return ""


func _resolve_auth() -> Node:
	if auth_node != null and is_instance_valid(auth_node):
		return auth_node
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("CloudAuth")
	return null


func _extract_etag(headers: PackedStringArray) -> String:
	for h in headers:
		var lower := h.to_lower()
		if lower.begins_with("etag:"):
			return h.substr(5).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""


func _handle_error_response(resp: Dictionary) -> Dictionary:
	var status: int = resp.get("status", 0)
	var body_str: String = resp.get("body", "")
	var error_msg: String = resp.get("error", "")

	if error_msg.is_empty() and not body_str.is_empty():
		var parsed = JSON.parse_string(body_str)
		if parsed is Dictionary and parsed.has("error"):
			error_msg = str(parsed["error"])
		else:
			error_msg = "HTTP %d: %s" % [status, body_str]
	elif error_msg.is_empty():
		error_msg = "HTTP %d" % status

	var budget_paused: bool = false
	if status == 403:
		var auth := _resolve_auth()
		if auth != null and auth.has_method("check_cloud_service_status"):
			var chk: Dictionary = await auth.check_cloud_service_status()
			if chk.get("paused", false):
				budget_paused = true
				error_msg = auth.get_cloud_pause_message()

	return {
		"ok": false,
		"status": status,
		"data": null,
		"etag": "",
		"error": error_msg,
		"budget_paused": budget_paused
	}


func _http_request(url: String, method: HTTPClient.Method, headers: PackedStringArray, body: String = "") -> Dictionary:
	var auth := _resolve_auth()
	if auth != null and auth.has_method("make_http_request"):
		return await auth.make_http_request(url, method, headers, body)

	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		var hr := HTTPRequest.new()
		loop.root.add_child(hr)
		var err := hr.request(url, headers, method, body)
		if err != OK:
			hr.queue_free()
			return {"status": 0, "headers": PackedStringArray(), "body": "", "error": "HTTPRequest error: %d" % err}
		var results = await hr.request_completed
		hr.queue_free()
		var res_status: int = results[1]
		var res_headers: PackedStringArray = results[2]
		var res_body: String = results[3].get_string_from_utf8()
		return {"status": res_status, "headers": res_headers, "body": res_body, "error": ""}

	return {"status": 0, "headers": PackedStringArray(), "body": "", "error": "No SceneTree available for HTTPRequest"}
