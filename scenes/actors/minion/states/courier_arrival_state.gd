extends MinionState

## Mounted on courier_actor.tscn as the IdleState script (override). Lifecycle:
##
##   1. Courier spawns at the tower with `waypoint = legs[0].source_pos` and a
##      delivery payload — `delivery_legs: Array[{source_pos, sub_orders}]`,
##      `return_pos`, `return_zone`. Each sub_order is {minion_ids, target_pos}.
##      Initial state is IdleState (= this script).
##   2. tick() sees we're far from the head leg's source, transitions to
##      ChaseState. Inherited ChaseState walks via NavigationAgent3D RVO.
##   3. ChaseState returns control on arrival → tick() runs the **visibility
##      check** for each sub_order at the head leg: minion ids within
##      `courier_visual_range` of the courier get their order delivered (via
##      `MinionManager.command_selection_move` with formation-slot fan-out);
##      out-of-range / dead / hostile-flipped ids are stripped out of the
##      sub_order's id list and remain pending.
##   4. If every sub_order at the leg is now empty → the leg is done; pop and
##      advance to the next leg (or to the homeward waypoint).
##   5. If anything's still pending, the courier loiters at the source for
##      `courier_wait_seconds` (read from MinionType). Each tick during the
##      wait re-runs step 3, so a minion that wanders into range mid-wait
##      gets its order. When the timer expires, whatever's still missing is
##      flushed onto `delivery_failures` (carried home and reported via
##      KnowledgeManager.notify_delivery_failures on home zone overlap).
##   6. Homeward despawn is owned by MinionActor._physics_process's per-tick
##      zone-overlap check — when the courier's body crosses into the
##      return_zone Area3D, the failure list is flushed and the courier is
##      cleaned up via notify_minion_died.

## Distance at which the courier is treated as having "arrived" at a leg's
## source. Wider than nav's target_desired_distance so a stuck-arrival inside
## that radius still triggers the visibility check instead of bouncing
## Chase ↔ arrival_state.
const DELIVERY_DISTANCE: float = 4.0

## -1 = not waiting; 0+ = seconds remaining at the current leg.
var _wait_remaining: float = -1.0

func enter(_previous_state: RewindableState, _tick: int) -> void:
	# Reset the wait timer whenever we re-enter idle so each leg gets a fresh
	# courier_wait_seconds budget.
	_wait_remaining = -1.0

