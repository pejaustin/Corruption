class_name MinionManager extends Node

## Host-authoritative unit spawner, sync, and command manager.
## Unit roster comes from the MinionCatalog via FactionData; each unit is a
## MinionActor scene that self-applies its MinionType stats on spawn.
##
## GDD v2: there is no summoning currency. Undead troops are raised from human
## remains brought to the tower (or to a site with the right capability), one
## body per unit (GDD §5); see raise_from_remains().

signal minion_spawned(minion: MinionActor)
signal minion_died(minion: MinionActor)
signal remains_changed(peer_id: int, count: int)

const SYNC_INTERVAL: float = 0.1
## Distance between adjacent slots in the move-command formation. Big enough
## that NavigationAgent3D RVO (radius 0.5) doesn't see neighbors as blockers
## once minions are settled.
const FORMATION_SPACING: float = 1.6
## Phalanx width — minions fill one rank left-to-right, then start a new
## rank behind. Front rank sits at the click point; trailing ranks fall
## back toward the squad's centroid.
const FORMATION_WIDTH: int = 4
## Units raised or spawned this close to their tower muster at its gate.
const MUSTER_RADIUS: float = 60.0

var _next_minion_id: int = 1
var _minions_node: Node3D
var _sync_timer: float = 0.0

## peer_id -> human remains waiting at that player's tower to be raised.
var remains: Dictionary[int, int] = {}
# slot_index -> MinionSpawnPoint / MinionRallyPoint, populated by bind_tower_markers
var _spawn_points: Dictionary[int, MinionSpawnPoint] = {}
var _rally_points: Dictionary[int, MinionRallyPoint] = {}
## slot_index -> CourierSpawn marker (plain Node3D, not a typed class — see
## Tower.courier_spawn). Couriers spawn and return here instead of at
## _spawn_points, which is authored high on the tower and unreachable by
## NavigationAgent3D from the world below.
var _courier_spawns: Dictionary[int, Node3D] = {}
## Per-peer override map. When a test harness or other minimal scene doesn't
## have the full Tower / MultiplayerManager / slot infrastructure, callers can
## bind a peer directly to a MinionSpawnPoint via bind_peer_spawn_point().
## Checked first by get_spawn_point_for; falls through to the slot-based map.
var _peer_spawn_overrides: Dictionary[int, MinionSpawnPoint] = {}
## Same shape, but for the courier spawn point.
var _peer_courier_spawn_overrides: Dictionary[int, Node3D] = {}
## peer_id → tower slot, learned from _bind_rally_rpc on EVERY peer.
## MultiplayerManager._player_slot_order only exists on the host, so clients
## must resolve slots from this map — see _slot_for_peer.
var _peer_slots: Dictionary[int, int] = {}
## Host-only: players who have already been given their starting forces.
var _started_peers: Dictionary[int, bool] = {}

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
	# Tower Advisors are pre-placed in tower.tscn rather than spawned, so they
	# need the same adoption to join the manager's sync set — otherwise the
	# host's advisor AI follows its overlord while every client watches its own
	# frozen local copy (_sync_all_minions only covers _minions_node children).
	# Towers cached their `advisor` reference in _ready, and node references
	# survive the reparent, so bind_advisor keeps working afterwards. Adoption
	# order (enemies first, then advisors in tower tree order) is identical on
	# every peer so the numeric IDs align for the sync RPCs. owner_peer_id and
	# faction are NOT clobbered here — _bind_rally_rpc sets them later.
	for n in get_tree().get_nodes_in_group(Tower.GROUP):
		var t := n as Tower
		if t == null or t.advisor == null:
			continue
		var advisor: MinionActor = t.advisor
		var advisor_pos := advisor.global_position
		var advisor_id := _next_minion_id
		_next_minion_id += 1
		advisor.get_parent().remove_child(advisor)
		advisor.name = str(advisor_id)
		_minions_node.add_child(advisor)
		advisor.global_position = advisor_pos
		advisor.waypoint = advisor_pos
		minion_spawned.emit(advisor)

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
		if towers[i].courier_spawn:
			_courier_spawns[i] = towers[i].courier_spawn
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
		_give_starting_forces.call_deferred(pid)

