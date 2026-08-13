class_name PixelBody
extends Node3D
## 把 2D 像素行星画进 SubViewport，再作为面向相机的 Sprite3D 放到 3D 世界里。

var data: CelestialBodyData

var _planet: Control
var _viewport: SubViewport
var _sprite: Sprite3D


func setup(body: CelestialBodyData) -> void:
	data = body
	name = body.id
	global_position = body.world_position

	var margin: int = PlanetFactory.margin_for_path(body.scene_path)
	var vp_size: int = body.map_pixels * margin

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(vp_size, vp_size)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.handle_input_locally = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.gui_disable_input = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)

	_planet = PlanetFactory.instantiate_planet(body.scene_path, body.map_pixels, body.seed_value)
	_viewport.add_child(_planet)

	_sprite = Sprite3D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.pixel_size = (body.world_radius * 2.0) / float(vp_size)
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.08
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.centered = true
	_sprite.no_depth_test = false
	add_child(_sprite)

	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitoring = false
	area.monitorable = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = body.collision_radius
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)

	if body.kind != CelestialBodyData.Kind.HAZARD and body.kind != CelestialBodyData.Kind.STAR:
		var static_body := StaticBody3D.new()
		static_body.collision_layer = 1
		static_body.collision_mask = 0
		var body_shape := CollisionShape3D.new()
		var body_sphere := SphereShape3D.new()
		body_sphere.radius = body.collision_radius
		body_shape.shape = body_sphere
		static_body.add_child(body_shape)
		add_child(static_body)


func apply_star_light(star_pos: Vector3) -> void:
	if _planet == null or not _planet.has_method("set_light"):
		return
	var to_star: Vector3 = star_pos - global_position
	to_star.y = 0.0
	if to_star.length_squared() < 0.001:
		return
	var dir: Vector3 = to_star.normalized()
	var light_uv := Vector2(0.5 - dir.x * 0.32, 0.5 - dir.z * 0.32)
	_planet.call("set_light", light_uv)
