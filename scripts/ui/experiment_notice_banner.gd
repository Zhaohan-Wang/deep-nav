class_name ExperimentNoticeBanner
extends MarginContainer
## 两个角色共用的非阻塞实验提示：位置、尺寸、时长和视觉层级完全一致。

var _serial := 0
var _message: Label


func _ready() -> void:
	name = "ExperimentNoticeBanner"
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.075
	anchor_bottom = 0.075
	offset_left = -260.0
	offset_right = 260.0
	offset_bottom = 92.0
	z_index = 56
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_panel_style())
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	panel.add_child(row)
	var icon := UiStyle.make_icon("signal",UiStyle.AMBER,24.0)
	icon.custom_minimum_size = Vector2(30,30)
	row.add_child(icon)
	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation",2)
	row.add_child(text_col)
	var title := UiStyle.make_label("航行系统提示",13,UiStyle.AMBER)
	text_col.add_child(title)
	_message = UiStyle.make_label("",18,UiStyle.TEXT)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_child(_message)


func show_message(message: String,duration_s: float = 3.0) -> void:
	_serial += 1
	var serial := _serial
	# 按实际文案宽度收束；两种条件可以不同宽，但始终在同一位置居中。
	var text_width := UiStyle.hud_font().get_string_size(message,HORIZONTAL_ALIGNMENT_LEFT,-1.0,18).x
	var banner_width := clampf(text_width+88.0,360.0,590.0)
	offset_left = -banner_width*0.5
	offset_right = banner_width*0.5
	_message.text = message
	visible = true
	modulate = Color.WHITE
	await get_tree().create_timer(duration_s).timeout
	if serial == _serial and is_instance_valid(self):
		visible = false


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018,0.055,0.085,0.97)
	style.border_color = Color(UiStyle.AMBER,0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0,0,0,0.55)
	style.shadow_size = 10
	return style