func _give_starting_forces(peer_id: int) -> void:
	## Host-only, once per player: one small group of troops at the tower's
	## muster point (GDD Q38). Couriers start in the tower's pool (CourierPool).
	if not multiplayer.is_server() or _started_peers.get(peer_id, false):
		return
	var spawn := get_courier_spawn_for(peer_id)
	if spawn == null:
		return
	_started_peers[peer_id] = true
	KnowledgeManager.give_starting_couriers(peer_id)
	for i in MatchConfig.STARTING_GROUP_SIZE:
		var offset := Vector3(float(i % 2) * FORMATION_SPACING, 0.5, float(i / 2) * FORMATION_SPACING)
		spawn_unit_for_peer(peer_id, &"", spawn.global_position + offset)

@rpc("authority", "call_local", "reliable")
func _bind_rally_rpc(slot_index: int, peer_id: int, faction: int) -> void:
	# Record the peer→slot pairing locally — this is the only slot source
	# clients have (MultiplayerManager's table is host-only).
	_peer_slots[peer_id] = slot_index
	GameState.set_player_slot(peer_id, slot_index)
	var rally: MinionRallyPoint = _rally_points.get(slot_index)
	if rally:
		rally.bind(peer_id, faction)
	# Each tower has a pre-placed Advisor; bind it to the same peer so it
	# follows the right overlord and accepts only that overlord's handoffs.
	for n in get_tree().get_nodes_in_group(Tower.GROUP):
		var t := n as Tower
		if t and t.slot_index == slot_index:
			t.bind_advisor(peer_id, faction)
			break

@rpc("any_peer", "reliable")
func _request_rally_bindings() -> void:
	if not multiplayer.is_server():
		return
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
		# Broadcast (not rpc_id to the requester): the host's own initial bind
		# loop can race slot assignment and miss peers, leaving host-side
		# tower/advisor owner bindings unset (advisor never follows, handoffs
		# rejected). Re-broadcasting to everyone is idempotent — same values
		# re-applied — and heals the host plus any client that missed a peer.
		_bind_rally_rpc.rpc(slot, pid, _get_player_faction(pid))

func _slot_for_peer(peer_id: int) -> int:
	## Slot lookup that works on every peer. _peer_slots is populated by
	## _bind_rally_rpc (host broadcast), so clients can resolve slots without
	## MultiplayerManager._player_slot_order — that table is host-only. Falls
	## back to the MultiplayerManager table for host-side callers that run
	## before bindings have been broadcast.
	if peer_id in _peer_slots:
		return _peer_slots[peer_id]
	var mm := _mp_manager()
	if mm == null:
		return -1
	return mm.get_player_slot(peer_id)

func get_spawn_point_for(peer_id: int) -> MinionSpawnPoint:
	if peer_id in _peer_spawn_overrides:
		return _peer_spawn_overrides[peer_id]
	return _spawn_points.get(_slot_for_peer(peer_id))

func bind_peer_spawn_point(peer_id: int, spawn: MinionSpawnPoint) -> void:
	## Direct peer→spawn binding for environments without a MultiplayerManager
	## (e.g. test harnesses). Production code uses bind_tower_markers via the
	## tower/MP slot table; this is the harness shortcut.
	if spawn == null:
		_peer_spawn_overrides.erase(peer_id)
		return
	_peer_spawn_overrides[peer_id] = spawn

func get_courier_spawn_for(peer_id: int) -> Node3D:
	## The point couriers spawn at and return to. Override map first (test
	## harnesses), then the tower slot's CourierSpawn child, then a fallback to
	## the regular spawn point so legacy scenes that haven't authored a
	## CourierSpawn yet keep dispatching couriers (just to the unreachable old
	## location, which is the bug we're fixing — but not regressing in scope).
	if peer_id in _peer_courier_spawn_overrides:
		return _peer_courier_spawn_overrides[peer_id]
	var slot := _slot_for_peer(peer_id)
	if slot in _courier_spawns:
		return _courier_spawns[slot]
	return get_spawn_point_for(peer_id)

func bind_peer_courier_spawn(peer_id: int, spawn: Node3D) -> void:
	## Test-harness equivalent of bind_peer_spawn_point for the courier-only
	## spawn marker. Pass null to clear.
	if spawn == null:
		_peer_courier_spawn_overrides.erase(peer_id)
		return
	_peer_courier_spawn_overrides[peer_id] = spawn

