class_name MinionManager extends Node

## Host-authoritative minion spawner, sync, and command manager.
## Overlords spend resources to summon minions, then command them via War Table.
## Minion roster comes from the MinionCatalog via FactionData; each minion is a
## MinionActor scene that self-applies its MinionType stats on spawn.

signal minion_spawned(minion: MinionActor)
signal minion_died(minion: MinionActor)

const MAX_MINIONS_PER_PLAYER: int = 5
const RESOURCE_GAIN_RATE: float = 2.0
const STARTING_RESOURCES: int = 20
const SYNC_INTERVAL: float = 0.1
## Undeath raise-dead has its own cost/limit
const RAISE_DEAD_COST: int = 3
const DOMINATE_COST: int = 10

var _next_minion_id: int = 1
var _minions_node: Node3D
var _sync_timer: float = 0.0

# peer_id -> float (resources for summoning)
var resources: Dictionary[int, float] = {}
# slot_index -> MinionSpawnPoint / MinionRallyPoint, populated by bind_tower_markers
var _spawn_points: Dictionary[int, MinionSpawnPoint] = {}
var _rally_points: Dictionary[int, MinionRallyPoint] = {}
# peer_id -> multiplier (<1.0 = discount). Granted by the Domination Mastery ritual.
var domination_discounts: Dictionary[int, float] = {}

func _ready() -> void:
	_minions_node = Node3D.new()
	_minions_node.name = "Minions"
	call_deferred("_setup_minions_node")

func _setup_minions_node() -> void:
	var world = get_tree().current_scene.get_node_or_null("World")
	if world:
		world.add_child(_minions_node)
	_adopt_preplaced_minions()
	bind_tower_markers()

func _adopt_preplaced_minions() -> void:
	## Moves any MinionActor authored into the scene (e.g. World/Enemies/Guard1)
	## into _minions_node with a numeric name so manager sync/lookup works.
	## All peers do this so the numeric IDs align for sync RPCs.
	var scene := get_tree().current_scene
	if scene == null:
		return
	var enemies_node = scene.get_node_or_null("World/Enemies")
	if enemies_node == null:
		return
	for child in enemies_node.get_children():
		if not (child is MinionActor):
			continue
		var minion: MinionActor = child
		var pos := minion.global_position
		var id := _next_minion_id
		_next_minion_id += 1
		minion.get_parent().remove_child(minion)
		minion.name = str(id)
		minion.owner_peer_id = -1
		minion.faction = GameConstants.Faction.NEUTRAL
		_minions_node.add_child(minion)
		minion.global_position = pos
		minion.waypoint = pos
		minion_spawned.emit(minion)

func _mp_manager() -> MultiplayerManager:
	return get_tree().current_scene.get_node_or_null("MultiplayerManager") as MultiplayerManager

func bind_tower_markers() -> void:
	## Pair each tower with a rally point by child order:
	##   Towers[0] ↔ Markers[0], Towers[1] ↔ Markers[1], …
	## Then bind each rally to the connected peer in the matching tower slot.
	_spawn_points.clear()
	_rally_points.clear()
	var scene := get_tree().current_scene
	if scene == null:
		return
	var towers_root := scene.get_node_or_null("World/Env/Towers")
	var markers_root := scene.get_node_or_null("World/Markers")
	if towers_root == null or markers_root == null:
		return
	var towers: Array[Tower] = []
	for child in towers_root.get_children():
		if child is Tower:
			towers.append(child)
	var rallies: Array[MinionRallyPoint] = []
	for child in markers_root.get_children():
		if child is MinionRallyPoint:
			rallies.append(child)
	for i in towers.size():
		var rally: MinionRallyPoint = rallies[i] if i < rallies.size() else null
		towers[i].assign_slot(i, rally)
		if towers[i].spawn_point:
			_spawn_points[i] = towers[i].spawn_point
		if rally:
			_rally_points[i] = rally
	# Peer binding is host-authoritative: host knows the slot table, clients
	# receive bindings via _bind_rally_rpc so their local rally marker flips
	# visible for the owning peer only.
	if not multiplayer.is_server():
		_request_rally_bindings.rpc_id(1)
		return
	var mm := _mp_manager()
	if mm == null:
		return
	var peers = multiplayer.get_peers().duplicate()
	if multiplayer.get_unique_id() not in peers:
		peers.append(multiplayer.get_unique_id())
	for pid in peers:
		var slot := mm.get_player_slot(pid)
		if slot < 0 or slot not in _rally_points:
			continue
		_bind_rally_rpc.rpc(slot, pid, _get_player_faction(pid))

