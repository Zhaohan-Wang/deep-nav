class_name ShipBurst3D
extends Node3D
## 飞船爆炸：中心闪光 + 冲击光环 + 像素方块碎片。
## 视觉语言参考 dyadic-force 的 BallBurst，改成 3D 方块。

const SHARD_COUNT: int = 22
const SPARK_COUNT: int = 16
const LIFE: float = 0.95
const FLASH_LIFE: float = 0.22
const RING_LIFE: float = 0.42

const SHARD_COLORS: Array[Color] = [
	Color("e8a04a"),
	Color("d45b6a"),
	Color("6b2430"),
	Color("c8d4dc"),
	Color("3ec4d4"),
	Color("fff0c8"),
]

class Shard:
	var node: MeshInstance3D
	var vel: Vector3 = Vector3.ZERO
	var spin: Vector3 = Vector3.ZERO
	var base_scale: Vector3 = Vector3.ONE
	var start_alpha: float = 1.0

var _shards: Array[Shard] = []
var _age: float = 0.0
var _flash: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spawn_flash()
	_spawn_ring()
	_spawn_light()
	_spawn_shards()
	_spawn_sparks()


func _process(delta: float) -> void:
	var dt: float = delta
	if Engine.time_scale > 0.001 and Engine.time_scale < 0.5:
		dt = delta / maxf(Engine.time_scale, 0.05)
	_age += dt
	var t: float = clampf(_age / LIFE, 0.0, 1.0)
	if _flash != null:
		var ft: float = clampf(_age / FLASH_LIFE, 0.0, 1.0)
		var s: float = lerpf(0.4, 6.5, 1.0 - pow(1.0 - ft, 3.0))
		_flash.scale = Vector3.ONE * s
		_set_alpha(_flash, 0.95 * (1.0 - ft * ft))
		if ft >= 1.0:
			_flash.queue_free()
			_flash = null
	if _ring != null:
		var rt: float = clampf(_age / RING_LIFE, 0.0, 1.0)
		var s2: float = lerpf(0.8, 11.0, 1.0 - pow(1.0 - rt, 2.0))
		_ring.scale = Vector3(s2, s2 * 0.15, s2)
		_set_alpha(_ring, 0.85 * (1.0 - rt))
		if rt >= 1.0:
			_ring.queue_free()
			_ring = null
	if _light != null:
		_light.light_energy = lerpf(8.0, 0.0, t)
	for shard: Shard in _shards:
		shard.vel += Vector3(0.0, -6.0, 0.0) * dt
		shard.vel *= 0.985
		shard.node.position += shard.vel * dt
		shard.node.rotate_x(shard.spin.x * dt)
		shard.node.rotate_y(shard.spin.y * dt)
		shard.node.scale = shard.base_scale * lerpf(1.0, 0.25, t)
		_set_alpha(shard.node, shard.start_alpha * (1.0 - pow(t, 1.5)))
	if _age >= LIFE:
		queue_free()


func _spawn_flash() -> void:
	_flash = _make_sphere(0.35, Color(1.0, 0.96, 0.82, 0.95), true)
	add_child(_flash)


func _spawn_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.58
	torus.rings = 16
	torus.ring_segments = 8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.45, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	torus.material = mat
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	add_child(_ring)


func _spawn_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.78, 0.42)
	_light.light_energy = 8.0
	_light.omni_range = 28.0
	add_child(_light)


func _spawn_shards() -> void:
	for i: int in SHARD_COUNT:
		var color: Color = SHARD_COLORS[i % SHARD_COLORS.size()]
		var size: float = randf_range(0.18, 0.42)
		var mesh_inst: MeshInstance3D = _make_box(size, color)
		var dir: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 1.0), randf_range(-1.0, 1.0)).normalized()
		_add_shard(mesh_inst, dir * randf_range(8.0, 22.0), Vector3(
			randf_range(-8.0, 8.0), randf_range(-8.0, 8.0), randf_range(-8.0, 8.0)
		))


func _spawn_sparks() -> void:
	for i: int in SPARK_COUNT:
		var mesh_inst: MeshInstance3D = _make_box(0.12, Color("fff4c8"))
		var dir: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 0.8), randf_range(-1.0, 1.0)).normalized()
		_add_shard(mesh_inst, dir * randf_range(14.0, 28.0), Vector3.ZERO)


func _add_shard(mesh_inst: MeshInstance3D, vel: Vector3, spin: Vector3) -> void:
	add_child(mesh_inst)
	var shard := Shard.new()
	shard.node = mesh_inst
	shard.vel = vel
	shard.spin = spin
	shard.base_scale = mesh_inst.scale
	shard.start_alpha = 1.0
	_shards.append(shard)


func _make_box(size: float, color: Color) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(size, size, size * randf_range(0.6, 1.4))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	box.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = box
	return inst


func _make_sphere(radius: float, color: Color, _bright: bool) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.7)
	mat.emission_energy_multiplier = 2.2
	sphere.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = sphere
	return inst


func _set_alpha(inst: MeshInstance3D, alpha: float) -> void:
	var prim := inst.mesh as PrimitiveMesh
	if prim == null:
		return
	var std := prim.material as StandardMaterial3D
	if std == null:
		return
	var c: Color = std.albedo_color
	c.a = alpha
	std.albedo_color = c


static func play(parent: Node, world_pos: Vector3) -> ShipBurst3D:
	var burst := ShipBurst3D.new()
	burst.name = "ShipBurst3D"
	parent.add_child(burst)
	burst.global_position = world_pos
	return burst
