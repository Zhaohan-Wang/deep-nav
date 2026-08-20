class_name SurveyPanel
extends Control
## 任务结束后的独立三步微量表：先锚定客观航向事件，再分别测量搭档与系统状态信任。

signal submitted(role: String, answers: Dictionary)

const INSTRUMENT_VERSION := "event-attribution-2.2"
const PAGE_COUNT := 3
const REQUIRED_KEYS: Array[String] = [
	"event_primary_cause","event_attribution_confidence",
	"partner_capability_trust","partner_predictability","partner_reliance_intent",
	"navigation_information_trust","ship_response_predictability","system_reliance_intent",
]

var role: String
var outcome: String
var _summary: Dictionary = {}
var _answers: Dictionary = {}
var _page := 0
var _page_host: VBoxContainer
var _step_label: Label
var _back: Button
var _next: Button
var _submit: Button
var _cause_buttons: Array[Button] = []


func setup(role_name: String, outcome_name: String, summary: Dictionary) -> void:
	role = role_name
	outcome = outcome_name
	_summary = summary.duplicate(true)
	_answers = {
		"instrument_version": INSTRUMENT_VERSION,
		"outcome_success": bool(_summary.get("success",false)),
		"severe_heading_deviations_observed": int(_summary.get("severe_heading_deviations",0)),
		"waypoint_drift_events_observed": int(_summary.get("waypoint_drift_events",0)),
		"ship_shear_events_observed": int(_summary.get("ship_shear_events",0)),
	}
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
		safe.add_theme_constant_override("margin_%s" % side,16)
	add_child(safe)
	var card := AppStyle.panel()
	card.name = "SurveyCard"
	var card_style := AppStyle.box(AppStyle.PANEL,Color("29435a"),2)
	card_style.content_margin_top = 12
	card_style.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel",card_style)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe.add_child(card)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation",6)
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
	_page_host.add_theme_constant_override("separation",5)
	shell.add_child(_page_host)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",12)
	shell.add_child(footer)
	_back = AppStyle.button("上一步",Vector2(180,50))
	AppStyle.set_button_audio_cue(_back,"page_turn")
	_back.pressed.connect(func(): _show_page(_page-1))
	footer.add_child(_back)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_next = AppStyle.button("下一步",Vector2(220,50),true)
	AppStyle.set_button_audio_cue(_next,"page_turn")
	_next.pressed.connect(func(): _show_page(_page+1))
	footer.add_child(_next)
	_submit = AppStyle.button("提交个人答案",Vector2(260,50),true)
	AppStyle.set_button_audio_cue(_submit,"confirm")
	_submit.pressed.connect(_on_submit)
	footer.add_child(_submit)
	_show_page(0)


func _role_text() -> String:
	return "领航员" if role == "navigator" else "驾驶员"


func _partner_role_text() -> String:
	return "驾驶员" if role == "navigator" else "领航员"


func _cause_options() -> Array[String]:
	if role == "navigator":
		return [
			"我的航点引导\n落点、时机、路线",
			"驾驶员操控\n转向、速度、响应",
			"导航信息\n航点、方向、仪表",
			"飞船响应\n转向、变速不如预期",
			"航行环境\n外力、障碍、航道",
			"多种原因\n没有单一主因",
			"无法判断\n信息不足",
		]
	return [
		"我的操控\n转向、速度、响应",
		"领航员引导\n落点、时机、路线",
		"导航信息\n航点、方向、仪表",
		"飞船响应\n转向、变速不如预期",
		"航行环境\n外力、障碍、航道",
		"多种原因\n没有单一主因",
		"无法判断\n信息不足",
	]


func _show_page(index: int) -> void:
	var previous_page := _page
	_page = clampi(index,0,PAGE_COUNT-1)
	for child: Node in _page_host.get_children():
		child.queue_free()
	_step_label.text = "步骤 %d / %d" % [_page+1,PAGE_COUNT]
	_back.visible = _page > 0
	_next.visible = _page < PAGE_COUNT-1
	_submit.visible = _page == PAGE_COUNT-1
	match _page:
		0: _build_attribution_page()
		1: _build_partner_page()
		2: _build_system_page()
	_refresh()
	if _page != previous_page:
		GameAudio.play_ui_page_turn()


func _build_attribution_page() -> void:
	var context := AppStyle.label(_outcome_context_text(),15,AppStyle.AMBER)
	context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_host.add_child(context)
	_page_host.add_child(_event_metric_cards())
	_page_host.add_child(HSeparator.new())
	_page_host.add_child(AppStyle.label(_attribution_question(),18,AppStyle.TEXT))
	var guide := AppStyle.label("导航信息＝看到的内容；飞船响应＝实际转向和变速。",14,AppStyle.CYAN)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_page_host.add_child(guide)
	_cause_buttons = []
	var options := _cause_options()
	var grid := GridContainer.new()
	grid.name = "EventPrimaryCause"
	grid.columns = 4
	grid.custom_minimum_size = Vector2(0,110)
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	_page_host.add_child(grid)
	for i: int in range(options.size()):
		var option := Button.new()
		option.text = options[i]
		option.focus_mode = Control.FOCUS_NONE
		option.custom_minimum_size = Vector2(0,57)
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		option.add_theme_font_override("font",AppStyle.FONT_CJK)
		option.add_theme_font_size_override("font_size",13)
		option.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		AppStyle.wire_button_audio(option,"choice")
		option.pressed.connect(_on_cause_picked.bind(i + 1))
		grid.add_child(option)
		_cause_buttons.append(option)
	_refresh_cause_buttons()
	_page_host.add_child(_scale("我对以上原因判断有把握","event_attribution_confidence"))


