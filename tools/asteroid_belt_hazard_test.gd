extends SceneTree
## 验证每条非边界小行星带都有“可擦伤外缘 + 不可穿越核心”，并覆盖高速扫掠。

const Catalog = preload("res://scripts/mission_catalog.gd")
const Hazard = preload("res://scripts/belt_hazard.gd")
const SHIP_RADIUS:=1.2

var failures: PackedStringArray=[]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var belt_count:=0
	for mission: SectorData in Catalog.all():
		for belt: BeltData in mission.belts:
			if belt.is_boundary: continue
			belt_count+=1
			var cross:=_cross_section(belt)
			var center: Vector3=cross["center"]
			var normal: Vector3=cross["normal"]
			var expanded_half: float=float(cross["half_width"])+SHIP_RADIUS
			# 弯曲样条的一侧可能靠近另一段曲线；选择真正朝向带外的法向做外缘检查。
			var far_distance:=expanded_half+8.0
			var plus_fraction:=Hazard.penetration_fraction(center+normal*far_distance,belt,SHIP_RADIUS)
			var minus_fraction:=Hazard.penetration_fraction(center-normal*far_distance,belt,SHIP_RADIUS)
			if minus_fraction<plus_fraction: normal=-normal
			var outside:=center+normal*far_distance
			var fringe:=center+normal*(expanded_half*0.76)
			var cross_from:=center-normal*(expanded_half+4.0)
			var cross_to:=center+normal*(expanded_half+4.0)
			var outside_fraction:=Hazard.penetration_fraction(outside,belt,SHIP_RADIUS)
			var fringe_fraction:=Hazard.penetration_fraction(fringe,belt,SHIP_RADIUS)
			var core_fraction:=Hazard.penetration_fraction(center,belt,SHIP_RADIUS)
			var swept_fraction:=Hazard.max_fraction_along_segment(cross_from,cross_to,belt,SHIP_RADIUS)
			_check(outside_fraction<=0.001,"%s/%s 外部被错误判为带内" % [mission.id,belt.id])
			_check(fringe_fraction>0.0 and fringe_fraction<Hazard.CORE_FRACTION,
				"%s/%s 没有独立的可擦伤外缘" % [mission.id,belt.id])
			_check(core_fraction>=0.99,"%s/%s 中心没有形成致死核心" % [mission.id,belt.id])
			_check(swept_fraction>=Hazard.CORE_FRACTION,
				"%s/%s 高速直穿没有扫到致死核心" % [mission.id,belt.id])
			_check(Hazard.classify(outside_fraction)==Hazard.Exposure.CLEAR,
				"%s/%s 外部危险分类错误" % [mission.id,belt.id])
			_check(Hazard.classify(fringe_fraction)==Hazard.Exposure.GRAZE,
				"%s/%s 外缘没有分类为小额擦伤" % [mission.id,belt.id])
			_check(Hazard.classify(swept_fraction)==Hazard.Exposure.CORE,
				"%s/%s 直穿没有分类为立即解体" % [mission.id,belt.id])
		var route_max:=0.0
		for i: int in range(mission.route_checkpoints.size()-1):
			var a:=mission.route_checkpoints[i]
			var b:=mission.route_checkpoints[i+1]
			var samples:=maxi(1,int(ceil(a.distance_to(b)/3.0)))
			for j: int in range(samples+1):
				var point:=a.lerp(b,float(j)/float(samples))
				for belt: BeltData in mission.belts:
					if belt.is_boundary: continue
					route_max=maxf(route_max,Hazard.penetration_fraction(point,belt,SHIP_RADIUS))
		_check(route_max<Hazard.CORE_FRACTION,
			"%s 审核安全路线进入了小行星带致死核心（%.2f）" % [mission.id,route_max])

	if not failures.is_empty():
		for failure: String in failures: push_error(failure)
		quit(1); return
	print("ASTEROID_BELT_HAZARD_OK belts=%d" % belt_count)
	quit(0)


func _cross_section(belt: BeltData) -> Dictionary:
	if belt.shape==BeltData.Shape.RING:
		var angle:=0.73
		var inner:=belt.point_on_ring(angle,belt.inner_radius)
		var outer:=belt.point_on_ring(angle,belt.outer_radius)
		return {"center":(inner+outer)*0.5,"normal":(outer-inner).normalized(),"half_width":inner.distance_to(outer)*0.5}
	if belt.shape==BeltData.Shape.SPLINE:
		var t:=0.5
		var tangent:=belt.spline_tangent(t)
		var normal:=Vector3(-tangent.z,0.0,tangent.x).normalized()
		return {"center":belt.spline_point(t),"normal":normal,"half_width":belt.spline_half_width(t)}
	var center:=(belt.from_point+belt.to_point)*0.5
	var tangent:=(belt.to_point-belt.from_point).normalized()
	return {"center":center,"normal":Vector3(-tangent.z,0.0,tangent.x).normalized(),"half_width":belt.half_width}


func _check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)
