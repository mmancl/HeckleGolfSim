class_name LeaderboardService
extends RefCounted

## Service managing global leaderboards queries, client-side tie-breaking,
## metric formatting, and 10-minute caching (in-memory + user://leaderboard_cache.json).

const CACHE_TTL_SEC := 600 # 10 minutes
const DEFAULT_LIMIT := 25
const CACHE_FILE := "user://leaderboard_cache.json"

const CATEGORIES: Array[Dictionary] = [
	{
		"id": "longest_drive",
		"title": "Longest Drive",
		"field": "longest_drive_yds",
		"dir": "DESCENDING",
		"unit": "yds",
		"decimals": 1
	},
	{
		"id": "longest_putt",
		"title": "Longest Putt",
		"field": "longest_putt_ft",
		"dir": "DESCENDING",
		"unit": "ft",
		"decimals": 1
	},
	{
		"id": "lowest_score_18",
		"title": "Lowest Score (18H)",
		"field": "best_to_par_18",
		"secondary_field": "best_gross_18",
		"dir": "ASCENDING",
		"unit": "to_par",
		"decimals": 0
	},
	{
		"id": "lowest_score_9",
		"title": "Lowest Score (9H)",
		"field": "best_to_par_9",
		"secondary_field": "best_gross_9",
		"dir": "ASCENDING",
		"unit": "to_par",
		"decimals": 0
	},
	{
		"id": "most_achievements",
		"title": "Most Achievements",
		"field": "achievements_count",
		"dir": "DESCENDING",
		"unit": "count",
		"decimals": 0
	},
	{
		"id": "most_games",
		"title": "Most Games Played",
		"field": "matches_played",
		"dir": "DESCENDING",
		"unit": "games",
		"decimals": 0
	},
	{
		"id": "most_wins",
		"title": "Most Wins",
		"field": "wins",
		"dir": "DESCENDING",
		"unit": "wins",
		"decimals": 0
	}
]

const FirestoreClientClass = preload("res://Utils/Cloud/firestore_client.gd")

var firestore: RefCounted = null
var _cache: Dictionary = {}


func _init(p_firestore: RefCounted = null) -> void:
	if p_firestore != null:
		firestore = p_firestore
	_load_cache_from_disk()


static func get_categories() -> Array[Dictionary]:
	return CATEGORIES


static func get_category_def(category_id: String) -> Dictionary:
	for cat in CATEGORIES:
		if cat.get("id", "") == category_id:
			return cat
	return {}


## Fetches leaderboard entries for category_id.
## Returns {"ok": bool, "entries": Array[Dictionary], "from_cache": bool, "updated_at": int, "error": String}
func fetch_category(category_id: String, force_refresh: bool = false) -> Dictionary:
	var cat_def := get_category_def(category_id)
	if cat_def.is_empty():
		return {
			"ok": false,
			"entries": [],
			"from_cache": false,
			"updated_at": 0,
			"error": "Unknown category: %s" % category_id
		}

	var now: int = int(Time.get_unix_time_from_system())

	# 1. Check in-memory cache if not forcing refresh
	if not force_refresh and _cache.has(category_id):
		var cached_data: Dictionary = _cache[category_id]
		var updated_at: int = int(cached_data.get("updated_at", 0))
		if now - updated_at < CACHE_TTL_SEC:
			var cached_entries: Array = cached_data.get("entries", [])
			return {
				"ok": true,
				"entries": cached_entries,
				"from_cache": true,
				"updated_at": updated_at,
				"error": ""
			}

	# 2. Resolve FirestoreClient
	var client := _get_firestore_client()
	if client == null:
		if _cache.has(category_id):
			var cached_data: Dictionary = _cache[category_id]
			return {
				"ok": true,
				"entries": cached_data.get("entries", []),
				"from_cache": true,
				"updated_at": int(cached_data.get("updated_at", 0)),
				"error": "Firestore client unavailable, returning cached data"
			}
		return {
			"ok": false,
			"entries": [],
			"from_cache": false,
			"updated_at": 0,
			"error": "Firestore client unavailable"
		}

	# 3. Execute zero-auth query against public_profiles
	var field: String = cat_def.get("field", "")
	var dir: String = cat_def.get("dir", "DESCENDING")
	var order_by := [{"field": field, "dir": dir}]
	var where_filters: Array = []
	var unit: String = cat_def.get("unit", "")
	if unit in ["yds", "ft", "count", "games", "wins"]:
		where_filters.append({"field": field, "op": "GREATER_THAN", "val": 0.0})

	var resp = await client.run_query("public_profiles", where_filters, order_by, DEFAULT_LIMIT, false)
	if not resp.get("ok", false) and where_filters.size() > 0:
		resp = await client.run_query("public_profiles", [], order_by, DEFAULT_LIMIT, false)
	var is_ok: bool = resp.get("ok", false)

	if is_ok:
		var raw_docs: Array = resp.get("documents", [])
		var sorted_docs := sort_entries(cat_def, raw_docs)
		_cache[category_id] = {
			"entries": sorted_docs,
			"updated_at": now
		}
		_save_cache_to_disk()
		return {
			"ok": true,
			"entries": sorted_docs,
			"from_cache": false,
			"updated_at": now,
			"error": ""
		}
	else:
		# If query fails, fall back to cached data if available
		if _cache.has(category_id):
			var cached_data: Dictionary = _cache[category_id]
			return {
				"ok": true,
				"entries": cached_data.get("entries", []),
				"from_cache": true,
				"updated_at": int(cached_data.get("updated_at", 0)),
				"error": resp.get("error", "Offline - using cached leaderboard")
			}
		return {
			"ok": false,
			"entries": [],
			"from_cache": false,
			"updated_at": 0,
			"error": resp.get("error", "Failed to fetch leaderboard data")
		}


