class_name MissionCatalog
extends RefCounted
## 正式实验关卡目录。所有地图变化都从这里生成，避免复制运行场景。

const IDS: PackedStringArray = ["practice", "level_1", "level_2", "level_3", "level_4"]


static func all() -> Array[SectorData]:
	return [practice(), level_1(), level_2(), level_3(), level_4()]


static func by_id(id: String) -> SectorData:
	for mission: SectorData in all():
		if mission.id == id:
			return mission
	return practice()


static func practice() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "practice", 0, "训练航道", "角色熟悉", 180.0, PackedStringArray(),
		"建立领航员放置航点、驾驶员跟随指令的共同操作模型；航线宽、危险物少。")
	s.display_name = "训练航道"
	s.participant_name = "训练航道"
	s.briefing = "训练任务：确认角色分工，沿开阔航线抵达绿洲。"
	s.participant_briefing = "确认角色分工，沿开阔航线抵达绿洲近空。"
	s.participant_hint = "先用短距离航点建立共同节奏，确认双方都理解当前分工。"
	s.map_view_half = 110.0
	s.spawn_position = Vector3(-170, 0, 55)
	_move_body(s, "haven", Vector3(170, 0, -55))
	_move_body(s, "sol", Vector3(-65, 0, -62))
	_move_body(s, "ring", Vector3(25, 0, 76))
	_move_body(s, "cinder", Vector3(108, 0, 42))
	_resize_body(s,"sol",24.0); _resize_body(s,"haven",14.0)
	_reskin_body(s,"ring","浅潮","res://assets/planets/IceWorld/IceWorld.tscn",13.0,412,"ice")
	_reskin_body(s,"cinder","旱原","res://assets/planets/DryTerran/DryTerran.tscn",10.0,237,"rock")
	s.belts = [_boundary(6200,118.0,2.0)]
	s.route_checkpoints = PackedVector3Array([
		s.spawn_position, Vector3(-102, 0, 42), Vector3(-34, 0, 20), Vector3(36, 0, -8),
		Vector3(104, 0, -34), Vector3(170, 0, -55)
	])
	# 训练关短，解体直接回起点，不设中继站。
	s.relay_stations = PackedVector3Array()
	return s


static func level_1() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "level_1", 1, "织环航道", "正常协作", 150.0, PackedStringArray(),
		"建立无扰动基线；开阔进场先形成共同节奏，单一环带再迫使领航员明确选择绕行方向。")
	s.participant_name = "织环航道"
	s.participant_briefing = "穿过织环尘带，将飞船送至绿洲近空。"
	s.participant_hint = "先观察环带开口，再用连续航点表达绕行方向。"
	s.map_view_half = 78.0
	s.spawn_position = Vector3(-270, 0, 58)
	_move_body(s,"haven",Vector3(270,0,-62)); _move_body(s,"sol",Vector3(-205,0,-60))
	_move_body(s,"ring",Vector3(-48,0,0)); _move_body(s,"cinder",Vector3(112,0,42))
	_resize_body(s,"sol",26.0)
	_reskin_body(s,"ring","织环","res://assets/planets/GasPlanetLayers/GasPlanetLayers.tscn",19.0,331,"gas")
	_reskin_body(s,"cinder","游砾","res://assets/planets/Asteroids/Asteroid.tscn",12.0,519,"rock")
	_reskin_body(s,"haven","绿洲","res://assets/planets/Rivers/Rivers.tscn",15.0,108,"habitable")
	var weave_ring := _ring("weave_ring",Vector3(-48,0,0),28,49,7101)
	weave_ring.aspect=1.12; weave_ring.radial_irregularity=0.17
	weave_ring.rock_count=48; weave_ring.debris_count=62; weave_ring.flight_rock_ratio=0.52; weave_ring.rock_scale=1.08
	s.belts = [
		weave_ring,
		_boundary(6204,120.0,2.8),
	]
	# 环带本身形成上下两条清晰绕行路线；基准路线从远离熔岩星的一侧通过。
	s.route_checkpoints = PackedVector3Array([
		s.spawn_position,Vector3(-216,0,48),Vector3(-165,0,38),Vector3(-125,0,25),
		Vector3(-112,0,-10),Vector3(-104,0,-42),Vector3(-76,0,-61),Vector3(-30,0,-62),
		Vector3(38,0,-42),Vector3(106,0,-24),
		Vector3(166,0,-34),Vector3(222,0,-50),Vector3(270,0,-62)
	])
	s.safe_gate_points = PackedVector3Array([Vector3(166,0,-34)])
	# 环带绕行完成后一座中继站，避免后半段解体整段重来。
	s.relay_stations = PackedVector3Array([Vector3(38,0,-42)])
	return s


