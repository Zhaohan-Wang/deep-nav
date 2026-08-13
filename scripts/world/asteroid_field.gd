class_name AsteroidField
extends Node3D
## 按 BeltData 生成有厚度的小行星带：航面稀疏挡路，上下铺开撑空间感。

const COLLISION_LAYER: int = 8
## 石头碰撞球碰到这个高度带，才算挡飞船。
const FLIGHT_HIT_SLAB: float = 2.8


var _light_dir: Vector3 = Vector3(0.42, 0.62, 0.48)


func setup(belts: Array[BeltData], light_dir: Vector3) -> void:
	_light_dir = light_dir.normalized()
	for belt: BeltData in belts:
		_spawn_belt(belt)


func _spawn_belt(belt: BeltData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = belt.seed_value
	if belt.is_boundary:
		# 连续椭圆墙负责真正挡住飞船；碎石只是外形，避免从缝里钻出去。
		_spawn_boundary_wall(belt)

	var span: float = _height_span(belt)
	# 廊道要能穿，航面略密一点；环带和外墙把密度留给上下两层。
	var mid_rock_ratio: float = 0.36 if belt.shape == BeltData.Shape.BAND else 0.20
	var mid_debris_ratio: float = 0.20 if belt.shape == BeltData.Shape.BAND else 0.10
	var mid_rocks: int = maxi(2, int(round(float(belt.rock_count) * mid_rock_ratio)))
	var mid_debris: int = maxi(1, int(round(float(belt.debris_count) * mid_debris_ratio)))
	var vol_rocks: int = maxi(0, belt.rock_count - mid_rocks)
	var vol_debris: int = maxi(0, belt.debris_count - mid_debris)
	# 石头变小后补一点碎石，带才不会空。
	vol_debris += 32 if belt.is_boundary else 24

	for i: int in range(mid_rocks):
		var pos: Vector3 = belt.sample_xz(rng)
		pos.y = _sample_mid_y(rng)
		_spawn_rock(pos, _sample_radius(rng, 0.52, 1.12), rng, 14.0, belt.is_boundary)
	for i: int in range(mid_debris):
		var pos: Vector3 = belt.sample_xz(rng)
		pos.y = _sample_mid_y(rng)
		_spawn_rock(pos, _sample_radius(rng, 0.28, 0.56), rng, 8.0, belt.is_boundary)
	for i: int in range(vol_rocks):
		var pos: Vector3 = belt.sample_xz(rng)
		pos.y = _sample_volume_y(rng, span)
		_spawn_rock(pos, _sample_radius(rng, 0.38, 0.88), rng, 10.0, belt.is_boundary)
	for i: int in range(vol_debris):
		var pos: Vector3 = belt.sample_xz(rng)
		pos.y = _sample_volume_y(rng, span)
		_spawn_rock(pos, _sample_radius(rng, 0.16, 0.42), rng, 6.0, belt.is_boundary)


func _height_span(belt: BeltData) -> float:
	if belt.is_boundary:
		return 28.0
	if belt.shape == BeltData.Shape.BAND:
		return 15.0
	return 22.0


## 多数偏小、偶尔略大，避免清一色，也避免长到行星那么大。
func _sample_radius(rng: RandomNumberGenerator, radius_min: float, radius_max: float) -> float:
	var t: float = rng.randf()
	t = t * t
	return lerpf(radius_min, radius_max, t)


func _sample_mid_y(rng: RandomNumberGenerator) -> float:
	# 高斯抖开，不要齐刷刷贴在 y=0 一条线上。
	return clampf(rng.randfn(0.0, 0.95), -2.4, 2.4)


func _sample_volume_y(rng: RandomNumberGenerator, span: float) -> float:
	# 高斯铺成一团云，再把航面附近扔掉，避免又叠成一张饼。
	var clear: float = 4.6
	for _attempt: int in range(8):
		var y: float = rng.randfn(0.0, span * 0.48)
		y = clampf(y, -span * 1.25, span * 1.25)
		if absf(y) >= clear:
			return y
	return span * 0.62 if rng.randf() < 0.5 else -span * 0.62


func _pick_palette(rng: RandomNumberGenerator) -> Array[Color]:
	var lit: Array[Color] = [
		Color("a3a8c2"), Color("8a7a84"), Color("c4b49a"), Color("7a8494")
	]
	var mid: Array[Color] = [
		Color("4c6885"), Color("4a3c48"), Color("6a5a48"), Color("3a4450")
	]
	var shade: Array[Color] = [
		Color("2a2e4a"), Color("1e1824"), Color("2c241c"), Color("181c24")
	]
	var idx: int = rng.randi_range(0, 3)
	return [lit[idx], mid[idx], shade[idx]]


func _spawn_boundary_wall(belt: BeltData) -> void:
	var wall := StaticBody3D.new()
	wall.name = "SectorBoundary"
	wall.collision_layer = COLLISION_LAYER
	wall.collision_mask = 0
	wall.add_to_group("asteroid")
	wall.add_to_group("world_boundary")
	var bounce_mat := PhysicsMaterial.new()
	bounce_mat.friction = 0.18
	bounce_mat.bounce = 0.38
	wall.physics_material_override = bounce_mat
	add_child(wall)

	var segment_count: int = 56
	var thickness: float = maxf(belt.outer_radius - belt.inner_radius, 10.0)
	var height: float = 12.0
	for i: int in range(segment_count):
		var angle_a: float = TAU * float(i) / float(segment_count)
		var angle_b: float = TAU * float(i + 1) / float(segment_count)
		var p0: Vector3 = belt.point_on_ring(angle_a, belt.inner_radius)
		var p1: Vector3 = belt.point_on_ring(angle_b, belt.inner_radius)
		var chord: Vector3 = p1 - p0
		chord.y = 0.0
		var chord_len: float = chord.length()
		if chord_len < 0.05:
			continue
		var tangent: Vector3 = chord / chord_len
		var outward: Vector3 = tangent.cross(Vector3.UP)
		if outward.length_squared() < 0.0001:
			continue
		outward = outward.normalized()
		var mid: Vector3 = (p0 + p1) * 0.5
		mid.y = 0.0
		var from_center := Vector3(mid.x - belt.center.x, 0.0, mid.z - belt.center.z)
		if outward.dot(from_center) < 0.0:
			outward = -outward
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(chord_len * 1.12, height, thickness)
		col.shape = box
		var basis := Basis(tangent, Vector3.UP, outward).orthonormalized()
		col.transform = Transform3D(basis, mid + outward * (thickness * 0.5))
		wall.add_child(col)


func _spawn_rock(pos: Vector3, radius: float, rng: RandomNumberGenerator, damage: float, is_boundary: bool) -> void:
	# 三轴只做轻微分歧，看起来仍是同一类碎石，而不是被拉扁的椭圆。
	var sx: float = rng.randf_range(0.94, 1.06)
	var sy: float = rng.randf_range(0.90, 1.04)
	var sz: float = rng.randf_range(0.94, 1.06)
	var hit_radius: float = radius * maxf(sx, sz) * 1.06

	# 只有擦到航面的石头才挂碰撞；高/低的只做景深，避免镜头被头顶碎石顶住。
	var hits_flight: bool = absf(pos.y) - hit_radius <= FLIGHT_HIT_SLAB

	var root := Node3D.new()
	root.position = pos
	add_child(root)
	if hits_flight:
		var body := StaticBody3D.new()
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = 0
		body.add_to_group("asteroid")
		if is_boundary:
			body.add_to_group("world_boundary")
		body.set_meta("asteroid_damage", damage)
		var bounce_mat := PhysicsMaterial.new()
		bounce_mat.friction = 0.16
		bounce_mat.bounce = 0.28
		body.physics_material_override = bounce_mat
		var col := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = hit_radius
		col.shape = sphere
		body.add_child(col)
		root.add_child(body)

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 8
	mesh.rings = 6
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixel_asteroid_3d.gdshader") as Shader
	var palette: Array[Color] = _pick_palette(rng)
	mat.set_shader_parameter("col_lit", palette[0])
	mat.set_shader_parameter("col_mid", palette[1])
	mat.set_shader_parameter("col_shade", palette[2])
	mat.set_shader_parameter("seed", rng.randf_range(1.1, 8.8))
	mat.set_shader_parameter("pixels", clampf(radius * 22.0 + rng.randf_range(8.0, 14.0), 12.0, 28.0))
	mat.set_shader_parameter("lump", rng.randf_range(0.07, 0.14))
	mat.set_shader_parameter("light_dir", _light_dir)
	mesh.material = mat

	var visual := MeshInstance3D.new()
	visual.set_script(load("res://scripts/world/asteroid_rock.gd") as Script)
	visual.mesh = mesh
	visual.scale = Vector3(radius * sx, radius * sy, radius * sz)
	visual.rotation = Vector3(
		rng.randf_range(0.0, TAU),
		rng.randf_range(0.0, TAU),
		rng.randf_range(0.0, TAU)
	)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.set("tumble", Vector3(
		rng.randf_range(-0.55, 0.55),
		rng.randf_range(-0.85, 0.85),
		rng.randf_range(-0.45, 0.45)
	))
	root.add_child(visual)
