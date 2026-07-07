extends Node

signal active_player_changed(player: Dictionary)
signal hole_completed(scores: Array)
signal game_over(scores: Array)

var players: Array[Dictionary] = []
var active_player_index: int = 0
var current_hole_index: int = 0
var hole_ids: Array = []
var hole_info: Dictionary = {}
var par_scores: Dictionary = {} # par per hole
var practice_mode_active: bool = false

# History and Save State
var current_match_id: String = ""
var course_title: String = "Course"
var scene_path: String = ""
var config_path: String = ""
var current_club: String = "Dr"
var is_finished: bool = false
var unix_time: float = 0.0
var formatted_date: String = ""

func _ready() -> void:
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").connect("club_selected", Callable(self, "_on_club_selected"))

func _on_club_selected(club_name: String) -> void:
	current_club = club_name

func setup_game(player_configs: Array, config_data: Dictionary, p_scene_path: String = "", p_config_path: String = "") -> void:
	players.clear()
	for config in player_configs:
		var p := {
			"name": config.get("name", "Player"),
			"tee": config.get("tee", "Blue"),
			"strokes": 0,
			"total_strokes": 0,
			"last_hole_score": 0,
			"position": Vector3.ZERO,
			"holed_out": false,
			"shot_history": [],
			"hole_scores": {},
			"last_shot_penalty": 0,
			"active": true,
			"shot_stats": {}
		}
		players.append(p)
		
	course_title = config_data.get("Title", "")
	if course_title.is_empty():
		var course_info_node = config_data.get("Course Info", {})
		course_title = course_info_node.get("Title", "Course")
		
	hole_info = config_data.get("Hole Info", {})
	hole_ids = hole_info.keys()
	hole_ids.sort()
	current_hole_index = 0
	
	scene_path = p_scene_path
	config_path = p_config_path
	is_finished = false
	unix_time = Time.get_unix_time_from_system()
	formatted_date = Time.get_datetime_string_from_system(false, true)
	current_match_id = "match_" + str(int(unix_time)) + "_" + str(randi() % 1000)
	
	print("[MultiplayerManager] Game setup complete. Players: %d, Holes: %d" % [players.size(), hole_ids.size()])
	save_current_match()

func start_hole() -> void:
	if current_hole_index >= hole_ids.size():
		is_finished = true
		save_current_match()
		emit_signal("game_over", players)
		return
		
	var hole_id: String = hole_ids[current_hole_index]
	var current_hole = hole_info[hole_id]
	var tee_boxes = current_hole.get("Tee Boxes", {})
	
	# Reset states for current hole
	for p in players:
		p["strokes"] = 0
		p["holed_out"] = not p.get("active", true)
		p["last_shot_penalty"] = 0
		
		# Set player position to their chosen tee box
		var tee_color: String = p["tee"]
		var tee_pos = tee_boxes.get(tee_color, [0.0, 0.0])
		# Node coordinates in 3D: X and Z represent ground plane coordinates
		p["position"] = Vector3(tee_pos[0], 0.02, tee_pos[1])
		p["shot_history"].clear()

	# Determine honors (Tee-off order)
	if current_hole_index == 0:
		# First hole: Keep active players first, then inactive players
		players.sort_custom(func(a, b):
			var a_active = a.get("active", true)
			var b_active = b.get("active", true)
			if a_active != b_active:
				return a_active
			return false
		)
	else:
		# Honors: Lowest score on previous hole tees off first. If tied, keep order. Inactive players go to the bottom.
		players.sort_custom(func(a, b):
			var a_active = a.get("active", true)
			var b_active = b.get("active", true)
			if a_active != b_active:
				return a_active
			if a["last_hole_score"] != b["last_hole_score"]:
				return a["last_hole_score"] < b["last_hole_score"]
			return false
		)
		
	# Find first active player
	active_player_index = 0
	for i in range(players.size()):
		if players[i].get("active", true):
			active_player_index = i
			break
			
	emit_signal("active_player_changed", get_active_player())
	print("[MultiplayerManager] Starting Hole: %s. Active Player: %s" % [hole_id, get_active_player()["name"]])
	save_current_match()

func get_active_player() -> Dictionary:
	if players.is_empty():
		return {}
	return players[active_player_index]

