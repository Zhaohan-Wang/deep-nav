extends SceneTree

var _failures: Array[String] = []
var game: Node
var experiment_log: Node


func _initialize() -> void:
	game = root.get_node("Game")
	experiment_log = root.get_node("ExperimentLog")
	_run.call_deferred()


func _check(condition: bool,message: String) -> void:
	if not condition:
		_failures.append(message)


func _run() -> void:
	game.experiment_mode = true
	game.clear_experiment_setup()
	_check(game.lock_experiment_setup(903),"group setup should lock")
	_check(game.dyad_id=="D903","dyad id should be normalized")
	_check(game.attribution_condition in ["explicit","ambiguous"],"condition should be randomized to a valid arm")
	_check(game.condition_assignment_method=="runtime_random_1_to_1","condition assignment method should be recorded")
	_check(game.participant_id_for_seat(0)=="D903B","group 903 should flip participant A to screen B")
	_check(game.participant_id_for_seat(1)=="D903A","screen B should map to participant A")

	experiment_log.begin_session()
	_check(not experiment_log.session_id.is_empty(),"session should start after group setup")
	var raw_dir: String = experiment_log.session_dir
	experiment_log.begin_mission_attempt(1)
	experiment_log.log_event("pipeline_probe","screen_a",{"comma":"a,b","quote":"\"ok\""})
	for i: int in range(120):
		game.ship_position = Vector3(float(i),0.0,-float(i))
		game.ship_velocity = Vector3(1.0,0.0,-1.0)
		experiment_log.sample_frame()
	experiment_log.record_waypoint({"waypoint_id":"probe-waypoint","request_sequence":1,"accepted":true})
	experiment_log.set_active_target_event("probe-event-01","waypoint_drift")
	experiment_log.record_target_event({"event_id":"probe-event-01","event_type":"waypoint_drift"})
	for role: String in ["navigator","pilot"]:
		experiment_log.record_rating(role,"probe-event-01",{
			"questionnaire_variant":"event_responsibility_100","target_event_applicable":true,
			"responsibility_self":20,"responsibility_partner":20,"responsibility_navigation_system":20,
			"responsibility_ship_system":20,"responsibility_environment":20,
		})
	experiment_log.record_mission({"outcome":"probe","success":true,"elapsed":1.0,"limit":10.0,"waypoints":1,"target_event_triggered":true})
	experiment_log.close_session()

	var events_path := "%s/events.csv" % raw_dir
	var frames_path := "%s/frames.csv" % raw_dir
	var session_path := "%s/sessions.csv" % raw_dir
	_check(FileAccess.file_exists(events_path),"events.csv should exist")
	_check(FileAccess.file_exists(frames_path),"frames.csv should exist")
	_check(FileAccess.file_exists(session_path),"sessions.csv should exist")
	_check(_csv_row_count(events_path)>=4,"events should contain start, probe, and end")
	_check(_csv_row_count(frames_path)==121,"all 120 frame rows should be written")
	_check(_csv_row_count(session_path)==2,"session should contain one metadata row")
	_check(_csv_row_count("%s/missions.csv" % raw_dir)==2,"mission summary should be written")
	_check(_csv_row_count("%s/target_events.csv" % raw_dir)==2,"target-event summary should be written")
	_check(_csv_row_count("%s/waypoints.csv" % raw_dir)==2,"waypoint summary should be written")
	_check(FileAccess.file_exists("%s/quality_report.json" % raw_dir),"quality report should be generated")

	game.has_waypoint = true
	game.ship_position = Vector3.ZERO
	game.waypoint = Vector3(10.0,0.0,0.0)
	game.trigger_waypoint_drift(13.0)
	_check(is_equal_approx(rad_to_deg(atan2(-game.waypoint.z,game.waypoint.x)),13.0),"waypoint drift should rotate by 13 degrees")
	game.call("reset_run")
	game.has_waypoint = true
	game.ship_position = Vector3.ZERO
	game.waypoint = Vector3(10.0,0.0,0.0)
	game.call("arm_waypoint_drift",28.0,"test_zone")
	_check(game.waypoint.is_equal_approx(Vector3(10.0,0.0,0.0)),"arming a level 3 pulse visibly moved an existing waypoint")
	_check((game.get("_pending_waypoint_drifts") as Array).size()==1,"armed level 3 pulse was not held for the next click")
	_check(bool(game.call("set_waypoint",Vector3(10.0,0.0,0.0))),"armed waypoint click was rejected")
	_check(is_equal_approx(rad_to_deg(atan2(-game.waypoint.z,game.waypoint.x)),28.0),"next click did not appear directly at the distorted position")
	_check((game.get("_pending_waypoint_drifts") as Array).is_empty(),"applied click did not consume exactly one armed pulse")
	game.call("reset_run")
	game.has_waypoint = false
	game.trigger_waypoint_drift(24.0)
	game.trigger_waypoint_drift(-31.5)
	var pending_drifts := game.get("_pending_waypoint_drifts") as Array
	_check(pending_drifts.size()==2,"waypoint drift pulses without an active waypoint should queue instead of overwriting each other")
	_check(is_equal_approx(float(pending_drifts[0]),24.0) and is_equal_approx(float(pending_drifts[1]),-31.5),"queued waypoint drift order or sign changed")

	_cleanup(raw_dir)
	game.clear_experiment_setup()
	if _failures.is_empty():
		print("EXPERIMENT_PIPELINE_TEST_OK")
		quit(0)
	else:
		for failure: String in _failures:
			push_error("EXPERIMENT_PIPELINE_TEST_FAIL: %s" % failure)
		quit(1)


func _csv_row_count(path: String) -> int:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null:
		return 0
	var count := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if not row.is_empty() and not (row.size()==1 and row[0].is_empty()):
			count += 1
	return count


func _cleanup(raw_dir: String) -> void:
	var absolute_raw := ProjectSettings.globalize_path(raw_dir)
	for filename: String in ["sessions.csv","missions.csv","target_events.csv","ratings.csv","waypoints.csv","events.csv","frames.csv"]:
		DirAccess.remove_absolute("%s/%s" % [absolute_raw,filename])
	DirAccess.remove_absolute("%s/quality_report.json" % absolute_raw)
	DirAccess.remove_absolute(absolute_raw)
	var session_parent := absolute_raw.get_base_dir()
	var dyad_parent := session_parent.get_base_dir()
	DirAccess.remove_absolute(session_parent)
	DirAccess.remove_absolute(dyad_parent)
