extends PlayerState

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	if try_enter_channel():
		return
	# Tier D: airborne attack press → JumpAttackState. Same plunge as JumpState;
	# states share AttackData (`jump_attack.tres`) for consistent feel.
	if get_light_attack() or get_heavy_attack() or player.avatar_input.consume_if_buffered(&"light_attack") or player.avatar_input.consume_if_buffered(&"heavy_attack"):
		if actor.try_transition(&"JumpAttackState"):
			return
	rotate_player_model(delta)
	move_air(delta)
	physics_move()

	if actor.is_on_floor():
		if get_movement_input() != Vector2.ZERO:
			state_machine.transition(&"MoveState")
		else:
			state_machine.transition(&"IdleState")
