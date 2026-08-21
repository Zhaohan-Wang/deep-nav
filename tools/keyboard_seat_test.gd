extends SceneTree
## 两键盘固定席位：内置=A、外接=B；岗位变化只改变每把键盘的职责。

const HID_A := 0x04
const HID_E := 0x08
const HID_W := 0x1A


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var raw := root.get_node("RawMice")
	var displays := root.get_node("Displays")
	raw.set("_bridge_ready",true)
	raw.set("_keyboards",{0:"Apple Internal Keyboard",1:"External Keyboard"})
	raw.set("_pressed_keys",{0:{},1:{}})
	raw.set("_keyboard_input_seen",{0:true,1:true})

	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var navigator: Control = main.get("_navigator_view")
	var stages: Variant = navigator.get("_stages")

	# 默认领航在 A、驾驶在 B：只有外接键盘 B 的 WASD 驱动飞船。
	assert(displays.pilot_seat()==1,"pilot should start on screen B")
	(raw.get("_pressed_keys")[0] as Dictionary)[HID_W] = true
	assert(is_zero_approx(displays.pilot_thrust_axis()),"built-in keyboard must not drive screen-B pilot")
	(raw.get("_pressed_keys")[1] as Dictionary)[HID_W] = true
	assert(is_equal_approx(displays.pilot_thrust_axis(),1.0),"external keyboard must drive screen-B pilot")
	(raw.get("_pressed_keys")[1] as Dictionary)[HID_A] = true
	assert(is_equal_approx(displays.pilot_turn_axis(),1.0),"external keyboard A key must steer screen-B pilot")

	# 鼠标 HID 桥仍正常、但驾驶席键盘因接收器重连而缺席时，系统键盘必须兜底，
	# 不能把 WASD 静默变成零输入。
	raw.set("_keyboards",{0:"Apple Internal Keyboard"})
	raw.set("_keyboard_input_seen",{0:true,1:false})
	Input.action_press("thrust")
	assert(is_equal_approx(displays.pilot_thrust_axis(),1.0),
		"missing external HID keyboard must fall back to system WASD")
	Input.action_release("thrust")
	raw.set("_keyboards",{0:"Apple Internal Keyboard",1:"External Keyboard"})
	raw.set("_keyboard_input_seen",{0:true,1:true})

	var raised: bool = bool(stages.deck_raised)
	raw.key_changed.emit(1,HID_E,true)
	assert(stages.deck_raised==raised,"pilot keyboard must not toggle navigator map")
	raw.key_changed.emit(0,HID_E,true)
	assert(stages.deck_raised!=raised,"built-in navigator keyboard must toggle map")

	# 换岗后职责随角色移动：内置键盘驾驶，外接键盘开关星图。
	displays.set_primary_role(displays.Role.PILOT)
	(raw.get("_pressed_keys")[0] as Dictionary).clear()
	(raw.get("_pressed_keys")[1] as Dictionary).clear()
	(raw.get("_pressed_keys")[1] as Dictionary)[HID_W] = true
	assert(is_zero_approx(displays.pilot_thrust_axis()),"external navigator keyboard must not drive screen-A pilot")
	(raw.get("_pressed_keys")[0] as Dictionary)[HID_W] = true
	assert(is_equal_approx(displays.pilot_thrust_axis(),1.0),"built-in keyboard must drive screen-A pilot")
	raised = bool(stages.deck_raised)
	raw.key_changed.emit(0,HID_E,true)
	assert(stages.deck_raised==raised,"pilot keyboard E must be ignored after role swap")
	raw.key_changed.emit(1,HID_E,true)
	assert(stages.deck_raised!=raised,"external navigator keyboard must toggle map after role swap")

	# F6 只校正鼠标，键盘与按键状态不交换。
	var keyboards_before := (raw.get("_keyboards") as Dictionary).duplicate(true)
	var keys_before := (raw.get("_pressed_keys") as Dictionary).duplicate(true)
	raw.set("_devices",{0:"Mouse A",1:"Mouse B"})
	raw.call("swap_mouse_seats")
	assert(raw.get("_keyboards")==keyboards_before,"mouse calibration must not swap keyboards")
	assert(raw.get("_pressed_keys")==keys_before,"mouse calibration must not swap keyboard state")
	print("KEYBOARD_SEAT_TEST_OK builtin=A external=B pilot=WASD navigator=E")
	quit(0)
