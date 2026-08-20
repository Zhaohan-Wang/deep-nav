class_name BeltHazard
extends RefCounted
## 小行星带的连续危险几何。随机岩块负责可见碰撞，这一层负责保证不存在“从缝里直穿”。

## 船体进入带宽的外层 58% 以内属于稀疏擦伤区；更深处是不可穿越的致密核心。
const CORE_FRACTION: float = 0.58
const SWEEP_STEP: float = 0.65

enum Exposure {
	CLEAR,
	GRAZE,
	CORE,
}


static func classify(fraction: float) -> Exposure:
	if fraction<=0.0:
		return Exposure.CLEAR
	if fraction<CORE_FRACTION:
		return Exposure.GRAZE
	return Exposure.CORE


static func penetration_fraction(point: Vector3,belt: BeltData,hull_radius: float) -> float:
	if belt == null or belt.is_boundary:
		return 0.0
	if belt.shape == BeltData.Shape.SPLINE and not _inside_spline_broadphase(point,belt,hull_radius):
		return 0.0
	var profile := _cross_section(point,belt)
	var half_width: float = float(profile["half_width"])
	var distance: float = float(profile["distance"])
	var expanded_half_width := half_width + maxf(hull_radius,0.0)
	if expanded_half_width <= 0.001:
		return 0.0
	return clampf((expanded_half_width-distance)/expanded_half_width,0.0,1.0)


static func max_fraction_along_segment(from: Vector3,to: Vector3,belt: BeltData,hull_radius: float) -> float:
	var planar_from := Vector3(from.x,0.0,from.z)
	var planar_to := Vector3(to.x,0.0,to.z)
	var sample_count := maxi(1,int(ceil(planar_from.distance_to(planar_to)/SWEEP_STEP)))
	var result := 0.0
	for i: int in range(sample_count+1):
		var point := planar_from.lerp(planar_to,float(i)/float(sample_count))
		result=maxf(result,penetration_fraction(point,belt,hull_radius))
		if result>=0.999:
			return result
	return result


static func max_sector_fraction(from: Vector3,to: Vector3,belts: Array[BeltData],hull_radius: float) -> Dictionary:
	var result := {"fraction":0.0,"belt":null}
	for belt: BeltData in belts:
		if belt.is_boundary:
			continue
		var fraction := max_fraction_along_segment(from,to,belt,hull_radius)
		if fraction>float(result["fraction"]):
			result={"fraction":fraction,"belt":belt}
	return result


static func _cross_section(point: Vector3,belt: BeltData) -> Dictionary:
	var planar_point := Vector3(point.x,0.0,point.z)
	if belt.shape==BeltData.Shape.RING:
		var rel := planar_point-belt.center
		var angle := atan2(rel.z,rel.x/maxf(belt.aspect,0.01))
		var inner := belt.point_on_ring(angle,belt.inner_radius)
		var outer := belt.point_on_ring(angle,belt.outer_radius)
		var centerline := (inner+outer)*0.5
		return {
			"distance":planar_point.distance_to(centerline),
			"half_width":inner.distance_to(outer)*0.5,
		}
	if belt.shape==BeltData.Shape.SPLINE:
		var nearest_t := _nearest_spline_t(planar_point,belt)
		return {
			"distance":planar_point.distance_to(belt.spline_point(nearest_t)),
			"half_width":belt.spline_half_width(nearest_t),
		}
	var delta := belt.to_point-belt.from_point
	delta.y=0.0
	var t := clampf((planar_point-belt.from_point).dot(delta)/maxf(delta.length_squared(),0.001),0.0,1.0)
	return {
		"distance":planar_point.distance_to(belt.from_point+delta*t),
		"half_width":belt.half_width,
	}


static func _inside_spline_broadphase(point: Vector3,belt: BeltData,hull_radius: float) -> bool:
	# 大多数物理帧飞船离样条带很远；先用保守 AABB 排除，避免每条带都做 91 次样条求值。
	if belt.control_points.size() < 2:
		return true
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var max_spacing := 0.0
	for i: int in range(belt.control_points.size()):
		var control := belt.control_points[i]
		min_x = minf(min_x,control.x)
		max_x = maxf(max_x,control.x)
		min_z = minf(min_z,control.z)
		max_z = maxf(max_z,control.z)
		if i > 0:
			max_spacing = maxf(max_spacing,control.distance_to(belt.control_points[i-1]))
	var max_width := belt.half_width
	for width: float in belt.width_profile:
		max_width = maxf(max_width,width)
	# Catmull-Rom 曲线可能越出控制点包围盒；额外加入 30% 最大点距，保持判定保守。
	var margin := max_width + belt.spline_wobble + maxf(hull_radius,0.0) + max_spacing * 0.30 + 1.0
	return (
		point.x >= min_x-margin and point.x <= max_x+margin
		and point.z >= min_z-margin and point.z <= max_z+margin
	)


static func _nearest_spline_t(point: Vector3,belt: BeltData) -> float:
	var best_t := 0.0
	var best_distance := INF
	const COARSE_SEGMENTS := 64
	for i: int in range(COARSE_SEGMENTS+1):
		var t := float(i)/float(COARSE_SEGMENTS)
		var distance := point.distance_squared_to(belt.spline_point(t))
		if distance<best_distance:
			best_distance=distance
			best_t=t
	var radius := 1.0/float(COARSE_SEGMENTS)
	for pass_index: int in range(3):
		var start := maxf(0.0,best_t-radius)
		var end := minf(1.0,best_t+radius)
		for i: int in range(9):
			var t := lerpf(start,end,float(i)/8.0)
			var distance := point.distance_squared_to(belt.spline_point(t))
			if distance<best_distance:
				best_distance=distance
				best_t=t
		radius*=0.25
	return best_t
