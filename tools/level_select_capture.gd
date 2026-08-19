extends SceneTree
## 只渲染任务进度页，供快速检查首图排版。

const OUTPUT := "res://artifacts/runtime/level_select_experiment.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var game := root.get_node("/root/Game")
	game.begin_mission_sequence()
	var page := (load("res://scenes/level_select.tscn") as PackedScene).instantiate()
	root.add_child(page)
	for i: int in range(8):
		await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/runtime"))
	var error := root.get_texture().get_image().save_png(OUTPUT)
	assert(error == OK,"level-select capture failed: %s" % error_string(error))
	print("LEVEL_SELECT_CAPTURE_OK %s" % OUTPUT)
	quit(0)
