extends PlayerState

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	if try_enter_channel():
		return
	if try_roll():
		return
	# Block before attack: a held guard takes priority over a buffered swing,
	# matching Souls' "block-cancel-attack-press" grammar. Also runs before
	# movement so the player can guard from a standstill.
	if try_block():
		return
	actor.velocity.x = 0
	actor.velocity.z = 0
	rotate_player_model(delta)
	physics_move()

	if actor.is_on_floor():
		# Heavy press takes priority over light — Souls grammar: light follows
		# light, heavy interrupts. The riposte check inside try_heavy_attack
		# also fires here, so a heavy near a posture-broken target executes.
		if try_heavy_attack():
			return
		if try_light_attack():
			return
		if get_movement_input() != Vector2.ZERO:
			state_machine.transition(&"MoveState")
		elif get_jump():
			state_machine.transition(&"JumpState")
	else:
		state_machine.transition(&"FallState")
