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
var selected_course_length: String = "Full 18"
var game_mode: String = "Standard" # Standard, Scramble, 2v2 Scramble, Skins
var team_assignments: Dictionary = {} # Team name -> Array of player names

# Game mode specific runtime state
var scramble_best_pos: Vector3 = Vector3.ZERO
var team_best_pos: Dictionary = {} # team_name -> Vector3
var skins_won: Dictionary = {} # player_name -> int
var carryover_skins: int = 0
var carryover_eligible_players: Array = [] # player names eligible for carryover
var hole_skins_results: Dictionary = {} # hole_id -> Dictionary

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

var player_colors: Array[Color] = [
	Color(0.24, 0.46, 0.72), # Blue
	Color(0.85, 0.35, 0.25), # Coral/Red
	Color(0.25, 0.65, 0.35), # Green
	Color(0.85, 0.65, 0.15), # Yellow/Gold
	Color(0.65, 0.25, 0.85), # Purple
	Color(0.15, 0.75, 0.75), # Cyan
	Color(0.85, 0.45, 0.75), # Pink
	Color(0.95, 0.55, 0.15)  # Orange
]

func get_player_color(player: Dictionary) -> Color:
	if player.has("color"):
		return player["color"]
	for i in range(players.size()):
		if players[i]["name"] == player.get("name", ""):
			return player_colors[i % player_colors.size()]
	return player_colors[0]

func setup_game(player_configs: Array, config_data: Dictionary, p_scene_path: String = "", p_config_path: String = "", course_length: String = "Full 18", p_game_mode: String = "Standard", p_team_assignments: Dictionary = {}) -> void:
	game_mode = p_game_mode
	team_assignments = p_team_assignments.duplicate(true)
	skins_won.clear()
	carryover_skins = 0
	carryover_eligible_players.clear()
	hole_skins_results.clear()
	scramble_best_pos = Vector3.ZERO
	team_best_pos.clear()

	# Default 2v2 Scramble teams if not provided
	if game_mode == "2v2 Scramble" and team_assignments.is_empty():
		var t1 = []
		var t2 = []
		for i in range(player_configs.size()):
			var p_name = player_configs[i].get("name", "Player " + str(i + 1))
			if i < 2:
				t1.append(p_name)
			else:
				t2.append(p_name)
		team_assignments["Team 1"] = t1
		team_assignments["Team 2"] = t2

	players.clear()
	for i in range(player_configs.size()):
		var config = player_configs[i]
		var p_name = config.get("name", "Player")
		var p_team = config.get("team", "")
		if p_team.is_empty() and game_mode == "2v2 Scramble":
			for t_name in team_assignments.keys():
				if p_name in team_assignments[t_name]:
					p_team = t_name
					break
			if p_team.is_empty():
				p_team = "Team 1" if i < 2 else "Team 2"

		var p := {
			"name": p_name,
			"tee": config.get("tee", "Blue"),
			"team": p_team,
			"strokes": 0,
			"total_strokes": 0,
			"last_hole_score": 0,
			"position": Vector3.ZERO,
			"holed_out": false,
			"shot_history": [],
			"hole_scores": {},
			"last_shot_penalty": 0,
			"active": true,
			"shot_stats": {},
			"shot_reduction": 0.0,
			"lie_type": "teebox",
			"color": player_colors[i % player_colors.size()],
			"mulligan_history": {},
			"last_shot_tracer_points": [],
			"last_aim_target_pos": Vector3.ZERO,
			"last_aim_yaw_offset_deg": 0.0
		}
		players.append(p)
		register_player(p_name)
		skins_won[p_name] = 0
		
	course_title = config_data.get("Title", "")
	if course_title.is_empty():
		var course_info_node = config_data.get("Course Info", {})
		course_title = course_info_node.get("Title", "Course")
		
	hole_info = config_data.get("Hole Info", {})
	var all_hole_ids = hole_info.keys()
	all_hole_ids.sort_custom(func(a, b):
		var num_a = int(a.replace("Hole ", ""))
		var num_b = int(b.replace("Hole ", ""))
		return num_a < num_b
	)
	
	selected_course_length = course_length
	hole_ids = []
	if selected_course_length == "Front 9":
		for i in range(min(9, all_hole_ids.size())):
			hole_ids.append(all_hole_ids[i])
	elif selected_course_length == "Back 9":
		if all_hole_ids.size() >= 10:
			for i in range(9, min(18, all_hole_ids.size())):
				hole_ids.append(all_hole_ids[i])
		else:
			hole_ids = all_hole_ids.duplicate()
	else:
		hole_ids = all_hole_ids.duplicate()
		
	current_hole_index = 0
	
	scene_path = p_scene_path
	config_path = p_config_path
	is_finished = false
	unix_time = Time.get_unix_time_from_system()
	formatted_date = Time.get_datetime_string_from_system(false, true)
	current_match_id = "match_" + str(int(unix_time)) + "_" + str(randi() % 1000)
	
	print("[MultiplayerManager] Game setup complete. Mode: %s, Players: %d, Holes: %d" % [game_mode, players.size(), hole_ids.size()])
	save_current_match()

