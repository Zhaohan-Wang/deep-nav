extends Node
## 全流程双屏协调器：共用页面镜像到副屏，任务中副屏承载驾驶员专属页面。
##
## 输入与光标的三条铁律（互相配合，缺一不可）：
## 1. hover 必须跟随事件坐标：根窗口启用子窗口内嵌（gui_embed_subwindows=true）。
##    Godot 在原生多窗口模式下会按真实 OS 指针的位置计算 hover（Viewport::_update_mouse_over
##    走 DisplayServer 分支），合成事件的 hover 会被真实指针不断覆盖，表现为闪烁。
##    内嵌模式下 hover 只看事件自身坐标；需要真正落在第二块屏的窗口用 force_native 保持原生。
##    副作用红利：OptionButton 等弹窗变成内嵌窗口，虚拟鼠标的合成事件也能点到。
## 2. 系统合并指针不参与交互但必须与席位 A 保持同位：双鼠标模式下把它钉在焦点窗口内
##    对应席位光标的位置上。这样它残余的真实事件计算出的 hover 与虚拟光标一致，不会打架。
##    它的事件本体全部吞掉，避免重复点击。
## 3. 系统光标永远不可见：全部形状替换成透明贴图 + 常驻 MOUSE_MODE_HIDDEN。
##
## 光标显示方案（核心原则：每个席位的光标只画一份，且必须画在事件所在的画布里）：
## - 席位 A：不透明，画在根窗口画布上（合成事件也推给根窗口，坐标同源，永远不会分家）。
## - 席位 B：主屏画布上画 0.42 半透明底光标；副屏本地再画一个不透明的盖在镜像之上。
##   于是主屏看到：A 不透明 + B 半透明；副屏看到：A 不透明（镜像原样）+ B 不透明。
## 已知妥协：副屏上的席位 A 光标做不到半透明——镜像是根视口纹理的原样拷贝，无法对
## 其中的单个元素改透明度。曾用“主屏透明原生覆盖窗画不透明 A”实现过完整方案，但覆盖
## 窗与根窗口的几何对齐在 macOS 上不可靠（菜单栏避让等会造成固定偏移），表现为主屏出现
## “一实一虚”两个 A 光标且实的那个位置错误。位置严格统一优先级高于透明度效果，故移除。

signal roles_swapped(primary_role: int, secondary_role: int)
signal shared_key_input(event: InputEventKey)
## Godot 的 GUI hover 是 Viewport 全局单指针；这里立即保存每个实体鼠标各自命中的控件。
signal seat_hover_changed(seat: int, hovered: Control)

enum Role { NAVIGATOR, PILOT }

const PRIMARY_SEAT_POINTER_DEVICE: int = 1101
const SECONDARY_SEAT_POINTER_DEVICE: int = 1102
const COMPANION_CURSOR_OPACITY: float = 0.42
const SYSTEM_CURSOR_SHAPE_COUNT: int = 17
const DISPLAY_RECHECK_SECONDS: float = 2.0
const POINTER_PARK_TOLERANCE_PX: float = 2.0
const HID_KEY_A: int = 0x04
const HID_KEY_D: int = 0x07
const HID_KEY_S: int = 0x16
const HID_KEY_W: int = 0x1A

var _secondary_window: Window
var _mirror_host: Control
var _mirror_texture: TextureRect
var _role_host: Control
var _cursor_layer: CanvasLayer
var _secondary_cursor_layer: CanvasLayer
var _cursor_a: VirtualCursor
var _cursor_b: VirtualCursor
var _secondary_cursor: VirtualCursor
var _pointer_hint: Label
var _seat_a_pos: Vector2 = Vector2.ZERO
var _seat_b_pos: Vector2 = Vector2.ZERO
var _seat_buttons: Dictionary = {0: {}, 1: {}}
var _shared_mode: bool = true
var _role_pointer_on_secondary: bool = false
var _last_screen_count: int = -1
var _display_recheck_elapsed: float = 0.0
var _raw_mouse_mode: bool = false
var _raw_status: String = "正在等待两只外接鼠标"
var _primary_role: int = Role.NAVIGATOR
var _transparent_system_cursor: Texture2D
var _cursors_placed: bool = false


