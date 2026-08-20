extends Control
## 实验模式的研究编号录入。只收数字组号，不收姓名、关系或自由文本。

const UI = preload("res://scripts/ui/app_style.gd")

var _number: LineEdit
var _preview: Label
var _continue: Button


func _ready() -> void:
	Displays.show_shared_page()
	Displays.shared_key_input.connect(_on_shared_key_input)
	add_child(UI.page())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UI.panel()
	panel.custom_minimum_size = Vector2(880,610)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side: String in ["left","right"]:
		margin.add_theme_constant_override("margin_%s" % side,54)
	for side: String in ["top","bottom"]:
		margin.add_theme_constant_override("margin_%s" % side,42)
	panel.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",18)
	margin.add_child(body)

	var eyebrow := UI.label("EXPERIMENT SETUP / 研究编号",18,UI.CYAN)
	body.add_child(eyebrow)
	body.add_child(UI.label("输入实验组号",42,UI.TEXT))
	var privacy := UI.label("只输入研究员分配的数字编号。请勿填写姓名、联系方式或其他身份信息。",18,UI.MUTED)
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(privacy)
	body.add_child(HSeparator.new())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	body.add_child(row)
	var caption := UI.label("组号",26,UI.AMBER)
	caption.custom_minimum_size.x = 110
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	_number = LineEdit.new()
	_number.name = "DyadNumber"
	_number.placeholder_text = "例如：12"
	_number.max_length = 6
	_number.custom_minimum_size = Vector2(0,70)
	_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_number.add_theme_font_override("font",UI.FONT_CJK)
	_number.add_theme_font_size_override("font_size",30)
	_number.add_theme_color_override("font_color",UI.TEXT)
	_number.add_theme_color_override("font_placeholder_color",Color(UI.MUTED,0.72))
	_number.add_theme_color_override("caret_color",UI.AMBER)
	_number.add_theme_color_override("selection_color",Color(UI.CYAN,0.32))
	_number.add_theme_stylebox_override("normal",UI.box(UI.PANEL_2,Color("29435a"),2))
	_number.add_theme_stylebox_override("focus",UI.box(Color("10283a"),UI.CYAN,3))
	_number.add_theme_stylebox_override("read_only",UI.box(UI.PANEL,UI.MUTED,2))
	_number.text_changed.connect(_on_number_changed)
	_number.text_submitted.connect(func(_text: String): _submit())
	row.add_child(_number)

	_preview = UI.label("",22,UI.TEXT)
	_preview.custom_minimum_size.y = 150
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_preview)
	var note := UI.label("实验条件由组号自动平衡分配，不在参与者界面显示。A/B 是稳定参与者编号，不随领航员/驾驶员岗位变化。",16,UI.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(note)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",14)
	body.add_child(actions)
	var back := UI.button("返回标题",Vector2(250,66))
	UI.set_button_audio_cue(back,"page_turn")
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title_screen.tscn"))
	actions.add_child(back)
	_continue = UI.button("锁定并继续",Vector2(330,66),true)
	_continue.name = "ContinueButton"
	_continue.disabled = true
	UI.set_button_audio_cue(_continue,"confirm")
	_continue.pressed.connect(_submit)
	actions.add_child(_continue)
	_focus_number.call_deferred()
	_refresh()


func _focus_number() -> void:
	get_window().grab_focus()
	_number.grab_focus()


## 正常情况下 LineEdit 会直接吃掉按键；这里处理窗口刚切换或焦点暂时丢失的情况。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if _apply_number_key(event as InputEventKey):
		get_viewport().set_input_as_handled()


func _on_shared_key_input(key: InputEventKey) -> void:
	_apply_number_key(key)


func _apply_number_key(key: InputEventKey) -> bool:
	if not key.pressed or key.echo:
		return false
	if key.unicode>=48 and key.unicode<=57:
		if _number.text.length()<_number.max_length:
			_number.text += char(key.unicode)
			_number.caret_column = _number.text.length()
			_refresh()
		return true
	elif key.keycode==KEY_BACKSPACE or key.physical_keycode==KEY_BACKSPACE:
		if not _number.text.is_empty():
			_number.text = _number.text.substr(0,_number.text.length()-1)
			_number.caret_column = _number.text.length()
			_refresh()
		return true
	elif key.keycode==KEY_ENTER or key.keycode==KEY_KP_ENTER:
		_submit()
		return true
	return false


func _on_number_changed(value: String) -> void:
	var digits := ""
	for character: String in value:
		if character >= "0" and character <= "9":
			digits += character
	if digits != value:
		_number.text = digits
		_number.caret_column = digits.length()
	_refresh()


func _sequence() -> int:
	return _number.text.to_int() if not _number.text.is_empty() else 0


func _refresh() -> void:
	var sequence := _sequence()
	_continue.disabled = sequence <= 0
	if sequence <= 0:
		_preview.text = "尚未录入组号"
		_preview.add_theme_color_override("font_color",UI.MUTED)
		return
	var dyad := "D%03d" % sequence
	var a_on_screen_a := posmod(sequence - 1,4) < 2
	_preview.text = "本组编号  %s\n参与者编号  %sA / %sB\n屏幕分配  屏幕 A → %s ｜ 屏幕 B → %s" % [
		dyad,dyad,dyad,
		"%sA" % dyad if a_on_screen_a else "%sB" % dyad,
		"%sB" % dyad if a_on_screen_a else "%sA" % dyad,
	]
	_preview.add_theme_color_override("font_color",UI.TEXT)


func _submit() -> void:
	var sequence := _sequence()
	if sequence <= 0 or not Game.lock_experiment_setup(sequence):
		_refresh()
		return
	ExperimentLog.close_session()
	ExperimentLog.begin_session()
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")
