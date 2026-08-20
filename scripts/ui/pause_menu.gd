class_name PauseMenu
extends Control
## 单块角色屏幕上的暂停菜单；Main 会在领航员和驾驶员页面各放一份。

signal resume_requested
signal restart_requested
signal level_select_requested
signal title_requested


func setup(role: String) -> void:
	name = "PauseMenu_%s" % role
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 920
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.004, 0.010, 0.024, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 28
	center.offset_right = -28
	center.offset_top = 22
	center.offset_bottom = -22
	add_child(center)

	var card := AppStyle.panel()
	card.name = "PauseCard"
	card.custom_minimum_size = Vector2(520, 458)
	center.add_child(card)

	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 12)
	card.add_child(body)

	var eyebrow := AppStyle.label("DEEP NAV // FLIGHT HOLD", 15, AppStyle.MUTED)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(eyebrow)
	var title := AppStyle.label("航行已暂停", 36, AppStyle.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var hint := AppStyle.label("按 ESC 或选择“继续游戏”返回任务", 16, AppStyle.MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)

	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 6)
	body.add_child(rule)

	var actions := VBoxContainer.new()
	actions.name = "PauseActions"
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 9)
	body.add_child(actions)
	_add_action(actions, "继续游戏", true, resume_requested, "popup_close")
	_add_action(actions, "重玩本关", false, restart_requested, "confirm")
	_add_action(actions, "返回选关", false, level_select_requested, "page_turn")
	var title_button := _add_action(actions, "返回标题", false, title_requested, "page_turn")
	title_button.add_theme_color_override("font_color", AppStyle.DANGER)


func _add_action(
	parent: VBoxContainer,
	label_text: String,
	accent: bool,
	request_signal: Signal,
	audio_cue: String
) -> Button:
	var button := AppStyle.button(label_text, Vector2(390, 58), accent)
	AppStyle.set_button_audio_cue(button, audio_cue)
	button.pressed.connect(request_signal.emit)
	parent.add_child(button)
	return button
