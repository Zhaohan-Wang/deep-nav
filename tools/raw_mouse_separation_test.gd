extends SceneTree
## 回归检查完整链路：原生桥 slot -> RawMice seat -> Displays 独立光标。
## 不能直接调用 Displays._on_raw_mouse_motion，否则会漏掉“两个物理 slot 被映射到
## 同一 seat”这一类真实回归。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var raw := root.get_node("/root/RawMice")
	var displays := root.get_node("/root/Displays")
	await process_frame

	# 模拟桥先完成握手，再分别报告两个物理鼠标。测试前清空单例状态，
	# 避免未来有其他测试复用进程时污染设备映射。
	raw.set("_devices", {})
	raw.set("_mouse_slots_to_seats", {0: 0, 1: 1})
	raw.call("_handle_message", {"type": "ready", "ok": true, "code": 0})
	raw.call("_handle_message", {
		"type": "device",
		"kind": "mouse",
		"connected": true,
		"slot": 0,
		"product": "Regression Mouse A",
	})
	raw.call("_handle_message", {
		"type": "device",
		"kind": "mouse",
		"connected": true,
		"slot": 1,
		"product": "Regression Mouse B",
	})
	assert(raw.connected_mouse_count() == 2, "raw bridge slots must remain two devices")
	assert(bool(displays.get("_raw_mouse_mode")), "two raw mice must enable separated mode")

	displays.show_shared_page()
	displays.call("_center_shared_cursors")
	var start_a: Vector2 = displays.seat_cursor_position(0)
	var start_b: Vector2 = displays.seat_cursor_position(1)

	# slot 0 只能移动 A；如果 RawMice 把两只设备并到 seat 0，下面任一断言都会失败。
	raw.call("_handle_message", {"type": "motion", "slot": 0, "dx": 41.0, "dy": -7.0})
	var after_a: Vector2 = displays.seat_cursor_position(0)
	var after_b: Vector2 = displays.seat_cursor_position(1)
	assert(after_a.is_equal_approx(start_a + Vector2(41.0, -7.0)), "physical slot 0 did not drive seat A")
	assert(after_b.is_equal_approx(start_b), "physical slot 0 leaked into seat B")

	# slot 1 必须只移动 B，且两只可见光标的位置与各自席位状态一致。
	raw.call("_handle_message", {"type": "motion", "slot": 1, "dx": -23.0, "dy": 19.0})
	var final_a: Vector2 = displays.seat_cursor_position(0)
	var final_b: Vector2 = displays.seat_cursor_position(1)
	assert(final_a.is_equal_approx(after_a), "physical slot 1 leaked into seat A")
	assert(final_b.is_equal_approx(start_b + Vector2(-23.0, 19.0)), "physical slot 1 did not drive seat B")
	var cursor_a := displays.get("_cursor_a") as VirtualCursor
	var cursor_b := displays.get("_cursor_b") as VirtualCursor
	assert(cursor_a.visible and cursor_b.visible, "both shared-page cursors must remain visible")
	assert(cursor_a.position.is_equal_approx(final_a), "seat A cursor rendering is detached from seat A state")
	assert(cursor_b.position.is_equal_approx(final_b), "seat B cursor rendering is detached from seat B state")
	assert(not cursor_a.position.is_equal_approx(cursor_b.position), "two physical mice collapsed onto one cursor")

	print("RAW_MOUSE_SEPARATION_OK slots=2 seats=2 cursors=independent")
	quit(0)
