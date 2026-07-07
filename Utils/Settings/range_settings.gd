class_name RangeSettings
extends SettingCollector

var range_units := Setting.new(PhysicsEnums.Units.IMPERIAL)
var camera_follow_mode := Setting.new(true)
var shot_injector_enabled := Setting.new(false)
var auto_ball_reset := Setting.new(false)
var ball_reset_timer := Setting.new(3.0, 1.0, 15.0)
var temperature := Setting.new(75, -40, 120)
var altitude := Setting.new(0.0, -1000.0, 10000.0)
var surface_type := Setting.new(PhysicsEnums.SurfaceType.FAIRWAY)
var shot_tracer_count := Setting.new(1, 0, 4)
var ball_type := Setting.new(0)
var camera_height := Setting.new(1.6, 0.5, 10.0)
var camera_distance := Setting.new(10.0, 2.0, 30.0)
var camera_fov := Setting.new(25.0, 1.0, 60.0)
var camera_far := Setting.new(1000.0, 100.0, 1000.0)
var dof_enabled := Setting.new(false)
var dof_blur_amount := Setting.new(0.03, 0.0, 0.3)
var vignette_enabled := Setting.new(false)
var vignette_intensity := Setting.new(1.5, 0.0, 3.0)
var gimme_range_1_enabled := Setting.new(true)
var gimme_range_1_distance := Setting.new(5.0, 0.5, 20.0)
var gimme_range_2_enabled := Setting.new(false)
var gimme_range_2_distance := Setting.new(25.0, 0.5, 30.0)
var custom_next_player := Setting.new(true)

func _init():
	settings = {
		"range_units": range_units,
		"camera_follow_mode": camera_follow_mode,
		"shot_injector_enabled": shot_injector_enabled,
		"auto_ball_reset": auto_ball_reset,
		"ball_reset_timer": ball_reset_timer,
		"temperature": temperature,
		"altitude": altitude,
		"surface_type": surface_type,
		"shot_tracer_count": shot_tracer_count,
		"ball_type": ball_type,
		"camera_height": camera_height,
		"camera_distance": camera_distance,
		"camera_fov": camera_fov,
		"camera_far": camera_far,
		"dof_enabled": dof_enabled,
		"dof_blur_amount": dof_blur_amount,
		"vignette_enabled": vignette_enabled,
		"vignette_intensity": vignette_intensity,
		"gimme_range_1_enabled": gimme_range_1_enabled,
		"gimme_range_1_distance": gimme_range_1_distance,
		"gimme_range_2_enabled": gimme_range_2_enabled,
		"gimme_range_2_distance": gimme_range_2_distance,
		"custom_next_player": custom_next_player,
	}

