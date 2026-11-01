class_name LinkService
extends RefCounted

## Service managing account linking requests, delegation grants,
## and access revocation between host simulators and visiting players.

signal link_request_updated(player_name: String, status: String, cloud_uid: String)
signal incoming_requests_loaded(requests: Array[Dictionary])
signal active_delegates_loaded(delegates: Array[Dictionary])

const FirestoreClientClass = preload("res://Utils/Cloud/firestore_client.gd")

var firestore = null
var auth_node: Node = null


func _init(p_firestore = null, p_auth_node: Node = null) -> void:
	if p_firestore != null:
		firestore = p_firestore
	if p_auth_node != null:
		auth_node = p_auth_node


## Deterministic ID: requester_uid + "__" + target_email.strip_edges().to_lower().sha256_text().substr(0, 20)
static func make_request_id(requester_uid: String, target_email: String) -> String:
	var clean_uid := requester_uid.strip_edges()
	var clean_email := target_email.strip_edges().to_lower()
	return "%s__%s" % [clean_uid, clean_email.sha256_text().substr(0, 20)]


## Called by user1 (host) for a secondary local profile
func send_link_request(local_player_name: String, target_email: String) -> Dictionary:
	var auth := _get_auth()
	if auth == null or not auth.has_method("is_signed_in") or not auth.is_signed_in():
		return {"ok": false, "error": "Must be signed in to link a cloud account"}
	if auth.has_method("is_cloud_service_paused") and auth.is_cloud_service_paused():
		return {"ok": false, "error": "Cloud service paused", "budget_paused": true}

	var clean_email := target_email.strip_edges().to_lower()
	if clean_email.length() < 3 or clean_email.find("@") == -1 or clean_email.find(".") == -1:
		return {"ok": false, "error": "Invalid target email address"}

	var requester_uid: String = auth.get_uid()
	if requester_uid.is_empty():
		return {"ok": false, "error": "No user ID available"}

	var req_id := make_request_id(requester_uid, clean_email)
	var requester_name: String = auth.get_display_name() if auth.has_method("get_display_name") else ""
	if requester_name.is_empty():
		var mp := _get_mp()
		if mp != null and mp.has_method("get_primary_player_name"):
			requester_name = mp.get_primary_player_name()
	if requester_name.is_empty():
		requester_name = "Host"

	var requester_email: String = auth.get_email() if auth.has_method("get_email") else ""

	var doc_data := {
		"schema_version": 1,
		"request_id": req_id,
		"requester_uid": requester_uid,
		"requester_name": requester_name,
		"requester_email": requester_email,
		"target_email_lower": clean_email,
		"status": "pending",
		"created_at": int(Time.get_unix_time_from_system()),
		"local_player_name": local_player_name
	}

	var client = _get_firestore()
	if client == null:
		return {"ok": false, "error": "No Firestore client"}

	var res: Dictionary = await client.set_doc("link_requests/" + req_id, doc_data)
	if not res.get("ok", false):
		return {"ok": false, "error": res.get("error", "Failed to create link request")}

	# Update local profile in registry to "pending_link"
	var mp := _get_mp()
	if mp != null and mp.has_method("get_registered_players"):
		var players: Array = mp.get_registered_players()
		for p in players:
			if str(p.get("name", "")).to_lower() == local_player_name.to_lower():
				p["link_role"] = "pending_link"
				p["pending_request_id"] = req_id
				p["pending_target_email"] = clean_email
				p["email"] = clean_email
				break
		mp.save_registered_players(players)

	link_request_updated.emit(local_player_name, "pending", "")
	return {"ok": true, "request_id": req_id, "data": doc_data}


