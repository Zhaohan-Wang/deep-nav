extends Node
## 全局游戏音效：短音效并发池，以及按驾驶输入分层的火箭推进声。

const PLAYER_COUNT: int = 8
const INPUT_DEADZONE: float = 0.12
const ENGINE_SILENT_DB: float = -48.0
const ENGINE_STOP_DB: float = -42.0
const ENGINE_ATTACK_DB_PER_S: float = 50.0
const ENGINE_RELEASE_DB_PER_S: float = 34.0
const TRANSITION_CROSSFADE_S: float = 0.18
const TRANSITION_ENGINE_DUCK_DB: float = 2.0
const ENGINE_START_DB: float = -18.0
const IMPACT_COOLDOWN_MS: int = 90
const UI_COOLDOWN_MS: int = 45
const AMBIENT_FAR_DB: float = -9.0
const AMBIENT_NEAR_DB: float = -2.0
const AMBIENT_NEAR_GAP: float = 14.0
const AMBIENT_FAR_GAP: float = 100.0
const AMBIENT_ATTACK_DB_PER_S: float = 3.0
const AMBIENT_RELEASE_DB_PER_S: float = 1.5

const WAYPOINT_PLACED: AudioStream = preload("res://assets/audio/ui/Confirm_01.ogg")
const WAYPOINT_DENIED: AudioStream = preload("res://assets/audio/ui/Denied_02.ogg")
const SHIP_IMPACT: AudioStream = preload("res://assets/audio/gameplay/ship_impact.ogg")
const MISSION_COMPLETE: AudioStream = preload("res://assets/audio/gameplay/mission_complete.ogg")
const RELAY_REACHED: AudioStream = preload("res://assets/audio/gameplay/relay_reached.ogg")
const SYSTEM_ALERT: AudioStream = preload("res://assets/audio/gameplay/system_alert.ogg")
const UI_CLICK: AudioStream = preload("res://assets/audio/gameplay/ui_click.ogg")
const UI_HOVER: AudioStream = preload("res://assets/audio/ui/ui_hover.ogg")
const UI_PRESS: AudioStream = preload("res://assets/audio/ui/ui_press.ogg")
const UI_CHOICE: AudioStream = preload("res://assets/audio/ui/ui_choice.ogg")
const UI_SLIDER_TICK: AudioStream = preload("res://assets/audio/ui/ui_slider_tick.ogg")
const UI_PAGE_TURN: AudioStream = preload("res://assets/audio/ui/ui_page_turn.ogg")
const UI_CONFIRM: AudioStream = preload("res://assets/audio/ui/ui_confirm.ogg")
const UI_POPUP_OPEN: AudioStream = preload("res://assets/audio/ui/ui_popup_open.ogg")
const UI_POPUP_CLOSE: AudioStream = preload("res://assets/audio/ui/ui_popup_close.ogg")
const ROCKET_EXPLOSION: AudioStream = preload("res://assets/audio/gameplay/rocket_explosion.ogg")
const ROCKET_ENGINE: AudioStreamOggVorbis = preload("res://assets/audio/gameplay/rocket_engine_loop.ogg")
const ROCKET_TRANSITION: AudioStream = preload("res://assets/audio/gameplay/rocket_thrust_transition.ogg")
const ROCKET_TURN: AudioStream = preload("res://assets/audio/gameplay/rocket_turn_burst.ogg")
const SPACE_AMBIENCE: AudioStreamOggVorbis = preload("res://assets/audio/ambient/space_white_noise.ogg")
const MISSION_MUSIC: Dictionary = {
	"practice": preload("res://assets/audio/music/bgm_practice.ogg"),
	"level_1": preload("res://assets/audio/music/bgm_level_1.ogg"),
	"level_2": preload("res://assets/audio/music/bgm_level_3.ogg"),
	"level_3": preload("res://assets/audio/music/bgm_level_4.ogg"),
}
const MISSION_MUSIC_DB: Dictionary = {
	"practice": -11.0,
	"level_1": -10.5,
	"level_2": -9.5,
	"level_3": -9.0,
}