func _ready() -> void:
	# SceneTree 暂停后仍需维护双屏虚拟光标，并把 ESC 转交给暂停菜单。
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 铁律 1：内嵌子窗口，让 hover 跟随事件坐标；双屏窗口用 force_native 保持原生。
	get_tree().root.gui_embed_subwindows = true
	_install_transparent_system_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_build_secondary_window()
	_build_shared_pointer_overlay()
	RawMice.mouse_motion.connect(_on_raw_mouse_motion)
	RawMice.mouse_button.connect(_on_raw_mouse_button)
	RawMice.mouse_wheel.connect(_on_raw_mouse_wheel)
	RawMice.device_changed.connect(_on_raw_mouse_device_changed)
	RawMice.keyboard_device_changed.connect(_on_raw_keyboard_device_changed)
	RawMice.bridge_status.connect(_on_raw_mouse_bridge_status)
	call_deferred("_finish_startup")


func _process(delta: float) -> void:
	if _shared_mode and not _cursors_placed:
		_center_shared_cursors()
	_enforce_cursor_policy()
	_display_recheck_elapsed += delta
	if _display_recheck_elapsed >= DISPLAY_RECHECK_SECONDS:
		_display_recheck_elapsed = 0.0
		var count := maxi(DisplayServer.get_screen_count(), 1)
		if count != _last_screen_count:
			_layout_windows()


func _input(event: InputEvent) -> void:
	if event.device == PRIMARY_SEAT_POINTER_DEVICE or event.device == SECONDARY_SEAT_POINTER_DEVICE:
		return
	if _raw_mouse_mode and event is InputEventMouse:
		# 铁律 2：系统合并指针的事件不参与交互；真正的点击由 HID 席位事件合成。
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		# 单鼠标回退：真实指针驱动席位 A 光标，事件本身继续正常派发给 GUI。
		_seat_a_pos = _clamp_to_root((event as InputEventMouseMotion).position)
		if _shared_mode:
			_update_shared_cursors()
		else:
			_role_pointer_on_secondary = false
			_update_role_cursors()
			_refresh_role_cursor_visibility()
		return
	if not _shared_mode:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.physical_keycode == KEY_F4 and key.pressed and not key.echo:
			swap_roles()
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_F6 and key.pressed and not key.echo:
			RawMice.swap_mouse_seats()
			get_viewport().set_input_as_handled()


func _build_secondary_window() -> void:
	_secondary_window = Window.new()
	_secondary_window.visible = false
	_secondary_window.name = "PilotDisplay"
	_secondary_window.title = "DeepNav — 席位 B"
	_secondary_window.borderless = true
	_secondary_window.unresizable = true
	_secondary_window.transient = false
	_secondary_window.force_native = DisplayServer.get_name() != "headless"
	# 副屏自己的弹窗（问卷下拉等）内嵌在副屏窗口里，别飘回主屏。
	_secondary_window.gui_embed_subwindows = true
	# 关键：新建 Window 默认不做内容缩放（content_scale_mode=DISABLED），UI 会按显示器
	# 原生像素 1:1 绘制。副屏必须与主窗口一样套设计分辨率，具体数值随页面切换：
	# 共用页 1920×1080，任务页 960×540（见 _role_stage_resolution 的历史依据）。
	_apply_window_content_scale(_secondary_window, _design_resolution())
	_secondary_window.close_requested.connect(_on_secondary_close_requested)
	_secondary_window.window_input.connect(_on_secondary_window_input)
	add_child(_secondary_window)

	var background := ColorRect.new()
	background.color = Color("05060a")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_secondary_window.add_child(background)

	_mirror_host = Control.new()
	_mirror_host.name = "SharedPageMirror"
	_mirror_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mirror_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_secondary_window.add_child(_mirror_host)
	_mirror_texture = TextureRect.new()
	_mirror_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mirror_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mirror_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mirror_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_mirror_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mirror_host.add_child(_mirror_texture)

	_role_host = Control.new()
	_role_host.name = "RolePageHost"
	_role_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_role_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_role_host.visible = false
	_secondary_window.add_child(_role_host)
	_secondary_cursor_layer = CanvasLayer.new()
	_secondary_cursor_layer.layer = 100
	_secondary_window.add_child(_secondary_cursor_layer)
	_secondary_cursor = VirtualCursor.new()
	_secondary_cursor.role_name = "屏幕 B"
	_secondary_cursor.accent = UiStyle.AMBER
	_secondary_cursor.active = true
	_secondary_cursor_layer.add_child(_secondary_cursor)