func start_hole() -> void:
	if current_hole_index >= hole_ids.size():
		is_finished = true
		save_current_match()
		
		# Evaluate round achievements for all active players
		if has_node("/root/AchievementManager") and not practice_mode_active:
			var ach_mgr = get_node("/root/AchievementManager")
			var min_strokes = 99999
			for p in players:
				if p.get("active", true) and p.get("total_strokes", 0) > 0:
					if p["total_strokes"] < min_strokes:
						min_strokes = p["total_strokes"]
			for p in players:
				if p.get("active", true) and p.get("total_strokes", 0) > 0:
					var p_name = p.get("name", "")
					var is_winner = (p["total_strokes"] == min_strokes)
					var p_stats = calculate_player_stats(p_name)
					var total_wins = p_stats.get("wins", 0)
					ach_mgr.check_round_achievements(p_name, p["total_strokes"], hole_ids.size(), is_winner, total_wins)

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
		p["shot_reduction"] = 0.0
		p["lie_type"] = "teebox"
		p["lies_in_hole"] = []
		p["last_putt_dist_yards"] = 0.0
		
		# Set player position to their chosen tee box
		var tee_color: String = p["tee"]
		var tee_pos = tee_boxes.get(tee_color, [0.0, 0.0])
		var is_driver = current_club.to_lower() in ["dr", "driver", "1w"]
		var offset_y = 0.059435 if is_driver else 0.021335
		p["position"] = Vector3(tee_pos[0], offset_y, tee_pos[1])
		p["shot_history"].clear()
		p["last_aim_target_pos"] = Vector3.ZERO
		p["last_aim_yaw_offset_deg"] = 0.0

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
	var prev_lie = active_player.get("lie_type", "")
	active_player["strokes"] += 1
	active_player["total_strokes"] += 1
	active_player["position"] = final_position
	active_player["shot_history"].append(final_position)

	# Record the tracer points of the shot that just ended
	var tracer_pts = []
	var player_node = get_tree().root.find_child("Player", true, false)
	var last_aim_target = Vector3.ZERO
	var last_aim_yaw = 0.0
	if player_node != null:
		var current_tracer = player_node.get("current_tracer")
		if is_instance_valid(current_tracer) and "points" in current_tracer:
			tracer_pts = current_tracer.points.duplicate()
		if player_node.get("_last_aim_target_pos") != null:
			last_aim_target = player_node.get("_last_aim_target_pos")
		if player_node.get("_last_aim_yaw_offset_deg") != null:
			last_aim_yaw = player_node.get("_last_aim_yaw_offset_deg")
	active_player["last_shot_tracer_points"] = tracer_pts
	active_player["last_aim_target_pos"] = last_aim_target
	active_player["last_aim_yaw_offset_deg"] = last_aim_yaw

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

		# Also record the shot globally
		var p_name = active_player.get("name", "")
		if not p_name.is_empty() and not current_club.is_empty():
			record_global_shot(p_name, current_club, raw_shot_data)

	# Track lies and shot achievements
	if not active_player.has("lies_in_hole"):
		active_player["lies_in_hole"] = []
	active_player["lies_in_hole"].append(active_player.get("lie_type", ""))
	
	if prev_lie == "green":
		var current_hole_info = hole_info.get(hole_ids[current_hole_index], {})
		var hole_l = current_hole_info.get("Hole Location", [0.0, 0.0])
		var pin_pos = Vector3(hole_l[0], 0.0, hole_l[1])
		var prev_pos = active_player.get("shot_history", [])
		if prev_pos.size() >= 2:
			active_player["last_putt_dist_yards"] = prev_pos[-2].distance_to(pin_pos) * 1.09361

	if has_node("/root/AchievementManager") and not practice_mode_active:
		var total_yds = (raw_shot_data.get("TotalDistance", 0.0) as float) * 1.09361
		get_node("/root/AchievementManager").check_shot_achievements(active_player.get("name", ""), current_club, total_yds)

	# Check for holing out/clap triggers
	if not practice_mode_active:
		var current_hole = hole_info[hole_ids[current_hole_index]]
		var hole_loc = current_hole.get("Hole Location", [0.0, 0.0])
		var target_pin = Vector3(hole_loc[0], final_position.y, hole_loc[1])
		var par = current_hole.get("Par", 4)
		
		var dist_to_pin = final_position.distance_to(target_pin)
		
		# Cup has a radius of 0.12m. If ball stops in it, player holed out.
		if dist_to_pin < 0.12:
			active_player["holed_out"] = true
			print("[MultiplayerManager] Player %s holed out! Score: %d" % [active_player["name"], active_player["strokes"]])
			if active_player["strokes"] <= par:
				GlobalSettings.play_golf_clap()
			if has_node("/root/AnnouncerEngine"):
				get_node("/root/AnnouncerEngine").call("AnnounceHoleScore", active_player["name"], active_player["strokes"], par)
			if has_node("/root/AchievementManager"):
				var putt_dist = active_player.get("last_putt_dist_yards", 0.0)
				get_node("/root/AchievementManager").check_hole_achievements(active_player.get("name", ""), par, active_player["strokes"], active_player.get("lies_in_hole", []), putt_dist)
		else:
			# Play clap if drive lands in fairway, or ball lands on green in par-1 or less strokes
			var landed_in_fairway = (par >= 4 and active_player["strokes"] == 1 and active_player.get("lie_type", "") == "fairway")
			var landed_on_green = (prev_lie != "green" and active_player.get("lie_type", "") == "green" and active_player["strokes"] <= par - 1)
			if landed_in_fairway or landed_on_green:
				GlobalSettings.play_golf_clap()

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

	# Mode-specific shot handling (Scramble / 2v2 Scramble)
	if game_mode == "Scramble" and not hole_ids.is_empty():
		_handle_scramble_shot(active_player)
	elif game_mode == "2v2 Scramble" and not hole_ids.is_empty():
		_handle_2v2_scramble_shot(active_player)
					
	save_current_match()