@rpc("authority", "call_local", "reliable")
func _bind_rally_rpc(slot_index: int, peer_id: int, faction: int) -> void:
	var rally: MinionRallyPoint = _rally_points.get(slot_index)
	if rally:
		rally.bind(peer_id, faction)

@rpc("any_peer", "reliable")
func _request_rally_bindings() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	var mm := _mp_manager()
	if mm == null:
		return
	var peers = multiplayer.get_peers().duplicate()
	if multiplayer.get_unique_id() not in peers:
		peers.append(multiplayer.get_unique_id())
	for pid in peers:
		var slot := mm.get_player_slot(pid)
		if slot < 0:
			continue
		_bind_rally_rpc.rpc_id(requester, slot, pid, _get_player_faction(pid))

func get_spawn_point_for(peer_id: int) -> MinionSpawnPoint:
	var mm := _mp_manager()
	if mm == null:
		return null
	return _spawn_points.get(mm.get_player_slot(peer_id))

func get_rally_point_for(peer_id: int) -> MinionRallyPoint:
	var mm := _mp_manager()
	if mm == null:
		return null
	return _rally_points.get(mm.get_player_slot(peer_id))

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	var peers = multiplayer.get_peers().duplicate()
	if multiplayer.get_unique_id() not in peers:
		peers.append(multiplayer.get_unique_id())
	for pid in peers:
		if pid not in resources:
			resources[pid] = STARTING_RESOURCES
		resources[pid] += RESOURCE_GAIN_RATE * delta

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_sync_all_minions()

func get_all_minions() -> Array[MinionActor]:
	var result: Array[MinionActor] = []
	if _minions_node:
		for child in _minions_node.get_children():
			if child is MinionActor:
				result.append(child)
	return result

func get_minions_for_player(peer_id: int) -> Array[MinionActor]:
	var result: Array[MinionActor] = []
	for minion in get_all_minions():
		if minion.owner_peer_id == peer_id:
			result.append(minion)
	return result

func get_minion_count(peer_id: int) -> int:
	return get_minions_for_player(peer_id).size()

func get_resources(peer_id: int) -> float:
	return resources.get(peer_id, 0.0)

# --- Spawning ---

@rpc("any_peer", "call_local", "reliable")
func request_summon_minion(type_id: String = "", override_pos: Vector3 = Vector3.INF) -> void:
	## Any peer can request a minion. Host validates resources and limits.
	## If type_id is empty, spawns the faction's default minion.
	## If override_pos is Vector3.INF, the summon happens at the sender's
	## tower spawn marker and initial waypoint is the sender's rally point.
	if not multiplayer.is_server():
		request_summon_minion.rpc_id(1, type_id, override_pos)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if get_minion_count(sender) >= MAX_MINIONS_PER_PLAYER:
		return
	var faction: int = _get_player_faction(sender)
	var mtype: MinionType = _resolve_minion_type(faction, StringName(type_id))
	if mtype == null:
		return
	if get_resources(sender) < mtype.cost:
		return
	var spawn_pos := override_pos
	var initial_waypoint := spawn_pos
	if spawn_pos == Vector3.INF:
		var sp := get_spawn_point_for(sender)
		if sp == null:
			return
		spawn_pos = sp.global_position
		initial_waypoint = spawn_pos
	var rally := get_rally_point_for(sender)
	if rally:
		initial_waypoint = rally.global_position
	resources[sender] -= mtype.cost
	_sync_resources.rpc(sender, resources[sender])
	var id := _next_minion_id
	_next_minion_id += 1
	_spawn_minion_rpc.rpc(id, sender, faction, spawn_pos, String(mtype.id), initial_waypoint)

