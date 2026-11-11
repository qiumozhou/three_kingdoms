extends RefCounted

const TICKS_PER_MONTH := 10
const MONTHS_PER_YEAR := 12
const TICK_SECONDS := 0.5
const ARMY_SPEED := 10.0
const MAX_OFFICERS := 5
const CITY_CAPACITY := 10
const COURT := preload("res://scripts/unity_court_rules.gd")

var scenario: UnityScenario
var rng: RandomNumberGenerator
var court: RefCounted
var roads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
	"res://assets/unity_reference/strategy_roads.json"))
var road_points := PackedVector2Array()
var links: Array[Array] = []
var armies: Array[Dictionary] = []
var month := 0
var ticks := 0
var elapsed := 0.0


func _init(world: UnityScenario, random: RandomNumberGenerator) -> void:
	scenario = world
	rng = random
	court = COURT.new(world, random)
	for node: Array in roads["nodes"]:
		road_points.append(Vector2(node[0], node[1]))
		links.append([])
	var breaks: Dictionary = roads["breaks"]
	for i in road_points.size():
		for j in range(i + 1, road_points.size()):
			if road_points[i].distance_to(road_points[j]) > 30.0:
				continue
			if breaks.get(str(i), []).has(float(j)) or breaks.get(str(j), []).has(float(i)):
				continue
			links[i].append(j)
			links[j].append(i)


func point(city: int) -> Vector2:
	return road_points[int(roads["cities"][city])]


func route(origin: int, target: int) -> Array[int]:
	return _route_nodes(int(roads["cities"][origin]), int(roads["cities"][target]))


func _route_from(position: Vector2, target: int) -> Array[int]:
	var nearest := 0
	var best := INF
	for i in road_points.size():
		var distance := position.distance_to(road_points[i])
		if distance < best:
			best = distance
			nearest = i
		if distance < 1.0:
			break
	return _route_nodes(nearest, int(roads["cities"][target]))


func _route_nodes(start: int, end: int) -> Array[int]:
	if start == end:
		return [end]
	var queue: Array[int] = [end]
	var distance := {end: 0}
	var read := 0
	while read < queue.size() and not distance.has(start):
		var node := queue[read]
		read += 1
		for neighbor: int in links[node]:
			if not distance.has(neighbor):
				distance[neighbor] = distance[node] + 1
				queue.append(neighbor)
	var result: Array[int] = []
	if not distance.has(start):
		return result
	while start != end:
		for neighbor: int in links[start]:
			if distance.get(neighbor, -1) == distance[start] - 1:
				result.append(neighbor)
				start = neighbor
				break
	return result


func route_distance(origin: int, target: int) -> float:
	var position := point(origin)
	var distance := 0.0
	for node in route(origin, target):
		distance += position.distance_to(road_points[node])
		position = road_points[node]
	return distance


func restore_armies(saved: Array) -> void:
	armies.assign(saved)
	for army in armies:
		if not army.has("road"):
			army["road"] = _route_from(army["position"], army["target"]) if army["target"] >= 0 else []
			army.erase("path")


func dispatch(origin: int, target: int, officers: Array[int], commander: int,
		prefect: int, funds: int, take_prisoners: bool, computer := false) -> Dictionary:
	var path := route(origin, target)
	if path.is_empty():
		return {}
	var army := form_army(origin, officers, commander, prefect, funds, take_prisoners, computer)
	if not army.is_empty():
		army["target"] = target
		army["road"] = path
		army["garrison"] = false
	return army


func form_army(origin: int, officers: Array[int], commander: int,
		prefect: int, funds: int, take_prisoners: bool, computer := false) -> Dictionary:
	var city := scenario.cities[origin]
	var owner: int = city["King"]
	if owner < 0 or officers.is_empty() or officers.size() > MAX_OFFICERS:
		return {}
	var remaining: Array = city["generals"].duplicate()
	for id in officers:
		if not remaining.has(id):
			return {}
		remaining.erase(id)
	if not officers.has(commander) or (not remaining.is_empty() and not remaining.has(prefect)):
		return {}
	var army := {"king": owner, "origin": origin, "target": -1, "city": origin,
		"commander": commander, "officers": officers.duplicate(), "prisons": [],
		"funds": clampi(funds, 0, city["Money"]), "road": [], "position": point(origin),
		"retreating": false, "garrison": true}
	if not computer:
		city["Money"] -= army["funds"]
	city["generals"] = remaining
	city["prefect"] = prefect if not remaining.is_empty() else -1
	if remaining.is_empty():
		scenario.kings[owner]["cities"].erase(origin)
		city["King"] = -1
	for id in officers:
		scenario.generals[id]["City"] = -1
	if take_prisoners:
		army["prisons"] = city["prisons"].duplicate()
		city["prisons"].clear()
		for id: int in army["prisons"]:
			scenario.generals[id]["City"] = -1
	armies.append(army)
	return army


