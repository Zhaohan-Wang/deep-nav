extends Node
## 左右分屏。3D 世界挂在主场景，两个 SubViewport 共用同一套世界与各自相机。

const VIEW_SIZE := Vector2i(640, 360)
const VIEW_FOV: float = 64.0
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
## 解体白屏关键帧（时间秒 → 白度）：闪两下 → 短停纯白 → 快淡出。
const DEATH_CURVE: Array[Vector2] = [
	Vector2(0.00, 0.0),
	Vector2(0.07, 0.85),
	Vector2(0.16, 0.08),
	Vector2(0.25, 0.92),
	Vector2(0.34, 0.10),
	Vector2(0.50, 1.0),
	Vector2(0.68, 1.0),
	Vector2(0.88, 0.0),
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
var _extra_window: Window
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


func _process(delta: float) -> void:
	if _ship == null or _nav_camera == null or _pilot_camera == null:
		return
	var shake: Vector3 = _shake.tick(delta)
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


func _bind_inputs() -> void:
	_bind_key("thrust", KEY_W)
	_bind_key("brake", KEY_S)
	_bind_key("turn_left", KEY_A)
	_bind_key("turn_right", KEY_D)
	_bind_key("cycle_view", KEY_F2)
	_bind_key("dual_window", KEY_F3)
	_bind_key("reset_run", KEY_R)


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

	var bezel: ColorRect = UiStyle.make_color_rect(Color("05060a"))
	bezel.custom_minimum_size = Vector2(6.0, 0.0)
	_split.add_child(bezel)

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
	_pilot_viewport.add_child(_pilot_camera)
	_pilot_fog_mat = _attach_depth_fog(_pilot_camera)
	_pilot_camera.make_current()
	_pilot_camera.global_transform = _ship.pilot_mount.global_transform
	# 驾驶舱摇杆挂在驾驶员相机下，领航员相机剔除舱内渲染层。
	_pilot_camera.add_child(CockpitStick3D.new())
	_nav_camera.cull_mask &= ~CockpitStick3D.RENDER_LAYER


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
	# 传回起点后，旧碰撞缓存可能再发一次解体。此时序列还在跑，忽略并保持能开。
	if _restarting:
		if _death_time >= DEATH_RESET_TIME:
			Game.ship_alive = true
			if _ship != null:
				_ship.snap_to_state()
		return
	_restarting = true
	_shake.add(1.35)
	_hurt_flash = 1.0
	_light_flash = 1.0
	_sfx_denied.play()
	if _world != null:
		ShipBurst3D.play(_world, world_pos)
	# 顿帧强化冲击 → 白屏闪两下后拉到纯白 → 纯白遮挡下传回出生点 → 淡出。
	Engine.time_scale = 0.08
	await get_tree().create_timer(0.09, true, false, true).timeout
	Engine.time_scale = 1.0
	_death_time = 0.0
	await get_tree().create_timer(DEATH_RESET_TIME, true, false, true).timeout
	_reset_run(false)
	var total: float = DEATH_CURVE[DEATH_CURVE.size() - 1].x
	await get_tree().create_timer(total - DEATH_RESET_TIME, true, false, true).timeout
	_restarting = false


func _apply_view_mode(mode: int) -> void:
	if mode != Game.ViewMode.DUAL_WINDOW:
		_close_extra_window()
	_nav_slot.visible = mode != Game.ViewMode.PILOT_ONLY
	_pilot_slot.visible = mode != Game.ViewMode.NAVIGATOR_ONLY
	if mode == Game.ViewMode.DUAL_WINDOW:
		_open_extra_window()


func _toggle_dual_window() -> void:
	if Game.view_mode == Game.ViewMode.DUAL_WINDOW:
		Game.set_view_mode(Game.ViewMode.SPLIT)
	else:
		Game.set_view_mode(Game.ViewMode.DUAL_WINDOW)


func _open_extra_window() -> void:
	if _extra_window != null:
		return
	_extra_window = Window.new()
	_extra_window.title = "DeepNav — 驾驶员"
	_extra_window.size = Vector2i(960, 1080)
	var screen_index: int = mini(1, DisplayServer.get_screen_count() - 1)
	_extra_window.current_screen = screen_index
	_extra_window.position = DisplayServer.screen_get_position(screen_index)
	_extra_window.close_requested.connect(_on_extra_close)
	add_child(_extra_window)
	# 副窗同样用 16:9 页框，避免驾驶员页被拉成竖屏。
	var extra_page: Control = UiStyle.make_wide_page_frame(_pilot_view)
	extra_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_extra_window.add_child(extra_page)
	_nav_slot.size_flags_stretch_ratio = 1.0
	_pilot_slot.visible = false


func _close_extra_window() -> void:
	if _extra_window == null:
		return
	# 副窗关掉后，把驾驶员页塞回左侧 16:9 页框。
	var pilot_frame: AspectRatioContainer = _find_page_frame(_pilot_slot)
	if _pilot_view.get_parent() != pilot_frame and pilot_frame != null:
		_pilot_view.reparent(pilot_frame)
	_extra_window.queue_free()
	_extra_window = null
	_pilot_slot.visible = true
	_nav_slot.size_flags_stretch_ratio = 1.0


func _find_page_frame(slot: Control) -> AspectRatioContainer:
	for child in slot.get_children():
		if child is AspectRatioContainer:
			return child as AspectRatioContainer
	return null


func _on_extra_close() -> void:
	Game.set_view_mode(Game.ViewMode.SPLIT)


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


func _on_complete_sfx() -> void:
	_sfx_complete.play()
