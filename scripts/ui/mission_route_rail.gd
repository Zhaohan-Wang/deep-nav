class_name MissionRouteRail
extends Control
## 星图航程轨的紧凑 HUD 版本；两个岗位看到完全相同的公开进度。

const RAIL_COLOR := Color(0.94, 0.67, 0.28, 0.38)
const RAIL_FILL := Color(0.33, 0.89, 0.93, 0.72)
const SHIP_COLOR := Color(0.33, 0.89, 0.93, 1.0)

var progress_ratio: float = 0.0:
	set(value):
		var next := clampf(value, 0.0, 1.0)
		if is_equal_approx(progress_ratio, next):
			return
		progress_ratio = next
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(210.0, 18.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var y := size.y * 0.5
	var start := Vector2(8.0, y)
	var finish := Vector2(maxf(size.x - 8.0, start.x + 1.0), y)
	var ship := start.lerp(finish, progress_ratio)

	# 保留原星图的琥珀色全航程与青色飞船标记，并补一段已完成航程，
	# 在很窄的底栏里仍能一眼看清当前位置。
	draw_line(start, finish, RAIL_COLOR, 2.0, true)
	draw_line(start, ship, RAIL_FILL, 2.0, true)
	for point: Vector2 in [start, finish]:
		draw_line(point + Vector2(0.0, -4.0), point + Vector2(0.0, 4.0), Color(RAIL_COLOR, 0.9), 1.0, true)
	draw_circle(ship, 6.0, Color(SHIP_COLOR, 0.13))
	draw_circle(ship, 3.2, SHIP_COLOR)
