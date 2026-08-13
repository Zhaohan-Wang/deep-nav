class_name WaypointBeacon
extends Node3D
## 3D 航点光柱，方便领航员从大范围视窗里确认标记位置。

var _mesh: MeshInstance3D


func _ready() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.18
	cylinder.bottom_radius = 0.45
	cylinder.height = 18.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.91, 0.63, 0.29, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_keep_scale = false
	cylinder.material = mat
	_mesh = MeshInstance3D.new()
	_mesh.mesh = cylinder
	_mesh.position = Vector3(0.0, 9.0, 0.0)
	add_child(_mesh)
	visible = false
	Game.waypoint_changed.connect(_on_waypoint)


func _on_waypoint(world_pos: Vector3, enabled: bool) -> void:
	visible = enabled
	if enabled:
		global_position = Vector3(world_pos.x, 0.0, world_pos.z)
