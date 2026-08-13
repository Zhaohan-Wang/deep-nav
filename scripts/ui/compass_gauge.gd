class_name CompassGauge
extends Control
## 航向罗盘：刻度盘随航向转动（当前航向永远对着顶部固定指标），
## 航点相对方位用琥珀色菱形标在盘内侧，玩家不用再心算“左舷 23°”。

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
	var heading_deg: float = fposmod(rad_to_deg(Game.ship_heading), 360.0)
	_draw_ticks(center, radius, heading_deg)
	_draw_lubber(center, radius)
	_draw_waypoint(center, radius)
	_draw_readout(center, radius, heading_deg)


## 以正上方为 0、向右为正的极角转屏幕坐标。
func _pos_from_top(center: Vector2, theta: float, r: float) -> Vector2:
	return center + Vector2(sin(theta), -cos(theta)) * r


func _draw_ticks(center: Vector2, radius: float, heading_deg: float) -> void:
	for v: int in range(0, 360, 15):
		# 航向增大（左转）时刻度向右流动，和窗外世界的转动方向一致。
		var theta: float = deg_to_rad(heading_deg - float(v))
		var major: bool = v % 90 == 0
		var mid: bool = v % 45 == 0
		var outer: float = radius * 0.90
		var inner: float = radius * (0.74 if major else (0.80 if mid else 0.85))
		var col: Color = UiStyle.TEXT if major else Color(UiStyle.MUTED.r, UiStyle.MUTED.g, UiStyle.MUTED.b, 0.8)
		draw_line(_pos_from_top(center, theta, inner), _pos_from_top(center, theta, outer), col, 2.0 if major else 1.0)
		if major:
			var label_pos: Vector2 = _pos_from_top(center, theta, radius * 0.58)
			draw_string(UiStyle.hud_font(), label_pos + Vector2(-24.0, 4.0), str(v), HORIZONTAL_ALIGNMENT_CENTER, 48.0, 8, UiStyle.MUTED)


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


func _draw_waypoint(center: Vector2, radius: float) -> void:
	if not Game.has_waypoint:
		return
	var to: Vector3 = Game.waypoint - Game.ship_position
	to.y = 0.0
	if to.length_squared() < 0.25:
		return
	var desired: float = atan2(-to.x, -to.z)
	# delta > 0 表示航点在左舷。
	var delta: float = wrapf(desired - Game.ship_heading, -PI, PI)
	var p: Vector2 = _pos_from_top(center, -delta, radius * 0.66)
	# 中心到标记的淡线，帮助一眼读出偏角方向。
	draw_line(center, p, Color(UiStyle.AMBER.r, UiStyle.AMBER.g, UiStyle.AMBER.b, 0.25), 1.0)
	var s: float = maxf(radius * 0.07, 3.5)
	var points := PackedVector2Array([
		p + Vector2(0.0, -s),
		p + Vector2(s, 0.0),
		p + Vector2(0.0, s),
		p + Vector2(-s, 0.0),
	])
	draw_colored_polygon(points, UiStyle.AMBER)


func _draw_readout(center: Vector2, radius: float, heading_deg: float) -> void:
	var text: String = "%03d°" % (int(round(heading_deg)) % 360)
	draw_string(UiStyle.hud_font(), Vector2(center.x - radius, center.y + radius * 0.10), text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 16, UiStyle.CYAN)
