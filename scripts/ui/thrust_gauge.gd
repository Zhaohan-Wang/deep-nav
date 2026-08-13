class_name ThrustGauge
extends Control
## 中央推进表盘：中心是飞船俯视 icon，推进器点火用加速箭头表示——
## 主推在船尾后方叠出向前的箭头，倒车在船头前方叠出向后的箭头，
## 左右转向沿盘沿排出一段切向箭头弧。外圈弧线是船体完整度。

const SHIP_TEXTURE_PATH: String = "res://assets/ships/base/Scout.png"
## 船体环缺口留在正下方：从左下 135° 起沿顺时针扫 270°。
const HULL_ARC_START: float = 3.0 * PI / 4.0
const HULL_ARC_SPAN: float = 1.5 * PI
## 箭头亮度流动速度（周期 / 秒）。
const FLOW_SPEED: float = 1.6
## 船体低于该值时环变红。
const HULL_DANGER: float = 35.0

## 正式表盘背景图之后从这里换入；为空时画占位圆。
@export var bg_texture: Texture2D = null

var _ship_icon: Texture2D
var _time: float = 0.0
## 受击闪烁强度，随时间衰减。
var _flash: float = 0.0
var _last_hull: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship_icon = load(SHIP_TEXTURE_PATH) as Texture2D
	_last_hull = Game.hull


func _process(delta: float) -> void:
	_time += delta
	# 靠船体值下降沿触发闪烁，不用额外接信号。
	if Game.hull < _last_hull - 0.01:
		_flash = 1.0
	_last_hull = Game.hull
	_flash = move_toward(_flash, 0.0, delta * 1.6)
	queue_redraw()


func _draw() -> void:
	var radius: float = minf(size.x, size.y) * 0.5 - 2.0
	if radius < 8.0:
		return
	var center: Vector2 = size * 0.5
	GaugeDraw.draw_dial_bg(self, center, radius, bg_texture)
	_draw_hull_ring(center, radius)
	_draw_ship(center, radius)
	_draw_main_thrust(center, radius)
	_draw_turn_thrust(center, radius)


func _draw_hull_ring(center: Vector2, radius: float) -> void:
	var ring_r: float = radius * 0.93
	var width: float = clampf(radius * 0.07, 2.5, 6.0)
	var track := Color(UiStyle.MUTED.r, UiStyle.MUTED.g, UiStyle.MUTED.b, 0.28)
	draw_arc(center, ring_r, HULL_ARC_START, HULL_ARC_START + HULL_ARC_SPAN, 72, track, width)
	var frac: float = clampf(Game.hull / Game.MAX_HULL, 0.0, 1.0)
	if frac <= 0.003:
		return
	var color: Color = UiStyle.AMBER if Game.hull > HULL_DANGER else UiStyle.DANGER
	color = color.lerp(UiStyle.DANGER, _flash)
	var segments: int = maxi(8, int(72.0 * frac))
	draw_arc(center, ring_r, HULL_ARC_START, HULL_ARC_START + HULL_ARC_SPAN * frac, segments, color, width)


func _draw_ship(center: Vector2, radius: float) -> void:
	if _ship_icon == null:
		return
	# 贴图四周有透明留白，画满一点实际船体才够大。
	var h: float = radius * 1.02
	var aspect: float = float(_ship_icon.get_width()) / float(_ship_icon.get_height())
	var w: float = h * aspect
	# 受击时飞船 icon 短暂泛红，与船体环闪烁同步。
	var tint: Color = Color.WHITE.lerp(UiStyle.DANGER, _flash * 0.8)
	draw_texture_rect(_ship_icon, Rect2(center - Vector2(w, h) * 0.5, Vector2(w, h)), false, tint)


func _draw_main_thrust(center: Vector2, radius: float) -> void:
	var throttle: float = Game.throttle
	var phase: float = _time * FLOW_SPEED
	if throttle > 0.03:
		# 主引擎：船尾后方一串向前的加速箭头。
		var origin: Vector2 = center + Vector2(0.0, radius * 0.52)
		GaugeDraw.draw_accel_arrows(self, origin, Vector2.UP, 3, radius * 0.14, radius * 0.30, radius * 0.13, UiStyle.CYAN, throttle, phase)
	elif throttle < -0.03:
		# 反推：船头前方一串向后的箭头，用琥珀色区分。
		var origin: Vector2 = center + Vector2(0.0, -radius * 0.52)
		GaugeDraw.draw_accel_arrows(self, origin, Vector2.DOWN, 3, radius * 0.14, radius * 0.26, radius * 0.12, UiStyle.AMBER, -throttle, phase)


func _draw_turn_thrust(center: Vector2, radius: float) -> void:
	# 正值 = 左转（与飞船输入轴一致）。
	var turn: float = Input.get_axis("turn_right", "turn_left")
	if absf(turn) < 0.05:
		return
	var phase: float = _time * FLOW_SPEED
	var arc_r: float = radius * 0.62
	var strength: float = absf(turn)
	var side: float = 1.0 if turn > 0.0 else -1.0
	for k: int in range(3):
		# 从船头两侧沿盘沿往转向侧排开；theta 以正上方为 0，向右为正。
		var theta: float = -side * deg_to_rad(26.0 + 20.0 * float(k))
		var pos: Vector2 = center + Vector2(sin(theta), -cos(theta)) * arc_r
		# 沿圆周的切向：左转指向逆时针，右转指向顺时针。
		var tangent: Vector2 = Vector2(cos(theta), sin(theta)) * -side
		var wave: float = 0.5 + 0.5 * sin(TAU * (phase - float(k) / 3.0))
		var alpha: float = strength * (0.30 + 0.70 * wave)
		var tint := Color(UiStyle.CYAN.r, UiStyle.CYAN.g, UiStyle.CYAN.b, alpha)
		GaugeDraw.draw_chevron(self, pos, tangent, radius * 0.22, radius * 0.11, tint)
