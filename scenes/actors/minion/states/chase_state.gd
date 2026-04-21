extends MinionState

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	if minion == null:
		return
	# Hand off to JumpState if the agent flagged a jumpable link this tick.
	if minion.jump_target != Vector3.INF:
		state_machine.transition(&"JumpState")
		return
	var target := find_hostile_target()
	var destination: Vector3
	if target:
		destination = target.global_position
		var dist := distance_to(target)
		if dist < minion.attack_range:
			minion.attack_timer = 0.0
			state_machine.transition(&"AttackState")
			return
	elif minion.waypoint != Vector3.ZERO and actor.global_position.distance_to(minion.waypoint) > 1.5:
		destination = minion.waypoint
	else:
		state_machine.transition(&"IdleState")
		return

	var nav := minion.nav_agent
	
	var use_nav := nav != null
	if use_nav:
		nav.target_position = destination
	# If nav agent hasn't found a path (e.g., spawn outside the navmesh), fall
	# back to direct steering so the minion still makes progress.
	var flat_dist := Vector2(
		destination.x - actor.global_position.x,
		destination.z - actor.global_position.z
	).length()
	if flat_dist < 1.0:
		actor.velocity.x = 0
		actor.velocity.z = 0
		physics_move()
		state_machine.transition(&"IdleState")
		return

	var next_pos: Vector3 = destination
	if use_nav and not nav.is_navigation_finished():
		next_pos = nav.get_next_path_position()
	var dir := next_pos - actor.global_position
	dir.y = 0
	if dir.length() > 0.1:
		dir = dir.normalized()
		actor.velocity.x = dir.x * minion.move_speed
		actor.velocity.z = dir.z * minion.move_speed
		face_direction(dir)
	physics_move()
