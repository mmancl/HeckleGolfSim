extends Node

signal achievement_unlocked(player_name: String, achievement: Dictionary)

const SAVE_PATH = "user://player_achievements.json"

var achievements_db: Dictionary = {
	"first_par": {
		"id": "first_par",
		"title": "First Par",
		"description": "Complete a hole at equal to par",
		"badge_path": "res://assets/images/achievements/badge_first_par.svg",
		"category": "Hole",
		"rarity": "Common"
	},
	"first_birdie": {
		"id": "first_birdie",
		"title": "First Birdie",
		"description": "Complete a hole at 1-under par",
		"badge_path": "res://assets/images/achievements/badge_first_birdie.svg",
		"category": "Hole",
		"rarity": "Common"
	},
	"first_eagle": {
		"id": "first_eagle",
		"title": "First Eagle",
		"description": "Complete a hole at 2-under par",
		"badge_path": "res://assets/images/achievements/badge_first_eagle.svg",
		"category": "Hole",
		"rarity": "Rare"
	},
	"first_albatross": {
		"id": "first_albatross",
		"title": "Double Eagle",
		"description": "Complete a hole at 3-under par",
		"badge_path": "res://assets/images/achievements/badge_first_albatross.svg",
		"category": "Hole",
		"rarity": "Legendary"
	},
	"hole_in_one": {
		"id": "hole_in_one",
		"title": "Ace Master",
		"description": "Make a hole-in-one on any hole!",
		"badge_path": "res://assets/images/achievements/badge_hole_in_one.svg",
		"category": "Hole",
		"rarity": "Legendary"
	},
	"broke_100_18": {
		"id": "broke_100_18",
		"title": "Century Breaker",
		"description": "Shoot under 100 in an 18-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_100.svg",
		"category": "18-Hole",
		"rarity": "Common"
	},
	"broke_90_18": {
		"id": "broke_90_18",
		"title": "Sub-90 Club",
		"description": "Shoot under 90 in an 18-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_90.svg",
		"category": "18-Hole",
		"rarity": "Rare"
	},
	"broke_80_18": {
		"id": "broke_80_18",
		"title": "Single Digit Pace",
		"description": "Shoot under 80 in an 18-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_80.svg",
		"category": "18-Hole",
		"rarity": "Epic"
	},
	"broke_70_18": {
		"id": "broke_70_18",
		"title": "Scratch Golfer",
		"description": "Shoot under 70 in an 18-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_70.svg",
		"category": "18-Hole",
		"rarity": "Epic"
	},
	"broke_60_18": {
		"id": "broke_60_18",
		"title": "Legendary 59",
		"description": "Shoot under 60 in an 18-hole round!",
		"badge_path": "res://assets/images/achievements/badge_broke_60.svg",
		"category": "18-Hole",
		"rarity": "Legendary"
	},
	"broke_50_9": {
		"id": "broke_50_9",
		"title": "Half-Course Hero",
		"description": "Shoot under 50 in a 9-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_50_9.svg",
		"category": "9-Hole",
		"rarity": "Common"
	},
	"broke_45_9": {
		"id": "broke_45_9",
		"title": "Front/Back Specialist",
		"description": "Shoot under 45 in a 9-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_45_9.svg",
		"category": "9-Hole",
		"rarity": "Rare"
	},
	"broke_40_9": {
		"id": "broke_40_9",
		"title": "Sharp Shooter",
		"description": "Shoot under 40 in a 9-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_40_9.svg",
		"category": "9-Hole",
		"rarity": "Epic"
	},
	"broke_35_9": {
		"id": "broke_35_9",
		"title": "Under Par Nine",
		"description": "Shoot under 35 in a 9-hole round",
		"badge_path": "res://assets/images/achievements/badge_broke_35_9.svg",
		"category": "9-Hole",
		"rarity": "Epic"
	},
	"broke_30_9": {
		"id": "broke_30_9",
		"title": "Unstoppable Nine",
		"description": "Shoot under 30 in a 9-hole round!",
		"badge_path": "res://assets/images/achievements/badge_broke_30_9.svg",
		"category": "9-Hole",
		"rarity": "Legendary"
	},
	"win_1_round": {
		"id": "win_1_round",
		"title": "First Victory",
		"description": "Win your first round of golf",
		"badge_path": "res://assets/images/achievements/badge_win_1.svg",
		"category": "Wins",
		"rarity": "Common"
	},
	"win_5_rounds": {
		"id": "win_5_rounds",
		"title": "5-Time Champion",
		"description": "Win 5 total rounds of golf",
		"badge_path": "res://assets/images/achievements/badge_win_5.svg",
		"category": "Wins",
		"rarity": "Rare"
	},
	"win_10_rounds": {
		"id": "win_10_rounds",
		"title": "Decathlon Winner",
		"description": "Win 10 total rounds of golf",
		"badge_path": "res://assets/images/achievements/badge_win_10.svg",
		"category": "Wins",
		"rarity": "Epic"
	},
	"win_50_rounds": {
		"id": "win_50_rounds",
		"title": "Hall of Famer",
		"description": "Win 50 total rounds of golf!",
		"badge_path": "res://assets/images/achievements/badge_win_50.svg",
		"category": "Wins",
		"rarity": "Legendary"
	},
	"long_drive": {
		"id": "long_drive",
		"title": "Bomb Dropper",
		"description": "Hit a drive exceeding 300 yards",
		"badge_path": "res://assets/images/achievements/badge_long_drive.svg",
		"category": "Special",
		"rarity": "Rare"
	},
	"long_putt": {
		"id": "long_putt",
		"title": "Downtown Drain",
		"description": "Drain a putt from 30+ feet out",
		"badge_path": "res://assets/images/achievements/badge_long_putt.svg",
		"category": "Special",
		"rarity": "Rare"
	},
	"sand_save": {
		"id": "sand_save",
		"title": "Beach Escape",
		"description": "Make par or better after hitting out of a sand bunker",
		"badge_path": "res://assets/images/achievements/badge_sand_save.svg",
		"category": "Special",
		"rarity": "Rare"
	}
}

