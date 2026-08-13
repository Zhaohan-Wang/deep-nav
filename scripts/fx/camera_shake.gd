class_name CameraShake
extends RefCounted
## 3D 震屏，思路对齐 dyadic-force 的 SpringCamera2D：强度衰减 + 每帧随机位移。

var strength: float = 0.0
var decay: float = 9.5
var max_offset: float = 1.35


func add(amount: float) -> void:
	strength = minf(max_offset, strength + amount)


func tick(delta: float) -> Vector3:
	strength = move_toward(strength, 0.0, decay * delta)
	if strength < 0.012:
		return Vector3.ZERO
	return Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * strength