func record_shot(final_position: Vector3, raw_shot_data: Dictionary = {}) -> void:
	var active_player = get_active_player()
	active_player["strokes"] += 1
	active_player["total_strokes"] += 1
	active_player["position"] = final_position
	active_player["shot_history"].append(final_position)

	if not hole_ids.is_empty():
		var hole_id: String = hole_ids[current_hole_index]
		active_player["hole_scores"][hole_id] = active_player["strokes"]
		
		# Record the shot stats for this hole
		if not active_player.has("shot_stats"):
			active_player["shot_stats"] = {}
		if not active_player["shot_stats"].has(hole_id):
			active_player["shot_stats"][hole_id] = []
			
		var carry_val = raw_shot_data.get("CarryDistance", 0.0) as float
		var total_val = raw_shot_data.get("TotalDistance", 0.0) as float
		var apex_val = raw_shot_data.get("Apex", 0.0) as float
		var side_val = raw_shot_data.get("SideDistance", 0.0) as float
		
		var back_spin = raw_shot_data.get("BackSpin", 0.0) as float
		var side_spin = raw_shot_data.get("SideSpin", 0.0) as float
		var total_spin = raw_shot_data.get("TotalSpin", 0.0) as float
		var spin_axis = raw_shot_data.get("SpinAxis", 0.0) as float
		
		if total_spin == 0.0 and (back_spin != 0.0 or side_spin != 0.0):
			total_spin = sqrt(back_spin * back_spin + side_spin * side_spin)
		if spin_axis == 0.0 and (back_spin != 0.0 or side_spin != 0.0):
			spin_axis = rad_to_deg(atan2(side_spin, back_spin))
		if total_spin != 0.0 and spin_axis != 0.0:
			if back_spin == 0.0:
				back_spin = total_spin * cos(deg_to_rad(spin_axis))
			if side_spin == 0.0:
				side_spin = total_spin * sin(deg_to_rad(spin_axis))
				
		var shot_num = active_player["strokes"]
		var stat_entry = {
			"shot_num": shot_num,
			"club": current_club,
			"speed_mph": raw_shot_data.get("Speed", 0.0) as float,
			"vla_deg": raw_shot_data.get("VLA", 0.0) as float,
			"hla_deg": raw_shot_data.get("HLA", 0.0) as float,
			"back_spin_rpm": back_spin,
			"side_spin_rpm": side_spin,
			"total_spin_rpm": total_spin,
			"spin_axis_deg": spin_axis,
			"carry_yds": carry_val * 1.09361,
			"total_yds": total_val * 1.09361,
			"apex_ft": apex_val * 3.28084,
			"offline_yds": side_val * 1.09361
		}
		active_player["shot_stats"][hole_id].append(stat_entry)

	# Check for holing out
	if not practice_mode_active:
		var current_hole = hole_info[hole_ids[current_hole_index]]
		var hole_loc = current_hole.get("Hole Location", [0.0, 0.0])
		var target_pin = Vector3(hole_loc[0], final_position.y, hole_loc[1])
		
		var dist_to_pin = final_position.distance_to(target_pin)
		
		# 6-inch diameter cup has a radius of 3 inches (~0.0762m). If ball stops in it, player holed out.
		if dist_to_pin < 0.0762:
			active_player["holed_out"] = true
			print("[MultiplayerManager] Player %s holed out! Score: %d" % [active_player["name"], active_player["strokes"]])
		else:
			# Check gimme ranges if enabled
			var g1_enabled = GlobalSettings.range_settings.gimme_range_1_enabled.value
			var g1_dist_yards = GlobalSettings.range_settings.gimme_range_1_distance.value
			
			var g2_enabled = GlobalSettings.range_settings.gimme_range_2_enabled.value
			var g2_dist_yards = GlobalSettings.range_settings.gimme_range_2_distance.value
			
			var dist_to_pin_yards = dist_to_pin * 1.09361 # meters to yards
			
			if g1_enabled and g2_enabled:
				if g1_dist_yards < g2_dist_yards:
					if dist_to_pin_yards <= g1_dist_yards:
						_apply_gimme(active_player, 1, hole_ids[current_hole_index])
					elif dist_to_pin_yards <= g2_dist_yards:
						_apply_gimme(active_player, 2, hole_ids[current_hole_index])
				else:
					if dist_to_pin_yards <= g2_dist_yards:
						_apply_gimme(active_player, 2, hole_ids[current_hole_index])
					elif dist_to_pin_yards <= g1_dist_yards:
						_apply_gimme(active_player, 1, hole_ids[current_hole_index])
			elif g1_enabled:
				if dist_to_pin_yards <= g1_dist_yards:
					_apply_gimme(active_player, 1, hole_ids[current_hole_index])
			elif g2_enabled:
				if dist_to_pin_yards <= g2_dist_yards:
					_apply_gimme(active_player, 2, hole_ids[current_hole_index])
					
	save_current_match()

