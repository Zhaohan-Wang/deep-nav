class_name BeltData
extends Resource
## 一小段可复用的小行星带：环带或廊道，3D 生成与 2D 标注共用同一份数据。

enum Shape {
	RING, ## 绕某个中心的圆环 / 椭圆环。
	BAND, ## 两点之间的碎石廊道。
	SPLINE, ## 多控制点的自然碎石脊，可渐变宽度。
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
@export var control_points: PackedVector3Array = PackedVector3Array()
@export var width_profile: PackedFloat32Array = PackedFloat32Array()
## 样条中心线的多频小幅偏移（世界单位）。
@export var spline_wobble: float = 0.0
## 非边界环带的径向不规则度，0.1 表示约 10% 起伏。
@export var radial_irregularity: float = 0.0
@export var rock_count: int = 22
@export var debris_count: int = 28
## 实际落在飞行平面的岩块比例；正式关可以高于装饰性尘带。
@export var flight_rock_ratio: float = 0.36
@export var rock_scale: float = 1.0
@export var seed_value: int = 1
## 扇区外圈，用来挡住飞出地图。
@export var is_boundary: bool = false
## 2 是椭圆；正式长地图边界使用 6，形成两端圆滑、长段近似等宽的超椭圆航区。
@export var boundary_exponent: float = 2.0


func radius_x(radius_z: float) -> float:
	return radius_z * maxf(aspect, 0.01)


## 在带内随机取一个水平坐标（高度由生成器按层铺开）。
func sample_xz(rng: RandomNumberGenerator) -> Vector3:
	if shape == Shape.RING or is_boundary:
		var angle: float = rng.randf() * TAU
		var radius_z: float = lerpf(inner_radius, outer_radius, rng.randf())
		return point_on_ring(angle, radius_z)
	if shape == Shape.SPLINE and control_points.size() >= 2:
		var t: float = rng.randf()
		var along: Vector3 = spline_point(t)
		var tangent: Vector3 = spline_tangent(t)
		var side := Vector3(-tangent.z, 0.0, tangent.x)
		if side.length_squared() < 0.0001:
			side = Vector3.RIGHT
		else:
			side = side.normalized()
		return along + side * rng.randf_range(-spline_half_width(t), spline_half_width(t))
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
	if not is_boundary and radial_irregularity > 0.0001:
		var phase: float = float(posmod(seed_value, 997)) * 0.0137
		var wave: float = sin(angle * 3.0 + phase) * 0.56 + sin(angle * 5.0 - phase * 1.7) * 0.29 + sin(angle * 8.0 + phase * 0.4) * 0.15
		radius_z *= 1.0 + radial_irregularity * wave
	var exponent: float = maxf(boundary_exponent,2.0) if is_boundary else 2.0
	var c := cos(angle); var s := sin(angle); var power := 2.0/exponent
	var x := signf(c)*pow(absf(c),power)*radius_x(radius_z)
	var z := signf(s)*pow(absf(s),power)*radius_z
	return center+Vector3(x,0.0,z)


func spline_point(t: float) -> Vector3:
	var clamped_t := clampf(t, 0.0, 1.0)
	var base := _spline_base_point(clamped_t)
	if spline_wobble <= 0.0001:
		return base
	var before: Vector3 = _spline_base_point(maxf(0.0, clamped_t - 0.002))
	var after: Vector3 = _spline_base_point(minf(1.0, clamped_t + 0.002))
	var tangent := after - before
	tangent.y = 0.0
	var side := Vector3(-tangent.z, 0.0, tangent.x).normalized()
	var phase: float = float(posmod(seed_value, 991)) * 0.019
	var wave: float = sin(clamped_t * TAU * 2.0 + phase) * 0.62 + sin(clamped_t * TAU * 5.0 - phase * 0.7) * 0.38
	return base + side * wave * spline_wobble


func _spline_base_point(t: float) -> Vector3:
	if control_points.is_empty():
		return Vector3.ZERO
	if control_points.size() == 1:
		return control_points[0]
	var clamped_t := clampf(t, 0.0, 1.0)
	var segments: int = control_points.size() - 1
	var scaled: float = clamped_t * float(segments)
	var i: int = mini(int(floor(scaled)), segments - 1)
	var u: float = scaled - float(i)
	if clamped_t >= 1.0:
		i = segments - 1
		u = 1.0
	var p0: Vector3 = control_points[maxi(0, i - 1)]
	var p1: Vector3 = control_points[i]
	var p2: Vector3 = control_points[i + 1]
	var p3: Vector3 = control_points[mini(control_points.size() - 1, i + 2)]
	var u2: float = u * u
	var u3: float = u2 * u
	return ((2.0 * p1) + (-p0 + p2) * u + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * u2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * u3) * 0.5


func spline_tangent(t: float) -> Vector3:
	var before: Vector3 = spline_point(maxf(0.0, t - 0.003))
	var after: Vector3 = spline_point(minf(1.0, t + 0.003))
	var tangent := after - before
	tangent.y = 0.0
	return tangent.normalized() if tangent.length_squared() > 0.000001 else Vector3.RIGHT


func spline_half_width(t: float) -> float:
	if width_profile.is_empty():
		return half_width
	if width_profile.size() == 1:
		return maxf(0.5, width_profile[0])
	var scaled: float = clampf(t, 0.0, 1.0) * float(width_profile.size() - 1)
	var i: int = mini(int(floor(scaled)), width_profile.size() - 2)
	return maxf(0.5, lerpf(width_profile[i], width_profile[i + 1], scaled - float(i)))


## 点在椭圆外时 > 1。用 inner / outer 当 Z 半径。
func ellipse_factor(world_pos: Vector3, radius_z: float) -> float:
	var rx: float = maxf(radius_x(radius_z), 0.01)
	var rz: float = maxf(radius_z, 0.01)
	var dx: float = world_pos.x - center.x
	var dz: float = world_pos.z - center.z
	var exponent: float = maxf(boundary_exponent,2.0) if is_boundary else 2.0
	return pow(pow(absf(dx)/rx,exponent)+pow(absf(dz)/rz,exponent),1.0/exponent)


func outward_normal(world_pos: Vector3,radius_z: float) -> Vector3:
	var rx := maxf(radius_x(radius_z),0.01); var rz := maxf(radius_z,0.01)
	var dx := world_pos.x-center.x; var dz := world_pos.z-center.z
	var exponent: float = maxf(boundary_exponent,2.0) if is_boundary else 2.0
	var gx := signf(dx)*pow(absf(dx)/rx,exponent-1.0)/rx
	var gz := signf(dz)*pow(absf(dz)/rz,exponent-1.0)/rz
	var normal := Vector3(gx,0.0,gz)
	return normal.normalized() if normal.length_squared()>0.000001 else Vector3.ZERO


## 连续边界墙按真实椭圆周长动态细分；长地图不会仍只用固定的少量碰撞段。
func boundary_segment_count(max_chord: float = 8.0) -> int:
	var perimeter := 0.0
	var previous := point_on_ring(0.0,inner_radius)
	for i: int in range(1,513):
		var current := point_on_ring(TAU*float(i)/512.0,inner_radius)
		perimeter+=previous.distance_to(current); previous=current
	return clampi(int(ceil(perimeter/maxf(max_chord,2.0))),96,320)
