extends Node

## Autoload. Spawns floating damage numbers when actors take damage.
##
## Subscribes lazily — listens for `Node` add events on the SceneTree, connects
## the actor's `took_damage` signal when one enters, lets Godot clean up the
## connection when the actor exits the tree (signals on freed objects auto-
## disconnect; no manual disconnect needed).
##
## Cosmetic-only. Actor.took_damage is gated by Actor._is_resimulating(), so
## numbers don't double-spawn during rollback resimulation.

const DAMAGE_NUMBER_SCENE_PATH: String = "res://scenes/ui/damage_number.tscn"

var _scene_cache: PackedScene

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for n in get_tree().get_nodes_in_group(&"actors"):
		_try_connect(n)

func _on_node_added(node: Node) -> void:
	_try_connect(node)

func _try_connect(node: Node) -> void:
	if node is Actor:
		var actor: Actor = node
		if not actor.took_damage.is_connected(_on_actor_took_damage):
			actor.took_damage.connect(_on_actor_took_damage.bind(actor))

func _on_actor_took_damage(amount: int, _source: Node, victim: Actor) -> void:
	if amount <= 0:
		return
	if victim == null or not is_instance_valid(victim):
		return
	if _scene_cache == null:
		_scene_cache = load(DAMAGE_NUMBER_SCENE_PATH) as PackedScene
	if _scene_cache == null:
		return
	var instance := _scene_cache.instantiate() as Node3D
	if instance == null:
		return
	var parent := victim.get_tree().current_scene
	if parent == null:
		instance.queue_free()
		return
	parent.add_child(instance)
	instance.global_position = victim.global_position + Vector3(0.0, 2.5, 0.0)
	if instance.has_method("show_amount"):
		instance.call(&"show_amount", amount)