func select_next_player() -> void:
	var remaining_players = players.filter(func(p): return p.get("active", true) and not p["holed_out"])
	
	if remaining_players.is_empty():
		# All players have holed out. Hole complete!
		for p in players:
			if p.get("active", true):
				p["last_hole_score"] = p["strokes"]
				if not hole_ids.is_empty():
					var hole_id = hole_ids[current_hole_index]
					p["hole_scores"][hole_id] = p["strokes"]
			else:
				p["last_hole_score"] = 0
				if not hole_ids.is_empty():
					var hole_id = hole_ids[current_hole_index]
					p["hole_scores"][hole_id] = null
		
		save_current_match()
		emit_signal("hole_completed", players)
		return
		
	# Check if all players have taken their first shot (tee shot)
	var any_no_shot = players.any(func(p): return p.get("active", true) and p["strokes"] == 0)
	
	if any_no_shot:
		# If someone hasn't teed off yet, they tee off in sequential order
		for i in range(players.size()):
			if players[i].get("active", true) and players[i]["strokes"] == 0:
				active_player_index = i
				emit_signal("active_player_changed", get_active_player())
				return
				
	var just_hit_player = get_active_player()
	
	# If everyone has teed off, standard golf etiquette: "Away player hits first"
	var hole_id: String = hole_ids[current_hole_index]
	var current_hole = hole_info[hole_id]
	var hole_loc = current_hole.get("Hole Location", [0.0, 0.0])
	var target_pin = Vector3(hole_loc[0], 0.0, hole_loc[1])
	
	var furthest_player = null
	var max_dist := -1.0
	
	for p in remaining_players:
		var flat_pos := Vector3(p["position"].x, 0.0, p["position"].z)
		var dist = flat_pos.distance_to(target_pin)
		if dist > max_dist:
			max_dist = dist
			furthest_player = p
			
	var next_player = furthest_player
	if furthest_player != null and not just_hit_player.is_empty() and just_hit_player != furthest_player:
		var custom_enabled = GlobalSettings.range_settings.custom_next_player.value
		if custom_enabled and (just_hit_player in remaining_players):
			var just_hit_flat := Vector3(just_hit_player["position"].x, 0.0, just_hit_player["position"].z)
			var furthest_flat := Vector3(furthest_player["position"].x, 0.0, furthest_player["position"].z)
			var dist_between_yards = just_hit_flat.distance_to(furthest_flat) * 1.09361
			if dist_between_yards <= 10.0:
				next_player = just_hit_player
				print("[MultiplayerManager] Custom turn order: %s just hit and is within 10 yards (%.2f yds) of furthest player %s. Keeping %s active." % [just_hit_player["name"], dist_between_yards, furthest_player["name"], just_hit_player["name"]])
			
	if next_player != null:
		active_player_index = players.find(next_player)
		emit_signal("active_player_changed", get_active_player())
		print("[MultiplayerManager] Next to play: %s" % get_active_player()["name"])

func advance_hole() -> void:
	current_hole_index += 1
	start_hole()

func _apply_gimme(active_player, extra_strokes: int, hole_id: String) -> void:
	active_player["strokes"] += extra_strokes
	active_player["total_strokes"] += extra_strokes
	active_player["hole_scores"][hole_id] = active_player["strokes"]
	active_player["holed_out"] = true
	print("[MultiplayerManager] Player %s holed out via +%d stroke(s) gimme! Score: %d" % [active_player["name"], extra_strokes, active_player["strokes"]])
	save_current_match()

func add_new_player(player_name: String, tee_color: String) -> void:
	var p := {
		"name": player_name,
		"tee": tee_color,
		"strokes": 0,
		"total_strokes": 0,
		"last_hole_score": 0,
		"position": Vector3.ZERO,
		"holed_out": false,
		"shot_history": [],
		"hole_scores": {},
		"last_shot_penalty": 0,
		"active": true,
		"shot_stats": {}
	}
	
	# Mark all previous holes as "-" (null)
	for i in range(current_hole_index):
		var h_id = hole_ids[i]
		p["hole_scores"][h_id] = null
		
	# Setup position to current tee box if a hole is active
	if current_hole_index < hole_ids.size():
		var hole_id: String = hole_ids[current_hole_index]
		var current_hole = hole_info[hole_id]
		var tee_boxes = current_hole.get("Tee Boxes", {})
		var tee_pos = tee_boxes.get(tee_color, [0.0, 0.0])
		p["position"] = Vector3(tee_pos[0], 0.02, tee_pos[1])
		
	players.append(p)
	print("[MultiplayerManager] Added new player mid-game: %s" % player_name)
	save_current_match()

