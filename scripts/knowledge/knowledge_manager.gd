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
## (build order step 7). Runtime-mutable; see above. Default-off now that the
## courier path is the canonical "real game" flow — the test harness flips it
## back on for direct-command iteration.
static var INSTANT_COMMANDS: bool = false

## Radius around a friendly minion (or its tower) within which activity leaks
## into the owner's WorldModel. Unused while INFINITE_BROADCAST_RANGE is true.
const BROADCAST_RANGE: float = 30.0

## How often sightings are flushed from truth into belief.
const UPDATE_INTERVAL: float = 0.1

var _models: Dictionary[int, WorldModel] = {}
var _update_timer: float = 0.0
var _tick: int = 0
## Monotonic id used as the key in WorldModel.pending_commands. Every stage in
## the lifecycle (draft → readied → dispatched) shares the same id space — a
## draft promotes in place rather than disappear-and-reappear, so the war
## table just sees the entry's `stage` field flip and the arrow recolor.
var _next_command_id: int = 1

## Lifecycle of a movement command:
##   draft     — recorded by the war-table MapTarget after a piece selection;
##               red arrow on the diorama; cancelable via the ResetMarker.
##   readied   — overlord interacted with the table's Paper; the orders are
##               now committed (no further table edits) but no courier has
##               been dispatched. Amber arrow.
##   dispatched— overlord handed the paper to the Advisor; couriers are in the
##               world. Black arrow + blue route.
const STAGE_DRAFT: StringName = &"draft"
const STAGE_READIED: StringName = &"readied"
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

func notify_delivery_failures(peer_id: int, failures: Array) -> void:
	## Called by a returning courier when one or more of its legs couldn't
	## find the targeted minions in visual range. Each failure entry is
	## {minion_ids, target_pos, leg_source} produced by courier_arrival_state.
	## Stamped with the current tick and appended to the peer's WorldModel
	## inbox; HUD code can surface the most recent N entries to the overlord.
	if failures.is_empty():
		return
	if not has_model(peer_id):
		return
	var model := get_model(peer_id)
	for f in failures:
		var minion_ids: Array = (f.get("minion_ids", []) as Array).duplicate()
		if minion_ids.is_empty():
			continue
		model.failure_messages.append({
			"tick": _tick,
			"leg_source": f.get("leg_source", Vector3.ZERO) as Vector3,
			"minion_ids": minion_ids,
			"target_pos": f.get("target_pos", Vector3.INF) as Vector3,
		})
	# TODO: replace this print with a HUD toast / inbox widget once the
	# overlord-side UI for advisor messages exists.
	print("[KnowledgeManager] Peer %d courier failed to deliver %d order%s" % [
		peer_id, failures.size(), "" if failures.size() == 1 else "s"
	])

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

func issue_move_command(peer_id: int, minion_ids: Array[int], target_pos: Vector3) -> void:
	## minion_ids identifies which of the overlord's minions the order is for.
	## The courier travels to the believed location of those minions (looked up
	## from the peer's WorldModel) and only delivers to that specific set.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mm := scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	if INSTANT_COMMANDS:
		# Bypass the courier loop: command exactly the selected minions, with
		# formation-slot distribution so N minions to one point get N distinct
		# waypoints instead of piling up.
		mm.command_selection_move(minion_ids, target_pos)
		return
	if minion_ids.is_empty():
		return
	# Couriers spawn AND return at the tower's CourierSpawn marker. The regular
	# MinionSpawnPoint sits high on the tower (where summoned minions descend
	# from) and is not reachable by NavigationAgent3D from the world below —
	# couriers ordered to return there would walk forever. get_courier_spawn_for
	# falls back to the regular spawn for scenes that haven't authored a
	# CourierSpawn yet.
	var spawn := mm.get_courier_spawn_for(peer_id)
	if spawn == null:
		push_warning("[KnowledgeManager] No courier spawn for peer %d; draft not recorded" % peer_id)
		return
	# Per-piece source positions: each known minion contributes one leg with
	# its own believed pos. Phase 1 = one leg per minion (no clustering yet);
	# phase 4 (multi-stop courier) groups colocated minions into shared legs.
	# Drop the order entirely if we have no belief about any of the selected
	# ids — better than dispatching a blind courier.
	var legs := _build_legs(peer_id, minion_ids)
	if legs.is_empty():
		return
	# `source_pos` (centroid) is kept for the courier path until phase 4 swaps
	# couriers to the legs schema. Renderers should read `legs` directly.
	var source_pos := _believed_centroid(peer_id, minion_ids)
	var cmd_id := _next_command_id
	_next_command_id += 1
	get_model(peer_id).pending_commands[cmd_id] = {
		"stage": STAGE_DRAFT,
		"spawn_pos": spawn.global_position,
		"source_pos": source_pos,
		"target_pos": target_pos,
		"minion_ids": minion_ids.duplicate(),
		"legs": legs,
		"courier_id": -1,
		"issued_tick": _tick,
	}

