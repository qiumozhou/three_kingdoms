extends SceneTree

const SCENARIO := preload("res://scripts/unity_scenario.gd")

var failures := 0


func _initialize() -> void:
	_expect(SCENARIO.available_scenarios(false) == [1], "new game defaults to MOD02")
	_expect(SCENARIO.available_scenarios(true) == [0, 1, 2, 3, 4], "clear unlocks all five scenarios")
	_expect(SCENARIO.load_scenario(-1) == null, "invalid scenario index is rejected")
	var king_counts := [14, 18, 8, 8, 5]
	var selectable_counts := [6, 7, 5, 5, 5]
	for index in range(5):
		var scenario := SCENARIO.load_scenario(index)
		_expect(scenario != null, "scenario %d loads" % index)
		if scenario == null:
			continue
		_expect(scenario.kings.size() == king_counts[index] + 1, "king count includes extra slot")
		_expect(SCENARIO.selectable_count(index) == selectable_counts[index], "selectable count")
		_expect(scenario.cities.size() == 48 and scenario.generals.size() == 255, "full city and general lists")
		if index == 1:
			_expect(scenario.kings[0]["Name"] == "曹操" and scenario.kings[0]["cities"] == [9],
				"MOD02 starts Cao Cao in Chenliu")
			_expect(scenario.cities[9]["Name"] == "陈留" and scenario.cities[9]["prefect"] == 98,
				"the ruler takes precedence as prefect")
			_expect(scenario.generals[0]["job"] == 27 and scenario.generals[0]["arms_current"] == 1
				and scenario.generals[0]["formation_current"] == 32, "Unity general initialization")
			_expect(scenario.generals[1]["City"] == -1, "unaffiliated general is removed from city roster")
	print("Unity scenario tests: %d failure(s)" % failures)
	quit(0 if failures == 0 else 1)


func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
