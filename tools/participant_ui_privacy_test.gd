extends SceneTree
## 防回归：正式实验即使误带 debug=true，也不能在参与者页面显示研究元数据。

const FORBIDDEN: PackedStringArray = [
	"关键航段","扰动槽位","扰动锚点","安全门","路线检查点","研究目的","条件标签",
	"waypoint_drift","ship_shear","recovery_window","导航异常归因","协作恢复","无扰动基线",
	"磁暴坐标区","太阳风剪切"
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node_or_null("Game")
	assert(game != null,"Game autoload missing")
	game.set("experiment_mode",true)
	game.set("debug_mode",true)
	assert(not game.call("researcher_debug_enabled"),"experiment mode must suppress researcher debug")
	var packed := load("res://scenes/level_select.tscn") as PackedScene
	var page := packed.instantiate()
	root.add_child(page)
	await process_frame
	var catalog = load("res://scripts/mission_catalog.gd")
	for mission: SectorData in catalog.all():
		page.call("_select",mission)
		await process_frame
		var visible_text := _all_text(page)
		for token: String in FORBIDDEN:
			assert(not visible_text.contains(token),"participant UI leaked '%s' in %s" % [token,mission.id])
		assert(visible_text.contains("任务规则"),"mission rules panel missing")
	page.queue_free()
	await process_frame
	game.call("select_mission","level_4")
	var main_packed := load("res://scenes/main.tscn") as PackedScene
	var main_page := main_packed.instantiate()
	root.add_child(main_page)
	for i: int in range(4):
		await process_frame
	var gameplay_text := _all_text(main_page)
	for token: String in FORBIDDEN:
		assert(not gameplay_text.contains(token),"gameplay UI leaked '%s'" % token)
	main_page.queue_free()
	await process_frame

	game.set("experiment_mode",false)
	game.set("debug_mode",true)
	assert(game.call("researcher_debug_enabled"),"researcher debug should remain available outside experiment mode")
	var debug_page := packed.instantiate()
	root.add_child(debug_page)
	await process_frame
	debug_page.call("_select",catalog.by_id("level_3"))
	await process_frame
	var debug_text := _all_text(debug_page)
	assert(debug_text.contains("RESEARCH DEBUG"),"researcher diagnostics missing")
	assert(debug_text.contains("waypoint_drift"),"disturbance slot missing in researcher diagnostics")
	print("PARTICIPANT_UI_PRIVACY_OK missions=%d" % catalog.all().size())
	quit(0)


func _all_text(node: Node) -> String:
	var output := ""
	if node is Label or node is Button:
		output += str(node.get("text")) + "\n"
	for child: Node in node.get_children():
		output += _all_text(child)
	return output