func order_march(army: Dictionary, target: int) -> bool:
	var path := _route_from(army["position"], target)
	if path.is_empty():
		return false
	if target == army["origin"] and army["target"] >= 0:
		army["origin"] = army["target"]
	army["target"] = target
	army["road"] = path
	army["garrison"] = false
	army["victory"] = false
	army["retreating"] = false
	return true


func hold_army(army: Dictionary) -> void:
	army["garrison"] = true
	army["victory"] = false
	army["retreating"] = false


func station_excess_officers() -> void:
	for city_id in scenario.cities.size():
		var city := scenario.cities[city_id]
		var roster: Array = city["generals"]
		while roster.size() > CITY_CAPACITY:
			var group: Array[int] = []
			var count := mini(MAX_OFFICERS, roster.size() - CITY_CAPACITY)
			for index in count:
				var id: int = roster.pop_back()
				group.append(id)
				scenario.generals[id]["City"] = -1
				if id == city["prefect"]:
					city["prefect"] = _preferred_officer(roster, city["King"])
			armies.append({"king": city["King"], "origin": city_id, "target": -1, "city": city_id,
				"commander": _preferred_officer(group, city["King"]), "officers": group, "prisons": [],
				"funds": 0, "road": [], "position": point(city_id), "retreating": false, "garrison": true})


func advance(delta: float, player: int) -> Dictionary:
	if delta <= 0.0:
		return _move_armies(0.0, player)
	while delta > 0.0:
		var step := minf(delta, TICK_SECONDS - elapsed)
		elapsed += step
		delta -= step
		var event := _move_armies(step, player)
		if not event.is_empty():
			return event
		if elapsed >= TICK_SECONDS:
			elapsed = 0.0
			_add_reserves()
			ticks += 1
			if ticks == TICKS_PER_MONTH:
				ticks = 0
				month += 1
				if month == MONTHS_PER_YEAR:
					month = 0
					return {"year_end": true}
				_monthly_actions(player)
	return {}


func _move_armies(delta: float, player: int) -> Dictionary:
	for army in armies.duplicate():
		if not armies.has(army):
			continue
		var moving_delta := delta
		var retreat_delta := 0.0
		if army["retreating"] or army.get("victory", false):
			var timer: float = army.get("state_time", 0.0)
			var remaining := maxf(0.0, 3.0 - timer)
			if army["retreating"]:
				retreat_delta = minf(delta, remaining)
			else:
				moving_delta = maxf(0.0, delta - remaining)
			army["state_time"] = timer + delta
			if army["state_time"] > 3.0:
				army["retreating"] = false
				army["victory"] = false
		var path: Array = army["road"]
		var budget := ARMY_SPEED * (moving_delta + retreat_delta)
		var city := -1
		var position: Vector2 = army["position"]
		var garrison: bool = army.get("garrison", false)
		while not garrison and not path.is_empty():
			var node: int = path.front()
			var destination := road_points[node]
			var distance := position.distance_to(destination)
			if distance > budget:
				position = position.move_toward(destination, budget)
				break
			budget -= distance
			position = destination
			city = _city_in_range(position, 5.0)
			if city >= 0:
				break
			path.pop_front()
		army["position"] = position
		if not army["retreating"]:
			for opponent in armies.duplicate():
				if opponent == army or opponent["king"] == army["king"] or opponent["retreating"]:
					continue
				var opponent_position: Vector2 = opponent["position"]
				if opponent_position.distance_to(army["position"]) >= 10.0:
					continue
				if army["king"] == player:
					return {"army": army, "opponent": opponent}
				if opponent["king"] == player:
					return {"army": opponent, "opponent": army}
				_resolve_computer_field(army, opponent)
				break
		if not armies.has(army) or army["retreating"] and army["road"] != path:
			continue
		if city < 0:
			continue
		path.pop_front()
		army["city"] = city
		var owner: int = scenario.cities[city]["King"]
		if owner >= 0 and owner != army["king"] and not army["retreating"]:
			if owner == player or army["king"] == player:
				return {"army": army, "city": city}
			_resolve_computer_attack(army, city)
			continue
		if path.is_empty():
			if owner < 0 or owner == army["king"]:
				enter_city(army, city)
			else:
				if owner == player or army["king"] == player:
					return {"army": army, "city": city}
				_resolve_computer_attack(army, city)
	return {}


