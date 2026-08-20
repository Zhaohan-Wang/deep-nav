extends SceneTree
## 音效系统冒烟：资源、循环标记、输入边沿触发和爆炸停机。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var audio := root.get_node_or_null("GameAudio")
	assert(audio != null, "GameAudio autoload missing")
	for path: String in [
		"res://assets/audio/ui/Confirm_01.ogg",
		"res://assets/audio/ui/Denied_02.ogg",
		"res://assets/audio/gameplay/ship_impact.ogg",
		"res://assets/audio/gameplay/mission_complete.ogg",
		"res://assets/audio/gameplay/relay_reached.ogg",
		"res://assets/audio/gameplay/system_alert.ogg",
		"res://assets/audio/gameplay/ui_click.ogg",
		"res://assets/audio/gameplay/rocket_explosion.ogg",
		"res://assets/audio/gameplay/rocket_engine_loop.ogg",
		"res://assets/audio/gameplay/rocket_thrust_transition.ogg",
		"res://assets/audio/gameplay/rocket_turn_burst.ogg",
		"res://assets/audio/ambient/space_white_noise.ogg",
		"res://assets/audio/music/bgm_practice.ogg",
		"res://assets/audio/music/bgm_level_1.ogg",
		"res://assets/audio/music/bgm_level_2.ogg",
		"res://assets/audio/music/bgm_level_3.ogg",
		"res://assets/audio/music/bgm_level_4.ogg",
		"res://assets/audio/ui/ui_hover.ogg",
		"res://assets/audio/ui/ui_press.ogg",
		"res://assets/audio/ui/ui_choice.ogg",
		"res://assets/audio/ui/ui_slider_tick.ogg",
		"res://assets/audio/ui/ui_page_turn.ogg",
		"res://assets/audio/ui/ui_confirm.ogg",
		"res://assets/audio/ui/ui_popup_open.ogg",
		"res://assets/audio/ui/ui_popup_close.ogg",
	]:
		assert(load(path) is AudioStream, "audio resource missing: %s" % path)

	var engine := audio.get("_engine") as AudioStreamPlayer
	var transition := audio.get("_transition") as AudioStreamPlayer
	var turn := audio.get("_turn") as AudioStreamPlayer
	var explosion := audio.get("_explosion") as AudioStreamPlayer
	var music := audio.get("_music") as AudioStreamPlayer
	var ambient := audio.get("_ambient") as AudioStreamPlayer
	assert(engine != null and engine.stream is AudioStreamOggVorbis, "engine loop player missing")
	assert((engine.stream as AudioStreamOggVorbis).loop, "engine stream must loop")
	assert(ambient != null and ambient.stream is AudioStreamOggVorbis, "ambient player missing")
	assert((ambient.stream as AudioStreamOggVorbis).loop, "space ambience must loop")

	audio.call("start_mission_audio", "level_4")
	assert(music.playing and ambient.playing, "mission music layers did not start")
	var far_volume := ambient.volume_db
	for _i: int in 20:
		audio.call("update_ambient_proximity", 0.0, 0.1)
	assert(ambient.volume_db > far_volume, "planet proximity did not raise ambience")
	audio.call("set_gameplay_paused", true)
	assert(music.stream_paused and ambient.stream_paused, "pause did not stop long-form audio")
	audio.call("set_gameplay_paused", false)
	assert(not music.stream_paused and not ambient.stream_paused, "resume did not restore long-form audio")

	for cue: String in [
		"hover", "press", "choice", "slider_tick",
		"page_turn", "confirm", "popup_open", "popup_close",
	]:
		audio.call("play_ui_%s" % cue)
		assert(
			_pool_has_stream(audio, "res://assets/audio/ui/ui_%s.ogg" % cue),
			"UI cue did not use its assigned stream: %s" % cue
		)

	audio.call("update_ship_motion", 1.0, 0.0, 4.0, true, 0.016)
	assert(engine.playing, "thrust must start engine loop")
	assert(transition.playing, "thrust edge must trigger transition")
	assert(engine.volume_db >= -18.0, "engine loop must overlap the thrust transient immediately")
	assert(transition.volume_db >= -1.5, "thrust transient mix is too quiet")
	audio.call("update_ship_motion", 1.0, -1.0, 5.0, true, 0.016)
	assert(turn.playing, "turn edge must trigger turn burst")
	assert(turn.volume_db >= -6.0, "turn burst mix is too quiet")

	audio.call("stop_ship_motion", true)
	assert(not engine.playing and not transition.playing and not turn.playing, "hard stop leaked ship audio")
	audio.call("play_explosion")
	assert(explosion.playing, "explosion did not play")
	audio.call("play_waypoint_placed")
	audio.call("play_waypoint_denied")
	audio.call("play_ship_impact", 0.5)
	audio.call("play_relay_reached")
	audio.call("play_system_alert")
	audio.call("play_mission_complete")
	audio.call("play_ui_click")
	audio.call("stop_mission_audio", true)
	assert(not music.playing and not ambient.playing, "mission audio leaked after scene exit")
	print("AUDIO_SYSTEM_TEST_OK")
	quit(0)


func _pool_has_stream(audio: Node, path: String) -> bool:
	var expected := load(path) as AudioStream
	var players: Array = audio.get("_players")
	for player: AudioStreamPlayer in players:
		if player.playing and player.stream == expected:
			return true
	return false
