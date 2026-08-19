extends SceneTree
## 直接渲染玩家实际使用的 SectorMap，不经过驾驶舱缩小，输出可检查的全尺寸 PNG。

const OUT_DIR := "res://artifacts/star_maps"
const OVERVIEW_DIR := "res://artifacts/star_map_overviews"
const MISSIONS: PackedStringArray = ["practice","level_1","level_2","level_3","level_4"]


func _initialize() -> void:
	_capture_all.call_deferred()


func _capture_all() -> void:
	var game:=root.get_node_or_null("Game")
	if game==null:
		push_error("STAR_MAP_CAPTURE_FAILED Game autoload missing"); quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OVERVIEW_DIR))
	for mission_id: String in MISSIONS:
		game.call("select_mission",mission_id)
		var sector: SectorData=game.get("current_sector")
		var route:=sector.route_checkpoints
		var middle: Vector3=route[route.size()/2]
		game.set("ship_position",middle)
		var map:=Control.new(); map.set_script(load("res://scripts/ui/sector_map.gd") as Script)
		map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(map)
		for i: int in range(12): await process_frame
		await create_timer(0.2).timeout
		var image:=root.get_texture().get_image()
		var path:="%s/%s.png" % [OUT_DIR,mission_id]
		if image.save_png(path)!=OK:
			push_error("STAR_MAP_CAPTURE_FAILED %s" % path); quit(1); return
		print("STAR_MAP_CAPTURE_OK %s %dx%d" % [path,image.get_width(),image.get_height()])
		map.queue_free(); await process_frame

		# 同一套真实 SectorMap 临时拉远，用于检查全图比例、资产分布和路线边界。
		var original_half: float=sector.map_view_half
		sector.map_view_half=_overview_half(sector)
		var overview:=Control.new(); overview.set_script(load("res://scripts/ui/sector_map.gd") as Script)
		overview.set("fixed_focus_enabled",true); overview.set("fixed_focus_world",Vector3.ZERO)
		overview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(overview)
		for i: int in range(12): await process_frame
		await create_timer(0.2).timeout
		var overview_image:=root.get_texture().get_image()
		var overview_path:="%s/%s.png" % [OVERVIEW_DIR,mission_id]
		if overview_image.save_png(overview_path)!=OK:
			push_error("STAR_MAP_OVERVIEW_FAILED %s" % overview_path); quit(1); return
		print("STAR_MAP_OVERVIEW_OK %s %dx%d" % [overview_path,overview_image.get_width(),overview_image.get_height()])
		overview.queue_free(); await process_frame
		sector.map_view_half=original_half
	print("STAR_MAP_CAPTURE_ALL_OK count=%d overviews=%d" % [MISSIONS.size(),MISSIONS.size()])
	quit(0)


func _overview_half(sector: SectorData) -> float:
	var half_x:=0.0; var half_z:=0.0
	for belt: BeltData in sector.belts:
		if belt.is_boundary:
			half_x=maxf(half_x,belt.outer_radius*belt.aspect)
			half_z=maxf(half_z,belt.outer_radius)
	# 1920:1080 下仍使用各向同性比例，并留 7% 边距给边界和标签。
	return maxf(half_z,half_x/(16.0/9.0))*1.07
