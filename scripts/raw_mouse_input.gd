extends Node
## macOS 原始 HID 鼠标输入：由独立原生桥接进程按物理设备区分两只鼠标。

signal mouse_motion(slot: int, delta: Vector2)
signal mouse_button(slot: int, button: int, pressed: bool)
signal mouse_wheel(slot: int, delta: int)
signal device_changed(slot: int, connected: bool, product: String)
signal keyboard_device_changed(slot: int, connected: bool, product: String)
signal key_changed(slot: int, usage: int, pressed: bool)
signal bridge_status(ready: bool, message: String)

const BRIDGE_PATH := "res://native/macos/bin/deepnav-hid-mouse-bridge"
const UDP_PORT: int = 39271
const BIND_RETRY_SECONDS: float = 2.0

var _udp: PacketPeerUDP
var _bridge_pid: int = -1
var _devices: Dictionary = {}
var _keyboards: Dictionary = {}
var _pressed_keys: Dictionary = {0: {}, 1: {}}
## 鼠标允许 F6 校正左右；键盘固定为内置=A、外接=B，绝不跟随鼠标交换。
var _mouse_slots_to_seats: Dictionary = {0: 0, 1: 1}
var _bridge_ready: bool = false
var _platform_supported: bool = false
var _listening: bool = false
var _bind_retry_elapsed: float = 0.0


func _ready() -> void:
	# 暂停菜单仍要接收两只鼠标和两个键盘的原始输入。
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		return
	if OS.get_name() != "macOS":
		bridge_status.emit(false, "当前原始双鼠标桥仅支持 macOS")
		return
	_platform_supported = true
	_try_start_listening()


func _process(delta: float) -> void:
	if not _platform_supported:
		return
	if not _listening:
		# 上一个进程实例退出较慢时端口会短暂被占；持续重试直到绑定成功。
		_bind_retry_elapsed += delta
		if _bind_retry_elapsed >= BIND_RETRY_SECONDS:
			_bind_retry_elapsed = 0.0
			_try_start_listening()
		return
	while _udp.get_available_packet_count() > 0:
		var raw := _udp.get_packet().get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			_handle_message(parsed as Dictionary)


func _try_start_listening() -> void:
	if _udp == null:
		_udp = PacketPeerUDP.new()
	var bind_error := _udp.bind(UDP_PORT, "127.0.0.1")
	if bind_error != OK:
		_udp.close()
		bridge_status.emit(false, "双鼠标输入端口被占用，正在重试…")
		print("RAW_MOUSE_BIND_RETRY error=%s" % error_string(bind_error))
		return
	var executable := _bridge_executable()
	if not FileAccess.file_exists(executable):
		_udp.close()
		bridge_status.emit(false, "缺少双鼠标桥接程序，请先运行 tools/build_macos_hid_bridge.sh")
		return
	_bridge_pid = OS.create_process(executable, PackedStringArray([str(UDP_PORT)]))
	if _bridge_pid < 0:
		_udp.close()
		bridge_status.emit(false, "双鼠标桥接程序启动失败")
		return
	_listening = true


func _bridge_executable() -> String:
	if not OS.has_feature("editor"):
		var bundled := OS.get_executable_path().get_base_dir().get_base_dir().path_join(
			"Helpers/deepnav-hid-mouse-bridge"
		)
		if FileAccess.file_exists(bundled):
			return bundled
	return ProjectSettings.globalize_path(BRIDGE_PATH)


func _exit_tree() -> void:
	if _bridge_pid > 0 and OS.is_process_running(_bridge_pid):
		# 先让桥接进程有机会恢复 macOS 系统光标；父进程异常退出时桥内看门狗也会自动恢复。
		OS.execute("/bin/kill", PackedStringArray(["-TERM", str(_bridge_pid)]))


