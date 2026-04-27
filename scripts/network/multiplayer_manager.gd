class_name MultiplayerManager
extends Node

# The bulk of this script is for the authority (host/server).

@export var _player_spawn_point: Node3D

var _multiplayer_scene: PackedScene = preload("res://scenes/actors/player/overlord/overlord_actor.tscn")
var _players_in_game: Dictionary = {}
var _player_slot_order: Array[int] = [] # Tracks join order for tower assignment

# Tower spawn positions as offsets from PlayerSpawnPoint (72, 41, 1)
# Each tower's floor is at local Y=40, so spawn Y = tower_global_Y + 40 + 1 (standing height)
# Offset = tower_spawn_global - PlayerSpawnPoint_global
@onready var TOWER_SPAWNS: Array[Vector3] = _get_tower_spawns()

func _ready() -> void:
	print("MultiplayerManager ready!")

	# Listen for avatar changes on all peers so we can update player modes
	GameState.avatar_changed.connect(_on_avatar_changed)

	if multiplayer.has_multiplayer_peer() && is_multiplayer_authority():
		multiplayer.peer_connected.connect(_peer_connected)
		multiplayer.peer_disconnected.connect(_peer_disconnected)

		if NetworkManager.is_hosting_game && not OS.has_feature(NetworkManager.DEDICATED_SERVER_FEATURE_NAME):
			print("Adding Host player to game...")
			_add_player_to_game(1)

func _add_player_to_game(network_id: int) -> void:
	if is_multiplayer_authority():
		print("Adding player to game: %s" % network_id)

		if _players_in_game.get(network_id) == null:
			var player_to_add = _multiplayer_scene.instantiate()
			player_to_add.name = str(network_id)
			_ready_player(player_to_add, network_id)

			_players_in_game[network_id] = player_to_add
			_player_spawn_point.add_child(player_to_add)
		else:
			print("Warning! Attempted to add existing player to game: %s" % network_id)

func _remove_player_from_game(network_id: int) -> void:
	if is_multiplayer_authority():
		print("Removing player from game: %s" % network_id)
		if _players_in_game.has(network_id):
			var player_to_remove = _players_in_game[network_id]
			if player_to_remove:
				player_to_remove.queue_free()
				_players_in_game.erase(network_id)
			_player_slot_order.erase(network_id)

func _ready_player(player: OverlordActor, network_id: int) -> void:
	if is_multiplayer_authority():
		# Assign to next available tower slot
		_player_slot_order.append(network_id)
		var slot = _player_slot_order.find(network_id)
		if slot < TOWER_SPAWNS.size():
			player.position = TOWER_SPAWNS[slot]
			print("Player %s assigned to Tower %d" % [network_id, slot + 1])
		else:
			# Fallback if somehow more than 4 players
			player.position = TOWER_SPAWNS[0]
			print("Warning: No tower slot for player %s, using Tower 1" % network_id)

func get_next_available_slot() -> int:
	## Returns the next open tower slot index (0-3), or -1 if full.
	var used_slots = _player_slot_order.size()
	if used_slots < GameConstants.MAX_PLAYERS:
		return used_slots
	return -1

func get_player_slot(network_id: int) -> int:
	## Returns the tower slot (0-3) for a given player, or -1 if not found.
	return _player_slot_order.find(network_id)

func _on_avatar_changed(old_peer_id: int, new_peer_id: int) -> void:
	# Transfer control to/from the shared Avatar entity
	var avatar = get_tree().current_scene.get_node_or_null("World/Avatar")
	if not avatar or not avatar is AvatarActor:
		push_warning("Avatar node not found in scene tree at World/Avatar")
		return

	# Release previous controller's Overlord
	if old_peer_id > 0 and _player_spawn_point:
		for child in _player_spawn_point.get_children():
			if child is OverlordActor and child.name.to_int() == old_peer_id:
				child.set_overlord_active(true)

	if new_peer_id > 0:
		# Activate Avatar with new controller
		avatar.activate(new_peer_id)
		# Disable the controller's Overlord input/camera
		if _player_spawn_point:
			for child in _player_spawn_point.get_children():
				if child is OverlordActor and child.name.to_int() == new_peer_id:
					child.set_overlord_active(false)
	else:
		# No one controls it — go dormant
		avatar.deactivate()

func _peer_connected(network_id: int) -> void:
	print("Peer connected: %s" % network_id)
	if is_multiplayer_authority():
		_add_player_to_game(network_id)

func _peer_disconnected(network_id: int) -> void:
	print("Peer disconnected: %s" % network_id)
	_remove_player_from_game(network_id)

func _get_tower_spawns() -> Array[Vector3]:
	var towers_arr : Array[Vector3] = []
	for tower in %Towers.get_children():
		var tower_spawn : Marker3D = tower.get_node("SpawnPoint")
		towers_arr.append(_player_spawn_point.to_local(tower_spawn.global_position))
		
	return towers_arr
