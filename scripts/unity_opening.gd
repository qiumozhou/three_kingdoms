extends Control

const SCENARIO := preload("res://scripts/unity_scenario.gd")
const COURT := preload("res://scripts/unity_court_rules.gd")
const SAVES := preload("res://scripts/unity_court_save.gd")
const STRATEGY := preload("res://scripts/unity_strategy.gd")
const TITLE := preload("res://assets/unity_reference/320-1.png")
const TITLE_MENU := preload("res://assets/unity_reference/377-1.png")
const TITLE_VOLUME := preload("res://assets/unity_reference/378-1.png")
const TITLE_MUSIC := preload("res://assets/unity_reference/Music01.mp3")
const TITLE_CLICK := preload("res://assets/unity_reference/00038.wav")
const SELECT_BACKGROUND := preload("res://assets/unity_reference/366-1.png")
const SELECT_MENU := preload("res://assets/unity_reference/318-1.png")
const RESULT_FRAME := preload("res://assets/unity_reference/319-1.png")
const LIST_FRAME := preload("res://assets/unity_reference/274-1.png")
const CONFIRM_FRAME := preload("res://assets/unity_reference/363-1.png")
const MAP := preload("res://assets/unity_reference/389-1.png")
const BATTLE := preload("res://scenes/battle.tscn")
const BATTLE_SKY := preload("res://assets/unity_reference/1591-1.png")
const BATTLE_GROUND := preload("res://assets/unity_reference/1622-1.png")
const COURT_MENU := preload("res://assets/unity_reference/264-1.png")
const COURT_INFO := preload("res://assets/unity_reference/265-1.png")
const SOURCE_FONT := preload("res://assets/unity_reference/Font.fnt")
const POWER_MAP := preload("res://assets/unity_reference/342-1.png")
const STRATEGY_FLAGS := preload("res://assets/unity_reference/strategy_flags.png")
const STRATEGY_ARMIES := preload("res://assets/unity_reference/strategy_armies.png")
const VICTORY_FLAG_OFFSETS := [
	[Vector2(5, 30), Vector2(2, 31), Vector2(5, 31)],
	[Vector2(5, 32), Vector2(6, 31), Vector2(5, 31)],
	[Vector2(2, 30), Vector2(0, 31), Vector2(2, 31)]]
const CITY_MARKER := preload("res://assets/unity_reference/316-1.png")
const MAP_MUSIC := preload("res://assets/unity_reference/Music03.ogg")
const COURT_MUSIC := preload("res://assets/unity_reference/Music02.ogg")
const DEFEAT_ART := preload("res://assets/unity_reference/367-1.png")
const CREDITS_ART := preload("res://assets/unity_reference/2-1.png")
const HALLS := [
	preload("res://assets/unity_reference/390-1.png"),
	preload("res://assets/unity_reference/392-1.png"),
	preload("res://assets/unity_reference/391-1.png"),
]

var scenario: UnityScenario
var court: RefCounted
var strategy: RefCounted
var king_id := -1
var scenario_index := SCENARIO.DEFAULT_INDEX
var game_passed := false
var general_names := FileAccess.get_file_as_string(
	"res://assets/unity_reference/general_names.txt").split("\n", false)
var rng := RandomNumberGenerator.new()
var menu: Control
var details: Control
var battle: Node2D
var year := 190
var computer_court_year := 190
var save_directory := "user://"
var progress_path := "user://unity_progress.cfg"
var court_font: Font
var power_markers: Control
var court_music: AudioStreamPlayer
var music_source: AudioStream
var title_effect: AudioStreamPlayer
var volume_settings := ConfigFile.new()
var volume_path := "user://unity_volume.cfg"
var strategy_running := false
var strategy_started := false
var date_label: Label
var map_camera := Vector2.ZERO
var map_view: TextureRect
var map_drag_start := Vector2.ZERO
var map_dragging := false
var map_interactive := false
var map_armies: Control
var map_cities: Control
var flag_frames := SpriteFrames.new()
var army_frames := SpriteFrames.new()
var draft_officers: Array[int] = []
var draft_funds := 0
var draft_prisoners := false
var draft_commander := -1
var draft_prefect := -1
var encounter_army: Dictionary
var encounter_opponent: Dictionary
var encounter_city := -1
var encounter_player := -1
var encounter_enemy := -1
var encounter_positions: Dictionary = {}
var attackers_left: Array[int] = []
var defenders_left: Array[int] = []


func _ready() -> void:
	_load_map_frames(flag_frames, STRATEGY_FLAGS, "strategy_flags")
	_load_map_frames(army_frames, STRATEGY_ARMIES, "strategy_armies")
	court_font = SOURCE_FONT.duplicate()
	court_font.fallbacks = [ThemeDB.fallback_font]
	court_music = AudioStreamPlayer.new()
	var theme_music := COURT_MUSIC.duplicate() as AudioStreamOggVorbis
	theme_music.loop = true
	court_music.stream = theme_music
	music_source = COURT_MUSIC
	add_child(court_music)
	title_effect = AudioStreamPlayer.new()
	title_effect.stream = TITLE_CLICK
	add_child(title_effect)
	volume_settings.load(volume_path)
	court_music.volume_linear = float(volume_settings.get_value("audio", "music", 100)) / 100.0
	title_effect.volume_linear = float(volume_settings.get_value("audio", "effect", 100)) / 100.0
	var progress := ConfigFile.new()
	if progress.load(progress_path) == OK:
		game_passed = progress.has_section_key("progress", "GamePass")
	_show_title()


func _exit_tree() -> void:
	if is_instance_valid(court_music):
		court_music.stop()


func _show_title() -> void:
	_build_background(TITLE)
	menu = Control.new()
	menu.position = Vector2(362.25, 280.5)
	menu.size = TITLE_MENU.get_size() * 1.5
	add_child(menu)
	_title_frame(TITLE_MENU)
	_title_button("开始游戏", 12, _start_game).grab_focus()
	_title_button("继续游戏", 57, _show_slots.bind(false))
	_title_button("音量设定", 102, _show_title_volume)
	_title_button("结束游戏", 147, get_tree().quit)
	_slide_in(menu, -600)


func _title_frame(texture: Texture2D) -> void:
	var fill := ColorRect.new()
	fill.color = Color(0.0, 16.0 / 255.0, 90.0 / 255.0, 0.5)
	fill.position = Vector2(5, 5)
	fill.size = menu.size - Vector2(10, 10)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(fill)
	_place_texture(menu, texture, menu.size / 2.0, menu.size)


func _title_button(caption: String, y: float, action: Callable) -> Button:
	var button := _button(menu, caption, func() -> void:
		if DisplayServer.get_name() != "headless":
			title_effect.play()
		action.call())
	button.flat = true
	button.position = Vector2(12, y)
	button.size = Vector2(menu.size.x - 24, 42)
	button.add_theme_font_override("font", court_font)
	button.add_theme_font_size_override("font_size", 30)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color("#fce89a"))
	return button


func _show_title_volume() -> void:
	_build_background(TITLE)
	menu = Control.new()
	menu.size = TITLE_VOLUME.get_size() * 1.5
	menu.position = Vector2(480, 384) - menu.size / 2.0
	add_child(menu)
	_title_frame(TITLE_VOLUME)
	var channels := ["effect", "music"]
	for index in channels.size():
		var channel: String = channels[index]
		var slider := HSlider.new()
		slider.position = Vector2(57, 79 + 135 * index)
		slider.size.x = 337
		slider.max_value = 100
		slider.step = 1
		slider.value = volume_settings.get_value("audio", channel, 100)
		menu.add_child(slider)
		slider.value_changed.connect(func(value: float) -> void:
			volume_settings.set_value("audio", channel, int(value))
			if channel == "music":
				court_music.volume_linear = value / 100.0
			else:
				title_effect.volume_linear = value / 100.0)
	_title_button("返回", 238, func() -> void:
		volume_settings.save(volume_path)
		_show_title()).grab_focus()
	_slide_in(menu, -720)


func _start_game() -> void:
	var available := SCENARIO.available_scenarios(game_passed)
	if available.size() == 1:
		_show_kings(available[0])
		return
	_build_screen(MAP, Rect2(42, 125, 236, 0))
	_label(menu, "选择剧本")
	for index in available:
		_button(menu, "剧本 %d" % (index + 1), _show_kings.bind(index))
	_button(menu, "返回", _show_title)


func _show_kings(index: int) -> void:
	scenario = SCENARIO.load_scenario(index)
	if scenario == null:
		return
	scenario_index = index
	king_id = -1
	court = COURT.new(scenario, rng)
	strategy = STRATEGY.new(scenario, rng)
	strategy_started = false
	map_camera = Vector2.ZERO
	year = 190
	computer_court_year = 190
	_build_background(SELECT_BACKGROUND)
	var tint := ColorRect.new()
	tint.color = Color(0.0, 16.0 / 255.0, 90.0 / 255.0, 0.5)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tint)
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu = Control.new()
	add_child(menu)
	_place_texture(menu, SELECT_MENU, Vector2(141, 261), SELECT_MENU.get_size() * 1.5)
	for id in range(SCENARIO.selectable_count(index)):
		_source_button(menu, scenario.kings[id]["Name"], Rect2(39, 112.5 + id * 45, 180, 42), _select_king.bind(id))
	_source_button(menu, "返回", Rect2(861, 660, 84, 45), _start_game if game_passed else _show_title)
	details = Control.new()
	add_child(details)
	_draw_selection_map(scenario.kings[0]["cities"])
	_draw_king_summary(0)
	move_child(menu, get_child_count() - 1)
	_slide_in(menu, -450)


func _source_lines(parent: Control, caption: String, position: Vector2, font_size := 21, line_height := 24) -> void:
	var lines := caption.split("\n")
	for index in lines.size():
		var label := Label.new()
		label.text = lines[index]
		label.position = position + Vector2(0, index * line_height)
		label.add_theme_font_override("font", court_font)
		label.add_theme_font_size_override("font_size", font_size)
		parent.add_child(label)


func _source_button(parent: Control, caption: String, area: Rect2, callback: Callable) -> Button:
	var button := _button(parent, caption, callback)
	button.flat = true
	button.position = area.position
	button.size = area.size
	button.add_theme_font_override("font", court_font)
	button.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_color_override("font_hover_color", Color.GREEN)
	return button


func _draw_selection_map(cities: Array) -> void:
	if get_node_or_null("SelectionMap") == null:
		var art := _place_texture(self, POWER_MAP, Vector2(615, 262.5), POWER_MAP.get_size() * 1.5)
		art.name = "SelectionMap"
	power_markers = Control.new()
	add_child(power_markers)
	for id in scenario.cities.size():
		var point: Array = court.tables["map_points"][id]
		var marker := _place_texture(power_markers, CITY_MARKER,
			Vector2(615, 262.5) + Vector2(point[0], -point[1]) * 1.5, CITY_MARKER.get_size() * 1.5)
		marker.modulate = Color.WHITE if cities.has(id) else Color(0.5, 0, 0, 1)


