class_name WorldModel extends RefCounted

## One player's belief about the world — lossy, late, possibly wrong (GDD §1:
## "none of the genre's free information exists"). Lives on that player's own
## machine and is only ever changed by reports (KnowledgeManager): what the
## tower sees at its gate, what couriers and returning groups bring home, and
## the beacons everyone sees in the sky. Never read by the simulation.

signal record_added(entry: Dictionary)
signal changed

## group id -> { id, pos: Vector3, count: int, status: StringName, goal: int,
##   dest_point: StringName, leader_id: int, experience: float,
##   maneuvers: Array, tick: int, source: StringName }
## GroupManager.AVATAR_GROUP_ID is the Paladin when this player holds him.
var believed_groups: Dictionary[int, Dictionary] = {}
## unit id -> { pos: Vector3, owner_peer_id: int, faction: int, tick: int }
## Units of rivals and of the good faction seen by your people.
var believed_enemies: Dictionary[int, Dictionary] = {}
## Map points this player has on their map (GDD Q3).
var known_points: Dictionary[StringName, bool] = {}
## site node name -> { holder: int, tick: int }. Beacons are seen by all.
var believed_sites: Dictionary[StringName, Dictionary] = {}
## Orders this player has sent: cmd id -> { group_ids: Array[int],
##   route_points: Array[StringName], dest_point: StringName, goal: int,
##   stage: StringName (&"requested", &"dispatched", &"delivered", &"undelivered",
##   &"lost", &"refused"), courier_id: int, tick: int }
var orders: Dictionary[int, Dictionary] = {}
## What this player expects of a group they ordered (Austin, 2026-10-09): group
## id -> { cmd_id, path: Array[Vector3] (where it was, then the route, ending
##   at the destination), goal, dest_point, anchor_dist (metres along path at
##   anchor_tick), anchor_tick, state: &"expected", &"confirmed" (a report agreed) or &"missing", missing_pos }.
## The piece walks the path at EXPECTED_SPEED from the order; it is only
## "missing" when information contradicts the expectation. Age never does.
var expectations: Dictionary[int, Dictionary] = {}
## Pieces moved by hand on the map floor to guess or plan (GDD Q10): group id
## (or enemy unit id, negated - 1000000) -> world position. Cleared by asking
## the advisor to update the map.
var piece_overrides: Dictionary[int, Vector3] = {}
## The ledger (GDD §6): resource site name -> { pile: int, tick: int }, the
## latest reports of goods held elsewhere.
var ledger: Dictionary[StringName, Dictionary] = {}
## Couriers waiting at the tower (mirrored from the host).
var couriers_home: int = 0
## The advisor's most recent report lines.
var last_report_lines: Array[String] = []

## What this player has on record (GDD §2 "Desk with books", Q37): leaders'
## maneuvers, relics held, what's been learned. Each entry:
##   { kind: StringName (&"report", &"group", &"relic", &"site", ...),
##     title: String, text: String, tick: int }
var records: Array[Dictionary] = []
## The player's own free notes, written at the desk. Local to this peer.
var notes: String = ""

func add_record(kind: StringName, title: String, text: String, tick: int) -> void:
	var entry := {"kind": kind, "title": title, "text": text, "tick": tick}
	records.append(entry)
	record_added.emit(entry)

func is_point_known(point_id: StringName) -> bool:
	return known_points.get(point_id, false)

## PLACEHOLDER: tuning, not designed — how fast the map expects a group to walk (m/s).
const EXPECTED_SPEED: float = 3.5
## PLACEHOLDER: tuning, not designed — how long a confirming report keeps a
## piece looking confirmed before the map is extrapolating again (seconds).
const CONFIRMED_SECONDS: float = 10.0
## PLACEHOLDER: tuning, not designed — a report this far (m) off the expected
## route contradicts the expectation.
const CONTRADICTION_RADIUS: float = 25.0
## PLACEHOLDER: tuning, not designed — a report this near the end of the route
## ends the expectation (they arrived).
const ARRIVED_RADIUS: float = 12.0

