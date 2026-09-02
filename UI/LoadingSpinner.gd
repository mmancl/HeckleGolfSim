extends Control
class_name LoadingSpinner

@export var color: Color = Color(0.24, 0.46, 0.72, 1.0)
@export var speed: float = 5.0
@export var thickness: float = 6.0
@export var radius: float = 24.0

var _angle: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Ensure the control uses a reasonable default size if not explicitly set
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(radius * 2 + thickness + 10, radius * 2 + thickness + 10)

func _process(delta: float) -> void:
	if is_visible_in_tree():
		_angle += speed * delta
		if _angle >= PI * 2:
			_angle -= PI * 2
		queue_redraw()

func _draw() -> void:
	var center = size / 2.0
	var points = 32
	var angle_step = (PI * 1.7) / points # Leave a small gap to make it look like a spinner ring
	
	for i in range(points):
		var segment_angle = _angle + i * ((PI * 1.7) / points)
		var alpha = float(i) / float(points)
		var c = Color(color.r, color.g, color.b, color.a * alpha)
		var next_angle = segment_angle + angle_step
		
		var p1 = center + Vector2(cos(segment_angle), sin(segment_angle)) * radius
		var p2 = center + Vector2(cos(next_angle), sin(next_angle)) * radius
		draw_line(p1, p2, c, thickness, true)