func get_rally_point_for(peer_id: int) -> MinionRallyPoint:
	return _rally_points.get(_slot_for_peer(peer_id))

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

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

func get_minion_by_id(minion_id: int) -> MinionActor:
	if not _minions_node:
		return null
	return _minions_node.get_node_or_null(str(minion_id)) as MinionActor

func get_minion_count(peer_id: int) -> int:
	return get_minions_for_player(peer_id).size()

func get_remains(peer_id: int) -> int:
	return remains.get(peer_id, 0)

func add_remains(peer_id: int, count: int) -> void:
	## Host-only: a body arrived at this player's tower.
	if not multiplayer.is_server():
		return
	_sync_remains.rpc(peer_id, get_remains(peer_id) + count)

@rpc("authority", "call_local", "reliable")
func _sync_remains(peer_id: int, count: int) -> void:
	remains[peer_id] = count
	remains_changed.emit(peer_id, count)

# --- Spawning ---

@rpc("any_peer", "call_local", "reliable")
func request_raise_from_remains(type_id: String = "") -> void:
	## The summoning circle (GDD §2, §5): one body at the sender's tower is
	## raised into one undead unit, which musters at the rally point.
	if not multiplayer.is_server():
		request_raise_from_remains.rpc_id(1, type_id)
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if get_remains(sender) <= 0:
		return
	var sp := get_spawn_point_for(sender)
	if sp == null:
		return
	if spawn_unit_for_peer(sender, StringName(type_id), sp.global_position) < 0:
		return
	_sync_remains.rpc(sender, get_remains(sender) - 1)

func spawn_unit_for_peer(peer_id: int, type_id: StringName, pos: Vector3) -> int:
	## Host-only. Spawns one of this player's units at `pos`. Near the tower it
	## musters at the tower gate with the group waiting there; elsewhere it
	## forms its own group where it stands. Empty type_id = the faction's
	## default unit. Returns the new unit's id, or -1.
	if not multiplayer.is_server():
		return -1
	var faction: int = _get_player_faction(peer_id)
	var mtype: MinionType = _resolve_minion_type(faction, type_id)
	if mtype == null:
		return -1
	var id := _next_minion_id
	_next_minion_id += 1
	_spawn_minion_rpc.rpc(id, peer_id, faction, pos, String(mtype.id), pos)
	var unit := get_minion_by_id(id)
	var gm := get_tree().current_scene.get_node_or_null("GroupManager") as GroupManager
	if unit == null or gm == null:
		return id
	var group := gm.join_home_group(peer_id, unit)
	var gate := get_courier_spawn_for(peer_id)
	if gate and Vector2(pos.x - gate.global_position.x, pos.z - gate.global_position.z).length() <= MUSTER_RADIUS:
		_assign_formation_waypoints(gm.get_members(group), gate.global_position)
	return id

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

func spawn_neutral_minion(pos: Vector3, type_id: StringName = &"neutral_zombie", waypoint: Vector3 = Vector3.INF) -> int:
	## Host-only. Spawns a good-faction NPC (owner_peer_id = -1, faction = NEUTRAL).
	if not multiplayer.is_server():
		return -1
	var id := _next_minion_id
	_next_minion_id += 1
	var wp := waypoint if waypoint != Vector3.INF else pos
	_spawn_minion_rpc.rpc(id, -1, GameConstants.Faction.NEUTRAL, pos, String(type_id), wp)
	return id

# --- Ownership changes (bought nobles, thralls) ---

func set_unit_owner(minion: MinionActor, peer_id: int) -> void:
	## Host-only: a unit changes sides (a bought noble joins you, or defects).
	if not multiplayer.is_server():
		return
	_set_unit_owner_rpc.rpc(minion.name.to_int(), peer_id)
	var gm := get_tree().current_scene.get_node_or_null("GroupManager") as GroupManager
	if gm == null:
		return
	var old := gm.get_group(minion.group_id)
	if old:
		old.member_ids.erase(minion.name.to_int())
	minion.group_id = -1
	if peer_id > 0:
		gm.join_home_group(peer_id, minion)