func _handle_scramble_shot(active_player: Dictionary) -> void:
	var active_ps = players.filter(func(p): return p.get("active", true))
	if active_ps.is_empty():
		return
		
	var hole_id = hole_ids[current_hole_index]
	var current_hole = hole_info[hole_id]
	var hole_loc = current_hole.get("Hole Location", [0.0, 0.0])
	var target_pin = Vector3(hole_loc[0], 0.0, hole_loc[1])
	
	if active_player["holed_out"]:
		var group_score = active_player["strokes"]
		for p in active_ps:
			p["holed_out"] = true
			p["strokes"] = group_score
			p["hole_scores"][hole_id] = group_score
		print("[MultiplayerManager] Scramble group holed out! Score: %d" % group_score)
		return

	var current_stroke = active_player["strokes"]
	var all_took_stroke = active_ps.all(func(p): return p["strokes"] >= current_stroke or p["holed_out"])
	
	if all_took_stroke:
		var closest_pos = active_player["position"]
		var min_dist = 99999.0
		var best_p_name = active_player["name"]
		
		for p in active_ps:
			if not p["holed_out"] and p["strokes"] == current_stroke:
				var flat_pos = Vector3(p["position"].x, 0.0, p["position"].z)
				var dist = flat_pos.distance_to(target_pin)
				if dist < min_dist:
					min_dist = dist
					closest_pos = p["position"]
					best_p_name = p["name"]
					
		scramble_best_pos = closest_pos
		for p in active_ps:
			if not p["holed_out"]:
				p["position"] = scramble_best_pos
		print("[MultiplayerManager] Scramble best shot for stroke %d selected at %s (Player: %s)." % [current_stroke, str(scramble_best_pos), best_p_name])

func _handle_2v2_scramble_shot(active_player: Dictionary) -> void:
	var team_name = active_player.get("team", "Team 1")
	var team_ps = players.filter(func(p): return p.get("active", true) and p.get("team", "") == team_name)
	if team_ps.is_empty():
		return
		
	var hole_id = hole_ids[current_hole_index]
	var current_hole = hole_info[hole_id]
	var hole_loc = current_hole.get("Hole Location", [0.0, 0.0])
	var target_pin = Vector3(hole_loc[0], 0.0, hole_loc[1])
	
	if active_player["holed_out"]:
		var team_score = active_player["strokes"]
		for p in team_ps:
			p["holed_out"] = true
			p["strokes"] = team_score
			p["hole_scores"][hole_id] = team_score
		print("[MultiplayerManager] 2v2 Scramble %s holed out! Score: %d" % [team_name, team_score])
		return

	var current_stroke = active_player["strokes"]
	var all_team_took_stroke = team_ps.all(func(p): return p["strokes"] >= current_stroke or p["holed_out"])
	
	if all_team_took_stroke:
		var closest_pos = active_player["position"]
		var min_dist = 99999.0
		var best_p_name = active_player["name"]
		
		for p in team_ps:
			if not p["holed_out"] and p["strokes"] == current_stroke:
				var flat_pos = Vector3(p["position"].x, 0.0, p["position"].z)
				var dist = flat_pos.distance_to(target_pin)
				if dist < min_dist:
					min_dist = dist
					closest_pos = p["position"]
					best_p_name = p["name"]
					
		team_best_pos[team_name] = closest_pos
		for p in team_ps:
			if not p["holed_out"]:
				p["position"] = closest_pos
		print("[MultiplayerManager] 2v2 Scramble best shot for %s (stroke %d) selected at %s (Player: %s)." % [team_name, current_stroke, str(closest_pos), best_p_name])

func select_next_player() -> void:
	var remaining_players = players.filter(func(p): return p.get("active", true) and not p["holed_out"])
	
	if remaining_players.is_empty():
		# All players have holed out. Hole complete!
		var hole_id = hole_ids[current_hole_index] if not hole_ids.is_empty() else ""
		for p in players:
			if p.get("active", true):
				p["last_hole_score"] = p["strokes"]
				if not hole_id.is_empty():
					p["hole_scores"][hole_id] = p["strokes"]
			else:
				p["last_hole_score"] = 0
				if not hole_id.is_empty():
					p["hole_scores"][hole_id] = null
		
		if game_mode == "Skins" and not hole_id.is_empty():
			_evaluate_skins_for_hole(hole_id)
		
		save_current_match()
		emit_signal("hole_completed", players)
		return
		
	# Check if all players have taken their first shot (tee shot)
	var any_no_shot = players.any(func(p): return p.get("active", true) and p["strokes"] == 0)
	
	if any_no_shot:
		for i in range(players.size()):
			if players[i].get("active", true) and players[i]["strokes"] == 0:
				active_player_index = i
				emit_signal("active_player_changed", get_active_player())
				return
				
	# Away player hits first (filtered by lowest strokes taken so far on this hole)
	var min_strokes = 9999
	for p in remaining_players:
		if p["strokes"] < min_strokes:
			min_strokes = p["strokes"]
			
	var min_stroke_players = remaining_players.filter(func(p): return p["strokes"] == min_strokes)
	
	var hole_id: String = hole_ids[current_hole_index]
	var current_hole = hole_info[hole_id]
	var hole_loc = current_hole.get("Hole Location", [0.0, 0.0])
	var target_pin = Vector3(hole_loc[0], 0.0, hole_loc[1])
	
	var just_hit_player = get_active_player()
	var furthest_player = null
	var max_dist := -1.0
	
	for p in min_stroke_players:
		var flat_pos := Vector3(p["position"].x, 0.0, p["position"].z)
		var dist = flat_pos.distance_to(target_pin)
		if dist > max_dist:
			max_dist = dist
			furthest_player = p
			
	var next_player = furthest_player
	if furthest_player != null and not just_hit_player.is_empty() and just_hit_player != furthest_player:
		var custom_enabled = GlobalSettings.range_settings.custom_next_player.value
		if custom_enabled and (just_hit_player in min_stroke_players):
			var just_hit_flat := Vector3(just_hit_player["position"].x, 0.0, just_hit_player["position"].z)
			var furthest_flat := Vector3(furthest_player["position"].x, 0.0, furthest_player["position"].z)
			var dist_between_yards = just_hit_flat.distance_to(furthest_flat) * 1.09361
			if dist_between_yards <= 10.0:
				next_player = just_hit_player
				print("[MultiplayerManager] Custom turn order: %s active." % just_hit_player["name"])
			
	if next_player != null:
		active_player_index = players.find(next_player)
		emit_signal("active_player_changed", get_active_player())
		print("[MultiplayerManager] Next to play: %s" % get_active_player()["name"])