func _build_shared_pointer_overlay() -> void:
	# 根画布光标层：席位 A 不透明（这就是唯一的一份 A 光标），席位 B 半透明底光标。
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.layer = 100
	add_child(_cursor_layer)
	_cursor_a = VirtualCursor.new()
	_cursor_a.role_name = "屏幕 A"
	_cursor_a.accent = UiStyle.CYAN
	_cursor_a.active = true
	_cursor_layer.add_child(_cursor_a)
	_cursor_b = VirtualCursor.new()
	_cursor_b.role_name = "屏幕 B"
	_cursor_b.accent = UiStyle.AMBER
	_cursor_b.active = false
	_cursor_b.modulate.a = COMPANION_CURSOR_OPACITY
	_cursor_layer.add_child(_cursor_b)
	_pointer_hint = AppStyle.label("正在连接双鼠标输入…", 16, AppStyle.MUTED)
	_pointer_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pointer_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_pointer_hint.offset_top = -34.0
	_pointer_hint.offset_bottom = -8.0
	_pointer_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_layer.add_child(_pointer_hint)


func _finish_startup() -> void:
	_mirror_texture.texture = get_tree().root.get_texture()
	_layout_windows()
	_center_shared_cursors()
	# RawMice 比 Displays 更早加载。即使设备消息在本节点接好信号前已经到达，
	# 也必须从单例当前状态恢复双鼠标模式，不能退回 macOS 合并指针。
	_sync_raw_mouse_state()
	# 守卫：直接以任务场景启动时，主场景的 show_role_page 可能已先执行；不得踩回共用页。
	if _shared_mode:
		show_shared_page()
	else:
		_refresh_cursor_visibility()


func _layout_windows() -> void:
	if _secondary_window == null:
		return
	var count := maxi(DisplayServer.get_screen_count(), 1)
	_last_screen_count = count
	var root := get_tree().root
	var main_screen := clampi(root.current_screen, 0, count - 1)
	if count >= 2:
		var pilot_screen := _first_other_screen(main_screen, count)
		_fit_window_to_screen(root, main_screen)
		_fit_window_to_screen(_secondary_window, pilot_screen)
		print("DUAL_DISPLAY_READY screens=%d primary_seat=%d secondary_seat=%d" % [count, main_screen, pilot_screen])
	else:
		var screen_position := DisplayServer.screen_get_position(0)
		var screen_size := DisplayServer.screen_get_size(0)
		var left_width := maxi(screen_size.x / 2, 1)
		root.borderless = true
		root.position = screen_position
		root.size = Vector2i(left_width, screen_size.y)
		_secondary_window.borderless = true
		_secondary_window.position = screen_position + Vector2i(left_width, 0)
		_secondary_window.size = Vector2i(maxi(screen_size.x - left_width, 1), screen_size.y)
		print("DUAL_DISPLAY_PREVIEW screens=1 split_on_primary=true")
	_secondary_window.show()
	_refresh_cursor_visibility()


func _first_other_screen(main_screen: int, screen_count: int) -> int:
	for index: int in range(screen_count):
		if index != main_screen:
			return index
	return main_screen


func _fit_window_to_screen(window: Window, screen_index: int) -> void:
	window.borderless = true
	window.current_screen = screen_index
	window.position = DisplayServer.screen_get_position(screen_index)
	window.size = DisplayServer.screen_get_size(screen_index)


