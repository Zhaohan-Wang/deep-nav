extends SceneTree
## 航点超距截断与冷却时钟的防回归检查。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	game.call("select_mission","practice")
	var ship: Vector3 = game.get("ship_position")
	var destination: CelestialBodyData = game.call("objective_body")
	assert(destination != null,"practice destination missing")
	var direction := destination.world_position-ship
	direction.y = 0.0
	direction = direction.normalized()
	var results: Array[Dictionary] = []
	game.waypoint_request_result.connect(func(accepted: bool,reason: String,remaining: float):
		results.append({"accepted":accepted,"reason":reason,"remaining":remaining})
	)
	var max_distance: float = game.get("waypoint_max_distance")
	var accepted: bool = game.call("set_waypoint",ship+direction*max_distance*4.0)
	assert(accepted,"far click should place a clamped waypoint")
	var waypoint: Vector3 = game.get("waypoint")
	var actual := waypoint-ship
	actual.y = 0.0
	assert(absf(actual.length()-max_distance)<0.01,"clamped waypoint is not on maximum range")
	assert(actual.normalized().dot(direction)>0.9999,"clamped waypoint changed click angle")
	assert(not results.is_empty() and results[-1].reason=="clamped_range","clamped placement result not reported")
	var sample_now := Time.get_ticks_msec()
	var remaining_before: float = game.call("waypoint_cooldown_remaining",sample_now)
	assert(remaining_before>0.0,"accepted waypoint did not start cooldown")
	# 使用同一时钟的两个确定采样点，避免无窗口测试以超实时速度跑帧造成计时抖动。
	var remaining_after: float = game.call("waypoint_cooldown_remaining",sample_now+250)
	assert(remaining_after<remaining_before,"cooldown UI source is not dynamically advancing")
	assert(game.call("waypoint_cooldown_display_state",sample_now)=="cooling","cooldown notice is not visible while locked")
	var cooldown_end := sample_now+int(ceil(remaining_before*1000.0))
	assert(game.call("waypoint_cooldown_display_state",cooldown_end+20)=="ready","ready notice did not turn green after cooldown")
	assert(game.call("waypoint_cooldown_display_state",cooldown_end+2020)=="hidden","ready notice did not hide after two seconds")
	assert(not game.call("set_waypoint",ship+direction*10.0),"second waypoint bypassed cooldown")
	assert(results[-1].reason=="cooldown" and results[-1].remaining>0.0,"cooldown rejection missing live remaining time")
	print("WAYPOINT_BEHAVIOR_OK clamp_distance=%.1f angle_preserved=true cooldown_dynamic=true" % max_distance)
	quit(0)
