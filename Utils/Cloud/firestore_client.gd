class_name FirestoreClient
extends RefCounted

## Pure-GDScript Cloud Firestore REST client.
## Wraps https://firestore.googleapis.com/v1/projects/{projectId}/databases/(default)/documents.

var project_id: String = ""
var api_key: String = ""
var base_url: String = ""
var auth_node: Node = null


func _init(p_auth_node: Node = null) -> void:
	auth_node = p_auth_node
	_load_config()


func _load_config() -> void:
	if FileAccess.file_exists("res://Resources/firebase_config.json"):
		var f := FileAccess.open("res://Resources/firebase_config.json", FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				project_id = parsed.get("projectId", "")
				api_key = parsed.get("apiKey", "")
	if not project_id.is_empty():
		base_url = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents" % project_id


# ── VALUE SERIALIZATION & DESERIALIZATION ────────────────────────────────

static func gd_to_firestore_value(val: Variant) -> Dictionary:
	match typeof(val):
		TYPE_NIL:
			return {"nullValue": null}
		TYPE_BOOL:
			return {"booleanValue": val}
		TYPE_INT:
			return {"integerValue": str(val)}
		TYPE_FLOAT:
			return {"doubleValue": float(val)}
		TYPE_STRING, TYPE_STRING_NAME:
			return {"stringValue": str(val)}
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, \
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var values: Array = []
			for item in val:
				values.append(gd_to_firestore_value(item))
			return {"arrayValue": {"values": values}}
		TYPE_DICTIONARY:
			var fields: Dictionary = {}
			for k in val:
				fields[str(k)] = gd_to_firestore_value(val[k])
			return {"mapValue": {"fields": fields}}
		_:
			return {"stringValue": str(val)}


static func firestore_value_to_gd(val_dict: Dictionary) -> Variant:
	if val_dict.has("nullValue"):
		return null
	if val_dict.has("booleanValue"):
		return bool(val_dict["booleanValue"])
	if val_dict.has("integerValue"):
		return int(val_dict["integerValue"])
	if val_dict.has("doubleValue"):
		return float(val_dict["doubleValue"])
	if val_dict.has("stringValue"):
		return str(val_dict["stringValue"])
	if val_dict.has("timestampValue"):
		return str(val_dict["timestampValue"])
	if val_dict.has("referenceValue"):
		return str(val_dict["referenceValue"])
	if val_dict.has("geoPointValue"):
		return val_dict["geoPointValue"]
	if val_dict.has("arrayValue"):
		var arr: Array = []
		var av: Variant = val_dict.get("arrayValue")
		if av is Dictionary and av.has("values") and av["values"] is Array:
			for item in av["values"]:
				if item is Dictionary:
					arr.append(firestore_value_to_gd(item))
				else:
					arr.append(item)
		return arr
	if val_dict.has("mapValue"):
		var d: Dictionary = {}
		var mv: Variant = val_dict.get("mapValue")
		if mv is Dictionary and mv.has("fields") and mv["fields"] is Dictionary:
			var fields: Dictionary = mv["fields"]
			for k in fields:
				var v: Variant = fields[k]
				if v is Dictionary:
					d[k] = firestore_value_to_gd(v)
				else:
					d[k] = v
		return d
	return null


static func dict_to_firestore_fields(d: Dictionary) -> Dictionary:
	var fields: Dictionary = {}
	for k in d:
		fields[str(k)] = gd_to_firestore_value(d[k])
	return fields


static func firestore_fields_to_dict(f: Dictionary) -> Dictionary:
	var dict: Dictionary = {}
	for k in f:
		var v: Variant = f[k]
		if v is Dictionary:
			dict[k] = firestore_value_to_gd(v)
		else:
			dict[k] = v
	return dict


# ── REST API OPERATIONS ──────────────────────────────────────────────────

func get_doc(doc_path: String, require_auth: bool = true) -> Dictionary:
	var clean_path := doc_path.strip_edges().trim_prefix("/").trim_suffix("/")
	var url := "%s/%s" % [base_url, clean_path]
	var headers := PackedStringArray(["Accept: application/json"])

	var token := await _get_auth_token()
	if require_auth and token.is_empty():
		return {
			"ok": false,
			"status": 401,
			"data": {},
			"update_time": "",
			"error": "Authentication required",
			"budget_paused": false
		}
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	elif not api_key.is_empty():
		url += "?key=%s" % api_key

	var resp := await _http_request(url, HTTPClient.METHOD_GET, headers)
	var status: int = resp.get("status", 0)

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "{}"))
		if parsed is Dictionary:
			var raw_fields: Dictionary = parsed.get("fields", {})
			return {
				"ok": true,
				"status": 200,
				"data": firestore_fields_to_dict(raw_fields),
				"update_time": str(parsed.get("updateTime", "")),
				"error": "",
				"budget_paused": false
			}

	return await _handle_error_response(resp)


