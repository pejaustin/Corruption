class_name Tower extends Node3D

## One of the four overlord towers. Owns its own MinionSpawnPoint in-scene.
## The tower_scene pairs each tower with a MinionRallyPoint from World/Markers
## by child order (Tower → MinionRallyPoint, Tower2 → MinionRallyPoint2, …).

var slot_index: int = -1
var spawn_point: MinionSpawnPoint
var rally_point: MinionRallyPoint

func _ready() -> void:
	spawn_point = _find_own_spawn_point()

func _find_own_spawn_point() -> MinionSpawnPoint:
	for n in get_tree().get_nodes_in_group(MinionSpawnPoint.GROUP):
		if n is MinionSpawnPoint and is_ancestor_of(n):
			return n
	return null

func assign_slot(index: int, rally: MinionRallyPoint) -> void:
	slot_index = index
	rally_point = rally
	if spawn_point:
		spawn_point.slot_index = index
	if rally_point:
		rally_point.slot_index = index
