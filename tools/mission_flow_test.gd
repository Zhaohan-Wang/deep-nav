extends SceneTree
## 量表屏内约束 + 解体复活不重置任务的流程防回归。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_end_ui_layout()
	_check_causal_explanation_copy()
	_check_waypoint_drift_randomization()
	_check_relay_respawn_policy()
	await _check_timed_respawn_flow()
	_check_heading_event_counter()
	print("MISSION_FLOW_OK per_mission=shared100_then_confidence_then_state6 trust_order=participant_stable cards_inside=960x540 death_respawns=true timeout_only_failure=true relay_stations=visible")
	quit(0)


func _check_end_ui_layout() -> void:
	var host := Control.new()
	host.size = Vector2(960,540)
	root.add_child(host)
	var summary := {
		"mission_id":"level_1","outcome":"超时未完成","success":false,"elapsed":150.0,"limit":150.0,
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
	assert(_visible_text(result).contains("150 / 150 秒"),"formal result did not show elapsed mission time")
	result.show_summary(summary.merged({"mission_id":"practice","elapsed":0.0,"timed":false},true))
	await process_frame
	assert(_visible_text(result).contains("不计时") and not _visible_text(result).contains("0 /"),"practice result must be explicitly untimed")
	result.free()
	var game_for_bar:=root.get_node("Game")
	game_for_bar.call("select_mission","level_1")
	game_for_bar.set("mission_elapsed_s",45.0); game_for_bar.set("mission_time_limit_s",160.0); game_for_bar.set("mission_timer_active",true)
	var status_bar: Control=load("res://scripts/ui/mission_status_bar.gd").new(); host.add_child(status_bar); await process_frame
	assert(_visible_text(status_bar).contains("剩余时间") and _visible_text(status_bar).contains("距终点") and _visible_text(status_bar).contains("共同航程"),"shared bottom mission status is incomplete")
	_assert_inside(status_bar,host.get_global_rect(),"mission status bar")
	status_bar.free()
	var survey: Control = load("res://scripts/ui/survey_panel.gd").new()
	host.add_child(survey)
	survey.setup("navigator","超时未完成",summary)
	await process_frame
	var trust_order := survey.get("_page_ids") as Array
	assert(trust_order.size()==3 and trust_order.has("partner") and trust_order.has("navigation") and trust_order.has("ship"),"formal mission must contain three trust blocks")
	assert((survey.get("_answers") as Dictionary)["questionnaire_variant"]=="post_attribution_state","formal state variant was not recorded")
	assert((survey.get("_answers") as Dictionary)["instrument_version"]=="post-attribution-state-4.2","formal state instrument version was not updated")
	survey.call("_show_page",trust_order.find("partner"))
	await process_frame
	assert(_visible_text(survey).contains("我的搭档（驾驶员）仍然能够可靠地履行自己的任务职责"),"partner wording was not role-specific and neutral")
	_assert_visible_controls_inside(survey,host.get_global_rect(),"normal survey page 1")
	for page_index: int in [1,2]:
		survey.call("_show_page",page_index)
		await process_frame
		_assert_visible_controls_inside(survey,host.get_global_rect(),"normal survey page %d"%(page_index+1))
	var captured: Dictionary = {}
	survey.submitted.connect(func(_role: String,answers: Dictionary): captured.merge(answers,true))
	var normal_answers := survey.get("_answers") as Dictionary
	normal_answers["partner_state_reliability"] = 6
	normal_answers["partner_state_reliance"] = 1
	normal_answers["navigation_state_reliability"] = 5
	normal_answers["navigation_state_reliance"] = 4
	normal_answers["ship_state_reliability"] = 3
	normal_answers["ship_state_reliance"] = 2
	survey.call("_on_submit")
	assert(int(captured["partner_state_reliability"])==6 and int(captured["partner_state_reliance"])==1,"partner reliability and reliance must remain separate")
	assert((captured.trust_block_order as Array)==trust_order,"saved trust order did not match participant order")
	assert(_visible_text(survey).contains("请留在本页等待搭档完成"),"submitted participant fell back to gameplay instead of waiting")
	survey.free()

	var practice: Control = load("res://scripts/ui/survey_panel.gd").new()
	host.add_child(practice)
	practice.setup("navigator","完成",summary.merged({"mission_id":"practice","success":true},true))
	await process_frame
	assert((practice.get("_page_ids") as Array)==["training"],"practice must contain operation comprehension only")
	assert(_visible_text(practice).contains("操作理解检查"),"practice comprehension page missing")
	var navigator_training := practice.get("_answers") as Dictionary
	assert(navigator_training.has("navigator_can_place_waypoint") and not navigator_training.has("pilot_knows_flight_controls"),"navigator must receive navigator-only training items")
	assert(not _visible_text(practice).contains("W／S"),"navigator was shown pilot control questions")
	for key: String in ["navigator_can_place_waypoint","navigator_knows_map_toggle","navigator_knows_waypoint_constraints","navigator_knows_route_guidance"]:
		navigator_training[key] = "yes"
	assert(bool(practice.call("_page_complete")),"navigator completion must not wait for pilot items")
	_assert_visible_controls_inside(practice,host.get_global_rect(),"practice survey page 1")
	practice.free()
	var pilot_practice: Control = load("res://scripts/ui/survey_panel.gd").new()
	host.add_child(pilot_practice)
	pilot_practice.setup("pilot","完成",summary.merged({"mission_id":"practice","success":true},true))
	await process_frame
	var pilot_training := pilot_practice.get("_answers") as Dictionary
	assert(pilot_training.has("pilot_knows_flight_controls") and not pilot_training.has("navigator_can_place_waypoint"),"pilot must receive pilot-only training items")
	assert(not _visible_text(pilot_practice).contains("按 E 键"),"pilot was shown navigator map questions")
	for key: String in ["pilot_knows_flight_controls","pilot_knows_waypoint_flying","pilot_knows_flight_status","pilot_knows_status_communication"]:
		pilot_training[key] = "yes"
	assert(bool(pilot_practice.call("_page_complete")),"pilot completion must not wait for navigator items")
	pilot_practice.free()

	var game := root.get_node("Game")
	var event_summary := summary.merged({"mission_id":"level_3","success":true,"waypoint_drift_events":1},true)
	var event_survey: Control = load("res://scripts/ui/survey_panel.gd").new()
	host.add_child(event_survey)
	event_survey.setup("pilot","完成",event_summary)
	await process_frame
	assert((event_survey.get("_page_ids") as Array).size()==3,"level 3 must contain six state items in three blocks")
	assert(event_survey.find_child("SubmitAttribution",true,false)==null,"level 3 mixed responsibility controls into the state stage")
	_assert_visible_controls_inside(event_survey,host.get_global_rect(),"level 3 state page 1")
	for page_index: int in [1,2]:
		event_survey.call("_show_page",page_index)
		await process_frame
		_assert_visible_controls_inside(event_survey,host.get_global_rect(),"level 3 state page %d"%(page_index+1))
	event_survey.free()
	var review_panel: Control = load("res://scripts/ui/experiment_review_panel.gd").new()
	host.add_child(review_panel)
	review_panel.setup("navigator","复核说明")
	await process_frame
	_assert_visible_controls_inside(review_panel,host.get_global_rect(),"experiment review")
	assert(review_panel.find_child("ExperimenterRetry",true,false)!=null,"experiment review retry action missing")
	_check_review_policy()
	host.queue_free()
	await process_frame


func _check_causal_explanation_copy() -> void:
	var tracker: Node = load("res://scripts/main.gd").new()
	assert(str(tracker.call("_causal_explanation_message","waypoint_drift","explicit"))=="检测到磁暴干扰。航点位置已发生偏移。","explicit waypoint explanation changed")
	assert(str(tracker.call("_causal_explanation_message","waypoint_drift","ambiguous"))=="检测到航点位置偏移，原因未知。","ambiguous waypoint explanation changed")
	assert(str(tracker.call("_causal_explanation_message","ship_shear","explicit"))=="检测到太阳风扰动。飞船已出现横向偏移。","explicit ship explanation changed")
	assert(str(tracker.call("_causal_explanation_message","ship_shear","ambiguous"))=="检测到飞船横向偏移，原因未知。","ambiguous ship explanation changed")
	assert(str(tracker.call("_causal_explanation_message","recovery_window","explicit"))==str(tracker.call("_causal_explanation_message","recovery_window","ambiguous")),"recovery copy differed between conditions")
	assert(str(tracker.call("_causal_explanation_message","waypoint_drift_armed","explicit")).is_empty(),"cause was shown before a waypoint actually shifted")
	tracker.free()


func _check_waypoint_drift_randomization() -> void:
	var tracker: Node = load("res://scripts/main.gd").new()
	var seeded_rng := RandomNumberGenerator.new()
	seeded_rng.seed = 20260820
	tracker.set("_waypoint_drift_rng",seeded_rng)
	var saw_clockwise := false
	var saw_counterclockwise := false
	var magnitudes := {}
	for _draw_index: int in range(32):
		var angle := float(tracker.call("_draw_waypoint_drift_angle"))
		assert(absf(angle)>=24.0 and absf(angle)<=36.0,"waypoint drift escaped the stronger 24-36 degree range")
		saw_clockwise = saw_clockwise or angle < 0.0
		saw_counterclockwise = saw_counterclockwise or angle > 0.0
		magnitudes[absf(angle)] = true
	assert(saw_clockwise and saw_counterclockwise,"waypoint drift must be able to turn in both directions")
	assert(magnitudes.size()>4,"waypoint drift magnitude remained effectively fixed")
	tracker.free()


func _check_review_policy() -> void:
	var game := root.get_node("Game")
	var tracker: Node = load("res://scripts/main.gd").new()
	game.call("select_mission","practice")
	tracker.set("_survey_answers",{
		"navigator":{"training_review_required":true},
		"pilot":{"training_review_required":false},
	})
	assert(str(tracker.call("_required_review").get("code",""))=="training_comprehension","training uncertainty must require experimenter review")
	game.call("select_mission","level_3")
	assert(str(tracker.call("_required_review").get("code",""))=="target_event_unexposed","unexposed target anomaly must require replay")
	game.call("select_mission","level_1")
	tracker.set("_survey_answers",{
		"navigator":{"target_event_applicable":false},
		"pilot":{"target_event_applicable":false},
	})
	assert(str(tracker.call("_required_review").get("code",""))=="mission_review_missing","normal mission without a saved review must not enter attribution")
	game.call("store_event_review","level_1",{"mission_id":"level_1"})
	assert((tracker.call("_required_review") as Dictionary).is_empty(),"normal mission with a saved review was incorrectly rejected")
	tracker.free()


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
	game.set("_triggered_disturbances",{0:true,1:true})
	game.call("respawn_ship_at",claimed.position,claimed.heading)
	assert((game.get("_triggered_disturbances") as Dictionary).size()==2,"death respawn re-armed already crossed disturbance gates")
	game.call("reset_run")
	assert(not bool(game.call("is_relay_reached",0)),"new run must clear relay claims")


func _check_timed_respawn_flow() -> void:
	var game := root.get_node("Game")
	game.call("select_mission","level_1")
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
	# 普通正式关超时判负并自然结算，但不进入事件责任归因或状态量表。
	main.call("_begin_mission_end","超时未完成",false)
	await create_timer(6.0,true,false,true).timeout
	assert(bool(main.get("_mission_ended")),"timeout did not end mission")
	assert(not bool(game.get("ship_alive")),"terminal timeout explosion incorrectly respawned")
	assert(root.find_children("MissionAttribution_*","",true,false).is_empty(),"normal level incorrectly opened event attribution")
	assert(root.find_children("SurveyPanel_*","",true,false).is_empty(),"normal level incorrectly opened post-event state surveys")
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