func _outcome_context_text() -> String:
	if bool(_summary.get("success",false)):
		return "本局已完成。只判断下列航向事件，不评价任务成败。"
	return "本局未完成。只判断下列航向事件，不评价任务成败。"


func _event_metric_cards() -> Control:
	var row := HBoxContainer.new()
	row.name = "ObjectiveEventFacts"
	row.add_theme_constant_override("separation",8)
	row.add_child(_metric_card("Metric_SevereHeading","严重航向偏离",int(_summary.get("severe_heading_deviations",0)),"次",AppStyle.AMBER))
	row.add_child(_metric_card("Metric_WaypointDirection","航点方向改变",int(_summary.get("waypoint_drift_events",0)),"次",AppStyle.CYAN))
	row.add_child(_metric_card("Metric_LateralShift","飞船横向偏移",int(_summary.get("ship_shear_events",0)),"次",AppStyle.CYAN))
	row.add_child(_metric_card("Metric_Impacts","碰撞 / 解体",int(_summary.get("hits",0))," / %d 次" % int(_summary.get("revivals",0)),AppStyle.MUTED))
	return row


func _metric_card(node_name: String,title: String,value: int,suffix: String,accent: Color) -> Control:
	var card := PanelContainer.new()
	card.name = node_name
	card.custom_minimum_size = Vector2(0,66)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",_metric_box(accent))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation",2)
	card.add_child(col)
	var heading := AppStyle.label(title,14,accent)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)
	var number := AppStyle.label("%d%s" % [value,suffix],21,AppStyle.TEXT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(number)
	return card


static func _metric_box(accent: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("0e1b2b")
	box.border_color = Color(accent,0.72)
	box.set_border_width_all(2)
	box.set_corner_radius_all(3)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _attribution_question() -> String:
	var observed := (
		int(_summary.get("severe_heading_deviations",0))
		+ int(_summary.get("waypoint_drift_events",0))
		+ int(_summary.get("ship_shear_events",0))
	)
	if observed > 0:
		return "这些航向事件主要受哪个因素影响？"
	return "本局航向保持主要受哪个因素影响？"


func _on_cause_picked(value: int) -> void:
	_answers["event_primary_cause"] = value
	_refresh_cause_buttons()
	_refresh()


func _refresh_cause_buttons() -> void:
	var picked := int(_answers.get("event_primary_cause",0))
	var options := _cause_options()
	for i: int in range(_cause_buttons.size()):
		var option := _cause_buttons[i]
		if not is_instance_valid(option):
			continue
		var selected := picked == i + 1
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
		option.text = ("✓ " + options[i]) if selected else options[i]


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


func _build_partner_page() -> void:
	var partner := _partner_role_text()
	_page_host.add_child(AppStyle.label("搭档状态 · %s" % partner,18,AppStyle.TEXT))
	if role == "navigator":
		_page_host.add_child(_scale("驾驶员能准确执行航点","partner_capability_trust"))
		_add_vertical_spacer()
		_page_host.add_child(_scale("驾驶员的操作可预期","partner_predictability"))
	else:
		_page_host.add_child(_scale("领航员能给出及时、可执行的航点","partner_capability_trust"))
		_add_vertical_spacer()
		_page_host.add_child(_scale("领航员的航点安排可预期","partner_predictability"))
	_add_vertical_spacer()
	_page_host.add_child(_scale("下一关我愿意继续依赖%s" % partner,"partner_reliance_intent"))


func _build_system_page() -> void:
	_page_host.add_child(AppStyle.label("航行设备",18,AppStyle.TEXT))
	_page_host.add_child(_scale("导航信息可信（航点、方向、仪表）","navigation_information_trust"))
	_add_vertical_spacer()
	_page_host.add_child(_scale("飞船响应可预期（转向、速度）","ship_response_predictability"))
	_add_vertical_spacer()
	_page_host.add_child(_scale("下一关我愿意继续依赖航行设备","system_reliance_intent"))


func _add_vertical_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0,6)
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(spacer)


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


func _page_complete() -> bool:
	var keys: Array[String]
	match _page:
		0: keys = ["event_primary_cause","event_attribution_confidence"]
		1: keys = ["partner_capability_trust","partner_predictability","partner_reliance_intent"]
		_: keys = ["navigation_information_trust","ship_response_predictability","system_reliance_intent"]
	for key: String in keys:
		if not _answers.has(key):
			return false
	return true


func _refresh() -> void:
	if _next != null:
		_next.disabled = not _page_complete()
	if _submit != null:
		_submit.disabled = not _all_answered()


func _all_answered() -> bool:
	for key: String in REQUIRED_KEYS:
		if not _answers.has(key):
			return false
	return true


func _on_submit() -> void:
	_submit.disabled = true
	_submit.text = "已提交 · 等待搭档"
	_back.disabled = true
	submitted.emit(role,_answers.duplicate(true))
