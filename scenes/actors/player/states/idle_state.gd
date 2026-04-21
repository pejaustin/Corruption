extends PlayerState

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	rotate_player_model(delta)
	physics_move()

	if actor.is_on_floor():
		if get_attack():
			state_machine.transition(&"AttackState")
		elif get_movement_input() != Vector2.ZERO:
			state_machine.transition(&"MoveState")
		elif get_jump():
			state_machine.transition(&"JumpState")
	else:
		state_machine.transition(&"FallState")
