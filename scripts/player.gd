extends CharacterBody2D

const SPEED := 280.0
const JUMP_VELOCITY := -460.0
const GRAVITY := 1400.0

var jumps_remaining := 1

@onready var body = $Body


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	velocity.x = Input.get_axis("move_left", "move_right") * SPEED
	if Input.is_action_just_pressed("jump") and jumps_remaining > 0:
		velocity.y = JUMP_VELOCITY
		jumps_remaining -= 1

	move_and_slide()
	if is_on_floor():
		jumps_remaining = 2
	else:
		# Walking off a ledge leaves only the single air jump.
		jumps_remaining = mini(jumps_remaining, 1)

	body.update_pose(delta, velocity.x, is_on_floor())
