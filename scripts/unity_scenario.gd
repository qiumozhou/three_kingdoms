extends RefCounted
class_name UnityScenario

const DEFAULT_INDEX := 1
const SELECTABLE_COUNTS := [6, 7, 5, 5, 5]
const KING_COUNTS := [14, 18, 8, 8, 5]

var kings: Array[Dictionary] = []
var cities: Array[Dictionary] = []
var generals: Array[Dictionary] = []
var city_routes: Array = JSON.parse_string(FileAccess.get_file_as_string(
	"res://assets/unity_reference/city_routes.json"))


static func load_scenario(index: int) -> UnityScenario:
	if index < 0 or index >= SELECTABLE_COUNTS.size():
		return null
	var xml := XMLParser.new()
	var path := "res://assets/unity_reference/MOD%02d.xml" % (index + 1)
	if xml.open(path) != OK:
		push_error("Cannot open Unity scenario %s" % path)
		return null
	var scenario := new()
	var section: Array[Dictionary] = []
	var status := xml.read()
	while status == OK:
		if xml.get_node_type() == XMLParser.NODE_ELEMENT:
			match xml.get_node_name():
				"King":
					section = scenario.kings
				"City":
					section = scenario.cities
				"General":
					section = scenario.generals
				"Item":
					var row := {}
					for attribute in range(xml.get_attribute_count()):
						var key := xml.get_attribute_name(attribute)
						var value := xml.get_attribute_value(attribute)
						row[key] = int(value) if value.is_valid_int() else value
					section.append(row)
		status = xml.read()
	if (status != ERR_FILE_EOF or scenario.kings.size() != KING_COUNTS[index]
			or scenario.cities.size() != 48 or scenario.generals.size() != 255):
		push_error("Invalid Unity scenario %s" % path)
		return null
	scenario._initialize_state()
	return scenario


static func available_scenarios(game_passed: bool) -> Array[int]:
	if game_passed:
		return [0, 1, 2, 3, 4]
	return [DEFAULT_INDEX]


static func selectable_count(index: int) -> int:
	return SELECTABLE_COUNTS[index] if index >= 0 and index < SELECTABLE_COUNTS.size() else 0


func can_assign(king_id: int, id: int, command: String) -> bool:
	if command != "Defense" and command != "Population":
		return false
	var king := kings[king_id]
	var general := generals[id]
	var stat := "Strength" if command == "Defense" else "Intellect"
	return (general["King"] == king_id and general["City"] >= 0
		and id != king["GeneralIdx"] and general["active"] == 1 and general[stat] >= 80)


func assign(king_id: int, id: int, command: String, rng: RandomNumberGenerator) -> int:
	if not can_assign(king_id, id, command):
		return 0
	generals[id]["active"] = 0
	return improve_city(id, command, rng)


func improve_city(id: int, command: String, rng: RandomNumberGenerator) -> int:
	var general := generals[id]
	var city := cities[general["City"]]
	var defense := command == "Defense"
	var bonus_limit: int = general["Strength"] - 80 if defense else (general["Intellect"] - 80) * 100
	var increase := 30 + rng.randi_range(0, 9) if defense else 9000 + rng.randi_range(0, 999)
	if bonus_limit > 0:
		increase += rng.randi_range(0, bonus_limit - 1)
	city[command] = mini(city[command] + increase, 9999 if defense else 999999)
	return increase


func ready_defender(city_id: int) -> int:
	var city := cities[city_id]
	var prefect: int = city["prefect"]
	if city["King"] == -1:
		return -1
	if prefect >= 0 and generals[prefect]["HealthCur"] > 0:
		return prefect
	for id: int in city["generals"]:
		if generals[id]["HealthCur"] > 0:
			return id
	return -1


func occupy_city(origin: int, target: int, attacker: int) -> void:
	var city := cities[target]
	var previous_owner: int = city["King"]
	var new_owner: int = generals[attacker]["King"]
	var former_city := cities[origin]
	if previous_owner >= 0:
		kings[previous_owner]["cities"].erase(target)
		for id: int in city["generals"]:
			kings[previous_owner]["generals"].erase(id)
			city["prisons"].append(id)
	for id: int in city["prisons"]:
		generals[id]["prisonerIdx"] = new_owner
	former_city["generals"].erase(attacker)
	if former_city["prefect"] == attacker:
		former_city["prefect"] = former_city["generals"][0] if not former_city["generals"].is_empty() else -1
	city["King"] = new_owner
	city["prefect"] = attacker
	city["generals"] = [attacker]
	generals[attacker]["City"] = target
	kings[new_owner]["cities"].append(target)


func _initialize_state() -> void:
	kings.append({"Index": kings.size(), "GeneralIdx": 0, "Active": 1})
	for king in kings:
		king["cities"] = []
		king["generals"] = []
	for city in cities:
		city["generals"] = []
		city["prisons"] = []
		city["objects"] = []
		var owner: int = city["King"]
		city["prefect"] = 0 if owner == -1 else -1
		if owner >= 0:
			kings[owner]["cities"].append(city["Index"])

	for id in range(generals.size() - 1, -1, -1):
		var general := generals[id]
		var owner: int = general["King"]
		var city_id: int = general["City"]
		if owner >= 0:
			kings[owner]["generals"].append(id)
		if city_id >= 0:
			var city := cities[city_id]
			if owner == -1 or owner != city["King"]:
				general["King"] = -1
				general["City"] = -1
			else:
				city["generals"].append(id)
				var leader: int = kings[owner]["GeneralIdx"]
				var prefect: int = city["prefect"]
				if id == leader or (prefect != leader and (
						prefect == -1 or generals[prefect]["Strength"] < general["Strength"])):
					city["prefect"] = id
		general["job"] = general["Magic0"]
		general["active"] = 1
		general["prisonerIdx"] = -1
		general["loyalty"] = 100
		var arms_bit := 0
		while arms_bit < 11 and (general["Arms"] & (1 << arms_bit)) == 0:
			arms_bit += 1
		general["arms_current"] = 1 << arms_bit
		var formation_bit := 7
		while formation_bit >= 0 and (general["Formation"] & (1 << formation_bit)) == 0:
			formation_bit -= 1
		general["formation_current"] = 1 << (formation_bit & 31)
