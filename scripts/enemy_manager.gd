class_name EnemyManager extends Node

## Host-authoritative enemy spawner and sync manager.
## Ensures enemies are created/destroyed on all clients.

var _enemy_scene: PackedScene = preload("res://scenes/actors/enemy/zombie/zombie_actor.tscn")
var _next_enemy_id: int = 1
var _enemies_node: Node3D

func _ready() -> void:
	# Find or create the Enemies container
	_enemies_node = get_tree().current_scene.get_node_or_null("World/Enemies")
	if not _enemies_node and multiplayer.is_server():
		_enemies_node = Node3D.new()
		_enemies_node.name = "Enemies"
		get_tree().current_scene.get_node("World").add_child(_enemies_node)

func spawn_enemy(pos: Vector3, patrol: Vector3 = Vector3.ZERO) -> Variant:
	## Host-only: spawn an enemy and replicate to all clients.
	if not multiplayer.is_server():
		return null
	var id = _next_enemy_id
	_next_enemy_id += 1
	if patrol == Vector3.ZERO:
		patrol = pos
	_spawn_enemy_rpc.rpc(id, pos, patrol)
	return _enemies_node.get_node_or_null(str(id))

@rpc("authority", "call_local", "reliable")
func _spawn_enemy_rpc(id: int, pos: Vector3, patrol: Vector3) -> void:
	if not _enemies_node:
		_enemies_node = get_tree().current_scene.get_node_or_null("World/Enemies")
		if not _enemies_node:
			_enemies_node = Node3D.new()
			_enemies_node.name = "Enemies"
			get_tree().current_scene.get_node("World").add_child(_enemies_node)
	var enemy = _enemy_scene.instantiate()
	enemy.name = str(id)
	enemy.patrol_point = patrol
	_enemies_node.add_child(enemy)
	enemy.global_position = pos

@rpc("authority", "call_local", "reliable")
func _remove_enemy_rpc(id: int) -> void:
	if _enemies_node:
		var enemy = _enemies_node.get_node_or_null(str(id))
		if enemy:
			enemy.queue_free()

func notify_enemy_died(enemy: EnemyActor) -> void:
	## Called by EnemyActor on the host when it's ready to be removed.
	if not multiplayer.is_server():
		return
	_remove_enemy_rpc.rpc(enemy.name.to_int())

func get_enemy_count() -> int:
	if _enemies_node:
		return _enemies_node.get_child_count()
	return 0
