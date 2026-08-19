extends SceneTree
## 在真实主场景和 Ship 脚本中验证：外缘扣少量耐久，核心立即触发解体。

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
	if fringe_killed or not bool(game.get("ship_alive")) or grazed_hull>=100.0 or grazed_hull<92.9:
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED fringe hull=%.2f alive=%s" % [grazed_hull,game.get("ship_alive")])
		quit(1); return

	game.set("ship_alive",true); game.set("hull",100.0)
	var core_killed: bool=ship.call("_apply_asteroid_belt_hazard",0.016,center-normal*(expanded_half+4.0),center+normal*(expanded_half+4.0))
	if not core_killed or bool(game.get("ship_alive")):
		push_error("ASTEROID_BELT_GAMEPLAY_FAILED core did not explode")
		quit(1); return
	print("ASTEROID_BELT_GAMEPLAY_OK fringe_damage=%.2f core_exploded=true" % (100.0-grazed_hull))
	quit(0)
