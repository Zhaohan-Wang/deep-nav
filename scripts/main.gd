extends Node
## 左右分屏。3D 世界挂在主场景，两个 SubViewport 共用同一套世界与各自相机。

const SurveyPanelScript = preload("res://scripts/ui/survey_panel.gd")
const ExperimentReviewPanelScript = preload("res://scripts/ui/experiment_review_panel.gd")
const MissionAttributionPanelScript = preload("res://scripts/ui/mission_attribution_panel.gd")
const MissionResultPanelScript = preload("res://scripts/ui/mission_result_panel.gd")
const PauseMenuScript = preload("res://scripts/ui/pause_menu.gd")
const TutorialOverlayScript = preload("res://scripts/ui/tutorial_overlay.gd")

const VIEW_SIZE := Vector2i(640, 360)
const VIEW_FOV: float = 64.0
## 驾驶员比领航员更窄，窗口里放大一点，少看到全景。
const PILOT_FOV: float = 50.0
const VIEW_NEAR: float = 0.12
const VIEW_FAR: float = 3600.0
const NAV_ARM_BACK: float = 16.0
const NAV_ARM_UP: float = 9.0
const NAV_LOOK_HEIGHT: float = 1.35
const NAV_ARM_MIN: float = 4.2
const CAMERA_PROBE_RADIUS: float = 0.75
const CAMERA_OBSTACLE_MASK: int = 1 | 8
const NAV_FOCUS_PADDING: float = 0.35
const PILOT_FOCUS_AHEAD: float = 26.0
const NAV_ARM_FOLLOW: float = 7.2
## 离致死行星表面小于此距离时开始接近警告。
const PROXIMITY_WARN_DISTANCE: float = 14.0
## 解体白屏关键帧（时间秒 → 白度）：闪两下 → 停纯白 → 快淡出。
const DEATH_CURVE: Array[Vector2] = [
	Vector2(0.00, 0.0),
	Vector2(0.07, 0.85),
	Vector2(0.16, 0.08),
	Vector2(0.25, 0.92),
	Vector2(0.34, 0.10),
	Vector2(0.50, 1.0),
	Vector2(1.00, 1.0),
	Vector2(1.20, 0.0),
]
## 纯白保持期间把船传回出生点（玩家看不到瞬移）。
const DEATH_RESET_TIME: float = 0.58
const HID_KEY_ESCAPE: int = 0x29
const PAUSE_TOGGLE_DEBOUNCE_MS: int = 180
## 客观事件锚点：移动中持续背离当前航点才计数，短暂转弯不算严重偏离。
const SEVERE_HEADING_ENTER_RAD := deg_to_rad(60.0)
const SEVERE_HEADING_EXIT_RAD := deg_to_rad(40.0)
const SEVERE_HEADING_MIN_S := 2.0
const SEVERE_HEADING_MIN_SPEED := 3.0
const SEVERE_HEADING_MIN_WAYPOINT_DISTANCE := 8.0
const FLIGHT_TRAIL_SAMPLE_S := 0.12
const FLIGHT_TRAIL_POINT_CAP := 1800
## 第三关的航点异常不使用固定角度。每次触发独立抽取方向和幅度；
## 24° 已明显高于旧版 13°，36° 则保留足够强的异常感但不直接反转航向。
const WAYPOINT_DRIFT_MIN_DEG := 24.0
const WAYPOINT_DRIFT_MAX_DEG := 36.0
const WAYPOINT_DRIFT_STEP_DEG := 0.5

var _world: Node3D
var _ship: Ship
var _pilot_camera: Camera3D
var _nav_camera: Camera3D
var _nav_viewport: SubViewport
var _pilot_viewport: SubViewport
var _navigator_view: NavigatorView
var _pilot_view: PilotView
var _nav_slot: Control
var _pilot_slot: Control
var _split: HBoxContainer
var _bezel: ColorRect
var _extra_window: Window
var _root_ui: Control
var _shake: CameraShake = CameraShake.new()
var _restarting: bool = false
var _nav_view_mat: ShaderMaterial
var _pilot_view_mat: ShaderMaterial
var _hurt_flash: float = 0.0
## 受击瞬间的灯光过载，快速衰减。
var _light_flash: float = 0.0
## 接近警告当前强度（0..1，随距离渐入渐出）与闪烁相位。
var _warn_level: float = 0.0
var _warn_phase: float = 0.0
## >= 0 表示解体白屏序列进行中（累计时间）。
var _death_time: float = -1.0
## 只盖左右两块 16:9 屏幕（含各自 UI），不盖窗外黑边。
var _death_overlays: Array[ColorRect] = []
var _hit_hitching: bool = false
var _nav_fog_mat: ShaderMaterial
var _pilot_fog_mat: ShaderMaterial
var _nav_arm_offset: Vector3 = Vector3.ZERO
var _camera_probe: SphereShape3D
var _camera_probe_query: PhysicsShapeQueryParameters3D
var _mission_elapsed: float = 0.0
var _active_gameplay_elapsed: float = 0.0
var _mission_terminal_session_ms: float = 0.0
var _mission_deaths: int = 0
var _mission_hits: int = 0
var _mission_waypoints: int = 0
var _mission_waypoint_requests: int = 0
var _mission_rejected_waypoints: int = 0
var _mission_damage_taken: float = 0.0
var _last_hull_for_damage: float = Game.MAX_HULL
var _mission_path_length: float = 0.0
var _path_last_position: Vector3 = Vector3.ZERO
var _severe_heading_deviations: int = 0
var _heading_deviation_candidate_s: float = 0.0
var _heading_deviation_active: bool = false
var _waypoint_drift_events: int = 0
var _ship_shear_events: int = 0
var _mission_finishing: bool = false
var _mission_ended: bool = false
var _mission_outcome: String = ""
var _mission_summary: Dictionary = {}
var _survey_answers: Dictionary = {}
var _mission_attribution_answers: Dictionary = {}
var _review_transitioning := false
var _result_panels: Array[Control] = []
var _pause_menus: Array[Control] = []
var _tutorial_overlays: Array[Control] = []
var _last_pause_toggle_ms: int = -1000
var _pause_scene_transitioning: bool = false
var _target_event_record: Dictionary = {}
var _target_event_written := false
var _target_event_elapsed_s := 0.0
var _target_event_gate_index := -1
var _target_recovery_hold_s := 0.0
var _active_waypoint_record: Dictionary = {}
var _waypoint_elapsed_s := 0.0
var _alignment_hold_s := 0.0
var _override_hold_s := 0.0
var _last_waypoint_heading_error := 0.0
var _flight_trail := PackedVector2Array()
var _failed_flight_trails: Array[PackedVector2Array] = []
var _collision_points := PackedVector2Array()
var _flight_trail_timer := 0.0
var _target_event_peak_position: Variant = null
var _target_event_positions := PackedVector2Array()
var _waypoint_drift_rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_waypoint_drift_rng.randomize()
	var attempt_number := Game.note_mission_attempt()
	ExperimentLog.begin_mission_attempt(attempt_number)
	_bind_inputs()
	_build_ui()
	_build_world_and_cameras()
	Game.waypoint_changed.connect(_on_waypoint_sfx)
	Game.ship_exploded.connect(_on_ship_exploded)
	Game.destination_reached.connect(_on_complete_sfx)
	Game.view_mode_changed.connect(_apply_view_mode)
	Game.ship_hit.connect(_on_ship_hit)
	Game.destination_reached.connect(_on_mission_success)
	Game.waypoint_request_result.connect(_on_waypoint_request_result)
	Game.disturbance_gate_crossed.connect(_on_disturbance_gate_crossed)
	Game.disturbance_effect_applied.connect(_on_disturbance_effect_applied)
	Game.safe_gate_crossed.connect(_on_safe_gate_crossed)
	Game.relay_station_reached.connect(_on_relay_station_reached)
	Displays.roles_swapped.connect(_on_display_roles_swapped)
	Displays.shared_key_input.connect(_on_shared_key_input)
	RawMice.key_changed.connect(_on_raw_keyboard_key)
	# 双屏贯穿整个应用；单显示器环境也保留两个并排窗口用于开发预览。
	Game.set_view_mode(Game.ViewMode.DUAL_WINDOW)
	Game.mission_elapsed_s = 0.0
	Game.mission_time_limit_s = Game.current_sector.time_limit_s if Game.current_sector != null else 0.0
	Game.mission_timer_active = _mission_timer_enabled()
	_last_hull_for_damage = Game.hull
	_path_last_position = Game.ship_position
	_flight_trail.append(_world_to_trail(Game.ship_position))
	if Game.current_sector != null:
		GameAudio.start_mission_audio(Game.current_sector.id)


func _exit_tree() -> void:
	# 双屏席位会临时挂到常驻 Displays 节点；场景退出前必须先收回来，
	# 否则重复进关或串行性能测试会把上一关的整套 UI 留在副窗口继续渲染。
	_close_extra_window()
	GameAudio.stop_ship_motion(true)
	GameAudio.stop_mission_audio(true)
	if get_tree() != null and get_tree().paused:
		get_tree().paused = false