func update_group(entry: Dictionary, tick: int, source: StringName) -> void:
	var gid := int(entry.get("id", -1))
	var e := entry.duplicate(true)
	e["tick"] = tick
	e["source"] = source
	if int(e.get("count", 1)) <= 0:
		believed_groups.erase(gid)
		expectations.erase(gid)
		return
	believed_groups[gid] = e
	_check_expectation(gid, e, source)

# --- Expectations ---

func expect(gid: int, cmd_id: int, start: Vector3, route: Array, goal: int, dest_point: StringName, tick: int) -> void:
	## An order was sent: the group should now be walking `route` from `start`.
	var path: Array[Vector3] = [start]
	for p in route:
		path.append(p)
	expectations[gid] = {"cmd_id": cmd_id, "path": path, "goal": goal, "dest_point": dest_point,
		"anchor_dist": 0.0, "anchor_tick": tick, "state": &"expected", "missing_pos": start}

func piece_state(gid: int) -> StringName:
	## &"confirmed" (the last report stands), &"expected" or &"missing".
	var x: Dictionary = expectations.get(gid, {})
	var state: StringName = x.get("state", &"confirmed")
	if state == &"confirmed" and not x.is_empty() and float(NetworkTime.tick - int(x["anchor_tick"])) / _rate() > CONFIRMED_SECONDS:
		return &"expected"  # The report was a while ago; the map is extrapolating again.
	return state

static func _rate() -> float:
	return float(NetworkTime.tickrate) if NetworkTime.tickrate > 0 else 30.0

func expected_position(gid: int, tick: int) -> Vector3:
	var x: Dictionary = expectations.get(gid, {})
	if x.is_empty():
		return Vector3.INF
	if x["state"] == &"missing":
		return x["missing_pos"]
	var dist := float(x["anchor_dist"]) + EXPECTED_SPEED * maxf(0.0, float(tick - int(x["anchor_tick"]))) / _rate()
	return point_along(x["path"], dist)

func group_position(gid: int, tick: int) -> Vector3:
	## Where this player's map puts a group: the expectation, else the last report.
	var at := expected_position(gid, tick)
	if at != Vector3.INF:
		return at
	var e: Dictionary = believed_groups.get(gid, {})
	return e.get("pos", Vector3.ZERO)

func search_points(gid: int, tick: int, max_points: int) -> Array[Vector3]:
	## Where a courier looks, in order, if the group is not where the map puts
	## it: the rest of the route ahead, then back along it.
	var out: Array[Vector3] = []
	var x: Dictionary = expectations.get(gid, {})
	if x.is_empty():
		return out
	var path: Array = x["path"]
	var dist := float(x["anchor_dist"]) + EXPECTED_SPEED * maxf(0.0, float(tick - int(x["anchor_tick"]))) / _rate()
	var at := 0.0
	var ahead: Array[Vector3] = []
	var behind: Array[Vector3] = []
	for i in path.size():
		if i > 0:
			at += (path[i - 1] as Vector3).distance_to(path[i])
		if at > dist:
			ahead.append(path[i])
		else:
			behind.append(path[i])
	behind.reverse()
	out.append_array(ahead)
	out.append_array(behind)
	if out.size() > max_points:
		out.resize(max_points)
	return out

func mark_missing(gid: int, tick: int) -> void:
	## A courier could not find the group where it was expected (or looked
	## along its route and found nothing): the piece stays where it was
	## expected, drawn as missing.
	var at := group_position(gid, tick)
	var x: Dictionary = expectations.get(gid, {})
	if x.is_empty():
		x = {"cmd_id": -1, "path": [at], "goal": -1, "dest_point": &"", "anchor_dist": 0.0, "anchor_tick": tick}
	x["state"] = &"missing"
	x["missing_pos"] = at
	expectations[gid] = x

