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
	var has_backspin := raw_ball_data.has("BackSpin")
	var has_sidespin := raw_ball_data.has("SideSpin")
	var has_total := raw_ball_data.has("TotalSpin")
	var has_axis := raw_ball_data.has("SpinAxis")
	var backspin: float = (raw_ball_data.get("BackSpin", 0.0) as float)
	var sidespin: float = (raw_ball_data.get("SideSpin", 0.0) as float)
	var total_spin: float = (raw_ball_data.get("TotalSpin", 0.0) as float)
	var spin_axis: float = (raw_ball_data.get("SpinAxis", 0.0) as float)
	if total_spin == 0.0 and (has_backspin or has_sidespin):
		total_spin = sqrt(backspin*backspin + sidespin*sidespin)
	if not has_axis and (has_backspin or has_sidespin):
		spin_axis = rad_to_deg(atan2(sidespin, backspin))
	if has_total and has_axis:
		if not has_backspin:
			backspin = total_spin * cos(deg_to_rad(spin_axis))
		if not has_sidespin:
			sidespin = total_spin * sin(deg_to_rad(spin_axis))
	
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
		else:
			ball_data["Distance"] = "---"
			ball_data["Carry"] = "---"
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
		else:
			ball_data["Distance"] = "---"
			ball_data["Carry"] = "---"
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
	var has_face_angle := raw_ball_data.has("FaceAngle") or raw_ball_data.has("ClubFaceAngle") or raw_ball_data.has("FaceToTarget") or raw_ball_data.has("RawFaceAngle")
	if has_face_angle:
		var face_angle = float(raw_ball_data.get("FaceAngle", raw_ball_data.get("ClubFaceAngle", raw_ball_data.get("FaceToTarget", raw_ball_data.get("RawFaceAngle", 0.0)))))
		if abs(face_angle) < 0.1:
			ball_data["FaceAngle"] = "0.0 Sq"
		elif face_angle > 0.0:
			ball_data["FaceAngle"] = "%.1f O" % face_angle
		else:
			ball_data["FaceAngle"] = "%.1f C" % abs(face_angle)
		ball_data["RawFaceAngle"] = face_angle
	elif raw_speed_mph > 20.0:
		# Fallback estimation using launch direction and spin axis
		var est_face = raw_hla * 0.75 + (spin_axis * 0.15)
		if abs(est_face) < 0.1:
			ball_data["FaceAngle"] = "0.0 Sq"
		elif est_face > 0.0:
			ball_data["FaceAngle"] = "%.1f O" % est_face
		else:
			ball_data["FaceAngle"] = "%.1f C" % abs(est_face)
		ball_data["RawFaceAngle"] = est_face
	else:
		ball_data["FaceAngle"] = "---"

	# Club Path
	var has_club_path := raw_ball_data.has("ClubPath") or raw_ball_data.has("Path") or raw_ball_data.has("RawClubPath")
	if has_club_path:
		var club_path = float(raw_ball_data.get("ClubPath", raw_ball_data.get("Path", raw_ball_data.get("RawClubPath", 0.0))))
		if abs(club_path) < 0.1:
			ball_data["ClubPath"] = "0.0 Str"
		elif club_path > 0.0:
			ball_data["ClubPath"] = "%.1f In-Out" % club_path
		else:
			ball_data["ClubPath"] = "%.1f Out-In" % abs(club_path)
		ball_data["RawClubPath"] = club_path
	elif raw_speed_mph > 20.0 and ball_data.has("RawFaceAngle"):
		var est_path = (raw_hla - float(ball_data["RawFaceAngle"]) * 0.75) / 0.25
		if abs(est_path) < 0.1:
			ball_data["ClubPath"] = "0.0 Str"
		elif est_path > 0.0:
			ball_data["ClubPath"] = "%.1f In-Out" % est_path
		else:
			ball_data["ClubPath"] = "%.1f Out-In" % abs(est_path)
		ball_data["RawClubPath"] = est_path
	else:
		ball_data["ClubPath"] = "---"

	# Face to Path
	var has_face_to_path := raw_ball_data.has("FaceToPath") or raw_ball_data.has("RawFaceToPath")
	if has_face_to_path:
		var face_to_path = float(raw_ball_data.get("FaceToPath", raw_ball_data.get("RawFaceToPath", 0.0)))
		if abs(face_to_path) < 0.1:
			ball_data["FaceToPath"] = "0.0 Sq"
		elif face_to_path > 0.0:
			ball_data["FaceToPath"] = "%.1f O" % face_to_path
		else:
			ball_data["FaceToPath"] = "%.1f C" % abs(face_to_path)
		ball_data["RawFaceToPath"] = face_to_path
	elif ball_data.has("RawFaceAngle") and ball_data.has("RawClubPath"):
		var face_to_path = float(ball_data["RawFaceAngle"]) - float(ball_data["RawClubPath"])
		if abs(face_to_path) < 0.1:
			ball_data["FaceToPath"] = "0.0 Sq"
		elif face_to_path > 0.0:
			ball_data["FaceToPath"] = "%.1f O" % face_to_path
		else:
			ball_data["FaceToPath"] = "%.1f C" % abs(face_to_path)
		ball_data["RawFaceToPath"] = face_to_path
	else:
		ball_data["FaceToPath"] = "---"

	# Attack Angle (AoA)
	if raw_ball_data.has("AttackAngle") or raw_ball_data.has("AngleOfAttack"):
		var attack_angle = float(raw_ball_data.get("AttackAngle", raw_ball_data.get("AngleOfAttack", 0.0)))
		ball_data["AttackAngle"] = ("+%.1f" % attack_angle) if attack_angle > 0.0 else ("%.1f" % attack_angle)
	else:
		ball_data["AttackAngle"] = "---"

	# Dynamic Loft
	if raw_ball_data.has("DynamicLoft") and float(raw_ball_data.get("DynamicLoft", 0.0)) > 0.01:
		var dynamic_loft = float(raw_ball_data.get("DynamicLoft", 0.0))
		ball_data["DynamicLoft"] = "%.1f" % dynamic_loft
	else:
		ball_data["DynamicLoft"] = "---"

	# Clubhead Speed & Smash Factor
	var has_club_speed := raw_ball_data.has("ClubSpeed") and float(raw_ball_data.get("ClubSpeed", 0.0)) > 0.0
	var has_smash_factor := raw_ball_data.has("SmashFactor") and float(raw_ball_data.get("SmashFactor", 0.0)) > 0.05

	var club_speed_mph := 0.0
	if has_club_speed:
		club_speed_mph = float(raw_ball_data.get("ClubSpeed", 0.0))
		if units == PhysicsEnums.Units.IMPERIAL:
			ball_data["ClubSpeed"] = "%.1f" % club_speed_mph
		else:
			ball_data["ClubSpeed"] = "%.1f" % (club_speed_mph * 0.44704)
	else:
		ball_data["ClubSpeed"] = "---"

	if has_smash_factor:
		ball_data["SmashFactor"] = "%.2f" % float(raw_ball_data.get("SmashFactor", 0.0))
	elif has_club_speed and raw_speed_mph > 0.0 and club_speed_mph > 0.0:
		ball_data["SmashFactor"] = "%.2f" % (raw_speed_mph / club_speed_mph)
	else:
		ball_data["SmashFactor"] = "---"

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
	if raw_ball_data.has("ClubSpeed"):
		ball_data["ClubSpeed"] = float(raw_ball_data["ClubSpeed"])
	if raw_ball_data.has("SmashFactor"):
		ball_data["SmashFactor"] = float(raw_ball_data["SmashFactor"])
	if raw_ball_data.has("AttackAngle"):
		ball_data["AttackAngle"] = float(raw_ball_data["AttackAngle"])
	elif raw_ball_data.has("AngleOfAttack"):
		ball_data["AttackAngle"] = float(raw_ball_data["AngleOfAttack"])

	return ball_data