## Checks status of outgoing pending requests created by CloudAuth.get_uid();
## called on startup and every 10s while the "Waiting for Approval" modal is open (max 10 min).
func check_outgoing_requests() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var mp := _get_mp()
	if mp == null or not mp.has_method("get_registered_players"):
		return results

	var auth := _get_auth()
	var my_uid: String = auth.get_uid() if (auth != null and auth.has_method("get_uid")) else ""

	var players: Array = mp.get_registered_players()
	var modified := false
	var client = _get_firestore()
	if client == null:
		return results

	for p in players:
		if str(p.get("link_role", "")) != "pending_link":
			continue

		var p_name: String = str(p.get("name", ""))
		var req_id: String = str(p.get("pending_request_id", ""))
		if req_id.is_empty() and p.has("pending_target_email") and not my_uid.is_empty():
			req_id = make_request_id(my_uid, str(p["pending_target_email"]))

		if req_id.is_empty():
			continue

		var res: Dictionary = await client.get_doc("link_requests/" + req_id)
		if res.get("ok", false) and res.get("data") is Dictionary:
			var doc_data: Dictionary = res["data"]
			var status: String = str(doc_data.get("status", "pending"))
			var target_uid: String = str(doc_data.get("target_uid", ""))
			doc_data["local_player_name"] = p_name
			doc_data["request_id"] = req_id
			results.append(doc_data)

			if status == "approved" and not target_uid.is_empty():
				p["link_role"] = "linked"
				p["cloud_uid"] = target_uid
				p["last_synced_rev"] = 0
				p.erase("pending_request_id")
				p.erase("pending_target_email")
				modified = true
				mp.save_registered_players(players)
				link_request_updated.emit(p_name, "approved", target_uid)
				var sync := _get_cloud_sync()
				if sync != null:
					if sync.has_method("enqueue_historical_local_matches_for_profile"):
						sync.call("enqueue_historical_local_matches_for_profile", p_name, target_uid)
					if sync.has_method("mark_profile_dirty"):
						sync.call("mark_profile_dirty", p_name)
					if sync.has_method("sync_single_profile"):
						sync.call("sync_single_profile", p_name, target_uid)
			elif status in ["denied", "revoked"]:
				p["link_role"] = "none"
				p.erase("pending_request_id")
				p.erase("pending_target_email")
				modified = true
				link_request_updated.emit(p_name, status, "")

	if modified:
		mp.save_registered_players(players)

	return results


## Called by user1 to stop syncing a linked profile on this device
func unlink_secondary_profile_locally(local_player_name: String) -> Dictionary:
	var mp := _get_mp()
	if mp == null or not mp.has_method("get_registered_players"):
		return {"ok": false, "error": "MultiplayerManager not available"}
	var players: Array = mp.get_registered_players()
	var found := false
	for p in players:
		if str(p.get("name", "")).to_lower() == local_player_name.to_lower():
			p["link_role"] = "none"
			p["cloud_uid"] = ""
			p.erase("pending_request_id")
			p.erase("pending_target_email")
			found = true
			break
	if found:
		mp.save_registered_players(players)
		link_request_updated.emit(local_player_name, "none", "")
		return {"ok": true}
	return {"ok": false, "error": "Player not found"}


## Called by user2 (account owner) to see who wants access to user2's stats
func fetch_incoming_link_requests() -> Array[Dictionary]:
	var auth := _get_auth()
	if auth == null or not auth.has_method("is_signed_in") or not auth.is_signed_in():
		return []
	var my_email: String = auth.get_email().strip_edges().to_lower()
	if my_email.is_empty():
		return []
	var client = _get_firestore()
	if client == null:
		return []

	var res: Dictionary = await client.run_query("link_requests", [
		{"field": "target_email_lower", "op": "EQUAL", "val": my_email}
	], [], 50, true)

	var docs: Array[Dictionary] = []
	if res.get("ok", false) and res.get("documents") is Array:
		for d in res["documents"]:
			if d is Dictionary:
				var doc_dict: Dictionary = d.duplicate()
				if not doc_dict.has("request_id") and doc_dict.has("_doc_name"):
					var parts: PackedStringArray = str(doc_dict["_doc_name"]).split("/")
					doc_dict["request_id"] = parts[parts.size() - 1]
				docs.append(doc_dict)

	docs.sort_custom(func(a, b): return int(a.get("created_at", 0)) > int(b.get("created_at", 0)))
	incoming_requests_loaded.emit(docs)
	return docs


## Called by user2 to fetch active approved delegates from profiles/{my_uid}/delegates
func fetch_active_delegates() -> Array[Dictionary]:
	var auth := _get_auth()
	if auth == null or not auth.has_method("is_signed_in") or not auth.is_signed_in():
		return []
	var my_uid: String = auth.get_uid()
	if my_uid.is_empty():
		return []
	var client = _get_firestore()
	if client == null:
		return []

	var docs: Array[Dictionary] = []
	if client.has_method("list_docs"):
		var res: Dictionary = await client.list_docs("profiles/" + my_uid + "/delegates", 50, true)
		if res.get("ok", false) and res.get("documents") is Array:
			for d in res["documents"]:
				if d is Dictionary:
					var doc_dict: Dictionary = d.duplicate()
					if not doc_dict.has("delegate_uid") and doc_dict.has("_doc_id"):
						doc_dict["delegate_uid"] = doc_dict["_doc_id"]
					docs.append(doc_dict)

	active_delegates_loaded.emit(docs)
	return docs


