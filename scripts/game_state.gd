extends Node
## 全局游戏状态：当前扇区、飞船、航点、显示模式。
## 关卡锁定只在实验模式生效；关掉实验模式后，四关都可以直接进、可重复玩。

const Catalog = preload("res://scripts/mission_catalog.gd")
const RouteGateScript = preload("res://scripts/route_gate.gd")

signal ship_state_changed(position: Vector3, heading: float, speed: float, throttle: float)
signal waypoint_changed(world_pos: Vector3, enabled: bool)
signal waypoint_request_result(accepted: bool, reason: String, remaining_s: float)
signal hull_changed(hull: float)
signal destination_reached
signal ship_hit(remaining_hull: float)
signal ship_exploded(world_pos: Vector3)
signal view_mode_changed(mode: int)
signal settings_changed
signal disturbance_gate_crossed(index: int,slot: String,anchor: Vector3)
signal disturbance_effect_applied(effect: String,payload: Dictionary)
signal safe_gate_crossed(index: int,anchor: Vector3)
signal relay_station_reached(index: int,position: Vector3,station_name: String)

enum ViewMode {
	SPLIT,
	NAVIGATOR_ONLY,
	PILOT_ONLY,
	DUAL_WINDOW,
}

const SHIP_RADIUS: float = 1.2
const MAX_HULL: float = 100.0
const MAX_SPEED: float = 16.0
## 飞到中继站这个半径内即认领；按计划航线经过时不会错过。
const RELAY_REACH_RADIUS: float = 22.0

var current_sector: SectorData
var celestial_bodies: Array[CelestialBodyData] = []
var ship_position: Vector3 = Vector3.ZERO
var ship_heading: float = 0.0
var ship_velocity: Vector3 = Vector3.ZERO
var ship_angular_velocity: float = 0.0
var ship_speed: float = 0.0
var throttle: float = 0.0
var hull: float = MAX_HULL
## 0..1：接近连续世界边界的程度，供两端一致显示告警。
var boundary_proximity: float = 0.0
var waypoint: Vector3 = Vector3.ZERO
var has_waypoint: bool = false
var waypoint_request_sequence: int = 0
var last_waypoint_requested: Vector3 = Vector3.ZERO
var last_waypoint_applied: Vector3 = Vector3.ZERO
var view_mode: int = ViewMode.SPLIT
var mission_complete: bool = false
var ship_alive: bool = true
## 由主任务场景逐帧同步，供两块角色屏和结算页读取同一计时状态。
var mission_elapsed_s: float = 0.0
var mission_time_limit_s: float = 0.0
var mission_timer_active: bool = false
var selected_mission_id: String = "practice"
## 本次应用运行内的临时关卡进度；不写 settings.cfg，退出应用即自然清空。
var session_mission_index: int = 0
var session_mission_results: Dictionary = {}
var debug_mode: bool = false
var experiment_mode: bool = false
var master_volume: float = 0.85
var screen_shake_enabled: bool = true
var fullscreen_dual_display: bool = true
var waypoint_cooldown_s: float = 4.0
var waypoint_max_distance: float = 72.0
const SETTINGS_PATH := "user://settings.cfg"
## 每次需要参与者重新确认声音、动态效果和 macOS 权限说明时递增。
const SETTINGS_REVISION: int = 2
const EXPERIMENT_PROTOCOL_VERSION := "in-game-measures-4.3"
var settings_revision: int = 0
var dyad_sequence: int = 0
var dyad_id: String = ""
var participant_a: String = ""
var participant_b: String = ""
var participant_a_seat: int = 0
var attribution_condition: String = ""
var condition_assignment_method: String = ""
var condition_assignment_token: String = ""
var experiment_setup_locked: bool = false
## 新手关不锁岗位；首次进入正式关时保存屏幕 A 的岗位，后续正式关沿用。
var formal_roles_locked: bool = false
var locked_primary_role: int = 0
## 两个预设异常的中性回顾资料跨关保存在内存中；新实验序列开始时清空。
var event_review_records: Dictionary = {}
var mission_attempt_counts: Dictionary = {}
var _last_waypoint_msec: int = -1
var _triggered_disturbances: Dictionary = {}
var _triggered_safe_gates: Dictionary = {}
## 扰动门经过时可能恰好没有活动航点；用队列保留每一次脉冲，避免后来的随机值覆盖前一次。
var _pending_waypoint_drifts: Array[float] = []
var _reached_relays: Dictionary = {}
var last_relay_index: int = -1


