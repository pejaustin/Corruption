extends GutTest

## Base for component tests that need the match's managers but not the world: a bare
## "stage" made current_scene, holding only what game code looks up there
## (MinionManager with its Minions root, GroupManager). No terrain, no navmesh,
## no towers. Add what a test needs with `stage.add_child`.

var stage: Node3D
var mm: MinionManager
var gm: GroupManager
var _previous_scene: Node

func before_each() -> void:
	stage = Node3D.new()
	stage.name = "Stage"
	var minions := Node3D.new()
	minions.name = "Minions"
	stage.add_child(minions)
	mm = MinionManager.new()
	mm.name = "MinionManager"
	mm.minions_root = minions
	mm.body_scene = preload("res://scenes/world/places/body.tscn")
	stage.add_child(mm)
	gm = GroupManager.new()
	gm.name = "GroupManager"
	stage.add_child(gm)
	_previous_scene = get_tree().current_scene
	get_tree().root.add_child(stage)
	get_tree().current_scene = stage
	# Units snap to the navigation map on spawn. The map is empty, but querying it before its first
	# synchronization errors, so the first test waits a few physics frames for it.
	var nav_map := stage.get_world_3d().navigation_map
	for i in 10:
		if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
			break
		await get_tree().physics_frame

func after_each() -> void:
	# netfox nodes connect their signals deferred; let that run so freeing them disconnects cleanly.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = _previous_scene
	stage.free()
	GameState.reset()

func add_overlord(peer := 1) -> OverlordActor:
	## Player `peer`'s overlord body, idle (its input and physics off).
	var overlord := (preload("res://scenes/actors/player/overlord/overlord_actor.tscn").instantiate()) as OverlordActor
	overlord.name = str(peer)
	stage.add_child(overlord)
	overlord.process_mode = Node.PROCESS_MODE_DISABLED
	return overlord

func add_avatar() -> AvatarActor:
	## The Paladin at World/Avatar, where game code looks for him, idle.
	var world := stage.get_node_or_null(^"World") as Node3D
	if world == null:
		world = Node3D.new()
		world.name = "World"
		stage.add_child(world)
	var avatar := (preload("res://scenes/actors/player/avatar/avatar_actor.tscn").instantiate()) as AvatarActor
	avatar.name = "Avatar"
	world.add_child(avatar)
	avatar.process_mode = Node.PROCESS_MODE_DISABLED
	return avatar

func add_tower(owner_peer: int) -> Tower:
	## A bare Tower owned by `owner_peer` (no building), to parent a tower's interactables under.
	var tower := Tower.new()
	var timer := Timer.new()
	timer.name = "TrickleTimer"
	tower.add_child(timer)
	stage.add_child(tower)
	tower.owner_peer_id = owner_peer
	return tower

func spawn(type_id: StringName, owner_peer: int, pos := Vector3.ZERO) -> MinionActor:
	## A unit of `type_id` for `owner_peer` (a player id, or GameConstants.GOOD_SIDE).
	var id := mm.spawn_unit_for_peer(owner_peer, type_id, pos) if owner_peer > 0 else mm.spawn_neutral_minion(pos, type_id, pos)
	var unit := mm.get_minion_by_id(id)
	unit.set_physics_process(false)
	return unit

func spawn_live(type_id: StringName, owner_peer: int, pos := Vector3.ZERO) -> MinionActor:
	## A unit that thinks and moves: real physics, its state machine running.
	var unit := spawn(type_id, owner_peer, pos)
	unit.set_physics_process(true)
	return unit

func add_ground(size := Vector2(80, 20)) -> NavigationRegion3D:
	## Flat ground centred on the origin with a navmesh baked over it, for tests that need units to walk.
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.agent_radius = 0.75
	mesh.agent_height = 3.0
	region.navigation_mesh = mesh
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 1.0, size.y)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	region.add_child(body)
	stage.add_child(region)
	region.bake_navigation_mesh(false)
	# The map picks up the baked mesh on a later synchronization (it returns the origin until then).
	var map := stage.get_world_3d().navigation_map
	for i in 20:
		if NavigationServer3D.map_get_closest_point(map, Vector3(1, 0, 1)) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	return region

func run_physics(game_seconds: float) -> void:
	## Let real physics (and the navigation server) run for `game_seconds` of game time.
	var elapsed := 0.0
	while elapsed < game_seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