@rpc("authority", "call_local", "reliable")
func _set_unit_owner_rpc(id: int, peer_id: int) -> void:
	var m := get_minion_by_id(id)
	if m == null:
		return
	m.owner_peer_id = peer_id
	m.faction = _get_player_faction(peer_id) if peer_id > 0 else GameConstants.Faction.NEUTRAL

# --- Carrying (bodies, captives, goods) ---

func set_carry(minion: MinionActor, kind: StringName, amount: int = 0) -> void:
	## Host-only. What a unit carries, mirrored to every peer for its look.
	if not multiplayer.is_server():
		return
	_set_carry_rpc.rpc(minion.name.to_int(), kind, amount)

@rpc("authority", "call_local", "reliable")
func _set_carry_rpc(id: int, kind: StringName, amount: int) -> void:
	var m := get_minion_by_id(id)
	if m:
		m.set_carrying(kind, amount)

# --- Bodies (GDD §5: undead are raised from the bodies of killed humans) ---

var _bodies: Dictionary[int, Body] = {}
var _next_body_id: int = 1

func spawn_body(pos: Vector3) -> void:
	## Host-only.
	if not multiplayer.is_server():
		return
	var id := _next_body_id
	_next_body_id += 1
	_spawn_body_rpc.rpc(id, pos)

@rpc("authority", "call_local", "reliable")
func _spawn_body_rpc(id: int, pos: Vector3) -> void:
	var body := Body.new()
	body.body_id = id
	body.name = "Body%d" % id
	if _minions_node:
		_minions_node.get_parent().add_child(body)
	body.global_position = pos
	_bodies[id] = body

func take_body(body: Body) -> void:
	## Host-only: someone picked it up.
	if multiplayer.is_server() and body.body_id in _bodies:
		_remove_body_rpc.rpc(body.body_id)

@rpc("authority", "call_local", "reliable")
func _remove_body_rpc(id: int) -> void:
	var body: Body = _bodies.get(id)
	_bodies.erase(id)
	if body and is_instance_valid(body):
		body.queue_free()

func get_bodies() -> Array[Body]:
	var out: Array[Body] = []
	for b in _bodies.values():
		if is_instance_valid(b):
			out.append(b)
	return out

# --- Treasury (GDD §6: the treasure room shows the tower's holdings exactly) ---

## peer_id -> goods held at that player's tower.
var treasury: Dictionary[int, int] = {}
signal treasury_changed(peer_id: int, amount: int)

func get_treasury(peer_id: int) -> int:
	return treasury.get(peer_id, 0)

func add_treasury(peer_id: int, amount: int) -> void:
	## Host-only.
	if multiplayer.is_server():
		_sync_treasury.rpc(peer_id, maxi(0, get_treasury(peer_id) + amount))

@rpc("authority", "call_local", "reliable")
func _sync_treasury(peer_id: int, amount: int) -> void:
	treasury[peer_id] = amount
	treasury_changed.emit(peer_id, amount)

func spawn_named_minion_for_peer(peer_id: int, type_id: StringName, pos: Vector3, waypoint: Vector3 = Vector3.INF) -> int:
	## Host-only. Spawns a specific minion type for a specific owner — used by
	## Advisor-mediated dispatch (couriers) and other system-driven spawns.
	## Returns the new minion id, or -1 if not the host.
	if not multiplayer.is_server():
		return -1
	var faction: int = _get_player_faction(peer_id)
	var id := _next_minion_id
	_next_minion_id += 1
	var wp := waypoint if waypoint != Vector3.INF else pos
	_spawn_minion_rpc.rpc(id, peer_id, faction, pos, String(type_id), wp)
	return id

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
	_assign_formation_waypoints(get_minions_for_player(sender), target_pos)
	# War Table clicks also relocate the sender's rally so future summons
	# muster at the latest command point.
	var rally := get_rally_point_for(sender)
	if rally and rally.owning_peer_id == sender:
		_apply_rally_move.rpc(rally.slot_index, target_pos)

