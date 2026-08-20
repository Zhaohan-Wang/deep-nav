class_name Planet3D
extends Node3D
## 把 2D PixelPlanets 原样画进视口，再作为 3D 广告牌。材质与星图同一套。

const SphericalProjection = preload("res://scripts/world/spherical_billboard_projection.gd")

var data: CelestialBodyData
var _planet: Control
var _viewport: SubViewport
var _sprite: Sprite3D
var _physical_radius: float
var _anim_time: float = 1000.0
var _anim_accum: float = 0.0
const ANIM_FPS: float = 8.0


func setup(body: CelestialBodyData) -> void:
	data = body
	_physical_radius = body.world_radius
	name = body.id
	# 大行星贴在飞船航道水平面上，不抬高度，镜头才能正对看见。
	global_position = Vector3(body.world_position.x, 0.0, body.world_position.z)

	var pixels: int = clampi(int(round(body.world_radius * 4.2)), 100, 168)
	var margin: int = PlanetFactory.margin_for_path(body.scene_path)
	var vp_size: int = pixels * margin

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(vp_size, vp_size)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.handle_input_locally = false
	# 仍然使用 Sprite3D，但把 2D 行星低帧率烘到 SubViewport，
	# 保留云层/环带/黑洞盘的动态外观，同时避免每帧都重绘。
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.gui_disable_input = true
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_viewport)

	_planet = PlanetFactory.instantiate_planet(body.scene_path, pixels, body.seed_value, false)
	# 行星内部自己不自动跑时钟，改由这里低频推进并按需重绘。
	_planet.set("override_time", true)
	if _planet.has_method("set_custom_time"):
		_planet.call("set_custom_time", _anim_time)
	_viewport.add_child(_planet)

	_sprite = Sprite3D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# 行星本体直径对齐 world_radius；光环 / 日冕画在视口多出来的边距里。
	_sprite.pixel_size = (body.world_radius * 2.0) / float(pixels)
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.08
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.centered = true
	add_child(_sprite)
	_update_spherical_projection()

	_build_collision(body)
	if body.visual == "star":
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.84, 0.55)
		light.light_energy = 2.4
		light.omni_range = body.world_radius * 18.0
		add_child(light)


func _process(delta: float) -> void:
	_update_spherical_projection()
	_tick_planet_animation(delta)


func _update_spherical_projection() -> void:
	if _sprite == null or _physical_radius <= 0.0:
		return
	# 飞船驾驶员的相机与飞船中心几乎重合。碰撞球保证正常游戏中 d > r；
	# 这里的最小正数只防止传送/重置同一帧产生除零，不参与正常视觉曲线。
	var center_distance := global_position.distance_to(Game.ship_position)
	var valid_distance := maxf(center_distance, _physical_radius + 0.001)
	var projection_scale := SphericalProjection.scale_factor(
		_physical_radius, valid_distance
	)
	_sprite.scale = Vector3.ONE * projection_scale


func apply_star_light(star_pos: Vector3) -> void:
	if _planet == null or not _planet.has_method("set_light"):
		return
	var light_uv: Vector2 = PlanetFactory.light_uv_from_star(global_position, star_pos)
	_planet.call("set_light", light_uv)
	# setup 后同一帧会设置恒星方向，确保最终光照状态至少渲染一帧。
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _tick_planet_animation(delta: float) -> void:
	if _planet == null or not _planet.has_method("set_custom_time"):
		return
	_anim_accum += delta
	var frame_step := 1.0 / ANIM_FPS
	if _anim_accum < frame_step:
		return
	_anim_time += _anim_accum * maxf(data.spin_speed, 0.02)
	_anim_accum = 0.0
	_planet.call("set_custom_time", _anim_time)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build_collision(body: CelestialBodyData) -> void:
	var static_body := StaticBody3D.new()
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	static_body.add_to_group("planet_body")
	var bounce_mat := PhysicsMaterial.new()
	bounce_mat.friction = 0.12
	bounce_mat.bounce = 0.18
	static_body.physics_material_override = bounce_mat
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = body.collision_radius
	col.shape = sphere
	static_body.add_child(col)
	# 和飞船同一高度，避免球体在航面上方/下方被错过。
	static_body.position = Vector3.ZERO
	add_child(static_body)
	if body.kind == CelestialBodyData.Kind.DESTINATION:
		_build_dock_zone(body)


func _build_dock_zone(body: CelestialBodyData) -> void:
	var dock := Area3D.new()
	dock.collision_layer = 0
	dock.collision_mask = 4
	dock.monitoring = true
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	var extra: float = 6.0
	if Game.current_sector != null:
		extra = Game.current_sector.dock_range
	sphere.radius = body.collision_radius + extra
	col.shape = sphere
	dock.add_child(col)
	dock.body_entered.connect(_on_dock_entered)
	add_child(dock)


func _on_dock_entered(body: Node3D) -> void:
	if body is Ship:
		Game.mark_destination_reached()
