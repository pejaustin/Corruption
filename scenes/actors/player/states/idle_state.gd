extends PlayerState

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	if try_enter_channel():
		return
	if try_roll():
		return
	actor.velocity.x = 0
	actor.velocity.z = 0
	rotate_player_model(delta)
	physics_move()

	if actor.is_on_floor():
		if try_attack():
			return
		if get_movement_input() != Vector2.ZERO:
			state_machine.transition(&"MoveState")
		elif get_jump():
			state_machine.transition(&"JumpState")
	else:
		state_machine.transition(&"FallState")
