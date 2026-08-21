class_name MissionTrailLegendIcon
extends Control
## 航迹图图例的真实图形样例，避免用“青／灰／红／琥珀”等文字让参与者自行对应。

enum Kind { CURRENT_TRAIL, FAILED_TRAIL, COLLISION, TARGET_EVENT }

const CURRENT := Color(0.33,0.89,0.93,1.0)
const FAILED := Color(0.86,0.45,0.48,0.95)
const HIT := Color(1.0,0.30,0.32,1.0)
const EVENT := Color(1.0,0.72,0.28,1.0)
const DARK := Color(0.03,0.08,0.13,1.0)

var kind: Kind = Kind.CURRENT_TRAIL


func setup(value: Kind) -> void:
	kind = value
	custom_minimum_size = Vector2(34,20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var center := Vector2(size.x*0.5,size.y*0.5)
	match kind:
		Kind.CURRENT_TRAIL:
			draw_line(Vector2(3,center.y),Vector2(size.x-3,center.y),CURRENT,3.2,true)
			draw_circle(Vector2(3,center.y),2.0,CURRENT)
			draw_circle(Vector2(size.x-3,center.y),2.0,CURRENT)
		Kind.FAILED_TRAIL:
			_draw_dashed_line(Vector2(2,center.y),Vector2(size.x-9,center.y),FAILED,2.5)
			_draw_crash(Vector2(size.x-6,center.y),4.5)
		Kind.COLLISION:
			_draw_collision(center,6.0)
		Kind.TARGET_EVENT:
			draw_circle(center,7.0,Color(EVENT,0.20),false,1.5,true)
			_draw_diamond(center,5.0)


func _draw_dashed_line(from: Vector2,to: Vector2,color: Color,width: float) -> void:
	var direction := (to-from).normalized()
	var distance := from.distance_to(to)
	var cursor := 0.0
	while cursor < distance:
		var end := minf(cursor+4.5,distance)
		draw_line(from+direction*cursor,from+direction*end,color,width,true)
		cursor += 7.5


func _draw_collision(center: Vector2,radius: float) -> void:
	draw_circle(center,radius,Color(HIT,0.20))
	draw_circle(center,radius,HIT,false,1.5,true)
	draw_line(center-Vector2(3.5,3.5),center+Vector2(3.5,3.5),Color.WHITE,1.7,true)
	draw_line(center+Vector2(-3.5,3.5),center+Vector2(3.5,-3.5),Color.WHITE,1.7,true)


func _draw_crash(center: Vector2,radius: float) -> void:
	draw_circle(center,radius,FAILED)
	for direction: Vector2 in [Vector2.UP,Vector2.RIGHT,Vector2.DOWN,Vector2.LEFT]:
		draw_line(center+direction*(radius-1.0),center+direction*(radius+2.5),FAILED,1.5,true)
	draw_line(center-Vector2(2.5,2.5),center+Vector2(2.5,2.5),DARK,1.4,true)
	draw_line(center+Vector2(-2.5,2.5),center+Vector2(2.5,-2.5),DARK,1.4,true)


func _draw_diamond(center: Vector2,radius: float) -> void:
	var points := PackedVector2Array([
		center+Vector2(0,-radius),center+Vector2(radius,0),
		center+Vector2(0,radius),center+Vector2(-radius,0),
	])
	draw_colored_polygon(points,EVENT)
	draw_polyline(PackedVector2Array([points[0],points[1],points[2],points[3],points[0]]),DARK,1.4,true)
