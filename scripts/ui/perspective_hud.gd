class_name PerspectiveHud
extends Control
## 把一块 HUD 画成垫在台面上的后仰梯形；点击会映射回原始平面。

var pitch: float = 0.88
var top_scale: float = 0.90

var _viewport: SubViewport
var _content: Control
var _mat: ShaderMaterial


func setup(content: Control) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_content = content

	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.handle_input_locally = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)
	if content.get_parent() != null:
		content.get_parent().remove_child(content)
	_viewport.add_child(content)

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/hud_perspective.gdshader") as Shader
	_mat.set_shader_parameter("pitch", pitch)
	_mat.set_shader_parameter("top_scale", top_scale)

	var surface := ColorRect.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.color = Color.WHITE
	surface.material = _mat
	add_child(surface)
	call_deferred("_bind_texture")


func set_content_size(content_size: Vector2) -> void:
	if _viewport == null:
		return
	var px := Vector2i(maxi(2, int(round(content_size.x))), maxi(2, int(round(content_size.y))))
	if _viewport.size != px:
		_viewport.size = px
	if _content != null:
		_content.position = Vector2.ZERO
		_content.size = Vector2(px)
	if _mat != null:
		_mat.set_shader_parameter("pitch", pitch)
		_mat.set_shader_parameter("top_scale", top_scale)
	_bind_texture()


func set_pose(pitch_value: float, top_value: float) -> void:
	pitch = pitch_value
	top_scale = top_value
	if _mat != null:
		_mat.set_shader_parameter("pitch", pitch)
		_mat.set_shader_parameter("top_scale", top_scale)


func _bind_texture() -> void:
	if _viewport == null or _mat == null:
		return
	_mat.set_shader_parameter("view_tex", _viewport.get_texture())


func _has_point(point: Vector2) -> bool:
	if modulate.a < 0.2 or not visible:
		return false
	return _hit_uv(point).x >= 0.0


func _gui_input(event: InputEvent) -> void:
	if _viewport == null or not visible or modulate.a < 0.2:
		return
	if not (event is InputEventMouse):
		return
	var mouse := event as InputEventMouse
	var uv: Vector2 = _hit_uv(mouse.position)
	if uv.x < 0.0:
		return
	var copy := event.duplicate() as InputEventMouse
	copy.position = Vector2(_viewport.size) * uv
	copy.global_position = copy.position
	_viewport.push_input(copy, true)
	accept_event()


func _hit_uv(point: Vector2) -> Vector2:
	if size.y < 2.0 or size.x < 2.0:
		return Vector2(-1.0, -1.0)
	var y0: float = size.y * (1.0 - pitch)
	if point.y < y0 or point.y > size.y:
		return Vector2(-1.0, -1.0)
	var t: float = (point.y - y0) / maxf(size.y * pitch, 0.001)
	var scale: float = lerpf(top_scale, 1.0, t)
	var x: float = (point.x / size.x - 0.5) / maxf(scale, 0.001) + 0.5
	if x < 0.0 or x > 1.0:
		return Vector2(-1.0, -1.0)
	return Vector2(x, t)
