extends MinionState

const Placement := preload("res://scenes/actors/minion/advisor_placement.gd")

## Advisor walking to his spot (`minion.waypoint`, chosen by AdvisorIdleState).
## Arrives within Placement.ARRIVE_RADIUS, then returns to Idle, so an
## unreachable-by-a-hair waypoint can't leave him stuck pushing at it.
##
## Mounted on the RewindableStateMachine under the node name "ChaseState" via
## script-property override on advisor_actor.tscn; peer states still call
## `state_machine.transition(&"ChaseState")` to enter this.

## Give up after this long (seconds) so a blocked path can't pin him in Chase.
const MAX_WALK_SECONDS: float = 8.0
var _walking: float = 0.0

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_walking = 0.0
	if minion.nav_agent != null:
		# The default stop distance is wider than our arrival radius, which left him short of his spot.
		minion.nav_agent.target_desired_distance = Placement.ARRIVE_RADIUS * 0.5

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	var nav := minion.nav_agent
	var target := minion.waypoint
	_walking += delta
	var to_target := target - actor.global_position
	to_target.y = 0
	if nav == null or to_target.length() < Placement.ARRIVE_RADIUS or _walking > MAX_WALK_SECONDS:
		actor.velocity.x = 0
		actor.velocity.z = 0
		physics_move()
		state_machine.transition(&"IdleState")
		return

	nav.target_position = target
	if nav.is_navigation_finished():
		actor.velocity.x = 0
		actor.velocity.z = 0
		physics_move()
		state_machine.transition(&"IdleState")
		return

	var dir := nav.get_next_path_position() - actor.global_position
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
		nav.set_velocity(dir * minion.move_speed)
		actor.velocity.x = minion.safe_velocity.x
		actor.velocity.z = minion.safe_velocity.z
		face_direction(dir)
	physics_move()