func _handle_message(message: Dictionary) -> void:
	var type := str(message.get("type", ""))
	if type == "ready":
		_bridge_ready = bool(message.get("ok", false))
		var code := int(message.get("code", 0))
		var detail := "原始双鼠标输入已就绪" if _bridge_ready else "无法读取物理鼠标（错误码 %d），请在系统设置中允许输入监控" % code
		bridge_status.emit(_bridge_ready, detail)
		print("RAW_MOUSE_BRIDGE ready=%s code=%d" % [_bridge_ready, code])
	elif type == "device":
		var device_slot := int(message.get("slot", -1))
		if device_slot < 0 or device_slot > 1:
			return
		var connected := bool(message.get("connected", false))
		var kind := str(message.get("kind", "mouse"))
		var product := str(message.get("product", "HID Device"))
		if kind == "keyboard":
			var slot := device_slot
			if connected:
				_keyboards[slot] = product
			else:
				_keyboards.erase(slot)
				(_pressed_keys[slot] as Dictionary).clear()
			keyboard_device_changed.emit(slot, connected, product)
			if Game.experiment_mode:
				ExperimentLog.log_event("input_device_changed","screen_a" if slot==0 else "screen_b",{
					"kind":"keyboard","connected":connected,"product":product,
				})
			print("RAW_KEYBOARD_DEVICE seat=%d connected=%s product=%s" % [slot, connected, product])
		else:
			var slot := int(_mouse_slots_to_seats.get(device_slot, device_slot))
			if connected:
				_devices[slot] = product
			else:
				_devices.erase(slot)
			device_changed.emit(slot, connected, product)
			if Game.experiment_mode:
				ExperimentLog.log_event("input_device_changed","screen_a" if slot==0 else "screen_b",{
					"kind":"mouse","connected":connected,"product":product,
				})
			print("RAW_MOUSE_DEVICE seat=%d connected=%s product=%s" % [slot, connected, product])
	elif type == "motion":
		var device_slot := int(message.get("slot", -1))
		mouse_motion.emit(int(_mouse_slots_to_seats.get(device_slot, device_slot)), Vector2(float(message.get("dx", 0.0)), float(message.get("dy", 0.0))))
	elif type == "button":
		var device_slot := int(message.get("slot", -1))
		mouse_button.emit(int(_mouse_slots_to_seats.get(device_slot, device_slot)), int(message.get("button", 1)), bool(message.get("pressed", false)))
	elif type == "wheel":
		var device_slot := int(message.get("slot", -1))
		mouse_wheel.emit(int(_mouse_slots_to_seats.get(device_slot, device_slot)), int(message.get("delta", 0)))
	elif type == "key":
		var device_slot := int(message.get("slot", -1))
		var seat := device_slot
		var usage := int(message.get("usage", 0))
		var pressed := bool(message.get("pressed", false))
		if seat >= 0 and seat <= 1:
			var keys := _pressed_keys[seat] as Dictionary
			var was_pressed := keys.has(usage)
			if was_pressed==pressed:
				return
			if pressed:
				keys[usage] = true
			else:
				keys.erase(usage)
			key_changed.emit(seat, usage, pressed)
			if Game.experiment_mode:
				ExperimentLog.log_event("keyboard_key","screen_a" if seat==0 else "screen_b",{
					"usage":usage,"pressed":pressed,"keyboard":keyboard_name(seat),
				})


func connected_mouse_count() -> int:
	return _devices.size()


func device_name(slot: int) -> String:
	return str(_devices.get(slot, ""))


func is_ready() -> bool:
	return _bridge_ready


func swap_mouse_seats() -> void:
	_mouse_slots_to_seats[0] = 1 - int(_mouse_slots_to_seats.get(0, 0))
	_mouse_slots_to_seats[1] = 1 - int(_mouse_slots_to_seats.get(1, 1))
	var previous_a := str(_devices.get(0, ""))
	var previous_b := str(_devices.get(1, ""))
	_devices.clear()
	if not previous_b.is_empty(): _devices[0] = previous_b
	if not previous_a.is_empty(): _devices[1] = previous_a
	device_changed.emit(0, not previous_b.is_empty(), previous_b)
	device_changed.emit(1, not previous_a.is_empty(), previous_a)
	if Game.experiment_mode:
		ExperimentLog.log_event("mouse_seats_swapped","system",{
			"screen_a_device":previous_b,
			"screen_b_device":previous_a,
		})
	print("RAW_MOUSE_SEATS_SWAPPED seat_a=%s seat_b=%s" % [previous_b, previous_a])


func has_keyboard(seat: int) -> bool:
	return _keyboards.has(seat)


func connected_keyboard_count() -> int:
	return _keyboards.size()


func keyboard_name(seat: int) -> String:
	return str(_keyboards.get(seat,""))


func is_hid_key_pressed(seat: int, usage: int) -> bool:
	return seat >= 0 and seat <= 1 and (_pressed_keys[seat] as Dictionary).has(usage)
