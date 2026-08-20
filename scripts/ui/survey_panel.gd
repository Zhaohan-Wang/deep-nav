class_name SurveyPanel
extends Control
## 任务结束后的独立两步微量表；固定在单个 16:9 角色页内，不会跨屏或纵向溢出。

signal submitted(role: String, answers: Dictionary)

## 主要原因选项平铺直选（答案编码与旧下拉一致：1 起）。不用弹窗：
## 内嵌弹窗会盖住虚拟光标，且合成的按下+抬起事件会让它开了又立刻收回。
const CAUSE_OPTIONS: Array[String] = ["自己的操作或判断","搭档的操作或判断","飞船或导航系统","外部环境","无法判断"]

var role: String
var outcome: String
var _answers: Dictionary = {}
var _page := 0
var _page_host: VBoxContainer
var _step_label: Label
var _back: Button
var _next: Button
var _submit: Button
var _cause_buttons: Array[Button] = []


func setup(role_name: String, outcome_name: String, _summary: Dictionary) -> void:
	role = role_name
	outcome = outcome_name
	name = "SurveyPanel_%s" % role
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 900
	var dim := ColorRect.new()
	dim.color = Color(0.006,0.014,0.035,0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right"]:
		safe.add_theme_constant_override("margin_%s" % side,32)
	for side: String in ["top","bottom"]:
		safe.add_theme_constant_override("margin_%s" % side,24)
	add_child(safe)
	var card := AppStyle.panel()
	card.name = "SurveyCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe.add_child(card)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation",8)
	card.add_child(shell)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	shell.add_child(header)
	var title := AppStyle.label("个人独立作答 · %s" % _role_text(),24,AppStyle.CYAN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_step_label = AppStyle.label("",17,AppStyle.AMBER)
	header.add_child(_step_label)
	var privacy := AppStyle.label("答案不会向搭档展示；双方提交前请勿讨论。",15,AppStyle.MUTED)
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shell.add_child(privacy)
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation",4)
	shell.add_child(rule)
	_page_host = VBoxContainer.new()
	_page_host.name = "SurveyPageHost"
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_theme_constant_override("separation",9)
	shell.add_child(_page_host)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",12)
	shell.add_child(footer)
	_back = AppStyle.button("上一步",Vector2(180,50))
	AppStyle.set_button_audio_cue(_back,"page_turn")
	_back.pressed.connect(func(): _show_page(0))
	footer.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_next = AppStyle.button("下一步",Vector2(220,50),true)
	AppStyle.set_button_audio_cue(_next,"page_turn")
	_next.pressed.connect(func(): _show_page(1))
	footer.add_child(_next)
	_submit = AppStyle.button("提交个人答案",Vector2(260,50),true)
	AppStyle.set_button_audio_cue(_submit,"confirm")
	_submit.pressed.connect(_on_submit)
	footer.add_child(_submit)
	_show_page(0)


func _role_text() -> String:
	return "领航员" if role == "navigator" else "驾驶员"


func _show_page(index: int) -> void:
	var previous_page := _page
	_page = clampi(index,0,1)
	for child: Node in _page_host.get_children():
		child.queue_free()
	_step_label.text = "步骤 %d / 2" % (_page+1)
	_back.visible = _page > 0
	_next.visible = _page == 0
	_submit.visible = _page == 1
	if _page == 0:
		_build_attribution_page()
	else:
		_build_trust_page()
	_refresh()
	if _page != previous_page:
		GameAudio.play_ui_page_turn()


func _build_attribution_page() -> void:
	_page_host.add_child(AppStyle.label("刚才任务结果最主要由什么造成？（点击直接选择）",19,AppStyle.TEXT))
	_cause_buttons = []
	var row := HBoxContainer.new()
	row.name = "PrimaryCause"
	row.add_theme_constant_override("separation",10)
	_page_host.add_child(row)
	for i: int in range(CAUSE_OPTIONS.size()):
		var option := Button.new()
		option.text = CAUSE_OPTIONS[i]
		option.focus_mode = Control.FOCUS_NONE
		option.custom_minimum_size = Vector2(0,58)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_font_override("font",AppStyle.FONT_CJK)
		option.add_theme_font_size_override("font_size",15)
		AppStyle.wire_button_audio(option,"choice")
		option.pressed.connect(_on_cause_picked.bind(i + 1))
		row.add_child(option)
		_cause_buttons.append(option)
	_refresh_cause_buttons()
	_page_host.add_child(_scale("我对刚才原因判断有把握","attribution_confidence"))
	var hint := AppStyle.label("请根据刚才这一次具体飞行作答，而不是评价搭档的一贯表现。",14,AppStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_host.add_child(hint)


func _on_cause_picked(value: int) -> void:
	_answers["primary_cause"] = value
	_refresh_cause_buttons()
	_refresh()


func _refresh_cause_buttons() -> void:
	var picked := int(_answers.get("primary_cause",0))
	for i: int in range(_cause_buttons.size()):
		var option := _cause_buttons[i]
		if not is_instance_valid(option):
			continue
		var selected := picked == i + 1
		# 选中项高亮；一旦选过，未选中的整体压暗变透明。
		option.modulate.a = 1.0 if picked == 0 or selected else 0.38
		var fill := Color("11313f") if selected else AppStyle.PANEL_2
		var border := AppStyle.CYAN if selected else Color("29435a")
		AppStyle.set_button_hover_styles(
			option,
			_choice_box(fill,border,2 if selected else 1),
			_choice_box(Color("16394a"),AppStyle.CYAN,2),
			AppStyle.CYAN if selected else AppStyle.TEXT,
			AppStyle.CYAN
		)
		option.add_theme_stylebox_override("pressed",_choice_box(AppStyle.AMBER,AppStyle.TEXT,2))
		option.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
		option.text = ("✓ " + CAUSE_OPTIONS[i]) if selected else CAUSE_OPTIONS[i]


static func _choice_box(fill: Color,border: Color,width: int) -> StyleBoxFlat:
	var out := StyleBoxFlat.new()
	out.bg_color = fill
	out.border_color = border
	out.set_border_width_all(width)
	out.set_corner_radius_all(3)
	out.content_margin_left = 8
	out.content_margin_right = 8
	out.content_margin_top = 10
	out.content_margin_bottom = 10
	return out


func _build_trust_page() -> void:
	_page_host.add_child(_scale("现在我信任搭档能够完成其职责","partner_trust"))
	_page_host.add_child(_scale("现在我信任飞船与导航系统的信息","system_trust"))
	_page_host.add_child(_scale("下一段任务中，我愿意继续依赖搭档","continued_reliance"))


func _scale(question: String,key: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",2)
	var head := HBoxContainer.new()
	col.add_child(head)
	var q := AppStyle.label(question,16)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(q)
	var answered := _answers.has(key)
	var current := int(_answers.get(key,4))
	var value := AppStyle.label("%d / 7" % current if answered else "请选择",17,AppStyle.AMBER)
	head.add_child(value)
	var slider := HSlider.new()
	slider.name = "Scale_%s" % key
	slider.min_value = 1
	slider.max_value = 7
	slider.step = 1
	slider.value = current
	slider.tick_count = 7
	slider.ticks_on_borders = true
	AppStyle.style_slider(slider)
	slider.custom_minimum_size = Vector2(0,34)
	slider.value_changed.connect(func(v: float): _record_scale(key,int(v),value))
	slider.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_record_scale.call_deferred(key,int(round(slider.value)),value)
	)
	col.add_child(slider)
	var ends := HBoxContainer.new()
	var low := AppStyle.label("1  完全不同意",13,AppStyle.MUTED)
	low.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(low)
	ends.add_child(AppStyle.label("7  完全同意",13,AppStyle.MUTED))
	col.add_child(ends)
	return col


func _record_scale(key: String,value_number: int,value_label: Label) -> void:
	_answers[key] = value_number
	if is_instance_valid(value_label):
		value_label.text = "%d / 7" % value_number
	_refresh()


func _refresh() -> void:
	if _next != null:
		_next.disabled = not (_answers.has("primary_cause") and _answers.has("attribution_confidence"))
	if _submit != null:
		_submit.disabled = not _all_answered()


func _all_answered() -> bool:
	for key: String in ["primary_cause","attribution_confidence","partner_trust","system_trust","continued_reliance"]:
		if not _answers.has(key):
			return false
	return true


func _on_submit() -> void:
	_submit.disabled = true
	_submit.text = "已提交 · 等待搭档"
	_back.disabled = true
	submitted.emit(role,_answers.duplicate(true))