func _draw_king_summary(id: int) -> void:
	_place_texture(details, RESULT_FRAME, Vector2(480, 621), RESULT_FRAME.get_size() * 1.5)
	var king := scenario.kings[id]
	var head := load("res://assets/unity_reference/heads/%d.png" % (king["GeneralIdx"] + 1)) as Texture2D
	_place_texture(details, head, Vector2(96, 621), Vector2(144, 144))
	var money := 0
	var population := 0
	var troops := 0
	for city: int in king["cities"]:
		money += int(scenario.cities[city]["Money"])
		population += int(scenario.cities[city]["Population"])
	for general: int in king["generals"]:
		troops += int(scenario.generals[general]["SoldierCur"] + scenario.generals[general]["KnightCur"])
	var captions := ["君主", king["Name"], "城数", str(king["cities"].size()),
		"金钱", str(money), "武将", "%d人" % king["generals"].size(),
		"人口", "%d人" % population, "总兵数", "%d人" % troops]
	for row in 3:
		for column in 4:
			_court_text(details, captions[row * 4 + column], Vector2([216, 333, 495, 681][column], 568.5 + row * 48))


func _select_king(id: int) -> void:
	king_id = id
	_clear(details)
	remove_child(power_markers)
	power_markers.queue_free()
	_draw_selection_map(scenario.kings[id]["cities"])
	_draw_king_summary(id)
	move_child(details, get_child_count() - 1)
	var confirm := Control.new()
	confirm.name = "KingConfirm"
	confirm.position = Vector2(384, 120 + 45 * id)
	details.add_child(confirm)
	_place_texture(confirm, CONFIRM_FRAME, Vector2.ZERO, CONFIRM_FRAME.get_size() * 1.5)
	_source_button(confirm, "确定", Rect2(-90, -45, 180, 42), _show_court).grab_focus()
	_source_button(confirm, "取消", Rect2(-90, 0, 180, 42), _cancel_king)


func _cancel_king() -> void:
	var previous := king_id
	king_id = -1
	var confirm := details.get_node("KingConfirm")
	details.remove_child(confirm)
	confirm.queue_free()
	menu.get_child(previous + 1).grab_focus()


