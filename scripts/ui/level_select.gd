extends Control

const UI = preload("res://scripts/ui/app_style.gd")
const Catalog = preload("res://scripts/mission_catalog.gd")
const Preview = preload("res://scripts/ui/mission_preview.gd")

## 认领角色卡的顺序：0 = 领航员，1 = 驾驶员。
const ROLE_NAMES: Array[String] = ["领航员", "驾驶员"]
const ROLE_BLURBS: Array[String] = ["掌握星图与航线 · 使用所在屏幕键盘的 E 键开关星图", "掌握驾驶舱与推进 · 使用所在屏幕键盘的 WASD 驾驶"]
const ROLE_ICONS: Array[String] = [UiStyle.NAVIGATOR_BADGE_PATH, UiStyle.PILOT_BADGE_PATH]
const SEAT_NONE: int = -1
const SEAT_A: int = 0
const SEAT_B: int = 1

var _selected: SectorData
var _detail: VBoxContainer
var _cards: Array[Button] = []
var _confirm_layer: Control
var _role_claims: Array[int] = [SEAT_NONE, SEAT_NONE]
var _claim_cards: Array[PanelContainer] = []
var _claim_status: Array[Label] = []
var _claim_hover: Array[bool] = [false, false]
var _claim_hint: Label
var _start_button: Button
var _selection_status: Label
var _launch_button: Button


func _ready() -> void:
	Displays.show_shared_page()
	RawMice.keyboard_device_changed.connect(_on_keyboard_device_changed)
	add_child(UI.page())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",76)
	margin.add_theme_constant_override("margin_right",76)
	margin.add_theme_constant_override("margin_top",42)
	margin.add_theme_constant_override("margin_bottom",42)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation",20)
	margin.add_child(root)
	_build_header(root)
	var divider := ColorRect.new()
	divider.color = Color(UI.CYAN,0.25)
	divider.custom_minimum_size.y = 2
	root.add_child(divider)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",26)
	root.add_child(body)
	_build_mission_list(body)
	var panel := UI.panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 680
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation",14)
	scroll.add_child(_detail)
	_build_footer(root)
	if Game.unlock_all_missions():
		var open_id := Game.selected_mission_id
		if open_id.is_empty() or not Catalog.IDS.has(open_id):
			open_id = Catalog.IDS[0]
		_select(Catalog.by_id(open_id))
	elif Game.active_mission_id().is_empty():
		_show_sequence_complete()
	else:
		_select(Catalog.by_id(Game.active_mission_id()))


