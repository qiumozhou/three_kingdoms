extends RefCounted

const EQUIPMENT := 1
const ARMS := 2
const FORMATION := 3

var tables: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
	"res://assets/unity_reference/court_tables.json"))
var scenario: UnityScenario
var rng: RandomNumberGenerator


func _init(world: UnityScenario, random: RandomNumberGenerator) -> void:
	scenario = world
	rng = random


func can_search(king: int, officer: int) -> bool:
	var general := scenario.generals[officer]
	return (general["King"] == king and general["City"] >= 0 and general["active"] == 1
		and general["prisonerIdx"] == -1 and officer != scenario.kings[king]["GeneralIdx"]
		and (general["Strength"] >= 85 or general["Intellect"] >= 85))


func search(king: int, officer: int) -> Dictionary:
	if not can_search(king, officer):
		return {}
	var general := scenario.generals[officer]
	general["active"] = 0
	@warning_ignore("integer_division")
	var outcome := rng.randi_range(0, 99) / 20
	return _search_city(general["City"], outcome, 50)


func _search_city(city_id: int, outcome: int, inventory_limit: int) -> Dictionary:
	var city := scenario.cities[city_id]
	if outcome == 1:
		var free: Array[int] = []
		for id in range(scenario.generals.size()):
			if scenario.generals[id]["King"] == -1 and scenario.generals[id]["prisonerIdx"] == -1:
				free.append(id)
		if not free.is_empty():
			return {"recruit": free[rng.randi_range(0, free.size() - 1)], "city": city_id}
	elif outcome >= 2 and city["objects"].size() < inventory_limit:
		var code := 0
		match outcome:
			2:
				code = (EQUIPMENT << 16) | rng.randi_range(0, tables["equipment"].size() - 1)
			3:
				code = (ARMS << 16) | (1 << rng.randi_range(0, tables["arms"].size() - 1))
			4:
				code = (FORMATION << 16) | (1 << rng.randi_range(0, tables["formations"].size() - 1))
		city["objects"].append(code)
		return {"item": code}
	return {}


func invite(officer: int, city_id: int) -> bool:
	if rng.randi_range(0, 99) >= 50 or scenario.generals[officer]["King"] != -1:
		return false
	_recruit(officer, city_id)
	return true


func _recruit(officer: int, city_id: int) -> void:
	var city := scenario.cities[city_id]
	var general := scenario.generals[officer]
	var total_levels := 0
	for id: int in city["generals"]:
		total_levels += int(scenario.generals[id]["Level"])
	@warning_ignore("integer_division")
	var average := total_levels / maxi(1, city["generals"].size())
	general["Experience"] = level_experience(average)
	level_up(general)
	general["active"] = 0
	_join_city(officer, city_id)


func _join_city(officer: int, city_id: int) -> void:
	var city := scenario.cities[city_id]
	var general := scenario.generals[officer]
	general["City"] = city_id
	general["King"] = city["King"]
	general["loyalty"] = 90
	general["prisonerIdx"] = -1
	city["prisons"].erase(officer)
	if not city["generals"].has(officer):
		city["generals"].append(officer)
	if city["prefect"] == -1:
		city["prefect"] = officer
	var roster: Array = scenario.kings[city["King"]]["generals"]
	if not roster.has(officer):
		roster.append(officer)


func can_surrender(king: int, officer: int) -> bool:
	var general := scenario.generals[officer]
	var city_id: int = general["City"]
	return (general["prisonerIdx"] == king and general["active"] == 1 and city_id >= 0
		and scenario.cities[city_id]["King"] == king and scenario.cities[city_id]["prisons"].has(officer))


func surrender(king: int, officer: int, computer := false) -> bool:
	if not can_surrender(king, officer):
		return false
	var general := scenario.generals[officer]
	var loyalty: int = general["loyalty"]
	if not computer:
		general["active"] = 0
	@warning_ignore("integer_division")
	var success: bool = general["King"] == king or (
		rng.randi_range(0, 99) > loyalty if computer else rng.randi_range(0, 99) < (100 - loyalty) / 2)
	if not success:
		general["loyalty"] = maxi(0, loyalty - rng.randi_range(5, 19))
		return false
	_join_city(officer, general["City"])
	if not computer:
		general["SoldierCur"] = general["SoldierMax"]
		general["KnightCur"] = general["KnightMax"]
	return true


