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
	_meta(s, "level_1", 1, "织环航道", "正常协作", 160.0, PackedStringArray(),
		"建立无扰动基线；三枚织环依次挡住直航线，必须分别绕行南—北—南，整体航程显著拉长。")
	s.participant_name = "织环航道"
	s.participant_briefing = "依次绕过三枚织环尘带，将飞船送至绿洲近空。"
	s.participant_hint = "每一枚环带都要单独决定绕行侧，不要一次指向终点。"
	s.map_view_half = 78.0
	s.spawn_position = Vector3(-280, 0, 52)
	_move_body(s, "haven", Vector3(280, 0, -56))
	_move_body(s, "sol", Vector3(-230, 0, -55))
	_move_body(s, "ring", Vector3(-120, 0, 6))
	_move_body(s, "cinder", Vector3(135, 0, 10))
	_resize_body(s, "sol", 26.0)
	_reskin_body(s, "ring", "织环甲", "res://assets/planets/GasPlanetLayers/GasPlanetLayers.tscn", 16.0, 331, "gas")
	_reskin_body(s, "cinder", "织环丙", "res://assets/planets/GasPlanet/GasPlanet.tscn", 15.0, 519, "gas")
	_reskin_body(s, "haven", "绿洲", "res://assets/planets/Rivers/Rivers.tscn", 15.0, 108, "habitable")
	_add_body(s, "weave_mid", "织环乙", "res://assets/planets/GasPlanetLayers/GasPlanetLayers.tscn",
		Vector3(8, 0, -16), 14.0, 447, CelestialBodyData.Kind.PLANET, "gas")
	# 三环横贯航线：南绕甲 → 北绕乙 → 南绕丙。直冲会依次撞进三枚环带。
	var ring_a := _ring("weave_ring_a", Vector3(-120, 0, 6), 22, 38, 7101)
	ring_a.aspect = 1.08; ring_a.radial_irregularity = 0.12
	ring_a.rock_count = 40; ring_a.debris_count = 52; ring_a.flight_rock_ratio = 0.55; ring_a.rock_scale = 1.06
	var ring_b := _ring("weave_ring_b", Vector3(8, 0, -16), 20, 36, 7102)
	ring_b.aspect = 1.10; ring_b.radial_irregularity = 0.14
	ring_b.rock_count = 38; ring_b.debris_count = 50; ring_b.flight_rock_ratio = 0.55; ring_b.rock_scale = 1.06
	var ring_c := _ring("weave_ring_c", Vector3(135, 0, 10), 21, 37, 7103)
	ring_c.aspect = 1.06; ring_c.radial_irregularity = 0.13
	ring_c.rock_count = 40; ring_c.debris_count = 52; ring_c.flight_rock_ratio = 0.55; ring_c.rock_scale = 1.06
	# 上下两条长碎石封边把“溜边”路径堵掉，玩家只能在中间三环链之间连续决策。
	var top_lock := _band("top_lock", Vector3(-250, 0, 88), Vector3(250, 0, 88), 20.0, 7104)
	top_lock.rock_count = 40; top_lock.debris_count = 50
	var bottom_lock := _band("bottom_lock", Vector3(-250, 0, -92), Vector3(250, 0, -92), 20.0, 7105)
	bottom_lock.rock_count = 40; bottom_lock.debris_count = 50
	s.belts = [ring_a, ring_b, ring_c, top_lock, bottom_lock, _boundary(6204, 122.0, 3.15)]
	# 每个检查点都离环带外缘至少约 12u，避免审核路线擦芯。
	s.route_checkpoints = PackedVector3Array([
		s.spawn_position, Vector3(-240, 0, 48), Vector3(-190, 0, 40),
		Vector3(-170, 0, 0), Vector3(-155, 0, -40), Vector3(-120, 0, -48), Vector3(-80, 0, -46),
		Vector3(-55, 0, -42), Vector3(-38, 0, -5), Vector3(-30, 0, 25), Vector3(8, 0, 32), Vector3(45, 0, 28),
		Vector3(75, 0, 20), Vector3(90, 0, -10), Vector3(105, 0, -38), Vector3(135, 0, -42), Vector3(175, 0, -48),
		Vector3(230, 0, -56), Vector3(280, 0, -56),
	])
	s.safe_gate_points = PackedVector3Array([Vector3(175, 0, -48)])
	s.relay_stations = PackedVector3Array([Vector3(45, 0, 28)])
	return s


