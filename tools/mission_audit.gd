extends SceneTree
## 关卡语义检查 + 直接可读 PNG。每个障碍和实验事件都必须服务于预定航段。

const Catalog = preload("res://scripts/mission_catalog.gd")
const Layout = preload("res://scripts/belt_layout.gd")
const Gate = preload("res://scripts/route_gate.gd")
const OUT := "res://artifacts/maps"
const PUBLIC_FORBIDDEN: PackedStringArray = [
	"waypoint_drift","ship_shear","recovery_window","扰动槽位","扰动锚点","安全门","路线检查点",
	"导航异常归因","无扰动基线","磁暴坐标区","太阳风剪切"
]
var failures: PackedStringArray = []

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ids: Dictionary = {}
	for mission: SectorData in Catalog.all():
		_check(not ids.has(mission.id), "%s ID 重复" % mission.id); ids[mission.id] = true
		_check(not mission.participant_name.is_empty(),"%s 缺少参与者中性关名" % mission.id)
		_check(not mission.participant_briefing.is_empty(),"%s 缺少参与者中性简报" % mission.id)
		_check(not mission.participant_hint.is_empty(),"%s 缺少参与者中性协作提示" % mission.id)
		var public_copy := "%s\n%s\n%s" % [mission.participant_name,mission.participant_briefing,mission.participant_hint]
		for token: String in PUBLIC_FORBIDDEN:
			_check(not public_copy.contains(token),"%s 的参与者文案泄漏内部词：%s" % [mission.id,token])
		_check(mission.time_limit_s >= 60.0, "%s 时限过短" % mission.id)
		_check(mission.max_attempts == 0, "%s 仍会按解体次数提前结束" % mission.id)
		_check(mission.route_checkpoints.size() >= 3, "%s 缺少路线检查点" % mission.id)
		_check(mission.relay_stations.size() <= 2, "%s 中继站超过两座" % mission.id)
		if mission.id == "practice":
			_check(mission.relay_stations.is_empty(), "%s 训练关不应设置中继站" % mission.id)
		for station: Vector3 in mission.relay_stations:
			_check(_point_near_route(station, mission.route_checkpoints, 16.0), "%s 中继站不在计划航段上" % mission.id)
			_check(station.distance_to(mission.spawn_position) >= 80.0, "%s 中继站离起点过近" % mission.id)
			for belt: BeltData in mission.belts:
				if belt.is_boundary:
					continue
				_check(BeltHazard.penetration_fraction(station, belt, 1.2) < BeltHazard.CORE_FRACTION,
					"%s 中继站落在 %s 的致密核心里" % [mission.id, belt.id])
		_check(mission.disturbance_slots.size() == mission.disturbance_anchors.size(), "%s 扰动槽与触发点数量不一致" % mission.id)
		for anchor: Vector3 in mission.disturbance_anchors:
			_check(_point_near_route(anchor, mission.route_checkpoints, 18.0), "%s 扰动点不在计划航段上" % mission.id)
			var tangent: Vector3=Gate.tangent_at(anchor,mission.route_checkpoints)
			var lateral:=Vector3(-tangent.z,0.0,tangent.x)
			for offset: float in [-100.0,100.0]:
				_check(Gate.crossed(anchor-tangent*10.0+lateral*offset,anchor+tangent*10.0+lateral*offset,anchor,mission.route_checkpoints),
					"%s 扰动事件门不能覆盖侧向绕行" % mission.id)
		for gate: Vector3 in mission.safe_gate_points:
			_check(_point_near_route(gate, mission.route_checkpoints, 12.0), "%s 安全门不在计划航段上" % mission.id)
		for i: int in range(mission.route_checkpoints.size() - 1):
			_check(mission.route_checkpoints[i].distance_to(mission.route_checkpoints[i + 1]) <= 84.0,
				"%s 第 %d 段超过单次清晰引导距离" % [mission.id,i + 1])
		if not mission.disturbance_anchors.is_empty():
			_check(mission.safe_gate_points.size() >= mission.disturbance_anchors.size(), "%s 每个扰动后都必须有独立安全门" % mission.id)
			for i: int in mini(mission.disturbance_anchors.size(),mission.safe_gate_points.size()):
				var recovery: float = _route_progress(mission.safe_gate_points[i],mission.route_checkpoints) - _route_progress(mission.disturbance_anchors[i],mission.route_checkpoints)
				_check(recovery >= 48.0 and recovery <= 120.0, "%s 第 %d 个扰动后到安全门的反应航程不合理" % [mission.id,i + 1])
		var dest := _body(mission, mission.objective_body_id)
		_check(dest != null, "%s 缺少终点" % mission.id)
		if dest != null:
			_check(mission.spawn_position.distance_to(dest.world_position) >= 100.0, "%s 起终点利用率不足" % mission.id)
			_check(dest.world_radius>=14.0,"%s 目标星缺乏视觉与碰撞体量" % mission.id)
		var large_bodies:=0; var largest_radius:=0.0
		for body: CelestialBodyData in mission.bodies:
			largest_radius=maxf(largest_radius,body.world_radius)
			if body.world_radius>=10.0: large_bodies+=1
			if body.kind==CelestialBodyData.Kind.STAR: _check(body.world_radius>=24.0,"%s 恒星缺乏主导画面的尺度" % mission.id)
			if body.kind==CelestialBodyData.Kind.HAZARD: _check(body.world_radius>=26.0,"%s 危险天体缺乏压迫尺度" % mission.id)
		_check(largest_radius>=18.0,"%s 缺少能够主导画面的核心天体" % mission.id)
		_check(large_bodies>=3,"%s 具有碰撞威胁的中大型天体不足" % mission.id)
		var boundary_count := 0
		var boundary: BeltData = null
		var open_ring_count := 0
		var spline_count := 0
		for belt: BeltData in mission.belts:
			if belt.is_boundary:
				boundary_count += 1
				boundary = belt
			else:
				if belt.shape == BeltData.Shape.RING: open_ring_count += 1
				if belt.shape == BeltData.Shape.SPLINE: spline_count += 1
				_check(_belt_near_route(belt, mission.route_checkpoints), "%s 的 %s 与计划航线无关" % [mission.id, belt.id])
				var flight_rocks := 0
				for sample: Dictionary in Layout.samples(belt):
					if bool(sample["hits_flight"]): flight_rocks += 1
				_check(flight_rocks >= 4, "%s 的 %s 在飞行平面没有足够实体岩块" % [mission.id,belt.id])
		_check(boundary_count == 1, "%s 必须恰有一个边界带" % mission.id)
		# 实验关之间的空间语法也是实验控制的一部分，不能只换皮肤。
		if mission.id == "level_1":
			_check(open_ring_count == 1 and spline_count == 0,
				"level_1 必须保持单环分岔基线，不能退化成走廊")
			_check(mission.disturbance_slots.is_empty(),
				"level_1 基线关不得包含实验扰动")
		if mission.id == "level_3":
			_check(open_ring_count == 0 and spline_count == 2,
				"level_3 必须保持双样条单解走廊，不能重新变成 level_1 的环带")
			_check(mission.disturbance_slots == PackedStringArray(["waypoint_drift"]),
				"level_3 必须且只能包含一次航点漂移")
			var blocker := _body(mission,"ring")
			var rejoin_guard := _body(mission,"cinder")
			var entry_star := _body(mission,"sol")
			_check(blocker != null and blocker.kind == CelestialBodyData.Kind.HAZARD and blocker.world_radius >= 30.0,
				"level_3 走廊出口缺少具有压迫尺度的阻断天体")
			_check(rejoin_guard != null and rejoin_guard.world_radius >= 16.0,
				"level_3 立即回切缺少有碰撞意义的月体")
			if entry_star != null:
				var entry_points := PackedVector3Array()
				for i: int in mini(5,mission.route_checkpoints.size()):
					entry_points.append(mission.route_checkpoints[i])
				var entry_gap := _distance_to_path(entry_star.world_position,entry_points)-entry_star.collision_radius
				_check(entry_gap >= 8.0 and entry_gap <= 24.0,
					"level_3 入口恒星必须形成可感知但可安全绕过的侧向压力（当前 %.1f u）" % entry_gap)
			if blocker != null and dest != null and not mission.safe_gate_points.is_empty():
				var safe_gate := mission.safe_gate_points[0]
				_check(_distance_to_segment(blocker.world_position,safe_gate,dest.world_position)
					<= blocker.collision_radius + Game.SHIP_RADIUS,
					"level_3 寂井没有真正截断安全门到终点的直线路径")
				_check(_route_progress(blocker.world_position,mission.route_checkpoints)
					> _route_progress(safe_gate,mission.route_checkpoints) + 20.0,
					"level_3 阻断天体必须位于事件安全门之后，不能污染即时归因段")
				if rejoin_guard != null:
					var upper_bypass := blocker.world_position + Vector3(0.0,0.0,blocker.collision_radius + 8.0)
					_check(_distance_to_segment(rejoin_guard.world_position,upper_bypass,dest.world_position)
						<= rejoin_guard.collision_radius + Game.SHIP_RADIUS + 1.0,
						"level_3 无声月没有限制最省事的立即回切")
		if boundary != null:
			_check(boundary.outer_radius-boundary.inner_radius >= 10.0, "%s 连续边界墙过薄" % mission.id)
			_check(boundary.boundary_segment_count() >= 96, "%s 连续边界墙细分不足" % mission.id)
			for p: Vector3 in mission.route_checkpoints:
				_check(boundary.ellipse_factor(p,boundary.inner_radius-5.0) < 1.0, "%s 计划航线侵入边界排斥区" % mission.id)
			for body: CelestialBodyData in mission.bodies:
				var body_limit := boundary.inner_radius-body.collision_radius-5.0
				_check(body_limit > 1.0 and boundary.ellipse_factor(body.world_position,body_limit) < 1.0,
					"%s 天体 %s 侵入连续边界" % [mission.id,body.id])
		for i: int in mission.bodies.size():
			for j: int in range(i + 1, mission.bodies.size()):
				var a := mission.bodies[i]; var b := mission.bodies[j]
				_check(a.world_position.distance_to(b.world_position) > a.collision_radius + b.collision_radius + 5.0,
					"%s 天体 %s/%s 过近" % [mission.id, a.id, b.id])
		_write_png(mission)
		print("MISSION_AUDIT_OK %s bodies=%d belts=%d checkpoints=%d intent=%s" % [mission.id, mission.bodies.size(), mission.belts.size(), mission.route_checkpoints.size(), mission.design_intent])
	if not failures.is_empty():
		for failure: String in failures: push_error(failure)
		quit(1); return
	print("MISSION_CATALOG_OK count=%d" % Catalog.all().size()); quit(0)