@rpc("authority", "call_local", "reliable")
func _spawn_minion_rpc(id: int, owner_id: int, faction: int, pos: Vector3, type_id: String, initial_waypoint: Vector3 = Vector3.INF) -> void:
	if not _minions_node:
		return
	var minion_scene := FactionData.get_minion_scene_for_id(StringName(type_id))
	if minion_scene == null:
		push_warning("[MinionManager] No scene in catalog for minion id '%s'" % type_id)
		return
	var minion := minion_scene.instantiate() as MinionActor
	minion.name = str(id)
	minion.owner_peer_id = owner_id
	minion.faction = faction
	_minions_node.add_child(minion)
	minion.global_position = pos
	minion.waypoint = initial_waypoint if initial_waypoint != Vector3.INF else pos
	minion_spawned.emit(minion)

func _resolve_minion_type(faction: int, type_id: StringName) -> MinionType:
	if type_id == &"":
		return FactionData.get_default_minion(faction)
	var mtype := FactionData.get_catalog().minion_type_for_id(type_id)
	if mtype != null:
		return mtype
	return FactionData.get_default_minion(faction)

# --- Neutral spawns (world enemies like zombies, guardian boss) ---

func spawn_neutral_minion(pos: Vector3, type_id: StringName = &"neutral_zombie", waypoint: Vector3 = Vector3.INF) -> void:
	## Host-only. Spawns a neutral NPC (owner_peer_id = -1, faction = NEUTRAL).
	## Bypasses resource cost and per-player minion caps.
	if not multiplayer.is_server():
		return
	var id := _next_minion_id
	_next_minion_id += 1
	var wp := waypoint if waypoint != Vector3.INF else pos
	_spawn_minion_rpc.rpc(id, -1, GameConstants.Faction.NEUTRAL, pos, String(type_id), wp)

# --- Raise Dead (Undeath trait) ---

func raise_dead_at(owner_peer_id: int, faction: int, pos: Vector3) -> void:
	## Host-only: spawn a free skeleton at a corpse location.
	if not multiplayer.is_server():
		return
	if get_minion_count(owner_peer_id) >= MAX_MINIONS_PER_PLAYER:
		return
	if get_resources(owner_peer_id) < RAISE_DEAD_COST:
		return
	resources[owner_peer_id] -= RAISE_DEAD_COST
	_sync_resources.rpc(owner_peer_id, resources[owner_peer_id])
	var id := _next_minion_id
	_next_minion_id += 1
	# Always raises a skeleton regardless of faction (it's undead now)
	_spawn_minion_rpc.rpc(id, owner_peer_id, faction, pos, "skeleton")
	print("[MinionManager] Raise dead: spawned skeleton for peer %d" % owner_peer_id)

# --- Rally point ---

@rpc("any_peer", "call_local", "reliable")
func request_move_rally(new_pos: Vector3) -> void:
	## Only the rally's owning overlord may move it. Rally position is
	## broadcast to all peers (so host/minion logic stays consistent) but
	## the node itself is only visible to the owner (see MinionRallyPoint).
	if not multiplayer.is_server():
		request_move_rally.rpc_id(1, new_pos)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var rally := get_rally_point_for(sender)
	if rally == null:
		return
	if rally.owning_peer_id != sender:
		return
	_apply_rally_move.rpc(rally.slot_index, new_pos)

@rpc("authority", "call_local", "reliable")
func _apply_rally_move(slot_index: int, new_pos: Vector3) -> void:
	var rally: MinionRallyPoint = _rally_points.get(slot_index)
	if rally:
		rally.move_to(new_pos)

# --- Commands ---