func _build_legs(peer_id: int, minion_ids: Array[int]) -> Array[Dictionary]:
	## Snapshot each selected minion's believed position into its own leg. The
	## source_pos is frozen at draft time so the rendered arrow shows the order
	## as it was given, even if the minion subsequently moves before the
	## courier delivers. Skips ids we have no belief about (their arrows would
	## have nothing meaningful to point from).
	var out: Array[Dictionary] = []
	if not has_model(peer_id):
		return out
	var model := get_model(peer_id)
	for mid in minion_ids:
		var entry: Dictionary = model.believed_friendly_minions.get(mid, {})
		if entry.is_empty():
			continue
		out.append({
			"source_pos": entry.get("pos", Vector3.ZERO) as Vector3,
			"minion_ids": [mid] as Array,
		})
	return out

func _believed_centroid(peer_id: int, minion_ids: Array[int]) -> Vector3:
	if not has_model(peer_id):
		return Vector3.INF
	var model := get_model(peer_id)
	var sum := Vector3.ZERO
	var n := 0
	for mid in minion_ids:
		var entry: Dictionary = model.believed_friendly_minions.get(mid, {})
		if entry.is_empty():
			continue
		sum += entry.get("pos", Vector3.ZERO) as Vector3
		n += 1
	if n == 0:
		return Vector3.INF
	return sum / n

func get_draft_count(peer_id: int) -> int:
	if not has_model(peer_id):
		return 0
	var n: int = 0
	for entry in get_model(peer_id).pending_commands.values():
		if entry.get("stage", STAGE_DISPATCHED) == STAGE_DRAFT:
			n += 1
	return n

func get_readied_count(peer_id: int) -> int:
	if not has_model(peer_id):
		return 0
	var n: int = 0
	for entry in get_model(peer_id).pending_commands.values():
		if entry.get("stage", STAGE_DISPATCHED) == STAGE_READIED:
			n += 1
	return n

func ready_drafts(peer_id: int) -> int:
	## Promote every draft entry to readied. Triggered by the war-table Paper
	## interactable: the orders leave the table and are now committed (no further
	## edits via Reset). The Advisor will pick them up and dispatch couriers.
	## Returns the number of entries promoted.
	if not has_model(peer_id):
		return 0
	var model := get_model(peer_id)
	var n: int = 0
	for cmd_id in model.pending_commands.keys():
		var entry: Dictionary = model.pending_commands[cmd_id]
		if entry.get("stage", STAGE_DISPATCHED) == STAGE_DRAFT:
			entry["stage"] = STAGE_READIED
			entry["readied_tick"] = _tick
			model.pending_commands[cmd_id] = entry
			n += 1
	return n

func is_minion_pending(peer_id: int, minion_id: int) -> bool:
	## True if `minion_id` is locked into any draft or dispatched command for
	## this peer. The war table uses this to grey out / un-clickable pieces
	## that already have orders, so a second click can't double-book them. The
	## lock lifts when the command is cancelled (clear_drafts / cancel_last_draft)
	## or when the courier delivers and the entry is dropped via
	## notify_minion_removed.
	if not has_model(peer_id):
		return false
	var model := get_model(peer_id)
	for entry in model.pending_commands.values():
		# Prefer the legs schema when present so the test follows the canonical
		# per-piece order grouping. Fallback to the flat minion_ids field for
		# legacy entries that predated phase 1.
		var legs: Array = entry.get("legs", [])
		if not legs.is_empty():
			for leg in legs:
				var ids: Array = leg.get("minion_ids", [])
				if minion_id in ids:
					return true
			continue
		var flat_ids: Array = entry.get("minion_ids", [])
		if minion_id in flat_ids:
			return true
	return false

func cancel_last_draft(peer_id: int) -> bool:
	## Pop the most recently issued draft. Used by the war table's "undo last
	## command" key so the overlord can back out without exiting the table.
	## Returns true if a draft was removed.
	if not has_model(peer_id):
		return false
	var model := get_model(peer_id)
	var latest_id: int = -1
	var latest_tick: int = -1
	for cmd_id in model.pending_commands.keys():
		var entry: Dictionary = model.pending_commands[cmd_id]
		if entry.get("stage", STAGE_DISPATCHED) != STAGE_DRAFT:
			continue
		var t: int = int(entry.get("issued_tick", 0))
		# Tie-break on cmd_id so two drafts issued the same tick still pop in
		# LIFO order (later id == later issue).
		if t > latest_tick or (t == latest_tick and cmd_id > latest_id):
			latest_tick = t
			latest_id = cmd_id
	if latest_id < 0:
		return false
	model.pending_commands.erase(latest_id)
	return true