static func level_2() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "level_2", 2, "折光走廊", "精确引导", 160.0, PackedStringArray(),
		"两段错位碎石带形成清晰的减速—转向—再加速节奏；每次航点都有明确局部用途。")
	s.display_name = "折光走廊"
	s.participant_name = "折光走廊"
	s.briefing = "正式任务 02：依次穿过两段错位航门，避免一次性指向远端。"
	s.participant_briefing = "依次通过错位航门，将飞船送至河港近空。"
	s.participant_hint = "把长航程拆成短段，转向前留出减速距离。"
	s.map_view_half = 76.0
	s.spawn_position = Vector3(-330, 0, 70)
	_move_body(s, "haven", Vector3(330, 0, -68))
	_move_body(s, "sol", Vector3(-260, 0, -60))
	_move_body(s, "ring", Vector3(12, 0, 78))
	_move_body(s, "cinder", Vector3(246, 0, 42))
	_resize_body(s,"sol",26.0)
	_reskin_body(s,"ring","寒镜","res://assets/planets/IceWorld/IceWorld.tscn",14.0,812,"ice")
	_reskin_body(s,"cinder","熔核","res://assets/planets/LavaWorld/LavaWorld.tscn",14.0,604,"lava")
	_reskin_body(s,"haven","河港","res://assets/planets/Rivers/Rivers.tscn",15.0,452,"habitable")
	s.belts = [
		_spline("gate_1_upper",[-178,-108,-166,-74,-150,-28,-132,40],[9,9,8,7],2.8,5201,58),
		_spline("gate_1_lower",[-128,64,-112,80,-96,96,-82,108],[7,8,9,10],2.2,5202,40),
		_spline("gate_2_upper",[44,-108,56,-88,70,-73,88,-62],[10,9,8,7],2.4,5203,40),
		_spline("gate_2_lower",[94,-38,110,-12,125,44,136,108],[7,8,9,10],3.0,5204,58),
		_boundary(6201,120.0,3.6),
	]
	s.route_checkpoints = PackedVector3Array([
		s.spawn_position,Vector3(-266,0,68),Vector3(-202,0,62),Vector3(-132,0,52),
		Vector3(-62,0,25),Vector3(-22,0,8),Vector3(18,0,-10),Vector3(55,0,-30),Vector3(92,0,-50),Vector3(162,0,-48),
		Vector3(226,0,-50),Vector3(282,0,-59),Vector3(330,0,-68)
	])
	s.safe_gate_points = PackedVector3Array([Vector3(162,0,-48)])
	# 第一道航门之后一座中继站。
	s.relay_stations = PackedVector3Array([Vector3(-22,0,8)])
	return s


