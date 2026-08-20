class_name SectorMap
extends Control
## 领航员底部的 2D 全图：比例尺与 3D 碰撞半径对齐。

signal waypoint_requested(world_pos: Vector3)

var _bodies_layer: Control
var _ship_icon: Sprite2D
var _engine_icon: Sprite2D
var _map_rect: Rect2 = Rect2()
var _overlay: Control
var _belt_viewport: SubViewport
var _belt_sprite: Sprite2D
var _belt_world_rect: Rect2 = Rect2()
var _belt_bake_scale: float = 0.0
var _belt_bake_sector: String = ""
var _grid_material: ShaderMaterial
var _space_material: ShaderMaterial
var _focus_world: Vector3 = Vector3.ZERO
var _target_focus_world: Vector3 = Vector3.ZERO
## 自动全景截图专用；正常游戏始终关闭。
var fixed_focus_enabled: bool = false
var fixed_focus_world: Vector3 = Vector3.ZERO


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layers()
	Game.ship_state_changed.connect(_on_ship_state)
	Game.waypoint_changed.connect(_on_waypoint_changed)
	resized.connect(_relayout)
	set_process(true)
	_focus_world = fixed_focus_world if fixed_focus_enabled else _desired_focus(Game.ship_position)
	_target_focus_world = _focus_world
	_relayout()
	_on_ship_state(Game.ship_position, Game.ship_heading, Game.ship_speed, Game.throttle)
	_on_waypoint_changed(Game.waypoint, Game.has_waypoint)


func _process(delta: float) -> void:
	var follow: float = 1.0 - exp(-delta * 4.2)
	if _focus_world.distance_squared_to(_target_focus_world) > 0.001:
		_focus_world = _focus_world.lerp(_target_focus_world, follow)
		_position_world_items()


func _build_layers() -> void:
	# 不再拉伸一张固定星云图。程序背景读取世界坐标，星点、尘云与远景以不同视差跟随地图。
	var space := ColorRect.new()
	space.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_space_material = ShaderMaterial.new()
	_space_material.shader = load("res://shaders/pixel_space_map.gdshader") as Shader
	space.material = _space_material
	space.color = Color.WHITE
	add_child(space)

	var grid := ColorRect.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid_material = ShaderMaterial.new()
	_grid_material.shader = load("res://shaders/map_panel.gdshader") as Shader
	grid.material = _grid_material
	grid.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(grid)

	# 危险带是静态世界几何：整关一次烘焙成纹理，主星图每帧只提交一个 Sprite。
	# 飞船、航点、雷达、目标信标仍由动态覆盖层实时绘制。
	_belt_viewport = SubViewport.new()
	_belt_viewport.transparent_bg = true
	_belt_viewport.disable_3d = true
	_belt_viewport.handle_input_locally = false
	_belt_viewport.gui_disable_input = true
	_belt_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_belt_viewport)
	_belt_sprite = Sprite2D.new()
	_belt_sprite.name = "BakedBeltLayer"
	_belt_sprite.centered = false
	_belt_sprite.texture = _belt_viewport.get_texture()
	_belt_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_belt_sprite)

	_bodies_layer = Control.new()
	_bodies_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bodies_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bodies_layer)

	var overlay := Control.new()
	overlay.set_script(load("res://scripts/ui/sector_map_overlay.gd") as Script)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_overlay = overlay

	_spawn_planets()

	_engine_icon = Sprite2D.new()
	_engine_icon.name = "EngineIcon"
	_engine_icon.centered = true
	_engine_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_engine_icon.visible = false
	add_child(_engine_icon)

	_ship_icon = Sprite2D.new()
	_ship_icon.name = "ShipIcon"
	_ship_icon.texture = load("res://assets/ships/deep_nav_ship.png") as Texture2D
	_ship_icon.centered = true
	_ship_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_ship_icon)


