extends MovementState

func enter(previous_state: RewindableState, tick: int) -> void:
	overlord.velocity.y = JUMP_VELOCITY

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	rotate_player_model(delta)
	move_player(delta)

	force_update_is_on_floor()
	if not overlord.is_on_floor():
		state_machine.transition(&"FallState")
