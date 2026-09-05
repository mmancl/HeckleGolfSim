extends RefCounted

# GolfSwingAnalyzer
# Comprehensive golf swing diagnostic engine combining:
# 1. Real launch monitor ballistic benchmarks (Smash Factor, AoA, Face-to-Path, Spin, Launch Angle)
#    tailored by club type according to professional standards (Golf Sim Depot guide).
# 2. In-depth 3D/2D MediaPipe skeleton wireframe kinematics analyzing setup squareness,
#    thoracic & pelvic rotation, X-factor coil, kinematic sequencing, early extension, and arm structure.
# 3. Cross-correlated unified diagnostic ranking that pairs ballistic symptoms with biomechanical root causes.

class_name GolfSwingAnalyzer

# =============================================================================
# 1. LAUNCH MONITOR BALLISTIC ANALYSIS (PHASE 1 - INSTANT DIAGNOSTICS)
# =============================================================================

## Analyzes launch monitor data immediately while wireframe computes in background.
## Evaluates Smash Factor, Face-to-Path, AoA, Spin Rate, Launch Window, and Club Path against club-specific benchmarks.
static func analyze_launch_monitor(shot_data: Dictionary) -> Array[Dictionary]:
	var recs: Array[Dictionary] = []
	if shot_data.is_empty():
		return recs

	var club_name: String = str(shot_data.get("Club", shot_data.get("club", "Driver")))
	var club_cat: String = _classify_club(club_name)
	var is_tee: bool = bool(shot_data.get("is_tee", shot_data.get("lie_type", "") == "teebox"))
	if not shot_data.has("is_tee") and not shot_data.has("lie_type"):
		is_tee = (club_cat == "driver")
	var lie_type: String = str(shot_data.get("lie_type", "teebox" if is_tee else "fairway")).to_lower()
	var club_disp: String = get_club_display_name(club_name)
	var lie_disp: String = "Tee Shot" if is_tee else ("Fairway" if lie_type == "fairway" else lie_type.capitalize())

	# Ball & Club flight metrics
	var ball_speed: float = _get_float_val(shot_data, ["Speed", "BallSpeed"], 0.0)
	var club_speed: float = _get_float_val(shot_data, ["ClubSpeed"], 0.0)
	var smash_factor: float = _get_float_val(shot_data, ["SmashFactor"], 0.0)
	var vla: float = _get_float_val(shot_data, ["VLA", "VerticalLaunchAngle"], 14.0)
	var hla: float = _get_float_val(shot_data, ["HLA", "HorizontalLaunchAngle"], 0.0)
	var total_spin: float = _get_float_val(shot_data, ["TotalSpin", "BackSpin"], 0.0)
	var back_spin: float = _get_float_val(shot_data, ["BackSpin"], 0.0)
	var side_spin: float = _get_float_val(shot_data, ["SideSpin"], 0.0)
	var spin_axis: float = _get_float_val(shot_data, ["SpinAxis", "SideSpinAxis"], 0.0)
	
	# Derive spin axis from side spin if needed
	if not shot_data.has("SpinAxis") and (abs(side_spin) > 0.0 or abs(back_spin) > 0.0):
		if back_spin > 0.0:
			spin_axis = rad_to_deg(atan2(side_spin, back_spin))
		else:
			spin_axis = clamp(side_spin / 95.0, -25.0, 25.0)

	var attack_angle: float = _get_float_val(shot_data, ["AttackAngle", "AngleOfAttack"], 999.0) # 999 indicates not directly provided
	var club_path: float = _get_float_val(shot_data, ["ClubPath", "Path"], 0.0)
	var face_angle: float = _get_float_val(shot_data, ["FaceAngle", "ClubFaceAngle"], 0.0)
	var face_to_path: float = _get_float_val(shot_data, ["FaceToPath"], 999.0)
	if face_to_path > 900.0 and (shot_data.has("FaceAngle") or shot_data.has("ClubPath")):
		face_to_path = face_angle - club_path
	elif face_to_path > 900.0:
		# Estimate face to path from spin axis (every degree of face-to-path produces ~2.2° spin axis)
		face_to_path = spin_axis / 2.2

	var carry: float = _get_float_val(shot_data, ["Carry", "CarryDistance", "Distance", "TotalDistance"], 0.0)

	# Estimate smash factor if missing but speeds available
	if smash_factor <= 0.5 and ball_speed > 0.0 and club_speed > 0.0:
		smash_factor = ball_speed / club_speed

	# ─── 1. SMASH FACTOR & IMPACT EFFICIENCY (TOP PRIORITY FOR DISTANCE & CONSISTENCY) ───
	if smash_factor > 0.5:
		var target_smash_min: float = 1.44
		var target_smash_max: float = 1.50
		var bench_desc: String = "1.45–1.50 (Pro Benchmark)"
		var crit_thresh: float = 1.38

		if club_cat == "mid_iron":
			target_smash_min = 1.33
			target_smash_max = 1.38
			bench_desc = "1.33–1.38 (Solid Iron Compression)"
			crit_thresh = 1.25
		elif club_cat == "long_iron":
			target_smash_min = 1.35
			target_smash_max = 1.42
			bench_desc = "1.35–1.42 (Long Iron Strike)"
			crit_thresh = 1.28
		elif club_cat == "wedge":
			target_smash_min = 1.20
			target_smash_max = 1.28
			bench_desc = "1.20–1.28 (Controlled Wedge Strike)"
			crit_thresh = 1.15
		elif club_cat == "wood":
			target_smash_min = 1.40
			target_smash_max = 1.48
			bench_desc = "1.40–1.48 (Fairway Wood)"
			crit_thresh = 1.33
		elif club_cat == "hybrid":
			target_smash_min = 1.36
			target_smash_max = 1.44
			bench_desc = "1.36–1.44 (Hybrid Strike)"
			crit_thresh = 1.30

		var fix_inst = "Focus on centered face contact before swinging faster. Smooth out your transition to find the middle of the clubface."
		var drill_inst = "⛳ Impact Tape / Dry Erase Drill: Spray clubface with dry-shampoo or impact decal; confirm strike is centered on sweet spot."
		if club_cat in ["wood", "hybrid"]:
			fix_inst = "Focus on centered face contact with a smooth sweeping delivery through the turf rather than swinging harder."
			drill_inst = "⛳ Sweet Spot Impact Spray: Spray clubface to confirm ball contact is centered without catching the ground early."
		elif club_cat in ["mid_iron", "long_iron", "wedge"]:
			fix_inst = "Focus on centered face contact and compressing the ball before taking turf."
			drill_inst = "⛳ Strike Decal Drill: Spray clubface to ensure impact is centered in grooves 3 through 6."

		if smash_factor < crit_thresh:
			var yards_lost: int = int((target_smash_min - smash_factor) * (club_speed if club_speed > 0 else 95.0) * 1.5)
			yards_lost = clamp(yards_lost, 12, 35)
			recs.append({
				"priority": 1,
				"score": 96,
				"severity": "CRITICAL",
				"category": "STRIKE EFFICIENCY & SMASH",
				"issue_type": "Low Smash Factor",
				"title": "Low %s Smash Factor (%.2f vs %s)" % [club_disp, smash_factor, bench_desc],
				"camera_flaw": "Off-center strike contact detected on %s." % club_disp,
				"launch_effect": "Off-center impact (toe/heel/low) leaking approx %d yards of potential carry." % yards_lost,
				"player_val": "Smash Factor: %.2f | Ball Speed: %.1f mph" % [smash_factor, ball_speed],
				"benchmark_val": "Target: %s" % bench_desc,
				"fix_instruction": fix_inst,
				"drill": drill_inst
			})
		elif smash_factor < target_smash_min:
			recs.append({
				"priority": 2,
				"score": 82,
				"severity": "HIGH",
				"category": "STRIKE EFFICIENCY & SMASH",
				"issue_type": "Sub-Optimal Smash Factor",
				"title": "Sub-Optimal %s Efficiency (%.2f Smash)" % [club_disp, smash_factor],
				"camera_flaw": "Slightly off-center strike contact reducing energy transfer.",
				"launch_effect": "Transfer ratio below optimal %s; ball speed could increase by 4-8 mph with centered contact." % bench_desc,
				"player_val": "Smash Factor: %.2f" % smash_factor,
				"benchmark_val": "Target: %s" % bench_desc,
				"fix_instruction": "Maintain steady head position through the strike and check ball position relative to stance.",
				"drill": "⛳ Gate Drill: Place two markers just wider than clubhead; swing cleanly through the gate."
			})

	# ─── 2. FACE-TO-PATH & SPIN AXIS (PRIMARY ACCURACY & CURVATURE GOVERNOR) ───
	var is_severe_slice: bool = spin_axis > 8.0 or face_to_path > 3.5
	var is_mild_slice: bool = spin_axis > 4.0 or face_to_path > 2.0
	var is_severe_hook: bool = spin_axis < -8.0 or face_to_path < -3.5
	var is_mild_hook: bool = spin_axis < -4.0 or face_to_path < -2.0

	if is_severe_slice:
		var path_str = ("%.1f° Out-to-In" % abs(club_path)) if club_path < 0 else ("%.1f° In-to-Out" % club_path)
		recs.append({
			"priority": 1,
			"score": 94 + int(abs(spin_axis) * 0.4),
			"severity": "CRITICAL",
			"category": "CLUB FACE & SWING PATH",
			"issue_type": "Slice / Open Face-to-Path",
			"title": "Open Face Relative to Path (+%.1f° Spin Axis Slice)" % spin_axis,
			"camera_flaw": "Clubface delivered open relative to swing path at impact.",
			"launch_effect": "Face-to-Path of %+.1f° creates heavy clockwise sidespin, slicing ball offline right." % face_to_path,
			"player_val": "Spin Axis: +%.1f° | Face-to-Path: %+.1f° | Path: %s" % [spin_axis, face_to_path, path_str],
			"benchmark_val": "Target: -2.0° to +2.0° Face-to-Path | ±3.0° Axis",
			"fix_instruction": "Strengthen lead hand grip slightly. At transition, shallow the club onto an inside delivery path and rotate trail forearm through impact.",
			"drill": "⛳ Headcover Barrier Drill: Place a clubhead cover 5 inches outside the ball to groove an inside-to-out swing path."
		})
	elif is_mild_slice:
		recs.append({
			"priority": 2,
			"score": 78,
			"severity": "HIGH",
			"category": "CLUB FACE & SWING PATH",
			"issue_type": "Fade / Open Face",
			"title": "Slightly Open Face-to-Path (+%.1f° Axis Fade)" % spin_axis,
			"camera_flaw": "Face open relative to swing path producing mild fade spin.",
			"launch_effect": "Gentle curve to the right (+%.1f° spin axis); monitor face angle at impact." % spin_axis,
			"player_val": "Spin Axis: +%.1f° | Face-to-Path: %+.1f°" % [spin_axis, face_to_path],
			"benchmark_val": "Target: ±2.0° Face-to-Path",
			"fix_instruction": "Ensure clubface is square at address and maintain quiet wrists through the takeaway.",
			"drill": "⛳ Alignment Stick Gate: Practice launching ball along target line between two alignment rods."
		})
	elif is_severe_hook:
		recs.append({
			"priority": 1,
			"score": 92 + int(abs(spin_axis) * 0.4),
			"severity": "CRITICAL",
			"category": "CLUB FACE & SWING PATH",
			"issue_type": "Hook / Closed Face-to-Path",
			"title": "Closed Face Relative to Path (%.1f° Spin Axis Hook)" % spin_axis,
			"camera_flaw": "Clubface closed relative to path, causing rapid leftward curvature.",
			"launch_effect": "Face-to-Path of %+.1f° produces counter-clockwise sidespin hook taking ball left." % face_to_path,
			"player_val": "Spin Axis: %.1f° | Face-to-Path: %+.1f°" % [spin_axis, face_to_path],
			"benchmark_val": "Target: -2.0° to +2.0° Face-to-Path | ±3.0° Axis",
			"fix_instruction": "Check that grip is not excessively strong. Rotate chest and torso through impact rather than flipping hands early.",
			"drill": "⛳ Split-Hand Drill: Hold grip with 3-inch gap between hands; practice turning chest through without flipping wrists."
		})
	elif is_mild_hook:
		recs.append({
			"priority": 3,
			"score": 74,
			"severity": "MEDIUM",
			"category": "CLUB FACE & SWING PATH",
			"issue_type": "Draw / Closed Face",
			"title": "Moderate Draw Curvature (%.1f° Spin Axis)" % spin_axis,
			"camera_flaw": "Face delivered slightly closed relative to path.",
			"launch_effect": "Ball draws left of intended flight line.",
			"player_val": "Spin Axis: %.1f° | Face-to-Path: %+.1f°" % [spin_axis, face_to_path],
			"benchmark_val": "Target: ±2.0° Face-to-Path",
			"fix_instruction": "Keep trail wrist extended slightly longer through impact zone.",
			"drill": "⛳ Towel Drill: Hold towel across chest with arms to synchronize upper body rotation."
		})

	# ─── 3. ANGLE OF ATTACK (AOA) OPTIMIZATION ───
	if attack_angle < 900.0:
		if club_cat == "driver":
			if is_tee:
				if attack_angle < -1.5:
					var spin_penalty = int(abs(attack_angle - 2.5) * 260)
					var yds_gain = int(abs(attack_angle - 2.5) * 4.5)
					yds_gain = clamp(yds_gain, 12, 28)
					recs.append({
						"priority": 2,
						"score": 88,
						"severity": "HIGH",
						"category": "LAUNCH CONDITIONS & AOA",
						"issue_type": "Steep Driver Attack Angle",
						"title": "Negative Driver Attack Angle (%.1f° Downward on Tee)" % attack_angle,
						"camera_flaw": "Hitting down on driver steepens spin and robs carry distance.",
						"launch_effect": "Adds ~%d RPM excessive spin; hitting UP (+1° to +5°) unlocks +%d yds carry." % [spin_penalty, yds_gain],
						"player_val": "AoA: %.1f° | Total Spin: %.0f RPM" % [attack_angle, total_spin],
						"benchmark_val": "Driver Tee Target: +1.0° to +5.0° (Upward)",
						"fix_instruction": "Tee ball forward off inside of lead heel. Tilt spine 6°–10° away from target at address to sweep upward on the teed ball.",
						"drill": "⛳ Empty Box Drill: Place an empty golf ball box 12 inches in front of tee; hit drive without touching box."
					})
			else:
				# Driver off the deck / turf
				if attack_angle < -3.5:
					recs.append({
						"priority": 2,
						"score": 85,
						"severity": "HIGH",
						"category": "LAUNCH CONDITIONS & AOA",
						"issue_type": "Steep Driver Off Turf",
						"title": "Steep Driver Strike Off Turf (%.1f° AoA)" % attack_angle,
						"camera_flaw": "Steep angle of attack digging into turf with driver.",
						"launch_effect": "Off-the-deck driver requires a level sweep; chopping down causes severe distance loss.",
						"player_val": "AoA: %.1f°" % attack_angle,
						"benchmark_val": "Turf Driver Target: -1.0° to +1.0° (Level)",
						"fix_instruction": "Sweep the ball cleanly off the grass with a level shoulder rotation. Do not hit down steeply.",
						"drill": "⛳ Sweeping Brush Drill: Practice clipping the grass smoothly without gouging turf."
					})
		elif club_cat == "wood":
			if is_tee:
				# Wood off tee
				if attack_angle < -2.5:
					recs.append({
						"priority": 2,
						"score": 84,
						"severity": "HIGH",
						"category": "LAUNCH CONDITIONS & AOA",
						"issue_type": "Steep Wood Tee Shot",
						"title": "Steep Attack Angle on Teed %s (%.1f° Downward)" % [club_disp, attack_angle],
						"camera_flaw": "Chopping down into teed fairway wood.",
						"launch_effect": "Spins up excessively and loses penetration into the wind.",
						"player_val": "AoA: %.1f°" % attack_angle,
						"benchmark_val": "Teed Wood Target: -1.0° to +1.5° (Sweeping)",
						"fix_instruction": "Peg the ball low (only 1/4 of ball above crown). Sweep cleanly through impact with a shallow path.",
						"drill": "⛳ Low Peg Drill: Push tee into ground until ball is barely floating above grass blades."
					})
			else:
				# Wood off turf / fairway / rough (NO TEE!)
				if attack_angle > 0.8:
					recs.append({
						"priority": 2,
						"score": 88,
						"severity": "HIGH",
						"category": "LAUNCH CONDITIONS & AOA",
						"issue_type": "Scooping Wood Off Turf",
						"title": "Scooping %s Off Turf (+%.1f° Upward AoA)" % [club_disp, attack_angle],
						"camera_flaw": "Torso hung back trying to lift the fairway wood off the turf into the air.",
						"launch_effect": "Hitting up on a fairway wood off the turf causes thin, topped, or chunked contact.",
						"player_val": "AoA: %+.1f° (Upward) | VLA: %.1f°" % [attack_angle, vla],
						"benchmark_val": "Optimal Turf Wood: -1.0° to -3.0° (Shallow Brush)",
						"fix_instruction": "Do not try to lift or hit up on the ball. Trust the club's built-in loft! Position ball 1-2 balls inside lead heel and sweep the turf with a wide, level bottom arc.",
						"drill": "⛳ Sweeping Coin Drill: Place a coin or leaf 2 inches ahead of ball; sweep through impact brushing the coin forward along the grass."
					})
				elif attack_angle < -4.5:
					recs.append({
						"priority": 2,
						"score": 85,
						"severity": "HIGH",
						"category": "LAUNCH CONDITIONS & AOA",
						"issue_type": "Steep Wood Off Turf",
						"title": "Steep Strike on %s (%.1f° Downward AoA)" % [club_disp, attack_angle],
						"camera_flaw": "Downswing plane too steep into turf for a fairway wood.",
						"launch_effect": "Digs into the turf, producing excessive spin ballooning and lost rollout.",
						"player_val": "AoA: %.1f° (Steep) | Total Spin: %.0f RPM" % [attack_angle, total_spin],
						"benchmark_val": "Optimal Turf Wood: -1.0° to -3.0° (Shallow Brush)",
						"fix_instruction": "Shallow out your transition. Keep shoulders level and feel the clubhead gliding through the turf rather than chopping into it.",
						"drill": "⛳ Brush the Grass Drill: Rehearse wide practice swings skimming the grass blades without disturbing the soil."
					})
		elif club_cat == "hybrid":
			if not is_tee and attack_angle > 0.5:
				recs.append({
					"priority": 2,
					"score": 85,
					"severity": "HIGH",
					"category": "LAUNCH CONDITIONS & AOA",
					"issue_type": "Scooping Hybrid Off Turf",
					"title": "Scooping Hybrid (+%.1f° Upward AoA)" % attack_angle,
					"camera_flaw": "Trying to lift hybrid off turf instead of hitting down with forward compression.",
					"launch_effect": "Thin contact and loss of compression.",
					"player_val": "AoA: %+.1f°" % attack_angle,
					"benchmark_val": "Hybrid Target: -2.0° to -4.0° (Descending Strike)",
					"fix_instruction": "Treat the hybrid like a 5-iron: strike slightly down on the ball before brushing the grass.",
					"drill": "⛳ Towel Behind Ball: Lay a towel 3 inches behind ball; strike ball without touching towel."
				})
			elif attack_angle < -5.5:
				recs.append({
					"priority": 2,
					"score": 82,
					"severity": "HIGH",
					"category": "LAUNCH CONDITIONS & AOA",
					"issue_type": "Steep Hybrid Strike",
					"title": "Steep Hybrid Strike (%.1f° AoA)" % attack_angle,
					"camera_flaw": "Steep downswing angle causing fat contact.",
					"launch_effect": "Excess spin and lost distance.",
					"player_val": "AoA: %.1f°" % attack_angle,
					"benchmark_val": "Hybrid Target: -2.0° to -4.0°",
					"fix_instruction": "Widen your swing arc and sweep through turf smoothly.",
					"drill": "⛳ Smooth Sweeping Practice: Make rhythm swings focusing on shallow turf contact."
				})
		elif club_cat in ["mid_iron", "long_iron", "wedge"]:
			if attack_angle > 0.5:
				var c_type = "Iron" if club_cat != "wedge" else "Wedge"
				var targ_range = "-3.0° to -5.0°" if club_cat != "wedge" else "-4.0° to -6.5°"
				recs.append({
					"priority": 2,
					"score": 85,
					"severity": "HIGH",
					"category": "LAUNCH CONDITIONS & AOA",
					"issue_type": "Scooping / Upward %s AoA" % c_type,
					"title": "Positive Attack Angle on %s (+%.1f° Scooping)" % [c_type, attack_angle],
					"camera_flaw": "Hitting up on iron/wedge leads to thin contact and lost compression.",
					"launch_effect": "Causes thin strikes, inconsistent turf interaction, and insufficient green-stopping spin.",
					"player_val": "AoA: %+.1f° | Launch Angle: %.1f°" % [attack_angle, vla],
					"benchmark_val": "Optimal %s AoA: %s (Downward)" % [c_type, targ_range],
					"fix_instruction": "Position ball center of stance, transfer 60% weight to lead foot at impact, and strike ball before turf.",
					"drill": "⛳ Towel Behind Ball: Lay a small towel 3 inches behind ball; strike ball crisply without touching towel."
				})

	# ─── 4. SPIN RATE HARMONY (BALLOONING VS KNUCKLEBALL) ───
	if total_spin > 0.0:
		if club_cat == "driver":
			if total_spin > 3000.0:
				var drill_desc = "⛳ High Tee Drill: Tee ball up half a ball higher to encourage contact on upper quadrant of face." if is_tee else "⛳ Centered Strike Drill: Spray clubface to confirm contact is centered, avoiding low-face strikes."
				var fix_desc = "Strike higher on clubface (above center creates gear effect reducing spin). Ensure driver attack angle is positive." if is_tee else "Sweep cleanly off turf and ensure centered impact to avoid low-face spin multiplication."
				recs.append({
					"priority": 3,
					"score": 77,
					"severity": "MEDIUM",
					"category": "SPIN DYNAMICS",
					"issue_type": "Excessive Driver Spin",
					"title": "Excessive Driver Spin (%.0f RPM Ballooning)" % total_spin,
					"camera_flaw": "High spin rate produces steep climb and eliminates fairway rollout.",
					"launch_effect": "Ball balloons into wind, losing 15-25 yards of total distance.",
					"player_val": "Spin: %.0f RPM (Optimal: 2,000–2,600 RPM)" % total_spin,
					"benchmark_val": "Driver Target: 2,000–2,600 RPM",
					"fix_instruction": fix_desc,
					"drill": drill_desc
				})
			elif total_spin < 1700.0 and ball_speed > 110.0:
				var drill_desc = "⛳ Level Strike Practice: Verify ball rests at center equator on driver face at address." if is_tee else "⛳ Centered Face Strike: Verify ball strikes middle groove on clubface."
				var fix_desc = "Check launch angle and strike height. Slightly lower tee height if hitting too high on face." if is_tee else "Check launch angle and strike height. Avoid hitting high on the crown."
				recs.append({
					"priority": 3,
					"score": 70,
					"severity": "MEDIUM",
					"category": "SPIN DYNAMICS",
					"issue_type": "Insufficient Driver Spin",
					"title": "Low Driver Spin Rate (%.0f RPM Knuckleball)" % total_spin,
					"camera_flaw": "Insufficient backspin to maintain aerodynamic lift.",
					"launch_effect": "Ball drops out of sky early, reducing airborne carry.",
					"player_val": "Spin: %.0f RPM" % total_spin,
					"benchmark_val": "Target: 2,000–2,600 RPM",
					"fix_instruction": fix_desc,
					"drill": drill_desc
				})
		elif club_cat == "wood":
			var wood_min_spin = 2600.0 if is_tee else 3000.0
			var wood_max_spin = 3800.0 if is_tee else 4400.0
			var wood_bench = "2,800–3,600 RPM (Tee Shot)" if is_tee else "3,200–4,200 RPM (Off Turf)"
			if total_spin > wood_max_spin + 400.0:
				recs.append({
					"priority": 3,
					"score": 76,
					"severity": "MEDIUM",
					"category": "SPIN DYNAMICS",
					"issue_type": "Excessive Wood Spin",
					"title": "Excessive %s Spin (%.0f RPM Ballooning)" % [club_disp, total_spin],
					"camera_flaw": "Chopping attack angle or low-face contact imparting excessive backspin.",
					"launch_effect": "Shot balloons into the wind and stops dead with zero rollout.",
					"player_val": "Spin: %.0f RPM (%s)" % [total_spin, wood_bench],
					"benchmark_val": "Target: %s" % wood_bench,
					"fix_instruction": "Shallow out your downswing. A level sweeping contact through the ball creates penetrating ball flight with optimal roll.",
					"drill": "⛳ Wide Arc Drill: Keep wrists firm and swing through with a wide sweeping extension through impact."
				})
			elif total_spin < wood_min_spin - 600.0 and ball_speed > 90.0:
				recs.append({
					"priority": 3,
					"score": 70,
					"severity": "MEDIUM",
					"category": "SPIN DYNAMICS",
					"issue_type": "Low Wood Spin",
					"title": "Low %s Spin (%.0f RPM Knuckleball)" % [club_disp, total_spin],
					"camera_flaw": "Ball struck too high on crown or severe delofting.",
					"launch_effect": "Ball lacks enough backspin lift and falls prematurely out of the air.",
					"player_val": "Spin: %.0f RPM" % total_spin,
					"benchmark_val": "Target: %s" % wood_bench,
					"fix_instruction": "Catch ball centered on the sweet spot. Avoid forward-pressing shaft excessively at address.",
					"drill": "⛳ Center Strike Verification: Check face contact marks to ensure strike is not on the upper crown."
				})
		elif club_cat == "hybrid":
			if total_spin > 5200.0:
				recs.append({
					"priority": 3,
					"score": 74,
					"severity": "MEDIUM",
					"category": "SPIN DYNAMICS",
					"issue_type": "High Hybrid Spin",
					"title": "Excessive Hybrid Spin (%.0f RPM Ballooning)" % total_spin,
					"camera_flaw": "Glancing strike or steep descending blow.",
					"launch_effect": "Shot climbs steeply and loses penetrating carry.",
					"player_val": "Spin: %.0f RPM" % total_spin,
					"benchmark_val": "Target: 3,800–4,800 RPM",
					"fix_instruction": "Smooth out transition to shallow approach path and strike centered.",
					"drill": "⛳ Sweeping Mat Drill: Swing with smooth tempo, brushing mat without digging."
				})
		elif club_cat == "mid_iron":
			if total_spin < 4800.0 and total_spin > 1000.0:
				recs.append({
					"priority": 3,
					"score": 75,
					"severity": "MEDIUM",
					"category": "SPIN DYNAMICS",
					"issue_type": "Low Iron Spin",
					"title": "Low %s Spin (%.0f RPM Won't Hold Green)" % [club_disp, total_spin],
					"camera_flaw": "Insufficient backspin to stop approach shots on greens.",
					"launch_effect": "Ball will land flat and roll out off green rather than checking up.",
					"player_val": "Spin: %.0f RPM (Target: 6,000–7,000 RPM)" % total_spin,
					"benchmark_val": "Target: 6,000–7,000 RPM (Rule of Thumb: Club # × 1,000)",
					"fix_instruction": "Hit down on ball with forward shaft lean to compress grooves against ball cover.",
					"drill": "⛳ Impact Bag Drill: Practice hitting into impact bag with hands leading clubhead."
				})

	# ─── 5. LAUNCH ANGLE WINDOW (VLA) ───
	if club_cat == "driver":
		if vla < 9.5 and vla > 3.0:
			var drill_desc = "⛳ High Launch Gate: Imagine hitting over a 15-foot crossbar located 30 yards ahead." if is_tee else "⛳ Sweeping Arc: Rehearse level sweeping strikes without delofting."
			var fix_desc = "Tee ball slightly higher and ensure head stays behind ball through impact." if is_tee else "Check ball position inside lead heel and ensure chest is not leaning forward ahead of ball."
			recs.append({
				"priority": 4,
				"score": 69,
				"severity": "MEDIUM",
				"category": "LAUNCH WINDOW",
				"issue_type": "Low Driver Launch",
				"title": "Low Driver Launch Angle (%.1f° vs 11°–14.5° Optimal)" % vla,
				"camera_flaw": "Takeoff trajectory too low to optimize carry flight.",
				"launch_effect": "Limits apex height and carry distance; ball lands prematurely.",
				"player_val": "VLA: %.1f°" % vla,
				"benchmark_val": "Target: 11.0°–14.5°",
				"fix_instruction": fix_desc,
				"drill": drill_desc
			})
		elif vla > 16.5:
			var drill_desc = "⛳ Level Peg Drill: Lower tee height until half the ball is above crown." if is_tee else "⛳ Stay Centered: Prevent scooping or hanging back on trail foot."
			var fix_desc = "Check for steep attack angle or ball teed excessively high." if is_tee else "Avoid scooping wrists before impact; keep lead wrist flat through strike."
			recs.append({
				"priority": 4,
				"score": 67,
				"severity": "MEDIUM",
				"category": "LAUNCH WINDOW",
				"issue_type": "High Driver Launch / Pop-up",
				"title": "High Driver Launch Trajectory (%.1f° VLA Pop-up)" % vla,
				"camera_flaw": "Excessive vertical launch angle creating steep ballooning apex.",
				"launch_effect": "Loss of forward penetration; susceptible to wind shear.",
				"player_val": "VLA: %.1f°" % vla,
				"benchmark_val": "Target: 11.0°–14.5°",
				"fix_instruction": fix_desc,
				"drill": drill_desc
			})
	elif club_cat == "wood":
		var min_vla = 9.5 if is_tee else 8.5
		var max_vla = 16.0 if is_tee else 15.0
		var bench_vla = "11.0°–15.0° (Teed Wood)" if is_tee else "10.0°–14.0° (Off Turf)"
		if vla < min_vla and vla > 2.0:
			recs.append({
				"priority": 4,
				"score": 71,
				"severity": "MEDIUM",
				"category": "LAUNCH WINDOW",
				"issue_type": "Low Wood Launch",
				"title": "Low Trajectory on %s (%.1f° VLA)" % [club_disp, vla],
				"camera_flaw": "Trajectory too flat off the %s to achieve maximum carry." % ("tee" if is_tee else "turf"),
				"launch_effect": "Ball trajectory cuts off early, costing 15–30 yards of airborne carry.",
				"player_val": "VLA: %.1f° (Optimal: %s)" % [vla, bench_vla],
				"benchmark_val": "Target: %s" % bench_vla,
				"fix_instruction": "Position ball 1-2 balls inside lead heel. Let the natural loft launch the ball—do not lean shaft excessively forward.",
				"drill": "⛳ Sweeper Drill: Focus on sweeping the grass smoothly without driving down into the turf."
			})
		elif vla > max_vla + 2.0:
			recs.append({
				"priority": 4,
				"score": 68,
				"severity": "MEDIUM",
				"category": "LAUNCH WINDOW",
				"issue_type": "High Wood Launch / Scoop",
				"title": "High Ballooning Launch on %s (%.1f° VLA)" % [club_disp, vla],
				"camera_flaw": "Flipping wrists or scooping up on the ball at impact.",
				"launch_effect": "Steep launch angle catches wind and drops straight down with no rollout.",
				"player_val": "VLA: %.1f°" % vla,
				"benchmark_val": "Target: %s" % bench_vla,
				"fix_instruction": "Maintain firm lead wrist through impact. Rotate body through to lead side rather than flipping hands.",
				"drill": "⛳ Flat Wrist Impact Drill: Practice short punch shots keeping lead wrist flat and pointing at target."
			})

	# ─── 6. SWING PATH & HORIZONTAL LAUNCH DIRECTION (HLA) ───
	if abs(hla) > 3.2:
		var dir_str = "Push Right" if hla > 0 else "Pull Left"
		recs.append({
			"priority": 4,
			"score": 65,
			"severity": "MEDIUM",
			"category": "AIM & ALIGNMENT",
			"issue_type": "Launch Direction Deviation",
			"title": "Horizontal Launch Off-Line (%s %+.1f°)" % [dir_str, hla],
			"camera_flaw": "Clubface oriented away from target line at moment of impact.",
			"launch_effect": "Initial takeoff starts %.1f° off center before spin takes effect." % abs(hla),
			"player_val": "HLA: %+.1f° (%s)" % [hla, dir_str],
			"benchmark_val": "Target: -1.5° to +1.5° HLA",
			"fix_instruction": "Verify stance and clubface alignment with target before beginning takeaway.",
			"drill": "⛳ Railway Alignment: Lay two clubs parallel pointing directly at your target."
		})

	# If no major flaws, acknowledge solid execution
	if recs.is_empty():
		recs.append({
			"priority": 1,
			"score": 30,
			"severity": "LOW",
			"category": "BALL FLIGHT MAINTENANCE",
			"issue_type": "Pure Ball Strike",
			"title": "Pro-Grade Ball Launch & Face Control!",
			"camera_flaw": "Clean contact and square club delivery.",
			"launch_effect": "Solid smash (%.2f), clean spin axis (%+.1f°), and carry (%.0f yds)." % [smash_factor, spin_axis, carry],
			"player_val": "Smash: %.2f | Spin Axis: %+.1f°" % [smash_factor, spin_axis],
			"benchmark_val": "Pro Benchmark: Matched",
			"fix_instruction": "Maintain consistent tempo, rhythm, and pre-shot visualization.",
			"drill": "⛳ Target Fairway Practice: Continue repeating your reliable baseline swing."
		})

	recs.sort_custom(func(a, b): return a["score"] > b["score"])
	for idx in range(recs.size()):
		recs[idx]["priority"] = idx + 1

	return recs


