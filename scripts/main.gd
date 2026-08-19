extends Node
## 左右分屏。3D 世界挂在主场景，两个 SubViewport 共用同一套世界与各自相机。

const SurveyPanelScript = preload("res://scripts/ui/survey_panel.gd")
const MissionResultPanelScript = preload("res://scripts/ui/mission_result_panel.gd")

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
var _sfx_confirm: AudioStreamPlayer
var _sfx_denied: AudioStreamPlayer
var _sfx_complete: AudioStreamPlayer
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
var _mission_deaths: int = 0
var _mission_hits: int = 0
var _mission_waypoints: int = 0
var _mission_finishing: bool = false
var _mission_ended: bool = false
var _mission_outcome: String = ""
var _survey_answers: Dictionary = {}
var _result_panels: Array[Control] = []


func _ready() -> void:
	_bind_inputs()
	_build_audio()
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
	Game.safe_gate_crossed.connect(_on_safe_gate_crossed)
	Game.relay_station_reached.connect(_on_relay_station_reached)
	Displays.roles_swapped.connect(_on_display_roles_swapped)
	# 双屏贯穿整个应用；单显示器环境也保留两个并排窗口用于开发预览。
	Game.set_view_mode(Game.ViewMode.DUAL_WINDOW)


func _process(delta: float) -> void:
	if _ship == null or _nav_camera == null or _pilot_camera == null:
		return
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
	if not _mission_ended and not _mission_finishing and Game.current_sector != null:
		_mission_elapsed += delta
		if _mission_elapsed >= Game.current_sector.time_limit_s:
			_mission_elapsed = Game.current_sector.time_limit_s
			_begin_mission_end("超时未完成",false)


func _physics_process(_delta: float) -> void:
	ExperimentLog.sample_frame()


func _unhandled_input(event: InputEvent) -> void:
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
	elif event.is_action_pressed("swap_mouse_seats"):
		RawMice.swap_mouse_seats()
		get_viewport().set_input_as_handled()


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
	_bind_key("swap_mouse_seats", KEY_F6)


func _bind_key(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	else:
		InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _build_audio() -> void:
	_sfx_confirm = _make_player("res://assets/audio/ui/Confirm_01.ogg")
	_sfx_denied = _make_player("res://assets/audio/ui/Denied_02.ogg")
	_sfx_complete = _make_player("res://assets/audio/ui/Complete_01.ogg")


func _make_player(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = load(path) as AudioStream
	player.bus = "Master"
	add_child(player)
	return player


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
	var checkpoint := Game.last_respawn_point()
	Game.respawn_ship_at(checkpoint.position,checkpoint.heading)
	if _ship != null:
		_ship.snap_to_state()
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
	_sfx_denied.play()
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
		_sfx_confirm.play()


func _on_waypoint_request_result(accepted: bool, reason: String, remaining_s: float) -> void:
	if accepted:
		_mission_waypoints += 1
	if not accepted: _sfx_denied.play()
	ExperimentLog.log_event("waypoint_request","navigator",{
		"accepted":accepted,"reason":reason,"remaining_s":remaining_s,"ship_x":Game.ship_position.x,"ship_z":Game.ship_position.z
	})


func _on_disturbance_gate_crossed(index: int,slot: String,anchor: Vector3) -> void:
	ExperimentLog.log_event("disturbance_gate_crossed","system",{
		"index":index,"slot":slot,"anchor_x":anchor.x,"anchor_z":anchor.z
	})


func _on_safe_gate_crossed(index: int,anchor: Vector3) -> void:
	ExperimentLog.log_event("safe_gate_crossed","system",{
		"index":index,"anchor_x":anchor.x,"anchor_z":anchor.z
	})


func _on_relay_station_reached(index: int,position: Vector3,station_name: String) -> void:
	ExperimentLog.log_event("relay_station_reached","system",{
		"index":index,"name":station_name,"x":position.x,"z":position.z
	})


func _on_complete_sfx() -> void:
	_sfx_complete.play()


func _on_mission_success() -> void:
	_begin_mission_end("完成",true)


func _begin_mission_end(outcome: String,success: bool) -> void:
	if _mission_ended or _mission_finishing:
		return
	_mission_finishing = true
	_mission_outcome = outcome
	Engine.time_scale = 1.0
	if not success:
		# 时间耗尽才是失败条件；此时以完整爆炸反馈结束当前飞行。
		if Game.ship_alive:
			Game.explode_ship()
		await get_tree().create_timer(1.25,true,false,true).timeout
	else:
		await get_tree().create_timer(0.65,true,false,true).timeout
	_mission_ended = true
	var limit := Game.current_sector.time_limit_s if Game.current_sector != null else _mission_elapsed
	var summary := {
		"outcome":outcome,"success":success,"elapsed":_mission_elapsed,"limit":limit,
		"revivals":_mission_deaths,"hits":_mission_hits,"waypoints":_mission_waypoints,"hull":Game.hull
	}
	ExperimentLog.log_event("mission_end","system",summary)
	await _show_result_flow(outcome,success,summary)
	_show_surveys(outcome,summary)


func _show_result_flow(outcome: String,success: bool,summary: Dictionary) -> void:
	_result_panels.clear()
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
	for panel: Control in _result_panels:
		if is_instance_valid(panel):
			panel.show_summary(summary)
	await get_tree().create_timer(2.8,true,false,true).timeout
	for panel: Control in _result_panels:
		if is_instance_valid(panel):
			panel.queue_free()
	_result_panels.clear()
	await get_tree().process_frame


func _show_surveys(outcome: String,summary: Dictionary) -> void:
	var nav: Control = SurveyPanelScript.new(); _navigator_view.add_child(nav); nav.setup("navigator",outcome,summary); nav.submitted.connect(_on_survey_submitted)
	var pilot: Control = SurveyPanelScript.new(); _pilot_view.add_child(pilot); pilot.setup("pilot",outcome,summary); pilot.submitted.connect(_on_survey_submitted)


func _on_survey_submitted(role: String, answers: Dictionary) -> void:
	_survey_answers[role]=answers; ExperimentLog.record_survey(role,"mission_end",answers)
	if _survey_answers.size() >= 2:
		# 两人均提交才算真正玩完本关；完成、超时等结果都锁住本关并推进队列。
		Game.mark_current_mission_played(_mission_outcome)
		var sequence_finished := Game.active_mission_id().is_empty()
		await get_tree().create_timer(0.8).timeout
		Game.set_view_mode(Game.ViewMode.SPLIT)
		if sequence_finished:
			# 最后一关量表落盘后结束本次实验，再进入双屏共享的感谢页。
			ExperimentLog.close_session()
			get_tree().change_scene_to_file("res://scenes/thank_you.tscn")
		else:
			get_tree().change_scene_to_file("res://scenes/level_select.tscn")
