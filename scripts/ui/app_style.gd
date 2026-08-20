class_name AppStyle
extends RefCounted
## DeepNav 菜单构件：干净深空底、像素边框、清晰正文。

const BG := Color("050914")
const PANEL := Color("0b1524")
const PANEL_2 := Color("101f31")
const CYAN := Color("58e1dc")
const AMBER := Color("f0b35a")
const TEXT := Color("e8f2f5")
const MUTED := Color("8295a3")
const DANGER := Color("ef6673")
const FONT_CJK: FontFile = preload("res://assets/fonts/ipix_12px.ttf")
const FONT_BODY: FontFile = preload("res://assets/fonts/atkinson_mono.ttf")
const HOVER_ENTER_DELAY_S: float = 0.075
const HOVER_EXIT_GRACE_S: float = 0.12


static func page() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(bg)
	var grid := Control.new(); grid.set_script(preload("res://scripts/ui/menu_grid.gd"))
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grid)
	return root


static func label(text: String, size: int = 24, color: Color = TEXT) -> Label:
	var out := Label.new(); out.text = text
	out.add_theme_font_override("font", FONT_CJK); out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color); return out


static func button(text: String, min_size := Vector2(320, 72), accent: bool = false) -> Button:
	var out := Button.new(); out.text = text; out.custom_minimum_size = min_size
	# UI 只由两只实体鼠标操作；禁用键盘/手柄焦点，避免默认焦点框伪装成不一致的 hover。
	out.focus_mode = Control.FOCUS_NONE
	out.add_theme_font_override("font", FONT_CJK); out.add_theme_font_size_override("font_size", 23)
	var normal_color := BG if accent else TEXT
	var normal_style := box(AMBER if accent else PANEL_2, CYAN if accent else Color("29435a"), 2)
	var hover_style := box(CYAN, CYAN, 2)
	out.add_theme_stylebox_override("pressed", box(AMBER, TEXT, 3))
	out.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	set_button_hover_styles(out, normal_style, hover_style, normal_color, BG)
	wire_button_audio(out)
	return out


static func wire_button_audio(button: BaseButton, press_cue: String = "press") -> void:
	button.set_meta("ui_press_cue", press_cue)
	if button.has_meta("ui_audio_wired"):
		return
	button.set_meta("ui_audio_wired", true)
	wire_control_hover(button, Callable(), Callable(), true)
	button.pressed.connect(func() -> void:
		if not button.disabled:
			var cue := str(button.get_meta("ui_press_cue", "press"))
			if cue != "none":
				_play_control_audio(button, cue)
	)


static func wire_control_hover(
	control: Control,
	on_enter: Callable = Callable(),
	on_exit: Callable = Callable(),
	play_audio: bool = true
) -> void:
	control.set_meta("ui_hover_on_enter", on_enter)
	control.set_meta("ui_hover_on_exit", on_exit)
	control.set_meta("ui_hover_play_audio", play_audio)
	if control.has_meta("ui_hover_wired"):
		return
	control.set_meta("ui_hover_wired", true)
	control.set_meta("ui_hover_active", false)
	control.set_meta("ui_hover_inside", false)
	control.set_meta("ui_hover_generation", 0)
	control.set_meta("ui_hover_seats", {})
	control.mouse_entered.connect(func() -> void:
		var displays := control.get_node_or_null("/root/Displays")
		if displays == null or not bool(displays.call("uses_raw_mouse_mode")):
			_request_hover_state(control, true)
	)
	control.mouse_exited.connect(func() -> void:
		var displays := control.get_node_or_null("/root/Displays")
		if displays == null or not bool(displays.call("uses_raw_mouse_mode")):
			_request_hover_state(control, false)
	)
	if control.is_inside_tree():
		_connect_display_hover(control)
	else:
		control.tree_entered.connect(_connect_display_hover.bind(control), CONNECT_ONE_SHOT)


static func _connect_display_hover(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return
	var displays := control.get_node_or_null("/root/Displays")
	if displays != null and displays.has_signal("seat_hover_changed"):
		var control_ref: WeakRef = weakref(control)
		var hover_callback := func(seat: int, hovered: Control) -> void:
			var target := control_ref.get_ref() as Control
			if target == null:
				return
			if not bool(displays.call("uses_raw_mouse_mode")):
				return
			var seats := target.get_meta("ui_hover_seats", {}) as Dictionary
			var inside := hovered == target or (hovered != null and target.is_ancestor_of(hovered))
			if bool(seats.get(seat, false)) == inside:
				return
			seats[seat] = inside
			target.set_meta("ui_hover_seats", seats)
			var any_inside := false
			for value: Variant in seats.values():
				if bool(value):
					any_inside = true
					break
			_request_hover_state(target, any_inside)
		displays.connect("seat_hover_changed", hover_callback)
		var exit_callback := func() -> void:
			if is_instance_valid(displays) and displays.is_connected("seat_hover_changed", hover_callback):
				displays.disconnect("seat_hover_changed", hover_callback)
		control.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)


static func set_hover_callbacks(control: Control, on_enter: Callable, on_exit: Callable) -> void:
	wire_control_hover(control, on_enter, on_exit, bool(control.get_meta("ui_hover_play_audio", true)))


