class_name SurveyPanel
extends Control
## 训练关做操作理解；正常关测基线状态；异常关在责任分配后测即时状态信任。

signal submitted(role: String, answers: Dictionary)

const INSTRUMENT_VERSION := "post-attribution-state-4.2"
const BASELINE_INSTRUMENT_VERSION := "baseline-state-1.0"
const NAVIGATOR_TRAINING_ITEMS: Array[Array] = [
	["我知道如何在自己的星图上用鼠标设置航点。","navigator_can_place_waypoint"],
	["我知道可以按 E 键打开或关闭完整星图。","navigator_knows_map_toggle"],
	["我知道航点有最大设置距离，并且每次设置后需要等待冷却。","navigator_knows_waypoint_constraints"],
	["我知道需要根据航线情况向驾驶员说明方向，并在需要时更新航点。","navigator_knows_route_guidance"],
]
const PILOT_TRAINING_ITEMS: Array[Array] = [
	["我知道如何使用 W／S 控制推进或减速，使用 A／D 控制转向。","pilot_knows_flight_controls"],
	["我知道需要结合航点位置和当前飞行情况驾驶飞船。","pilot_knows_waypoint_flying"],
	["我知道需要观察飞船的速度、方向和船体状态，及时避开危险。","pilot_knows_flight_status"],
	["我知道在航点不清楚或需要调整路线时，应及时向领航员说明。","pilot_knows_status_communication"],
]
const TRUST_ORDERS: Array[Array] = [
	["partner","navigation","ship"], ["partner","ship","navigation"],
	["navigation","partner","ship"], ["navigation","ship","partner"],
	["ship","partner","navigation"], ["ship","navigation","partner"],
]

var role := ""
var outcome := ""
var _summary: Dictionary = {}
var _answers: Dictionary = {}
var _page_ids: Array = []
var _page := 0
var _mission_id := ""
var _started_ms := 0
var _page_host: VBoxContainer
var _step_label: Label
var _back: Button
var _next: Button
var _submit: Button
var _training_buttons: Dictionary = {}

func setup(role_name: String,outcome_name: String,summary: Dictionary) -> void:
	role = role_name
	outcome = outcome_name
	_summary = summary.duplicate(true)
	_mission_id = str(_summary.get("mission_id",Game.selected_mission_id))
	_page_ids = ["training"] if _mission_id == "practice" else _trust_order()
	_started_ms = Time.get_ticks_msec()
	var is_training := _mission_id == "practice"
	var is_baseline := _mission_id == "level_1"
	_answers = {
		"instrument_version":("training-role-comprehension-4.1" if is_training else
			(BASELINE_INSTRUMENT_VERSION if is_baseline else INSTRUMENT_VERSION)),
		"questionnaire_variant":("training_comprehension" if is_training else
			("baseline_state" if is_baseline else "post_attribution_state")),
		"mission_id":_mission_id,
		"outcome_success":bool(_summary.get("success",false)),
		"trust_block_order":_page_ids.duplicate() if _mission_id!="practice" else [],
		"training_review_required":false,
	}
	for item: Array in _training_items(): _answers[str(item[1])] = null
	_build()

func _trust_order() -> Array:
	var participant := Game.participant_id_for_role(role)
	if participant.is_empty(): participant = "preview-%s" % role
	return TRUST_ORDERS[posmod(hash("%s|trust-order" % participant),TRUST_ORDERS.size())].duplicate()

