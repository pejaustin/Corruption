class_name CourierErrand

## A courier's errand when it goes wrong (Austin, 2026-10-13, #627). Host-only,
## static, run from MinionActor for couriers:
##   - tick: a courier that gets no closer to its next stop for GIVE_UP_SECONDS
##     turns home with the errands it could not finish (blocked, or the group
##     seen but out of reach). Blocked on the way home too, it stops where it is;
##     after LOST_SECONDS its owner is told it is lost.
##   - look: a group it was sent to, seen within SIGHT_METRES in line of sight,
##     is recognised: its state (en route, stuck, arrived) is noted, the
##     courier walks to where it really is, and a check needs nothing more.
## CourierArrivalState runs the errand itself (stops, hand-over, search).

## PLACEHOLDER: tuning — seconds a courier may go without getting closer to its
## next stop before it turns home (and, on the way home, before it stops).
const GIVE_UP_SECONDS: float = 30.0
## PLACEHOLDER: tuning — metres closer that count as progress.
const PROGRESS_METRES: float = 1.0
## PLACEHOLDER: tuning — seconds a courier stranded on its way home stands
## before its owner is told it is lost.
const LOST_SECONDS: float = 60.0
## PLACEHOLDER: tuning — how far (m) a courier recognises the group it was sent to.
const SIGHT_METRES: float = 40.0
## Eye height for the line-of-sight ray (both ends).
const EYE_HEIGHT: float = 1.5
## The world layer: what blocks sight.
const SIGHT_MASK: int = 1
## A waiting courier stands within this of its stop (CourierArrivalState.DELIVERY_DISTANCE).
const AT_STOP_METRES: float = 4.0
## A waypoint moved this far is a new stop: progress is measured afresh.
const NEW_STOP_METRES: float = 1.5

# --- Giving up ---

static func tick(c: MinionActor, delta: float) -> void:
	if not c.can_take_damage():
		return
	if c.errand_state == &"stranded":
		if c.errand_lost_seconds < 0.0:
			return  # Already reported lost.
		c.errand_lost_seconds += delta
		if c.errand_lost_seconds >= LOST_SECONDS:
			c.errand_lost_seconds = -1.0
			KnowledgeManager.courier_stranded(c)
		return
	var wp := c.waypoint
	if wp == Vector3.ZERO:
		return
	if c.errand_tracked_waypoint.distance_to(wp) > NEW_STOP_METRES:
		_reset_progress(c)
	var d := _flat(c.global_position - wp)
	# Waiting at a stop (handing over, searching) is not being stuck.
	if c._state_machine.state == &"IdleState" and d <= AT_STOP_METRES:
		return
	if d < c.errand_best_distance - PROGRESS_METRES:
		c.errand_best_distance = d
		c.errand_stall_seconds = 0.0
		return
	c.errand_stall_seconds += delta
	if c.errand_stall_seconds >= GIVE_UP_SECONDS:
		give_up(c, &"blocked")

static func give_up(c: MinionActor, reason: StringName) -> void:
	## Turn home with what could not be done; blocked on the way home, stop.
	if c.errand_state == &"homeward" or (c.delivery_legs.is_empty() and c.scout_route.is_empty()):
		c.errand_state = &"stranded"
		c.errand_lost_seconds = 0.0
		c.waypoint = Vector3.ZERO
		c.velocity = Vector3.ZERO
		c._state_machine.transition(&"IdleState")
		return
	c.errand_state = &"homeward"
	var undelivered: Array = c.carried_report.get("undelivered", [])
	for leg in c.delivery_legs:
		for sub in leg.get("sub_orders", []):
			if sub.get("done", false):
				continue
			var entry := {"group_id": int(sub.get("group_id", -1)), "cmd_id": int(sub.get("cmd_id", -1)),
				"reason": &"unreachable" if sub.has("seen") else reason, "at": c.global_position}
			undelivered.append(entry)
			merge_sighting(c, sub)
			note_order(c, sub, &"undelivered")
	if c.delivery_legs.is_empty():
		undelivered.append({"group_id": -1, "cmd_id": -1, "reason": reason, "at": c.global_position})
	c.carried_report["undelivered"] = undelivered
	c.delivery_legs.clear()
	c.scout_route.clear()
	c.waypoint = c.return_pos
	_reset_progress(c)
	c._state_machine.transition(&"ChaseState")