func set_doc(doc_path: String, fields: Dictionary, update_mask: PackedStringArray = [], update_time: String = "", current_document_exists: Variant = null) -> Dictionary:
	var clean_path := doc_path.strip_edges().trim_prefix("/").trim_suffix("/")
	var url := "%s/%s" % [base_url, clean_path]
	var query_params: Array[String] = []

	if update_mask.size() > 0:
		for field in update_mask:
			query_params.append("updateMask.fieldPaths=%s" % field.uri_encode())
	if not update_time.is_empty():
		query_params.append("currentDocument.updateTime=%s" % update_time.uri_encode())
	if current_document_exists != null:
		query_params.append("currentDocument.exists=%s" % str(bool(current_document_exists)).to_lower())

	var token := await _get_auth_token()
	if not token.is_empty():
		pass
	elif not api_key.is_empty():
		query_params.append("key=%s" % api_key)

	if query_params.size() > 0:
		url += "?" + "&".join(query_params)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	var body := JSON.stringify({
		"fields": dict_to_firestore_fields(fields)
	})

	var resp := await _http_request(url, HTTPClient.METHOD_PATCH, headers, body)
	var status: int = resp.get("status", 0)

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "{}"))
		if parsed is Dictionary:
			var raw_fields: Dictionary = parsed.get("fields", {})
			return {
				"ok": true,
				"status": 200,
				"data": firestore_fields_to_dict(raw_fields),
				"update_time": str(parsed.get("updateTime", "")),
				"error": "",
				"budget_paused": false
			}

	return await _handle_error_response(resp)


func delete_doc(doc_path: String) -> Dictionary:
	var clean_path := doc_path.strip_edges().trim_prefix("/").trim_suffix("/")
	var url := "%s/%s" % [base_url, clean_path]
	var headers := PackedStringArray(["Accept: application/json"])

	var token := await _get_auth_token()
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	elif not api_key.is_empty():
		url += "?key=%s" % api_key

	var resp := await _http_request(url, HTTPClient.METHOD_DELETE, headers)
	var status: int = resp.get("status", 0)
	if status == 200 or status == 204:
		return {
			"ok": true,
			"status": status,
			"data": {},
			"update_time": "",
			"error": "",
			"budget_paused": false
		}

	return await _handle_error_response(resp)


func list_docs(collection_path: String, page_size: int = 50, require_auth: bool = true) -> Dictionary:
	var clean_path := collection_path.strip_edges().trim_prefix("/").trim_suffix("/")
	var url := "%s/%s?pageSize=%d" % [base_url, clean_path, page_size]
	var headers := PackedStringArray(["Accept: application/json"])

	var token := await _get_auth_token()
	if require_auth and token.is_empty():
		return {
			"ok": false,
			"status": 401,
			"data": {},
			"documents": [],
			"update_time": "",
			"error": "Authentication required",
			"budget_paused": false
		}
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	elif not api_key.is_empty():
		url += "&key=%s" % api_key

	var resp := await _http_request(url, HTTPClient.METHOD_GET, headers)
	var status: int = resp.get("status", 0)

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "{}"))
		var docs: Array = []
		if parsed is Dictionary and parsed.has("documents") and parsed["documents"] is Array:
			for item in parsed["documents"]:
				if item is Dictionary and item.has("fields"):
					var doc_fields: Dictionary = firestore_fields_to_dict(item.get("fields", {}))
					doc_fields["_doc_name"] = item.get("name", "")
					doc_fields["_update_time"] = item.get("updateTime", "")
					var parts: PackedStringArray = str(item.get("name", "")).split("/")
					if parts.size() > 0:
						doc_fields["_doc_id"] = parts[parts.size() - 1]
					docs.append(doc_fields)
		return {
			"ok": true,
			"status": 200,
			"data": {"documents": docs},
			"documents": docs,
			"update_time": "",
			"error": "",
			"budget_paused": false
		}

	var err_resp = await _handle_error_response(resp)
	err_resp["documents"] = []
	return err_resp


func run_query(collection_id: String, where_filters: Array = [], order_by: Array = [], limit: int = 25, require_auth: bool = false) -> Dictionary:
	var url := "%s:runQuery" % base_url
	var query_params: Array[String] = []

	var token := await _get_auth_token()
	if require_auth and token.is_empty():
		return {
			"ok": false,
			"status": 401,
			"data": {},
			"documents": [],
			"update_time": "",
			"error": "Authentication required",
			"budget_paused": false
		}
	if not token.is_empty():
		pass
	elif not api_key.is_empty():
		query_params.append("key=%s" % api_key)

	if query_params.size() > 0:
		url += "?" + "&".join(query_params)

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	var structured_query := {
		"from": [{"collectionId": collection_id}],
		"limit": limit
	}
	if where_filters.size() > 0:
		structured_query["where"] = _build_where_clause(where_filters)
	if order_by.size() > 0:
		var normalized_order: Array = []
		for ob in order_by:
			if ob is Dictionary:
				if ob.has("field") and ob["field"] is String:
					var dir_str: String = ob.get("dir", ob.get("direction", "ASCENDING"))
					normalized_order.append({
						"field": {"fieldPath": ob["field"]},
						"direction": dir_str
					})
				else:
					normalized_order.append(ob)
			else:
				normalized_order.append(ob)
		structured_query["orderBy"] = normalized_order

	var body := JSON.stringify({"structuredQuery": structured_query})
	var resp := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "[]"))
		var docs: Array = []
		if parsed is Array:
			for item in parsed:
				if item is Dictionary and item.has("document"):
					var doc_info: Dictionary = item["document"]
					var doc_fields: Dictionary = firestore_fields_to_dict(doc_info.get("fields", {}))
					doc_fields["_doc_name"] = doc_info.get("name", "")
					doc_fields["_update_time"] = doc_info.get("updateTime", "")
					docs.append(doc_fields)
		return {
			"ok": true,
			"status": 200,
			"data": {"documents": docs},
			"documents": docs,
			"update_time": "",
			"error": "",
			"budget_paused": false
		}

	var err_resp = await _handle_error_response(resp)
	err_resp["documents"] = []
	return err_resp


