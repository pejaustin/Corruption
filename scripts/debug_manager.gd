extends Node

## Debug manager for solo testing.
## F2: Add a dummy player (fills remaining tower slots).
## Dummy players spawn as idle Overlords with no input authority.
## Leaves room for real players joining via Godot's multi-instance debug.

const DUMMY_BASE_ID := 9001

var _dummy_count := 0
var _player_scene = preload("res://scenes/player/player.tscn")

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		if not multiplayer.is_server():
			print("[Debug] Only the host can spawn dummy players")
			return
		add_dummy_player()

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

func _get_multiplayer_manager() -> MultiplayerManager:
	var scene = get_tree().current_scene
	if scene:
		return scene.get_node_or_null("MultiplayerManager") as MultiplayerManager
	return null
