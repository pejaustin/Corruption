extends PlayerState

func enter(previous_state: RewindableState, tick: int) -> void:
	actor.velocity.y = JUMP_VELOCITY

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	if try_enter_channel():
		return
	# Tier D: airborne attack press routes into JumpAttackState (overhead
	# plunge). Either button fires the same state — heavy and light both map
	# to the airborne moveset for now (faction asymmetry is Tier E's call).
	if get_light_attack() or get_heavy_attack() or player.avatar_input.consume_if_buffered(&"light_attack") or player.avatar_input.consume_if_buffered(&"heavy_attack"):
		if actor.try_transition(&"JumpAttackState"):
			return
	rotate_player_model(delta)
	move_air(delta)
	physics_move()

	if actor.velocity.y <= 0:
		state_machine.transition(&"FallState")
