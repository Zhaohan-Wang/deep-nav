class_name SpaceWorld
extends Node3D
## 共享的 3D 像素宇宙：大行星、小行星、飞船。

var _sky_materials: Array[ShaderMaterial] = []


func _ready() -> void:
	_setup_environment()
	_spawn_bodies()
	_spawn_asteroids()
	_spawn_ship()
	add_child(WaypointBeacon.new())
	_spawn_relay_stations()
	set_process(true)


func _process(_delta: float) -> void:
	var travel := Vector2(Game.ship_position.x, Game.ship_position.z) * 0.0014
	for material: ShaderMaterial in _sky_materials:
		material.set_shader_parameter("travel_offset", travel)


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.009, 0.014)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.04, 0.045, 0.06)
	env.ambient_light_energy = 0.28
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	# 引擎雾按相机距离，转弯时会把原本清晰的物体糊掉；改由屏幕雾按飞船距离计算。
	env.fog_enabled = false
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	# 一层很淡的大块明暗就够，第二层碎云会抢行星。
	_spawn_sky_layer(3000.0, 0.48, 0.23, 0.0)
	var stars := Node3D.new()
	stars.name = "StarField"
	stars.set_script(load("res://scripts/world/star_field.gd") as Script)
	add_child(stars)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.90, 0.78)
	sun.light_energy = 0.85
	sun.shadow_enabled = false
	add_child(sun)
	var star: CelestialBodyData = Game.find_star()
	if star != null:
		sun.position = star.world_position
		if sun.position.length_squared() > 0.001:
			sun.look_at(Vector3.ZERO, Vector3.UP)
	else:
		sun.rotation_degrees = Vector3(-42.0, 50.0, 0.0)


func _spawn_sky_layer(radius: float, noise_scale: float, dust_strength: float, layer_offset: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 16
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/pixel_sky.gdshader") as Shader
	sky_mat.set_shader_parameter("noise_scale", noise_scale)
	sky_mat.set_shader_parameter("dust_strength", dust_strength)
	sky_mat.set_shader_parameter("layer_offset", layer_offset)
	_sky_materials.append(sky_mat)
	sky_mat.render_priority = -128
	mesh.material = sky_mat
	var dome := MeshInstance3D.new()
	dome.mesh = mesh
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	dome.extra_cull_margin = 2800.0
	add_child(dome)


func _spawn_bodies() -> void:
	var planets: Array[Planet3D] = []
	for body: CelestialBodyData in Game.celestial_bodies:
		var planet := Planet3D.new()
		add_child(planet)
		planet.setup(body)
		planets.append(planet)
	var star: CelestialBodyData = Game.find_star()
	if star != null:
		for planet: Planet3D in planets:
			planet.apply_star_light(star.world_position)


func _spawn_asteroids() -> void:
	var field := AsteroidField.new()
	field.name = "AsteroidField"
	var light_dir := Vector3(0.42, 0.62, 0.48)
	var star: CelestialBodyData = Game.find_star()
	if star != null:
		light_dir = star.world_position
		if light_dir.length_squared() > 0.001:
			light_dir = light_dir.normalized()
	var belts: Array[BeltData] = []
	if Game.current_sector != null:
		belts = Game.current_sector.belts
	field.setup(belts, light_dir)
	add_child(field)


func _spawn_ship() -> void:
	var ship_scene: PackedScene = load("res://scenes/ship.tscn") as PackedScene
	var ship: Node = ship_scene.instantiate()
	add_child(ship)


func _spawn_relay_stations() -> void:
	if Game.current_sector == null:
		return
	var station_script := load("res://scripts/world/relay_station_3d.gd") as Script
	for i: int in range(Game.current_sector.relay_stations.size()):
		var station := Node3D.new()
		station.set_script(station_script)
		add_child(station)
		station.call("setup", i, Game.current_sector.relay_stations[i])