func clear_drafts(peer_id: int) -> int:
	## Discard every draft entry. Dispatched commands (couriers already running)
	## are untouched — those are committed and only end when their courier
	## delivers or dies. Returns the number of drafts removed.
	if not has_model(peer_id):
		return 0
	var model := get_model(peer_id)
	var to_remove: Array[int] = []
	for cmd_id in model.pending_commands.keys():
		var entry: Dictionary = model.pending_commands[cmd_id]
		if entry.get("stage", STAGE_DISPATCHED) == STAGE_DRAFT:
			to_remove.append(cmd_id)
	for cmd_id in to_remove:
		model.pending_commands.erase(cmd_id)
	return to_remove.size()

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
	# Info-couriers retreat via RetreatState, which looks up the regular
	# MinionSpawnPoint — so spawning them from CourierSpawn would mismatch the
	# return target. Keep the regular spawn for now; if/when info-couriers also
	# need the courier-specific marker, RetreatState has to learn about it too.
	var spawn := mm.get_spawn_point_for(peer_id)
	if spawn == null:
		push_warning("[KnowledgeManager] No spawn point for peer %d; info-courier not dispatched" % peer_id)
		return
	mm.spawn_named_minion_for_peer(peer_id, &"info_courier", spawn.global_position, target_pos)

func dispatch_readied(peer_id: int) -> void:
	## Host-only. Walk the owner's pending_commands, batch every readied entry's
	## sub-orders into the fewest couriers (subject to MinionType.max_orders
	## capacity per courier), spawn those couriers, and promote each batched
	## entry to "dispatched" with the courier_id of its assigned courier.
	##
	## Trigger: overlord interacts with the Advisor after readying drafts at
	## the war-table Paper.
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
	# Collect every sub-order from every readied entry. A "sub-order" is one
	# (source_pos, minion_ids, target_pos, source_cmd_id) tuple — typically
	# one per piece-on-the-board the order covers.
	var sub_orders: Array[Dictionary] = []
	var readied_cmd_ids: Array[int] = []
	for cmd_id in model.pending_commands.keys():
		var entry: Dictionary = model.pending_commands[cmd_id]
		if entry.get("stage", STAGE_DISPATCHED) != STAGE_READIED:
			continue
		readied_cmd_ids.append(cmd_id)
		var entry_target: Vector3 = entry.get("target_pos", Vector3.ZERO)
		var entry_legs: Array = entry.get("legs", [])
		for leg in entry_legs:
			var ids: Array = leg.get("minion_ids", [])
			if ids.is_empty():
				continue
			sub_orders.append({
				"source_pos": leg.get("source_pos", Vector3.ZERO),
				"minion_ids": ids.duplicate(),
				"target_pos": entry_target,
				"cmd_id": cmd_id,
			})
	if sub_orders.is_empty():
		return
	# Capacity per courier — read off the courier MinionType.tres so different
	# courier variants can carry different loads. Falls back to 1 (legacy
	# one-courier-per-entry) if the catalog isn't populated yet.
	var courier_type: MinionType = FactionData.get_catalog().minion_type_for_id(&"courier")
	var max_orders: int = 1
	if courier_type and courier_type.max_orders > 0:
		max_orders = courier_type.max_orders
	# Spawn position is shared across all couriers for this peer.
	var spawn_world: Vector3 = Vector3.ZERO
	var spawn_node := mm.get_courier_spawn_for(peer_id)
	if spawn_node:
		spawn_world = spawn_node.global_position
	var return_zone: Area3D = mm.get_courier_spawn_for(peer_id) as Area3D
	# Greedy first-fit: chunk sub_orders into batches of at most max_orders.
	# A more sophisticated assignment could co-locate same-source sub_orders
	# in the same courier, but the cluster step below already groups them by
	# source so a sequential chunking yields good results in practice.
	var cmd_to_courier: Dictionary[int, int] = {}
	var i: int = 0
	while i < sub_orders.size():
		var batch: Array[Dictionary] = []
		var end: int = mini(i + max_orders, sub_orders.size())
		for j in range(i, end):
			batch.append(sub_orders[j])
		i = end
		# Group this courier's sub_orders into legs (one leg per source cluster).
		var legs: Array[Dictionary] = _build_legs_from_sub_orders(batch)
		var ordered_legs: Array[Dictionary] = _order_legs_greedy(spawn_world, legs)
		if ordered_legs.is_empty():
			continue
		var first_source: Vector3 = ordered_legs[0].get("source_pos", spawn_world)
		var courier_id: int = mm.spawn_named_minion_for_peer(peer_id, &"courier", spawn_world, first_source)
		if courier_id < 0:
			continue
		var courier := mm.get_minion_by_id(courier_id)
		if courier:
			courier.delivery_legs = ordered_legs
			courier.return_pos = spawn_world
			courier.return_zone = return_zone
		# Build the route polyline once and share it across every entry that
		# sourced a sub_order on this courier; the renderer dedups by
		# courier_id so duplicate writes are visually harmless.
		var route: PackedVector3Array = PackedVector3Array()
		route.append(spawn_world)
		for leg in ordered_legs:
			route.append(leg.get("source_pos", spawn_world))
		# Map each contributing cmd_id to this courier.
		var contributing: Dictionary[int, bool] = {}
		for sub in batch:
			contributing[int(sub["cmd_id"])] = true
		for cmd_id in contributing:
			cmd_to_courier[cmd_id] = courier_id
			var entry: Dictionary = model.pending_commands.get(cmd_id, {})
			if entry.is_empty():
				continue
			entry["stage"] = STAGE_DISPATCHED
			entry["courier_id"] = courier_id
			entry["dispatched_tick"] = _tick
			entry["route_waypoints"] = route
			model.pending_commands[cmd_id] = entry

