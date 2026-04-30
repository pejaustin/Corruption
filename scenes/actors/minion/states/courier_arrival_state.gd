extends MinionState

## Mounted on courier_actor.tscn as the IdleState script (override). Lifecycle:
##
##   1. Courier spawns at the tower with `waypoint = source_pos` (the believed
##      location of the minions the order is for) and a delivery payload —
##      `delivery_minion_ids`, `delivery_target_pos`, `return_pos`. Initial
##      state is IdleState (= this script).
##   2. tick() sees we're far from the source, transitions to ChaseState. The
##      inherited ChaseState handles travel via NavigationAgent3D RVO.
##   3. ChaseState returns control on arrival → tick() runs the delivery
##      branch: _deliver(). Each id in delivery_minion_ids that's still alive
##      and owned by us has its waypoint set to delivery_target_pos.
##   4. _deliver() sets `waypoint = return_pos` and clears the payload, so
##      the next ChaseState run is the homeward leg.
##   5. On arrival at return_pos, tick() despawns the courier (Leave mode —
##      Stay mode TBD per war-table.md step 12).

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

	# At the current waypoint. If we still have a delivery payload, this is the
	# source leg; deliver and pivot to the homeward leg. Otherwise this is the
	# homeward arrival — despawn.
	if not minion.delivery_minion_ids.is_empty():
		_deliver()
		return
	_despawn()

func _deliver() -> void:
	var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		_despawn()
		return
	for mid in minion.delivery_minion_ids:
		var target := mm.get_minion_by_id(mid)
		if target == null or not is_instance_valid(target):
			continue
		if target.owner_peer_id != minion.owner_peer_id:
			continue
		if not target.can_take_damage():
			continue
		target.waypoint = minion.delivery_target_pos
	# Payload spent. Set the homeward waypoint so the next ChaseState run heads
	# back to the spawn / rally point. If return_pos was never populated (host
	# bug), fall through to despawn rather than wander.
	minion.delivery_minion_ids = []
	minion.delivery_target_pos = Vector3.INF
	if minion.return_pos == Vector3.INF:
		_despawn()
		return
	minion.waypoint = minion.return_pos

func _despawn() -> void:
	var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	# Standard host-driven cleanup — RPCs queue_free to all peers and clears
	# the WorldModel sighting. minion_died has no listeners doing combat-side
	# effects (verified via grep), so this is safe semantic reuse.
	mm.notify_minion_died(minion)
