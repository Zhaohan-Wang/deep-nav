extends SceneTree
## 验证中央船体环：真实值即时下降、残影先停顿、再平滑收束；恢复时两层同步。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game:=root.get_node("Game")
	game.call("select_mission","level_1")
	var scene: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for i: int in range(5): await process_frame
	# 双显示协调器会把驾驶员页重挂到独立 Window，不能只在 Main 子树内查找。
	var ring:=_find_ring(root)
	if ring==null:
		_fail("central hull ring missing"); return
	game.set("hull",100.0); game.emit_signal("hull_changed",100.0)
	game.set("hull",64.0); game.emit_signal("hull_changed",64.0)
	if absf(ring.current_hull()-64.0)>0.01 or absf(ring.trailing_hull()-100.0)>0.01:
		_fail("damage did not separate immediate and trailing layers"); return
	await create_timer(0.16).timeout
	if ring.trailing_hull()<99.9:
		_fail("trailing layer moved before hold finished"); return
	await create_timer(0.54).timeout
	if ring.trailing_hull()<=64.0 or ring.trailing_hull()>=99.9:
		_fail("trailing layer did not visibly converge"); return
	# 连续受击必须从当前残影重启，而不能瞬移到旧目标。
	var before_second_hit: float=ring.trailing_hull()
	game.set("hull",38.0); game.emit_signal("hull_changed",38.0)
	if absf(ring.current_hull()-38.0)>0.01 or ring.trailing_hull()<before_second_hit-0.01:
		_fail("rapid hit did not restart from current trailing value"); return
	await create_timer(1.34).timeout
	if absf(ring.trailing_hull()-38.0)>0.15:
		_fail("trailing layer did not settle on real hull"); return
	game.set("hull",100.0); game.emit_signal("hull_changed",100.0)
	if absf(ring.current_hull()-100.0)>0.01 or absf(ring.trailing_hull()-100.0)>0.01:
		_fail("healing/reset did not synchronize both layers"); return
	print("HULL_RING_FEEDBACK_OK hold=0.32 duration=0.88 rapid_hit=true")
	quit(0)


func _find_ring(node: Node) -> Node:
	if node.has_method("current_hull") and node.has_method("trailing_hull"):
		return node
	for child: Node in node.get_children():
		var result:=_find_ring(child)
		if result!=null: return result
	return null


func _fail(reason: String) -> void:
	push_error("HULL_FEEDBACK_FAILED %s" % reason)
	quit(1)
