class_name TutorialOverlay
extends Control
## 训练关角色教程。全屏图片只负责绘制，除翻页按钮外的区域全部穿透鼠标。

signal finished(role: String)

const NAVIGATOR_PAGES := 7
const PILOT_PAGES := 8
const OVERLAY_Z_INDEX := 700

var role := ""
var page_paths := PackedStringArray()
var page_index := 0
var _image: TextureRect
var _previous_button: Button
var _next_button: Button
var _page_label: Label


func setup(role_name: String) -> void:
	role = role_name
	name = "TutorialOverlay_%s" % role
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = OVERLAY_Z_INDEX
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	page_paths = _paths_for_role(role)
	_build()
	_show_page(0)


func _paths_for_role(role_name: String) -> PackedStringArray:
	var count := NAVIGATOR_PAGES if role_name == "navigator" else PILOT_PAGES
	var folder := "navigator" if role_name == "navigator" else "pilot"
	var paths := PackedStringArray()
	for index: int in range(1, count + 1):
		paths.append("res://assets/tutorial/%s/%02d.png" % [folder, index])
	return paths


func _build() -> void:
	_image = TextureRect.new()
	_image.name = "TutorialImage"
	# 教程图按 1920×1080 制作，必须完整覆盖当前席位屏幕；缩进会露出底层画面，
	# 在不同显示器比例下尤其明显。
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)

	# 放在右上角，避开领航员星图的主要点击区域。只有两个按钮本身截获鼠标。
	var margin := MarginContainer.new()
	margin.name = "TutorialNavigation"
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin.offset_left = -418.0
	margin.offset_top = 18.0
	margin.offset_right = -18.0
	margin.offset_bottom = 82.0
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var panel := AppStyle.panel()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	_previous_button = AppStyle.button("上一页", Vector2(112, 44), false)
	_previous_button.name = "PreviousPage"
	_previous_button.add_theme_font_size_override("font_size", 18)
	_previous_button.pressed.connect(_show_previous)
	row.add_child(_previous_button)

	_page_label = AppStyle.label("", 16, AppStyle.MUTED)
	_page_label.name = "PageNumber"
	_page_label.custom_minimum_size = Vector2(54, 0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_page_label)

	_next_button = AppStyle.button("下一页", Vector2(112, 44), true)
	_next_button.name = "NextPage"
	_next_button.add_theme_font_size_override("font_size", 18)
	_next_button.pressed.connect(_show_next_or_finish)
	row.add_child(_next_button)


func _show_page(index: int) -> void:
	if page_paths.is_empty():
		return
	page_index = clampi(index, 0, page_paths.size() - 1)
	_image.texture = load(page_paths[page_index]) as Texture2D
	_previous_button.disabled = page_index == 0
	_next_button.text = "完成" if page_index == page_paths.size() - 1 else "下一页"
	_page_label.text = "%d / %d" % [page_index + 1, page_paths.size()]


func _show_previous() -> void:
	if page_index > 0:
		_show_page(page_index - 1)


func _show_next_or_finish() -> void:
	if page_index < page_paths.size() - 1:
		_show_page(page_index + 1)
		return
	_image.texture = null
	visible = false
	finished.emit(role)
