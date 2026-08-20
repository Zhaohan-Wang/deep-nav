extends SceneTree
## 暂停菜单回归：双屏覆盖、菜单顺序，以及系统/原生键盘 ESC。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	var menus := main.get("_pause_menus") as Array
	assert(menus.size() == 2, "pause menu must cover navigator and pilot screens")
	for menu: Node in menus:
		assert(not (menu as Control).visible, "pause menu must start hidden")
		assert(menu.process_mode == Node.PROCESS_MODE_ALWAYS, "pause menu must work while paused")

	var actions := (menus[0] as Node).find_child("PauseActions", true, false)
	assert(actions != null, "pause action list missing")
	var labels: Array[String] = []
	for child: Node in actions.get_children():
		if child is Button:
			labels.append((child as Button).text)
	assert(labels == ["继续游戏", "重玩本关", "返回选关", "返回标题"], "pause action order changed")

	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	escape.physical_keycode = KEY_ESCAPE
	main.call("_unhandled_input", escape)
	assert(paused, "root-window ESC did not pause")
	for menu: Node in menus:
		assert((menu as Control).visible, "both role screens must show pause menu")
	main.call("_set_pause_state", false)
	assert(not paused, "resume did not unpause")

	main.set("_last_pause_toggle_ms", -1000)
	main.call("_on_raw_keyboard_key", 1, 0x29, true)
	assert(paused, "raw HID ESC did not pause")
	main.call("_set_pause_state", false)
	assert(not paused, "raw HID pause could not be closed")

	assert(root.get_node("RawMice").process_mode == Node.PROCESS_MODE_ALWAYS, "raw input stops while paused")
	assert(root.get_node("Displays").process_mode == Node.PROCESS_MODE_ALWAYS, "dual-screen input stops while paused")
	main.call("_set_pause_state", true)
	assert(main.call("_prepare_pause_scene_transition"), "first pause exit must start a global scene transition")
	assert(not main.call("_prepare_pause_scene_transition"), "both screens must not start duplicate scene transitions")
	var displays := root.get_node("Displays")
	assert(bool(displays.get("_shared_mode")), "pause exit must restore shared dual-screen mode")
	var role_host := displays.get("_role_host") as Control
	assert(role_host.get_child_count() == 0, "pause exit left a role page orphaned on the second screen")
	assert(not paused, "pause exit must unpause before changing scenes")
	main.queue_free()
	await process_frame
	print("PAUSE_MENU_TEST_OK screens=2 escape=root+raw exit=global+deduplicated order=safe")
	quit(0)
