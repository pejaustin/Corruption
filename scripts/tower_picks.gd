class_name TowerPicks
extends RefCounted

## Each seat picks its own tower in the lobby (Austin, 2026-10-13); a tower nobody picked is left out of the match.
## A pick is the tower's slot (`Tower.slot_index`, 0-3), authored in the landscape scene. These helpers hold the
## rules (one seat per tower, every seat needs one) and the removal of the unpicked towers, so the lobby, GameState
## and the tests share them. Data-only: no state of its own beyond the name cache.

const TOWER_SCENE_PATH: String = "res://scenes/world/env/tower.tscn"

## world size -> (slot -> tower name), read once per size.
static var _names: Dictionary[int, Dictionary] = {}

static func slot_names(world_size: int) -> Dictionary[int, String]:
	## The towers of a world size by slot, named as Austin named their markers in the landscape scene
	## ("Naf Ishun", "Volcano Tower", ...). Read from the scene file's text (cheap, no world is instanced), or in a build from the packed scene's state.
	if _names.has(world_size):
		return _names[world_size]
	var path: String = MatchConfig.LANDSCAPE_SCENES.get(world_size, MatchConfig.LANDSCAPE_SCENES[MatchConfig.WorldSize.NORMAL])
	var out := _names_from_text(path)
	if out.is_empty():
		out = _names_from_state(path)
	if out.is_empty() and world_size != MatchConfig.WorldSize.NORMAL:
		# The scene did not load (the legacy 6 km map's ground may be missing): the towers' slots and names are the
		# 2 km map's (PLACEHOLDER notes in the 6 km scene).
		return slot_names(MatchConfig.WorldSize.NORMAL)
	_names[world_size] = out
	return out

static func _names_from_state(path: String) -> Dictionary[int, String]:
	## From the packed scene's state (needs the scene to load, which pulls in the world's art; the way in a build).
	var out: Dictionary[int, String] = {}
	var packed := load(path) as PackedScene
	if packed == null:
		return out
	var state := packed.get_state()
	for i in state.get_node_count():
		var inst := state.get_node_instance(i)
		if inst == null or inst.resource_path != TOWER_SCENE_PATH:
			continue
		var node_path := state.get_node_path(i)
		if node_path.get_name_count() < 2:
			continue
		for j in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"slot_index":
				out[int(state.get_node_property_value(i, j))] = String(node_path.get_name(node_path.get_name_count() - 2))
	return out

static func _names_from_text(path: String) -> Dictionary[int, String]:
	## From the .tscn text, when the scene itself can't load (a checkout whose art isn't imported). Not in a build,
	## where scenes are binary.
	var out: Dictionary[int, String] = {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return out
	var text := file.get_as_text()
	var id_match := RegEx.create_from_string("\\[ext_resource[^\\]]*path=\"" + TOWER_SCENE_PATH + "\"[^\\]]*id=\"([^\"]+)\"").search(text)
	if id_match == null:
		return out
	var node_re := RegEx.create_from_string("^\\[node name=\"Tower\" parent=\"((?:[^\"\\\\]|\\\\.)*)\".*instance=ExtResource\\(\"" + id_match.get_string(1) + "\"\\)")
	var parent_name := ""
	for line in text.split("\n"):
		if line.begins_with("["):
			parent_name = ""
			var m := node_re.search(line)
			if m != null:
				var raw := m.get_string(1).replace("\\'", "'")
				parent_name = raw.get_slice("/", raw.get_slice_count("/") - 1)
		elif parent_name != "" and line.begins_with("slot_index = "):
			out[int(line.trim_prefix("slot_index = "))] = parent_name
	return out

static func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < GameConstants.MAX_PLAYERS

static func is_free(picks: Dictionary, peer_id: int, slot: int) -> bool:
	## True when no other seat has `slot`.
	for pid in picks:
		if int(pid) != peer_id and int(picks[pid]) == slot:
			return false
	return true

static func can_pick(picks: Dictionary, peer_id: int, slot: int) -> bool:
	return is_valid_slot(slot) and is_free(picks, peer_id, slot)

static func all_picked(seats: Array, picks: Dictionary) -> bool:
	## True when every seat has a tower.
	for pid in seats:
		if not picks.has(pid):
			return false
	return true

static func picked_slots(picks: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for pid in picks:
		out.append(int(picks[pid]))
	out.sort()
	return out

static func remove_unpicked(tree: SceneTree, picked: Array[int], rallies: Array[MinionRallyPoint] = []) -> Array[int]:
	## Leaves every tower in a slot not in `picked` out of the match, on this peer: the tower (its building, spawn point,
	## trickle, map floor, beacon, corruption site, advisor), the rally point of its slot (`rallies[slot]`), and the map
	## point of its gate. The towers' map floors forget that point, and the other points stop listing it as a neighbour.
	## Returns the removed slots. Nodes leave the tree at once (so groups and lookups no longer see them) and are freed
	## at the end of the frame. Does nothing for a tower with no authored slot.
	var removed: Array[int] = []
	for tower in Tower.in_slot_order(tree):
		if tower.slot_index < 0 or tower.slot_index in picked:
			continue
		removed.append(tower.slot_index)
		tower.get_parent().remove_child(tower)
		tower.queue_free()
	for slot in removed:
		if slot < rallies.size() and rallies[slot] != null:
			rallies[slot].get_parent().remove_child(rallies[slot])
			rallies[slot].queue_free()
	var gone: Array[MapPoint] = []
	for point in MapPoint.all_points(tree):
		if point.kind == MapPoint.Kind.TOWER and point.tower_slot in removed:
			gone.append(point)
	for point in gone:
		for other in MapPoint.all_points(tree):
			other.neighbors.erase(point)
		for tower in Tower.in_slot_order(tree):
			var map_floor := tower.get_node_or_null(^"MapFloor") as MapFloor
			if map_floor != null:
				map_floor.forget_point(point.point_id)
		point.get_parent().remove_child(point)
		point.queue_free()
	return removed
