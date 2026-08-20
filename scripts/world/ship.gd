class_name Ship
extends RigidBody3D
## 飞船：刚体物理撞场景（对齐 dyadic-force 的球），冲击用速度突变判定扣血。

const BeltHazardGeometry = preload("res://scripts/belt_hazard.gd")
const TurningModel = preload("res://scripts/ship_turning_model.gd")

const THRUST_ACCEL: float = 14.0
const REVERSE_ACCEL: float = 8.0
const MAX_YAW_RATE: float = TurningModel.MAX_YAW_RATE
## 低于此速度突变视为轻蹭，不扣血。
const IMPACT_THRESHOLD: float = 3.2
## 达到此冲击大约扣 20 船体。
const REFERENCE_IMPACT: float = 9.0
const MAX_HIT_DAMAGE: float = 32.0
const DAMAGE_EXPONENT: float = 1.35
const I_FRAME_DURATION: float = 0.7
const SPAWN_I_FRAME_DURATION: float = 1.2
## 先用明确的排斥区把玩家推回航区；实体墙仍是高速撞击的最后防线。
const BOUNDARY_WARN_FACTOR: float = 0.86
const BOUNDARY_REPEL_FACTOR: float = 0.91
const BOUNDARY_REPEL_ACCEL: float = 38.0
const BOUNDARY_EDGE_DRAG: float = 2.8
## 稀疏外缘是可恢复的擦伤：持续危险和实体碎石撞击都约为原伤害的三分之一。
const BELT_GRAZE_TICK: float = 0.42
const BELT_GRAZE_DAMAGE_MIN: float = 1.0
const BELT_GRAZE_DAMAGE_MAX: float = 2.33
const ASTEROID_EDGE_IMPACT_SCALE: float = 0.333

const GROUP_PLANET: String = "planet_body"
const GROUP_ASTEROID: String = "asteroid"
const GROUP_WORLD_BOUNDARY: String = "world_boundary"

@onready var pilot_mount: Marker3D = $PilotMount
@onready var hull_sprite: Sprite3D = $HullSprite

var angular_yaw: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _i_frames: float = 0.0
var _boundary_guard_active: bool = false
var _belt_graze_cooldown: float = 0.0
var _belt_contact_id: String = ""


func _ready() -> void:
	gravity_scale = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 12
	continuous_cd = true
	axis_lock_linear_y = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = 4
	collision_mask = 1 | AsteroidField.COLLISION_LAYER
	linear_damp = 0.22
	angular_damp = 0.08
	mass = 1.0
	var mat := PhysicsMaterial.new()
	mat.friction = 0.08
	mat.bounce = 0.42
	physics_material_override = mat
	_sync_hull_shape()
	global_position = Game.ship_position
	rotation = Vector3(0.0, Game.ship_heading, 0.0)
	hull_sprite.visible = false
	_prev_velocity = linear_velocity
	_i_frames = SPAWN_I_FRAME_DURATION


func _sync_hull_shape() -> void:
	var shape_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	var sphere := shape_node.shape as SphereShape3D
	if sphere == null:
		sphere = SphereShape3D.new()
		shape_node.shape = sphere
	sphere.radius = Game.SHIP_RADIUS


func _physics_process(delta: float) -> void:
	_i_frames = maxf(0.0, _i_frames - delta)
	_belt_graze_cooldown=maxf(0.0,_belt_graze_cooldown-delta)
	if not Game.ship_alive or Game.mission_complete:
		Game.boundary_proximity = 0.0
		freeze = true
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_sync_game(delta)
		return
	freeze = false

	# 贴上行星本体即解体，不走冲击阈值。出生无敌期内跳过，避免传送后残留接触再杀一次。
	if _i_frames <= 0.0 and _is_touching_group(GROUP_PLANET):
		Game.explode_ship()
		_sync_game(delta)
		return

	var turn: float = Displays.pilot_turn_axis()
	angular_yaw = TurningModel.step_yaw_rate(angular_yaw, turn, delta)
	angular_velocity = Vector3(0.0, angular_yaw, 0.0)

	var thrust_axis: float = Displays.pilot_thrust_axis()
	var forward: Vector3 = get_forward()
	if thrust_axis > 0.0:
		apply_central_force(forward * THRUST_ACCEL * thrust_axis)
	elif thrust_axis < 0.0:
		apply_central_force(forward * REVERSE_ACCEL * thrust_axis)

	var planar := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if planar.length() > Game.MAX_SPEED:
		planar = planar.normalized() * Game.MAX_SPEED
	linear_velocity = planar
	_apply_boundary_guard(delta)
	_clamp_to_sector()
	if _apply_asteroid_belt_hazard(delta,Game.ship_position,global_position):
		_sync_game(delta)
		return
	# 与 dyadic-force 相同：本帧脚本改完速度后再用突变判断撞击。
	_detect_impact()
	_prev_velocity = linear_velocity
	_sync_game(delta)


