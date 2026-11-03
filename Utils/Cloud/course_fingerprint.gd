class_name CourseFingerprint
extends RefCounted

## Course identity, canonical key generation, and SHA-1 geometry fingerprinting.
## Protects multiplayer determinism by ensuring all clients play on identical hole geometry (Hole H12).

static var _slug_regex: RegEx = null


## Extracts hole integer number from hole id (e.g. "Hole 1" -> 1).
static func get_hole_number_from_id(hole_id: String, fallback_idx: int = 0) -> int:
	if hole_id.is_empty():
		return fallback_idx + 1
	var clean := hole_id.replace("Hole", "").strip_edges()
	if clean.is_valid_int():
		return int(clean)
	return fallback_idx + 1


## Normalizes course titles to clean alphanumeric slugs with single underscores (e.g. "augusta_national_golf_club").
static func slugify(text: String) -> String:
	if _slug_regex == null:
		_slug_regex = RegEx.new()
		_slug_regex.compile("[^a-z0-9]+")
	var lower := text.to_lower()
	var replaced := _slug_regex.sub(lower, "_", true)
	var trimmed := replaced.strip_edges().trim_prefix("_").trim_suffix("_")
	return trimmed if not trimmed.is_empty() else "course"


## Calculates distance in meters between two lat/lon coordinates using the Haversine formula.
static func haversine_distance_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var r := 6371000.0 # Earth's radius in meters
	var phi1 := deg_to_rad(lat1)
	var phi2 := deg_to_rad(lat2)
	var delta_phi := deg_to_rad(lat2 - lat1)
	var delta_lambda := deg_to_rad(lon2 - lon1)
	var a := sin(delta_phi / 2.0) * sin(delta_phi / 2.0) + cos(phi1) * cos(phi2) * sin(delta_lambda / 2.0) * sin(delta_lambda / 2.0)
	var c := 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
	return r * c


## Computes deterministic 40-character SHA-1 hex fingerprint from sorted Hole Info.
## Coordinates are snapped to 0.5m to avoid cross-platform floating-point string formatting noise.
static func compute_fingerprint(hole_info: Dictionary) -> String:
	if hole_info.is_empty():
		return "".sha1_text()

	var hole_ids: Array = hole_info.keys()
	hole_ids.sort_custom(func(a, b):
		var na := get_hole_number_from_id(str(a))
		var nb := get_hole_number_from_id(str(b))
		if na == nb:
			return str(a) < str(b)
		return na < nb
	)

	var hole_strings: Array[String] = []
	for h_id in hole_ids:
		var h_data = hole_info[h_id]
		if not (h_data is Dictionary):
			continue
		var par: int = int(h_data.get("Par", h_data.get("par", 4)))
		var h_loc = h_data.get("Hole Location", h_data.get("hole_location", [0.0, 0.0]))
		var gx := 0.0
		var gy := 0.0
		var gz := 0.0
		if h_loc is Array and h_loc.size() > 0:
			gx = float(h_loc[0])
			if h_loc.size() == 2:
				gy = 0.0
				gz = float(h_loc[1])
			elif h_loc.size() >= 3:
				gy = float(h_loc[1])
				gz = float(h_loc[2])

		var hole_str := "%s:P%d:G%.1f,%.1f,%.1f" % [
			str(h_id),
			par,
			snapped(gx, 0.5),
			snapped(gy, 0.5),
			snapped(gz, 0.5)
		]

		var tee_boxes = h_data.get("Tee Boxes", h_data.get("tee_boxes", {}))
		if tee_boxes is Dictionary:
			var tee_keys: Array = tee_boxes.keys()
			tee_keys.sort()
			for t_name in tee_keys:
				var t_pos = tee_boxes[t_name]
				var tx := 0.0
				var ty := 0.0
				var tz := 0.0
				if t_pos is Array and t_pos.size() > 0:
					tx = float(t_pos[0])
					if t_pos.size() == 2:
						ty = 0.0
						tz = float(t_pos[1])
					elif t_pos.size() >= 3:
						ty = float(t_pos[1])
						tz = float(t_pos[2])
				hole_str += ":%s:%.1f,%.1f,%.1f" % [
					str(t_name),
					snapped(tx, 0.5),
					snapped(ty, 0.5),
					snapped(tz, 0.5)
				]

		hole_strings.append(hole_str)

	var joined := ";".join(hole_strings)
	return joined.sha1_text()