func _process(delta: float) -> void:
	if _ship == null or _nav_camera == null or _pilot_camera == null:
		return
	if get_tree().paused:
		return
	var ship_audio_active := (
		Game.ship_alive and not _restarting and not _mission_finishing and not _mission_ended
	)
	GameAudio.update_ship_motion(
		Displays.pilot_thrust_axis(),
		Displays.pilot_turn_axis(),
		_ship.linear_velocity.length(),
		ship_audio_active,
		delta
	)
	GameAudio.update_ambient_proximity(_nearest_body_surface_gap(), delta)
	var shake: Vector3 = _shake.tick(delta) if Game.screen_shake_enabled else Vector3.ZERO
	_hurt_flash = move_toward(_hurt_flash, 0.0, delta * 2.4)
	# 受击红光带一点频闪，比匀速淡出更像灯光故障。
	var flicker: float = 0.72 + 0.28 * sin(float(Time.get_ticks_msec()) * 0.055)
	_set_hurt_flash(_hurt_flash * (flicker if _hurt_flash > 0.01 else 1.0))
	_light_flash = move_toward(_light_flash, 0.0, delta * 4.5)
	_set_view_param("light_flash", _light_flash)
	_update_proximity_warning(delta)
	_update_death_flash(delta)
	_update_nav_camera(delta, shake)
	_pilot_camera.global_transform = _ship.pilot_mount.global_transform
	_pilot_camera.global_position += _pilot_camera.global_transform.basis.x * shake.x
	_pilot_camera.global_position += _pilot_camera.global_transform.basis.y * shake.y
	_pilot_camera.rotation_degrees.z = shake.x * 4.5
	_apply_ship_focus(_nav_camera, _nav_fog_mat, _nav_camera.global_position.distance_to(_ship.global_position) + NAV_FOCUS_PADDING)
	_apply_ship_focus(_pilot_camera, _pilot_fog_mat, PILOT_FOCUS_AHEAD)
	if not _mission_ended and not _mission_finishing:
		# 训练关虽然不显示倒计时，仍需保留真实有效操作时长；短暂慢动作也不能让实验时钟变慢。
		var active_delta := delta/maxf(Engine.time_scale,0.05)
		if Game.ship_alive and not _restarting:
			_active_gameplay_elapsed += active_delta
		if _mission_timer_enabled():
			_mission_elapsed += active_delta
			Game.mission_elapsed_s = _mission_elapsed
			if _mission_elapsed >= Game.current_sector.time_limit_s:
				_mission_elapsed = Game.current_sector.time_limit_s
				_begin_mission_end("超时未完成",false)


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	_track_severe_heading_deviation(delta)
	_sample_flight_trail(delta)
	var active_delta := delta/maxf(Engine.time_scale,0.05)
	_update_mission_path_length()
	_update_waypoint_response(active_delta)
	_update_target_event_window(active_delta)
	ExperimentLog.sample_frame()


func _update_mission_path_length() -> void:
	var current := Game.ship_position
	if (_mission_ended or _mission_finishing or _restarting or not Game.ship_alive):
		_path_last_position = current
		return
	var step := current.distance_to(_path_last_position)
	# 复活和场景初始化造成的是位置跳转，不是玩家实际飞过的路径。
	if step <= 25.0:
		_mission_path_length += step
	_path_last_position = current


func _current_waypoint_heading_error_deg() -> float:
	if not Game.has_waypoint:
		return -1.0
	var to_waypoint := Game.waypoint-Game.ship_position
	to_waypoint.y = 0.0
	if to_waypoint.length_squared() <= 0.0001:
		return -1.0
	return rad_to_deg(absf(wrapf(atan2(-to_waypoint.x,-to_waypoint.z)-Game.ship_heading,-PI,PI)))


func _current_route_cross_track_error() -> float:
	if Game.current_sector == null:
		return -1.0
	var route := Game.current_sector.route_checkpoints
	if route.size() < 2:
		return -1.0
	var nearest := INF
	for i: int in range(route.size()-1):
		var a: Vector3 = route[i]
		var ab: Vector3 = route[i+1]-a
		var t := clampf((Game.ship_position-a).dot(ab)/maxf(ab.length_squared(),0.0001),0.0,1.0)
		nearest = minf(nearest,Game.ship_position.distance_to(a+ab*t))
	return nearest if nearest<INF else -1.0


func _update_waypoint_response(delta: float) -> void:
	if _active_waypoint_record.is_empty():
		return
	_waypoint_elapsed_s += delta
	_active_waypoint_record["response_window_observed_ms"] = _waypoint_elapsed_s*1000.0
	var heading_error := _current_waypoint_heading_error_deg()
	if heading_error >= 0.0:
		_last_waypoint_heading_error = heading_error
		if (_waypoint_elapsed_s >= 3.0
				and not _active_waypoint_record.has("heading_error_reduction_3s_deg")):
			_active_waypoint_record["heading_error_reduction_3s_deg"] = (
				float(_active_waypoint_record.get("initial_heading_error_deg",heading_error))-heading_error
			)
		if heading_error <= 20.0:
			_alignment_hold_s += delta
			if (_alignment_hold_s >= 0.4
					and not _active_waypoint_record.has("time_to_alignment_20deg_ms")):
				_active_waypoint_record["time_to_alignment_20deg_ms"] = maxf(0.0,_waypoint_elapsed_s-_alignment_hold_s)*1000.0
		else:
			_alignment_hold_s = 0.0
	if not _active_waypoint_record.has("waypoint_response_latency_ms"):
		var initial_turn := float(_active_waypoint_record.get("initial_pilot_turn",0.0))
		var initial_thrust := float(_active_waypoint_record.get("initial_pilot_thrust",0.0))
		if (absf(Displays.pilot_turn_axis()-initial_turn)>=0.15
				or absf(Displays.pilot_thrust_axis()-initial_thrust)>=0.15):
			_active_waypoint_record["waypoint_response_latency_ms"] = _waypoint_elapsed_s*1000.0


func _finalize_active_waypoint(status: String,overridden: bool = false) -> void:
	if _active_waypoint_record.is_empty():
		return
	_active_waypoint_record["response_window_observed_ms"] = _waypoint_elapsed_s*1000.0
	_active_waypoint_record["waypoint_override"] = overridden
	_active_waypoint_record["completion_status"] = status
	ExperimentLog.record_waypoint(_active_waypoint_record)
	_active_waypoint_record = {}
	_waypoint_elapsed_s = 0.0
	_alignment_hold_s = 0.0
	_override_hold_s = 0.0
	_last_waypoint_heading_error = 0.0


func _update_target_event_window(_delta: float) -> void:
	if _target_event_record.is_empty() or _target_event_written:
		return
	_target_event_elapsed_s += _delta
	_target_event_record["window_observed_ms"] = minf(_target_event_elapsed_s,15.0)*1000.0
	# 15 秒分析窗结束后仍保留事件记录，直到安全门或关卡自然结束，以免丢失到达安全点时间。
	if _target_event_elapsed_s > 15.0:
		if not bool(_target_event_record.get("analysis_window_complete",false)):
			_target_event_record["analysis_window_complete"] = true
			_target_event_record["disintegrated_15s"] = not Game.ship_alive
		return
	var heading_error := _current_waypoint_heading_error_deg()
	if heading_error >= 0.0:
		_target_event_record["max_heading_error_deg_15s"] = maxf(float(_target_event_record.get("max_heading_error_deg_15s",0.0)),heading_error)
		for sample_s: int in [3,5]:
			var key := "heading_error_reduction_%ds_deg" % sample_s
			if _target_event_elapsed_s >= sample_s and not _target_event_record.has(key):
				_target_event_record[key] = float(_target_event_record.get("heading_error_at_onset_deg",heading_error))-heading_error
	var cross_track_error := _current_route_cross_track_error()
	if cross_track_error >= 0.0:
		_target_event_record["max_cross_track_error_15s"] = maxf(
			float(_target_event_record.get("max_cross_track_error_15s",0.0)),cross_track_error
		)
	if not _target_event_record.has("pilot_response_latency_ms") and (
		absf(Displays.pilot_turn_axis()-float(_target_event_record.get("pilot_turn_at_onset",0.0)))>=0.15
		or absf(Displays.pilot_thrust_axis()-float(_target_event_record.get("pilot_thrust_at_onset",0.0)))>=0.15
	):
		_target_event_record["pilot_response_latency_ms"] = _target_event_elapsed_s*1000.0
	if heading_error >= 0.0 and heading_error <= 20.0 and Game.ship_speed <= 18.0:
		_target_recovery_hold_s += _delta
		if (not bool(_target_event_record.get("recovered_within_window",false))
				and _target_event_elapsed_s >= 0.5 and _target_recovery_hold_s >= 1.0):
			_target_event_record["recovered_within_window"] = true
			_target_event_record["recovery_time_ms"] = maxf(0.0,_target_event_elapsed_s-_target_recovery_hold_s)*1000.0
	else:
		_target_recovery_hold_s = 0.0
	_target_event_record["damage_events_15s"] = _mission_hits-int(_target_event_record.get("hits_at_onset",_mission_hits))
	_target_event_record["hull_loss_15s"] = maxf(0.0,float(_target_event_record.get("hull_at_onset",Game.hull))-Game.hull)
	if _target_event_elapsed_s >= 15.0:
		_target_event_record["analysis_window_complete"] = true
		_target_event_record["disintegrated_15s"] = not Game.ship_alive


func _finalize_target_event(outcome: String) -> void:
	if _target_event_record.is_empty() or _target_event_written: return
	_target_event_record["outcome"] = outcome
	if not _target_event_record.has("disintegrated_15s"):
		_target_event_record["disintegrated_15s"] = not Game.ship_alive and _target_event_elapsed_s<=15.0
	_target_event_record["collision_within_15s"] = int(_target_event_record.get("damage_events_15s",0)) > 0
	_target_event_record["explosion_within_15s"] = bool(_target_event_record.get("disintegrated_15s",false))
	var details := _target_event_record.get("details",{}) as Dictionary
	if _target_event_record.has("pilot_response_latency_ms"):
		details["pilot_response_latency_ms"] = _target_event_record.pilot_response_latency_ms
	if _target_event_record.has("recovery_time_ms"):
		details["recovery_time_ms"] = _target_event_record.recovery_time_ms
	_target_event_record["details"] = details
	ExperimentLog.record_target_event(_target_event_record)
	_target_event_written = true
	_target_recovery_hold_s = 0.0
	ExperimentLog.clear_active_target_event()
	ExperimentLog.advance_segment()


func _sample_flight_trail(delta: float) -> void:
	if (_mission_ended or _mission_finishing or _restarting or not Game.ship_alive
			or _flight_trail.size() >= FLIGHT_TRAIL_POINT_CAP):
		return
	_flight_trail_timer -= delta
	if _flight_trail_timer > 0.0:
		return
	_flight_trail_timer = FLIGHT_TRAIL_SAMPLE_S
	var point := _world_to_trail(Game.ship_position)
	if _flight_trail.is_empty() or _flight_trail[_flight_trail.size()-1].distance_to(point) > 0.04:
		_flight_trail.append(point)


func _archive_failed_flight_trail() -> void:
	if _flight_trail.size() >= 2:
		_failed_flight_trails.append(_flight_trail.duplicate())
	_flight_trail = PackedVector2Array()
	_flight_trail_timer = 0.0


func _world_to_trail(position: Vector3) -> Vector2:
	return Vector2(position.x,position.z)


