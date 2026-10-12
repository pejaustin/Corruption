extends "res://tools/tests/test_base.gd"

## Avatar encounters (Austin, 2026-10-12): the temple's mini-dungeon and the
## runestone's arena duel, entered by the possessed Paladin at the site through
## SiteEncounter.request_enter (what the interact prompt calls). Placeholder
## layouts; the rules under test are Austin's.

var world: Node
var avatar: AvatarActor
var mm: MinionManager
var home: Vector3

func run_tests() -> void:
	world = await load_world()
	NetworkTime.start()
	await frames(10)
	avatar = world.get_node("World/Avatar") as AvatarActor
	mm = world.get_node("MinionManager") as MinionManager
	home = avatar.global_position
	var temple := world.get_node("SiteAvatar") as CorruptionSite
	var runestone := world.get_node("SiteBoss") as CorruptionSite
	var temple_enc := temple.get_node_or_null("Encounter") as SiteEncounter
	var stone_enc := runestone.get_node_or_null("Encounter") as SiteEncounter
	check(temple_enc != null and stone_enc != null, "temples and runestones have an encounter door")
	for node in get_tree().get_nodes_in_group(CorruptionSite.GROUP):
		var site := node as CorruptionSite
		if site.get_encounter() == SiteType.Encounter.NONE:
			check(site.get_node_or_null("Encounter") == null, "%s has no encounter (towns, work sites, the chapel and towers have none)" % site.name)
	check(temple_enc.space.room_count >= 3 and temple_enc.space.room_count <= 5, "the dungeon has 3-5 rooms (%d)" % temple_enc.space.room_count)
	check(stone_enc.space.room_count == 1, "the arena is one room")
	await frames(5)
	check(temple_enc.space.global_position.y < -100.0 and stone_enc.space.global_position.y < -100.0, "the encounter spaces sit far below the map")

	# Possess the Paladin.
	GameState.set_avatar_owner(1)
	await frames(5)
	GameState.request_possess_avatar()
	await frames(5)
	check(GameState.is_avatar_owner(1) and GameState.is_avatar(1), "player 1 owns and drives the Paladin")
	avatar.avatar_input.ai_driver = null
	Engine.time_scale = 4.0

	# He must be at the site to enter.
	await put_avatar(runestone.global_position + Vector3(40, 1, 0))
	check(not temple_enc.try_enter(1), "he cannot enter a temple from far away")
	await put_avatar(temple.global_position + Vector3(3, 1, 0))

	# --- Temple: defeat inside a dungeon follows the Paladin's own defeat rules ---
	temple_enc.request_enter()
	await frames(5)
	check(temple_enc.is_active() and temple_enc.active_peer == 1, "E at the temple takes him into the dungeon")
	check(avatar.global_position.y < -100.0, "he stands in the dungeon, far below the map (y %.0f)" % avatar.global_position.y)
	var foes := temple_enc.foes_alive()
	check(foes.size() >= 6, "the Goddess's forces are in (%d)" % foes.size())
	check(not temple_enc.try_enter(1), "a second entry while inside does nothing")
	avatar.last_hit_by = GameConstants.GOOD_SIDE
	avatar.incoming_damage += avatar.hp + 10
	await wait_until(func() -> bool: return not temple_enc.is_active())
	check(not temple_enc.is_active(), "defeated inside, he leaves the encounter")
	check(avatar.global_position.y > -100.0 and flat_dist(avatar, temple) <= SiteEncounter.ENTER_RADIUS + 1.0, "he is carried back out to the temple")
	check(temple.holder_peer_id == -1 and temple.forces_present, "a defeat does not corrupt the temple")
	check(not GameState.has_avatar_owner(), "defeat wiped his owner (AvatarActor._die)")
	await wait_until(func() -> bool: return avatar.hp > 0, 15.0)
	check(avatar.hp > 0, "he gets up again")
	await retake_avatar()

	# --- Temple: resistance, then clearing ---
	await put_avatar(temple.global_position + Vector3(3, 1, 0))
	check(temple_enc.try_enter(1), "he enters again")
	await frames(5)
	avatar.god_mode = true
	check(avatar.get_control_level() < AvatarActor.RESIST_GOOD_BELOW_LEVEL, "with no crystals his control is low (level %d)" % avatar.get_control_level())
	var priest: MinionActor = null
	for foe in temple_enc.foes_alive():
		if foe.minion_type.id == &"priest":
			priest = foe
	check(priest != null, "the dungeon has priests")
	var before := priest.hp
	check(not avatar.strike(priest, 10) and priest.hp == before, "at low control he resists striking a priest")
	var inside := temple_enc.foes_alive().size()
	for foe in temple_enc.foes_alive():
		foe.take_damage(foe.hp + 1)
	await wait_until(func() -> bool: return not temple_enc.is_active(), 20.0)
	check(inside >= 6 and not temple_enc.is_active(), "clearing every room ends the encounter (%d enemies)" % inside)
	check(temple.holder_peer_id == 1 and not temple.forces_present, "clearing the dungeon corrupts the temple for him, and the forces are gone")
	check(avatar.global_position.y > -100.0 and flat_dist(avatar, temple) <= SiteEncounter.ENTER_RADIUS + 1.0, "he walks out at the temple")
	check(not temple_enc.can_enter() and not temple_enc.try_enter(1), "a corrupted temple has nothing to clear")

	# --- The forces come back when it returns to neutral; he can leave by losing his owner ---
	temple.debug_give_to(-1)
	await frames(5)
	check(temple.forces_present and temple_enc.can_enter(), "back to neutral, the forces return")
	await put_avatar(temple.global_position + Vector3(3, 1, 0))
	check(temple_enc.try_enter(1) and temple_enc.foes_alive().size() >= 6, "the returned forces fill the dungeon again")
	await frames(5)
	GameState.set_avatar_owner(-1)
	await wait_until(func() -> bool: return not temple_enc.is_active())
	check(not temple_enc.is_active() and avatar.global_position.y > -100.0, "losing the Paladin mid-dungeon sends him out")
	check(temple.holder_peer_id == -1, "and the temple stays neutral")
	await retake_avatar()

	# --- Runestone: an arena duel ---
	await put_avatar(runestone.global_position + Vector3(3, 1, 0))
	stone_enc.request_enter()
	await frames(5)
	check(stone_enc.is_active() and avatar.global_position.y < -100.0, "E at the runestone takes him into the arena")
	var lords := stone_enc.foes_alive()
	check(lords.size() == 1 and lords[0].minion_type.id == &"boss_form", "one sealed Dark Lord (the boss stand-in)")
	avatar.god_mode = true
	lords[0].take_damage(lords[0].hp + 1)
	await wait_until(func() -> bool: return not stone_enc.is_active(), 20.0)
	check(not stone_enc.is_active(), "beating the Dark Lord ends the duel")
	check(runestone.is_spent() and CorruptionSite.powers_won(get_tree(), 1) == [runestone.grant], "he wins the runestone's power")
	check(avatar.global_position.y > -100.0 and flat_dist(avatar, runestone) <= SiteEncounter.ENTER_RADIUS + 1.0, "he walks out at the runestone")
	check(not stone_enc.can_enter() and not stone_enc.try_enter(1), "a spent runestone cannot be entered")
	check(not runestone.win_runestone(1) and not runestone.win_runestone(2) and CorruptionSite.powers_won(get_tree(), 1).size() == 1 and CorruptionSite.powers_won(get_tree(), 2).is_empty(), "a second win gives nothing")

	# --- Losing the duel ---
	runestone.runestone_winner = -1  # the next round
	avatar.god_mode = false
	await put_avatar(runestone.global_position + Vector3(3, 1, 0))
	check(stone_enc.try_enter(1), "a fresh runestone can be entered again")
	await frames(5)
	avatar.last_hit_by = GameConstants.GOOD_SIDE
	avatar.incoming_damage += avatar.hp + 10
	await wait_until(func() -> bool: return not stone_enc.is_active())
	check(not stone_enc.is_active() and avatar.global_position.y > -100.0, "losing the duel sends him back out")
	check(not runestone.is_spent(), "and wins nothing")
	Engine.time_scale = 1.0

func flat_dist(a: Node3D, b: Node3D) -> float:
	var d := a.global_position - b.global_position
	return Vector2(d.x, d.z).length()

func put_avatar(pos: Vector3) -> void:
	avatar.pin_transform(Transform3D(Basis.IDENTITY, pos))
	await frames(10)
	avatar.unpin_transform()
	await frames(3)

func retake_avatar() -> void:
	## Back to player 1 and driving him, standing up.
	## He is moved home first: standing at a temple, the Paladin corrupts it himself.
	await wait_until(func() -> bool: return avatar.hp > 0, 15.0)
	await put_avatar(home)
	GameState.set_avatar_owner(1)
	await frames(5)
	GameState.request_possess_avatar()
	await frames(5)
	avatar.avatar_input.ai_driver = null

func wait_until(cond: Callable, timeout: float = 10.0) -> void:
	var waited := 0.0
	while not cond.call() and waited < timeout:
		await seconds(0.25)
		waited += 0.25
