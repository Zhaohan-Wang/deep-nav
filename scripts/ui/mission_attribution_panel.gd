class_name MissionAttributionPanel
extends Control
## 核心异常关结束后填写：先做异常觉察检查，再做 100 分责任预算分配。

const MissionFlightTrailScript = preload("res://scripts/ui/mission_flight_trail.gd")

signal submitted(display_role: String, answer: Dictionary)

const INSTRUMENT_VERSION := "event-attribution-5.0"
const BUDGET := 100
const STEP := 5
const ITEM_KEYS: Array[String] = ["self","partner","navigation_system","ship_system","environment"]

var display_role := ""
var participant_id := ""
var _record: Dictionary = {}
var _item_order: Array[String] = []
var _allocations: Dictionary = {}
var _confidence: Variant = null
var _event_awareness: Variant = null
var _awareness_buttons: Array[Button] = []
var _reset_count := 0
var _started_ms := 0
var _assigned_label: Label
var _remaining_label: Label
var _submit: Button
var _reset: Button
var _sliders: Dictionary = {}
var _value_labels: Dictionary = {}
var _confidence_buttons: Array[Button] = []
var _confidence_panel: Control
var _allocation_controls: Array[Control] = []
var _allocation_locked := false
var _updating := false


func setup(role_name: String,stable_participant_id: String,mission_record: Dictionary) -> void:
	display_role = role_name
	participant_id = stable_participant_id if not stable_participant_id.is_empty() else "preview-%s" % role_name
	_record = mission_record.duplicate(false)
	_prepare_item_order()
	for key: String in ITEM_KEYS:
		_allocations[key] = 0
	_started_ms = Time.get_ticks_msec()
	name = "MissionAttribution_%s" % display_role
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 980

	var dim := ColorRect.new()
	dim.color = Color(0.004,0.012,0.03,0.985)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right"]:
		safe.add_theme_constant_override("margin_%s" % side,12)
	for side: String in ["top","bottom"]:
		safe.add_theme_constant_override("margin_%s" % side,14)
	add_child(safe)
	var card := AppStyle.panel()
	card.name = "MissionAttributionCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := AppStyle.box(AppStyle.PANEL,Color("29435a"),2)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel",style)
	safe.add_child(card)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation",6)
	card.add_child(shell)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",8)
	shell.add_child(header)
	var title := AppStyle.label(_attribution_title(),22,AppStyle.CYAN)
	header.add_child(title)
	var context := AppStyle.label(_review_title(),15,AppStyle.AMBER)
	context.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(context)
	header.add_child(AppStyle.label(_review_meta(),12,AppStyle.MUTED))
	var privacy := AppStyle.label("请独立作答。你的答案不会向搭档展示。",11,AppStyle.MUTED)
	shell.add_child(privacy)
	shell.add_child(_awareness_row())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	shell.add_child(body)
	body.add_child(_review_column())
	var right_panel := PanelContainer.new()
	right_panel.name = "ResponsibilityAllocationPanel"
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel",_section_box(Color("071522"),Color("31566c"),2))
	body.add_child(right_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation",5)
	right_panel.add_child(right)
	var allocation_heading := HBoxContainer.new()
	allocation_heading.add_theme_constant_override("separation",8)
	right.add_child(allocation_heading)
	allocation_heading.add_child(_question_badge("问题 2"))
	var allocation_title := AppStyle.label("职责分配",18,AppStyle.TEXT)
	allocation_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	allocation_heading.add_child(allocation_title)
	allocation_heading.add_child(AppStyle.label("五项合计必须为 100 分",11,AppStyle.AMBER))
	var budget_title := AppStyle.label("结合这次事件及之后的航行，你认为以下各项应承担多少责任？",14,AppStyle.TEXT)
	budget_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(budget_title)
	var totals := HBoxContainer.new()
	var totals_spacer := Control.new()
	totals_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	totals.add_child(totals_spacer)
	_assigned_label = AppStyle.label("",13,AppStyle.CYAN)
	totals.add_child(_assigned_label)
	_remaining_label = AppStyle.label("",13,AppStyle.AMBER)
	totals.add_child(_remaining_label)
	right.add_child(totals)
	var operation_hint := AppStyle.label("拖动滑条或点击 −5／＋5。分数越高，表示责任越大；五项合计为100分。",10,AppStyle.MUTED)
	operation_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(operation_hint)
	var role_at_mission := _mission_role()
	for item_key: String in _item_order:
		right.add_child(_allocation_row(item_key,role_at_mission))
	_confidence_panel = _confidence_row()
	_confidence_panel.visible = false
	right.add_child(_confidence_panel)
	var action_spacer := Control.new()
	action_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(action_spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",10)
	right.add_child(actions)
	_reset = AppStyle.button("重新分配",Vector2(125,44))
	_reset.name = "ResetAllocation"
	_reset.pressed.connect(_reset_allocation)
	actions.add_child(_reset)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_submit = AppStyle.button("确认责任分配",Vector2(180,44),true)
	_submit.name = "SubmitAttribution"
	_submit.pressed.connect(_on_submit)
	actions.add_child(_submit)
	_refresh()


func _prepare_item_order() -> void:
	_item_order.assign(ITEM_KEYS)
	var rng := RandomNumberGenerator.new()
	# 同一参与者在两次异常归因中保持相同顺序，参与者之间独立随机。
	rng.seed = absi(hash("%s|%s|responsibility-order" % [Game.dyad_id,participant_id]))
	for i: int in range(_item_order.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var swap := _item_order[i]
		_item_order[i] = _item_order[j]
		_item_order[j] = swap


func _review_column() -> Control:
	var column := VBoxContainer.new()
	column.name = "MissionFlightReview"
	column.custom_minimum_size = Vector2(390,0)
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",6)
	if _is_target_event_mission() and _mission_image() != null:
		column.add_child(_screenshot_review_card())
	column.add_child(_trail_review_card())
	return column


func _trail_review_card() -> Control:
	var card := PanelContainer.new()
	card.name = "MissionTrailCard"
	card.custom_minimum_size = Vector2(0,70)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",_small_box(Color("07111e"),Color("29435a"),1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",2)
	card.add_child(col)
	var heading := HBoxContainer.new()
	col.add_child(heading)
	var trail_title := AppStyle.label("事件前后航迹",12,AppStyle.TEXT)
	trail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(trail_title)
	heading.add_child(AppStyle.label("青航迹 · 灰坠毁 · 红碰撞 · 琥珀异常",8,AppStyle.MUTED))
	var trail: Control = MissionFlightTrailScript.new()
	trail.name = "MissionFlightTrail"
	col.add_child(trail)
	trail.call("setup",_record)
	trail.custom_minimum_size = Vector2(370,58)
	return card


func _screenshot_review_card() -> Control:
	var card := PanelContainer.new()
	card.name = "MissionPeakCard"
	card.custom_minimum_size = Vector2(0,238)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.add_theme_stylebox_override("panel",_small_box(Color("07111e"),Color("5d4930"),1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",2)
	card.add_child(col)
	var heading := HBoxContainer.new()
	col.add_child(heading)
	var caption := AppStyle.label("事件发生时的航行画面",12,AppStyle.AMBER)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(caption)
	heading.add_child(AppStyle.label("包含当时系统提示",9,AppStyle.MUTED))
	var image_frame := Control.new()
	image_frame.name = "MissionScreenshot"
	# 原始参与者画面固定为 16:9；显示框保持同一比例，避免左右留黑或裁切证据。
	image_frame.custom_minimum_size = Vector2(370,208)
	col.add_child(image_frame)
	var texture := TextureRect.new()
	texture.name = "MissionScreenshotImage"
	texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var image := _mission_image()
	if image != null and not image.is_empty():
		texture.texture = ImageTexture.create_from_image(image)
	image_frame.add_child(texture)
	if texture.texture == null:
		var placeholder := AppStyle.label("本关画面未保存",15,AppStyle.MUTED)
		placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image_frame.add_child(placeholder)
	return card


func _allocation_row(item_key: String,mission_role: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	var label := AppStyle.label(_item_label(item_key,mission_role),13,AppStyle.TEXT)
	label.name = "AllocationLabel_%s" % item_key
	label.custom_minimum_size = Vector2(150,0)
	row.add_child(label)
	var minus := _small_button("−5",Vector2(44,31))
	minus.pressed.connect(_adjust.bind(item_key,-STEP))
	row.add_child(minus)
	_allocation_controls.append(minus)
	var slider := HSlider.new()
	slider.name = "Budget_%s" % item_key
	slider.min_value = 0
	slider.max_value = BUDGET
	slider.step = STEP
	slider.value = _value(item_key)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	AppStyle.style_slider(slider)
	slider.custom_minimum_size = Vector2(0,27)
	slider.value_changed.connect(_slider_changed.bind(item_key,slider))
	row.add_child(slider)
	_allocation_controls.append(slider)
	var plus := _small_button("＋5",Vector2(44,31))
	plus.pressed.connect(_adjust.bind(item_key,STEP))
	row.add_child(plus)
	_allocation_controls.append(plus)
	var value := AppStyle.label("%d分" % _value(item_key),14,AppStyle.AMBER)
	value.custom_minimum_size = Vector2(48,0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	_sliders[item_key] = slider
	_value_labels[item_key] = value
	return row


func _confidence_row() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",1)
	var row := HBoxContainer.new()
	row.name = "ConfidenceRow"
	row.add_theme_constant_override("separation",4)
	col.add_child(row)
	var question := AppStyle.label("对本次分配有多大把握？",13,AppStyle.TEXT)
	question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(question)
	var labels: Array[String] = ["完全没有把握","比较没有把握","有点没有把握","一般","有一些把握","比较有把握","非常有把握"]
	for score: int in range(1,8):
		var button := _small_button(str(score),Vector2(35,31))
		button.tooltip_text = "%d＝%s" % [score,labels[score-1]]
		button.pressed.connect(_set_confidence.bind(score))
		row.add_child(button)
		_confidence_buttons.append(button)
	var legend := AppStyle.label("1 完全没有 · 2 比较没有 · 3 有点没有 · 4 一般 · 5 有一些 · 6 比较有 · 7 非常有把握",10,AppStyle.MUTED)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(legend)
	return col


func _awareness_row() -> Control:
	var panel := PanelContainer.new()
	panel.name = "EventAwarenessCheck"
	panel.add_theme_stylebox_override("panel",_section_box(Color("0b1d2b"),Color("3d718b"),2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",9)
	panel.add_child(row)
	row.add_child(_question_badge("问题 1"))
	var question := AppStyle.label(_awareness_question(),14,AppStyle.TEXT)
	question.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question.custom_minimum_size = Vector2(250,0)
	question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(question)
	for entry: Dictionary in [
		{"value":"clear","label":"明确注意到"},
		{"value":"uncertain","label":"好像注意到，但不确定"},
		{"value":"not_noticed","label":"没有注意到"},
	]:
		var button := _small_button(str(entry.label),Vector2(126,32))
		button.pressed.connect(_set_event_awareness.bind(str(entry.value)))
		row.add_child(button)
		_awareness_buttons.append(button)
	return panel


func _question_badge(text: String) -> Label:
	var badge := AppStyle.label(text,12,Color("d8f6ff"))
	badge.custom_minimum_size = Vector2(62,30)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_stylebox_override("normal",_small_box(Color("16394a"),AppStyle.CYAN,1))
	return badge


func _set_event_awareness(value: String) -> void:
	if _allocation_locked: return
	_event_awareness = value
	_refresh()


func _adjust(item_key: String,delta: int) -> void:
	_set_value(item_key,_value(item_key)+delta)


func _slider_changed(raw_value: float,item_key: String,slider: HSlider) -> void:
	if _updating:
		return
	_set_value(item_key,int(round(raw_value/STEP))*STEP)
	_updating = true
	slider.set_value_no_signal(_value(item_key))
	_updating = false


func _set_value(item_key: String,requested: int) -> void:
	if _allocation_locked:
		return
	var current := _value(item_key)
	var accepted := clampi(requested,0,BUDGET)
	if accepted > current:
		accepted = mini(accepted,current+_remaining())
	accepted = int(round(float(accepted)/STEP))*STEP
	_allocations[item_key] = accepted
	_refresh()


func _set_confidence(score: int) -> void:
	if not _allocation_locked:
		return
	_confidence = score
	_refresh()


func _reset_allocation() -> void:
	for key: String in ITEM_KEYS:
		_allocations[key] = 0
	_confidence = null
	_reset_count += 1
	_refresh()


func _refresh() -> void:
	_updating = true
	for key: String in ITEM_KEYS:
		var slider := _sliders.get(key) as HSlider
		if slider != null:
			slider.set_value_no_signal(_value(key))
		var label := _value_labels.get(key) as Label
		if label != null:
			label.text = "%d分" % _value(key)
	_updating = false
	var assigned := _assigned()
	if _assigned_label != null:
		_assigned_label.text = "已分配：%d分 / 100分" % assigned
	if _remaining_label != null:
		_remaining_label.text = "剩余可分配：%d分" % (BUDGET-assigned)
	for i: int in range(_confidence_buttons.size()):
		var button := _confidence_buttons[i]
		button.disabled = not _allocation_locked
		var selected: bool = _confidence == i+1
		button.modulate.a = 1.0 if _confidence == null or selected else 0.45
		button.add_theme_color_override("font_color",AppStyle.CYAN if selected else AppStyle.TEXT)
	var awareness_values := ["clear","uncertain","not_noticed"]
	for i: int in range(_awareness_buttons.size()):
		var selected: bool = _event_awareness == awareness_values[i]
		_awareness_buttons[i].modulate.a = 1.0 if _event_awareness == null or selected else 0.48
		_awareness_buttons[i].add_theme_color_override("font_color",AppStyle.CYAN if selected else AppStyle.TEXT)
	if _submit != null:
		_submit.disabled = (_confidence == null) if _allocation_locked else (assigned != BUDGET or _event_awareness == null)


func _on_submit() -> void:
	if _submit.disabled:
		return
	if not _allocation_locked:
		_allocation_locked = true
		_reset.disabled = true
		for control: Control in _allocation_controls:
			if control is Button:
				(control as Button).disabled = true
			elif control is HSlider:
				(control as HSlider).editable = false
		_confidence_panel.visible = true
		_submit.text = "提交并继续"
		_refresh()
		GameAudio.play_ui_page_turn()
		return
	_submit.disabled = true
	_submit.text = "正在进入下一部分"
	submitted.emit(display_role,_answer())


func _answer() -> Dictionary:
	var elapsed := float(Time.get_ticks_msec()-_started_ms)/1000.0
	return {
		"instrument_version":INSTRUMENT_VERSION,
		"pair_id":Game.dyad_id,
		"participant_id":participant_id,
		"role":_mission_role(),
		"experimental_condition":Game.attribution_condition,
		"mission_id":str(_record.get("mission_id",Game.selected_mission_id)),
		"mission_label":_mission_label(),
		"outcome":str(_record.get("outcome","")),
		"outcome_success":bool(_record.get("success",false)),
		"event_type":"mission_responsibility",
		"questionnaire_variant":"event_responsibility_100" if _is_target_event_mission() else "mission_responsibility_100",
		"event_id":str(_record.get("event_id","%s-mission-review" % Game.selected_mission_id)),
		"attempt_number":int(_record.get("attempt_number",1)),
		"target_event_type":_record.get("target_event_type",null),
		"target_event_applicable":_is_target_event_mission(),
		"target_event_exposed":_record.get("target_event_exposed",null),
		"target_event_pulse_count":_record.get("target_event_pulse_count",null),
		"event_awareness":_event_awareness,
		"responsibility_self":_value("self"),
		"responsibility_partner":_value("partner"),
		"responsibility_navigation_system":_value("navigation_system"),
		"responsibility_ship_system":_value("ship_system"),
		"responsibility_environment":_value("environment"),
		"attribution_confidence":int(_confidence),
		"response_time":elapsed,
		"item_display_order":_item_order.duplicate(),
		"reset_count":_reset_count,
		"screenshot_available":_mission_image() != null,
		"capture_kind":str(_record.get("capture_kind","none")),
	}


func _value(item_key: String) -> int:
	return int(_allocations.get(item_key,0))


func _assigned() -> int:
	var total := 0
	for key: String in ITEM_KEYS:
		total += _value(key)
	return total


func _remaining() -> int:
	return BUDGET-_assigned()


func _view_record() -> Dictionary:
	var views := _record.get("views",{}) as Dictionary
	if views.has(participant_id):
		return views[participant_id] as Dictionary
	if views.has(display_role):
		return views[display_role] as Dictionary
	return {}


func _mission_image() -> Image:
	return _view_record().get("image") as Image


func _mission_role() -> String:
	return str(_view_record().get("role",display_role))


func _mission_label() -> String:
	var saved := str(_record.get("mission_label",""))
	if not saved.is_empty():
		return saved
	match str(_record.get("mission_id",Game.selected_mission_id)):
		"level_1": return "正式任务 01"
		"level_2": return "正式任务 02"
		_: return "正式任务 03"


func _review_meta() -> String:
	var elapsed := float(_record.get("elapsed",0.0))
	var outcome := str(_record.get("outcome",""))
	return "%s · 用时 %.1f 秒" % [outcome,elapsed] if not outcome.is_empty() else "用时 %.1f 秒" % elapsed


func _attribution_title() -> String:
	return "事件回顾与责任分配" if _is_target_event_mission() else "本关回顾与责任分配"


func _review_title() -> String:
	match str(_record.get("target_event_type","")):
		"waypoint_drift": return "%s · 航点位置偏移" % _mission_label()
		"ship_shear": return "%s · 飞船横向偏移" % _mission_label()
	return "%s · 本关航行表现" % _mission_label()


func _awareness_question() -> String:
	match str(_record.get("target_event_type","")):
		"waypoint_drift": return "在刚才的航行中，你是否注意到航点位置发生了偏移？"
		"ship_shear": return "在刚才的航行中，你是否注意到飞船出现了横向偏移？"
	return "在刚才的航行中，你是否注意到异常情况？"


func _is_target_event_mission() -> bool:
	return str(_record.get("target_event_type","")) in ["waypoint_drift","ship_shear"]


func _item_label(item_key: String,mission_role: String) -> String:
	match item_key:
		"self": return "我自己（%s）" % _role_text(mission_role)
		"partner": return "我的搭档（%s）" % _role_text("pilot" if mission_role == "navigator" else "navigator")
		"navigation_system": return "领航系统"
		"ship_system": return "飞船控制系统"
		_: return "外部环境"


func _role_text(role_name: String) -> String:
	return "领航员" if role_name == "navigator" else "驾驶员"


func _small_button(text: String,min_size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	button.add_theme_font_override("font",AppStyle.FONT_CJK)
	button.add_theme_font_size_override("font_size",13)
	button.add_theme_stylebox_override("normal",_small_box(AppStyle.PANEL_2,Color("29435a"),1))
	button.add_theme_stylebox_override("hover",_small_box(Color("16394a"),AppStyle.CYAN,2))
	button.add_theme_stylebox_override("pressed",_small_box(AppStyle.AMBER,AppStyle.TEXT,2))
	button.add_theme_stylebox_override("disabled",_small_box(Color("0a111b"),Color("1b2a38"),1))
	button.add_theme_color_override("font_disabled_color",Color(AppStyle.MUTED,0.45))
	AppStyle.wire_button_audio(button,"choice")
	return button


static func _small_box(fill: Color,border: Color,width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(3)
	box.content_margin_left = 5
	box.content_margin_right = 5
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


static func _section_box(fill: Color,border: Color,width: int) -> StyleBoxFlat:
	var box := _small_box(fill,border,width)
	box.set_corner_radius_all(5)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box