func _body(mission: SectorData, id: String) -> CelestialBodyData:
	for body: CelestialBodyData in mission.bodies:
		if body.id == id: return body
	return null

func _belt_near_route(belt: BeltData, points: PackedVector3Array) -> bool:
	for p: Vector3 in points:
		if belt.shape == BeltData.Shape.RING:
			if belt.center.distance_to(p) < belt.outer_radius + 40.0: return true
		elif belt.shape == BeltData.Shape.SPLINE:
			for i: int in range(33):
				if belt.spline_point(float(i) / 32.0).distance_to(p) < belt.spline_half_width(float(i) / 32.0) + 46.0: return true
		else:
			var ab:=belt.to_point-belt.from_point
			var t:=clampf((p-belt.from_point).dot(ab)/maxf(ab.length_squared(),0.001),0.0,1.0)
			if p.distance_to(belt.from_point+ab*t)<52.0: return true
	return false

func _point_near_route(point: Vector3, points: PackedVector3Array, distance: float) -> bool:
	for i: int in range(points.size() - 1):
		var a := points[i]; var ab := points[i + 1] - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if point.distance_to(a + ab * t) <= distance: return true
	return false

func _route_progress(point: Vector3, points: PackedVector3Array) -> float:
	var best_distance := INF; var best_progress := 0.0; var walked := 0.0
	for i: int in range(points.size() - 1):
		var a := points[i]; var ab := points[i + 1] - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(),0.001),0.0,1.0)
		var distance := point.distance_to(a + ab * t)
		if distance < best_distance:
			best_distance = distance; best_progress = walked + ab.length() * t
		walked += ab.length()
	return best_progress