static func level_3() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "level_3", 3, "磁暴坐标区", "导航异常归因", 180.0,
		PackedStringArray(["waypoint_drift"]),
		"单一弯曲校准航道先建立稳定预期；安全门后由大型寂井截断直线并迫使外侧绕行，让测量段清楚、恢复段有技巧。")
	s.display_name = "磁暴坐标区"
	s.participant_name = "寂井侧翼"
	s.briefing = "正式任务 03：沿磁暴校准走廊通过寂井侧翼。导航读数可能出现异常，请继续协作。"
	s.participant_briefing = "沿校准走廊通过寂井侧翼，将飞船送至陆脊近空。"
	s.participant_hint = "保持短句沟通；接近大型危险天体时，提早决定绕行侧。"
	s.map_view_half = 76.0
	s.spawn_position = Vector3(-350, 0, 68)
	_move_body(s, "haven", Vector3(350, 0, -66))
	_move_body(s, "sol", Vector3(-250, 0, 28))
	_move_body(s, "ring", Vector3(210, 0, -22))
	_move_body(s, "cinder", Vector3(275, 0, -2))
	_resize_body(s,"sol",27.0)
	_reskin_body(s,"ring","寂井","res://assets/planets/BlackHole/BlackHole.tscn",32.0,703,"black_hole",CelestialBodyData.Kind.HAZARD)
	_reskin_body(s,"cinder","无声月","res://assets/planets/NoAtmosphere/NoAtmosphere.tscn",17.0,219,"rock")
	_reskin_body(s,"haven","陆脊","res://assets/planets/LandMasses/LandMasses.tscn",16.0,608,"habitable")
	# 与 Level 1 的“完整环带二选一”相反，这里用两条不对称磁化碎石脊围出
	# 唯一、连续、可读的校准走廊。直接冲终点会切进南脊，沿走廊则无需猜路线。
	var north_ridge := _spline("magnetic_north_ridge",
		[-176,108,-140,107,-95,105,-48,96,0,78,52,57,105,35,155,12,195,-8],
		[12,11,9,8,8,8,9,10,12],3.4,6301,92,0.68,1.14)
	var south_ridge := _spline("magnetic_south_ridge",
		[-184,35,-140,34,-95,31,-48,24,0,8,52,-11,105,-31,155,-53,180,-108],
		[11,9,8,7,7,8,9,11,13],3.0,6302,92,0.68,1.14)
	s.belts = [
		north_ridge,
		south_ridge,
		_boundary(6202,120.0,3.75),
	]
	s.route_checkpoints = PackedVector3Array([
		s.spawn_position,Vector3(-286,0,68),Vector3(-222,0,72),Vector3(-164,0,82),
		Vector3(-110,0,82),Vector3(-56,0,68),Vector3(-2,0,50),Vector3(52,0,29),
		Vector3(101,0,10),Vector3(143,0,-8),Vector3(165,0,-24),Vector3(178,0,-52),
		Vector3(205,0,-76),Vector3(250,0,-82),Vector3(300,0,-76),Vector3(350,0,-66)
	])
	s.disturbance_anchors = PackedVector3Array([Vector3(52,0,29)])
	s.safe_gate_points = PackedVector3Array([Vector3(143,0,-8)])
	# 校准走廊出口一座中继站，寂井绕行段解体不退回起点。
	s.relay_stations = PackedVector3Array([Vector3(143,0,-8)])
	return s


static func level_4() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "level_4", 4, "太阳风剪切", "协作恢复", 180.0,
		PackedStringArray(["ship_shear", "recovery_window"]),
		"先给出稳定直线建立共同预期，再以横向剪切打破预期；后半段留出恢复空间，测量是否继续依赖搭档。")
	s.display_name = "太阳风剪切"
	s.participant_name = "潮汐远航"
	s.briefing = "正式任务 04：通过太阳风剪切带，并在异常后恢复稳定航线。"
	s.participant_briefing = "穿越深空航区，将飞船送至潮汐站近空。"
	s.participant_hint = "维持稳定节奏；偏离航线时，优先确认当前位置和下一航点。"
	s.map_view_half = 72.0
	s.spawn_position = Vector3(-340, 0, 12)
	_move_body(s, "haven", Vector3(340, 0, -18))
	_move_body(s, "sol", Vector3(-262, 0, -58))
	_move_body(s, "ring", Vector3(4, 0, -82))
	_move_body(s, "cinder", Vector3(172, 0, 68))
	_resize_body(s,"sol",26.0)
	_reskin_body(s,"ring","条纹巨星","res://assets/planets/GasPlanet/GasPlanet.tscn",18.0,881,"gas")
	_reskin_body(s,"cinder","裂火","res://assets/planets/LavaWorld/LavaWorld.tscn",15.0,947,"lava")
	_reskin_body(s,"haven","潮汐站","res://assets/planets/Rivers/Rivers.tscn",15.0,760,"habitable")
	var shear_upper:=_spline("shear_upper",[-126,-108,-126,-49,-86,4,-20,-46,42,2,102,-42,151,-27,151,-108],
		[12,10,8,7,7,8,10,12],3.2,6401,112,0.70,1.16)
	var shear_lower:=_spline("shear_lower",[-126,108,-126,66,-86,48,-20,-2,42,46,102,2,151,17,151,108],
		[12,10,8,7,7,8,10,12],3.6,6402,112,0.70,1.16)
	s.belts = [
		# 两条自然弯曲的 U 形碎石脊接到外圈，留下唯一的剪切航槽；不能贴边绕过实验段。
		shear_upper,shear_lower,
		_boundary(6203,120.0,3.6),
	]
	s.route_checkpoints=PackedVector3Array([s.spawn_position,Vector3(-276,0,12),Vector3(-210,0,11),Vector3(-146,0,10)])
	# 标准路线从两条同源样条的几何中线生成，地图改形后不会悄悄穿进碎石带。
	for i: int in range(8,49):
		var t:=float(i)/56.0
		s.route_checkpoints.append((shear_upper.spline_point(t)+shear_lower.spline_point(t))*0.5)
	for p: Vector3 in [Vector3(170,0,-9),Vector3(230,0,-12),Vector3(282,0,-15),Vector3(340,0,-18)]: s.route_checkpoints.append(p)
	s.disturbance_anchors = PackedVector3Array([Vector3(18,0,3),Vector3(210,0,-11)])
	s.safe_gate_points = PackedVector3Array([Vector3(106,0,-20),Vector3(282,0,-15)])
	# 长关两座：前半出口一座，后半恢复段一座。
	s.relay_stations = PackedVector3Array([Vector3(106,0,-20),Vector3(230,0,-12)])
	return s