## 研究元数据只能在纯调试模式展示。实验模式拥有更高优先级，防止误开两个开关时泄漏条件。
func researcher_debug_enabled() -> bool:
	return debug_mode and not experiment_mode


func unlock_all_missions() -> bool:
	return not experiment_mode


func _ready() -> void:
	_ensure_input_actions()
	load_settings()
	current_sector = Catalog.by_id(selected_mission_id)
	_apply_sector()


func _ensure_input_actions() -> void:
	# 自动检查会直接实例化飞船而不经过 Main；先注册动作名，按键绑定仍由 Main 统一配置。
	for action: String in ["thrust","brake","turn_left","turn_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func select_mission(id: String) -> void:
	selected_mission_id = id
	current_sector = Catalog.by_id(id)
	reset_run()


func begin_mission_sequence() -> void:
	session_mission_index = 0
	session_mission_results.clear()
	event_review_records.clear()
	mission_attempt_counts.clear()
	formal_roles_locked = false
	locked_primary_role = 0
	select_mission(Catalog.IDS[0])


func note_mission_attempt() -> int:
	var attempt := int(mission_attempt_counts.get(selected_mission_id,0)) + 1
	mission_attempt_counts[selected_mission_id] = attempt
	return attempt


func current_mission_attempt_number() -> int:
	return maxi(int(mission_attempt_counts.get(selected_mission_id,1)),1)


func store_event_review(event_type: String,record: Dictionary) -> void:
	event_review_records[event_type] = record


func event_review(event_type: String) -> Dictionary:
	return event_review_records.get(event_type,{}) as Dictionary


func has_mission_review(mission_id: String) -> bool:
	return event_review_records.has(mission_id)


## 条件在锁定实验组时运行时随机分配。组号只负责稳定编号和屏幕侧别，不再决定条件。
func lock_experiment_setup(sequence: int) -> bool:
	if sequence <= 0:
		return false
	dyad_sequence = sequence
	dyad_id = "D%03d" % sequence
	participant_a = "%sA" % dyad_id
	participant_b = "%sB" % dyad_id
	# 正式实验固定玩法参数，不继承预览模式中的本机设置。
	waypoint_cooldown_s = 4.0
	waypoint_max_distance = 72.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var token := rng.randi()
	attribution_condition = "explicit" if posmod(token,2) == 0 else "ambiguous"
	condition_assignment_method = "runtime_random_1_to_1"
	condition_assignment_token = str(token)
	var block := posmod(sequence - 1,4)
	participant_a_seat = 0 if block < 2 else 1
	experiment_setup_locked = true
	return true


func clear_experiment_setup() -> void:
	dyad_sequence = 0
	dyad_id = ""
	participant_a = ""
	participant_b = ""
	participant_a_seat = 0
	attribution_condition = ""
	condition_assignment_method = ""
	condition_assignment_token = ""
	experiment_setup_locked = false
	formal_roles_locked = false
	locked_primary_role = 0


func lock_formal_roles(primary_role: int) -> void:
	locked_primary_role = 0 if primary_role == 0 else 1
	formal_roles_locked = true


func formal_role_for_primary_screen() -> int:
	return locked_primary_role


func participant_id_for_seat(seat: int) -> String:
	if not experiment_setup_locked:
		return ""
	return participant_a if seat == participant_a_seat else participant_b


func participant_id_for_role(role: String) -> String:
	if role not in ["navigator","pilot"]:
		return ""
	var displays := get_node_or_null("/root/Displays")
	if displays == null:
		return ""
	for seat: int in [0,1]:
		if String(displays.call("role_name_for_seat",seat)) == role:
			return participant_id_for_seat(seat)
	return ""


func participant_letter_for_seat(seat: int) -> String:
	if not experiment_setup_locked:
		return ""
	return "A" if seat == participant_a_seat else "B"


func active_mission_id() -> String:
	if session_mission_index < 0 or session_mission_index >= Catalog.IDS.size():
		return ""
	return Catalog.IDS[session_mission_index]


func can_play_mission(id: String) -> bool:
	if id.is_empty() or not Catalog.IDS.has(id):
		return false
	if unlock_all_missions():
		return true
	return id == active_mission_id() and not session_mission_results.has(id)


func mission_session_status(id: String) -> String:
	if unlock_all_missions():
		if session_mission_results.has(id):
			return "open"
		return "current" if id == selected_mission_id else "open"
	if session_mission_results.has(id):
		return "completed"
	if id == active_mission_id():
		return "current"
	return "locked"


func mark_current_mission_played(outcome: String) -> void:
	var active := active_mission_id()
	if active.is_empty() or selected_mission_id != active or session_mission_results.has(active):
		return
	session_mission_results[active] = outcome
	session_mission_index += 1
	var next_id := active_mission_id()
	if not next_id.is_empty():
		selected_mission_id = next_id
		current_sector = Catalog.by_id(next_id)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	settings_revision = int(cfg.get_value("meta", "settings_revision", 0))
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 0.85)), 0.0, 1.0)
	debug_mode = bool(cfg.get_value("mode", "debug", false))
	experiment_mode = bool(cfg.get_value("mode", "experiment", false))
	screen_shake_enabled = bool(cfg.get_value("visual", "screen_shake", true))
	# 双屏是应用的固定结构，旧配置中的关闭值不再覆盖它。
	fullscreen_dual_display = true
	waypoint_cooldown_s = clampf(float(cfg.get_value("navigation", "cooldown_s", 4.0)), 0.5, 5.0)
	waypoint_max_distance = clampf(float(cfg.get_value("navigation", "max_distance", 72.0)), 24.0, 140.0)
	_apply_volume()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "settings_revision", settings_revision)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("mode", "debug", debug_mode)
	cfg.set_value("mode", "experiment", experiment_mode)
	cfg.set_value("visual", "screen_shake", screen_shake_enabled)
	cfg.set_value("visual", "dual_display", true)
	cfg.set_value("navigation", "cooldown_s", waypoint_cooldown_s)
	cfg.set_value("navigation", "max_distance", waypoint_max_distance)
	cfg.save(SETTINGS_PATH)
	_apply_volume()
	settings_changed.emit()