@rpc("any_peer", "call_local", "reliable")
func command_minions_move(target_pos: Vector3) -> void:
	if not multiplayer.is_server():
		command_minions_move.rpc_id(1, target_pos)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	for minion in get_minions_for_player(sender):
		minion.waypoint = target_pos
	# War Table clicks also relocate the sender's rally so future summons
	# muster at the latest command point.
	var rally := get_rally_point_for(sender)
	if rally and rally.owning_peer_id == sender:
		_apply_rally_move.rpc(rally.slot_index, target_pos)

@rpc("any_peer", "call_local", "reliable")
func command_minion_move(minion_id: int, target_pos: Vector3) -> void:
	if not multiplayer.is_server():
		command_minion_move.rpc_id(1, minion_id, target_pos)
		return
	if not _minions_node:
		return
	var minion := _minions_node.get_node_or_null(str(minion_id)) as MinionActor
	if minion == null:
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if minion.owner_peer_id == sender:
		minion.waypoint = target_pos

# --- Domination (Eldritch) ---

@rpc("any_peer", "call_local", "reliable")
func request_dominate_minion(minion_id: int, new_owner_id: int) -> void:
	if not multiplayer.is_server():
		request_dominate_minion.rpc_id(1, minion_id, new_owner_id)
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var faction: int = _get_player_faction(sender)
	if faction != GameConstants.Faction.ELDRITCH:
		return
	if not _minions_node:
		return
	var minion := _minions_node.get_node_or_null(str(minion_id)) as MinionActor
	if minion == null:
		return
	if minion.owner_peer_id == sender:
		return
	if not minion.can_take_damage():
		return
	var cost := DOMINATE_COST
	if sender in domination_discounts:
		cost = int(DOMINATE_COST * domination_discounts[sender])
	if get_resources(sender) < cost:
		return
	if get_minion_count(sender) >= MAX_MINIONS_PER_PLAYER:
		return
	resources[sender] -= cost
	_sync_resources.rpc(sender, resources[sender])
	_dominate_minion.rpc(minion_id, sender, faction)

@rpc("authority", "call_local", "reliable")
func _dominate_minion(minion_id: int, new_owner: int, new_faction: int) -> void:
	if not _minions_node:
		return
	var minion := _minions_node.get_node_or_null(str(minion_id)) as MinionActor
	if minion == null:
		return
	minion.owner_peer_id = new_owner
	minion.faction = new_faction
	print("[MinionManager] Minion %d dominated by peer %d" % [minion_id, new_owner])

# --- Sync ---

func _sync_all_minions() -> void:
	for minion in get_all_minions():
		_sync_minion_actor.rpc(
			minion.name.to_int(),
			minion.global_position,
			minion.rotation.y,
			minion._state_machine.state,
			minion.hp
		)

@rpc("authority", "call_remote", "unreliable")
func _sync_minion_actor(id: int, pos: Vector3, rot_y: float, new_state: StringName, new_hp: int) -> void:
	if not _minions_node:
		return
	var minion := _minions_node.get_node_or_null(str(id)) as MinionActor
	if minion:
		minion.sync_from_server(pos, rot_y, new_state, new_hp)

@rpc("authority", "call_local", "reliable")
func _sync_resources(peer_id: int, amount: float) -> void:
	resources[peer_id] = amount

func notify_minion_died(minion: MinionActor) -> void:
	if not multiplayer.is_server():
		return
	minion_died.emit(minion)
	var id := minion.name.to_int()
	KnowledgeManager.notify_minion_removed(id)
	_remove_minion.rpc(id)

@rpc("authority", "call_local", "reliable")
func _remove_minion(id: int) -> void:
	if _minions_node:
		var minion := _minions_node.get_node_or_null(str(id))
		if minion:
			minion.queue_free()

func _get_player_faction(peer_id: int) -> int:
	return GameState.get_faction(peer_id)

func set_domination_discount(peer_id: int, multiplier: float) -> void:
	## Granted by the Domination Mastery ritual. Persists for the match.
	domination_discounts[peer_id] = multiplier
