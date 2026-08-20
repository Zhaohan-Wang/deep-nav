class_name MissionResultPanel
extends Control
## 先明确结果，再展示飞行总结；之后才由 Main 换成独立量表。

const SUCCESS_ART: Texture2D = preload("res://assets/ui/results/mission_success.jpg")
const FAILURE_ART: Texture2D = preload("res://assets/ui/results/mission_failure.jpg")

var _card: PanelContainer
var _content: VBoxContainer


func setup(role: String) -> void:
	name = "MissionResult_%s" % role
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 850
	var dim := ColorRect.new()
	dim.color = Color(0.004,0.012,0.03,0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 28
	center.offset_right = -28
	center.offset_top = 22
	center.offset_bottom = -22
	add_child(center)
	_card = AppStyle.panel()
	_card.name = "MissionResultCard"
	_card.custom_minimum_size = Vector2(650,330)
	center.add_child(_card)
	_content = VBoxContainer.new()
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation",14)
	_card.add_child(_content)


func show_result(outcome: String,success: bool) -> void:
	_clear_content()
	_card.custom_minimum_size = Vector2(820,480)
	var artwork := Control.new()
	artwork.custom_minimum_size = Vector2(0,420)
	artwork.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	artwork.size_flags_vertical = Control.SIZE_EXPAND_FILL
	artwork.clip_contents = true
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(artwork)

	var image := TextureRect.new()
	image.texture = SUCCESS_ART if success else FAILURE_ART
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.add_child(image)

	# 图片承担结果叙事，仅在底部留一个强识别的大标题。
	var title_back := ColorRect.new()
	title_back.color = Color(0.004,0.012,0.03,0.82)
	title_back.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	title_back.offset_top = -76
	title_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	artwork.add_child(title_back)
	var title := AppStyle.label("任务成功" if success else "任务失败",42,AppStyle.CYAN if success else AppStyle.DANGER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_back.add_child(title)


func show_summary(summary: Dictionary) -> void:
	_clear_content()
	_card.custom_minimum_size = Vector2(720,390)
	var title := AppStyle.label("本次飞行总结",28,AppStyle.CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_child(grid)
	_add_stat(grid,"任务结果",str(summary.get("outcome","—")),AppStyle.CYAN if bool(summary.get("success",false)) else AppStyle.DANGER)
	var time_text := "不计时" if not bool(summary.get("timed",true)) else "%.0f / %.0f 秒" % [summary.get("elapsed",0.0),summary.get("limit",0.0)]
	_add_stat(grid,"飞行用时",time_text,AppStyle.AMBER)
	_add_stat(grid,"复活次数","%d 次" % summary.get("revivals",0),AppStyle.TEXT)
	_add_stat(grid,"受击次数","%d 次" % summary.get("hits",0),AppStyle.TEXT)
	_add_stat(grid,"设置航点","%d 次" % summary.get("waypoints",0),AppStyle.TEXT)
	_add_stat(grid,"剩余船体","%d%%" % int(round(float(summary.get("hull",0.0)))),AppStyle.AMBER)
	var next := AppStyle.label("请回顾这次飞行。接下来，两位玩家将分别回答几个简短问题。",16,AppStyle.MUTED)
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(next)


func _add_stat(grid: GridContainer,label_text: String,value_text: String,color: Color) -> void:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(205,76)
	cell.add_theme_constant_override("separation",3)
	var label := AppStyle.label(label_text,15,AppStyle.MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)
	var value := AppStyle.label(value_text,20,color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(value)
	grid.add_child(cell)


func _clear_content() -> void:
	for child: Node in _content.get_children():
		child.free()
