extends Control
## 星图危险区、航线、飞船雷达光环与终点信标。

const PING_PERIOD: float = 1.65
const PING_COUNT: int = 3
const PING_MIN: float = 8.0
const PING_MAX: float = 46.0

## 终点信标：绿色雷达波纹，节奏比船雷达慢，两者不会混淆。
const DEST_PING_PERIOD: float = 2.2
const DEST_PING_MIN: float = 6.0
const DEST_PING_MAX: float = 34.0
const DEST_GREEN: Color = Color("5fe08a")

## 尘带描边 / 碎石点配色：低饱和暖灰，不再用大片橙色。
const BELT_FILL: Color = Color(0.60, 0.48, 0.38, 0.10)
const BELT_FILL_BOUNDARY: Color = Color(0.46, 0.28, 0.26, 0.14)
const BELT_EDGE: Color = Color(0.85, 0.62, 0.45, 0.42)
const BELT_EDGE_BOUNDARY: Color = Color(0.80, 0.45, 0.38, 0.48)
## 每条带最多画多少颗碎石点。
const BELT_ROCK_CAP: int = 90

var _ping_time: float = 0.0
var _dest_time: float = 0.0
## 标记旋转 / 脉动的公共时钟。
var _spin: float = 0.0


func _ready() -> void:
	# 雷达环要自己转，不能只等飞船状态刷新。
	set_process(true)


func _process(delta: float) -> void:
	_ping_time = fmod(_ping_time + delta, PING_PERIOD)
	_dest_time = fmod(_dest_time + delta, DEST_PING_PERIOD)
	_spin = fmod(_spin + delta, TAU * 60.0)
	queue_redraw()


func _draw() -> void:
	var map := get_parent() as SectorMap
	if map == null:
		return
	_draw_belts(map)
	_draw_boundary_outside(map)
	_draw_dest_beacon(map)
	_draw_waypoint_marker(map)
	_draw_ship_radar(map)


func _draw_ship_radar(map: SectorMap) -> void:
	if not Game.ship_alive:
		return
	var center: Vector2 = map.world_to_map(Game.ship_position)
	var cyan: Color = UiStyle.CYAN
	# 与船标同一套 2D 朝向：heading 0 朝地图上方，正转（左转）指向左。
	var heading: float = Game.ship_heading
	var fwd := Vector2(-sin(heading), -cos(heading))
	# 航向矢量线：从船头引出的细线，长度随航速伸缩，端点一个小点。
	# 航空显示的画法，比实心楔形干净得多。
	var vec_len: float = 15.0 + Game.ship_speed * 1.5
	var from: Vector2 = center + fwd * 9.0
	var mid: Vector2 = center + fwd * (9.0 + (vec_len - 9.0) * 0.62)
	var to: Vector2 = center + fwd * vec_len
	draw_line(from, mid, Color(cyan, 0.9), 1.2, true)
	draw_line(mid, to, Color(cyan, 0.45), 1.2, true)
	draw_circle(to, 1.7, Color(cyan, 0.95))
	for i: int in range(PING_COUNT):
		var phase: float = fmod(_ping_time / PING_PERIOD + float(i) / float(PING_COUNT), 1.0)
		var radius: float = lerpf(PING_MIN, PING_MAX, phase)
		var alpha: float = (1.0 - phase) * (1.0 - phase) * 0.7
		draw_arc(center, radius, 0.0, TAU, 40, Color(cyan, alpha), 1.6, true)


