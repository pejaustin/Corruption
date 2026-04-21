class_name MinionRallyPoint extends Marker3D

## Per-tower rally flag. Only the owning overlord can see or move it.
## MinionManager binds slot_index → owning peer_id at match start.
## Commands from the War Table move the marker; newly summoned minions
## set their initial waypoint to its global position.

const GROUP: StringName = &"minion_rally_points"

@export var slot_index: int = 0

var owning_peer_id: int = -1
var faction: int = GameConstants.Faction.NEUTRAL

func _ready() -> void:
	add_to_group(GROUP)
	_refresh_visibility()

func bind(peer_id: int, faction_id: int) -> void:
	owning_peer_id = peer_id
	faction = faction_id
	_refresh_visibility()

func move_to(new_pos: Vector3) -> void:
	global_position = new_pos

func _refresh_visibility() -> void:
	# Only the owning peer sees their own rally flag. Host treats unbound
	# markers as hidden until bind() is called.
	visible = owning_peer_id > 0 and owning_peer_id == multiplayer.get_unique_id()
