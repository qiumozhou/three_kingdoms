extends SceneTree

var passed := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# A timeout also makes script/runtime errors fail instead of hanging forever.
	create_timer(15.0).timeout.connect(func() -> void: quit(1))
	if await _test_gameplay() != true:
		failed += 1
	if await _test_walking() != true:
		failed += 1
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_gameplay() -> bool:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody2D = scene.get_node("Player")
	await _frames(30)
	_check(player.is_on_floor(), "player lands on the ground")
	_check(player.get("jumps_remaining") == 2, "landing grants two jumps")
	var start_x := player.position.x
	Input.action_press("move_right")
	await _frames(10)
	Input.action_release("move_right")
	_check(player.position.x > start_x + 30.0, "move right")
	Input.action_press("move_left")
	await _frames(10)
	Input.action_release("move_left")
	_check(absf(player.position.x - start_x) < 10.0, "move left")
	await _jump()
	_check(player.velocity.y < 0.0, "first jump rises")
	_check(player.get("jumps_remaining") == 1, "first jump consumes one charge")
	await _frames(8)
	await _jump()
	_check(player.velocity.y < -350.0, "second jump gives a fresh upward impulse")
	_check(player.get("jumps_remaining") == 0, "second jump consumes last charge")
	await _frames(8)
	var before_third := player.velocity.y
	await _jump()
	_check(player.velocity.y > before_third, "third press cannot reset upward velocity")
	_check(player.get("jumps_remaining") == 0, "third press grants no extra jump")
	await _frames(100)
	_check(player.is_on_floor(), "player lands after double jump")
	_check(player.get("jumps_remaining") == 2, "landing restores both charges")
	Input.action_press("jump")
	await _frames(5)
	_check(player.get("jumps_remaining") == 1, "holding Space does not trigger an air jump")
	await _frames(100)
	_check(player.is_on_floor(), "holding Space does not auto-jump on landing")
	Input.action_release("jump")
	await _frames(1)
	await _jump()
	_check(player.velocity.y < 0.0, "a new press jumps again after landing")
	scene.queue_free()
	return true


func _test_walking() -> bool:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	var player: CharacterBody2D = scene.get_node("Player")
	var body: Node2D = player.get_node("Body")
	_check(body is Polygon2D, "player has an articulated walking mesh")
	if not body is Polygon2D:
		scene.queue_free()
		return true
	await _frames(30)
	var idle_pose: PackedVector2Array = body.get("polygon")
	Input.action_press("move_right")
	await _frames(6)
	var first_step: PackedVector2Array = body.get("polygon")
	_check(first_step != idle_pose, "moving changes the leg pose")
	_check(body.scale.x > 0.0, "right movement faces right")
	await _frames(6)
	_check(body.get("polygon") != first_step, "walking advances through different step poses")
	Input.action_release("move_right")
	await _frames(2)
	_check(body.get("polygon") == idle_pose, "stopping restores the exact standing pose")
	Input.action_press("move_left")
	await _frames(6)
	_check(body.scale.x < 0.0, "left movement faces left")
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	_check(not player.is_on_floor(), "walking player can still jump")
	_check(body.get("polygon") == idle_pose, "airborne player pauses the walking cycle")
	Input.action_release("move_left")
	scene.queue_free()
	return true


func _jump() -> void:
	Input.action_press("jump")
	await _frames(1)
	Input.action_release("jump")
	await _frames(1)


func _frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("PASS: ", label)
	else:
		failed += 1
		push_error("FAIL: " + label)
