extends AvatarMovementState

func enter(prev_state: RewindableState, tick: int):
	parent.velocity.y = JUMP_VELOCITY

func tick(delta, tick, is_fresh):
	rotate_player_model(delta)
	move_player(delta)

	force_update_is_on_floor()
	if parent.velocity.y <= 0:
		state_machine.transition(&"FallState")

func move_player(delta: float, speed: float = WALK_SPEED):
	var input_dir: Vector2 = get_movement_input()
	var direction = (avatar_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var speed_mod = speed * 0.6

	if direction:
		parent.velocity.x = direction.x * speed_mod
		parent.velocity.z = direction.z * speed_mod

	parent.velocity *= NetworkTime.physics_factor
	parent.move_and_slide()
	parent.velocity /= NetworkTime.physics_factor
