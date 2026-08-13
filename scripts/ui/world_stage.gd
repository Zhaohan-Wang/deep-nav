extends AspectRatioContainer
## 用当前宽度锁定 16:9 高度，让左右两个三维视窗一样大。


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_lock_height()


func _lock_height() -> void:
	# 分栏宽度变化时，把高度锁成同一套 16:9，左右视窗才会一样大。
	var target: float = size.x / maxf(ratio, 0.01)
	if absf(custom_minimum_size.y - target) > 0.5:
		custom_minimum_size.y = target
