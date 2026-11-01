extends Object
class_name RainPhysics

## Utility class for rain physics adjustments in Heckle Golf Simulator.
##
## Rules:
## 1. When playing in the rain, distance and spin numbers sent from the launch monitor
##    are reduced by 10% (speed/distance * 0.90, spin * 0.90).
## 2. When in the rain, shot rollout is reduced by 60% (40% remaining rollout,
##    achieved via 2.5x rolling & kinetic friction and sqrt(0.40) wet turf bounce damping).
## 3. When playing in the sun, absolutely zero changes are made to physics (1.0x baseline).

const RAIN_SHOT_REDUCTION_PERCENT: float = 10.0
const RAIN_SHOT_MULTIPLIER: float = 0.90 # 10% reduction
const RAIN_ROLLOUT_REDUCTION_PERCENT: float = 60.0
const RAIN_ROLLOUT_FACTOR: float = 0.40 # 1.0 - 0.60 = 40% remaining rollout
const RAIN_FRICTION_MULTIPLIER: float = 2.50 # 1.0 / 0.40 = 2.5x friction for 60% rollout reduction
const RAIN_BOUNCE_RETENTION: float = 0.632455532 # sqrt(0.40) to scale tangential & normal velocity on wet bounce


## Checks whether rain mode is currently active in the session.
static func is_rain_active() -> bool:
	# 1. Check GlobalSettings singleton
	if Engine.has_singleton("GlobalSettings"):
		var gs = Engine.get_singleton("GlobalSettings")
		if gs.has_method("is_rain_mode"):
			if gs.is_rain_mode():
				return true
	elif Engine.get_main_loop() is SceneTree:
		var root = (Engine.get_main_loop() as SceneTree).root
		if root != null and root.has_node("GlobalSettings"):
			var gs = root.get_node("GlobalSettings")
			if gs.has_method("is_rain_mode"):
				if gs.call("is_rain_mode"):
					return true

	# 2. Check active WeatherLightingController
	var w_ctrl_script = load("res://Courses/Range/weather_lighting_controller.gd")
	if w_ctrl_script != null and w_ctrl_script.has_method("is_rain_active"):
		if bool(w_ctrl_script.call("is_rain_active")):
			return true

	return false


## Applies a 10% reduction to speed, distance, and spin metrics in the shot payload when in rain.
## Idempotent per shot payload (prevents double reduction across multiple forwarding hooks).
static func apply_rain_shot_reduction(data: Dictionary) -> void:
	if not is_rain_active():
		return
	if data == null or data.is_empty():
		return
	if data.get("_rain_reduction_applied", false):
		return

	# Handle nested BallData if present
	if data.has("BallData") and data["BallData"] is Dictionary:
		apply_rain_shot_reduction(data["BallData"])

	data["_rain_reduction_applied"] = true
	data["_rain_reduction_pct"] = RAIN_SHOT_REDUCTION_PERCENT

	# Speed / BallSpeed reduction (10%)
	var raw_speed: float = float(data.get("Speed", data.get("BallSpeed", 0.0)))
	if raw_speed > 0.0:
		data["_original_rain_speed"] = raw_speed
		var reduced_speed := raw_speed * RAIN_SHOT_MULTIPLIER
		data["Speed"] = reduced_speed
		if data.has("BallSpeed"):
			data["BallSpeed"] = reduced_speed

	# Spin metrics reduction (10%)
	if data.has("TotalSpin"):
		var raw_total_spin: float = float(data["TotalSpin"])
		data["_original_rain_total_spin"] = raw_total_spin
		data["TotalSpin"] = maxf(0.0, raw_total_spin * RAIN_SHOT_MULTIPLIER)
	if data.has("total_spin"):
		data["total_spin"] = maxf(0.0, float(data["total_spin"]) * RAIN_SHOT_MULTIPLIER)
	if data.has("Spin"):
		data["Spin"] = maxf(0.0, float(data["Spin"]) * RAIN_SHOT_MULTIPLIER)

	if data.has("BackSpin"):
		data["BackSpin"] = float(data["BackSpin"]) * RAIN_SHOT_MULTIPLIER
	if data.has("back_spin"):
		data["back_spin"] = float(data["back_spin"]) * RAIN_SHOT_MULTIPLIER

	if data.has("SideSpin"):
		data["SideSpin"] = float(data["SideSpin"]) * RAIN_SHOT_MULTIPLIER
	if data.has("side_spin"):
		data["side_spin"] = float(data["side_spin"]) * RAIN_SHOT_MULTIPLIER

	# Distance fields reduction (10%) if provided by monitor/bridge
	for dist_key in ["Distance", "CarryDistance", "Carry", "TotalDistance", "distance", "carry", "total_distance", "carry_distance"]:
		if data.has(dist_key) and float(data[dist_key]) > 0.0:
			data["_original_rain_" + dist_key] = float(data[dist_key])
			data[dist_key] = float(data[dist_key]) * RAIN_SHOT_MULTIPLIER

	# Smash factor adjustment if club speed present
	var club_speed: float = float(data.get("ClubSpeed", 0.0))
	if club_speed > 0.1 and data.has("Speed"):
		data["SmashFactor"] = float(data["Speed"]) / club_speed
	elif data.has("SmashFactor"):
		data["SmashFactor"] = float(data["SmashFactor"]) * RAIN_SHOT_MULTIPLIER

	print("[RainPhysics] Rain active: reduced launch distance/speed and spin numbers by 10%% (Speed: %.1f -> %.1f mph)" % [
		raw_speed, float(data.get("Speed", raw_speed))
	])