var _player_data: Dictionary = {}
var _popup_instance: Node = null

func _ready() -> void:
	_player_data = _load_data()
	call_deferred("_setup_popup_ui")

func _setup_popup_ui() -> void:
	if _popup_instance != null and is_instance_valid(_popup_instance):
		return
	var ach_popup_scene = load("res://UI/AchievementPopup/achievement_popup.tscn")
	if ach_popup_scene != null:
		_popup_instance = ach_popup_scene.instantiate()
		add_child(_popup_instance)

func is_showing_achievement() -> bool:
	if _popup_instance != null and is_instance_valid(_popup_instance):
		if _popup_instance.has_method("is_showing_achievement"):
			return bool(_popup_instance.call("is_showing_achievement"))
	return false

func _load_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		return json.data
	return {}

func _save_data() -> void:
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_player_data, "\t"))

func get_all_achievements() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	var order = [
		"first_par", "first_birdie", "first_eagle", "first_albatross", "hole_in_one",
		"broke_100_18", "broke_90_18", "broke_80_18", "broke_70_18", "broke_60_18",
		"broke_50_9", "broke_45_9", "broke_40_9", "broke_35_9", "broke_30_9",
		"win_1_round", "win_5_rounds", "win_10_rounds", "win_50_rounds",
		"long_drive", "long_putt", "sand_save"
	]
	for id in order:
		if achievements_db.has(id):
			list.append(achievements_db[id])
	return list

func get_unlocked_achievements(player_name: String) -> Dictionary:
	if player_name.is_empty():
		return {}
	return _player_data.get(player_name, {})

func is_unlocked(player_name: String, ach_id: String) -> bool:
	if player_name.is_empty() or not achievements_db.has(ach_id):
		return false
	var p_ach = _player_data.get(player_name, {})
	return p_ach.has(ach_id)