func _distance_to_segment(point: Vector3,a: Vector3,b: Vector3) -> float:
	var ab := b-a
	var t := clampf((point-a).dot(ab)/maxf(ab.length_squared(),0.001),0.0,1.0)
	return point.distance_to(a+ab*t)

func _distance_to_path(point: Vector3,points: PackedVector3Array) -> float:
	var result := INF
	for i: int in range(points.size()-1):
		result=minf(result,_distance_to_segment(point,points[i],points[i+1]))
	return result

func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _write_png(m: SectorData) -> void:
	var bounds := _content_bounds(m)
	var scale: float = 460.0 / maxf(bounds.size.y,1.0)
	var width: int = clampi(int(ceil(bounds.size.x * scale + 80.0)),720,2200)
	if bounds.size.x * scale + 80.0 > 2200.0: scale = 2120.0 / bounds.size.x
	var image := Image.create(width,540,false,Image.FORMAT_RGBA8); image.fill(Color("050914"))
	var offset := Vector2(40.0-bounds.position.x*scale,40.0-bounds.position.y*scale)
	var map := func(p: Vector3) -> Vector2i: return Vector2i(round(offset.x+p.x*scale),round(offset.y+p.z*scale))
	for x: int in range(0,width+1,48): _line(image,Vector2i(x,0),Vector2i(x,539),Color("173349"),1)
	for y: int in range(0,541,48): _line(image,Vector2i(0,y),Vector2i(width-1,y),Color("173349"),1)
	for belt: BeltData in m.belts:
		if belt.is_boundary:
			_draw_boundary_png(image,belt,map)
			_draw_belt_cloud(image,belt,map,scale)
			continue
		if belt.shape == BeltData.Shape.RING:
			var center: Vector2i=map.call(belt.center)
			for i: int in range(72):
				_line(image,map.call(belt.point_on_ring(TAU*float(i)/72.0,belt.inner_radius)),map.call(belt.point_on_ring(TAU*float(i+1)/72.0,belt.inner_radius)),Color("634938"),1)
				_line(image,map.call(belt.point_on_ring(TAU*float(i)/72.0,belt.outer_radius)),map.call(belt.point_on_ring(TAU*float(i+1)/72.0,belt.outer_radius)),Color("634938"),1)
		elif belt.shape == BeltData.Shape.SPLINE:
			for i: int in range(48):
				var t0:=float(i)/48.0; var t1:=float(i+1)/48.0
				for sign: float in [-1.0,1.0]:
					var p0:=belt.spline_point(t0); var tangent0:=belt.spline_tangent(t0); var side0:=Vector3(-tangent0.z,0.0,tangent0.x).normalized()
					var p1:=belt.spline_point(t1); var tangent1:=belt.spline_tangent(t1); var side1:=Vector3(-tangent1.z,0.0,tangent1.x).normalized()
					_line(image,map.call(p0+side0*belt.spline_half_width(t0)*sign),map.call(p1+side1*belt.spline_half_width(t1)*sign),Color("634938"),1)
		else:
			var from: Vector2i=map.call(belt.from_point); var to: Vector2i=map.call(belt.to_point)
			var delta:=Vector2(to-from); var side:=Vector2(-delta.y,delta.x).normalized()*belt.half_width*scale
			_line(image,Vector2i(Vector2(from)+side),Vector2i(Vector2(to)+side),Color("634938"),1)
			_line(image,Vector2i(Vector2(from)-side),Vector2i(Vector2(to)-side),Color("634938"),1)
		_draw_belt_cloud(image,belt,map,scale)
	for i: int in range(m.route_checkpoints.size()-1):
		_dashed(image,map.call(m.route_checkpoints[i]),map.call(m.route_checkpoints[i+1]),Color("f0b35a"))
	for p: Vector3 in m.route_checkpoints: _disc(image,map.call(p),4,Color("f0b35a"))
	for anchor: Vector3 in m.disturbance_anchors:
		var c: Vector2i=map.call(anchor); _ring(image,c,10,2,Color("f06eb6")); _line(image,c+Vector2i(-7,0),c+Vector2i(7,0),Color("f06eb6"),1); _line(image,c+Vector2i(0,-7),c+Vector2i(0,7),Color("f06eb6"),1)
	for gate: Vector3 in m.safe_gate_points:
		var c: Vector2i=map.call(gate); _ring(image,c,13,2,Color("55e6c7")); _ring(image,c,8,1,Color("55e6c7"))
	for station: Vector3 in m.relay_stations:
		var c: Vector2i=map.call(station); _ring(image,c,16,2,Color("58e1dc")); _disc(image,c,5,Color("58e1dc"))
	for body: CelestialBodyData in m.bodies:
		var color := Color("58e1dc") if body.kind == CelestialBodyData.Kind.DESTINATION else Color("65788d")
		_disc(image,map.call(body.world_position),maxi(6,int(body.world_radius*scale)),color)
		_ring(image,map.call(body.world_position),maxi(6,int(body.world_radius*scale)),2,Color("e8f2f5"))
	_disc(image,map.call(m.spawn_position),8,Color("f0b35a")); _ring(image,map.call(m.spawn_position),11,2,Color("f0b35a"))
	image.save_png("%s/%s.png" % [OUT,m.id])

