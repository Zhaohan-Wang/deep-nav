class_name DualStageColumn
extends Control
## 三维铺满整页；2D 做成小 16:9 显示器，作为 UI 叠在画面底部居中。

const ASPECT: float = 16.0 / 9.0
## 小显示器宽度占页面的比例，再用最大宽度卡住，避免全屏时变得过大。
const MONITOR_WIDTH_RATIO: float = 0.40
const MONITOR_MAX_WIDTH: float = 440.0
const MONITOR_MIN_WIDTH: float = 280.0
const BOTTOM_MARGIN: float = 14.0
const BANNER_GAP: float = 6.0

## 铺满的三维层。
var _world: Control
## 叠在上面的小显示器 / 仪表台。
var _monitor: Control
## 显示器上方的状态条，可为空。
var _banner: Control
## 显示器区域的宽高比与宽度约束，默认保持 16:9 小显示器；
## 驾驶员仪表台等更宽的面板可在 setup 前覆盖这些值。
var monitor_aspect: float = ASPECT
var monitor_width_ratio: float = MONITOR_WIDTH_RATIO
var monitor_max_width: float = MONITOR_MAX_WIDTH
var monitor_min_width: float = MONITOR_MIN_WIDTH
## 显示器底边相对页面高度的位置（1 = 贴底，0.8 = 底边抬到 80% 高度处）。
var monitor_bottom_ratio: float = 1.0


func setup(world: Control, monitor: Control, banner: Control = null) -> void:
	_world = world
	_monitor = monitor
	_banner = banner
	add_child(_world)
	add_child(_monitor)
	if _banner != null:
		add_child(_banner)
	call_deferred("_place")


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

	var monitor_w: float = clampf(col_w * monitor_width_ratio, monitor_min_width, monitor_max_width)
	monitor_w = minf(monitor_w, maxf(col_w - 24.0, 64.0))
	var monitor_h: float = monitor_w / maxf(monitor_aspect, 0.01)
	var monitor_x: float = (col_w - monitor_w) * 0.5
	var monitor_y: float = maxf(col_h * monitor_bottom_ratio - monitor_h - BOTTOM_MARGIN, 4.0)
	_monitor.position = Vector2(monitor_x, monitor_y)
	_monitor.size = Vector2(monitor_w, monitor_h)

	if _banner != null:
		var banner_h: float = maxf(_banner.get_combined_minimum_size().y, 36.0)
		_banner.position = Vector2(monitor_x, monitor_y - banner_h - BANNER_GAP)
		_banner.size = Vector2(monitor_w, banner_h)