func _build_legs_from_sub_orders(batch: Array[Dictionary]) -> Array[Dictionary]:
	## Group a courier's batch of sub-orders into legs by source-pos proximity.
	## Each leg is "stop at this source cluster, deliver these sub_orders."
	var legs: Array[Dictionary] = []
	var d2: float = _CLUSTER_DISTANCE * _CLUSTER_DISTANCE
	for sub in batch:
		var src: Vector3 = sub.get("source_pos", Vector3.ZERO)
		var sub_order: Dictionary = {
			"minion_ids": (sub.get("minion_ids", []) as Array).duplicate(),
			"target_pos": sub.get("target_pos", Vector3.INF),
		}
		var merged: bool = false
		for leg in legs:
			var leg_src: Vector3 = leg["source_pos"]
			if leg_src.distance_squared_to(src) <= d2:
				var existing: Array = leg["sub_orders"]
				existing.append(sub_order)
				leg["sub_orders"] = existing
				# Update centroid as a running mean weighted by sub_order count.
				var n_existing: int = existing.size()
				leg["source_pos"] = leg_src.lerp(src, 1.0 / float(n_existing))
				merged = true
				break
		if not merged:
			legs.append({
				"source_pos": src,
				"sub_orders": [sub_order],
			})
	return legs

const _CLUSTER_DISTANCE: float = 3.0  # world meters

func _cluster_legs(legs: Array) -> Array[Dictionary]:
	## Greedy proximity clustering: minions whose snapshot source positions are
	## within _CLUSTER_DISTANCE meters merge into a shared leg. Phase 4's
	## courier visits one source per cluster instead of one per minion.
	var clusters: Array[Dictionary] = []
	var d2: float = _CLUSTER_DISTANCE * _CLUSTER_DISTANCE
	for leg in legs:
		var src: Vector3 = leg.get("source_pos", Vector3.ZERO)
		var ids: Array = leg.get("minion_ids", [])
		if ids.is_empty():
			continue
		var merged := false
		for c in clusters:
			var cs: Vector3 = c["source_pos"]
			if cs.distance_squared_to(src) <= d2:
				var existing: Array = c["minion_ids"]
				var n_existing: int = existing.size()
				var n_new: int = ids.size()
				var w_new: float = float(n_new) / float(n_existing + n_new)
				c["source_pos"] = cs.lerp(src, w_new)
				existing.append_array(ids)
				c["minion_ids"] = existing
				merged = true
				break
		if not merged:
			clusters.append({
				"source_pos": src,
				"minion_ids": ids.duplicate(),
			})
	return clusters

func _order_legs_greedy(start: Vector3, legs: Array[Dictionary]) -> Array[Dictionary]:
	## Greedy nearest-neighbor TSP. Starting from `start`, repeatedly pick the
	## unvisited leg whose source_pos is closest to the current cursor. N is
	## small (capped by selection size, typically ≤ 5 after clustering) so the
	## greedy approximation is good enough.
	var remaining: Array[Dictionary] = legs.duplicate()
	var ordered: Array[Dictionary] = []
	var cursor: Vector3 = start
	while not remaining.is_empty():
		var best_i: int = 0
		var best_d2: float = INF
		for i in remaining.size():
			var d2 := cursor.distance_squared_to(remaining[i].get("source_pos", cursor))
			if d2 < best_d2:
				best_d2 = d2
				best_i = i
		var pick: Dictionary = remaining[best_i]
		ordered.append(pick)
		remaining.remove_at(best_i)
		cursor = pick.get("source_pos", cursor)
	return ordered
