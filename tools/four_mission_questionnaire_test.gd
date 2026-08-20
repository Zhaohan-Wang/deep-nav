extends SceneTree
## 第一至第四关逐关检查：每人连续完成 100 分责任分配与状态信任，只在最后等待一次。

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game := root.get_node("Game")
	game.experiment_mode = true
	game.call("lock_experiment_setup",1)
	await _check_state_surveys()
	await _check_mission_capture_for_all_four()
	await _check_allocator_for_all_four()
	await _check_each_level_enters_allocator()
	print("FOUR_MISSION_QUESTIONNAIRE_OK target_levels=3,4 responsibility_then_state=continuous awareness_check=true single_target_event=true")
	quit(0)

func _check_state_surveys() -> void:
	var host := _host()
	for mission_id: String in _levels():
		var survey: Control = load("res://scripts/ui/survey_panel.gd").new()
		host.add_child(survey)
		survey.setup("navigator","完成",_summary(mission_id))
		await process_frame
		var state_order := survey.get("_page_ids") as Array
		assert(state_order.size()==3 and state_order.has("partner") and state_order.has("navigation") and state_order.has("ship"),"%s did not contain three balanced trust blocks" % mission_id)
		survey.call("_show_page",state_order.find("partner"))
		await process_frame
		assert(_all_text(survey).contains("我的搭档（驾驶员）仍然能够可靠地履行自己的任务职责"),"%s partner wording was not role-specific" % mission_id)
		_assert_visible_inside(survey,host.get_global_rect(),mission_id+" state 1")
		for page_index: int in [1,2]:
			survey.call("_show_page",page_index)
			await process_frame
			_assert_visible_inside(survey,host.get_global_rect(),mission_id+" state %d"%(page_index+1))
		survey.free()
	host.queue_free()
	await process_frame

func _check_mission_capture_for_all_four() -> void:
	var game := root.get_node("Game")
	for mission_id: String in _levels():
		game.call("select_mission",mission_id)
		var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(main)
		for i: int in range(5): await process_frame
		main.set("_mission_elapsed",42.5)
		if mission_id == "level_3": main.set("_waypoint_drift_events",1)
		if mission_id == "level_4": main.set("_ship_shear_events",1)
		if mission_id in ["level_3","level_4"]:
			var target_type := "waypoint_drift" if mission_id=="level_3" else "ship_shear"
			var target_record := _record(mission_id)
			target_record["capture_kind"] = "target_peak"
			game.call("store_event_review",target_type,target_record)
		main.call("_capture_mission_review","完成",true)
		var record := game.call("event_review",mission_id) as Dictionary
		assert(str(record.get("mission_id",""))==mission_id,"%s review was not saved" % mission_id)
		if mission_id in ["level_3","level_4"]:
			assert(str(record.get("capture_kind",""))=="target_peak","%s did not use the target peak frame" % mission_id)
			_assert_two_images(record,mission_id)
		else:
			assert((record.get("views",{}) as Dictionary).is_empty(),"%s should not use a meaningless mission-end screenshot" % mission_id)
		main.queue_free()
		await process_frame

