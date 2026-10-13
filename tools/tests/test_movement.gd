extends "res://tools/tests/test_base.gd"

## Actor movement, pathing and combat engagement (audit 2026-10-13): speeds are the set move_speed at any physics rate,
## chasers close to attack range, waypoints settle, unreachable targets are dropped.

var mm: MinionManager
var gm: GroupManager
const CLEAR_RADIUS: float = 80.0

var origin: Vector3 = Vector3.ZERO
var only: String = OS.get_environment("ONLY")

func run_tests() -> void:
	var world := await load_world()
	mm = world.get_node("MinionManager") as MinionManager
	gm = world.get_node("GroupManager") as GroupManager
	KnowledgeManager.INSTANT_COMMANDS = true
	for m in mm.get_all_minions():
		mm.despawn_minion(m)
	await seconds(8.0)  # Let the host bake the world navmesh.
	origin = _find_open_ground()
	_park_paladin()

	# ONLY=<name> runs one section while iterating.
	for section in [&"_speed_at_rates", &"_jump_lands", &"_chase_closes"]:
		if only.is_empty() or only == String(section):
			await call(section)

func _find_open_ground() -> Vector3:
	## A navmesh point with no actor within CLEAR_RADIUS and a straight 60 m run along +x, so tests are not
	## disturbed by townsfolk, towers or the Paladin.
	var map_rid: RID = get_tree().current_scene.get_world_3d().navigation_map
	for i in 400:
		var p: Vector3 = NavigationServer3D.map_get_random_point(map_rid, 1, true)
		if absf(p.x) > 700.0 or absf(p.z) > 700.0:
			continue
		var clear := true
		for a in get_tree().get_nodes_in_group(&"actors"):
			if (a as Node3D).global_position.distance_to(p) < CLEAR_RADIUS:
				clear = false
				break
		if not clear:
			continue
		var end: Vector3 = NavigationServer3D.map_get_closest_point(map_rid, p + Vector3(60, 0, 0))
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map_rid, p, end, true)
		var length := 0.0
		for j in range(1, path.size()):
			length += path[j - 1].distance_to(path[j])
		if path.size() >= 2 and length < 66.0 and absf(end.y - p.y) < 3.0 and Vector2(end.x - p.x, end.z - p.z).length() > 55.0:
			print("[tests] open ground at ", p)
			return p + Vector3.UP * 0.5
	push_error("no open ground found")
	return Vector3.ZERO

func _park_paladin() -> void:
	## Keep the Paladin's AI out of the way of these tests.
	var avatar := get_tree().current_scene.get_node("World/Avatar") as AvatarActor
	avatar.avatar_input.ai_driver = null
	avatar.pin_transform(Transform3D(Basis.IDENTITY, origin + Vector3(300, -300, 300)))

func _spawn(owner_id: int, type: StringName, pos: Vector3) -> MinionActor:
	var id: int
	if owner_id > 0:
		id = mm.spawn_unit_for_peer(owner_id, type, pos)
	else:
		id = mm.spawn_neutral_minion(pos, type, pos)
	await frames(5)
	return mm.get_minion_by_id(id)

func _snap(p: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_tree().current_scene.get_world_3d().navigation_map, p)

func _speed_at_rates() -> void:
	var default_rate: int = Engine.physics_ticks_per_second
	for rate in [20, 30, 45, 60, 120]:
		Engine.physics_ticks_per_second = rate
		var skel := await _spawn(1, &"skeleton", origin)
		if skel == null:
			check(false, "speed @%d Hz: spawn" % rate)
			continue
		skel.waypoint = _snap(origin + Vector3(40, 0, 0))
		await seconds(1.0)  # Get up to speed, off the spawn.
		var start := skel.global_position
		var finite := true
		var elapsed := 0.0
		var t0 := Time.get_ticks_msec()
		while elapsed < 2.0:
			await get_tree().physics_frame
			elapsed += 1.0 / float(rate)
			if not (skel.velocity.is_finite() and skel.global_position.is_finite()):
				finite = false
		var wall := (Time.get_ticks_msec() - t0) / 1000.0
		var moved := Vector2(skel.global_position.x - start.x, skel.global_position.z - start.z).length()
		var speed := moved / maxf(wall, 0.001)
		check(finite, "speed @%d Hz: velocity and position stay finite" % rate)
		check(absf(speed - skel.move_speed) <= skel.move_speed * 0.2, "speed @%d Hz: %.2f m/s is the set %.2f m/s" % [rate, speed, skel.move_speed])
		mm.despawn_minion(skel)
		await frames(3)
	Engine.physics_ticks_per_second = default_rate

func _jump_lands() -> void:
	## A jump arc lands where it aims (it was doubled: the launch velocity went through the 2x physics factor).
	var skel := await _spawn(1, &"skeleton", origin)
	await seconds(1.0)
	var target := _snap(skel.global_position + Vector3(6, 0, 0))
	skel.waypoint = skel.global_position
	skel.jump_target = target
	skel._state_machine.transition(&"JumpState")
	var waited := 0.0
	while skel._state_machine.state == &"JumpState" and waited < 4.0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	var miss := Vector2(skel.global_position.x - target.x, skel.global_position.z - target.z).length()
	check(waited < 4.0 and miss <= 1.0, "jump lands within 1 m of its target (missed by %.2f m after %.2f s)" % [miss, waited])
	mm.despawn_minion(skel)
	await frames(3)

func _chase_closes() -> void:
	## A skeleton chasing a holy knight that walks away at half speed gets a swing in, and damage lands once he stops.
	var skel := await _spawn(1, &"skeleton", origin)
	var knight := await _spawn(-1, &"holy_knight", origin + Vector3(6, 0, 0))
	knight.aggro_radius = 0.0  # He only walks his waypoint: never turns on the skeleton.
	knight.move_speed = skel.move_speed * 0.5
	knight.nav_agent.max_speed = knight.move_speed
	knight.waypoint = _snap(origin + Vector3(26, 0, 0))  # He walks 20 m, then stands: a swing at a target in full flight misses by design.
	var hp := knight.hp
	var swung_at := -1.0
	var elapsed := 0.0
	while elapsed < 20.0 and knight.hp == hp:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		if swung_at < 0.0 and skel._state_machine.state == &"AttackState":
			swung_at = elapsed
	check(swung_at >= 0.0 and swung_at < 7.0, "a chaser starts a swing while the target is still walking away (at %.1f s; he stops at about 10 s)" % swung_at)
	check(knight.hp < hp, "the swing lands damage within 20 s (knight %d/%d, %.1f s)" % [knight.hp, hp, elapsed])
	for m in [skel, knight]:
		mm.despawn_minion(m)
	await frames(3)
