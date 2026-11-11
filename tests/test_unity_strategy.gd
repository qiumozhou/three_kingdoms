extends SceneTree

const STRATEGY := preload("res://scripts/unity_strategy.gd")
const SAVES := preload("res://scripts/unity_court_save.gd")
const OPENING := preload("res://scenes/unity_opening.tscn")

var failures := 0


func _initialize() -> void:
	await process_frame
	var world := UnityScenario.load_scenario(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 190
	var strategy := STRATEGY.new(world, rng)
	_test_routes(strategy)
	_test_march(world, strategy)
	_test_computer_reinforcement()
	_test_computer_casualties()
	_test_computer_damage_boundaries()
	_test_field()
	_test_army_state_timing()
	_test_retreat_to_lost_city()
	_test_garrison_evacuation()
	_test_outcomes()
	print("Unity strategy tests: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)


func _test_routes(strategy: RefCounted) -> void:
	var routes := PackedStringArray()
	for origin in 48:
		for target in 48:
			routes.append(",".join(PackedStringArray(strategy.route(origin, target))))
	# Produced by running the reference MyPathfinding.cs on the Strategy.unity nodes.
	var expected := "6a6c31f3b92dd31ee5ec646845b0138fc701ca423db394c29657edde8a9496f4"
	_expect("\n".join(routes).sha256_text() == expected, "all 2304 routes match the Unity C# implementation")
	_expect(strategy.route(9, 8) == [88, 87, 86, 85, 84, 83, 82], "MOD02 expedition uses all seven road waypoints")


func _test_march(world: UnityScenario, strategy: RefCounted) -> void:
	_expect(strategy.point(0).is_equal_approx(Vector2(482.23, 401.735)), "map uses Unity's city positions")
	_expect(strategy.route(9, 8).size() > 1 and strategy.route(9, 47).size() > 1, "paths follow the Unity city graph")
	var city := world.cities[9]
	var funds: int = city["Money"]
	var reserve: int = city["Reservist"]
	var officers: Array[int] = [56, 93]
	var army: Dictionary = strategy.dispatch(9, 8, officers, 56, 98, 123, false)
	_expect(not army.is_empty() and army["officers"] == [56, 93] and army["commander"] == 56,
		"expedition carries multiple officers and appointed commander")
	_expect(world.generals[56]["City"] == -1 and not city["generals"].has(56)
		and city["Money"] == funds - 123, "dispatch removes soldiers and funds from source city")
	var start: Vector2 = army["position"]
	strategy.advance(0.49, 0)
	_expect(city["Reservist"] == reserve and absf(start.distance_to(army["position"]) - 4.9) < 0.001,
		"marching uses Unity speed before the first reserve tick")
	strategy.advance(0.01, 0)
	_expect(city["Reservist"] == reserve + 1 and city["Money"] == funds - 223,
		"half-second tick adds one reserve and costs 100")
	var path := ProjectSettings.globalize_path("res://.godot/strategy-test-%d.cfg" % OS.get_process_id())
	var state := {"index": 1, "king": 0, "year": 190, "armies": strategy.armies,
		"kings": world.kings, "cities": world.cities, "generals": world.generals}
	_expect(SAVES.write(path, state) == OK and SAVES.read(path)["armies"][0]["position"] == army["position"],
		"marching army position and route survive a save round trip")
	DirAccess.remove_absolute(path)
	for general in world.generals:
		if general["King"] != 0:
			general["HealthMax"] = mini(50, general["HealthMax"])
	var event: Dictionary = strategy.advance(strategy.route_distance(9, 8) / 10.0, 0)
	_expect(event.get("city") == 8 and event.get("army") == army and world.cities[8]["King"] != 0,
		"enemy city produces a battle event and stays under its current owner")
	world.generals[139]["SoldierCur"] = 0
	strategy.adjust_troops(9, 139, 3)
	_expect(world.generals[139]["SoldierCur"] == 3, "conscription uses the city reserve")
	strategy.adjust_troops(9, 139, -2)
	_expect(world.generals[139]["SoldierCur"] == 1, "released troops return to the reserve")
	strategy.armies.clear()
	var returning_officers: Array[int] = [139]
	var returning: Dictionary = strategy.dispatch(9, 9, returning_officers, 139, 98, 50, false)
	_expect(not returning.is_empty(), "the origin city can be selected as the destination")
	strategy.advance(0.0, 0)
	_expect(strategy.armies.is_empty() and city["generals"].has(139)
		and world.generals[139]["City"] == 9 and city["prefect"] == 98,
		"the returning officer joins the garrison without replacing the prefect")


func _test_computer_reinforcement() -> void:
	var world := UnityScenario.load_scenario(1)
	var rng := RandomNumberGenerator.new()
	var strategy := STRATEGY.new(world, rng)
	var source := world.cities[6]
	var destination := world.cities[8]
	source["King"] = 1
	source["Money"] = 500
	source["generals"] = [98, 93, 56]
	source["prefect"] = 98
	source["prisons"] = [139]
	destination["King"] = 1
	destination["generals"] = []
	for id in [98, 93, 56]:
		world.generals[id]["HealthCur"] = 80
		world.generals[id]["City"] = 6
	# The original CityAct and SetArmyMove received the same rolls: 95, 2, 395, 63.
	rng.seed = 30
	strategy._computer_city_act(destination, 0)
	_expect(strategy.armies.size() == 1, "a weak friendly city calls in reinforcements")
	if strategy.armies.size() != 1:
		return
	var army: Dictionary = strategy.armies[0]
	_expect(army["origin"] == 6 and army["target"] == 8 and army["officers"] == [56, 93]
		and army["commander"] == 56 and army["prisons"] == [139] and army["funds"] == 395
		and source["Money"] == 500 and source["generals"] == [98],
		"reinforcement selects from the end of the roster and keeps the original dispatch funding behavior")


func _test_field() -> void:
	var world := UnityScenario.load_scenario(1)
	var strategy := STRATEGY.new(world, RandomNumberGenerator.new())
	var a: Dictionary = strategy.dispatch(9, 8, [56], 56, 98, 0, false)
	var enemy_city := world.cities[8]
	var other: Array = enemy_city["generals"]
	var commander: int = other.back()
	var prefect: int = other.front() if other.size() > 1 else -1
	var b: Dictionary = strategy.dispatch(8, 9, [commander], commander, prefect, 0, false)
	_expect(not b.is_empty(), "opposing army can leave its garrison")
	if b.is_empty():
		return
	b["position"] = a["position"] + Vector2(9, 0)
	var event: Dictionary = strategy.advance(0.0, 0)
	_expect(event.get("army") == a and event.get("opponent") == b, "opposing armies within ten units trigger field battle")
	strategy.finish_field(a, b)
	_expect(b["retreating"] and b["target"] == 8 and not a["retreating"],
		"field battle loser turns back while winner retains its route")


func _test_army_state_timing() -> void:
	var world := UnityScenario.load_scenario(1)
	var strategy := STRATEGY.new(world, RandomNumberGenerator.new())
	var army: Dictionary = strategy.dispatch(9, 0, [56], 56, 98, 0, false)
	army["road"] = [0]
	army["victory"] = true
	army["state_time"] = 0.0
	var start: Vector2 = army["position"]
	strategy._move_armies(2.9, 0)
	_expect(army["position"] == start, "the victorious army stays in place during Unity's three-second celebration")
	strategy._move_armies(0.2, 0)
	_expect(not army["victory"] and is_equal_approx(start.distance_to(army["position"]), 1.0),
		"the victorious army resumes its route after the celebration")
	army["retreating"] = true
	army["state_time"] = 0.0
	start = army["position"]
	strategy._move_armies(3.0, 0)
	_expect(army["retreating"] and is_equal_approx(start.distance_to(army["position"]), 60.0),
		"the retreating army moves at double speed for the first three seconds")
	strategy._move_armies(0.1, 0)
	_expect(not army["retreating"] and absf(start.distance_to(army["position"]) - 61.0) < 0.001,
		"the retreating army resumes normal speed and can encounter enemies again")


func _test_retreat_to_lost_city() -> void:
	var world := UnityScenario.load_scenario(1)
	var strategy := STRATEGY.new(world, RandomNumberGenerator.new())
	var army: Dictionary = strategy.dispatch(9, 8, [56], 56, 98, 0, false)
	world.cities[9]["King"] = 1
	world.kings[0]["cities"].clear()
	army["position"] = strategy.point(8)
	strategy.retreat(army, 8)
	_expect(strategy.armies.has(army) and army["origin"] == 8 and army["target"] == 9,
		"losing the origin city preserves the retreating army and Unity's original return destination")
	army["road"] = [int(strategy.roads["cities"][9])]
	army["position"] = strategy.point(9)
	var event: Dictionary = strategy._move_armies(0.0, 0)
	_expect(event.get("army") == army and event.get("city") == 9,
		"reaching the captured origin produces a battle even during the escape interval")


func _test_garrison_evacuation() -> void:
	var world := UnityScenario.load_scenario(1)
	var strategy := STRATEGY.new(world, RandomNumberGenerator.new())
	var officers: Array[int] = [56, 93, 98, 139, 52, 58, 87]
	for id in officers:
		world.generals[id]["King"] = 0
	strategy._evacuate(9, officers)
	_expect(strategy.armies.size() == 2 and strategy.armies[0]["officers"] == [87, 58, 52, 139, 98]
		and strategy.armies[1]["officers"] == [93, 56] and strategy.armies[0]["commander"] == 98,
		"the defeated garrison evacuates from the roster's end in five-officer groups and gives the ruler command")


func _test_computer_casualties() -> void:
	var world := UnityScenario.load_scenario(1)
	var rng := RandomNumberGenerator.new()
	var strategy := STRATEGY.new(world, rng)
	var winner := world.generals[56]
	var loser := world.generals[98]
	winner.merge({"King": 0, "Level": 1, "Experience": 0, "KnightCur": 10, "SoldierCur": 20,
		"Strength": 80, "HealthCur": 200, "HealthMax": 200, "ManaCur": 10, "ManaMax": 10}, true)
	loser.merge({"King": 1, "Level": 1, "KnightCur": 2, "SoldierCur": 5,
		"Strength": 80, "HealthCur": 20, "ManaCur": 0}, true)
	world.cities[9]["generals"] = [56]
	world.cities[9]["prefect"] = 56
	world.cities[8]["King"] = 1
	world.cities[8]["generals"] = [98]
	world.cities[8]["prefect"] = 98
	var a: Dictionary = strategy.dispatch(9, 8, [56], 56, -1, 0, false)
	var b: Dictionary = strategy.dispatch(8, 9, [98], 98, -1, 0, false)
	rng.seed = 190
	var expected := RandomNumberGenerator.new()
	expected.seed = 190
	expected.randi_range(0, 19)
	var damage := 212 + expected.randi_range(0, 19)
	strategy._resolve_computer_field(a, b)
	_expect(winner["Experience"] == 150 and winner["HealthCur"] == 405 - damage
		and winner["KnightCur"] == 0 and winner["SoldierCur"] == 0 and winner["ManaCur"] == 0,
		"automatic battle awards duel and campaign experience and carries the winning army's losses")
	_expect(loser["HealthCur"] == 2 and loser["ManaCur"] == 2
		and loser["KnightCur"] == 0 and loser["SoldierCur"] == 0,
		"the automatic battle loser retains Unity's two health and two mana")


func _test_computer_damage_boundaries() -> void:
	var world := UnityScenario.load_scenario(1)
	var strategy := STRATEGY.new(world, RandomNumberGenerator.new())
	# Outputs from the original ArmyController.WarResult and CheckIsLevelUp C# methods.
	var cases := [[20, 20, 20, 10, 200], [80, 10, 20, 10, 200], [86, 9, 20, 10, 200],
		[140, 0, 20, 10, 200], [143, 0, 19, 10, 200], [200, 0, 0, 10, 200],
		[205, 0, 0, 0, 200], [211, 0, 0, 0, 194], [405, 0, 0, 0, 15]]
	for level in [1, 6]:
		for result: Array in cases:
			var general := world.generals[56]
			general.merge({"Level": level, "Experience": 1970 if level == 6 else 0,
				"KnightCur": 10, "SoldierCur": 20, "KnightMax": 100, "SoldierMax": 100,
				"Strength": 80, "HealthCur": 200, "HealthMax": 200, "ManaCur": 10, "ManaMax": 10}, true)
			strategy._resolve_computer_duel(56, 93, result[0])
			strategy.reward_force([56], true)
			_expect(general["Experience"] == (2573 if level == 6 else 150)
				and [general["KnightCur"], general["SoldierCur"], general["ManaCur"], general["HealthCur"]] == result.slice(1),
				"automatic battle matches the original C# at level %d and damage %d" % [level, result[0]])


func _test_outcomes() -> void:
	var opening := OPENING.instantiate()
	var path := ProjectSettings.globalize_path("res://.godot/victory-test-%d.cfg" % OS.get_process_id())
	opening.progress_path = path
	root.add_child(opening)
	opening._show_kings(1)
	opening.king_id = 0
	for city: Dictionary in opening.scenario.cities:
		city["King"] = 0
	opening._show_strategy("")
	var progress := ConfigFile.new()
	_expect(progress.load(path) == OK and progress.get_value("progress", "GamePass") == 1,
		"owning every city records the original game-clear unlock")
	var restarted := OPENING.instantiate()
	restarted.progress_path = path
	root.add_child(restarted)
	_expect(restarted.game_passed and UnityScenario.available_scenarios(restarted.game_passed).size() == 5,
		"new title reads the persisted unlock")
	var advance := opening.get_node("DialogueAdvance") as Button
	_expect(opening.menu.get_child(0).text == "经过多年的征战，统一中国的梦想终于实现了！",
		"victory starts with the original ruler dialogue")
	advance.pressed.emit()
	advance.pressed.emit()
	_expect(opening.menu.get_child(1).text == "于西元190年，曹操统一了全中国。",
		"victory records the year and the selected ruler before credits")
	opening.scenario.kings[0]["Active"] = 0
	opening._show_strategy("")
	_expect(opening.strategy.outcome(0) == -1 and opening.menu.get_child(0).text == "很遗憾，统一中国的梦想无法实现了....",
		"an eliminated player faction reaches the defeat ending")
	opening.queue_free()
	restarted.queue_free()
	DirAccess.remove_absolute(path)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
