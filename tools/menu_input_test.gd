extends SceneTree
## 回归检查：组号键盘输入、统一像素字体，以及鼠标 UI 不残留手柄焦点框。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var setup := (load("res://scenes/experiment_setup.tscn") as PackedScene).instantiate()
	root.add_child(setup)
	await process_frame
	await process_frame
	var number := setup.find_child("DyadNumber",true,false) as LineEdit
	assert(number!=null,"group number input missing")
	assert(number.get_theme_font("font")==AppStyle.FONT_CJK,"group input must use the pixel CJK font")
	number.release_focus()
	setup.call("_unhandled_key_input",_digit_event(4))
	await process_frame
	assert(number.text=="4","focus-loss keyboard fallback must reach group number")

	var displays := root.get_node("Displays")
	displays.call("_on_secondary_window_input",_digit_event(7))
	await process_frame
	assert(number.text=="47","secondary-window keyboard input must route to group number")
	setup.queue_free()
	await process_frame

	var title := (load("res://scenes/title_screen.tscn") as PackedScene).instantiate()
	root.add_child(title)
	await process_frame
	await process_frame
	var start := title.find_child("StartButton",true,false) as Button
	var settings := title.find_child("SettingsButton",true,false) as Button
	assert(start!=null and settings!=null,"title buttons missing")
	assert(start.focus_mode==Control.FOCUS_NONE and settings.focus_mode==Control.FOCUS_NONE,"mouse buttons must not retain controller focus")
	assert(start.has_meta("ui_audio_wired") and settings.has_meta("ui_audio_wired"),"title buttons must have shared UI audio")
	assert(start.get_meta("ui_press_cue")=="page_turn","start button must use page transition audio")
	assert(settings.get_meta("ui_press_cue")=="popup_open","settings button must use popup audio")
	var start_hover := start.get_theme_stylebox("hover") as StyleBoxFlat
	var settings_hover := settings.get_theme_stylebox("hover") as StyleBoxFlat
	assert(start_hover.bg_color==settings_hover.bg_color,"start hover fill must match other title buttons")
	assert(start_hover.border_color==settings_hover.border_color,"start hover border must match other title buttons")
	for toggle_name: String in ["DebugModeSwitch","ExperimentModeSwitch"]:
		var row := title.find_child(toggle_name,true,false)
		var toggle := _first_button(row)
		assert(toggle!=null and toggle.focus_mode==Control.FOCUS_NONE,"%s must be mouse-only" % toggle_name)
		assert(toggle.has_meta("ui_audio_wired") and toggle.get_meta("ui_press_cue")=="choice","%s must have choice audio" % toggle_name)
	# 保留正常基线的直接事件路由：两个原始席位只能更新各自光标。
	displays.set("_raw_mouse_mode",true)
	displays.call("_center_shared_cursors")
	var cursor_a := displays.get("_cursor_a") as VirtualCursor
	var cursor_b := displays.get("_cursor_b") as VirtualCursor
	var start_a := cursor_a.position
	var start_b := cursor_b.position
	displays.call("_on_raw_mouse_motion",0,Vector2(48,0))
	displays.call("_on_raw_mouse_motion",1,Vector2(-48,0))
	assert(cursor_a.position.x > start_a.x + 40.0,"seat A cursor must move independently of hover pickup")
	assert(cursor_b.position.x < start_b.x - 40.0,"seat B cursor must move independently of hover pickup")
	assert(cursor_a.position.distance_to(cursor_b.position) > 80.0,"two raw mice must not collapse onto one cursor")
	displays.set("_raw_mouse_mode",false)
	var slider := HSlider.new()
	AppStyle.style_slider(slider)
	assert(slider.has_meta("ui_audio_wired"),"styled sliders must have tick audio")
	print("MENU_INPUT_TEST_OK keyboard=root+secondary font=pixel hover=baseline focus=mouse_only audio=shared")
	quit(0)


func _digit_event(digit: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_0+digit
	event.physical_keycode = KEY_0+digit
	event.unicode = 48+digit
	return event


func _first_button(node: Node) -> Button:
	if node is Button:
		return node as Button
	for child: Node in node.get_children():
		var found := _first_button(child)
		if found!=null:
			return found
	return null
