extends MinionState

## Idle goes back to Chase only beyond this flat distance from the waypoint: ChaseState calls a nav-finished
## unit arrived within about 1.5 m, so the margin keeps a unit from flipping between the two at the edge.
const ARRIVE_RADIUS: float = 1.5
## PLACEHOLDER: tuning — hysteresis margin added to ARRIVE_RADIUS before Idle re-enters Chase (metres).
const REENTER_MARGIN: float = 1.5

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	if check_retreat():
		return

	actor.velocity.x = 0
	actor.velocity.z = 0

	# Head to waypoint if one is set and we're not there yet (flat distance: a goal off the ground is not unreachable)
	if minion.waypoint != Vector3.ZERO and flat_distance_to_point(minion.waypoint) > ARRIVE_RADIUS + REENTER_MARGIN:
		state_machine.transition(&"ChaseState")
		return

	physics_move()

	var target := find_hostile_target()
	if target and distance_to(target) < minion.aggro_radius:
		state_machine.transition(&"ChaseState")