func _show_court(message: String = "") -> void:
	var king := scenario.kings[king_id]
	var city_count: int = king["cities"].size()
	_build_background(_court_background())
	menu = Control.new()
	add_child(menu)
	_place_texture(menu, COURT_MENU, Vector2(262.5, 375.0), COURT_MENU.get_size() * 1.5)
	var captions := ["使用物品", "武将资料", "招降俘虏", "搜  索", "筑  城", "开  发",
		"势力地图", "武将升迁", "内政终了", "进度存档", "回主选单"]
	var actions: Array[Callable] = [_show_item_officers, _show_officers.bind(""), _show_prisoners,
		_show_officers.bind("Search"), _show_officers.bind("Defense"), _show_officers.bind("Population"),
		_show_power_map, _show_promotion, _confirm_end_court, _show_slots.bind(true), _show_title]
	for index in captions.size():
		var button := _button(menu, captions[index], actions[index])
		button.flat = true
		for state in ["normal", "hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		button.add_theme_font_override("font", court_font)
		button.add_theme_font_size_override("font_size", 33)
		button.add_theme_color_override("font_hover_color", Color("#ff4949"))
		var y := 705.0 if index == 10 else 217.5 + index * 45.0
		button.size = Vector2(210, 42)
		button.position = Vector2(255, y) - button.size / 2.0
	details = Control.new()
	add_child(details)
	_place_texture(details, COURT_INFO, Vector2(652.5, 375.0), COURT_INFO.get_size() * 1.5)
	var head := load("res://assets/unity_reference/heads/%d.png" % (king["GeneralIdx"] + 1)) as Texture2D
	_place_texture(details, head, Vector2(626.25, 255.0), Vector2(150, 150))
	var money := 0
	var population := 0
	var soldiers := 0
	for city_id: int in king["cities"]:
		money += int(scenario.cities[city_id]["Money"])
		population += int(scenario.cities[city_id]["Population"])
	for id: int in king["generals"]:
		soldiers += int(scenario.generals[id]["SoldierCur"]) + int(scenario.generals[id]["KnightCur"])
	var labels := ["时间", "君主", "城数", "金钱", "人口", "武将", "士兵"]
	var values := ["%d 年" % year, king["Name"], str(city_count), str(money),
		"%d 人" % population, "%d 人" % king["generals"].size(), "%d 人" % soldiers]
	var positions := [135.0, 367.5, 412.5, 457.5, 502.5, 547.5, 592.5]
	for index in labels.size():
		_court_text(details, labels[index], Vector2(547.5, positions[index]))
		_court_text(details, values[index], Vector2(645.0, positions[index]))
	_slide_in(menu, -450.0)
	_slide_in(details, 450.0)
	if not message.is_empty():
		var notice := _panel(Rect2(350, 655, 405, 0))
		_label(notice, message)


func _court_background() -> Texture2D:
	var city_count: int = scenario.kings[king_id]["cities"].size()
	return HALLS[0 if city_count < 16 else (1 if city_count < 32 else 2)]


func _court_text(parent: Control, caption: String, anchor: Vector2) -> void:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_override("font", court_font)
	label.add_theme_font_size_override("font_size", 30)
	label.position = anchor - Vector2(0, 17)
	parent.add_child(label)


func _slide_in(panel: Control, offset: float) -> void:
	var destination := panel.position.x
	panel.position.x += offset
	panel.create_tween().tween_property(panel, "position:x", destination, 0.4
		).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _show_officers(command: String) -> void:
	if command in ["Defense", "Population"]:
		_show_city_assignment(command)
		return
	var caption: String = {"": "武将资料", "Defense": "筑城", "Population": "开发", "Search": "搜索"}[command]
	var rows := _court_list(caption, 310)
	for id: int in scenario.kings[king_id]["generals"]:
		var name_text := general_names[id].strip_edges()
		if command.is_empty():
			_button(rows, name_text, _show_officer_info.bind(id))
		elif command == "Search" and court.can_search(king_id, id):
			_button(rows, name_text, _search.bind(id))
		elif scenario.can_assign(king_id, id, command):
			_button(rows, name_text, _assign.bind(id, command))
	if rows.get_child_count() == 0:
		_label(rows, "没有可执行的武将")


func _show_city_assignment(command: String, selected_city := -1) -> void:
	_build_background(_court_background())
	menu = Control.new()
	add_child(menu)
	var header := preload("res://assets/unity_reference/272-1.png") if command == "Defense" else preload("res://assets/unity_reference/273-1.png")
	_place_texture(menu, header, Vector2(141, 45), header.get_size() * 1.5)
	_place_texture(menu, LIST_FRAME, Vector2(141, 307.5), LIST_FRAME.get_size() * 1.5)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(39, 105)
	scroll.size = Vector2(207, 393)
	menu.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for id: int in scenario.kings[king_id]["generals"]:
		var general := scenario.generals[id]
		var qualified: bool = general["Strength" if command == "Defense" else "Intellect"] >= 80
		if id == scenario.kings[king_id]["GeneralIdx"] or general["City"] < 0 or not qualified:
			continue
		var button := _source_button(rows, general_names[id].strip_edges(), Rect2(0, 0, 180, 45), _assign.bind(id, command))
		button.disabled = not scenario.can_assign(king_id, id, command)
	_source_button(menu, "返回", Rect2(861, 660, 84, 45), _show_court.bind(""))
	var city_id: int = selected_city if selected_city >= 0 else scenario.kings[king_id]["cities"][0]
	_draw_selection_map([city_id])
	details = Control.new()
	add_child(details)
	_place_texture(details, RESULT_FRAME, Vector2(480, 621), RESULT_FRAME.get_size() * 1.5)
	var city := scenario.cities[city_id]
	var captions := ["城名", city["Name"], "防御力", str(city["Defense"]), "武将", str(city["generals"].size()),
		"人口", "%d人" % city["Population"], "预备兵", "%d/%d" % [city["Reservist"], city["ReservistMax"]], "金钱", str(city["Money"])]
	for row in 3:
		for column in 4:
			_court_text(details, captions[row * 4 + column], Vector2([60, 195, 426, 552][column], 570 + row * 48))
	move_child(menu, get_child_count() - 1)


func _assign(id: int, command: String) -> void:
	var city_id: int = scenario.generals[id]["City"]
	var increase := scenario.assign(king_id, id, command, rng)
	if increase == 0:
		return
	_show_city_assignment(command, city_id)
	_clear(details)
	_place_texture(details, RESULT_FRAME, Vector2(480, 621), RESULT_FRAME.get_size() * 1.5)
	var head := load("res://assets/unity_reference/heads/%d.png" % (id + 1)) as Texture2D
	_place_texture(details, head, Vector2(96, 621), Vector2(144, 144))
	var result := Label.new()
	result.position = Vector2(195, 567)
	result.size = Vector2(720, 100)
	result.add_theme_font_override("font", court_font)
	result.add_theme_font_size_override("font_size", 30)
	result.text = "%s城防御力增加%d" % [scenario.cities[city_id]["Name"], increase] if command == "Defense" else "%s城人口增加%d人" % [scenario.cities[city_id]["Name"], increase]
	details.add_child(result)
	_reveal_text(result, 0.05, _show_city_assignment.bind(command, city_id), 0.2, true)


func _court_list(caption: String, width: float = 310.0) -> VBoxContainer:
	_build_screen(_court_background(), Rect2(42, 74, width, 0))
	_label(menu, caption)
	var rows := _scroll_rows(menu)
	_button(menu, "返回", _show_court.bind(""))
	details = _panel(Rect2(575, 100, 345, 0))
	return rows


func _show_officer_info(id: int) -> void:
	_clear(details)
	var general := scenario.generals[id]
	_label(details, general_names[id].strip_edges())
	var city_id: int = general["City"]
	var job: int = general["job"]
	_label(details, "%s　等级 %d　%s" % [
		scenario.cities[city_id]["Name"] if city_id >= 0 else "不在城中",
		general["Level"], court.tables["jobs"][job] if job >= 0 else ""])
	_label(details, "武力 %d　智力 %d　经验 %d" % [general["Strength"], general["Intellect"], general["Experience"]])
	_label(details, "体力 %d/%d　技力 %d/%d" % [
		general["HealthCur"], general["HealthMax"], general["ManaCur"], general["ManaMax"]])
	_label(details, "士兵 %d/%d　骑兵 %d/%d" % [
		general["SoldierCur"], general["SoldierMax"], general["KnightCur"], general["KnightMax"]])
	var equipment: int = general["Equipment"]
	_label(details, "装备　%s" % (court.tables["equipment"][equipment][0] if equipment >= 0 else "无"))
	var rows := _scroll_rows(details)
	for index in range(court.tables["arms"].size()):
		var mask := 1 << index
		if (general["Arms"] & mask) != 0:
			var arms := _button(rows, court.tables["arms"][index], _select_battle_option.bind(id, "arms_current", mask))
			arms.disabled = general["arms_current"] == mask
	for index in range(court.tables["formations"].size()):
		var mask := 1 << index
		if (general["Formation"] & mask) != 0:
			var formation := _button(rows, court.tables["formations"][index], _select_battle_option.bind(id, "formation_current", mask))
			formation.disabled = general["formation_current"] == mask
	rows.get_parent().custom_minimum_size.y = 220


func _select_battle_option(id: int, field: String, mask: int) -> void:
	scenario.generals[id][field] = mask
	_show_officer_info(id)


func _search(id: int) -> void:
	var result: Dictionary = court.search(king_id, id)
	_show_officers("Search")
	if result.has("recruit"):
		var candidate: int = result["recruit"]
		_confirm(details, "找到人才 %s，是否邀请加入？" % general_names[candidate].strip_edges(),
			_invite.bind(candidate, result["city"]), _show_officers.bind("Search"))
	elif result.has("item"):
		_label(details, "找到了物品：%s" % court.item_name(result["item"]))
	else:
		_label(details, "什么都找不到……")


func _invite(id: int, city: int) -> void:
	var accepted: bool = court.invite(id, city)
	_show_officers("Search")
	_label(details, "%s%s" % [general_names[id].strip_edges(), "加入了我方。" if accepted else "婉拒了邀请。"])


func _show_item_officers() -> void:
	var rows := _court_list("使用物品")
	for id: int in scenario.kings[king_id]["generals"]:
		if scenario.generals[id]["City"] >= 0:
			_button(rows, general_names[id].strip_edges(), _show_inventory.bind(id))


func _show_inventory(id: int) -> void:
	_clear(details)
	var general := scenario.generals[id]
	_label(details, general_names[id].strip_edges())
	var rows := _scroll_rows(details)
	for city_id: int in scenario.kings[king_id]["cities"]:
		var city := scenario.cities[city_id]
		for slot in range(city["objects"].size()):
			var code: int = city["objects"][slot]
			var item := _button(rows, "%s · %s" % [city["Name"], court.item_name(code)],
				_confirm_item.bind(id, city_id, slot))
			item.disabled = not court.can_use_item(general, code)
	if general["Equipment"] >= 0:
		_button(rows, "卸下装备", _confirm_item.bind(id, general["City"], -1))
	if rows.get_child_count() == 0:
		_label(rows, "没有可用物品。")


func _confirm_item(id: int, city: int, slot: int) -> void:
	var caption: String = "卸下装备？" if slot == -1 else "使用%s？" % court.item_name(scenario.cities[city]["objects"][slot])
	_confirm(details, caption, _use_item.bind(id, city, slot), _show_inventory.bind(id))


func _use_item(id: int, city: int, slot: int) -> void:
	if slot == -1:
		court.unequip(king_id, id)
	else:
		court.use_item(king_id, id, city, slot)
	_show_inventory(id)


func _show_prisoners() -> void:
	var rows := _court_list("招降俘虏")
	for city_id: int in scenario.kings[king_id]["cities"]:
		for id: int in scenario.cities[city_id]["prisons"]:
			var button := _button(rows, general_names[id].strip_edges(), _confirm_surrender.bind(id))
			button.disabled = not court.can_surrender(king_id, id)
	if rows.get_child_count() == 0:
		_label(rows, "没有抓到任何武将。")


func _confirm_surrender(id: int) -> void:
	_confirm(details, "将军，请加入我方，共创和平大业。", _surrender.bind(id), _show_prisoners)


func _surrender(id: int) -> void:
	var accepted: bool = court.surrender(king_id, id)
	_show_prisoners()
	_label(details, "%s%s" % [general_names[id].strip_edges(), "加入了我方。" if accepted else "拒绝归降。"])


func _show_promotion() -> void:
	var rows := _court_list("武将升迁")
	for id: int in scenario.kings[king_id]["generals"]:
		if not court.promotion_choices(id).is_empty():
			_button(rows, general_names[id].strip_edges(), _show_jobs.bind(id))
	if rows.get_child_count() == 0:
		_label(rows, "没有可以升迁的武将。")


func _show_jobs(id: int) -> void:
	_clear(details)
	_label(details, "封 %s 为" % general_names[id].strip_edges())
	for job: int in court.promotion_choices(id):
		_button(details, court.tables["jobs"][job], _promote.bind(id, job))


func _promote(id: int, job: int) -> void:
	if court.promote(id, job):
		_show_promotion()
		_label(details, "封 %s 为 %s。" % [general_names[id].strip_edges(), court.tables["jobs"][job]])


func _show_power_map() -> void:
	_build_screen(_court_background(), Rect2(35, 85, 225, 0))
	_label(menu, "势力地图")
	var rows := _scroll_rows(menu)
	var first := -1
	for id in range(scenario.kings.size() - 1):
		if scenario.kings[id]["Active"] == 1:
			_button(rows, scenario.kings[id]["Name"], _select_power.bind(id))
			if first == -1:
				first = id
	_button(menu, "返回", _show_court.bind(""))
	_place_texture(self, POWER_MAP, Vector2(615, 262.5), POWER_MAP.get_size() * 1.5)
	power_markers = Control.new()
	power_markers.position = Vector2(615, 262.5)
	add_child(power_markers)
	details = _panel(Rect2(280, 541, 640, 0))
	if first >= 0:
		_select_power(first)


func _select_power(id: int) -> void:
	_clear(power_markers)
	_clear(details)
	var ruler := scenario.kings[id]
	var names := PackedStringArray()
	for city_id in scenario.cities.size():
		var point: Array = court.tables["map_points"][city_id]
		var selected: bool = ruler["cities"].has(city_id)
		var marker := _place_texture(power_markers, CITY_MARKER,
			Vector2(point[0], -point[1]) * 1.5, CITY_MARKER.get_size() * 1.5)
		marker.modulate = Color.WHITE if selected else Color(0.5, 0, 0, 1)
		if selected:
			names.append(scenario.cities[city_id]["Name"])
	_label(details, "%s　城池 %d　武将 %d" % [ruler["Name"], names.size(), ruler["generals"].size()])
	_label(details, "、".join(names))


func _confirm_end_court() -> void:
	var info := details
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_place_texture(panel, CONFIRM_FRAME, Vector2(429, 600), CONFIRM_FRAME.get_size() * 1.5)
	_source_button(panel, "确定", Rect2(339, 555, 180, 42), _end_court).grab_focus()
	_source_button(panel, "取消", Rect2(339, 600, 180, 42), func() -> void:
		remove_child(panel)
		panel.queue_free()
		details = info
		menu.get_child(9).grab_focus())
	details = panel


func _end_court() -> void:
	if computer_court_year < year:
		court.run_computer_court(king_id)
		computer_court_year = year
	if not strategy_started:
		strategy_started = true
		var ruler: int = scenario.kings[king_id]["GeneralIdx"]
		var city: int = scenario.generals[ruler]["City"]
		if city >= 0:
			_show_city(city)
			return
	_show_strategy("")


func _advance_year() -> void:
	court.start_new_year(king_id)
	_show_court("公元 %d 年，进入内政。" % year)


func _confirm(parent: Control, caption: String, accept: Callable, cancel: Callable) -> void:
	_clear(parent)
	_label(parent, caption)
	_button(parent, "确定", accept).grab_focus()
	_button(parent, "取消", cancel)


func _save_path(slot: int) -> String:
	return save_directory.path_join("unity_court_%02d.cfg" % (slot + 1))


func _show_slots(saving: bool) -> void:
	_build_screen(_court_background() if saving else TITLE, Rect2(225, 150, 510, 0))
	_label(menu, "进度存档" if saving else "继续游戏")
	for slot in range(SAVES.SLOT_COUNT):
		var state := SAVES.read(_save_path(slot))
		var caption := "进度 %d · 空" % (slot + 1)
		if not state.is_empty():
			var ruler: Dictionary = state["kings"][state["king"]]
			caption = "进度 %d · %s · 城数 %02d · 武将 %03d · %d 年" % [
				slot + 1, ruler["Name"], ruler["cities"].size(), ruler["generals"].size(), state["year"]]
		var button := _button(menu, caption, _confirm_save.bind(slot) if saving else _load_slot.bind(slot))
		button.disabled = not saving and state.is_empty()
	_button(menu, "返回", _show_court.bind("") if saving else _show_title)


func _confirm_save(slot: int) -> void:
	_confirm(menu, "保存到进度 %d？" % (slot + 1), _save_slot.bind(slot), _show_slots.bind(true))


func _save_slot(slot: int) -> void:
	var state := {"index": scenario_index, "king": king_id, "year": year,
		"computer_court_year": computer_court_year, "rng_state": rng.state,
		"armies": strategy.armies, "month": strategy.month, "ticks": strategy.ticks,
		"strategy_started": strategy_started,
		"kings": scenario.kings, "cities": scenario.cities, "generals": scenario.generals}
	var error := SAVES.write(_save_path(slot), state)
	_show_slots(true)
	_label(menu, "已保存进度。" if error == OK else "保存失败。")


func _load_slot(slot: int) -> void:
	var state := SAVES.read(_save_path(slot))
	if state.is_empty():
		return
	var loaded := SCENARIO.load_scenario(state["index"])
	if loaded == null:
		return
	loaded.kings.assign(state["kings"])
	loaded.cities.assign(state["cities"])
	loaded.generals.assign(state["generals"])
	scenario = loaded
	court = COURT.new(scenario, rng)
	strategy = STRATEGY.new(scenario, rng)
	strategy.restore_armies(state.get("armies", []))
	strategy.month = state.get("month", 0)
	strategy.ticks = state.get("ticks", 0)
	strategy_started = state.get("strategy_started", false)
	scenario_index = state["index"]
	king_id = state["king"]
	year = state["year"]
	computer_court_year = state.get("computer_court_year", 190)
	if state.has("rng_state"):
		rng.state = state["rng_state"]
	_show_court("已读取进度。")


func _process(delta: float) -> void:
	if strategy_running:
		_step_strategy(delta)


func _step_strategy(delta: float) -> void:
	var event: Dictionary = strategy.advance(delta, king_id)
	if event.has("year_end"):
		year += 1
		_show_strategy_dialogue("内政时间到了....", _advance_year)
	elif event.has("army"):
		_begin_encounter(event["army"], event.get("city", -1), event.get("opponent", {}))
	elif strategy.outcome(king_id) != 0:
		_show_ending(strategy.outcome(king_id) > 0)
	else:
		_update_strategy_map()


func _show_strategy(message: String, running := false) -> void:
	var ending: int = strategy.outcome(king_id)
	if ending != 0:
		_show_ending(ending > 0)
		return
	_zoom_map(_build_background(MAP))
	strategy_running = running
	map_interactive = true
	_add_strategy_markers(_show_city, true)
	menu = _panel(Rect2(20, 18, 200, 0))
	date_label = Label.new()
	menu.add_child(date_label)
	_button(menu, "暂停行军" if running else "继续行军", _show_strategy.bind(message, not running))
	_button(menu, "我方城池", _show_owned_cities)
	if not message.is_empty():
		_label(menu, message)
	_update_strategy_map()


func _add_strategy_markers(select_city: Callable, select_armies := false) -> void:
	map_cities = Control.new()
	add_child(map_cities)
	for id in scenario.cities.size():
		var city := scenario.cities[id]
		var flag := _button(map_cities, city["Name"], select_city.bind(id) if select_city.is_valid() else Callable())
		if not select_city.is_valid():
			flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			flag.focus_mode = Control.FOCUS_NONE
		flag.add_theme_font_size_override("font_size", 13)
		flag.custom_minimum_size = Vector2.ZERO
		flag.size = Vector2(48, 44)
		var padding := StyleBoxEmpty.new()
		padding.content_margin_top = 20
		for state in ["normal", "hover", "pressed", "focus"]:
			flag.add_theme_stylebox_override(state, padding)
		flag.flat = true
		flag.add_theme_color_override("font_outline_color", Color.BLACK)
		flag.add_theme_constant_override("outline_size", 4)
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = flag_frames
		sprite.scale = Vector2(1.5, 1.5)
		sprite.position = Vector2(24, 11)
		sprite.show_behind_parent = true
		flag.add_child(sprite)
	map_armies = Control.new()
	map_armies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_armies.set_meta("select_armies", select_armies)
	add_child(map_armies)
	_update_strategy_map()

func _flag_animation(faction: String) -> StringName:
	return &"neutral" if faction.is_empty() else StringName(faction)


func _load_map_frames(frames: SpriteFrames, atlas: Texture2D, name_text: String) -> void:
	var clips: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/unity_reference/%s.json" % name_text))
	for name_in_data: String in clips:
		var clip := _flag_animation(name_in_data)
		frames.add_animation(clip)
		frames.set_animation_speed(clip, 1.0)
		for frame: Array in clips[name_in_data]:
			var texture := AtlasTexture.new()
			texture.atlas = atlas
			texture.region = Rect2(frame[0], frame[1], frame[2], frame[3])
			frames.add_frame(clip, texture, frame[4])


func _map_position(world: Vector2) -> Vector2:
	return Vector2(480, 360) + Vector2(world.x - map_camera.x, map_camera.y - world.y) * 1.5


func _zoom_map(art: TextureRect) -> void:
	map_view = art
	art.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	art.size = MAP.get_size() * 1.5
	art.position = _map_position(Vector2.ZERO) - art.size / 2.0


func _input(event: InputEvent) -> void:
	if not map_interactive:
		return
	if is_instance_valid(menu) and menu.has_meta("cancel_destination"):
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton
				and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed):
			get_viewport().set_input_as_handled()
			_show_strategy("", true)
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			map_drag_start = event.position
			map_dragging = false
		elif map_dragging:
			get_viewport().set_input_as_handled()
			map_dragging = false
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not map_dragging:
			var offset: Vector2 = (event.position - map_drag_start).abs()
			map_dragging = maxf(offset.x, offset.y) > 7.5
		if map_dragging:
			map_camera += Vector2(-event.relative.x, event.relative.y) / 1.5
			map_camera = map_camera.clamp(Vector2(-320, -240), Vector2(320, 240))
			_update_strategy_map()
			get_viewport().set_input_as_handled()