static func level_2() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "level_2", 2, "折光走廊", "精确引导", 180.0, PackedStringArray(),
		"四组开口错位的碎石门强制减速—转向—再加速；开口依次北/南/北/南，不能一次瞄穿。")
	s.display_name = "折光走廊"
	s.participant_name = "折光走廊"
	s.briefing = "正式任务 02：依次穿过四组错位航门，避免一次性指向远端。"
	s.participant_briefing = "依次通过错位航门，将飞船送至河港近空。"
	s.participant_hint = "每个开口方向都不同；转向前留出减速距离。"
	s.map_view_half = 74.0
	s.spawn_position = Vector3(-350, 0, 48)
	_move_body(s, "haven", Vector3(350, 0, -48))
	_move_body(s, "sol", Vector3(-290, 0, -55))
	_move_body(s, "ring", Vector3(-40, 0, 78))
	_move_body(s, "cinder", Vector3(220, 0, -72))
	_resize_body(s, "sol", 26.0)
	_reskin_body(s, "ring", "寒镜", "res://assets/planets/IceWorld/IceWorld.tscn", 14.0, 812, "ice")
	_reskin_body(s, "cinder", "熔核", "res://assets/planets/LavaWorld/LavaWorld.tscn", 14.0, 604, "lava")
	_reskin_body(s, "haven", "河港", "res://assets/planets/Rivers/Rivers.tscn", 15.0, 452, "habitable")
	# 四组门：开口分别在北 / 南 / 北 / 南。上脊堵住南侧，下脊堵住北侧，开口错开。
	s.belts = [
		# 门1：开口偏北（约 z=+42）
		_spline("gate_1_upper", [-220, -108, -210, -70, -198, -20, -185, 28], [10, 10, 9, 8], 2.6, 5201, 52),
		_spline("gate_1_lower", [-180, 58, -168, 78, -155, 96, -142, 108], [8, 9, 10, 11], 2.4, 5202, 44),
		# 门2：开口偏南（约 z=-38）
		_spline("gate_2_upper", [-110, -108, -98, -96, -86, -82, -74, -58], [11, 10, 9, 8], 2.4, 5203, 44),
		_spline("gate_2_lower", [-70, -20, -58, 20, -44, 70, -30, 108], [8, 9, 10, 11], 2.8, 5204, 52),
		# 门3：开口偏北（约 z=+36）
		_spline("gate_3_upper", [10, -108, 22, -70, 34, -22, 48, 22], [10, 10, 9, 8], 2.6, 5205, 52),
		_spline("gate_3_lower", [52, 52, 64, 74, 78, 94, 92, 108], [8, 9, 10, 11], 2.4, 5206, 44),
		# 门4：开口偏南（约 z=-42）
		_spline("gate_4_upper", [130, -108, 142, -96, 154, -82, 166, -62], [11, 10, 9, 8], 2.4, 5207, 44),
		_spline("gate_4_lower", [170, -24, 182, 16, 196, 66, 210, 108], [8, 9, 10, 11], 2.8, 5208, 52),
		_boundary(6201, 120.0, 3.75),
	]
	s.route_checkpoints = PackedVector3Array([
		s.spawn_position, Vector3(-300, 0, 46), Vector3(-250, 0, 44),
		Vector3(-210, 0, 42), Vector3(-185, 0, 42), Vector3(-150, 0, 20),
		Vector3(-110, 0, -10), Vector3(-90, 0, -36), Vector3(-70, 0, -38), Vector3(-30, 0, -10),
		Vector3(10, 0, 16), Vector3(40, 0, 34), Vector3(55, 0, 36), Vector3(100, 0, 10),
		Vector3(140, 0, -24), Vector3(160, 0, -42), Vector3(175, 0, -42), Vector3(230, 0, -44),
		Vector3(290, 0, -46), Vector3(350, 0, -48),
	])
	s.safe_gate_points = PackedVector3Array([Vector3(230, 0, -44)])
	s.relay_stations = PackedVector3Array([Vector3(-30, 0, -10), Vector3(100, 0, 10)])
	return s