func _check_allocator_for_all_four() -> void:
	var host := _host()
	var first_order: Array = []
	for mission_id: String in _levels():
		var panel: Control = load("res://scripts/ui/mission_attribution_panel.gd").new()
		host.add_child(panel)
		panel.setup("navigator","D001A",_record(mission_id))
		await process_frame
		var order := panel.get("_item_order") as Array
		if first_order.is_empty(): first_order.assign(order)
		else: assert(order==first_order,"item order changed between levels")
		assert(order.size()==5,"%s did not show five responsibility objects" % mission_id)
		assert(int(panel.call("_assigned"))==0 and int(panel.call("_remaining"))==100,"%s did not start at 0/100" % mission_id)
		assert((panel.find_child("SubmitAttribution",true,false) as Button).disabled,"%s allowed incomplete submission" % mission_id)
		var text := _all_text(panel)
		assert(text.contains(_label(mission_id)) and text.contains(_review_heading(mission_id)),"%s title was not mission-specific" % mission_id)
		assert(text.contains("我自己（领航员）") and text.contains("我的搭档（驾驶员）"),"%s role labels were wrong" % mission_id)
		assert(text.contains("领航系统") and text.contains("飞船控制系统") and text.contains("外部环境"),"%s responsibility labels were wrong" % mission_id)
		assert(text.contains("事件前后航迹") and panel.find_child("MissionFlightTrail",true,false)!=null,"%s flight trail review was missing" % mission_id)
		if mission_id == "level_3":
			var trail_review := panel.find_child("MissionFlightTrail",true,false)
			assert((trail_review.get("_target_positions") as PackedVector2Array).size()==1,"level 3 did not draw exactly one target event")
			assert((trail_review.get("_fixed_bounds") as Rect2).is_equal_approx(Rect2(-480,-120,960,240)),"level 3 trail did not use a stable full-mission frame")
		if mission_id == "level_3":
			assert(text.contains("你是否注意到航点位置发生了偏移"),"level 3 awareness question was not event-specific")
			assert(not text.contains("领航员放置航点后"),"level 3 review foregrounded an actor before responsibility allocation")
		if mission_id == "level_4": assert(text.contains("你是否注意到飞船出现了横向偏移"),"level 4 awareness question was not event-specific")
		if mission_id in ["level_3","level_4"]:
			var screenshot := panel.find_child("MissionScreenshot",true,false) as Control
			var screenshot_image := panel.find_child("MissionScreenshotImage",true,false) as TextureRect
			assert(screenshot != null and screenshot.size.y>=95.0,"%s peak screenshot was too short to review" % mission_id)
			assert(screenshot_image != null and screenshot_image.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"%s peak screenshot was cropped instead of fully fitted" % mission_id)
		assert(text.contains("−5") and text.contains("＋5") and text.contains("剩余可分配：100分"),"%s controls were incomplete" % mission_id)
		assert(not text.contains("磁暴") and not text.contains("太阳风"),"%s leaked a cause" % mission_id)
		_assert_visible_inside(panel,host.get_global_rect(),mission_id+" allocator")
		panel.call("_set_event_awareness","clear")
		panel.call("_set_value","self",60)
		panel.call("_set_value","partner",40)
		panel.call("_set_value","navigation_system",5)
		assert(int(panel.call("_value","navigation_system"))==0 and int(panel.call("_value","self"))==60,"%s exceeded or auto-normalized budget" % mission_id)
		panel.call("_set_value","self",55)
		panel.call("_set_value","navigation_system",5)
		var answer: Dictionary = {}
		panel.submitted.connect(func(_role: String,data: Dictionary): answer.merge(data,true))
		panel.call("_on_submit")
		assert(answer.is_empty() and bool(panel.get("_allocation_locked")),"%s did not separate allocation confirmation from confidence" % mission_id)
		assert((panel.find_child("ConfidenceRow",true,false) as Control).is_visible_in_tree(),"%s confidence did not appear after allocation confirmation" % mission_id)
		panel.call("_set_confidence",6)
		panel.call("_on_submit")
		assert(str(answer.get("mission_id",""))==mission_id,"%s stored the wrong mission" % mission_id)
		assert(str(answer.get("instrument_version",""))=="event-attribution-5.0","%s stored the wrong version" % mission_id)
		if mission_id == "level_3": assert(int(answer.get("target_event_pulse_count",0))==1,"level 3 did not save exactly one target event")
		assert(str(answer.get("event_awareness",""))=="clear","%s did not save event awareness" % mission_id)
		assert(_total(answer)==100 and int(answer.attribution_confidence)==6,"%s saved an invalid allocation" % mission_id)
		assert((answer.item_display_order as Array)==first_order,"%s did not save item order" % mission_id)
		assert(bool(answer.screenshot_available)==(mission_id in ["level_3","level_4"]),"%s screenshot applicability was wrong" % mission_id)
		assert(_all_text(panel).contains("正在进入下一部分"),"%s inserted a partner wait between questionnaires" % mission_id)
		panel.free()
	host.queue_free()
	await process_frame

func _check_each_level_enters_allocator() -> void:
	var game := root.get_node("Game")
	for mission_id: String in ["level_3","level_4"]:
		game.session_mission_index = MissionCatalog.IDS.find(mission_id)
		game.call("select_mission",mission_id)
		game.call("store_event_review",mission_id,_record(mission_id))
		if mission_id == "level_3": game.call("store_event_review","waypoint_drift",_record(mission_id))
		if mission_id == "level_4": game.call("store_event_review","ship_shear",_record(mission_id))
		var tracker: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		root.add_child(tracker)
		for i: int in range(5): await process_frame
		tracker.set("_mission_outcome","完成")
		tracker.set("_mission_summary",_summary(mission_id))
		if mission_id=="level_3": tracker.set("_waypoint_drift_events",1)
		if mission_id=="level_4": tracker.set("_ship_shear_events",1)
		tracker.call("_show_mission_attribution_surveys")
		await process_frame
		assert(root.find_children("MissionAttribution_*","",true,false).size()==2,"%s did not open two allocators" % mission_id)
		tracker.call("_on_mission_attribution_submitted","navigator",{"mission_id":mission_id})
		await process_frame
		assert(root.find_children("SurveyPanel_navigator","",true,false).size()==1,"%s navigator did not continue directly to state trust" % mission_id)
		assert(root.find_children("SurveyPanel_pilot","",true,false).is_empty(),"%s pilot advanced before submitting responsibility" % mission_id)
		assert(root.find_children("MissionAttribution_pilot","",true,false).size()==1,"%s removed the pilot allocator too early" % mission_id)
		await tracker.call("_on_mission_attribution_submitted","pilot",{"mission_id":mission_id})
		assert(root.find_children("SurveyPanel_*","",true,false).size()==2,"%s did not open state trust after both responsibility submissions" % mission_id)
		assert(not game.session_mission_results.has(mission_id),"%s advanced before post-attribution trust submission" % mission_id)
		tracker.queue_free()
		await process_frame

