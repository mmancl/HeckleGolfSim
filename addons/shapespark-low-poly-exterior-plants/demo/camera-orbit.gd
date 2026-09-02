extends Camera3D


var time := 0.0


func _process(delta):
	time += delta

	global_position = Vector3(sin(time / 6) * 25, 7, cos(time / 6) * 25)
	look_at(Vector3(0, 3, 0), Vector3.UP)