static func format_metric_value(category_def: Dictionary, doc: Dictionary) -> String:
	var field_name: String = category_def.get("field", "")
	if not doc.has(field_name) or doc[field_name] == null:
		return "--"

	var val = doc[field_name]
	var unit: String = category_def.get("unit", "")
	var decimals: int = category_def.get("decimals", 0)

	if unit == "to_par":
		var par_int: int = int(val)
		var par_str: String = ""
		if par_int == 0:
			par_str = "E"
		elif par_int > 0:
			par_str = "+%d" % par_int
		else:
			par_str = str(par_int)

		var sec_field: String = category_def.get("secondary_field", "")
		if not sec_field.is_empty() and doc.has(sec_field) and doc[sec_field] != null:
			var gross_val = int(doc[sec_field])
			if gross_val > 0:
				par_str += " (%d)" % gross_val
		return par_str

	if unit == "yds":
		return "%.*f yds" % [decimals, float(val)]
	elif unit == "ft":
		return "%.*f ft" % [decimals, float(val)]
	elif unit == "count" or unit == "games" or unit == "wins":
		return "%d" % int(val)

	if decimals > 0:
		return "%.*f" % [decimals, float(val)]
	return str(val)


static func sort_entries(category_def: Dictionary, entries: Array) -> Array:
	var field: String = category_def.get("field", "")
	var sec_field: String = category_def.get("secondary_field", "")
	var is_desc: bool = category_def.get("dir", "DESCENDING") == "DESCENDING"
	var unit: String = category_def.get("unit", "")
	var filter_positive: bool = unit in ["yds", "ft", "count", "games", "wins"]

	var filtered: Array = []
	for e in entries:
		if e is Dictionary:
			var val = e.get(field, null)
			if val == null:
				continue
			if filter_positive and float(val) <= 0.0:
				continue
			filtered.append(e)

	var sorted: Array = filtered.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var val_a = a.get(field, null)
		var val_b = b.get(field, null)
		if val_a == null and val_b != null:
			return false
		if val_a != null and val_b == null:
			return true
		if val_a != null and val_b != null:
			var fa: float = float(val_a)
			var fb: float = float(val_b)
			if not is_equal_approx(fa, fb):
				return fa > fb if is_desc else fa < fb

		# Primary fields are equal; apply tie breaker on secondary_field (gross score ascending)
		if not sec_field.is_empty():
			var sa = a.get(sec_field, null)
			var sb = b.get(sec_field, null)
			if sa != null and sb != null:
				var fsa: float = float(sa)
				var fsb: float = float(sb)
				if not is_equal_approx(fsa, fsb):
					return fsa < fsb

		return false
	)
	return sorted


func clear_cache(delete_disk: bool = true) -> void:
	_cache.clear()
	if delete_disk and FileAccess.file_exists(CACHE_FILE):
		DirAccess.remove_absolute(CACHE_FILE)


func _load_cache_from_disk() -> void:
	if not FileAccess.file_exists(CACHE_FILE):
		return
	var f := FileAccess.open(CACHE_FILE, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		_cache = parsed


func _save_cache_to_disk() -> void:
	var f := FileAccess.open(CACHE_FILE, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_cache))
	f.close()


func _get_firestore_client() -> RefCounted:
	if firestore != null:
		return firestore
	var auth := _resolve_cloud_auth()
	if auth != null and "firestore" in auth and auth.firestore != null:
		firestore = auth.firestore
		return firestore
	firestore = FirestoreClientClass.new()
	return firestore


func _resolve_cloud_auth() -> Node:
	var loop = Engine.get_main_loop()
	if loop is SceneTree and loop.root != null:
		return loop.root.get_node_or_null("CloudAuth")
	return null
