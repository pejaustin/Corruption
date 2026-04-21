extends MinionState

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0

	# Head to waypoint if one is set and we're not there yet
	if minion.waypoint != Vector3.ZERO and actor.global_position.distance_to(minion.waypoint) > 1.5:
		state_machine.transition(&"ChaseState")
		return

	physics_move()

	var target := find_hostile_target()
	if target and distance_to(target) < minion.aggro_radius:
		state_machine.transition(&"ChaseState")