func _build() -> void:
	name = "SurveyPanel_%s" % role
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 990
	var dim := ColorRect.new(); dim.color=Color(0.006,0.014,0.035,0.985); dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(dim)
	var safe := MarginContainer.new(); safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right"]: safe.add_theme_constant_override("margin_%s"%side,32)
	for side: String in ["top","bottom"]: safe.add_theme_constant_override("margin_%s"%side,18)
	add_child(safe)
	var card := AppStyle.panel(); card.name="SurveyCard"; card.size_flags_horizontal=Control.SIZE_EXPAND_FILL; card.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var style := AppStyle.box(AppStyle.PANEL,Color("29435a"),2); style.content_margin_top=14; style.content_margin_bottom=14; card.add_theme_stylebox_override("panel",style); safe.add_child(card)
	var shell := VBoxContainer.new(); shell.add_theme_constant_override("separation",8); card.add_child(shell)
	var header := HBoxContainer.new(); shell.add_child(header)
	var title_text := ("操作理解检查" if _mission_id=="practice" else
		("基线状态评价" if _mission_id=="level_1" else "当前状态评价"))
	var title := AppStyle.label("%s · %s" % [title_text,_role_text()],24,AppStyle.CYAN); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(title)
	_step_label=AppStyle.label("",17,AppStyle.AMBER); header.add_child(_step_label)
	var privacy_text := ("请根据刚才的练习回答。" if _mission_id=="practice" else
		("请根据刚才的正常航行回答；你的答案不会向搭档展示。" if _mission_id=="level_1" else
		"责任分配已完成。请根据刚才的航行回答以下问题；你的答案不会向搭档展示。"))
	var privacy := AppStyle.label(privacy_text,14,AppStyle.MUTED); privacy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; shell.add_child(privacy)
	shell.add_child(HSeparator.new())
	_page_host=VBoxContainer.new(); _page_host.name="SurveyPageHost"; _page_host.size_flags_vertical=Control.SIZE_EXPAND_FILL; _page_host.add_theme_constant_override("separation",8); shell.add_child(_page_host)
	var footer := HBoxContainer.new(); footer.add_theme_constant_override("separation",12); shell.add_child(footer)
	_back=AppStyle.button("上一步",Vector2(180,50)); _back.pressed.connect(func():_show_page(_page-1)); footer.add_child(_back)
	var spacer:=Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL; footer.add_child(spacer)
	_next=AppStyle.button("下一类对象",Vector2(220,50),true); _next.pressed.connect(func():_show_page(_page+1)); footer.add_child(_next)
	_submit=AppStyle.button("提交并继续",Vector2(250,50),true); _submit.pressed.connect(_on_submit); footer.add_child(_submit)
	_show_page(0)

func _show_page(index: int) -> void:
	_page=clampi(index,0,_page_ids.size()-1)
	for child: Node in _page_host.get_children(): child.queue_free()
	_training_buttons.clear()
	_step_label.text="操作检查" if _mission_id=="practice" else "第 %d / 3 部分"%(_page+1)
	_back.visible=_page>0; _next.visible=_page<_page_ids.size()-1; _submit.visible=_page==_page_ids.size()-1
	match str(_page_ids[_page]):
		"training": _build_training()
		"partner":
			var partner := _partner_label()
			_build_trust_block(partner,[
				["经过刚才的任务经历，我认为%s仍然能够可靠地履行自己的任务职责。"%partner,"partner_state_reliability"],
				["在接下来的航行中，我愿意继续依赖%s提供的判断或操作。"%partner,"partner_state_reliance"],])
		"navigation": _build_trust_block("领航系统",[
			["经过刚才的任务经历，我认为领航系统提供的信息仍然是可靠的。","navigation_state_reliability"],
			["在接下来的航行中，我愿意继续依据领航系统提供的信息行动。","navigation_state_reliance"],])
		"ship": _build_trust_block("飞船控制系统",[
			["经过刚才的任务经历，我认为飞船控制系统对操作输入的响应仍然是可靠的。","ship_state_reliability"],
			["在接下来的航行中，我愿意继续依赖飞船控制系统完成任务。","ship_state_reliance"],])
	_refresh()

func _build_training() -> void:
	_page_host.add_child(AppStyle.label("以下内容只检查你刚才承担的%s岗位。请选择“是／不确定／否”。" % _role_text(),17,AppStyle.TEXT))
	for item: Array in _training_items():
		_add_training_choice(str(item[0]),str(item[1]))

func _add_training_choice(question: String,key: String) -> void:
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",8)
	var label:=AppStyle.label(question,15,AppStyle.TEXT); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
	var buttons:Array[Button]=[]
	for entry:Dictionary in [{"v":"yes","t":"是"},{"v":"unsure","t":"不确定"},{"v":"no","t":"否"}]:
		var button:=AppStyle.button(entry.t,Vector2(92,43)); button.pressed.connect(_record_training.bind(key,entry.v)); row.add_child(button); buttons.append(button)
	_training_buttons[key]=buttons; _page_host.add_child(row); _refresh_training(key)

func _record_training(key:String,value:String)->void:
	_answers[key]=value; _refresh_training(key); _refresh()

