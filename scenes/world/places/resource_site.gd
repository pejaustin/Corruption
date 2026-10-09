class_name ResourceSite extends Node3D

## A resource location (GDD §6): it produces goods only while an intelligent
## overseer works it — a human or one of a player's units standing in it.
## Goods pile up here until hauled away by order. Which goods exist is
## Austin's (ticket #586); there is one placeholder kind, "goods".

const GROUP: StringName = &"resource_sites"
const TICK_INTERVAL: float = 1.0

@export var radius: float = 10.0
## PLACEHOLDER: tuning, not designed — goods per second while worked, and the
## most that can pile up.
@export var rate: float = 0.25
@export var max_pile: int = 200
## PLACEHOLDER: tuning — villagers working it at match start.
@export var starting_overseers: int = 1

var pile: float = 0.0
var _timer: float = 0.0
var _stack: MeshInstance3D

func _ready() -> void:
	add_to_group(GROUP)
	_build_look()
	if multiplayer.is_server():
		_spawn_overseers.call_deferred()

func _spawn_overseers() -> void:
	# MinionManager adopts its unit root a frame after the world is ready.
	await get_tree().process_frame
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	for i in starting_overseers:
		mm.spawn_neutral_minion(global_position + Vector3(randf_range(-3, 3), 1, randf_range(-3, 3)), &"villager")

func get_pile() -> int:
	return int(pile)

func take(amount: int) -> int:
	## Host-only. Removes up to `amount` goods; returns how many were taken.
	var n := mini(amount, int(pile))
	pile -= n
	_sync_pile.rpc(pile)
	return n

func is_worked() -> bool:
	for node in get_tree().get_nodes_in_group(&"minions"):
		var m := node as MinionActor
		if m == null or not m.can_take_damage():
			continue
		if Vector2(m.global_position.x - global_position.x, m.global_position.z - global_position.z).length() > radius:
			continue
		if m.is_human and m.owner_peer_id <= 0:
			return true
		if m.owner_peer_id > 0 and m.minion_trait == &"":
			return true
	return false

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_timer += delta
	if _timer < TICK_INTERVAL:
		return
	if is_worked() and pile < max_pile:
		pile = minf(max_pile, pile + rate * _timer)
		_sync_pile.rpc(pile)
	_timer = 0.0

@rpc("authority", "call_local", "unreliable")
func _sync_pile(value: float) -> void:
	pile = value
	if _stack:
		_stack.scale = Vector3(1, maxf(0.05, pile / float(max_pile)) * 4.0, 1)

func _build_look() -> void:
	## PLACEHOLDER: art — a crate stack that grows with the pile.
	_stack = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 0.5, 1.2)
	_stack.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.55, 0.25)
	_stack.material_override = mat
	_stack.position = Vector3(2.5, 0.25, 0)
	_stack.scale = Vector3(1, 0.2, 1)
	add_child(_stack)

static func near(tree: SceneTree, pos: Vector3, max_dist: float) -> ResourceSite:
	for n in tree.get_nodes_in_group(GROUP):
		var r := n as ResourceSite
		if r and Vector2(r.global_position.x - pos.x, r.global_position.z - pos.z).length() <= max_dist:
			return r
	return null
