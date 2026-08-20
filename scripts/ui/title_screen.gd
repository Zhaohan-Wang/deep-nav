extends Control

const UI = preload("res://scripts/ui/app_style.gd")
const BACKGROUND_PATH := "res://assets/ui/title/title_background.jpg"
const TITLE_PATH := "res://assets/ui/title/deep_nav_title.png"

var _settings: Control
var _background: TextureRect
var _title_art: Sprite2D
var _title_base := Vector2(58,44)
var _previous_transform_snap := true
var _previous_vertex_snap := true

func _ready() -> void:
	Displays.show_shared_page()
	# 游戏场景需要像素吸附，但它会把标题的慢速漂浮量化成一格一格的跳动。
	# 仅在封面存活期间关闭吸附，离开封面时立即恢复，不影响游戏内像素画面。
	_previous_transform_snap = get_viewport().snap_2d_transforms_to_pixel
	_previous_vertex_snap = get_viewport().snap_2d_vertices_to_pixel
	get_viewport().snap_2d_transforms_to_pixel = false
	get_viewport().snap_2d_vertices_to_pixel = false
	# 上次异常退出可能留下两个开关同时为真；正式实验永远压过研究调试显示。
	if Game.experiment_mode:
		Game.debug_mode = false
	_build_cover()
	# 右下菜单直接悬浮在封面上。每个可操作项自己承担层级和反馈，不再套一层笨重外框。
	var menu := VBoxContainer.new()
	menu.name = "TitleMenu"
	menu.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	menu.position = Vector2(-440,-548)
	menu.size = Vector2(380,498)
	menu.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_theme_constant_override("separation",12)
	add_child(menu)
	var debug_switch := _mode_switch("调试模式", Game.debug_mode, func(v): Game.debug_mode = v)
	debug_switch.name = "DebugModeSwitch"
	menu.add_child(debug_switch)
	var experiment_switch := _mode_switch("实验模式", Game.experiment_mode, func(v): Game.experiment_mode = v)
	experiment_switch.name = "ExperimentModeSwitch"
	menu.add_child(experiment_switch)
	var start := UI.button("开始游戏",Vector2(380,74),true); start.name = "StartButton"; UI.set_button_audio_cue(start,"page_turn"); start.pressed.connect(_start); menu.add_child(start)
	var settings := UI.button("设置",Vector2(380,64)); settings.name = "SettingsButton"; UI.set_button_audio_cue(settings,"popup_open"); settings.pressed.connect(_open_settings); menu.add_child(settings)
	var data := UI.button("打开数据文件夹",Vector2(380,64))
	data.name = "OpenDataFolderButton"
	data.pressed.connect(_open_experiment_logs)
	menu.add_child(data)
	var quit := UI.button("退出",Vector2(380,64)); quit.name = "QuitButton"; UI.set_button_audio_cue(quit,"popup_close"); quit.pressed.connect(func(): get_tree().quit()); menu.add_child(quit)
	GameAudio.play_ui_popup_open()
	if Game.needs_settings_confirmation():
		_open_first_run_setup.call_deferred()