## 航点：慢速旋转的菱形准星 + 固定方位短刻度 + 中心点，无方向暗示。
func _draw_waypoint_marker(map: SectorMap) -> void:
	if not Game.has_waypoint:
		return
	var p: Vector2 = map.world_to_map(Game.waypoint)
	# 航线：船到航点的虚线，压在标记下面。
	var from: Vector2 = map.world_to_map(Game.ship_position)
	draw_dashed_line(from, p, Color(UiStyle.AMBER, 0.55), 1.5, 8.0)
	var amber: Color = UiStyle.AMBER
	var pulse: float = 0.5 + 0.5 * sin(_spin * 3.2)
	var r: float = 7.0 + pulse * 1.4
	# 旋转菱形轮廓。
	var outline := PackedVector2Array()
	for k: int in range(5):
		var a: float = _spin * 0.9 + TAU * float(k) / 4.0
		outline.append(p + Vector2(cos(a), sin(a)) * r)
	draw_polyline(outline, Color(amber, 0.95), 1.4, true)
	# 固定的四方位短刻度，旋转的菱形在里面转，层次感就出来了。
	for k: int in range(4):
		var a: float = TAU * float(k) / 4.0
		var dir := Vector2(cos(a), sin(a))
		draw_line(p + dir * (r + 3.0), p + dir * (r + 6.5), Color(amber, 0.6 + 0.3 * pulse), 1.2, true)
	draw_circle(p, 1.6, amber)


## 终点信标：环绕行星旋转的锁定弧 + 绿色雷达波纹 + 停靠圈，无方向暗示。
func _draw_dest_beacon(map: SectorMap) -> void:
	var dest: CelestialBodyData = Game.objective_body()
	if dest == null or Game.current_sector == null:
		return
	var center: Vector2 = map.world_to_map(dest.world_position)
	var scale_px: float = Game.map_pixels_per_unit(size)
	# 停靠圈：贴边进入即完成的范围。
	var dock_radius: float = (dest.collision_radius + Game.current_sector.dock_range) * scale_px
	draw_arc(center, dock_radius, 0.0, TAU, 64, Color(DEST_GREEN, 0.55), 1.6, true)
	# 波纹从行星边缘向外扩散。
	var edge: float = dest.world_radius * scale_px
	for i: int in range(PING_COUNT):
		var phase: float = fmod(_dest_time / DEST_PING_PERIOD + float(i) / float(PING_COUNT), 1.0)
		var radius: float = edge + lerpf(DEST_PING_MIN, DEST_PING_MAX, phase)
		var alpha: float = (1.0 - phase) * (1.0 - phase) * 0.8
		draw_arc(center, radius, 0.0, TAU, 48, Color(DEST_GREEN, alpha), 1.6, true)
	# 环绕行星缓慢旋转的四段锁定弧：目标被“标记”而不是被指向。
	var lock_r: float = edge + 5.0
	for k: int in range(4):
		var a0: float = _spin * 0.55 + TAU * float(k) / 4.0
		draw_arc(center, lock_r, a0, a0 + TAU * 0.15, 12, Color(DEST_GREEN, 0.9), 1.6, true)


func _draw_belts(map: SectorMap) -> void:
	if Game.current_sector == null:
		return
	for belt: BeltData in Game.current_sector.belts:
		if belt.shape == BeltData.Shape.RING or belt.is_boundary:
			_draw_ring_belt(map, belt)
		else:
			_draw_band_belt(map, belt)
		_scatter_rocks(map, belt)


func _draw_ring_belt(map: SectorMap, belt: BeltData) -> void:
	var center: Vector2 = map.world_to_map(belt.center)
	var scale_px: float = Game.map_pixels_per_unit(size)
	var inner_z: float = belt.inner_radius * scale_px
	var outer_z: float = belt.outer_radius * scale_px
	var inner_x: float = inner_z * belt.aspect
	var outer_x: float = outer_z * belt.aspect
	var segs: int = 72 if belt.is_boundary else 56
	var fill: PackedVector2Array = PackedVector2Array()
	for i: int in range(segs + 1):
		var a: float = TAU * float(i) / float(segs)
		fill.append(center + Vector2(cos(a) * outer_x, sin(a) * outer_z))
	for i: int in range(segs + 1):
		var a: float = TAU * float(segs - i) / float(segs)
		fill.append(center + Vector2(cos(a) * inner_x, sin(a) * inner_z))
	if fill.size() >= 3:
		draw_colored_polygon(fill, BELT_FILL_BOUNDARY if belt.is_boundary else BELT_FILL)
	var edge: Color = BELT_EDGE_BOUNDARY if belt.is_boundary else BELT_EDGE
	_draw_dashed_ellipse(center, outer_x, outer_z, edge, 1.2)
	_draw_dashed_ellipse(center, inner_x, inner_z, Color(edge, edge.a * 0.8), 1.0)