func tick(delta: float, _tick: int, _is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if not multiplayer.is_server():
		return
	if minion.waypoint == Vector3.ZERO:
		return

	var has_payload := not minion.delivery_legs.is_empty()
	if not has_payload:
		# Going home. ChaseState walks; per-tick zone check on MinionActor
		# handles despawn (see _physics_process there).
		state_machine.transition(&"ChaseState")
		return

	# Has payload — at or heading to the head leg's source.
	if _wait_remaining < 0.0:
		# Not yet in wait state. If we haven't arrived, keep chasing.
		var to_target := actor.global_position.distance_to(minion.waypoint)
		if to_target > DELIVERY_DISTANCE:
			state_machine.transition(&"ChaseState")
			return
		# Arrived — first visibility pass. Anything visible is delivered now;
		# anything not visible stays in the sub_order's id list for retry.
		_attempt_delivery_at_head_leg()
		if _is_head_leg_fully_delivered():
			_advance_after_leg()
			return
		# Some / all targets weren't visible. Begin loiter.
		_wait_remaining = minion.courier_wait_seconds
		return

	# In wait. Keep re-checking each tick — minions might walk into range.
	_attempt_delivery_at_head_leg()
	if _is_head_leg_fully_delivered():
		_advance_after_leg()
		return
	_wait_remaining -= delta
	if _wait_remaining <= 0.0:
		# Loiter timed out. Flush whatever's still pending into the courier's
		# failure list so it's reported on home arrival, then advance.
		_record_remaining_as_failures()
		_advance_after_leg()

func _attempt_delivery_at_head_leg() -> void:
	## For each sub_order at the head leg, find minion ids whose actors are
	## currently within `courier_visual_range` of the courier and deliver to
	## them. Strips delivered ids out of the sub_order's `minion_ids` so a
	## subsequent retry only re-considers the still-missing remainder.
	## Untargetable / dead / ownership-changed ids are also removed (the
	## courier can't deliver to a minion that no longer exists or is no
	## longer ours), but they accumulate into the same "missing" bucket so
	## they show up as failures on the home report.
	var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	var leg: Dictionary = minion.delivery_legs[0]
	var sub_orders: Array = leg.get("sub_orders", [])
	var visual_range: float = minion.courier_visual_range
	if visual_range <= 0.0:
		# Sanity fallback: a courier without a configured range still works
		# at point-blank. Without this, visual_range = 0 makes every check
		# fail and the courier never delivers anything.
		visual_range = DELIVERY_DISTANCE
	var visual_range_sq: float = visual_range * visual_range
	for sub in sub_orders:
		var ids: Array = sub.get("minion_ids", [])
		var target_pos: Vector3 = sub.get("target_pos", Vector3.INF)
		if target_pos == Vector3.INF or ids.is_empty():
			continue
		var visible: Array = []
		var still_pending: Array = []
		for raw in ids:
			var mid: int = int(raw)
			var target := mm.get_minion_by_id(mid)
			if target == null or not is_instance_valid(target) or not target.can_take_damage():
				# Dead or removed — can't deliver. Don't keep retrying; let
				# this fall through to the failure report at wait-timeout.
				still_pending.append(mid)
				continue
			if target.owner_peer_id != minion.owner_peer_id:
				# Domination flipped ownership; not ours to command.
				still_pending.append(mid)
				continue
			if actor.global_position.distance_squared_to(target.global_position) > visual_range_sq:
				still_pending.append(mid)
				continue
			visible.append(mid)
		if not visible.is_empty():
			mm.command_selection_move(visible, target_pos)
		sub["minion_ids"] = still_pending

func _is_head_leg_fully_delivered() -> bool:
	var leg: Dictionary = minion.delivery_legs[0]
	for sub in leg.get("sub_orders", []):
		if not (sub.get("minion_ids", []) as Array).is_empty():
			return false
	return true

func _record_remaining_as_failures() -> void:
	## Anything still in the head leg's sub_orders after the wait timer
	## expires becomes a failure entry on the courier's home report.
	var leg: Dictionary = minion.delivery_legs[0]
	var leg_source: Vector3 = leg.get("source_pos", actor.global_position)
	for sub in leg.get("sub_orders", []):
		var missing: Array = sub.get("minion_ids", [])
		if missing.is_empty():
			continue
		minion.delivery_failures.append({
			"minion_ids": missing.duplicate(),
			"target_pos": sub.get("target_pos", Vector3.INF),
			"leg_source": leg_source,
		})

func _advance_after_leg() -> void:
	_wait_remaining = -1.0
	minion.delivery_legs.pop_front()
	if minion.delivery_legs.is_empty():
		if minion.return_pos == Vector3.INF:
			_despawn()
			return
		minion.waypoint = minion.return_pos
		return
	var next: Dictionary = minion.delivery_legs[0]
	minion.waypoint = next.get("source_pos", minion.return_pos)

func _despawn() -> void:
	var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	# Flush any failures into the WorldModel before tear-down. Normally the
	# home-zone overlap check on MinionActor handles this, but if the courier
	# despawns from this state path (e.g. return_pos was INF) we still want
	# the overlord to learn about missed deliveries.
	if not minion.delivery_failures.is_empty():
		KnowledgeManager.notify_delivery_failures(minion.owner_peer_id, minion.delivery_failures)
		minion.delivery_failures.clear()
	mm.notify_minion_died(minion)
