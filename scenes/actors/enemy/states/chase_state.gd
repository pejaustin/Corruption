extends EnemyState

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	var avatar := find_avatar()
	if not avatar or avatar.is_dormant:
		state_machine.transition(&"IdleState")
		return

	var dist := distance_to(avatar)
	if dist > EnemyActor.DEAGGRO_RADIUS:
		state_machine.transition(&"IdleState")
		return
	if dist < EnemyActor.ATTACK_RANGE:
		enemy.attack_timer = 0.0
		state_machine.transition(&"AttackState")
		return

	var dir := (avatar.global_position - actor.global_position)
	dir.y = 0
	dir = dir.normalized()
	actor.velocity.x = dir.x * EnemyActor.SPEED
	actor.velocity.z = dir.z * EnemyActor.SPEED
	face_direction(dir)
	physics_move()