func _design_resolution() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	)


func _role_stage_resolution() -> Vector2i:
	# 历史依据（git d2c153c）：任务 UI 是在“一块 1920×1080 屏并排两个 16:9 视图”里调的，
	# 旧双窗口模式的副窗口也是硬编码 960×1080、视图 960×540。因此单个任务视图的设计
	# 空间是设计分辨率的一半（960×540）；任务页按它渲染，再由引擎放大铺满整屏，
	# 布局与老版本逐像素一致。
	return _design_resolution() / 2


func _apply_window_content_scale(window: Window, size: Vector2i) -> void:
	window.content_scale_size = size
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _set_stage_resolution(target: Vector2i) -> void:
	var root := get_tree().root
	if root.content_scale_size == target and _secondary_window.content_scale_size == target:
		return
	# 换设计空间时按比例迁移两个席位光标，避免留在旧坐标系里跑出屏幕。
	var before := Vector2(root.get_visible_rect().size)
	_apply_window_content_scale(root, target)
	_apply_window_content_scale(_secondary_window, target)
	var after := Vector2(root.get_visible_rect().size)
	if before.x > 0.0 and before.y > 0.0:
		var ratio := after / before
		_seat_a_pos = _clamp_to_root(_seat_a_pos * ratio)
		_seat_b_pos *= ratio


func show_shared_page() -> void:
	_shared_mode = true
	_set_stage_resolution(_design_resolution())
	_refresh_cursor_identity()
	if _mirror_host != null:
		_mirror_host.visible = true
	if _role_host != null:
		_role_host.visible = false
	_refresh_cursor_visibility()
	_refresh_pointer_hint()
	if not _cursors_placed:
		_center_shared_cursors()
	else:
		_update_shared_cursors()


func show_role_page(content: Control) -> Window:
	_shared_mode = false
	_set_stage_resolution(_role_stage_resolution())
	_refresh_cursor_identity()
	_mirror_host.visible = false
	_role_host.visible = true
	if content.get_parent() != _role_host:
		if content.get_parent() == null:
			_role_host.add_child(content)
		else:
			content.reparent(_role_host)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_seat_b_pos = _secondary_window.get_visible_rect().size * 0.5
	_update_role_cursors()
	_refresh_cursor_visibility()
	_refresh_pointer_hint()
	return _secondary_window


func release_role_page(content: Control = null) -> void:
	if content != null and content.get_parent() == _role_host:
		_role_host.remove_child(content)
	_center_shared_cursors()
	show_shared_page()


func secondary_window() -> Window:
	return _secondary_window


func relayout() -> void:
	_layout_windows()


func display_status() -> String:
	var count := maxi(DisplayServer.get_screen_count(), 1)
	return "已检测到 %d 块显示器 · 全流程双屏已启用" % count if count >= 2 else "当前仅检测到 1 块显示器 · 使用左右双窗预览"


func primary_role() -> int:
	return _primary_role


func secondary_role() -> int:
	return Role.PILOT if _primary_role == Role.NAVIGATOR else Role.NAVIGATOR


func role_for_seat(seat: int) -> int:
	return primary_role() if seat == 0 else secondary_role()


func role_name_for_seat(seat: int) -> String:
	return "navigator" if role_for_seat(seat) == Role.NAVIGATOR else "pilot"


func seat_cursor_position(seat: int) -> Vector2:
	return _seat_a_pos if seat == 0 else _seat_b_pos


func seat_button_pressed(seat: int, button: int = MOUSE_BUTTON_LEFT) -> bool:
	return bool((_seat_buttons.get(seat,{}) as Dictionary).get(button,false))


func uses_raw_mouse_mode() -> bool:
	return _raw_mouse_mode


func pilot_seat() -> int:
	return 0 if primary_role() == Role.PILOT else 1


func pilot_turn_axis() -> float:
	var seat := pilot_seat()
	if RawMice.has_keyboard(seat):
		return float(RawMice.is_hid_key_pressed(seat, HID_KEY_A)) - float(RawMice.is_hid_key_pressed(seat, HID_KEY_D))
	return Input.get_axis("turn_right", "turn_left") if not RawMice.is_ready() else 0.0


