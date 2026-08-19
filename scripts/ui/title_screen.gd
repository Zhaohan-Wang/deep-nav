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
	var start := UI.button("开始游戏",Vector2(380,74),true); start.pressed.connect(_start); menu.add_child(start)
	var settings := UI.button("设置",Vector2(380,64)); settings.pressed.connect(_open_settings); menu.add_child(settings)
	var data := UI.button("打开数据文件夹",Vector2(380,64))
	data.name = "OpenDataFolderButton"
	data.pressed.connect(_open_experiment_logs)
	menu.add_child(data)
	var quit := UI.button("退出",Vector2(380,64)); quit.pressed.connect(func(): get_tree().quit()); menu.add_child(quit)
	start.grab_focus.call_deferred()


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
	# 标题页是实验组间边界：先关闭可能残留的旧 session，再建立新目录。
	ExperimentLog.close_session()
	ExperimentLog.begin_session()
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")


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
	toggle.focus_mode = Control.FOCUS_ALL
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
	toggle.focus_entered.connect(func(): _animate_switch_focus(toggle,1.08))
	toggle.focus_exited.connect(func(): _animate_switch_focus(toggle,1.0))
	toggle.mouse_entered.connect(func(): toggle.grab_focus())
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


func _animate_switch_focus(toggle: Button, target: float) -> void:
	var tween := toggle.create_tween()
	tween.tween_property(toggle,"scale",Vector2.ONE*target,0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _open_settings() -> void:
	if _settings != null: return
	_settings = Control.new(); _settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(_settings)
	var dim := ColorRect.new(); dim.color = Color(0,0,0,0.72); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _settings.add_child(dim)
	var panel := UI.panel(); panel.set_anchors_preset(Control.PRESET_CENTER); panel.position = Vector2(-390,-390); panel.size = Vector2(780,780); _settings.add_child(panel)
	var box := VBoxContainer.new(); box.add_theme_constant_override("separation", 18); panel.add_child(box)
	box.add_child(UI.label("系统设置", 38, UI.CYAN))
	box.add_child(_toggle("画面震动", Game.screen_shake_enabled, func(v): Game.screen_shake_enabled = v))
	var display_status := UI.label(Displays.display_status(), 21, UI.CYAN)
	display_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(display_status)
	box.add_child(_slider("主音量", 0, 100, Game.master_volume * 100.0, func(v): Game.master_volume = v / 100.0, "%d%%"))
	box.add_child(_slider("航点冷却", 1, 5, Game.waypoint_cooldown_s, func(v): Game.waypoint_cooldown_s = v, "%.0f 秒"))
	box.add_child(_slider("航点最大距离", 24, 140, Game.waypoint_max_distance, func(v): Game.waypoint_max_distance = v, "%.0f 单位"))
	var done := UI.button("保存并返回", Vector2(360,72), true); done.pressed.connect(_close_settings); box.add_child(done); done.grab_focus.call_deferred()

func _toggle(text: String, value: bool, changed: Callable) -> Control:
	var row := HBoxContainer.new(); var label := UI.label(text, 23); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
	var check := CheckButton.new(); check.button_pressed = value; check.text = "开启" if value else "关闭"; check.add_theme_font_override("font", UI.FONT_CJK)
	check.toggled.connect(func(v): check.text = "开启" if v else "关闭"; changed.call(v)); row.add_child(check); return row

func _slider(text: String, min_v: float, max_v: float, value: float, changed: Callable, format: String) -> Control:
	var col := VBoxContainer.new(); var head := HBoxContainer.new(); col.add_child(head)
	var label := UI.label(text, 22); label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(label)
	var number := UI.label(format % value, 21, UI.AMBER); head.add_child(number)
	var slider := HSlider.new(); slider.min_value=min_v; slider.max_value=max_v; slider.step=1; slider.value=value; UI.style_slider(slider)
	slider.value_changed.connect(func(v): number.text = format % v; changed.call(v)); col.add_child(slider); return col

func _close_settings() -> void:
	Game.save_settings(); _settings.queue_free(); _settings = null
