class_name AsteroidField
extends Node3D
## 按 BeltData 生成有厚度的小行星带：航面稀疏挡路，上下铺开撑空间感。

const Layout = preload("res://scripts/belt_layout.gd")
const COLLISION_LAYER: int = 8
## 两台相机会把世界各画一遍；远到只剩亚像素的碎石再淡出，避免近处密度突然变空。
const FLIGHT_ROCK_VISIBILITY_RANGE: float = 520.0
const DECORATIVE_ROCK_VISIBILITY_RANGE: float = 460.0
const ROCK_VISIBILITY_MARGIN: float = 90.0
const PALETTES: Array = [
	[Color("a3a8c2"),Color("4c6885"),Color("2a2e4a")],
	[Color("8a7a84"),Color("4a3c48"),Color("1e1824")],
	[Color("c4b49a"),Color("6a5a48"),Color("2c241c")],
	[Color("7a8494"),Color("3a4450"),Color("181c24")],
]


var _light_dir: Vector3 = Vector3(0.42, 0.62, 0.48)
var _batch_meshes: Array[SphereMesh] = []


func setup(belts: Array[BeltData], light_dir: Vector3) -> void:
	_light_dir = light_dir.normalized()
	_prepare_batch_meshes()
	for belt: BeltData in belts:
		_spawn_belt(belt)


func _spawn_belt(belt: BeltData) -> void:
	if belt.is_boundary:
		# 连续椭圆墙负责真正挡住飞船；碎石只是外形，避免从缝里钻出去。
		_spawn_boundary_wall(belt)

	var batches: Array = [[],[],[],[]]
	var collision_body := _make_collision_body(belt)
	for sample: Dictionary in Layout.samples(belt):
		var visual_rng: RandomNumberGenerator = Layout.visual_rng(belt,int(sample["index"]))
		var entry := _visual_entry(sample,visual_rng)
		(batches[int(entry["palette"])] as Array).append(entry)
		if bool(sample["hits_flight"]):
			_append_collision(collision_body,belt,sample)
	for palette_index: int in range(PALETTES.size()):
		_spawn_visual_batch(belt,palette_index,batches[palette_index] as Array)


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


func _prepare_batch_meshes() -> void:
	_batch_meshes.clear()
	var rock_shader := load("res://shaders/pixel_asteroid_3d.gdshader") as Shader
	for palette_value: Variant in PALETTES:
		var palette := palette_value as Array
		var mat := ShaderMaterial.new()
		mat.shader = rock_shader
		mat.set_shader_parameter("col_lit",palette[0])
		mat.set_shader_parameter("col_mid",palette[1])
		mat.set_shader_parameter("col_shade",palette[2])
		mat.set_shader_parameter("light_dir",_light_dir)
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 7
		mesh.rings = 5
		mesh.material = mat
		_batch_meshes.append(mesh)


func _make_collision_body(belt: BeltData) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "%sColliders" % belt.id
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0
	body.add_to_group("asteroid")
	if belt.is_boundary:
		body.add_to_group("world_boundary")
	body.set_meta("belt_id",belt.id)
	var bounce_mat := PhysicsMaterial.new()
	bounce_mat.friction = 0.16
	bounce_mat.bounce = 0.28
	body.physics_material_override = bounce_mat
	add_child(body)
	return body


func _append_collision(body: StaticBody3D,belt: BeltData,sample: Dictionary) -> void:
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = float(sample["hit_radius"])
	col.shape = sphere
	col.position = Vector3(sample["position"])
	col.set_meta("belt_id",belt.id)
	col.set_meta("sample_index",int(sample["index"]))
	col.set_meta("hit_radius",float(sample["hit_radius"]))
	col.set_meta("asteroid_damage",float(sample["damage"]))
	body.add_child(col)


func _visual_entry(sample: Dictionary,rng: RandomNumberGenerator) -> Dictionary:
	var radius := float(sample["radius"])
	var scale := Vector3(
		radius*rng.randf_range(0.76,1.26),
		radius*rng.randf_range(0.68,1.18),
		radius*rng.randf_range(0.78,1.30)
	)
	var palette := rng.randi_range(0,PALETTES.size()-1)
	var seed_value := rng.randf_range(1.1,8.8)
	var pixels := clampf(radius*22.0+rng.randf_range(8.0,14.0),12.0,28.0)
	var lump := rng.randf_range(0.13,0.27)
	var rotation := Vector3(rng.randf_range(0.0,TAU),rng.randf_range(0.0,TAU),rng.randf_range(0.0,TAU))
	var spin := rng.randf_range(0.14,0.85) * (-1.0 if rng.randf()<0.5 else 1.0)
	return {
		"palette":palette,
		"transform":Transform3D(Basis.from_euler(rotation).scaled(scale),Vector3(sample["position"])),
		"custom":Color(inverse_lerp(1.1,8.8,seed_value),inverse_lerp(12.0,28.0,pixels),
			inverse_lerp(0.13,0.27,lump),inverse_lerp(-0.85,0.85,spin)),
		"extent":maxf(scale.x,maxf(scale.y,scale.z))*1.35,
		"sample_index":int(sample["index"]),
		"hits_flight":bool(sample["hits_flight"]),
	}


func _spawn_visual_batch(belt: BeltData,palette_index: int,entries: Array) -> void:
	if entries.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_custom_data = true
	multi.mesh = _batch_meshes[palette_index]
	multi.instance_count = entries.size()
	var indices := PackedInt32Array()
	var positions := PackedVector3Array()
	var active_count := 0
	var bounds := AABB()
	var has_bounds := false
	for i: int in range(entries.size()):
		var entry: Dictionary = entries[i]
		var transform: Transform3D = entry["transform"]
		var custom: Color = entry["custom"]
		multi.set_instance_transform(i,transform)
		multi.set_instance_custom_data(i,custom)
		indices.append(int(entry["sample_index"]))
		positions.append(transform.origin)
		if bool(entry["hits_flight"]): active_count += 1
		var extent := Vector3.ONE*float(entry["extent"])
		var rock_bounds := AABB(transform.origin-extent,extent*2.0)
		bounds = rock_bounds if not has_bounds else bounds.merge(rock_bounds)
		has_bounds = true
	if has_bounds:
		multi.custom_aabb = bounds
	var batch := MultiMeshInstance3D.new()
	batch.name = "%sPalette%d" % [belt.id,palette_index]
	batch.multimesh = multi
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.visibility_range_end = FLIGHT_ROCK_VISIBILITY_RANGE
	batch.visibility_range_end_margin = ROCK_VISIBILITY_MARGIN
	batch.set_meta("belt_id",belt.id)
	batch.set_meta("sample_indices",indices)
	batch.set_meta("sample_positions",positions)
	batch.set_meta("rock_count",entries.size())
	batch.set_meta("active_count",active_count)
	batch.set_meta("decorative_count",entries.size()-active_count)
	add_child(batch)
