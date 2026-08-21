class_name SpeedGauge
extends Control
## 航速表：像汽车滚筒仪表一样转动的刻度盘——当前速度永远对着顶部固定指标，
## 加速时刻度整体向左流动。只在上半圈显示可见范围内的刻度，靠边缘渐隐。

## 每单位速度对应的转角。
const DEG_PER_UNIT: float = 13.0
## 顶部两侧各显示这么多度的刻度，超出即隐藏。
const VISIBLE_HALF_DEG: float = 96.0
## 接近极速时读数变琥珀色提醒。
const FAST_RATIO: float = 0.88

## 正式表盘背景图之后从这里换入；为空时画占位圆。
@export var bg_texture: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - 2.0
	if radius < 8.0:
		return
	var center: Vector2 = size * 0.5
	GaugeDraw.draw_dial_bg(self, center, radius, bg_texture)
	var speed: float = _signed_speed()
	_draw_ticks(center, radius, speed)
	_draw_lubber(center, radius)
	_draw_readout(center, radius, speed)


## 只显示沿船头方向的速度分量：前进为正，倒车或向后滑行为负。
func _signed_speed() -> float:
	var forward:=Vector3(-sin(Game.ship_heading),0.0,-cos(Game.ship_heading))
	return Vector3(Game.ship_velocity.x,0.0,Game.ship_velocity.z).dot(forward)


## 以正上方为 0、向右为正的极角转屏幕坐标。
func _pos_from_top(center: Vector2, theta: float, r: float) -> Vector2:
	return center + Vector2(sin(theta), -cos(theta)) * r


func _draw_ticks(center: Vector2, radius: float, speed: float) -> void:
	for v: int in range(-int(Game.MAX_SPEED), int(Game.MAX_SPEED) + 1):
		var rel: float = (float(v) - speed) * DEG_PER_UNIT
		if absf(rel) > VISIBLE_HALF_DEG:
			continue
		var theta: float = deg_to_rad(rel)
		var is_zero: bool = v == 0
		var major: bool = v % 4 == 0
		# 越靠近可见范围边缘越淡，模拟滚筒转出视野。
		var fade: float = clampf(1.25 - absf(rel) / VISIBLE_HALF_DEG, 0.15, 1.0)
		var outer: float = radius * 0.90
		var inner: float = radius * (0.70 if is_zero else (0.76 if major else 0.84))
		var base: Color = UiStyle.CYAN if is_zero else (UiStyle.TEXT if major else UiStyle.MUTED)
		var col := Color(base.r, base.g, base.b, base.a * fade)
		draw_line(_pos_from_top(center, theta, inner), _pos_from_top(center, theta, outer), col, 4.0 if is_zero else (2.0 if major else 1.0))
		if major:
			var label_pos: Vector2 = _pos_from_top(center, theta, radius * 0.60)
			var label_base:Color=UiStyle.CYAN if is_zero else UiStyle.MUTED
			var label_col := Color(label_base.r,label_base.g,label_base.b,fade)
			draw_string(UiStyle.hud_font(), label_pos + Vector2(-24.0, 4.0), str(v), HORIZONTAL_ALIGNMENT_CENTER, 48.0, 11 if is_zero else 8, label_col)


## 顶部固定指标：向下指向盘面的小三角。
func _draw_lubber(center: Vector2, radius: float) -> void:
	var half_w: float = maxf(radius * 0.055, 3.0)
	var tip: Vector2 = center + Vector2(0.0, -radius * 0.68)
	var base_y: float = -radius * 0.82
	var points := PackedVector2Array([
		tip,
		center + Vector2(-half_w, base_y),
		center + Vector2(half_w, base_y),
	])
	draw_colored_polygon(points, UiStyle.CYAN)


func _draw_readout(center: Vector2, radius: float, speed: float) -> void:
	var col: Color = UiStyle.CYAN if absf(speed) < Game.MAX_SPEED * FAST_RATIO else UiStyle.AMBER
	var value_text := "+%.1f" % speed if speed > 0.05 else ("%.1f" % speed if speed < -0.05 else "0.0")
	draw_string(UiStyle.hud_font(), Vector2(center.x - radius, center.y + radius * 0.10), value_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 16, col)
	var direction_text := "前进" if speed > 0.05 else ("倒车" if speed < -0.05 else "停止")
	draw_string(UiStyle.hud_font(), Vector2(center.x-radius,center.y+radius*0.28),direction_text,HORIZONTAL_ALIGNMENT_CENTER,radius*2.0,10,UiStyle.MUTED)
