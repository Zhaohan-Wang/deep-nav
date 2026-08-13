class_name NavigatorView
extends Control
## 领航员整页为 16:9 三维；星图是叠在画面上的小 16:9 显示器。

var view_host: Control
var _map: SectorMap
var _status: Label
var _help: Label
var _stages: DualStageColumn


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_build()
	Game.ship_state_changed.connect(_on_ship_state)
	Game.waypoint_changed.connect(_on_waypoint)
	Game.destination_reached.connect(_on_arrived)
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

	# 不透明圆角状态条，留足两行文字的高度。
	var banner: PanelContainer = UiStyle.make_round_panel()
	banner.custom_minimum_size = Vector2(0.0, 68.0)

	var banner_col := VBoxContainer.new()
	banner_col.add_theme_constant_override("separation", 4)
	banner_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(banner_col)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	status_row.add_child(UiStyle.make_icon("minimap", UiStyle.CYAN, 16.0))
	_status = UiStyle.make_label("", 12, UiStyle.TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status)
	banner_col.add_child(status_row)

	var help_row := HBoxContainer.new()
	help_row.add_theme_constant_override("separation", 8)
	help_row.add_child(UiStyle.make_icon("signal", UiStyle.AMBER, 16.0))
	_help = UiStyle.make_label("", 12, UiStyle.MUTED)
	_help.autowrap_mode = TextServer.AUTOWRAP_OFF
	_help.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_row.add_child(_help)
	banner_col.add_child(help_row)

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


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_nav_deck") and _stages != null:
		_stages.toggle_deck()
		get_viewport().set_input_as_handled()


func _on_map_waypoint(world_pos: Vector3) -> void:
	Game.set_waypoint(world_pos)


func _on_ship_state(position: Vector3, heading: float, speed: float, _throttle: float) -> void:
	var deg: int = int(round(rad_to_deg(heading)))
	if deg < 0:
		deg += 360
	var dest: CelestialBodyData = Game.objective_body()
	var dest_dist: float = 0.0
	var dest_name: String = "目标"
	if dest != null:
		dest_dist = Vector3(dest.world_position.x - position.x, 0.0, dest.world_position.z - position.z).length()
		dest_name = dest.display_name
	var sector_name: String = "扇区"
	if Game.current_sector != null:
		sector_name = Game.current_sector.display_name
	_status.text = "%s  %4.0f,%4.0f  %03d°  %.1f  距%s %.0f" % [
		sector_name, position.x, position.z, deg, speed, dest_name, dest_dist
	]


func _show_briefing() -> void:
	if Game.current_sector == null:
		return
	_help.text = Game.current_sector.briefing
	_help.add_theme_color_override("font_color", UiStyle.AMBER)


func _on_waypoint(world_pos: Vector3, enabled: bool) -> void:
	if enabled:
		_help.text = "航点 (%.0f, %.0f)  左键可改" % [world_pos.x, world_pos.z]
		_help.add_theme_color_override("font_color", UiStyle.AMBER)
	else:
		_show_briefing()


func _on_arrived() -> void:
	_status.text = "合同完成  ·  已进入绿洲近空"
	_status.add_theme_color_override("font_color", UiStyle.CYAN)
	_help.text = "航程完成。R 可再飞一趟。"
	_help.add_theme_color_override("font_color", UiStyle.CYAN)
