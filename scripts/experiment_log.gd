extends Node
## 实验原始数据只追加。主线程只构造短字符串并入队；专用 worker 独占 FileAccess。

const ROOT_DIR := "user://experiments"
const SCHEMA_VERSION := "4.1.0"
const ANALYSIS_POLICY_VERSION := "outcome-inclusive-1.0"
const FLUSH_INTERVAL_S := 1.0
const MAX_PENDING_FRAMES := 6000

const COMMON_COLUMNS: Array[String] = [
	"schema_version","protocol_version","session_id","dyad_id","participant_id","mission_id",
	"attempt_id","life_id","segment_id","event_id","role","condition","fault_type",
]
var SESSION_COLUMNS = COMMON_COLUMNS + [
	"participant_a","participant_b","screen_a_participant","screen_b_participant","started_utc",
	"godot_version","platform","screen_a_mouse","screen_b_mouse","screen_a_keyboard","screen_b_keyboard",
	"condition_assignment_method","condition_assignment_token",
]
var MISSION_COLUMNS = COMMON_COLUMNS + [
	"attempt_number","started_session_elapsed_ms","ended_session_elapsed_ms","outcome","success",
	"wall_time_ms","active_gameplay_time_ms","survey_pause_time_ms","other_pause_time_ms","time_limit_ms",
	"damage_events","damage_taken","deaths","waypoint_requests","accepted_waypoints","rejected_waypoints","hull_end",
	"path_length","direct_distance","path_efficiency_ratio",
	"severe_heading_deviations","waypoint_drift_events","ship_shear_events","target_event_triggered","aborted_reason",
]
var TARGET_EVENT_COLUMNS = COMMON_COLUMNS + [
	"event_type","event_time_session_ms","event_time_mission_ms","trigger_gate_index","parameter_name","parameter_value",
	"ship_x","ship_z","speed_at_event","waypoint_distance_at_event","obstacle_distance_at_event",
	"navigator_repair_latency_ms","repair_waypoint_angle_deg","repair_waypoint_distance","failed_waypoint_requests",
	"pilot_response_latency_ms","recovery_time_ms","heading_error_at_onset_deg",
	"heading_error_reduction_3s_deg","heading_error_reduction_5s_deg",
	"max_heading_error_deg_15s","max_cross_track_error_15s","time_to_safe_gate_ms","damage_events_15s",
	"hull_loss_15s","collision_within_15s","explosion_within_15s","disintegrated_15s",
	"recovered_within_window","window_observed_ms","outcome","payload_json",
]
var RATING_COLUMNS = COMMON_COLUMNS + [
	"instrument_version","questionnaire_variant","outcome_success","target_event_applicable","target_event_exposed",
	"event_awareness",
	"trust_block_order","partner_state_reliability","partner_state_reliance",
	"navigation_state_reliability","navigation_state_reliance","ship_state_reliability","ship_state_reliance",
	"responsibility_self","responsibility_partner","responsibility_navigation_system","responsibility_ship_system",
	"responsibility_environment","attribution_confidence","item_display_order","reset_count","screenshot_available",
	"response_time_s","payload_json",
]
var WAYPOINT_COLUMNS = COMMON_COLUMNS + [
	"waypoint_id","request_sequence","request_session_elapsed_ms","accepted","reason","remaining_cooldown_ms",
	"requested_x","requested_z","applied_x","applied_z","ship_x","ship_z","initial_heading_error_deg",
	"waypoint_distance","drifted","drift_angle_deg","response_window_observed_ms","waypoint_response_latency_ms",
	"heading_error_reduction_3s_deg","time_to_alignment_20deg_ms","waypoint_override","completion_status","payload_json",
]
var EVENT_COLUMNS = COMMON_COLUMNS + [
	"monotonic_us","session_elapsed_ms","physics_frame","event_type","seat","payload_json",
]
var FRAME_COLUMNS = COMMON_COLUMNS + [
	"monotonic_us","session_elapsed_ms","physics_frame","phase",
	"screen_a_participant","screen_a_role","screen_a_cursor_x","screen_a_cursor_y","screen_a_left_down",
	"screen_b_participant","screen_b_role","screen_b_cursor_x","screen_b_cursor_y","screen_b_left_down",
	"pilot_thrust_raw","pilot_turn_raw","ship_x","ship_z","velocity_x","velocity_z",
	"heading_rad","angular_velocity_rad_s","speed","throttle","hull","boundary_proximity",
	"has_waypoint","waypoint_x","waypoint_z","waypoint_distance","nearest_obstacle_distance",
]

