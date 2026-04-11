extends PlayerState

func enter(previous_state: RewindableState, tick: int):
	actor.velocity.y = JUMP_VELOCITY

func tick(delta: float, tick: int, is_fresh: bool):
	rotate_player_model(delta)
	move_air(delta)
	physics_move()

	if actor.velocity.y <= 0:
		state_machine.transition(&"FallState")