func _track_severe_heading_deviation(delta: float) -> void:
	if (_mission_ended or _mission_finishing or not Game.ship_alive or not Game.has_waypoint
			or Game.ship_speed < SEVERE_HEADING_MIN_SPEED):
		_reset_heading_deviation_state()
		return
	var to_waypoint := Game.waypoint - Game.ship_position
	to_waypoint.y = 0.0
	if to_waypoint.length() < SEVERE_HEADING_MIN_WAYPOINT_DISTANCE:
		_reset_heading_deviation_state()
		return
	var target_heading := atan2(-to_waypoint.x,-to_waypoint.z)
	var heading_error := absf(wrapf(target_heading-Game.ship_heading,-PI,PI))
	if _heading_deviation_active:
		if heading_error <= SEVERE_HEADING_EXIT_RAD:
			_reset_heading_deviation_state()
		return
	if heading_error < SEVERE_HEADING_ENTER_RAD:
		_heading_deviation_candidate_s = 0.0
		return
	_heading_deviation_candidate_s += delta
	if _heading_deviation_candidate_s < SEVERE_HEADING_MIN_S:
		return
	_heading_deviation_active = true
	_severe_heading_deviations += 1
	ExperimentLog.log_event("severe_heading_deviation","system",{
		"index":_severe_heading_deviations,
		"heading_error_degrees":rad_to_deg(heading_error),
		"threshold_degrees":rad_to_deg(SEVERE_HEADING_ENTER_RAD),
		"minimum_duration_s":SEVERE_HEADING_MIN_S,
		"speed":Game.ship_speed,
		"ship_x":Game.ship_position.x,"ship_z":Game.ship_position.z,
		"waypoint_x":Game.waypoint.x,"waypoint_z":Game.waypoint.z,
	})


func _reset_heading_deviation_state() -> void:
	_heading_deviation_candidate_s = 0.0
	_heading_deviation_active = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if get_tree().paused:
		return
	if event.is_action_pressed("cycle_view"):
		Game.cycle_view_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("dual_window"):
		_toggle_dual_window()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset_run"):
		_reset_run()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("switch_pointer_role") and Game.view_mode == Game.ViewMode.DUAL_WINDOW:
		_switch_pointer_role()
		get_viewport().set_input_as_handled()
	# 鼠标席位翻转已移至设置页面按钮，不再绑定快捷键


func _on_shared_key_input(event: InputEventKey) -> void:
	if event.pressed and not event.echo and (
		event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE
	):
		_toggle_pause()


func _on_raw_keyboard_key(_seat: int, usage: int, pressed: bool) -> void:
	if pressed and usage == HID_KEY_ESCAPE:
		_toggle_pause()


func _toggle_pause() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_pause_toggle_ms < PAUSE_TOGGLE_DEBOUNCE_MS:
		return
	if not get_tree().paused and (_restarting or _mission_finishing or _mission_ended):
		return
	_last_pause_toggle_ms = now
	_set_pause_state(not get_tree().paused)


func _set_pause_state(paused: bool) -> void:
	for menu: Control in _pause_menus:
		if menu != null:
			menu.visible = paused
	if paused:
		GameAudio.stop_ship_motion(true)
	GameAudio.set_gameplay_paused(paused)
	if paused:
		GameAudio.play_ui_popup_open()
	else:
		GameAudio.play_ui_popup_close()
	get_tree().paused = paused
	ExperimentLog.log_event("pause_toggled", "system", {
		"paused": paused,
		"elapsed": _mission_elapsed,
	})


func _resume_from_pause() -> void:
	_set_pause_state(false)


func _restart_current_mission() -> void:
	if not _prepare_pause_scene_transition():
		return
	ExperimentLog.log_event("pause_action", "system", {
		"action": "restart_mission",
		"elapsed": _mission_elapsed,
	})
	_record_aborted_mission("manual_restart")
	Game.reset_run()
	get_tree().reload_current_scene()


func _return_to_level_select() -> void:
	if not _prepare_pause_scene_transition():
		return
	ExperimentLog.log_event("pause_action", "system", {
		"action": "return_level_select",
		"elapsed": _mission_elapsed,
	})
	_record_aborted_mission("return_level_select")
	Game.reset_run()
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")


func _return_to_title() -> void:
	if not _prepare_pause_scene_transition():
		return
	ExperimentLog.log_event("pause_action", "system", {
		"action": "return_title",
		"elapsed": _mission_elapsed,
	})
	_record_aborted_mission("return_title")
	ExperimentLog.close_session()
	Game.clear_experiment_setup()
	Game.reset_run()
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")


func _prepare_pause_scene_transition() -> bool:
	# 任一屏幕发起退出都只执行一次；先收回副屏角色页，再让下一场景重新镜像到两块屏幕。
	if _pause_scene_transitioning:
		return false
	_pause_scene_transitioning = true
	_set_pause_state(false)
	Game.set_view_mode(Game.ViewMode.SPLIT)
	Displays.show_shared_page()
	return true


func _mission_direct_distance() -> float:
	if Game.current_sector == null:
		return 0.0
	var route := Game.current_sector.route_checkpoints
	if route.size() >= 2:
		return route[0].distance_to(route[route.size()-1])
	if Game.objective_body() != null:
		return Game.current_sector.spawn_position.distance_to(Game.objective_body().world_position)
	return 0.0


func _record_aborted_mission(reason: String) -> void:
	if _mission_ended or _mission_finishing:
		return
	_mission_finishing = true
	_mission_terminal_session_ms = ExperimentLog.session_elapsed_ms()
	_finalize_active_waypoint("mission_aborted")
	_finalize_target_event("mission_aborted")
	var direct_distance := _mission_direct_distance()
	var summary := {
		"mission_id":Game.selected_mission_id,"outcome":"中途退出","success":false,
		"elapsed":_mission_elapsed,"active_gameplay_elapsed":_active_gameplay_elapsed,
		"terminal_session_elapsed_ms":_mission_terminal_session_ms,
		"limit":Game.current_sector.time_limit_s if Game.current_sector != null else 0.0,
		"revivals":_mission_deaths,"hits":_mission_hits,"damage_taken":_mission_damage_taken,
		"waypoint_requests":_mission_waypoint_requests,"waypoints":_mission_waypoints,
		"rejected_waypoints":_mission_rejected_waypoints,"hull":Game.hull,
		"path_length":_mission_path_length,"direct_distance":direct_distance,
		"path_efficiency_ratio":minf(1.0,direct_distance/_mission_path_length) if _mission_path_length>0.001 else null,
		"severe_heading_deviations":_severe_heading_deviations,
		"waypoint_drift_events":_waypoint_drift_events,"ship_shear_events":_ship_shear_events,
		"target_event_triggered":(_waypoint_drift_events+_ship_shear_events)>0,
		"aborted_reason":reason,
	}
	ExperimentLog.log_event("mission_aborted","system",summary)
	ExperimentLog.record_mission(summary)


func _bind_inputs() -> void:
	_bind_key("thrust", KEY_W)
	_bind_key("brake", KEY_S)
	_bind_key("turn_left", KEY_A)
	_bind_key("turn_right", KEY_D)
	_bind_key("cycle_view", KEY_F2)
	_bind_key("dual_window", KEY_F3)
	_bind_key("reset_run", KEY_R)
	_bind_key("toggle_nav_deck", KEY_E)
	_bind_key("switch_pointer_role", KEY_F4)
	# swap_mouse_seats 快捷键已移除；翻转操作改为设置页面按钮


func _bind_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_ui() -> void:
	var ui := Control.new()
	_root_ui = ui
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)

	_split = HBoxContainer.new()
	_split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_split.add_theme_constant_override("separation", 0)
	ui.add_child(_split)

	_navigator_view = NavigatorView.new()
	_pilot_view = PilotView.new()

	_nav_slot = UiStyle.make_wide_page_frame(_navigator_view)
	_nav_slot.size_flags_stretch_ratio = 1.0
	_split.add_child(_nav_slot)

	_bezel = UiStyle.make_color_rect(Color("05060a"))
	_bezel.custom_minimum_size = Vector2(6.0, 0.0)
	_split.add_child(_bezel)

	_pilot_slot = UiStyle.make_wide_page_frame(_pilot_view)
	_split.add_child(_pilot_slot)

	# 白屏只叠在两块游戏页上，letterbox / 中缝保持原色。
	_death_overlays.append(_attach_screen_white(_navigator_view))
	_death_overlays.append(_attach_screen_white(_pilot_view))
	_build_pause_menus()
	_build_tutorial_overlays()


func _build_pause_menus() -> void:
	for entry: Dictionary in [
		{"role": "navigator", "page": _navigator_view},
		{"role": "pilot", "page": _pilot_view},
	]:
		var menu := PauseMenuScript.new() as Control
		(entry.page as Control).add_child(menu)
		menu.call("setup", str(entry.role))
		menu.connect("resume_requested", _resume_from_pause)
		menu.connect("restart_requested", _restart_current_mission)
		menu.connect("level_select_requested", _return_to_level_select)
		menu.connect("title_requested", _return_to_title)
		_pause_menus.append(menu)


func _build_tutorial_overlays() -> void:
	if not _is_tutorial_mission():
		return
	for entry: Dictionary in [
		{"role": "navigator", "page": _navigator_view},
		{"role": "pilot", "page": _pilot_view},
	]:
		var overlay := TutorialOverlayScript.new() as Control
		(entry.page as Control).add_child(overlay)
		overlay.call("setup", str(entry.role))
		overlay.connect("finished", _on_tutorial_finished)
		_tutorial_overlays.append(overlay)


func _on_tutorial_finished(role: String) -> void:
	ExperimentLog.log_event("tutorial_completed", role, {
		"mission": Game.selected_mission_id,
	})


func _is_tutorial_mission() -> bool:
	return Game.current_sector != null and Game.current_sector.id == "practice"


func _mission_timer_enabled() -> bool:
	return Game.current_sector != null and not _is_tutorial_mission()