func _levels() -> Array[String]: return ["level_1","level_2","level_3","level_4"]

func _host() -> Control:
	var host := Control.new()
	host.size = Vector2(960,540)
	root.add_child(host)
	return host

func _summary(mission_id: String) -> Dictionary:
	return {"mission_id":mission_id,"outcome":"完成","success":true,"waypoint_drift_events":1 if mission_id=="level_3" else 0,"ship_shear_events":1 if mission_id=="level_4" else 0}

func _record(mission_id: String) -> Dictionary:
	var image := Image.create(640,360,false,Image.FORMAT_RGB8)
	image.fill(Color("14293c"))
	return {
		"event_id":"%s-review-1" % mission_id,"event_type":"mission_responsibility","mission_id":mission_id,"mission_label":_label(mission_id),
		"elapsed":65.0,"outcome":"完成","success":true,"attempt_number":1,
		"target_event_type":"waypoint_drift" if mission_id=="level_3" else ("ship_shear" if mission_id=="level_4" else null),
		"target_event_exposed":true if mission_id in ["level_3","level_4"] else null,
		"target_event_pulse_count":1 if mission_id in ["level_3","level_4"] else null,
		"capture_kind":"target_peak" if mission_id in ["level_3","level_4"] else "none",
		"views":{"D001A":{"role":"navigator","image":image},"D001B":{"role":"pilot","image":image},"navigator":{"role":"navigator","image":image},"pilot":{"role":"pilot","image":image}} if mission_id in ["level_3","level_4"] else {},
		"flight_trail":PackedVector2Array([Vector2(-40,12),Vector2(-10,4),Vector2(20,-6),Vector2(48,0)]),
		"failed_flight_trails":[PackedVector2Array([Vector2(-40,12),Vector2(-25,22),Vector2(-18,30)])],
		"collision_points":PackedVector2Array([Vector2(-18,30),Vector2(20,-6)]),
		"flight_start":Vector2(-40,12),"flight_goal":Vector2(48,0),
		"target_event_position":Vector2(20,-6) if mission_id in ["level_3","level_4"] else null,
		"target_event_positions":PackedVector2Array([Vector2(20,-6)]) if mission_id in ["level_3","level_4"] else PackedVector2Array(),
		"flight_world_bounds":Rect2(-480,-120,960,240),
	}

func _label(mission_id: String) -> String: return "正式任务 %02d" % MissionCatalog.IDS.find(mission_id)

func _review_heading(mission_id: String) -> String:
	if mission_id=="level_3": return "航点位置偏移"
	if mission_id=="level_4": return "飞船横向偏移"
	return "本关航行表现"

func _assert_two_images(record: Dictionary,label: String) -> void:
	var views := record.get("views",{}) as Dictionary
	for participant: String in ["D001A","D001B"]:
		assert(views.has(participant),"%s missed %s view" % [label,participant])
		var image := (views[participant] as Dictionary).get("image") as Image
		assert(image != null and not image.is_empty(),"%s saved an empty image" % label)

func _total(a: Dictionary) -> int:
	return int(a.responsibility_self)+int(a.responsibility_partner)+int(a.responsibility_navigation_system)+int(a.responsibility_ship_system)+int(a.responsibility_environment)

func _all_text(node: Node) -> String:
	var out := ""
	if node is Label: out += (node as Label).text
	elif node is Button: out += (node as Button).text
	for child: Node in node.get_children(): out += _all_text(child)
	return out

func _assert_visible_inside(node: Node,bounds: Rect2,label: String) -> void:
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree() and c.size.x>0.5 and c.size.y>0.5:
			var rect := c.get_global_rect()
			assert(rect.position.x>=bounds.position.x-0.5 and rect.position.y>=bounds.position.y-0.5,"%s starts outside" % label)
			assert(rect.end.x<=bounds.end.x+0.5 and rect.end.y<=bounds.end.y+0.5,
				"%s exceeds screen: %s end=(%.1f,%.1f) bounds=(%.1f,%.1f)" % [label,c.name,rect.end.x,rect.end.y,bounds.end.x,bounds.end.y])
	for child: Node in node.get_children(): _assert_visible_inside(child,bounds,label)
