class_name MinionState extends ActorState

## Base state for minion-specific states. Uses faction-aware hostility to pick targets.

var minion: MinionActor:
	get: return actor as MinionActor

## PLACEHOLDER: tuning — a target further above or below than this (metres) cannot be fought: the Paladin parked at
## y = -400 inside a site encounter, a unit on a roof.
const MAX_VERTICAL_REACH: float = 4.0
## PLACEHOLDER: tuning — a target whose nearest navmesh point is further than this (metres) cannot be walked to.
const MAX_NAV_GAP: float = 2.5
## PLACEHOLDER: tuning — seconds a lost or unreachable target is left alone before it can be picked again.
const IGNORE_SECONDS: float = 6.0

## PLACEHOLDER: tuning — seconds between a unit's scans of every actor for a target (kept target in between).
const SCAN_INTERVAL: float = 0.25
## PLACEHOLDER: tuning — random extra milliseconds per scan, so units do not all scan on the same frame.
const SCAN_STAGGER_MSEC: int = 100

func find_hostile_target() -> Actor:
	## Throttled per unit: the O(n) scan runs every SCAN_INTERVAL, and between scans the current target is kept
	## while it is still a valid one (a dead or lost target forces an immediate rescan).
	var now: int = Time.get_ticks_msec()
	if now < minion.next_scan_msec:
		var kept: Actor = minion.scan_target
		if kept == null:
			return null
		if is_instance_valid(kept) and kept.can_take_damage() and not minion.is_ignoring(kept):
			return kept
	minion.scan_target = _scan_for_target()
	minion.next_scan_msec = now + int(SCAN_INTERVAL * 1000.0) + randi() % SCAN_STAGGER_MSEC
	return minion.scan_target

func _scan_for_target() -> Actor:
	var best: Actor = null
	var best_dist: float = INF
	for node in actor.get_tree().get_nodes_in_group(&"actors"):
		var candidate := node as Actor
		if candidate == null or candidate == actor:
			continue
		if not candidate.can_take_damage():
			continue
		if candidate is AvatarActor and (candidate as AvatarActor).is_dormant:
			continue
		if not minion.is_hostile_to(candidate):
			continue
		if not minion.can_see(candidate):
			continue
		if minion.is_ignoring(candidate):
			continue
		var d := distance_to(candidate)
		if d < best_dist:
			if not is_reachable(candidate):
				minion.ignore_target(candidate, IGNORE_SECONDS)
				continue
			best_dist = d
			best = candidate
	return best

func is_reachable(candidate: Node3D) -> bool:
	## Cheap walkability test: the navmesh has a point near the target (not on a roof or in the void).
	var nav := minion.nav_agent
	if nav == null:
		return true
	var map_rid: RID = nav.get_navigation_map()
	if not map_rid.is_valid():
		return true
	var closest := NavigationServer3D.map_get_closest_point(map_rid, candidate.global_position)
	return closest.distance_to(candidate.global_position) <= MAX_NAV_GAP

func distance_to(target: Node3D) -> float:
	## Horizontal distance; INF when the target is out of vertical reach, so aggro, chase and attack all drop it.
	var diff := actor.global_position - target.global_position
	if absf(diff.y) > MAX_VERTICAL_REACH:
		return INF
	diff.y = 0
	return diff.length()

func flat_distance_to_point(point: Vector3) -> float:
	var diff := actor.global_position - point
	diff.y = 0
	return diff.length()

func face_direction(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	var target := actor.global_position - dir
	actor.look_at(target, Vector3.UP)

func check_retreat() -> bool:
	## Combat states call this at the top of tick(). When the minion is opt-in
	## retreat-capable and HP has dipped past the threshold, transitions into
	## RetreatState and returns true so the caller can early-out for this tick.
	## Host-only — clients receive the resulting state via sync.
	if not multiplayer.is_server():
		return false
	if not minion.can_retreat:
		return false
	if minion.hp > int(minion.max_hp_value * minion.retreat_hp_threshold):
		return false
	if state_machine.state == &"RetreatState" or state_machine.state == &"DeathState":
		return false
	state_machine.transition(&"RetreatState")
	return true
