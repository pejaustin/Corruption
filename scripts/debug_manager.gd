extends Node

## Debug helpers invoked from the in-game pause menu's Debug section.
## Dummy players spawn as idle Overlords with no input authority, leaving room
## for real players joining via Godot's multi-instance debug.

const DUMMY_BASE_ID: int = 9001

signal aggro_rings_toggled(visible: bool)
signal combat_boxes_toggled(visible: bool)
signal courier_visual_range_toggled(visible: bool)

var _dummy_count := 0
var _player_scene: PackedScene = preload("res://scenes/actors/player/overlord/overlord_actor.tscn")
## Set by the lobby before the world scene loads. MultiplayerManager._ready
## consumes this list on the host after registering the host + connected peers.
var pending_cpu_ids: Array[int] = []
## Global toggle for minion aggro-radius debug rings. Local-only (each peer
## can choose independently). MinionActor subscribes to aggro_rings_toggled.
var show_aggro_rings: bool = false
## Global toggle for AttackHitbox / Hurtbox visualization. Local-only. Each
## component subscribes to combat_boxes_toggled.
var show_combat_boxes: bool = false
## Global toggle for the courier visual-range debug sphere. Local-only.
## MinionActor (when its MinionType has a non-zero courier_visual_range)
## subscribes to courier_visual_range_toggled.
var show_courier_visual_range: bool = false

func toggle_aggro_rings() -> void:
	show_aggro_rings = not show_aggro_rings
	aggro_rings_toggled.emit(show_aggro_rings)
	print("[Debug] Minion aggro rings: %s" % ("ON" if show_aggro_rings else "OFF"))

func toggle_combat_boxes() -> void:
	show_combat_boxes = not show_combat_boxes
	combat_boxes_toggled.emit(show_combat_boxes)
	print("[Debug] Combat boxes: %s" % ("ON" if show_combat_boxes else "OFF"))

func toggle_courier_visual_range() -> void:
	show_courier_visual_range = not show_courier_visual_range
	courier_visual_range_toggled.emit(show_courier_visual_range)
	print("[Debug] Courier visual range: %s" % ("ON" if show_courier_visual_range else "OFF"))

func toggle_instant_commands() -> void:
	## Flips KnowledgeManager.INSTANT_COMMANDS: ON, the advisor's orders reach
	## groups at once instead of riding a courier.
	KnowledgeManager.INSTANT_COMMANDS = not KnowledgeManager.INSTANT_COMMANDS
	print("[Debug] INSTANT_COMMANDS: %s" % ("ON" if KnowledgeManager.INSTANT_COMMANDS else "OFF"))

func toggle_read_couriers() -> void:
	## Host: lets the local player read captured couriers' papers (the unlock
	## itself is Austin's to design, ticket #543).
	if not multiplayer.is_server():
		return
	var me := multiplayer.get_unique_id()
	KnowledgeManager.can_read_couriers[me] = not KnowledgeManager.can_read_couriers.get(me, false)
	print("[Debug] Read captured couriers: %s" % ("ON" if KnowledgeManager.can_read_couriers[me] else "OFF"))

func add_dummy_player() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can spawn dummy players")
		return
	var mm = _get_multiplayer_manager()
	if not mm:
		print("[Debug] MultiplayerManager not found — are you in a game scene?")
		return

	var next_slot = mm.get_next_available_slot()
	if next_slot == -1:
		print("[Debug] All tower slots full — no room for more players")
		return

	var dummy_id = DUMMY_BASE_ID + _dummy_count
	_dummy_count += 1

	# Use the multiplayer manager's spawn logic so dummies get proper tower placement
	var spawn_point = mm._player_spawn_point
	if not spawn_point:
		print("[Debug] No PlayerSpawnPoint found")
		return

	var dummy = _player_scene.instantiate()
	dummy.name = str(dummy_id)

	mm._player_slot_order.append(dummy_id)
	var slot = mm._player_slot_order.find(dummy_id)
	dummy.position = mm.TOWER_SPAWNS[slot]

	mm._players_in_game[dummy_id] = dummy
	spawn_point.add_child(dummy)
	print("[Debug] Spawned dummy player %d at Tower %d" % [dummy_id, slot + 1])

