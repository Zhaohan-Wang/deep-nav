class_name UiStyle
extends RefCounted
## 驾驶舱 / 星图共用的像素界面配色与控件工厂。

const BG: Color = Color("07080d")
const PANEL: Color = Color("12151c")
const PANEL_ALT: Color = Color("1a1f2b")
const BEZEL: Color = Color("0a0c12")
const CYAN: Color = Color("6be0d4")
const CYAN_DIM: Color = Color("2d6f6c")
const AMBER: Color = Color("e8a04a")
const DANGER: Color = Color("d45b6a")
const TEXT: Color = Color("c8d4dc")
const MUTED: Color = Color("6d7a86")
const VIEW_ASPECT: float = 16.0 / 9.0
const VIEW_FRAME_MARGIN: int = 6
const FONT_PATH: String = "res://assets/fonts/BoldPixels.ttf"
const FRAME_PATH: String = "res://assets/ui/frames/btn_frame.png"
const BAR_TRACK_PATH: String = "res://assets/ui/bars/bar_track.png"
const BAR_FILL_PATH: String = "res://assets/ui/bars/bar_fill.png"
const ICON_DIR: String = "res://assets/ui/icons/"

static var _hud_font: Font = null
static var _icon_cache: Dictionary[String, Texture2D] = {}


## 像素字为主，缺字形（中文）时走系统黑体。
static func hud_font() -> Font:
	if _hud_font != null:
		return _hud_font
	var pixel := load(FONT_PATH) as FontFile
	if pixel == null:
		return ThemeDB.fallback_font
	pixel.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var cjk := SystemFont.new()
	cjk.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans SC"])
	cjk.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	pixel.fallbacks = [cjk]
	_hud_font = pixel
	return _hud_font


## 像素字只在 8 的倍数上清晰。
static func pixel_font_size(requested: int) -> int:
	if requested <= 10:
		return 8
	if requested <= 18:
		return 16
	return 24


static func make_color_rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", hud_font())
	label.add_theme_font_size_override("font_size", pixel_font_size(font_size))
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func make_icon(icon_name: String, color: Color, px: float = 16.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = icon_texture(icon_name)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = color
	icon.custom_minimum_size = Vector2(px, px)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


static func icon_texture(icon_name: String) -> Texture2D:
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var tex := load(ICON_DIR + icon_name + ".png") as Texture2D
	_icon_cache[icon_name] = tex
	return tex


static func make_sketch_frame(color: Color = Color(CYAN.r, CYAN.g, CYAN.b, 0.72)) -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.texture = load(FRAME_PATH) as Texture2D
	frame.patch_margin_left = 24
	frame.patch_margin_top = 14
	frame.patch_margin_right = 24
	frame.patch_margin_bottom = 14
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_STRETCH
	frame.modulate = color
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return frame


## 不透明圆角面板：驾驶舱顶栏 / 状态条用。内容边距由样式内建。
static func make_round_panel(corner: int = 10) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, 1.0)
	style.set_corner_radius_all(corner)
	style.border_color = Color(CYAN_DIM.r, CYAN_DIM.g, CYAN_DIM.b, 1.0)
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


static func make_stat_bar(fill_color: Color) -> TextureProgressBar:
	var bar := TextureProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.01
	bar.nine_patch_stretch = true
	bar.texture_under = load(BAR_TRACK_PATH) as Texture2D
	bar.texture_progress = load(BAR_FILL_PATH) as Texture2D
	bar.tint_under = Color("1a1216")
	bar.tint_progress = fill_color
	bar.custom_minimum_size = Vector2(0.0, 14.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


static func make_header(title: String) -> Control:
	var bar := ColorRect.new()
	bar.color = PANEL
	bar.custom_minimum_size = Vector2(0.0, 36.0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = make_label(title, 16, CYAN)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 12.0
	bar.add_child(label)
	return bar


static func make_viewport_display(scanline: float) -> TextureRect:
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader: Shader = load("res://shaders/porthole.gdshader") as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("scanline_strength", scanline)
	mat.set_shader_parameter("vignette_strength", 1.15)
	mat.set_shader_parameter("noise_strength", 0.03)
	view.material = mat
	return view


## 左右两侧共用的 16:9 三维视窗，避免一边铺满竖屏、一边缩在小框里。
static func make_world_stage(content: Control, caption: String) -> AspectRatioContainer:
	var stage := AspectRatioContainer.new()
	stage.set_script(load("res://scripts/ui/world_stage.gd") as Script)
	stage.ratio = VIEW_ASPECT
	stage.stretch_mode = AspectRatioContainer.STRETCH_WIDTH_CONTROLS_HEIGHT
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var outer: ColorRect = make_color_rect(BEZEL)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", VIEW_FRAME_MARGIN)
	inner.add_theme_constant_override("margin_top", VIEW_FRAME_MARGIN)
	inner.add_theme_constant_override("margin_right", VIEW_FRAME_MARGIN)
	inner.add_theme_constant_override("margin_bottom", VIEW_FRAME_MARGIN)

	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(content)
	inner.add_child(clip)
	outer.add_child(inner)

	if not caption.is_empty():
		var label: Label = make_label(caption, 12, MUTED)
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.position = Vector2(12.0, 8.0)
		outer.add_child(label)

	stage.add_child(outer)
	return stage


## 把整页锁成 16:9 横版，在分栏里上下留空。
static func make_wide_page_frame(page: Control) -> Control:
	var slot := Control.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var letterbox: ColorRect = make_color_rect(BG)
	letterbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(letterbox)
	var frame := AspectRatioContainer.new()
	frame.ratio = VIEW_ASPECT
	frame.stretch_mode = AspectRatioContainer.STRETCH_FIT
	frame.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	frame.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if page.get_parent() != null:
		page.get_parent().remove_child(page)
	frame.add_child(page)
	slot.add_child(frame)
	return slot


## 填满父节点的带框视窗，外层页面比例由 16:9 页框负责。
static func make_framed_fill(content: Control, caption: String) -> Control:
	var outer := Control.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill: ColorRect = make_color_rect(Color(BEZEL.r, BEZEL.g, BEZEL.b, 0.92))
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_child(fill)
	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", VIEW_FRAME_MARGIN + 4)
	inner.add_theme_constant_override("margin_top", VIEW_FRAME_MARGIN + 4)
	inner.add_theme_constant_override("margin_right", VIEW_FRAME_MARGIN + 4)
	inner.add_theme_constant_override("margin_bottom", VIEW_FRAME_MARGIN + 4)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip.add_child(content)
	inner.add_child(clip)
	outer.add_child(inner)
	var frame: NinePatchRect = make_sketch_frame()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_child(frame)
	if not caption.is_empty():
		var label: Label = make_label(caption, 12, MUTED)
		label.set_anchors_preset(Control.PRESET_TOP_LEFT)
		label.position = Vector2(12.0, 8.0)
		outer.add_child(label)
	return outer


static func make_framed_slot(margin: int, caption_gap: int) -> ColorRect:
	var outer: ColorRect = make_color_rect(BEZEL)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner := MarginContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("margin_left", margin)
	inner.add_theme_constant_override("margin_top", margin + caption_gap)
	inner.add_theme_constant_override("margin_right", margin)
	inner.add_theme_constant_override("margin_bottom", margin)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(clip)
	outer.add_child(inner)
	outer.set_meta("content_slot", clip)
	return outer


static func framed_content(frame: Control) -> Control:
	return frame.get_meta("content_slot") as Control
