extends SceneTree
## 单次应用运行内的顺序任务进度：仅当前关可玩，玩完即锁定并推进；新流程归零。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("/root/Game")
	var catalog = load("res://scripts/mission_catalog.gd")
	game.set("experiment_mode",true)
	game.begin_mission_sequence()
	assert(game.active_mission_id() == "practice","new sequence must start at practice")
	assert(game.can_play_mission("practice"),"practice must be the only initial playable mission")
	for id: String in catalog.IDS:
		if id != "practice":
			assert(not game.can_play_mission(id),"%s must start locked" % id)
	await _assert_page_state(0)

	for i: int in range(catalog.IDS.size()):
		var id: String = catalog.IDS[i]
		assert(game.active_mission_id() == id,"sequence skipped %s" % id)
		game.select_mission(id)
		game.mark_current_mission_played("完成" if i % 2 == 0 else "超时未完成")
		assert(game.mission_session_status(id) == "completed","played mission must close regardless of outcome")
		assert(not game.can_play_mission(id),"played mission must never be replayable")
		if i + 1 < catalog.IDS.size():
			var next_id: String = catalog.IDS[i + 1]
			assert(game.active_mission_id() == next_id,"next mission did not unlock")
			assert(game.can_play_mission(next_id),"next mission must be the only playable mission")
			await _assert_page_state(i + 1)

	assert(game.active_mission_id().is_empty(),"sequence must end after the final mission")
	await _assert_page_state(-1)

	game.begin_mission_sequence()
	assert(game.active_mission_id() == "practice","new sequence must clear temporary progress")
	assert(game.session_mission_results.is_empty(),"temporary results must reset with a new sequence")
	game.set("experiment_mode",false)
	assert(game.unlock_all_missions(),"preview mode must open every mission")
	assert(game.can_play_mission("level_4"),"turning experiment mode off must make every catalog mission playable")
	var free_page := (load("res://scenes/level_select.tscn") as PackedScene).instantiate()
	root.add_child(free_page)
	await process_frame
	await process_frame
	var free_cards: Array = free_page.get("_cards")
	for card: Variant in free_cards:
		assert(not (card as Button).disabled,"preview mode must keep all mission cards enabled")
	assert(not (free_page.get("_launch_button") as Button).disabled,"preview mode must keep launch available")
	free_page.queue_free()
	await process_frame
	print("SESSION_PROGRESS_OK missions=%d sequential=experiment free_play=preview" % catalog.IDS.size())
	quit(0)


func _assert_page_state(active_index: int) -> void:
	var page := (load("res://scenes/level_select.tscn") as PackedScene).instantiate()
	root.add_child(page)
	await process_frame
	await process_frame
	var cards: Array = page.get("_cards")
	assert(cards.size() == 5,"mission progress rail must show all five stages")
	var enabled_count := 0
	for i: int in range(cards.size()):
		var card := cards[i] as Button
		if not card.disabled:
			enabled_count += 1
			assert(i == active_index,"wrong mission card is enabled")
	assert(enabled_count == (0 if active_index < 0 else 1),"exactly one mission must be enabled while sequence is active")
	var launch := page.get("_launch_button") as Button
	assert(launch.disabled == (active_index < 0),"launch availability must follow the active mission")
	page.queue_free()
	await process_frame
