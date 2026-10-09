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
const CRATE_SIZE: Vector3 = Vector3(0.45, 0.3, 0.45)
const CRATE_GAP: float = 0.05
const CRATE_COLOR: Color = Color(0.7, 0.55, 0.25)
# PLACEHOLDER: wording
const PLAQUE_FORMAT: String = "Goods: %d"
const PLAQUE_HEIGHT: float = 2.2

var _crates: MultiMeshInstance3D
var _plaque: Label3D
var _shown_goods: int = -1
var _shown_peer: int = -2

func _ready() -> void:
	_build_look()
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
	return _crates.multimesh.visible_instance_count if _crates and _crates.multimesh else 0

func get_plaque_text() -> String:
	return _plaque.text if _plaque else ""

func _refresh() -> void:
	var peer := get_owner_peer()
	var goods := get_goods() if is_visible_to_local_peer() else 0
	visible = is_visible_to_local_peer()
	if goods == _shown_goods and peer == _shown_peer:
		return
	_shown_goods = goods
	_shown_peer = peer
	_crates.multimesh.visible_instance_count = mini(goods, MAX_CRATES)
	_plaque.text = PLAQUE_FORMAT % goods

func _minion_manager() -> MinionManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("MinionManager") as MinionManager if scene else null

func _build_look() -> void:
	## PLACEHOLDER: art — plain boxes in a grid, filling bottom-up.
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var box := BoxMesh.new()
	box.size = CRATE_SIZE
	multi.mesh = box
	multi.instance_count = MAX_CRATES
	var per_layer: int = STACK_COLUMNS * STACK_ROWS
	for i in MAX_CRATES:
		var layer: int = i / per_layer
		var slot: int = i % per_layer
		var x: float = float(slot % STACK_COLUMNS) * (CRATE_SIZE.x + CRATE_GAP)
		var z: float = float(slot / STACK_COLUMNS) * (CRATE_SIZE.z + CRATE_GAP)
		var y: float = CRATE_SIZE.y * 0.5 + float(layer) * CRATE_SIZE.y
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
	multi.visible_instance_count = 0
	_crates = MultiMeshInstance3D.new()
	_crates.name = "Crates"
	_crates.multimesh = multi
	var mat := StandardMaterial3D.new()
	mat.albedo_color = CRATE_COLOR
	_crates.material_override = mat
	add_child(_crates)
	_plaque = Label3D.new()
	_plaque.name = "Plaque"
	_plaque.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_plaque.font_size = 48
	_plaque.outline_size = 8
	_plaque.position = Vector3(float(STACK_COLUMNS) * 0.25, PLAQUE_HEIGHT, 0.0)
	add_child(_plaque)
