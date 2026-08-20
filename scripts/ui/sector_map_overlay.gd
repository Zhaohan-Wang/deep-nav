extends Control
## 星图危险区、航线、飞船雷达光环与终点信标。

const Layout = preload("res://scripts/belt_layout.gd")

const PING_PERIOD: float = 1.65
const PING_COUNT: int = 3
const PING_MIN: float = 18.0
const PING_MAX: float = 46.0

## 终点信标：绿色雷达波纹，节奏比船雷达慢，两者不会混淆。
const DEST_PING_PERIOD: float = 2.2
const DEST_PING_MIN: float = 6.0
const DEST_PING_MAX: float = 34.0
const DEST_GREEN: Color = Color("5fe08a")

## 尘带描边 / 碎石点配色：低饱和暖灰，不再用大片橙色。
const BELT_FILL: Color = Color(0.60, 0.48, 0.38, 0.16)
const BELT_FILL_BOUNDARY: Color = Color(0.46, 0.28, 0.26, 0.20)
const BELT_EDGE: Color = Color(0.91, 0.68, 0.48, 0.68)
const BELT_EDGE_BOUNDARY: Color = Color(0.90, 0.48, 0.40, 0.72)
## 每条带最多画多少颗碎石点。
const BELT_ROCK_CAP: int = 90

var _ping_time: float = 0.0
var _dest_time: float = 0.0
## 标记旋转 / 脉动的公共时钟。
var _spin: float = 0.0
## 碎石带几何按关卡烘焙一次；每帧只做世界到屏幕的平移缩放。
var _belt_cache_sector: String = ""
var _belt_cache: Array[Dictionary] = []
## 静态碎石层可在离屏视口中一次烘焙；正常动态覆盖层不再重复提交它。
var static_belt_bake: bool = false
var bake_world_rect: Rect2 = Rect2()
var bake_scale_px: float = 1.0


func _ready() -> void:
	# 雷达环要自己转，不能只等飞船状态刷新。
	set_process(not static_belt_bake)
	if static_belt_bake:
		queue_redraw()


func _process(delta: float) -> void:
	_ping_time = fmod(_ping_time + delta, PING_PERIOD)
	_dest_time = fmod(_dest_time + delta, DEST_PING_PERIOD)
	_spin = fmod(_spin + delta, TAU * 60.0)
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	if static_belt_bake:
		_draw_belts(null)
		return
	var map := get_parent() as SectorMap
	if map == null:
		return
	_draw_body_measurements(map)
	_draw_dest_beacon(map)
	_draw_relay_stations(map)
	_draw_waypoint_marker(map)
	_draw_ship_radar(map)
	# 航程轨已移到底部公共 HUD，星图只保留领航信息。


## 每颗天体都画真实碰撞半径圈。像素光环可以越界，但物理大小必须一眼可验证。
func _draw_body_measurements(map: SectorMap) -> void:
	var scale_px: float = map.pixels_per_unit()
	var viewport := Rect2(Vector2.ZERO, size)
	for body: CelestialBodyData in Game.celestial_bodies:
		var center: Vector2 = map.world_to_map(body.world_position)
		var radius: float = body.collision_radius * scale_px
		if not viewport.grow(radius + 8.0).has_point(center):
			continue
		var color := Color(0.60, 0.82, 0.86, 0.48)
		if body.kind == CelestialBodyData.Kind.STAR:
			color = Color(1.0, 0.73, 0.36, 0.56)
		elif body.kind == CelestialBodyData.Kind.DESTINATION:
			color = Color(DEST_GREEN, 0.82)
		# 四段短弧比完整白圈更像传感器标定，也不会遮住行星像素。
		for k: int in range(4):
			var a0: float = TAU * float(k) / 4.0 + 0.12
			draw_arc(center, radius, a0, a0 + 0.52, 12, color, 1.6, true)
		for k: int in range(4):
			var a: float = TAU * float(k) / 4.0
			var direction := Vector2(cos(a), sin(a))
			draw_line(center + direction * maxf(radius - 3.0, 1.0), center + direction * (radius + 5.0), color, 1.4, true)


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
	var vec_len: float = 20.0+Game.ship_speed*1.5
	var from: Vector2 = center+fwd*15.0
	var mid: Vector2 = center+fwd*(15.0+(vec_len-15.0)*0.62)
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
	var header_h: float = 66.0 if size.y >= 650.0 else 34.0
	var bottom_reserve: float = 66.0 if size.y >= 650.0 else 40.0
	var safe_rect := Rect2(34.0, header_h + 12.0, maxf(1.0, size.x - 68.0), maxf(1.0, size.y - header_h - bottom_reserve))
	if not safe_rect.has_point(center):
		_draw_offscreen_destination(dest, center, safe_rect)
		return
	var scale_px: float = map.pixels_per_unit()
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