func _build_header(root: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 76
	root.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation",2)
	header.add_child(titles)
	var eyebrow := UI.label("DEEP NAV  /  MISSION SEQUENCE",15,UI.MUTED)
	eyebrow.add_theme_font_override("font",UI.FONT_BODY)
	titles.add_child(eyebrow)
	titles.add_child(UI.label("任务进度",42,UI.CYAN))
	var mode := VBoxContainer.new()
	mode.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(mode)
	var mode_label := UI.label(_mode_text(),18,UI.AMBER)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode.add_child(mode_label)
	var active_number := mini(Game.session_mission_index + 1,Catalog.IDS.size())
	var progress_text := "测试入口 · 全部关卡开放"
	if not Game.unlock_all_missions():
		progress_text = "全部任务已结束" if Game.active_mission_id().is_empty() else "当前任务 %02d / %02d" % [active_number,Catalog.IDS.size()]
	var progress := UI.label(progress_text,16,UI.MUTED)
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode.add_child(progress)


func _build_mission_list(body: HBoxContainer) -> void:
	var list := VBoxContainer.new()
	list.custom_minimum_size = Vector2(420,0)
	list.add_theme_constant_override("separation",10)
	body.add_child(list)
	list.add_child(UI.label("本次流程",18,UI.AMBER))
	for mission: SectorData in Catalog.all():
		var status := Game.mission_session_status(mission.id)
		var unlocked := Game.unlock_all_missions()
		var prefix := "✓" if status == "completed" else ("▶" if status == "current" or unlocked else "◆")
		var suffix := "已结束" if status == "completed" else ("当前任务" if status == "current" else ("测试开放" if unlocked else "尚未开放"))
		var b := UI.button("%s  %02d   %s     %s" % [prefix,mission.order_index,mission.public_display_name(),suffix],Vector2(420,72))
		UI.set_button_audio_cue(b,"choice")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not unlocked and status != "current"
		b.modulate.a = 1.0 if unlocked or status == "current" else (0.54 if status == "completed" else 0.28)
		if unlocked or status == "current":
			b.pressed.connect(_select.bind(mission))
		list.add_child(b)
		_cards.append(b)


func _build_footer(root: VBoxContainer) -> void:
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",18)
	root.add_child(footer)
	var back := UI.button("返回",Vector2(220,66))
	UI.set_button_audio_cue(back,"page_turn")
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title_screen.tscn"))
	footer.add_child(back)
	_selection_status = UI.label("",18,UI.MUTED)
	_selection_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(_selection_status)
	_launch_button = UI.button("进入准备确认",Vector2(340,66),true)
	UI.set_button_audio_cue(_launch_button,"popup_open")
	_launch_button.disabled = not Game.unlock_all_missions() and Game.active_mission_id().is_empty()
	_launch_button.text = "流程已完成" if _launch_button.disabled else "进入准备确认"
	_launch_button.pressed.connect(_open_confirm)
	footer.add_child(_launch_button)


func _mode_text() -> String:
	if Game.unlock_all_missions():
		return "◇ 预览模式 · 关卡全开"
	if Game.experiment_mode:
		return "● 实验模式 · 正式记录"
	if Game.researcher_debug_enabled():
		return "◆ 研究调试 · 参数可见"
	return "预览模式"


func _select(mission: SectorData) -> void:
	_selected = mission
	var current := Game.can_play_mission(mission.id)
	_selection_status.text = "当前任务  %02d / %s" % [mission.order_index,mission.public_display_name()] if current else "任务记录  %02d / %s" % [mission.order_index,mission.public_display_name()]
	if _launch_button != null:
		_launch_button.disabled = not current
	for child in _detail.get_children():
		child.queue_free()
	_detail.add_child(_mission_preview(mission))
	var title_row := HBoxContainer.new()
	_detail.add_child(title_row)
	var index := UI.label("%02d" % mission.order_index,42,UI.AMBER)
	index.custom_minimum_size.x = 72
	title_row.add_child(index)
	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title_box)
	title_box.add_child(UI.label(mission.public_display_name(),31,UI.TEXT))
	var destination := _destination_name(mission)
	title_box.add_child(UI.label("目的地  /  %s" % destination,17,UI.CYAN))
	var brief := UI.label(_public_briefing(mission),20,UI.TEXT)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(brief)
	_detail.add_child(_section_rule("任务规则"))
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation",12)
	_detail.add_child(stats)
	stats.add_child(_stat_card("任务时限","%d 秒" % int(mission.time_limit_s)))
	var revival := "解体后返回起点" if mission.relay_stations.is_empty() else "解体后返回已抵达的中继站"
	stats.add_child(_stat_card("复活规则",revival))
	_detail.add_child(_section_rule("协作提示"))
	var hint := UI.label(_public_hint(mission),18,UI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(hint)
	if Game.researcher_debug_enabled():
		_add_research_debug(mission)


func _show_sequence_complete() -> void:
	_selected = null
	_selection_status.text = "本次流程已完成"
	for child in _detail.get_children():
		child.queue_free()
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 110
	_detail.add_child(spacer)
	var done := UI.label("全部任务已结束",38,UI.CYAN)
	done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_child(done)
	var note := UI.label("本次临时进度已经走完。\n返回标题页重新开始，或退出应用后再次启动，即可从第一关重新进行。",20,UI.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(note)


func _mission_preview(mission: SectorData) -> Control:
	var path := "res://assets/ui/mission_previews/%s.jpg" % mission.id
	if ResourceLoader.exists(path):
		var preview := Control.new()
		preview.custom_minimum_size = Vector2(0.0,470.0)
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 凹槽底色完整包住图片：图片低于面板表面，而不是向外投影。
		var recess := ColorRect.new()
		recess.color = Color("030812")
		recess.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		recess.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(recess)
		var frame := Control.new()
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		frame.offset_left = 9.0
		frame.offset_top = 9.0
		frame.offset_right = -9.0
		frame.offset_bottom = -9.0
		frame.clip_contents = true
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(frame)
		var image := TextureRect.new()
		image.texture = load(path) as Texture2D
		image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(image)
		# 上/左压暗，模拟内凹阴影；下/右细反光定义凹槽底面。
		var inner_top := ColorRect.new()
		inner_top.color = Color(0.0,0.0,0.0,0.48)
		inner_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
		inner_top.offset_bottom = 14.0
		inner_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(inner_top)
		var inner_left := ColorRect.new()
		inner_left.color = Color(0.0,0.0,0.0,0.42)
		inner_left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		inner_left.offset_right = 14.0
		inner_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(inner_left)
		var inner_bottom := ColorRect.new()
		inner_bottom.color = Color(UI.CYAN,0.22)
		inner_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		inner_bottom.offset_top = -2.0
		inner_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(inner_bottom)
		var inner_right := ColorRect.new()
		inner_right.color = Color(UI.CYAN,0.18)
		inner_right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		inner_right.offset_left = -2.0
		inner_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(inner_right)
		return preview
	var fallback := Preview.new()
	fallback.mission_index = mission.order_index
	return fallback


func _section_rule(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	row.add_child(UI.label(text,16,UI.AMBER))
	var line := ColorRect.new()
	line.color = Color(UI.CYAN,0.18)
	line.custom_minimum_size.y = 1
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line)
	return row


func _stat_card(caption: String,value: String) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",UI.box(UI.PANEL_2,Color("29435a"),1))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",3)
	panel.add_child(box)
	box.add_child(UI.label(caption,15,UI.MUTED))
	box.add_child(UI.label(value,23,UI.CYAN))
	return panel


func _add_research_debug(mission: SectorData) -> void:
	_detail.add_child(_section_rule("RESEARCH DEBUG · 参与者不可见"))
	var slots := "无" if mission.disturbance_slots.is_empty() else ", ".join(mission.disturbance_slots)
	var debug_text := "研究目的：%s\n条件标签：%s\n路线检查点：%d  ·  扰动槽位：%s  ·  扰动锚点：%d  ·  安全门：%d\n世界半径：%.0f  ·  天体：%d  ·  小行星带：%d" % [
		mission.design_intent,mission.challenge_type,mission.route_checkpoints.size(),slots,
		mission.disturbance_anchors.size(),mission.safe_gate_points.size(),mission.world_half,
		mission.bodies.size(),mission.belts.size()
	]
	var debug := UI.label(debug_text,15,UI.DANGER)
	debug.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(debug)


func _destination_name(mission: SectorData) -> String:
	for body: CelestialBodyData in mission.bodies:
		if body.id == mission.objective_body_id:
			return body.display_name
	return "待载入"


func _public_briefing(mission: SectorData) -> String:
	return mission.participant_briefing if not mission.participant_briefing.is_empty() else "抵达指定目标航区。"


func _public_hint(mission: SectorData) -> String:
	return mission.participant_hint if not mission.participant_hint.is_empty() else "保持沟通，并根据当前星图分段规划航点。"


func _unhandled_input(event: InputEvent) -> void:
	if _confirm_layer != null and event.is_action_pressed("ui_cancel"):
		_close_confirm()
		get_viewport().set_input_as_handled()


func _open_confirm() -> void:
	if _selected == null or not Game.can_play_mission(_selected.id) or _confirm_layer != null:
		return
	_role_claims = [SEAT_NONE, SEAT_NONE]
	_claim_cards = []
	_claim_status = []
	_claim_hover = [false, false]
	_confirm_layer = Control.new()
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm_layer)
	# 全屏不透明底：认领页是独立的一步，不让底下的任务列表透出来干扰。
	var dim := ColorRect.new()
	dim.color = UI.BG
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",56)
	margin.add_theme_constant_override("margin_right",56)
	margin.add_theme_constant_override("margin_top",28)
	margin.add_theme_constant_override("margin_bottom",28)
	_confirm_layer.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",18)
	margin.add_child(box)

	# 头部：任务标题 + 关闭按钮。
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",20)
	box.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation",2)
	header.add_child(titles)
	var eyebrow := UI.label("MISSION START  /  CREW ASSIGNMENT",15,UI.MUTED)
	eyebrow.add_theme_font_override("font",UI.FONT_BODY)
	titles.add_child(eyebrow)
	titles.add_child(UI.label("认领角色 · %02d %s" % [_selected.order_index,_selected.public_display_name()],38,UI.CYAN))
	var close := UI.button("✕ 关闭",Vector2(170,58))
	UI.set_button_audio_cue(close,"popup_close")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(_close_confirm)
	header.add_child(close)

	var divider := ColorRect.new()
	divider.color = Color(UI.CYAN,0.25)
	divider.custom_minimum_size.y = 2
	box.add_child(divider)

	var instruction := UI.label("两位成员分别用自己屏幕的鼠标点击下方卡片认领角色；认领结果决定任务中每块屏幕显示谁的画面。再次点击可取消认领。",20,UI.TEXT)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(instruction)

	# 角色卡片上下各占一行，横幅图标才能铺满整宽。
	var cards := VBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation",16)
	box.add_child(cards)
	for role_index: int in range(ROLE_NAMES.size()):
		var card := _build_claim_card(role_index)
		cards.add_child(card)
		_claim_cards.append(card)

	_claim_hint = UI.label("等待认领：屏幕 A（青色光标）与屏幕 B（琥珀色光标）各认领一个角色",19,UI.MUTED)
	_claim_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_claim_hint.custom_minimum_size.y = 30
	box.add_child(_claim_hint)

	# 底部动作行。
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",20)
	box.add_child(actions)
	var change := UI.button("更换模式",Vector2(280,66))
	UI.set_button_audio_cue(change,"page_turn")
	change.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title_screen.tscn"))
	actions.add_child(change)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_start_button = UI.button("等待双方认领",Vector2(420,66),true)
	_start_button.disabled = true
	UI.set_button_audio_cue(_start_button,"confirm")
	_start_button.pressed.connect(_launch)
	actions.add_child(_start_button)
	_refresh_claim_ui()