func _spawn_planets() -> void:
	var star: CelestialBodyData = Game.find_star()
	for body: CelestialBodyData in Game.celestial_bodies:
		var pixels: int = body.map_pixels
		var margin: int = PlanetFactory.margin_for_path(body.scene_path)
		var host := Control.new()
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.custom_minimum_size = Vector2(pixels * margin, pixels * margin)
		host.size = host.custom_minimum_size
		var planet: Control = PlanetFactory.instantiate_planet(body.scene_path, pixels, body.seed_value)
		if star != null and planet.has_method("set_light"):
			planet.call("set_light", PlanetFactory.light_uv_from_star(body.world_position, star.world_position))
		host.add_child(planet)
		_bodies_layer.add_child(host)
		host.set_meta("body_id", body.id)
		host.set_meta("pixels", pixels)
		host.set_meta("margin", margin)


func _relayout() -> void:
	_map_rect = Rect2(Vector2.ZERO, size)
	var scale_px: float = Game.map_pixels_per_unit(_map_rect.size)
	_ensure_belt_bake(scale_px)
	_fit_ship_icon(scale_px)
	_update_grid(scale_px)
	_position_world_items()


func _position_world_items() -> void:
	var scale_px: float = Game.map_pixels_per_unit(_map_rect.size)
	_position_belt_texture(scale_px)
	for host: Node in _bodies_layer.get_children():
		if not (host is Control):
			continue
		var ctrl := host as Control
		if not ctrl.has_meta("body_id"):
			continue
		var id: String = str(ctrl.get_meta("body_id"))
		var data: CelestialBodyData = Game.find_body(id)
		if data == null:
			continue
		var pixels: int = int(ctrl.get_meta("pixels"))
		# 行星圆盘直径 = 2 * world_radius * 每单位像素，和 3D 碰撞球一致。
		var disc_px: float = data.world_radius * 2.0 * scale_px
		var zoom: float = disc_px / maxf(float(pixels), 1.0)
		ctrl.scale = Vector2(zoom, zoom)
		var pos: Vector2 = world_to_map(data.world_position)
		var drawn: Vector2 = ctrl.size * ctrl.scale
		ctrl.position = pos - drawn * 0.5
	var ship_pos := world_to_map(Game.ship_position)
	_ship_icon.position = ship_pos
	_engine_icon.position = ship_pos
	if _overlay != null:
		_overlay.queue_redraw()
	_update_grid(scale_px)


func _ensure_belt_bake(display_scale: float) -> void:
	if (_belt_viewport==null or _belt_sprite==null or Game.current_sector==null
			or size.x<1.0 or size.y<1.0 or display_scale<=0.0):
		return
	var sector_id:=Game.current_sector.id
	if _belt_bake_sector==sector_id and absf(_belt_bake_scale-display_scale)<0.001:
		return
	_belt_bake_sector=sector_id
	_belt_world_rect=_belt_bounds()
	var world_size:=_belt_world_rect.size
	var bake_scale:=display_scale
	var longest_px:=maxf(world_size.x,world_size.y)*bake_scale
	if longest_px>4096.0:
		bake_scale*=4096.0/longest_px
	_belt_bake_scale=bake_scale
	var bake_size:=Vector2i(
		maxi(1,int(ceil(world_size.x*bake_scale))),
		maxi(1,int(ceil(world_size.y*bake_scale)))
	)
	_belt_viewport.size=bake_size
	for child: Node in _belt_viewport.get_children():
		_belt_viewport.remove_child(child)
		child.queue_free()
	var bake:=Control.new()
	bake.name="StaticBeltBake"
	bake.set_script(load("res://scripts/ui/sector_map_overlay.gd") as Script)
	bake.set("static_belt_bake",true)
	bake.set("bake_world_rect",_belt_world_rect)
	bake.set("bake_scale_px",bake_scale)
	bake.size=Vector2(bake_size)
	bake.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_belt_viewport.add_child(bake)
	_belt_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
	_belt_sprite.texture=_belt_viewport.get_texture()
	_position_belt_texture(display_scale)


func _belt_bounds() -> Rect2:
	for belt: BeltData in Game.current_sector.belts:
		if not belt.is_boundary:
			continue
		var half:=Vector2(belt.outer_radius*maxf(belt.aspect,0.01),belt.outer_radius)+Vector2.ONE*8.0
		return Rect2(Vector2(belt.center.x,belt.center.z)-half,half*2.0)
	var half:=Vector2.ONE*(Game.current_sector.world_half+8.0)
	return Rect2(-half,half*2.0)