func _draw_offscreen_destination(dest: CelestialBodyData, projected: Vector2, safe_rect: Rect2) -> void:
	var center := size * 0.5
	var direction: Vector2 = (projected - center).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.RIGHT
	var marker := Vector2(
		clampf(projected.x, safe_rect.position.x, safe_rect.end.x),
		clampf(projected.y, safe_rect.position.y, safe_rect.end.y)
	)
	var side := Vector2(-direction.y, direction.x)
	var arrow := PackedVector2Array([
		marker + direction * 8.0,
		marker - direction * 9.0 + side * 7.0,
		marker - direction * 9.0 - side * 7.0,
	])
	draw_colored_polygon(arrow, Color(DEST_GREEN, 0.94))
	draw_arc(marker, 14.0, 0.0, TAU, 24, Color(DEST_GREEN, 0.45), 1.2, true)
	var font_size: int = 24 if size.y >= 650.0 else 16
	var text: String = "任务目标"
	var text_width: float = UiStyle.hud_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var text_pos := marker + Vector2(16.0, 7.0)
	if direction.x > 0.35:
		text_pos.x = marker.x - text_width - 16.0
	text_pos.x = clampf(text_pos.x, 10.0, maxf(10.0, size.x - text_width - 10.0))
	text_pos.y = clampf(text_pos.y, safe_rect.position.y + font_size, safe_rect.end.y)
	draw_string(UiStyle.hud_font(), text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, DEST_GREEN)


func _draw_relay_stations(map: SectorMap) -> void:
	if Game.current_sector == null:
		return
	var font_size: int = 14 if size.y >= 650.0 else 11
	for i: int in range(Game.current_sector.relay_stations.size()):
		var world: Vector3 = Game.current_sector.relay_stations[i]
		var center: Vector2 = map.world_to_map(world)
		var reached := Game.is_relay_reached(i)
		var color := DEST_GREEN if reached else UiStyle.CYAN
		var pulse: float = 0.55 + 0.45 * (0.5 + 0.5 * sin(_spin * 2.1 + float(i)))
		draw_arc(center, 9.0, 0.0, TAU, 20, Color(color, 0.35 + pulse * 0.25), 1.4, true)
		draw_arc(center, 5.5, 0.0, TAU, 16, Color(color, 0.92), 1.6, true)
		draw_circle(center, 2.2, Color(color, 0.95))
		var label := Game.relay_station_name(i)
		if reached:
			label = "已抵达 · %s" % label
		var text_width := UiStyle.hud_font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		var text_pos := Vector2(center.x - text_width * 0.5, center.y - 16.0)
		text_pos.x = clampf(text_pos.x, 8.0, maxf(8.0, size.x - text_width - 8.0))
		text_pos.y = clampf(text_pos.y, 28.0, size.y - 8.0)
		draw_string(UiStyle.hud_font(), text_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)


func _draw_belts(map: SectorMap) -> void:
	_ensure_belt_cache()
	var scale_px: float = bake_scale_px if static_belt_bake else map.pixels_per_unit()
	for baked: Dictionary in _belt_cache:
		var fill_color := baked["fill_color"] as Color
		var left := baked["left"] as PackedVector2Array
		var right := baked["right"] as PackedVector2Array
		if left.size() >= 2 and right.size() == left.size():
			var screen_left := _map_points(map, left)
			var screen_right := _map_points(map, right)
			for i: int in range(screen_left.size() - 1):
				_fill_spline_triangle(screen_left[i], screen_left[i + 1], screen_right[i], fill_color)
				_fill_spline_triangle(screen_left[i + 1], screen_right[i + 1], screen_right[i], fill_color)
		else:
			var fill := _map_points(map, baked["fill"] as PackedVector2Array)
			if fill.size() >= 3:
				draw_colored_polygon(fill, fill_color)
		var edges := baked["edges"] as Array
		for edge: Variant in edges:
			var pair := edge as PackedVector2Array
			if pair.size() < 2:
				continue
			draw_line(_map_point(map, pair[0]), _map_point(map, pair[1]), baked["edge_color"] as Color, float(baked["edge_width"]), true)
		for rock: Variant in baked["rocks"] as Array:
			var sample := rock as Dictionary
			var radius: float = clampf(float(sample["radius"]) * scale_px, 0.8, 2.4)
			draw_circle(_map_point(map, sample["point"] as Vector2), radius, Color(0.76, 0.65, 0.52, 0.94))


