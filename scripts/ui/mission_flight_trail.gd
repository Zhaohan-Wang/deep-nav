class_name MissionFlightTrail
extends Control
## 整关共同航迹：当前航段实线、坠毁航段虚线、碰撞点红叉、目标异常琥珀菱形。

const GRID := Color(0.20,0.35,0.45,0.16)
const CURRENT := Color(0.33,0.89,0.93,0.92)
const FAILED := Color(0.62,0.73,0.79,0.42)
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
	custom_minimum_size = Vector2(306.0,112.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var pad := 12.0
	var scale := minf((size.x-pad*2.0)/bounds.size.x,(size.y-pad*2.0)/bounds.size.y)
	var offset := (size-bounds.size*scale)*0.5-bounds.position*scale
	for segment: Variant in _failed_trails:
		var points := segment as PackedVector2Array
		if points.size() >= 2:
			_draw_dashed(_to_screen(points,offset,scale),FAILED,2.4,6.0,5.0)
	if _trail.size() >= 2:
		draw_polyline(_to_screen(_trail,offset,scale),CURRENT,3.2,true)
	for point: Vector2 in _hits:
		var hit := offset+point*scale
		draw_line(hit-Vector2(3.5,3.5),hit+Vector2(3.5,3.5),HIT,2.0,true)
		draw_line(hit+Vector2(-3.5,3.5),hit+Vector2(3.5,-3.5),HIT,2.0,true)
	var start := offset+_start*scale
	draw_circle(start,3.5,START)
	var goal := offset+_goal*scale
	draw_circle(goal,5.0,GOAL,false,2.0,true)
	for target: Vector2 in _target_positions:
		var event := offset+target*scale
		draw_colored_polygon(PackedVector2Array([
			event+Vector2(0,-6),event+Vector2(6,0),event+Vector2(0,6),event+Vector2(-6,0),
		]),EVENT)


func _content_bounds() -> Rect2:
	if _fixed_bounds.size.x > 0.0 and _fixed_bounds.size.y > 0.0:
		return _fixed_bounds
	var points := PackedVector2Array([_start,_goal])
	points.append_array(_trail)
	points.append_array(_hits)
	for segment: Variant in _failed_trails:
		points.append_array(segment as PackedVector2Array)
	points.append_array(_target_positions)
	if points.is_empty():
		return Rect2()
	var min_point := points[0]
	var max_point := points[0]
	for point: Vector2 in points:
		min_point.x=minf(min_point.x,point.x); min_point.y=minf(min_point.y,point.y)
		max_point.x=maxf(max_point.x,point.x); max_point.y=maxf(max_point.y,point.y)
	var bounds := Rect2(min_point,max_point-min_point).grow(3.0)
	bounds.size.x=maxf(bounds.size.x,1.0); bounds.size.y=maxf(bounds.size.y,1.0)
	return bounds


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
