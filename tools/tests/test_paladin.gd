extends "res://tools/tests/test_base.gd"

## The Paladin (GDD §8): takeover by troops when he is low, the hold fading
## away from corruption, zero HP wiping his owner, control tiers, resistance,
## the unclaimed AI, overpowering, and the Palantir voice group.

func run_tests() -> void:
	var world := await load_world()
	# The Paladin is a netfox rollback actor: damage drains in its tick loop.
	if NetworkTime.has_method("start"):
		NetworkTime.start()
	await frames(10)
	var gs := GameState
	var mm := world.get_node("MinionManager") as MinionManager
	var avatar := world.get_node("World/Avatar") as AvatarActor
	var hold := avatar.hold
	var site := world.get_node("SiteAvatar") as CorruptionSite
	check(avatar != null and hold != null, "the Paladin has a hold")
	check(not gs.has_avatar_owner() and avatar.get_allegiance() == GameConstants.GOOD_SIDE, "he starts with the good faction")
	check(not avatar.is_dormant and avatar.can_take_damage(), "unowned, he is awake")
	check(avatar.get_control_level() == AvatarActor.CONTROL_LEVEL_MAX, "unowned, nothing is locked")

	# Hold him still for the takeover checks (the AI would walk him off).
	var ai_driver := avatar.avatar_input.ai_driver
	avatar.avatar_input.ai_driver = null
	Engine.time_scale = 4.0
	var here := avatar.global_position

	# Full HP: troops around him do not turn him.
	avatar.god_mode = true
	for i in 5:
		mm.spawn_unit_for_peer(1, &"", here + Vector3(2.0, 0.5, float(i) - 2.0))
	await seconds(3.0)
	check(hold.get_takeover(1) == 0.0 and not gs.has_avatar_owner(), "no takeover while he is at full HP")

	# Low HP: anyone's troops can begin turning him.
	avatar.god_mode = false
	avatar.incoming_damage += avatar.hp - int(avatar.get_max_hp() * 0.2)
	await frames(10)
	avatar.god_mode = true
	check(hold.is_low(), "damage brings him low (hp %d)" % avatar.hp)
	await seconds(3.0)
	check(hold.get_takeover(1) > 0.0, "troops near him at low HP build takeover progress (%.2f)" % hold.get_takeover(1))
	hold.takeover[1] = 0.99
	await seconds(1.5)
	check(gs.avatar_owner_peer_id == 1, "a finished takeover hands him to that player")
	await frames(10)
	check(avatar.hp == avatar.get_max_hp(), "the new owner gets him at full HP")
	for m in mm.get_minions_for_player(1):
		mm.notify_minion_died(m)
	await frames(5)

	# Control tiers: no AVATAR_CONTROL sites -> level 1, walking only.
	check(avatar.get_control_level() == 1, "owner with no control sites: level 1")
	check(avatar.can_use(AvatarActor.ACTION_WALK) and not avatar.can_use(AvatarActor.ACTION_ATTACK), "level 1 walks but cannot attack")

	# The hold fades away from his owner's corruption.
	var start_hold := hold.hold
	await seconds(2.0)
	check(hold.hold < start_hold, "away from corruption the hold fades (%.3f)" % hold.hold)
	hold.hold = 0.005
	await seconds(1.5)
	check(not gs.has_avatar_owner(), "an empty hold loses him to the good faction")

	# Near a site his owner holds, the hold stays full.
	gs.set_avatar_owner(1)
	await frames(5)
	site.global_position = avatar.global_position
	site.debug_give_to(1)
	await frames(5)
	hold.hold = 0.5
	await seconds(1.5)
	check(hold.hold == 1.0 and gs.avatar_owner_peer_id == 1, "inside a held site the hold stays full")

	# More corruption, more control.
	check(avatar.get_control_level() == 2, "one control site: level 2")
	check(avatar.can_use(AvatarActor.ACTION_ATTACK) and not avatar.can_use(AvatarActor.ACTION_RUN), "level 2 attacks but cannot run yet")

	# He resists striking the good faction at low control.
	var priest_pos := here + Vector3(0, 0.5, 30)
	mm.spawn_neutral_minion(priest_pos)
	await frames(5)
	var good: MinionActor = null
	var best := 10.0
	for m in mm.get_all_minions():
		var d := _flat(m.global_position, priest_pos)
		if m.owner_peer_id == -1 and d < best:
			best = d
			good = m
	check(good != null, "a good-faction soldier to strike")
	if good:
		var resisted: Array[bool] = [false]
		avatar.resisted.connect(func(_t: Actor) -> void: resisted[0] = true)
		var before := good.hp
		var landed := avatar.strike(good, 10)
		check(not landed and good.hp == before and resisted[0], "level 2: he resists striking the good faction")
		# A second control site (stand-in: the chapel retyped) lifts it.
		var chapel := world.get_node("SiteChapel") as CorruptionSite
		chapel.site_type = site.site_type
		chapel.debug_give_to(1)
		await frames(5)
		check(avatar.get_control_level() == 3, "two control sites: level 3")
		check(not avatar.resists_striking(good), "level 3: he strikes the good faction")

	# Zero HP wipes his corruption; he gets up where he fell.
	var fell_at := avatar.global_position
	avatar.god_mode = false
	avatar.incoming_damage += avatar.hp + 10
	await seconds(1.0)
	check(not gs.has_avatar_owner() and not gs.has_avatar(), "zero HP: the owner and controller lose him")
	check(avatar.global_position.distance_to(fell_at) < 2.0, "he is not sent home at zero HP")
	await seconds(AvatarActor.RECOVER_DELAY + 1.0)
	check(avatar.hp > 0 and avatar.hp < avatar.get_max_hp(), "he recovers in place, weak (hp %d)" % avatar.hp)

	# Unclaimed and weak, the good faction takes him home to recover.
	avatar.avatar_input.ai_driver = ai_driver
	var home := avatar.avatar_ai.get_city_centre()
	var dist_before := _flat(avatar.global_position, home)
	await seconds(4.0)
	check(avatar.avatar_ai.is_recovering(), "weak and unclaimed: he is recovering")
	check(_flat(avatar.global_position, home) < dist_before - 1.0, "he walks toward the city centre (%.1f -> %.1f)" % [dist_before, _flat(avatar.global_position, home)])
	avatar.avatar_input.ai_driver = null

	# Overpowering: more control sites than his owner, from a Palantir.
	check(hold.can_overpower(1), "two control sites outweigh the good faction's none")
	gs.request_set_watching(true)
	await frames(5)
	check(gs.is_watching(1) and 1 in gs.get_paladin_voice_peers(), "a Palantir viewer joins the voice group")
	hold.request_overpower()
	await seconds(1.0)
	check(hold.get_overpower(1) > 0.0, "the overpower runs while you look in")
	hold.overpower[1] = 0.999
	await seconds(1.5)
	check(gs.avatar_owner_peer_id == 1, "a finished overpower takes him")
	gs.request_set_watching(false)
	await frames(5)
	check(not gs.is_watching(1) and gs.get_paladin_voice_peers().is_empty(), "leaving the Palantir leaves the voice group")
	Engine.time_scale = 1.0
	if NetworkTime.has_method("stop"):
		NetworkTime.stop()

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
