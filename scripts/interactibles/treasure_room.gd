class_name TreasureRoom extends Node3D

## The tower's treasure room (GDD §2, §6, ticket #565): shows exactly what the
## tower holds (`MinionManager.get_treasury`) as stacked crates, one per good up
## to MAX_CRATES, with the exact number on a plaque. Only the tower's owner
## sees it (the other towers' rooms stay empty on your screen).
## PLACEHOLDER: the crate look, the plaque wording, the spot in the tower and
## every number below.

## PLACEHOLDER: tuning — crates shown at most (the plaque still says the exact
## number), and how they stack.
const MAX_CRATES: int = 200
const STACK_COLUMNS: int = 5
const STACK_ROWS: int = 4
## The size of crate.tscn's box, for spacing the stack.
const CRATE_SIZE: Vector3 = Vector3(0.45, 0.3, 0.45)
const CRATE_GAP: float = 0.05
# PLACEHOLDER: wording
const PLAQUE_FORMAT: String = "Goods: %d"

## Instanced once per good shown.
@export var crate_scene: PackedScene

var _shown_goods: int = -1
var _shown_peer: int = -2

@onready var _crates: Node3D = %Crates
@onready var _plaque: Label3D = %Plaque

func _ready() -> void:
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func get_owner_peer() -> int:
	var n: Node = get_parent()
	while n:
		if n is Tower:
			return (n as Tower).owner_peer_id
		n = n.get_parent()
	return multiplayer.get_unique_id()  # no tower around (a test harness)

func is_visible_to_local_peer() -> bool:
	return get_owner_peer() == multiplayer.get_unique_id()

func get_goods() -> int:
	var mm := _minion_manager()
	return mm.get_treasury(get_owner_peer()) if mm else 0

func get_crate_count() -> int:
	return _crates.get_child_count()

func get_plaque_text() -> String:
	return _plaque.text

func _refresh() -> void:
	var peer := get_owner_peer()
	var goods := get_goods() if is_visible_to_local_peer() else 0
	visible = is_visible_to_local_peer()
	if goods == _shown_goods and peer == _shown_peer:
		return
	_shown_goods = goods
	_shown_peer = peer
	_set_crate_count(mini(goods, MAX_CRATES))
	_plaque.text = PLAQUE_FORMAT % goods

func _minion_manager() -> MinionManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("MinionManager") as MinionManager if scene else null

func _set_crate_count(count: int) -> void:
	## Crates fill the grid bottom-up, one layer at a time.
	var per_layer: int = STACK_COLUMNS * STACK_ROWS
	while _crates.get_child_count() < count:
		var i: int = _crates.get_child_count()
		var layer: int = i / per_layer
		var slot: int = i % per_layer
		var crate := crate_scene.instantiate() as Node3D
		crate.position = Vector3(
			float(slot % STACK_COLUMNS) * (CRATE_SIZE.x + CRATE_GAP),
			CRATE_SIZE.y * 0.5 + float(layer) * CRATE_SIZE.y,
			float(slot / STACK_COLUMNS) * (CRATE_SIZE.z + CRATE_GAP))
		_crates.add_child(crate)
	while _crates.get_child_count() > count:
		var last: Node = _crates.get_child(_crates.get_child_count() - 1)
		_crates.remove_child(last)
		last.queue_free()