static func level_3() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "level_3", 3, "磁暴坐标区", "导航异常归因", 200.0,
		PackedStringArray(["waypoint_drift"]),
		"两段校准井依次施压；每段进出口由行星挡住，迫使绕行进出。漂移落在第一井中段，安全门后进入第二井，出口再被寂井截断。")
	s.display_name = "磁暴坐标区"
	s.participant_name = "寂井侧翼"
	s.briefing = "正式任务 03：依次通过两段校准井。导航读数可能出现异常，请继续协作。"
	s.participant_briefing = "依次通过两段校准井，将飞船送至陆脊近空。"
	s.participant_hint = "进出口都被天体挡住；保持短句沟通，提早决定绕行侧。"
	s.map_view_half = 74.0
	s.spawn_position = Vector3(-350, 0, 58)
	_move_body(s, "haven", Vector3(350, 0, -60))
	# 入口挡星：压住直冲第一井（侧向净空约 12u）。
	_move_body(s, "sol", Vector3(-255, 0, 30))
	# 第二井出口寂井：截断安全门后的直线。
	_move_body(s, "ring", Vector3(220, 0, -20))
	# 无声月：封住寂井上方立即回切。
	_move_body(s, "cinder", Vector3(285, 0, -20))
	_resize_body(s, "sol", 27.0)
	_reskin_body(s, "ring", "寂井", "res://assets/planets/BlackHole/BlackHole.tscn", 32.0, 703, "black_hole", CelestialBodyData.Kind.HAZARD)
	_reskin_body(s, "cinder", "无声月", "res://assets/planets/NoAtmosphere/NoAtmosphere.tscn", 17.0, 219, "rock")
	_reskin_body(s, "haven", "陆脊", "res://assets/planets/LandMasses/LandMasses.tscn", 16.0, 608, "habitable")
	# 第一井出口 / 第二井入口挡星。
	_add_body(s, "well_gate", "磁锚", "res://assets/planets/IceWorld/IceWorld.tscn",
		Vector3(15, 0, 36), 18.0, 641, CelestialBodyData.Kind.PLANET, "ice")
	var well1_north := _spline("well1_north",
		[-200, 108, -160, 104, -110, 96, -60, 82, -20, 68, 10, 52],
		[13, 12, 11, 10, 10, 12], 3.0, 6301, 72, 0.68, 1.12)
	var well1_south := _spline("well1_south",
		[-210, 18, -160, 14, -110, 8, -60, -4, -20, -18, 5, -48],
		[12, 11, 10, 9, 10, 12], 2.8, 6302, 72, 0.68, 1.12)
	var well2_north := _spline("well2_north",
		[50, 62, 90, 50, 130, 32, 170, 10, 205, -10, 230, -36],
		[13, 12, 11, 10, 10, 12], 3.0, 6303, 72, 0.68, 1.12)
	var well2_south := _spline("well2_south",
		[40, -28, 85, -38, 125, -50, 165, -62, 200, -78, 225, -108],
		[12, 11, 10, 9, 10, 13], 2.8, 6304, 72, 0.68, 1.12)
	s.belts = [well1_north, well1_south, well2_north, well2_south, _boundary(6202, 120.0, 3.85)]
	s.route_checkpoints = PackedVector3Array([
		s.spawn_position, Vector3(-310, 0, 56), Vector3(-280, 0, 68),
		# 绕过入口恒星进入井1
		Vector3(-240, 0, 72), Vector3(-190, 0, 66), Vector3(-140, 0, 54), Vector3(-90, 0, 42),
		Vector3(-45, 0, 30), Vector3(-10, 0, 16),
		# 绕磁锚（此处为安全门）再进井2
		Vector3(20, 0, -4), Vector3(55, 0, 6), Vector3(95, 0, -2), Vector3(135, 0, -16),
		Vector3(175, 0, -28), Vector3(190, 0, -50),
		# 外侧绕寂井
		Vector3(210, 0, -70), Vector3(245, 0, -84), Vector3(295, 0, -78), Vector3(350, 0, -60),
	])
	s.disturbance_anchors = PackedVector3Array([Vector3(-90, 0, 42)])
	s.safe_gate_points = PackedVector3Array([Vector3(5, 0, 8)])
	s.relay_stations = PackedVector3Array([Vector3(5, 0, 8), Vector3(175, 0, -28)])
	return s


