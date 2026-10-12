extends "res://tools/tests/test_base.gd"

## Points of interest (Austin, 2026-10-12): temples raise Paladin control, the
## Paladin's dungeon shortcut, the Goddess's forces returning on purify,
## runestone powers won once per round, burial grounds mined by the parent
## site's holder, and which POIs hold a Paladin encounter.

func run_tests() -> void:
	var world := await load_world()
	var gs := GameState
	var mm := world.get_node("MinionManager") as MinionManager
	var avatar := world.get_node("World/Avatar") as AvatarActor
	var temple := world.get_node("SiteAvatar") as CorruptionSite
	var runestone := world.get_node("SiteBoss") as CorruptionSite
	check(temple.is_kind(SiteType.PoiKind.TEMPLE) and runestone.is_kind(SiteType.PoiKind.RUNESTONE), "the map has a temple and a runestone")
	check(temple.get_encounter() == SiteType.Encounter.DUNGEON, "a temple holds a mini-dungeon")
	check(runestone.get_encounter() == SiteType.Encounter.ARENA, "a runestone holds an arena duel")
	check(temple.grant != &"" and runestone.grant != &"", "each has a per-site grant (placeholder default)")
	for node in get_tree().get_nodes_in_group(Settlement.GROUP):
		check(node is Settlement, "towns stand as settlements, with no Paladin encounter")
		break

	# Temple crystals raise control of the Paladin.
	gs.set_avatar_owner(1)
	await frames(5)
	var before := avatar.get_control_level()
	temple.debug_give_to(1)
	await frames(5)
	check(avatar.get_control_level() == before + 1, "holding a temple raises his control (%d -> %d)" % [before, avatar.get_control_level()])

	# Purified back to neutral: the Goddess's forces come back.
	check(temple.paladin_cleared(1) == false, "a temple you already hold has no forces to clear")
	temple.debug_give_to(-1)
	await frames(5)
	check(temple.forces_present and not temple.is_held(), "back to neutral, the Goddess's forces return")

	# The Paladin clearing the dungeon corrupts it at once.
	gs.set_avatar_owner(1)
	check(temple.paladin_cleared(1), "the Paladin clears the temple's dungeon")
	await frames(5)
	check(temple.holder_peer_id == 1 and not temple.forces_present, "clearing it corrupts the temple at once")

	# Troops purify it: the forces return.
	Engine.time_scale = 4.0
	for m in mm.get_minions_for_player(1):
		mm.notify_minion_died(m)
	mm.spawn_neutral_minion(temple.global_position + Vector3(1, 1, 0), &"holy_knight")
	temple.progress = 0.02
	await seconds(3.0)
	check(not temple.is_held() and temple.forces_present, "purified, the temple's forces are back")
	Engine.time_scale = 1.0

	# Runestones: the first winner takes the power; then it is spent.
	check(runestone.win_runestone(1), "winning the runestone duel")
	await frames(5)
	check(runestone.is_spent() and CorruptionSite.powers_won(get_tree(), 1) == [runestone.grant], "the first winner takes its power")
	check(not runestone.win_runestone(1) and CorruptionSite.powers_won(get_tree(), 1).size() == 1, "a spent runestone gives nothing more this round")

	# Burial grounds belong to a parent site; its holder mines them.
	var crypt := temple.get_node("BurialGround") as BurialGround
	var battlefield := runestone.get_node("BurialGround") as BurialGround
	check(crypt != null and crypt.kind == BurialGround.Kind.CRYPT, "the temple has a crypt")
	check(battlefield != null and battlefield.kind == BurialGround.Kind.ANCIENT_BATTLEFIELD, "the runestone has an ancient battlefield")
	var timer := crypt.get_node("MineTimer") as Timer
	var remains_before := mm.get_remains(1)
	var traits: Array[StringName] = []
	crypt.mined.connect(func(_p: int, t: StringName) -> void: traits.append(t))
	temple.debug_give_to(1)
	await frames(5)
	timer.start(0.3)
	await seconds(1.0)
	check(mm.get_remains(1) > remains_before and traits.size() > 0 and traits[0] == crypt.troop_trait, "the temple's holder mines its crypt (%d -> %d remains)" % [remains_before, mm.get_remains(1)])
	temple.debug_give_to(-1)
	await frames(5)
	var after_lost := mm.get_remains(1)
	timer.start(0.3)
	await seconds(1.0)
	check(mm.get_remains(1) == after_lost, "nobody mines a crypt whose temple is neutral")