## Inspects a course config JSON file and returns full course metadata, canonical key, and fingerprint.
static func inspect_course_config(config_path: String) -> Dictionary:
	if not FileAccess.file_exists(config_path):
		return {"ok": false, "error": "Config file not found: %s" % config_path}

	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "Unable to open config file: %s" % config_path}

	var content := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(content)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "Invalid course JSON in: %s" % config_path}

	var title: String = str(parsed.get("Title", parsed.get("title", "")))
	if title.is_empty():
		title = config_path.get_base_dir().get_file()

	var lat: float = float(parsed.get("Latitude", parsed.get("latitude", parsed.get("lat", 0.0))))
	var lon: float = float(parsed.get("Longitude", parsed.get("longitude", parsed.get("lon", 0.0))))
	var location: String = str(parsed.get("Location", parsed.get("location", "")))
	var raw_is_custom: bool = bool(parsed.get("is_custom", parsed.get("IsCustom", false)))
	var is_custom: bool = raw_is_custom or (lat == 0.0 and lon == 0.0) or config_path.contains("custom_")
	var raw_is_cached: bool = bool(parsed.get("is_cached", parsed.get("IsCached", false)))
	var is_cached: bool = raw_is_cached or location.to_lower().contains("cached") or config_path.contains("Cached")

	var hole_info: Dictionary = parsed.get("Hole Info", parsed.get("hole_info", {}))
	var fingerprint := compute_fingerprint(hole_info)
	var canonical_key := "%s@%.4f,%.4f" % [slugify(title), lat, lon]

	var hole_ids: Array[String] = []
	for k in hole_info.keys():
		hole_ids.append(str(k))
	hole_ids.sort_custom(func(a, b):
		var na := get_hole_number_from_id(a)
		var nb := get_hole_number_from_id(b)
		if na == nb:
			return a < b
		return na < nb
	)

	var scene_path: String = str(parsed.get("scene_path", parsed.get("ScenePath", "course.tscn")))
	if not scene_path.begins_with("res://") and not scene_path.begins_with("user://"):
		scene_path = config_path.get_base_dir().path_join(scene_path)

	return {
		"ok": true,
		"title": title,
		"key": canonical_key,
		"lat": lat,
		"lon": lon,
		"location": location,
		"is_custom": is_custom,
		"is_cached": is_cached,
		"fingerprint": fingerprint,
		"hole_ids": hole_ids,
		"scene_path": scene_path,
		"config_path": config_path
	}


## Scans user://courses (and built-in course paths) for a course matching course_key or nearby lat/lon.
static func find_installed_course(course_key: String, lat: float, lon: float, title: String) -> Dictionary:
	var search_dirs := [
		"user://courses",
		"res://Courses/UserCourses",
		"res://Courses/Cached"
	]

	var norm_target_title := slugify(title)

	for base_dir in search_dirs:
		if not DirAccess.dir_exists_absolute(base_dir):
			continue
		var subdirs := DirAccess.get_directories_at(base_dir)
		for subdir in subdirs:
			if subdir.begins_with("."):
				continue
			var course_dir: String = str(base_dir).path_join(str(subdir))
			var cfg_path: String = course_dir.path_join("course.json")
			if not FileAccess.file_exists(cfg_path):
				continue

			var info := inspect_course_config(cfg_path)
			if not info.get("ok", false):
				continue

			# 1. Exact canonical key match
			if not course_key.is_empty() and info.get("key", "") == course_key:
				return info

			# 2. Normalized title match + coordinate proximity (within 200m or both 0)
			var cur_title_slug: String = slugify(info.get("title", ""))
			if cur_title_slug == norm_target_title:
				var info_lat: float = float(info.get("lat", 0.0))
				var info_lon: float = float(info.get("lon", 0.0))
				if (info_lat != 0.0 or info_lon != 0.0) and (lat != 0.0 or lon != 0.0):
					var dist := haversine_distance_meters(info_lat, info_lon, lat, lon)
					if dist <= 200.0:
						return info
				elif info_lat == 0.0 and info_lon == 0.0 and lat == 0.0 and lon == 0.0:
					return info

	return {}
