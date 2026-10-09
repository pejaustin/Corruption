extends MinionState

## A courier's errand (GDD §4: "Couriers carry all information, including
## orders"). Mounted as the IdleState of courier_actor.tscn.
##
##   1. Walk (ChaseState) to the head stop: where the player believed the group
##      to be.
##   2. Look for any member of the group within courier_visual_range. Found:
##      hand over the order, take the group's report (status, what it saw,
##      places it passed). Not found: wait courier_wait_seconds re-checking,
##      then give up and note the failure.
##   3. Next stop; with no stops left, walk the scouting route if sent alone to
##      look, then head home. MinionActor despawns it at its gate and hands
##      the report to KnowledgeManager.courier_arrived_home.

## Arrival tolerance at a stop (wider than the nav agent's own).
const DELIVERY_DISTANCE: float = 4.0

var _wait_remaining: float = -1.0

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_wait_remaining = -1.0

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	if not multiplayer.is_server():
		return
	if minion.waypoint == Vector3.ZERO:
		return
	if minion.delivery_legs.is_empty():
		_tick_scouting_or_home()
		return
	if _wait_remaining < 0.0:
		if actor.global_position.distance_to(minion.waypoint) > DELIVERY_DISTANCE:
			state_machine.transition(&"ChaseState")
			return
		_attempt_delivery()
		if _head_leg_done():
			_advance()
			return
		_wait_remaining = minion.courier_wait_seconds
		return
	_attempt_delivery()
	if _head_leg_done():
		_advance()
		return
	_wait_remaining -= delta
	if _wait_remaining <= 0.0:
		_record_failures()
		_advance()

func _tick_scouting_or_home() -> void:
	if minion.scout_route.is_empty():
		state_machine.transition(&"ChaseState")  # Homeward; the gate despawns it.
		return
	var next: Vector3 = minion.scout_route[0]
	if minion.waypoint != next:
		minion.waypoint = next
	if actor.global_position.distance_to(next) > DELIVERY_DISTANCE:
		state_machine.transition(&"ChaseState")
		return
	minion.scout_route.pop_front()
	if minion.scout_route.is_empty():
		minion.waypoint = minion.return_pos
	else:
		minion.waypoint = minion.scout_route[0]

func _attempt_delivery() -> void:
	var gm := _gm()
	if gm == null:
		return
	var leg: Dictionary = minion.delivery_legs[0]
	var range_sq: float = maxf(minion.courier_visual_range, DELIVERY_DISTANCE)
	range_sq *= range_sq
	for sub in leg.get("sub_orders", []):
		if sub.get("done", false):
			continue
		var gid := int(sub.get("group_id", -1))
		if gid == GroupManager.AVATAR_GROUP_ID:
			var avatar := _find_commandable_avatar()
			if avatar and actor.global_position.distance_squared_to(avatar.global_position) <= range_sq:
				gm.set_order(gid, sub.get("order", {}))
				sub["done"] = true
				_note_order(sub, &"delivered")
			continue
		var group := gm.get_group(gid)
		if group == null or group.owner_peer_id != minion.owner_peer_id:
			continue
		for m in gm.get_members(group):
			if actor.global_position.distance_squared_to(m.global_position) <= range_sq:
				# The report is taken before the new order: it tells you how the
				# group was when the courier found it.
				_merge_report(gm.make_report(group))
				gm.set_order(gid, sub.get("order", {}))
				sub["done"] = true
				_note_order(sub, &"delivered")
				break

func _head_leg_done() -> bool:
	for sub in minion.delivery_legs[0].get("sub_orders", []):
		if not sub.get("done", false):
			return false
	return true

func _record_failures() -> void:
	for sub in minion.delivery_legs[0].get("sub_orders", []):
		if sub.get("done", false):
			continue
		var gid := int(sub.get("group_id", -1))
		minion.delivery_failures.append({"group_id": gid, "cmd_id": int(sub.get("cmd_id", -1))})
		_note_order(sub, &"undelivered")
		var gm := _gm()
		if gm and gm.get_group(gid) == null:
			var lost: Array = minion.carried_report.get("lost_groups", [])
			lost.append(gid)
			minion.carried_report["lost_groups"] = lost

func _note_order(sub: Dictionary, stage: StringName) -> void:
	var orders: Array = minion.carried_report.get("orders", [])
	orders.append({"cmd_id": int(sub.get("cmd_id", -1)), "stage": stage})
	minion.carried_report["orders"] = orders

func _merge_report(part: Dictionary) -> void:
	for key in ["groups", "sightings", "points"]:
		var into: Array = minion.carried_report.get(key, [])
		into.append_array(part.get(key, []))
		minion.carried_report[key] = into

func _advance() -> void:
	_wait_remaining = -1.0
	minion.delivery_legs.pop_front()
	if not minion.delivery_legs.is_empty():
		minion.waypoint = minion.delivery_legs[0].get("source_pos", minion.return_pos)
	elif not minion.scout_route.is_empty():
		minion.waypoint = minion.scout_route[0]
	else:
		minion.waypoint = minion.return_pos

func _find_commandable_avatar() -> AvatarActor:
	if GameState.avatar_owner_peer_id != minion.owner_peer_id:
		return null
	var avatar := actor.get_tree().current_scene.get_node_or_null("World/Avatar") as AvatarActor
	if avatar == null or avatar.hp <= 0 or avatar.avatar_ai == null:
		return null
	return avatar

func _gm() -> GroupManager:
	return actor.get_tree().current_scene.get_node_or_null("GroupManager") as GroupManager
