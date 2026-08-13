class_name PilotDashboard
extends Control
## 驾驶员仪表台：左罗盘、中推进盘、右航速盘，三块圆表横排贴在画面底部。
## 中盘最大、两侧略小并与中盘圆心对齐，形成驾驶舱仪表簇的观感。

## 两侧表盘相对中盘的直径比例。
const SIDE_SCALE: float = 0.78
## 表盘之间的间距相对中盘直径的比例。
const GAP_SCALE: float = 0.10

var compass: CompassGauge
var thrust: ThrustGauge
var speed: SpeedGauge


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass = CompassGauge.new()
	thrust = ThrustGauge.new()
	speed = SpeedGauge.new()
	add_child(compass)
	add_child(thrust)
	add_child(speed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


func _place() -> void:
	if size.x < 4.0 or size.y < 4.0:
		return
	# 中盘直径受高度和三盘总宽双重约束。
	var d1: float = minf(size.y, size.x / (1.0 + 2.0 * (GAP_SCALE + SIDE_SCALE)))
	var d2: float = d1 * SIDE_SCALE
	var gap: float = d1 * GAP_SCALE
	var cx: float = size.x * 0.5
	# 中盘贴底，两侧盘与中盘圆心水平对齐。
	var cy: float = size.y - d1 * 0.5
	thrust.position = Vector2(cx - d1 * 0.5, size.y - d1)
	thrust.size = Vector2(d1, d1)
	compass.position = Vector2(cx - d1 * 0.5 - gap - d2, cy - d2 * 0.5)
	compass.size = Vector2(d2, d2)
	speed.position = Vector2(cx + d1 * 0.5 + gap, cy - d2 * 0.5)
	speed.size = Vector2(d2, d2)