var TABLE_COLUMNS := {
	"sessions":SESSION_COLUMNS,
	"missions":MISSION_COLUMNS,
	"target_events":TARGET_EVENT_COLUMNS,
	"ratings":RATING_COLUMNS,
	"waypoints":WAYPOINT_COLUMNS,
	"events":EVENT_COLUMNS,
	"frames":FRAME_COLUMNS,
}

var session_id := ""
var session_dir := ""
var _session_start_us: int = 0
var _last_clock_us: int = 0
var _flush_elapsed := 0.0
var _writer_thread: Thread
var _queue_mutex := Mutex.new()
var _queue_signal := Semaphore.new()
var _queue: Array[Dictionary] = []
var _queued_frames := 0
var _dropped_frames := 0
var _writer_running := false
var _writer_error := ""
var _attempt_number := 0
var _attempt_id := ""
var _life_number := 0
var _life_id := ""
var _segment_id := ""
var _active_event_id := ""
var _active_fault_type := ""
var _attempt_started_elapsed_ms := 0.0
var _sampling_enabled := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if session_id.is_empty():
		return
	_flush_elapsed += delta
	if _flush_elapsed >= FLUSH_INTERVAL_S:
		_flush_elapsed = 0.0
		_enqueue({"kind":"flush"})
	_queue_mutex.lock()
	var error := _writer_error
	_writer_error = ""
	_queue_mutex.unlock()
	if not error.is_empty():
		push_error("ExperimentLog writer: %s" % error)


func begin_session() -> void:
	if not Game.experiment_mode or not session_id.is_empty():
		return
	if not Game.experiment_setup_locked:
		push_error("ExperimentLog: experiment group must be locked before session start")
		return
	if ensure_root().is_empty():
		return
	var stamp := Time.get_datetime_string_from_system(true,true).replace(":","-")
	var run_stamp := stamp
	var collision_index := 1
	var base := "%s/dyad-%s/%s" % [ROOT_DIR,Game.dyad_id,run_stamp]
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base)):
		collision_index += 1
		run_stamp = "%s_%02d" % [stamp,collision_index]
		base = "%s/dyad-%s/%s" % [ROOT_DIR,Game.dyad_id,run_stamp]
	session_id = "%s_%s" % [Game.dyad_id,run_stamp]
	session_dir = "%s/raw" % base
	var absolute_dir := ProjectSettings.globalize_path(session_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_dir) != OK:
		push_error("ExperimentLog: cannot create session directory")
		session_id = ""
		session_dir = ""
		return
	_session_start_us = Time.get_ticks_usec()
	_last_clock_us = _session_start_us
	_flush_elapsed = 0.0
	_dropped_frames = 0
	_writer_error = ""
	_start_writer(absolute_dir)
	var session_values: Array[Variant] = _common_values("","system","","","",false) + [
		Game.participant_a,Game.participant_b,Game.participant_id_for_seat(0),
		Game.participant_id_for_seat(1),Time.get_datetime_string_from_system(true,true),
		str(Engine.get_version_info().get("string","")),OS.get_name(),
		RawMice.device_name(0),RawMice.device_name(1),
		RawMice.keyboard_name(0),RawMice.keyboard_name(1),
		str(Game.get("condition_assignment_method")),str(Game.get("condition_assignment_token")),
	]
	_enqueue({"kind":"line","table":"sessions","line":_csv_line(session_values)})
	log_event("session_start","system",{
		"protocol_version":Game.EXPERIMENT_PROTOCOL_VERSION,
		"condition":Game.attribution_condition,
		"participant_a_seat":Game.participant_a_seat,
	})