func needs_settings_confirmation() -> bool:
	return settings_revision < SETTINGS_REVISION


func confirm_settings_revision() -> void:
	settings_revision = SETTINGS_REVISION
	save_settings()


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.001)))


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
	boundary_proximity = 0.0
	has_waypoint = false
	last_waypoint_requested = Vector3.ZERO
	last_waypoint_applied = Vector3.ZERO
	_last_waypoint_msec = -1
	mission_complete = false
	ship_alive = true
	mission_elapsed_s = 0.0
	mission_time_limit_s = current_sector.time_limit_s if current_sector != null else 0.0
	mission_timer_active = current_sector != null and current_sector.id != "practice"
	_triggered_disturbances.clear()
	_triggered_safe_gates.clear()
	_pending_waypoint_drifts.clear()
	_reached_relays.clear()
	last_relay_index = -1
	hull_changed.emit(hull)
	waypoint_changed.emit(waypoint, false)
	ship_state_changed.emit(ship_position, ship_heading, ship_speed, throttle)


func update_mission_progress(previous: Vector3,current: Vector3) -> void:
	if current_sector == null or mission_complete or not ship_alive: return
	for i: int in range(current_sector.disturbance_anchors.size()):
		if _triggered_disturbances.has(i): continue
		var anchor:=current_sector.disturbance_anchors[i]
		if RouteGateScript.crossed(previous,current,anchor,current_sector.route_checkpoints):
			_triggered_disturbances[i]=true
			var slot:=current_sector.disturbance_slots[i] if i<current_sector.disturbance_slots.size() else "event"
			disturbance_gate_crossed.emit(i,slot,anchor)
	for i: int in range(current_sector.safe_gate_points.size()):
		if _triggered_safe_gates.has(i): continue
		var anchor:=current_sector.safe_gate_points[i]
		if RouteGateScript.crossed(previous,current,anchor,current_sector.route_checkpoints):
			_triggered_safe_gates[i]=true
			safe_gate_crossed.emit(i,anchor)
	_check_relay_stations(current)