func commit_writes(writes: Array) -> Dictionary:
	var url := "%s:commit" % base_url
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json"
	])

	var token := await _get_auth_token()
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)
	elif not api_key.is_empty():
		url += "?key=%s" % api_key

	var body := JSON.stringify({"writes": writes})
	var resp := await _http_request(url, HTTPClient.METHOD_POST, headers, body)
	var status: int = resp.get("status", 0)

	if status == 200:
		var parsed = JSON.parse_string(resp.get("body", "{}"))
		return {
			"ok": true,
			"status": 200,
			"data": parsed if parsed is Dictionary else {},
			"update_time": "",
			"error": "",
			"budget_paused": false
		}

	return await _handle_error_response(resp)


# ── INTERNAL HELPERS ─────────────────────────────────────────────────────

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


func _build_where_clause(filters: Array) -> Dictionary:
	if filters.size() == 1:
		return _build_filter(filters[0])
	var composite: Array = []
	for f in filters:
		composite.append(_build_filter(f))
	return {
		"compositeFilter": {
			"op": "AND",
			"filters": composite
		}
	}


func _build_filter(filter_dict: Dictionary) -> Dictionary:
	# Expects { "field": String, "op": String, "val": Variant }
	# op e.g. "EQUAL", "LESS_THAN", "GREATER_THAN_OR_EQUAL", etc.
	var field: String = filter_dict.get("field", "")
	var op: String = filter_dict.get("op", "EQUAL").to_upper()
	var val: Variant = filter_dict.get("val", null)
	return {
		"fieldFilter": {
			"field": {"fieldPath": field},
			"op": op,
			"value": gd_to_firestore_value(val)
		}
	}


func _handle_error_response(resp: Dictionary) -> Dictionary:
	var status: int = resp.get("status", 0)
	var body_str: String = resp.get("body", "")
	var error_msg: String = resp.get("error", "")

	if error_msg.is_empty() and not body_str.is_empty():
		var parsed = JSON.parse_string(body_str)
		var err_obj = null
		if parsed is Dictionary and parsed.has("error"):
			err_obj = parsed["error"]
		elif parsed is Array and not parsed.is_empty() and parsed[0] is Dictionary and parsed[0].has("error"):
			err_obj = parsed[0]["error"]

		if err_obj is Dictionary:
			error_msg = str(err_obj.get("message", "HTTP %d" % status))
		elif err_obj != null:
			error_msg = str(err_obj)
		else:
			error_msg = "HTTP %d" % status if body_str.length() > 100 else "HTTP %d: %s" % [status, body_str]
	elif error_msg.is_empty():
		error_msg = "HTTP %d" % status

	if error_msg.contains("Missing or insufficient permissions"):
		error_msg = "Permission denied: Missing or insufficient permissions."

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
		"data": {},
		"update_time": "",
		"error": error_msg,
		"budget_paused": budget_paused
	}


func _http_request(url: String, method: HTTPClient.Method, headers: PackedStringArray, body: String = "") -> Dictionary:
	var auth := _resolve_auth()
	if auth != null and auth.has_method("make_http_request"):
		return await auth.make_http_request(url, method, headers, body)

	# Standalone fallback via temporary HTTPRequest in SceneTree
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		var hr := HTTPRequest.new()
		loop.root.add_child(hr)
		var err := hr.request(url, headers, method, body)
		if err != OK:
			hr.queue_free()
			return {"status": 0, "headers": PackedStringArray(), "body": "", "error": "HTTPRequest start failed: %d" % err}
		var results = await hr.request_completed
		hr.queue_free()
		var res_status: int = results[1]
		var res_headers: PackedStringArray = results[2]
		var res_body: String = results[3].get_string_from_utf8()
		return {"status": res_status, "headers": res_headers, "body": res_body, "error": ""}

	return {"status": 0, "headers": PackedStringArray(), "body": "", "error": "No SceneTree available for HTTPRequest"}
