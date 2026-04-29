extends MinionState

## Ratio (vs minion.move_speed) of velocity *projected onto the direction to
## the destination* below which the agent is considered to be making no
## progress. Measuring progress (not raw speed) catches the orbit case: RVO
## often emits full-magnitude lateral safe_velocity as agents slide around
## each other, so |safe_velocity| stays high while actual closing speed is
## ~zero. The dot product nails the difference.
const STUCK_PROGRESS_RATIO: float = 0.25
## Seconds the agent must stay below STUCK_VELOCITY_RATIO before being
## treated as arrived. Long enough to ride out a single corner-turn or
## momentary deflection, short enough that pile-ups settle quickly.
const STUCK_DURATION: float = 0.5

var _stuck_time: float = 0.0

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_stuck_time = 0.0

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	if minion == null:
		return
	if check_retreat():
		return
	# Hand off to JumpState if the agent flagged a jumpable link this tick.
	if minion.jump_target != Vector3.INF:
		state_machine.transition(&"JumpState")
		return
	var target := find_hostile_target()
	# Only chase hostiles inside aggro range; distant hostiles must be ignored
	# so a minion heading to rally doesn't divert across the map to a target.
	if target and distance_to(target) > minion.aggro_radius:
		target = null
	var destination: Vector3
	if target:
		destination = target.global_position
		if distance_to(target) < minion.attack_range:
			minion.attack_timer = 0.0
			state_machine.transition(&"AttackState")
			return
	elif minion.waypoint != Vector3.ZERO:
		destination = minion.waypoint
	else:
		state_machine.transition(&"IdleState")
		return

	var nav := minion.nav_agent
	if nav == null:
		state_machine.transition(&"IdleState")
		return

	nav.target_position = destination
	if nav.is_navigation_finished():
		actor.velocity.x = 0
		actor.velocity.z = 0
		physics_move()
		state_machine.transition(&"IdleState")
		return

	var next_pos: Vector3 = nav.get_next_path_position()
	var dir := next_pos - actor.global_position
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
		# Hand the desired velocity to the agent; it computes an
		# avoidance-adjusted version and emits velocity_computed, which
		# minion._on_velocity_computed caches on minion.safe_velocity.
		# We read it here (one-tick lag, normal for RVO) and apply it.
		nav.set_velocity(dir * minion.move_speed)
		actor.velocity.x = minion.safe_velocity.x
		actor.velocity.z = minion.safe_velocity.z
		face_direction(dir)

		# "Stuck = arrived" backup, in case formation slots are blocked or
		# a minion ends up sharing a slot. Measure the velocity component
		# pointing AT the destination — if that's ~zero for a while the
		# agent has no closing speed regardless of how fast it's sliding
		# sideways. Skip when chasing a live target so units don't give
		# up on a fleeing enemy during a momentary pile-up at a chokepoint.
		if target == null:
			var to_dest := destination - actor.global_position
			to_dest.y = 0
			var to_dest_len: float = to_dest.length()
			if to_dest_len > 0.01:
				var to_dest_dir: Vector3 = to_dest / to_dest_len
				var v: Vector3 = minion.safe_velocity
				v.y = 0
				var progress_speed: float = v.dot(to_dest_dir)
				if progress_speed < minion.move_speed * STUCK_PROGRESS_RATIO:
					_stuck_time += delta
					if _stuck_time >= STUCK_DURATION:
						actor.velocity.x = 0
						actor.velocity.z = 0
						physics_move()
						state_machine.transition(&"IdleState")
						return
				else:
					_stuck_time = 0.0
	physics_move()
