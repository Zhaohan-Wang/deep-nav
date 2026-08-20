class_name ExperimentReviewPanel
extends Control
## 问卷提交后的实验员复核页；复核前不推进关卡序列。

signal retry_confirmed


func setup(role: String,reason: String) -> void:
	name = "ExperimentReview_%s" % role
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 1010
	var dim := ColorRect.new()
	dim.color = Color(0.004,0.012,0.03,0.98)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_left = 48
	center.offset_right = -48
	center.offset_top = 36
	center.offset_bottom = -36
	add_child(center)
	var card := AppStyle.panel()
	card.custom_minimum_size = Vector2(690,360)
	center.add_child(card)
	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation",18)
	card.add_child(content)
	var title := AppStyle.label("需要实验员复核",30,AppStyle.AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var body := AppStyle.label(reason,18,AppStyle.TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(body)
	var note := AppStyle.label("本次作答已经单独保存，但本关不会计为完成，也不会推进到下一关。",15,AppStyle.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	var retry := AppStyle.button("实验员确认说明完毕 · 重试本关",Vector2(460,58),true)
	retry.name = "ExperimenterRetry"
	retry.pressed.connect(func():
		retry.disabled = true
		retry_confirmed.emit()
	)
	content.add_child(retry)
