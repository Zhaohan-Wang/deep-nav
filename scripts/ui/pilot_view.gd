class_name PilotView
extends Control
## 驾驶员整页为 16:9 三维；底部是三块圆形仪表组成的仪表台
## （左：航向罗盘，中：推进表盘 + 船体环，右：航速盘），
## 仪表台上方只留一条精简状态行（告警 / 航点距离 / 船体读数）。

## 仪表台区域的宽高比与宽度约束：约等于中盘 + 两侧盘横排的外接矩形。
## 宽度占页面一半以上，整体抬到偏居中的位置，底部留给 3D 摇杆和之后的猴子手。
const DASH_ASPECT: float = 2.8
const DASH_WIDTH_RATIO: float = 0.66
const DASH_MAX_WIDTH: float = 920.0
const DASH_MIN_WIDTH: float = 420.0
const DASH_BOTTOM_RATIO: float = 0.80
const MissionStatusBarScript = preload("res://scripts/ui/mission_status_bar.gd")
const ExperimentNoticeBannerScript = preload("res://scripts/ui/experiment_notice_banner.gd")

## 告警优先级：抵达 / 解体 > 刚撞上 > 接近障碍 > 默认指挥提示。
enum AlertKind {
	IDLE,
	PROXIMITY,
	IMPACT,
	RELAY,
	DESTROYED,
	ARRIVED,
}

## 实际撞上后，警告再多停这一会儿，然后按距离决定是否收回。
const IMPACT_HOLD: float = 1.6
const RELAY_HOLD: float = 3.6
## 离致死行星表面多近开始亮「撞击警告」，带一点回差避免边缘闪烁。
const PROXIMITY_WARN_DISTANCE: float = 14.0
const PROXIMITY_ENTER: float = 0.28
const PROXIMITY_EXIT: float = 0.10

var porthole_host: Control
var stick_host: Control
var _dashboard: PilotDashboard
var _alert: Label
var _alert_icon: TextureRect
var _range_label: Label
var _hull_label: Label
var _alert_kind: int = AlertKind.IDLE
var _impact_hold: float = 0.0
var _relay_hold: float = 0.0
var _experiment_hold: float = 0.0
var _experiment_notice: String = ""
var _experiment_banner: Control
var _proximity_on: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	Game.ship_state_changed.connect(_on_ship_state)
	Game.hull_changed.connect(_on_hull)
	Game.ship_hit.connect(_on_hit)
	Game.ship_exploded.connect(_on_exploded)
	Game.destination_reached.connect(_on_arrived)
	Game.relay_station_reached.connect(_on_relay_reached)
	_on_ship_state(Game.ship_position, Game.ship_heading, Game.ship_speed, Game.throttle)
	_on_hull(Game.hull)


func _build() -> void:
	var bg: ColorRect = UiStyle.make_color_rect(UiStyle.BG)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	porthole_host = Control.new()
	porthole_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dashboard = PilotDashboard.new()

	var stages := DualStageColumn.new()
	stages.monitor_aspect = DASH_ASPECT
	stages.monitor_width_ratio = DASH_WIDTH_RATIO
	stages.monitor_max_width = DASH_MAX_WIDTH
	stages.monitor_min_width = DASH_MIN_WIDTH
	stages.monitor_bottom_ratio = DASH_BOTTOM_RATIO
	stages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stages)
	stages.setup(porthole_host, _dashboard, _make_banner(), UiStyle.make_view_overlay(UiStyle.PILOT_VIEW_PATH))
	add_child(UiStyle.make_role_badge(UiStyle.PILOT_BADGE_PATH))
	add_child(MissionStatusBarScript.new())
	_experiment_banner = ExperimentNoticeBannerScript.new()
	add_child(_experiment_banner)

	# 3D 摇杆单独一层，压在 Pad View / 仪表 / 徽章上面，白屏遮罩仍在其上。
	stick_host = Control.new()
	stick_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stick_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stick_host.z_index = 32
	add_child(stick_host)


## 仪表台上方的状态条：不透明圆角矩形，告警文本（左）、航点距离（中右）、船体读数（右）。
## 驾驶员不显示具体任务目标，只听领航员指挥。
func _make_banner() -> Control:
	var banner: PanelContainer = UiStyle.make_round_panel()
	banner.custom_minimum_size = Vector2(0.0, 38.0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(row)

	_alert_icon = UiStyle.make_icon("signal", UiStyle.MUTED, 16.0)
	row.add_child(_alert_icon)
	_alert = UiStyle.make_label(_default_alert_text(), 12, UiStyle.MUTED)
	_alert.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_alert.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_alert)

	row.add_child(UiStyle.make_icon("target", UiStyle.MUTED, 16.0))
	_range_label = UiStyle.make_label("航点 --", 12, UiStyle.MUTED)
	row.add_child(_range_label)

	row.add_child(UiStyle.make_icon("heart", UiStyle.AMBER, 16.0))
	_hull_label = UiStyle.make_label("100", 12, UiStyle.AMBER)
	row.add_child(_hull_label)
	return banner


func _default_alert_text() -> String:
	return "请听从领航员指挥"