func _evaluate_skins_for_hole(hole_id: String) -> void:
	var active_ps = players.filter(func(p): return p.get("active", true))
	if active_ps.is_empty():
		return
		
	var min_strokes = 9999
	for p in active_ps:
		var s = p["strokes"]
		if s < min_strokes:
			min_strokes = s
			
	var low_players = active_ps.filter(func(p): return p["strokes"] == min_strokes)
	
	if low_players.size() == 1:
		var winner = low_players[0]
		var w_name = winner["name"]
		var skins_to_award = 1
		
		if carryover_skins > 0:
			if carryover_eligible_players.is_empty() or w_name in carryover_eligible_players:
				skins_to_award += carryover_skins
				carryover_skins = 0
				carryover_eligible_players.clear()
			else:
				var eligible_ps = active_ps.filter(func(p): return p["name"] in carryover_eligible_players)
				if not eligible_ps.is_empty():
					var elig_min = 9999
					for ep in eligible_ps:
						if ep["strokes"] < elig_min:
							elig_min = ep["strokes"]
					var elig_low = eligible_ps.filter(func(p): return p["strokes"] == elig_min)
					if elig_low.size() == 1:
						var c_winner = elig_low[0]["name"]
						skins_won[c_winner] = skins_won.get(c_winner, 0) + carryover_skins
						print("[Skins] %s won carryover pot of %d skins from prior tied hole!" % [c_winner, carryover_skins])
						carryover_skins = 0
						carryover_eligible_players.clear()
						
		skins_won[w_name] = skins_won.get(w_name, 0) + skins_to_award
		hole_skins_results[hole_id] = {
			"winner": w_name,
			"skins_awarded": skins_to_award,
			"carryover": carryover_skins
		}
		print("[Skins] Hole %s winner: %s (+%d skin(s))" % [hole_id, w_name, skins_to_award])
	else:
		carryover_skins += 1
		
		if not carryover_eligible_players.is_empty():
			var eligible_ps = active_ps.filter(func(p): return p["name"] in carryover_eligible_players)
			if not eligible_ps.is_empty():
				var elig_min = 9999
				for ep in eligible_ps:
					if ep["strokes"] < elig_min:
						elig_min = ep["strokes"]
				var elig_low = eligible_ps.filter(func(p): return p["strokes"] == elig_min)
				if elig_low.size() == 1:
					var c_winner = elig_low[0]["name"]
					var prev_pot = carryover_skins - 1
					if prev_pot > 0:
						skins_won[c_winner] = skins_won.get(c_winner, 0) + prev_pot
						print("[Skins] %s won prior carryover pot of %d skins!" % [c_winner, prev_pot])
						carryover_skins = 1
						
		carryover_eligible_players.clear()
		for lp in low_players:
			carryover_eligible_players.append(lp["name"])
			
		hole_skins_results[hole_id] = {
			"winner": "Tie",
			"skins_awarded": 0,
			"carryover": carryover_skins
		}
		print("[Skins] Hole %s tied. Carryover pot now: %d skin(s)" % [hole_id, carryover_skins])

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
	
	var par = 4
	if hole_info.has(hole_id):
		par = hole_info[hole_id].get("Par", 4)
	if active_player["strokes"] <= par:
		GlobalSettings.play_golf_clap()
		
	if has_node("/root/AnnouncerEngine"):
		get_node("/root/AnnouncerEngine").call("AnnounceHoleScore", active_player["name"], active_player["strokes"], par)
		
	if has_node("/root/AchievementManager") and not practice_mode_active:
		var putt_dist = active_player.get("last_putt_dist_yards", 0.0)
		get_node("/root/AchievementManager").check_hole_achievements(active_player.get("name", ""), par, active_player["strokes"], active_player.get("lies_in_hole", []), putt_dist)


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
		"shot_stats": {},
		"shot_reduction": 0.0,
		"lie_type": "teebox",
		"mulligan_history": {},
		"last_shot_tracer_points": [],
		"last_aim_target_pos": Vector3.ZERO,
		"last_aim_yaw_offset_deg": 0.0
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
		var is_driver = current_club.to_lower() in ["dr", "driver", "1w"]
		var offset_y = 0.059435 if is_driver else 0.021335
		p["position"] = Vector3(tee_pos[0], offset_y, tee_pos[1])
		
	players.append(p)
	register_player(player_name)
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
		if current_hole_index < hole_ids.size():
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
		player["last_aim_target_pos"] = Vector3.ZERO
		player["last_aim_yaw_offset_deg"] = 0.0
		
		# Set position to current tee box
		if current_hole_index < hole_ids.size():
			var hole_id: String = hole_ids[current_hole_index]
			var current_hole = hole_info[hole_id]
			var tee_boxes = current_hole.get("Tee Boxes", {})
			# FIXED tee_color bug: use player["tee"] instead of undefined tee_color
			var tee_pos = tee_boxes.get(player["tee"], [0.0, 0.0])
			var is_driver = current_club.to_lower() in ["dr", "driver", "1w"]
			var offset_y = 0.059435 if is_driver else 0.021335
			player["position"] = Vector3(tee_pos[0], offset_y, tee_pos[1])
			
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
		"players": _serialize_players(players),
		"hole_pars": _get_hole_pars(),
		"selected_course_length": selected_course_length,
		"game_mode": game_mode,
		"team_assignments": team_assignments,
		"skins_won": skins_won,
		"carryover_skins": carryover_skins,
		"carryover_eligible_players": carryover_eligible_players,
		"hole_skins_results": hole_skins_results
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
	selected_course_length = match_data.get("selected_course_length", "Full 18")
	game_mode = match_data.get("game_mode", "Standard")
	team_assignments = match_data.get("team_assignments", {})
	skins_won = match_data.get("skins_won", {})
	carryover_skins = match_data.get("carryover_skins", 0)
	carryover_eligible_players = match_data.get("carryover_eligible_players", [])
	hole_skins_results = match_data.get("hole_skins_results", {})
	
	# Load config so we have hole info, par scores, etc.
	var config_file = FileAccess.open(config_path, FileAccess.READ)
	if config_file != null:
		var text = config_file.get_as_text()
		var json_parser = JSON.new()
		if text.strip_edges() != "" and json_parser.parse(text) == OK:
			var parsed = json_parser.data
			if typeof(parsed) == TYPE_DICTIONARY:
				hole_info = parsed.get("Hole Info", {})
				var all_hole_ids = hole_info.keys()
				all_hole_ids.sort_custom(func(a, b):
					var num_a = int(a.replace("Hole ", ""))
					var num_b = int(b.replace("Hole ", ""))
					return num_a < num_b
				)
				
				# Filter hole_ids
				hole_ids = []
				if selected_course_length == "Front 9":
					for i in range(min(9, all_hole_ids.size())):
						hole_ids.append(all_hole_ids[i])
				elif selected_course_length == "Back 9":
					if all_hole_ids.size() >= 10:
						for i in range(9, min(18, all_hole_ids.size())):
							hole_ids.append(all_hole_ids[i])
					else:
						hole_ids = all_hole_ids.duplicate()
				else:
					hole_ids = all_hole_ids.duplicate()
			
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
						
		# Convert Vector3 in last_shot_tracer_points
		if dup.has("last_shot_tracer_points") and typeof(dup["last_shot_tracer_points"]) == TYPE_ARRAY:
			var pts_serialized = []
			for pt in dup["last_shot_tracer_points"]:
				if typeof(pt) == TYPE_VECTOR3:
					pts_serialized.append([pt.x, pt.y, pt.z])
				else:
					pts_serialized.append(pt)
			dup["last_shot_tracer_points"] = pts_serialized
			
		# Convert last_aim_target_pos
		if dup.has("last_aim_target_pos") and typeof(dup["last_aim_target_pos"]) == TYPE_VECTOR3:
			var pos: Vector3 = dup["last_aim_target_pos"]
			dup["last_aim_target_pos"] = [pos.x, pos.y, pos.z]
			
		# Convert Vector3 in mulligan_history
		if dup.has("mulligan_history") and typeof(dup["mulligan_history"]) == TYPE_DICTIONARY:
			var mulligan_hist_serialized = {}
			for hole_key in dup["mulligan_history"]:
				var shots_list = dup["mulligan_history"][hole_key]
				if typeof(shots_list) == TYPE_ARRAY:
					var serialized_list = []
					for entry in shots_list:
						if typeof(entry) == TYPE_DICTIONARY:
							var entry_dup = entry.duplicate(true)
							if entry_dup.has("start_pos") and typeof(entry_dup["start_pos"]) == TYPE_VECTOR3:
								var pos: Vector3 = entry_dup["start_pos"]
								entry_dup["start_pos"] = [pos.x, pos.y, pos.z]
							if entry_dup.has("end_pos") and typeof(entry_dup["end_pos"]) == TYPE_VECTOR3:
								var pos: Vector3 = entry_dup["end_pos"]
								entry_dup["end_pos"] = [pos.x, pos.y, pos.z]
							if entry_dup.has("aim_target_pos") and typeof(entry_dup["aim_target_pos"]) == TYPE_VECTOR3:
								var pos: Vector3 = entry_dup["aim_target_pos"]
								entry_dup["aim_target_pos"] = [pos.x, pos.y, pos.z]
							if entry_dup.has("tracer_points") and typeof(entry_dup["tracer_points"]) == TYPE_ARRAY:
								var pts_serialized = []
								for pt in entry_dup["tracer_points"]:
									if typeof(pt) == TYPE_VECTOR3:
										pts_serialized.append([pt.x, pt.y, pt.z])
									else:
										pts_serialized.append(pt)
								entry_dup["tracer_points"] = pts_serialized
							serialized_list.append(entry_dup)
					mulligan_hist_serialized[hole_key] = serialized_list
			dup["mulligan_history"] = mulligan_hist_serialized
					
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
							
		# Convert Vector3 in last_shot_tracer_points back
		if dup.has("last_shot_tracer_points") and typeof(dup["last_shot_tracer_points"]) == TYPE_ARRAY:
			var pts_deserialized = []
			for pt in dup["last_shot_tracer_points"]:
				if typeof(pt) == TYPE_ARRAY and pt.size() == 3:
					pts_deserialized.append(Vector3(pt[0], pt[1], pt[2]))
				else:
					pts_deserialized.append(pt)
			dup["last_shot_tracer_points"] = pts_deserialized
			
		# Convert last_aim_target_pos back
		if dup.has("last_aim_target_pos") and typeof(dup["last_aim_target_pos"]) == TYPE_ARRAY:
			var arr = dup["last_aim_target_pos"]
			if arr.size() == 3:
				dup["last_aim_target_pos"] = Vector3(arr[0], arr[1], arr[2])
			else:
				dup["last_aim_target_pos"] = Vector3.ZERO
				
		# Convert Vector3 in mulligan_history back
		if dup.has("mulligan_history") and typeof(dup["mulligan_history"]) == TYPE_DICTIONARY:
			var mulligan_hist_deserialized = {}
			for hole_key in dup["mulligan_history"]:
				var shots_list = dup["mulligan_history"][hole_key]
				if typeof(shots_list) == TYPE_ARRAY:
					var deserialized_list = []
					for entry in shots_list:
						if typeof(entry) == TYPE_DICTIONARY:
							var entry_dup = entry.duplicate(true)
							if entry_dup.has("start_pos") and typeof(entry_dup["start_pos"]) == TYPE_ARRAY:
								var arr = entry_dup["start_pos"]
								if arr.size() == 3:
									entry_dup["start_pos"] = Vector3(arr[0], arr[1], arr[2])
							if entry_dup.has("end_pos") and typeof(entry_dup["end_pos"]) == TYPE_ARRAY:
								var arr = entry_dup["end_pos"]
								if arr.size() == 3:
									entry_dup["end_pos"] = Vector3(arr[0], arr[1], arr[2])
							if entry_dup.has("aim_target_pos") and typeof(entry_dup["aim_target_pos"]) == TYPE_ARRAY:
								var arr = entry_dup["aim_target_pos"]
								if arr.size() == 3:
									entry_dup["aim_target_pos"] = Vector3(arr[0], arr[1], arr[2])
							if entry_dup.has("tracer_points") and typeof(entry_dup["tracer_points"]) == TYPE_ARRAY:
								var pts_deserialized = []
								for pt in entry_dup["tracer_points"]:
									if typeof(pt) == TYPE_ARRAY and pt.size() == 3:
										pts_deserialized.append(Vector3(pt[0], pt[1], pt[2]))
									else:
										pts_deserialized.append(pt)
								entry_dup["tracer_points"] = pts_deserialized
							deserialized_list.append(entry_dup)
					mulligan_hist_deserialized[hole_key] = deserialized_list
			dup["mulligan_history"] = mulligan_hist_deserialized
			
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