static func level_4() -> SectorData:
	var s := SectorCatalog.make_sector_01()
	_meta(s, "level_4", 4, "太阳风剪切", "协作恢复", 195.0,
		PackedStringArray(["ship_shear", "recovery_window"]),
		"先用短直线建立共同预期，再进入叠加大弧线的连续波浪航槽；上下危险脊在两端接入外圈，封死溜边路线，后半段逐渐加厚收窄。")
	s.display_name = "太阳风剪切"
	s.participant_name = "潮汐远航"
	s.briefing = "正式任务 04：通过太阳风剪切带，并在异常后恢复稳定航线。"
	s.participant_briefing = "穿越深空航区，将飞船送至潮汐站近空。"
	s.participant_hint = "按弯道分段布置航点；连续转向时主动降速。"
	s.map_view_half = 72.0
	s.spawn_position = Vector3(-340, 0, 12)
	_move_body(s, "haven", Vector3(340, 0, -18))
	_move_body(s, "sol", Vector3(-262, 0, -58))
	_move_body(s, "ring", Vector3(4, 0, -82))
	_move_body(s, "cinder", Vector3(172, 0, 68))
	_resize_body(s, "sol", 26.0)
	_reskin_body(s, "ring", "条纹巨星", "res://assets/planets/GasPlanet/GasPlanet.tscn", 18.0, 881, "gas")
	_reskin_body(s, "cinder", "裂火", "res://assets/planets/LavaWorld/LavaWorld.tscn", 15.0, 947, "lava")
	_reskin_body(s, "haven", "潮汐站", "res://assets/planets/Rivers/Rivers.tscn", 15.0, 760, "habitable")
	# 两条危险脊共享“向南下沉再回升”的大弧线，并在其上叠加连续反向波浪。
	# 四个端头分别接入外圈上下边界，玩家只能从入口漏斗进入航槽，不能溜边绕过整段。
	# 不能把上下控制点做成镜像，否则两条样条的几何中线会重新退化成直线。
	var shear_upper := _spline("shear_upper",
		[-330, -105, -310, -82, -280, -38, -220, -6, -155, -60, -90, 6, -25, -56, 40, 10, 105, -59, 170, -1, 235, -64, 280, -52, 310, -82, 330, -105],
		[11, 11, 11, 11, 12, 12, 12, 13, 13, 14, 14, 15, 15, 15], 1.8, 6401, 136, 0.72, 1.10)
	var shear_lower := _spline("shear_lower",
		[-330, 105, -310, 92, -280, 50, -220, 82, -155, 28, -90, 94, -25, 32, 40, 98, 105, 29, 170, 87, 235, 24, 280, 36, 310, 58, 330, 105],
		[11, 11, 11, 11, 12, 12, 12, 13, 13, 14, 14, 15, 15, 15], 2.0, 6402, 136, 0.72, 1.10)
	s.belts = [shear_upper, shear_lower, _boundary(6203, 120.0, 3.6)]
	# 从封边漏斗到出口完整采样两脊中线，大弧线和局部弯折都直接进入审核路线。
	s.route_checkpoints = PackedVector3Array([s.spawn_position])
	for i: int in range(61):
		var t := float(i) / 60.0
		s.route_checkpoints.append((shear_upper.spline_point(t) + shear_lower.spline_point(t)) * 0.5)
	s.route_checkpoints.append(Vector3(340, 0, -18))
	var first_anchor := s.route_checkpoints[16]
	var first_safe := s.route_checkpoints[20]
	var second_anchor := s.route_checkpoints[38]
	var second_safe := s.route_checkpoints[42]
	s.disturbance_anchors = PackedVector3Array([first_anchor, second_anchor])
	s.safe_gate_points = PackedVector3Array([first_safe, second_safe])
	s.relay_stations = PackedVector3Array([first_safe, second_safe])
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


static func _add_body(s: SectorData, id: String, display_name: String, scene_path: String,
		pos: Vector3, radius: float, seed: int, kind: CelestialBodyData.Kind, visual: String) -> void:
	var body := CelestialBodyData.new()
	body.id = id
	body.display_name = display_name
	body.scene_path = scene_path
	body.world_position = pos
	body.world_radius = radius
	body.collision_radius = radius
	body.map_pixels = clampi(int(round(radius * 8.0)), 48, 160)
	body.seed_value = seed
	body.kind = kind
	body.visual = visual
	body.spin_speed = 0.12
	s.bodies.append(body)


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