func _build_world_and_cameras() -> void:
	var nav_box := _make_view_box(2.0)
	_nav_view_mat = nav_box.material as ShaderMaterial
	_navigator_view.view_host.add_child(nav_box)
	_nav_viewport = _make_viewport(VIEW_SIZE)
	_nav_viewport.own_world_3d = false
	nav_box.add_child(_nav_viewport)

	var world_scene: PackedScene = load("res://scenes/space_world.tscn") as PackedScene
	_world = world_scene.instantiate() as Node3D
	add_child(_world)
	_ship = _world.get_node("Ship") as Ship

	_camera_probe = SphereShape3D.new()
	_camera_probe.radius = CAMERA_PROBE_RADIUS
	_camera_probe_query = PhysicsShapeQueryParameters3D.new()
	_camera_probe_query.shape = _camera_probe
	_camera_probe_query.collision_mask = CAMERA_OBSTACLE_MASK
	_camera_probe_query.collide_with_areas = false
	_camera_probe_query.collide_with_bodies = true
	_camera_probe_query.exclude = [_ship.get_rid()]

	_nav_camera = _make_camera()
	_nav_viewport.add_child(_nav_camera)
	_nav_fog_mat = _attach_depth_fog(_nav_camera)
	_nav_camera.make_current()
	_nav_arm_offset = _desired_nav_arm()
	_nav_camera.global_position = _ship.global_position + _nav_arm_offset
	_look_at_ship(_nav_camera)

	var pilot_box := _make_view_box(2.0)
	_pilot_view_mat = pilot_box.material as ShaderMaterial
	_pilot_view.porthole_host.add_child(pilot_box)
	_pilot_viewport = _make_viewport(VIEW_SIZE)
	_pilot_viewport.own_world_3d = false
	pilot_box.add_child(_pilot_viewport)
	_pilot_camera = _make_camera()
	_pilot_camera.fov = PILOT_FOV
	_pilot_viewport.add_child(_pilot_camera)
	_pilot_fog_mat = _attach_depth_fog(_pilot_camera)
	_pilot_camera.make_current()
	_pilot_camera.global_transform = _ship.pilot_mount.global_transform
	# 摇杆改画在驾驶员页最上层的透明视口里，主相机不再渲染舱内层。
	_pilot_camera.cull_mask &= ~CockpitStick3D.RENDER_LAYER
	_nav_camera.cull_mask &= ~CockpitStick3D.RENDER_LAYER
	_build_pilot_stick_overlay()


func _build_pilot_stick_overlay() -> void:
	# 独立透明视口：摇杆贴在屏幕上，压过 Pad View 和仪表。
	var stick_box := _make_view_box(2.0)
	_pilot_view.stick_host.add_child(stick_box)
	var stick_viewport := _make_viewport(VIEW_SIZE)
	stick_viewport.transparent_bg = true
	stick_viewport.own_world_3d = true
	stick_box.add_child(stick_viewport)
	var stick_camera := _make_camera()
	# 摇杆坐标按原来的 64° 视野标定；窗外镜头的 50° 不能套在这一层，否则杆会沉到画面外。
	stick_camera.fov = VIEW_FOV
	stick_camera.cull_mask = CockpitStick3D.RENDER_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	stick_camera.environment = env
	stick_viewport.add_child(stick_camera)
	stick_camera.make_current()
	stick_camera.add_child(CockpitStick3D.new())


func _make_view_box(pixel_scale: float) -> SubViewportContainer:
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/pixel_composite.gdshader") as Shader
	mat.set_shader_parameter("pixel_scale", pixel_scale)
	mat.set_shader_parameter("color_levels", 12.0)
	mat.set_shader_parameter("dither_strength", 0.012)
	mat.set_shader_parameter("contrast", 1.08)
	mat.set_shader_parameter("saturation", 0.96)
	box.material = mat
	return box