func toggle_player_active(idx: int, active: bool) -> void:
	if idx < 0 or idx >= players.size():
		return
		
	var player = players[idx]
	if player.get("active", true) == active:
		return
		
	player["active"] = active
	print("[MultiplayerManager] Player %s active status changed to %s" % [player["name"], active])
	
	if not active:
		# Mark current hole score as null
		if not hole_ids.is_empty():
			var hole_id = hole_ids[current_hole_index]
			player["hole_scores"][hole_id] = null
		player["holed_out"] = true
		
		# If they were the active player, select next
		if active_player_index == idx:
			select_next_player()
	else:
		# Mark all completed holes as "-" (null) if they don't have a score
		for i in range(current_hole_index):
			var h_id = hole_ids[i]
			if not player["hole_scores"].has(h_id) or player["hole_scores"][h_id] == null:
				player["hole_scores"][h_id] = null
				
		player["holed_out"] = false
		player["strokes"] = 0
		player["last_shot_penalty"] = 0
		player["shot_history"].clear()
		
		# Set position to current tee box
		if current_hole_index < hole_ids.size():
			var hole_id: String = hole_ids[current_hole_index]
			var current_hole = hole_info[hole_id]
			var tee_boxes = current_hole.get("Tee Boxes", {})
			# FIXED tee_color bug: use player["tee"] instead of undefined tee_color
			var tee_pos = tee_boxes.get(player["tee"], [0.0, 0.0])
			player["position"] = Vector3(tee_pos[0], 0.02, tee_pos[1])
			
		# If current active player is empty/inactive, select this one
		var current_active = get_active_player()
		if current_active.is_empty() or not current_active.get("active", true):
			active_player_index = idx
			emit_signal("active_player_changed", get_active_player())
			
	save_current_match()

# --- Saving & Resuming Match State ---

func save_current_match() -> void:
	if current_match_id.is_empty():
		return
		
	var save_dir = "user://match_history"
	if not DirAccess.dir_exists_absolute(save_dir):
		var err = DirAccess.make_dir_recursive_absolute(save_dir)
		if err != OK:
			push_error("[MultiplayerManager] Failed to create match history directory")
			return
			
	var file_path = save_dir.path_join(current_match_id + ".json")
	var f = FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		push_error("[MultiplayerManager] Failed to write save file: " + file_path)
		return
		
	var data = {
		"match_id": current_match_id,
		"course_title": course_title,
		"scene_path": scene_path,
		"config_path": config_path,
		"current_hole_index": current_hole_index,
		"active_player_index": active_player_index,
		"practice_mode_active": practice_mode_active,
		"is_finished": is_finished,
		"unix_time": unix_time,
		"formatted_date": formatted_date,
		"players": _serialize_players(players)
	}
	
	f.store_string(JSON.stringify(data, "\t", false))
	f.close()
	print("[MultiplayerManager] Match saved successfully to: " + file_path)
	_enforce_history_limit()

func resume_match(match_data: Dictionary) -> void:
	current_match_id = match_data.get("match_id", "")
	course_title = match_data.get("course_title", "")
	scene_path = match_data.get("scene_path", "")
	config_path = match_data.get("config_path", "")
	current_hole_index = match_data.get("current_hole_index", 0)
	active_player_index = match_data.get("active_player_index", 0)
	practice_mode_active = match_data.get("practice_mode_active", false)
	is_finished = match_data.get("is_finished", false)
	unix_time = match_data.get("unix_time", 0.0)
	formatted_date = match_data.get("formatted_date", "")
	
	# Load config so we have hole info, par scores, etc.
	var config_file = FileAccess.open(config_path, FileAccess.READ)
	if config_file != null:
		var text = config_file.get_as_text()
		var json_parser = JSON.new()
		if text.strip_edges() != "" and json_parser.parse(text) == OK:
			var parsed = json_parser.data
			if typeof(parsed) == TYPE_DICTIONARY:
				hole_info = parsed.get("Hole Info", {})
				hole_ids = hole_info.keys()
				hole_ids.sort()
			
	players = _deserialize_players(match_data.get("players", []))
	
	print("[MultiplayerManager] Resuming game on course: %s, hole: %d" % [course_title, current_hole_index])
	
	# Transition scene to course
	SceneManager.load_course(scene_path, config_path)

