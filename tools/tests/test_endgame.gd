extends "res://tools/tests/test_base.gd"

## The endgame (GDD §9): the Paladin entering the holy site starts the boss
## gauntlet, weakest rival first; a boss that beats him takes him home; beating
## every boss wins; the good faction's draw locks the site.

var _outcomes: Array[StringName] = []
var _won: Array[int] = []

func run_tests() -> void:
	var world := await load_world()
	var gs := GameState
	var mm := world.get_node("MinionManager") as MinionManager
	var avatar := world.get_node("World/Avatar") as AvatarActor
	var holy := world.get_node("World/Places/HolySite") as HolySite
	check(holy != null and holy.is_in_group(HolySite.GROUP), "the holy site is in the world")
	holy.gauntlet_ended.connect(func(outcome: StringName, _p: int) -> void: _outcomes.append(outcome))
	gs.game_won.connect(func(peer: int) -> void: _won.append(peer))
	avatar.avatar_input.ai_driver = null
	for m in mm.get_all_minions():
		if m.minion_type_id == &"holy_knight":
			mm.despawn_minion(m)
	avatar.god_mode = true
	Engine.time_scale = 4.0

	# Three seats; rival 3 holds the boss site, rival 2 the chapel: 2 is weaker.
	gs.set_player_slot(1, 0)
	gs.set_player_slot(2, 1)
	gs.set_player_slot(3, 2)
	(world.get_node("SiteChapel") as CorruptionSite).debug_give_to(2)
	(world.get_node("SiteBoss") as CorruptionSite).debug_give_to(3)
	await frames(5)
	check(HolySite.strength_of(3) > HolySite.strength_of(2) and HolySite.strength_of(2) > 0.0, "boss-type sites count for more (%.1f vs %.1f)" % [HolySite.strength_of(3), HolySite.strength_of(2)])
	var expect: Array[int] = [2, 3]
	check(HolySite.order_for(1) == expect, "the gauntlet runs weakest first")
	var home := Marker3D.new()
	world.add_child(home)
	home.global_position = Vector3(60, 5, 60)
	mm.bind_peer_courier_spawn(3, home)

	# Away from the holy site, or not his owner: nothing starts.
	gs.set_avatar_owner(1)
	await frames(5)
	holy.global_position = avatar.global_position + Vector3(200, 0, 0)
	await seconds(1.0)
	check(HolySite.state == HolySite.State.IDLE, "his owner away from the holy site: no gauntlet")
	gs.set_avatar_owner(-1)
	await frames(5)
	holy.global_position = avatar.global_position
	await seconds(1.0)
	check(HolySite.state == HolySite.State.IDLE, "unowned in the holy site: no gauntlet")

	# Owned and inside: it starts with the weakest.
	gs.set_avatar_owner(1)
	await seconds(1.0)
	check(HolySite.state == HolySite.State.GAUNTLET and HolySite.boss_peer == 2, "owned and inside: the gauntlet starts with the weakest rival")
	var boss := _boss_of(mm, 2)
	check(boss != null and boss.minion_type_id == &"boss_form", "that rival's boss form stands in the holy site")
	check(boss != null and boss.max_hp_value > HolySite.BOSS_BASE_HP, "boss health grows with the sites held (%d)" % (boss.max_hp_value if boss else 0))

	# Beat the first; the next steps up, stronger.
	boss.take_damage(99999)
	await seconds(1.5)
	check(HolySite.boss_peer == 3, "beating a boss brings on the next")
	var boss3 := _boss_of(mm, 3)
	check(boss3 != null and boss3.max_hp_value > boss.max_hp_value, "the stronger rival's boss is stronger")

	# A boss beats the Paladin: he is that player's, and goes to their tower.
	avatar.god_mode = false
	avatar.incoming_damage += avatar.hp + 10
	await seconds(1.5)
	check(_outcomes.has(&"lost") and HolySite.state == HolySite.State.IDLE, "a boss beating the Paladin ends the gauntlet")
	check(gs.avatar_owner_peer_id == 3, "the winning boss's player owns him")
	check(avatar.global_position.distance_to(home.global_position) < 4.0, "he is taken to their tower")
	check(_boss_of(mm, 3) == null, "the boss form is gone with the gauntlet")
	avatar.god_mode = true
	await seconds(AvatarActor.RECOVER_DELAY + 1.0)
	check(avatar.hp > 0, "he gets up again")

	# A fresh gauntlet: the new owner brings him back to the city centre.
	avatar.god_mode = true
	holy.global_position = avatar.global_position
	await seconds(1.0)
	check(HolySite.state == HolySite.State.GAUNTLET and HolySite.boss_peer == 1, "his new owner starts a fresh gauntlet against the others")
	gs.set_avatar_owner(1)
	await seconds(1.0)
	check(_outcomes.has(&"aborted"), "losing his owner mid-gauntlet ends it (and the new owner, in the holy site, starts their own)")

	# Beating every boss wins.
	holy.global_position = avatar.global_position
	await seconds(1.0)
	var guard := 0
	while HolySite.state == HolySite.State.GAUNTLET and guard < 6:
		var b := _boss_of(mm, HolySite.boss_peer)
		if b:
			b.take_damage(99999)
		await seconds(1.5)
		guard += 1
	var expect_won: Array[int] = [1]
	check(_outcomes.has(&"won") and _won == expect_won, "beating every boss wins the match for the Paladin's owner")

	# The draw locks the site.
	var gf := world.get_node("GoodFaction") as GoodFaction
	GoodFaction.step = GoodFaction.DRAW_AT_STEP - 1
	gf._grow()
	await frames(5)
	check(holy.locked, "the good faction's draw locks the holy site")
	holy.global_position = avatar.global_position
	await seconds(1.0)
	check(HolySite.state != HolySite.State.GAUNTLET, "a locked holy site starts no gauntlet")
	Engine.time_scale = 1.0

func _boss_of(mm: MinionManager, peer: int) -> MinionActor:
	for m in mm.get_minions_for_player(peer):
		if m.minion_type_id == &"boss_form" and m.hp > 0:
			return m
	return null
