class_name AppStyle
extends RefCounted
## DeepNav 菜单构件：干净深空底、像素边框、清晰正文。

const BG := Color("050914")
const PANEL := Color("0b1524")
const PANEL_2 := Color("101f31")
const CYAN := Color("58e1dc")
const AMBER := Color("f0b35a")
const TEXT := Color("e8f2f5")
const MUTED := Color("8295a3")
const DANGER := Color("ef6673")
const FONT_CJK: FontFile = preload("res://assets/fonts/ipix_12px.ttf")
const FONT_BODY: FontFile = preload("res://assets/fonts/atkinson_mono.ttf")


static func page() -> Control:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG; bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE; root.add_child(bg)
	var grid := Control.new(); grid.set_script(preload("res://scripts/ui/menu_grid.gd"))
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grid)
	return root


static func label(text: String, size: int = 24, color: Color = TEXT) -> Label:
	var out := Label.new(); out.text = text
	out.add_theme_font_override("font", FONT_CJK); out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color); return out


static func button(text: String, min_size := Vector2(320, 72), accent: bool = false) -> Button:
	var out := Button.new(); out.text = text; out.custom_minimum_size = min_size
	out.add_theme_font_override("font", FONT_CJK); out.add_theme_font_size_override("font_size", 23)
	out.add_theme_color_override("font_color", BG if accent else TEXT)
	out.add_theme_color_override("font_hover_color", BG)
	out.add_theme_stylebox_override("normal", box(AMBER if accent else PANEL_2, CYAN if accent else Color("29435a"), 2))
	out.add_theme_stylebox_override("hover", box(CYAN, CYAN, 2))
	out.add_theme_stylebox_override("pressed", box(AMBER, TEXT, 3))
	out.add_theme_stylebox_override("focus", box(Color("162c40"), CYAN, 3))
	return out


static func panel() -> PanelContainer:
	var out := PanelContainer.new(); out.add_theme_stylebox_override("panel", box(PANEL, Color("29435a"), 2)); return out


static func box(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var out := StyleBoxFlat.new(); out.bg_color = fill; out.border_color = border
	out.set_border_width_all(width); out.set_corner_radius_all(4)
	out.content_margin_left = 24; out.content_margin_right = 24
	out.content_margin_top = 16; out.content_margin_bottom = 16; return out


static func style_slider(slider: Slider) -> void:
	slider.custom_minimum_size = Vector2(360, 52)
	var track := StyleBoxFlat.new(); track.bg_color = Color("22384a"); track.set_corner_radius_all(0)
	track.content_margin_top = 7; track.content_margin_bottom = 7
	var fill := track.duplicate() as StyleBoxFlat; fill.bg_color = CYAN
	slider.add_theme_stylebox_override("slider", track); slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_icon_override("grabber", _pixel_circle(26, AMBER, TEXT))
	slider.add_theme_icon_override("grabber_highlight", _pixel_circle(30, CYAN, TEXT))


## 像素风圆形滑钮：低分辨率光栅化圆，再最近邻放大一倍，保留锯齿台阶感。
static func _pixel_circle(diameter: int, fill: Color, border: Color) -> Texture2D:
	var base := maxi(diameter / 2, 5)
	var image := Image.create(base, base, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var center := (base - 1) * 0.5
	var radius := base * 0.5 - 0.5
	for y: int in range(base):
		for x: int in range(base):
			var distance := Vector2(x - center, y - center).length()
			if distance <= radius - 1.1:
				image.set_pixel(x, y, fill)
			elif distance <= radius:
				image.set_pixel(x, y, border)
	image.resize(base * 2, base * 2, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(image)
