extends SceneTree
## 后期关卡性能预算：碎石必须批量提交、不得逐颗运行脚本，静态行星不得持续重绘。

const Catalog = preload("res://scripts/mission_catalog.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	var total_rocks := 0
	var active_rocks := 0
	var decorative_rocks := 0
	var total_batches := 0
	for mission: SectorData in Catalog.all():
		game.call("select_mission",mission.id)
		var field := AsteroidField.new()
		field.setup(mission.belts,Vector3(0.42,0.62,0.48))
		root.add_child(field)
		await process_frame
		var mission_batches := 0
		for node: Node in field.get_children():
			if not node is MultiMeshInstance3D: continue
			var batch:=node as MultiMeshInstance3D
			mission_batches+=1; total_batches+=1
			total_rocks+=int(batch.get_meta("rock_count",0))
			active_rocks+=int(batch.get_meta("active_count",0))
			decorative_rocks+=int(batch.get_meta("decorative_count",0))
			assert(batch.multimesh!=null and batch.multimesh.use_custom_data,
				"rock batch must carry per-instance shader data")
			assert(batch.visibility_range_end == AsteroidField.FLIGHT_ROCK_VISIBILITY_RANGE,
				"rock batch visibility budget changed")
		assert(mission_batches<=mission.belts.size()*4,
			"%s creates too many rock draw batches (%d)" % [mission.id,mission_batches])
		assert(field.find_children("*","MeshInstance3D",true,false).all(func(node: Node) -> bool:
			var script:=node.get_script() as Script
			return script==null or not script.resource_path.ends_with("asteroid_rock.gd")),
			"per-rock process scripts must not survive MultiMesh batching")
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
	assert(belts.size() == (game.get("current_sector") as SectorData).belts.size(),
		"level 2 belt overlay cache should bake every belt once")
	overlay.queue_free()
	await process_frame
	# 运行时挂载，避免独立测试脚本在 autoload 注册前静态展开 SectorMap 的 Game 类型引用。
	var map:=Control.new()
	map.set_script(load("res://scripts/ui/sector_map.gd") as Script)
	map.size=Vector2(540.0,304.0)
	root.add_child(map)
	await process_frame
	await process_frame
	assert(map.find_child("BakedBeltLayer",true,false)!=null,
		"sector map must composite the static belts from one baked texture")
	var belt_viewport:=map.get("_belt_viewport") as SubViewport
	assert(belt_viewport!=null and belt_viewport.render_target_update_mode!=SubViewport.UPDATE_ALWAYS,
		"static belt texture must not redraw every frame")
	map.queue_free()
	await process_frame
	print("PERFORMANCE_BUDGET_OK rocks=%d batches=%d active_scripts=0 active=%d decorative=%d planets=update_once map=baked_once" % [
		total_rocks,total_batches,active_rocks,decorative_rocks,
	])
	quit(0)