# --- Sight ---

static func look(c: MinionActor) -> void:
	## Recognise the groups this courier was sent to when they come into view.
	if c.errand_state != &"" or c.delivery_legs.is_empty():
		return
	var gm := _gm(c)
	if gm == null:
		return
	var any_done := false
	for leg in c.delivery_legs:
		for sub in leg.get("sub_orders", []):
			if sub.get("done", false):
				continue
			var g := gm.get_group(int(sub.get("group_id", -1)))
			if g == null or g.owner_peer_id != c.owner_peer_id:
				continue
			var seen := _first_in_sight(c, gm.get_members(g))
			if seen == null:
				continue
			var snap := gm.snapshot(g)
			snap["sighted"] = true  # Seen from afar: nothing handed over, nothing heard.
			var first: bool = not sub.has("seen")
			sub["seen"] = snap
			if sub.get("order", {}).get("check", false):
				# Seeing them is all a check needs.
				merge_sighting(c, sub)
				sub["done"] = true
				note_order(c, sub, &"checked")
				any_done = true
			elif first:
				# Walk to where they are, not where the map had them.
				var mm := _mm(c)
				var at: Vector3 = mm.snap_to_navmesh_point(seen.global_position) if mm else seen.global_position
				leg["source_pos"] = at
				if is_same(leg, c.delivery_legs[0]):
					c.waypoint = at
	if any_done:
		_drop_done_legs(c)

static func _first_in_sight(c: MinionActor, members: Array[MinionActor]) -> MinionActor:
	var space := c.get_world_3d().direct_space_state
	var eye := c.global_position + Vector3.UP * EYE_HEIGHT
	for m in members:
		if c.global_position.distance_to(m.global_position) > SIGHT_METRES:
			continue
		# Data-only: a ray query.
		var query := PhysicsRayQueryParameters3D.create(eye, m.global_position + Vector3.UP * EYE_HEIGHT, SIGHT_MASK)
		if space.intersect_ray(query).is_empty():
			return m
	return null

# --- Shared with CourierArrivalState ---

static func note_order(c: MinionActor, sub: Dictionary, stage: StringName) -> void:
	var orders: Array = c.carried_report.get("orders", [])
	orders.append({"cmd_id": int(sub.get("cmd_id", -1)), "stage": stage})
	c.carried_report["orders"] = orders

static func merge_sighting(c: MinionActor, sub: Dictionary) -> void:
	## The last look at a group the courier saw but did not speak to.
	if not sub.has("seen"):
		return
	var groups: Array = c.carried_report.get("groups", [])
	groups.append(sub["seen"])
	c.carried_report["groups"] = groups

static func next_waypoint(c: MinionActor) -> Vector3:
	## The next stop: the head leg, else the scouting route, else home.
	if not c.delivery_legs.is_empty():
		return c.delivery_legs[0].get("source_pos", c.return_pos)
	if not c.scout_route.is_empty():
		return c.scout_route[0]
	return c.return_pos

static func _drop_done_legs(c: MinionActor) -> void:
	var head: Dictionary = c.delivery_legs[0]
	var left: Array[Dictionary] = []
	for leg in c.delivery_legs:
		for sub in leg.get("sub_orders", []):
			if not sub.get("done", false):
				left.append(leg)
				break
	c.delivery_legs = left
	if left.is_empty() or not is_same(left[0], head):
		c.waypoint = next_waypoint(c)

static func _reset_progress(c: MinionActor) -> void:
	c.errand_tracked_waypoint = c.waypoint
	c.errand_best_distance = INF
	c.errand_stall_seconds = 0.0

static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

static func _gm(c: MinionActor) -> GroupManager:
	var scene := c.get_tree().current_scene
	return scene.get_node_or_null("GroupManager") as GroupManager if scene else null

static func _mm(c: MinionActor) -> MinionManager:
	var scene := c.get_tree().current_scene
	return scene.get_node_or_null("MinionManager") as MinionManager if scene else null
