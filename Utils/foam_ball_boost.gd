extends Object
class_name FoamBallBoost

## Utility class for applying ball speed boost to compensate for foam practice balls.
## Foam balls compress significantly more and have much lower mass, causing launch monitors
## to register artificially slow ball launch velocities.
##
## Scaling rules:
## - Drivers & Woods: 100% of slider boost %
## - Hybrids & Irons: 75% of slider boost %
## - Wedges: 50% of slider boost %
## - Putter: 0% (no boost)

const DEFAULT_BOOST_PERCENT := 20.0

## Returns the fraction of the boost percentage (0.0 to 1.0) applied to the specified club.
static func get_club_boost_ratio(club_str: String) -> float:
	var c := club_str.strip_edges().to_lower()
	if c.is_empty():
		return 1.0 # Default to driver/wood ratio if club not specified
	
	# Putter: 0%
	if c in ["pt", "putt", "putter"] or c.begins_with("putt"):
		return 0.0
	
	# Wedges: 50%
	if c in ["pw", "gw", "sw", "lw", "aw"] \
		or c.ends_with("wedge") \
		or c.begins_with("wedge") \
		or c in ["pitching wedge", "gap wedge", "sand wedge", "lob wedge", "approach wedge"] \
		or c in ["pitching", "sand", "lob", "approach"]:
		return 0.50
	
	# Degree wedges (e.g., 46, 48, 50, 52, 54, 56, 58, 60, 62, 64)
	if c.is_valid_int():
		var deg := c.to_int()
		if deg >= 44 and deg <= 64:
			return 0.50
	
	# Hybrids: 75%
	if (c.ends_with("h") and c.length() <= 3) or c.contains("hybrid"):
		return 0.75
	
	# Irons: 75%
	if (c.ends_with("i") and c.length() <= 3) or c.contains("iron"):
		return 0.75
	
	# Drivers & Woods: 100%
	if c in ["dr", "driver", "1w"] \
		or (c.ends_with("w") and c.length() <= 3) \
		or c.contains("wood"):
		return 1.00
	
	# Fallback to 1.0
	return 1.00


## Calculates the effective boost percentage for a club.
static func get_effective_boost_pct(boost_percent: float, club_str: String) -> float:
	return boost_percent * get_club_boost_ratio(club_str)


## Calculates the multiplier to apply to ball speed.
static func calculate_multiplier(club_str: String, boost_percent: float) -> float:
	var effective_pct := get_effective_boost_pct(boost_percent, club_str)
	return 1.0 + (effective_pct / 100.0)


## Applies foam ball boost to a shot payload dictionary in-place.
## Guaranteed to be idempotent per shot payload (prevents double-boosting).
static func apply_boost(data: Dictionary, fallback_club: String = "") -> void:
	var global_settings = null
	if Engine.has_singleton("GlobalSettings"):
		global_settings = Engine.get_singleton("GlobalSettings")
	elif Engine.get_main_loop() != null and Engine.get_main_loop() is SceneTree and Engine.get_main_loop().root != null and Engine.get_main_loop().root.has_node("GlobalSettings"):
		global_settings = Engine.get_main_loop().root.get_node("GlobalSettings")
	
	if global_settings == null or not ("range_settings" in global_settings):
		return
	
	var range_settings = global_settings.range_settings
	if range_settings == null:
		return
	
	# Check if setting is enabled
	if "foam_ball_boost_enabled" in range_settings:
		if not bool(range_settings.foam_ball_boost_enabled.value):
			return
	else:
		return
	
	# Idempotency check: never double boost the same shot dictionary
	if data.get("_foam_boost_applied", false):
		return
	
	var boost_percent: float = DEFAULT_BOOST_PERCENT
	if "foam_ball_boost_percent" in range_settings:
		boost_percent = float(range_settings.foam_ball_boost_percent.value)
	
	if boost_percent <= 0.0:
		data["_foam_boost_applied"] = true
		return
	
	# Determine club
	var club: String = str(data.get("Club", data.get("club", "")))
	if club.is_empty():
		club = fallback_club
	if club.is_empty() and "current_selected_club" in global_settings:
		club = str(global_settings.current_selected_club)
	if club.is_empty():
		club = "Dr"
	
	var effective_pct := get_effective_boost_pct(boost_percent, club)
	var multiplier := 1.0 + (effective_pct / 100.0)
	
	data["_foam_boost_applied"] = true
	data["_foam_boost_effective_pct"] = effective_pct
	
	if not data.has("Club"):
		data["Club"] = club
	
	var raw_speed: float = float(data.get("Speed", data.get("BallSpeed", 0.0)))
	data["_original_speed"] = raw_speed
	
	if raw_speed > 0.0 and multiplier != 1.0:
		var boosted_speed: float = raw_speed * multiplier
		data["Speed"] = boosted_speed
		if data.has("BallSpeed"):
			data["BallSpeed"] = boosted_speed
		
		# Update SmashFactor if present
		if data.has("ClubSpeed") and float(data["ClubSpeed"]) > 0.0:
			data["SmashFactor"] = boosted_speed / float(data["ClubSpeed"])
		elif data.has("SmashFactor") and float(data["SmashFactor"]) > 0.0:
			data["SmashFactor"] = float(data["SmashFactor"]) * multiplier
		
		print("[FoamBallBoost] Applied +%.1f%% boost to %s shot. Speed: %.1f -> %.1f mph" % [
			effective_pct, club, raw_speed, boosted_speed
		])
