extends PlayerState

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	rotate_player_model(delta)
	move_horizontal(delta)
	physics_move()

	if actor.is_on_floor():
		if get_attack():
			state_machine.transition(&"AttackState")
		elif get_movement_input() == Vector2.ZERO:
			state_machine.transition(&"IdleState")
		elif get_jump():
			state_machine.transition(&"JumpState")
	else:
		state_machine.transition(&"FallState")
