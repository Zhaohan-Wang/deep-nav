extends Node
## 仅实验模式写盘；原始事件只追加，不覆盖。调试模式不会混入正式数据。

const ROOT_DIR: String = "user://experiments"

var session_id: String = ""
var session_dir: String = ""
var _events: FileAccess
var _frames: FileAccess
var _frame_since_flush: int = 0

func begin_session() -> void:
	if not Game.experiment_mode or not session_id.is_empty(): return
	if ensure_root().is_empty():
		return
	var stamp := Time.get_datetime_string_from_system(true, true).replace(":", "-")
	session_id = "deepnav_%s" % stamp
	session_dir = "%s/%s/raw" % [ROOT_DIR,session_id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(session_dir))
	_events = FileAccess.open("%s/events.csv" % session_dir, FileAccess.WRITE)
	_events.store_csv_line(PackedStringArray(["session_id", "monotonic_us", "mission_id", "event_type", "role", "payload_json"]))
	_frames = FileAccess.open("%s/frames.csv" % session_dir, FileAccess.WRITE)
	_frames.store_csv_line(PackedStringArray(["session_id","monotonic_us","mission_id","x","z","heading","speed","throttle","turn_left","turn_right","hull","waypoint_x","waypoint_z"]))
	var session := FileAccess.open("%s/session.csv" % session_dir, FileAccess.WRITE)
	session.store_csv_line(PackedStringArray(["session_id","started_utc","debug_mode","godot_version"]))
	session.store_csv_line(PackedStringArray([session_id,Time.get_datetime_string_from_system(true,true),str(Game.debug_mode),Engine.get_version_info().get("string","")]))
	log_event("session_start", "system", {"debug_mode": Game.debug_mode})


## 与 Dyadic Force 一致：标题页先确保根目录存在，再交给 OS 打开。
func ensure_root() -> String:
	var absolute := ProjectSettings.globalize_path(ROOT_DIR)
	if DirAccess.dir_exists_absolute(absolute):
		return ROOT_DIR
	if DirAccess.make_dir_recursive_absolute(absolute) != OK:
		return ""
	return ROOT_DIR


func close_session() -> void:
	if _events != null:
		_events.flush()
		_events.close()
		_events = null
	if _frames != null:
		_frames.flush()
		_frames.close()
		_frames = null
	session_id = ""
	session_dir = ""
	_frame_since_flush = 0


func _exit_tree() -> void:
	close_session()

func log_event(type: String, role: String, payload: Dictionary = {}) -> void:
	if not Game.experiment_mode: return
	if session_id.is_empty(): begin_session()
	if _events == null: return
	_events.store_csv_line(PackedStringArray([
		session_id, str(Time.get_ticks_usec()), Game.selected_mission_id, type, role, JSON.stringify(payload)
	]))
	_events.flush()

func record_survey(role: String, event_id: String, answers: Dictionary) -> void:
	log_event("survey_submit", role, {"event_id": event_id, "answers": answers})

func sample_frame() -> void:
	if not Game.experiment_mode or _frames == null: return
	_frames.store_csv_line(PackedStringArray([
		session_id,str(Time.get_ticks_usec()),Game.selected_mission_id,str(Game.ship_position.x),str(Game.ship_position.z),
		str(Game.ship_heading),str(Game.ship_speed),str(Game.throttle),str(maxf(Displays.pilot_turn_axis(),0.0)),
		str(maxf(-Displays.pilot_turn_axis(),0.0)),str(Game.hull),str(Game.waypoint.x if Game.has_waypoint else NAN),
		str(Game.waypoint.z if Game.has_waypoint else NAN)
	]))
	_frame_since_flush += 1
	if _frame_since_flush >= 60:
		_frames.flush(); _frame_since_flush = 0
