extends Object
class_name ShotFormatter

# Formats ball/shot data for UI display, with unit conversion and derived spin/club delivery metrics.
# If show_distance is false, Distance is left unchanged from prev_data (or set to "---" if not provided).
static func format_ball_display(raw_ball_data: Dictionary, player: Node, units: int, show_distance: bool, prev_data: Dictionary = {}) -> Dictionary:
	var ball_data: Dictionary = {}
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
	
	var raw_speed_mph := float(raw_ball_data.get("Speed", 0.0))
	var raw_vla := float(raw_ball_data.get("VLA", 0.0))
	var raw_hla := float(raw_ball_data.get("HLA", 0.0))

	# --- 1. Ball & Distance Metrics ---
	if units == PhysicsEnums.Units.IMPERIAL:
		if show_distance:
			ball_data["Distance"] = "%.1f" % (player.get_distance() * m2yd)
		else:
			ball_data["Distance"] = prev_data.get("Distance", "---")
		var carry_val = player.carry
		if carry_val <= 0 and raw_ball_data.has("CarryDistance"):
			carry_val = raw_ball_data.get("CarryDistance", 0.0) as float
		ball_data["Carry"] = "%.1f" % (carry_val * m2yd)
		ball_data["Apex"] = "%.1f" % (player.apex * 3.28084)
		var side_distance = player.get_side_distance() * m2yd
		var side_text := "R"
		if side_distance < 0:
			side_text = "L"
		side_text += ("%.1f" % abs(side_distance))
		ball_data["Offline"] = side_text
		ball_data["Speed"] = "%.1f" % raw_speed_mph
	else:
		if show_distance:
			ball_data["Distance"] = "%.1f" % player.get_distance()
		else:
			ball_data["Distance"] = prev_data.get("Distance", "---")
		var carry_val = player.carry
		if carry_val <= 0 and raw_ball_data.has("CarryDistance"):
			carry_val = raw_ball_data.get("CarryDistance", 0.0) as float
		ball_data["Carry"] = "%.1f" % carry_val
		ball_data["Apex"] = "%.1f" % player.apex
		var side_distance = player.get_side_distance()
		var side_text := "R"
		if side_distance < 0:
			side_text = "L"
		side_text += ("%.1f" % abs(side_distance))
		ball_data["Offline"] = side_text
		ball_data["Speed"] = "%.1f" % (raw_speed_mph * 0.44704)
	
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
		descent_deg = clampf(raw_vla * 1.45 + (player.apex * 0.15), 15.0, 60.0)
	ball_data["DescentAngle"] = "%.1f" % descent_deg

	# --- 3. Club Delivery Metrics ---
	# Club Face Angle
	var face_angle := 0.0
	if raw_ball_data.has("FaceAngle"):
		face_angle = float(raw_ball_data.get("FaceAngle", 0.0))
	elif raw_ball_data.has("ClubFaceAngle"):
		face_angle = float(raw_ball_data.get("ClubFaceAngle", 0.0))
	elif raw_ball_data.has("FaceToTarget"):
		face_angle = float(raw_ball_data.get("FaceToTarget", 0.0))
	else:
		# Estimate face angle using launch direction and spin axis
		face_angle = raw_hla * 0.75 + (spin_axis * 0.15)
	
	if abs(face_angle) < 0.1:
		ball_data["FaceAngle"] = "0.0 Sq"
	elif face_angle > 0.0:
		ball_data["FaceAngle"] = "%.1f O" % face_angle
	else:
		ball_data["FaceAngle"] = "%.1f C" % abs(face_angle)

	# Club Path
	var club_path := 0.0
	if raw_ball_data.has("ClubPath"):
		club_path = float(raw_ball_data.get("ClubPath", 0.0))
	elif raw_ball_data.has("Path"):
		club_path = float(raw_ball_data.get("Path", 0.0))
	else:
		club_path = (raw_hla - face_angle * 0.75) / 0.25

	if abs(club_path) < 0.1:
		ball_data["ClubPath"] = "0.0 Str"
	elif club_path > 0.0:
		ball_data["ClubPath"] = "%.1f In-Out" % club_path
	else:
		ball_data["ClubPath"] = "%.1f Out-In" % abs(club_path)

	# Face to Path
	var face_to_path := face_angle - club_path
	if raw_ball_data.has("FaceToPath"):
		face_to_path = float(raw_ball_data.get("FaceToPath", 0.0))
	if abs(face_to_path) < 0.1:
		ball_data["FaceToPath"] = "0.0 Sq"
	elif face_to_path > 0.0:
		ball_data["FaceToPath"] = "%.1f O" % face_to_path
	else:
		ball_data["FaceToPath"] = "%.1f C" % abs(face_to_path)

	# Attack Angle (AoA)
	var attack_angle := 0.0
	if raw_ball_data.has("AttackAngle"):
		attack_angle = float(raw_ball_data.get("AttackAngle", 0.0))
	elif raw_ball_data.has("AngleOfAttack"):
		attack_angle = float(raw_ball_data.get("AngleOfAttack", 0.0))
	else:
		if raw_vla >= 14.0:
			attack_angle = clampf((raw_vla - 12.0) * 0.35, -1.0, 4.5)
		else:
			attack_angle = clampf((raw_vla - 16.0) * 0.30, -6.0, 0.0)
	ball_data["AttackAngle"] = ("+%.1f" % attack_angle) if attack_angle > 0.0 else ("%.1f" % attack_angle)

	# Dynamic Loft
	var dynamic_loft := 0.0
	if raw_ball_data.has("DynamicLoft"):
		dynamic_loft = float(raw_ball_data.get("DynamicLoft", 0.0))
	else:
		dynamic_loft = max(8.0, raw_vla * 0.85 + 2.0)
	ball_data["DynamicLoft"] = "%.1f" % dynamic_loft

	# Clubhead Speed & Smash Factor
	var smash_factor := 1.45
	if raw_ball_data.has("SmashFactor") and float(raw_ball_data.get("SmashFactor", 0.0)) > 0.5:
		smash_factor = float(raw_ball_data.get("SmashFactor", 0.0))
	elif raw_speed_mph > 130.0:
		smash_factor = 1.48
	elif raw_speed_mph > 100.0:
		smash_factor = 1.38
	elif raw_speed_mph > 60.0:
		smash_factor = 1.25
	else:
		smash_factor = 1.15

	var club_speed_mph := 0.0
	if raw_ball_data.has("ClubSpeed") and float(raw_ball_data.get("ClubSpeed", 0.0)) > 0.0:
		club_speed_mph = float(raw_ball_data.get("ClubSpeed", 0.0))
		if club_speed_mph > 0.0 and raw_speed_mph > 0.0:
			smash_factor = raw_speed_mph / club_speed_mph
	elif raw_speed_mph > 0.0:
		club_speed_mph = raw_speed_mph / smash_factor

	if units == PhysicsEnums.Units.IMPERIAL:
		ball_data["ClubSpeed"] = "%.1f" % club_speed_mph
	else:
		ball_data["ClubSpeed"] = "%.1f" % (club_speed_mph * 0.44704)
	
	ball_data["SmashFactor"] = "%.2f" % smash_factor

	return ball_data