func pilot_thrust_axis() -> float:
	var seat := pilot_seat()
	if RawMice.has_keyboard(seat):
		return float(RawMice.is_hid_key_pressed(seat, HID_KEY_W)) - float(RawMice.is_hid_key_pressed(seat, HID_KEY_S))
	return Input.get_axis("brake", "thrust") if not RawMice.is_ready() else 0.0


func swap_roles() -> void:
	_primary_role = secondary_role()
	_refresh_cursor_identity()
	roles_swapped.emit(primary_role(), secondary_role())
	if Game.experiment_mode:
		ExperimentLog.log_event("display_roles_swapped","system",{
			"screen_a_role":role_name_for_seat(0),
			"screen_b_role":role_name_for_seat(1),
		})
	print("DISPLAY_ROLES_SWAPPED primary=%s secondary=%s" % [_role_name(primary_role()), _role_name(secondary_role())])


func set_primary_role(role: int) -> void:
	# 任务开始确认页的认领结果直接指定“主屏显示哪个岗位”，副屏自动取另一个。
	if _primary_role == role:
		return
	_primary_role = role
	_refresh_cursor_identity()
	roles_swapped.emit(primary_role(), secondary_role())
	print("DISPLAY_ROLES_ASSIGNED primary=%s secondary=%s" % [_role_name(primary_role()), _role_name(secondary_role())])


func _role_name(role: int) -> String:
	return "领航员" if role == Role.NAVIGATOR else "驾驶员"


func _refresh_cursor_identity() -> void:
	if _shared_mode:
		# 岗位尚未分配或当前为共用页面时，只显示固定的屏幕席位。
		_cursor_a.role_name = "屏幕 A"
		_cursor_a.accent = UiStyle.CYAN
		_cursor_b.role_name = "屏幕 B"
		_cursor_b.accent = UiStyle.AMBER
		_secondary_cursor.role_name = "屏幕 B"
		_secondary_cursor.accent = UiStyle.AMBER
		_secondary_window.title = "DeepNav — 席位 B"
	else:
		var primary_is_nav := primary_role() == Role.NAVIGATOR
		_cursor_a.role_name = "领航" if primary_is_nav else "驾驶"
		_cursor_a.accent = UiStyle.CYAN if primary_is_nav else UiStyle.AMBER
		_cursor_b.role_name = "驾驶" if primary_is_nav else "领航"
		_cursor_b.accent = UiStyle.AMBER if primary_is_nav else UiStyle.CYAN
		_secondary_cursor.role_name = _cursor_b.role_name
		_secondary_cursor.accent = _cursor_b.accent
		_secondary_window.title = "DeepNav — 席位 B · %s" % _role_name(secondary_role())
	_cursor_a.queue_redraw()
	_cursor_b.queue_redraw()
	_secondary_cursor.queue_redraw()


func _on_secondary_window_input(event: InputEvent) -> void:
	if event.device == SECONDARY_SEAT_POINTER_DEVICE:
		return
	if _raw_mouse_mode and event is InputEventMouse:
		_secondary_window.set_input_as_handled()
		return
	if not _shared_mode:
		if event is InputEventMouseMotion:
			# 单鼠标回退：真实指针进入副屏时，用席位 B 光标显示它的位置。
			_role_pointer_on_secondary = true
			_seat_b_pos = (event as InputEventMouseMotion).position
			_update_role_cursors()
			_refresh_role_cursor_visibility()
		return
	if event is InputEventMouseMotion:
		_seat_b_pos = _secondary_to_root((event as InputEventMouseMotion).position)
		_update_shared_cursors()
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		_seat_b_pos = _secondary_to_root(mouse.position)
		_push_pilot_button(mouse.pressed, mouse.button_index)
	elif event is InputEventKey:
		# 共用页可能因 macOS 把副屏原生窗口置为活动窗口而收不到文字输入。
		# 直接交给当前共用页，避免原生子窗口之间重复派发同一事件。
		shared_key_input.emit(event as InputEventKey)
		_secondary_window.set_input_as_handled()