## Called by user2 to approve a request
func approve_link_request(request_doc: Dictionary) -> Dictionary:
	var auth := _get_auth()
	if auth == null or not auth.has_method("is_signed_in") or not auth.is_signed_in():
		return {"ok": false, "error": "Not signed in"}
	if auth.has_method("is_cloud_service_paused") and auth.is_cloud_service_paused():
		return {"ok": false, "error": "Cloud service paused", "budget_paused": true}
	if auth.has_method("is_email_verified") and not auth.is_email_verified():
		return {"ok": false, "error": "Email verification required before approving shared access", "needs_verification": true}

	var my_uid: String = auth.get_uid()
	var delegate_uid: String = str(request_doc.get("requester_uid", ""))
	if delegate_uid.is_empty():
		return {"ok": false, "error": "Invalid requester UID"}

	var req_id: String = str(request_doc.get("request_id", ""))
	if req_id.is_empty() and request_doc.has("_doc_name"):
		var parts: PackedStringArray = str(request_doc["_doc_name"]).split("/")
		req_id = parts[parts.size() - 1]
	if req_id.is_empty():
		req_id = make_request_id(delegate_uid, auth.get_email())

	var client = _get_firestore()
	if client == null:
		return {"ok": false, "error": "No Firestore client"}

	# 1. SET profiles/{uid2}/delegates/{uid1}
	var delegate_data := {
		"delegate_uid": delegate_uid,
		"delegate_name": str(request_doc.get("requester_name", "")),
		"delegate_email": str(request_doc.get("requester_email", "")),
		"request_id": req_id,
		"created_at": int(Time.get_unix_time_from_system())
	}
	var del_res: Dictionary = await client.set_doc("profiles/" + my_uid + "/delegates/" + delegate_uid, delegate_data)
	if not del_res.get("ok", false):
		return {"ok": false, "error": del_res.get("error", "Failed to grant delegate access")}

	# 2. UPDATE link_requests/{req_id}
	var req_update := {
		"status": "approved",
		"target_uid": my_uid,
		"updated_at": int(Time.get_unix_time_from_system())
	}
	var req_res: Dictionary = await client.set_doc("link_requests/" + req_id, req_update, PackedStringArray(["status", "target_uid", "updated_at"]))
	if not req_res.get("ok", false):
		print("[LinkService] Warning: Delegate created, but link_request status update returned: %s" % req_res.get("error"))

	return {"ok": true}


## Called by user2 to deny a request
func deny_link_request(request_doc: Dictionary) -> Dictionary:
	var auth := _get_auth()
	if auth == null or not auth.has_method("is_signed_in") or not auth.is_signed_in():
		return {"ok": false, "error": "Not signed in"}
	var my_uid: String = auth.get_uid()

	var req_id: String = str(request_doc.get("request_id", ""))
	if req_id.is_empty() and request_doc.has("_doc_name"):
		var parts: PackedStringArray = str(request_doc["_doc_name"]).split("/")
		req_id = parts[parts.size() - 1]

	var client = _get_firestore()
	if client == null:
		return {"ok": false, "error": "No Firestore client"}

	var req_update := {
		"status": "denied",
		"target_uid": my_uid,
		"updated_at": int(Time.get_unix_time_from_system())
	}
	return await client.set_doc("link_requests/" + req_id, req_update, PackedStringArray(["status", "target_uid", "updated_at"]))


## Called by user2 to revoke an existing delegate
func revoke_delegate(delegate_uid: String, request_id: String = "") -> Dictionary:
	var auth := _get_auth()
	if auth == null or not auth.has_method("is_signed_in") or not auth.is_signed_in():
		return {"ok": false, "error": "Not signed in"}
	var my_uid: String = auth.get_uid()
	var client = _get_firestore()
	if client == null:
		return {"ok": false, "error": "No Firestore client"}

	var del_res: Dictionary = await client.delete_doc("profiles/" + my_uid + "/delegates/" + delegate_uid)

	if not request_id.is_empty():
		var req_update := {
			"status": "revoked",
			"target_uid": my_uid,
			"updated_at": int(Time.get_unix_time_from_system())
		}
		await client.set_doc("link_requests/" + request_id, req_update, PackedStringArray(["status", "target_uid", "updated_at"]))

	return del_res


# ── INTERNAL HELPERS ─────────────────────────────────────────────────────

func _get_auth() -> Node:
	if auth_node != null and is_instance_valid(auth_node):
		return auth_node
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("CloudAuth")
	return null


func _get_firestore():
	if firestore != null:
		return firestore
	return FirestoreClientClass.new(_get_auth())


func _get_mp() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("MultiplayerManager")
	return null


func _get_cloud_sync() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("CloudSync")
	return null
