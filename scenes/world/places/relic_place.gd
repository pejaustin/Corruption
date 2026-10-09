class_name RelicPlace extends Node3D

## A relic lying somewhere on the map (GDD §5, Q35), waiting for a group sent to
## bring it home (OrderGoal.RETRIEVE). One relic, taken once; if its carrier dies
## it falls back here. Which relics exist and where they lie is Austin's
## (tickets #580, #584); the placement in world.tscn is a placeholder.

const GROUP: StringName = &"relic_places"

@export var relic: Relic
@export var radius: float = 6.0

var available: bool = true

@onready var _look: MeshInstance3D = %Look

func _ready() -> void:
	add_to_group(GROUP)
	_look.visible = available

func get_relic_index() -> int:
	return Relic.index_of(relic)

func take() -> int:
	## Host-only. Returns the relic's index, or -1 when it is gone.
	if not multiplayer.is_server() or not available:
		return -1
	_sync_available.rpc(false)
	return get_relic_index()

@rpc("authority", "call_local", "reliable")
func _sync_available(value: bool) -> void:
	available = value
	if _look:
		_look.visible = value

static func near(tree: SceneTree, pos: Vector3, max_dist: float) -> RelicPlace:
	for n in tree.get_nodes_in_group(GROUP):
		var p := n as RelicPlace
		if p and Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() <= max_dist:
			return p
	return null

static func restore(tree: SceneTree, relic_index: int) -> void:
	## Host-only: a carrier fell; the relic lies where it was found again.
	for n in tree.get_nodes_in_group(GROUP):
		var p := n as RelicPlace
		if p and not p.available and p.get_relic_index() == relic_index:
			p._sync_available.rpc(true)
			return
