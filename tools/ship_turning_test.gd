extends SceneTree
## 航向手感预算：起转与收转都有明显惯性，反打仍必须能主动消掉残余角速度。

const Turning = preload("res://scripts/ship_turning_model.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var delta := 1.0 / 60.0
	var yaw_rate := 0.0
	for i: int in range(27):
		yaw_rate = Turning.step_yaw_rate(yaw_rate, 1.0, delta)
	assert(yaw_rate >= Turning.MAX_YAW_RATE - 0.001,
		"full turn input must reach maximum yaw rate within 0.45 s")

	var stop_time := 0.0
	var residual_angle := 0.0
	while absf(yaw_rate) > 0.0001 and stop_time < 1.2:
		yaw_rate = Turning.step_yaw_rate(yaw_rate, 0.0, delta)
		residual_angle += absf(yaw_rate) * delta
		stop_time += delta
	assert(stop_time >= 0.48 and stop_time <= 0.58,
		"released turn input should keep a visible 0.48-0.58 s tail (actual %.3f s)" % stop_time)
	assert(rad_to_deg(residual_angle) >= 19.0 and rad_to_deg(residual_angle) <= 24.0,
		"released turn input should retain a visible 19-24 degree coast (%.2f deg)" % rad_to_deg(residual_angle))

	yaw_rate = Turning.MAX_YAW_RATE
	for i: int in range(13):
		yaw_rate = Turning.step_yaw_rate(yaw_rate, -1.0, delta)
	assert(yaw_rate < 0.0,
		"counter-steer must cancel the old turn direction within 0.22 s")

	assert(is_zero_approx(Turning.step_yaw_rate(0.0, 0.02, delta)),
		"tiny turn input inside the deadzone must not create drift")
	print("SHIP_TURNING_OK stop_s=%.3f residual_deg=%.2f counter_rate=%.3f" % [
		stop_time, rad_to_deg(residual_angle), yaw_rate])
	quit(0)
