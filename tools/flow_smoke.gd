extends SceneTree
## 逐页实例化，确保标题、选关和游戏主场景都能进入树。

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	for path: String in [
		"res://scenes/title_screen.tscn",
		"res://scenes/level_select.tscn",
		"res://scenes/main.tscn",
		"res://scenes/thank_you.tscn",
	]:
		var packed := load(path) as PackedScene
		assert(packed != null, "scene missing: %s" % path)
		var page := packed.instantiate(); root.add_child(page)
		await process_frame; await process_frame
		assert(page.is_inside_tree(), "scene failed: %s" % path)
		if path.ends_with("thank_you.tscn"):
			assert(page.find_child("ThankYouArtwork",true,false) != null, "thank-you artwork missing")
			assert(page.find_child("ReturnToTitleButton",true,false) != null, "thank-you return button missing")
			assert(page.find_child("QuitButton",true,false) != null, "thank-you quit button missing")
		print("FLOW_SCENE_OK %s nodes=%d" % [path, _count(page)])
		page.queue_free(); await process_frame
	var catalog = load("res://scripts/mission_catalog.gd")
	assert(catalog.all().size() == 5, "mission count")
	print("FLOW_SMOKE_OK"); quit(0)

func _count(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children(): total += _count(child)
	return total