func spawn_pending_cpus() -> void:
	## Drains pending_cpu_ids, spawning one dummy per id. Called by
	## MultiplayerManager._ready on the host after host + peers are seated.
	if pending_cpu_ids.is_empty():
		return
	var ids := pending_cpu_ids.duplicate()
	pending_cpu_ids.clear()
	spawn_lobby_cpus(ids)

func spawn_lobby_cpus(cpu_ids: Array) -> void:
	## Spawns one dummy player per pre-allocated CPU id from the lobby.
	## Unlike add_dummy_player(), the caller chooses the peer ids so the
	## lobby's faction / name dicts (already synced into GameState) line up.
	if not multiplayer.is_server():
		return
	var mm := _get_multiplayer_manager()
	if not mm:
		print("[Debug] MultiplayerManager not found — CPU slots not spawned")
		return
	var spawn_point: Node3D = mm._player_spawn_point
	if not spawn_point:
		print("[Debug] No PlayerSpawnPoint found")
		return
	for raw_id in cpu_ids:
		var cpu_id: int = int(raw_id)
		if mm._players_in_game.has(cpu_id):
			continue
		var dummy: Node = _player_scene.instantiate()
		if dummy == null:
			push_error("[Debug] _player_scene.instantiate() returned null — overlord_actor.tscn may be broken")
			return
		dummy.name = str(cpu_id)
		mm._player_slot_order.append(cpu_id)
		var slot: int = mm._player_slot_order.find(cpu_id)
		if slot < mm.TOWER_SPAWNS.size():
			dummy.position = mm.TOWER_SPAWNS[slot]
		else:
			dummy.position = mm.TOWER_SPAWNS[0]
		mm._players_in_game[cpu_id] = dummy
		spawn_point.add_child(dummy)
		# Keep _dummy_count past lobby ids so a later F2 doesn't reuse them.
		var offset: int = cpu_id - DUMMY_BASE_ID + 1
		if offset > _dummy_count:
			_dummy_count = offset
		print("[Debug] Spawned lobby CPU %d at Tower %d" % [cpu_id, slot + 1])

func get_dummy_count() -> int:
	return _dummy_count

func reset() -> void:
	## Called when returning to main menu so a new session starts clean.
	_dummy_count = 0
	pending_cpu_ids.clear()

func get_max_dummy_players() -> int:
	var mm = _get_multiplayer_manager()
	if mm:
		return GameConstants.MAX_PLAYERS - mm._player_slot_order.size()
	return 0

func is_dummy(peer_id: int) -> bool:
	return peer_id >= DUMMY_BASE_ID and peer_id < DUMMY_BASE_ID + 100

func toggle_god_mode() -> void:
	var avatar = _get_avatar()
	if avatar:
		avatar.god_mode = !avatar.god_mode
		print("[Debug] God mode: %s" % ("ON" if avatar.god_mode else "OFF"))
	else:
		print("[Debug] Avatar not found")

func kill_avatar() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can kill the Avatar")
		return
	var avatar = _get_avatar()
	if avatar and not avatar.is_dormant:
		avatar.incoming_damage += avatar.hp
		print("[Debug] Avatar killed")
	else:
		print("[Debug] Avatar not active")

