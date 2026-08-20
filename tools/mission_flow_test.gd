extends SceneTree
## 量表屏内约束 + 解体复活不重置任务的流程防回归。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_end_ui_layout()
	_check_relay_respawn_policy()
	await _check_timed_respawn_flow()
	_check_heading_event_counter()
	print("MISSION_FLOW_OK survey_pages=3 role_specific=true event_anchored=true heading_counter=true cards_inside=960x540 death_respawns=true timeout_only_failure=true relay_stations=visible")
	quit(0)


func _check_end_ui_layout() -> void:
	var host := Control.new()
	host.size = Vector2(960,540)
	root.add_child(host)
	var summary := {
		"outcome":"超时未完成","success":false,"elapsed":150.0,"limit":150.0,
		"revivals":4,"hits":9,"waypoints":12,"hull":0.0,
		"severe_heading_deviations":3,"waypoint_drift_events":1,"ship_shear_events":0,
	}
	var result: Control = load("res://scripts/ui/mission_result_panel.gd").new()
	host.add_child(result)
	result.setup("navigator")
	result.show_result("超时未完成",false)
	await process_frame
	_assert_inside(result.find_child("MissionResultCard",true,false) as Control,host.get_global_rect(),"result card")
	result.show_summary(summary)
	await process_frame
	_assert_inside(result.find_child("MissionResultCard",true,false) as Control,host.get_global_rect(),"summary card")
	result.free()
	var survey: Control = load("res://scripts/ui/survey_panel.gd").new()
	host.add_child(survey)
	survey.setup("navigator","超时未完成",summary)
	await process_frame
	_assert_visible_controls_inside(survey,host.get_global_rect(),"survey page 1")
	var severe_metric := survey.find_child("Metric_SevereHeading",true,false) as Control
	assert(severe_metric != null and _visible_text(severe_metric).contains("严重航向偏离") and _visible_text(severe_metric).contains("3次"),"survey did not highlight observed severe heading events")
	assert(str(survey.call("_outcome_context_text")).contains("不评价任务成败"),"failure context did not separate outcome from event attribution")
	var nav_causes := survey.call("_cause_options") as Array
	assert(str(nav_causes[1]).contains("驾驶员操控"),"navigator did not receive navigator-specific cause wording")
	assert(str(nav_causes[2]).contains("航点、方向、仪表"),"navigation information option remained ambiguous")
	assert(str(nav_causes[3]).contains("转向、变速不如预期"),"ship response option remained ambiguous")
	assert(nav_causes.size()==7,"cause choices must preserve multiple-cause and insufficient-information responses")
	survey.call("_show_page",1)
	await process_frame
	await process_frame
	_assert_visible_controls_inside(survey,host.get_global_rect(),"survey page 2")
	survey.call("_show_page",2)
	await process_frame
	await process_frame
	_assert_visible_controls_inside(survey,host.get_global_rect(),"survey page 3")
	var pilot_survey: Control = load("res://scripts/ui/survey_panel.gd").new()
	host.add_child(pilot_survey)
	pilot_survey.setup("pilot","完成",summary.merged({"success":true},true))
	assert(str((pilot_survey.call("_cause_options") as Array)[1]).contains("领航员引导"),"pilot did not receive pilot-specific cause wording")
	assert(str(pilot_survey.call("_outcome_context_text")).contains("不评价任务成败"),"success context did not separate outcome from event attribution")
	host.queue_free()
	await process_frame


