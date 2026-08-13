class_name BeltData
extends Resource
## 一小段可复用的小行星带：环带或廊道，3D 生成与 2D 标注共用同一份数据。

enum Shape {
	RING, ## 绕某个中心的圆环 / 椭圆环。
	BAND, ## 两点之间的碎石廊道。
}

@export var id: String = ""
@export var display_name: String = ""
@export var shape: Shape = Shape.RING
@export var center: Vector3 = Vector3.ZERO
@export var inner_radius: float = 16.0
@export var outer_radius: float = 28.0
## X 半径 = Z 半径 * aspect。1 是正圆，16/9 贴合横版星图。
@export var aspect: float = 1.0
@export var from_point: Vector3 = Vector3.ZERO
@export var to_point: Vector3 = Vector3.ZERO
@export var half_width: float = 8.0
@export var rock_count: int = 22
@export var debris_count: int = 28
@export var seed_value: int = 1
## 扇区外圈，用来挡住飞出地图。
@export var is_boundary: bool = false


func radius_x(radius_z: float) -> float:
	return radius_z * maxf(aspect, 0.01)


## 在带内随机取一个水平坐标（高度由生成器按层铺开）。
func sample_xz(rng: RandomNumberGenerator) -> Vector3:
	if shape == Shape.RING or is_boundary:
		var angle: float = rng.randf() * TAU
		var radius_z: float = lerpf(inner_radius, outer_radius, rng.randf())
		return point_on_ring(angle, radius_z)
	var t: float = rng.randf()
	var along: Vector3 = from_point.lerp(to_point, t)
	var delta: Vector3 = to_point - from_point
	delta.y = 0.0
	var side: Vector3 = Vector3(-delta.z, 0.0, delta.x)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	return along + side * rng.randf_range(-half_width, half_width)


func point_on_ring(angle: float, radius_z: float) -> Vector3:
	return center + Vector3(cos(angle) * radius_x(radius_z), 0.0, sin(angle) * radius_z)


## 点在椭圆外时 > 1。用 inner / outer 当 Z 半径。
func ellipse_factor(world_pos: Vector3, radius_z: float) -> float:
	var rx: float = maxf(radius_x(radius_z), 0.01)
	var rz: float = maxf(radius_z, 0.01)
	var dx: float = world_pos.x - center.x
	var dz: float = world_pos.z - center.z
	return sqrt((dx * dx) / (rx * rx) + (dz * dz) / (rz * rz))
