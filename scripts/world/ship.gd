class_name Ship
extends RigidBody3D
## 飞船：刚体物理撞场景（对齐 dyadic-force 的球），冲击用速度突变判定扣血。

const THRUST_ACCEL: float = 14.0
const REVERSE_ACCEL: float = 8.0
const TURN_ACCEL: float = 2.55
const ANGULAR_DAMP_RATE: float = 0.30
const MAX_YAW_RATE: float = 1.45
## 低于此速度突变视为轻蹭，不扣血。
const IMPACT_THRESHOLD: float = 3.2
## 达到此冲击大约扣 20 船体。
const REFERENCE_IMPACT: float = 9.0
const MAX_HIT_DAMAGE: float = 32.0
const DAMAGE_EXPONENT: float = 1.35
const I_FRAME_DURATION: float = 0.7
const SPAWN_I_FRAME_DURATION: float = 1.2

const GROUP_PLANET: String = "planet_body"
const GROUP_ASTEROID: String = "asteroid"

@onready var pilot_mount: Marker3D = $PilotMount
@onready var hull_sprite: Sprite3D = $HullSprite

var angular_yaw: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _i_frames: float = 0.0


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
	if not Game.ship_alive or Game.mission_complete:
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

	var turn: float = Input.get_axis("turn_right", "turn_left")
	angular_yaw += turn * TURN_ACCEL * delta
	angular_yaw *= 1.0 - ANGULAR_DAMP_RATE * delta
	angular_yaw = clampf(angular_yaw, -MAX_YAW_RATE, MAX_YAW_RATE)
	angular_velocity = Vector3(0.0, angular_yaw, 0.0)

	var thrust_axis: float = Input.get_axis("brake", "thrust")
	var forward: Vector3 = get_forward()
	if thrust_axis > 0.0:
		apply_central_force(forward * THRUST_ACCEL * thrust_axis)
	elif thrust_axis < 0.0:
		apply_central_force(forward * REVERSE_ACCEL * thrust_axis)

	var planar := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if planar.length() > Game.MAX_SPEED:
		planar = planar.normalized() * Game.MAX_SPEED
	linear_velocity = planar
	_clamp_to_sector()
	# 与 dyadic-force 相同：本帧脚本改完速度后再用突变判断撞击。
	_detect_impact()
	_prev_velocity = linear_velocity
	_sync_game(delta)


func _detect_impact() -> void:
	var impact: float = (_prev_velocity - linear_velocity).length()
	if impact < IMPACT_THRESHOLD:
		return
	_apply_impact_damage(impact)


func _is_touching_group(group_name: String) -> bool:
	var bodies: Array = get_colliding_bodies()
	for i: int in range(bodies.size()):
		var node := bodies[i] as Node
		if node != null and node.is_in_group(group_name):
			return true
	return false


func _apply_impact_damage(strength: float) -> void:
	if _i_frames > 0.0 or not Game.ship_alive:
		return
	var amount: float = _damage_from_impact(strength)
	_i_frames = I_FRAME_DURATION
	Game.apply_hull_damage(amount)


func _damage_from_impact(strength: float) -> float:
	var span: float = maxf(REFERENCE_IMPACT - IMPACT_THRESHOLD, 1.0)
	var normalized: float = clampf((strength - IMPACT_THRESHOLD) / span, 0.0, 3.0)
	var raw: float = minf(pow(normalized, DAMAGE_EXPONENT), 1.0) * MAX_HIT_DAMAGE
	return clampf(maxf(raw, 8.0), 8.0, MAX_HIT_DAMAGE)


func _sync_game(delta: float) -> void:
	Game.ship_position = global_position
	Game.ship_heading = rotation.y
	Game.ship_velocity = linear_velocity
	Game.ship_angular_velocity = angular_yaw
	Game.ship_speed = Vector3(linear_velocity.x, 0.0, linear_velocity.z).length()
	var target_throttle: float = clampf(Input.get_axis("brake", "thrust"), -1.0, 1.0)
	if Game.mission_complete:
		target_throttle = 0.0
	Game.throttle = lerpf(Game.throttle, target_throttle, clampf(delta * 6.0, 0.0, 1.0))
	visible = Game.ship_alive
	collision_layer = 4 if Game.ship_alive else 0
	Game.ship_state_changed.emit(Game.ship_position, Game.ship_heading, Game.ship_speed, Game.throttle)


func _clamp_to_sector() -> void:
	var wall: BeltData = _boundary_belt()
	if wall == null:
		return
	# 正常弹墙交给刚体；只有整艘船已经穿出外沿时才拉回，避免和物理抢位置。
	var outer_factor: float = wall.ellipse_factor(global_position, wall.outer_radius)
	if outer_factor <= 1.04:
		return
	var inner_limit: float = maxf(wall.inner_radius - Game.SHIP_RADIUS, 1.0)
	var inner_factor: float = wall.ellipse_factor(global_position, inner_limit)
	if inner_factor > 0.0001:
		global_position.x = wall.center.x + (global_position.x - wall.center.x) / inner_factor
		global_position.z = wall.center.z + (global_position.z - wall.center.z) / inner_factor
	global_position.y = 0.0
	linear_velocity = Vector3.ZERO


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
	visible = true
	hull_sprite.visible = false
	collision_layer = 4
	collision_mask = 1 | AsteroidField.COLLISION_LAYER
	sleeping = false
	freeze = false
	contact_monitor = true
	max_contacts_reported = 12
