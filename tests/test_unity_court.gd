extends SceneTree

const OPENING := preload("res://scenes/unity_opening.tscn")
const BATTLE_RULES := preload("res://scripts/unity_battle_rules.gd")

var failures := 0


func _initialize() -> void:
	await process_frame
	var opening := OPENING.instantiate()
	root.add_child(opening)
	opening.game_passed = false
	_press(opening.menu, "开始游戏")
	_press(opening.menu, "曹操")
	_press(opening.details, "确定")
	await _test_layout(opening)
	var world: UnityScenario = opening.scenario
	_test_commands(opening, world)
	_test_year(opening, world)
	_test_save(opening, world)
	var rules := BATTLE_RULES.new()
	_expect(rules.formation_slots(1, 100, 0, true).size() == 100
		and rules.formation_slots(64, 0, 100, false).size() == 100,
		"high-level armies preserve all 100 slots in either side")
	opening.queue_free()
	await process_frame
	print("Unity court tests: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)


func _test_layout(opening: Control) -> void:
	await create_timer(0.45).timeout
	var command: Button = opening.menu.get_child(1)
	_expect(command.get_global_rect().get_center().is_equal_approx(Vector2(255, 217.5)),
		"command lands at its Unity screen coordinate, got %s" % command.get_global_rect().get_center())
	_expect(opening.court_music.stream is AudioStreamOggVorbis, "court uses original music")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = command.get_global_rect().get_center()
	click.pressed = true
	root.push_input(click, true)
	click = click.duplicate()
	click.pressed = false
	root.push_input(click, true)
	_expect(opening.menu.get_child(0).text == "使用物品", "main court button receives actual GUI input")
	_press(opening.menu, "返回")


func _test_commands(opening: Control, world: UnityScenario) -> void:
	_expect(opening.menu.get_child_count() == 12, "original court has 11 commands and its background")
	var city := world.cities[9]
	var ruler := world.generals[98]
	var strength: int = ruler["Strength"]
	var intellect: int = ruler["Intellect"]
	var roll := RandomNumberGenerator.new()
	for value in range(100):
		roll.seed = value
		var outcome := roll.randi_range(0, 99)
		if outcome >= 40 and outcome < 60:
			opening.rng.seed = value
			break
	_press(opening.menu, "搜  索")
	_press(opening.menu, "夏侯惇")
	_expect(city["objects"].size() == 1 and world.generals[56]["active"] == 0,
		"search stores equipment and consumes the searcher's action")
	_press(opening.menu, "返回")

	city["objects"].assign([1 << 16, (2 << 16) | 8, (3 << 16) | 64])
	_press(opening.menu, "使用物品")
	_press(opening.menu, "曹操")
	_press(opening.details, "陈留 · 孙子兵法")
	_press(opening.details, "确定")
	_expect(ruler["Equipment"] == 0 and ruler["Strength"] == strength - 9
		and ruler["Intellect"] == intellect + 10 and city["objects"][0] == (1 << 16) + 11,
		"equipment swap applies original bonuses and returns the previous item")
	_press(opening.details, "陈留 · 弓箭兵兵符")
	_press(opening.details, "确定")
	_expect((ruler["Arms"] & 8) != 0 and city["objects"].size() == 2,
		"an arms token unlocks the original troop type and is consumed")
	_press(opening.details, "陈留 · 鉤形阵法之书")
	_press(opening.details, "确定")
	_expect((ruler["Formation"] & 64) != 0, "formation manual adds its formation mask")
	_press(opening.menu, "返回")

	_press(opening.menu, "武将资料")
	_press(opening.menu, "曹操")
	_press(opening.details, "弓箭兵")
	_press(opening.details, "鉤形阵法")
	_expect(ruler["arms_current"] == 8 and ruler["formation_current"] == 64,
		"officer information can switch learned battle options")
	_press(opening.menu, "返回")

	var captive := world.generals[1]
	captive["City"] = 9
	captive["King"] = 0
	captive["prisonerIdx"] = 0
	city["prisons"].append(1)
	_press(opening.menu, "招降俘虏")
	_press(opening.menu, "于禁")
	_press(opening.details, "确定")
	_expect(captive["prisonerIdx"] == -1 and city["generals"].has(1)
		and not city["prisons"].has(1) and captive["SoldierCur"] == captive["SoldierMax"],
		"friendly captives automatically rejoin with full troops")
	_press(opening.menu, "返回")

	ruler["Level"] = 10
	_press(opening.menu, "武将升迁")
	_press(opening.menu, "曹操")
	_press(opening.details, "虎威将军")
	_expect(ruler["Magic1"] == 29 and ruler["job"] == 29,
		"promotion writes the original job and unlocks its battle skill")
	_press(opening.menu, "返回")
	_press(opening.menu, "势力地图")
	_press(opening.menu, "曹操")
	_expect(opening.power_markers.get_child_count() == 48, "power map shows every city")
	_press(opening.menu, "返回")


func _test_year(opening: Control, world: UnityScenario) -> void:
	var prisoner := world.generals[0]
	prisoner["City"] = 9
	prisoner["prisonerIdx"] = 0
	world.cities[9]["prisons"].append(0)
	var funds: int = world.cities[9]["Money"]
	var population: int = world.cities[9]["Population"]
	var injured := world.generals[98]
	injured["HealthCur"] = 0
	_press(opening.menu, "内政终了")
	_press(opening.details, "确定")
	_expect(prisoner["loyalty"] == 100, "first court does not execute computer actions")
	_press(opening.menu, "返回地图")
	_press(opening.menu, "继续行军")
	for general in world.generals:
		if general["King"] != 0:
			general["HealthMax"] = mini(50, general["HealthMax"])
	opening._step_strategy(60.0)
	var advance := opening.get_node("DialogueAdvance") as Button
	advance.pressed.emit()
	advance.pressed.emit()
	@warning_ignore("integer_division")
	var reserve_cost := mini(world.cities[9]["ReservistMax"], (funds - 1) / 100) * 100
	_expect(opening.year == 191 and world.generals[56]["active"] == 1
		and world.cities[9]["Money"] == funds - reserve_cost + int(2250 + population / 133.34),
		"yearly income and action reset use Unity rules")
	_expect(injured["HealthCur"] == 44, "eleven strategic months recover health at Unity's monthly rate")
	_press(opening.menu, "内政终了")
	_press(opening.details, "确定")
	var loyalty: int = prisoner["loyalty"]
	_expect(loyalty >= 81 and loyalty <= 95, "later computer court applies original loyalty decay")
	opening._show_court()
	_press(opening.menu, "内政终了")
	_press(opening.details, "确定")
	_expect(prisoner["loyalty"] == loyalty, "computer court does not repeat within the same year")
	opening._show_court()


func _test_save(opening: Control, world: UnityScenario) -> void:
	var directory := ProjectSettings.globalize_path("res://.godot/court-test-%d" % OS.get_process_id())
	_expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "test save directory is writable")
	opening.save_directory = directory
	_press(opening.menu, "进度存档")
	_expect(opening.menu.get_child_count() == 10, "save screen has eight slots")
	_press(opening.menu, "进度 1 · 空")
	_press(opening.menu, "确定")
	var slot := "%s/unity_court_01.cfg" % directory
	_expect(FileAccess.file_exists(slot), "save writes the selected slot")
	_press(opening.menu, "返回")
	world.cities[9]["Money"] += 17
	_press(opening.menu, "进度存档")
	_press(opening.menu, "进度 1 · 曹操 · 城数 01 · 武将 %03d · 191 年" % world.kings[0]["generals"].size())
	_press(opening.menu, "确定")

	var restarted := OPENING.instantiate()
	root.add_child(restarted)
	restarted.save_directory = directory
	_press(restarted.menu, "继续游戏")
	_press(restarted.menu, "进度 1 · 曹操 · 城数 01 · 武将 %03d · 191 年" % world.kings[0]["generals"].size())
	_expect(restarted.year == 191 and restarted.computer_court_year == 191
		and restarted.scenario != null and restarted.scenario.cities[9] == world.cities[9]
		and restarted.scenario.generals[98] == world.generals[98],
		"fresh opening reloads the overwritten slot with inventories and officer state")
	restarted.queue_free()
	DirAccess.remove_absolute(slot)
	DirAccess.remove_absolute(directory)


func _press(parent: Node, caption: String) -> void:
	for node in parent.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text == caption and not button.disabled:
			button.pressed.emit()
			return
	_expect(false, "expected an enabled button: %s" % caption)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
