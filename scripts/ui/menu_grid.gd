extends Control

func _draw() -> void:
	for x: int in range(0, int(size.x) + 1, 48):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.15, 0.34, 0.46, 0.10), 1)
	for y: int in range(0, int(size.y) + 1, 48):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.15, 0.34, 0.46, 0.10), 1)