func _city_in_range(position: Vector2, radius: float) -> int:
	for city in scenario.cities.size():
		if position.distance_to(point(city)) < radius:
			return city
	return -1


func _add_reserves() -> void:
	var neutral := scenario.kings.size() - 1
	for city in scenario.cities:
		if city["King"] >= 0 and city["King"] != neutral and city["Money"] > 100 and city["Reservist"] < city["ReservistMax"]:
			city["Reservist"] += 1
			city["Money"] -= 100


func _monthly_actions(player: int) -> void:
	for general in scenario.generals:
		@warning_ignore("integer_division")
		general["HealthCur"] = mini(general["HealthMax"], general["HealthCur"] + int(general["Strength"]) / 20)
		@warning_ignore("integer_division")
		general["ManaCur"] = mini(general["ManaMax"], general["ManaCur"] + int(general["Intellect"]) / 20)
	for city in scenario.cities:
		_computer_city_act(city, player)
	for army in armies.duplicate():
		if army.get("garrison", false) and army["king"] != player:
			var position: Vector2 = army["position"]
			var city := _city_in_range(position, 30.0)
			if city >= 0 and scenario.cities[city]["King"] == army["king"]:
				enter_city(army, city)


func _computer_city_act(city: Dictionary, player: int) -> void:
	var owner: int = city["King"]
	if owner < 0 or owner == player or owner == scenario.kings.size() - 1:
		return
	var ready := 0
	for id: int in city["generals"]:
		var general := scenario.generals[id]
		for kind in ["Knight", "Soldier"]:
			var added := clampi(general[kind + "Max"] - general[kind + "Cur"], 0, city["Reservist"])
			city["Reservist"] -= added
			general[kind + "Cur"] += added
		if general["HealthCur"] > 50 and ((general["SoldierCur"] + general["KnightCur"]) * 2
				> general["SoldierMax"] + general["KnightMax"]):
			ready += 1
	var origin: int = city["Index"]
	for target: int in scenario.city_routes[origin]:
		var neighbor := scenario.cities[target]
		var garrison: int = neighbor["generals"].size()
		if neighbor["King"] == owner:
			if ready < 8 and garrison > 2 and rng.randi_range(0, 99) > 88:
				_computer_dispatch(target, origin, rng.randi_range(1, garrison - 1))
				break
		elif neighbor["King"] == -1:
			if ready > 3 and rng.randi_range(0, 99) > 80:
				_computer_dispatch(origin, target, rng.randi_range(1, city["generals"].size() - 1))
				break
		elif ready > 2 and rng.randi_range(0, 99) > 88:
			var difference := ready - garrison
			if difference >= 2:
				_computer_dispatch(origin, target, rng.randi_range(garrison + 1, city["generals"].size() - 1))
				break
			if difference > 0 and rng.randi_range(0, 99) > 50:
				_computer_dispatch(origin, target, garrison)
				break
			if difference == 0 and rng.randi_range(0, 99) > 88:
				_computer_dispatch(origin, target, garrison - 1)
				break


func _computer_dispatch(origin: int, target: int, count: int) -> void:
	var city := scenario.cities[origin]
	for offset in range(0, count, MAX_OFFICERS):
		var funds := rng.randi_range(0, maxi(0, city["Money"] - 1))
		var officers: Array[int] = []
		var remaining: Array = city["generals"].duplicate()
		var prefect: int = city["prefect"]
		for index in range(remaining.size() - 1, -1, -1):
			var id: int = remaining[index]
			if scenario.generals[id]["HealthCur"] <= 50:
				continue
			if id == prefect and rng.randi_range(0, 99) <= 50:
				continue
			officers.append(id)
			remaining.remove_at(index)
			if officers.size() == mini(MAX_OFFICERS, count - offset):
				break
		if officers.is_empty():
			continue
		var take_prisoners: bool = not city["prisons"].is_empty() and rng.randi_range(0, 99) > 60
		var commander := _preferred_officer(officers, city["King"])
		if officers.has(prefect):
			commander = prefect
			prefect = _preferred_officer(remaining, city["King"])
		dispatch(origin, target, officers, commander, prefect, funds, take_prisoners, true)


