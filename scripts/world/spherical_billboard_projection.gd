class_name SphericalBillboardProjection
extends RefCounted
## 球体广告牌的透视校正。
##
## 半径为 r 的真实球体，在球心距离观察点 d（d > r）时，轮廓角半径为：
##     alpha = asin(r / d)
## 平面广告牌半径为 R 时，角半径为：
##     beta = atan(R / d)
## 令 alpha == beta，可得唯一的连续解：
##     R = r * d / sqrt(d² - r²)
## 因此远处 R -> r；接近球面时轮廓自然快速扩张至覆盖整个视野。


static func visual_radius(physical_radius: float, center_distance: float) -> float:
	assert(physical_radius > 0.0)
	assert(center_distance > physical_radius)
	return physical_radius * center_distance / sqrt(
		center_distance * center_distance - physical_radius * physical_radius
	)


static func scale_factor(physical_radius: float, center_distance: float) -> float:
	return visual_radius(physical_radius, center_distance) / physical_radius


static func sphere_angular_diameter(physical_radius: float, center_distance: float) -> float:
	assert(physical_radius > 0.0)
	assert(center_distance > physical_radius)
	return 2.0 * asin(physical_radius / center_distance)


static func billboard_angular_diameter(visual_billboard_radius: float, center_distance: float) -> float:
	assert(visual_billboard_radius > 0.0)
	assert(center_distance > 0.0)
	return 2.0 * atan(visual_billboard_radius / center_distance)
