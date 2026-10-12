class_name EncounterSpace extends Node3D

## An encounter's rooms, authored in a .tscn (temple_dungeon, runestone_arena).
## SiteEncounter instances it far below the map and moves the Paladin to
## `Entry`. Enemies are EncounterSpawn markers anywhere under this node.
## PLACEHOLDER: everything here is stand-in layout, not designed.

## Rooms (a dungeon is 3-5, the arena has one).
@export_range(1, 5) var room_count: int = 1

@onready var entry: Marker3D = %Entry

func spawns() -> Array[EncounterSpawn]:
	var out: Array[EncounterSpawn] = []
	for node in find_children("*", "EncounterSpawn", true, false):
		out.append(node as EncounterSpawn)
	return out