func _get_hole_pars() -> Dictionary:
	var pars = {}
	for h_id in hole_ids:
		var hole = hole_info.get(h_id, {})
		pars[h_id] = hole.get("Par", 4)
	return pars


# --- Persistent Player Registry ---
const REGISTRY_PATH = "user://players_registry.json"

func get_registered_players() -> Array[Dictionary]:
	if not FileAccess.file_exists(REGISTRY_PATH):
		return []
	var file = FileAccess.open(REGISTRY_PATH, FileAccess.READ)
	if file == null:
		return []
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK and typeof(json.data) == TYPE_ARRAY:
		var result: Array[Dictionary] = []
		for item in json.data:
			if typeof(item) == TYPE_DICTIONARY:
				result.append(item)
		return result
	return []

func save_registered_players(players_list: Array) -> void:
	var file = FileAccess.open(REGISTRY_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(players_list, "\t"))

func register_player(player_name: String) -> void:
	if player_name.is_empty():
		return
	var registered = get_registered_players()
	for p in registered:
		if p.get("name", "").to_lower() == player_name.to_lower():
			return # Already exists
	
	var new_player = {
		"name": player_name,
		"created_at": Time.get_unix_time_from_system()
	}
	registered.append(new_player)
	save_registered_players(registered)
	print("[MultiplayerManager] Registered new player: ", player_name)

