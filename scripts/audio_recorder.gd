extends Node
## 单设备整场原始录音。录音与磁盘写入位于独立 macOS helper，不占用游戏帧。

const HELPER_PATH := "res://native/macos/bin/DeepNavAudioRecorder.app/Contents/MacOS/deepnav-audio-recorder"

var _pid := -1
var _audio_relative_path := ""
var _metadata_relative_path := ""


func start_session(raw_dir: String, session_id: String, session_start_us: int) -> bool:
	stop_session()
	if DisplayServer.get_name()=="headless" or OS.get_name()!="macOS":
		return false
	var helper := _helper_executable()
	if not FileAccess.file_exists(helper):
		push_warning("AudioRecorder: helper missing; run tools/build_macos_audio_recorder.sh")
		return false
	var audio_dir := "%s/audio" % raw_dir
	var absolute_audio_dir := ProjectSettings.globalize_path(audio_dir)
	if DirAccess.make_dir_recursive_absolute(absolute_audio_dir)!=OK:
		push_warning("AudioRecorder: cannot create audio directory")
		return false
	_audio_relative_path = "%s/session.caf" % audio_dir
	_metadata_relative_path = "%s/audio_metadata.json" % audio_dir
	var arguments := PackedStringArray([
		ProjectSettings.globalize_path(_audio_relative_path),
		ProjectSettings.globalize_path(_metadata_relative_path),
		session_id,
		str(session_start_us),
	])
	_pid = OS.create_process(helper,arguments)
	if _pid<=0:
		_pid = -1
		_audio_relative_path = ""
		_metadata_relative_path = ""
		push_warning("AudioRecorder: failed to start helper")
		return false
	return true


func _helper_executable() -> String:
	if not OS.has_feature("editor"):
		var bundled := OS.get_executable_path().get_base_dir().get_base_dir().path_join(
			"Helpers/DeepNavAudioRecorder.app/Contents/MacOS/deepnav-audio-recorder"
		)
		if FileAccess.file_exists(bundled):
			return bundled
	return ProjectSettings.globalize_path(HELPER_PATH)


func stop_session() -> void:
	if _pid>0 and OS.is_process_running(_pid):
		OS.execute("/bin/kill",PackedStringArray(["-TERM",str(_pid)]))
		# 停止发生在问卷提交或应用退出之后；短暂等待保证 CAF 文件头和元数据已落盘。
		var deadline := Time.get_ticks_msec()+2000
		while OS.is_process_running(_pid) and Time.get_ticks_msec()<deadline:
			OS.delay_msec(20)
		if OS.is_process_running(_pid):
			OS.execute("/bin/kill",PackedStringArray(["-KILL",str(_pid)]))
	_pid = -1


func is_recording() -> bool:
	return _pid>0 and OS.is_process_running(_pid)


func audio_path() -> String:
	return _audio_relative_path


func metadata_path() -> String:
	return _metadata_relative_path


func _exit_tree() -> void:
	stop_session()
