extends SceneTree
## 用真实 PhysicsDirectSpaceState3D 从航区内向外扫掠飞船碰撞球，逐角度寻找边界漏洞。

const Catalog = preload("res://scripts/mission_catalog.gd")
const FieldScript = preload("res://scripts/world/asteroid_field.gd")
const SHIP_RADIUS := 1.2
const ANGLE_SAMPLES := 180


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var failures: PackedStringArray = []
	for mission: SectorData in Catalog.all():
		var boundary := _boundary(mission)
		if boundary == null:
			failures.append("%s missing boundary" % mission.id)
			continue
		var host := Node3D.new()
		root.add_child(host)
		var field := Node3D.new()
		field.set_script(FieldScript)
		host.add_child(field)
		field.call("_spawn_boundary_wall",boundary)
		await physics_frame
		await physics_frame
		var sphere := SphereShape3D.new(); sphere.radius=SHIP_RADIUS
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape=sphere; query.collision_mask=8; query.collide_with_bodies=true; query.collide_with_areas=false
		var hits := 0
		for i: int in range(ANGLE_SAMPLES):
			var angle := TAU*float(i)/float(ANGLE_SAMPLES)
			var start := boundary.point_on_ring(angle,boundary.inner_radius-8.0)
			var finish := boundary.point_on_ring(angle,boundary.outer_radius+8.0)
			query.transform=Transform3D(Basis.IDENTITY,start)
			query.motion=finish-start
			var cast := host.get_world_3d().direct_space_state.cast_motion(query)
			if cast.is_empty() or cast[0]>=0.999:
				failures.append("%s boundary leak near angle %.1f°" % [mission.id,rad_to_deg(angle)])
			else:
				hits+=1
		print("BOUNDARY_SWEEP_OK %s hits=%d/%d segments=%d" % [mission.id,hits,ANGLE_SAMPLES,boundary.boundary_segment_count()])
		host.queue_free()
		await process_frame
	await _check_guard_behavior(failures)
	if not failures.is_empty():
		for failure: String in failures: push_error(failure)
		quit(1)
		return
	print("BOUNDARY_PHYSICS_OK missions=%d sweeps=%d" % [Catalog.all().size(),Catalog.all().size()*ANGLE_SAMPLES])
	quit(0)


func _boundary(mission: SectorData) -> BeltData:
	for belt: BeltData in mission.belts:
		if belt.is_boundary: return belt
	return null


func _check_guard_behavior(failures: PackedStringArray) -> void:
	var game := root.get_node_or_null("Game")
	if game == null:
		failures.append("Game autoload missing for boundary guard test")
		return
	game.call("select_mission","level_4")
	var mission: SectorData = game.get("current_sector")
	var wall := _boundary(mission)
	var ship_scene := load("res://scenes/ship.tscn") as PackedScene
	var ship := ship_scene.instantiate() as RigidBody3D
	root.add_child(ship)
	await process_frame
	ship.set_physics_process(false)
	var safe_radius := wall.inner_radius-SHIP_RADIUS
	ship.global_position=wall.point_on_ring(PI*0.5,safe_radius*0.96)
	ship.linear_velocity=Vector3(16.0,0.0,0.0)
	for i: int in range(120): ship.call("_apply_boundary_guard",1.0/60.0)
	var slide_speed := ship.linear_velocity.length()
	if slide_speed>=4.0: failures.append("boundary edge sliding stayed too fast: %.2f" % slide_speed)
	ship.global_position=wall.point_on_ring(PI*0.5,safe_radius*0.96)
	ship.linear_velocity=Vector3(0.0,0.0,16.0)
	for i: int in range(30): ship.call("_apply_boundary_guard",1.0/60.0)
	var outward_speed := ship.linear_velocity.dot(wall.outward_normal(ship.global_position,safe_radius))
	if outward_speed>=3.0: failures.append("boundary head-on guard did not cancel outward speed: %.2f" % outward_speed)
	print("BOUNDARY_GUARD_OK slide_speed=%.2f outward_speed=%.2f proximity=%.2f" % [slide_speed,outward_speed,float(game.get("boundary_proximity"))])
	ship.queue_free()
	await process_frame
