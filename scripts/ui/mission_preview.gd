class_name MissionPreview
extends Control
## 参与者安全的任务预览占位：只表达航区气质，不绘制真实路线、关键航段或事件位置。

const BG := Color("081321")
const CYAN := Color("58e1dc")
const AMBER := Color("f0b35a")

var mission_index: int = 0:
	set(value):
		mission_index = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0.0,230.0)


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO,size)
	draw_rect(bounds,BG,true)
	draw_rect(bounds,Color(CYAN,0.28),false,1.0)
	var spacing := 28.0
	var offset := float((mission_index*11)%int(spacing))
	var x := -offset
	while x<size.x:
		draw_line(Vector2(x,0),Vector2(x,size.y),Color(CYAN,0.045),1.0)
		x+=spacing
	var y := offset*0.55
	while y<size.y:
		draw_line(Vector2(0,y),Vector2(size.x,y),Color(CYAN,0.04),1.0)
		y+=spacing
	var planet_center := Vector2(size.x*0.74,size.y*0.48)
	var planet_r := minf(size.y*0.31,74.0)+float(mission_index%3)*5.0
	for ring: int in range(4):
		var radius := planet_r+float(ring)*8.0
		draw_arc(planet_center,radius,-0.85,2.35,48,Color(CYAN,0.22-float(ring)*0.035),1.0,true)
	draw_circle(planet_center,planet_r,Color("172f45"))
	draw_circle(planet_center-Vector2(planet_r*0.22,planet_r*0.2),planet_r*0.72,Color("244d63"))
	draw_arc(planet_center,planet_r*0.66,0.2,2.7,32,Color(AMBER,0.62),2.0,true)
	var beacon := Vector2(size.x*0.20,size.y*0.58)
	for radius: float in [8.0,15.0,23.0]:
		draw_arc(beacon,radius,0.0,TAU,32,Color(CYAN,0.56-radius/80.0),1.2,true)
	draw_circle(beacon,2.4,CYAN)
	draw_arc(size*Vector2(0.48,0.95),size.x*0.36,3.65,5.68,64,Color(AMBER,0.18),2.0,true)