func set_waypoint(world_pos: Vector3) -> bool:
	waypoint_request_sequence += 1
	last_waypoint_requested = Vector3(world_pos.x,0.0,world_pos.z)
	last_waypoint_applied = Vector3.ZERO
	var now: int = Time.get_ticks_msec()
	var remaining_s := waypoint_cooldown_remaining(now)
	if remaining_s > 0.0:
		waypoint_request_result.emit(false, "cooldown", remaining_s)
		return false
	var requested := Vector3(world_pos.x, 0.0, world_pos.z)
	var from_ship := requested - ship_position
	from_ship.y = 0.0
	var clamped_to_range := false
	if from_ship.length() > waypoint_max_distance:
		# 保留用户点击的方位，只把距离截到领航员当前允许的最远半径。
		# 这样远处点击仍能快速表达方向，不会因为一次误差完全丢失操作。
		requested = ship_position + from_ship.normalized() * waypoint_max_distance
		requested.y = 0.0
		clamped_to_range = true
	var boundary := _boundary_belt()
	if boundary != null and boundary.ellipse_factor(requested,boundary.inner_radius-6.0)>=1.0:
		waypoint_request_result.emit(false,"boundary",0.0)
		return false
	waypoint = requested
	if not _pending_waypoint_drifts.is_empty():
		var pending := float(_pending_waypoint_drifts.pop_front())
		_apply_waypoint_drift(pending,"next_waypoint",false)
	last_waypoint_applied = waypoint
	has_waypoint = true
	_last_waypoint_msec = now
	waypoint_changed.emit(waypoint, true)
	waypoint_request_result.emit(true, "clamped_range" if clamped_to_range else "accepted", 0.0)
	return true


func trigger_waypoint_drift(angle_degrees: float) -> void:
	if has_waypoint:
		_apply_waypoint_drift(angle_degrees,"active_waypoint",true)
	else:
		arm_waypoint_drift(angle_degrees,"no_active_waypoint")


## 实验关只武装下一次领航点击，不移动已经显示的航点。
## 因此参与者只会看到偏移后的最终航点，不会看到标记先落下再突然跳动。
func arm_waypoint_drift(angle_degrees: float,reason: String = "disturbance_zone") -> void:
	_pending_waypoint_drifts.append(angle_degrees)
	disturbance_effect_applied.emit("waypoint_drift_armed",{
		"angle_degrees":angle_degrees,
		"reason":reason,
		"queued_pulse_count":_pending_waypoint_drifts.size(),
	})


func _apply_waypoint_drift(angle_degrees: float,timing: String,notify_waypoint: bool) -> void:
	var before := waypoint
	var relative := waypoint-ship_position
	relative = relative.rotated(Vector3.UP,deg_to_rad(angle_degrees))
	waypoint = ship_position+relative
	waypoint.y = 0.0
	has_waypoint = true
	if notify_waypoint:
		waypoint_changed.emit(waypoint,true)
	disturbance_effect_applied.emit("waypoint_drift",{
		"angle_degrees":angle_degrees,"timing":timing,
		"before_x":before.x,"before_z":before.z,
		"after_x":waypoint.x,"after_z":waypoint.z,
	})


## 星图每帧读取同一时钟，进度条和实际输入锁定不会发生漂移。
func waypoint_cooldown_remaining(now_msec: int = -1) -> float:
	if _last_waypoint_msec < 0:
		return 0.0
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var elapsed_s: float = float(now - _last_waypoint_msec) / 1000.0
	return maxf(0.0,waypoint_cooldown_s-elapsed_s)


func waypoint_cooldown_readiness(now_msec: int = -1) -> float:
	if waypoint_cooldown_s <= 0.001:
		return 1.0
	return clampf(1.0-waypoint_cooldown_remaining(now_msec)/waypoint_cooldown_s,0.0,1.0)


## 使用过航点后始终显示唯一状态：冷却中或已就绪。只有从未使用时隐藏。
func waypoint_cooldown_display_state(now_msec: int = -1) -> String:
	if _last_waypoint_msec < 0:
		return "hidden"
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var elapsed_s := float(now-_last_waypoint_msec)/1000.0
	if elapsed_s < waypoint_cooldown_s:
		return "cooling"
	return "ready"


func clear_waypoint() -> void:
	has_waypoint = false
	waypoint_changed.emit(waypoint, false)


func explode_ship() -> void:
	if not ship_alive:
		return
	hull = 0.0
	hull_changed.emit(hull)
	ship_alive = false
	ship_exploded.emit(ship_position)


## 单次解体后的生命重置：保留本关计时、已触发事件和统计，只恢复飞船与航点。
func _check_relay_stations(current: Vector3) -> void:
	if current_sector == null:
		return
	for i: int in range(current_sector.relay_stations.size()):
		if _reached_relays.has(i):
			continue
		var station: Vector3 = current_sector.relay_stations[i]
		if current.distance_to(station) > RELAY_REACH_RADIUS:
			continue
		_reached_relays[i] = true
		if i > last_relay_index:
			last_relay_index = i
		relay_station_reached.emit(i, station, relay_station_name(i))


func is_relay_reached(index: int) -> bool:
	return _reached_relays.has(index)