func unlock_achievement(player_name: String, ach_id: String) -> bool:
	if player_name.is_empty() or not achievements_db.has(ach_id):
		return false
		
	if not _player_data.has(player_name):
		_player_data[player_name] = {}
		
	if _player_data[player_name].has(ach_id):
		return false # Already unlocked
		
	var ach_def = achievements_db[ach_id]
	_player_data[player_name][ach_id] = {
		"unlocked_at": Time.get_unix_time_from_system()
	}
	_save_data()
	
	print("[AchievementManager] Unlocked '%s' (%s) for player '%s'!" % [ach_def.title, ach_id, player_name])
	emit_signal("achievement_unlocked", player_name, ach_def)
	return true

# --- Evaluation Helpers ---

func check_hole_achievements(player_name: String, hole_par: int, strokes: int, lies_in_hole: Array = [], putt_dist_yards: float = 0.0, holed_in_cup: bool = false) -> void:
	if player_name.is_empty() or strokes <= 0:
		return
		
	# Hole-in-One (must go into the actual cup, never from a gimme)
	if holed_in_cup and strokes == 1:
		unlock_achievement(player_name, "hole_in_one")
		
	var diff = strokes - hole_par
	if diff == 0:
		unlock_achievement(player_name, "first_par")
	elif diff == -1:
		# Birdie requires ball entering the actual cup, no gimmes
		if holed_in_cup:
			unlock_achievement(player_name, "first_birdie")
	elif diff == -2:
		# Eagle requires ball entering the actual cup, no gimmes
		if holed_in_cup:
			unlock_achievement(player_name, "first_eagle")
	elif diff <= -3:
		# Albatross / Double Eagle requires ball entering the actual cup, no gimmes
		if holed_in_cup:
			unlock_achievement(player_name, "first_albatross")
		
	# Long putt (if holed out with putt >= 10 yards / 30 feet directly into cup, never from gimme range)
	if holed_in_cup and putt_dist_yards >= 10.0 and lies_in_hole.size() > 0 and lies_in_hole[-1] == "green":
		unlock_achievement(player_name, "long_putt")
		
	# Sand save: Par or better after hitting out of a bunker
	if diff <= 0 and "bunker" in lies_in_hole:
		unlock_achievement(player_name, "sand_save")

func check_shot_achievements(player_name: String, club_name: String, total_yards: float) -> void:
	if player_name.is_empty():
		return
	if total_yards >= 300.0 and (club_name.begins_with("Dr") or club_name.to_lower() == "driver"):
		unlock_achievement(player_name, "long_drive")

func check_round_achievements(player_name: String, total_strokes: int, hole_count: int, is_winner: bool, total_wins: int) -> void:
	if player_name.is_empty() or total_strokes <= 0:
		return
		
	# 18-hole milestones
	if hole_count >= 18:
		if total_strokes < 100:
			unlock_achievement(player_name, "broke_100_18")
		if total_strokes < 90:
			unlock_achievement(player_name, "broke_90_18")
		if total_strokes < 80:
			unlock_achievement(player_name, "broke_80_18")
		if total_strokes < 70:
			unlock_achievement(player_name, "broke_70_18")
		if total_strokes < 60:
			unlock_achievement(player_name, "broke_60_18")
			
	# 9-hole milestones
	if hole_count >= 9 and hole_count < 18:
		if total_strokes < 50:
			unlock_achievement(player_name, "broke_50_9")
		if total_strokes < 45:
			unlock_achievement(player_name, "broke_45_9")
		if total_strokes < 40:
			unlock_achievement(player_name, "broke_40_9")
		if total_strokes < 35:
			unlock_achievement(player_name, "broke_35_9")
		if total_strokes < 30:
			unlock_achievement(player_name, "broke_30_9")
			
	# Win milestones
	if is_winner:
		unlock_achievement(player_name, "win_1_round")
		if total_wins >= 5:
			unlock_achievement(player_name, "win_5_rounds")
		if total_wins >= 10:
			unlock_achievement(player_name, "win_10_rounds")
		if total_wins >= 50:
			unlock_achievement(player_name, "win_50_rounds")