var _players: Array[AudioStreamPlayer] = []
var _engine: AudioStreamPlayer
var _transition: AudioStreamPlayer
var _turn: AudioStreamPlayer
var _explosion: AudioStreamPlayer
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _music_tween: Tween
var _ambient_tween: Tween
var _next_player: int = 0
var _last_thrust_sign: int = 0
var _last_turn_sign: int = 0
var _engine_crossfade_left: float = 0.0
var _last_impact_ms: int = -1000
var _last_ui_sound_ms: Dictionary = {}
var _mission_audio_active: bool = false
var _ambient_resume_position: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index: int in PLAYER_COUNT:
		var player := _new_player("Sfx%02d" % (index + 1))
		_players.append(player)
	_engine = _new_player("RocketEngine")
	var loop_stream := ROCKET_ENGINE.duplicate() as AudioStreamOggVorbis
	loop_stream.loop = true
	_engine.stream = loop_stream
	_engine.volume_db = ENGINE_SILENT_DB
	_transition = _new_player("RocketTransition")
	_transition.stream = ROCKET_TRANSITION
	_turn = _new_player("RocketTurn")
	_turn.stream = ROCKET_TURN
	_explosion = _new_player("RocketExplosion")
	_explosion.stream = ROCKET_EXPLOSION
	_music = _new_player("MissionMusic")
	_ambient = _new_player("SpaceAmbience")
	var ambient_loop := SPACE_AMBIENCE.duplicate() as AudioStreamOggVorbis
	ambient_loop.loop = true
	_ambient.stream = ambient_loop
	_ambient.volume_db = AMBIENT_FAR_DB


func _new_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = "Master"
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


