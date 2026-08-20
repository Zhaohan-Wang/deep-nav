extends SceneTree
## 后期关卡性能预算：装饰碎石不得逐帧运行，远景必须裁剪，静态行星不得持续重绘。

const Catalog = preload("res://scripts/mission_catalog.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	var total_rocks := 0
	var active_rocks := 0
	var decorative_rocks := 0
	for mission: SectorData in Catalog.all():
		game.call("select_mission",mission.id)
		var field := AsteroidField.new()
		field.setup(mission.belts,Vector3(0.42,0.62,0.48))
		root.add_child(field)
		await process_frame
		for node: Node in field.find_children("*","MeshInstance3D",true,false):
			var visual := node as MeshInstance3D
			var script := visual.get_script() as Script
			if script == null or not script.resource_path.ends_with("asteroid_rock.gd"):
				continue
			total_rocks += 1
			var hits_flight := bool(visual.get_parent().get_meta("hits_flight",false))
			if hits_flight:
				active_rocks += 1
				assert(visual.is_processing(),"flight rock lost its tumble feedback")
				assert(visual.visibility_range_end == AsteroidField.FLIGHT_ROCK_VISIBILITY_RANGE,
					"flight rock visibility budget changed")
			else:
				decorative_rocks += 1
				assert(visual.process_mode == Node.PROCESS_MODE_DISABLED,
					"decorative rock still consumes _process every frame")
				assert(visual.visibility_range_end == AsteroidField.DECORATIVE_ROCK_VISIBILITY_RANGE,
					"decorative rock visibility budget changed")
		field.queue_free()
		await process_frame

	game.call("select_mission","level_3")
	var bodies := game.get("celestial_bodies") as Array
	var largest := bodies[0] as CelestialBodyData
	for body: CelestialBodyData in bodies:
		if body.world_radius > largest.world_radius:
			largest = body
	var planet := Node3D.new()
	planet.set_script(load("res://scripts/world/planet_3d.gd") as Script)
	root.add_child(planet)
	planet.call("setup",largest)
	var viewport := planet.get("_viewport") as SubViewport
	assert(viewport.render_target_update_mode == SubViewport.UPDATE_ONCE,
		"static planet viewport must not redraw continuously")
	planet.queue_free()
	await process_frame

	assert(total_rocks > 0 and decorative_rocks > active_rocks,
		"performance fixture no longer covers the heavy decorative layer")
	game.call("select_mission","level_2")
	var overlay := Control.new()
	overlay.set_script(load("res://scripts/ui/sector_map_overlay.gd") as Script)
	root.add_child(overlay)
	overlay.call("_ensure_belt_cache")
	var belts := overlay.get("_belt_cache") as Array
	assert(belts.size() == 5, "level 2 belt overlay cache should bake every belt once")
	overlay.queue_free()
	await process_frame
	print("PERFORMANCE_BUDGET_OK rocks=%d active=%d decorative=%d planets=update_once map=full_rate_cached" % [
		total_rocks,active_rocks,decorative_rocks,
	])
	quit(0)