func _update_strategy_map() -> void:
	map_view.position = _map_position(Vector2.ZERO) - map_view.size / 2.0
	if is_instance_valid(date_label) and date_label.is_inside_tree():
		var month: int = strategy.month + 1
		date_label.text = "西元 %d年%s%d月" % [year, " " if month < 10 else "", month]
	for id in scenario.cities.size():
		var flag: Button = map_cities.get_child(id)
		flag.position = _map_position(strategy.point(id)) - flag.size / 2.0 - Vector2(0, 12)
		var owner: int = scenario.cities[id]["King"]
		if flag.get_meta("owner", -2) != owner:
			var color := Color("#ffe581") if owner == king_id else (Color.WHITE if owner >= 0 else Color("#c9c9c9"))
			flag.add_theme_color_override("font_color", color)
			var sprite: AnimatedSprite2D = flag.get_child(0)
			var animation := _flag_animation(scenario.kings[owner]["Name"].strip_edges()) if owner >= 0 else &"default"
			sprite.visible = animation != &"default" and flag_frames.has_animation(animation)
			if sprite.visible:
				sprite.play(animation)
				if not strategy_running:
					sprite.pause()
			flag.set_meta("owner", owner)
	if map_armies.get_child_count() != strategy.armies.size():
		_clear(map_armies)
		for index in strategy.armies.size():
			var marker := AnimatedSprite2D.new()
			marker.sprite_frames = army_frames
			marker.scale = Vector2(1.5, 1.5)
			var flag := AnimatedSprite2D.new()
			flag.sprite_frames = flag_frames
			marker.add_child(flag)
			map_armies.add_child(marker)
			if map_armies.get_meta("select_armies"):
				var button := Button.new()
				button.flat = true
				button.self_modulate.a = 0.0
				button.size = Vector2(18, 26)
				button.focus_mode = Control.FOCUS_NONE
				button.pressed.connect(_select_map_army.bind(marker))
				marker.add_child(button)
	for index in strategy.armies.size():
		_update_army_marker(map_armies.get_child(index), strategy.armies[index])


func _update_army_marker(marker: AnimatedSprite2D, army: Dictionary) -> void:
	var location: Vector2 = army["position"]
	var direction: Vector2 = army.get("direction", Vector2.LEFT)
	if not army.get("garrison", false) and not army["road"].is_empty():
		var offset: Vector2 = strategy.road_points[army["road"][0]] - location
		if not offset.is_zero_approx():
			direction = offset.normalized()
			army["direction"] = direction
	var diagonal := absf(direction.y) > 0.5
	var direction_index := (1 if direction.y > 0 else 2) if diagonal else 0
	var suffix := ("Up" if direction.y > 0 else "Down") if diagonal else ""
	var clip := StringName(("ArymEscape" if army["retreating"] else "ArmyRun") + suffix)
	if army.get("victory", false):
		clip = StringName("ArymVictory" + suffix)
	if army.get("garrison", false):
		clip = &"ArmyGarrison"
	marker.position = _map_position(location)
	marker.flip_h = direction.x > 0
	if marker.animation != clip or strategy_running and not marker.is_playing():
		marker.play(clip)
	if army.get("garrison", false):
		marker.frame = direction_index
		marker.pause()
	var flag: AnimatedSprite2D = marker.get_child(0)
	var faction := _flag_animation(scenario.kings[army["king"]]["Name"].strip_edges())
	flag.visible = flag_frames.has_animation(faction)
	if flag.visible:
		flag.flip_h = marker.flip_h
		var flag_offset := Vector2(7, 24)
		if diagonal:
			flag_offset.x = (11 if army["retreating"] else 6) if direction.y > 0 else 0
		if army.get("victory", false):
			flag_offset = VICTORY_FLAG_OFFSETS[direction_index][marker.frame]
		elif army.get("garrison", false):
			flag_offset.x = [7, 8, 3][direction_index]
		flag.position = Vector2(flag_offset.x if marker.flip_h else -flag_offset.x, -flag_offset.y)
		if marker.get_child_count() > 1:
			marker.get_child(1).position = flag.position - Vector2(9, 13)
		if flag.animation != faction or strategy_running and not flag.is_playing():
			flag.play(faction)
	if not strategy_running:
		marker.pause()
		flag.pause()


func _show_owned_cities() -> void:
	_build_screen(MAP, Rect2(40, 70, 230, 0))
	_label(menu, "我方城池")
	var rows := _scroll_rows(menu)
	for id: int in scenario.kings[king_id]["cities"]:
		_button(rows, scenario.cities[id]["Name"], _show_city.bind(id))
	_button(menu, "返回地图", _show_strategy.bind(""))


func _show_city(id: int) -> void:
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	menu = Control.new()
	add_child(menu)
	_place_texture(menu, preload("res://assets/unity_reference/275-1.png"), Vector2(180, 270), Vector2(273, 390))
	var city := scenario.cities[id]
	var names := ["部队出征", "部队徵兵", "武将资料", "俘虏资料", "任命太守"]
	var actions: Array[Callable] = [_show_expedition.bind(id), _show_city_officers.bind(id, "征兵"),
		_show_city_officers.bind(id, "武将资料"), _show_city_officers.bind(id, "俘虏资料"),
		_show_city_officers.bind(id, "任命太守")]
	for index in names.size():
		var button := _source_button(menu, names[index], Rect2(57, 204 + index * 45, 246, 42), actions[index])
		button.disabled = (city["King"] != king_id or index == 3 and city["prisons"].is_empty()
			or index == 4 and city["prefect"] == scenario.kings[king_id]["GeneralIdx"])
	_source_button(menu, "返回地图", Rect2(855, 660, 90, 45), _show_strategy.bind(""))
	details = Control.new()
	add_child(details)
	_place_texture(details, preload("res://assets/unity_reference/276-1.png"), Vector2(624, 270), Vector2(597, 390))
	var prefect: int = city["prefect"]
	if prefect >= 0:
		var head := load("res://assets/unity_reference/heads/%d.png" % (prefect + 1)) as Texture2D
		_place_texture(details, head, Vector2(774, 177), Vector2(144, 144))
	var troops := 0
	for officer: int in city["generals"]:
		troops += int(scenario.generals[officer]["SoldierCur"] + scenario.generals[officer]["KnightCur"])
	var owner: int = city["King"]
	var captions := ["时间", "%d年" % year, "太守", general_names[prefect].strip_edges() if prefect >= 0 else "",
		"君主", scenario.kings[owner]["Name"] if owner >= 0 else "", "城名", city["Name"],
		"防御力", str(city["Defense"]), "人口", str(city["Population"]), "金钱", str(city["Money"])]
	for row in 7:
		_court_text(details, captions[row * 2], Vector2(381, 138 + row * 45))
		_court_text(details, captions[row * 2 + 1], Vector2(510, 138 + row * 45))
	var totals := ["武将数", str(city["generals"].size()), "兵数", str(troops), "预备兵",
		"%d/%d" % [city["Reservist"], city["ReservistMax"]], "俘虏", str(city["prisons"].size())]
	for row in 4:
		_court_text(details, totals[row * 2], Vector2(663, 273 + row * 45))
		_court_text(details, totals[row * 2 + 1], Vector2(783, 273 + row * 45))
	move_child(menu, get_child_count() - 1)


