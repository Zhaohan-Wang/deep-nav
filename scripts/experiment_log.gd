extends Node
## 实验原始数据只追加。主线程只构造短字符串并入队；专用 worker 独占 FileAccess。

const ROOT_DIR := "user://experiments"
const SCHEMA_VERSION := "2.0.0"
const FLUSH_INTERVAL_S := 1.0
const MAX_PENDING_FRAMES := 6000

const SESSION_COLUMNS: Array[String] = [
	"schema_version","protocol_version","session_id","dyad_id","participant_a","participant_b",
	"screen_a_participant","screen_b_participant","attribution_condition","started_utc",
	"godot_version","platform","screen_a_mouse","screen_b_mouse","screen_a_keyboard","screen_b_keyboard",
	"audio_requested",
]
const EVENT_COLUMNS: Array[String] = [
	"schema_version","session_id","monotonic_us","session_elapsed_ms","physics_frame",
	"mission_id","event_type","participant_id","seat","role","payload_json",
]
const FRAME_COLUMNS: Array[String] = [
	"schema_version","session_id","monotonic_us","session_elapsed_ms","physics_frame","mission_id","phase",
	"screen_a_participant","screen_a_role","screen_a_cursor_x","screen_a_cursor_y","screen_a_left_down",
	"screen_b_participant","screen_b_role","screen_b_cursor_x","screen_b_cursor_y","screen_b_left_down",
	"pilot_thrust_raw","pilot_turn_raw","ship_x","ship_z","velocity_x","velocity_z",
	"heading_rad","angular_velocity_rad_s","speed","throttle","hull","boundary_proximity",
	"has_waypoint","waypoint_x","waypoint_z",
]

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
	var audio_started := AudioRecorder.start_session(session_dir,session_id,_session_start_us)
	var session_values: Array[Variant] = [
		SCHEMA_VERSION,Game.EXPERIMENT_PROTOCOL_VERSION,session_id,Game.dyad_id,
		Game.participant_a,Game.participant_b,Game.participant_id_for_seat(0),
		Game.participant_id_for_seat(1),Game.attribution_condition,
		Time.get_datetime_string_from_system(true,true),
		str(Engine.get_version_info().get("string","")),OS.get_name(),
		RawMice.device_name(0),RawMice.device_name(1),
		RawMice.keyboard_name(0),RawMice.keyboard_name(1),audio_started,
	]
	_enqueue({"kind":"line","table":"session","line":_csv_line(session_values)})
	log_event("session_start","system",{
		"protocol_version":Game.EXPERIMENT_PROTOCOL_VERSION,
		"condition":Game.attribution_condition,
		"participant_a_seat":Game.participant_a_seat,
		"audio_started":audio_started,
		"audio_file":AudioRecorder.audio_path(),
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
		"audio_active":AudioRecorder.is_recording(),
	})
	AudioRecorder.stop_session()
	_enqueue({"kind":"stop"})
	if _writer_thread != null:
		_writer_thread.wait_to_finish()
		_writer_thread = null
	_writer_running = false
	session_id = ""
	session_dir = ""
	_session_start_us = 0
	_last_clock_us = 0
	_flush_elapsed = 0.0
	_queue_mutex.lock()
	_queue.clear()
	_queued_frames = 0
	_queue_mutex.unlock()


func _exit_tree() -> void:
	close_session()


func log_event(type: String, role: String, payload: Dictionary = {}) -> void:
	if not Game.experiment_mode or session_id.is_empty():
		return
	var now := _clock_us()
	var seat := _seat_for_actor(role)
	var participant := Game.participant_id_for_seat(seat) if seat >= 0 else ""
	var row: Array[Variant] = [
		SCHEMA_VERSION,session_id,now,float(now-_session_start_us)/1000.0,
		Engine.get_physics_frames(),Game.selected_mission_id,type,participant,
		seat if seat>=0 else "",role,JSON.stringify(payload),
	]
	_enqueue({"kind":"line","table":"events","line":_csv_line(row)})


func record_survey(role: String, event_id: String, answers: Dictionary) -> void:
	log_event("survey_submit",role,{"event_id":event_id,"answers":answers})


func sample_frame() -> void:
	if not Game.experiment_mode or session_id.is_empty():
		return
	var now := _clock_us()
	var seat_a_pos := Displays.seat_cursor_position(0)
	var seat_b_pos := Displays.seat_cursor_position(1)
	var phase := "finished" if Game.mission_complete else ("dead" if not Game.ship_alive else "running")
	var row: Array[Variant] = [
		SCHEMA_VERSION,session_id,now,float(now-_session_start_us)/1000.0,
		Engine.get_physics_frames(),Game.selected_mission_id,phase,
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
	]
	_enqueue({"kind":"line","table":"frames","line":_csv_line(row)})


func _start_writer(absolute_dir: String) -> void:
	_writer_running = true
	_writer_thread = Thread.new()
	var paths := {
		"session":"%s/session.csv" % absolute_dir,
		"events":"%s/events.csv" % absolute_dir,
		"frames":"%s/frames.csv" % absolute_dir,
	}
	var headers := {
		"session":_csv_line(SESSION_COLUMNS),
		"events":_csv_line(EVENT_COLUMNS),
		"frames":_csv_line(FRAME_COLUMNS),
	}
	var error := _writer_thread.start(_writer_loop.bind(paths,headers))
	if error != OK:
		_writer_running = false
		_writer_thread = null
		_writer_error = "cannot start writer thread: %s" % error_string(error)


func _writer_loop(paths: Dictionary,headers: Dictionary) -> void:
	var files := {}
	for table: String in ["session","events","frames"]:
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
