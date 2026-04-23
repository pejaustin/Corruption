extends Node3D

## Harness scene for iterating on the War Table diorama without booting the
## full game. Spawns wandering fake minions, feeds their positions into a
## dedicated WorldModel keyed by FAKE_PEER_ID, and lets you exercise the
## render / mapping / command paths with hotkeys.
##
## Hotkeys (see Hud label for the on-screen copy):
##   1 — teleport a random fake minion to a random point
##   2 — despawn a random fake minion
##   3 — toggle infinite-broadcast-range mode (off = only friendlies within
##       TEST_BROADCAST_RANGE of another friendly leak into belief)
##   4 — spawn an extra friendly minion (stand-in for a command-dispatch test)
##   Click on the diorama — projects the click to a world point via the map
##       and spawns a persistent debug marker there; useful for validating
##       table-to-world mapping visually.

const FAKE_PEER_ID: int = 9999
const TEST_BROADCAST_RANGE: float = 8.0
const FRIENDLY_COUNT: int = 3
const ENEMY_COUNT: int = 2

@export var war_table_map: WarTableMap
@export var fake_minions_root: Node3D
@export var debug_markers_root: Node3D
@export var camera: Camera3D
@export var status_label: Label
@export var fake_minion_scene: PackedScene
@export var playspace_extent: Vector2 = Vector2(15.0, 15.0)
@export var friendly_faction: int = GameConstants.Faction.UNDEATH
@export var enemy_faction: int = GameConstants.Faction.DEMONIC

var _next_minion_id: int = 1
var _broadcast_infinite: bool = true
var _tick: int = 0

func _ready() -> void:
	assert(war_table_map, "Assign war_table_map in the inspector")
	assert(fake_minions_root, "Assign fake_minions_root in the inspector")
	assert(fake_minion_scene, "Assign fake_minion_scene in the inspector")
	for i in FRIENDLY_COUNT:
		_spawn_fake_minion(friendly_faction, FAKE_PEER_ID)
	for i in ENEMY_COUNT:
		_spawn_fake_minion(enemy_faction, -1)
	_refresh_status()

func _process(_delta: float) -> void:
	_tick += 1
	_push_sightings()
	war_table_map.render_from_model(KnowledgeManager.get_model(FAKE_PEER_ID))

func _spawn_fake_minion(faction: int, owner_id: int) -> FakeMinion:
	var m: FakeMinion = fake_minion_scene.instantiate()
	_next_minion_id += 1
	m.name = str(_next_minion_id)
	m.faction = faction
	m.owner_peer_id = owner_id
	m.playspace_extent = playspace_extent
	fake_minions_root.add_child(m)
	m.global_position = Vector3(
		randf_range(-playspace_extent.x, playspace_extent.x),
		0.0,
		randf_range(-playspace_extent.y, playspace_extent.y),
	)
	_tint_mesh(m, faction)
	return m

func _tint_mesh(m: FakeMinion, faction: int) -> void:
	var mesh := m.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GameConstants.faction_colors.get(faction, Color.WHITE)
	mesh.material_override = mat

func _push_sightings() -> void:
	var model := KnowledgeManager.get_model(FAKE_PEER_ID)
	var friendlies: Array[FakeMinion] = []
	var all: Array[FakeMinion] = []
	for child in fake_minions_root.get_children():
		if child is FakeMinion:
			all.append(child)
			if child.owner_peer_id == FAKE_PEER_ID:
				friendlies.append(child)
	# Rebuild each tick so removed minions stop leaking into belief.
	var alive_ids: Dictionary[int, bool] = {}
	for m in all:
		var id := m.name.to_int()
		alive_ids[id] = true
		var is_friendly := m.owner_peer_id == FAKE_PEER_ID
		if not _broadcast_infinite and not _observable(m, friendlies):
			continue
		model.update_minion_sighting(
			id, m.global_position, m.owner_peer_id, m.faction, _tick, is_friendly
		)
	# Prune sightings for despawned fake minions so pieces disappear from the table.
	for id in model.believed_friendly_minions.keys():
		if id not in alive_ids:
			model.forget_minion(id)
	for id in model.believed_enemy_minions.keys():
		if id not in alive_ids:
			model.forget_minion(id)

func _observable(subject: FakeMinion, friendlies: Array[FakeMinion]) -> bool:
	if subject.owner_peer_id == FAKE_PEER_ID:
		return true
	for f in friendlies:
		if f.global_position.distance_to(subject.global_position) <= TEST_BROADCAST_RANGE:
			return true
	return false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_teleport_random_minion()
				_refresh_status()
			KEY_2:
				_kill_random_minion()
				_refresh_status()
			KEY_3:
				_broadcast_infinite = not _broadcast_infinite
				_refresh_status()
			KEY_4:
				_spawn_fake_minion(friendly_faction, FAKE_PEER_ID)
				_refresh_status()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_place_marker_from_click(event.position)

func _teleport_random_minion() -> void:
	var minions := _all_fake_minions()
	if minions.is_empty():
		return
	var m := minions[randi() % minions.size()]
	m.global_position = Vector3(
		randf_range(-playspace_extent.x, playspace_extent.x),
		m.global_position.y,
		randf_range(-playspace_extent.y, playspace_extent.y),
	)

func _kill_random_minion() -> void:
	var minions := _all_fake_minions()
	if minions.is_empty():
		return
	var m := minions[randi() % minions.size()]
	m.queue_free()

func _all_fake_minions() -> Array[FakeMinion]:
	var out: Array[FakeMinion] = []
	for child in fake_minions_root.get_children():
		if child is FakeMinion:
			out.append(child)
	return out

func _place_marker_from_click(screen_pos: Vector2) -> void:
	if camera == null or war_table_map == null or debug_markers_root == null:
		return
	var world_pos: Vector3 = war_table_map.camera_ray_to_world(camera, screen_pos)
	if world_pos == Vector3.INF:
		return
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0)
	mat.emission_energy_multiplier = 0.5
	marker.material_override = mat
	debug_markers_root.add_child(marker)
	marker.global_position = world_pos

func _refresh_status() -> void:
	if status_label == null:
		return
	var mode := "INFINITE" if _broadcast_infinite else "%.0fm friendly-scout" % TEST_BROADCAST_RANGE
	status_label.text = """War Table Test Scene
Broadcast range: %s
Fake minions: %d (friendlies push into WorldModel for peer %d)

[1] teleport random minion
[2] despawn random minion
[3] toggle broadcast range
[4] spawn friendly minion
[Click] project table point → debug marker in world
""" % [mode, _all_fake_minions().size(), FAKE_PEER_ID]
