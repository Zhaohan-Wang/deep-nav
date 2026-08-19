class_name ThrustGauge
extends Control
## 中央推进表盘：中心是飞船俯视 icon，推进器点火用加速箭头表示——
## 主推在船尾后方叠出向前的箭头，倒车在船头前方叠出向后的箭头，
## 左右转向沿盘沿排出一段切向箭头弧。外圈弧线是船体完整度。

## 俯视姿态图约定：图片顶部就是船头；不旋转、不翻转。
const SHIP_TEXTURE_PATH: String = "res://assets/ui/cockpit/attitude_indicator.png"
## 船体环缺口留在正下方：从左下 135° 起沿顺时针扫 270°。
const HULL_ARC_START: float = 3.0 * PI / 4.0
const HULL_ARC_SPAN: float = 1.5 * PI
## 箭头亮度流动速度（周期 / 秒）。
const FLOW_SPEED: float = 1.6
## 船体低于该值时环变红。
const HULL_DANGER: float = 35.0
const CHIP_HOLD: float = 0.32
const CHIP_DURATION: float = 0.88
const HULL_SEGMENTS: int = 24
const HULL_HEALTHY := Color("55d8ca")
const HULL_CAUTION := Color("e7b65a")
const HULL_CRITICAL := Color("ef5b68")
const HULL_CHIP := Color("d97955")
const HULL_TRACK := Color("2b3a4d")

## 正式表盘背景图之后从这里换入；为空时画占位圆。
@export var bg_texture: Texture2D = null

var _ship_icon: Texture2D
var _time: float = 0.0
## 受击闪烁强度，随时间衰减。
var _flash: float = 0.0
var _visible_hull: float = 100.0
var _trailing_hull: float = 100.0
var _chip_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship_icon = load(SHIP_TEXTURE_PATH) as Texture2D
	_visible_hull=Game.hull
	_trailing_hull=Game.hull
	Game.hull_changed.connect(_on_hull_changed)


func _process(delta: float) -> void:
	_time += delta
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
	var width: float = clampf(radius * 0.085, 3.5, 7.5)
	# 24 段深蓝灰底槽：保持像素仪表感，同时比一根普通圆线更容易读出损失比例。
	_draw_segmented_arc(center,ring_r,0.0,1.0,Color(HULL_TRACK,0.62),width)
	var frac: float = clampf(_visible_hull / Game.MAX_HULL, 0.0, 1.0)
	var trailing_frac: float=clampf(_trailing_hull/Game.MAX_HULL,0.0,1.0)
	if trailing_frac>frac+0.001:
		# 只让被扣掉的区段发出暖色残光；真实耐久部分不再整圈染红。
		_draw_segmented_arc(center,ring_r,frac,trailing_frac,Color(HULL_CHIP,0.18),width+4.0)
		var chip_color:=HULL_CHIP.lerp(Color("ff9a66"),_flash*0.55)
		_draw_segmented_arc(center,ring_r,frac,trailing_frac,Color(chip_color,0.92),width)
	if frac <= 0.003:
		return
	var color:=_hull_color(frac)
	_draw_segmented_arc(center,ring_r,0.0,frac,Color(color,0.16),width+3.0)
	_draw_segmented_arc(center,ring_r,0.0,frac,color,width)
	# 当前值端点是唯一高亮焦点；受击只增强端点与损伤段，不污染整条健康弧。
	var end_angle:=HULL_ARC_START+HULL_ARC_SPAN*frac
	var end_pos:=center+Vector2(cos(end_angle),sin(end_angle))*ring_r
	draw_circle(end_pos,width*0.52,color.lerp(Color.WHITE,_flash*0.46))


func _draw_segmented_arc(center: Vector2,ring_r: float,from_fraction: float,to_fraction: float,
		color: Color,width: float) -> void:
	var from:=clampf(from_fraction,0.0,1.0)
	var to:=clampf(to_fraction,0.0,1.0)
	if to<=from+0.0001: return
	var cell:=1.0/float(HULL_SEGMENTS)
	var gap:=cell*0.18
	for i: int in range(HULL_SEGMENTS):
		var segment_from:=maxf(from,float(i)*cell+gap*0.5)
		var segment_to:=minf(to,float(i+1)*cell-gap*0.5)
		if segment_to<=segment_from: continue
		var angle_from:=HULL_ARC_START+HULL_ARC_SPAN*segment_from
		var angle_to:=HULL_ARC_START+HULL_ARC_SPAN*segment_to
		var points:=maxi(3,int(8.0*(segment_to-segment_from)/cell))
		draw_arc(center,ring_r,angle_from,angle_to,points,color,width,true)


func _hull_color(frac: float) -> Color:
	if frac>=0.50:
		return HULL_HEALTHY
	if frac>=0.25:
		return HULL_HEALTHY.lerp(HULL_CAUTION,(0.50-frac)/0.25)
	return HULL_CAUTION.lerp(HULL_CRITICAL,(0.25-frac)/0.25)


func _on_hull_changed(hull: float) -> void:
	var next:=clampf(hull,0.0,Game.MAX_HULL)
	if next<_visible_hull-0.001:
		_visible_hull=next
		_flash=1.0
		if _chip_tween!=null and _chip_tween.is_valid(): _chip_tween.kill()
		_chip_tween=create_tween()
		_chip_tween.tween_method(_set_trailing_hull,_trailing_hull,next,CHIP_DURATION) \
			.set_delay(CHIP_HOLD).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		_visible_hull=next
		_trailing_hull=next
		if _chip_tween!=null and _chip_tween.is_valid(): _chip_tween.kill()
	queue_redraw()


func _set_trailing_hull(value: float) -> void:
	_trailing_hull=maxf(value,_visible_hull)
	queue_redraw()


func current_hull() -> float:
	return _visible_hull


func trailing_hull() -> float:
	return _trailing_hull


func _draw_ship(center: Vector2, radius: float) -> void:
	if _ship_icon == null:
		return
	# 新姿态球本身就是圆形仪表，缩在船体耐久环以内，方向箭头向上对应船头。
	var h: float = radius*0.92
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
	var turn: float = Displays.pilot_turn_axis()
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