func _show_city_officers(city_id: int, action: String) -> void:
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	menu = _panel(Rect2(42, 70, 330, 0))
	_label(menu, action)
	details = _panel(Rect2(570, 100, 345, 0))
	var rows := _scroll_rows(menu)
	var city := scenario.cities[city_id]
	for id: int in city["prisons" if action == "俘虏资料" else "generals"]:
		_button(rows, _officer_with_troops(id), _city_officer_action.bind(city_id, id, action))
	_button(menu, "返回", _show_city.bind(city_id))


func _city_officer_action(city_id: int, id: int, action: String) -> void:
	if action == "征兵":
		_clear(details)
		_label(details, _officer_with_troops(id))
		var reserve: int = scenario.cities[city_id]["Reservist"]
		_label(details, "预备兵 %d" % reserve)
		var amount := SpinBox.new()
		var general := scenario.generals[id]
		amount.min_value = -int(general["KnightCur"] + general["SoldierCur"])
		amount.max_value = reserve
		amount.prefix = "兵力调整 "
		details.add_child(amount)
		_button(details, "确定", func() -> void:
			strategy.adjust_troops(city_id, id, int(amount.value))
			_show_city_officers(city_id, action))
	elif action == "任命太守":
		scenario.cities[city_id]["prefect"] = id
		_show_city(city_id)
	else:
		_show_officer_info(id)


func _show_expedition(origin: int) -> void:
	draft_officers.clear()
	draft_funds = 0
	draft_prisoners = false
	draft_commander = -1
	draft_prefect = -1
	_draw_expedition(origin)


func _expedition_roster(origin: int) -> Array:
	var city := scenario.cities[origin]
	var roster: Array = city["generals"].duplicate()
	roster.reverse()
	if roster.has(city["prefect"]):
		roster.erase(city["prefect"])
		roster.push_front(city["prefect"])
	return roster


func _draw_expedition(origin: int) -> void:
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	menu = Control.new()
	add_child(menu)
	var city := scenario.cities[origin]
	var roster := _expedition_roster(origin)
	var total_troops := 0
	for id in roster:
		total_troops += int(scenario.generals[id]["KnightCur"] + scenario.generals[id]["SoldierCur"])
	var prefect: int = city["prefect"]
	var city_panel := _strategy_panel(Vector2(0, -450))
	_strategy_frame(city_panel, preload("res://assets/unity_reference/285-1.png"), Vector2(480, 84),
		[Rect2(9, 9, 942, 150)])
	_court_text(city_panel, "城市", Vector2(60, 36))
	_court_text(city_panel, city["Name"], Vector2(150, 36))
	_court_text(city_panel, "太守", Vector2(60, 84))
	_court_text(city_panel, general_names[prefect].strip_edges() if prefect >= 0 else "—", Vector2(150, 84))
	for index in 3:
		var y := 36 + index * 48
		_court_text(city_panel, ["武将", "兵数", "金钱"][index], Vector2(405, y))
		_court_text(city_panel, str([roster.size(), total_troops, city["Money"]][index]), Vector2(495, y))
	var funds_panel := _strategy_panel(Vector2(0, -450))
	_strategy_frame(funds_panel, preload("res://assets/unity_reference/287-1.png"), Vector2(123, 306),
		[Rect2(9, 173.25, 228, 79.5), Rect2(9, 264.75, 228, 172.5)])
	_expedition_funds(funds_panel, city["Money"])
	var actions := _strategy_panel(Vector2(-450, 0))
	_strategy_frame(actions, preload("res://assets/unity_reference/286-1.png"), Vector2(123, 591),
		[Rect2(9, 471, 228, 78), Rect2(9, 562.5, 228, 150)])
	var confirm := _source_button(actions, "确定", Rect2(14, 592.5, 218, 42), _prepare_departure.bind(origin))
	confirm.disabled = draft_officers.is_empty()
	_source_button(actions, "取消", Rect2(14, 637.5, 218, 42), _show_city.bind(origin))
	var officers := _strategy_panel(Vector2(450, 0))
	_strategy_frame(officers, preload("res://assets/unity_reference/288-1.png"), Vector2(600, 442.5),
		[Rect2(249, 172.5, 702, 540)])
	var checkbox_off := preload("res://assets/unity_reference/329-1.png")
	var checkbox_on := preload("res://assets/unity_reference/330-1.png")
	for index in roster.size():
		var id: int = roster[index]
		var general := scenario.generals[id]
		var y := 262.5 + index * 45.0
		var selected := draft_officers.has(id)
		var box := _place_texture(officers, checkbox_on if selected else checkbox_off, Vector2(270, y), Vector2(25.5, 25.5))
		var row := Control.new()
		row.position.y = y
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		officers.add_child(row)
		row.modulate = Color.GREEN if selected else Color.WHITE
		var arms := int(log(float(general["arms_current"])) / log(2.0) + 0.5)
		var cells := [general_names[id].strip_edges(), "%02d" % general["Level"],
			str(general["Strength"]), str(general["Intellect"]), court.tables["arms"][arms],
			str(general["KnightCur"] + general["SoldierCur"])]
		for column in cells.size():
			_court_text(row, cells[column], Vector2([297, 456, 567, 674, 756, 886][column], 0))
		var button := _source_button(officers, _officer_with_troops(id), Rect2(249, y - 21, 695, 42), func() -> void:
			_toggle_officer(id)
			box.texture = checkbox_on if draft_officers.has(id) else checkbox_off
			row.modulate = Color.GREEN if draft_officers.has(id) else Color.WHITE
			confirm.disabled = draft_officers.is_empty())
		button.self_modulate.a = 0.0
		button.disabled = general["HealthCur"] <= 0
		if button.disabled:
			row.modulate = Color.GRAY


func _strategy_panel(offset: Vector2) -> Control:
	var panel := Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(panel)
	panel.position = offset
	panel.create_tween().tween_property(panel, "position", Vector2.ZERO, 0.4
		).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	return panel


func _strategy_frame(panel: Control, texture: Texture2D, center: Vector2, fill_areas: Array[Rect2]) -> void:
	for area in fill_areas:
		var fill := _place_texture(panel, preload("res://assets/unity_reference/UI_BG.png"), area.get_center(), area.size)
		fill.stretch_mode = TextureRect.STRETCH_SCALE
		fill.self_modulate.a = 0.5
	_place_texture(panel, texture, center, texture.get_size() * 1.5)


func _expedition_funds(panel: Control, treasury: int) -> void:
	var slider := HSlider.new()
	slider.position = Vector2(60, 304)
	slider.size = Vector2(126, 34)
	slider.max_value = ceilf(treasury / 100.0)
	slider.step = 1
	slider.value = ceilf(draft_funds / 100.0)
	slider.self_modulate.a = 0.0
	panel.add_child(slider)
	_place_texture(panel, preload("res://assets/unity_reference/331-1.png"), Vector2(123, 321), Vector2(130.5, 36))
	var fill := _place_texture(panel, preload("res://assets/unity_reference/349-1.png"), Vector2(123, 321), Vector2(126, 27))
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	var amount := Label.new()
	amount.add_theme_font_override("font", court_font)
	amount.add_theme_font_size_override("font_size", 30)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.position = Vector2(76, 365)
	amount.size.x = 140
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(amount)
	var update_funds := func(step: float) -> void:
		draft_funds = mini(treasury, int(step) * 100)
		amount.text = str(draft_funds)
		fill.visible = step > 0
		fill.size.x = 126.0 * step / maxf(slider.max_value, 1.0)
	slider.value_changed.connect(update_funds)
	update_funds.call(slider.value)
	var left := preload("res://assets/unity_reference/356-1.png")
	var right := preload("res://assets/unity_reference/357-1.png")
	for direction in [-1, 1]:
		var arrow := TextureButton.new()
		arrow.texture_normal = left if direction < 0 else right
		arrow.ignore_texture_size = true
		arrow.stretch_mode = TextureButton.STRETCH_SCALE
		arrow.position = Vector2(22.5 if direction < 0 else 187.5, 303)
		arrow.size = Vector2(36, 36)
		arrow.pressed.connect(func() -> void: slider.value += direction)
		panel.add_child(arrow)


func _officer_with_troops(id: int) -> String:
	var general := scenario.generals[id]
	return "%s · %d 兵" % [general_names[id].strip_edges(), general["SoldierCur"] + general["KnightCur"]]


func _toggle_officer(id: int) -> void:
	if draft_officers.has(id):
		draft_officers.erase(id)
	elif draft_officers.size() < STRATEGY.MAX_OFFICERS:
		draft_officers.append(id)


func _prepare_departure(origin: int) -> void:
	if draft_officers.is_empty():
		return
	var city := scenario.cities[origin]
	if draft_officers.size() == city["generals"].size():
		menu.hide()
		menu = _panel(Rect2(300, 250, 360, 0))
		_confirm(menu, "全体出征将放弃%s，是否继续？" % city["Name"], func() -> void:
			draft_prisoners = true
			_choose_commander(origin), _draw_expedition.bind(origin))
	elif not city["prisons"].is_empty():
		menu.hide()
		menu = _panel(Rect2(300, 250, 360, 0))
		_label(menu, "是否携带俘虏？")
		_button(menu, "是", _take_expedition_prisoners.bind(origin, true))
		_button(menu, "否", _take_expedition_prisoners.bind(origin, false))
	else:
		_choose_commander(origin)


func _take_expedition_prisoners(origin: int, take: bool) -> void:
	draft_prisoners = take
	_choose_commander(origin)


func _expedition_choice(caption: String) -> void:
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	menu = _panel(Rect2(40, 70, 310, 0))
	_label(menu, caption)


func _choose_commander(origin: int) -> void:
	var prefect: int = scenario.cities[origin]["prefect"]
	if draft_officers.size() == 1 or draft_officers.has(prefect):
		draft_commander = prefect if draft_officers.has(prefect) else draft_officers[0]
		_choose_prefect(origin)
		return
	_expedition_choice("选择主将")
	for id in _expedition_roster(origin):
		if draft_officers.has(id):
			_button(menu, general_names[id].strip_edges(), _set_commander.bind(origin, id))
	_button(menu, "取消", _draw_expedition.bind(origin))


func _set_commander(origin: int, id: int) -> void:
	draft_commander = id
	_choose_prefect(origin)


func _choose_prefect(origin: int) -> void:
	var city := scenario.cities[origin]
	var remaining: Array = city["generals"].filter(func(id: int) -> bool: return not draft_officers.has(id))
	if remaining.size() <= 1 or remaining.has(city["prefect"]):
		draft_prefect = city["prefect"] if remaining.has(city["prefect"]) else (remaining[0] if remaining.size() == 1 else -1)
		_show_destinations(origin)
		return
	_expedition_choice("任命新太守")
	for id in _expedition_roster(origin):
		if remaining.has(id):
			_button(menu, general_names[id].strip_edges(), _set_prefect.bind(origin, id))
	_button(menu, "取消", _draw_expedition.bind(origin))


