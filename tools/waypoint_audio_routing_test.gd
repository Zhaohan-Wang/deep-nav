extends SceneTree
## 航点音效专项：冷却重复点击静默，真正无效的边界请求才播放失败音。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	game.call("select_mission", "practice")
	var scene := load("res://scenes/main.tscn") as PackedScene
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var audio := root.get_node("GameAudio")
	_stop_pool(audio)
	main.call("_on_waypoint_request_result", false, "cooldown", 2.5)
	assert(not _pool_has_stream(audio, "res://assets/audio/ui/Denied_02.ogg"),
		"cooldown repetition must stay silent")

	main.call("_on_waypoint_request_result", false, "boundary", 0.0)
	assert(_pool_has_stream(audio, "res://assets/audio/ui/Denied_02.ogg"),
		"a genuinely invalid boundary request should retain the failure cue")

	main.queue_free()
	await process_frame
	print("WAYPOINT_AUDIO_ROUTING_OK cooldown=silent boundary=denied")
	quit(0)


func _stop_pool(audio: Node) -> void:
	var players: Array = audio.get("_players")
	for player: AudioStreamPlayer in players:
		player.stop()


func _pool_has_stream(audio: Node, path: String) -> bool:
	var expected := load(path) as AudioStream
	var players: Array = audio.get("_players")
	for player: AudioStreamPlayer in players:
		if player.playing and player.stream == expected:
			return true
	return false
