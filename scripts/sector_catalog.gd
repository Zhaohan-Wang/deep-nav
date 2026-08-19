class_name SectorCatalog
extends RefCounted
## 关卡目录。后面加图只在这里取用行星 / 尘带素材。


static func make_sector_01() -> SectorData:
	var sector := SectorData.new()
	sector.id = "ring_passage"
	sector.display_name = "织环航道"
	sector.briefing = "合同 01：穿过织环尘带，把船送到绿洲近空。撞上行星会解体，贴边进入轨道才算完成。"
	sector.objective_hint = "目标  绿洲近空  ·  可绕行或穿过尘带"
	sector.world_half = 168.0
	sector.spawn_position = Vector3(4.0, 0.0, 70.0)
	sector.spawn_heading = 0.0
	sector.objective_body_id = "haven"
	sector.dock_range = 6.0

	# 本关只用四颗：星、气态、岩质、宜居。冰/熔岩/黑洞留给后面的图。
	sector.bodies = [
		_body(
			"sol", "烛火", "res://assets/planets/Star/Star.tscn",
			Vector3(-74.0, 0.0, -70.0), 11.0, 214, CelestialBodyData.Kind.STAR, "star", 0.04
		),
		_body(
			"ring", "织环", "res://assets/planets/GasPlanetLayers/GasPlanetLayers.tscn",
			Vector3(-26.0, 0.0, -6.0), 10.0, 331, CelestialBodyData.Kind.PLANET, "gas", 0.11
		),
		_body(
			"cinder", "烬月", "res://assets/planets/NoAtmosphere/NoAtmosphere.tscn",
			Vector3(46.0, 0.0, 24.0), 5.5, 219, CelestialBodyData.Kind.PLANET, "rock", 0.16
		),
		_body(
			# 终点挪远：离烬月与织环尘带都留出更宽的空档。
			"haven", "绿洲", "res://assets/planets/LandMasses/LandMasses.tscn",
			Vector3(44.0, 0.0, -82.0), 8.0, 108, CelestialBodyData.Kind.DESTINATION, "habitable", 0.07
		),
	]

	var ring_belt := BeltData.new()
	ring_belt.id = "weave_ring"
	ring_belt.display_name = "织环尘带"
	ring_belt.shape = BeltData.Shape.RING
	ring_belt.center = Vector3(-26.0, 0.0, -6.0)
	ring_belt.inner_radius = 20.0
	ring_belt.outer_radius = 36.0
	ring_belt.rock_count = 26
	ring_belt.debris_count = 34
	ring_belt.seed_value = 9041

	var gate_belt := BeltData.new()
	gate_belt.id = "gravel_gate"
	gate_belt.display_name = "碎石门"
	gate_belt.shape = BeltData.Shape.BAND
	gate_belt.from_point = Vector3(22.0, 0.0, 48.0)
	gate_belt.to_point = Vector3(-6.0, 0.0, 12.0)
	gate_belt.half_width = 9.0
	gate_belt.rock_count = 14
	gate_belt.debris_count = 18
	gate_belt.seed_value = 4177

	# 外圈碎石墙：16:9 椭圆，贴合小地图外沿。
	var wall := BeltData.new()
	wall.id = "sector_wall"
	wall.display_name = ""
	wall.shape = BeltData.Shape.RING
	wall.center = Vector3.ZERO
	wall.inner_radius = 140.0
	wall.outer_radius = 156.0
	wall.aspect = 16.0 / 9.0
	wall.rock_count = 72
	wall.debris_count = 52
	wall.seed_value = 6203
	wall.is_boundary = true
	wall.boundary_exponent = 6.0

	sector.belts = [gate_belt, ring_belt, wall]
	return sector


static func _body(
		id: String,
		display_name: String,
		scene_path: String,
		world_position: Vector3,
		world_radius: float,
		seed_value: int,
		kind: CelestialBodyData.Kind,
		visual: String,
		spin_speed: float
	) -> CelestialBodyData:
	var data := CelestialBodyData.new()
	data.id = id
	data.display_name = display_name
	data.scene_path = scene_path
	data.world_position = world_position
	# 星图像素分辨率只影响颗粒，显示直径一律按 world_radius 换算。
	data.map_pixels = clampi(int(round(world_radius * 8.0)), 48, 128)
	data.world_radius = world_radius
	data.collision_radius = world_radius
	data.seed_value = seed_value
	data.kind = kind
	data.visual = visual
	data.spin_speed = spin_speed
	return data