func _set_prefect(origin: int, id: int) -> void:
	draft_prefect = id
	_show_destinations(origin)


func _show_destinations(origin: int) -> void:
	var officers: Array[int] = []
	var roster := _expedition_roster(origin)
	roster.reverse()
	officers.assign(roster.filter(func(id: int) -> bool: return draft_officers.has(id)))
	var army: Dictionary = strategy.form_army(origin, officers, draft_commander,
		draft_prefect, draft_funds, draft_prisoners)
	if not army.is_empty():
		_select_army_destination(army)


func _select_army_destination(army: Dictionary) -> void:
	_zoom_map(_build_background(MAP))
	map_interactive = true
	_add_strategy_markers(func(target: int) -> void:
		if strategy.order_march(army, target):
			_show_strategy("", true))
	menu = Control.new()
	add_child(menu)
	menu.set_meta("cancel_destination", true)
	var banner := _place_texture(menu, CONFIRM_FRAME, Vector2(480, 60), Vector2(386, 75))
	banner.stretch_mode = TextureRect.STRETCH_SCALE
	_court_text(menu, "请选择兵团目的城市", Vector2(333, 60))
	_source_button(menu, "返回", Rect2(855, 660, 90, 45), _show_strategy.bind("", true))


func _select_map_army(marker: AnimatedSprite2D) -> void:
	var army: Dictionary = strategy.armies[marker.get_index()]
	var pointer := get_global_mouse_position()
	var hit := marker.get_child(1) as Button
	if not hit.get_global_rect().has_point(pointer):
		_show_army_commands(army)
		return
	var city := -1
	for candidate: Button in map_cities.get_children():
		if candidate.get_global_rect().has_point(pointer):
			city = candidate.get_index()
			break
	var armies: Array[Dictionary] = []
	for other: AnimatedSprite2D in map_armies.get_children():
		var flag_button := other.get_child(1) as Button
		if flag_button.get_global_rect().has_point(pointer):
			armies.append(strategy.armies[other.get_index()])
	if city < 0 and armies.size() < 2:
		_show_army_commands(army)
		return
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	menu = _panel(Rect2(675, 120, 235, 0))
	if city >= 0:
		_button(menu, "%s城" % scenario.cities[city]["Name"], _show_city.bind(city))
	for selected in armies:
		_button(menu, "%s部队" % general_names[selected["commander"]].strip_edges(), _show_army_commands.bind(selected))
	_button(menu, "返回", _show_strategy.bind("", true))


func _show_army_commands(army: Dictionary) -> void:
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	menu = Control.new()
	add_child(menu)
	var commands := _strategy_panel(Vector2(-450, 0))
	_strategy_frame(commands, preload("res://assets/unity_reference/278-1.png"), Vector2(180, 270),
		[Rect2(48.75, 103.5, 262.5, 78), Rect2(48.75, 196.5, 262.5, 240)])
	var info := _strategy_panel(Vector2(450, 0))
	_strategy_frame(info, preload("res://assets/unity_reference/279-1.png"), Vector2(622.5, 270),
		[Rect2(330, 102, 585, 336)])
	var commander: int = army["commander"]
	var name_text := general_names[commander].strip_edges()
	var troops := 0
	for id in army["officers"]:
		troops += int(scenario.generals[id]["SoldierCur"] + scenario.generals[id]["KnightCur"])
	var owner: int = army["king"]
	var target: int = army["target"]
	var friendly := owner == king_id
	var faction: String = scenario.kings[owner]["Name"] if owner < scenario.kings.size() - 1 else "盗贼"
	_court_text(info, faction + "军", Vector2(352.5, 157.5))
	var labels := ["主将", "目的地", "武将数", "兵数", "俘虏"]
	var values := [name_text, scenario.cities[target]["Name"] if target >= 0 else "---",
		str(army["officers"].size()), str(troops) if friendly else "---",
		str(army["prisons"].size()) if friendly else "---"]
	for index in labels.size():
		var y := 202.5 + index * 45.0
		_court_text(info, labels[index], Vector2(352.5, y))
		_court_text(info, values[index], Vector2(480, y))
	_court_text(info, "金钱", Vector2(666, 382.5))
	_court_text(info, str(army["funds"]) if friendly else "---", Vector2(780, 382.5))
	var head := load("res://assets/unity_reference/heads/%d.png" % (commander + 1)) as Texture2D
	_place_texture(info, head, Vector2(768, 227.25), Vector2(144, 144))
	var city: int = strategy._city_in_range(army["position"], 30.0)
	var command_names := ["武将资料", "变更目的", "部队驻防", "俘虏资料", "进入城内"]
	var actions: Array[Callable] = [
		_show_army_roster.bind(army, "officers"), _select_army_destination.bind(army),
		func() -> void:
			strategy.hold_army(army)
			_show_strategy("", true),
		_show_army_roster.bind(army, "prisons"),
		func() -> void:
			strategy.enter_city(army, city)
			_show_strategy("", true)]
	for index in command_names.size():
		var button := _source_button(commands, command_names[index], Rect2(57, 204 + index * 45, 246, 42), actions[index])
		button.disabled = (not friendly or index == 3 and army["prisons"].is_empty()
			or index == 4 and (city < 0 or scenario.cities[city]["King"] != owner))
	_source_button(menu, "返回", Rect2(855, 660, 90, 45), _show_strategy.bind("", true))


func _show_army_roster(army: Dictionary, roster: String) -> void:
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	menu = _panel(Rect2(60, 90, 260, 0))
	details = _panel(Rect2(350, 90, 420, 0))
	for id: int in army[roster]:
		_button(menu, _officer_with_troops(id), _show_officer_info.bind(id))
	_button(menu, "返回", _show_army_commands.bind(army))


func _begin_encounter(army: Dictionary, target: int, opponent: Dictionary = {}) -> void:
	encounter_army = army
	encounter_opponent = opponent
	encounter_city = target
	encounter_player = -1
	encounter_positions.clear()
	attackers_left.assign(_encounter_roster(true).filter(func(id: int) -> bool: return scenario.generals[id]["HealthCur"] > 0))
	defenders_left.assign(_encounter_roster(false).filter(func(id: int) -> bool: return scenario.generals[id]["HealthCur"] > 0))
	var commander := general_names[army["commander"]].strip_edges()
	var message: String
	if target == -1:
		message = "我军%s部队遭遇%s军，发生战斗！" % [
			commander, general_names[opponent["commander"]].strip_edges()]
	elif army["king"] == king_id:
		message = "我军%s部队攻击%s城！" % [commander, scenario.cities[target]["Name"]]
	else:
		message = "%s城遭到%s军的攻击！" % [scenario.cities[target]["Name"], commander]
	var destination := Vector2(army["position"]).clamp(Vector2(-320, -240), Vector2(320, 240))
	_show_strategy_dialogue(message, _show_encounter)
	if not map_camera.is_equal_approx(destination):
		map_view.create_tween().tween_method(func(position: Vector2) -> void:
			map_camera = position
			_update_strategy_map(), map_camera, destination, map_camera.distance_to(destination) / 500.0)


func _show_strategy_dialogue(message: String, proceed: Callable) -> void:
	_zoom_map(_build_background(MAP))
	_add_strategy_markers(Callable())
	_show_bottom_dialogue(scenario.kings[king_id]["GeneralIdx"], message, proceed)


func _show_bottom_dialogue(speaker: int, message: String, proceed: Callable) -> void:
	var dialogue := Control.new()
	add_child(dialogue)
	dialogue.position.y = 720.0
	var fill := ColorRect.new()
	fill.color = Color8(0, 8, 90, 128)
	fill.position = Vector2(11.25, 11.25)
	fill.size = Vector2(937.5, 169.5)
	dialogue.add_child(fill)
	var frame := preload("res://assets/unity_reference/341-1.png")
	_place_texture(dialogue, frame, Vector2(480, 96), frame.get_size() * 1.5)
	_place_texture(dialogue, preload("res://assets/unity_reference/372-1.png"), Vector2(97.5, 96), Vector2(150, 150))
	var portrait := load("res://assets/unity_reference/heads/%d.png" % (speaker + 1)) as Texture2D
	if portrait != null:
		_place_texture(dialogue, portrait, Vector2(97.5, 96), Vector2(144, 144))
	menu = VBoxContainer.new()
	menu.position = Vector2(195, 40.5)
	menu.size.x = 720.0
	dialogue.add_child(menu)
	_label(menu, message)
	var text := menu.get_child(0) as Label
	text.add_theme_font_override("font", court_font)
	text.add_theme_font_size_override("font_size", 30)
	dialogue.create_tween().tween_property(dialogue, "position:y", 528.0, 0.4)
	_reveal_text(menu.get_child(0), 0.05, proceed, 0.2, true)


func _show_encounter() -> void:
	if attackers_left.is_empty() or defenders_left.is_empty():
		if encounter_city == -1:
			var won := not attackers_left.is_empty()
			strategy.finish_field(encounter_army if won else encounter_opponent,
				encounter_opponent if won else encounter_army)
			_show_strategy("野战胜利" if won else "野战败退", true)
			return
		var city_name: String = scenario.cities[encounter_city]["Name"]
		if not attackers_left.is_empty():
			strategy.enter_city(encounter_army, encounter_city, false)
			_show_strategy("攻克 %s" % city_name, true)
		else:
			strategy.reward_force(scenario.cities[encounter_city]["generals"], false)
			strategy.retreat(encounter_army, encounter_city)
			_show_strategy("进攻%s的军队败退" % city_name, true)
		return
	var attacking: bool = encounter_army["king"] == king_id
	var mine: Array[int] = attackers_left if attacking else defenders_left
	var enemy: Array[int] = defenders_left if attacking else attackers_left
	if encounter_player < 0:
		encounter_player = mine[0]
	encounter_enemy = enemy[rng.randi_range(0, enemy.size() - 1)]
	_show_battle_selection(attacking)


func _encounter_commander(attacker: bool) -> int:
	if attacker:
		return encounter_army["commander"]
	if encounter_city < 0:
		return encounter_opponent["commander"]
	return scenario.cities[encounter_city]["prefect"]


func _encounter_roster(attacker: bool) -> Array:
	var roster: Array
	if attacker:
		roster = encounter_army["officers"].duplicate()
	elif encounter_city < 0:
		roster = encounter_opponent["officers"].duplicate()
	else:
		roster = scenario.cities[encounter_city]["generals"].duplicate()
	var commander := _encounter_commander(attacker)
	if roster.has(commander):
		roster.erase(commander)
		roster.push_front(commander)
	return roster


