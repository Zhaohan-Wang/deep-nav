extends Node3D
## 装饰星放在航道够不到的远处。大小接近、亮度均匀，避免亚像素闪烁。

const NEAR_BG: float = 2200.0
const FAR_BG: float = 3300.0
const STAR_TINT := Color(0.80, 0.84, 0.94)


func _ready() -> void:
	_spawn_shell(36, NEAR_BG, 2600.0, 11.0, 13.0)
	_spawn_shell(48, 2600.0, FAR_BG, 10.0, 12.0)
	_spawn_shell(56, 2800.0, FAR_BG, 9.0, 11.0)


func _spawn_shell(count: int, radius_min: float, radius_max: float, scale_min: float, scale_max: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = STAR_TINT
	mat.disable_receive_shadows = true
	mesh.material = mat

	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = count

	var rng := RandomNumberGenerator.new()
	rng.seed = int(radius_min * 17.0 + radius_max * 9.0)

	for i: int in range(count):
		var pos: Vector3 = _pick_position(rng, radius_min, radius_max)
		var star_scale: float = rng.randf_range(scale_min, scale_max)
		var xform := Transform3D.IDENTITY
		xform.origin = pos
		xform.basis = xform.basis.scaled(Vector3(star_scale, star_scale, star_scale))
		multi.set_instance_transform(i, xform)

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	instance.extra_cull_margin = 400.0
	add_child(instance)


func _pick_position(rng: RandomNumberGenerator, radius_min: float, radius_max: float) -> Vector3:
	var dir: Vector3 = Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)
	)
	if dir.length_squared() < 0.001:
		dir = Vector3.UP
	dir = dir.normalized()
	var radius: float = rng.randf_range(radius_min, radius_max)
	return dir * radius
