class_name FakeMinion extends Node3D

## Wandering stand-in for a MinionActor. Used only by the War Table test scene
## so diorama iteration doesn't require booting the full game.

@export var faction: int = 0
@export var owner_peer_id: int = -1
@export var playspace_extent: Vector2 = Vector2(15.0, 15.0)
@export var speed: float = 2.0

var _target: Vector3 = Vector3.ZERO

func _ready() -> void:
	_pick_target()

func _process(delta: float) -> void:
	var to_target: Vector3 = _target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.3:
		_pick_target()
		return
	global_position += to_target.normalized() * speed * delta

func _pick_target() -> void:
	_target = Vector3(
		randf_range(-playspace_extent.x, playspace_extent.x),
		global_position.y,
		randf_range(-playspace_extent.y, playspace_extent.y),
	)
