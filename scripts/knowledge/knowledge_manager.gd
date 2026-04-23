extends Node

## Autoload. Maintains each overlord's WorldModel — their belief about the
## battlefield — and exposes the API the War Table reads from. See
## docs/systems/war-table.md for the full design.
##
## Feature flags below let the rest of the game run while individual pieces of
## the information-warfare system are built. With both flags true, this module
## is a transparent passthrough: every minion updates every model every tick,
## and commands go directly to MinionManager.

## When true, every friendly and enemy minion continuously updates every
## overlord's WorldModel regardless of distance from the owning tower. Flip
## off once broadcast-range tuning is ready (build order step 5).
const INFINITE_BROADCAST_RANGE: bool = true

## When true, War Table clicks are executed immediately via MinionManager.
## When false, clicks record an intent and an Advisor dispatches a courier
## (build order step 7).
const INSTANT_COMMANDS: bool = true

## Radius around a friendly minion (or its tower) within which activity leaks
## into the owner's WorldModel. Unused while INFINITE_BROADCAST_RANGE is true.
const BROADCAST_RANGE: float = 30.0

## How often sightings are flushed from truth into belief.
const UPDATE_INTERVAL: float = 0.1

var _models: Dictionary[int, WorldModel] = {}
var _update_timer: float = 0.0
var _tick: int = 0

func get_model(peer_id: int) -> WorldModel:
	if peer_id not in _models:
		_models[peer_id] = WorldModel.new()
	return _models[peer_id]

func has_model(peer_id: int) -> bool:
	return peer_id in _models

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < UPDATE_INTERVAL:
		return
	_update_timer = 0.0
	_tick += 1
	_ingest_sightings()

func _ingest_sightings() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mm := scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	var peers := _known_peers()
	if peers.is_empty():
		return
	var minions := mm.get_all_minions()
	for pid in peers:
		var model := get_model(pid)
		for m in minions:
			if not is_instance_valid(m):
				continue
			if not INFINITE_BROADCAST_RANGE and not _observable_by(pid, m, minions):
				continue
			var is_friendly := m.owner_peer_id == pid
			model.update_minion_sighting(
				m.name.to_int(),
				m.global_position,
				m.owner_peer_id,
				m.faction,
				_tick,
				is_friendly,
			)

func _observable_by(peer_id: int, minion: MinionActor, all_minions: Array[MinionActor]) -> bool:
	# Placeholder for range check. Path 1 (broadcast range) lights up in a
	# later build step — for now we just approximate by distance from any
	# friendly minion.
	for other in all_minions:
		if other.owner_peer_id != peer_id:
			continue
		if other.global_position.distance_to(minion.global_position) <= BROADCAST_RANGE:
			return true
	return false

func _known_peers() -> Array[int]:
	var out: Array[int] = []
	var scene := get_tree().current_scene
	if scene == null:
		return out
	var mp := scene.get_node_or_null("MultiplayerManager")
	if mp and mp.has_method("get_connected_peers"):
		for pid in mp.get_connected_peers():
			out.append(pid)
		return out
	# Fallback: use the multiplayer layer directly.
	if multiplayer and multiplayer.multiplayer_peer:
		var self_id := multiplayer.get_unique_id()
		if self_id != 0:
			out.append(self_id)
		for pid in multiplayer.get_peers():
			if pid not in out:
				out.append(pid)
	return out

func notify_minion_removed(minion_id: int) -> void:
	for model in _models.values():
		model.forget_minion(minion_id)

func current_tick() -> int:
	return _tick

# --- Commands ---

func issue_move_command(peer_id: int, target_pos: Vector3) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mm := scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	if INSTANT_COMMANDS:
		mm.command_minions_move(target_pos)
		return
	# Courier dispatch path — placeholder for step 7.
	push_warning("[KnowledgeManager] Courier commands not yet implemented")
