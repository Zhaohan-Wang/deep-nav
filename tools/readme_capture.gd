extends SceneTree
## 专门给 README 出图：认领页 16:9，以及领航员 / 驾驶员各一张整屏。

const OUT_CLAIM := "res://artifacts/runtime/role_claim_16x9.png"
const OUT_NAV := "res://artifacts/runtime/readme_navigator.png"
const OUT_PILOT := "res://artifacts/runtime/readme_pilot.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var game := root.get_node_or_null("Game")
	if game == null:
		push_error("README_CAPTURE_FAILED Game autoload missing")
		quit(1)
		return
	game.set("fullscreen_dual_display", false)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	for _i: int in range(4):
		await process_frame

	if not await _capture_role_claim(game):
		quit(1)
		return
	if not await _capture_role_views(game):
		quit(1)
		return
	print("README_CAPTURE_OK claim=%s navigator=%s pilot=%s" % [OUT_CLAIM, OUT_NAV, OUT_PILOT])
	quit(0)


func _capture_role_claim(game: Node) -> bool:
	game.set("experiment_mode", false)
	game.set("debug_mode", false)
	var page := (load("res://scenes/level_select.tscn") as PackedScene).instantiate()
	root.add_child(page)
	for _i: int in range(10):
		await process_frame
	page.call("_open_confirm")
	for _i: int in range(6):
		await process_frame
	var displays := root.get_node("/root/Displays")
	var cards: Array = page.get("_claim_cards")
	if cards.size() != 2:
		push_error("README_CAPTURE_FAILED claim cards missing")
		return false
	await _click(cards[0], displays.PRIMARY_SEAT_POINTER_DEVICE)
	await _click(cards[1], displays.SECONDARY_SEAT_POINTER_DEVICE)
	for _i: int in range(4):
		await process_frame
	await create_timer(0.2).timeout
	if not _save(OUT_CLAIM):
		return false
	page.queue_free()
	for _i: int in range(4):
		await process_frame
	return true


func _capture_role_views(game: Node) -> bool:
	game.call("select_mission", "level_1")
	var packed := load("res://scenes/main.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	for _i: int in range(12):
		await process_frame
	await create_timer(0.6).timeout
	var ship := scene.get_node_or_null("SpaceWorld/Ship") as Node3D
	if ship == null:
		push_error("README_CAPTURE_FAILED ship missing")
		return false
	ship.global_position = Vector3(-165.0, 0.0, 38.0)
	ship.rotation = Vector3.ZERO
	ship.set("linear_velocity", Vector3.ZERO)
	game.set("ship_position", ship.global_position)
	game.set("ship_heading", 0.0)
	game.call("set_waypoint", Vector3(-112.0, 0.0, -10.0))

	game.call("set_view_mode", Game.ViewMode.NAVIGATOR_ONLY)
	for _i: int in range(10):
		await process_frame
	await create_timer(0.35).timeout
	if not _save(OUT_NAV):
		return false

	game.call("set_view_mode", Game.ViewMode.PILOT_ONLY)
	for _i: int in range(10):
		await process_frame
	await create_timer(0.35).timeout
	return _save(OUT_PILOT)


func _click(card: Control, device: int) -> void:
	var pos := card.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.device = device
		event.position = pos
		event.global_position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _save(path: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("README_CAPTURE_FAILED empty image %s" % path)
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/runtime"))
	var error := image.save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("README_CAPTURE_FAILED save=%s error=%s" % [path, error])
		return false
	print("README_CAPTURE_SAVED %s %dx%d" % [path, image.get_width(), image.get_height()])
	return true
