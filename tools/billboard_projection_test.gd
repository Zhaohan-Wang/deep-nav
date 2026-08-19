extends SceneTree
## 验证 3D 行星广告牌在所有距离上与真实球体具有相同的视角轮廓。

const SphericalProjection = preload("res://scripts/world/spherical_billboard_projection.gd")


func _initialize() -> void:
	var radii: Array[float] = [8.0, 12.0, 18.0, 24.0, 29.0]
	var distance_ratios: Array[float] = [1.02, 1.05, 1.1, 1.25, 1.5, 2.0, 4.0, 8.0, 20.0]
	var checks := 0
	for radius: float in radii:
		for ratio: float in distance_ratios:
			var distance := radius * ratio
			var visual_radius := SphericalProjection.visual_radius(radius, distance)
			var sphere_angle := SphericalProjection.sphere_angular_diameter(radius, distance)
			var billboard_angle := SphericalProjection.billboard_angular_diameter(
				visual_radius, distance
			)
			if absf(sphere_angle - billboard_angle) > 0.00001:
				push_error(
					"BILLBOARD_PROJECTION_FAILED r=%.2f d=%.2f sphere=%.8f billboard=%.8f"
					% [radius, distance, sphere_angle, billboard_angle]
				)
				quit(1)
				return
			checks += 1

	# 两条物理边界：远处应收敛回实际半径；飞船贴近碰撞面时，
	# 任何大型星体都应超出驾驶员 50° 的纵向视野，而不是像小道具。
	var far_scale := SphericalProjection.scale_factor(24.0, 24.0 * 1000.0)
	if absf(far_scale - 1.0) > 0.000001:
		push_error("BILLBOARD_PROJECTION_FAILED far-field scale=%f" % far_scale)
		quit(1)
		return
	var pilot_fov := deg_to_rad(50.0)
	for radius: float in [18.0, 24.0, 29.0]:
		var contact_distance: float = radius + Game.SHIP_RADIUS
		var contact_angle := SphericalProjection.sphere_angular_diameter(
			radius, contact_distance
		)
		if contact_angle <= pilot_fov * 2.5:
			push_error(
				"BILLBOARD_PROJECTION_FAILED contact silhouette lacks pressure r=%.1f angle=%.1fdeg"
				% [radius, rad_to_deg(contact_angle)]
			)
			quit(1)
			return
		checks += 1

	print("BILLBOARD_PROJECTION_OK checks=%d" % checks)
	quit(0)
