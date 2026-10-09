class_name Settlement extends Node3D

## A human settlement (GDD §5): villagers going about their lives, one or a
## few nobles who can be bought, and soldiers of the good faction. Killing
## its people after promising to spare it breaks that promise and the noble
## you bought turns on you (Q23).
## Host spawns its people at match start. Placement and numbers are
## placeholders (the map is Austin's, ticket #584).

const GROUP: StringName = &"settlements"
## How often idle villagers pick a new spot to wander to.
const WANDER_INTERVAL: float = 6.0

@export var radius: float = 16.0
## PLACEHOLDER: tuning, not designed — the people living here.
@export var villagers: int = 4
@export var nobles: int = 1
@export var soldiers: int = 2
@export var villager_type: StringName = &"villager"
@export var noble_type: StringName = &"noble"
@export var soldier_type: StringName = &"holy_knight"

## peer id -> promise made when buying a noble here (&"spare" / &"assassinate").
var promises: Dictionary[int, StringName] = {}
var _wander_timer: float = 0.0
var _people: Array[int] = []

func _ready() -> void:
	add_to_group(GROUP)
	if multiplayer.is_server():
		_spawn_people.call_deferred()

func _spawn_people() -> void:
	# MinionManager adopts its unit root a frame after the world is ready.
	await get_tree().process_frame
	var mm := _mm()
	if mm == null:
		return
	for i in villagers:
		_spawn(mm, villager_type)
	for i in nobles:
		_spawn(mm, noble_type)
	for i in soldiers:
		_spawn(mm, soldier_type)

func _spawn(mm: MinionManager, type_id: StringName) -> void:
	var pos := _random_spot()
	var id := mm.spawn_neutral_minion(pos + Vector3.UP, type_id, pos)
	var m := mm.get_minion_by_id(id)
	if m:
		m.settlement_name = StringName(name)
		_people.append(id)

func _random_spot() -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * radius
	var p := global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 100.0, p + Vector3.DOWN * 100.0, 1))
	return hit.position if not hit.is_empty() else p

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_wander_timer += delta
	if _wander_timer < WANDER_INTERVAL:
		return
	_wander_timer = 0.0
	var mm := _mm()
	if mm == null:
		return
	for id in _people:
		var m := mm.get_minion_by_id(id)
		if m and m.owner_peer_id <= 0 and m.can_take_damage() and m.attack_damage == 0 and randf() < 0.5:
			m.waypoint = _random_spot()

func nobles_of(peer_id: int) -> Array[MinionActor]:
	var out: Array[MinionActor] = []
	var mm := _mm()
	for id in _people:
		var m := mm.get_minion_by_id(id) if mm else null
		if m and m.is_noble and m.owner_peer_id == peer_id:
			out.append(m)
	return out

static func find(tree: SceneTree, settlement_name: StringName) -> Settlement:
	for n in tree.get_nodes_in_group(GROUP):
		if n.name == settlement_name:
			return n
	return null

static func on_human_killed(human: MinionActor) -> void:
	## Host-only. Killing a settlement's people breaks a promise to spare it.
	var s := find(human.get_tree(), human.settlement_name)
	var killer := human.last_hit_by
	if s == null or killer <= 0 or s.promises.get(killer, &"") != &"spare":
		return
	s.promises.erase(killer)
	var mm := s._mm()
	for noble in s.nobles_of(killer):
		mm.set_unit_owner(noble, -1)
	KnowledgeManager.deliver_report(killer, {"source": &"courier",
		"lines": ["PLACEHOLDER: Your word to %s is broken; their noble turns on you." % s.name]})

func _mm() -> MinionManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("MinionManager") as MinionManager if scene else null
