class_name MissionStatusBar
extends PanelContainer
## 两个岗位共用的底部任务状态：时间、共同进度和终点距离。

const MissionRouteRailScript = preload("res://scripts/ui/mission_route_rail.gd")

var _time: Label
var _progress: Control
var _progress_text: Label
var _distance: Label


func _ready() -> void:
	name = "MissionStatusBar"
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_left = 14.0
	offset_right = -14.0
	offset_top = -48.0
	offset_bottom = -10.0
	z_index = 40
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel",_box(Color(0.025,0.055,0.085,0.94),Color(UiStyle.CYAN,0.42),1,5,10.0))
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",10); row.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(row)
	_time=UiStyle.make_label("",12,UiStyle.AMBER); _time.custom_minimum_size.x=138; row.add_child(_time)
	var divider_a:=ColorRect.new(); divider_a.color=Color(UiStyle.CYAN,0.3); divider_a.custom_minimum_size=Vector2(1,18); divider_a.size_flags_vertical=Control.SIZE_SHRINK_CENTER; row.add_child(divider_a)
	row.add_child(UiStyle.make_label("共同航程",12,UiStyle.TEXT))
	_progress=MissionRouteRailScript.new() as Control
	row.add_child(_progress)
	_progress_text=UiStyle.make_label("0%",12,UiStyle.CYAN); _progress_text.custom_minimum_size.x=52; _progress_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(_progress_text)
	var divider_b:=ColorRect.new(); divider_b.color=Color(UiStyle.CYAN,0.3); divider_b.custom_minimum_size=Vector2(1,18); divider_b.size_flags_vertical=Control.SIZE_SHRINK_CENTER; row.add_child(divider_b)
	_distance=UiStyle.make_label("距终点 --",12,UiStyle.TEXT); _distance.custom_minimum_size.x=126; _distance.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; row.add_child(_distance)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _time == null:
		return
	if Game.mission_timer_active:
		var remaining:=maxf(Game.mission_time_limit_s-Game.mission_elapsed_s,0.0)
		_time.text="剩余时间  %d 秒" % int(ceil(remaining))
	else:
		_time.text="新手关  ·  不计时"
	var ratio:=Game.mission_progress_ratio()
	_progress.set("progress_ratio",ratio)
	_progress_text.text="%d%%" % int(round(ratio*100.0))
	_distance.text="距终点  %.0f" % Game.objective_distance()


func _box(fill: Color,border: Color,width: int,corner: int,margin: float) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new(); style.bg_color=fill; style.border_color=border; style.set_border_width_all(width); style.set_corner_radius_all(corner)
	style.content_margin_left=margin; style.content_margin_right=margin; style.content_margin_top=4.0; style.content_margin_bottom=4.0
	return style