func item_name(item: int) -> String:
	var value := item & 0xffff
	match item >> 16:
		EQUIPMENT:
			return tables["equipment"][value][0]
		ARMS:
			return "%s兵符" % tables["arms"][_bit_index(value)]
		FORMATION:
			return "%s之书" % tables["formations"][_bit_index(value)]
	return ""


func _bit_index(value: int) -> int:
	var bit := 0
	while value > 1:
		value >>= 1
		bit += 1
	return bit


func can_use_item(general: Dictionary, item: int) -> bool:
	var value := item & 0xffff
	match item >> 16:
		EQUIPMENT:
			return general["Equipment"] != value
		ARMS:
			return (general["Arms"] & value) == 0
		FORMATION:
			return (general["Formation"] & value) == 0
	return false


func use_item(king: int, officer: int, city_id: int, slot: int, computer := false) -> bool:
	var city := scenario.cities[city_id]
	var general := scenario.generals[officer]
	var inventory: Array = city["objects"]
	if city["King"] != king or general["King"] != king or general["prisonerIdx"] != -1:
		return false
	if slot < 0 or slot >= inventory.size() or not can_use_item(general, inventory[slot]):
		return false
	var item: int = inventory[slot]
	var value := item & 0xffff
	if item >> 16 == EQUIPMENT:
		var previous: int = general["Equipment"]
		if computer and not _computer_wants_equipment(general, value):
			return false
		if previous >= 0:
			_modify_equipment_stats(general, previous, -1)
			inventory[slot] = (EQUIPMENT << 16) | previous
		else:
			inventory.remove_at(slot)
		general["Equipment"] = value
		_modify_equipment_stats(general, value, 1)
	else:
		var field := "Arms" if item >> 16 == ARMS else "Formation"
		general[field] |= value
		inventory.remove_at(slot)
	return true


func unequip(king: int, officer: int) -> bool:
	var general := scenario.generals[officer]
	var equipment: int = general["Equipment"]
	if equipment < 0 or general["King"] != king or general["City"] < 0 or general["prisonerIdx"] != -1:
		return false
	scenario.cities[general["City"]]["objects"].append((EQUIPMENT << 16) | equipment)
	var type: int = int(tables["equipment"][equipment][1])
	# The original remove-only command adjusts weapons and books, unlike an equipment swap.
	if type == 0 or type == 3:
		_modify_equipment_stats(general, equipment, -1)
	general["Equipment"] = -1
	return true


func _modify_equipment_stats(general: Dictionary, equipment: int, sign_value: int) -> void:
	var item: Array = tables["equipment"][equipment]
	var change := int(item[2]) * sign_value
	match int(item[1]):
		0:
			general["Intellect"] = clampi(general["Intellect"] + change, 0, 999)
		1:
			general["ManaMax"] = clampi(general["ManaMax"] + change, 0, 999)
			general["ManaCur"] = clampi(general["ManaCur"] + change, 0, general["ManaMax"])
		2:
			general["HealthMax"] = clampi(general["HealthMax"] + change, 0, 999)
			general["HealthCur"] = clampi(general["HealthCur"] + change, 0, general["HealthMax"])
		3:
			general["Strength"] = clampi(general["Strength"] + change, 0, 999)


func _computer_wants_equipment(general: Dictionary, equipment: int) -> bool:
	var next: Array = tables["equipment"][equipment]
	var scholar: bool = general["Intellect"] > 70 and general["Intellect"] - general["Strength"] >= 10
	var warrior: bool = general["Strength"] > 70 and general["Strength"] - general["Intellect"] >= 10
	if (scholar and next[1] == 3) or (warrior and next[1] == 0):
		return false
	if general["Equipment"] < 0:
		return true
	var previous: Array = tables["equipment"][general["Equipment"]]
	if next[1] == previous[1]:
		return next[2] > previous[2]
	return not ((scholar and next[1] != 0) or (warrior and next[1] != 3))


func promotion_choices(officer: int, computer := false) -> Array[int]:
	var general := scenario.generals[officer]
	var level: int = general["Level"]
	if level < 10 or general["prisonerIdx"] != -1:
		return []
	if general["Magic1"] == -1:
		if level < 30 or level >= 40 or computer:
			return _job_branch(general["Magic0"], 2)
	elif general["Magic2"] == -1 and level >= 20 and (level < 30 or level >= 40 or computer):
		return _job_branch(general["Magic1"], 3)
	elif general["Magic3"] == -1 and general["Magic2"] >= 0 and level >= 40:
		return [18 if general["Magic2"] < 18 else 49]
	return []