func _assign_formation_waypoints(minions: Array[MinionActor], target: Vector3) -> void:
	## Phalanx slot assignment. Each minion gets its own waypoint inside a
	## grid centered on `target`, oriented so the front rank faces away from
	## the squad's current centroid (the formation "arrives" pointing forward
	## from where it came). Closest minion to target → front-center, then fan
	## out — minimizes total travel and avoids paths crossing.
	if minions.is_empty():
		return
	var centroid := Vector3.ZERO
	for m in minions:
		centroid += m.global_position
	centroid /= float(minions.size())
	var to_target := target - centroid
	to_target.y = 0
	var forward: Vector3 = to_target.normalized() if to_target.length() > 0.01 else Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var ordered: Array[MinionActor] = minions.duplicate()
	ordered.sort_custom(func(a: MinionActor, b: MinionActor) -> bool:
		return a.global_position.distance_squared_to(target) < b.global_position.distance_squared_to(target))
	for i in ordered.size():
		var col: int = i % FORMATION_WIDTH
		var row: int = i / FORMATION_WIDTH
		var col_offset: float = (float(col) - (FORMATION_WIDTH - 1) * 0.5) * FORMATION_SPACING
		var row_offset: float = -float(row) * FORMATION_SPACING
		var slot: Vector3 = target + right * col_offset + forward * row_offset
		# Snap each slot to the navmesh so a slot that lands inside a wall /
		# off the walkable region doesn't strand a minion at "as close as I
		# can get" forever. The agent's nav map is authoritative for what's
		# walkable from this minion's perspective.
		ordered[i].waypoint = _snap_to_navmesh(ordered[i], slot)

func _snap_to_navmesh(minion: MinionActor, point: Vector3) -> Vector3:
	if minion == null or minion.nav_agent == null:
		return point
	var map_rid: RID = minion.nav_agent.get_navigation_map()
	if not map_rid.is_valid():
		return point
	var snapped: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, point)
	# If the navmesh map isn't loaded yet, map_get_closest_point may return
	# Vector3.ZERO. Fall back to the original point in that case.
	if snapped == Vector3.ZERO and point != Vector3.ZERO:
		return point
	return snapped

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

func command_selection_move(minion_ids: Array, target_pos: Vector3) -> void:
	## Host-only. Distribute a set of minions across formation slots around
	## `target_pos`, so N minions to one location get N distinct waypoints
	## instead of all stacking on one point. The selection is filtered to the
	## minions that actually exist; ownership is NOT checked here because the
	## caller (war-table dispatch / courier delivery) is already authoritative
	## about who's allowed to be in the list.
	if not multiplayer.is_server():
		return
	if _minions_node == null:
		return
	var actors: Array[MinionActor] = []
	for raw in minion_ids:
		var actor := _minions_node.get_node_or_null(str(int(raw))) as MinionActor
		if actor == null or not is_instance_valid(actor):
			continue
		if not actor.can_take_damage():
			continue
		actors.append(actor)
	if actors.is_empty():
		return
	_assign_formation_waypoints(actors, target_pos)

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

func despawn_minion(minion: MinionActor) -> void:
	## Host-only: remove a unit that left play without dying (a courier home,
	## a trainee turned courier). Groups still drop it.
	if not multiplayer.is_server():
		return
	minion_died.emit(minion)
	_remove_minion.rpc(minion.name.to_int())

func notify_minion_died(minion: MinionActor) -> void:
	if not multiplayer.is_server():
		return
	if minion.minion_trait in KnowledgeManager.COURIER_TRAITS:
		KnowledgeManager.courier_lost(minion, minion.last_hit_by)
	minion_died.emit(minion)
	var id := minion.name.to_int()
	KnowledgeManager.notify_minion_removed(id)
	_remove_minion.rpc(id)

@rpc("authority", "call_local", "reliable")
func _remove_minion(id: int) -> void:
	# Tell every peer's KnowledgeManager so per-peer pending_commands and
	# WorldModel sightings clear in lockstep with the actor going away.
	# Without this, only the host saw the entry vanish (notify_minion_died
	# called notify_minion_removed locally), so client war tables kept their
	# arrows up after couriers despawned. notify_minion_removed is idempotent
	# — running it again on the host is harmless.
	KnowledgeManager.notify_minion_removed(id)
	if _minions_node:
		var minion := _minions_node.get_node_or_null(str(id))
		if minion:
			minion.queue_free()

func _get_player_faction(peer_id: int) -> int:
	return GameState.get_faction(peer_id)
