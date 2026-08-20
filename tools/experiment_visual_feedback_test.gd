extends SceneTree
## 正式实验模式必须持续更新镜头，并保留完整的解体视觉反馈。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	game.set("experiment_mode", true)
	game.call("select_mission", "level_1")
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in range(6):
		await process_frame

	var ship := main.get("_ship") as Node3D
	var nav_camera := main.get("_nav_camera") as Camera3D
	var pilot_camera := main.get("_pilot_camera") as Camera3D
	assert(ship != null and nav_camera != null and pilot_camera != null, "3D ship and cameras must exist")
	var nav_before := nav_camera.global_position
	var pilot_before := pilot_camera.global_position
	ship.global_position += Vector3(28.0, 0.0, -16.0)
	main.call("_process", 0.5)
	assert(nav_camera.global_position.distance_to(nav_before) > 1.0, "navigator camera stopped following in experiment mode")
	assert(pilot_camera.global_position.distance_to(pilot_before) > 1.0, "pilot camera stopped following in experiment mode")
	assert(float(main.get("_mission_elapsed")) > 0.4 and float(game.get("mission_elapsed_s")) > 0.4, "formal mission timer did not advance in experiment mode")

	main.call("_prime_explosion_visual", ship.global_position)
	main.set("_death_time", 0.0)
	main.call("_process", 0.22)
	var overlays := main.get("_death_overlays") as Array
	assert(overlays.size() == 2 and (overlays[0] as ColorRect).color.a > 0.05, "death white flash did not advance")
	var world := main.get("_world") as Node
	assert(world != null and world.find_child("ShipBurst3D", true, false) != null, "3D explosion burst was not spawned")
	print("EXPERIMENT_VISUAL_FEEDBACK_OK cameras=follow death=flash+burst")
	quit(0)
