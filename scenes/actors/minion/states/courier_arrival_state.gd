extends MinionState

## Mounted on courier_actor.tscn as the IdleState script (override). Lifecycle:
##
##   1. Courier spawns with waypoint set to the order target. Initial state is
##      IdleState (= this script).
##   2. tick() sees we're far from waypoint and transitions to ChaseState. The
##      inherited ChaseState handles travel via NavigationAgent3D RVO.
##   3. ChaseState transitions back to IdleState (= this) on arrival.
##   4. tick() now sees we're at the waypoint and fires _deliver_and_despawn.
##
## Stay/Leave delivery modes (war-table.md step 12) are not yet implemented;
## this is the basic Stay-equivalent that just delivers and evaporates.

const ARRIVAL_DISTANCE: float = 2.0

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if not multiplayer.is_server():
		return
	if minion.waypoint == Vector3.ZERO:
		return

	var to_target := actor.global_position.distance_to(minion.waypoint)
	if to_target > ARRIVAL_DISTANCE:
		state_machine.transition(&"ChaseState")
		return

	_deliver_and_despawn()

func _deliver_and_despawn() -> void:
	var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	var squad: Array[MinionActor] = []
	for m in mm.get_minions_for_player(minion.owner_peer_id):
		if m == minion:
			continue
		squad.append(m)
	mm._assign_formation_waypoints(squad, minion.waypoint)
	# Standard host-driven cleanup — RPCs queue_free to all peers and clears
	# the WorldModel sighting. minion_died has no listeners doing combat-side
	# effects (verified via grep), so this is safe semantic reuse.
	mm.notify_minion_died(minion)
