class_name VirtualCursor
extends Control
## 游戏内绘制的角色光标。实际输入由 Main 路由，这里只负责显示。

var active: bool = false:
	set(value):
		active = value
		queue_redraw()
var role_name: String = ""
var accent: Color = UiStyle.CYAN


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(86.0, 38.0)
	size = custom_minimum_size
	z_index = 1000
	queue_redraw()


func _draw() -> void:
	var edge: Color = Color("071019")
	# 同伴光标仍保留岗位颜色，清晰度统一交给协调器用整体透明度表达。
	var fill: Color = accent
	var points := PackedVector2Array([
		Vector2(2.0, 2.0),
		Vector2(2.0, 27.0),
		Vector2(8.5, 20.5),
		Vector2(13.0, 31.0),
		Vector2(18.5, 28.5),
		Vector2(14.0, 18.5),
		Vector2(24.0, 18.0),
	])
	draw_colored_polygon(points, edge)
	var inner := PackedVector2Array([
		Vector2(4.5, 5.0),
		Vector2(4.5, 21.0),
		Vector2(9.2, 16.4),
		Vector2(13.8, 27.0),
		Vector2(15.4, 26.2),
		Vector2(10.8, 15.8),
		Vector2(18.2, 15.4),
	])
	draw_colored_polygon(inner, fill)
	if active:
		draw_arc(Vector2(4.0, 4.0), 5.0, 0.0, TAU, 20, Color(fill, 0.55), 1.5, true)
	if not role_name.is_empty():
		draw_rect(Rect2(25.0, 3.0, 55.0, 24.0), Color("071019e6"), true)
		draw_rect(Rect2(25.0, 3.0, 55.0, 24.0), Color(fill, 0.8), false, 1.0)
		draw_string(UiStyle.hud_font(), Vector2(31.0, 20.0), role_name, HORIZONTAL_ALIGNMENT_LEFT, 45.0, 14, fill)
