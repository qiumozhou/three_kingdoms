extends SceneTree

var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	change_scene_to_file("res://scenes/campaign.tscn")
	await scene_changed
	var campaign := current_scene
	_check(not _button("City1").disabled and _button("City2").disabled, "only adjacent enemy city starts unlocked")
	_button("City1").pressed.emit()
	_button("Cancel").pressed.emit()
	_check(not _button("City1").disabled, "cancelling general selection returns to map")
	_button("City1").pressed.emit()
	_button("General1").pressed.emit()
	var battle: Node = campaign.get("battle")
	_check(battle.get_node("FriendlyName").text == "张飞" and battle.get_node("EnemyName").text == "管亥",
		"battle displays the selected general and city defender")
	_check(battle.get("blue_units").size() == 43 and battle.get("red_units").size() == 35
		and battle.get("blue_general").health == 120.0, "battle receives troop counts and general health")

	_defeat_army(battle.get("blue_units"))
	battle.get("red_units")[0].health = 0.0
	battle.call("_physics_process", 0.0)
	await process_frame
	_button("ReturnToMap").pressed.emit()
	_check(campaign.get("battle") == null and not _button("City1").disabled and _button("City2").disabled,
		"defeat removes battle and leaves city ownership unchanged")
	_check(campaign.get("troops")[1] == 0 and campaign.get("garrisons")[1] == 33,
		"defeat carries both sides' losses back to map")
	_button("City1").pressed.emit()
	_check(_button("General1").disabled, "a general with no troops cannot deploy")
	_button("Cancel").pressed.emit()
	_button("Recruit").pressed.emit()
	_check(campaign.get("troops")[1] == 42, "recruiting restores friendly troops")

	_button("City1").pressed.emit()
	_button("General0").pressed.emit()
	battle = campaign.get("battle")
	_check(battle.get("red_units").size() == 34, "second attack uses surviving enemy troops")
	battle.get("blue_units")[0].health = 0.0
	_defeat_army(battle.get("red_units"))
	battle.call("_physics_process", 0.0)
	await process_frame
	_button("ReturnToMap").pressed.emit()
	_check(_button("City1").disabled and not _button("City2").disabled and campaign.get("troops")[0] == 49,
		"victory captures the city, unlocks the route and carries friendly losses")
	_button("City2").pressed.emit()
	_button("General0").pressed.emit()
	battle = campaign.get("battle")
	_check(battle.get("blue_units").size() == 50, "next battle uses surviving friendly troops")
	_defeat_army(battle.get("red_units"))
	battle.call("_physics_process", 0.0)
	await process_frame
	_button("ReturnToMap").pressed.emit()
	_button("Reset").pressed.emit()
	_check(not _button("City1").disabled and _button("City2").disabled
		and campaign.get("troops") == [50, 42] and campaign.get("garrisons") == [0, 34, 48],
		"completing and restarting the campaign restores the initial map")
	quit(1 if failed else 0)


func _button(id: String) -> Button:
	return current_scene.find_child(id, true, false) as Button


func _defeat_army(army: Array) -> void:
	for unit in army:
		unit.health = 0.0


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failed += 1
		push_error("FAIL: " + description)