# =============================================================================
# 2. SKELETON WIREFRAME SEQUENCE BIOMECHANICS (PHASE 2)
# =============================================================================

## Analyzes the full frame sequence of landmarks to detect:
## - Address (P1): Shoulder tilt, shoulder & hip squareness/alignment
## - Top of Backswing (P4): Shoulder rotation, hip rotation, X-Factor coil, lateral sway, reverse spine tilt
## - Downswing Transition: Kinematic sequencing (hips clearing vs shoulder cast)
## - Impact (P7): Spine angle retention (early extension), hip clearance angle, shoulder alignment, lead arm structure
## Returns a detailed biomechanical dictionary.
static func analyze_skeleton_sequence(recorded_frames: Array[Dictionary], fallback_telemetry: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {
		"has_valid_data": false,
		"address_shoulder_tilt": 0.0,
		"address_shoulder_hip_alignment": 0.0, # degrees open/closed at setup
		"top_shoulder_turn": 0.0,
		"top_hip_turn": 0.0,
		"top_x_factor": 0.0,
		"top_hip_sway": 0.0,
		"top_reverse_spine_tilt": 0.0,
		"transition_shoulder_cast": false,
		"impact_spine_loss": 0.0,
		"impact_early_extension": 0.0,
		"impact_hip_clearance": 0.0, # degrees hips are open at impact
		"impact_chicken_wing": false,
		"lead_elbow_angle": 180.0,
		"flaws_detected": []
	}

	if recorded_frames.is_empty():
		if fallback_telemetry.get("has_valid_telemetry", false):
			result["has_valid_data"] = true
			result["top_shoulder_turn"] = fallback_telemetry.get("shoulder_turn", 0.0)
			result["impact_early_extension"] = fallback_telemetry.get("early_extension", 0.0)
			result["top_hip_sway"] = fallback_telemetry.get("hip_sway", 0.0)
			var m_spine = fallback_telemetry.get("spine_angle", 35.0)
			result["impact_spine_loss"] = max(0.0, 35.0 - m_spine)
		return result

	# Extract valid landmark frames
	var valid_frames: Array[Dictionary] = []
	for f in recorded_frames:
		var lms: Dictionary = f.get("landmarks", {})
		if lms.has("left_shoulder") and lms.has("right_shoulder") and lms.has("left_hip") and lms.has("right_hip"):
			valid_frames.append(f)

	if valid_frames.size() < 4:
		return result

	result["has_valid_data"] = true
	var total_f = valid_frames.size()

	# ─── 1. ADDRESS PHASE (P1) ───
	# Sample first 2-4 frames
	var addr_count: int = min(4, total_f / 4)
	var base_ls := Vector2.ZERO
	var base_rs := Vector2.ZERO
	var base_lh := Vector2.ZERO
	var base_rh := Vector2.ZERO
	var base_ls_z: float = 0.0
	var base_rs_z: float = 0.0

	for i in range(addr_count):
		var lm = valid_frames[i]["landmarks"]
		base_ls += Vector2(float(lm["left_shoulder"].get("x", 0)), float(lm["left_shoulder"].get("y", 0)))
		base_rs += Vector2(float(lm["right_shoulder"].get("x", 0)), float(lm["right_shoulder"].get("y", 0)))
		base_lh += Vector2(float(lm["left_hip"].get("x", 0)), float(lm["left_hip"].get("y", 0)))
		base_rh += Vector2(float(lm["right_hip"].get("x", 0)), float(lm["right_hip"].get("y", 0)))
		base_ls_z += float(lm["left_shoulder"].get("z", 0.0))
		base_rs_z += float(lm["right_shoulder"].get("z", 0.0))

	base_ls /= float(addr_count)
	base_rs /= float(addr_count)
	base_lh /= float(addr_count)
	base_rh /= float(addr_count)
	base_ls_z /= float(addr_count)
	base_rs_z /= float(addr_count)

	var base_s_mid = (base_ls + base_rs) * 0.5
	var base_h_mid = (base_lh + base_rh) * 0.5
	var torso_scale: float = max(0.01, base_s_mid.distance_to(base_h_mid))
	var base_shoulder_width: float = max(0.01, base_ls.distance_to(base_rs))
	var base_hip_width: float = max(0.01, base_lh.distance_to(base_rh))

	# Address Shoulder Tilt: Trail shoulder lower than lead shoulder
	# In screen coords, Y increases downward. (base_rs.y - base_ls.y) > 0 means trail shoulder lower.
	var shoulder_tilt_rad: float = atan2(base_rs.y - base_ls.y, abs(base_rs.x - base_ls.x))
	var addr_shoulder_tilt_deg: float = rad_to_deg(shoulder_tilt_rad)
	result["address_shoulder_tilt"] = addr_shoulder_tilt_deg

	# Address Shoulder vs Hip Squareness:
	var s_angle = rad_to_deg(atan2(base_rs.y - base_ls.y, base_rs.x - base_ls.x))
	var h_angle = rad_to_deg(atan2(base_rh.y - base_lh.y, base_rh.x - base_lh.x))
	var align_diff: float = s_angle - h_angle
	result["address_shoulder_hip_alignment"] = align_diff

	var base_spine_vec = base_s_mid - base_h_mid
	var base_spine_angle = rad_to_deg(atan2(abs(base_spine_vec.x), -base_spine_vec.y))

	# ─── 2. DETECT KEY SWING FRAMES (P4 TOP & P7 IMPACT) ───
	var top_idx: int = -1
	var min_wrist_y: float = 999.0
	var min_shoulder_w: float = 999.0

	var p4_search_limit: int = int(total_f * 0.65)
	for i in range(1, p4_search_limit):
		var lm = valid_frames[i]["landmarks"]
		var ls = Vector2(float(lm["left_shoulder"].get("x", 0)), float(lm["left_shoulder"].get("y", 0)))
		var rs = Vector2(float(lm["right_shoulder"].get("x", 0)), float(lm["right_shoulder"].get("y", 0)))
		var sw = ls.distance_to(rs)
		
		var wy: float = 999.0
		if lm.has("left_wrist"):
			wy = float(lm["left_wrist"].get("y", 999.0))
		if lm.has("right_wrist"):
			wy = min(wy, float(lm["right_wrist"].get("y", 999.0)))

		# Highest hands (lowest y) or greatest shoulder contraction
		if wy < min_wrist_y or (sw < min_shoulder_w and wy < 0.6):
			min_wrist_y = wy
			min_shoulder_w = sw
			top_idx = i

	if top_idx < 1:
		top_idx = clamp(int(total_f * 0.38), 1, total_f - 2)

	# Impact frame (P7) around 55% - 70%
	var impact_idx: int = clamp(int(total_f * 0.60), top_idx + 1, total_f - 1)

	# ─── 3. TOP OF BACKSWING (P4) KINEMATICS ───
	var top_lm = valid_frames[top_idx]["landmarks"]
	var top_ls = Vector2(float(top_lm["left_shoulder"].get("x", 0)), float(top_lm["left_shoulder"].get("y", 0)))
	var top_rs = Vector2(float(top_lm["right_shoulder"].get("x", 0)), float(top_lm["right_shoulder"].get("y", 0)))
	var top_lh = Vector2(float(top_lm["left_hip"].get("x", 0)), float(top_lm["left_hip"].get("y", 0)))
	var top_rh = Vector2(float(top_lm["right_hip"].get("x", 0)), float(top_lm["right_hip"].get("y", 0)))

	var top_sw: float = top_ls.distance_to(top_rs)
	var top_hw: float = top_lh.distance_to(top_rh)
	var top_s_mid = (top_ls + top_rs) * 0.5
	var top_h_mid = (top_lh + top_rh) * 0.5

	# Shoulder turn from cosine foreshortening + z
	var s_ratio = clamp(top_sw / base_shoulder_width, 0.0, 1.0)
	var top_s_turn = rad_to_deg(acos(s_ratio))
	# Z-depth refinement if present
	if top_lm["left_shoulder"].has("z") and top_lm["right_shoulder"].has("z"):
		var dz = abs(float(top_lm["left_shoulder"]["z"]) - float(top_lm["right_shoulder"]["z"]))
		var z_turn = rad_to_deg(atan2(dz, max(0.001, top_sw)))
		if z_turn > top_s_turn and z_turn < 120.0:
			top_s_turn = z_turn
	result["top_shoulder_turn"] = top_s_turn

	# Hip turn
	var h_ratio = clamp(top_hw / base_hip_width, 0.0, 1.0)
	var top_h_turn = rad_to_deg(acos(h_ratio))
	result["top_hip_turn"] = top_h_turn

	# X-Factor (Shoulder-Hip Separation)
	var x_factor = max(0.0, top_s_turn - top_h_turn)
	result["top_x_factor"] = x_factor

	# Lateral Hip Sway at Top
	var sway = ((top_h_mid.x - base_h_mid.x) / torso_scale) * 10.0
	result["top_hip_sway"] = sway

	# Reverse Spine Angle at Top
	# If shoulder midpoint leans towards target relative to hips
	var top_spine_vec = top_s_mid - top_h_mid
	var top_spine_tilt = rad_to_deg(atan2(top_spine_vec.x - base_spine_vec.x, -top_spine_vec.y))
	result["top_reverse_spine_tilt"] = top_spine_tilt

	# ─── 4. TRANSITION SEQUENCING (P4 -> P6) ───
	# Check if shoulders uncoil before hips move
	var shoulders_uncoiled_first: bool = false
	if top_idx + 2 < impact_idx:
		var mid_t_idx = top_idx + 1
		var mid_lm = valid_frames[mid_t_idx]["landmarks"]
		var mid_ls = Vector2(float(mid_lm["left_shoulder"].get("x", 0)), float(mid_lm["left_shoulder"].get("y", 0)))
		var mid_rs = Vector2(float(mid_lm["right_shoulder"].get("x", 0)), float(mid_lm["right_shoulder"].get("y", 0)))
		var mid_lh = Vector2(float(mid_lm["left_hip"].get("x", 0)), float(mid_lm["left_hip"].get("y", 0)))
		var mid_rh = Vector2(float(mid_lm["right_hip"].get("x", 0)), float(mid_lm["right_hip"].get("y", 0)))
		var mid_sw = mid_ls.distance_to(mid_rs)
		var mid_hw = mid_lh.distance_to(mid_rh)
		# If shoulder width expanded (uncoiled) before hip width expanded
		if (mid_sw - top_sw) > 0.02 and (mid_hw - top_hw) <= 0.005:
			shoulders_uncoiled_first = true
	result["transition_shoulder_cast"] = shoulders_uncoiled_first

	# ─── 5. IMPACT POSTURE & CLEARANCE (P7) ───
	var imp_lm = valid_frames[impact_idx]["landmarks"]
	var imp_ls = Vector2(float(imp_lm["left_shoulder"].get("x", 0)), float(imp_lm["left_shoulder"].get("y", 0)))
	var imp_rs = Vector2(float(imp_lm["right_shoulder"].get("x", 0)), float(imp_lm["right_shoulder"].get("y", 0)))
	var imp_lh = Vector2(float(imp_lm["left_hip"].get("x", 0)), float(imp_lm["left_hip"].get("y", 0)))
	var imp_rh = Vector2(float(imp_lm["right_hip"].get("x", 0)), float(imp_lm["right_hip"].get("y", 0)))
	var imp_s_mid = (imp_ls + imp_rs) * 0.5
	var imp_h_mid = (imp_lh + imp_rh) * 0.5

	# Early Extension (Pelvic thrust forward / spine angle rise)
	var imp_spine_vec = imp_s_mid - imp_h_mid
	var imp_spine_angle = rad_to_deg(atan2(abs(imp_spine_vec.x), -imp_spine_vec.y))
	var spine_loss = max(0.0, base_spine_angle - imp_spine_angle)
	result["impact_spine_loss"] = spine_loss

	var pelvic_thrust = ((base_h_mid.y - imp_h_mid.y) / torso_scale) * 10.0
	result["impact_early_extension"] = pelvic_thrust

	# Hip Clearance at Impact:
	# At impact, hips should be 30°–45° open to target line
	var imp_hw = imp_lh.distance_to(imp_rh)
	var imp_h_ratio = clamp(imp_hw / base_hip_width, 0.0, 1.0)
	var hip_clearance_deg = rad_to_deg(acos(imp_h_ratio))
	result["impact_hip_clearance"] = hip_clearance_deg

	# Lead Arm Chicken Wing Check:
	# Measure angle at left elbow (left_shoulder -> left_elbow -> left_wrist)
	if imp_lm.has("left_shoulder") and imp_lm.has("left_elbow") and imp_lm.has("left_wrist"):
		var le_s = Vector2(float(imp_lm["left_shoulder"].get("x", 0)), float(imp_lm["left_shoulder"].get("y", 0)))
		var le_e = Vector2(float(imp_lm["left_elbow"].get("x", 0)), float(imp_lm["left_elbow"].get("y", 0)))
		var le_w = Vector2(float(imp_lm["left_wrist"].get("x", 0)), float(imp_lm["left_wrist"].get("y", 0)))
		var v1 = (le_s - le_e).normalized()
		var v2 = (le_w - le_e).normalized()
		var elbow_angle = rad_to_deg(acos(clamp(v1.dot(v2), -1.0, 1.0)))
		result["lead_elbow_angle"] = elbow_angle
		if elbow_angle < 152.0:
			result["impact_chicken_wing"] = true

	return result


# =============================================================================
# 3. CROSS-CORRELATION & UNIFIED RANKING (PHASE 3)
# =============================================================================

## Combines launch monitor metrics with deep skeleton kinematics into a single
## ranked, prioritized list of swing recommendations.
static func analyze_shot_unified(shot_data: Dictionary, skeleton: Dictionary) -> Array[Dictionary]:
	var final_recs: Array[Dictionary] = []
	var lm_recs = analyze_launch_monitor(shot_data)

	if not skeleton.get("has_valid_data", false):
		return lm_recs

	var club_name: String = str(shot_data.get("Club", shot_data.get("club", "Driver")))
	var club_cat: String = _classify_club(club_name)
	var is_tee: bool = bool(shot_data.get("is_tee", shot_data.get("lie_type", "") == "teebox"))
	if not shot_data.has("is_tee") and not shot_data.has("lie_type"):
		is_tee = (club_cat == "driver")
	var lie_type: String = str(shot_data.get("lie_type", "teebox" if is_tee else "fairway")).to_lower()
	var club_disp: String = get_club_display_name(club_name)

	var spine_loss: float = skeleton.get("impact_spine_loss", 0.0)
	var early_ext: float = skeleton.get("impact_early_extension", 0.0)
	var s_turn: float = skeleton.get("top_shoulder_turn", 85.0)
	var h_turn: float = skeleton.get("top_hip_turn", 40.0)
	var x_factor: float = skeleton.get("top_x_factor", 45.0)
	var hip_sway: float = skeleton.get("top_hip_sway", 0.0)
	var shoulder_tilt: float = skeleton.get("address_shoulder_tilt", 8.0)
	var shoulder_align: float = skeleton.get("address_shoulder_hip_alignment", 0.0)
	var shoulder_cast: bool = skeleton.get("transition_shoulder_cast", false)
	var hip_clearance: float = skeleton.get("impact_hip_clearance", 35.0)
	var chicken_wing: bool = skeleton.get("impact_chicken_wing", false)

	var spin_axis: float = _get_float_val(shot_data, ["SpinAxis"], 0.0)
	var smash: float = _get_float_val(shot_data, ["SmashFactor"], 1.45)
	var aoa: float = _get_float_val(shot_data, ["AttackAngle", "AngleOfAttack"], 999.0)
	var ball_speed: float = _get_float_val(shot_data, ["Speed", "BallSpeed"], 0.0)
	var carry: float = _get_float_val(shot_data, ["Carry", "CarryDistance"], 0.0)

	var used_lm_types: Array[String] = []

	# ─── CORRELATION 1: SMASH FACTOR LOSS + EARLY EXTENSION ───
	var has_smash_issue: bool = (club_cat == "driver" and smash < 1.42) or (club_cat in ["wood", "hybrid"] and smash < 1.35) or (club_cat in ["mid_iron", "long_iron"] and smash < 1.30)
	var has_posture_loss: bool = early_ext > 1.8 or spine_loss > 6.0

	if has_smash_issue and has_posture_loss:
		used_lm_types.append("Low Smash Factor")
		used_lm_types.append("Sub-Optimal Smash Factor")
		final_recs.append({
			"priority": 1,
			"score": 98,
			"severity": "CRITICAL",
			"category": "POSTURE & STRIKE EFFICIENCY",
			"issue_type": "Early Extension Contact Loss",
			"title": "Early Extension Causing Off-Center Strike (%.2f Smash)" % smash,
			"camera_flaw": "Hips thrust %.1f units toward ball, losing %.1f° of address spine inclination into impact." % [early_ext, spine_loss],
			"launch_effect": "Standing up out of posture pulls sweet spot off ball center, leaking 15–30 yards.",
			"player_val": "Spine Angle Lost: %.1f° | Smash: %.2f" % [spine_loss, smash],
			"benchmark_val": "Pro Benchmark: < 3.0° Spine Loss | 1.48+ Smash",
			"fix_instruction": "Keep trail glute pressed back against an imaginary chair through the entire transition and impact zone.",
			"drill": "⛳ Chair / Wall Butt Drill: Touch lead hip to a chair behind you at address; keep hips in contact with chair until after impact."
		})
	elif has_posture_loss:
		final_recs.append({
			"priority": 2,
			"score": 86,
			"severity": "HIGH",
			"category": "BIOMECHANICS & POSTURE",
			"issue_type": "Early Extension",
			"title": "Early Extension (%.1f° Posture Inclination Lost)" % spine_loss,
			"camera_flaw": "Camera detected torso rising %.1f° out of address posture before strike." % spine_loss,
			"launch_effect": "Forces hands to flip to reach the ball, destabilizing face angle control.",
			"player_val": "Spine Loss: %.1f° | Forward Thrust: %.1f" % [spine_loss, early_ext],
			"benchmark_val": "Benchmark: Retain Address Posture (35° Spine)",
			"fix_instruction": "Stay down through the shot. Feel your chest looking down at the turf until the ball is airborne.",
			"drill": "⛳ Head-on-Wall Drill: Place forehead lightly against a soft cushion on a wall; rehearse slow-motion turn without lifting head."
		})

	# ─── CORRELATION 2: SLICE / OPEN FACE + OVER-THE-TOP SEQUENCE & SETUP ───
	var has_slice: bool = spin_axis > 5.0
	var has_ott_body: bool = shoulder_cast or shoulder_align > 5.0 or chicken_wing

	if has_slice and has_ott_body:
		used_lm_types.append("Slice / Open Face-to-Path")
		used_lm_types.append("Fade / Open Face")
		var cause_desc: String = ""
		if shoulder_cast:
			cause_desc += "Shoulders uncoiled ahead of hips on downswing. "
		if shoulder_align > 5.0:
			cause_desc += "Shoulders were %.1f° open at address setup. " % shoulder_align
		if chicken_wing:
			cause_desc += "Lead elbow collapsed to %.0f° (chicken wing). " % skeleton.get("lead_elbow_angle", 145.0)

		final_recs.append({
			"priority": 1,
			"score": 97,
			"severity": "CRITICAL",
			"category": "SWING PLANE & KINEMATICS",
			"issue_type": "Over-the-Top Slice",
			"title": "Over-The-Top Downswing (+%.1f° Spin Axis Slice)" % spin_axis,
			"camera_flaw": cause_desc.strip_edges(),
			"launch_effect": "Forces club onto out-to-in steep path with open face relative to path.",
			"player_val": "Spin Axis: +%.1f° | Shoulder Setup: %+.1f°" % [spin_axis, shoulder_align],
			"benchmark_val": "Target: -2° to +2° Path | Square Shoulders",
			"fix_instruction": "Square shoulders parallel to target line at setup. Start downswing by shifting weight onto lead heel, letting arms drop inside.",
			"drill": "⛳ Headcover Under Armpit: Place glove under trail armpit; hit balls keeping glove pinned until well after impact."
		})

	# ─── CORRELATION 3: DRIVER STEEP AOA + FLAT ADDRESS SHOULDERS / REVERSE TILT ───
	if club_cat == "driver" and is_tee and aoa < -1.0 and aoa > -20.0:
		if shoulder_tilt < 4.0:
			used_lm_types.append("Steep Driver Attack Angle")
			var yds_recov = int(abs(aoa - 3.0) * 4.2)
			yds_recov = clamp(yds_recov, 14, 28)
			final_recs.append({
				"priority": 2,
				"score": 89,
				"severity": "HIGH",
				"category": "SETUP & LAUNCH OPTIMIZATION",
				"issue_type": "Level Shoulders Causing Steep Driver Strike",
				"title": "Flat Setup Tilting Driver AoA (%.1f° Downward on Tee)" % aoa,
				"camera_flaw": "Shoulder tilt at address was only %.1f° (ideal: 8°–12° secondary spine tilt)." % shoulder_tilt,
				"launch_effect": "Prevents sweeping upward on ball; causes downward strike that kills ~%d yards." % yds_recov,
				"player_val": "Address Shoulder Tilt: %.1f° | AoA: %.1f°" % [shoulder_tilt, aoa],
				"benchmark_val": "Target: 8.0°–12.0° Tilt | +2.0° to +5.0° AoA",
				"fix_instruction": "At address, bump lead hip slightly toward target so spine tilts 8° away from target. Trail shoulder must sit lower than lead shoulder to hit upward on the teed ball.",
				"drill": "⛳ Zipper Tilt Drill: Hold club vertically against sternum; tilt upper body away from target until shaft points at inside of trail knee."
			})
	elif club_cat == "wood" and not is_tee and (aoa > 0.8 or spine_loss > 4.5):
		used_lm_types.append("Scooping Wood Off Turf")
		final_recs.append({
			"priority": 2,
			"score": 90,
			"severity": "HIGH",
			"category": "SETUP & FAIRWAY TURF SWEEP",
			"issue_type": "Hanging Back On Fairway Wood",
			"title": "Hanging Back on %s (%.1f° Spine Loss)" % [club_disp, spine_loss],
			"camera_flaw": "Body tilted backward and torso rose %.1f° out of posture trying to lift ball off turf." % spine_loss,
			"launch_effect": "Causes low-point to fall behind the ball, resulting in fat or topped fairway wood shots.",
			"player_val": "Spine Loss: %.1f° | AoA: %+.1f°" % [spine_loss, aoa],
			"benchmark_val": "Target: Retain Address Posture | -1.0° to -3.0° AoA",
			"fix_instruction": "Shift weight onto lead side during downswing. Keep your chest facing down toward the turf through impact and sweep the grass.",
			"drill": "⛳ Step-Through Drill: Step your trail foot forward toward target after striking fairway wood to ensure weight shifts fully onto lead side."
		})

	# ─── CORRELATION 4: RESTRICTED SHOULDER TURN & POWER LEAK ───
	if s_turn < 75.0:
		used_lm_types.append("Low Ball Speed")
		final_recs.append({
			"priority": 3,
			"score": 79,
			"severity": "MEDIUM",
			"category": "POWER & ROTATIONAL COIL",
			"issue_type": "Restricted Shoulder Turn",
			"title": "Restricted Shoulder Rotation (%.1f° vs 90° Benchmark)" % s_turn,
			"camera_flaw": "Camera measured only %.1f° of shoulder turn at top of backswing (X-Factor: %.1f°)." % [s_turn, x_factor],
			"launch_effect": "Shortens swing radius and limits coil energy, reducing potential ball speed.",
			"player_val": "Shoulder Turn: %.1f° | X-Factor: %.1f°" % [s_turn, x_factor],
			"benchmark_val": "Pro Benchmark: 90.0° Turn | 45.0° X-Factor",
			"fix_instruction": "Allow your lead heel to float slightly if needed, and focus on turning your lead shoulder fully behind the ball.",
			"drill": "⛳ Cross-Arm Chest Turn: Cross arms across shoulders and rotate until shaft points down toward ball line."
		})

	# ─── CORRELATION 5: LATERAL HIP SWAY ───
	if abs(hip_sway) > 3.0:
		var dir_txt = "away from target" if hip_sway < 0 else "toward target"
		final_recs.append({
			"priority": 3,
			"score": 73,
			"severity": "MEDIUM",
			"category": "LOWER BODY STABILITY",
			"issue_type": "Lateral Hip Sway",
			"title": "Lateral Hip Sway (%.1f units %s)" % [abs(hip_sway), dir_txt],
			"camera_flaw": "Hips slid %.1f units laterally instead of pivoting within foot foundation." % [abs(hip_sway), dir_txt],
			"launch_effect": "Shifts swing low point unpredictably, causing fat or thin strikes.",
			"player_val": "Hip Sway: %.1f units" % abs(hip_sway),
			"benchmark_val": "Target: Centered Pivot (< 1.5 units sway)",
			"fix_instruction": "Feel pressure on the inside instep of your trail foot. Turn around your spine axis without sliding hips sideways.",
			"drill": "⛳ Ball Under Trail Foot: Place half a tennis ball under outside edge of trail foot during backswing."
		})

	# ─── CORRELATION 6: STALLED HIPS AT IMPACT ───
	if hip_clearance < 18.0 and not has_smash_issue:
		final_recs.append({
			"priority": 4,
			"score": 68,
			"severity": "MEDIUM",
			"category": "IMPACT ROTATION",
			"issue_type": "Stalled Hips at Impact",
			"title": "Hips Square at Impact (Only %.1f° Open)" % hip_clearance,
			"camera_flaw": "Hips stopped turning into impact, leaving pelvis nearly square to target line.",
			"launch_effect": "Forces the hands and arms to take over through impact, making face control erratic.",
			"player_val": "Hip Clearance: %.1f° Open" % hip_clearance,
			"benchmark_val": "Target: 35.0°–45.0° Open at Impact",
			"fix_instruction": "Focus on clearing the lead hip behind you as your first downswing move. Belt buckle should face the target by follow-through.",
			"drill": "⛳ Step-Through Drill: Practice hitting short shots where your trail foot steps forward toward the target immediately after impact."
		})

	# Add any launch monitor recommendations that weren't subsumed by cross-correlations
	for r in lm_recs:
		var t = str(r.get("issue_type", ""))
		if not t in used_lm_types and t != "Pure Ball Strike":
			final_recs.append(r)

	if final_recs.is_empty():
		final_recs = lm_recs

	# Sort by score descending and assign clean 1-based priorities
	final_recs.sort_custom(func(a, b): return a["score"] > b["score"])
	for idx in range(final_recs.size()):
		final_recs[idx]["priority"] = idx + 1

	return final_recs


# =============================================================================
# 4. BACKWARD COMPATIBILITY & HELPERS
# =============================================================================

## Legacy entry point for compatibility with earlier callers
static func analyze_shot(shot_data: Dictionary, skeleton_telemetry: Dictionary = {}) -> Array[Dictionary]:
	if skeleton_telemetry.get("has_valid_telemetry", false):
		var fake_skel: Dictionary = {
			"has_valid_data": true,
			"address_shoulder_tilt": 8.0,
			"address_shoulder_hip_alignment": 0.0,
			"top_shoulder_turn": _get_float_val(skeleton_telemetry, ["shoulder_turn"], 85.0),
			"top_hip_turn": 40.0,
			"top_x_factor": 45.0,
			"top_hip_sway": _get_float_val(skeleton_telemetry, ["hip_sway"], 0.0),
			"transition_shoulder_cast": false,
			"impact_spine_loss": max(0.0, 35.0 - _get_float_val(skeleton_telemetry, ["spine_angle"], 35.0)),
			"impact_early_extension": _get_float_val(skeleton_telemetry, ["early_extension"], 0.0),
			"impact_hip_clearance": 35.0,
			"impact_chicken_wing": false,
			"lead_elbow_angle": 180.0
		}
		return analyze_shot_unified(shot_data, fake_skel)
	else:
		return analyze_launch_monitor(shot_data)


static func get_club_display_name(club_name: String) -> String:
	var c = club_name.to_lower().strip_edges()
	if c in ["dr", "1w", "driver"] or "driver" in c:
		return "Driver"
	elif c == "3w":
		return "3-Wood"
	elif c == "4w":
		return "4-Wood"
	elif c == "5w":
		return "5-Wood"
	elif c == "7w":
		return "7-Wood"
	elif "wood" in c or c == "fw":
		return "Fairway Wood"
	elif c in ["2h", "3h", "4h", "5h"]:
		return c.to_upper().replace("H", "-Hybrid")
	elif "hybrid" in c or "rescue" in c:
		return "Hybrid"
	elif c in ["1i", "2i", "3i", "4i", "5i", "6i", "7i", "8i", "9i"]:
		return c.to_upper().replace("I", "-Iron")
	elif "iron" in c:
		return club_name.capitalize()
	elif c in ["pw", "pitching"]:
		return "Pitching Wedge"
	elif c in ["gw", "aw", "gap", "approach"]:
		return "Gap Wedge"
	elif c in ["sw", "sand"]:
		return "Sand Wedge"
	elif c in ["lw", "lob"]:
		return "Lob Wedge"
	elif "wedge" in c:
		return "Wedge"
	elif "putt" in c or c == "pt":
		return "Putter"
	return club_name.capitalize() if not club_name.is_empty() else "Driver"


static func _classify_club(club_name: String) -> String:
	var c = club_name.to_lower().strip_edges()
	if "putt" in c or c == "pt":
		return "putter"
	if c in ["dr", "1w", "driver"] or "driver" in c:
		return "driver"
	if c in ["3w", "4w", "5w", "7w", "wood", "fairway", "fw"] or "wood" in c:
		return "wood"
	if c in ["2h", "3h", "4h", "5h", "hybrid", "rescue"] or "hybrid" in c:
		return "hybrid"
	if c in ["pw", "gw", "sw", "lw", "aw", "pitching", "sand", "gap", "approach", "lob", "wedge"] or "wedge" in c or c in ["9i", "9-iron"]:
		return "wedge"
	if c in ["1i", "2i", "3i", "4i", "5i", "1-iron", "2-iron", "3-iron", "4-iron", "5-iron"]:
		return "long_iron"
	if c in ["6i", "7i", "8i", "6-iron", "7-iron", "8-iron"] or "iron" in c:
		return "mid_iron"
	return "driver"


static func _get_float_val(dict: Dictionary, keys: Array, default_val: float) -> float:
	for k in keys:
		if dict.has(k):
			var val = dict[k]
			if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
				return float(val)
			elif typeof(val) == TYPE_STRING:
				# Clean string of trailing labels like " In-Out", " Sq", " O", " C", " yd"
				var s: String = str(val).strip_edges()
				var parts = s.split(" ")
				if parts.size() > 0:
					var num_str = parts[0].replace("+", "")
					var parsed = float(num_str)
					if not is_nan(parsed):
						return parsed
	return default_val