## 标题页先确保根目录存在，再交给 OS 打开。
func ensure_root() -> String:
	var absolute := ProjectSettings.globalize_path(ROOT_DIR)
	if DirAccess.dir_exists_absolute(absolute):
		return ROOT_DIR
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		return ""
	return ROOT_DIR


func close_session() -> void:
	if session_id.is_empty():
		return
	log_event("session_end","system",{
		"dropped_frame_rows":_dropped_frames,
	})
	_enqueue({"kind":"stop"})
	if _writer_thread != null:
		_writer_thread.wait_to_finish()
		_writer_thread = null
	_write_quality_report(ProjectSettings.globalize_path(session_dir))
	_writer_running = false
	_sampling_enabled = false
	_attempt_number = 0
	_attempt_id = ""
	_life_number = 0
	_life_id = ""
	_segment_id = ""
	_active_event_id = ""
	_active_fault_type = ""
	session_id = ""
	session_dir = ""
	_session_start_us = 0
	_last_clock_us = 0
	_flush_elapsed = 0.0
	_queue_mutex.lock()
	_queue.clear()
	_queued_frames = 0
	_queue_mutex.unlock()


func _write_quality_report(absolute_raw_dir: String) -> void:
	var issues: Array[String] = []
	var missions := _read_csv_records("%s/missions.csv" % absolute_raw_dir)
	var targets := _read_csv_records("%s/target_events.csv" % absolute_raw_dir)
	var waypoints := _read_csv_records("%s/waypoints.csv" % absolute_raw_dir)
	var ratings := _read_csv_records("%s/ratings.csv" % absolute_raw_dir)
	if missions.is_empty(): issues.append("missions.csv 没有任务汇总记录")
	if targets.is_empty(): issues.append("target_events.csv 没有目标异常记录")
	if waypoints.is_empty(): issues.append("waypoints.csv 没有航点请求记录")
	for mission: Dictionary in missions:
		var aborted := not str(mission.get("aborted_reason","")).is_empty()
		if not aborted and float(mission.get("active_gameplay_time_ms",0.0)) <= 0.0:
			issues.append("任务 %s 的游戏内用时不大于 0" % mission.get("attempt_id",""))
		if not aborted and str(mission.get("mission_id","")) in ["level_1","level_2","level_3"]:
			if float(mission.get("path_length",0.0)) <= 0.0:
				issues.append("正式任务 %s 缺少实际航行路径长度" % mission.get("attempt_id",""))
			if float(mission.get("direct_distance",0.0)) <= 0.0:
				issues.append("正式任务 %s 缺少起终点直线距离" % mission.get("attempt_id",""))
	var target_ids := {}
	for target: Dictionary in targets:
		var event_id := str(target.get("event_id",""))
		if _csv_value_is_missing(event_id):
			issues.append("存在缺少 event_id 的目标异常")
		elif target_ids.has(event_id):
			issues.append("目标异常 event_id 重复：%s" % event_id)
		else:
			target_ids[event_id] = true
		if _csv_value_is_missing(target.get("trigger_gate_index",null)):
			issues.append("目标异常缺少触发门编号：%s" % event_id)
		if (_csv_value_is_missing(target.get("window_observed_ms",null))
				or float(target.get("window_observed_ms",0.0)) <= 0.0):
			issues.append("目标异常没有异常后行为观察窗口：%s" % event_id)
	for waypoint: Dictionary in waypoints:
		if str(waypoint.get("accepted","false")).to_lower()=="true":
			if _csv_value_is_missing(waypoint.get("completion_status",null)):
				issues.append("已接受航点缺少响应窗口结局：%s" % waypoint.get("waypoint_id",""))
			if _csv_value_is_missing(waypoint.get("response_window_observed_ms",null)):
				issues.append("已接受航点缺少响应观察时长：%s" % waypoint.get("waypoint_id",""))
	for rating: Dictionary in ratings:
		var variant := str(rating.get("questionnaire_variant",""))
		if variant=="event_responsibility_100":
			var values := ["responsibility_self","responsibility_partner","responsibility_navigation_system","responsibility_ship_system","responsibility_environment"]
			var has_all := true
			var total := 0
			for column: String in values:
				if _csv_value_is_missing(rating.get(column,null)):
					has_all = false
				else:
					total += int(rating[column])
			if not has_all:
				issues.append("责任分配缺少项目：%s / %s" % [rating.get("participant_id",""),rating.get("event_id","")])
			elif total != 100:
				issues.append("责任分配总和不是 100：%s / %s" % [rating.get("participant_id",""),rating.get("event_id","")])
			var confidence := int(rating.get("attribution_confidence",0))
			if confidence < 1 or confidence > 7:
				issues.append("归因信心不在 1—7 范围：%s / %s" % [rating.get("participant_id",""),rating.get("event_id","")])
			if not ["clear","uncertain","not_noticed"].has(str(rating.get("event_awareness",""))):
				issues.append("异常觉察答案无效：%s / %s" % [rating.get("participant_id",""),rating.get("event_id","")])
			if str(rating.get("screenshot_available","false")).to_lower()!="true":
				issues.append("事件问卷缺少参与者画面：%s / %s" % [rating.get("participant_id",""),rating.get("event_id","")])
		elif variant in ["baseline_state","post_attribution_state"]:
			var state_values := ["partner_state_reliability","partner_state_reliance","navigation_state_reliability","navigation_state_reliance","ship_state_reliability","ship_state_reliance"]
			for column: String in state_values:
				if _csv_value_is_missing(rating.get(column,null)):
					issues.append("状态评价缺少项目 %s：%s / %s" % [column,rating.get("participant_id",""),rating.get("event_id","")])
				elif int(rating[column]) < 1 or int(rating[column]) > 7:
					issues.append("状态评价不在 1—7 范围 %s：%s / %s" % [column,rating.get("participant_id",""),rating.get("event_id","")])
		var rating_event := str(rating.get("event_id",""))
		if str(rating.get("target_event_applicable","false")).to_lower()=="true" and not target_ids.has(rating_event):
			issues.append("目标事件问卷未连接到 target_events.csv：%s" % rating_event)
	var expected_variants := {
		"practice":["training_comprehension"],
		"level_1":["baseline_state"],
		"level_2":["event_responsibility_100","post_attribution_state"],
		"level_3":["event_responsibility_100","post_attribution_state"],
	}
	for mission: Dictionary in missions:
		var mission_id := str(mission.get("mission_id",""))
		if not expected_variants.has(mission_id) or not str(mission.get("aborted_reason","")).is_empty(): continue
		var attempt_id := str(mission.get("attempt_id",""))
		for variant: String in expected_variants[mission_id]:
			var count := 0
			for rating: Dictionary in ratings:
				if (str(rating.get("mission_id",""))==mission_id
						and str(rating.get("attempt_id",""))==attempt_id
						and str(rating.get("questionnaire_variant",""))==variant):
					count += 1
			if count != 2:
				issues.append("任务 %s 的 %s 应有两名参与者记录，实际为 %d" % [attempt_id,variant,count])
	var report := {
		"schema_version":SCHEMA_VERSION,"session_id":session_id,"dyad_id":Game.dyad_id,
		"analysis_policy_version":ANALYSIS_POLICY_VERSION,
		"analysis_policy_notes":[
			"任务成功、超时、碰撞或解体均为有效实验结局，不作为质量失败条件。",
			"目标异常后因解体或自然结算而缩短的观察窗按终止截尾保留，不视为漏记。",
		],
		"generated_utc":Time.get_datetime_string_from_system(true,true),
		"passed":issues.is_empty(),"issue_count":issues.size(),"issues":issues,
		"row_counts":{"missions":missions.size(),"target_events":targets.size(),"waypoints":waypoints.size(),"ratings":ratings.size()},
	}
	var file := FileAccess.open("%s/quality_report.json" % absolute_raw_dir,FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	if not issues.is_empty():
		push_warning("ExperimentLog quality check found %d issue(s); see quality_report.json" % issues.size())


func _read_csv_records(path: String) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.eof_reached(): return records
	var header := file.get_csv_line()
	while not file.eof_reached():
		var values := file.get_csv_line()
		if values.is_empty() or (values.size()==1 and values[0].is_empty()): continue
		var record := {}
		for i: int in range(mini(header.size(),values.size())): record[header[i]] = values[i]
		records.append(record)
	return records


func _csv_value_is_missing(value: Variant) -> bool:
	var text := str(value).strip_edges().to_lower()
	return text.is_empty() or text=="<null>" or text=="null"


func _exit_tree() -> void:
	close_session()


func log_event(type: String, role: String, payload: Dictionary = {}) -> void:
	if not Game.experiment_mode or session_id.is_empty():
		return
	var now := _clock_us()
	var seat := _seat_for_actor(role)
	var participant := Game.participant_id_for_seat(seat) if seat >= 0 else ""
	var row: Array[Variant] = _common_values(participant,role) + [
		now,float(now-_session_start_us)/1000.0,Engine.get_physics_frames(),type,
		seat if seat>=0 else "",JSON.stringify(payload),
	]
	_enqueue({"kind":"line","table":"events","line":_csv_line(row)})


func record_survey(role: String, event_id: String, answers: Dictionary) -> void:
	log_event("survey_submit",role,{"event_id":event_id,"answers":answers})
	record_rating(role,event_id,answers)


func begin_mission_attempt(attempt_number: int) -> String:
	_attempt_number = maxi(attempt_number,1)
	_attempt_id = "%s-attempt-%02d" % [Game.selected_mission_id,_attempt_number]
	_life_number = 1
	_life_id = "%s-life-%02d" % [_attempt_id,_life_number]
	_segment_id = "%s-segment-00" % _attempt_id
	_active_event_id = ""
	_active_fault_type = ""
	_attempt_started_elapsed_ms = session_elapsed_ms()
	_sampling_enabled = true
	log_event("mission_start","system",{"attempt_number":_attempt_number})
	return _attempt_id


func begin_new_life() -> String:
	_life_number += 1
	_life_id = "%s-life-%02d" % [_attempt_id,_life_number]
	return _life_id


func set_segment(index: int) -> void:
	_segment_id = "%s-segment-%02d" % [_attempt_id,maxi(index,0)]


func advance_segment() -> String:
	var current := int(_segment_id.get_slice("-",_segment_id.get_slice_count("-")-1)) if not _segment_id.is_empty() else 0
	set_segment(current+1)
	return _segment_id


func set_active_target_event(event_id: String,fault_type: String) -> void:
	_active_event_id = event_id
	_active_fault_type = fault_type


func clear_active_target_event() -> void:
	_active_event_id = ""
	_active_fault_type = ""


func current_attempt_id() -> String:
	return _attempt_id


func current_life_id() -> String:
	return _life_id


func current_segment_id() -> String:
	return _segment_id


func active_event_id() -> String:
	return _active_event_id


func session_elapsed_ms() -> float:
	if _session_start_us <= 0:
		return 0.0
	return float(Time.get_ticks_usec()-_session_start_us)/1000.0


func record_mission(summary: Dictionary) -> void:
	if session_id.is_empty() or _attempt_id.is_empty():
		return
	# 任务终点时间由主场景在自然结束条件满足的那一刻冻结，排除之后的失败动画与问卷界面。
	var ended_ms := float(summary.get("terminal_session_elapsed_ms",session_elapsed_ms()))
	var wall_time_ms := maxf(0.0,ended_ms-_attempt_started_elapsed_ms)
	var active_ms := float(summary.get("active_gameplay_elapsed",summary.get("elapsed",0.0)))*1000.0
	var survey_pause_ms := float(summary.get("survey_pause_s",0.0))*1000.0
	var other_pause_ms := maxf(0.0,wall_time_ms-active_ms-survey_pause_ms)
	var row := _common_values("","system","","",Game.selected_mission_id) + [
		_attempt_number,_attempt_started_elapsed_ms,ended_ms,str(summary.get("outcome","")),
		bool(summary.get("success",false)),wall_time_ms,active_ms,survey_pause_ms,other_pause_ms,
		float(summary.get("limit",0.0))*1000.0,int(summary.get("hits",0)),float(summary.get("damage_taken",0.0)),
		int(summary.get("revivals",0)),int(summary.get("waypoint_requests",summary.get("waypoints",0))),
		int(summary.get("waypoints",0)),int(summary.get("rejected_waypoints",0)),float(summary.get("hull",Game.hull)),
		summary.get("path_length",null),summary.get("direct_distance",null),summary.get("path_efficiency_ratio",null),
		int(summary.get("severe_heading_deviations",0)),int(summary.get("waypoint_drift_events",0)),
		int(summary.get("ship_shear_events",0)),bool(summary.get("target_event_triggered",false)),
		str(summary.get("aborted_reason","")),
	]
	_enqueue({"kind":"line","table":"missions","line":_csv_line(row)})
	_sampling_enabled = false


func record_target_event(record: Dictionary) -> void:
	var event_id := str(record.get("event_id",_active_event_id))
	var fault := str(record.get("fault_type",record.get("event_type",_active_fault_type)))
	var row := _common_values("","system",event_id,fault,str(record.get("mission_id",Game.selected_mission_id))) + [
		str(record.get("event_type",fault)),record.get("event_time_session_ms",null),record.get("event_time_mission_ms",null),
		record.get("trigger_gate_index",null),record.get("parameter_name",null),record.get("parameter_value",null),
		record.get("ship_x",null),record.get("ship_z",null),record.get("speed_at_event",null),
		record.get("waypoint_distance_at_event",null),record.get("obstacle_distance_at_event",null),
		record.get("navigator_repair_latency_ms",null),record.get("repair_waypoint_angle_deg",null),
		record.get("repair_waypoint_distance",null),record.get("failed_waypoint_requests",0),
		record.get("pilot_response_latency_ms",null),record.get("recovery_time_ms",null),
		record.get("heading_error_at_onset_deg",null),record.get("heading_error_reduction_3s_deg",null),
		record.get("heading_error_reduction_5s_deg",null),
		record.get("max_heading_error_deg_15s",null),record.get("max_cross_track_error_15s",null),
		record.get("time_to_safe_gate_ms",null),record.get("damage_events_15s",0),record.get("hull_loss_15s",0.0),
		bool(record.get("collision_within_15s",false)),bool(record.get("explosion_within_15s",false)),
		bool(record.get("disintegrated_15s",false)),bool(record.get("recovered_within_window",false)),
		record.get("window_observed_ms",0.0),str(record.get("outcome","")),JSON.stringify(record.get("details",{})),
	]
	_enqueue({"kind":"line","table":"target_events","line":_csv_line(row)})


func record_rating(role: String,event_id: String,answers: Dictionary) -> void:
	var seat := _seat_for_actor(role)
	var participant := Game.participant_id_for_seat(seat) if seat >= 0 else str(answers.get("participant_id",""))
	var fault := str(answers.get("target_event_type",""))
	var row := _common_values(participant,role,event_id,fault,str(answers.get("mission_id",Game.selected_mission_id))) + [
		answers.get("instrument_version",null),answers.get("questionnaire_variant",null),answers.get("outcome_success",null),
		answers.get("target_event_applicable",false),answers.get("target_event_exposed",null),
		answers.get("event_awareness",null),
		JSON.stringify(answers.get("trust_block_order",[])),answers.get("partner_state_reliability",null),
		answers.get("partner_state_reliance",null),answers.get("navigation_state_reliability",null),
		answers.get("navigation_state_reliance",null),answers.get("ship_state_reliability",null),
		answers.get("ship_state_reliance",null),answers.get("responsibility_self",null),
		answers.get("responsibility_partner",null),answers.get("responsibility_navigation_system",null),
		answers.get("responsibility_ship_system",null),answers.get("responsibility_environment",null),
		answers.get("attribution_confidence",null),JSON.stringify(answers.get("item_display_order",[])),
		answers.get("reset_count",null),answers.get("screenshot_available",null),answers.get("response_time",null),JSON.stringify(answers),
	]
	_enqueue({"kind":"line","table":"ratings","line":_csv_line(row)})


func record_waypoint(record: Dictionary) -> void:
	var participant := Game.participant_id_for_role("navigator")
	var row := _common_values(participant,"navigator",str(record.get("event_id",_active_event_id)),str(record.get("fault_type",_active_fault_type))) + [
		record.get("waypoint_id",null),record.get("request_sequence",null),record.get("request_session_elapsed_ms",null),
		bool(record.get("accepted",false)),record.get("reason",null),record.get("remaining_cooldown_ms",null),
		record.get("requested_x",null),record.get("requested_z",null),record.get("applied_x",null),record.get("applied_z",null),
		record.get("ship_x",null),record.get("ship_z",null),record.get("initial_heading_error_deg",null),
		record.get("waypoint_distance",null),bool(record.get("drifted",false)),record.get("drift_angle_deg",null),
		record.get("response_window_observed_ms",null),record.get("waypoint_response_latency_ms",null),
		record.get("heading_error_reduction_3s_deg",null),record.get("time_to_alignment_20deg_ms",null),
		bool(record.get("waypoint_override",false)),record.get("completion_status",null),JSON.stringify(record.get("details",{})),
	]
	_enqueue({"kind":"line","table":"waypoints","line":_csv_line(row)})


func sample_frame() -> void:
	if not Game.experiment_mode or session_id.is_empty() or not _sampling_enabled:
		return
	var now := _clock_us()
	var seat_a_pos := Displays.seat_cursor_position(0)
	var seat_b_pos := Displays.seat_cursor_position(1)
	var phase := "finished" if Game.mission_complete else ("dead" if not Game.ship_alive else "running")
	var pilot_participant := Game.participant_id_for_role("pilot")
	var waypoint_distance: Variant = Game.ship_position.distance_to(Game.waypoint) if Game.has_waypoint else null
	var row: Array[Variant] = _common_values(pilot_participant,"pilot") + [
		now,float(now-_session_start_us)/1000.0,Engine.get_physics_frames(),phase,
		Game.participant_id_for_seat(0),Displays.role_name_for_seat(0),
		seat_a_pos.x,seat_a_pos.y,Displays.seat_button_pressed(0),
		Game.participant_id_for_seat(1),Displays.role_name_for_seat(1),
		seat_b_pos.x,seat_b_pos.y,Displays.seat_button_pressed(1),
		Displays.pilot_thrust_axis(),Displays.pilot_turn_axis(),
		Game.ship_position.x,Game.ship_position.z,Game.ship_velocity.x,Game.ship_velocity.z,
		Game.ship_heading,Game.ship_angular_velocity,Game.ship_speed,Game.throttle,
		Game.hull,Game.boundary_proximity,Game.has_waypoint,
		Game.waypoint.x if Game.has_waypoint else "",
		Game.waypoint.z if Game.has_waypoint else "",
		waypoint_distance,_nearest_obstacle_distance(),
	]
	_enqueue({"kind":"line","table":"frames","line":_csv_line(row)})


func _start_writer(absolute_dir: String) -> void:
	_writer_running = true
	_writer_thread = Thread.new()
	var paths := {}
	var headers := {}
	for table: String in TABLE_COLUMNS.keys():
		paths[table] = "%s/%s.csv" % [absolute_dir,table]
		headers[table] = _csv_line(TABLE_COLUMNS[table])
	var error := _writer_thread.start(_writer_loop.bind(paths,headers))
	if error != OK:
		_writer_running = false
		_writer_thread = null
		_writer_error = "cannot start writer thread: %s" % error_string(error)


func _writer_loop(paths: Dictionary,headers: Dictionary) -> void:
	var files := {}
	for table: String in TABLE_COLUMNS.keys():
		var file := FileAccess.open(str(paths[table]),FileAccess.WRITE)
		if file == null:
			_set_writer_error("cannot open %s" % paths[table])
			return
		file.store_string(str(headers[table])+"\r\n")
		files[table] = file
	var stopping := false
	while not stopping:
		_queue_signal.wait()
		var batch: Array[Dictionary] = []
		_queue_mutex.lock()
		batch.assign(_queue)
		_queue.clear()
		for command: Dictionary in batch:
			if command.get("kind","")=="line" and command.get("table","")=="frames":
				_queued_frames = maxi(0,_queued_frames-1)
		_queue_mutex.unlock()
		for command: Dictionary in batch:
			match str(command.get("kind","")):
				"line":
					var table := str(command.get("table",""))
					if files.has(table):
						(files[table] as FileAccess).store_string(str(command.get("line",""))+"\r\n")
				"flush":
					for file: FileAccess in files.values():
						file.flush()
				"stop":
					stopping = true
	for file: FileAccess in files.values():
		file.flush()
		file.close()


func _enqueue(command: Dictionary) -> void:
	if not _writer_running:
		return
	_queue_mutex.lock()
	if command.get("kind","")=="line" and command.get("table","")=="frames":
		if _queued_frames>=MAX_PENDING_FRAMES:
			_dropped_frames += 1
			_queue_mutex.unlock()
			return
		_queued_frames += 1
	var wake := _queue.is_empty()
	_queue.append(command)
	_queue_mutex.unlock()
	if wake:
		_queue_signal.post()


func _set_writer_error(message: String) -> void:
	_queue_mutex.lock()
	_writer_error = message
	_queue_mutex.unlock()


func _clock_us() -> int:
	var now := Time.get_ticks_usec()
	if now<=_last_clock_us:
		now = _last_clock_us+1
	_last_clock_us = now
	return now


func _seat_for_actor(actor: String) -> int:
	match actor:
		"screen_a": return 0
		"screen_b": return 1
		"navigator": return 0 if Displays.primary_role()==Displays.Role.NAVIGATOR else 1
		"pilot": return Displays.pilot_seat()
	return -1


func _common_values(
	participant_id: String,
	role: String,
	event_id: String = "",
	fault_type: String = "",
	mission_id: String = "",
	use_active_event: bool = true
) -> Array[Variant]:
	var resolved_event := event_id
	var resolved_fault := fault_type
	if use_active_event:
		if resolved_event.is_empty():
			resolved_event = _active_event_id
		if resolved_fault.is_empty():
			resolved_fault = _active_fault_type
	return [
		SCHEMA_VERSION,Game.EXPERIMENT_PROTOCOL_VERSION,session_id,Game.dyad_id,participant_id,
		Game.selected_mission_id if mission_id.is_empty() else mission_id,_attempt_id,_life_id,_segment_id,
		resolved_event,role,Game.attribution_condition,resolved_fault,
	]


func _nearest_obstacle_distance() -> Variant:
	if Game.current_sector == null:
		return null
	var nearest := INF
	for body: CelestialBodyData in Game.celestial_bodies:
		if body.kind == CelestialBodyData.Kind.DESTINATION:
			continue
		var gap := Game.ship_position.distance_to(body.world_position)-body.collision_radius-Game.SHIP_RADIUS
		nearest = minf(nearest,gap)
	return nearest if nearest < INF else null


static func _csv_line(values: Array) -> String:
	var encoded := PackedStringArray()
	for value: Variant in values:
		var text := str(value)
		if text.contains("\""):
			text = text.replace("\"","\"\"")
		if text.contains(",") or text.contains("\"") or text.contains("\n") or text.contains("\r"):
			text = "\"%s\"" % text
		encoded.append(text)
	return ",".join(encoded)