func _push_pilot_button(pressed: bool, button_index: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_push_root_button(SECONDARY_SEAT_POINTER_DEVICE, _seat_b_pos, pressed, button_index)


func _push_root_button(device: int, position: Vector2, pressed: bool, button_index: MouseButton = MOUSE_BUTTON_LEFT, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.device = device
	event.position = position
	event.global_position = position
	event.button_index = button_index
	event.pressed = pressed
	event.factor = factor
	get_tree().root.push_input(event, true)


func _push_motion(target: Viewport, device: int, position: Vector2, delta: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = device
	event.position = position
	event.global_position = position
	event.relative = delta
	event.screen_relative = delta
	target.push_input(event, true)
	var seat := 0 if device == PRIMARY_SEAT_POINTER_DEVICE else 1
	seat_hover_changed.emit(seat, target.gui_get_hovered_control())


func _secondary_to_root(position: Vector2) -> Vector2:
	var source := get_tree().root.get_visible_rect().size
	var destination := _secondary_window.get_visible_rect().size
	if source.x <= 0.0 or source.y <= 0.0 or destination.x <= 0.0 or destination.y <= 0.0:
		return Vector2.ZERO
	var scale := minf(destination.x / source.x, destination.y / source.y)
	var rendered_size := source * scale
	var offset := (destination - rendered_size) * 0.5
	return _clamp_to_root((position - offset) / maxf(scale, 0.001))


func _root_to_secondary(position: Vector2) -> Vector2:
	var source := get_tree().root.get_visible_rect().size
	var destination := _secondary_window.get_visible_rect().size
	if source.x <= 0.0 or source.y <= 0.0 or destination.x <= 0.0 or destination.y <= 0.0:
		return Vector2.ZERO
	var scale := minf(destination.x / source.x, destination.y / source.y)
	var rendered_size := source * scale
	var offset := (destination - rendered_size) * 0.5
	return position * scale + offset


func _clamp_to_root(position: Vector2) -> Vector2:
	var bounds := get_tree().root.get_visible_rect().size
	return Vector2(
		clampf(position.x, 0.0, maxf(bounds.x - 2.0, 0.0)),
		clampf(position.y, 0.0, maxf(bounds.y - 2.0, 0.0))
	)


func _center_shared_cursors() -> void:
	var bounds := get_tree().root.get_visible_rect().size
	if bounds.x <= 2.0 or bounds.y <= 2.0:
		return
	_seat_a_pos = bounds * Vector2(0.42, 0.5)
	_seat_b_pos = bounds * Vector2(0.58, 0.5)
	_cursors_placed = true
	_update_shared_cursors()


func _update_shared_cursors() -> void:
	if not _shared_mode:
		return
	if _cursor_a != null:
		_cursor_a.position = _seat_a_pos
	if _cursor_b != null:
		_cursor_b.position = _seat_b_pos
	if _secondary_cursor != null:
		var scale := _secondary_mirror_scale()
		_secondary_cursor.scale = Vector2.ONE * scale
		_secondary_cursor.position = _root_to_secondary(_seat_b_pos)


func _update_role_cursors() -> void:
	if _shared_mode:
		return
	if _cursor_a != null:
		_cursor_a.position = _seat_a_pos
	if _secondary_cursor != null:
		_secondary_cursor.scale = Vector2.ONE
		_secondary_cursor.position = _seat_b_pos


func _secondary_mirror_scale() -> float:
	var source := get_tree().root.get_visible_rect().size
	var destination := _secondary_window.get_visible_rect().size
	if source.x <= 0.0 or source.y <= 0.0:
		return 1.0
	return minf(destination.x / source.x, destination.y / source.y)


func _on_secondary_close_requested() -> void:
	# 双屏是应用结构的一部分，误点关闭只会重新显示并重新铺屏。
	_secondary_window.show()
	call_deferred("_layout_windows")


func _on_raw_mouse_motion(slot: int, delta: Vector2) -> void:
	if not _raw_mouse_mode or (slot != 0 and slot != 1):
		return
	if _shared_mode:
		if slot == 0:
			_seat_a_pos = _clamp_to_root(_seat_a_pos + delta)
		else:
			_seat_b_pos = _clamp_to_root(_seat_b_pos + delta)
		# 先画光标，再注入 GUI；即使后续 hover 查询失败，也不能中断任一席位的光标刷新。
		_update_shared_cursors()
		if slot == 0:
			_push_motion(get_tree().root, PRIMARY_SEAT_POINTER_DEVICE, _seat_a_pos, delta)
		else:
			_push_motion(get_tree().root, SECONDARY_SEAT_POINTER_DEVICE, _seat_b_pos, delta)
	elif slot == 0:
		_seat_a_pos = _clamp_to_root(_seat_a_pos + delta)
		_update_role_cursors()
		_push_motion(get_tree().root, PRIMARY_SEAT_POINTER_DEVICE, _seat_a_pos, delta)
	else:
		var bounds := _secondary_window.get_visible_rect().size
		_seat_b_pos = Vector2(
			clampf(_seat_b_pos.x + delta.x, 0.0, maxf(bounds.x - 2.0, 0.0)),
			clampf(_seat_b_pos.y + delta.y, 0.0, maxf(bounds.y - 2.0, 0.0))
		)
		_update_role_cursors()
		_push_motion(_secondary_window, SECONDARY_SEAT_POINTER_DEVICE, _seat_b_pos, delta)


func _on_raw_mouse_button(slot: int, button: int, pressed: bool) -> void:
	if not _raw_mouse_mode or (slot != 0 and slot != 1):
		return
	var mouse_button: MouseButton = clampi(button, MOUSE_BUTTON_LEFT, MOUSE_BUTTON_XBUTTON2)
	var buttons := _seat_buttons.get(slot,{}) as Dictionary
	buttons[mouse_button] = pressed
	_seat_buttons[slot] = buttons
	_push_seat_button(slot, mouse_button, pressed)


func _on_raw_mouse_wheel(slot: int, delta: int) -> void:
	if not _raw_mouse_mode or (slot != 0 and slot != 1) or delta == 0:
		return
	# HID 滚轮正值为远离使用者（向上滚）；转成 Godot 的滚轮“按键”一压一放。
	var wheel_button: MouseButton = MOUSE_BUTTON_WHEEL_UP if delta > 0 else MOUSE_BUTTON_WHEEL_DOWN
	var factor := float(absi(delta))
	_push_seat_button(slot, wheel_button, true, factor)
	_push_seat_button(slot, wheel_button, false, factor)


func _push_seat_button(slot: int, button_index: MouseButton, pressed: bool, factor: float = 1.0) -> void:
	if _shared_mode or slot == 0:
		var position := _seat_a_pos if slot == 0 else _seat_b_pos
		var device := PRIMARY_SEAT_POINTER_DEVICE if slot == 0 else SECONDARY_SEAT_POINTER_DEVICE
		_push_root_button(device, position, pressed, button_index, factor)
	else:
		var event := InputEventMouseButton.new()
		event.device = SECONDARY_SEAT_POINTER_DEVICE
		event.position = _seat_b_pos
		event.global_position = _seat_b_pos
		event.button_index = button_index
		event.pressed = pressed
		event.factor = factor
		_secondary_window.push_input(event, true)


func _on_raw_mouse_device_changed(_slot: int, _connected: bool, _product: String) -> void:
	_sync_raw_mouse_state()


func _sync_raw_mouse_state() -> void:
	_raw_mouse_mode = RawMice.is_ready() and RawMice.connected_mouse_count() >= 2
	if _raw_mouse_mode:
		_raw_status = "鼠标 A %s · 鼠标 B %s · %s · F6 只校正鼠标" % [
			RawMice.device_name(0),RawMice.device_name(1),_keyboard_status(),
		]
	else:
		_raw_status = "鼠标 %d / 2 · %s" % [RawMice.connected_mouse_count(),_keyboard_status()]
		seat_hover_changed.emit(0, null)
		seat_hover_changed.emit(1, null)
	_refresh_cursor_visibility()
	_refresh_pointer_hint()


func _on_raw_keyboard_device_changed(_slot: int,_connected: bool,_product: String) -> void:
	_on_raw_mouse_device_changed(-1,false,"")


func _keyboard_status() -> String:
	var a := RawMice.keyboard_name(0)
	var b := RawMice.keyboard_name(1)
	return "键盘 A（内置）%s · 键盘 B（外接）%s" % [
		"✓" if not a.is_empty() else "缺失",
		"✓" if not b.is_empty() else "缺失",
	]


func _on_raw_mouse_bridge_status(ready: bool, message: String) -> void:
	_raw_status = message
	if ready:
		_sync_raw_mouse_state()
	else:
		_raw_mouse_mode = false
		seat_hover_changed.emit(0, null)
		seat_hover_changed.emit(1, null)
		_refresh_cursor_visibility()
		_refresh_pointer_hint()


func _refresh_cursor_visibility() -> void:
	if _cursor_layer == null or _secondary_cursor_layer == null:
		return
	if _shared_mode:
		# 共用页面：根画布画不透明 A + 半透明 B（都进镜像），副屏本地再叠不透明 B。
		_cursor_layer.visible = true
		_cursor_a.visible = true
		_cursor_b.visible = true
		_secondary_cursor_layer.visible = true
		_secondary_cursor.visible = true
		_update_shared_cursors()
	else:
		# 任务页面：没有镜像，各窗口只画自己席位的不透明光标；半透明底光标不再需要。
		_cursor_layer.visible = true
		_cursor_b.visible = false
		_secondary_cursor_layer.visible = true
		if _raw_mouse_mode:
			_cursor_a.visible = true
			_secondary_cursor.visible = true
		else:
			_refresh_role_cursor_visibility()
		_update_role_cursors()


func _refresh_role_cursor_visibility() -> void:
	# 单鼠标回退的任务页面：唯一的真实指针在哪块屏上，就只显示那块屏的光标。
	if _shared_mode or _raw_mouse_mode:
		return
	_cursor_a.visible = not _role_pointer_on_secondary
	_secondary_cursor.visible = _role_pointer_on_secondary


func _install_transparent_system_cursor() -> void:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_transparent_system_cursor = ImageTexture.create_from_image(image)
	for shape: int in range(SYSTEM_CURSOR_SHAPE_COUNT):
		Input.set_custom_mouse_cursor(_transparent_system_cursor, shape, Vector2.ZERO)


func _exit_tree() -> void:
	for shape: int in range(SYSTEM_CURSOR_SHAPE_COUNT):
		Input.set_custom_mouse_cursor(null, shape)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _enforce_cursor_policy() -> void:
	# 铁律 3：常驻隐藏。铁律 2：双鼠标模式下把合并指针钉在焦点窗口内对应席位光标的位置。
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if not _raw_mouse_mode:
		return
	var root := get_tree().root
	if root.has_focus():
		_park_pointer(root, root.get_final_transform() * _seat_a_pos)
	elif _secondary_window != null and _secondary_window.has_focus():
		var local := _root_to_secondary(_seat_b_pos) if _shared_mode else _seat_b_pos
		_park_pointer(_secondary_window, _secondary_window.get_final_transform() * local)


func _park_pointer(window: Window, pixel_pos: Vector2) -> void:
	var target_global := Vector2(window.position) + pixel_pos
	if target_global.distance_to(Vector2(DisplayServer.mouse_get_position())) > POINTER_PARK_TOLERANCE_PX:
		DisplayServer.warp_mouse(Vector2i(pixel_pos))


func _refresh_pointer_hint() -> void:
	if _pointer_hint == null:
		return
	_pointer_hint.visible = _shared_mode
	_pointer_hint.text = _raw_status if _raw_mouse_mode else "%s · 备用：驾驶员 WASD + F / 手柄左摇杆 + A" % _raw_status
