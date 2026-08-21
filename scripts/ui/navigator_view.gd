class_name NavigatorView
extends Control
## 领航员整页为 16:9 三维；星图是叠在画面上的小 16:9 显示器。

const HID_KEY_E: int = 0x08
const MissionStatusBarScript = preload("res://scripts/ui/mission_status_bar.gd")
const ExperimentNoticeBannerScript = preload("res://scripts/ui/experiment_notice_banner.gd")

var view_host: Control
var _map: SectorMap
var _status: Label
var _help: Label
var _stages: DualStageColumn
var _notice_serial: int = 0
var _experiment_banner: Control
var _waypoint_feedback_active: bool = false
var _waypoint_feedback_prefix: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	Game.ship_state_changed.connect(_on_ship_state)
	Game.waypoint_changed.connect(_on_waypoint)
	Game.waypoint_request_result.connect(_on_waypoint_result)
	Game.destination_reached.connect(_on_arrived)
	Game.relay_station_reached.connect(_on_relay_reached)
	RawMice.key_changed.connect(_on_keyboard_key)
	_on_ship_state(Game.ship_position, Game.ship_heading, Game.ship_speed, Game.throttle)
	_show_briefing()


func _build() -> void:
	var bg: ColorRect = UiStyle.make_color_rect(UiStyle.BG)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	view_host = Control.new()
	view_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map = SectorMap.new()
	_map.waypoint_requested.connect(_on_map_waypoint)
	var monitor: Control = UiStyle.make_framed_fill(_map, "")

	# 航行状态和当前提示合并为一条，避免控制台上方再占两行空间。
	var banner: PanelContainer = UiStyle.make_round_panel()
	banner.custom_minimum_size = Vector2(0.0, 44.0)

	var banner_row := HBoxContainer.new()
	banner_row.add_theme_constant_override("separation",8)
	banner_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(banner_row)
	banner_row.add_child(UiStyle.make_icon("minimap",UiStyle.CYAN,16.0))
	_status = UiStyle.make_label("", 12, UiStyle.TEXT)
	_status.custom_minimum_size = Vector2(170.0,0.0)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_stretch_ratio = 0.42
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	banner_row.add_child(_status)
	var divider := ColorRect.new()
	divider.color = Color(UiStyle.CYAN,0.28)
	divider.custom_minimum_size = Vector2(1.0,18.0)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_row.add_child(divider)
	_help = UiStyle.make_label("", 12, UiStyle.MUTED)
	_help.autowrap_mode = TextServer.AUTOWRAP_OFF
	_help.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help.size_flags_stretch_ratio = 0.58
	_help.clip_text = true
	banner_row.add_child(_help)

	var stages := DualStageColumn.new()
	_stages = stages
	# 小地图整体放大一档。
	stages.monitor_width_ratio = 0.47
	stages.monitor_max_width = 540.0
	stages.monitor_min_width = 320.0
	# 状态条和小屏一起略微后仰，垫在控制台上。
	stages.hud_pitch = 0.88
	stages.hud_top_scale = 0.90
	stages.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stages)
	stages.setup(
		view_host,
		monitor,
		banner,
		UiStyle.make_view_overlay(UiStyle.NAV_VIEW_PATH),
		UiStyle.make_view_overlay(UiStyle.NAV_HAND_PATH)
	)
	add_child(UiStyle.make_role_badge(UiStyle.NAVIGATOR_BADGE_PATH))
	add_child(MissionStatusBarScript.new())
	_experiment_banner = ExperimentNoticeBannerScript.new()
	add_child(_experiment_banner)


func _process(_delta: float) -> void:
	if _waypoint_feedback_active:
		_refresh_waypoint_feedback()


func _unhandled_input(event: InputEvent) -> void:
	# 对已识别的席位使用固定 HID 分流；如果领航席键盘未成功枚举，则允许
	# macOS 合并键盘事件兜底，避免鼠标桥正常但 E 键完全失效。
	var navigator_seat := 0 if Displays.role_for_seat(0)==Displays.Role.NAVIGATOR else 1
	if event.is_action_pressed("toggle_nav_deck") and not RawMice.has_live_keyboard_input(navigator_seat):
		_toggle_map(0,"system_fallback")
		get_viewport().set_input_as_handled()