func _draw_band_belt(map: SectorMap, belt: BeltData) -> void:
	var from: Vector2 = map.world_to_map(belt.from_point)
	var to: Vector2 = map.world_to_map(belt.to_point)
	var scale_px: float = Game.map_pixels_per_unit(size)
	var half: float = belt.half_width * scale_px
	var delta: Vector2 = to - from
	if delta.length_squared() < 0.001:
		return
	var along: Vector2 = delta.normalized()
	var side := Vector2(-along.y, along.x)
	var quad: PackedVector2Array = PackedVector2Array([
		from + side * half,
		to + side * half,
		to - side * half,
		from - side * half,
	])
	draw_colored_polygon(quad, BELT_FILL)
	draw_dashed_line(from + side * half, to + side * half, BELT_EDGE, 1.2, 8.0)
	draw_dashed_line(from - side * half, to - side * half, BELT_EDGE, 1.2, 8.0)


## 用尘带自己的种子在带内撒碎石点，和 3D 生成同一套分布逻辑，
## 大小明暗随机，看上去就是一片真实的石头而不是斜线网格。
func _scatter_rocks(map: SectorMap, belt: BeltData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = belt.seed_value
	var count: int = mini(belt.rock_count + belt.debris_count, BELT_ROCK_CAP)
	for i: int in range(count):
		var p: Vector2 = map.world_to_map(belt.sample_xz(rng))
		var t: float = rng.randf()
		var radius: float = lerpf(0.7, 2.1, t * t)
		var shade: float = rng.randf_range(0.55, 1.0)
		var col := Color(0.70 * shade, 0.62 * shade, 0.54 * shade, 0.85)
		draw_circle(p, radius, col)


func _draw_boundary_outside(map: SectorMap) -> void:
	if Game.current_sector == null:
		return
	var wall: BeltData = null
	for belt: BeltData in Game.current_sector.belts:
		if belt.is_boundary:
			wall = belt
			break
	if wall == null:
		return
	var center: Vector2 = map.world_to_map(wall.center)
	var scale_px: float = Game.map_pixels_per_unit(size)
	var outer_z: float = wall.outer_radius * scale_px
	var outer_x: float = outer_z * wall.aspect
	var far_r: float = 0.0
	var corners: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(size.x, 0.0),
		Vector2(0.0, size.y),
		size,
	]
	for corner: Vector2 in corners:
		far_r = maxf(far_r, center.distance_to(corner))
	if far_r <= maxf(outer_x, outer_z) + 1.0:
		return
	var fill: PackedVector2Array = PackedVector2Array()
	var segs: int = 72
	for i: int in range(segs + 1):
		var a: float = TAU * float(i) / float(segs)
		fill.append(center + Vector2(cos(a), sin(a)) * far_r)
	for i: int in range(segs + 1):
		var a: float = TAU * float(segs - i) / float(segs)
		fill.append(center + Vector2(cos(a) * outer_x, sin(a) * outer_z))
	if fill.size() >= 3:
		draw_colored_polygon(fill, Color(0.03, 0.025, 0.04, 0.55))


func _draw_dashed_ellipse(center: Vector2, radius_x: float, radius_z: float, color: Color, width: float) -> void:
	var dashes: int = 40
	for i: int in range(dashes):
		if i % 2 == 1:
			continue
		var a0: float = TAU * float(i) / float(dashes)
		var a1: float = TAU * float(i + 1) / float(dashes)
		var p0: Vector2 = center + Vector2(cos(a0) * radius_x, sin(a0) * radius_z)
		var p1: Vector2 = center + Vector2(cos(a1) * radius_x, sin(a1) * radius_z)
		draw_line(p0, p1, color, width, true)
