class_name DualStageColumn
extends Control
## 三维铺满整页；舱内画面垫在三维之上、UI 之下；2D 显示器再叠在最上面。

const ASPECT: float = 16.0 / 9.0
## 小显示器宽度占页面的比例，再用最大宽度卡住，避免全屏时变得过大。
const MONITOR_WIDTH_RATIO: float = 0.40
const MONITOR_MAX_WIDTH: float = 440.0
const MONITOR_MIN_WIDTH: float = 280.0
const BOTTOM_MARGIN: float = 14.0
const BANNER_GAP: float = 6.0
const DECK_DURATION: float = 0.4
## 放下时屏幕再后仰一点，像往台面推出去。
const DECK_STOW_PITCH: float = 0.62
const DECK_STOW_TOP_SCALE: float = 0.72

## 铺满的三维层。
var _world: Control
## 舱内画面，垫在三维上面、所有 UI 下面。
var _overlay: Control
## 舱内手势等，叠在舱体上面、UI 下面。
var _midground: Control
## 叠在上面的小显示器 / 仪表台。
var _monitor: Control
## 显示器上方的状态条，可为空。
var _banner: Control
## 透视后的 HUD 宿主；为空表示保持平面。
var _tilt: PerspectiveHud
var _hud_stack: Control
## 显示器区域的宽高比与宽度约束，默认保持 16:9 小显示器；
## 驾驶员仪表台等更宽的面板可在 setup 前覆盖这些值。
var monitor_aspect: float = ASPECT
var monitor_width_ratio: float = MONITOR_WIDTH_RATIO
var monitor_max_width: float = MONITOR_MAX_WIDTH
var monitor_min_width: float = MONITOR_MIN_WIDTH
## 显示器底边相对页面高度的位置（1 = 贴底，0.8 = 底边抬到 80% 高度处）。
var monitor_bottom_ratio: float = 1.0
## < 1 时把状态条和小屏一起压成后仰梯形，腾出圆形窗口。
var hud_pitch: float = 1.0
## < 1 时梯形顶边收窄，形成透视。
var hud_top_scale: float = 1.0
## 抬起/放下：1 为现在的台面状态，0 为手和屏幕都收出画面。
var deck_raised: bool = true
var _deck_t: float = 1.0
var _mid_rest: Vector2 = Vector2.ZERO
var _tilt_rest: Vector2 = Vector2.ZERO


func setup(world: Control, monitor: Control, banner: Control = null, overlay: Control = null, midground: Control = null) -> void:
	_world = world
	_overlay = overlay
	_midground = midground
	_monitor = monitor
	_banner = banner
	add_child(_world)
	if _overlay != null:
		add_child(_overlay)
	if _midground != null:
		add_child(_midground)
	if _uses_tilt():
		_hud_stack = Control.new()
		_hud_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud_stack.add_child(_monitor)
		if _banner != null:
			_hud_stack.add_child(_banner)
		_tilt = PerspectiveHud.new()
		_tilt.pitch = hud_pitch
		_tilt.top_scale = hud_top_scale
		add_child(_tilt)
		_tilt.setup(_hud_stack)
	else:
		add_child(_monitor)
		if _banner != null:
			add_child(_banner)
	set_process(_midground != null or _tilt != null)
	clip_contents = true
	call_deferred("_place")


func toggle_deck() -> void:
	set_deck_raised(not deck_raised)


func set_deck_raised(raised: bool) -> void:
	deck_raised = raised
	set_process(true)


func _uses_tilt() -> bool:
	return hud_pitch < 0.999 or hud_top_scale < 0.999


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


func _place() -> void:
	if _world == null or _monitor == null:
		return
	var col_w: float = size.x
	var col_h: float = size.y
	if col_w < 2.0 or col_h < 2.0:
		return
	_world.position = Vector2.ZERO
	_world.size = Vector2(col_w, col_h)
	if _overlay != null:
		_overlay.position = Vector2.ZERO
		_overlay.size = Vector2(col_w, col_h)
	if _midground != null:
		_mid_rest = Vector2.ZERO
		_midground.size = Vector2(col_w, col_h)

	var monitor_w: float = clampf(col_w * monitor_width_ratio, monitor_min_width, monitor_max_width)
	monitor_w = minf(monitor_w, maxf(col_w - 24.0, 64.0))
	var monitor_h: float = monitor_w / maxf(monitor_aspect, 0.01)
	var monitor_x: float = (col_w - monitor_w) * 0.5
	var monitor_y: float = maxf(col_h * monitor_bottom_ratio - monitor_h - BOTTOM_MARGIN, 4.0)

	var banner_h: float = 0.0
	var gap: float = 0.0
	if _banner != null:
		banner_h = maxf(_banner.get_combined_minimum_size().y, 36.0)
		gap = BANNER_GAP

	if _tilt != null:
		var hud_h: float = banner_h + gap + monitor_h
		var hud_y: float = monitor_y - banner_h - gap
		_tilt_rest = Vector2(monitor_x, hud_y)
		_tilt.size = Vector2(monitor_w, hud_h)
		_tilt.set_content_size(Vector2(monitor_w, hud_h))
		if _banner != null:
			_banner.position = Vector2.ZERO
			_banner.size = Vector2(monitor_w, banner_h)
			_monitor.position = Vector2(0.0, banner_h + gap)
		else:
			_monitor.position = Vector2.ZERO
		_monitor.size = Vector2(monitor_w, monitor_h)
		_apply_deck_pose()
		return

	_monitor.position = Vector2(monitor_x, monitor_y)
	_monitor.size = Vector2(monitor_w, monitor_h)
	if _banner != null:
		_banner.position = Vector2(monitor_x, monitor_y - banner_h - gap)
		_banner.size = Vector2(monitor_w, banner_h)
	_apply_deck_pose()


func _process(delta: float) -> void:
	var target: float = 1.0 if deck_raised else 0.0
	if is_equal_approx(_deck_t, target):
		return
	_deck_t = move_toward(_deck_t, target, delta / DECK_DURATION)
	_apply_deck_pose()


func _deck_k() -> float:
	var t: float = clampf(_deck_t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _apply_deck_pose() -> void:
	var k: float = _deck_k()
	var drop: float = 1.0 - k
	if _midground != null:
		_midground.position = _mid_rest + Vector2(0.0, size.y * 0.55 * drop)
		_midground.modulate.a = k
		_midground.visible = k > 0.001
	if _tilt != null:
		_tilt.position = _tilt_rest + Vector2(0.0, (_tilt.size.y + 36.0) * drop)
		_tilt.modulate.a = k
		_tilt.visible = k > 0.001
		_tilt.mouse_filter = Control.MOUSE_FILTER_STOP if k > 0.2 else Control.MOUSE_FILTER_IGNORE
		_tilt.set_pose(
			lerpf(DECK_STOW_PITCH, hud_pitch, k),
			lerpf(DECK_STOW_TOP_SCALE, hud_top_scale, k)
		)
