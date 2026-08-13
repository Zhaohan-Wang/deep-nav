class_name GaugeDraw
extends RefCounted
## 圆形仪表共用绘制工具：占位表盘底、加速箭头（chevron）。
## 表盘背景目前用代码画圈占位，之后换成正式贴图时只需给 bg 传入纹理。

## 表盘底完全不透明，驾驶舱仪表不透出后面的星空。
const DIAL_FILL: Color = Color(0.045, 0.055, 0.085, 1.0)
const DIAL_RIM: Color = Color(0.42, 0.50, 0.56, 0.85)
const DIAL_RIM_INNER: Color = Color(0.25, 0.30, 0.36, 0.50)


## 占位背景：深色实心圆 + 内外两圈描边；bg 非空时直接铺贴图。
static func draw_dial_bg(ci: CanvasItem, center: Vector2, radius: float, bg: Texture2D = null) -> void:
	if bg != null:
		var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		ci.draw_texture_rect(bg, rect, false)
		return
	ci.draw_circle(center, radius, DIAL_FILL)
	ci.draw_arc(center, radius - 1.0, 0.0, TAU, 72, DIAL_RIM, 2.0)
	ci.draw_arc(center, radius * 0.90, 0.0, TAU, 72, DIAL_RIM_INNER, 1.0)


## 单个加速箭头：V 形折线，尖端指向 dir。
## span 是两翼张开宽度，depth 是尖端到两翼的纵深。
static func draw_chevron(ci: CanvasItem, pos: Vector2, dir: Vector2, span: float, depth: float, color: Color, width: float = 2.0) -> void:
	var u: Vector2 = dir.normalized()
	var perp := Vector2(-u.y, u.x)
	var tip: Vector2 = pos + u * depth * 0.5
	var tail: Vector2 = pos - u * depth * 0.5
	var points := PackedVector2Array([
		tail + perp * span * 0.5,
		tip,
		tail - perp * span * 0.5,
	])
	ci.draw_polyline(points, color, width)


## 一串沿 dir 反方向排开的加速箭头（越远越靠后）。
## strength 控制整体亮度，phase 让亮度沿 dir 方向流动，形成“正在加速”的动感。
static func draw_accel_arrows(ci: CanvasItem, origin: Vector2, dir: Vector2, count: int, spacing: float, span: float, depth: float, color: Color, strength: float, phase: float) -> void:
	if strength <= 0.02:
		return
	var u: Vector2 = dir.normalized()
	for k: int in range(count):
		var wave: float = 0.5 + 0.5 * sin(TAU * (phase - float(k) / float(count)))
		var alpha: float = clampf(strength, 0.0, 1.0) * (0.30 + 0.70 * wave)
		var tint := Color(color.r, color.g, color.b, color.a * alpha)
		draw_chevron(ci, origin - u * spacing * float(k), dir, span, depth, tint)