func delete_player_permanently(player_name: String) -> void:
	# Remove from registry
	var registered = get_registered_players()
	var new_list = []
	for p in registered:
		if p.get("name", "").to_lower() != player_name.to_lower():
			new_list.append(p)
	save_registered_players(new_list)
	
	# Remove from club stats
	var stats = load_global_club_stats()
	if stats.has(player_name):
		stats.erase(player_name)
		save_global_club_stats(stats)
		
	clear_player_swing_issues(player_name)
	print("[MultiplayerManager] Permanently deleted player: ", player_name)

func clear_player_ball_history(player_name: String) -> void:
	# Clear entry from club stats
	var stats = load_global_club_stats()
	if stats.has(player_name):
		stats[player_name] = {}
		save_global_club_stats(stats)
	print("[MultiplayerManager] Cleared ball history for player: ", player_name)


# --- Global Club Stats Persistence ---

func load_global_club_stats() -> Dictionary:
	var path = "user://player_club_stats.json"
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK:
		if typeof(json.data) == TYPE_DICTIONARY:
			return json.data
	return {}

func save_global_club_stats(stats: Dictionary) -> void:
	var path = "user://player_club_stats.json"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(stats, "\t"))

func record_global_shot(player_name: String, club_name: String, raw_shot: Dictionary) -> void:
	if player_name.is_empty() or club_name.is_empty():
		return
	var stats = load_global_club_stats()
	if not stats.has(player_name):
		stats[player_name] = {}
	if not stats[player_name].has(club_name):
		stats[player_name][club_name] = []
		
	var entry = {
		"CarryDistance": raw_shot.get("CarryDistance", 0.0),
		"Speed": raw_shot.get("Speed", 0.0),
		"TotalSpin": raw_shot.get("TotalSpin", 0.0),
		"SideDistance": raw_shot.get("SideDistance", 0.0),
		"TargetDistance": raw_shot.get("TargetDistance", 0.0),
		"TotalDistance": raw_shot.get("TotalDistance", 0.0)
	}
	stats[player_name][club_name].append(entry)
	save_global_club_stats(stats)

