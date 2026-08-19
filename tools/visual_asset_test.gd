extends SceneTree
## 新封面、姿态仪和飞船图标的尺寸、透明通道与正向约定防回归。

const TITLE_BG := "res://assets/ui/title/title_background.jpg"
const TITLE_ART := "res://assets/ui/title/deep_nav_title.png"
const ATTITUDE := "res://assets/ui/cockpit/attitude_indicator.png"
const SHIP := "res://assets/ships/deep_nav_ship.png"
const THANK_YOU := "res://assets/ui/results/thank_you.jpg"
const MISSION_PREVIEWS: PackedStringArray = [
	"res://assets/ui/mission_previews/practice.jpg",
	"res://assets/ui/mission_previews/level_1.jpg",
	"res://assets/ui/mission_previews/level_2.jpg",
	"res://assets/ui/mission_previews/level_3.jpg",
	"res://assets/ui/mission_previews/level_4.jpg",
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_image(TITLE_BG,Vector2i(2752,1536),false)
	_check_image(TITLE_ART,Vector2i(1916,1136),true)
	_check_image(ATTITUDE,Vector2i(704,704),true)
	_check_image(THANK_YOU,Vector2i(2752,1536),false)
	var ship_image := _check_image(SHIP,Vector2i(838,792),true)
	for preview_path: String in MISSION_PREVIEWS:
		_check_image(preview_path,Vector2i(3168,1344),false)
	assert(_orange_score(ship_image,0.0,0.34)>_orange_score(ship_image,0.66,1.0)*2.0,
		"ship nose orientation changed: large orange nose must remain at image top")

	var title_packed := load("res://scenes/title_screen.tscn") as PackedScene
	var title_page := title_packed.instantiate()
	root.add_child(title_page)
	await process_frame
	var title_sprite := title_page.find_child("TitleArt",true,false) as Sprite2D
	assert(title_sprite != null,"title art missing")
	var title_background := title_page.find_child("TitleBackground",true,false) as TextureRect
	assert(title_background != null and title_background.scale==Vector2.ONE,"title background must remain completely still")
	assert(title_sprite.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR,"moving title lost smooth texture sampling")
	assert(not root.snap_2d_transforms_to_pixel and not root.snap_2d_vertices_to_pixel,"title page pixel snapping causes stepped animation")
	var title_drawn := Vector2(title_sprite.texture.get_width(),title_sprite.texture.get_height())*title_sprite.scale
	assert(title_drawn.distance_to(Vector2(500,296))<1.5,"title escaped intended 500x296 footprint")
	var title_menu := title_page.find_child("TitleMenu",true,false) as VBoxContainer
	var debug_switch := title_page.find_child("DebugModeSwitch",true,false) as Control
	var experiment_switch := title_page.find_child("ExperimentModeSwitch",true,false) as Control
	var data_button := title_page.find_child("OpenDataFolderButton",true,false) as Button
	assert(title_menu != null and title_menu.get_parent()==title_page,"title menu regained an outer frame")
	assert(debug_switch != null and debug_switch.custom_minimum_size.y>=72.0,"debug mode control became too small")
	assert(experiment_switch != null and experiment_switch.custom_minimum_size.y>=72.0,"experiment mode control became too small")
	assert(data_button != null and data_button.text=="打开数据文件夹","title data-folder entry missing")
	title_page.queue_free()
	await process_frame
	assert(root.snap_2d_transforms_to_pixel and root.snap_2d_vertices_to_pixel,"title page did not restore gameplay pixel snapping")

	var map := Control.new()
	map.set_script(load("res://scripts/ui/sector_map.gd") as Script)
	map.size = Vector2(800,600)
	root.add_child(map)
	await process_frame
	var ship_icon := map.find_child("ShipIcon",true,false) as Sprite2D
	assert(ship_icon != null and ship_icon.texture.resource_path==SHIP,"sector map still uses old ship")
	assert(map.find_children("*","Label",true,false).is_empty(),"sector map must not label planet or star names/types")
	var map_ship_extent := maxf(ship_icon.texture.get_width(),ship_icon.texture.get_height())*ship_icon.scale.x
	assert(absf(map_ship_extent-30.0)<0.2,"sector map ship icon escaped intended 30px size")
	map.call("_on_ship_state",Vector3.ZERO,0.0,0.0,0.0)
	assert(absf(ship_icon.rotation)<0.001,"heading 0 must point image nose upward")
	map.call("_on_ship_state",Vector3.ZERO,PI*0.5,0.0,0.0)
	assert(absf(ship_icon.rotation+PI*0.5)<0.001,"map heading rotation inverted")
	map.queue_free()

	for action: String in ["thrust","brake","turn_left","turn_right"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var gauge := Control.new()
	gauge.set_script(load("res://scripts/ui/thrust_gauge.gd") as Script)
	gauge.size = Vector2(240,240)
	root.add_child(gauge)
	await process_frame
	var attitude_texture := gauge.get("_ship_icon") as Texture2D
	assert(attitude_texture != null and attitude_texture.resource_path==ATTITUDE,"pilot gauge still uses old ship icon")
	print("VISUAL_ASSET_OK title=500x296 smooth_float=true background=static menu=frameless data_folder=true attitude=704x704 ship_nose=up mission_previews=5 thank_you=2752x1536")
	quit(0)


func _check_image(path: String,expected: Vector2i,needs_alpha: bool) -> Image:
	var texture := load(path) as Texture2D
	assert(texture != null,"texture import missing: %s" % path)
	var image := texture.get_image()
	assert(not image.is_empty(),"asset missing: %s" % path)
	assert(Vector2i(image.get_width(),image.get_height())==expected,"asset size changed: %s" % path)
	if needs_alpha:
		assert(image.detect_alpha()!=Image.ALPHA_NONE,"transparent asset lost alpha: %s" % path)
		assert(image.get_pixel(0,image.get_height()-1).a<0.5,"asset corner is no longer transparent: %s" % path)
	return image


func _orange_score(image: Image,from_y: float,to_y: float) -> float:
	var score := 0.0
	var y0 := int(image.get_height()*from_y)
	var y1 := int(image.get_height()*to_y)
	for y: int in range(y0,y1,4):
		for x: int in range(0,image.get_width(),4):
			var color := image.get_pixel(x,y)
			if color.a>0.5 and color.r>color.g*1.18 and color.g>color.b*1.12:
				score += color.a
	return score
