extends PlayerState

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	if try_enter_channel():
		return
	rotate_player_model(delta)
	move_air(delta)
	physics_move()

	if actor.is_on_floor():
		if get_movement_input() != Vector2.ZERO:
			state_machine.transition(&"MoveState")
		else:
			state_machine.transition(&"IdleState")