func _detect_impact() -> void:
	var impact: float = (_prev_velocity - linear_velocity).length()
	if impact < IMPACT_THRESHOLD:
		return
	var edge_asteroid_contact := (
		_is_touching_group(GROUP_ASTEROID)
		and not _is_touching_group(GROUP_WORLD_BOUNDARY)
	)
	_apply_impact_damage(impact, ASTEROID_EDGE_IMPACT_SCALE if edge_asteroid_contact else 1.0)


## 实验扰动使用一次性横向冲量，保留刚体碰撞和驾驶员后续修正的真实轨迹。
func apply_experiment_shear(strength: float) -> Vector3:
	var lateral := global_transform.basis.x.normalized()*strength
	apply_central_impulse(lateral)
	return lateral


func _is_touching_group(group_name: String) -> bool:
	var bodies: Array = get_colliding_bodies()
	for i: int in range(bodies.size()):
		var node := bodies[i] as Node
		if node != null and node.is_in_group(group_name):
			return true
	return false


func _apply_impact_damage(strength: float, damage_scale: float = 1.0) -> void:
	if _i_frames > 0.0 or not Game.ship_alive:
		return
	var amount: float = _damage_from_impact(strength) * maxf(damage_scale, 0.0)
	_i_frames = I_FRAME_DURATION
	Game.apply_hull_damage(amount)


func _damage_from_impact(strength: float) -> float:
	var span: float = maxf(REFERENCE_IMPACT - IMPACT_THRESHOLD, 1.0)
	var normalized: float = clampf((strength - IMPACT_THRESHOLD) / span, 0.0, 3.0)
	var raw: float = minf(pow(normalized, DAMAGE_EXPONENT), 1.0) * MAX_HIT_DAMAGE
	return clampf(maxf(raw, 8.0), 8.0, MAX_HIT_DAMAGE)


func _apply_asteroid_belt_hazard(_delta: float,previous: Vector3,current: Vector3) -> bool:
	if Game.current_sector==null:
		_set_belt_contact("")
		return false
	var exposure := BeltHazardGeometry.max_sector_fraction(
		previous,current,Game.current_sector.belts,Game.SHIP_RADIUS
	)
	var fraction: float = float(exposure["fraction"])
	var belt := exposure["belt"] as BeltData
	var exposure_class := BeltHazardGeometry.classify(fraction)
	if belt==null or exposure_class==BeltHazardGeometry.Exposure.CLEAR:
		_set_belt_contact("")
		return false
	_set_belt_contact(belt.id)
	if exposure_class==BeltHazardGeometry.Exposure.CORE:
		ExperimentLog.log_event("asteroid_belt_core_breach","pilot",{
			"belt_id":belt.id,"penetration":fraction,"x":current.x,"z":current.z
		})
		Game.explode_ship()
		return true
	if _belt_graze_cooldown<=0.0:
		var intensity := clampf(fraction/BeltHazardGeometry.CORE_FRACTION,0.0,1.0)
		var damage := lerpf(BELT_GRAZE_DAMAGE_MIN,BELT_GRAZE_DAMAGE_MAX,intensity)
		_belt_graze_cooldown=BELT_GRAZE_TICK
		Game.apply_hull_damage(damage)
		ExperimentLog.log_event("asteroid_belt_graze","pilot",{
			"belt_id":belt.id,"penetration":fraction,"damage":damage,
			"x":current.x,"z":current.z
		})
	return not Game.ship_alive


func _set_belt_contact(belt_id: String) -> void:
	if belt_id==_belt_contact_id:
		return
	if not _belt_contact_id.is_empty():
		ExperimentLog.log_event("asteroid_belt_exit","pilot",{"belt_id":_belt_contact_id})
	_belt_contact_id=belt_id
	if not _belt_contact_id.is_empty():
		ExperimentLog.log_event("asteroid_belt_enter","pilot",{"belt_id":_belt_contact_id})


