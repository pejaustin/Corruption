class_name MinionSpawnPoint extends Marker3D

## Per-tower marker where that tower's overlord summons their minions.
## The slot_index (0-3) matches MultiplayerManager.get_player_slot for the
## owning peer — placed in the editor under each tower's Summoning Circle.

const GROUP: StringName = &"minion_spawn_points"

@export var slot_index: int = 0

func _ready() -> void:
	add_to_group(GROUP)
