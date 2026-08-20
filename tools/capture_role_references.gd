extends SceneTree
## 为新手指引制作的干净底图：两个席位分别导出标准 1920×1080 PNG。

const OUTPUT_SIZE := Vector2i(1920, 1080)
const DESIGN_SIZE := Vector2i(960, 540)
const NAVIGATOR_PATH := "res://artifacts/tutorial/navigator_1920x1080.png"
const PILOT_PATH := "res://artifacts/tutorial/pilot_1920x1080.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var game := root.get_node_or_null("Game")
	var displays := root.get_node_or_null("Displays")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if game == null or displays == null or packed == null:
		_fail("缺少 Game、Displays 或主场景")
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/tutorial"))
	game.set("fullscreen_dual_display", false)
	game.set("experiment_mode", false)
	game.set("debug_mode", false)
	game.call("select_mission", "practice")
	# 面向训练关第一段航线，让两张图都是正常、可用于讲解的起步状态。
	var spawn: Vector3 = game.get("ship_position")
	var first_target := Vector3(-102.0, 0.0, 42.0)
	var direction := (first_target - spawn).normalized()
	game.set("ship_heading", atan2(-direction.x, -direction.z))

	var scene := packed.instantiate()
	root.add_child(scene)
	for frame: int in range(16):
		await process_frame

	# Main 会把两个岗位分配到独立窗口。覆盖物理窗口尺寸，但保留游戏正式使用的
	# 960×540 设计坐标，这样输出与全屏席位画面的布局和像素比例一致。
	displays.call("set_primary_role", 0)
	var secondary := displays.call("secondary_window") as Window
	if secondary == null:
		_fail("副屏窗口未创建")
		return
	_configure_window(root)
	_configure_window(secondary)
	_hide_pointer_overlays(displays)
	game.call("set_waypoint", first_target)
	for frame: int in range(12):
		await process_frame

	if not _save_viewport(root, NAVIGATOR_PATH):
		return
	if not _save_viewport(secondary, PILOT_PATH):
		return

	print("ROLE_REFERENCES_OK navigator=%s pilot=%s size=%dx%d" % [
		NAVIGATOR_PATH, PILOT_PATH, OUTPUT_SIZE.x, OUTPUT_SIZE.y
	])
	scene.queue_free()
	await process_frame
	quit(0)


func _configure_window(window: Window) -> void:
	window.borderless = true
	window.size = OUTPUT_SIZE
	window.content_scale_size = DESIGN_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _hide_pointer_overlays(displays: Node) -> void:
	for property_name: String in ["_cursor_layer", "_secondary_cursor_layer"]:
		var layer := displays.get(property_name) as CanvasLayer
		if layer != null:
			layer.visible = false


func _save_viewport(viewport: Viewport, path: String) -> bool:
	var image := viewport.get_texture().get_image()
	if image.get_size() != OUTPUT_SIZE:
		image.resize(OUTPUT_SIZE.x, OUTPUT_SIZE.y, Image.INTERPOLATE_NEAREST)
	var error := image.save_png(path)
	if error != OK:
		_fail("无法保存 %s：%s" % [path, error_string(error)])
		return false
	return true


func _fail(message: String) -> void:
	push_error("ROLE_REFERENCES_FAILED: %s" % message)
	quit(1)
