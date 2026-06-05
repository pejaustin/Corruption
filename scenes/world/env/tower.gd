class_name Tower extends Node3D

## One of the four overlord towers. Owns its own MinionSpawnPoint in-scene.
## The tower_scene pairs each tower with a MinionRallyPoint from World/Markers
## by child order (Tower → MinionRallyPoint, Tower2 → MinionRallyPoint2, …).

const GROUP: StringName = &"towers"

var slot_index: int = -1
var spawn_point: MinionSpawnPoint
## Marker3D where couriers (war-table delivery + info-gathering) spawn and
## return. Separate from spawn_point because the regular spawn lives high on
## the tower (where minions descend from), but couriers need somewhere on the
## navmesh they can actually pathfind back to. Authored as a child of tower.tscn
## named "CourierSpawn" — designers position it on the ground near the tower.
var courier_spawn: Node3D
var rally_point: MinionRallyPoint
## Pre-placed Advisor MinionActor under this tower. MinionManager binds its
## owner_peer_id to the peer assigned to this slot at match start so the
## advisor follows the right overlord and accepts only that overlord's
## war-table handoffs.
var advisor: MinionActor
## Peer this tower belongs to. Set by bind_advisor (which runs on every client
## via the same RPC that binds the rally point). The WarTable child uses this
## to gate rendering + interactivity so each overlord only sees / acts on
## their own table — foreign tables stay inert in the local client.
var owner_peer_id: int = -1

func _ready() -> void:
	add_to_group(GROUP)
	spawn_point = _find_own_spawn_point()
	courier_spawn = _find_own_courier_spawn()
	advisor = _find_own_advisor()

func _find_own_spawn_point() -> MinionSpawnPoint:
	for n in get_tree().get_nodes_in_group(MinionSpawnPoint.GROUP):
		if n is MinionSpawnPoint and is_ancestor_of(n):
			return n
	return null

func _find_own_courier_spawn() -> Node3D:
	# Authored as a direct "CourierSpawn" Marker3D child. Returns null on towers
	# that haven't been retrofitted with one yet — MinionManager falls back to
	# spawn_point in that case so old scenes keep dispatching couriers (just to
	# the unreachable old spot, which is the bug we're fixing).
	var named := get_node_or_null(^"CourierSpawn")
	return named as Node3D

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
## after slot→peer assignment is known. The faction matters: without it the
## advisor stays at Actor's NEUTRAL default and the owner's own minions read
## it as hostile (NEUTRAL is hostile to all non-neutral factions by design).
func bind_advisor(peer_id: int, faction: int) -> void:
	owner_peer_id = peer_id
	if advisor == null:
		advisor = _find_own_advisor()
	if advisor:
		advisor.owner_peer_id = peer_id
		advisor.faction = faction