func _refresh_training(key:String)->void:
	var values:Array[String]=["yes","unsure","no"]; var picked:=str(_answers.get(key,"")); var buttons:=_training_buttons.get(key,[]) as Array
	for i:int in range(buttons.size()): (buttons[i] as Button).modulate.a=1.0 if picked.is_empty() or picked==values[i] else 0.45

func _build_trust_block(block_title:String,items:Array)->void:
	_page_host.add_child(AppStyle.label("根据刚才的任务经历，请评价你目前对%s的看法。"%block_title,18,AppStyle.TEXT))
	for item:Array in items:
		_page_host.add_child(_scale(str(item[0]),str(item[1])))
		var spacer:=Control.new(); spacer.custom_minimum_size=Vector2(0,18); spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL; _page_host.add_child(spacer)

func _scale(question:String,key:String)->Control:
	var col:=VBoxContainer.new(); col.add_theme_constant_override("separation",5)
	var head:=HBoxContainer.new(); col.add_child(head)
	var q:=AppStyle.label(question,16,AppStyle.TEXT); q.size_flags_horizontal=Control.SIZE_EXPAND_FILL; q.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; head.add_child(q)
	var value_label:=AppStyle.label("请选择",16,AppStyle.AMBER); head.add_child(value_label)
	var slider:=HSlider.new(); slider.name="Scale_%s"%key; slider.min_value=1; slider.max_value=7; slider.step=1; slider.value=4; slider.tick_count=7; slider.ticks_on_borders=true; slider.custom_minimum_size=Vector2(0,36); AppStyle.style_slider(slider)
	slider.value_changed.connect(func(value:float): _answers[key]=int(value); value_label.text="%d / 7"%int(value); _refresh())
	col.add_child(slider)
	var ends:=HBoxContainer.new(); var low:=AppStyle.label("1  完全不同意",13,AppStyle.MUTED); low.size_flags_horizontal=Control.SIZE_EXPAND_FILL; ends.add_child(low); ends.add_child(AppStyle.label("7  完全同意",13,AppStyle.MUTED)); col.add_child(ends)
	return col

func _page_complete()->bool:
	var keys:Array[String]=[]
	match str(_page_ids[_page]):
		"training":
			for item: Array in _training_items(): keys.append(str(item[1]))
		"partner": keys=["partner_state_reliability","partner_state_reliance"]
		"navigation": keys=["navigation_state_reliability","navigation_state_reliance"]
		"ship": keys=["ship_state_reliability","ship_state_reliance"]
	for key:String in keys:
		if not _answers.has(key) or _answers[key]==null: return false
	return true

func _refresh()->void:
	if _next!=null: _next.disabled=not _page_complete()
	if _submit!=null: _submit.disabled=not _page_complete()

func _on_submit()->void:
	if not _page_complete(): return
	if _mission_id=="practice":
		for item: Array in _training_items():
			var key := str(item[1])
			if str(_answers.get(key,""))!="yes": _answers.training_review_required=true
	_answers.response_time=float(Time.get_ticks_msec()-_started_ms)/1000.0
	_submit.disabled=true; _submit.text="已提交 · 等待搭档"
	submitted.emit(role,_answers.duplicate(true)); _show_waiting()

func _role_text()->String: return "领航员" if role=="navigator" else "驾驶员"

func _partner_label()->String: return "我的搭档（驾驶员）" if role=="navigator" else "我的搭档（领航员）"

func _training_items() -> Array[Array]:
	return NAVIGATOR_TRAINING_ITEMS if role=="navigator" else PILOT_TRAINING_ITEMS

func _show_waiting() -> void:
	var cover := ColorRect.new(); cover.color=Color(0.006,0.014,0.035,0.99); cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); cover.z_index=0; add_child(cover)
	var center:=CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); center.z_index=1; add_child(center)
	var card:=AppStyle.panel(); card.custom_minimum_size=Vector2(600,260); center.add_child(card)
	var box:=VBoxContainer.new(); box.alignment=BoxContainer.ALIGNMENT_CENTER; box.add_theme_constant_override("separation",16); card.add_child(box)
	var title:=AppStyle.label("你的回答已提交",28,AppStyle.CYAN); title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; box.add_child(title)
	var note:=AppStyle.label("请留在本页等待搭档完成。\n双方提交前请不要讨论问卷内容。",17,AppStyle.TEXT); note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; box.add_child(note)
