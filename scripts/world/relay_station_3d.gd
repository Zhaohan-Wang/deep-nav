class_name RelayStation3D
extends Node3D
## 参与者可见的中继站：平台 + 光柱，和航点光柱区分开（青色双环，不是琥珀色）。

const BEAM_HEIGHT: float = 22.0

var station_index: int = 0
var _beam: MeshInstance3D
var _pulse: float = 0.0


func setup(index: int, world_pos: Vector3) -> void:
	station_index = index
	name = "RelayStation_%d" % index
	position = Vector3(world_pos.x, 0.0, world_pos.z)
	_add_ring(3.4, 0.16, Color(0.42, 0.88, 0.78, 0.92), 0.05)
	_add_ring(5.2, 0.10, Color(0.42, 0.88, 0.78, 0.55), 0.05)
	_add_pad()
	_add_beam()


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, TAU)
	if _beam != null:
		var reached := Game.is_relay_reached(station_index)
		var glow := 0.55 + 0.25 * (0.5 + 0.5 * sin(_pulse * 2.4))
		if reached:
			glow = 0.82 + 0.12 * (0.5 + 0.5 * sin(_pulse * 1.6))
		var mat := _beam.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.55, 0.95, 0.82, glow)


func _add_pad() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 2.4
	mesh.bottom_radius = 2.8
	mesh.height = 0.55
	mesh.radial_segments = 8
	var mat := _unshaded(Color(0.18, 0.28, 0.30, 0.95))
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = mat
	body.position = Vector3(0.0, 0.28, 0.0)
	add_child(body)


func _add_ring(radius: float, thickness: float, color: Color, height: float) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(radius - thickness, 0.2)
	mesh.outer_radius = radius
	mesh.rings = 16
	mesh.ring_segments = 10
	var ring := MeshInstance3D.new()
	ring.mesh = mesh
	ring.material_override = _unshaded(color)
	ring.position = Vector3(0.0, height, 0.0)
	add_child(ring)


func _add_beam() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.12
	mesh.bottom_radius = 0.38
	mesh.height = BEAM_HEIGHT
	_beam = MeshInstance3D.new()
	_beam.mesh = mesh
	_beam.material_override = _unshaded(Color(0.55, 0.95, 0.82, 0.7))
	_beam.position = Vector3(0.0, BEAM_HEIGHT * 0.5, 0.0)
	add_child(_beam)


func _unshaded(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat
