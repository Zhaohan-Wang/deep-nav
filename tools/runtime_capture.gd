extends SceneTree
## 真实渲染截图：以正式分屏模式启动主场景，等待材质/子视口稳定后保存 PNG。

const OUT_START := "res://artifacts/runtime/gameplay_split_start.png"
const OUT_WAYPOINT_COOLDOWN := "res://artifacts/runtime/gameplay_waypoint_cooldown.png"
const OUT_CONTROL_ARROWS := "res://artifacts/runtime/gameplay_control_arrows.png"
const OUT_TITLE := "res://artifacts/runtime/title_screen.png"
const OUT_FIRST_RUN := "res://artifacts/runtime/first_run_settings.png"
const OUT_THANK_YOU := "res://artifacts/runtime/thank_you.png"
const OUT_LEVEL_SELECT := "res://artifacts/runtime/level_select_experiment.png"
const OUT_HULL_DAMAGE := "res://artifacts/runtime/gameplay_hull_ring_damage.png"
const OUT_MID := "res://artifacts/runtime/gameplay_split_mid.png"
const OUT_PLANET_APPROACH := "res://artifacts/runtime/gameplay_planet_approach.png"
const OUT_BOUNDARY := "res://artifacts/runtime/gameplay_split_boundary.png"
const OUT_LEVEL3_CORRIDOR := "res://artifacts/runtime/gameplay_level3_corridor.png"
const OUT_LEVEL3_BLOCKER := "res://artifacts/runtime/gameplay_level3_blocker.png"
const OUT_NOTICE_EXPLICIT := "res://artifacts/runtime/experiment_notice_explicit.png"
const OUT_NOTICE_AMBIGUOUS := "res://artifacts/runtime/experiment_notice_ambiguous.png"
const OUT_LEVEL4_NOTICE_EXPLICIT := "res://artifacts/runtime/experiment_notice_level4_explicit.png"
const OUT_LEVEL4_NOTICE_AMBIGUOUS := "res://artifacts/runtime/experiment_notice_level4_ambiguous.png"
const OUT_EXPLOSION := "res://artifacts/runtime/gameplay_explosion.png"
const OUT_RESULT := "res://artifacts/runtime/mission_result.png"
const OUT_RESULT_SUCCESS := "res://artifacts/runtime/mission_result_success.png"
const OUT_SUMMARY := "res://artifacts/runtime/mission_summary.png"
const OUT_ATTRIBUTION := "res://artifacts/runtime/mission_attribution.png"
const OUT_SURVEY_1 := "res://artifacts/runtime/survey_page_1.png"
const OUT_SURVEY_2 := "res://artifacts/runtime/survey_page_2.png"
const OUT_SURVEY_3 := "res://artifacts/runtime/survey_page_3.png"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var game := root.get_node_or_null("Game")
	if game == null:
		push_error("RUNTIME_CAPTURE_FAILED Game autoload missing")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/runtime"))
	# 先验证发布版第一次打开时的版本化偏好确认。
	game.set("settings_revision",0)
	var first_run_title := (load("res://scenes/title_screen.tscn") as PackedScene).instantiate()
	root.add_child(first_run_title)
	for i: int in range(8): await process_frame
	if not _save_capture(OUT_FIRST_RUN): quit(1); return
	first_run_title.queue_free()
	for i: int in range(4): await process_frame
	# 其余视觉回归截图进入已确认状态，避免遮挡标题与后续流程。
	game.set("settings_revision",Game.SETTINGS_REVISION)
	game.set("fullscreen_dual_display",false)
	game.call("set_view_mode",0)
	game.set("experiment_mode",false)
	game.set("debug_mode",false)
	var title_packed := load("res://scenes/title_screen.tscn") as PackedScene
	var title_page := title_packed.instantiate()
	root.add_child(title_page)
	for i: int in range(8): await process_frame
	if not _save_capture(OUT_TITLE):
		quit(1)
		return
	title_page.queue_free()
	for i: int in range(4): await process_frame
	var thank_you_packed := load("res://scenes/thank_you.tscn") as PackedScene
	var thank_you_page := thank_you_packed.instantiate()
	root.add_child(thank_you_page)
	for i: int in range(8): await process_frame
	if not _save_capture(OUT_THANK_YOU):
		quit(1)
		return
	thank_you_page.queue_free()
	for i: int in range(4): await process_frame
	# 故意同时打开两个标志，截图与隐私测试共同证明实验模式不会泄漏研究参数。
	game.set("experiment_mode",true)
	game.set("debug_mode",true)
	var select_packed := load("res://scenes/level_select.tscn") as PackedScene
	var select_page := select_packed.instantiate()
	root.add_child(select_page)
	for i: int in range(8): await process_frame
	if not _save_capture(OUT_LEVEL_SELECT):
		quit(1)
		return
	select_page.queue_free()
	for i: int in range(4): await process_frame
	game.set("experiment_mode",false)
	game.set("debug_mode",false)
	game.call("select_mission","level_3")
	var packed := load("res://scenes/main.tscn") as PackedScene
	var scene := packed.instantiate()
	root.add_child(scene)
	for i: int in range(12):
		await process_frame
	await create_timer(0.8).timeout
	if not _save_capture(OUT_START):
		quit(1)
		return
	# 放置一个有效航点，专门验证星图右下角的实时冷却条和航点标记。
	game.call("set_waypoint",game.get("ship_position")+Vector3(32.0,0.0,-12.0))
	await create_timer(0.28,true,false,true).timeout
	if not _save_capture(OUT_WAYPOINT_COOLDOWN):
		quit(1)
		return
	Input.action_press("thrust",0.85)
	Input.action_press("turn_left",0.85)
	await create_timer(0.18,true,false,true).timeout
	if not _save_capture(OUT_CONTROL_ARROWS):
		quit(1)
		return
	Input.action_release("thrust")
	Input.action_release("turn_left")
	# 在收束条仍停留于旧值时截图，同时覆盖碰撞暖灯、红色边缘和即时耐久层。
	game.call("apply_hull_damage",38.0)
	await create_timer(0.12,true,false,true).timeout
	if not _save_capture(OUT_HULL_DAMAGE):
		quit(1)
		return
	game.set("hull",100.0)
	game.emit_signal("hull_changed",100.0)
	await create_timer(0.10,true,false,true).timeout
	var ship := scene.get_node_or_null("SpaceWorld/Ship") as Node3D
	if ship == null:
		push_error("RUNTIME_CAPTURE_FAILED ship missing")
		quit(1)
		return
	ship.global_position = Vector3(18.0,0.0,3.0)
	ship.set("linear_velocity",Vector3.ZERO)
	for i: int in range(12): await process_frame
	await create_timer(0.5).timeout
	if not _save_capture(OUT_MID):
		quit(1)
		return
	var pressure_body: CelestialBodyData = null
	for body: CelestialBodyData in game.get("celestial_bodies"):
		if body.kind == CelestialBodyData.Kind.STAR:
			pressure_body = body
			break
	if pressure_body == null:
		push_error("RUNTIME_CAPTURE_FAILED pressure body missing")
		quit(1)
		return
	# 从距恒星表面 14 单位处正视球心：这正是接近警告开始的位置。
	# 截图必须证明它已经像大型天体一样越出驾驶员画框，而不是小型贴图道具。
	var approach_distance: float = pressure_body.world_radius + 14.0
	ship.global_position = pressure_body.world_position + Vector3(0.0,0.0,approach_distance)
	ship.rotation = Vector3.ZERO
	ship.set("linear_velocity",Vector3.ZERO)
	ship.set("angular_velocity",Vector3.ZERO)
	game.set("ship_position",ship.global_position)
	for i: int in range(12): await process_frame
	await create_timer(0.35).timeout
	if not _save_capture(OUT_PLANET_APPROACH):
		quit(1)
		return
	var current_sector: SectorData=game.get("current_sector")
	var boundary: BeltData=null
	for belt: BeltData in current_sector.belts:
		if belt.is_boundary: boundary=belt; break
	if boundary==null:
		push_error("RUNTIME_CAPTURE_FAILED boundary missing"); quit(1); return
	ship.global_position=boundary.point_on_ring(PI*0.5,(boundary.inner_radius-1.2)*0.94)
	ship.rotation=Vector3(0.0,PI,0.0)
	ship.set("linear_velocity",Vector3.ZERO)
	for i: int in range(8): await process_frame
	await create_timer(0.25).timeout
	if not _save_capture(OUT_BOUNDARY): quit(1); return

	# 重新载入 Level 2，在真实 3D 驾驶视角检查双样条走廊，而不只看审核俯视图。
	scene.queue_free()
	for i: int in range(4): await process_frame
	game.call("select_mission","level_2")
	var level3_scene := packed.instantiate()
	root.add_child(level3_scene)
	for i: int in range(12): await process_frame
	var level3_ship := level3_scene.get_node_or_null("SpaceWorld/Ship") as Node3D
	if level3_ship == null:
		push_error("RUNTIME_CAPTURE_FAILED level3 ship missing")
		quit(1)
		return
	level3_ship.global_position = Vector3(-205.0,0.0,73.0)
	level3_ship.rotation = Vector3(0.0,-PI*0.5,0.0)
	level3_ship.set("linear_velocity",Vector3.ZERO)
	level3_ship.set("angular_velocity",Vector3.ZERO)
	game.set("ship_position",level3_ship.global_position)
	game.set("ship_heading",-PI*0.5)
	for i: int in range(12): await process_frame
	await create_timer(0.45).timeout
	if not _save_capture(OUT_LEVEL3_CORRIDOR): quit(1); return
	var blocker: CelestialBodyData = null
	for body: CelestialBodyData in game.get("celestial_bodies"):
		if body.id == "ring": blocker = body; break
	if blocker == null:
		push_error("RUNTIME_CAPTURE_FAILED level3 blocker missing")
		quit(1)
		return
	level3_ship.global_position = Vector3(143.0,0.0,-8.0)
	level3_ship.look_at(blocker.world_position,Vector3.UP)
	level3_ship.set("linear_velocity",Vector3.ZERO)
	level3_ship.set("angular_velocity",Vector3.ZERO)
	game.set("ship_position",level3_ship.global_position)
	game.set("ship_heading",level3_ship.rotation.y)
	for i: int in range(12): await process_frame
	await create_timer(0.45).timeout
	if not _save_capture(OUT_LEVEL3_BLOCKER): quit(1); return
	var notice_nav := level3_scene.get("_navigator_view") as Control
	var notice_pilot := level3_scene.get("_pilot_view") as Control
	notice_nav.call("show_experiment_notice","检测到磁暴干扰。航点位置已发生偏移。")
	notice_pilot.call("show_experiment_notice","检测到磁暴干扰。航点位置已发生偏移。")
	for i: int in range(4): await process_frame
	if not _save_role_pair(level3_scene,notice_nav,notice_pilot,OUT_NOTICE_EXPLICIT): quit(1); return
	notice_nav.call("show_experiment_notice","检测到航点位置偏移，原因未知。")
	notice_pilot.call("show_experiment_notice","检测到航点位置偏移，原因未知。")
	for i: int in range(4): await process_frame
	if not _save_role_pair(level3_scene,notice_nav,notice_pilot,OUT_NOTICE_AMBIGUOUS): quit(1); return
	game.call("explode_ship")
	await create_timer(0.05,true,false,true).timeout
	if not _save_capture(OUT_EXPLOSION): quit(1); return
	await create_timer(1.35,true,false,true).timeout
	var nav_view := level3_scene.get("_navigator_view") as Control
	var pilot_view := level3_scene.get("_pilot_view") as Control
	var result_panels: Array[Control] = []
	for entry: Dictionary in [{"role":"navigator","parent":nav_view},{"role":"pilot","parent":pilot_view}]:
		var result: Control = load("res://scripts/ui/mission_result_panel.gd").new()
		(entry.parent as Control).add_child(result)
		result.setup(entry.role)
		result.show_result("完成",true)
		result_panels.append(result)
	for i: int in range(3): await process_frame
	if not _save_capture(OUT_RESULT_SUCCESS): quit(1); return
	for result: Control in result_panels: result.show_result("超时未完成",false)
	for i: int in range(3): await process_frame
	if not _save_capture(OUT_RESULT): quit(1); return
	var summary := {
		"outcome":"超时未完成","success":false,"elapsed":160.0,"limit":160.0,
		"revivals":2,"hits":5,"waypoints":8,"hull":0.0,
		"severe_heading_deviations":3,"waypoint_drift_events":1,"ship_shear_events":0,
	}
	for result: Control in result_panels: result.show_summary(summary)
	for i: int in range(3): await process_frame
	if not _save_capture(OUT_SUMMARY): quit(1); return
	for result: Control in result_panels: result.free()
	for i: int in range(4): await process_frame
	nav_view.call("show_experiment_notice","检测到航点位置偏移，原因未知。")
	pilot_view.call("show_experiment_notice","检测到航点位置偏移，原因未知。")
	for i: int in range(3): await process_frame
	var participant_views := level3_scene.call("_capture_participant_views",false) as Dictionary
	var attribution_record := {
		"event_id":"runtime-level3-review","event_type":"mission_responsibility",
		"mission_id":"level_3","mission_label":"正式任务 03","elapsed":146.8,
		"outcome":"完成","success":true,"attempt_number":1,
		"target_event_type":"waypoint_drift","target_event_exposed":true,"target_event_pulse_count":1,
		"capture_kind":"target_peak","views":participant_views,
		"flight_trail":PackedVector2Array([
			Vector2(5,8),Vector2(42,2),Vector2(75,5),Vector2(108,-4),Vector2(140,-18),
			Vector2(175,-28),Vector2(210,-70),Vector2(260,-82),Vector2(310,-72),Vector2(350,-60),
		]),
		"failed_flight_trails":[
			PackedVector2Array([Vector2(-350,58),Vector2(-300,60),Vector2(-250,72),Vector2(-205,67),Vector2(-165,60)]),
			PackedVector2Array([Vector2(5,8),Vector2(48,2),Vector2(88,-2),Vector2(115,-9)]),
		],
		"collision_points":PackedVector2Array([Vector2(-165,60),Vector2(115,-9)]),
		"target_event_position":Vector2(160,-24),
		"target_event_positions":PackedVector2Array([Vector2(-110,47)]),
		"flight_start":Vector2(-350,58),"flight_goal":Vector2(350,-60),
		"flight_world_bounds":level3_scene.call("_mission_flight_bounds"),
	}
	var attribution_panels: Array[Control] = []
	for entry: Dictionary in [{"role":"navigator","parent":nav_view},{"role":"pilot","parent":pilot_view}]:
		var attribution: Control = load("res://scripts/ui/mission_attribution_panel.gd").new()
		(entry.parent as Control).add_child(attribution)
		attribution.setup(entry.role,entry.role,attribution_record)
		attribution_panels.append(attribution)
	for i: int in range(5): await process_frame
	if not _save_capture(OUT_ATTRIBUTION): quit(1); return
	for attribution: Control in attribution_panels: attribution.free()
	var surveys: Array[Control] = []
	for entry: Dictionary in [{"role":"navigator","parent":nav_view},{"role":"pilot","parent":pilot_view}]:
		var survey: Control = load("res://scripts/ui/survey_panel.gd").new()
		(entry.parent as Control).add_child(survey)
		survey.setup(entry.role,"超时未完成",summary)
		surveys.append(survey)
	for i: int in range(3): await process_frame
	if not _save_capture(OUT_SURVEY_1): quit(1); return
	for survey: Control in surveys: survey.call("_show_page",1)
	for i: int in range(3): await process_frame
	if not _save_capture(OUT_SURVEY_2): quit(1); return
	for survey: Control in surveys: survey.call("_show_page",2)
	for i: int in range(3): await process_frame
	if not _save_capture(OUT_SURVEY_3): quit(1); return
	for survey: Control in surveys: survey.free()
	level3_scene.queue_free()
	for i: int in range(4): await process_frame
	game.call("select_mission","level_3")
	var level4_scene := packed.instantiate()
	root.add_child(level4_scene)
	for i: int in range(12): await process_frame
	var level4_nav := level4_scene.get("_navigator_view") as Control
	var level4_pilot := level4_scene.get("_pilot_view") as Control
	var level4_ship := level4_scene.get_node_or_null("SpaceWorld/Ship") as Node3D
	var level4_sector := game.get("current_sector") as SectorData
	var actual_trigger := level4_sector.disturbance_anchors[0]
	var trigger_index := level4_sector.route_checkpoints.find(actual_trigger)
	var next_route := level4_sector.route_checkpoints[mini(trigger_index+1,level4_sector.route_checkpoints.size()-1)]
	level4_ship.global_position = actual_trigger
	level4_ship.look_at(next_route,Vector3.UP)
	level4_ship.set("linear_velocity",Vector3.ZERO)
	level4_ship.set("angular_velocity",Vector3.ZERO)
	game.set("ship_position",actual_trigger)
	game.set("ship_heading",level4_ship.rotation.y)
	for i: int in range(8): await process_frame
	level4_nav.call("show_experiment_notice","检测到太阳风扰动。飞船已出现横向偏移。")
	level4_pilot.call("show_experiment_notice","检测到太阳风扰动。飞船已出现横向偏移。")
	for i: int in range(4): await process_frame
	if not _save_role_pair(level4_scene,level4_nav,level4_pilot,OUT_LEVEL4_NOTICE_EXPLICIT): quit(1); return
	level4_nav.call("show_experiment_notice","检测到飞船横向偏移，原因未知。")
	level4_pilot.call("show_experiment_notice","检测到飞船横向偏移，原因未知。")
	for i: int in range(4): await process_frame
	if not _save_role_pair(level4_scene,level4_nav,level4_pilot,OUT_LEVEL4_NOTICE_AMBIGUOUS): quit(1); return
	print("RUNTIME_CAPTURE_OK level3_explicit=%s level3_ambiguous=%s level4_explicit=%s level4_ambiguous=%s" % [OUT_NOTICE_EXPLICIT,OUT_NOTICE_AMBIGUOUS,OUT_LEVEL4_NOTICE_EXPLICIT,OUT_LEVEL4_NOTICE_AMBIGUOUS])
	quit(0)


func _save_capture(path: String) -> bool:
	var image := root.get_texture().get_image()
	var error := image.save_png(path)
	if error != OK:
		push_error("RUNTIME_CAPTURE_FAILED %s error=%s" % [path,error])
		return false
	return true


func _save_role_pair(scene: Node,nav_view: Control,pilot_view: Control,path: String) -> bool:
	var nav := scene.call("_capture_page_region",nav_view,"navigator",false) as Image
	var pilot := scene.call("_capture_page_region",pilot_view,"pilot",false) as Image
	if nav == null or pilot == null or nav.is_empty() or pilot.is_empty():
		push_error("RUNTIME_CAPTURE_FAILED role pair empty: %s" % path)
		return false
	nav.resize(960,540,Image.INTERPOLATE_LANCZOS)
	pilot.resize(960,540,Image.INTERPOLATE_LANCZOS)
	var pair := Image.create(1920,540,false,Image.FORMAT_RGB8)
	pair.blit_rect(nav,Rect2i(Vector2i.ZERO,nav.get_size()),Vector2i.ZERO)
	pair.blit_rect(pilot,Rect2i(Vector2i.ZERO,pilot.get_size()),Vector2i(960,0))
	return pair.save_png(path) == OK
