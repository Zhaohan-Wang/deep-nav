extends SceneTree
## 教程专项：素材、翻页、鼠标穿透、暂停层级，以及训练关停表。

const TutorialScript = preload("res://scripts/ui/tutorial_overlay.gd")
const PauseScript = preload("res://scripts/ui/pause_menu.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("Game")
	for role: String in ["navigator", "pilot"]:
		var expected := 7 if role == "navigator" else 8
		var overlay := TutorialScript.new()
		root.add_child(overlay)
		overlay.setup(role)
		assert(overlay.page_paths.size() == expected, "%s tutorial page count changed" % role)
		assert(overlay.z_index == TutorialScript.OVERLAY_Z_INDEX, "tutorial z-index changed")
		_assert_mouse_passthrough(overlay)
		for page: int in range(expected):
			var texture := overlay.get_node("TutorialImage").texture as Texture2D
			assert(texture != null and texture.get_size() == Vector2(1920, 1080),
				"%s page %d is missing or not 1920x1080" % [role, page + 1])
			if page < expected - 1:
				overlay.get_node("TutorialNavigation").find_child("NextPage", true, false).pressed.emit()
		var next := overlay.get_node("TutorialNavigation").find_child("NextPage", true, false) as Button
		assert(next.text == "完成", "%s final button did not become 完成" % role)
		next.pressed.emit()
		assert(not overlay.visible, "%s tutorial did not close after 完成" % role)
		overlay.queue_free()
		await process_frame

	var pause := PauseScript.new()
	root.add_child(pause)
	pause.setup("navigator")
	assert(pause.z_index > TutorialScript.OVERLAY_Z_INDEX,
		"pause menu must render above tutorial")
	pause.queue_free()

	game.select_mission("practice")
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	assert(main.call("_is_tutorial_mission"), "practice should enable role tutorials")
	assert(not main.call("_mission_timer_enabled"), "practice timer must stay disabled")
	assert(main.get("_tutorial_overlays").size() == 2,
		"practice should create one tutorial overlay for each role")
	game.select_mission("level_1")
	assert(not main.call("_is_tutorial_mission"), "formal mission should not show tutorials")
	assert(main.call("_mission_timer_enabled"), "formal mission timer must remain enabled")
	main.queue_free()
	await process_frame

	print("TUTORIAL_OVERLAY_OK navigator=7 pilot=8 passthrough=true pause_above=true practice_timer=off")
	quit(0)


func _assert_mouse_passthrough(node: Node) -> void:
	if node is Control:
		var control := node as Control
		if control is Button:
			assert(control.mouse_filter == Control.MOUSE_FILTER_STOP,
				"tutorial buttons must remain clickable")
		else:
			assert(control.mouse_filter == Control.MOUSE_FILTER_IGNORE,
				"non-button tutorial layer blocks underlying input: %s" % control.name)
	for child: Node in node.get_children():
		_assert_mouse_passthrough(child)
