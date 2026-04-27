extends PlayerState

func enter(previous_state: RewindableState, tick: int) -> void:
	actor.velocity.y = JUMP_VELOCITY

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	if try_enter_channel():
		return
	rotate_player_model(delta)
	move_air(delta)
	physics_move()

	if actor.velocity.y <= 0:
		state_machine.transition(&"FallState")