func _content_bounds(m: SectorData) -> Rect2:
	var min_x := INF; var min_z := INF; var max_x := -INF; var max_z := -INF
	for p: Vector3 in m.route_checkpoints:
		min_x=minf(min_x,p.x); max_x=maxf(max_x,p.x); min_z=minf(min_z,p.z); max_z=maxf(max_z,p.z)
	for body: CelestialBodyData in m.bodies:
		min_x=minf(min_x,body.world_position.x-body.world_radius); max_x=maxf(max_x,body.world_position.x+body.world_radius)
		min_z=minf(min_z,body.world_position.z-body.world_radius); max_z=maxf(max_z,body.world_position.z+body.world_radius)
	for belt: BeltData in m.belts:
		if belt.is_boundary:
			min_x=minf(min_x,belt.center.x-belt.outer_radius*belt.aspect); max_x=maxf(max_x,belt.center.x+belt.outer_radius*belt.aspect)
			min_z=minf(min_z,belt.center.z-belt.outer_radius); max_z=maxf(max_z,belt.center.z+belt.outer_radius)
			continue
		if belt.shape == BeltData.Shape.RING:
			min_x=minf(min_x,belt.center.x-belt.outer_radius*belt.aspect); max_x=maxf(max_x,belt.center.x+belt.outer_radius*belt.aspect)
			min_z=minf(min_z,belt.center.z-belt.outer_radius); max_z=maxf(max_z,belt.center.z+belt.outer_radius)
		elif belt.shape == BeltData.Shape.SPLINE:
			for p: Vector3 in belt.control_points:
				min_x=minf(min_x,p.x-belt.half_width-belt.spline_wobble); max_x=maxf(max_x,p.x+belt.half_width+belt.spline_wobble)
				min_z=minf(min_z,p.z-belt.half_width-belt.spline_wobble); max_z=maxf(max_z,p.z+belt.half_width+belt.spline_wobble)
		else:
			min_x=minf(min_x,minf(belt.from_point.x,belt.to_point.x)-belt.half_width); max_x=maxf(max_x,maxf(belt.from_point.x,belt.to_point.x)+belt.half_width)
			min_z=minf(min_z,minf(belt.from_point.z,belt.to_point.z)-belt.half_width); max_z=maxf(max_z,maxf(belt.from_point.z,belt.to_point.z)+belt.half_width)
	return Rect2(min_x-18.0,min_z-18.0,max_x-min_x+36.0,max_z-min_z+36.0)

