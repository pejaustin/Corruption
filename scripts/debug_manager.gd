extends Node

## Debug manager for solo testing.
## F2: Add a dummy player (fills remaining tower slots).
## Dummy players spawn as idle Overlords with no input authority.
## Leaves room for real players joining via Godot's multi-instance debug.

const DUMMY_BASE_ID := 9001

var _dummy_count := 0
var _player_scene = preload("res://scenes/player/player.tscn")

var _enemy_scene = preload("res://scenes/actors/enemy/zombie/zombie_actor.tscn")

func _unhandled_input(event: InputEvent):
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_F2:
			if not multiplayer.is_server():
				print("[Debug] Only the host can spawn dummy players")
				return
			add_dummy_player()
		KEY_F4:
			_toggle_god_mode()
		KEY_F5:
			_kill_avatar()
		KEY_F6:
			_spawn_enemy_at_camera()

func add_dummy_player():
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

	# Register in the manager's slot order and position at the correct tower
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

func _toggle_god_mode():
	var avatar = _get_avatar()
	if avatar:
		avatar.god_mode = !avatar.god_mode
		print("[Debug] God mode: %s" % ("ON" if avatar.god_mode else "OFF"))
	else:
		print("[Debug] Avatar not found")

func _kill_avatar():
	if not multiplayer.is_server():
		print("[Debug] Only the host can kill the Avatar")
		return
	var avatar = _get_avatar()
	if avatar and not avatar.is_dormant:
		avatar.incoming_damage += avatar.hp
		print("[Debug] Avatar killed")
	else:
		print("[Debug] Avatar not active")

func _spawn_enemy_at_camera():
	if not multiplayer.is_server():
		print("[Debug] Only the host can spawn enemies")
		return
	var camera = get_viewport().get_camera_3d()
	if not camera:
		print("[Debug] No active camera")
		return
	# Spawn 5 meters in front of the camera, on the ground
	var spawn_pos = camera.global_position + (-camera.global_basis.z * 5.0)
	spawn_pos.y = 0  # ground level
	var enemy = _enemy_scene.instantiate()
	enemy.global_position = spawn_pos
	var enemies_node = get_tree().current_scene.get_node_or_null("World/Enemies")
	if not enemies_node:
		enemies_node = Node3D.new()
		enemies_node.name = "Enemies"
		get_tree().current_scene.get_node("World").add_child(enemies_node)
	enemies_node.add_child(enemy)
	print("[Debug] Spawned enemy at (%.1f, %.1f, %.1f)" % [spawn_pos.x, spawn_pos.y, spawn_pos.z])

func _get_avatar() -> PlayerActor:
	var scene = get_tree().current_scene
	if scene:
		return scene.get_node_or_null("World/Avatar") as PlayerActor
	return null

func _get_multiplayer_manager() -> MultiplayerManager:
	var scene = get_tree().current_scene
	if scene:
		return scene.get_node_or_null("MultiplayerManager") as MultiplayerManager
	return null
