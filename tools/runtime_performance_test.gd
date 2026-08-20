extends SceneTree

const MISSIONS: Array[String] = ["practice", "level_1", "level_2", "level_3", "level_4"]
const TARGET_FPS := 120.0
const MIN_MEAN_FPS := 115.0
const MAX_P95_FRAME_MS := 16.67
const MAX_BELOW_60_PERCENT := 2.0
const MAX_SEVERE_PERCENT := 1.0
const MAX_MEDIAN_DRAW_CALLS := 500.0
const MAX_MEDIAN_OBJECTS := 1100.0
const WARMUP_FRAMES := 60
const WARMUP_LIMIT_MS := 1000
const SAMPLE_FRAMES := 180
const SAMPLE_LIMIT_MS := 2500
const MIN_SAMPLE_FRAMES := 12


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node_or_null("Game")
	var packed_scene := load("res://scenes/main.tscn") as PackedScene
	if game == null or packed_scene == null:
		_fail_and_quit("无法加载 Game 或主场景")
		return

	game.set("fullscreen_dual_display", false)
	game.set("experiment_mode", false)
	game.set("debug_mode", false)
	root.size = Vector2i(1920, 1080)
	var failures: Array[String] = []

	for mission in MISSIONS:
		game.call("select_mission", mission)
		var scene := packed_scene.instantiate()
		root.add_child(scene)
		await _wait_bounded(WARMUP_FRAMES, WARMUP_LIMIT_MS)

		var frame_ms: Array[float] = []
		var draw_calls: Array[float] = []
		var objects: Array[float] = []
		var sample_started := Time.get_ticks_msec()
		var previous_tick := Time.get_ticks_usec()
		while frame_ms.size() < SAMPLE_FRAMES and Time.get_ticks_msec() - sample_started < SAMPLE_LIMIT_MS:
			await process_frame
			var current_tick := Time.get_ticks_usec()
			frame_ms.append(float(current_tick - previous_tick) / 1000.0)
			previous_tick = current_tick
			draw_calls.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			objects.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))

		var result := _evaluate_mission(mission, frame_ms, draw_calls, objects)
		print(result.summary)
		failures.append_array(result.failures)

		scene.queue_free()
		await _wait_bounded(4, 600)

	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		print("RUNTIME_PERFORMANCE_FAILED count=%d" % failures.size())
		quit(1)
		return

	print("RUNTIME_PERFORMANCE_OK missions=%d target_fps=%d" % [MISSIONS.size(), int(TARGET_FPS)])
	quit(0)


func _wait_bounded(frame_limit: int, time_limit_ms: int) -> void:
	var started := Time.get_ticks_msec()
	var frames := 0
	while frames < frame_limit and Time.get_ticks_msec() - started < time_limit_ms:
		await process_frame
		frames += 1


func _evaluate_mission(
	mission: String,
	frame_ms: Array[float],
	draw_calls: Array[float],
	objects: Array[float]
) -> Dictionary:
	var failures: Array[String] = []
	if frame_ms.size() < MIN_SAMPLE_FRAMES:
		failures.append("%s 只采到 %d 帧，场景过慢或未正常推进" % [mission, frame_ms.size()])
	if frame_ms.is_empty():
		return {
			"summary": "PERF %s samples=0" % mission,
			"failures": failures,
		}

	var mean_frame_ms := _mean(frame_ms)
	var mean_fps := 1000.0 / maxf(mean_frame_ms, 0.01)
	var below_60 := _over_ratio(frame_ms, 16.67)
	var severe := _over_ratio(frame_ms, 33.33)
	frame_ms.sort()
	draw_calls.sort()
	objects.sort()
	var p95_frame_ms := _percentile(frame_ms, 0.95)
	var median_draw_calls := _percentile(draw_calls, 0.5)
	var median_objects := _percentile(objects, 0.5)

	if mean_fps < MIN_MEAN_FPS:
		failures.append("%s 平均帧率 %.1f，低于 %.0f FPS 下限" % [mission, mean_fps, MIN_MEAN_FPS])
	if p95_frame_ms > MAX_P95_FRAME_MS:
		failures.append("%s P95 帧耗时 %.2fms，超过 %.2fms" % [mission, p95_frame_ms, MAX_P95_FRAME_MS])
	if below_60 > MAX_BELOW_60_PERCENT:
		failures.append("%s 低于 60 FPS 的帧占 %.1f%%，超过 %.1f%%" % [mission, below_60, MAX_BELOW_60_PERCENT])
	if severe > MAX_SEVERE_PERCENT:
		failures.append("%s 严重卡顿帧占 %.1f%%，超过 %.1f%%" % [mission, severe, MAX_SEVERE_PERCENT])
	if median_draw_calls > MAX_MEDIAN_DRAW_CALLS:
		failures.append("%s 绘制调用中位数 %.0f，超过 %.0f" % [mission, median_draw_calls, MAX_MEDIAN_DRAW_CALLS])
	if median_objects > MAX_MEDIAN_OBJECTS:
		failures.append("%s 渲染对象中位数 %.0f，超过 %.0f" % [mission, median_objects, MAX_MEDIAN_OBJECTS])

	return {
		"summary": "PERF %s fps=%.1f p95=%.2fms below60=%.1f%% severe=%.1f%% draws=%.0f objects=%.0f samples=%d" % [
			mission,
			mean_fps,
			p95_frame_ms,
			below_60,
			severe,
			median_draw_calls,
			median_objects,
			frame_ms.size(),
		],
		"failures": failures,
	}


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for value in values:
		total += value
	return total / maxf(float(values.size()), 1.0)


func _percentile(values: Array[float], ratio: float) -> float:
	if values.is_empty():
		return 0.0
	var index := clampi(int(floor(float(values.size() - 1) * ratio)), 0, values.size() - 1)
	return values[index]


func _over_ratio(values: Array[float], budget_ms: float) -> float:
	var count := 0
	for value in values:
		if value > budget_ms:
			count += 1
	return float(count) * 100.0 / maxf(float(values.size()), 1.0)


func _fail_and_quit(message: String) -> void:
	push_error(message)
	print("RUNTIME_PERFORMANCE_FAILED count=1")
	quit(1)
