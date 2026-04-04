extends MovementState

func tick(delta, tick, is_fresh):
	parent.velocity.x = 0
	parent.velocity.z = 0
	rotate_player_model(delta)
	move_player(delta)
	
	force_update_is_on_floor()
	if parent.is_on_floor():
		if get_movement_input() != Vector2.ZERO:
			state_machine.transition(&"MoveState")
		elif get_jump():
			state_machine.transition(&"JumpState")
		elif get_attack():
			state_machine.transition(&"AttackState")
	else:
		state_machine.transition(&"FallState")
