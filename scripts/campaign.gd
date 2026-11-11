extends Control

enum Screen { MAP, SELECT, BATTLE, RESULT }

const BATTLE := preload("res://scenes/battle.tscn")
const CITY_NAMES := ["平原", "北海", "濮阳"]
const CITY_GENERALS := ["刘备", "管亥", "吕布"]
const CITY_POSITIONS := [Vector2(226, 360), Vector2(480, 230), Vector2(735, 385)]
const INITIAL_GARRISONS := [0, 34, 48]
const GENERAL_NAMES := ["关羽", "张飞"]
const GENERAL_TROOPS := [50, 42]
const GENERAL_HEALTH := [90.0, 120.0]

var screen := Screen.MAP
var target_city := 0
var selected_general := 0
var garrisons := INITIAL_GARRISONS.duplicate()
var troops := GENERAL_TROOPS.duplicate()
var captured := [true, false, false]
var battle: Node2D
var interface: Control
var panel: VBoxContainer


func _ready() -> void:
	interface = Control.new()
	interface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(interface)
	var colors := Theme.new()
	colors.default_font_size = 19
	colors.set_color("font_color", "Label", Color("f0d7a6"))
	colors.set_color("font_color", "Button", Color("f7dfaf"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("25213a")
	normal.border_color = Color("99784a")
	normal.set_border_width_all(2)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("48405a")
	colors.set_stylebox("normal", "Button", normal)
	colors.set_stylebox("hover", "Button", hover)
	colors.set_stylebox("pressed", "Button", hover)
	interface.theme = colors
	_show_map()


func _draw() -> void:
	if screen == Screen.BATTLE or screen == Screen.RESULT:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("272439"))
	draw_rect(Rect2(24, 104, 912, 492), Color("92805b"))
	draw_rect(Rect2(30, 110, 900, 480), Color("504f39"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(30, 174), Vector2(192, 124), Vector2(355, 170), Vector2(415, 280),
		Vector2(324, 385), Vector2(169, 425), Vector2(30, 382),
	]), Color("666746"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(645, 125), Vector2(930, 110), Vector2(930, 424), Vector2(834, 456),
		Vector2(660, 350), Vector2(552, 249),
	]), Color("686044"))
	draw_polyline(PackedVector2Array([
		Vector2(620, 110), Vector2(570, 160), Vector2(615, 250), Vector2(546, 329),
		Vector2(525, 414), Vector2(442, 487), Vector2(418, 590),
	]), Color("426069"), 22, true)
	draw_polyline(PackedVector2Array(CITY_POSITIONS), Color("c3a777"), 5, true)


func _clear_interface(next: Screen) -> void:
	screen = next
	for child in interface.get_children():
		interface.remove_child(child)
		child.queue_free()
	queue_redraw()


func _show_map() -> void:
	_clear_interface(Screen.MAP)
	_make_panel(Vector2(24, 16), 912)
	_add_label("群英战记 · 河北战局", 34)
	var hint := "选择与我方相邻的敌城，派遣一名武将出战。"
	if captured[2]:
		hint = "河北诸城已尽归我方。"
	elif troops.max() == 0:
		hint = "我军兵力耗尽，先回平原补兵。"
	_add_label(hint, 17)
	for index in range(CITY_NAMES.size()):
		var city := Button.new()
		city.name = "City%d" % index
		city.text = "%s\n%s" % [
			CITY_NAMES[index], "我方城池" if captured[index] else "%s · 守军 %d" % [
				CITY_GENERALS[index], garrisons[index]],
		]
		city.size = Vector2(154, 66)
		city.position = CITY_POSITIONS[index] - city.size * 0.5
		city.disabled = captured[index] or not captured[index - 1] or troops.max() == 0
		city.pressed.connect(_show_selection.bind(index))
		interface.add_child(city)
		if not city.disabled:
			city.grab_focus()

	_make_panel(Vector2(24, 608), 912)
	_add_label(_roster_status(), 18)
	if captured[2]:
		_add_button("Reset", "重新开始战局", _reset_campaign).grab_focus()
	else:
		var recruit := _add_button("Recruit", "平原补兵", _recruit)
		recruit.disabled = troops == GENERAL_TROOPS
		if troops.max() == 0:
			recruit.grab_focus()


