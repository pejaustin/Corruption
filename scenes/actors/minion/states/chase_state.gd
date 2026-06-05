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
## Stuck-arrived only fires when the agent is at most this far from its
## destination. Beyond this, RVO orbits and chokepoint stalls are normal —
## giving up early causes minions to halt mid-path while still nowhere near
## the waypoint, and ping-pongs couriers between Chase ↔ arrival_state when
## the navmesh edge keeps them orbiting their spawn area. Inside this radius,
## the agent is "as good as arrived" and committing to idle/despawn is fine.
const STUCK_NEAR_DISTANCE: float = 3.5

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

	# Path-end commit: if our computed path's final point is meaningfully short
	# of the destination AND we've reached it, we're as close as the navmesh
	# allows — treat as arrived. Catches the "slot inside a wall / on a tiny
	# island" case where is_navigation_finished never fires because
	# target_position is unreachable. Without this the minion would orbit at
	# its path-end forever, since stuck-detection's STUCK_NEAR_DISTANCE gate
	# (3.5m) doesn't fire when the unreachable slot is further than that.
	var path_end: Vector3 = nav.get_final_position()
	var to_path_end: float = actor.global_position.distance_to(path_end)
	var path_end_to_dest: float = path_end.distance_to(destination)
	if to_path_end < 1.0 and path_end_to_dest > nav.target_desired_distance + 0.5:
		actor.velocity.x = 0
		actor.velocity.z = 0
		physics_move()
		if minion.minion_trait != &"courier":
			minion.waypoint = Vector3.ZERO
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
		# Also gated by distance: outside STUCK_NEAR_DISTANCE we keep trying
		# (lateral motion at long range is normal corner-cutting / chokepoint
		# routing — not a pile-up signal).
		if target == null:
			var to_dest := destination - actor.global_position
			to_dest.y = 0
			var to_dest_len: float = to_dest.length()
			if to_dest_len > 0.01 and to_dest_len <= STUCK_NEAR_DISTANCE:
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
						# Latch the current spot as "arrived" so IdleState's
						# distance-to-waypoint check doesn't immediately bounce
						# us back to chase. Couriers keep their original
						# waypoint — courier_arrival_state needs return_pos
						# intact to check the return zone overlap.
						if minion.minion_trait != &"courier":
							minion.waypoint = Vector3.ZERO
						state_machine.transition(&"IdleState")
						return
				else:
					_stuck_time = 0.0
			else:
				_stuck_time = 0.0
	physics_move()
