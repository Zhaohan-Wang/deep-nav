extends SceneTree
## 任务开始确认页（角色认领）端到端验证 + 截图：
## 用带席位设备号的合成点击驱动认领流程，验证“哪块屏点的就归哪块屏”、
## 抢占拒绝、取消认领、认领转移、关闭按钮，以及开始按钮的解锁条件。

const OUT_OPEN := "res://artifacts/runtime/role_claim_open.png"
const OUT_DONE := "res://artifacts/runtime/role_claim_done.png"
const SEAT_NONE := -1
const SEAT_A := 0
const SEAT_B := 1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game := root.get_node("/root/Game")
	game.set("experiment_mode", false)
	game.set("debug_mode", false)
	var displays := root.get_node("/root/Displays")
	var page := (load("res://scenes/level_select.tscn") as PackedScene).instantiate()
	root.add_child(page)
	for i: int in range(8):
		await process_frame
	page.call("_open_confirm")
	for i: int in range(4):
		await process_frame
	assert(page.get("_confirm_layer") != null, "confirm layer must open")
	var cards: Array = page.get("_claim_cards")
	assert(cards.size() == 2, "confirm must build two role cards")
	var device_a: int = displays.PRIMARY_SEAT_POINTER_DEVICE
	var device_b: int = displays.SECONDARY_SEAT_POINTER_DEVICE
	var can_capture := DisplayServer.get_name() != "headless"
	if can_capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/runtime"))
		_save(OUT_OPEN)

	# 屏幕 A 认领领航员。
	await _click(cards[0], device_a)
	assert(_claims(page) == [SEAT_A, SEAT_NONE], "screen A click must claim navigator for screen A")
	# 屏幕 B 试图抢已被认领的领航员：必须被拒绝。
	await _click(cards[0], device_b)
	assert(_claims(page) == [SEAT_A, SEAT_NONE], "claimed role must not be stolen by the other screen")
	# 屏幕 B 认领驾驶员，凑齐两个角色，开始按钮解锁。
	await _click(cards[1], device_b)
	assert(_claims(page) == [SEAT_A, SEAT_B], "screen B click must claim pilot for screen B")
	assert(not (page.get("_start_button") as Button).disabled, "start must unlock once both roles are claimed")
	if can_capture:
		_save(OUT_DONE)

	# 再点自己的卡片可取消认领，开始按钮重新锁定。
	await _click(cards[0], device_a)
	assert(_claims(page) == [SEAT_NONE, SEAT_B], "clicking own claim must release it")
	assert((page.get("_start_button") as Button).disabled, "start must lock again when a claim is released")
	# 同屏改点另一张空卡：旧认领自动转移，不会出现一屏双角色。
	await _click(cards[1], device_b)
	assert(_claims(page) == [SEAT_NONE, SEAT_NONE], "screen B second click must release its claim")
	await _click(cards[0], device_b)
	await _click(cards[1], device_b)
	assert(_claims(page) == [SEAT_NONE, SEAT_B], "claiming another card must move the seat's single claim")

	# 关闭按钮：关掉后重开，认领状态清零。
	page.call("_close_confirm")
	await process_frame
	assert(page.get("_confirm_layer") == null, "close must dismiss the confirm layer")
	page.call("_open_confirm")
	for i: int in range(2):
		await process_frame
	assert(_claims(page) == [SEAT_NONE, SEAT_NONE], "reopening must reset all claims")

	# 认领结果 → 屏幕角色分配的接口。
	displays.set_primary_role(displays.Role.PILOT)
	assert(displays.primary_role() == displays.Role.PILOT, "set_primary_role must assign the primary screen role")
	displays.set_primary_role(displays.Role.NAVIGATOR)
	assert(displays.primary_role() == displays.Role.NAVIGATOR, "set_primary_role must restore navigator")
	print("ROLE_CLAIM_OK")
	quit(0)


func _claims(page: Node) -> Array:
	var claims: Array = page.get("_role_claims")
	return [claims[0], claims[1]]


func _click(card: Control, device: int) -> void:
	var pos := card.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.device = device
		event.position = pos
		event.global_position = pos
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await process_frame


func _save(path: String) -> void:
	var image := root.get_texture().get_image()
	if image.save_png(path) != OK:
		push_error("ROLE_CLAIM_CAPTURE_FAILED %s" % path)