func _on_keyboard_key(seat: int,usage: int,pressed: bool) -> void:
	if not pressed or usage!=HID_KEY_E or Displays.role_for_seat(seat)!=Displays.Role.NAVIGATOR:
		return
	_toggle_map(seat,"hid")


func _toggle_map(seat: int,source: String) -> void:
	if _stages==null:
		return
	_stages.toggle_deck()
	ExperimentLog.log_event("navigator_map_toggle","navigator",{
		"seat":seat,"source":source,"raised":_stages.deck_raised,
		"keyboard":RawMice.keyboard_name(seat),
	})


func _on_map_waypoint(world_pos: Vector3) -> void:
	Game.set_waypoint(world_pos)


func _on_ship_state(_position: Vector3, heading: float, speed: float, _throttle: float) -> void:
	var deg: int = int(round(rad_to_deg(heading)))
	if deg < 0:
		deg += 360
	_status.text = "航向 %03d°  ·  航速 %.1f" % [deg,speed]
	if Game.boundary_proximity > 0.08:
		_status.text = "边界告警  ·  立即返航"
		_status.add_theme_color_override("font_color",UiStyle.DANGER)
	else:
		_status.add_theme_color_override("font_color",UiStyle.TEXT)


func _show_briefing() -> void:
	if Game.current_sector == null:
		return
	var briefing := Game.current_sector.participant_briefing if not Game.current_sector.participant_briefing.is_empty() else "抵达指定目标航区。"
	_help.text = "%s · 按 E 开关星图" % briefing
	_help.add_theme_color_override("font_color", UiStyle.AMBER)


func _on_waypoint(world_pos: Vector3, enabled: bool) -> void:
	if enabled:
		_help.text = "航点 (%.0f, %.0f)  左键可改" % [world_pos.x, world_pos.z]
		_help.add_theme_color_override("font_color", UiStyle.AMBER)
	else:
		_waypoint_feedback_active = false
		_show_briefing()


func _on_waypoint_result(accepted: bool,reason: String,_remaining_s: float) -> void:
	if accepted:
		_waypoint_feedback_active = true
		_waypoint_feedback_prefix = "航点已按该方向放在最远位置" if reason == "clamped_range" else "航点已设置"
		_refresh_waypoint_feedback()
		return
	match reason:
		"cooldown":
			_waypoint_feedback_active = true
			_waypoint_feedback_prefix = "当前航点保持不变"
			_refresh_waypoint_feedback()
			return
		"boundary": _help.text="航点无效：目标位于边界排斥区"
		_: _help.text="航点无效"
	_waypoint_feedback_active = false
	_help.add_theme_color_override("font_color",UiStyle.DANGER)


func _refresh_waypoint_feedback() -> void:
	var state := Game.waypoint_cooldown_display_state()
	if state == "cooling":
		_help.text = "%s · 冷却 %.1f 秒" % [_waypoint_feedback_prefix, Game.waypoint_cooldown_remaining()]
		_help.add_theme_color_override("font_color",UiStyle.AMBER)
	elif state == "ready":
		_help.text = "航点已就绪 · 可重新测算"
		_help.add_theme_color_override("font_color",Color("5fe08a"))
	else:
		_waypoint_feedback_active = false


func _on_relay_reached(_index: int, _position: Vector3, station_name: String) -> void:
	_waypoint_feedback_active = false
	_help.text = "已抵达%s · 解体后将从此处继续" % station_name
	_help.add_theme_color_override("font_color", UiStyle.CYAN)


func show_experiment_notice(message: String) -> void:
	if _experiment_banner != null:
		_experiment_banner.call("show_message",message,3.0)


func _on_arrived() -> void:
	_status.text = "合同完成  ·  已进入绿洲近空"
	_status.add_theme_color_override("font_color", UiStyle.CYAN)
	_help.text = "航程完成。R 可再飞一趟。"
	_help.add_theme_color_override("font_color", UiStyle.CYAN)