func _preferred_officer(officers: Array, owner: int) -> int:
	if officers.is_empty():
		return -1
	var ruler: int = scenario.kings[owner]["GeneralIdx"]
	if officers.has(ruler):
		return ruler
	var preferred: int = officers[0]
	for id: int in officers:
		if scenario.generals[id]["Strength"] > scenario.generals[preferred]["Strength"]:
			preferred = id
	return preferred


func _resolve_computer_attack(army: Dictionary, city_id: int) -> void:
	var city := scenario.cities[city_id]
	var attackers: Array = army["officers"]
	var defenders: Array = city["generals"]
	var a := 0
	var d := 0
	while a < attackers.size() and d < defenders.size():
		@warning_ignore("integer_division")
		var attacker_power := _power(attackers[a])
		@warning_ignore("integer_division")
		var defender_power := _power(defenders[d]) + int(city["Defense"]) / 10
		if attacker_power > defender_power:
			_resolve_computer_duel(attackers[a], defenders[d], defender_power)
			d += 1
		else:
			_resolve_computer_duel(defenders[d], attackers[a], attacker_power)
			a += 1
	if d == defenders.size():
		enter_city(army, city_id)
	else:
		reward_force(defenders, true)
		retreat(army, city_id)


func _resolve_computer_field(army: Dictionary, opponent: Dictionary) -> void:
	var attackers: Array = army["officers"]
	var defenders: Array = opponent["officers"]
	var a := 0
	var d := 0
	while a < attackers.size() and d < defenders.size():
		var attacker_power := _power(attackers[a])
		var defender_power := _power(defenders[d])
		if attacker_power > defender_power:
			_resolve_computer_duel(attackers[a], defenders[d], defender_power)
			d += 1
		else:
			_resolve_computer_duel(defenders[d], attackers[a], attacker_power)
			a += 1
	if d == defenders.size():
		finish_field(army, opponent, true)
	else:
		finish_field(opponent, army, true)


func _resolve_computer_duel(winner_id: int, loser_id: int, damage: int) -> void:
	var winner := scenario.generals[winner_id]
	mark_defeated(loser_id, winner["King"], false, true)
	court.award_battle_experience(winner_id)
	damage -= int(winner["Strength"])
	for troop in [["KnightCur", 6], ["SoldierCur", 3]]:
		var field: String = troop[0]
		var cost: int = troop[1]
		var capacity: int = winner[field] * cost
		if damage > capacity:
			damage -= capacity
			winner[field] = 0
		else:
			@warning_ignore("integer_division")
			winner[field] -= damage / cost
			return
	@warning_ignore("integer_division")
	var mana_power: int = int(winner["ManaCur"]) / 2
	if damage > mana_power:
		damage -= mana_power
		winner["ManaCur"] = 0
	else:
		winner["ManaCur"] -= damage * 2
		return
	winner["HealthCur"] = maxi(15, winner["HealthCur"] - damage)


func reward_force(officers: Array, simulated: bool) -> void:
	for id: int in officers:
		var general := scenario.generals[id]
		general["prisonerIdx"] = -1
		if general["Level"] > 4:
			court.award_battle_experience(id, 4 if simulated else 2)
		else:
			general["Experience"] += 50
			court.level_up(general)


