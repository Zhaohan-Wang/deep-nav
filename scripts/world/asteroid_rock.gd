extends MeshInstance3D
## 缓慢翻滚的 3D 小行星，用固定朝向而不是广告牌。

var tumble: Vector3 = Vector3.ZERO


func _process(delta: float) -> void:
	rotate_object_local(Vector3.RIGHT, tumble.x * delta)
	rotate_object_local(Vector3.UP, tumble.y * delta)
	rotate_object_local(Vector3.FORWARD, tumble.z * delta)
