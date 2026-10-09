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

func update_group(entry: Dictionary, tick: int, source: StringName) -> void:
	var gid := int(entry.get("id", -1))
	var e := entry.duplicate(true)
	e["tick"] = tick
	e["source"] = source
	if int(e.get("count", 1)) <= 0:
		believed_groups.erase(gid)
		return
	believed_groups[gid] = e

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
