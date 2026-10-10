extends "res://tools/tests/test_base.gd"

## Melee contact: units of opposing sides that meet actually hurt and kill each
## other (hitboxes, hurtboxes, attack animations), and a stray capture or
## parley flag never makes a fight endless.

var mm: MinionManager
var gm: GroupManager

func run_tests() -> void:
	var world := await load_world()
	mm = world.get_node("MinionManager") as MinionManager
	gm = world.get_node("GroupManager") as GroupManager
	KnowledgeManager.INSTANT_COMMANDS = true
	Engine.time_scale = 4.0
	for m in mm.get_all_minions():
		mm.despawn_minion(m)
	await seconds(8.0)  # Let the host bake the world navmesh.
	var origin := gm.get_centroid(gm.get_groups_for(1)[0]) if not gm.get_groups_for(1).is_empty() else Vector3.ZERO
	origin = _flat_y(origin)

	await _duel("skeleton vs holy knight", 1, &"skeleton", -1, &"holy_knight", origin, false)
	await _duel("skeleton vs holy knight (flags stale)", 1, &"skeleton", -1, &"holy_knight", origin + Vector3(30, 0, 0), true)
	await _brawl(origin + Vector3(-30, 0, 0))
	for t in [&"wraith", &"thrall", &"boss_form"]:
		await _duel("%s vs holy knight" % t, 1, t, -1, &"holy_knight", origin + Vector3(0, 0, 0.5), false)
	await _duel("player 1 vs player 2", 1, &"skeleton", 2, &"skeleton", origin + Vector3(0, 0, 0.5), false)
	await _capture_stalemate(origin)
	await _paladin(origin + Vector3(0, 0, 0.5))
	await _duel("skeleton vs villager", 1, &"skeleton", -1, &"villager", origin + Vector3(0, 0, 0.5), false)

func _brawl(at: Vector3) -> void:
	var side_a: Array[MinionActor] = []
	var side_b: Array[MinionActor] = []
	for i in 8:
		side_a.append(await _spawn(1, &"skeleton", at + Vector3(0, 0, i * 1.2)))
		side_b.append(await _spawn(-1, &"holy_knight", at + Vector3(3, 0, i * 1.2)))
	await seconds(40.0)
	var alive_a := 0
	var alive_b := 0
	for m in side_a:
		if is_instance_valid(m) and m.hp > 0:
			alive_a += 1
			print("    A ", m.name, " ", m._state_machine.state, " hp ", m.hp)
	for m in side_b:
		if is_instance_valid(m) and m.hp > 0:
			alive_b += 1
			print("    B ", m.name, " ", m._state_machine.state, " hp ", m.hp)
	check(alive_a == 0 or alive_b == 0, "brawl 8v8 ends (%d vs %d left)" % [alive_a, alive_b])

func _flat_y(p: Vector3) -> Vector3:
	return Vector3(p.x, p.y + 1.0, p.z)

func _spawn(owner_id: int, type: StringName, pos: Vector3) -> MinionActor:
	var id: int
	if owner_id > 0:
		id = mm.spawn_unit_for_peer(owner_id, type, pos)
	else:
		id = mm.spawn_neutral_minion(pos, type, pos)
	await frames(5)
	return mm.get_minion_by_id(id)

func _duel(label: String, owner_a: int, type_a: StringName, owner_b: int, type_b: StringName, at: Vector3, stale_flags: bool) -> void:
	var a := await _spawn(owner_a, type_a, at)
	var b := await _spawn(owner_b, type_b, at + Vector3(2.5, 0, 0))
	if a == null or b == null:
		check(false, "%s: both spawn" % label)
		return
	var hp_a := a.hp
	var hp_b := b.hp
	if stale_flags:
		a.capture_mode = false
		a.parley_mode = false
	await seconds(20.0)
	var a_alive := is_instance_valid(a) and a.hp > 0
	var b_alive := is_instance_valid(b) and b.hp > 0
	var hurt := (not a_alive or a.hp < hp_a) or (not b_alive or b.hp < hp_b)
	check(hurt, "%s: someone is hurt (a %s, b %s)" % [label, a.hp if is_instance_valid(a) else "dead", b.hp if is_instance_valid(b) else "dead"])
	check(not (a_alive and b_alive), "%s: someone dies" % label)
	for m in [a, b]:
		if is_instance_valid(m):
			mm.despawn_minion(m)
	await frames(5)

func _paladin(at: Vector3) -> void:
	var avatar := get_tree().current_scene.get_node("World/Avatar") as AvatarActor
	var ai_driver := avatar.avatar_input.ai_driver
	var waited := 0.0
	while avatar.hp <= 0 and waited < 40.0:  # Earlier fights may have felled him; he recovers.
		await seconds(2.0)
		waited += 2.0
	var skel := await _spawn(1, &"skeleton", at)
	var knight := await _spawn(-1, &"holy_knight", at + Vector3(40, 0, 0))
	avatar.global_position = at + Vector3(2.5, 0, 0)
	var hp := avatar.hp
	await seconds(20.0)
	check(not is_instance_valid(skel) or skel.hp <= 0 or avatar.hp < hp, "the Paladin and a player's unit hurt each other (skeleton %s, Paladin %d/%d)" % [skel.hp if is_instance_valid(skel) else "dead", avatar.hp, hp])
	for m in [skel, knight]:
		if is_instance_valid(m):
			mm.despawn_minion(m)

func _capture_stalemate(origin: Vector3) -> void:
	## A group out to take captives hits humans only down to 1 HP. It must then
	## leave them be, not swing at a human it can never kill (or never take).
	var at := origin + Vector3(0, 0.5, 0.5)  # was the world origin, on the old 300 m map's flat ground
	# Keep the Paladin out of it: he would join whichever fight is nearest.
	var avatar := get_tree().current_scene.get_node("World/Avatar") as AvatarActor
	var ai_driver := avatar.avatar_input.ai_driver
	avatar.avatar_input.ai_driver = null
	avatar.global_position = at + Vector3(80, 0, 0)
	for case in [[&"noble", "a noble"], [&"villager", "a villager"], [&"holy_knight", "a soldier"]]:
		var a := await _spawn(1, &"wraith", at)
		var b := await _spawn(-1, case[0], at + Vector3(2.5, 0, 0))
		a.capture_mode = true
		a.max_hp_value = 9999  # Survives a soldier's counterblows; this is about the clamp.
		a.hp = 9999
		await seconds(25.0)
		check(is_instance_valid(b) and b.hp >= 1, "capture mode never kills %s (hp %s)" % [case[1], b.hp if is_instance_valid(b) else "dead"])
		# A swing already under way finishes first; give it a moment to end.
		var grace := 0.0
		while a._state_machine.state == &"AttackState" and is_instance_valid(b) and b.hp <= 1 and grace < 3.0:
			await seconds(0.25)
			grace += 0.25
		var swinging: bool = a._state_machine.state == &"AttackState" and is_instance_valid(b) and b.hp <= 1
		check(not swinging, "capture mode: no endless swinging at %s (wraith %s)" % [case[1], a._state_machine.state])
		for m in [a, b]:
			if is_instance_valid(m):
				mm.despawn_minion(m)
		await frames(5)
	avatar.avatar_input.ai_driver = ai_driver