func start_mission_audio(mission_id: String) -> void:
	stop_mission_audio(true)
	var stream := MISSION_MUSIC.get(mission_id) as AudioStream
	if stream != null:
		_music.stream = stream
		_music.volume_db = -36.0
		_music.stream_paused = false
		_music.play()
		_music_tween = create_tween()
		_music_tween.tween_property(
			_music,
			"volume_db",
			float(MISSION_MUSIC_DB.get(mission_id, -7.0)),
			1.8
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_ambient.volume_db = AMBIENT_FAR_DB
	_ambient.stream_paused = false
	_ambient.play(_ambient_resume_position)
	_mission_audio_active = true


## 距离使用飞船外壳到最近天体表面的间隙；远处可闻，贴近时平滑增加 7 dB。
func update_ambient_proximity(nearest_surface_gap: float, delta: float) -> void:
	if not _mission_audio_active or _ambient_tween != null or not _ambient.playing or _ambient.stream_paused:
		return
	var gap := clampf(nearest_surface_gap, AMBIENT_NEAR_GAP, AMBIENT_FAR_GAP)
	var proximity := 1.0 - smoothstep(AMBIENT_NEAR_GAP, AMBIENT_FAR_GAP, gap)
	var target_db := lerpf(AMBIENT_FAR_DB, AMBIENT_NEAR_DB, proximity)
	var rate := AMBIENT_ATTACK_DB_PER_S if target_db > _ambient.volume_db else AMBIENT_RELEASE_DB_PER_S
	_ambient.volume_db = move_toward(_ambient.volume_db, target_db, rate * delta)


func finish_mission_audio() -> void:
	stop_ship_motion()
	if _music_tween != null:
		_music_tween.kill()
	if _music.playing:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", -38.0, 1.2) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		_music_tween.tween_callback(_music.stop)
	# 结果页仍保留很弱的空间底噪，直到离开任务场景。
	if _ambient_tween != null:
		_ambient_tween.kill()
	_ambient_tween = create_tween()
	_ambient_tween.tween_property(_ambient, "volume_db", AMBIENT_FAR_DB, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func set_gameplay_paused(paused: bool) -> void:
	if paused:
		stop_ship_motion(true)
	if _music != null and (_music.playing or _music.stream_paused):
		_music.stream_paused = paused
	if _ambient != null and (_ambient.playing or _ambient.stream_paused):
		_ambient.stream_paused = paused


func stop_mission_audio(immediate: bool = true) -> void:
	_mission_audio_active = false
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null
	if _ambient_tween != null:
		_ambient_tween.kill()
		_ambient_tween = null
	if _ambient != null and _ambient.playing:
		_ambient_resume_position = _ambient.get_playback_position()
		_ambient.stop()
	if _music != null:
		if immediate:
			_music.stop()
		else:
			_music.volume_db = -38.0
			_music.stop()
		_music.stream = null
	if _ambient != null:
		_ambient.stream_paused = false
	if _music != null:
		_music.stream_paused = false


## 推进声代表座舱内由结构传导的振动；音量主要跟推力指令走，速度只做轻微修饰。
func update_ship_motion(
	thrust_axis: float,
	turn_axis: float,
	speed: float,
	active: bool,
	delta: float
) -> void:
	var thrust := clampf(thrust_axis, -1.0, 1.0) if active else 0.0
	var turn_input := clampf(turn_axis, -1.0, 1.0) if active else 0.0
	if absf(thrust) < INPUT_DEADZONE:
		thrust = 0.0
	if absf(turn_input) < INPUT_DEADZONE:
		turn_input = 0.0

	var thrust_sign := _axis_sign(thrust)
	if thrust_sign != 0 and thrust_sign != _last_thrust_sign:
		_play_thrust_transition(thrust_sign)
		_engine_crossfade_left = TRANSITION_CROSSFADE_S
	_last_thrust_sign = thrust_sign

	var turn_sign := _axis_sign(turn_input)
	if turn_sign != 0 and turn_sign != _last_turn_sign:
		_turn.stop()
		_turn.volume_db = -6.0
		_turn.pitch_scale = 0.97 if turn_sign < 0 else 1.03
		_turn.play()
	_last_turn_sign = turn_sign

	_engine_crossfade_left = maxf(0.0, _engine_crossfade_left - delta)
	_update_engine_loop(thrust, speed, delta)


func _update_engine_loop(thrust: float, speed: float, delta: float) -> void:
	var power := absf(thrust)
	if power <= 0.0:
		_engine.volume_db = move_toward(
			_engine.volume_db, ENGINE_SILENT_DB, ENGINE_RELEASE_DB_PER_S * delta
		)
		if _engine.volume_db <= ENGINE_STOP_DB and _engine.playing:
			_engine.stop()
		return

	if not _engine.playing:
		# 起步瞬态与循环推进是叠加层；循环声从按键首帧即清晰进入。
		_engine.volume_db = ENGINE_START_DB
		_engine.play()
	var speed_mix := clampf(speed / maxf(Game.MAX_SPEED, 1.0), 0.0, 1.0)
	var target_db := lerpf(-12.0, -5.5, power) + speed_mix * 1.5
	if thrust < 0.0:
		target_db -= 2.0
	if _engine_crossfade_left > 0.0:
		# 只留轻微余量给瞬态，不再把常态引擎压成“随后才出现”的听感。
		target_db -= lerpf(
			0.0,
			TRANSITION_ENGINE_DUCK_DB,
			_engine_crossfade_left / TRANSITION_CROSSFADE_S
		)
	var rate := ENGINE_ATTACK_DB_PER_S if target_db > _engine.volume_db else ENGINE_RELEASE_DB_PER_S
	_engine.volume_db = move_toward(_engine.volume_db, target_db, rate * delta)
	var base_pitch := 0.84 if thrust < 0.0 else 0.94
	_engine.pitch_scale = base_pitch + power * 0.08 + speed_mix * 0.03


func _play_thrust_transition(direction: int) -> void:
	_transition.stop()
	_transition.volume_db = -1.5 if direction > 0 else -3.5
	_transition.pitch_scale = 1.0 if direction > 0 else 0.84
	_transition.play()


func stop_ship_motion(immediate: bool = false) -> void:
	_last_thrust_sign = 0
	_last_turn_sign = 0
	_engine_crossfade_left = 0.0
	_transition.stop()
	_turn.stop()
	if immediate:
		_engine.stop()
		_engine.volume_db = ENGINE_SILENT_DB


func play_waypoint_placed() -> void:
	_play(WAYPOINT_PLACED, 0.0, 1.0)


func play_waypoint_denied() -> void:
	_play(WAYPOINT_DENIED, 0.0, 1.0)


func play_ship_impact(hull_fraction: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_impact_ms < IMPACT_COOLDOWN_MS:
		return
	_last_impact_ms = now
	var damage_mix := 1.0 - clampf(hull_fraction, 0.0, 1.0)
	_play(SHIP_IMPACT, lerpf(-7.0, -3.0, damage_mix), lerpf(1.05, 0.90, damage_mix))


func play_explosion() -> void:
	stop_ship_motion(true)
	_explosion.stop()
	_explosion.volume_db = -1.5
	_explosion.pitch_scale = randf_range(0.97, 1.02)
	_explosion.play()


func play_mission_complete() -> void:
	stop_ship_motion()
	_play(MISSION_COMPLETE, 2.0, 1.0)


func play_relay_reached() -> void:
	_play(RELAY_REACHED, -6.0, 1.0)


func play_system_alert() -> void:
	_play(SYSTEM_ALERT, -7.5, 1.0)


func play_ui_click() -> void:
	play_ui_press()


func play_ui_hover() -> void:
	_play_ui_cue("hover", UI_HOVER, -13.0, randf_range(0.99, 1.02), 70)


func play_ui_press() -> void:
	_play_ui_cue("press", UI_PRESS, -5.0, randf_range(0.99, 1.01), UI_COOLDOWN_MS)


func play_ui_choice() -> void:
	_play_ui_cue("choice", UI_CHOICE, -4.0, 1.0, 55)


func play_ui_slider_tick() -> void:
	_play_ui_cue("slider_tick", UI_SLIDER_TICK, -10.0, randf_range(0.98, 1.02), 42)


func play_ui_page_turn() -> void:
	_play_ui_cue("page_turn", UI_PAGE_TURN, -4.5, 1.0, 90)


func play_ui_confirm() -> void:
	_play_ui_cue("confirm", UI_CONFIRM, -3.0, 1.0, 100)


func play_ui_popup_open() -> void:
	_play_ui_cue("popup_open", UI_POPUP_OPEN, -4.0, 1.0, 100)


func play_ui_popup_close() -> void:
	_play_ui_cue("popup_close", UI_POPUP_CLOSE, -4.0, 1.0, 100)


func _play_ui_cue(
	cue: String,
	stream: AudioStream,
	volume_db: float,
	pitch_scale: float,
	cooldown_ms: int
) -> void:
	var now := Time.get_ticks_msec()
	var previous := int(_last_ui_sound_ms.get(cue, -1000))
	if now - previous < cooldown_ms:
		return
	_last_ui_sound_ms[cue] = now
	_play(stream, volume_db, pitch_scale)


func _play(stream: AudioStream, volume_db: float, pitch_scale: float) -> void:
	if stream == null or _players.is_empty():
		return
	var player := _find_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()


func _find_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _players:
		if not player.playing:
			return player
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stop()
	return player


func _axis_sign(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0


func _exit_tree() -> void:
	stop_ship_motion(true)
	stop_mission_audio(true)
	for player: AudioStreamPlayer in _players:
		player.stop()
