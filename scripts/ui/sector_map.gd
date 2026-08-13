class_name SectorMap
extends Control
## 领航员底部的 2D 全图：比例尺与 3D 碰撞半径对齐。

signal waypoint_requested(world_pos: Vector3)

var _bodies_layer: Control
var _ship_icon: Sprite2D
var _engine_icon: Sprite2D
var _map_rect: Rect2 = Rect2()
var _overlay: Control


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_layers()
	Game.ship_state_changed.connect(_on_ship_state)
	Game.waypoint_changed.connect(_on_waypoint_changed)
	resized.connect(_relayout)
	_relayout()
	_on_ship_state(Game.ship_position, Game.ship_heading, Game.ship_speed, Game.throttle)
	_on_waypoint_changed(Game.waypoint, Game.has_waypoint)


func _build_layers() -> void:
	var back := TextureRect.new()
	back.texture = load("res://assets/backgrounds/blue-back.png") as Texture2D
	back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	back.stretch_mode = TextureRect.STRETCH_SCALE
	back.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 压暗底图，星云不能抢过图上的行星和标记。
	back.modulate = Color(0.50, 0.52, 0.60)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)

	var stars := TextureRect.new()
	stars.texture = load("res://assets/backgrounds/blue-stars.png") as Texture2D
	stars.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stars.stretch_mode = TextureRect.STRETCH_SCALE
	stars.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stars.modulate = Color(1.0, 1.0, 1.0, 0.45)
	stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(stars)

	var grid := ColorRect.new()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grid_mat := ShaderMaterial.new()
	grid_mat.shader = load("res://shaders/map_panel.gdshader") as Shader
	grid.material = grid_mat
	grid.color = Color(1.0, 1.0, 1.0, 1.0)
	add_child(grid)

	_bodies_layer = Control.new()
	_bodies_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bodies_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bodies_layer)
	_spawn_planets()

	var overlay := Control.new()
	overlay.set_script(load("res://scripts/ui/sector_map_overlay.gd") as Script)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	_overlay = overlay

	_engine_icon = Sprite2D.new()
	_engine_icon.texture = load("res://assets/ships/engine/Scout.png") as Texture2D
	_engine_icon.hframes = 10
	_engine_icon.centered = true
	_engine_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_engine_icon.visible = false
	add_child(_engine_icon)

	_ship_icon = Sprite2D.new()
	_ship_icon.texture = load("res://assets/ships/base/Scout.png") as Texture2D
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
	_fit_ship_icon(scale_px)
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
	if _overlay != null:
		_overlay.queue_redraw()


func _fit_ship_icon(_scale_px: float) -> void:
	# 星图飞船是领航符号，不能按 1.2 世界单位去缩，否则会变成一条线。
	if _ship_icon.texture == null:
		return
	var tex_w: float = float(_ship_icon.texture.get_width())
	var ship_px: float = 42.0
	var zoom: float = ship_px / maxf(tex_w, 1.0)
	_ship_icon.scale = Vector2(zoom, zoom)
	if _engine_icon.texture != null:
		var frame_w: float = float(_engine_icon.texture.get_width()) / maxf(float(_engine_icon.hframes), 1.0)
		var engine_zoom: float = ship_px / maxf(frame_w, 1.0)
		_engine_icon.scale = Vector2(engine_zoom, engine_zoom)


func world_to_map(world: Vector3) -> Vector2:
	return Game.world_to_map(world, _map_rect)


func map_to_world(map_pos: Vector2) -> Vector3:
	return Game.map_to_world(map_pos, _map_rect)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			waypoint_requested.emit(map_to_world(mouse.position))
			accept_event()


func _on_ship_state(position: Vector3, heading: float, _speed: float, throttle: float) -> void:
	var pos: Vector2 = world_to_map(position)
	_ship_icon.position = pos
	_engine_icon.position = pos
	# 3D 航向 0 朝向 -Z（地图上方），2D 正旋转为顺时针，所以取反。
	_ship_icon.rotation = -heading
	_engine_icon.rotation = -heading
	var thrusting: bool = throttle > 0.12
	_engine_icon.visible = thrusting
	if thrusting:
		_engine_icon.frame = int(Time.get_ticks_msec() / 80) % 10
	if _overlay != null:
		_overlay.queue_redraw()


func _on_waypoint_changed(_world_pos: Vector3, _enabled: bool) -> void:
	# 航点标记由覆盖层绘制（旋转准星），这里只触发重绘。
	if _overlay != null:
		_overlay.queue_redraw()
