class_name PlanetFactory
extends RefCounted
## 把 PixelPlanets 的 Control 场景实例化成可用的 2D 行星控件。


## 控件实际占用的边长（含光环边距）。
static func host_size(scene_path: String, pixels: int) -> int:
	return pixels * margin_for_path(scene_path)


## 带光环 / 日冕的天体需要更大的视口边距。
static func margin_for_path(scene_path: String) -> int:
	if scene_path.contains("GasPlanetLayers") or scene_path.contains("BlackHole"):
		return 3
	if scene_path.contains("Star"):
		return 2
	return 1


## 去掉原资源里为编辑器 GUI 准备的锚点，避免在小视口里被拉变形。
static func reset_layout(ctrl: Control, pixels: int, margin: int) -> void:
	ctrl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = 0.0
	ctrl.offset_top = 0.0
	ctrl.offset_right = 0.0
	ctrl.offset_bottom = 0.0
	ctrl.clip_contents = false
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# PixelPlanets 场景自带 100px 最小尺寸，3D 视口更小时会被裁成直角缺角。
	ctrl.custom_minimum_size = Vector2(float(pixels), float(pixels))
	var extra: float = float(pixels * (margin - 1)) * 0.5
	ctrl.position = Vector2(extra, extra)
	ctrl.size = Vector2(float(pixels), float(pixels))
	_clear_child_min_size(ctrl)
	_ignore_mouse_recursive(ctrl)


static func _clear_child_min_size(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			(child as Control).custom_minimum_size = Vector2.ZERO
		_clear_child_min_size(child)


static func _ignore_mouse_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child: Node in node.get_children():
		_ignore_mouse_recursive(child)


## 实例化行星，并立刻设置像素分辨率与随机种子。
static func instantiate_planet(scene_path: String, pixels: int, seed_value: int, enable_dither: bool = true) -> Control:
	var packed: PackedScene = load(scene_path) as PackedScene
	var planet: Control = packed.instantiate() as Control
	var margin: int = margin_for_path(scene_path)
	reset_layout(planet, pixels, margin)
	if planet.has_method("set_pixels"):
		planet.call("set_pixels", pixels)
	if planet.has_method("set_seed"):
		planet.call("set_seed", seed_value)
	if planet.has_method("set_dither"):
		planet.call("set_dither", enable_dither)
	return planet


## 2D / 3D 共用的恒星光照方向，保证星图和视口明暗一致。
static func light_uv_from_star(body_pos: Vector3, star_pos: Vector3) -> Vector2:
	var to_star: Vector3 = star_pos - body_pos
	to_star.y = 0.0
	if to_star.length_squared() < 0.001:
		return Vector2(0.5, 0.35)
	var dir: Vector3 = to_star.normalized()
	return Vector2(0.5 - dir.x * 0.32, 0.5 - dir.z * 0.32)
