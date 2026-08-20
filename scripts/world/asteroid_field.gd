class_name AsteroidField
extends Node3D
## 按 BeltData 生成有厚度的小行星带：航面稀疏挡路，上下铺开撑空间感。

const Layout = preload("res://scripts/belt_layout.gd")
const COLLISION_LAYER: int = 8
## 两台相机会把世界各画一遍；远到只剩亚像素的碎石再淡出，避免近处密度突然变空。
const FLIGHT_ROCK_VISIBILITY_RANGE: float = 520.0
const DECORATIVE_ROCK_VISIBILITY_RANGE: float = 460.0
const ROCK_VISIBILITY_MARGIN: float = 90.0


var _light_dir: Vector3 = Vector3(0.42, 0.62, 0.48)


func setup(belts: Array[BeltData], light_dir: Vector3) -> void:
	_light_dir = light_dir.normalized()
	for belt: BeltData in belts:
		_spawn_belt(belt)


func _spawn_belt(belt: BeltData) -> void:
	if belt.is_boundary:
		# 连续椭圆墙负责真正挡住飞船；碎石只是外形，避免从缝里钻出去。
		_spawn_boundary_wall(belt)

	for sample: Dictionary in Layout.samples(belt):
		var visual_rng: RandomNumberGenerator = Layout.visual_rng(belt,int(sample["index"]))
		_spawn_rock(Vector3(sample["position"]),float(sample["radius"]),visual_rng,float(sample["damage"]),
			belt.is_boundary,bool(sample["hits_flight"]),float(sample["hit_radius"]),belt.id,int(sample["index"]))


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

	var segment_count: int = belt.boundary_segment_count()
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
	_spawn_boundary_field_visual(wall,belt,segment_count)


func _spawn_boundary_field_visual(wall: StaticBody3D,belt: BeltData,segment_count: int) -> void:
	# 连续碰撞不能藏在看似可钻的石缝里；淡红能量幕明确表示碎石带中的封锁场。
	var surface:=SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(segment_count):
		var p0:=belt.point_on_ring(TAU*float(i)/float(segment_count),belt.inner_radius)
		var p1:=belt.point_on_ring(TAU*float(i+1)/float(segment_count),belt.inner_radius)
		var a:=p0+Vector3.DOWN*5.5; var b:=p1+Vector3.DOWN*5.5
		var c:=p1+Vector3.UP*5.5; var d:=p0+Vector3.UP*5.5
		for vertex: Vector3 in [a,b,c,a,c,d]: surface.add_vertex(vertex)
	var mesh:=surface.commit()
	var material:=StandardMaterial3D.new()
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	material.albedo_color=Color(0.72,0.18,0.22,0.075)
	material.emission_enabled=true
	material.emission=Color(0.55,0.08,0.12)
	material.emission_energy_multiplier=0.28
	var visual:=MeshInstance3D.new(); visual.name="BoundaryInterdictionField"
	visual.mesh=mesh; visual.material_override=material
	visual.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wall.add_child(visual)


func _spawn_rock(pos: Vector3, radius: float, rng: RandomNumberGenerator, damage: float,
		is_boundary: bool,hits_flight: bool,hit_radius: float,belt_id: String,sample_index: int) -> void:
	# 小行星不是行星：放开三轴差异与表面起伏，避免每颗都像规则圆球。
	var sx: float = rng.randf_range(0.76, 1.26)
	var sy: float = rng.randf_range(0.68, 1.18)
	var sz: float = rng.randf_range(0.78, 1.30)
	var root := Node3D.new()
	root.position = pos
	root.set_meta("belt_id",belt_id)
	root.set_meta("sample_index",sample_index)
	root.set_meta("hits_flight",hits_flight)
	root.set_meta("hit_radius",hit_radius)
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
	mesh.radial_segments = 7
	mesh.rings = 5
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixel_asteroid_3d.gdshader") as Shader
	var palette: Array[Color] = _pick_palette(rng)
	mat.set_shader_parameter("col_lit", palette[0])
	mat.set_shader_parameter("col_mid", palette[1])
	mat.set_shader_parameter("col_shade", palette[2])
	mat.set_shader_parameter("seed", rng.randf_range(1.1, 8.8))
	mat.set_shader_parameter("pixels", clampf(radius * 22.0 + rng.randf_range(8.0, 14.0), 12.0, 28.0))
	mat.set_shader_parameter("lump", rng.randf_range(0.13, 0.27))
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
	visual.visibility_range_end = FLIGHT_ROCK_VISIBILITY_RANGE if hits_flight else DECORATIVE_ROCK_VISIBILITY_RANGE
	visual.visibility_range_end_margin = ROCK_VISIBILITY_MARGIN
	# 体积层只负责远景密度，不需要每颗都运行脚本；飞行层岩块保留慢速翻滚反馈。
	if not hits_flight:
		visual.process_mode = Node.PROCESS_MODE_DISABLED
	visual.set("tumble", Vector3(
		rng.randf_range(-0.55, 0.55),
		rng.randf_range(-0.85, 0.85),
		rng.randf_range(-0.45, 0.45)
	))
	root.add_child(visual)
