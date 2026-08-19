extends SceneTree
## 验证“设备跟屏幕、角色可交换”：换岗只换页面，不交换两个输入席位。
## 同时验证光标方案：席位 A 光标只有一份且不透明（画在事件所在的根画布上），
## 席位 B 在根画布上保持同伴透明度、在副屏本地不透明；系统光标常驻隐藏。


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var main := packed.instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	var nav_slot := main.get("_nav_slot") as Control
	var pilot_slot := main.get("_pilot_slot") as Control
	var displays := root.get_node("/root/Displays")
	assert(displays.primary_role() == displays.Role.NAVIGATOR, "default primary role must be navigator")
	var cursor_a := displays.get("_cursor_a") as VirtualCursor
	var cursor_b := displays.get("_cursor_b") as VirtualCursor
	var secondary_cursor := displays.get("_secondary_cursor") as VirtualCursor
	var base_layer := displays.get("_cursor_layer") as CanvasLayer
	assert(cursor_a != null and cursor_b != null and secondary_cursor != null, "seat cursors must exist")
	# headless DisplayServer 不支持 mouse_mode，仅在真实显示环境下校验隐藏铁律。
	if DisplayServer.get_name() != "headless":
		assert(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, "system cursor must stay hidden for the whole app")
	assert(root.gui_embed_subwindows, "root must embed subwindows so hover follows event coordinates")
	assert(nav_slot.get_viewport() == root, "navigator must start on primary seat")
	assert(pilot_slot.get_viewport() == displays.secondary_window(), "pilot must start on secondary seat")

	# 分辨率复刻：任务 UI 的历史设计空间是 960×540（老版本一块 1920×1080 屏并排两个
	# 16:9 视图、旧副窗口硬编码 960×1080）。任务页两个窗口都必须按 960×540 渲染再放大；
	# 共用页恢复 1920×1080。两个窗口的拉伸模式必须始终一致。
	var secondary := displays.secondary_window() as Window
	var design_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	)
	var role_size := design_size / 2
	assert(secondary.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS, "secondary window must stretch canvas items like the root window")
	assert(secondary.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "secondary window must use expand aspect like the root window")
	# 主场景启动即进入任务页（双窗口模式）：两个窗口都应处于 960×540 任务设计空间。
	assert(root.content_scale_size == role_size, "role pages must render the root window at the historical 960x540 view space")
	assert(secondary.content_scale_size == role_size, "role pages must render the secondary window at the historical 960x540 view space")

	# 透明度方案：A 唯一且不透明；B 底光标半透明（进镜像），副屏本地 B 不透明。
	assert(is_equal_approx(cursor_a.modulate.a, 1.0), "seat-A cursor must be the single opaque instance on the root canvas")
	assert(is_equal_approx(cursor_b.modulate.a, 0.42), "mirrored screen-B base cursor must stay translucent")
	assert(is_equal_approx(secondary_cursor.modulate.a, 1.0), "screen B must have its own opaque cursor")

	# 共用页面：底光标层可见；副屏本地不透明 B 光标可见。
	displays.show_shared_page()
	await process_frame
	assert(base_layer.visible, "shared page must draw translucent base cursors into the mirror")
	assert(cursor_a.visible and cursor_b.visible, "shared page must draw both base cursors")
	assert(secondary_cursor.visible, "shared page must draw the opaque seat-B cursor on the secondary window")
	assert(cursor_a.role_name == "屏幕 A", "shared page must identify fixed screen A, not a role")
	assert(cursor_b.role_name == "屏幕 B", "shared page must identify fixed screen B, not a role")
	assert(root.content_scale_size == design_size, "shared pages must restore the full 1920x1080 design space on the root window")
	assert(secondary.content_scale_size == design_size, "shared pages must restore the full 1920x1080 design space on the secondary window")

	# 任务页面：没有镜像，根画布仍画席位 A 光标，但席位 B 底光标关闭。
	displays.show_role_page(pilot_slot)
	await process_frame
	assert(base_layer.visible, "role pages still draw the seat-A cursor on the root canvas")
	assert(not cursor_b.visible, "role pages must not draw the translucent seat-B base cursor")
	assert(root.content_scale_size == role_size, "returning to role pages must switch both windows back to 960x540")
	assert(secondary.content_scale_size == role_size, "returning to role pages must switch both windows back to 960x540")

	displays.swap_roles()
	await process_frame
	assert(displays.primary_role() == displays.Role.PILOT, "primary role did not swap")
	assert(pilot_slot.get_viewport() == root, "pilot page did not move to primary seat")
	assert(nav_slot.get_viewport() == displays.secondary_window(), "navigator page did not move to secondary seat")
	# 输入设备槽位不会随岗位交换；这里用公开的驾驶席位映射验证。
	assert(displays.pilot_seat() == 0, "pilot controls must follow role to primary seat")
	displays.swap_roles()
	await process_frame
	assert(displays.pilot_seat() == 1, "pilot controls must return to secondary seat")
	print("DISPLAY_SEAT_ROLE_OK")
	quit(0)