func _build_cover() -> void:
	_background = TextureRect.new()
	_background.name = "TitleBackground"
	_background.texture = load(BACKGROUND_PATH) as Texture2D
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	var wash := ColorRect.new()
	wash.color = Color(0.018,0.02,0.065,0.10)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	_title_art = Sprite2D.new()
	_title_art.texture = load(TITLE_PATH) as Texture2D
	_title_art.name = "TitleArt"
	var title_center := _title_base+Vector2(250,148)
	_title_art.position = title_center+Vector2(0,-5)
	# Sprite2D 不参与 Control 最小尺寸计算，源图不会再把 500×296 的目标框撑回 1916×1136。
	_title_art.scale = Vector2(500.0/1916.0,296.0/1136.0)
	# 线性重采样只用于缓慢移动的标题，避免缩小后的大图在亚像素位置闪烁。
	_title_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_title_art)
	var float_tween := _title_art.create_tween().set_loops()
	float_tween.tween_property(_title_art,"position:y",title_center.y+5.0,3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	float_tween.tween_property(_title_art,"position:y",title_center.y-5.0,3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _exit_tree() -> void:
	# 不把标题页的平滑策略带进需要像素吸附的星图和驾驶视角。
	var viewport := get_viewport()
	if viewport != null:
		viewport.snap_2d_transforms_to_pixel = _previous_transform_snap
		viewport.snap_2d_vertices_to_pixel = _previous_vertex_snap

func _start() -> void:
	if Game.experiment_mode:
		Game.debug_mode = false
	Game.save_settings()
	# 每次从标题页开始都建立一份新的内存进度；退出应用或重新开始均从训练关归零。
	Game.begin_mission_sequence()
	# 标题页是实验组间边界；实验模式先录入组号，锁定后才创建 session。
	ExperimentLog.close_session()
	Game.clear_experiment_setup()
	get_tree().change_scene_to_file(
		"res://scenes/experiment_setup.tscn" if Game.experiment_mode
		else "res://scenes/level_select.tscn"
	)


func _open_experiment_logs() -> void:
	var log_dir := ExperimentLog.ensure_root()
	if log_dir.is_empty() or not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(log_dir)):
		push_warning("TitleScreen: cannot create experiments directory")
		return
	var error := OS.shell_open(ProjectSettings.globalize_path(log_dir))
	if error != OK:
		push_warning("TitleScreen: failed to open experiments directory (%s)" % error)

func _mode_switch(text: String, value: bool, changed: Callable) -> Control:
	const TRACK_W := 100.0
	const TRACK_H := 44.0
	const KNOB := 38.0
	const KNOB_PAD := 3.0
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(380,72)
	row.add_theme_constant_override("separation",20)

	var label := UI.label(text,30,UI.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# 深色像素阴影让文字能从复杂背景中浮出来，又不会形成新的外框。
	label.add_theme_color_override("font_shadow_color",Color(0.015,0.025,0.055,0.95))
	label.add_theme_constant_override("shadow_offset_x",3)
	label.add_theme_constant_override("shadow_offset_y",3)
	row.add_child(label)

	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.button_pressed = value
	toggle.custom_minimum_size = Vector2(TRACK_W,TRACK_H)
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.flat = true
	toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state: String in ["normal","hover","pressed","hover_pressed","focus","disabled"]:
		toggle.add_theme_stylebox_override(state,StyleBoxEmpty.new())

	var track := Panel.new()
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track_off := _switch_track_style(Color("263343"),Color("7090a3"))
	var track_on := _switch_track_style(Color("1a6665"),UI.CYAN)
	track.add_theme_stylebox_override("panel",track_on if value else track_off)
	toggle.add_child(track)

	var knob := Panel.new()
	knob.custom_minimum_size = Vector2(KNOB,KNOB)
	knob.size = Vector2(KNOB,KNOB)
	knob.position = Vector2(TRACK_W-KNOB-KNOB_PAD if value else KNOB_PAD,KNOB_PAD)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_style := StyleBoxFlat.new()
	knob_style.bg_color = UI.AMBER if value else UI.TEXT
	knob_style.border_color = Color("07101c")
	knob_style.set_border_width_all(3)
	# 故意使用小倒角而非圆形：轮廓在低分辨率下更像像素开关。
	knob_style.set_corner_radius_all(3)
	knob.add_theme_stylebox_override("panel",knob_style)
	toggle.add_child(knob)

	var state_label := UI.label("ON" if value else "OFF",18,UI.AMBER if value else UI.MUTED)
	state_label.custom_minimum_size = Vector2(48,0)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(state_label)

	toggle.resized.connect(func(): toggle.pivot_offset = toggle.size*0.5)
	UI.wire_button_audio(toggle,"choice")
	UI.set_hover_callbacks(
		toggle,
		func(): _animate_switch_hover(toggle,1.08),
		func(): _animate_switch_hover(toggle,1.0)
	)
	toggle.toggled.connect(func(on: bool):
		track.add_theme_stylebox_override("panel",track_on if on else track_off)
		knob_style.bg_color = UI.AMBER if on else UI.TEXT
		knob.add_theme_stylebox_override("panel",knob_style)
		state_label.text = "ON" if on else "OFF"
		state_label.add_theme_color_override("font_color",UI.AMBER if on else UI.MUTED)
		var tween := toggle.create_tween().set_parallel(true)
		tween.tween_property(knob,"position:x",TRACK_W-KNOB-KNOB_PAD if on else KNOB_PAD,0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.tween_property(toggle,"scale",Vector2.ONE*1.12,0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(toggle,"scale",Vector2.ONE*1.08,0.07)
		changed.call(on)
		Game.save_settings()
	)
	row.add_child(toggle)
	return row


func _switch_track_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	style.shadow_color = Color(0.01,0.02,0.04,0.78)
	style.shadow_size = 0
	style.shadow_offset = Vector2(5,5)
	return style


func _animate_switch_hover(toggle: Button, target: float) -> void:
	var tween := toggle.create_tween()
	tween.tween_property(toggle,"scale",Vector2.ONE*target,0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _open_first_run_setup() -> void:
	if _settings != null: return
	_settings = Control.new()
	_settings.name = "FirstRunSettings"
	_settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_settings)
	var dim := ColorRect.new()
	dim.color = Color(0,0,0,0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings.add_child(dim)
	var panel := UI.panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-390,-360)
	panel.size = Vector2(780,720)
	_settings.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",20)
	panel.add_child(box)
	box.add_child(UI.label("新版首次设置",38,UI.CYAN))
	var intro := UI.label("DeepNav 1.1.0 需要重新确认本机偏好。保存后，本版本不会再次询问。",21,UI.TEXT)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	box.add_child(_toggle("启用游戏声音",Game.master_volume>0.001,func(enabled: bool):
		Game.master_volume = 0.85 if enabled and Game.master_volume<=0.001 else (Game.master_volume if enabled else 0.0)
		Game.save_settings()
	))
	box.add_child(_slider("游戏音量",0,100,Game.master_volume*100.0,func(v):
		Game.master_volume=v/100.0
		Game.save_settings()
	,"%d%%"))
	box.add_child(_toggle("画面震动",Game.screen_shake_enabled,func(enabled: bool):
		Game.screen_shake_enabled=enabled
		Game.save_settings()
	))
	var permission := UI.label(
		"macOS 权限说明\n双鼠标：需要“输入监控”（不是“辅助功能”）\n系统会在首次实际使用时询问；授权后请完全退出并重新打开 DeepNav。",
		20,UI.AMBER
	)
	permission.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(permission)
	var done := UI.button("保存设置并继续",Vector2(360,72),true)
	done.name = "ConfirmFirstRunSettings"
	UI.set_button_audio_cue(done,"confirm")
	done.pressed.connect(_confirm_first_run_settings)
	box.add_child(done)


func _confirm_first_run_settings() -> void:
	Game.confirm_settings_revision()
	_settings.queue_free()
	_settings = null


func _open_settings() -> void:
	if _settings != null: return
	_settings = Control.new(); _settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_settings)
	var dim := ColorRect.new(); dim.color = Color(0,0,0,0.72); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _settings.add_child(dim)
	var panel := UI.panel(); panel.set_anchors_preset(Control.PRESET_CENTER); panel.position = Vector2(-420,-430); panel.size = Vector2(840,860); _settings.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 18); panel.add_child(box)
	box.add_child(UI.label("系统设置", 38, UI.CYAN))
	box.add_child(_toggle("画面震动", Game.screen_shake_enabled, func(v): Game.screen_shake_enabled = v))
	var display_status := UI.label(Displays.display_status(), 21, UI.CYAN)
	display_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(display_status)
	box.add_child(_slider("主音量", 0, 100, Game.master_volume * 100.0, func(v): Game.master_volume = v / 100.0, "%d%%"))
	if not Game.experiment_mode:
		box.add_child(_slider("航点冷却", 1, 5, Game.waypoint_cooldown_s, func(v): Game.waypoint_cooldown_s = v, "%.0f 秒"))
		box.add_child(_slider("航点最大距离", 24, 140, Game.waypoint_max_distance, func(v): Game.waypoint_max_distance = v, "%.0f 单位"))
	box.add_child(_input_device_section())
	var done := UI.button("保存并返回", Vector2(360,72), true); UI.set_button_audio_cue(done,"popup_close"); done.pressed.connect(_close_settings); box.add_child(done)


## 输入设备区：显示当前鼠标/键盘席位分配，提供翻转按钮和键盘识别测试。
func _input_device_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)

	# 标题行
	var title_row := HBoxContainer.new()
	title_row.add_child(UI.label("─── 输入设备", 22, UI.MUTED))
	col.add_child(title_row)

	# ---- 鼠标区 ----
	var mouse_row := HBoxContainer.new()
	mouse_row.add_theme_constant_override("separation", 12)
	var mouse_col := VBoxContainer.new()
	mouse_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_col.add_theme_constant_override("separation", 4)

	# 刷新鼠标标签（每次打开设置时显示当前连接状态）
	var mouse_a_label := UI.label(_mouse_seat_text(0), 20, UI.TEXT)
	var mouse_b_label := UI.label(_mouse_seat_text(1), 20, UI.TEXT)
	mouse_col.add_child(mouse_a_label)
	mouse_col.add_child(mouse_b_label)
	mouse_row.add_child(mouse_col)

	var swap_btn := UI.button("翻转鼠标", Vector2(180, 56))
	UI.set_button_audio_cue(swap_btn, "choice")
	swap_btn.pressed.connect(func() -> void:
		RawMice.swap_mouse_seats()
		mouse_a_label.text = _mouse_seat_text(0)
		mouse_b_label.text = _mouse_seat_text(1)
	)
	mouse_row.add_child(swap_btn)
	col.add_child(mouse_row)

	# ---- 键盘区 ----
	var kb_col := VBoxContainer.new()
	kb_col.add_theme_constant_override("separation", 4)

	var kb_a_label := UI.label(_keyboard_seat_text(0), 20, UI.TEXT)
	var kb_b_label := UI.label(_keyboard_seat_text(1), 20, UI.TEXT)
	kb_col.add_child(kb_a_label)
	kb_col.add_child(kb_b_label)

	var swap_keyboard_btn := UI.button("翻转键盘", Vector2(180, 56))
	UI.set_button_audio_cue(swap_keyboard_btn, "choice")
	swap_keyboard_btn.pressed.connect(func() -> void:
		RawMice.swap_keyboard_seats()
		kb_a_label.text = _keyboard_seat_text(0)
		kb_b_label.text = _keyboard_seat_text(1)
	)
	kb_col.add_child(swap_keyboard_btn)
	col.add_child(kb_col)

	# ---- 键盘识别测试 ----
	col.add_child(UI.label("键盘识别测试：按住任意键盘上的 Shift 键", 19, UI.MUTED))
	var indicator_row := HBoxContainer.new()
	indicator_row.add_theme_constant_override("separation", 16)

	var ind_a := _kbd_indicator("屏幕 A", false)
	var ind_b := _kbd_indicator("屏幕 B", false)
	indicator_row.add_child(ind_a)
	indicator_row.add_child(ind_b)
	col.add_child(indicator_row)

	# 用 HID key 实时轮询，避免依赖 F/快捷键
	var timer := col.create_tween().set_loops()
	timer.tween_callback(func() -> void:
		# HID KeyboardOrKeypad：Left Shift=0xE1, Right Shift=0xE5
		var a_held := (
			RawMice.is_hid_key_pressed(0, 0xE1) or
			RawMice.is_hid_key_pressed(0, 0xE5)
		)
		var b_held := (
			RawMice.is_hid_key_pressed(1, 0xE1) or
			RawMice.is_hid_key_pressed(1, 0xE5)
		)
		_update_kbd_indicator(ind_a, a_held)
		_update_kbd_indicator(ind_b, b_held)
	).set_delay(0.05)
	col.add_child(Control.new())  # 底部留白

	return col


func _mouse_seat_text(seat: int) -> String:
	var name := RawMice.device_name(seat)
	return "鼠标 %s → 屏幕 %s" % [
		"A" if seat == 0 else "B",
		"A" if seat == 0 else "B",
	] + ("：" + name if not name.is_empty() else "（未连接）")


func _keyboard_seat_text(seat: int) -> String:
	var name := RawMice.keyboard_name(seat)
	return "键盘 %s → 屏幕 %s" % [
		"A" if seat == 0 else "B",
		"A" if seat == 0 else "B",
	] + ("：" + name if not name.is_empty() else "（未连接）")


func _kbd_indicator(label_text: String, active: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(180, 56)
	var style := StyleBoxFlat.new()
	style.bg_color = UI.CYAN if active else UI.PANEL_2
	style.border_color = UI.CYAN
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 8; style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.set_meta("kbd_style", style)
	var lbl := UI.label(label_text, 22, UI.BG if active else UI.MUTED)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(lbl)
	panel.set_meta("kbd_label", lbl)
	return panel


func _update_kbd_indicator(panel: PanelContainer, active: bool) -> void:
	var style := panel.get_meta("kbd_style") as StyleBoxFlat
	var lbl := panel.get_meta("kbd_label") as Label
	var was_active := style.bg_color == UI.CYAN
	if was_active == active:
		return
	style.bg_color = UI.CYAN if active else UI.PANEL_2
	lbl.add_theme_color_override("font_color", UI.BG if active else UI.MUTED)

func _toggle(text: String, value: bool, changed: Callable) -> Control:
	var row := HBoxContainer.new(); var label := UI.label(text, 23); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
	var check := CheckButton.new(); check.button_pressed = value; check.text = "开启" if value else "关闭"; check.add_theme_font_override("font", UI.FONT_CJK)
	UI.wire_button_audio(check,"choice")
	check.toggled.connect(func(v): check.text = "开启" if v else "关闭"; changed.call(v)); row.add_child(check); return row

func _slider(text: String, min_v: float, max_v: float, value: float, changed: Callable, format: String) -> Control:
	var col := VBoxContainer.new(); var head := HBoxContainer.new(); col.add_child(head)
	var label := UI.label(text, 22); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(label)
	var number := UI.label(format % value, 21, UI.AMBER); head.add_child(number)
	var slider := HSlider.new(); slider.min_value=min_v; slider.max_value=max_v; slider.step=1; slider.value=value; UI.style_slider(slider)
	slider.value_changed.connect(func(v): number.text = format % v; changed.call(v)); col.add_child(slider); return col

func _close_settings() -> void:
	Game.save_settings(); _settings.queue_free(); _settings = null