func _sync_game(delta: float) -> void:
	var previous_position:=Game.ship_position
	Game.ship_position = global_position
	Game.ship_heading = rotation.y
	Game.ship_velocity = linear_velocity
	Game.ship_angular_velocity = angular_yaw
	Game.ship_speed = Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()
	var target_throttle: float = clampf(Displays.pilot_thrust_axis(), -1.0, 1.0)
	if Game.mission_complete:
		target_throttle = 0.0
	Game.throttle = lerpf(Game.throttle, target_throttle, clampf(delta * 6.0, 0.0, 1.0))
	visible = Game.ship_alive
	collision_layer = 4 if Game.ship_alive else 0
	Game.update_mission_progress(previous_position,Game.ship_position)
	Game.ship_state_changed.emit(Game.ship_position, Game.ship_heading, Game.ship_speed, Game.throttle)


func _clamp_to_sector() -> void:
	var wall: BeltData = _boundary_belt()
	if wall == null:
		return
	# 正常弹墙交给刚体；只有整艘船已经穿出外沿时才拉回，避免和物理抢位置。
	var outer_factor: float = wall.ellipse_factor(global_position, wall.outer_radius)
	if outer_factor <= 1.01:
		return
	var inner_limit: float = maxf(wall.inner_radius - Game.SHIP_RADIUS, 1.0)
	var inner_factor: float = wall.ellipse_factor(global_position, inner_limit)
	if inner_factor > 0.0001:
		global_position.x = wall.center.x + (global_position.x - wall.center.x) / inner_factor
		global_position.z = wall.center.z + (global_position.z - wall.center.z) / inner_factor
	global_position.y = 0.0
	linear_velocity = Vector3.ZERO


func _apply_boundary_guard(delta: float) -> void:
	var wall := _boundary_belt()
	if wall == null:
		Game.boundary_proximity = 0.0
		return
	var safe_radius := maxf(wall.inner_radius-Game.SHIP_RADIUS,1.0)
	var factor := wall.ellipse_factor(global_position,safe_radius)
	Game.boundary_proximity = clampf((factor-BOUNDARY_WARN_FACTOR)/(1.0-BOUNDARY_WARN_FACTOR),0.0,1.0)
	var guard_now: bool = factor>=BOUNDARY_REPEL_FACTOR
	if guard_now != _boundary_guard_active:
		_boundary_guard_active = guard_now
		ExperimentLog.log_event("boundary_guard_enter" if guard_now else "boundary_guard_exit","pilot",{
			"factor":factor,"x":global_position.x,"z":global_position.z
		})
	if not guard_now: return
	var intensity := smoothstep(BOUNDARY_REPEL_FACTOR,1.0,factor)
	var outward := wall.outward_normal(global_position,safe_radius)
	if outward.length_squared()<0.000001: return
	apply_central_force(-outward*BOUNDARY_REPEL_ACCEL*intensity)
	var outward_speed := linear_velocity.dot(outward)
	if outward_speed>0.0:
		linear_velocity-=outward*outward_speed*clampf(delta*7.0*intensity,0.0,1.0)
	# 沿墙滑行也会显著减速，边缘不能成为绕过内部关卡的高速公路。
	linear_velocity*=exp(-delta*BOUNDARY_EDGE_DRAG*intensity)


func _boundary_belt() -> BeltData:
	if Game.current_sector == null:
		return null
	for belt: BeltData in Game.current_sector.belts:
		if belt.is_boundary:
			return belt
	return null


func get_forward() -> Vector3:
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		return forward.normalized()
	return Vector3.FORWARD


func snap_to_state() -> void:
	freeze = true
	# 先关掉接触监控，清掉撞毁位置留下的碰撞缓存，再传送回出生点。
	contact_monitor = false
	global_position = Game.ship_position
	rotation = Vector3(0.0, Game.ship_heading, 0.0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	angular_yaw = 0.0
	_prev_velocity = Vector3.ZERO
	_i_frames = SPAWN_I_FRAME_DURATION
	_boundary_guard_active = false
	_belt_graze_cooldown=0.0
	_belt_contact_id=""
	Game.boundary_proximity = 0.0
	visible = true
	hull_sprite.visible = false
	collision_layer = 4
	collision_mask = 1 | AsteroidField.COLLISION_LAYER
	sleeping = false
	freeze = false
	contact_monitor = true
	max_contacts_reported = 12