func finish_field(winner: Dictionary, loser: Dictionary, simulated := false) -> void:
	reward_force(winner["officers"], simulated)
	winner["garrison"] = false
	winner["victory"] = true
	winner["state_time"] = 0.0
	var owner: int = loser["king"]
	var captor: int = winner["king"]
	for id: int in loser["officers"].duplicate():
		if scenario.generals[id]["prisonerIdx"] != captor:
			continue
		loser["officers"].erase(id)
		winner["prisons"].append(id)
		scenario.kings[owner]["generals"].erase(id)
		if id == scenario.kings[owner]["GeneralIdx"] and owner < scenario.kings.size() - 1:
			_eliminate(owner)
	if loser["officers"].is_empty():
		for id: int in loser["prisons"]:
			winner["prisons"].append(id)
			scenario.generals[id]["prisonerIdx"] = captor
		winner["funds"] += loser["funds"]
		armies.erase(loser)
		return
	if not loser["officers"].has(loser["commander"]):
		loser["commander"] = loser["officers"][0]
	var destination: int = loser["origin"]
	loser["origin"] = loser["target"] if loser["target"] >= 0 else loser["city"]
	loser["road"] = _route_from(loser["position"], destination)
	loser["target"] = destination
	loser["retreating"] = true
	loser["victory"] = false
	loser["garrison"] = false
	loser["state_time"] = 0.0


func _power(id: int) -> int:
	var general := scenario.generals[id]
	@warning_ignore("integer_division")
	return (general["Level"] * 5 + general["KnightCur"] * 6 + general["SoldierCur"] * 3
		+ general["Strength"] * 2 + general["HealthCur"] + int(general["ManaCur"]) / 2 + rng.randi_range(0, 19))


func mark_defeated(id: int, captor: int, escaped: bool, simulated := false) -> void:
	var general := scenario.generals[id]
	if simulated:
		general["KnightCur"] = 0
		general["SoldierCur"] = 0
		general["HealthCur"] = 2
		general["ManaCur"] = 2
	var protection := int(general["Equipment"] >= 27 and general["Equipment"] <= 30)
	var faction := scenario.kings[general["King"]]
	if faction["GeneralIdx"] == id and not faction["cities"].is_empty():
		protection += 3
	var prior: int = general.get("escape", 0)
	if not escaped and rng.randi_range(0, 99) > 50 + protection * 25 - prior * 25:
		general["prisonerIdx"] = captor
		general["escape"] = 0
	else:
		general["escape"] = prior + 1


func adjust_troops(city_id: int, id: int, change: int) -> void:
	var city := scenario.cities[city_id]
	if not city["generals"].has(id):
		return
	var general := scenario.generals[id]
	var total: int = general["KnightCur"] + general["SoldierCur"]
	var next := clampi(total + change, maxi(0, total - city["ReservistMax"] + city["Reservist"]),
		mini(general["KnightMax"] + general["SoldierMax"], total + city["Reservist"]))
	var delta := next - total
	city["Reservist"] -= delta
	if delta >= 0:
		var mounted := mini(delta, general["KnightMax"] - general["KnightCur"])
		general["KnightCur"] += mounted
		general["SoldierCur"] += delta - mounted
	else:
		var foot := mini(-delta, general["SoldierCur"])
		general["SoldierCur"] -= foot
		general["KnightCur"] += delta + foot


func enter_city(army: Dictionary, city_id: int, simulated := true) -> void:
	var city := scenario.cities[city_id]
	var old: int = city["King"]
	var owner: int = army["king"]
	if old != owner:
		reward_force(army["officers"], simulated)
		var defenders: Array = city["generals"].duplicate()
		var evacuating: Array[int] = []
		city["generals"].clear()
		if old >= 0:
			scenario.kings[old]["cities"].erase(city_id)
		for id: int in defenders:
			var general := scenario.generals[id]
			if general["prisonerIdx"] == owner:
				_capture(id, city_id, owner)
			else:
				evacuating.append(id)
		city["King"] = owner
		city["prefect"] = army["commander"]
		scenario.kings[owner]["cities"].append(city_id)
		for id: int in city["prisons"]:
			scenario.generals[id]["prisonerIdx"] = owner
		_evacuate(city_id, evacuating)
	var count := mini(army["officers"].size(), maxi(0, CITY_CAPACITY - city["generals"].size()))
	for index in range(count - 1, -1, -1):
		var id: int = army["officers"][index]
		army["officers"].remove_at(index)
		city["generals"].append(id)
		scenario.generals[id]["City"] = city_id
		scenario.generals[id]["prisonerIdx"] = -1
		scenario.generals[id]["escape"] = 0
		if id == scenario.kings[owner]["GeneralIdx"]:
			city["prefect"] = id
	if not army["officers"].is_empty():
		army["commander"] = _preferred_officer(army["officers"], owner)
		hold_army(army)
		return
	if city["prefect"] == -1:
		city["prefect"] = army["commander"]
	for id: int in army["prisons"]:
		city["prisons"].append(id)
		scenario.generals[id]["City"] = city_id
		scenario.generals[id]["prisonerIdx"] = owner
	city["Money"] += army["funds"]
	armies.erase(army)