func _aim_world_point(default_distance: float) -> Vector3:
	## World point under the camera crosshair — raycast against world geometry
	## (layer 1), excluding the camera's own actor body. Returns Vector3.INF if
	## there's no active camera. The old `pos.y = 0` flatten broke when the
	## terrain rework raised ground height: points computed that way landed
	## beneath the heightmap, so spawns/orders vanished underground.
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3.INF
	var from := camera.global_position
	var dir := -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 300.0, 1)
	var exclude: Array[RID] = []
	var node: Node = camera
	while node:
		if node is CollisionObject3D:
			exclude.append((node as CollisionObject3D).get_rid())
		node = node.get_parent()
	query.exclude = exclude
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
	# Crosshair pointed at the sky — fall back to a point ahead, snapped to
	# the navmesh so it still lands on walkable ground.
	var ahead := from + dir * default_distance
	return NavigationServer3D.map_get_closest_point(camera.get_world_3d().navigation_map, ahead)

func spawn_enemy_at_camera() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can spawn enemies")
		return
	var spawn_pos := _aim_world_point(5.0)
	if spawn_pos == Vector3.INF:
		print("[Debug] No active camera")
		return
	spawn_pos.y += 0.5  # clear the surface so the body settles instead of clipping
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		mm.spawn_neutral_minion(spawn_pos)
		print("[Debug] Spawned neutral minion at (%.1f, %.1f, %.1f)" % [spawn_pos.x, spawn_pos.y, spawn_pos.z])
	else:
		print("[Debug] MinionManager not found")

func _get_avatar() -> AvatarActor:
	var scene = get_tree().current_scene
	if scene:
		return scene.get_node_or_null("World/Avatar") as AvatarActor
	return null

func spawn_minion_at_camera() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can spawn minions")
		return
	var spawn_pos := _aim_world_point(5.0)
	if spawn_pos == Vector3.INF:
		print("[Debug] No active camera")
		return
	spawn_pos.y += 0.5  # clear the surface so the body settles instead of clipping
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		mm.spawn_unit_for_peer(multiplayer.get_unique_id(), &"", spawn_pos)
		print("[Debug] Spawned minion at (%.1f, %.1f, %.1f)" % [spawn_pos.x, spawn_pos.y, spawn_pos.z])
	else:
		print("[Debug] MinionManager not found")

func order_avatar_to_camera() -> void:
	## Phase B test hook: sends the released (AI-driven) avatar a move order to
	## where the crosshair pointed when the menu opened — same entry point the
	## war table will use in Phase C (AvatarAI.command_move).
	if not multiplayer.is_server():
		print("[Debug] Only the host can order the avatar")
		return
	var target_pos := _aim_world_point(10.0)
	if target_pos == Vector3.INF:
		print("[Debug] No active camera")
		return
	var avatar = _get_avatar()
	if avatar and avatar.avatar_ai:
		avatar.avatar_ai.command_move(target_pos)
		print("[Debug] Avatar ordered to (%.1f, %.1f, %.1f)" % [target_pos.x, target_pos.y, target_pos.z])
	else:
		print("[Debug] Avatar (or its AI) not found")

func take_nearest_site() -> void:
	## Hands the corruption site nearest the camera to the local peer.
	if not multiplayer.is_server():
		print("[Debug] Only the host can hand out sites")
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var best: CorruptionSite = null
	var best_d := INF
	for node in GameState.get_all_sites():
		var site := node as CorruptionSite
		if site == null or site.permanent:
			continue
		var d := site.global_position.distance_to(camera.global_position)
		if d < best_d:
			best_d = d
			best = site
	if best == null:
		print("[Debug] No corruption site found")
		return
	best.debug_give_to(multiplayer.get_unique_id())
	print("[Debug] Gave %s to peer %d" % [best.get_display_name(), multiplayer.get_unique_id()])

func add_remains_to_self() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can add remains")
		return
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm:
		mm.add_remains(multiplayer.get_unique_id(), 1)
		print("[Debug] +1 remains at your tower (%d)" % mm.get_remains(multiplayer.get_unique_id()))

func _get_multiplayer_manager() -> MultiplayerManager:
	var scene = get_tree().current_scene
	if scene:
		return scene.get_node_or_null("MultiplayerManager") as MultiplayerManager
	return null