func _position_belt_texture(display_scale: float) -> void:
	if _belt_sprite==null or _belt_bake_scale<=0.0:
		return
	_belt_sprite.scale=Vector2.ONE*(display_scale/_belt_bake_scale)
	_belt_sprite.position=world_to_map(Vector3(_belt_world_rect.position.x,0.0,_belt_world_rect.position.y))


func _update_grid(scale_px: float) -> void:
	if _grid_material == null or size.x < 1.0 or size.y < 1.0:
		return
	var world_step: float = 10.0
	var grid_px: float = scale_px * world_step
	# 小窗里不让网格过密，但每格仍是真实的整数世界距离。
	if grid_px < 34.0:
		world_step = 20.0
		grid_px = scale_px * world_step
	var world_origin := _map_rect.get_center() - Vector2(_focus_world.x, _focus_world.z) * scale_px
	_grid_material.set_shader_parameter("canvas_size", size)
	_grid_material.set_shader_parameter("grid_size_px", grid_px)
	_grid_material.set_shader_parameter("grid_origin_px", world_origin)
	if _space_material != null:
		_space_material.set_shader_parameter("canvas_size", size)
		_space_material.set_shader_parameter("focus_world", Vector2(_focus_world.x, _focus_world.z))
		_space_material.set_shader_parameter("pixels_per_unit", scale_px)
		_space_material.set_shader_parameter("pixel_block", 3.0 if size.y >= 650.0 else 2.0)


func _fit_ship_icon(_scale_px: float) -> void:
	# 星图飞船是领航符号，不能按 1.2 世界单位去缩，否则会变成一条线。
	if _ship_icon.texture == null:
		return
	var tex_extent: float = maxf(float(_ship_icon.texture.get_width()),float(_ship_icon.texture.get_height()))
	# 新船主体在透明画布中的占比很高；30px 足够辨认，又不会盖住雷达环和附近天体。
	var ship_px: float = 30.0
	var zoom: float = ship_px/maxf(tex_extent,1.0)
	_ship_icon.scale = Vector2(zoom, zoom)


func world_to_map(world: Vector3) -> Vector2:
	return Game.world_to_map(world, _map_rect, _focus_world)


func map_to_world(map_pos: Vector2) -> Vector3:
	return Game.map_to_world(map_pos, _map_rect, _focus_world)


func pixels_per_unit() -> float:
	return Game.map_pixels_per_unit(_map_rect.size)


func _desired_focus(ship_pos: Vector3) -> Vector3:
	var dest := Game.objective_body()
	if dest == null or Game.current_sector == null:
		return ship_pos
	var ahead := dest.world_position - ship_pos
	ahead.y = 0.0
	if ahead.length_squared() > 0.001:
		ahead = ahead.normalized() * Game.current_sector.map_view_half * 0.24
	return ship_pos + ahead


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			# 双鼠标合成事件必须来自当前领航员席位；驾驶员空白点击不允许串到星图链路。
			if not Displays.pointer_device_matches_role(mouse.device, Displays.Role.NAVIGATOR):
				accept_event()
				return
			waypoint_requested.emit(map_to_world(mouse.position))
			accept_event()


func _on_ship_state(position: Vector3, heading: float, _speed: float, throttle: float) -> void:
	_target_focus_world = fixed_focus_world if fixed_focus_enabled else _desired_focus(position)
	var pos: Vector2 = world_to_map(position)
	_ship_icon.position = pos
	_engine_icon.position = pos
	# 3D 航向 0 朝向 -Z（地图上方），2D 正旋转为顺时针，所以取反。
	_ship_icon.rotation = -heading
	_engine_icon.rotation = -heading
	# 旧 Scout 的发动机序列与新船轮廓不一致，先禁用，避免推进时闪回旧飞船。
	_engine_icon.visible = false
	if _overlay != null:
		_overlay.queue_redraw()


func _on_waypoint_changed(_world_pos: Vector3, _enabled: bool) -> void:
	# 航点标记由覆盖层绘制（旋转准星），这里只触发重绘。
	if _overlay != null:
		_overlay.queue_redraw()