static func _meta(s: SectorData, id: String, order: int, short_name: String, challenge: String,
		time_limit: float, slots: PackedStringArray, intent: String) -> void:
	s.id = id
	s.order_index = order
	s.short_name = short_name
	s.challenge_type = challenge
	s.time_limit_s = time_limit
	# 解体次数不再结束任务；时限内从起点或已抵达的中继站复活。
	s.max_attempts = 0
	s.disturbance_slots = slots
	s.design_intent = intent


static func _move_body(s: SectorData, id: String, pos: Vector3) -> void:
	for body: CelestialBodyData in s.bodies:
		if body.id == id:
			body.world_position = pos


static func _resize_body(s: SectorData,id: String,radius: float) -> void:
	for body: CelestialBodyData in s.bodies:
		if body.id!=id: continue
		body.world_radius=radius; body.collision_radius=radius
		body.map_pixels=clampi(int(round(radius*8.0)),48,160)
		return


static func _reskin_body(s: SectorData,id: String,display_name: String,scene_path: String,radius: float,
		seed: int,visual: String,kind_override: int = -1) -> void:
	for body: CelestialBodyData in s.bodies:
		if body.id != id: continue
		body.display_name=display_name; body.scene_path=scene_path; body.world_radius=radius
		body.collision_radius=radius; body.map_pixels=clampi(int(round(radius*8.0)),48,160)
		body.seed_value=seed; body.visual=visual
		if kind_override>=0: body.kind=kind_override
		return


static func _band(id: String, from: Vector3, to: Vector3, half: float, seed: int) -> BeltData:
	var b := BeltData.new()
	b.id = id; b.shape = BeltData.Shape.BAND; b.from_point = from; b.to_point = to
	b.half_width = half; b.rock_count = 18; b.debris_count = 22; b.seed_value = seed
	return b


static func _ring(id: String, center: Vector3, inner: float, outer: float, seed: int) -> BeltData:
	var b := BeltData.new()
	b.id = id; b.shape = BeltData.Shape.RING; b.center = center
	b.inner_radius = inner; b.outer_radius = outer; b.rock_count = 28; b.debris_count = 34; b.seed_value = seed
	return b


## points 是 [x,z,x,z...]，避免关卡表被 Vector3 样板代码淹没。
static func _spline(id: String,points: Array,widths: Array,wobble: float,seed: int,rocks: int = 46,
		flight_ratio: float = 0.58,scale: float = 1.06) -> BeltData:
	var b:=BeltData.new(); b.id=id; b.shape=BeltData.Shape.SPLINE; b.seed_value=seed
	for i: int in range(0,points.size(),2): b.control_points.append(Vector3(float(points[i]),0.0,float(points[i+1])))
	for width: Variant in widths: b.width_profile.append(float(width))
	b.half_width=float(widths[0]) if not widths.is_empty() else 7.0; b.spline_wobble=wobble
	b.rock_count=rocks; b.debris_count=int(round(rocks*1.28)); b.flight_rock_ratio=flight_ratio; b.rock_scale=scale
	return b


static func _boundary(seed: int, inner_z: float = 140.0, aspect: float = 16.0 / 9.0) -> BeltData:
	var b := _ring("sector_wall", Vector3.ZERO, inner_z, inner_z + 14.0, seed)
	b.aspect = aspect; b.is_boundary = true; b.boundary_exponent=6.0; b.rock_count = 96; b.debris_count = 72
	return b