func _job_branch(previous: int, tier: int) -> Array[int]:
	var civil := previous < 18
	var job := previous + (6 if civil else 10)
	var choices: Array[int] = []
	for _choice in range(3):
		choices.append(job)
		job += 3 if civil else 5
		if job >= (tier * 6 if civil else 19 + tier * 10):
			job -= 5 if civil else 9
	return choices


func promote(officer: int, job: int, computer := false) -> bool:
	if not promotion_choices(officer, computer).has(job):
		return false
	var general := scenario.generals[officer]
	var slot := "Magic1" if general["Magic1"] == -1 else ("Magic2" if general["Magic2"] == -1 else "Magic3")
	general[slot] = job
	general["job"] = job
	return true


func run_computer_court(player: int) -> void:
	var neutral := scenario.kings.size() - 1
	for city in scenario.cities:
		var king: int = city["King"]
		if king < 0 or king == player or king == neutral:
			continue
		var city_id: int = city["Index"]
		for id: int in city["generals"].duplicate():
			var general := scenario.generals[id]
			if general["Strength"] >= 85 or general["Intellect"] >= 85:
				@warning_ignore("integer_division")
				var outcome := 1 if rng.randi_range(0, 99) > 50 else rng.randi_range(0, 99) / 20
				var result := _search_city(city_id, outcome, 5)
				if result.has("recruit"):
					_recruit(result["recruit"], city_id)
			elif general["Strength"] > 80:
				scenario.improve_city(id, "Defense", rng)
			elif general["Intellect"] > 80:
				scenario.improve_city(id, "Population", rng)
		for id: int in city["generals"]:
			var count: int = city["objects"].size()
			if count == 0:
				break
			use_item(king, id, city_id, rng.randi_range(0, count - 1), true)
		for id: int in city["prisons"].duplicate():
			surrender(king, id, true)
	for general in scenario.generals:
		if general["prisonerIdx"] != -1:
			general["loyalty"] = maxi(0, general["loyalty"] - rng.randi_range(5, 19))
		elif general["King"] >= 0 and general["King"] != player:
			var officer: int = general["Index"]
			var choices := promotion_choices(officer, true)
			while not choices.is_empty():
				promote(officer, choices[rng.randi_range(0, choices.size() - 1)], true)
				choices = promotion_choices(officer, true)


func start_new_year(player: int) -> void:
	var neutral := scenario.kings.size() - 1
	for city in scenario.cities:
		if city["King"] >= 0 and city["King"] != neutral:
			city["Money"] = mini(999999, city["Money"] + int(2250 + city["Population"] / 133.34))
	for general in scenario.generals:
		general["active"] = 1
		if general["King"] >= 0 and general["King"] != player and general["King"] != neutral:
			award_battle_experience(general["Index"])


func award_battle_experience(officer: int, divisor := 2) -> void:
	var general := scenario.generals[officer]
	var level: int = general["Level"]
	@warning_ignore("integer_division")
	general["Experience"] += (level_experience(level + 1) - level_experience(level)) / divisor
	level_up(general)


static func level_experience(level: int) -> int:
	match level:
		2: return 200
		3: return 377
		4: return 771
	if level >= 50:
		return 99999
	var offset := level - 5
	@warning_ignore("integer_division")
	return 1302 + 531 * offset + 137 * (offset + 1) * offset / 2


func level_up(general: Dictionary) -> void:
	while general["Level"] < 50 and general["Experience"] >= level_experience(general["Level"] + 1):
		general["Level"] += 1
		var level: int = general["Level"]
		if level <= 20:
			general["SoldierMax"] = 5 * level
		elif level <= 40:
			general["KnightMax"] = (level - 20) * 5
			general["SoldierMax"] = 100 - general["KnightMax"]
			general["KnightCur"] = clampi(general["KnightCur"] - maxi(0, general["SoldierCur"]
				- general["SoldierMax"]), 0, general["KnightMax"])
		else:
			general["SoldierMax"] = 0
			general["KnightMax"] = 100
			general["KnightCur"] = mini(100, general["KnightCur"] + general["SoldierCur"])
		general["SoldierCur"] = mini(general["SoldierCur"], general["SoldierMax"])
		general["ManaMax"] = mini(999, general["ManaMax"] + rng.randi_range(1, 2))
		general["HealthMax"] = mini(999, general["HealthMax"] + rng.randi_range(1, 2))
		if level == 50:
			general["Experience"] = 99999
