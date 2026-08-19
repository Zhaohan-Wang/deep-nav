extends Control

const UI = preload("res://scripts/ui/app_style.gd")
const ART_PATH := "res://assets/ui/results/thank_you.jpg"


func _ready() -> void:
	Displays.show_shared_page()
	add_child(UI.page())

	# 所有视觉元素作为一组居中，避免标题、配图和按钮被剩余空间拉散。
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.custom_minimum_size = Vector2(1320,0)
	content.add_theme_constant_override("separation",10)
	center.add_child(content)

	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation",-4)
	content.add_child(heading)
	var title := UI.label("感谢游玩",54,UI.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_child(title)
	var subtitle := UI.label("DEEP NAV  /  航行记录已完成",18,UI.CYAN)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_child(subtitle)

	# 沿用任务进度首图的内嵌凹槽；图片保持完整，不再做像素溶解。
	var art_stage := Control.new()
	art_stage.custom_minimum_size = Vector2(1320,737)
	art_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(art_stage)
	var recess := ColorRect.new()
	recess.color = Color("030812")
	recess.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	recess.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_stage.add_child(recess)
	var frame := Control.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 8
	frame.offset_top = 8
	frame.offset_right = -8
	frame.offset_bottom = -8
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_stage.add_child(frame)

	var art := TextureRect.new()
	art.name = "ThankYouArtwork"
	art.texture = load(ART_PATH) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(art)

	# 上/左内阴影与下/右冷色反光和任务进度页保持同一视觉语言。
	var inner_top := ColorRect.new()
	inner_top.color = Color(0,0,0,0.40)
	inner_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	inner_top.offset_bottom = 12
	inner_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inner_top)
	var inner_left := ColorRect.new()
	inner_left.color = Color(0,0,0,0.36)
	inner_left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	inner_left.offset_right = 12
	inner_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inner_left)
	var inner_bottom := ColorRect.new()
	inner_bottom.color = Color(UI.CYAN,0.20)
	inner_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	inner_bottom.offset_top = -2
	inner_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inner_bottom)
	var inner_right := ColorRect.new()
	inner_right.color = Color(UI.CYAN,0.16)
	inner_right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	inner_right.offset_left = -2
	inner_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(inner_right)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation",14)
	content.add_child(actions)
	var back := UI.button("返回标题",Vector2(280,62),true)
	back.name = "ReturnToTitleButton"
	back.pressed.connect(_return_to_title)
	actions.add_child(back)
	var quit := UI.button("退出",Vector2(200,62))
	quit.name = "QuitButton"
	quit.pressed.connect(func() -> void: get_tree().quit())
	actions.add_child(quit)
	back.grab_focus.call_deferred()


func _return_to_title() -> void:
	get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