func _serialize_players(players_array: Array[Dictionary]) -> Array:
	var serialized = []
	for p in players_array:
		var dup = p.duplicate(true)
		# Convert Vector3 position
		if dup.has("position") and typeof(dup["position"]) == TYPE_VECTOR3:
			var pos: Vector3 = dup["position"]
			dup["position"] = [pos.x, pos.y, pos.z]
		# Convert Vector3 in shot_history
		if dup.has("shot_history"):
			var history_serialized = []
			for pos in dup["shot_history"]:
				if typeof(pos) == TYPE_VECTOR3:
					history_serialized.append([pos.x, pos.y, pos.z])
				else:
					history_serialized.append(pos)
			dup["shot_history"] = history_serialized
		
		# Convert Vector3 in shot_stats positions
		if dup.has("shot_stats"):
			var stats = dup["shot_stats"]
			if typeof(stats) == TYPE_DICTIONARY:
				for hole_key in stats:
					var shots_list = stats[hole_key]
					if typeof(shots_list) == TYPE_ARRAY:
						for shot in shots_list:
							if typeof(shot) == TYPE_DICTIONARY and shot.has("position") and typeof(shot["position"]) == TYPE_VECTOR3:
								var pos: Vector3 = shot["position"]
								shot["position"] = [pos.x, pos.y, pos.z]
			elif typeof(stats) == TYPE_ARRAY:
				for shot in stats:
					if typeof(shot) == TYPE_DICTIONARY and shot.has("position") and typeof(shot["position"]) == TYPE_VECTOR3:
						var pos: Vector3 = shot["position"]
						shot["position"] = [pos.x, pos.y, pos.z]
					
		serialized.append(dup)
	return serialized

func _deserialize_players(serialized_array: Array) -> Array[Dictionary]:
	var deserialized: Array[Dictionary] = []
	for p in serialized_array:
		var dup: Dictionary = p.duplicate(true)
		# Convert position back to Vector3
		if dup.has("position") and typeof(dup["position"]) == TYPE_ARRAY:
			var arr = dup["position"]
			if arr.size() == 3:
				dup["position"] = Vector3(arr[0], arr[1], arr[2])
			else:
				dup["position"] = Vector3.ZERO
		# Convert shot_history back to Vector3
		if dup.has("shot_history") and typeof(dup["shot_history"]) == TYPE_ARRAY:
			var history_deserialized = []
			for item in dup["shot_history"]:
				if typeof(item) == TYPE_ARRAY and item.size() == 3:
					history_deserialized.append(Vector3(item[0], item[1], item[2]))
				else:
					history_deserialized.append(item)
			dup["shot_history"] = history_deserialized
			
		# Convert shot_stats position back to Vector3
		if dup.has("shot_stats"):
			var stats = dup["shot_stats"]
			if typeof(stats) == TYPE_DICTIONARY:
				for hole_key in stats:
					var shots_list = stats[hole_key]
					if typeof(shots_list) == TYPE_ARRAY:
						for shot in shots_list:
							if typeof(shot) == TYPE_DICTIONARY and shot.has("position") and typeof(shot["position"]) == TYPE_ARRAY:
								var arr = shot["position"]
								if arr.size() == 3:
									shot["position"] = Vector3(arr[0], arr[1], arr[2])
			elif typeof(stats) == TYPE_ARRAY:
				for shot in stats:
					if typeof(shot) == TYPE_DICTIONARY and shot.has("position") and typeof(shot["position"]) == TYPE_ARRAY:
						var arr = shot["position"]
						if arr.size() == 3:
							shot["position"] = Vector3(arr[0], arr[1], arr[2])
		deserialized.append(dup)
	return deserialized

func _enforce_history_limit() -> void:
	var dir_path = "user://match_history"
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	var dir = DirAccess.open(dir_path)
	if dir == null:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	var matches_files = []
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path = dir_path.path_join(file_name)
			var f = FileAccess.open(full_path, FileAccess.READ)
			if f != null:
				var text = f.get_as_text()
				var json_parser = JSON.new()
				if text.strip_edges() != "" and json_parser.parse(text) == OK:
					var json = json_parser.data
					if typeof(json) == TYPE_DICTIONARY:
						var u_time = json.get("unix_time", 0.0)
						matches_files.append({
							"file_name": file_name,
							"unix_time": u_time,
							"full_path": full_path
						})
		file_name = dir.get_next()
	dir.list_dir_end()
	
	# Sort matches by unix_time ascending (oldest first)
	matches_files.sort_custom(func(a, b): return a["unix_time"] < b["unix_time"])
	
	# If we have more than 10, delete the oldest
	while matches_files.size() > 10:
		var oldest = matches_files.pop_front()
		DirAccess.remove_absolute(oldest["full_path"])
		print("[MultiplayerManager] Removed oldest match history file: %s" % oldest["file_name"])
