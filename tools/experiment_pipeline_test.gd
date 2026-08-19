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
	_check(game.attribution_condition=="explicit","odd groups should use explicit condition")
	_check(game.participant_id_for_seat(0)=="D903B","group 903 should flip participant A to screen B")
	_check(game.participant_id_for_seat(1)=="D903A","screen B should map to participant A")

	experiment_log.begin_session()
	_check(not experiment_log.session_id.is_empty(),"session should start after group setup")
	var raw_dir: String = experiment_log.session_dir
	experiment_log.log_event("pipeline_probe","screen_a",{"comma":"a,b","quote":"\"ok\""})
	for i: int in range(120):
		game.ship_position = Vector3(float(i),0.0,-float(i))
		game.ship_velocity = Vector3(1.0,0.0,-1.0)
		experiment_log.sample_frame()
	experiment_log.close_session()

	var events_path := "%s/events.csv" % raw_dir
	var frames_path := "%s/frames.csv" % raw_dir
	var session_path := "%s/session.csv" % raw_dir
	_check(FileAccess.file_exists(events_path),"events.csv should exist")
	_check(FileAccess.file_exists(frames_path),"frames.csv should exist")
	_check(FileAccess.file_exists(session_path),"session.csv should exist")
	_check(_csv_row_count(events_path)>=4,"events should contain start, probe, and end")
	_check(_csv_row_count(frames_path)==121,"all 120 frame rows should be written")
	_check(_csv_row_count(session_path)==2,"session should contain one metadata row")

	game.has_waypoint = true
	game.ship_position = Vector3.ZERO
	game.waypoint = Vector3(10.0,0.0,0.0)
	game.trigger_waypoint_drift(13.0)
	_check(is_equal_approx(rad_to_deg(atan2(-game.waypoint.z,game.waypoint.x)),13.0),"waypoint drift should rotate by 13 degrees")

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
	for filename: String in ["events.csv","frames.csv","session.csv"]:
		DirAccess.remove_absolute("%s/%s" % [absolute_raw,filename])
	DirAccess.remove_absolute(absolute_raw)
	var session_parent := absolute_raw.get_base_dir()
	var dyad_parent := session_parent.get_base_dir()
	DirAccess.remove_absolute(session_parent)
	DirAccess.remove_absolute(dyad_parent)
