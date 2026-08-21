extends SceneTree
## 用地图数据检查“盲目直冲有风险、规划路线可读、正式关确实需要转向”。

const Catalog=preload("res://scripts/mission_catalog.gd")
var failures: PackedStringArray=[]

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for mission: SectorData in Catalog.all():
		var destination:=_body(mission,mission.objective_body_id)
		if destination==null: _fail("%s 缺少目标" % mission.id); continue
		var direct:=PackedVector3Array([mission.spawn_position,destination.world_position])
		var direct_risk:=_belt_exposure(direct,mission)
		var route_risk:=_belt_exposure(mission.route_checkpoints,mission)
		var route_length:=_path_length(mission.route_checkpoints)
		var direct_length:=mission.spawn_position.distance_to(destination.world_position)
		var turns:=_meaningful_turns(mission.route_checkpoints)
		var body_clearance:=_minimum_body_clearance(mission.route_checkpoints,mission)
		if mission.id=="practice":
			_check(route_risk<4.0,"训练关计划路线不应穿过危险带")
		else:
			_check(direct_risk>=7.0,"%s 直冲终点没有足够危险暴露（%.1f u）" % [mission.id,direct_risk])
			_check(route_risk<=direct_risk*0.48,"%s 规划路线没有显著降低危险（直线 %.1f / 路线 %.1f）" % [mission.id,direct_risk,route_risk])
			_check(route_risk<=4.0,"%s 规划路线仍穿入危险带（%.1f u）" % [mission.id,route_risk])
			_check(turns>=2,"%s 不需要至少两次有意义的转向" % mission.id)
			_check(route_length/direct_length>=1.015,"%s 计划路线几乎就是直线" % mission.id)
		if mission.id=="level_3":
			var reversals:=_lateral_reversals(mission.route_checkpoints)
			var lateral_span:=_lateral_span(mission.route_checkpoints)
			var macro_bow:=_macro_bow(mission.route_checkpoints)
			_check(reversals>=7,"level_3 波浪航槽不足 7 次反向弯折（当前 %d）" % reversals)
			_check(lateral_span>=58.0,"level_3 波浪航槽横向摆幅不足（当前 %.1f u）" % lateral_span)
			_check(absf(macro_bow)>=8.0,"level_3 只有局部波浪，没有贯穿全图的大弧线（当前 %.1f u）" % macro_bow)
			_check(route_length/direct_length>=1.18,"level_3 路线迂回率不足（当前 %.3f）" % (route_length/direct_length))
		_check(body_clearance>=3.0,"%s 计划路线离实体天体过近（净空 %.1f u）" % [mission.id,body_clearance])
		print("NAV_DIFFICULTY %s direct_risk=%.1f route_risk=%.1f detour=%.3f turns=%d body_clearance=%.1f" % [
			mission.id,direct_risk,route_risk,route_length/direct_length,turns,body_clearance])
	if not failures.is_empty():
		for failure: String in failures: push_error(failure)
		quit(1); return
	print("NAVIGATION_DIFFICULTY_OK missions=%d" % Catalog.all().size()); quit(0)

func _belt_exposure(points: PackedVector3Array,mission: SectorData) -> float:
	var exposure:=0.0
	for i: int in range(points.size()-1):
		var a:=points[i]; var b:=points[i+1]; var length:=a.distance_to(b)
		var samples:=maxi(1,int(ceil(length/2.0)))
		for j: int in samples:
			var p:=a.lerp(b,(float(j)+0.5)/float(samples))
			for belt: BeltData in mission.belts:
				if not belt.is_boundary and _inside_belt(p,belt): exposure+=length/float(samples); break
	return exposure

func _inside_belt(p: Vector3,belt: BeltData) -> bool:
	if belt.shape==BeltData.Shape.RING:
		var angle:=atan2(p.z-belt.center.z,(p.x-belt.center.x)/maxf(belt.aspect,0.01))
		var inner:=belt.point_on_ring(angle,belt.inner_radius)
		var outer:=belt.point_on_ring(angle,belt.outer_radius)
		var radius:=p.distance_to(belt.center)
		return radius>=inner.distance_to(belt.center) and radius<=outer.distance_to(belt.center)
	if belt.shape==BeltData.Shape.SPLINE:
		for i: int in range(97):
			var t:=float(i)/96.0
			if p.distance_to(belt.spline_point(t))<=belt.spline_half_width(t): return true
		return false
	var delta:=belt.to_point-belt.from_point
	var t:=clampf((p-belt.from_point).dot(delta)/maxf(delta.length_squared(),0.001),0.0,1.0)
	return p.distance_to(belt.from_point+delta*t)<=belt.half_width

func _meaningful_turns(points: PackedVector3Array) -> int:
	var count:=0
	for i: int in range(1,points.size()-1):
		var before:=(points[i]-points[i-1]).normalized(); var after:=(points[i+1]-points[i]).normalized()
		if rad_to_deg(acos(clampf(before.dot(after),-1.0,1.0)))>=8.0: count+=1
	return count

func _lateral_reversals(points: PackedVector3Array) -> int:
	var reversals:=0
	var previous_sign:=0.0
	for i: int in range(points.size()-1):
		var dz:=points[i+1].z-points[i].z
		if absf(dz)<0.35: continue
		var current_sign:=signf(dz)
		if not is_zero_approx(previous_sign) and current_sign!=previous_sign: reversals+=1
		previous_sign=current_sign
	return reversals

func _lateral_span(points: PackedVector3Array) -> float:
	var min_z:=INF
	var max_z:=-INF
	for point: Vector3 in points:
		min_z=minf(min_z,point.z)
		max_z=maxf(max_z,point.z)
	return max_z-min_z

func _macro_bow(points: PackedVector3Array) -> float:
	var first:=points[0]
	var last:=points[points.size()-1]
	var total:=0.0
	var samples:=0
	for i: int in range(points.size()):
		var progress:=float(i)/float(maxi(points.size()-1,1))
		if progress<0.20 or progress>0.80: continue
		var baseline:=lerpf(first.z,last.z,progress)
		total+=points[i].z-baseline
		samples+=1
	return total/float(maxi(samples,1))

func _minimum_body_clearance(points: PackedVector3Array,mission: SectorData) -> float:
	var result:=INF
	for i: int in range(points.size()-1):
		var length:=points[i].distance_to(points[i+1]); var samples:=maxi(1,int(ceil(length/2.0)))
		for j: int in range(samples+1):
			var p:=points[i].lerp(points[i+1],float(j)/float(samples))
			for body: CelestialBodyData in mission.bodies:
				if body.kind!=CelestialBodyData.Kind.DESTINATION:
					result=minf(result,p.distance_to(body.world_position)-body.collision_radius)
	return result

func _path_length(points: PackedVector3Array) -> float:
	var result:=0.0
	for i: int in range(points.size()-1): result+=points[i].distance_to(points[i+1])
	return result

func _body(mission: SectorData,id: String) -> CelestialBodyData:
	for body: CelestialBodyData in mission.bodies:
		if body.id==id: return body
	return null

func _check(ok: bool,message: String) -> void:
	if not ok: _fail(message)

func _fail(message: String) -> void: failures.append(message)
