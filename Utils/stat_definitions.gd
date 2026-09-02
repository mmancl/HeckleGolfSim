class_name StatDefinitions
extends Object

const MAX_DISPLAYED_STATS := 12

const DEFAULT_ENABLED_STAT_IDS: Array[String] = [
	"Distance",
	"Carry",
	"Speed",
	"VLA",
	"HLA",
	"BackSpin",
	"SideSpin",
	"TotalSpin",
	"SpinAxis",
	"Apex",
	"Offline",
	"FaceAngle"
]

const STATS: Array[Dictionary] = [
	# --- BALL FLIGHT METRICS ---
	{
		"id": "Distance",
		"short_label": "Distance",
		"name": "Total Distance",
		"category": "Ball Flight",
		"description": "Total distance traveled by the ball from the hitting point to its final resting position, including carry flight, bounces, and ground roll.",
		"units_imperial": "yd",
		"units_metric": "m",
		"default_enabled": true
	},
	{
		"id": "Carry",
		"short_label": "Carry",
		"name": "Carry Distance",
		"category": "Ball Flight",
		"description": "The straight-line flight distance the golf ball travels airborne before making initial contact with the turf or hazard.",
		"units_imperial": "yd",
		"units_metric": "m",
		"default_enabled": true
	},
	{
		"id": "Speed",
		"short_label": "Speed",
		"name": "Ball Speed",
		"category": "Ball Flight",
		"description": "The exit velocity of the golf ball immediately after separating from the clubface at impact. Primary driver of overall distance.",
		"units_imperial": "mph",
		"units_metric": "m/s",
		"default_enabled": true
	},
	{
		"id": "VLA",
		"short_label": "VLA",
		"name": "Vertical Launch Angle",
		"category": "Ball Flight",
		"description": "The initial takeoff angle of the ball relative to the flat ground plane immediately after impact. Crucial for optimizing launch window.",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": true
	},
	{
		"id": "HLA",
		"short_label": "HLA",
		"name": "Horizontal Launch Angle",
		"category": "Ball Flight",
		"description": "The starting launch direction of the ball relative to the target line (Push to the right or Pull to the left) before spin curvature takes effect.",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": true
	},
	{
		"id": "BackSpin",
		"short_label": "BackSpin",
		"name": "Back Spin",
		"category": "Ball Flight",
		"description": "The vertical rotational speed of the ball in revolutions per minute. Creates aerodynamic Magnus lift to keep the ball aloft and control green-stopping power.",
		"units_imperial": "rpm",
		"units_metric": "rpm",
		"default_enabled": true
	},
	{
		"id": "SideSpin",
		"short_label": "SideSpin",
		"name": "Side Spin",
		"category": "Ball Flight",
		"description": "The horizontal rotational spin component that produces lateral aerodynamic curvature in flight (Draw / Hook vs Fade / Slice).",
		"units_imperial": "rpm",
		"units_metric": "rpm",
		"default_enabled": true
	},
	{
		"id": "TotalSpin",
		"short_label": "TotalSpin",
		"name": "Total Spin",
		"category": "Ball Flight",
		"description": "The combined 3D rotational rate of the ball across all axes, expressed in revolutions per minute (RPM).",
		"units_imperial": "rpm",
		"units_metric": "rpm",
		"default_enabled": true
	},
	{
		"id": "SpinAxis",
		"short_label": "SpinAxis",
		"name": "Spin Axis",
		"category": "Ball Flight",
		"description": "The tilt angle of the golf ball's rotational axis relative to the horizon. Negative angles tilt left (Draw/Hook), positive angles tilt right (Fade/Slice).",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": true
	},
	{
		"id": "Apex",
		"short_label": "Apex",
		"name": "Apex (Peak Height)",
		"category": "Trajectory",
		"description": "The highest altitude / peak vertical height reached by the ball above the launch elevation during its flight.",
		"units_imperial": "ft",
		"units_metric": "m",
		"default_enabled": true
	},
	{
		"id": "Offline",
		"short_label": "Offline",
		"name": "Offline (Side Deviation)",
		"category": "Trajectory",
		"description": "The lateral distance the ball comes to rest to the Left (L) or Right (R) relative to the straight target aim line.",
		"units_imperial": "yd",
		"units_metric": "m",
		"default_enabled": true
	},
	{
		"id": "HangTime",
		"short_label": "Hang Time",
		"name": "Hang Time",
		"category": "Trajectory",
		"description": "The total airborne flight duration in seconds from the instant of impact until initial ground touchdown.",
		"units_imperial": "s",
		"units_metric": "s",
		"default_enabled": false
	},
	{
		"id": "DescentAngle",
		"short_label": "Descent",
		"name": "Descent Angle",
		"category": "Trajectory",
		"description": "The steepness angle at which the ball approaches the ground on landing. Steeper landing angles (45°+) help hold greens quickly.",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": false
	},

	# --- CLUB DELIVERY METRICS ---
	{
		"id": "FaceAngle",
		"short_label": "Face Ang",
		"name": "Club Face Angle",
		"category": "Club Delivery",
		"description": "The horizontal orientation of the clubface at impact relative to the target line (Open to the right, Square, or Closed to the left).",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": true
	},
	{
		"id": "ClubPath",
		"short_label": "Club Path",
		"name": "Club Swing Path",
		"category": "Club Delivery",
		"description": "The horizontal direction the clubhead is traveling through impact relative to the target line (In-to-Out for draws, Out-to-In for fades).",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": false
	},
	{
		"id": "FaceToPath",
		"short_label": "Face-Path",
		"name": "Face to Path",
		"category": "Club Delivery",
		"description": "The angle difference between the club face angle and the swing path (Face Angle minus Club Path). Directly dictates ball curvature and spin axis.",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": false
	},
	{
		"id": "AttackAngle",
		"short_label": "Attack Ang",
		"name": "Angle of Attack (AoA)",
		"category": "Club Delivery",
		"description": "The vertical angle at which the clubhead is moving at maximum compression. Negative represents hitting down (irons/wedges), positive represents hitting up (driver).",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": false
	},
	{
		"id": "DynamicLoft",
		"short_label": "Dyn Loft",
		"name": "Dynamic Loft",
		"category": "Club Delivery",
		"description": "The delivered vertical loft angle of the clubface at impact, reflecting shaft lean, forward press, and clubhead presentation.",
		"units_imperial": "deg",
		"units_metric": "deg",
		"default_enabled": false
	},
	{
		"id": "ClubSpeed",
		"short_label": "Club Spd",
		"name": "Clubhead Speed",
		"category": "Club Delivery",
		"description": "The velocity of the clubhead immediately prior to initial contact with the ball.",
		"units_imperial": "mph",
		"units_metric": "m/s",
		"default_enabled": false
	},
	{
		"id": "SmashFactor",
		"short_label": "Smash",
		"name": "Smash Factor",
		"category": "Club Delivery",
		"description": "Energy transfer efficiency from clubhead to ball, calculated as Ball Speed divided by Clubhead Speed (1.45 - 1.50 is optimal for Driver).",
		"units_imperial": "ratio",
		"units_metric": "ratio",
		"default_enabled": false
	}
]

static func get_stat_by_id(stat_id: String) -> Dictionary:
	for stat in STATS:
		if str(stat.get("id", "")) == stat_id:
			return stat
	return {}

static func get_all_stat_ids() -> Array[String]:
	var ids: Array[String] = []
	for stat in STATS:
		ids.append(str(stat.get("id", "")))
	return ids

static func get_default_enabled_stat_ids() -> Array[String]:
	return DEFAULT_ENABLED_STAT_IDS.duplicate()