func _show_battle_selection(attacking: bool, roster_offset := 0) -> void:
	_build_background(preload("res://assets/unity_reference/277-1.png"))
	menu = Control.new()
	add_child(menu)
	var attack_roster := _encounter_roster(true)
	var defend_roster := _encounter_roster(false)
	var mine: Array = attack_roster if attacking else defend_roster
	var enemies: Array = defend_roster if attacking else attack_roster
	var ready: Array[int] = attackers_left if attacking else defenders_left
	var mine_owner: int = scenario.generals[encounter_player]["King"]
	var enemy_owner: int = scenario.generals[encounter_enemy]["King"]
	_battle_selection_bar(menu, enemy_owner, enemies, Vector2(151, 45))
	_battle_selection_bar(menu, mine_owner, mine, Vector2(809, 45))
	for side in 2:
		var roster: Array = enemies if side == 0 else mine
		var available: Array[int] = (defenders_left if attacking else attackers_left) if side == 0 else ready
		var scroll := ScrollContainer.new()
		scroll.position = Vector2(21 if side == 0 else 729, 126)
		scroll.size = Vector2(216, 525)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		menu.add_child(scroll)
		var rows := Control.new()
		rows.custom_minimum_size = Vector2(210, roster.size() * 105)
		scroll.add_child(rows)
		if side == 1 and roster_offset > 0:
			scroll.set_deferred("scroll_vertical", roster_offset)
		for index in roster.size():
			var id: int = roster[index]
			var area := Rect2(0, index * 105, 210, 99)
			var card := ColorRect.new()
			card.color = Color8(23, 10, 80)
			card.position = area.position
			card.size = area.size
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(card)
			var head := load("res://assets/unity_reference/heads/%d.png" % (id + 1)) as Texture2D
			var portrait := _place_texture(card, head, Vector2(52.5 if side == 1 else 157.5, 49.5), Vector2(102, 99))
			if not available.has(id):
				portrait.modulate = Color(0.25, 0.25, 0.25)
			var general := scenario.generals[id]
			_battle_roster_label(card, general_names[id].strip_edges(), 0, side == 1)
			var values := [general["HealthCur"], general["ManaCur"], general["KnightCur"] + general["SoldierCur"]]
			for stat in 3:
				var icon := AtlasTexture.new()
				icon.atlas = preload("res://assets/unity_reference/313-1.png")
				icon.region = Rect2(181 if stat == 2 else 109, 51 + stat * 27, 22, 22)
				var y := 24 + stat * 24
				_place_texture(card, icon, Vector2(117 if side == 1 else 93, y + 13.5), Vector2(24, 24))
				_battle_roster_label(card, str(values[stat]), y, side == 1, true)
			if available.has(id) and id == (encounter_player if side == 1 else encounter_enemy):
				var outline := ReferenceRect.new()
				outline.editor_only = false
				outline.border_color = Color.RED
				outline.border_width = 2.0
				outline.size = area.size
				outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
				card.add_child(outline)
			if side == 1:
				var select := _source_button(rows, _officer_with_troops(id), area, func() -> void:
					encounter_player = id
					var offset := scroll.scroll_vertical
					_show_battle_selection(attacking, offset))
				select.self_modulate.a = 0.0
	_battle_selection_info(encounter_enemy, false, attacking)
	_battle_selection_info(encounter_player, true, attacking)
	_place_texture(menu, preload("res://assets/unity_reference/312-1.png"), Vector2(480, 171), Vector2(96, 96))
	_place_texture(menu, preload("res://assets/unity_reference/307-1.png"), Vector2(480, 600), Vector2(214.5, 229.5))
	var deploy := _source_button(menu, "出战", Rect2(381, 495, 198, 42),
		_start_duel.bind(encounter_player, encounter_enemy, attacking))
	deploy.disabled = not ready.has(encounter_player)
	if not deploy.disabled:
		deploy.grab_focus()
	_source_button(menu, "选择阵形", Rect2(381, 537, 198, 42),
		_show_encounter_formations.bind(attacking)).disabled = not ready.has(encounter_player)
	_source_button(menu, "武将位置", Rect2(381, 579, 198, 42),
		_show_encounter_positions.bind(attacking)).disabled = not ready.has(encounter_player)
	_source_button(menu, "武将资料", Rect2(381, 621, 198, 42), func() -> void:
		details = _panel(Rect2(15, 90, 300, 0))
		_show_officer_info(encounter_player))
	_source_button(menu, "退兵", Rect2(381, 663, 198, 42), _confirm_retreat.bind(attacking))