func remove_last_global_shot(player_name: String, club_name: String) -> void:
	if player_name.is_empty() or club_name.is_empty():
		return
	var stats = load_global_club_stats()
	if stats.has(player_name) and stats[player_name].has(club_name):
		if not stats[player_name][club_name].is_empty():
			stats[player_name][club_name].pop_back()
			save_global_club_stats(stats)

func calculate_player_stats(player_name: String) -> Dictionary:
	var stats = {
		"matches_played": 0,
		"wins": 0,
		"losses": 0,
		"ties": 0,
		"single_player_completed": 0,
		"avg_to_par": 0.0,
		"avg_to_par_valid": false,
		"best_courses": {},
		"longest_drive": 0.0
	}
	
	var dir_path = "user://match_history"
	if DirAccess.dir_exists_absolute(dir_path):
		var dir = DirAccess.open(dir_path)
		if dir != null:
			dir.list_dir_begin()
			var file_name = dir.get_next()
			var total_diff_sum = 0.0
			var par_diff_matches_count = 0
			
			while file_name != "":
				if not dir.current_is_dir() and file_name.ends_with(".json"):
					var full_path = dir_path.path_join(file_name)
					var f = FileAccess.open(full_path, FileAccess.READ)
					if f != null:
						var json_text = f.get_as_text()
						var json_parser = JSON.new()
						if json_text.strip_edges() != "" and json_parser.parse(json_text) == OK:
							var json = json_parser.data
							if typeof(json) == TYPE_DICTIONARY and json.get("is_finished", false):
								var is_practice = json.get("practice_mode_active", false)
								if not is_practice:
									var players_list = json.get("players", [])
									var target_player = null
									var active_players = []
									for p in players_list:
										if typeof(p) == TYPE_DICTIONARY and p.get("active", true):
											active_players.append(p)
											if p.get("name", "").to_lower() == player_name.to_lower():
												target_player = p
												
									if target_player != null:
										stats["matches_played"] += 1
										if active_players.size() > 1:
											var min_score = 99999
											var min_players = []
											for p in active_players:
												var score = int(p.get("total_strokes", 0))
												if score < min_score:
													min_score = score
													min_players = [p]
												elif score == min_score:
													min_players.append(p)
													
											var my_score = int(target_player.get("total_strokes", 0))
											if my_score == min_score:
												if min_players.size() == 1:
													stats["wins"] += 1
												else:
													stats["ties"] += 1
											else:
												stats["losses"] += 1
										else:
											stats["single_player_completed"] += 1
											
										var hole_pars = json.get("hole_pars", {})
										if typeof(hole_pars) != TYPE_DICTIONARY or hole_pars.is_empty():
											hole_pars = {}
											var config_p = json.get("config_path", "")
											if not config_p.is_empty() and FileAccess.file_exists(config_p):
												var cfg_file = FileAccess.open(config_p, FileAccess.READ)
												if cfg_file != null:
													var cfg_json = JSON.parse_string(cfg_file.get_as_text())
													if typeof(cfg_json) == TYPE_DICTIONARY:
														var h_info = cfg_json.get("Hole Info", {})
														for h_id in h_info:
															hole_pars[h_id] = h_info[h_id].get("Par", 4)
															
										var player_strokes = 0
										var par_sum = 0
										var hole_scores = target_player.get("hole_scores", {})
										if typeof(hole_scores) == TYPE_DICTIONARY:
											for h_id in hole_scores:
												var score = hole_scores[h_id]
												if score != null:
													player_strokes += int(score)
													par_sum += int(hole_pars.get(h_id, 4))
													
										if par_sum > 0:
											var diff = player_strokes - par_sum
											total_diff_sum += diff
											par_diff_matches_count += 1
											
											var course_t = json.get("course_title", "Course")
											var diff_sign = "+" if diff > 0 else ""
											var diff_str = "%s%d" % [diff_sign, diff] if diff != 0 else "E"
											
											if not stats["best_courses"].has(course_t) or diff < stats["best_courses"][course_t]["diff"]:
												stats["best_courses"][course_t] = {
													"diff": diff,
													"str": "%s (%d holes)" % [diff_str, hole_scores.size()]
												}
						
				file_name = dir.get_next()
			dir.list_dir_end()
			
			if par_diff_matches_count > 0:
				stats["avg_to_par"] = total_diff_sum / par_diff_matches_count
				stats["avg_to_par_valid"] = true
				
	var global_stats = load_global_club_stats()
	var player_club_stats = global_stats.get(player_name, {})
	var max_drive := 0.0
	if player_club_stats.has("Dr"):
		var shots = player_club_stats["Dr"]
		if typeof(shots) == TYPE_ARRAY:
			for shot in shots:
				if typeof(shot) == TYPE_DICTIONARY:
					var dist = float(shot.get("TotalDistance", 0.0)) * 1.09361
					if dist > max_drive:
						max_drive = dist
	stats["longest_drive"] = max_drive
	
	return stats