static func set_button_hover_styles(
	button: BaseButton,
	normal_style: StyleBox,
	hover_style: StyleBox,
	normal_color: Color,
	hover_color: Color
) -> void:
	button.set_meta("ui_hover_normal_style", normal_style)
	button.set_meta("ui_hover_style", hover_style)
	button.set_meta("ui_hover_normal_color", normal_color)
	button.set_meta("ui_hover_color", hover_color)
	_apply_debounced_hover_visual(button)


static func _request_hover_state(control: Control, inside: bool) -> void:
	if not is_instance_valid(control):
		return
	control.set_meta("ui_hover_inside", inside)
	var generation := int(control.get_meta("ui_hover_generation", 0)) + 1
	control.set_meta("ui_hover_generation", generation)
	var tree := control.get_tree()
	if tree == null:
		return
	var delay := HOVER_ENTER_DELAY_S if inside else HOVER_EXIT_GRACE_S
	var control_ref: WeakRef = weakref(control)
	tree.create_timer(delay, true, false, true).timeout.connect(
		_commit_hover_state.bind(control_ref, inside, generation),
		CONNECT_ONE_SHOT
	)


static func _commit_hover_state(control_ref: WeakRef, inside: bool, generation: int) -> void:
	var control := control_ref.get_ref() as Control
	if control == null:
		return
	if int(control.get_meta("ui_hover_generation", 0)) != generation:
		return
	if bool(control.get_meta("ui_hover_inside", false)) != inside:
		return
	if inside and control is BaseButton and (control as BaseButton).disabled:
		return
	if bool(control.get_meta("ui_hover_active", false)) == inside:
		return
	control.set_meta("ui_hover_active", inside)
	_apply_debounced_hover_visual(control)
	var callback := control.get_meta("ui_hover_on_enter" if inside else "ui_hover_on_exit", Callable()) as Callable
	if callback.is_valid():
		callback.call()
	if inside and bool(control.get_meta("ui_hover_play_audio", true)):
		_play_control_audio(control, "hover")


static func _apply_debounced_hover_visual(control: Control) -> void:
	var active := bool(control.get_meta("ui_hover_active", false))
	if control is BaseButton and control.has_meta("ui_hover_normal_style"):
		var button := control as BaseButton
		var style := control.get_meta("ui_hover_style" if active else "ui_hover_normal_style") as StyleBox
		var color := control.get_meta("ui_hover_color" if active else "ui_hover_normal_color") as Color
		# normal/hover 使用同一份“已确认状态”，屏蔽 Godot 单指针 hover 的逐帧抖动。
		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", color)
	if control is Slider and control.has_meta("ui_hover_grabber"):
		var slider := control as Slider
		var icon := control.get_meta("ui_hover_grabber_highlight" if active else "ui_hover_grabber") as Texture2D
		slider.add_theme_icon_override("grabber", icon)
		slider.add_theme_icon_override("grabber_highlight", icon)


static func set_button_audio_cue(button: BaseButton, press_cue: String) -> void:
	wire_button_audio(button, press_cue)


static func _play_control_audio(control: Control, cue: String) -> void:
	var audio := control.get_node_or_null("/root/GameAudio")
	var method := "play_ui_%s" % cue
	if audio != null and audio.has_method(method):
		audio.call(method)


static func panel() -> PanelContainer:
	var out := PanelContainer.new(); out.add_theme_stylebox_override("panel", box(PANEL, Color("29435a"), 2)); return out


static func box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var out := StyleBoxFlat.new(); out.bg_color = fill; out.border_color = border
	out.set_border_width_all(width); out.set_corner_radius_all(4)
	out.content_margin_left = 24; out.content_margin_right = 24
	out.content_margin_top = 16; out.content_margin_bottom = 16; return out


static func style_slider(slider: Slider) -> void:
	slider.custom_minimum_size = Vector2(360, 52)
	var track := StyleBoxFlat.new(); track.bg_color = Color("22384a"); track.set_corner_radius_all(0)
	track.content_margin_top = 7; track.content_margin_bottom = 7
	var fill := track.duplicate() as StyleBoxFlat; fill.bg_color = CYAN
	slider.add_theme_stylebox_override("slider", track); slider.add_theme_stylebox_override("grabber_area", fill)
	var grabber := _pixel_circle(26, AMBER, TEXT)
	var grabber_highlight := _pixel_circle(30, CYAN, TEXT)
	slider.set_meta("ui_hover_grabber", grabber)
	slider.set_meta("ui_hover_grabber_highlight", grabber_highlight)
	wire_control_hover(slider, Callable(), Callable(), false)
	_apply_debounced_hover_visual(slider)
	if not slider.has_meta("ui_audio_wired"):
		slider.set_meta("ui_audio_wired", true)
		slider.value_changed.connect(func(_value: float) -> void:
			_play_control_audio(slider, "slider_tick")
		)
		slider.drag_ended.connect(func(value_changed: bool) -> void:
			if value_changed:
				_play_control_audio(slider, "choice")
		)


## 像素风圆形滑钮：低分辨率光栅化圆，再最近邻放大一倍，保留锯齿台阶感。
static func _pixel_circle(diameter: int, fill: Color, border: Color) -> Texture2D:
	var base := maxi(diameter / 2, 5)
	var image := Image.create(base, base, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := (base - 1) * 0.5
	var radius := base * 0.5 - 0.5
	for y: int in range(base):
		for x: int in range(base):
			var distance := Vector2(x - center, y - center).length()
			if distance <= radius - 1.1:
				image.set_pixel(x, y, fill)
			elif distance <= radius:
				image.set_pixel(x, y, border)
	image.resize(base * 2, base * 2, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)
