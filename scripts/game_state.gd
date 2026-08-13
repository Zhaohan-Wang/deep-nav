extends Node
## 全局游戏状态：当前扇区、飞船、航点、显示模式。

signal ship_state_changed(position: Vector3, heading: float, speed: float, throttle: float)
signal waypoint_changed(world_pos: Vector3, enabled: bool)
signal hull_changed(hull: float)
signal destination_reached
signal ship_hit(remaining_hull: float)
signal ship_exploded(world_pos: Vector3)
signal view_mode_changed(mode: int)

enum ViewMode {
	SPLIT,
	NAVIGATOR_ONLY,
	PILOT_ONLY,
	DUAL_WINDOW,
}

const SHIP_RADIUS: float = 1.2
const MAX_HULL: float = 100.0
const MAX_SPEED: float = 16.0

var current_sector: SectorData
var celestial_bodies: Array[CelestialBodyData] = []
var ship_position: Vector3 = Vector3.ZERO
var ship_heading: float = 0.0
var ship_velocity: Vector3 = Vector3.ZERO
var ship_angular_velocity: float = 0.0
var ship_speed: float = 0.0
var throttle: float = 0.0
var hull: float = MAX_HULL
var waypoint: Vector3 = Vector3.ZERO
var has_waypoint: bool = false
var view_mode: int = ViewMode.SPLIT
var mission_complete: bool = false
var ship_alive: bool = true


func _ready() -> void:
	current_sector = SectorCatalog.make_sector_01()
	_apply_sector()


func world_half() -> float:
	if current_sector != null:
		return current_sector.world_half
	return 96.0


func _apply_sector() -> void:
	celestial_bodies = current_sector.bodies
	ship_position = current_sector.spawn_position
	ship_heading = current_sector.spawn_heading


func reset_run() -> void:
	_apply_sector()
	ship_velocity = Vector3.ZERO
	ship_angular_velocity = 0.0
	ship_speed = 0.0
	throttle = 0.0
	hull = MAX_HULL
	has_waypoint = false
	mission_complete = false
	ship_alive = true
	hull_changed.emit(hull)
	waypoint_changed.emit(waypoint, false)
	ship_state_changed.emit(ship_position, ship_heading, ship_speed, throttle)


func set_waypoint(world_pos: Vector3) -> void:
	waypoint = Vector3(world_pos.x, 0.0, world_pos.z)
	has_waypoint = true
	waypoint_changed.emit(waypoint, true)


func clear_waypoint() -> void:
	has_waypoint = false
	waypoint_changed.emit(waypoint, false)


func explode_ship() -> void:
	if not ship_alive:
		return
	ship_alive = false
	ship_exploded.emit(ship_position)


func apply_hull_damage(amount: float) -> void:
	if mission_complete or not ship_alive:
		return
	hull = maxf(0.0, hull - amount)
	hull_changed.emit(hull)
	ship_hit.emit(hull)
	if hull <= 0.0:
		explode_ship()


func mark_destination_reached() -> void:
	if mission_complete:
		return
	mission_complete = true
	destination_reached.emit()


func cycle_view_mode() -> void:
	if view_mode == ViewMode.DUAL_WINDOW:
		view_mode = ViewMode.SPLIT
	else:
		view_mode = (view_mode + 1) % 3
	view_mode_changed.emit(view_mode)


func set_view_mode(mode: int) -> void:
	view_mode = mode
	view_mode_changed.emit(view_mode)


## 星图用各向同性比例：1 世界单位 = 多少像素。取短边，保证圆还是圆。
func map_pixels_per_unit(map_size: Vector2) -> float:
	var span: float = world_half() * 2.0
	if span < 0.001 or map_size.x < 1.0 or map_size.y < 1.0:
		return 1.0
	return minf(map_size.x, map_size.y) / span


func world_to_map(world: Vector3, map_rect: Rect2) -> Vector2:
	var scale_px: float = map_pixels_per_unit(map_rect.size)
	var origin: Vector2 = map_rect.get_center()
	return Vector2(origin.x + world.x * scale_px, origin.y + world.z * scale_px)


func map_to_world(map_pos: Vector2, map_rect: Rect2) -> Vector3:
	var scale_px: float = map_pixels_per_unit(map_rect.size)
	if scale_px < 0.001:
		return Vector3.ZERO
	var origin: Vector2 = map_rect.get_center()
	return Vector3((map_pos.x - origin.x) / scale_px, 0.0, (map_pos.y - origin.y) / scale_px)


func find_body(id: String) -> CelestialBodyData:
	for body: CelestialBodyData in celestial_bodies:
		if body.id == id:
			return body
	return null


func find_star() -> CelestialBodyData:
	for body: CelestialBodyData in celestial_bodies:
		if body.kind == CelestialBodyData.Kind.STAR:
			return body
	return null


func objective_body() -> CelestialBodyData:
	if current_sector == null:
		return null
	return find_body(current_sector.objective_body_id)
