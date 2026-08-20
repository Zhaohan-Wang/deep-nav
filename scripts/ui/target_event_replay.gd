class_name TargetEventReplay
extends Control
## 两组共用的标准化目标异常回放。轨迹只由异常类型和固定协议参数生成，
## 不读取参与者实际操作，因此明确/模糊条件之间除诊断文字外完全一致。

signal playback_finished

const DURATION_S := 7.0
const EVENT_TIME_S := 3.0

var event_type := ""
var condition := ""
var elapsed_s := 0.0
var finished := false


func setup(type: String,condition_name: String) -> void:
	event_type = type
	condition = condition_name
	elapsed_s = 0.0
	finished = false
	custom_minimum_size = Vector2(0,250)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	if finished:
		return
	elapsed_s = minf(elapsed_s+delta,DURATION_S)
	queue_redraw()
	if elapsed_s >= DURATION_S:
		finished = true
		set_process(false)
		playback_finished.emit()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO,size)
	draw_rect(rect,Color("07111e"),true)
	draw_rect(rect,Color("29435a"),false,2.0)
	for x: float in range(0,int(size.x)+1,40):
		draw_line(Vector2(x,0),Vector2(x,size.y),Color(0.18,0.32,0.42,0.20),1.0)
	for y: float in range(0,int(size.y)+1,40):
		draw_line(Vector2(0,y),Vector2(size.x,y),Color(0.18,0.32,0.42,0.20),1.0)
	var left := 44.0
	var right := maxf(size.x-44.0,left+100.0)
	var center_y := size.y*0.48
	var event_x := lerpf(left,right,EVENT_TIME_S/DURATION_S)
	draw_line(Vector2(left,center_y),Vector2(right,center_y),Color("4a708e"),3.0)
	draw_dashed_line(Vector2(event_x,24),Vector2(event_x,size.y-42),Color("ffbe55"),2.0,7.0)
	draw_string(AppStyle.FONT_CJK,Vector2(event_x+7,39),"目标异常  3.0秒",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("ffbe55"))
	var progress := clampf(elapsed_s/DURATION_S,0.0,1.0)
	var ship_x := lerpf(left,right,progress)
	var ship_y := center_y
	if event_type == "ship_shear" and elapsed_s >= EVENT_TIME_S:
		var after := clampf((elapsed_s-EVENT_TIME_S)/3.2,0.0,1.0)
		ship_y -= sin(after*PI)*42.0
	_draw_trail(left,event_x,right,center_y)
	_draw_ship(Vector2(ship_x,ship_y))
	if event_type == "waypoint_drift":
		var marker := Vector2(minf(ship_x+105.0,right-8.0),center_y)
		if elapsed_s >= EVENT_TIME_S:
			marker.y -= tan(deg_to_rad(13.0))*82.0
		_draw_waypoint(marker)
	var status := _diagnostic_text() if elapsed_s >= EVENT_TIME_S else "回放中：异常尚未发生"
	draw_string(AppStyle.FONT_CJK,Vector2(18,size.y-17),status,HORIZONTAL_ALIGNMENT_LEFT,size.x-150,15,Color("6fe8ff") if elapsed_s>=EVENT_TIME_S else Color("8fa6b8"))
	draw_string(AppStyle.FONT_BODY,Vector2(size.x-112,size.y-17),"%0.1f / 7.0s" % elapsed_s,HORIZONTAL_ALIGNMENT_RIGHT,96,14,Color("8fa6b8"))


func _draw_trail(left: float,event_x: float,right: float,center_y: float) -> void:
	if event_type == "ship_shear":
		var points := PackedVector2Array()
		for i: int in range(51):
			var p := float(i)/50.0
			var x := lerpf(left,right,p)
			var y := center_y
			if x >= event_x:
				var a := clampf((x-event_x)/maxf(right-event_x,1.0),0.0,1.0)
				y -= sin(a*PI)*42.0
			points.append(Vector2(x,y))
		draw_polyline(points,Color("6fe8ff"),2.0)


func _draw_ship(pos: Vector2) -> void:
	var points := PackedVector2Array([
		pos+Vector2(13,0),pos+Vector2(-9,-8),pos+Vector2(-5,0),pos+Vector2(-9,8)
	])
	draw_colored_polygon(points,Color("e9f7ff"))
	draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[0]]),Color("6fe8ff"),2.0)


func _draw_waypoint(pos: Vector2) -> void:
	draw_circle(pos,8.0,Color("ffbe55"),false,2.0)
	draw_line(pos+Vector2(-12,0),pos+Vector2(12,0),Color("ffbe55"),1.0)
	draw_line(pos+Vector2(0,-12),pos+Vector2(0,12),Color("ffbe55"),1.0)


func _diagnostic_text() -> String:
	if condition == "explicit":
		return (
			"检测到磁暴干扰。航点位置已发生偏移。"
			if event_type == "waypoint_drift"
			else "检测到太阳风扰动。飞船已出现横向偏移。"
		)
	return (
		"检测到航点位置偏移，原因未知。"
		if event_type == "waypoint_drift"
		else "检测到飞船横向偏移，原因未知。"
	)
