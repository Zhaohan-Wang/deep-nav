extends SceneTree
## 单页真实渲染截图，只加载感谢页，不进入完整任务流程。

const OUT := "res://artifacts/runtime/thank_you.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var game := root.get_node_or_null("Game")
	if game != null:
		game.set("fullscreen_dual_display",false)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	var packed := load("res://scenes/thank_you.tscn") as PackedScene
	var page := packed.instantiate()
	root.add_child(page)
	for _i: int in range(12):
		await process_frame
	await create_timer(0.25).timeout
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("THANK_YOU_CAPTURE_FAILED empty viewport image")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/runtime"))
	var error := image.save_png(ProjectSettings.globalize_path(OUT))
	if error != OK:
		push_error("THANK_YOU_CAPTURE_FAILED save=%s" % error)
		quit(1)
		return
	print("THANK_YOU_CAPTURE_OK %s %dx%d" % [OUT,image.get_width(),image.get_height()])
	quit(0)