func _draw_belt_cloud(image: Image, belt: BeltData, map: Callable, scale: float) -> void:
	for sample: Dictionary in Layout.samples(belt):
		if not bool(sample["hits_flight"]): continue
		var center: Vector2i = map.call(Vector3(sample["position"]))
		var radius := maxi(1,int(float(sample["hit_radius"])*scale))
		_disc(image,center,radius,Color("a67955"))

func _draw_boundary_png(image: Image,belt: BeltData,map: Callable) -> void:
	var segs:=belt.boundary_segment_count()
	for radius: float in [belt.inner_radius,belt.outer_radius]:
		for i: int in range(segs):
			var a:=Vector2i(map.call(belt.point_on_ring(TAU*float(i)/float(segs),radius)))
			var b:=Vector2i(map.call(belt.point_on_ring(TAU*float(i+1)/float(segs),radius)))
			_line(image,a,b,Color("9b514d"),1)

func _line(img: Image,a: Vector2i,b: Vector2i,color: Color,width: int) -> void:
	var steps:=maxi(abs(b.x-a.x),abs(b.y-a.y)); if steps==0: _disc(img,a,width,color); return
	for i: int in range(steps+1):
		var p:=Vector2(a).lerp(Vector2(b),float(i)/steps); _disc(img,Vector2i(p.round()),maxi(0,width/2),color)

func _dashed(img: Image,a: Vector2i,b: Vector2i,color: Color) -> void:
	var steps:=maxi(abs(b.x-a.x),abs(b.y-a.y))
	for i: int in range(steps+1):
		if i%14<8: var p:=Vector2(a).lerp(Vector2(b),float(i)/maxi(1,steps)); _disc(img,Vector2i(p.round()),1,color)

func _disc(img: Image,c: Vector2i,r: int,color: Color) -> void:
	for y: int in range(-r,r+1):
		for x: int in range(-r,r+1):
			if x*x+y*y<=r*r and c.x+x>=0 and c.y+y>=0 and c.x+x<img.get_width() and c.y+y<img.get_height(): img.set_pixel(c.x+x,c.y+y,color)

func _ring(img: Image,c: Vector2i,r: int,width: int,color: Color) -> void:
	var inner:=maxi(0,r-width)
	for y: int in range(-r,r+1):
		for x: int in range(-r,r+1):
			var d:=x*x+y*y
			if d<=r*r and d>=inner*inner and c.x+x>=0 and c.y+y>=0 and c.x+x<img.get_width() and c.y+y<img.get_height(): img.set_pixel(c.x+x,c.y+y,color)