func _evacuate(city_id: int, officers: Array[int]) -> void:
	if officers.is_empty():
		return
	var owner: int = scenario.generals[officers[0]]["King"]
	var neighbors: Array = scenario.city_routes[city_id]
	var destinations: Array = neighbors.filter(func(id: int) -> bool: return scenario.cities[id]["King"] == owner)
	if destinations.is_empty():
		destinations = neighbors.filter(func(id: int) -> bool: return scenario.cities[id]["King"] == -1)
	if destinations.is_empty():
		destinations = neighbors
	for end in range(officers.size(), 0, -MAX_OFFICERS):
		var group: Array[int] = []
		for index in range(end - 1, maxi(0, end - MAX_OFFICERS) - 1, -1):
			group.append(officers[index])
		var target: int = destinations[0] if neighbors.size() == 1 else destinations[rng.randi_range(0, destinations.size() - 1)]
		for id in group:
			scenario.generals[id]["City"] = -1
		armies.append({"king": owner, "origin": city_id, "target": target, "city": city_id,
			"commander": _preferred_officer(group, owner), "officers": group, "prisons": [], "funds": 0,
			"road": route(city_id, target), "position": point(city_id), "retreating": true, "state_time": 0.0})


func retreat(army: Dictionary, from_city: int) -> void:
	var owner: int = army["king"]
	var captor: int = scenario.cities[from_city]["King"]
	if captor >= 0 and captor != owner:
		for id: int in scenario.cities[from_city]["generals"]:
			scenario.generals[id]["prisonerIdx"] = -1
		for id: int in army["officers"].duplicate():
			if scenario.generals[id]["prisonerIdx"] == captor:
				army["officers"].erase(id)
				_capture(id, from_city, captor)
	var destination: int = army["origin"]
	if army["officers"].is_empty():
		if captor >= 0 and captor != owner:
			for id: int in army["officers"]:
				_capture(id, from_city, captor)
			for id: int in army["prisons"]:
				_capture(id, from_city, captor)
			scenario.cities[from_city]["Money"] += army["funds"]
		armies.erase(army)
		return
	if not army["officers"].has(army["commander"]):
		army["commander"] = army["officers"][0]
	if destination == from_city:
		enter_city(army, destination)
	else:
		army["origin"] = from_city
		army["target"] = destination
		army["road"] = _route_from(army["position"], destination)
		army["retreating"] = true
		army["victory"] = false
		army["garrison"] = false
		army["state_time"] = 0.0


func _capture(id: int, city_id: int, captor: int) -> void:
	var general := scenario.generals[id]
	var owner: int = general["King"]
	general["City"] = city_id
	general["prisonerIdx"] = captor
	scenario.cities[city_id]["prisons"].append(id)
	if owner >= 0:
		scenario.kings[owner]["generals"].erase(id)
		if id == scenario.kings[owner]["GeneralIdx"] and owner != scenario.kings.size() - 1:
			_eliminate(owner)


func _eliminate(owner: int) -> void:
	var neutral := scenario.kings.size() - 1
	var faction := scenario.kings[owner]
	faction["Active"] = 0
	for city_id: int in faction["cities"]:
		var city := scenario.cities[city_id]
		city["King"] = neutral
		scenario.kings[neutral]["cities"].append(city_id)
		for id: int in city["prisons"]:
			scenario.generals[id]["prisonerIdx"] = neutral
	for general in scenario.generals:
		if general["King"] == owner:
			general["King"] = neutral
	for army in armies:
		if army["king"] == owner:
			army["king"] = neutral
	scenario.kings[neutral]["generals"].append_array(faction["generals"])
	faction["generals"].clear()
	faction["cities"].clear()


func outcome(player: int) -> int:
	if scenario.kings[player]["Active"] == 0:
		return -1
	for city in scenario.cities:
		if city["King"] != player:
			return 0
	return 1