func _show_selection(city: int) -> void:
	target_city = city
	_clear_interface(Screen.SELECT)
	_make_panel(Vector2(230, 160), 500, true)
	_add_label("出征 · %s" % CITY_NAMES[city], 32)
	_add_label("守将 %s    守军 %d" % [CITY_GENERALS[city], garrisons[city]], 19)
	var first_general: Button
	for index in range(GENERAL_NAMES.size()):
		var general := _add_button("General%d" % index, "%s    体力 %d    兵力 %d" % [
			GENERAL_NAMES[index], int(GENERAL_HEALTH[index]), troops[index],
		], _start_battle.bind(index))
		general.disabled = troops[index] == 0
		if not general.disabled and first_general == null:
			first_general = general
	var back := _add_button("Cancel", "返回地图", _show_map)
	(first_general if first_general != null else back).grab_focus()


func _start_battle(general: int) -> void:
	selected_general = general
	_clear_interface(Screen.BATTLE)
	battle = BATTLE.instantiate()
	battle.campaign_battle = true
	battle.friendly_name = GENERAL_NAMES[general]
	battle.enemy_name = CITY_GENERALS[target_city]
	battle.friendly_soldiers = troops[general]
	battle.enemy_soldiers = garrisons[target_city]
	battle.friendly_health = GENERAL_HEALTH[general]
	battle.battle_finished.connect(_show_result, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	add_child(battle)
	move_child(battle, 0)


func _show_result(victory: bool, friendly_survivors: int, enemy_survivors: int) -> void:
	var losses: int = troops[selected_general] - friendly_survivors
	troops[selected_general] = friendly_survivors
	garrisons[target_city] = enemy_survivors
	captured[target_city] = victory
	_clear_interface(Screen.RESULT)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.02, 0.05, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	interface.add_child(shade)
	_make_panel(Vector2(230, 195), 500, true)
	_add_label(("攻克 %s" if victory else "败退于 %s") % CITY_NAMES[target_city], 36)
	_add_label("%s · 剩余 %d 兵 · 损失 %d 兵" % [
		GENERAL_NAMES[selected_general], friendly_survivors, losses,
	], 20)
	_add_label("敌军剩余 %d 兵" % enemy_survivors, 19)
	_add_button("ReturnToMap", "返回地图", _return_from_battle).grab_focus()


func _return_from_battle() -> void:
	remove_child(battle)
	battle.queue_free()
	battle = null
	_show_map()


func _recruit() -> void:
	troops = GENERAL_TROOPS.duplicate()
	_show_map()


func _reset_campaign() -> void:
	captured = [true, false, false]
	garrisons = INITIAL_GARRISONS.duplicate()
	_recruit()


func _roster_status() -> String:
	return "我方城池 %d / %d     关羽 %d 兵     张飞 %d 兵" % [
		captured.count(true), CITY_NAMES.size(), troops[0], troops[1],
	]


func _make_panel(at: Vector2, width: float, framed: bool = false) -> void:
	panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 8)
	if framed:
		var frame := PanelContainer.new()
		frame.position = at
		frame.custom_minimum_size.x = width
		var style := StyleBoxFlat.new()
		style.bg_color = Color("242036")
		style.border_color = Color("ad8954")
		style.set_border_width_all(2)
		style.content_margin_left = 28
		style.content_margin_right = 28
		style.content_margin_top = 22
		style.content_margin_bottom = 22
		frame.add_theme_stylebox_override("panel", style)
		interface.add_child(frame)
		frame.add_child(panel)
	else:
		panel.position = at
		panel.custom_minimum_size.x = width
		interface.add_child(panel)


func _add_label(message: String, font_size: int) -> void:
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	panel.add_child(label)


func _add_button(id: String, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = id
	button.text = caption
	button.custom_minimum_size.y = 40
	button.pressed.connect(action)
	panel.add_child(button)
	return button
