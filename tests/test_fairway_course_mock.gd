extends Node3D

func is_point_in_fairway(pos_2d: Vector2) -> bool:
	# Mock fairway rectangle: X in [50, 150], Y in [0, 50]
	return pos_2d.x >= 50.0 and pos_2d.x <= 150.0 and pos_2d.y >= 0.0 and pos_2d.y <= 50.0
