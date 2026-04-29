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
## off once broadcast-range tuning is ready (build order step 5). Runtime-
## mutable so test harnesses can A/B the two modes without restarting.
static var INFINITE_BROADCAST_RANGE: bool = true

## When true, War Table clicks are executed immediately via MinionManager.
## When false, clicks record an intent and an Advisor dispatches a courier
## (build order step 7). Runtime-mutable; see above.
static var INSTANT_COMMANDS: bool = true

## Radius around a friendly minion (or its tower) within which activity leaks
## into the owner's WorldModel. Unused while INFINITE_BROADCAST_RANGE is true.
const BROADCAST_RANGE: float = 30.0

## How often sightings are flushed from truth into belief.
const UPDATE_INTERVAL: float = 0.1

var _models: Dictionary[int, WorldModel] = {}
var _update_timer: float = 0.0
var _tick: int = 0
## Monotonic id used as the key in WorldModel.pending_commands. Drafts and
## dispatched orders share the same id space — a draft promotes to dispatched
## in place when the Advisor takes the order, so the war table sees the entry
## flip stage rather than disappear-and-reappear.
var _next_command_id: int = 1

const STAGE_DRAFT: StringName = &"draft"
const STAGE_DISPATCHED: StringName = &"dispatched"

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
			# Your own couriers are rendered via pending_commands (intent-based,
			# midpoint-on-arrow), not as live pawns at their real position.
			# Skip them here so the war table doesn't double-render them. Rival
			# couriers DO leak in — to a rival you don't see intent, just a
			# minion you happen to spot.
			if m.minion_trait == &"courier" and m.owner_peer_id == pid:
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

func flush_observations(peer_id: int, log_entries: Array) -> void:
	## Path 2 of the WorldModel update flow (war-table.md). A retreating /
	## returning minion arrives home and dumps its accumulated _field_log into
	## the owner's WorldModel. Each entry is treated as an enemy sighting and
	## stamped with `source = &"return"` so the visualization can later style
	## report-derived sightings differently from live-broadcast ones.
	if log_entries == null or log_entries.is_empty():
		return
	var model := get_model(peer_id)
	for entry in log_entries:
		if not (entry is Dictionary):
			continue
		var observed_id: int = int(entry.get("id", -1))
		if observed_id < 0:
			continue
		var observed_owner: int = int(entry.get("owner_peer_id", -1))
		var is_friendly := observed_owner == peer_id
		model.update_minion_sighting(
			observed_id,
			entry.get("pos", Vector3.ZERO),
			observed_owner,
			int(entry.get("faction", GameConstants.Faction.NEUTRAL)),
			int(entry.get("observed_tick", _tick)),
			is_friendly,
			&"return",
		)

func notify_minion_removed(minion_id: int) -> void:
	for model in _models.values():
		model.forget_minion(minion_id)
	# Drop any pending command whose courier is this minion (delivered, killed,
	# or otherwise gone). The intent visual on the war table goes away with it.
	for model in _models.values():
		var dead_keys: Array[int] = []
		for cmd_id in model.pending_commands.keys():
			var entry: Dictionary = model.pending_commands[cmd_id]
			if int(entry.get("courier_id", -1)) == minion_id:
				dead_keys.append(cmd_id)
		for cmd_id in dead_keys:
			model.pending_commands.erase(cmd_id)

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
	# Courier path: the click only records intent as a *draft* in this peer's
	# WorldModel. The order doesn't reach the field until the overlord walks to
	# their Advisor and hands it off, at which point dispatch_drafts spawns a
	# courier per draft and promotes the entry to "dispatched".
	var spawn := mm.get_spawn_point_for(peer_id)
	if spawn == null:
		push_warning("[KnowledgeManager] No spawn point for peer %d; draft not recorded" % peer_id)
		return
	var cmd_id := _next_command_id
	_next_command_id += 1
	get_model(peer_id).pending_commands[cmd_id] = {
		"stage": STAGE_DRAFT,
		"start_pos": spawn.global_position,
		"target_pos": target_pos,
		"courier_id": -1,
		"issued_tick": _tick,
	}

func get_draft_count(peer_id: int) -> int:
	if not has_model(peer_id):
		return 0
	var n: int = 0
	for entry in get_model(peer_id).pending_commands.values():
		if entry.get("stage", STAGE_DISPATCHED) == STAGE_DRAFT:
			n += 1
	return n

func dispatch_info_courier(peer_id: int, target_pos: Vector3) -> void:
	## Host-only. Spawn an info-courier minion at the owner's tower spawn,
	## sent on a scout-and-return mission. The state machine
	## (info_courier_observe_state.gd → ChaseState → observe → RetreatState)
	## handles the lifecycle; on arrival home, accumulated _field_log entries
	## flush into the owner's WorldModel via flush_observations.
	##
	## Bypasses the draft / Advisor handoff loop deliberately — info missions
	## are reactive (you noticed something, you send eyes) and shouldn't queue
	## behind movement orders. War-table.md step 9's composition UI may later
	## introduce a unified draft surface that distinguishes order kinds.
	if not multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mm := scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	var spawn := mm.get_spawn_point_for(peer_id)
	if spawn == null:
		push_warning("[KnowledgeManager] No spawn point for peer %d; info-courier not dispatched" % peer_id)
		return
	mm.spawn_named_minion_for_peer(peer_id, &"info_courier", spawn.global_position, target_pos)

func dispatch_drafts(peer_id: int) -> void:
	## Host-only. Walk the owner's pending_commands, dispatch a courier for
	## every entry currently in the "draft" stage, and promote those entries to
	## "dispatched" (same command_id, courier_id filled in). The war table
	## renders by stage, so each red arrow flips to black in place.
	if not multiplayer.is_server():
		return
	if not has_model(peer_id):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mm := scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	var model := get_model(peer_id)
	var draft_ids: Array[int] = []
	for cmd_id in model.pending_commands.keys():
		var entry: Dictionary = model.pending_commands[cmd_id]
		if entry.get("stage", STAGE_DISPATCHED) == STAGE_DRAFT:
			draft_ids.append(cmd_id)
	for cmd_id in draft_ids:
		var entry: Dictionary = model.pending_commands[cmd_id]
		var start_pos: Vector3 = entry.get("start_pos", Vector3.ZERO)
		var target_pos: Vector3 = entry.get("target_pos", Vector3.ZERO)
		var courier_id: int = mm.spawn_named_minion_for_peer(peer_id, &"courier", start_pos, target_pos)
		if courier_id < 0:
			continue
		entry["stage"] = STAGE_DISPATCHED
		entry["courier_id"] = courier_id
		entry["dispatched_tick"] = _tick
		model.pending_commands[cmd_id] = entry
