extends SceneTree

var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	var battle: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(battle)
	await physics_frame
	_check(battle.get("blue_units").size() == 51, "blue army spawns 50 soldiers and a general")
	_check(battle.get("red_units").size() == 51, "red army spawns 50 soldiers and a general")
	battle.call("_set_blue_order", 1)
	var held_x: float = battle.get("blue_units")[0].position.x
	for frame in range(10):
		await physics_frame
	_check(is_equal_approx(battle.get("blue_units")[0].position.x, held_x), "hold order stops blue movement")
	battle.call("_set_blue_order", 0)
	for frame in range(2700):
		battle.call("_physics_process", 1.0 / 60.0)
		if battle.get("battle_over"):
			break
	_check(battle.get("battle_over"), "battle reaches a result")
	_check(battle.get("blue_units").is_empty() or battle.get("red_units").is_empty(), "one army is eliminated")
	var skill_battle: Node = load("res://scenes/battle.tscn").instantiate()
	root.add_child(skill_battle)
	var caster: Dictionary = skill_battle.get("blue_general")
	var target: Dictionary = skill_battle.get("red_general")
	var distant: Dictionary = skill_battle.get("red_units")[0]
	target.position = caster.position + Vector2(60, 0)
	var skill_button: Button = skill_battle.get_node("%SkillButton")
	skill_button.pressed.emit()
	_check(target.health == 60.0, "skill damages enemies inside its radius")
	_check(skill_battle.get("slash_time") > 0.0 and caster.attack_time > 0.0,
		"skill starts the dragon effect and casting pose")
	_check(distant.health == 30.0 and caster.health == 90.0, "skill spares distant enemies and its caster")
	_check(skill_button.disabled, "skill button is disabled during cooldown")
	var key := InputEventAction.new()
	key.action = &"general_skill"
	key.pressed = true
	skill_battle.call("_unhandled_input", key)
	_check(target.health == 60.0, "cooldown prevents an immediate recast")
	target.position = caster.position + Vector2(12, 0)
	var engaged_x: float = caster.position.x
	skill_battle.call("_set_blue_order", 2)
	for frame in range(5):
		await physics_frame
	_check(caster.position.x < engaged_x - 2.0, "retreat breaks contact in melee range")
	var first: Dictionary = skill_battle.get("blue_units")[0]
	var second: Dictionary = skill_battle.get("blue_units")[1]
	first.position = Vector2(430, 290)
	second.position = first.position
	skill_battle.call("_separate_units")
	var first_position: Vector2 = first.position
	_check(first_position.distance_to(second.position) >= 16.9, "overlapping soldiers regain personal space")
	for frame in range(45):
		skill_battle.call("_physics_process", 1.0 / 60.0)
	_check(skill_battle.get("slash_time") == 0.0, "dragon effect expires")
	print("Battle tests: %s" % ("PASS" if failed == 0 else "FAIL"))
	quit(1 if failed > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failed += 1
		push_error("FAIL: " + label)
