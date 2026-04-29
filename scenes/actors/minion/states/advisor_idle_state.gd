extends MinionState

## Advisor in idle: stand still, watch the owner overlord. If the overlord
## drifts past RE_FOLLOW_DISTANCE, hand off to AdvisorFollowState (mounted on
## the same RewindableStateMachine under the node name "ChaseState").

const RE_FOLLOW_DISTANCE: float = 3.5

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	var overlord := _find_owner_overlord()
	if overlord == null:
		return
	if actor.global_position.distance_to(overlord.global_position) > RE_FOLLOW_DISTANCE:
		state_machine.transition(&"ChaseState")

func _find_owner_overlord() -> OverlordActor:
	for node in actor.get_tree().get_nodes_in_group(&"actors"):
		var ov := node as OverlordActor
		if ov == null:
			continue
		if ov.name.to_int() == minion.owner_peer_id:
			return ov
	return null