func _make_viewport(size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.transparent_bg = false
	return viewport


func _make_camera() -> Camera3D:
	var camera := Camera3D.new()
	camera.fov = VIEW_FOV
	camera.near = VIEW_NEAR
	camera.far = VIEW_FAR
	camera.cull_mask = 0xFFFFF
	camera.current = false
	# 光学虚化改由屏幕 shader 按飞船焦点做薄透镜 CoC，避免和引擎景深叠糊。
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_near_enabled = false
	camera.attributes = attrs
	return camera


func _attach_depth_fog(camera: Camera3D) -> ShaderMaterial:
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/depth_fog.gdshader") as Shader
	mat.set_shader_parameter("fog_start", 20.0)
	mat.set_shader_parameter("fog_end", 88.0)
	mat.set_shader_parameter("fog_strength", 0.58)
	mat.set_shader_parameter("aperture", 3.2)
	mat.set_shader_parameter("max_coc_px", 5.5)
	quad.material = mat
	var fog := MeshInstance3D.new()
	fog.mesh = quad
	fog.extra_cull_margin = 16384.0
	fog.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fog.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	camera.add_child(fog)
	return mat


func _desired_nav_arm() -> Vector3:
	return _ship.global_transform.basis.z * NAV_ARM_BACK + Vector3.UP * NAV_ARM_UP


func _slerp_arm(from: Vector3, to: Vector3, weight: float) -> Vector3:
	var from_len: float = from.length()
	var to_len: float = to.length()
	if from_len < 0.001:
		return to
	var from_n: Vector3 = from / from_len
	var to_n: Vector3 = to.normalized()
	var aligned: float = from_n.dot(to_n)
	var dir: Vector3
	if aligned > 0.9995:
		dir = from_n.lerp(to_n, weight).normalized()
	elif aligned < -0.9995:
		dir = from_n.rotated(Vector3.UP, PI * weight).normalized()
	else:
		dir = from_n.slerp(to_n, weight)
	return dir * lerpf(from_len, to_len, weight)


func _spring_arm_position(desired_offset: Vector3) -> Vector3:
	var origin: Vector3 = _ship.global_position
	var desired: Vector3 = origin + desired_offset
	var dir: Vector3 = desired_offset.normalized()
	var from: Vector3 = origin + dir * 2.15
	if _ship.get_world_3d() == null:
		return desired
	_camera_probe_query.transform = Transform3D(Basis.IDENTITY, from)
	_camera_probe_query.motion = desired - from
	_camera_probe_query.exclude = [_ship.get_rid()]
	var hit: PackedFloat32Array = _ship.get_world_3d().direct_space_state.cast_motion(_camera_probe_query)
	var safe: float = 1.0
	if hit.size() >= 1:
		safe = hit[0]
	var pos: Vector3 = from.lerp(desired, safe)
	if pos.distance_to(origin) < NAV_ARM_MIN:
		pos = origin + dir * NAV_ARM_MIN
	return pos


func _look_at_ship(camera: Camera3D) -> void:
	var look_at_pos: Vector3 = _ship.global_position + Vector3.UP * NAV_LOOK_HEIGHT
	if camera.global_position.distance_to(look_at_pos) > 0.8:
		camera.look_at(look_at_pos, Vector3.UP)


func _update_nav_camera(delta: float, shake: Vector3) -> void:
	var desired: Vector3 = _desired_nav_arm()
	var follow: float = 1.0 - exp(-delta * NAV_ARM_FOLLOW)
	_nav_arm_offset = _slerp_arm(_nav_arm_offset, desired, follow)
	var cam_pos: Vector3 = _spring_arm_position(_nav_arm_offset)
	_nav_camera.global_position = cam_pos
	_look_at_ship(_nav_camera)
	_nav_camera.global_position += _nav_camera.global_transform.basis.x * shake.x
	_nav_camera.global_position += _nav_camera.global_transform.basis.y * shake.y
	_nav_camera.rotation_degrees.z = shake.x * 4.5


func _apply_ship_focus(camera: Camera3D, fog_mat: ShaderMaterial, focus_distance: float) -> void:
	if fog_mat == null:
		return
	fog_mat.set_shader_parameter("ship_world", _ship.global_position)
	fog_mat.set_shader_parameter("focus_distance", maxf(focus_distance, camera.near + 0.4))


func _set_hurt_flash(amount: float) -> void:
	_set_view_param("hurt_flash", amount)


## 同一个参数同时推给两侧视口的合成材质。
func _set_view_param(param: String, value: float) -> void:
	if _nav_view_mat != null:
		_nav_view_mat.set_shader_parameter(param, value)
	if _pilot_view_mat != null:
		_pilot_view_mat.set_shader_parameter(param, value)


## 接近致死行星时屏幕边缘闪橙红：越近强度越高、闪得越快。
func _update_proximity_warning(delta: float) -> void:
	var target: float = _proximity_factor()
	# 渐入渐出，避免在警戒圈边缘一帧进一帧出地跳变。
	_warn_level = move_toward(_warn_level, target, delta * 2.5)
	if _warn_level <= 0.01 or not Game.ship_alive:
		_set_view_param("warn_pulse", 0.0)
		return
	var freq: float = lerpf(1.6, 4.5, _warn_level)
	_warn_phase = fmod(_warn_phase + delta * freq, 1.0)
	var blink: float = 0.55 + 0.45 * sin(_warn_phase * TAU)
	# 开根让轻度接近也能看见，重度接近仍然拉满。
	_set_view_param("warn_pulse", pow(_warn_level, 0.7) * blink)


## 0..1：离最近的致死行星表面有多近。终点不算（靠近它是目标行为）。
func _proximity_factor() -> float:
	if not Game.ship_alive or Game.mission_complete:
		return 0.0
	var worst: float = 0.0
	for body: CelestialBodyData in Game.celestial_bodies:
		if body.kind == CelestialBodyData.Kind.DESTINATION:
			continue
		var to := Vector3(
			body.world_position.x - Game.ship_position.x,
			0.0,
			body.world_position.z - Game.ship_position.z
		)
		var gap: float = to.length() - body.collision_radius - Game.SHIP_RADIUS
		worst = maxf(worst, clampf(1.0 - gap / PROXIMITY_WARN_DISTANCE, 0.0, 1.0))
	return worst


func _nearest_body_surface_gap() -> float:
	var nearest := INF
	for body: CelestialBodyData in Game.celestial_bodies:
		var to := Vector3(
			body.world_position.x - Game.ship_position.x,
			0.0,
			body.world_position.z - Game.ship_position.z
		)
		var gap := to.length() - body.collision_radius - Game.SHIP_RADIUS
		nearest = minf(nearest, gap)
	return nearest if nearest < INF else 1000.0


## 解体白屏：按关键帧曲线推进——闪两下、拉到纯白、保持、淡出。
func _update_death_flash(delta: float) -> void:
	if _death_time < 0.0:
		return
	_death_time += delta
	var total: float = DEATH_CURVE[DEATH_CURVE.size() - 1].x
	if _death_time >= total:
		_apply_death_white(0.0)
		_death_time = -1.0
		return
	_apply_death_white(_death_value(_death_time))


## 关键帧线性插值。
func _death_value(t: float) -> float:
	for i: int in range(DEATH_CURVE.size() - 1):
		var a: Vector2 = DEATH_CURVE[i]
		var b: Vector2 = DEATH_CURVE[i + 1]
		if t <= b.x:
			var span: float = maxf(b.x - a.x, 0.0001)
			return lerpf(a.y, b.y, (t - a.x) / span)
	return 0.0


## 在一块 16:9 游戏页上盖一层白，作为该页 UI 的最顶层。
func _attach_screen_white(page: Control) -> ColorRect:
	var overlay: ColorRect = UiStyle.make_color_rect(Color(1.0, 1.0, 1.0, 0.0))
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 64
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(overlay)
	return overlay


## 白度只推给两块屏幕遮罩和视口 shader，窗外黑边不受影响。
func _apply_death_white(value: float) -> void:
	var alpha: float = clampf(value, 0.0, 1.0)
	for overlay: ColorRect in _death_overlays:
		if overlay != null:
			overlay.color.a = alpha
	_set_view_param("death_flash", value)


func _on_ship_hit(remaining: float) -> void:
	_mission_hits += 1
	_mission_damage_taken += maxf(0.0,_last_hull_for_damage-remaining)
	_last_hull_for_damage = remaining
	_collision_points.append(_world_to_trail(Game.ship_position))
	GameAudio.play_ship_impact(remaining / Game.MAX_HULL)
	ExperimentLog.log_event("ship_hit","pilot",{
		"hit_index":_mission_hits,"remaining_hull":remaining,
		"x":Game.ship_position.x,"z":Game.ship_position.z,
		"velocity_x":Game.ship_velocity.x,"velocity_z":Game.ship_velocity.z,
		"elapsed":_mission_elapsed,
	})
	_hurt_flash = 1.0
	_light_flash = 1.0
	_shake.add(0.95 if remaining > 0.1 else 1.25)
	if remaining > 0.1 and not _restarting and not _hit_hitching:
		_hit_hitching = true
		Engine.time_scale = 0.16
		await get_tree().create_timer(0.06, true, false, true).timeout
		if not _restarting:
			Engine.time_scale = 1.0
		_hit_hitching = false


func _on_ship_exploded(world_pos: Vector3) -> void:
	if _mission_ended:
		return
	# 超时判负时只播放终局爆炸，不再进入复活分支。
	if _mission_finishing:
		_prime_explosion_visual(world_pos)
		_death_time = 0.0
		return
	# 旧碰撞缓存可能在复活序列中再发一次解体；忽略重复信号。
	if _restarting:
		return
	_mission_deaths += 1
	_archive_failed_flight_trail()
	ExperimentLog.log_event("ship_exploded","pilot",{
		"revival":_mission_deaths,"x":world_pos.x,"z":world_pos.z,"elapsed":_mission_elapsed,
	})
	var target_exposed := _waypoint_drift_events > 0 or _ship_shear_events > 0
	if Game.selected_mission_id in ["level_2","level_3"] and target_exposed:
		# 第一次有效暴露后的解体就是异常后果；自然结束本航段并进入事件回顾。
		_prime_explosion_visual(world_pos)
		_death_time = 0.0
		_begin_mission_end.call_deferred("异常后飞船解体",false)
		return
	_finalize_active_waypoint("ship_exploded")
	_restarting = true
	_prime_explosion_visual(world_pos)
	# 顿帧强化冲击 → 白屏闪两下后拉到纯白 → 纯白遮挡下传回出生点 → 淡出。
	Engine.time_scale = 0.08
	await get_tree().create_timer(0.09, true, false, true).timeout
	Engine.time_scale = 1.0
	_death_time = 0.0
	await get_tree().create_timer(DEATH_RESET_TIME, true, false, true).timeout
	if _mission_finishing:
		_restarting = false
		return
	if Game.selected_mission_id in ["level_2","level_3"] and get_tree().current_scene != null:
		# 核心异常尚未发生：本次没有可评价事件，重新开始该关且保留下一次触发资格。
		ExperimentLog.log_event("pre_target_failure_restart","system",{"elapsed":_mission_elapsed})
		_record_aborted_mission("pre_target_failure")
		_restarting = false
		Game.reset_run()
		get_tree().reload_current_scene()
		return
	var checkpoint := Game.last_respawn_point()
	Game.respawn_ship_at(checkpoint.position,checkpoint.heading)
	_last_hull_for_damage = Game.hull
	_path_last_position = checkpoint.position
	ExperimentLog.begin_new_life()
	ExperimentLog.advance_segment()
	if _ship != null:
		_ship.snap_to_state()
	_flight_trail.append(_world_to_trail(checkpoint.position))
	ExperimentLog.log_event("ship_respawn","system",{
		"revival":_mission_deaths,"relay":checkpoint.index,"relay_name":checkpoint.name,
		"x":checkpoint.position.x,"z":checkpoint.position.z,"elapsed":_mission_elapsed
	})
	# 重生瞬间给一点暖光，明确告诉玩家已经重新接管飞船。
	_light_flash = 0.5
	var total: float = DEATH_CURVE[DEATH_CURVE.size() - 1].x
	await get_tree().create_timer(total - DEATH_RESET_TIME, true, false, true).timeout
	_restarting = false


func _prime_explosion_visual(world_pos: Vector3) -> void:
	_shake.add(1.35)
	_hurt_flash = 1.0
	_light_flash = 1.0
	GameAudio.play_explosion()
	if _world != null:
		ShipBurst3D.play(_world,world_pos)


func _apply_view_mode(mode: int) -> void:
	if mode != Game.ViewMode.DUAL_WINDOW:
		_close_extra_window()
	_nav_slot.visible = mode != Game.ViewMode.PILOT_ONLY
	_pilot_slot.visible = mode != Game.ViewMode.NAVIGATOR_ONLY
	if mode == Game.ViewMode.DUAL_WINDOW:
		_open_extra_window()
	else:
		_restore_main_window()


func _toggle_dual_window() -> void:
	if Game.view_mode == Game.ViewMode.DUAL_WINDOW:
		Game.set_view_mode(Game.ViewMode.SPLIT)
	else:
		Game.set_view_mode(Game.ViewMode.DUAL_WINDOW)


func _open_extra_window() -> void:
	if _extra_window != null:
		return
	_apply_display_role_layout()


func _close_extra_window() -> void:
	if _extra_window == null:
		return
	var secondary_slot := _secondary_role_slot()
	Displays.release_role_page(secondary_slot)
	_return_role_slots_to_split()
	_extra_window = null
	_pilot_slot.visible = true
	_nav_slot.size_flags_stretch_ratio = 1.0
	_bezel.visible = true


func _apply_display_role_layout() -> void:
	_return_role_slots_to_split()
	var secondary_slot := _secondary_role_slot()
	secondary_slot.visible = true
	_extra_window = Displays.show_role_page(secondary_slot)
	_nav_slot.visible = true
	_pilot_slot.visible = true
	_bezel.visible = false


func _secondary_role_slot() -> Control:
	return _nav_slot if Displays.secondary_role() == Displays.Role.NAVIGATOR else _pilot_slot


func _return_role_slots_to_split() -> void:
	for slot: Control in [_nav_slot, _pilot_slot]:
		if slot.get_parent() != _split:
			if slot.get_parent() == null:
				_split.add_child(slot)
			else:
				slot.reparent(_split)
	_split.move_child(_nav_slot, 0)
	_split.move_child(_bezel, 1)
	_split.move_child(_pilot_slot, 2)


func _on_display_roles_swapped(_primary_role: int, _secondary_role: int) -> void:
	if Game.view_mode == Game.ViewMode.DUAL_WINDOW:
		_apply_display_role_layout()


func _switch_pointer_role() -> void:
	if Game.experiment_mode:
		return
	Displays.swap_roles()


func _restore_main_window() -> void:
	Displays.relayout()


## clear_death_white=false 供解体流程使用：传回出生点时白屏还要继续盖着。
func _reset_run(clear_death_white: bool = true) -> void:
	Engine.time_scale = 1.0
	Game.reset_run()
	if _ship != null:
		_ship.snap_to_state()
	_shake.strength = 0.0
	_hurt_flash = 0.0
	_warn_level = 0.0
	_set_hurt_flash(0.0)
	_set_view_param("warn_pulse", 0.0)
	if clear_death_white:
		_death_time = -1.0
		_apply_death_white(0.0)
	# 重生瞬间给一点暖光，标记“回来了”。
	_light_flash = 0.5
	if _nav_camera != null and _ship != null:
		_nav_arm_offset = _desired_nav_arm()
		_nav_camera.global_position = _ship.global_position + _nav_arm_offset
		_look_at_ship(_nav_camera)


func _on_waypoint_sfx(_pos: Vector3, enabled: bool) -> void:
	if enabled:
		GameAudio.play_waypoint_placed()


func _on_waypoint_request_result(accepted: bool, reason: String, remaining_s: float) -> void:
	_mission_waypoint_requests += 1
	if accepted:
		_mission_waypoints += 1
	else:
		_mission_rejected_waypoints += 1
		if not _target_event_record.is_empty() and not _target_event_written:
			_target_event_record["failed_waypoint_requests"] = int(_target_event_record.get("failed_waypoint_requests",0))+1
	# 冷却中重复点击只是无效输入，不作为错误播放失败音；边界等真正无效请求才提示。
	if not accepted and reason != "cooldown":
		GameAudio.play_waypoint_denied()
	ExperimentLog.log_event("waypoint_request","navigator",{
		"request_sequence":Game.waypoint_request_sequence,
		"requested_x":Game.last_waypoint_requested.x,
		"requested_z":Game.last_waypoint_requested.z,
		"applied_x":Game.last_waypoint_applied.x if accepted else null,
		"applied_z":Game.last_waypoint_applied.z if accepted else null,
		"accepted":accepted,"reason":reason,"remaining_s":remaining_s,
		"ship_x":Game.ship_position.x,"ship_z":Game.ship_position.z,
	})
	var to_requested := Game.last_waypoint_requested-Game.ship_position
	to_requested.y = 0.0
	var drift_angle := 0.0
	if accepted:
		var before := Game.last_waypoint_requested-Game.ship_position
		var after := Game.last_waypoint_applied-Game.ship_position
		if before.length_squared()>0.0001 and after.length_squared()>0.0001:
			drift_angle = rad_to_deg(atan2(before.normalized().cross(after.normalized()).y,before.normalized().dot(after.normalized())))
	var applied_target := Game.last_waypoint_applied if accepted else Game.last_waypoint_requested
	var to_applied := applied_target-Game.ship_position
	to_applied.y = 0.0
	var applied_heading := atan2(-to_applied.x,-to_applied.z) if to_applied.length_squared()>0.0001 else Game.ship_heading
	var record := {
		"waypoint_id":"%s-waypoint-%04d" % [ExperimentLog.current_attempt_id(),Game.waypoint_request_sequence],
		"request_sequence":Game.waypoint_request_sequence,"request_session_elapsed_ms":ExperimentLog.session_elapsed_ms(),
		"accepted":accepted,"reason":reason,"remaining_cooldown_ms":remaining_s*1000.0,
		"requested_x":Game.last_waypoint_requested.x,"requested_z":Game.last_waypoint_requested.z,
		"applied_x":Game.last_waypoint_applied.x if accepted else null,"applied_z":Game.last_waypoint_applied.z if accepted else null,
		"ship_x":Game.ship_position.x,"ship_z":Game.ship_position.z,
		"initial_heading_error_deg":rad_to_deg(absf(wrapf(applied_heading-Game.ship_heading,-PI,PI))),
		"waypoint_distance":Game.ship_position.distance_to(Game.last_waypoint_applied) if accepted else Game.ship_position.distance_to(Game.last_waypoint_requested),
		"drifted":accepted and absf(drift_angle)>0.01,"drift_angle_deg":drift_angle,
		"event_id":ExperimentLog.active_event_id(),
		"fault_type":str(_target_event_record.get("fault_type","")) if not _target_event_record.is_empty() else "",
		"initial_pilot_turn":Displays.pilot_turn_axis(),
		"initial_pilot_thrust":Displays.pilot_thrust_axis(),
	}
	if not accepted:
		record["completion_status"] = "rejected"
		ExperimentLog.record_waypoint(record)
		return
	# 新航点会终止上一航点的响应窗口；每个已接受请求因此只写一行且都有明确结局。
	_finalize_active_waypoint("overridden",true)
	_active_waypoint_record = record
	_waypoint_elapsed_s = 0.0
	_alignment_hold_s = 0.0
	_last_waypoint_heading_error = float(record.initial_heading_error_deg)
	# 航点漂移是在本次请求内部生效的；这一次异常航点本身不能被误记成 0 ms 的“修正”。
	var is_later_repair := (
		accepted and not _target_event_record.is_empty() and not _target_event_written
		and Game.waypoint_request_sequence > int(_target_event_record.get("request_sequence_at_onset",Game.waypoint_request_sequence))
	)
	if is_later_repair and not _target_event_record.has("navigator_repair_latency_ms"):
		_target_event_record["navigator_repair_latency_ms"] = _target_event_elapsed_s*1000.0
		_target_event_record["repair_waypoint_distance"] = Game.ship_position.distance_to(Game.last_waypoint_applied)
		var onset_heading := float(_target_event_record.get("waypoint_heading_at_onset_rad",applied_heading))
		_target_event_record["repair_waypoint_angle_deg"] = rad_to_deg(absf(wrapf(applied_heading-onset_heading,-PI,PI)))


func _on_disturbance_gate_crossed(index: int,slot: String,anchor: Vector3) -> void:
	ExperimentLog.log_event("disturbance_gate_crossed","system",{
		"index":index,"slot":slot,"anchor_x":anchor.x,"anchor_z":anchor.z,
		"condition":Game.attribution_condition,
	})
	match slot:
		"waypoint_drift":
			if _waypoint_drift_events > 0 or not (Game.get("_pending_waypoint_drifts") as Array).is_empty():
				ExperimentLog.log_event("duplicate_target_event_suppressed","system",{"slot":slot,"gate_index":index})
				return
			_target_event_gate_index = index
			var drift_angle := _draw_waypoint_drift_angle()
			ExperimentLog.log_event("waypoint_drift_drawn","system",{
				"gate_index":index,
				"attempt_number":Game.current_mission_attempt_number(),
				"signed_angle_degrees":drift_angle,
				"magnitude_degrees":absf(drift_angle),
				"direction":"counterclockwise" if drift_angle > 0.0 else "clockwise",
				"minimum_degrees":WAYPOINT_DRIFT_MIN_DEG,
				"maximum_degrees":WAYPOINT_DRIFT_MAX_DEG,
			})
			# 只武装下一次领航点击；原始点击位置从不显示，直接生成偏移后的最终航点。
			Game.arm_waypoint_drift(drift_angle,"level_2_disturbance_gate")
		"ship_shear":
			if _ship_shear_events > 0:
				ExperimentLog.log_event("duplicate_target_event_suppressed","system",{"slot":slot,"gate_index":index})
				return
			_target_event_gate_index = index
			if _ship != null:
				var impulse := _ship.apply_experiment_shear(4.8)
				Game.disturbance_effect_applied.emit("ship_shear",{
					"impulse_x":impulse.x,"impulse_z":impulse.z,"strength":4.8,
				})
		"recovery_window":
			Game.disturbance_effect_applied.emit("recovery_window",{})


func _draw_waypoint_drift_angle() -> float:
	# 幅度和方向分开抽取，确保不会因一个带符号区间的实现细节偏向某一侧。
	var magnitude := snappedf(
		_waypoint_drift_rng.randf_range(WAYPOINT_DRIFT_MIN_DEG,WAYPOINT_DRIFT_MAX_DEG),
		WAYPOINT_DRIFT_STEP_DEG
	)
	var direction := -1.0 if _waypoint_drift_rng.randi_range(0,1) == 0 else 1.0
	return magnitude * direction


func _on_disturbance_effect_applied(effect: String,payload: Dictionary) -> void:
	var details := payload.duplicate()
	details["condition"] = Game.attribution_condition
	var pulse_index := (_waypoint_drift_events+1) if effect=="waypoint_drift" else ((_ship_shear_events+1) if effect=="ship_shear" else 0)
	var event_id := "%s_%s_%02d" % [ExperimentLog.current_attempt_id(),effect,pulse_index]
	if effect in ["waypoint_drift","ship_shear"]:
		ExperimentLog.advance_segment()
		ExperimentLog.set_active_target_event(event_id,effect)
	# 提示先进入两个参与者的真实画面，下一帧开始采集的事件截图必须保留该操纵信息。
	var message := _causal_explanation_message(effect,Game.attribution_condition)
	if not message.is_empty():
		GameAudio.play_system_alert()
		if _navigator_view != null: _navigator_view.show_experiment_notice(message)
		if _pilot_view != null: _pilot_view.show_experiment_notice(message)
		ExperimentLog.log_event("explanation_message_displayed","system",{
			"event_id":event_id,"fault_type":effect,
			"message_id":"%s_%s_v1" % [effect,Game.attribution_condition],"message_version":"1",
			"message_displayed":true,"display_duration_ms":3000,
			"displayed_to_participants":[Game.participant_id_for_role("navigator"),Game.participant_id_for_role("pilot")],
		})
	# 目标事件记录必须先于任何截图等待建立。第三关截图会等待下一帧；如果这一帧内
	# 恰好跨过安全门或飞船解体，结算回调仍应拿到完整的事件起点数据。
	if effect in ["waypoint_drift","ship_shear"]:
		details["pulse_index"] = pulse_index
		details["event_id"] = event_id
		_target_event_elapsed_s = 0.0
		_target_recovery_hold_s = 0.0
		_target_event_written = false
		var heading_at_onset := _current_waypoint_heading_error_deg()
		var to_waypoint := Game.waypoint-Game.ship_position if Game.has_waypoint else Vector3.ZERO
		to_waypoint.y = 0.0
		_target_event_record = {
			"event_id":event_id,"event_type":effect,"fault_type":effect,
			"event_time_session_ms":ExperimentLog.session_elapsed_ms(),"event_time_mission_ms":_mission_elapsed*1000.0,
			"trigger_gate_index":_target_event_gate_index,
			"parameter_name":"angle_degrees" if effect=="waypoint_drift" else "strength",
			"parameter_value":payload.get("angle_degrees",payload.get("strength",null)),
			"ship_x":Game.ship_position.x,"ship_z":Game.ship_position.z,"speed_at_event":Game.ship_speed,
			"waypoint_distance_at_event":Game.ship_position.distance_to(Game.waypoint) if Game.has_waypoint else null,
			"obstacle_distance_at_event":_nearest_body_surface_gap(),"details":details,
			"hits_at_onset":_mission_hits,"hull_at_onset":Game.hull,
			"waypoint_heading_at_onset_rad":atan2(-to_waypoint.x,-to_waypoint.z) if to_waypoint.length_squared()>0.0001 else Game.ship_heading,
			"request_sequence_at_onset":Game.waypoint_request_sequence,
			"pilot_turn_at_onset":Displays.pilot_turn_axis(),
			"pilot_thrust_at_onset":Displays.pilot_thrust_axis(),
		}
		if heading_at_onset >= 0.0:
			_target_event_record["heading_error_at_onset_deg"] = heading_at_onset
	if effect == "waypoint_drift":
		_waypoint_drift_events += 1
		_append_target_event_position(Game.ship_position)
		ExperimentLog.log_event("disturbance_effect_applied","system",{"effect":effect,"details":details})
		# 航点偏移在新航点出现的瞬间达到最大值；截图同时保留已显示的系统提示。
		var review_payload := payload.duplicate()
		review_payload["pulse_index"] = _waypoint_drift_events
		review_payload["event_id"] = event_id
		await _capture_target_event_review(effect,review_payload)
	elif effect == "ship_shear":
		_ship_shear_events += 1
		_append_target_event_position(Game.ship_position)
		ExperimentLog.log_event("disturbance_effect_applied","system",{"effect":effect,"details":details})
		# 横向漂移要观察一小段时间，按实际横向位移挑选峰值帧；原因提示无需等截图。
		var review_payload := payload.duplicate()
		review_payload["pulse_index"] = _ship_shear_events
		review_payload["event_id"] = event_id
		_capture_target_event_review(effect,review_payload)
	else:
		ExperimentLog.log_event("disturbance_effect_applied","system",{"effect":effect,"details":details})


func _append_target_event_position(world_position: Vector3) -> void:
	var point := _world_to_trail(world_position)
	# 每一个实际生效的异常都保留；即使两个脉冲位置接近，也不能因视觉去重丢掉记录。
	_target_event_positions.append(point)


func _causal_explanation_message(effect: String,condition: String) -> String:
	var explicit := condition == "explicit"
	match effect:
		"waypoint_drift":
			return (
				"检测到磁暴干扰。航点位置已发生偏移。"
				if explicit
				else "检测到航点位置偏移，原因未知。"
			)
		"ship_shear":
			return (
				"检测到太阳风扰动。飞船已出现横向偏移。"
				if explicit
				else "检测到飞船横向偏移，原因未知。"
			)
		"recovery_window":
			# 恢复提示不再强化原因；两个条件只在目标异常的因果说明上不同。
			return "飞船状态已恢复稳定。"
	return ""


func _capture_target_event_review(event_type: String,payload: Dictionary = {}) -> void:
	# 只保存参与者实际可见画面的任务相关区域，不叠加后台向量、真实坐标或研究者信息。
	var event_origin := Game.ship_position
	var travel_direction := Vector3(Game.ship_velocity.x,0.0,Game.ship_velocity.z)
	if travel_direction.length_squared() < 0.01 and _ship != null:
		travel_direction = _ship.get_forward()
	travel_direction = travel_direction.normalized()
	var lateral := Vector3(-travel_direction.z,0.0,travel_direction.x)
	var best_metric := -1.0
	var best_views: Dictionary = {}
	var best_time_s := _mission_elapsed
	var sample_count := 1 if event_type == "waypoint_drift" else 16
	for sample_index: int in range(sample_count):
		if sample_index == 0:
			await get_tree().process_frame
		else:
			await get_tree().create_timer(0.10).timeout
		if not is_instance_valid(_navigator_view) or not is_instance_valid(_pilot_view):
			return
		var metric := 0.0
		if event_type == "waypoint_drift":
			# 第三关按程序实际施加的角度记录峰值，不用玩家随后飞行产生的位移代替扰动强度。
			metric = absf(float(payload.get("angle_degrees",0.0)))
		else:
			metric = absf((Game.ship_position-event_origin).dot(lateral))
		if metric >= best_metric:
			best_metric = metric
			best_time_s = _mission_elapsed
			_target_event_peak_position = _world_to_trail(Game.ship_position)
			best_views = _capture_participant_views(true)
		if event_type == "ship_shear" and (not Game.ship_alive or Game.mission_complete):
			break
	if best_views.is_empty():
		return
	var attempt_number := Game.current_mission_attempt_number()
	var previous_record := Game.event_review(event_type)
	# 同一异常段只把程序脉冲中施加强度最大的一帧送入问卷；重试时第一帧总会覆盖旧尝试。
	if (int(previous_record.get("attempt_number",-1)) == attempt_number
			and float(previous_record.get("peak_metric",-1.0)) > best_metric):
		ExperimentLog.log_event("event_review_peak_retained","system",{
			"event_type":event_type,
			"pulse_index":int(payload.get("pulse_index",0)),
			"candidate_metric":best_metric,
			"retained_metric":float(previous_record.get("peak_metric",-1.0)),
		})
		return
	var mission_label := "正式任务 02" if event_type == "waypoint_drift" else "正式任务 03"
	Game.store_event_review(event_type,{
		"event_type":event_type,
		"event_id":str(payload.get("event_id",ExperimentLog.active_event_id())),
		"mission_id":Game.selected_mission_id,
		"mission_label":mission_label,
		"event_time_s":best_time_s,
		"attempt_number":attempt_number,
		"peak_pulse_index":int(payload.get("pulse_index",1)),
		"capture_kind":"target_peak",
		"peak_metric":best_metric,
		"peak_metric_name":"applied_waypoint_rotation_deg" if event_type == "waypoint_drift" else "observed_lateral_displacement",
		"signed_disturbance_value":float(payload.get("angle_degrees",0.0)) if event_type == "waypoint_drift" else float(payload.get("strength",0.0)),
		"target_event_position":_target_event_peak_position,
		"views":best_views,
	})
	ExperimentLog.log_event("event_review_captured","system",{
		"event_type":event_type,
		"event_id":Game.event_review(event_type).get("event_id",""),
		"capture_kind":"target_peak",
		"peak_metric":best_metric,
		"participant_views":best_views.keys(),
	})


func _capture_participant_views(focus_on_event: bool = false) -> Dictionary:
	if not is_instance_valid(_navigator_view) or not is_instance_valid(_pilot_view):
		return {}
	var views := {}
	for entry: Dictionary in [
		{"role":"navigator","page":_navigator_view},
		{"role":"pilot","page":_pilot_view},
	]:
		var role_name := str(entry.role)
		var page := entry.page as Control
		var image: Image
		if DisplayServer.get_name() == "headless":
			# 无图形测试后端没有可读纹理；用同尺寸帧验证保存与最终问卷链路。
			image = Image.create(VIEW_SIZE.x,VIEW_SIZE.y,false,Image.FORMAT_RGB8)
			image.fill(Color("101d2a"))
		else:
			image = _capture_page_region(page,role_name,focus_on_event)
		var participant := Game.participant_id_for_role(role_name)
		var key := participant if not participant.is_empty() else role_name
		views[key] = {"role":role_name,"image":image}
		# 非实验预览没有稳定参与者编号，角色键也便于测试和现场排查。
		views[role_name] = views[key]
	return views


func _capture_page_region(page: Control,_role_name: String,_focus_on_event: bool) -> Image:
	var viewport := page.get_viewport()
	var full := viewport.get_texture().get_image()
	if full == null or full.is_empty():
		return full
	var visible_size := viewport.get_visible_rect().size
	var page_rect := page.get_global_rect()
	var scale := Vector2(float(full.get_width())/maxf(visible_size.x,1.0),float(full.get_height())/maxf(visible_size.y,1.0))
	var rect := Rect2i(
		Vector2i(page_rect.position*scale),
		Vector2i(page_rect.size*scale)
	).intersection(Rect2i(Vector2i.ZERO,full.get_size()))
	# 保存参与者当时看到的完整任务画面；回顾 UI 再按比例缩放，绝不裁掉边缘信息。
	return full.get_region(rect) if rect.size.x > 0 and rect.size.y > 0 else full


func _capture_mission_review(outcome: String,success: bool) -> void:
	var mission_id := Game.selected_mission_id
	var mission_number := maxi(MissionCatalog.IDS.find(mission_id),1)
	var target_type: Variant = null
	var target_exposed: Variant = null
	if mission_id == "level_2":
		target_type = "waypoint_drift"
		target_exposed = _waypoint_drift_events > 0
	elif mission_id == "level_3":
		target_type = "ship_shear"
		target_exposed = _ship_shear_events > 0
	var target_record := Game.event_review(str(target_type)) if target_type != null else {}
	var record := {
		"event_type":"mission_responsibility",
		"event_id":str(target_record.get("event_id","%s-mission-review-attempt-%d" % [mission_id,Game.current_mission_attempt_number()])),
		"mission_id":mission_id,
		"mission_label":"正式任务 %02d" % mission_number,
		"elapsed":_mission_elapsed,
		"outcome":outcome,
		"success":success,
		"attempt_number":Game.current_mission_attempt_number(),
		"target_event_type":target_type,
		"target_event_exposed":target_exposed,
		"target_event_pulse_count":_waypoint_drift_events if mission_id == "level_2" else _ship_shear_events,
		# 第一、二关评价整关，不展示意义不明的结尾截图。
		"views":target_record.get("views",{}) if not target_record.is_empty() else {},
		"capture_kind":target_record.get("capture_kind","none"),
		"event_time_s":target_record.get("event_time_s",null),
		"peak_metric":target_record.get("peak_metric",null),
		"target_event_position":target_record.get("target_event_position",_target_event_peak_position),
		"target_event_positions":_target_event_positions.duplicate(),
		"flight_trail":_flight_trail.duplicate(),
		"failed_flight_trails":_failed_flight_trails.duplicate(true),
		"collision_points":_collision_points.duplicate(),
		"flight_start":_world_to_trail(Game.current_sector.spawn_position) if Game.current_sector != null else Vector2.ZERO,
		"flight_goal":_world_to_trail(Game.objective_body().world_position) if Game.objective_body() != null else Vector2.ZERO,
		"flight_world_bounds":_mission_flight_bounds(),
	}
	Game.store_event_review(mission_id,record)
	ExperimentLog.log_event("mission_review_captured","system",{
		"mission_id":mission_id,
		"event_id":Game.event_review(mission_id).get("event_id",""),
		"capture_kind":record.capture_kind,
		"participant_views":record.views.keys(),
	})


func _mission_flight_bounds() -> Rect2:
	if Game.current_sector == null:
		return Rect2(-100.0,-60.0,200.0,120.0)
	for belt: BeltData in Game.current_sector.belts:
		if belt.is_boundary and belt.shape == BeltData.Shape.RING:
			var horizontal := belt.inner_radius * belt.aspect
			var vertical := belt.inner_radius
			return Rect2(
				Vector2(belt.center.x-horizontal,belt.center.z-vertical),
				Vector2(horizontal*2.0,vertical*2.0)
			)
	var points := Game.current_sector.route_checkpoints
	if points.is_empty():
		return Rect2(-100.0,-60.0,200.0,120.0)
	var min_point := _world_to_trail(points[0])
	var max_point := min_point
	for point: Vector3 in points:
		var p := _world_to_trail(point)
		min_point.x = minf(min_point.x,p.x); min_point.y = minf(min_point.y,p.y)
		max_point.x = maxf(max_point.x,p.x); max_point.y = maxf(max_point.y,p.y)
	return Rect2(min_point,max_point-min_point).grow(18.0)


func _on_safe_gate_crossed(index: int,anchor: Vector3) -> void:
	if not _target_event_record.is_empty() and not _target_event_written:
		_target_event_record["time_to_safe_gate_ms"] = _target_event_elapsed_s*1000.0
		_finalize_target_event("safe_gate_reached")
	ExperimentLog.log_event("safe_gate_crossed","system",{
		"index":index,"anchor_x":anchor.x,"anchor_z":anchor.z
	})


func _on_relay_station_reached(index: int,position: Vector3,station_name: String) -> void:
	GameAudio.play_relay_reached()
	ExperimentLog.log_event("relay_station_reached","system",{
		"index":index,"name":station_name,"x":position.x,"z":position.z
	})


func _on_complete_sfx() -> void:
	GameAudio.play_mission_complete()


func _on_mission_success() -> void:
	_begin_mission_end("完成",true)


func _begin_mission_end(outcome: String,success: bool) -> void:
	if _mission_ended or _mission_finishing:
		return
	_mission_finishing = true
	_mission_terminal_session_ms = ExperimentLog.session_elapsed_ms()
	_finalize_active_waypoint("mission_success" if success else "mission_failure")
	_finalize_target_event("mission_success" if success else "mission_failure")
	GameAudio.stop_ship_motion()
	GameAudio.finish_mission_audio()
	_mission_outcome = outcome
	Engine.time_scale = 1.0
	# 结果动画覆盖任务页之前，整理整关航迹；第二、三关同时挂接目标异常峰值画面。
	if Game.selected_mission_id in ["level_1","level_2","level_3"]:
		_capture_mission_review(outcome,success)
	if not success:
		# 时间耗尽才是失败条件；此时以完整爆炸反馈结束当前飞行。
		if Game.ship_alive:
			Game.explode_ship()
		await get_tree().create_timer(1.25,true,false,true).timeout
	else:
		await get_tree().create_timer(0.65,true,false,true).timeout
	_mission_ended = true
	var limit := Game.current_sector.time_limit_s if Game.current_sector != null else _mission_elapsed
	var direct_distance := _mission_direct_distance()
	var summary := {
		"mission_id":Game.selected_mission_id,
		"outcome":outcome,"success":success,"elapsed":_mission_elapsed,"limit":limit,
		"timed":Game.selected_mission_id!="practice",
		"active_gameplay_elapsed":_active_gameplay_elapsed,
		"terminal_session_elapsed_ms":_mission_terminal_session_ms,
		"revivals":_mission_deaths,"hits":_mission_hits,"waypoints":_mission_waypoints,"hull":Game.hull,
		"waypoint_requests":_mission_waypoint_requests,"rejected_waypoints":_mission_rejected_waypoints,
		"damage_taken":_mission_damage_taken,"path_length":_mission_path_length,
		"direct_distance":direct_distance,
		"path_efficiency_ratio":minf(1.0,direct_distance/_mission_path_length) if _mission_path_length>0.001 else null,
		"severe_heading_deviations":_severe_heading_deviations,
		"waypoint_drift_events":_waypoint_drift_events,
		"ship_shear_events":_ship_shear_events,
		"target_event_triggered":(_waypoint_drift_events+_ship_shear_events)>0,
	}
	_mission_summary = summary.duplicate(true)
	ExperimentLog.log_event("mission_end","system",summary)
	ExperimentLog.record_mission(summary)
	await _show_result_flow(outcome,success,summary)
	if Game.selected_mission_id == "practice":
		_show_surveys(outcome,summary)
	elif Game.selected_mission_id == "level_1":
		# 正常条件只建立对象特定状态信任基线，没有唯一异常，不做事件责任分配。
		_show_surveys(outcome,summary)
	elif Game.selected_mission_id in ["level_2","level_3"]:
		var review := _required_review()
		if review.is_empty():
			_show_mission_attribution_surveys()
		else:
			ExperimentLog.log_event("mission_review_required","system",{
				"reason":review.code,
				"mission_id":Game.selected_mission_id,
			})
			_show_experiment_review(str(review.message))
	# 下一层先盖住飞行总结，随后再移除总结；任何一帧都不会露出驾驶舱。
	await get_tree().process_frame
	_dismiss_result_panels()


func _show_result_flow(outcome: String,success: bool,summary: Dictionary) -> void:
	_result_panels.clear()
	GameAudio.play_ui_popup_open()
	for entry: Dictionary in [
		{"role":"navigator","parent":_navigator_view},
		{"role":"pilot","parent":_pilot_view},
	]:
		var panel: Control = MissionResultPanelScript.new()
		(entry.parent as Control).add_child(panel)
		panel.setup(entry.role)
		panel.show_result(outcome,success)
		_result_panels.append(panel)
	await get_tree().create_timer(1.65,true,false,true).timeout
	GameAudio.play_ui_page_turn()
	for panel: Control in _result_panels:
		if is_instance_valid(panel):
			panel.show_summary(summary)
	await get_tree().create_timer(2.8,true,false,true).timeout
	# 保持总结页，直到责任分配／训练检查／实验员复核已经覆盖在它上面。


func _dismiss_result_panels() -> void:
	for panel: Control in _result_panels:
		if is_instance_valid(panel): panel.queue_free()
	_result_panels.clear()


func _show_surveys(outcome: String,summary: Dictionary) -> void:
	GameAudio.play_ui_popup_open()
	_show_survey_for_role("navigator",outcome,summary)
	_show_survey_for_role("pilot",outcome,summary)


func _show_survey_for_role(role: String,outcome: String,summary: Dictionary) -> void:
	var parent: Control = _navigator_view if role == "navigator" else _pilot_view
	if parent == null or parent.get_node_or_null("SurveyPanel_%s" % role) != null:
		return
	var panel: Control = SurveyPanelScript.new()
	parent.add_child(panel)
	panel.setup(role,outcome,summary)
	panel.submitted.connect(_on_survey_submitted)


func _on_survey_submitted(role: String, answers: Dictionary) -> void:
	if _survey_answers.has(role):
		return
	var linked_answers := answers.duplicate(true)
	var mission_review := Game.event_review(Game.selected_mission_id)
	linked_answers["target_event_applicable"] = str(mission_review.get("target_event_type","")) in ["waypoint_drift","ship_shear"]
	linked_answers["target_event_exposed"] = mission_review.get("target_event_exposed",null)
	linked_answers["target_event_type"] = mission_review.get("target_event_type",null)
	_survey_answers[role] = linked_answers
	ExperimentLog.record_survey(role,str(mission_review.get("event_id","mission_end")),linked_answers)
	if _survey_answers.size() < 2:
		return
	if Game.selected_mission_id == "practice":
		var review := _required_review()
		if not review.is_empty():
			_show_experiment_review(str(review.message))
			await get_tree().process_frame
			_clear_questionnaire_panels("SurveyPanel_")
			return
	await _complete_mission_questionnaires()


func _required_review() -> Dictionary:
	if Game.selected_mission_id == "practice":
		for answer: Dictionary in _survey_answers.values():
			if bool(answer.get("training_review_required",false)):
				return {
					"code":"training_comprehension",
					"message":"至少一名参与者对操作规则选择了“不确定”或“否”。\n请实验员重新说明对应规则，再让两名参与者重做训练关。",
				}
	if Game.selected_mission_id in ["level_2","level_3"]:
		var exposed := _waypoint_drift_events > 0 if Game.selected_mission_id == "level_2" else _ship_shear_events > 0
		if not exposed:
			return {
				"code":"target_event_unexposed",
				"message":"本关在结束前没有实际触发预设的目标异常，因此不能进入主要归因分析。\n请实验员确认后重试本关。",
			}
		var event_type := "waypoint_drift" if Game.selected_mission_id == "level_2" else "ship_shear"
		if Game.event_review(event_type).is_empty():
			return {
				"code":"event_review_missing",
				"message":"目标异常已经发生，但事件画面没有成功保存。\n请实验员确认后重试本关。",
			}
	if Game.selected_mission_id in ["level_1","level_2","level_3"]:
		if Game.event_review(Game.selected_mission_id).is_empty():
			return {
				"code":"mission_review_missing",
				"message":"本关结束画面没有成功保存，无法进入责任分配。\n请实验员确认后重试本关。",
			}
	return {}


func _show_mission_attribution_surveys() -> void:
	GameAudio.play_ui_popup_open()
	var record := Game.event_review(Game.selected_mission_id)
	for entry: Dictionary in [
		{"role":"navigator","parent":_navigator_view},
		{"role":"pilot","parent":_pilot_view},
	]:
		var role_name := str(entry.role)
		var panel: Control = MissionAttributionPanelScript.new()
		(entry.parent as Control).add_child(panel)
		panel.setup(role_name,Game.participant_id_for_role(role_name),record)
		panel.submitted.connect(_on_mission_attribution_submitted)


func _on_mission_attribution_submitted(role: String,answer: Dictionary) -> void:
	if _mission_attribution_answers.has(role):
		return
	_mission_attribution_answers[role] = answer.duplicate(true)
	ExperimentLog.record_survey(role,str(answer.get("event_id","mission_responsibility:%s" % Game.selected_mission_id)),answer)
	# 每名参与者独立连续作答：责任分配完成后立即进入自己的状态信任，
	# 不在两个量表之间设置双人同步点。
	_show_survey_for_role(role,_mission_outcome,_mission_summary)
	await get_tree().process_frame
	var parent: Control = _navigator_view if role == "navigator" else _pilot_view
	var attribution: Node = parent.get_node_or_null("MissionAttribution_%s" % role) if parent != null else null
	if attribution != null:
		attribution.queue_free()


func _complete_mission_questionnaires() -> void:
	# 每人连续完成责任分配和即时状态信任；这里只设置唯一一次双人等待。
	Game.mark_current_mission_played(_mission_outcome)
	var sequence_finished := Game.active_mission_id().is_empty()
	await get_tree().create_timer(0.8).timeout
	if sequence_finished:
		ExperimentLog.close_session()
		get_tree().change_scene_to_file("res://scenes/thank_you.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/level_select.tscn")


func _clear_questionnaire_panels(prefix: String) -> void:
	for parent: Control in [_navigator_view,_pilot_view]:
		for child: Node in parent.get_children():
			if child.name.begins_with(prefix):
				child.queue_free()


func _show_experiment_review(message: String) -> void:
	GameAudio.play_ui_popup_open()
	for entry: Dictionary in [
		{"role":"navigator","parent":_navigator_view},
		{"role":"pilot","parent":_pilot_view},
	]:
		var panel: Control = ExperimentReviewPanelScript.new()
		(entry.parent as Control).add_child(panel)
		panel.setup(entry.role,message)
		panel.retry_confirmed.connect(_on_review_retry_confirmed)


func _on_review_retry_confirmed() -> void:
	if _review_transitioning:
		return
	_review_transitioning = true
	ExperimentLog.log_event("mission_review_retry_confirmed","system",{
		"mission_id":Game.selected_mission_id,
	})
	Game.reset_run()
	get_tree().reload_current_scene()
