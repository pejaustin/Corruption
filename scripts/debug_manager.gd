extends Node

## Debug helpers invoked from the in-game pause menu's Debug section.
## Dummy players spawn as idle Overlords with no input authority, leaving room
## for real players joining via Godot's multi-instance debug.

const DUMMY_BASE_ID: int = 9001

signal aggro_rings_toggled(visible: bool)
signal combat_boxes_toggled(visible: bool)

var _dummy_count := 0
var _player_scene: PackedScene = preload("res://scenes/actors/player/overlord/overlord_actor.tscn")
## Global toggle for minion aggro-radius debug rings. Local-only (each peer
## can choose independently). MinionActor subscribes to aggro_rings_toggled.
var show_aggro_rings: bool = false
## Global toggle for AttackHitbox / Hurtbox visualization. Local-only. Each
## component subscribes to combat_boxes_toggled.
var show_combat_boxes: bool = false

func toggle_aggro_rings() -> void:
	show_aggro_rings = not show_aggro_rings
	aggro_rings_toggled.emit(show_aggro_rings)
	print("[Debug] Minion aggro rings: %s" % ("ON" if show_aggro_rings else "OFF"))

func toggle_combat_boxes() -> void:
	show_combat_boxes = not show_combat_boxes
	combat_boxes_toggled.emit(show_combat_boxes)
	print("[Debug] Combat boxes: %s" % ("ON" if show_combat_boxes else "OFF"))

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

func get_dummy_count() -> int:
	return _dummy_count

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

func spawn_enemy_at_camera() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can spawn enemies")
		return
	var camera = get_viewport().get_camera_3d()
	if not camera:
		print("[Debug] No active camera")
		return
	var spawn_pos = camera.global_position + (-camera.global_basis.z * 5.0)
	spawn_pos.y = 0
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
	var camera = get_viewport().get_camera_3d()
	if not camera:
		print("[Debug] No active camera")
		return
	var spawn_pos = camera.global_position + (-camera.global_basis.z * 5.0)
	spawn_pos.y = 0
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		var my_id = multiplayer.get_unique_id()
		mm.resources[my_id] = mm.resources.get(my_id, 0.0) + 25
		mm.request_summon_minion("", spawn_pos)
		print("[Debug] Spawned minion at (%.1f, %.1f, %.1f)" % [spawn_pos.x, spawn_pos.y, spawn_pos.z])
	else:
		print("[Debug] MinionManager not found")

func add_influence_to_self() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can set influence")
		return
	var my_id = multiplayer.get_unique_id()
	GameState.add_influence(my_id, 10.0)
	print("[Debug] Added 10 influence to peer %d (total: %.1f)" % [my_id, GameState.get_influence(my_id)])

func cycle_faction() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can swap factions")
		return
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if not mm:
		print("[Debug] MinionManager not found")
		return
	var my_id = multiplayer.get_unique_id()
	var current = mm._get_player_faction(my_id)
	var playable = GameConstants.PLAYABLE_FACTIONS
	var cur_idx = playable.find(current)
	var next_faction = playable[(cur_idx + 1) % playable.size()] if cur_idx >= 0 else playable[0]
	GameState.set_faction_override(my_id, next_faction)
	var name = GameConstants.faction_names.get(next_faction, "Unknown")
	print("[Debug] Faction swapped to %s (%d)" % [name, next_faction])

func boost_corruption() -> void:
	if not multiplayer.is_server():
		print("[Debug] Only the host can boost corruption")
		return
	var tm = get_tree().current_scene.get_node_or_null("TerritoryManager")
	if not tm:
		print("[Debug] TerritoryManager not found")
		return
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	var my_id = multiplayer.get_unique_id()
	var faction = 0
	if mm:
		faction = mm._get_player_faction(my_id)
	for x in range(-1, 2):
		for z in range(-1, 2):
			var cell = Vector2i(x, z)
			tm._add_corruption(cell, faction, 0.5)
	print("[Debug] Boosted corruption around origin (total: %.1f)" % tm.get_total_corruption())

func _get_multiplayer_manager() -> MultiplayerManager:
	var scene = get_tree().current_scene
	if scene:
		return scene.get_node_or_null("MultiplayerManager") as MultiplayerManager
	return null
