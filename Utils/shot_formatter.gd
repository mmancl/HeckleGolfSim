extends Object
class_name ShotFormatter

# Formats ball/shot data for UI display, with unit conversion and derived spin/club delivery metrics.
# If is_final_rest is false (during flight/rollout), dynamic stats (Distance, Carry, Apex, Offline, HangTime, DescentAngle)
# display "---" so that static metrics show immediately on strike while dynamic stats wait until the ball finishes rolling.
static func format_ball_display(raw_ball_data: Dictionary, player: Node, units: int, is_final_rest: bool = true, prev_data: Dictionary = {}) -> Dictionary:
	var ball_data: Dictionary = {}
	if raw_ball_data.is_empty():
		for stat_id in StatDefinitions.get_all_stat_ids():
			ball_data[stat_id] = "---"
		return ball_data

	var m2yd := 1.09361
	var computed_stats: Array[String] = []

	var has_backspin := raw_ball_data.has("BackSpin") and str(raw_ball_data["BackSpin"]) not in ["", "---", "N/A"]
	var has_sidespin := raw_ball_data.has("SideSpin") and str(raw_ball_data["SideSpin"]) not in ["", "---", "N/A"]
	var has_total := raw_ball_data.has("TotalSpin") and str(raw_ball_data["TotalSpin"]) not in ["", "---", "N/A"] and float(str(raw_ball_data["TotalSpin"])) > 0.0
	var has_axis := raw_ball_data.has("SpinAxis") and str(raw_ball_data["SpinAxis"]) not in ["", "---", "N/A"]
	var backspin: float = (raw_ball_data.get("BackSpin", 0.0) as float)
	var sidespin: float = (raw_ball_data.get("SideSpin", 0.0) as float)
	var total_spin: float = (raw_ball_data.get("TotalSpin", 0.0) as float)
	var spin_axis: float = (raw_ball_data.get("SpinAxis", 0.0) as float)
	if total_spin == 0.0 and (has_backspin or has_sidespin):
		total_spin = sqrt(backspin*backspin + sidespin*sidespin)
		if total_spin > 0.0:
			computed_stats.append("TotalSpin")
	if not has_axis and (has_backspin or has_sidespin):
		spin_axis = rad_to_deg(atan2(sidespin, backspin))
		computed_stats.append("SpinAxis")
	if has_total and has_axis:
		if not has_backspin:
			backspin = total_spin * cos(deg_to_rad(spin_axis))
			computed_stats.append("BackSpin")
		if not has_sidespin:
			sidespin = total_spin * sin(deg_to_rad(spin_axis))
			computed_stats.append("SideSpin")
	
	var raw_speed_mph := float(raw_ball_data.get("BallSpeed", raw_ball_data.get("Speed", 0.0)))
	var raw_vla := float(raw_ball_data.get("VLA", 0.0))
	var raw_hla := float(raw_ball_data.get("HLA", 0.0))

	# --- 1. Ball & Distance Metrics ---
	var has_saved_data = raw_ball_data.has("TotalDistance") or raw_ball_data.has("CarryDistance")
	if units == PhysicsEnums.Units.IMPERIAL:
		ball_data["Speed"] = "%.1f" % raw_speed_mph
		ball_data["BallSpeed"] = ball_data["Speed"]
		if player != null or has_saved_data:
			var dist_m = player.get_distance() if player != null else float(raw_ball_data.get("TotalDistance", 0.0))
			ball_data["Distance"] = "%.1f" % (dist_m * m2yd)
			var carry_val = player.carry if player != null else 0.0
			if carry_val <= 0:
				if raw_ball_data.has("CarryDistance"):
					carry_val = raw_ball_data.get("CarryDistance", 0.0) as float
				elif not is_final_rest:
					carry_val = dist_m
			ball_data["Carry"] = "%.1f" % (carry_val * m2yd)
			var apex_m = player.apex if player != null else float(raw_ball_data.get("Apex", 0.0))
			ball_data["Apex"] = "%.1f" % (apex_m * 3.28084)
			var side_distance = (player.get_side_distance() if player != null else float(raw_ball_data.get("SideDistance", 0.0))) * m2yd
			var side_text := ""
			if abs(side_distance) < 0.05:
				side_text = "0.0"
			else:
				side_text = ("R" if side_distance >= 0 else "L") + ("%.1f" % abs(side_distance))
			ball_data["Offline"] = side_text
			var rollout_enabled := true
			if Engine.has_singleton("GlobalSettings"):
				var gs = Engine.get_singleton("GlobalSettings")
				if gs.get("range_settings") != null and gs.range_settings.get("ball_rollout_enabled") != null:
					rollout_enabled = bool(gs.range_settings.ball_rollout_enabled.value)
			elif is_instance_valid(Engine.get_main_loop()):
				var root = Engine.get_main_loop().get("root") if Engine.get_main_loop().has_method("get") else null
				if root != null and root.has_node("GlobalSettings"):
					var gs = root.get_node("GlobalSettings")
					if gs.get("range_settings") != null and gs.range_settings.get("ball_rollout_enabled") != null:
						rollout_enabled = bool(gs.range_settings.ball_rollout_enabled.value)

			if not rollout_enabled or not is_final_rest:
				ball_data["Rollout"] = "---"
			else:
				var rollout_yd = (dist_m - carry_val) * m2yd
				ball_data["Rollout"] = "%.1f" % rollout_yd
		else:
			ball_data["Distance"] = "---"
			ball_data["Carry"] = "---"
			ball_data["Rollout"] = "---"
			ball_data["Apex"] = "---"
			ball_data["Offline"] = "---"
	else:
		ball_data["Speed"] = "%.1f" % (raw_speed_mph * 0.44704)
		ball_data["BallSpeed"] = ball_data["Speed"]
		if player != null or has_saved_data:
			var dist_m = player.get_distance() if player != null else float(raw_ball_data.get("TotalDistance", 0.0))
			ball_data["Distance"] = "%.1f" % dist_m
			var carry_val = player.carry if player != null else 0.0
			if carry_val <= 0:
				if raw_ball_data.has("CarryDistance"):
					carry_val = raw_ball_data.get("CarryDistance", 0.0) as float
				elif not is_final_rest:
					carry_val = dist_m
			ball_data["Carry"] = "%.1f" % carry_val
			var apex_m = player.apex if player != null else float(raw_ball_data.get("Apex", 0.0))
			ball_data["Apex"] = "%.1f" % apex_m
			var side_distance = player.get_side_distance() if player != null else float(raw_ball_data.get("SideDistance", 0.0))
			var side_text := ""
			if abs(side_distance) < 0.05:
				side_text = "0.0"
			else:
				side_text = ("R" if side_distance >= 0 else "L") + ("%.1f" % abs(side_distance))
			ball_data["Offline"] = side_text

			var rollout_enabled := true
			if Engine.has_singleton("GlobalSettings"):
				var gs = Engine.get_singleton("GlobalSettings")
				if gs.get("range_settings") != null and gs.range_settings.get("ball_rollout_enabled") != null:
					rollout_enabled = bool(gs.range_settings.ball_rollout_enabled.value)
			elif is_instance_valid(Engine.get_main_loop()):
				var root = Engine.get_main_loop().get("root") if Engine.get_main_loop().has_method("get") else null
				if root != null and root.has_node("GlobalSettings"):
					var gs = root.get_node("GlobalSettings")
					if gs.get("range_settings") != null and gs.range_settings.get("ball_rollout_enabled") != null:
						rollout_enabled = bool(gs.range_settings.ball_rollout_enabled.value)

			if not rollout_enabled or not is_final_rest:
				ball_data["Rollout"] = "---"
			else:
				var rollout_m = dist_m - carry_val
				ball_data["Rollout"] = "%.1f" % rollout_m
		else:
			ball_data["Distance"] = "---"
			ball_data["Carry"] = "---"
			ball_data["Rollout"] = "---"
			ball_data["Apex"] = "---"
			ball_data["Offline"] = "---"
	
	ball_data["BackSpin"] = str(int(backspin))
	ball_data["SideSpin"] = str(int(sidespin))
	ball_data["TotalSpin"] = str(int(total_spin))
	ball_data["SpinAxis"] = "%3.1f" % spin_axis
	ball_data["VLA"] = "%3.1f" % raw_vla
	ball_data["HLA"] = "%3.1f" % raw_hla

	# --- 2. Trajectory Dynamics (Hang Time & Descent Angle) ---
	var hang_time_sec := 0.0
	if raw_ball_data.has("HangTime"):
		hang_time_sec = float(raw_ball_data.get("HangTime", 0.0))
	elif player != null and player.get("ball") != null and "flight_time" in player.ball and float(player.ball.flight_time) > 0.0:
		hang_time_sec = float(player.ball.flight_time)
	elif raw_speed_mph > 0.0 and raw_vla > 0.0:
		var v_init_mps = raw_speed_mph * 0.44704
		var vy_init = v_init_mps * sin(deg_to_rad(raw_vla))
		hang_time_sec = max(0.5, (2.0 * vy_init) / 9.81 * 0.92) # approx flight arc
	ball_data["HangTime"] = "%.1f" % hang_time_sec

	var descent_deg := 0.0
	if raw_ball_data.has("DescentAngle"):
		descent_deg = float(raw_ball_data.get("DescentAngle", 0.0))
	elif raw_vla > 0.0:
		var curr_apex = player.apex if player != null else float(raw_ball_data.get("Apex", 0.0))
		descent_deg = clampf(raw_vla * 1.45 + (curr_apex * 0.15), 15.0, 60.0)
	ball_data["DescentAngle"] = "%.1f" % descent_deg

	# --- 3. Club Delivery Metrics ---
	# Club Face Angle
	var direct_face_angle := false
	var face_angle_num := 0.0
	for fa_key in ["FaceAngle", "ClubFaceAngle", "FaceToTarget", "RawFaceAngle"]:
		if raw_ball_data.has(fa_key):
			var fa_raw = str(raw_ball_data[fa_key]).strip_edges()
			if fa_raw not in ["", "---", "N/A"]:
				direct_face_angle = true
				var clean_fa = fa_raw.replace("O", "").replace("C", "").replace("Sq", "").strip_edges()
				var is_c = fa_raw.to_upper().ends_with("C")
				if clean_fa.is_valid_float():
					face_angle_num = -absf(float(clean_fa)) if is_c else float(clean_fa)
				break

	# Club Path
	var direct_club_path := false
	var club_path_num := 0.0
	for cp_key in ["ClubPath", "Path", "RawClubPath"]:
		if raw_ball_data.has(cp_key):
			var cp_raw = str(raw_ball_data[cp_key]).strip_edges()
			if cp_raw not in ["", "---", "N/A"]:
				direct_club_path = true
				var clean_cp = cp_raw.replace("I-O", "").replace("O-I", "").replace("In-Out", "").replace("Out-In", "").replace("Str", "").strip_edges()
				var is_oi = ("O-I" in cp_raw.to_upper()) or ("OUT-IN" in cp_raw.to_upper())
				if clean_cp.is_valid_float():
					club_path_num = -absf(float(clean_cp)) if is_oi else float(clean_cp)
				break

	# Face to Path
	var direct_face_to_path := false
	var face_to_path_num := 0.0
	for ftp_key in ["FaceToPath", "RawFaceToPath"]:
		if raw_ball_data.has(ftp_key):
			var ftp_raw = str(raw_ball_data[ftp_key]).strip_edges()
			if ftp_raw not in ["", "---", "N/A"]:
				direct_face_to_path = true
				var clean_ftp = ftp_raw.replace("O", "").replace("C", "").replace("Sq", "").strip_edges()
				var is_c = ftp_raw.to_upper().ends_with("C")
				if clean_ftp.is_valid_float():
					face_to_path_num = -absf(float(clean_ftp)) if is_c else float(clean_ftp)
				break

	# 1. Resolve Face to Path
	if direct_face_to_path:
		if absf(face_to_path_num) < 0.1:
			ball_data["FaceToPath"] = "0.0 Sq"
		elif face_to_path_num > 0.0:
			ball_data["FaceToPath"] = "%.1f O" % face_to_path_num
		else:
			ball_data["FaceToPath"] = "%.1f C" % absf(face_to_path_num)
		ball_data["RawFaceToPath"] = face_to_path_num
	elif direct_face_angle and direct_club_path:
		face_to_path_num = face_angle_num - club_path_num
		if absf(face_to_path_num) < 0.1:
			ball_data["FaceToPath"] = "0.0 Sq"
		elif face_to_path_num > 0.0:
			ball_data["FaceToPath"] = "%.1f O" % face_to_path_num
		else:
			ball_data["FaceToPath"] = "%.1f C" % absf(face_to_path_num)
		ball_data["RawFaceToPath"] = face_to_path_num
		computed_stats.append("FaceToPath")
	else:
		ball_data["FaceToPath"] = "N/A"

	# 2. Resolve Face Angle
	if direct_face_angle:
		if absf(face_angle_num) < 0.1:
			ball_data["FaceAngle"] = "0.0 Sq"
		elif face_angle_num > 0.0:
			ball_data["FaceAngle"] = "%.1f O" % face_angle_num
		else:
			ball_data["FaceAngle"] = "%.1f C" % absf(face_angle_num)
		ball_data["RawFaceAngle"] = face_angle_num
	elif direct_face_to_path and direct_club_path:
		face_angle_num = face_to_path_num + club_path_num
		if absf(face_angle_num) < 0.1:
			ball_data["FaceAngle"] = "0.0 Sq"
		elif face_angle_num > 0.0:
			ball_data["FaceAngle"] = "%.1f O" % face_angle_num
		else:
			ball_data["FaceAngle"] = "%.1f C" % absf(face_angle_num)
		ball_data["RawFaceAngle"] = face_angle_num
		computed_stats.append("FaceAngle")
	else:
		ball_data["FaceAngle"] = "N/A"

	# 3. Resolve Club Path
	if direct_club_path:
		if absf(club_path_num) < 0.1:
			ball_data["ClubPath"] = "0.0 Str"
		elif club_path_num > 0.0:
			ball_data["ClubPath"] = "%.1f I-O" % club_path_num
		else:
			ball_data["ClubPath"] = "%.1f O-I" % absf(club_path_num)
		ball_data["RawClubPath"] = club_path_num
	elif direct_face_angle and direct_face_to_path:
		club_path_num = face_angle_num - face_to_path_num
		if absf(club_path_num) < 0.1:
			ball_data["ClubPath"] = "0.0 Str"
		elif club_path_num > 0.0:
			ball_data["ClubPath"] = "%.1f I-O" % club_path_num
		else:
			ball_data["ClubPath"] = "%.1f O-I" % absf(club_path_num)
		ball_data["RawClubPath"] = club_path_num
		computed_stats.append("ClubPath")
	else:
		ball_data["ClubPath"] = "N/A"

	# Attack Angle (AoA)
	if raw_ball_data.has("AttackAngle") or raw_ball_data.has("AngleOfAttack"):
		var raw_aoa = raw_ball_data.get("AttackAngle", raw_ball_data.get("AngleOfAttack", 0.0))
		var attack_angle := 0.0
		if typeof(raw_aoa) == TYPE_INT or typeof(raw_aoa) == TYPE_FLOAT:
			attack_angle = float(raw_aoa)
		elif typeof(raw_aoa) == TYPE_STRING and str(raw_aoa) != "---" and str(raw_aoa) != "N/A":
			var cleaned_aoa = str(raw_aoa).strip_edges().replace("+", "")
			if cleaned_aoa.is_valid_float():
				attack_angle = float(cleaned_aoa)
		if abs(attack_angle) < 0.001:
			ball_data["AttackAngle"] = "N/A"
		else:
			ball_data["AttackAngle"] = ("+%.1f" % attack_angle) if attack_angle > 0.0 else ("%.1f" % attack_angle)
			ball_data["RawAttackAngle"] = attack_angle
	else:
		ball_data["AttackAngle"] = "N/A"

	# Dynamic Loft
	if raw_ball_data.has("DynamicLoft") and float(raw_ball_data.get("DynamicLoft", 0.0)) > 0.01:
		var dynamic_loft = float(raw_ball_data.get("DynamicLoft", 0.0))
		ball_data["DynamicLoft"] = "%.1f" % dynamic_loft
	else:
		ball_data["DynamicLoft"] = "N/A"

	# Clubhead Speed & Smash Factor
	var direct_club_speed := false
	var club_speed_mph := 0.0
	if raw_ball_data.has("ClubSpeed"):
		var cs_raw = str(raw_ball_data["ClubSpeed"]).strip_edges()
		if cs_raw not in ["", "---", "N/A"] and cs_raw.is_valid_float() and float(cs_raw) > 0.01:
			direct_club_speed = true
			club_speed_mph = float(cs_raw)

	var direct_smash := false
	var smash_factor_val := 0.0
	if raw_ball_data.has("SmashFactor"):
		var sf_raw = str(raw_ball_data["SmashFactor"]).strip_edges()
		if sf_raw not in ["", "---", "N/A"] and sf_raw.is_valid_float() and float(sf_raw) > 0.05:
			direct_smash = true
			smash_factor_val = float(sf_raw)

	if direct_club_speed:
		if units == PhysicsEnums.Units.IMPERIAL:
			ball_data["ClubSpeed"] = "%.1f" % club_speed_mph
		else:
			ball_data["ClubSpeed"] = "%.1f" % (club_speed_mph * 0.44704)
	elif direct_smash and smash_factor_val > 0.0 and raw_speed_mph > 0.0:
		club_speed_mph = raw_speed_mph / smash_factor_val
		if units == PhysicsEnums.Units.IMPERIAL:
			ball_data["ClubSpeed"] = "%.1f" % club_speed_mph
		else:
			ball_data["ClubSpeed"] = "%.1f" % (club_speed_mph * 0.44704)
		computed_stats.append("ClubSpeed")
	else:
		ball_data["ClubSpeed"] = "N/A"

	if direct_smash:
		ball_data["SmashFactor"] = "%.2f" % smash_factor_val
	elif direct_club_speed and raw_speed_mph > 0.0 and club_speed_mph > 0.0:
		ball_data["SmashFactor"] = "%.2f" % (raw_speed_mph / club_speed_mph)
		computed_stats.append("SmashFactor")
	else:
		ball_data["SmashFactor"] = "N/A"

	# Club identification
	if raw_ball_data.has("Club") and not str(raw_ball_data["Club"]).is_empty():
		ball_data["Club"] = str(raw_ball_data["Club"])
	elif raw_ball_data.has("club") and not str(raw_ball_data["club"]).is_empty():
		ball_data["Club"] = str(raw_ball_data["club"])
	elif player != null and player.get("ball") != null and "current_selected_club" in player.ball and not str(player.ball.current_selected_club).is_empty():
		ball_data["Club"] = str(player.ball.current_selected_club)
	elif player != null and player.has_method("_get_selected_club"):
		ball_data["Club"] = str(player._get_selected_club())
	elif prev_data.has("Club") and not str(prev_data["Club"]).is_empty():
		ball_data["Club"] = str(prev_data["Club"])

	# Lie and tee status
	if raw_ball_data.has("is_tee"):
		ball_data["is_tee"] = bool(raw_ball_data["is_tee"])
	elif player != null and player.get("ball") != null and "lie_type" in player.ball:
		ball_data["is_tee"] = (str(player.ball.lie_type).to_lower() == "teebox")
	elif prev_data.has("is_tee"):
		ball_data["is_tee"] = bool(prev_data["is_tee"])
	else:
		ball_data["is_tee"] = false

	if raw_ball_data.has("lie_type"):
		ball_data["lie_type"] = str(raw_ball_data["lie_type"])
	elif player != null and player.get("ball") != null and "lie_type" in player.ball:
		ball_data["lie_type"] = str(player.ball.lie_type)
	elif prev_data.has("lie_type"):
		ball_data["lie_type"] = str(prev_data["lie_type"])
	else:
		ball_data["lie_type"] = "teebox" if ball_data.get("is_tee", false) else "fairway"

	# Preserve numeric Club Delivery & Impact metrics for Shot Analysis & Profile Visuals
	if raw_ball_data.has("HorizontalFaceImpact"):
		ball_data["HorizontalFaceImpact"] = float(raw_ball_data["HorizontalFaceImpact"])
	elif raw_ball_data.has("impact_offset_horizontal"):
		ball_data["HorizontalFaceImpact"] = float(raw_ball_data["impact_offset_horizontal"])
	elif raw_ball_data.has("ImpactLocationX"):
		ball_data["HorizontalFaceImpact"] = float(raw_ball_data["ImpactLocationX"])

	if raw_ball_data.has("VerticalFaceImpact"):
		ball_data["VerticalFaceImpact"] = float(raw_ball_data["VerticalFaceImpact"])
	elif raw_ball_data.has("impact_offset_vertical"):
		ball_data["VerticalFaceImpact"] = float(raw_ball_data["impact_offset_vertical"])
	elif raw_ball_data.has("ImpactLocationY"):
		ball_data["VerticalFaceImpact"] = float(raw_ball_data["ImpactLocationY"])

	if raw_ball_data.has("impact_points"):
		ball_data["impact_points"] = raw_ball_data["impact_points"]

	# Preserve player identification and raw metrics for diagnostic analysis
	if raw_ball_data.has("player") and not str(raw_ball_data["player"]).is_empty():
		ball_data["player"] = str(raw_ball_data["player"])
	elif raw_ball_data.has("Player") and not str(raw_ball_data["Player"]).is_empty():
		ball_data["player"] = str(raw_ball_data["Player"])
	elif prev_data.has("player") and not str(prev_data["player"]).is_empty():
		ball_data["player"] = str(prev_data["player"])

	if raw_ball_data.has("CarryDistance"):
		ball_data["CarryDistance"] = float(raw_ball_data["CarryDistance"])
	if raw_ball_data.has("TotalDistance"):
		ball_data["TotalDistance"] = float(raw_ball_data["TotalDistance"])
	if raw_ball_data.has("SmashFactor") and not ball_data.has("SmashFactor"):
		ball_data["SmashFactor"] = float(raw_ball_data["SmashFactor"])
	if raw_ball_data.has("AttackAngle") and not ball_data.has("AttackAngle"):
		ball_data["AttackAngle"] = float(raw_ball_data["AttackAngle"])
	elif raw_ball_data.has("AngleOfAttack") and not ball_data.has("AttackAngle"):
		ball_data["AttackAngle"] = float(raw_ball_data["AngleOfAttack"])

	ball_data["_computed_stats"] = computed_stats
	return ball_data
