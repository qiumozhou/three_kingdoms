extends SceneTree

const OPENING := preload("res://scenes/unity_opening.tscn")
const BATTLE_RULES := preload("res://scripts/unity_battle_rules.gd")

var failures := 0


func _initialize() -> void:
	await process_frame
	var opening := OPENING.instantiate()
	opening.progress_path = ProjectSettings.globalize_path("res://.godot/opening-test-%d.cfg" % OS.get_process_id())
	root.add_child(opening)
	opening.rng.seed = 190
	opening.game_passed = false
	_expect(opening.menu.size == Vector2(235.5, 207.0)
		and _find_button(opening.menu, "音量设定") != null
		and _find_button(opening.menu, "结束游戏") != null,
		"title uses the original panel dimensions and menu entries")
	_press(opening.menu, "开始游戏")
	_expect(opening.scenario_index == 1 and opening.menu.get_child_count() == 9,
		"first game opens the seven MOD02 rulers")
	_press(opening.menu, "曹操")
	_press(opening.details, "取消")
	_expect(opening.king_id == -1, "cancel clears ruler selection")
	_press(opening.menu, "曹操")
	_press(opening.details, "确定")
	var scenario: UnityScenario = opening.scenario
	var city := scenario.cities[9]
	var defense: int = city["Defense"]
	var population: int = city["Population"]
	_expect(not scenario.can_assign(0, 98, "Defense"), "ruler cannot be assigned")
	_press(opening.menu, "筑  城")
	_press(opening.menu, "夏侯惇")
	_expect(city["Defense"] > defense and city["Defense"] <= defense + 39 + scenario.generals[56]["Strength"] - 81,
		"fortification uses Unity defense formula")
	_expect(not scenario.can_assign(0, 56, "Defense"), "fortification consumes general's action")
	_advance_dialogue(opening)
	_press(opening.menu, "返回")
	_press(opening.menu, "开  发")
	_press(opening.menu, "曹仁")
	_expect(city["Population"] >= population + 9000
		and city["Population"] <= population + 9999 + (scenario.generals[93]["Intellect"] - 80) * 100 - 1,
		"development uses Unity population formula")
	_expect(not scenario.can_assign(0, 93, "Population"), "development consumes general's action")
	_advance_dialogue(opening)
	_press(opening.menu, "返回")
	await _test_expedition(opening, scenario)
	var neutral := scenario.kings.size() - 1
	var original_owner: int = scenario.cities[7]["King"]
	scenario.cities[7]["King"] = neutral
	opening._update_strategy_map()
	opening._show_city(7)
	_expect(opening.menu.get_child_count() > 0, "a bandit city remains selectable after its ruler is defeated")
	scenario.cities[7]["King"] = original_owner
	opening._show_strategy("", true)
	opening.strategy.month = 11
	opening.strategy.ticks = 9
	opening._step_strategy(0.5)
	_expect(opening.menu.get_child(0).text == "内政时间到了....", "annual change displays the Unity dialogue")
	_advance_dialogue(opening)
	await _test_campaign_end(opening, scenario)
	_press(opening.menu, "开始游戏")
	_expect(opening.menu.get_child_count() == 7, "completed game offers all five scenarios")
	_press(opening.menu, "剧本 5")
	_expect(opening.scenario_index == 4 and opening.menu.get_child_count() == 7,
		"selecting a scenario opens its rulers")
	DirAccess.remove_absolute(opening.progress_path)
	print("Unity opening tests: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)


func _test_campaign_end(opening: Control, scenario: UnityScenario) -> void:
	_expect(opening.year == 191, "the 190 Cao Cao campaign enters its second year")
	_press(opening.menu, "内政终了")
	_press(opening.details, "确定")
	# Stage the last city so this replay covers the real victory trigger without playing 48 sieges.
	opening.strategy.armies.clear()
	for city in scenario.cities:
		city["King"] = 0
	scenario.cities[6]["King"] = -1
	scenario.cities[6]["generals"].clear()
	var officers: Array[int] = [56]
	var army: Dictionary = opening.strategy.dispatch(9, 6, officers, 56, 93, 0, false)
	_expect(not army.is_empty(), "Cao Cao can send the final expedition")
	opening._show_strategy("", true)
	opening._step_strategy(opening.strategy.route_distance(9, 6) / 10.0 + 0.1)
	_expect(scenario.cities[6]["King"] == 0 and not opening.game_passed,
		"taking the final empty city leaves the map running until the next strategy scene")
	opening.strategy.month = 11
	opening.strategy.ticks = 9
	opening._step_strategy(0.5)
	_advance_dialogue(opening)
	_press(opening.menu, "内政终了")
	_press(opening.details, "确定")
	_expect(opening.game_passed, "returning to strategy unlocks scenarios after the final city")
	_advance_dialogue(opening)
	var record := opening.menu.get_child(1) as Label
	_expect(record != null and record.text == "于西元192年，曹操统一了全中国。",
		"the victory presentation uses the year and ruler of this playthrough")
	if record == null:
		return
	record.visible_characters = record.text.length()
	(opening.get_node("DialogueAdvance") as Button).pressed.emit()
	await process_frame
	for tween in get_processed_tweens():
		tween.custom_step(39.1)
	if not opening.menu is Button:
		_expect(false, "credits allow return after scrolling")
		return
	for tween in get_processed_tweens():
		tween.custom_step(2.1)
	_expect(not opening.menu.disabled, "the ending unlocks the return click after two seconds")
	opening.menu.pressed.emit()


func _test_expedition(opening: Control, scenario: UnityScenario) -> void:
	var target := scenario.cities[8]
	var attacker := scenario.generals[98]
	var previous_owner: int = target["King"]
	for general in scenario.generals:
		if general["King"] != 0:
			general["HealthMax"] = mini(50, general["HealthMax"])
	_press(opening.menu, "内政终了")
	_expect(opening.menu.visible, "ending the court keeps the original command list visible")
	_press(opening.details, "取消")
	_expect(not opening.strategy_started, "cancelling the confirmation stays in court")
	_press(opening.menu, "内政终了")
	_press(opening.details, "确定")
	var defeated_attacker := scenario.generals[93]
	_depart(opening, 93)
	var transit: float = opening.strategy.route_distance(9, 8) / 10.0
	_expect(opening.battle == null and defeated_attacker["City"] == -1, "departure creates a marching army")
	var marker := opening.map_armies.get_child(0) as AnimatedSprite2D
	_expect(marker != null and marker.is_playing() and marker.sprite_frames.get_frame_count(marker.animation) == 6
		and marker.get_child(0).animation == &"曹操", "the marching army uses the original horse animation and faction flag")
	opening._step_strategy(transit + 0.1)
	_expect(opening.menu.get_child(0).text == "我军曹仁部队攻击濮阳城！",
		"the original attack announcement precedes officer selection")
	_advance_dialogue(opening)
	_expect(opening._encounter_roster(false)[0] == target["prefect"], "the city prefect leads the battle roster")
	_press(opening.menu, opening._officer_with_troops(93))
	_press(opening.menu, "武将位置")
	_press(opening.details, "前列")
	_press(opening.menu, "退兵")
	_press(opening.details, "取消")
	_press(opening.menu, "出战")
	_advance_dialogue(opening)
	_advance_dialogue(opening)
	if not is_instance_valid(opening.battle):
		_expect(false, "first expedition enters battle")
		return
	_expect(opening.battle.friendly_front, "the chosen officer starts the duel in the front row")
	_expect(opening.battle.commands_open, "the opening dialogue leads to Unity's paused battle command menu")
	var paused_seconds: float = opening.battle.battle_seconds
	_press(opening.battle, "加速")
	opening.battle._physics_process(1.0)
	_expect(opening.battle.battle_seconds == paused_seconds, "the command menu pauses the battle clock")
	_press(opening.battle.unity_commands, "返回")
	opening.battle._physics_process(0.25)
	_expect(is_equal_approx(opening.battle.battle_seconds, paused_seconds + 0.5), "acceleration advances two battle steps")
	_press(opening.battle, "正常")
	_expect(opening.battle.battle_speed == 1, "normal speed restores single battle steps")
	opening.battle._show_unity_commands()
	var troops: int = defeated_attacker["SoldierCur"]
	_press(opening.battle.unity_commands, "全军撤退")
	for frame in 1800:
		if opening.battle.battle_over:
			break
		opening.battle._physics_process(1.0 / 60.0)
		if opening.battle.assault_side != 0:
			_advance_dialogue(opening)
	await process_frame
	_expect(is_instance_valid(opening.battle) and opening.battle.presentation_paused,
		"the winner's dialogue keeps the battlefield visible after the duel")
	_advance_dialogue(opening)
	_expect(opening.menu.get_child(0).text == "我军战败....",
		"losing the last officer displays the original campaign report before returning to the map")
	opening.strategy.elapsed = 0.35
	var month: int = opening.strategy.month
	var ticks: int = opening.strategy.ticks
	_advance_dialogue(opening)
	_expect(opening.strategy.elapsed == 0.0 and opening.strategy.month == month and opening.strategy.ticks == ticks,
		"returning from battle restarts the partial reserve tick without losing the calendar")
	_expect(opening.battle == null and target["King"] == previous_owner
		and defeated_attacker["City"] == -1 and defeated_attacker["SoldierCur"] == troops
		and opening.strategy_running, "retreat preserves surviving troops and resumes the strategy clock")
	opening._step_strategy(transit - minf(3.0, transit / 2.0) + 0.1)
	_expect(defeated_attacker["City"] == 9, "retreating army returns to its friendly city")
	_depart(opening, 98)
	opening._step_strategy(transit + 0.1)
	_advance_dialogue(opening)
	_press(opening.menu, opening._officer_with_troops(98))
	_press(opening.menu, "出战")
	_advance_dialogue(opening)
	_advance_dialogue(opening)
	_expect(is_instance_valid(opening.battle), "expedition enters battle")
	if not is_instance_valid(opening.battle):
		return
	_press(opening.battle.unity_commands, "全军待机")
	var attacker_count: int = opening.attackers_left.size()
	var defender_count: int = opening.defenders_left.size()
	opening.battle.battle_seconds = 99.0
	opening.battle._physics_process(0.0)
	await process_frame
	_expect(opening.battle == null and opening.attackers_left.size() == attacker_count
		and opening.defenders_left.size() == defender_count, "timeout returns to selection with neither side defeated")
	_press(opening.menu, opening._officer_with_troops(98))
	_press(opening.menu, "出战")
	_advance_dialogue(opening)
	_advance_dialogue(opening)
	var battle: Node2D = opening.battle
	_press(battle.unity_commands, "全军待机")
	var defender: Dictionary = battle.enemy_officer
	_expect(battle.friendly_name == "曹操" and battle.enemy_health == float(defender["HealthCur"]),
		"battle receives actual attacker and defender")
	_expect(battle.blue_units.size() == attacker["SoldierCur"] + attacker["KnightCur"] + 1
		and battle.red_units.size() == defender["SoldierCur"] + defender["KnightCur"] + 1,
		"battle spawns both armies from scenario counts")
	_expect(battle.friendly_portrait != null and battle.enemy_portrait != null
		and battle.battlefield_sky != null and battle.battlefield_ground != null,
		"battle loads original portraits and environment")
	_expect(battle.blue_units[0]["atlas"] == "Green01"
		and battle.blue_units[0]["position"] == Vector2(69, 320),
		"Cao Cao's troops use Unity arms and formation coordinates")
	var rules: RefCounted = battle.unity_rules
	var walk_start: Array = rules.soldier_frame("Red01", false, "Run", 0.0)
	var walk_next: Array = rules.soldier_frame("Red01", false, "Run", 0.18)
	_expect(walk_start != walk_next, "Unity soldier animation advances using frame durations")
	var general_parts: Array[String] = battle.blue_general["parts"]
	_expect(general_parts == ["Horse001", "General004_Green", "Head003"],
		"Cao Cao uses Unity's horse, armor and head for the player's right side")
	for part in general_parts:
		var pose: Array = rules.general_frame(part, "Run", 0.18)
		_expect(rules.atlas_texture(pose[0]) != null and pose[1].size() == 6,
			"original general layer resolves to a texture and frame")
	_expect(BATTLE_RULES.block_chance(0, 3) == 20 and BATTLE_RULES.block_chance(3, 0) == 80
		and BATTLE_RULES.block_chance(10, 4) == 60, "asymmetric Unity arms counters")
	_expect(BATTLE_RULES.general_hit_chance(110, 70, true) == 81
		and BATTLE_RULES.general_hit_chance(0, 100, false) == 51, "Unity general hit chances")
	_test_mixed_formation(rules)
	_test_projectile(battle)
	_test_orders(opening, battle)
	_test_spell_groups(battle)
	_test_all_spells(battle)
	var initial_mana: int = battle.blue_general["mana"]
	battle._cast_skill()
	_expect(battle.pending_spell.is_empty() and battle.blue_general["mana"] == initial_mana,
		"an uncharged spell consumes no mana")
	battle.blue_general["charge"] = 132.0
	battle._cast_skill()
	_expect(battle.pending_spell.get("id") == 19 and battle.blue_general["mana"] == initial_mana - 20,
		"Cao Cao casts the configured Divine Sword with its Unity mana cost")
	battle._update_spell(2.5)
	_expect(battle.pending_spell.is_empty(), "Divine Sword resolves after its casting delay")
	for unit: Dictionary in battle.red_units:
		unit["health"] = 0.0
	battle._physics_process(0.0)
	await process_frame
	_advance_dialogue(opening)
	_advance_dialogue(opening)
	_expect(opening.battle == null and defender["HealthCur"] == 0 and defender["SoldierCur"] == 0,
		"battle result returns to map and records casualties")
	_expect(attacker["ManaCur"] == initial_mana - 20, "battle records remaining mana")
	if not opening.defenders_left.is_empty():
		_expect(target["King"] != 0, "remaining defenders keep control of city")
	for _duel in opening.defenders_left.size():
		_press(opening.menu, opening._officer_with_troops(98))
		_press(opening.menu, "出战")
		_advance_dialogue(opening)
		_advance_dialogue(opening)
		if not is_instance_valid(opening.battle):
			_expect(false, "next defender starts a new duel")
			break
		_press(opening.battle.unity_commands, "全军待机")
		for unit: Dictionary in opening.battle.red_units:
			unit["health"] = 0.0
		opening.battle._physics_process(0.0)
		await process_frame
		_advance_dialogue(opening)
		var last_duel: bool = opening.defenders_left.is_empty()
		if last_duel:
			attacker["prisonerIdx"] = previous_owner
		_advance_dialogue(opening)
		if last_duel:
			_expect(attacker["prisonerIdx"] == -1 and opening.menu.get_child(0).text == "我们被俘的武将救回来了!",
				"the winning side releases its previously captured officers before settlement")
			for report in 8:
				if not opening.has_node("DialogueAdvance"):
					break
				_advance_dialogue(opening)
	_expect(target["King"] == 0 and attacker["City"] == 8 and target["prefect"] == 98,
		"clearing defenders transfers city and places the attacker there")
	_expect(not scenario.kings[previous_owner]["cities"].has(8) and scenario.kings[0]["cities"].has(8),
		"city is moved between faction rosters")


func _depart(opening: Control, id: int) -> void:
	if _find_button(opening.menu, "部队出征") == null:
		_press(opening.menu, "我方城池")
		_press(opening.menu, "陈留")
	_press(opening.menu, "部队出征")
	var confirm := _find_button(opening.menu, "确定")
	_expect(confirm != null and confirm.disabled, "expedition requires a selected officer")
	_press(opening.menu, opening._officer_with_troops(id))
	_expect(not confirm.disabled, "selecting an officer enables expedition confirmation")
	_press(opening.menu, "确定")
	if id == 98:
		_press(opening.menu, "夏侯惇")
	if id == 93:
		var army: Dictionary = opening.strategy.armies.back()
		_expect(army["officers"] == [93] and army["target"] == -1 and army["garrison"],
			"expedition forms an army before a destination is picked")
		_press(opening.menu, "返回")
		_select_army_flag(opening, army)
		_expect(not opening.strategy_running, "selecting the army flag pauses the campaign map")
		_press(opening.menu, "进入城内")
		_expect(not opening.strategy.armies.has(army) and opening.scenario.generals[93]["City"] == 9,
			"a stationary army can rejoin the friendly city")
		_press(opening.map_cities, "陈留")
		_press(opening.menu, "部队出征")
		_press(opening.menu, opening._officer_with_troops(93))
		_press(opening.menu, "确定")
		army = opening.strategy.armies.back()
		_press(opening.map_cities, "濮阳")
		_select_army_flag(opening, army)
		_press(opening.menu, "部队驻防")
		var position: Vector2 = army["position"]
		opening._step_strategy(0.1)
		_expect(army["garrison"] and army["position"] == position, "garrison order halts an army on its route")
		_select_army_flag(opening, army)
		_press(opening.menu, "变更目的")
	_press(opening.map_cities, "濮阳")


func _select_army_flag(opening: Control, army: Dictionary) -> void:
	var marker: Node = opening.map_armies.get_child(opening.strategy.armies.find(army))
	(marker.get_child(1) as Button).pressed.emit()


func _test_mixed_formation(rules: RefCounted) -> void:
	var left: Array[Vector3i] = rules.formation_slots(1, 6, 4, true)
	var right: Array[Vector3i] = rules.formation_slots(1, 6, 4, false)
	_expect(left.size() == 10 and left[0] == Vector3i(48, 0, 2)
		and left[3] == Vector3i(48, 64, 3) and left[7] == Vector3i(-48, 0, 0),
		"Unity deploys the cavalry within the front rank and preserves the back rank")
	_expect(right.size() == 10 and right[3] == Vector3i(-48, 64, 3),
		"Unity right side uses its recorded coordinates")
	_expect(rules.formation_slots(4, 6, 4, true) == left, "mask 4 aliases Unity formation 1")


func _test_projectile(battle: Node2D) -> void:
	var saved: Array[Dictionary] = battle.red_units.duplicate()
	var target := {"position": Vector2(250, 324), "health": 1.0, "arms": 0}
	battle.red_units.assign([target])
	var shooter := {"position": Vector2(200, 320), "health": 1.0, "arms": 3,
		"side": 1.0, "facing": 1.0}
	battle._queue_projectile(shooter)
	battle._update_projectiles(0.2)
	_expect(battle.projectiles[0]["position"] == shooter.position and target.health == 1.0,
		"projectile does not leave before the firing pose")
	battle._update_projectiles(0.4)
	_expect(battle.projectiles.size() == 1 and target.health == 1.0,
		"projectile passes a target outside its flight lane")
	target.position = Vector2(300, 320)
	battle._update_projectiles(0.2)
	_expect(battle.projectiles.is_empty(), "same-lane collision consumes the projectile")
	battle.red_units.assign(saved)


func _test_orders(opening: Control, battle: Node2D) -> void:
	battle._apply_unity_order(0)
	var front := 0
	var back := 0
	for unit: Dictionary in battle.blue_units:
		if unit.get("front", false) and unit.has("order"):
			front += 1
		elif not unit.get("front", false) and unit.has("order"):
			back += 1
	_expect(front > 0 and back == 0, "front-rank command leaves the commander and rear rank unchanged")
	battle._set_blue_order(battle.Order.HOLD)
	battle._show_unity_commands()
	_press(battle.unity_commands, "全军突击")
	_expect(battle.presentation_paused and battle.assault_side == 1
		and battle.blue_general_order == battle.Order.HOLD, "player assault pauses for the order and holds the commander")
	_advance_dialogue(opening)
	_expect(not battle.presentation_paused and battle.assault_side == 0, "acknowledging assault resumes combat")
	battle._update_enemy_command(14.0)
	_expect(battle.presentation_paused and battle.assault_side == -1
		and battle.red_order == battle.Order.ADVANCE and battle.red_general_order == battle.Order.HOLD,
		"enemy assault pauses for the order and sends troops before its commander")
	_advance_dialogue(opening)
	battle._update_enemy_command(9.0)
	_expect(battle.red_general_order == battle.Order.ADVANCE, "enemy commander follows its troops")


func _test_spell_groups(battle: Node2D) -> void:
	var caster: Dictionary = battle.blue_general
	var initial_mana: int = caster["mana"]
	var initial_health: float = caster.health
	var initial_spell: int = caster["spell"]
	caster["spell"] = 37
	caster["charge"] = 132.0
	caster.health = 5.0
	battle._cast_skill()
	_expect(caster.health == 45.0 and caster["mana"] == initial_mana - 30,
		"Recuperation uses original healing and mana cost")
	caster["spell"] = 39
	caster["charge"] = 132.0
	caster["mana"] = initial_mana
	battle._cast_skill()
	_expect(battle.red_units[0]["magic_lock"] == 5.0 and not battle.red_general.has("magic_lock"),
		"Eight Gates locks soldiers for five seconds and excludes the general")
	caster["spell"] = initial_spell
	caster["charge"] = 60.0
	caster["mana"] = initial_mana
	caster.health = initial_health


func _test_all_spells(battle: Node2D) -> void:
	var saved_blue: Array[Dictionary] = battle.blue_units.duplicate(true)
	var saved_red: Array[Dictionary] = battle.red_units.duplicate(true)
	var rules: RefCounted = battle.unity_rules
	_expect(rules.spells.size() == 50, "all Unity magic configurations loaded")
	for id in range(50):
		battle.blue_units.assign(saved_blue.duplicate(true))
		battle.red_units.assign(saved_red.duplicate(true))
		battle.blue_general = battle.blue_units.back()
		battle.red_general = battle.red_units.back()
		battle.blue_general["spell"] = id
		battle.blue_general["mana"] = 100
		battle.blue_general["charge"] = 132.0
		battle._cast_skill()
		_expect(battle.blue_general["mana"] == 100 - rules.spells[id]["mp"],
			"skill %d uses its original mana cost" % id)
		for _tick in range(100):
			battle._update_spell(0.1)
			battle._update_composite_spell(0.1)
		_expect(battle.pending_spell.is_empty() and battle.composite_spells.is_empty()
			and battle.composite_states.is_empty(), "skill %d finishes its effects" % id)
	battle.blue_units.assign(saved_blue)
	battle.red_units.assign(saved_red)
	battle.blue_general = battle.blue_units.back()
	battle.red_general = battle.red_units.back()


func _advance_dialogue(opening: Control) -> void:
	var advance := opening.get_node_or_null("DialogueAdvance") as Button
	_expect(advance != null, "strategy dialogue has a click target")
	if advance != null:
		advance.pressed.emit()
		if advance.is_inside_tree():
			advance.pressed.emit()


func _press(parent: Node, caption: String) -> void:
	var button := _find_button(parent, caption)
	_expect(button != null, "button exists: %s" % caption)
	if button != null:
		button.pressed.emit()


func _find_button(parent: Node, caption: String) -> Button:
	if parent == null:
		return null
	for child in parent.get_children():
		if child is Button and child.text == caption:
			return child
		var nested := _find_button(child, caption)
		if nested != null:
			return nested
	return null


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
