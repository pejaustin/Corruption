extends AvatarMovementState

func tick(delta, tick, is_fresh):
	rotate_player_model(delta)
	move_player(delta)

	force_update_is_on_floor()
	if parent.is_on_floor():
		if get_movement_input() == Vector2.ZERO:
			state_machine.transition(&"IdleState")
		elif get_jump():
			state_machine.transition(&"JumpState")
	else:
		state_machine.transition(&"FallState")

func move_player(delta: float, speed = WALK_SPEED):
	var input_dir: Vector2 = get_movement_input()

	var direction = (avatar_camera.camera_basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var position_target = direction * speed

	if get_run():
		position_target *= RUN_MODIFIER

	var horizontal_velocity = position_target

	if horizontal_velocity:
		parent.velocity.x = horizontal_velocity.x
		parent.velocity.z = horizontal_velocity.z
	else:
		parent.velocity.x = move_toward(parent.velocity.x, 0, speed)
		parent.velocity.z = move_toward(parent.velocity.z, 0, speed)

	parent.velocity *= NetworkTime.physics_factor
	parent.move_and_slide()
	parent.velocity /= NetworkTime.physics_factor