func _battle_roster_label(card: Control, caption: String, y: float, friendly: bool, stat := false) -> void:
	var label := Label.new()
	label.text = caption
	label.position = Vector2(108 + (24 if stat else 0) if friendly else 0, y)
	label.size.x = 102 - (24 if stat else 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if friendly else HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_override("font", court_font)
	label.add_theme_font_size_override("font_size", 21)
	card.add_child(label)


func _battle_selection_bar(parent: Control, owner: int, officers: Array, center: Vector2) -> void:
	_place_texture(parent, preload("res://assets/unity_reference/293-1.png"), center, Vector2(273, 69))
	var troops := 0
	for id in officers:
		troops += int(scenario.generals[id]["SoldierCur"] + scenario.generals[id]["KnightCur"])
	_court_text(parent, scenario.kings[owner]["Name"] + "军", center - Vector2(120, 0))
	_source_lines(parent, "%d\n%d" % [officers.size(), troops], center + Vector2(75, -29))


func _battle_selection_info(id: int, friendly: bool, attacking: bool) -> void:
	var center := Vector2(615 if friendly else 345, 180)
	var head := load("res://assets/unity_reference/heads/%d.png" % (id + 1)) as Texture2D
	_place_texture(menu, preload("res://assets/unity_reference/372-1.png"), center, Vector2(153, 153))
	_place_texture(menu, head, center, Vector2(147, 147))
	_court_text(menu, general_names[id].strip_edges(), center + Vector2(-36, 105))
	var general := scenario.generals[id]
	var defense := 0
	if encounter_city >= 0 and friendly != attacking:
		defense = scenario.cities[encounter_city]["Defense"]
	var formation: int = general["formation_current"]
	var index := 0
	while formation > 1:
		index += 1
		formation >>= 1
	var caption := "等级 %d\n武力 %d\n智力 %d\n城防 %d\n地形 0\n阵型 %s\n位置 %s" % [
		general["Level"], general["Strength"], general["Intellect"], defense,
		court.tables["formations"][index], "前列" if friendly and encounter_positions.get(id, false) else "后列"]
	_source_lines(menu, caption, center + Vector2(-57, 123), 20, 24)


func _show_encounter_formations(attacking: bool) -> void:
	var panel := _battle_options(Rect2(330, 270, 300, 0))
	var general := scenario.generals[encounter_player]
	for index: int in court.tables["formations"].size():
		var mask := 1 << index
		if general["Formation"] & mask:
			_button(panel, court.tables["formations"][index], func() -> void:
				general["formation_current"] = mask
				_show_battle_selection(attacking))
	_button(panel, "返回", _show_battle_selection.bind(attacking))


func _show_encounter_positions(attacking: bool) -> void:
	var panel := _battle_options(Rect2(585, 550, 130, 0))
	for front in [false, true]:
		_button(panel, "前列" if front else "后列", func() -> void:
			encounter_positions[encounter_player] = front
			_show_battle_selection(attacking))
	_button(panel, "取消", _show_battle_selection.bind(attacking))


func _battle_options(area: Rect2) -> VBoxContainer:
	for button: Button in menu.find_children("*", "Button", true, false):
		button.disabled = true
	var panel := _panel(area)
	details = panel
	return panel


func _confirm_retreat(attacking: bool) -> void:
	var panel := _battle_options(Rect2(585, 558, 165, 0))
	_confirm(panel, "确定退兵？", _retreat_encounter, _show_battle_selection.bind(attacking))


func _retreat_encounter() -> void:
	_show_encounter_report("情况不妙全军撤退....", _resolve_retreat_encounter)


func _resolve_retreat_encounter() -> void:
	if encounter_city >= 0:
		if encounter_army["king"] == king_id:
			strategy.reward_force(scenario.cities[encounter_city]["generals"], false)
			strategy.retreat(encounter_army, encounter_city)
		else:
			var defenders: Array[int] = []
			defenders.assign(scenario.cities[encounter_city]["generals"])
			scenario.cities[encounter_city]["generals"].clear()
			strategy._evacuate(encounter_city, defenders)
			strategy.enter_city(encounter_army, encounter_city, false)
	else:
		strategy.finish_field(encounter_opponent, encounter_army)
	_show_strategy("我军撤退", true)


func _start_duel(player: int, enemy: int, attacking: bool) -> void:
	_clear(self)
	battle = BATTLE.instantiate()
	battle.campaign_battle = true
	battle.battlefield_sky = preload("res://assets/unity_reference/1620-1.png")
	battle.battlefield_wall = preload("res://assets/unity_reference/1609-1.png")
	battle.friendly_front = encounter_positions.get(player, false)
	battle.battlefield_ground = preload("res://assets/unity_reference/1626-1.png")
	for id in [player, enemy]:
		var general := scenario.generals[id]
		general["HealthCur"] = mini(general["HealthMax"], general["HealthCur"] + 10)
		general["ManaCur"] = mini(general["ManaMax"], general["ManaCur"] + 5)
	_set_battle_side(player, true)
	_set_battle_side(enemy, false)
	battle.battle_finished.connect(_finish_duel.bind(player, enemy, attacking),
		CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	battle.battle_timed_out.connect(_duel_timed_out.bind(player, enemy), CONNECT_DEFERRED | CONNECT_ONE_SHOT)
	battle.assault_ordered.connect(_show_assault_order)
	add_child(battle)
	battle.presentation_paused = true
	_show_battle_intro(false)


func _show_battle_intro(friendly: bool) -> void:
	var id: int = battle.friendly_officer["Index"] if friendly else battle.enemy_officer["Index"]
	var greetings := ["就让你看看我的厉害！", "反贼，还不速速下马受缚！",
		"不知死活的家伙，这不是你该来的地方！", "你的人头我是要定了，有什么遗言快交代吧！",
		"和我%s交手，你一定会后悔的！", "敢和我%s交手？来吧！", "谁敢和我%s交手！",
		"我乃%s，不怕死的人尽管过来吧！", "和我%s交手是你一生最大的错误！",
		"%s在此，谁敢与我决一死战！", "我乃%s是也！", "我是%s，来比试一下吧！"]
	var text: String = greetings[rng.randi_range(0, greetings.size() - 1)]
	if text.contains("%s"):
		text = text % general_names[id].strip_edges()
	_show_battle_dialogue(friendly, text, _finish_battle_intro if friendly else _show_battle_intro.bind(true))
	battle.presentation_focus.y = 335.0


func _show_battle_dialogue(friendly: bool, text: String, proceed: Callable) -> void:
	if is_instance_valid(menu) and menu.is_inside_tree():
		remove_child(menu)
		menu.queue_free()
	var id: int = battle.friendly_officer["Index"] if friendly else battle.enemy_officer["Index"]
	menu = Control.new()
	menu.position = Vector2(0, 519)
	add_child(menu)
	var frame := _place_texture(menu, preload("res://assets/unity_reference/313-1.png"), Vector2(480, 102), Vector2(960, 204))
	frame.flip_h = not friendly
	var fill := ColorRect.new()
	fill.color = Color8(0, 8, 90)
	fill.position = Vector2(7.5 if friendly else 157.5, 6)
	fill.size = Vector2(795, 189)
	menu.add_child(fill)
	var portrait: Texture2D = battle.friendly_portrait if friendly else battle.enemy_portrait
	_place_texture(menu, portrait, Vector2(877.5 if friendly else 82.5, 78), Vector2(144, 144))
	var name_text := general_names[id].strip_edges()
	var name_width := court_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	_court_text(menu, name_text, Vector2((882 if friendly else 78) - name_width / 2.0, 178.5))
	var line := Label.new()
	line.text = text
	line.position = Vector2(22.5 if friendly else 172.5, 23.5)
	line.size = Vector2(774, 147)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_override("font", court_font)
	line.add_theme_font_size_override("font_size", 30)
	menu.add_child(line)
	var general: Dictionary = battle.blue_general if friendly else battle.red_general
	battle.presentation_focus = Vector2(960.0 - general["position"].x, general["position"].y)
	_reveal_text(line, 0.05, proceed, 0.0, true)


func _finish_battle_intro() -> void:
	_resume_battle()
	battle._show_unity_commands()


func _show_assault_order(friendly: bool) -> void:
	battle.presentation_paused = true
	battle.assault_side = 1 if friendly else -1
	_show_battle_dialogue(friendly, "全军突击！", _resume_battle)


func _resume_battle() -> void:
	remove_child(menu)
	menu.queue_free()
	battle.presentation_paused = false
	battle.assault_side = 0


func _set_battle_side(id: int, friendly: bool) -> void:
	var general := scenario.generals[id]
	var portrait := load("res://assets/unity_reference/heads/%d.png" % (id + 1)) as Texture2D
	var name_text := general_names[id].strip_edges()
	if friendly:
		battle.friendly_officer = general
		battle.friendly_name = name_text
		battle.friendly_soldiers = general["SoldierCur"]
		battle.friendly_knights = general["KnightCur"]
		battle.friendly_health = general["HealthCur"]
		battle.friendly_portrait = portrait
	else:
		battle.enemy_officer = general
		battle.enemy_name = name_text
		battle.enemy_soldiers = general["SoldierCur"]
		battle.enemy_knights = general["KnightCur"]
		battle.enemy_health = general["HealthCur"]
		battle.enemy_portrait = portrait


func _finish_duel(victory: bool, _friendly_count: int, _enemy_count: int,
		player: int, enemy: int, attacking: bool) -> void:
	var escaped: bool = (battle.red_general_order if victory else battle.blue_general_order) == battle.Order.RETREAT
	var lines := ["不要脸，每次都逃！", "哼，下次再宰了你！", "说到逃跑，你倒是满在行的....",
		"不知羞耻的家伙，有胆回头再与我较量！", "别跑那么快，小心跌下马来！"] if escaped else [
		"凭这两三招也敢出来献丑！", "你想赢我，还早一百年啊！", "就这点本事，也敢出来！",
		"早说过你会后悔的....", "真是不堪一击！", "要我手下留情，不嫌太晚了吗！",
		"凭你的身手，滚回家吃奶吧，哈哈哈...."]
	battle.presentation_paused = true
	_show_battle_dialogue(victory, lines[rng.randi_range(0, lines.size() - 1)],
		_resolve_duel.bind(victory, player, enemy, attacking, escaped))


func _resolve_duel(victory: bool, player: int, enemy: int, attacking: bool, escaped: bool) -> void:
	_record_battle_side(player, battle.blue_general, battle.blue_units)
	_record_battle_side(enemy, battle.red_general, battle.red_units)
	var winner := player if victory else enemy
	var loser := enemy if victory else player
	court.award_battle_experience(winner)
	var winner_info := scenario.generals[winner]
	strategy.mark_defeated(loser, winner_info["King"], escaped)
	if victory == attacking:
		defenders_left.erase(loser)
	else:
		attackers_left.erase(loser)
	battle = null
	var finished := attackers_left.is_empty() or defenders_left.is_empty()
	var message := ""
	var speaker := player
	if finished:
		var won: bool = not attackers_left.is_empty() if attacking else not defenders_left.is_empty()
		message = "我军大获全胜！！" if won else "我军战败...."
	elif victory:
		message = "我军大胜！俘虏敌将%s！" % general_names[loser].strip_edges() if scenario.generals[loser]["prisonerIdx"] == king_id else "我军胜利！！"
	else:
		message = "我战败被俘了...." if scenario.generals[loser]["prisonerIdx"] == winner_info["King"] else "很遗憾，我战败了...."
	if finished or victory:
		speaker = _encounter_commander(attacking)
	_show_battle_selection(attacking)
	_show_encounter_report(message, _show_encounter, speaker)


func _show_encounter_report(message: String, proceed: Callable, speaker := -1) -> void:
	for button: Button in find_children("*", "Button", true, false):
		button.disabled = true
	if speaker < 0:
		speaker = _encounter_commander(encounter_army["king"] == king_id)
	_show_bottom_dialogue(speaker, message, proceed)


func _duel_timed_out(player: int, enemy: int) -> void:
	_record_battle_side(player, battle.blue_general, battle.blue_units)
	_record_battle_side(enemy, battle.red_general, battle.red_units)
	battle = null
	_show_encounter()


func _record_battle_side(id: int, officer: Dictionary, units: Array[Dictionary]) -> void:
	var general := scenario.generals[id]
	general["HealthCur"] = maxi(0, ceili(officer["health"]))
	general["ManaCur"] = officer.get("mana", general["ManaCur"])
	general["SoldierCur"] = 0
	general["KnightCur"] = 0
	for unit in units:
		if not unit.get("general", false) and unit["health"] > 0:
			var key := "KnightCur" if unit["knight"] else "SoldierCur"
			general[key] += 1


func _show_ending(victory: bool) -> void:
	if victory:
		game_passed = true
		var progress := ConfigFile.new()
		progress.set_value("progress", "GamePass", 1)
		progress.save(progress_path)
		_show_strategy_dialogue("经过多年的征战，统一中国的梦想终于实现了！", _show_victory_record)
	else:
		_show_strategy_dialogue("很遗憾，统一中国的梦想无法实现了....", _show_defeat_art)


func _show_victory_record() -> void:
	var dialogue := menu.get_parent() as Control
	var exit := dialogue.create_tween()
	exit.tween_property(dialogue, "position:y", 720.0, 0.4)
	exit.tween_callback(dialogue.queue_free)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.18, 0.75)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := preload("res://assets/unity_reference/328-1.png")
	_place_texture(shade, frame, Vector2(480, 360), frame.get_size() * 3.0)
	var text := Label.new()
	text.position = Vector2(225, 328)
	text.size = Vector2(510, 64)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	text.add_theme_font_size_override("font_size", 22)
	text.text = "于西元%d年，%s统一了全中国。" % [year, scenario.kings[king_id]["Name"].strip_edges()]
	shade.add_child(text)
	menu = shade
	_reveal_text(text, 0.5, _show_credits)


func _reveal_text(label: Label, seconds: float, proceed: Callable, delay := 0.0, skippable := false) -> void:
	var count := label.text.length()
	label.visible_characters = 0
	var reveal := label.create_tween()
	reveal.tween_interval(delay)
	reveal.tween_method(func(characters: float) -> void:
		label.visible_characters = floori(characters), 0.0, float(count), count * seconds)
	var advance := Button.new()
	advance.name = "DialogueAdvance"
	advance.flat = true
	advance.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(advance)
	advance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	advance.grab_focus()
	advance.pressed.connect(func() -> void:
		if label.visible_characters == count:
			remove_child(advance)
			advance.queue_free()
			proceed.call()
		elif skippable:
			reveal.kill()
			label.visible_characters = count)


func _show_defeat_art() -> void:
	_build_background(DEFEAT_ART)
	menu = _ending_exit()


func _ending_exit() -> Button:
	var advance := Button.new()
	advance.flat = true
	advance.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_child(advance)
	advance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	advance.disabled = true
	advance.pressed.connect(_show_title)
	var wait := advance.create_tween()
	wait.tween_interval(2.0)
	wait.tween_callback(func() -> void:
		advance.disabled = false
		advance.grab_focus())
	wait.tween_interval(8.0)
	wait.tween_callback(_show_title)
	return advance


func _show_credits() -> void:
	_build_background(DEFEAT_ART)
	var black := ColorRect.new()
	black.color = Color.BLACK
	add_child(black)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var size_on_screen := CREDITS_ART.get_size() * 1.5
	var credits := _place_texture(black, CREDITS_ART, Vector2(480, 735 + size_on_screen.y / 2.0), size_on_screen)
	var roll := credits.create_tween()
	roll.tween_property(credits, "position:y", credits.position.y - 2925.0, 39.0)
	roll.tween_callback(func() -> void: menu = _ending_exit())


func _scroll_rows(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 340
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	return rows


func _build_screen(background: Texture2D, area: Rect2) -> void:
	_build_background(background)
	menu = _panel(area)


func _build_background(background: Texture2D) -> TextureRect:
	map_interactive = false
	strategy_running = false
	_clear(self)
	if (background == TITLE or background in HALLS or background == MAP and strategy_started) and DisplayServer.get_name() != "headless":
		var stream: AudioStream = TITLE_MUSIC if background == TITLE else (MAP_MUSIC if background == MAP else COURT_MUSIC)
		if music_source != stream:
			music_source = stream
			court_music.stream = stream.duplicate()
			court_music.stream.loop = true
		if not court_music.playing:
			court_music.play()
	elif court_music.playing:
		court_music.stop()
	var art := TextureRect.new()
	art.texture = background
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return art


func _place_texture(parent: Control, texture: Texture2D, center: Vector2, dimensions: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = center - dimensions / 2.0
	art.size = dimensions
	parent.add_child(art)
	return art


func _panel(area: Rect2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = area.position
	panel.custom_minimum_size.x = area.size.x
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.07, 0.04, 0.92)
	style.border_color = Color("#aa8650")
	style.set_border_width_all(2)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	panel.add_child(list)
	return list


func _label(parent: Control, caption: String) -> void:
	var label := Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 19)
	parent.add_child(label)


func _button(parent: Control, caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size", 19)
	if callback.is_valid():
		button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _clear(parent: Node) -> void:
	for child in parent.get_children():
		if child == court_music or child == title_effect:
			continue
		parent.remove_child(child)
		child.queue_free()