func relay_station_name(index: int) -> String:
	if current_sector == null:
		return "中继站"
	var count := current_sector.relay_stations.size()
	if count <= 1:
		return "中继站"
	return "中继站 %s" % ("α" if index <= 0 else "β")


func last_respawn_point() -> Dictionary:
	if current_sector == null:
		return {"position": Vector3.ZERO, "heading": 0.0, "index": -1, "name": "起点"}
	if last_relay_index >= 0 and last_relay_index < current_sector.relay_stations.size():
		var station: Vector3 = current_sector.relay_stations[last_relay_index]
		return {
			"position": station,
			"heading": _heading_from(station),
			"index": last_relay_index,
			"name": relay_station_name(last_relay_index),
		}
	return {
		"position": current_sector.spawn_position,
		"heading": current_sector.spawn_heading,
		"index": -1,
		"name": "起点",
	}


func _heading_from(from: Vector3) -> float:
	if current_sector == null or current_sector.route_checkpoints.size() < 2:
		return current_sector.spawn_heading if current_sector != null else 0.0
	var points := current_sector.route_checkpoints
	var next_point := points[points.size() - 1]
	for i: int in range(points.size() - 1):
		if from.distance_to(points[i]) <= from.distance_to(points[i + 1]):
			next_point = points[i + 1]
			break
	var direction := next_point - from
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		return current_sector.spawn_heading
	return atan2(-direction.x, -direction.z)


func respawn_ship_at(checkpoint: Vector3,heading: float) -> void:
	ship_position = Vector3(checkpoint.x,0.0,checkpoint.z)
	ship_heading = heading
	ship_velocity = Vector3.ZERO
	ship_angular_velocity = 0.0
	ship_speed = 0.0
	throttle = 0.0
	hull = MAX_HULL
	boundary_proximity = 0.0
	has_waypoint = false
	ship_alive = true
	_last_waypoint_msec = -1
	hull_changed.emit(hull)
	waypoint_changed.emit(waypoint,false)
	ship_state_changed.emit(ship_position,ship_heading,ship_speed,throttle)


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
	var view_half: float = current_sector.map_view_half if current_sector != null else world_half()
	var span: float = view_half * 2.0
	if span < 0.001 or map_size.x < 1.0 or map_size.y < 1.0:
		return 1.0
	return minf(map_size.x, map_size.y) / span


func world_to_map(world: Vector3, map_rect: Rect2, focus: Vector3 = Vector3.ZERO) -> Vector2:
	var scale_px: float = map_pixels_per_unit(map_rect.size)
	var origin: Vector2 = map_rect.get_center()
	return Vector2(origin.x + (world.x - focus.x) * scale_px, origin.y + (world.z - focus.z) * scale_px)


func map_to_world(map_pos: Vector2, map_rect: Rect2, focus: Vector3 = Vector3.ZERO) -> Vector3:
	var scale_px: float = map_pixels_per_unit(map_rect.size)
	if scale_px < 0.001:
		return Vector3.ZERO
	var origin: Vector2 = map_rect.get_center()
	return Vector3((map_pos.x - origin.x) / scale_px + focus.x, 0.0, (map_pos.y - origin.y) / scale_px + focus.z)


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


func objective_distance() -> float:
	var destination := objective_body()
	if destination == null:
		return 0.0
	return Vector3(ship_position.x,0.0,ship_position.z).distance_to(Vector3(destination.world_position.x,0.0,destination.world_position.z))


func mission_progress_ratio() -> float:
	if current_sector == null:
		return 0.0
	var points := current_sector.route_checkpoints
	if points.size() < 2:
		var destination := objective_body()
		if destination == null:
			return 0.0
		var start_distance := current_sector.spawn_position.distance_to(destination.world_position)
		return clampf(1.0-objective_distance()/maxf(start_distance,0.001),0.0,1.0)
	var walked := 0.0
	var total := 0.0
	var best_distance := INF
	var best_progress := 0.0
	for i: int in range(points.size()-1):
		var a: Vector3 = points[i]
		var ab: Vector3 = points[i+1]-a
		var length := ab.length()
		var t := clampf((ship_position-a).dot(ab)/maxf(ab.length_squared(),0.001),0.0,1.0)
		var distance := ship_position.distance_to(a+ab*t)
		if distance < best_distance:
			best_distance = distance
			best_progress = walked+length*t
		walked += length
		total += length
	return clampf(best_progress/maxf(total,0.001),0.0,1.0)


func _boundary_belt() -> BeltData:
	if current_sector == null: return null
	for belt: BeltData in current_sector.belts:
		if belt.is_boundary: return belt
	return null