func _ensure_belt_cache() -> void:
	if Game.current_sector == null:
		_belt_cache.clear()
		_belt_cache_sector = ""
		return
	if _belt_cache_sector == Game.current_sector.id:
		return
	_belt_cache_sector = Game.current_sector.id
	_belt_cache.clear()
	for belt: BeltData in Game.current_sector.belts:
		_belt_cache.append(_bake_belt(belt))


func _bake_belt(belt: BeltData) -> Dictionary:
	var fill := PackedVector2Array()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var edges: Array[PackedVector2Array] = []
	if belt.shape == BeltData.Shape.RING or belt.is_boundary:
		var segs: int = 72 if belt.is_boundary else 56
		for i: int in range(segs + 1):
			fill.append(_xz(belt.point_on_ring(TAU * float(i) / float(segs), belt.outer_radius)))
		for i: int in range(segs + 1):
			fill.append(_xz(belt.point_on_ring(TAU * float(segs - i) / float(segs), belt.inner_radius)))
		_append_dashed_loop(edges, belt, belt.outer_radius, segs)
		_append_dashed_loop(edges, belt, belt.inner_radius, segs)
	elif belt.shape == BeltData.Shape.SPLINE and belt.control_points.size() >= 2:
		var segments: int = maxi(24, (belt.control_points.size() - 1) * 16)
		for i: int in range(segments + 1):
			var t: float = float(i) / float(segments)
			var point: Vector3 = belt.spline_point(t)
			var tangent: Vector3 = belt.spline_tangent(t)
			var side := Vector3(-tangent.z, 0.0, tangent.x).normalized()
			var width: float = belt.spline_half_width(t)
			left.append(_xz(point + side * width))
			right.append(_xz(point - side * width))
		for i: int in range(segments):
			if i % 2 == 0:
				edges.append(PackedVector2Array([left[i], left[i + 1]]))
				edges.append(PackedVector2Array([right[i], right[i + 1]]))
	else:
		var from := _xz(belt.from_point)
		var to := _xz(belt.to_point)
		var delta := to - from
		if delta.length_squared() >= 0.001:
			var along := delta.normalized()
			var side := Vector2(-along.y, along.x) * belt.half_width
			fill = PackedVector2Array([from + side, to + side, to - side, from - side])
			edges.append(PackedVector2Array([from + side, to + side]))
			edges.append(PackedVector2Array([from - side, to - side]))
	var rocks: Array[Dictionary] = []
	for sample: Dictionary in Layout.samples(belt):
		if not bool(sample["hits_flight"]):
			continue
		rocks.append({
			"point": _xz(Vector3(sample["position"])),
			"radius": float(sample["hit_radius"]),
		})
		if rocks.size() >= BELT_ROCK_CAP:
			break
	return {
		"fill": fill,
		"left": left,
		"right": right,
		"fill_color": BELT_FILL_BOUNDARY if belt.is_boundary else BELT_FILL,
		"edges": edges,
		"edge_color": BELT_EDGE_BOUNDARY if belt.is_boundary else BELT_EDGE,
		"edge_width": 1.2,
		"rocks": rocks,
	}


func _append_dashed_loop(edges: Array[PackedVector2Array], belt: BeltData, radius: float, segs: int) -> void:
	for i: int in range(segs):
		if i % 2 == 1:
			continue
		edges.append(PackedVector2Array([
			_xz(belt.point_on_ring(TAU * float(i) / float(segs), radius)),
			_xz(belt.point_on_ring(TAU * float(i + 1) / float(segs), radius)),
		]))


func _xz(world: Vector3) -> Vector2:
	return Vector2(world.x, world.z)


func _map_point(map: SectorMap, world_xz: Vector2) -> Vector2:
	if static_belt_bake:
		return (world_xz-bake_world_rect.position)*bake_scale_px
	return map.world_to_map(Vector3(world_xz.x, 0.0, world_xz.y))


