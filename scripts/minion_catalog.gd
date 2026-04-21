class_name MinionCatalog extends Resource

## Single registry of all minion scenes in the game. Edited as one .tres
## (res://data/minion_catalog.tres) so adding a minion is: create its type .tres,
## create its scene, drop the scene into `scenes`. Faction ownership lives on
## the MinionType itself, so the catalog doesn't need per-faction arrays.

@export var scenes: Array[PackedScene] = []

var _by_faction: Dictionary = {}
var _by_id: Dictionary = {}
var _type_by_scene: Dictionary = {}
var _indexed: bool = false

func _ensure_indexed() -> void:
	if _indexed:
		return
	_indexed = true
	_by_faction.clear()
	_by_id.clear()
	_type_by_scene.clear()
	for packed in scenes:
		if packed == null:
			continue
		var mtype := _extract_minion_type(packed)
		if mtype == null:
			push_warning("[MinionCatalog] Scene %s has no minion_type export" % packed.resource_path)
			continue
		_type_by_scene[packed] = mtype
		_by_id[mtype.id] = packed
		var list: Array = _by_faction.get(mtype.faction, [])
		list.append(packed)
		_by_faction[mtype.faction] = list

func _extract_minion_type(packed: PackedScene) -> MinionType:
	## Reads the root node's `minion_type` property from the PackedScene state
	## without instantiating. Returns null if not set.
	var state := packed.get_state()
	if state.get_node_count() == 0:
		return null
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"minion_type":
			return state.get_node_property_value(0, i) as MinionType
	return null

func scenes_for_faction(faction: int) -> Array[PackedScene]:
	_ensure_indexed()
	var result: Array[PackedScene] = []
	for packed in _by_faction.get(faction, []):
		result.append(packed)
	return result

func scene_for_id(type_id: StringName) -> PackedScene:
	_ensure_indexed()
	return _by_id.get(type_id, null)

func minion_type_for_scene(packed: PackedScene) -> MinionType:
	_ensure_indexed()
	return _type_by_scene.get(packed, null)

func minion_type_for_id(type_id: StringName) -> MinionType:
	var packed := scene_for_id(type_id)
	return _type_by_scene.get(packed, null) if packed else null

func minion_types_for_faction(faction: int) -> Array[MinionType]:
	_ensure_indexed()
	var result: Array[MinionType] = []
	for packed in _by_faction.get(faction, []):
		var mt: MinionType = _type_by_scene.get(packed, null)
		if mt:
			result.append(mt)
	return result