# --- Video Swing Analysis Recommendation Tracking ---

const SWING_ISSUES_PATH = "user://player_swing_issues.json"
const MONTH_NAMES = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

static func get_month_display_name(month_key: String) -> String:
	var parts = month_key.split("-")
	if parts.size() == 2:
		var m_idx = int(parts[1])
		if m_idx >= 1 and m_idx <= 12:
			return "%s %s" % [MONTH_NAMES[m_idx], parts[0]]
	return month_key

func load_player_swing_issues() -> Dictionary:
	if not FileAccess.file_exists(SWING_ISSUES_PATH):
		return {}
	var file = FileAccess.open(SWING_ISSUES_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK and typeof(json.data) == TYPE_DICTIONARY:
		return json.data
	return {}

func save_player_swing_issues(data: Dictionary) -> void:
	var file = FileAccess.open(SWING_ISSUES_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))

func record_player_swing_issues(player_name: String, recommendations: Array) -> void:
	if player_name.is_empty() or recommendations.is_empty():
		return
	
	var date_dict = Time.get_date_dict_from_system()
	var current_month = "%04d-%02d" % [date_dict.year, date_dict.month]
	
	var all_data = load_player_swing_issues()
	if not all_data.has(player_name):
		all_data[player_name] = {
			"all_time": {},
			"monthly": {}
		}
	
	var p_data = all_data[player_name]
	if not p_data.has("all_time") or typeof(p_data["all_time"]) != TYPE_DICTIONARY:
		p_data["all_time"] = {}
	if not p_data.has("monthly") or typeof(p_data["monthly"]) != TYPE_DICTIONARY:
		p_data["monthly"] = {}
	if not p_data["monthly"].has(current_month) or typeof(p_data["monthly"][current_month]) != TYPE_DICTIONARY:
		p_data["monthly"][current_month] = {}

	var recorded_any := false
	for rec in recommendations:
		if typeof(rec) != TYPE_DICTIONARY:
			continue
		var severity = str(rec.get("severity", ""))
		# Skip LOW severity (pro-grade maintenance notes)
		if severity == "LOW":
			continue
			
		var issue = str(rec.get("issue_type", rec.get("category", "General Flaw")))
		
		var cur_at = int(p_data["all_time"].get(issue, 0))
		p_data["all_time"][issue] = cur_at + 1
		
		var cur_mo = int(p_data["monthly"][current_month].get(issue, 0))
		p_data["monthly"][current_month][issue] = cur_mo + 1
		recorded_any = true
		
	if recorded_any:
		save_player_swing_issues(all_data)
		print("[MultiplayerManager] Recorded swing recommendations for %s (%s)" % [player_name, current_month])

func get_player_swing_issues(player_name: String) -> Dictionary:
	var all_data = load_player_swing_issues()
	return all_data.get(player_name, { "all_time": {}, "monthly": {} })

func clear_player_swing_issues(player_name: String) -> void:
	var all_data = load_player_swing_issues()
	if all_data.has(player_name):
		all_data.erase(player_name)
		save_player_swing_issues(all_data)
		print("[MultiplayerManager] Cleared swing issues for player: ", player_name)

func format_player_swing_issues_summary(player_name: String) -> String:
	var p_issues = get_player_swing_issues(player_name)
	var all_time: Dictionary = p_issues.get("all_time", {})
	var monthly: Dictionary = p_issues.get("monthly", {})
	
	if all_time.is_empty():
		return "VIDEO SWING ANALYSIS & RECOMMENDATION TOTALS:\nNo video swing recommendations recorded yet.\n"
		
	var date_dict = Time.get_date_dict_from_system()
	var current_month_key = "%04d-%02d" % [date_dict.year, date_dict.month]
	var current_month_name = get_month_display_name(current_month_key)
	
	var out = "VIDEO SWING ANALYSIS & RECOMMENDATION TOTALS:\n"
	out += "=============================================\n"
	
	var cur_month_issues: Dictionary = monthly.get(current_month_key, {})
	out += "This Month (%s):\n" % current_month_name
	if cur_month_issues.is_empty():
		out += "  (No swing recommendations recorded this month)\n"
	else:
		for issue_name in cur_month_issues:
			out += "  • %s: %d\n" % [issue_name, int(cur_month_issues[issue_name])]
			
	out += "\nAll-Time Running Totals:\n"
	for issue_name in all_time:
		out += "  • %s: %d\n" % [issue_name, int(all_time[issue_name])]
		
	return out + "\n"