func _map_points(map: SectorMap, worlds: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(worlds.size())
	for i: int in range(worlds.size()):
		out[i] = _map_point(map, worlds[i])
	return out


func _fill_spline_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color) -> void:
	if absf((b - a).cross(c - a)) < 0.04:
		return
	draw_colored_polygon(PackedVector2Array([a, b, c]), color)


## 固定在星图上沿的全程进度轨。实验模式只按起点与目的地距离显示公开进度；
## 标准路线、关键点、扰动锚点和安全门仅在研究人员调试模式显示。
func _draw_route_overview(map: SectorMap) -> void:
	if Game.current_sector == null:
		return
	var large: bool = size.y >= 650.0
	var font_size: int = 22 if large else 15
	var rail_y: float = 27.0 if large else 18.0
	var start := Vector2(14.0,rail_y)
	var finish := Vector2(size.x-14.0,rail_y)
	var display_state := Game.waypoint_cooldown_display_state()
	if display_state != "hidden":
		var remaining := Game.waypoint_cooldown_remaining()
		var notice := "航点冷却 %.1f秒" % remaining if display_state == "cooling" else "航点已就绪"
		var color := UiStyle.AMBER if display_state == "cooling" else DEST_GREEN
		var text_width := UiStyle.hud_font().get_string_size(notice,HORIZONTAL_ALIGNMENT_LEFT,-1.0,font_size).x
		var notice_rect := Rect2(10.0,6.0,text_width+20.0,32.0 if large else 23.0)
		draw_rect(notice_rect,Color(0.008,0.022,0.048,0.90),true)
		draw_rect(notice_rect,Color(color,0.48),false,1.0)
		draw_string(UiStyle.hud_font(),notice_rect.position+Vector2(10.0,font_size+2.0),notice,HORIZONTAL_ALIGNMENT_LEFT,-1.0,font_size,color)
		start.x = notice_rect.end.x+10.0
	draw_line(start,finish,Color(UiStyle.AMBER,0.38),2.0,true)
	var ship_t: float = _public_mission_progress()
	var show_research: bool = Game.researcher_debug_enabled()
	var points := Game.current_sector.route_checkpoints
	if show_research and points.size() >= 2:
		var total := _route_progress(points[points.size()-1],points)
		for i: int in range(points.size()):
			var t: float = _route_progress(points[i],points)/maxf(total,0.001)
			var x: float = lerpf(start.x,finish.x,t)
			draw_line(Vector2(x,start.y-3.0),Vector2(x,start.y+3.0),Color(UiStyle.AMBER,0.35),1.0,true)
		ship_t = clampf(_route_progress(Game.ship_position,points)/maxf(total,0.001),0.0,1.0)
	var ship := start.lerp(finish,ship_t)
	draw_circle(ship,3.2,UiStyle.CYAN)
	if show_research and points.size() >= 2:
		var total := _route_progress(points[points.size()-1],points)
		for anchor: Vector3 in Game.current_sector.disturbance_anchors:
			var a := start.lerp(finish,_route_progress(anchor,points)/maxf(total,0.001))
			draw_circle(a,2.4,Color("f06eb6"))
		for gate: Vector3 in Game.current_sector.safe_gate_points:
			var g := start.lerp(finish,_route_progress(gate,points)/maxf(total,0.001))
			draw_arc(g,3.5,0.0,TAU,12,Color("55e6c7"),1.0,true)
func _public_mission_progress() -> float:
	var destination := Game.objective_body()
	if destination == null or Game.current_sector == null:
		return 0.0
	var start_distance: float = Game.current_sector.spawn_position.distance_to(destination.world_position)
	var remaining: float = Game.ship_position.distance_to(destination.world_position)
	return clampf(1.0 - remaining / maxf(start_distance,0.001),0.0,1.0)


func _route_progress(point: Vector3,points: PackedVector3Array) -> float:
	var best_distance := INF; var best_progress := 0.0; var walked := 0.0
	for i: int in range(points.size()-1):
		var a:=points[i]; var ab:=points[i+1]-a
		var t:=clampf((point-a).dot(ab)/maxf(ab.length_squared(),0.001),0.0,1.0)
		var distance:=point.distance_to(a+ab*t)
		if distance<best_distance: best_distance=distance; best_progress=walked+ab.length()*t
		walked+=ab.length()
	return best_progress
