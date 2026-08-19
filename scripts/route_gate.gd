class_name RouteGate
extends RefCounted
## 关键事件使用横贯航区的单向平面，不用可被玩家从侧面绕开的点半径触发器。


static func crossed(previous: Vector3,current: Vector3,anchor: Vector3,route: PackedVector3Array) -> bool:
	var tangent:=tangent_at(anchor,route)
	if tangent.length_squared()<0.001: return false
	return (previous-anchor).dot(tangent)<0.0 and (current-anchor).dot(tangent)>=0.0


static func tangent_at(anchor: Vector3,route: PackedVector3Array) -> Vector3:
	var best:=INF; var tangent:=Vector3.ZERO
	for i: int in range(route.size()-1):
		var a:=route[i]; var ab:=route[i+1]-a; ab.y=0.0
		var t:=clampf((anchor-a).dot(ab)/maxf(ab.length_squared(),0.001),0.0,1.0)
		var distance:=anchor.distance_to(a+ab*t)
		if distance<best:
			best=distance; tangent=ab.normalized()
	return tangent
