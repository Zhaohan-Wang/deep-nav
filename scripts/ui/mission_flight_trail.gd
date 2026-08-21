class_name MissionFlightTrail
extends Control
## 事件前后真实航迹：当前航段实线、撞毁航段虚线、碰撞点冲击标记、目标异常琥珀菱形。

const GRID := Color(0.20,0.35,0.45,0.16)
const CURRENT := Color(0.33,0.89,0.93,0.92)
const FAILED := Color(0.86,0.45,0.48,0.82)
const HIT := Color(0.96,0.32,0.34,0.95)
const EVENT := Color(1.0,0.72,0.28,1.0)
const START := Color(0.33,0.89,0.93,0.95)
const GOAL := Color(0.37,0.88,0.54,0.95)

var _trail := PackedVector2Array()
var _failed_trails: Array = []
var _hits := PackedVector2Array()
var _start := Vector2.ZERO
var _goal := Vector2.ZERO
var _target_positions := PackedVector2Array()
var _fixed_bounds := Rect2()


func setup(record: Dictionary) -> void:
	_trail = record.get("flight_trail",PackedVector2Array()) as PackedVector2Array
	_failed_trails = (record.get("failed_flight_trails",[]) as Array).duplicate(true)
	_hits = record.get("collision_points",PackedVector2Array()) as PackedVector2Array
	_start = Vector2(record.get("flight_start",Vector2.ZERO))
	_goal = Vector2(record.get("flight_goal",Vector2.ZERO))
	_target_positions = record.get("target_event_positions",PackedVector2Array()) as PackedVector2Array
	if _target_positions.is_empty() and record.get("target_event_position",null) != null:
		_target_positions.append(Vector2(record.get("target_event_position")))
	_fixed_bounds = record.get("flight_world_bounds",Rect2()) as Rect2
	custom_minimum_size = Vector2(420.0,100.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("07111e"),true)
	for x: float in range(0,int(size.x)+1,24):
		draw_line(Vector2(x,0),Vector2(x,size.y),GRID,1.0)
	for y: float in range(0,int(size.y)+1,24):
		draw_line(Vector2(0,y),Vector2(size.x,y),GRID,1.0)
	var bounds := _content_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var pad := 18.0
	var scale := minf((size.x-pad*2.0)/bounds.size.x,(size.y-pad*2.0)/bounds.size.y)
	var offset := (size-bounds.size*scale)*0.5-bounds.position*scale
	for segment: Variant in _failed_trails:
		var points := segment as PackedVector2Array
		if points.size() >= 2:
			var failed_screen := _to_screen(points,offset,scale)
			_draw_dashed(failed_screen,FAILED,3.0,7.0,5.0)
			_draw_crash_marker(failed_screen[failed_screen.size()-1])
	if _trail.size() >= 2:
		draw_polyline(_to_screen(_trail,offset,scale),CURRENT,4.0,true)
	for point: Vector2 in _hits:
		var hit := offset+point*scale
		_draw_collision_marker(hit)
	var start := offset+_start*scale
	if _point_visible(start,pad):
		draw_circle(start,4.5,START)
	var goal := offset+_goal*scale
	# 未实际抵达的远端终点不再参与取景或强行显示，避免把事故前后航迹压成一小段。
	if _point_visible(goal,pad):
		draw_circle(goal,6.0,GOAL,false,2.4,true)
	for target: Vector2 in _target_positions:
		var event := offset+target*scale
		draw_circle(event,10.0,Color(EVENT,0.18),false,2.0,true)
		draw_colored_polygon(PackedVector2Array([
			event+Vector2(0,-7),event+Vector2(7,0),event+Vector2(0,7),event+Vector2(-7,0),
		]),EVENT)
		draw_polyline(PackedVector2Array([
			event+Vector2(0,-7),event+Vector2(7,0),event+Vector2(0,7),
			event+Vector2(-7,0),event+Vector2(0,-7),
		]),Color("08131d"),1.7,true)


func _content_bounds() -> Rect2:
	# 参与者页按本次真实出现过的内容取景。_fixed_bounds 仍保留在记录中供研究审核图使用，
	# 但不能拿整张关卡边界压缩一次只走到中段的事故航迹。
	var points := PackedVector2Array()
	points.append_array(_trail)
	points.append_array(_hits)
	for segment: Variant in _failed_trails:
		points.append_array(segment as PackedVector2Array)
	points.append_array(_target_positions)
	if points.is_empty():
		points.append(_start)
		points.append(_goal)
	if points.is_empty():
		return Rect2()
	var min_point := points[0]
	var max_point := points[0]
	for point: Vector2 in points:
		min_point.x=minf(min_point.x,point.x); min_point.y=minf(min_point.y,point.y)
		max_point.x=maxf(max_point.x,point.x); max_point.y=maxf(max_point.y,point.y)
	var bounds := Rect2(min_point,max_point-min_point).grow(4.0)
	bounds.size.x=maxf(bounds.size.x,1.0); bounds.size.y=maxf(bounds.size.y,1.0)
	return bounds


func _point_visible(point: Vector2,pad: float) -> bool:
	return Rect2(Vector2(pad,pad),size-Vector2.ONE*pad*2.0).has_point(point)


func _draw_collision_marker(center: Vector2) -> void:
	draw_circle(center,8.0,Color(HIT,0.20))
	draw_circle(center,7.0,HIT,false,2.0,true)
	draw_line(center-Vector2(4.5,4.5),center+Vector2(4.5,4.5),Color.WHITE,2.1,true)
	draw_line(center+Vector2(-4.5,4.5),center+Vector2(4.5,-4.5),Color.WHITE,2.1,true)
	for direction: Vector2 in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
		draw_line(center+direction*7.0,center+direction*10.5,HIT,1.7,true)


func _draw_crash_marker(center: Vector2) -> void:
	draw_circle(center,8.5,Color(FAILED,0.25))
	draw_circle(center,6.5,FAILED)
	for direction: Vector2 in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
		draw_line(center+direction*5.5,center+direction*10.0,FAILED,2.0,true)
	draw_line(center-Vector2(3.8,3.8),center+Vector2(3.8,3.8),Color("07111e"),2.0,true)
	draw_line(center+Vector2(-3.8,3.8),center+Vector2(3.8,-3.8),Color("07111e"),2.0,true)


func _to_screen(raw: PackedVector2Array,offset: Vector2,scale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in raw:
		points.append(offset+point*scale)
	return points


func _draw_dashed(points: PackedVector2Array,color: Color,width: float,dash: float,gap: float) -> void:
	var draw_on := true
	var budget := dash
	for i: int in range(points.size()-1):
		var delta := points[i+1]-points[i]
		var length := delta.length()
		if length < 0.001:
			continue
		var direction := delta/length
		var cursor := points[i]
		var remaining := length
		while remaining > 0.001:
			var step := minf(budget,remaining)
			var next := cursor+direction*step
			if draw_on:
				draw_line(cursor,next,color,width,true)
			cursor=next; remaining-=step; budget-=step
			if budget <= 0.001:
				draw_on=not draw_on
				budget=dash if draw_on else gap