func _build_claim_card(role_index: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_claim_card_input.bind(role_index))
	UI.wire_control_hover(
		card,
		_on_claim_card_hover.bind(role_index,true),
		_on_claim_card_hover.bind(role_index,false),
		true
	)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left",22)
	pad.add_theme_constant_override("margin_right",22)
	pad.add_theme_constant_override("margin_top",14)
	pad.add_theme_constant_override("margin_bottom",14)
	card.add_child(pad)
	var body := VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation",10)
	pad.add_child(body)
	# 原图是 1683×662 横幅：单独占满一行宽度，按比例尽量放大。
	var icon := TextureRect.new()
	icon.texture = load(ROLE_ICONS[role_index]) as Texture2D
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(0,280)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(icon)
	var meta := HBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_theme_constant_override("separation",16)
	body.add_child(meta)
	var names := VBoxContainer.new()
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation",2)
	meta.add_child(names)
	var title := UI.label(ROLE_NAMES[role_index],28,UI.TEXT)
	names.add_child(title)
	var blurb := UI.label(ROLE_BLURBS[role_index],16,UI.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(blurb)
	var status := UI.label("尚未认领 · 点击卡片认领",22,UI.MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(status)
	_claim_status.append(status)
	return card


func _on_claim_card_hover(role_index: int, hovered: bool) -> void:
	_claim_hover[role_index] = hovered
	_refresh_claim_ui()


func _on_claim_card_input(event: InputEvent, role_index: int) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and mouse.pressed:
			_handle_claim(role_index,_event_seat(mouse))


func _event_seat(event: InputEvent) -> int:
	# 席位 B 的合成事件带独立设备号；其余（席位 A 合成事件、单鼠标回退的真实事件）都算屏幕 A。
	return SEAT_B if event.device == Displays.SECONDARY_SEAT_POINTER_DEVICE else SEAT_A


func _handle_claim(role_index: int, seat: int) -> void:
	var current_owner := _role_claims[role_index]
	if current_owner == seat:
		_role_claims[role_index] = SEAT_NONE
		GameAudio.play_ui_choice()
		_claim_hint.text = "%s 已取消认领「%s」" % [_seat_name(seat),ROLE_NAMES[role_index]]
		ExperimentLog.log_event("role_unclaimed",_seat_actor(seat),{"role":ROLE_NAMES[role_index]})
	elif current_owner != SEAT_NONE:
		GameAudio.play_waypoint_denied()
		_claim_hint.text = "「%s」已由%s认领；如需更换，请由对方点击取消" % [ROLE_NAMES[role_index],_seat_name(current_owner)]
		_refresh_claim_ui()
		return
	else:
		for i: int in range(_role_claims.size()):
			if _role_claims[i] == seat:
				_role_claims[i] = SEAT_NONE
		_role_claims[role_index] = seat
		GameAudio.play_ui_choice()
		_claim_hint.text = "「%s」已由%s认领" % [ROLE_NAMES[role_index],_seat_name(seat)]
		ExperimentLog.log_event("role_claimed",_seat_actor(seat),{"role":ROLE_NAMES[role_index]})
	_refresh_claim_ui()


func _refresh_claim_ui() -> void:
	if _confirm_layer == null:
		return
	for i: int in range(_claim_cards.size()):
		var seat := _role_claims[i]
		var style: StyleBoxFlat
		if seat == SEAT_A:
			style = UI.box(Color("0c2733"),UI.CYAN,3)
		elif seat == SEAT_B:
			style = UI.box(Color("2b2113"),UI.AMBER,3)
		elif _claim_hover[i]:
			style = UI.box(UI.PANEL_2,Color("4a708e"),2)
		else:
			style = UI.box(UI.PANEL,Color("29435a"),2)
		_claim_cards[i].add_theme_stylebox_override("panel",style)
		var status := _claim_status[i]
		if seat == SEAT_NONE:
			status.text = "尚未认领 · 点击卡片认领"
			status.add_theme_color_override("font_color",UI.MUTED)
		else:
			status.text = "✓ 已由%s认领" % _seat_name(seat)
			status.add_theme_color_override("font_color",_seat_color(seat))
	var roles_ready := not _role_claims.has(SEAT_NONE)
	var keyboards_ready := not Game.experiment_mode or RawMice.connected_keyboard_count()>=2
	var ready := roles_ready and keyboards_ready
	_start_button.disabled = not ready
	_start_button.text = "开始任务" if ready else ("等待两把键盘" if roles_ready else "等待双方认领")
	if ready:
		_claim_hint.text = "屏幕 A（内置键盘）→ %s ｜ 屏幕 B（外接键盘）→ %s" % [_seat_role_name(SEAT_A),_seat_role_name(SEAT_B)]
		_claim_hint.add_theme_color_override("font_color",UI.TEXT)
	elif roles_ready and not keyboards_ready:
		_claim_hint.text = "实验模式需要：屏幕 A 的 Mac 内置键盘 + 屏幕 B 的一把外接键盘（当前 %d / 2）" % RawMice.connected_keyboard_count()
		_claim_hint.add_theme_color_override("font_color",UI.DANGER)
	else:
		_claim_hint.add_theme_color_override("font_color",UI.MUTED)


func _on_keyboard_device_changed(_seat: int,_connected: bool,_product: String) -> void:
	_refresh_claim_ui()


func _seat_name(seat: int) -> String:
	return "屏幕 A" if seat == SEAT_A else "屏幕 B"


func _seat_actor(seat: int) -> String:
	return "screen_a" if seat == SEAT_A else "screen_b"


func _seat_color(seat: int) -> Color:
	return UI.CYAN if seat == SEAT_A else UI.AMBER


func _seat_role_name(seat: int) -> String:
	for i: int in range(_role_claims.size()):
		if _role_claims[i] == seat:
			return ROLE_NAMES[i]
	return "—"


func _close_confirm() -> void:
	if _confirm_layer == null:
		return
	GameAudio.play_ui_popup_close()
	_confirm_layer.queue_free()
	_confirm_layer = null
	_claim_cards = []
	_claim_status = []
	_start_button = null
	_claim_hint = null


func _launch() -> void:
	if _selected == null or not Game.can_play_mission(_selected.id) or _role_claims.has(SEAT_NONE):
		return
	if Game.experiment_mode and RawMice.connected_keyboard_count()<2:
		return
	# 认领结果决定屏幕分配：领航员被屏幕 A 认领 → 主屏显示领航员画面，反之显示驾驶员。
	var primary_role: int = Displays.Role.NAVIGATOR if _role_claims[0] == SEAT_A else Displays.Role.PILOT
	Displays.set_primary_role(primary_role)
	Game.select_mission(_selected.id)
	ExperimentLog.log_event("mission_selected","system",{
		"mission":_selected.id,
		"screen_a_role":_seat_role_name(SEAT_A),
		"screen_b_role":_seat_role_name(SEAT_B),
	})
	get_tree().change_scene_to_file("res://scenes/main.tscn")
