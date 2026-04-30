class_name Tower extends Node3D

## One of the four overlord towers. Owns its own MinionSpawnPoint in-scene.
## The tower_scene pairs each tower with a MinionRallyPoint from World/Markers
## by child order (Tower → MinionRallyPoint, Tower2 → MinionRallyPoint2, …).

const GROUP: StringName = &"towers"

var slot_index: int = -1
var spawn_point: MinionSpawnPoint
var rally_point: MinionRallyPoint
## Pre-placed Advisor MinionActor under this tower. MinionManager binds its
## owner_peer_id to the peer assigned to this slot at match start so the
## advisor follows the right overlord and accepts only that overlord's
## war-table handoffs.
var advisor: MinionActor

func _ready() -> void:
	add_to_group(GROUP)
	spawn_point = _find_own_spawn_point()
	advisor = _find_own_advisor()

func _find_own_spawn_point() -> MinionSpawnPoint:
	for n in get_tree().get_nodes_in_group(MinionSpawnPoint.GROUP):
		if n is MinionSpawnPoint and is_ancestor_of(n):
			return n
	return null

func _find_own_advisor() -> MinionActor:
	# Authored as a direct "Advisor" child in tower.tscn. If the name shifts,
	# fall back to a typed search of immediate children so refactors don't
	# silently break the binding.
	var named := get_node_or_null(^"Advisor")
	if named is MinionActor:
		return named
	for child in get_children():
		if child is MinionActor and (child as MinionActor).minion_trait == &"advisor":
			return child
	return null

func assign_slot(index: int, rally: MinionRallyPoint) -> void:
	slot_index = index
	rally_point = rally
	if spawn_point:
		spawn_point.slot_index = index
	if rally_point:
		rally_point.slot_index = index

## Bind this tower's advisor to its owning overlord. Called by MinionManager
## after slot→peer assignment is known.
func bind_advisor(peer_id: int) -> void:
	if advisor == null:
		advisor = _find_own_advisor()
	if advisor:
		advisor.owner_peer_id = peer_id
