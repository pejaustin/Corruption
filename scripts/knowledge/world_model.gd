class_name WorldModel extends RefCounted

## An overlord's belief about the battlefield — lossy, delayed, possibly false.
## Rendered by the War Table. Mutated by the KnowledgeManager, never read by the
## simulation.
##
## Every entry is timestamped so staleness can be visualized and decay rules
## applied later. With INFINITE_BROADCAST_RANGE=true the model ends up a 1:1
## mirror of truth; once the flag flips off, entries start going stale and the
## asymmetry appears.

## minion_id -> { pos: Vector3, owner_peer_id: int, faction: int, last_updated_tick: int, source: StringName }
var believed_friendly_minions: Dictionary[int, Dictionary] = {}
var believed_enemy_minions: Dictionary[int, Dictionary] = {}

## peer_id -> { pos: Vector3, last_updated_tick: int }
var believed_avatar_positions: Dictionary[int, Dictionary] = {}

## gem_id -> { capture_progress: float, owner: int, last_updated_tick: int }
var believed_gem_states: Dictionary[StringName, Dictionary] = {}

## command_id -> {
##   stage: StringName,        # &"draft" before handoff, &"dispatched" after
##   start_pos: Vector3,        # where the courier will / does spawn from
##   target_pos: Vector3,       # where the order points
##   courier_id: int,           # -1 while a draft, real minion id once dispatched
##   issued_tick: int,
## }
var pending_commands: Dictionary[int, Dictionary] = {}

func update_minion_sighting(
	minion_id: int,
	pos: Vector3,
	owner_peer_id: int,
	faction: int,
	tick: int,
	is_friendly: bool,
	source: StringName = &"broadcast",
) -> void:
	var entry: Dictionary = {
		"pos": pos,
		"owner_peer_id": owner_peer_id,
		"faction": faction,
		"last_updated_tick": tick,
		"source": source,
	}
	if is_friendly:
		believed_friendly_minions[minion_id] = entry
		believed_enemy_minions.erase(minion_id)
	else:
		believed_enemy_minions[minion_id] = entry
		believed_friendly_minions.erase(minion_id)

func forget_minion(minion_id: int) -> void:
	believed_friendly_minions.erase(minion_id)
	believed_enemy_minions.erase(minion_id)

func all_believed_minions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in believed_friendly_minions.values():
		out.append(entry)
	for entry in believed_enemy_minions.values():
		out.append(entry)
	return out
