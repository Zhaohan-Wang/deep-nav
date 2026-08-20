class_name ShipTurningModel
extends RefCounted
## 航向角速度控制：起转和收转都保留可感知的船体惯性，反打仍能主动修正。

const MAX_YAW_RATE: float = 1.45
const TURN_RESPONSE_ACCEL: float = 3.4
const TURN_BRAKE_ACCEL: float = 2.8
const COUNTER_TURN_ACCEL: float = 7.2
const TURN_INPUT_DEADZONE: float = 0.04


## 每个物理帧把当前角速度推向玩家输入对应的目标角速度。
## 反向输入优先消掉原旋转，再建立新方向；松手保留明显但可控的转动长尾。
static func step_yaw_rate(current_rate: float, turn_input: float, delta: float) -> float:
	var input := clampf(turn_input, -1.0, 1.0)
	if absf(input) < TURN_INPUT_DEADZONE:
		input = 0.0
	var target_rate := input * MAX_YAW_RATE
	var accel := TURN_RESPONSE_ACCEL
	if is_zero_approx(target_rate):
		accel = TURN_BRAKE_ACCEL
	elif not is_zero_approx(current_rate) and signf(target_rate) != signf(current_rate):
		accel = COUNTER_TURN_ACCEL
	elif absf(target_rate) < absf(current_rate):
		accel = TURN_BRAKE_ACCEL
	return move_toward(current_rate, target_rate, accel * maxf(delta, 0.0))