func _visible_text(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text
	for child: Node in node.get_children():
		out += _visible_text(child)
	return out


func _check_heading_event_counter() -> void:
	var game := root.get_node("Game")
	game.call("select_mission","practice")
	game.set("ship_alive",true)
	game.set("has_waypoint",true)
	game.set("ship_position",Vector3.ZERO)
	game.set("waypoint",Vector3(10.0,0.0,0.0))
	game.set("ship_heading",0.0)
	game.set("ship_speed",4.0)
	var tracker: Node = load("res://scripts/main.gd").new()
	tracker.call("_track_severe_heading_deviation",1.1)
	tracker.call("_track_severe_heading_deviation",1.1)
	assert(int(tracker.get("_severe_heading_deviations"))==1,"sustained 90-degree deviation was not counted")
	tracker.call("_track_severe_heading_deviation",2.1)
	assert(int(tracker.get("_severe_heading_deviations"))==1,"one sustained episode was counted more than once")
	game.set("ship_heading",-PI/2.0)
	tracker.call("_track_severe_heading_deviation",0.1)
	game.call("reset_run")
	tracker.free()


func _check_relay_respawn_policy() -> void:
	var game := root.get_node("Game")
	game.call("select_mission","practice")
	assert((game.get("current_sector") as SectorData).relay_stations.is_empty(),"practice must restart from spawn")
	assert(int(game.call("last_respawn_point")["index"])==-1,"practice last respawn must be spawn")
	game.call("select_mission","level_3")
	var station: Vector3 = (game.get("current_sector") as SectorData).relay_stations[0]
	assert(int(game.call("last_respawn_point")["index"])==-1,"unreached relay must not become the respawn")
	game.call("update_mission_progress",station+Vector3(-8.0,0.0,0.0),station)
	assert(bool(game.call("is_relay_reached",0)),"flying through a relay must claim it")
	var claimed: Dictionary = game.call("last_respawn_point")
	assert(int(claimed["index"])==0,"claimed relay must become the respawn")
	assert(Vector3(claimed["position"]).distance_to(station)<0.1,"respawn must sit on the claimed relay")
	game.call("reset_run")
	assert(not bool(game.call("is_relay_reached",0)),"new run must clear relay claims")


func _check_timed_respawn_flow() -> void:
	var game := root.get_node("Game")
	game.call("select_mission","level_3")
	game.set("_triggered_disturbances",{0:true})
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	for i: int in range(5):
		await process_frame
	main.set("_mission_elapsed",40.0)
	game.call("explode_ship")
	await create_timer(1.5,true,false,true).timeout
	assert(game.get("ship_alive"),"ship did not respawn inside mission time")
	var spawn: Vector3 = (game.get("current_sector") as SectorData).spawn_position
	assert(Vector3(game.get("ship_position")).distance_to(spawn)<0.2,"death before any relay must return to spawn, not a hidden route point")
	assert(is_equal_approx(float(game.get("hull")),float(game.get("MAX_HULL"))),"respawn did not restore hull")
	assert(int(main.get("_mission_deaths"))==1,"revival was not counted")
	assert(float(main.get("_mission_elapsed"))>=40.0,"death reset mission timer")
	assert(not bool(main.get("_mission_ended")),"death incorrectly ended mission before timeout")
	assert((game.get("_triggered_disturbances") as Dictionary).has(0),"respawn cleared triggered mission events")
	# 超时才判负，并完整走过结果、总结、量表三个阶段；终局爆炸不得再复活。
	main.call("_begin_mission_end","超时未完成",false)
	await create_timer(6.0,true,false,true).timeout
	assert(bool(main.get("_mission_ended")),"timeout did not end mission")
	assert(not bool(game.get("ship_alive")),"terminal timeout explosion incorrectly respawned")
	# 双窗口模式会把驾驶员页重挂到独立 Window，因此从整棵场景树统计两份量表。
	assert(root.find_children("SurveyPanel_*","",true,false).size()==2,"timeout flow did not reach two independent surveys")
	main.queue_free()
	await process_frame


func _assert_inside(control: Control,bounds: Rect2,label: String) -> void:
	assert(control != null,"%s missing" % label)
	var rect := control.get_global_rect()
	assert(rect.position.x>=bounds.position.x-0.5 and rect.position.y>=bounds.position.y-0.5,"%s starts outside screen: %s" % [label,rect])
	assert(rect.end.x<=bounds.end.x+0.5 and rect.end.y<=bounds.end.y+0.5,"%s exceeds screen: %s > %s" % [label,rect,bounds])


func _assert_visible_controls_inside(node: Node,bounds: Rect2,label: String) -> void:
	if node is Control:
		var control := node as Control
		if control.is_visible_in_tree() and control.size.x>0.5 and control.size.y>0.5:
			_assert_inside(control,bounds,label+"/"+control.name)
	for child: Node in node.get_children():
		_assert_visible_controls_inside(child,bounds,label)
