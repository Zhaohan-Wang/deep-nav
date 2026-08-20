extends SceneTree
## 在真实主场景和 Ship 脚本中验证：外缘缓慢磨损，只有深入穿越核心才立即解体。

const Hazard=preload("res://scripts/belt_hazard.gd")
const SHIP_RADIUS:=1.2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game:=root.get_node("Game")
	game.call("select_mission","level_1")
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i: int in range(5): await process_frame
	var ship:=scene.get_node("SpaceWorld/Ship") as Node3D
	var sector: SectorData=game.get("current_sector")
	var belt: BeltData=null
	for candidate: BeltData in sector.belts:
		if not candidate.is_boundary:
			belt=candidate; break
	if ship==null or belt==null:
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED setup")
		quit(1); return

	var angle:=0.73
	var inner:=belt.point_on_ring(angle,belt.inner_radius)
	var outer:=belt.point_on_ring(angle,belt.outer_radius)
	var center:=(inner+outer)*0.5
	var normal:=(outer-inner).normalized()
	var expanded_half:=inner.distance_to(outer)*0.5+SHIP_RADIUS
	var fringe:=center+normal*(expanded_half*0.76)
	if Hazard.classify(Hazard.penetration_fraction(fringe,belt,SHIP_RADIUS))!=Hazard.Exposure.GRAZE:
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED fringe geometry")
		quit(1); return

	game.set("ship_alive",true); game.set("mission_complete",false); game.set("hull",100.0)
	var fringe_killed: bool=ship.call("_apply_asteroid_belt_hazard",0.016,fringe,fringe)
	var grazed_hull: float=float(game.get("hull"))
	var fringe_tick_damage:=100.0-grazed_hull
	if fringe_killed or not bool(game.get("ship_alive")) or fringe_tick_damage<0.8 or fringe_tick_damage>2.5:
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED fringe hull=%.2f alive=%s" % [grazed_hull,game.get("ship_alive")])
		quit(1); return

	# 约三秒持续贴边仍应给玩家充分撤离时间，不能像旧参数一样迅速清空船体。
	game.set("hull",100.0)
	for tick: int in range(8):
		ship.set("_belt_graze_cooldown",0.0)
		ship.call("_apply_asteroid_belt_hazard",0.42,fringe,fringe)
	var sustained_damage:=100.0-float(game.get("hull"))
	if not bool(game.get("ship_alive")) or sustained_damage<6.0 or sustained_damage>20.0:
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED sustained fringe damage=%.2f" % sustained_damage)
		quit(1); return

	# 已经明显深入、但尚未抵达中心线的区域仍是警告区，不应提前判为穿越。
	var deep_graze:=center+normal*(expanded_half*(1.0-(Hazard.CORE_FRACTION-0.04)))
	if Hazard.classify(Hazard.penetration_fraction(deep_graze,belt,SHIP_RADIUS))!=Hazard.Exposure.GRAZE:
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED deep graze geometry")
		quit(1); return
	game.set("ship_alive",true); game.set("hull",100.0); ship.set("_belt_graze_cooldown",0.0)
	var deep_graze_killed: bool=ship.call("_apply_asteroid_belt_hazard",0.016,deep_graze,deep_graze)
	if deep_graze_killed or not bool(game.get("ship_alive")):
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED deep graze exploded early")
		quit(1); return

	game.set("ship_alive",true); game.set("hull",100.0)
	var core_killed: bool=ship.call("_apply_asteroid_belt_hazard",0.016,center-normal*(expanded_half+4.0),center+normal*(expanded_half+4.0))
	if not core_killed or bool(game.get("ship_alive")):
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED core did not explode")
		quit(1); return
	print("ASTEROID_BELT_GAMEPLAY_OK fringe_tick=%.2f sustained_3s=%.2f core_at=%.2f core_exploded=true" % [
		fringe_tick_damage,sustained_damage,Hazard.CORE_FRACTION
	])
	quit(0)
