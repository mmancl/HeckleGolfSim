extends RefCounted

# GolfSwingAnalyzer
# Dual-source analysis engine evaluating real shot physics & skeleton pose telemetry.
# Uses actual measured landmark data (spine angle, shoulder turn, early extension)
# from the GolferSkeletonOverlay alongside launch monitor ballistic data.

class_name GolfSwingAnalyzer

static func analyze_shot(shot_data: Dictionary, skeleton_telemetry: Dictionary = {}) -> Array[Dictionary]:
	var recommendations: Array[Dictionary] = []
	
	# Parse Launch Monitor Data robustly
	var spin_axis: float = _get_float_val(shot_data, ["SpinAxis", "SideSpinAxis"], 0.0)
	if not shot_data.has("SpinAxis") and shot_data.has("SideSpin"):
		var side_spin = _get_float_val(shot_data, ["SideSpin"], 0.0)
		spin_axis = clamp(side_spin / 95.0, -25.0, 25.0)
		
	var hla: float = _get_float_val(shot_data, ["HLA", "HorizontalLaunchAngle"], 0.0)
	var vla: float = _get_float_val(shot_data, ["VLA", "VerticalLaunchAngle"], 14.5)
	var speed: float = _get_float_val(shot_data, ["Speed", "BallSpeed", "ClubSpeed"], 140.0)
	var total_spin: float = _get_float_val(shot_data, ["TotalSpin", "BackSpin"], 2800.0)
	var carry: float = _get_float_val(shot_data, ["Carry", "CarryDistance", "Distance", "TotalDistance"], 220.0)
	var club: String = str(shot_data.get("Club", "Driver"))

	# ── Camera Pose Telemetry ──
	# These come from REAL landmark measurements when available, otherwise use defaults
	var has_real_telemetry: bool = skeleton_telemetry.get("has_valid_telemetry", false)
	var measured_spine: float = _get_float_val(skeleton_telemetry, ["spine_angle"], 35.0)
	var measured_turn: float = _get_float_val(skeleton_telemetry, ["shoulder_turn"], 0.0)
	var measured_extension: float = _get_float_val(skeleton_telemetry, ["early_extension"], 0.0)
	var measured_hip_sway: float = _get_float_val(skeleton_telemetry, ["hip_sway"], 0.0)

	# ── Derive flaw indicators from BOTH data sources ──
	# Spine angle loss: use real telemetry if available, otherwise estimate from spin axis
	var spine_angle_loss: float
	if has_real_telemetry:
		# Compare measured spine to ideal address spine (~35°)
		# During impact, spine should be maintained. Loss > 8° is concerning.
		spine_angle_loss = max(0.0, 35.0 - measured_spine)  # How much spine was lost
	else:
		spine_angle_loss = 14.0 if abs(spin_axis) > 9.0 else (6.5 if abs(spin_axis) > 4.0 else 1.5)
	
	var over_the_top_deg: float = abs(hla) + (spin_axis * 0.4 if spin_axis > 0 else 0.0)
	var head_sway: float = abs(hla) * 0.8 + 0.5

	# --- 1. SLICE / OPEN CLUB FACE & OVER-THE-TOP (CRITICAL / HIGH) ---
	if spin_axis > 6.0 or over_the_top_deg > 2.0:
		var camera_detail := ""
		if has_real_telemetry:
			camera_detail = "Measured spine angle: %.1f° (lost %.1f° from address). Shoulder turn: %.1f°. Downswing shaft plane steepened outside backswing line." % [measured_spine, spine_angle_loss, measured_turn]
		else:
			camera_detail = "Downswing shaft plane steepened %.1f° outside backswing line with open wrist release." % over_the_top_deg
		
		recommendations.append({
			"priority": 1,
			"score": 95 + int(spin_axis),
			"severity": "CRITICAL" if spin_axis > 10.0 else "HIGH",
			"category": "SWING PLANE & CLUB FACE",
			"issue_type": "Slice / Open Club Face",
			"title": "Open Club Face at Impact (+%.1f° Spin Axis Slice)" % spin_axis,
			"camera_flaw": camera_detail,
			"launch_effect": "Open face relative to path caused +%.1f° Spin Axis slice curving right." % spin_axis,
			"player_val": "Spin Axis: +%.1f° (Slice) | Path: +%.1f°" % [spin_axis, over_the_top_deg],
			"benchmark_val": "Pro Benchmark: -2.0° to +2.0° Axis | Inside Path",
			"fix_instruction": "Drop trail elbow toward hip at transition to shallow club onto inside path. Rotate lead knuckles down through impact zone.",
			"drill": "⛳ Gate Drill: Place a headcover 6 inches outside ball to prevent outside-in downswing loop."
		})

	# --- 2. HOOK / CLOSED FACE (CRITICAL / HIGH) ---
	elif spin_axis < -6.0:
		var camera_detail := ""
		if has_real_telemetry:
			camera_detail = "Measured spine angle: %.1f°. Early extension: %.1f units. Wrists flipped early through impact zone." % [measured_spine, measured_extension]
		else:
			camera_detail = "Wrists flipped early through impact zone, closing face relative to path."
		
		recommendations.append({
			"priority": 1,
			"score": 92 + int(abs(spin_axis)),
			"severity": "CRITICAL" if spin_axis < -10.0 else "HIGH",
			"category": "CLUB FACE CONTROL",
			"issue_type": "Hook / Closed Club Face",
			"title": "Closed Club Face at Impact (%.1f° Spin Axis Hook)" % spin_axis,
			"camera_flaw": camera_detail,
			"launch_effect": "Closed face produced %.1f° Spin Axis leftward hook curve." % spin_axis,
			"player_val": "Spin Axis: %.1f° (Hook)" % spin_axis,
			"benchmark_val": "Pro Benchmark: -2.0° to +2.0° Axis",
			"fix_instruction": "Maintain lead wrist structure through impact zone without aggressively flipping hands.",
			"drill": "⛳ Split-Hand Drill: Hold club with 3-inch hand gap; practice chest-led turn through impact."
		})

	# --- 3. EARLY EXTENSION & POSTURE LOSS (HIGH) ---
	# Use real telemetry when available for much more accurate detection
	var early_ext_detected := false
	if has_real_telemetry:
		early_ext_detected = measured_extension > 2.0 or spine_angle_loss > 8.0
	else:
		early_ext_detected = spine_angle_loss > 5.0 or abs(spin_axis) > 8.0
	
	if early_ext_detected:
		var camera_detail := ""
		if has_real_telemetry:
			camera_detail = "Camera detected hips thrust %.1f units forward toward ball. Spine angle rose from ~35° to %.1f° (lost %.1f°)." % [measured_extension, measured_spine, spine_angle_loss]
		else:
			camera_detail = "Hips thrust forward toward ball line at impact, causing spine angle to rise."
		
		recommendations.append({
			"priority": 2,
			"score": 88,
			"severity": "HIGH",
			"category": "POSTURE & BIOMECHANICS",
			"issue_type": "Early Extension",
			"title": "Early Extension (Loss of %.1f° Spine Inclination)" % spine_angle_loss,
			"camera_flaw": camera_detail,
			"launch_effect": "Reduces impact smash efficiency and forces manual hand flipping.",
			"player_val": "Spine Angle: %.1f° at impact (Lost %.1f°)" % [measured_spine, spine_angle_loss],
			"benchmark_val": "Pro Benchmark: 35.0° Retained Spine Angle",
			"fix_instruction": "Keep lead hip pressed back against imaginary wall through impact. Maintain torso inclination until finish.",
			"drill": "⛳ Wall/Chair Drill: Touch lead hip against chair back at address and keep contact through turn."
		})

	# --- 4. PULL / PUSH LAUNCH ALIGNMENT (MEDIUM) ---
	if abs(hla) > 3.0:
		var side_name = "Push (Right)" if hla > 0 else "Pull (Left)"
		var camera_detail := ""
		if has_real_telemetry:
			camera_detail = "Measured hip sway: %.1f units lateral. Body alignment shifted %.1f° off target line." % [measured_hip_sway, abs(hla)]
		else:
			camera_detail = "Body alignment or swing path shifted %.1f° off target line." % abs(hla)
		
		recommendations.append({
			"priority": 3,
			"score": 75,
			"severity": "MEDIUM",
			"category": "ALIGNMENT & SWING PATH",
			"issue_type": "Push / Pull Alignment",
			"title": "Horizontal Launch Angle Offset (%s %.1f°)" % [side_name, abs(hla)],
			"camera_flaw": camera_detail,
			"launch_effect": "Ball started %.1f° off target line immediately at launch." % abs(hla),
			"player_val": "HLA: %+.1f° %s" % [hla, side_name],
			"benchmark_val": "Pro Benchmark: 0.0° ± 1.5° HLA",
			"fix_instruction": "Check shoulder and feet alignment parallel to target line at setup.",
			"drill": "⛳ Alignment Sticks: Set two parallel alignment rods on ground for feet and ball target line."
		})

	# --- 5. SHOULDER ROTATION & POWER COIL (MEDIUM) ---
	var rotation_restricted := false
	if has_real_telemetry:
		rotation_restricted = measured_turn < 75.0  # Use actual measured rotation
	else:
		rotation_restricted = speed < 125.0  # Estimate from ball speed only
	
	if rotation_restricted:
		var display_turn: float = measured_turn if has_real_telemetry else 80.0
		var camera_detail := ""
		if has_real_telemetry:
			camera_detail = "Camera measured %.1f° shoulder rotation at top of backswing — restricting power coil." % measured_turn
		else:
			camera_detail = "Estimated restricted shoulder turn based on ball speed (%.1f mph)." % speed
		
		recommendations.append({
			"priority": 4,
			"score": 68,
			"severity": "MEDIUM",
			"category": "POWER & BODY COIL",
			"issue_type": "Restricted Shoulder Rotation",
			"title": "Restricted Shoulder Rotation (%.1f° Turn at P4)" % display_turn,
			"camera_flaw": camera_detail,
			"launch_effect": "Restricts ball speed (%.1f mph) and carry distance (%.0f yds)." % [speed, carry],
			"player_val": "Shoulder Turn: %.1f° | Speed: %.1f mph" % [display_turn, speed],
			"benchmark_val": "Pro Benchmark: 90.0° Shoulder Turn",
			"fix_instruction": "Turn lead shoulder fully over trail knee on backswing while keeping trail hip grounded.",
			"drill": "⛳ Chest Club Turn Drill: Cross arms over chest with club; turn shoulders 90° over trail leg."
		})

	# --- 6. HIP SWAY (MEDIUM) — Only when real telemetry is available ---
	if has_real_telemetry and abs(measured_hip_sway) > 3.0:
		var sway_dir = "toward target" if measured_hip_sway > 0 else "away from target"
		recommendations.append({
			"priority": 5,
			"score": 62,
			"severity": "MEDIUM",
			"category": "LOWER BODY STABILITY",
			"issue_type": "Excessive Hip Sway",
			"title": "Excessive Hip Sway (%.1f units %s)" % [abs(measured_hip_sway), sway_dir],
			"camera_flaw": "Camera detected %.1f units of lateral hip movement %s during swing." % [abs(measured_hip_sway), sway_dir],
			"launch_effect": "Inconsistent low point and strike location, reducing accuracy.",
			"player_val": "Hip Sway: %.1f units %s" % [abs(measured_hip_sway), sway_dir],
			"benchmark_val": "Pro Benchmark: < 1.5 units lateral sway",
			"fix_instruction": "Keep trail hip anchored during backswing. Feel pressure on inside of trail foot.",
			"drill": "⛳ Stability Ball Drill: Place ball between knees during half swings to limit lateral movement."
		})

	# If no major flaws detected, praise good execution!
	if recommendations.is_empty():
		var camera_detail := ""
		if has_real_telemetry:
			camera_detail = "Camera measured clean spine retention (%.1f°), shoulder rotation (%.1f°), and minimal hip sway (%.1f)." % [measured_spine, measured_turn, measured_hip_sway]
		else:
			camera_detail = "Launch data shows clean face control and swing path."
		
		recommendations.append({
			"priority": 1,
			"score": 30,
			"severity": "LOW",
			"category": "SWING MAINTENANCE",
			"issue_type": "Pro-Grade Execution",
			"title": "Pro-Grade Face Control & Swing Plane!",
			"camera_flaw": camera_detail,
			"launch_effect": "Solid ball speed (%.1f mph), carry (%.0f yds), and Spin Axis (%+.1f°)." % [speed, carry, spin_axis],
			"player_val": "Spin Axis: %+.1f° | HLA: %+.1f°" % [spin_axis, hla],
			"benchmark_val": "Pro Benchmark: Matched",
			"fix_instruction": "Maintain your tempo and pre-shot routine. Focus on target visualization.",
			"drill": "⛳ Target Practice Drill: Practice hitting specific fairway zones with consistent rhythm."
		})

	recommendations.sort_custom(func(a, b): return a["score"] > b["score"])
	for idx in range(recommendations.size()):
		recommendations[idx]["priority"] = idx + 1
		
	return recommendations

static func _get_float_val(dict: Dictionary, keys: Array, default_val: float) -> float:
	for k in keys:
		if dict.has(k):
			var val = dict[k]
			if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
				return float(val)
			elif typeof(val) == TYPE_STRING:
				var parsed = float(val)
				if not is_nan(parsed):
					return parsed
	return default_val
