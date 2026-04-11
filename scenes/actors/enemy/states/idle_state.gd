extends EnemyState

func tick(delta: float, tick: int, is_fresh: bool):
	actor.velocity.x = 0
	actor.velocity.z = 0

	# Return to patrol point if drifted
	var to_patrol := enemy.patrol_point - actor.global_position
	to_patrol.y = 0
	if to_patrol.length() > 1.0:
		var dir := to_patrol.normalized()
		actor.velocity.x = dir.x * EnemyActor.SPEED * 0.5
		actor.velocity.z = dir.z * EnemyActor.SPEED * 0.5
		face_direction(dir)

	physics_move()

	var avatar := find_avatar()
	if avatar and distance_to(avatar) < EnemyActor.AGGRO_RADIUS:
		state_machine.transition(&"ChaseState")