func _check_expectation(gid: int, report: Dictionary, source: StringName) -> void:
	## Compare a report with what was expected. It confirms (the piece goes
	## back to normal and the expectation follows the real position) or it
	## contradicts (reality wins: the piece stands where the report put it).
	var x: Dictionary = expectations.get(gid, {})
	if x.is_empty():
		return
	var path: Array = x["path"]
	var pos: Vector3 = report.get("pos", Vector3.ZERO)
	var goal := int(report.get("goal", -1))
	var seen_tick := int(report.get("obs_tick", report.get("tick", 0)))
	var off := distance_to_path(path, pos)
	var near_start := (path[0] as Vector3).distance_to(pos) <= CONTRADICTION_RADIUS
	# A courier's snapshot taken as it hands the order over shows the group
	# as it was before that order: its old goal is not a contradiction.
	var before := int(report.get("before_cmd", -2)) == int(x["cmd_id"])
	var wrong_goal := goal != -1 and goal != int(x["goal"]) and not before
	if off > CONTRADICTION_RADIUS or wrong_goal:
		expectations.erase(gid)
		return
	var end: Vector3 = path[path.size() - 1]
	var finished := source == &"returned" or pos.distance_to(end) <= ARRIVED_RADIUS
	if goal == -1 and source == &"home" and orders.get(int(x["cmd_id"]), {}).get("stage", &"") == &"delivered":
		finished = true  # The order was taken, and now they are home without one.
	if finished:
		expectations.erase(gid)
		return
	if before and near_start or goal == -1 and near_start:
		# Seen before (or without) the order reaching it; the walk goes on.
		if x["state"] == &"missing":
			x["state"] = &"expected"
			x["anchor_dist"] = 0.0
			x["anchor_tick"] = seen_tick
		return
	x["state"] = &"confirmed"
	x["anchor_dist"] = project_on_path(path, pos)
	x["anchor_tick"] = seen_tick

static func path_length(path: Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += (path[i - 1] as Vector3).distance_to(path[i])
	return total

static func point_along(path: Array, dist: float) -> Vector3:
	if path.is_empty():
		return Vector3.ZERO
	var left := maxf(dist, 0.0)
	for i in range(1, path.size()):
		var seg := (path[i - 1] as Vector3).distance_to(path[i])
		if left <= seg:
			return (path[i - 1] as Vector3).lerp(path[i], left / maxf(seg, 0.001))
		left -= seg
	return path[path.size() - 1]

static func project_on_path(path: Array, pos: Vector3) -> float:
	## Arc length along `path` of the point nearest `pos` (flat).
	var best := INF
	var best_at := 0.0
	var at := 0.0
	for i in range(1, path.size()):
		var a: Vector3 = path[i - 1]
		var b: Vector3 = path[i]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var t := 0.0
		if ab.length_squared() > 0.0001:
			t = clampf(Vector2(pos.x - a.x, pos.z - a.z).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a.lerp(b, t)
		var d := Vector2(pos.x - q.x, pos.z - q.z).length()
		if d < best:
			best = d
			best_at = at + a.distance_to(b) * t
		at += a.distance_to(b)
	return best_at

static func distance_to_path(path: Array, pos: Vector3) -> float:
	if path.size() == 1:
		return Vector2(pos.x - path[0].x, pos.z - path[0].z).length()
	var at := project_on_path(path, pos)
	var q := point_along(path, at)
	return Vector2(pos.x - q.x, pos.z - q.z).length()

func update_enemy(entry: Dictionary) -> void:
	var uid := int(entry.get("id", -1))
	believed_enemies[uid] = {
		"pos": entry.get("pos", Vector3.ZERO),
		"owner_peer_id": int(entry.get("owner_peer_id", -1)),
		"faction": int(entry.get("faction", GameConstants.Faction.NEUTRAL)),
		"tick": int(entry.get("observed_tick", 0)),
	}

func forget_enemy(unit_id: int) -> void:
	believed_enemies.erase(unit_id)

func piece_position(key: int, believed: Vector3) -> Vector3:
	return piece_overrides.get(key, believed)