func _process(delta: float) -> void:
	if _alert_kind == AlertKind.ARRIVED or _alert_kind == AlertKind.DESTROYED:
		return
	if _impact_hold > 0.0:
		_impact_hold = maxf(0.0, _impact_hold - delta)
	if _relay_hold > 0.0:
		_relay_hold = maxf(0.0, _relay_hold - delta)
	if _experiment_hold > 0.0:
		_experiment_hold = maxf(0.0,_experiment_hold-delta)
	_refresh_alert()


## 只在「刚撞上」或「马上要撞」时亮警告，飞开就收回默认提示。
func _refresh_alert() -> void:
	if _alert_kind == AlertKind.ARRIVED or _alert_kind == AlertKind.DESTROYED:
		return
	var near: bool = _update_proximity()
	if _impact_hold > 0.0:
		_apply_alert(AlertKind.IMPACT, "撞击警告", "impact", UiStyle.DANGER)
		return
	if _experiment_hold > 0.0:
		_apply_alert(AlertKind.RELAY,_experiment_notice,"signal",UiStyle.AMBER)
		return
	if _relay_hold > 0.0:
		return
	if Game.boundary_proximity > 0.08:
		_apply_alert(AlertKind.PROXIMITY, "边界排斥区 · 请返回航区", "impact", UiStyle.DANGER)
		return
	if near:
		_apply_alert(AlertKind.PROXIMITY, "撞击警告", "impact", UiStyle.DANGER)
		return
	_apply_alert(AlertKind.IDLE, _default_alert_text(), "signal", UiStyle.MUTED)


func show_experiment_notice(message: String) -> void:
	if _experiment_banner != null:
		_experiment_banner.call("show_message",message,3.0)


## 接近致死行星时为 true；带进入/退出回差，避免在警戒圈边缘来回跳。
func _update_proximity() -> bool:
	var factor: float = _proximity_factor()
	if _proximity_on:
		_proximity_on = factor >= PROXIMITY_EXIT
	else:
		_proximity_on = factor >= PROXIMITY_ENTER
	return _proximity_on


## 0..1：离最近致死天体表面有多近。终点和已死/已完成不算。
func _proximity_factor() -> float:
	if not Game.ship_alive or Game.mission_complete:
		return 0.0
	var worst: float = Game.boundary_proximity
	for body: CelestialBodyData in Game.celestial_bodies:
		if body.kind == CelestialBodyData.Kind.DESTINATION:
			continue
		var to := Vector3(
			body.world_position.x - Game.ship_position.x,
			0.0,
			body.world_position.z - Game.ship_position.z
		)
		var gap: float = to.length() - body.collision_radius - Game.SHIP_RADIUS
		worst = maxf(worst, clampf(1.0 - gap / PROXIMITY_WARN_DISTANCE, 0.0, 1.0))
	return worst


func _on_ship_state(position: Vector3, _heading: float, _speed: float, _throttle: float) -> void:
	# 航点方位已画在罗盘盘沿，这里只更新距离读数。
	if Game.mission_complete:
		return
	if Game.has_waypoint:
		var to: Vector3 = Game.waypoint - position
		to.y = 0.0
		_range_label.text = "航点 %.0f" % to.length()
		_range_label.add_theme_color_override("font_color", UiStyle.AMBER)
	else:
		_range_label.text = "航点 --"
		_range_label.add_theme_color_override("font_color", UiStyle.MUTED)


func _on_hull(hull: float) -> void:
	_hull_label.text = "%d" % int(round(hull))
	var color: Color = UiStyle.AMBER if hull > 35.0 else UiStyle.DANGER
	_hull_label.add_theme_color_override("font_color", color)
	# 重开一局船体回满：清掉解体/撞击残留，再按当前距离决定要不要警告。
	if hull >= Game.MAX_HULL - 0.1 and _alert_kind != AlertKind.ARRIVED:
		_impact_hold = 0.0
		_proximity_on = false
		_alert_kind = AlertKind.IDLE
		_refresh_alert()


func _on_hit(_remaining: float) -> void:
	if _alert_kind == AlertKind.ARRIVED or _alert_kind == AlertKind.DESTROYED:
		return
	_impact_hold = IMPACT_HOLD
	_refresh_alert()


func _on_relay_reached(_index: int, _position: Vector3, station_name: String) -> void:
	if _alert_kind == AlertKind.ARRIVED or _alert_kind == AlertKind.DESTROYED:
		return
	_relay_hold = RELAY_HOLD
	_apply_alert(AlertKind.RELAY, "已抵达%s" % station_name, "signal", UiStyle.CYAN)


func _on_exploded(_pos: Vector3) -> void:
	_impact_hold = 0.0
	_apply_alert(AlertKind.DESTROYED, "船体解体", "skull", UiStyle.DANGER)


func _on_arrived() -> void:
	_impact_hold = 0.0
	_apply_alert(AlertKind.ARRIVED, "已抵达绿洲", "star", UiStyle.CYAN)
	_range_label.text = "航程完成"
	_range_label.add_theme_color_override("font_color", UiStyle.CYAN)


func _apply_alert(kind: int, text: String, icon_name: String, color: Color) -> void:
	if _alert_kind == kind and _alert != null and _alert.text == text:
		return
	_alert_kind = kind
	_alert.text = text
	_alert.add_theme_color_override("font_color", color)
	if _alert_icon != null:
		_alert_icon.texture = UiStyle.icon_texture(icon_name)
		_alert_icon.modulate = color
