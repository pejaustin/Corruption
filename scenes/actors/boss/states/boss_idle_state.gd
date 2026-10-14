extends BossState

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	face_camera(delta)
	physics_move()
	if not actor.is_on_floor():
		state_machine.transition(&"FallState")
		return
	if try_attack():
		return
	if get_movement_input() != Vector2.ZERO:
		state_machine.transition(&"MoveState")
