extends MinionState

## Advisor in follow: pathfind toward the owner overlord. Re-enter Idle once
## inside FOLLOW_DISTANCE so the advisor stops at conversational range and
## doesn't try to occupy the overlord's footprint.
##
## Mounted on the RewindableStateMachine under the node name "ChaseState" via
## script-property override on advisor_actor.tscn — that's why peer states
## still call `state_machine.transition(&"ChaseState")` to enter this.

const FOLLOW_DISTANCE: float = 2.0

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	var overlord := _find_owner_overlord()
	if overlord == null:
		state_machine.transition(&"IdleState")
		return

	var to_overlord := overlord.global_position - actor.global_position
	to_overlord.y = 0
	if to_overlord.length() < FOLLOW_DISTANCE:
		actor.velocity.x = 0
		actor.velocity.z = 0
		physics_move()
		state_machine.transition(&"IdleState")
		return

	var nav := minion.nav_agent
	if nav == null:
		state_machine.transition(&"IdleState")
		return

	nav.target_position = overlord.global_position
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
		nav.set_velocity(dir * minion.move_speed)
		actor.velocity.x = minion.safe_velocity.x
		actor.velocity.z = minion.safe_velocity.z
		face_direction(dir)
	physics_move()

func _find_owner_overlord() -> OverlordActor:
	for node in actor.get_tree().get_nodes_in_group(&"actors"):
		var ov := node as OverlordActor
		if ov == null:
			continue
		if ov.name.to_int() == minion.owner_peer_id:
			return ov
	return null
