extends BossState

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	face_camera(delta)
	physics_move()
	if actor.is_on_floor():
		state_machine.transition(&"IdleState")
