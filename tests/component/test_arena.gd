extends GutTest

## The combat test arena (tools/arena/, #640): a round puts the right bodies in play for the
## config. Rounds are begun directly, as the offline host; no fight is simulated.

const ARENA := preload("res://tools/arena/arena.tscn")

var arena: Node3D
var _previous_scene: Node

func before_each() -> void:
	arena = ARENA.instantiate()
	_previous_scene = get_tree().current_scene
	get_tree().root.add_child(arena)
	get_tree().current_scene = arena
	arena._is_host = true
	# The floor's navmesh is baked on ready; the map takes a few physics frames to have it (and,
	# shared by every test, to drop the last arena's floor: wait for this region alone).
	var nav_map := arena.get_world_3d().navigation_map
	var region: RID = arena.get_node(^"World/Nav").get_rid()
	for i in 60:
		var regions := NavigationServer3D.map_get_regions(nav_map)
		if regions.size() == 1 and regions[0] == region and NavigationServer3D.map_get_closest_point(nav_map, Vector3(5, 0, 5)) != Vector3.ZERO:
			break
		await get_tree().physics_frame
	await get_tree().physics_frame

func after_each() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = _previous_scene
	arena.free()
	GameState.reset()

func _begin(role: ArenaConfig.Role, opponent: ArenaConfig.Opponent, level := 4, attacks: Array[BossAttack] = []) -> ArenaConfig:
	var config := ArenaConfig.new()
	config.role = role
	config.opponent = opponent
	config.control_level = level
	config.boss_attacks = attacks
	config.minion_type = &"skeleton"
	config.minion_count = 3
	arena._begin_round(config.to_dict(), -1)
	await get_tree().process_frame
	return config

func _bosses() -> Array[BossActor]:
	var found: Array[BossActor] = []
	for node in arena.get_node(^"World/Bosses").get_children():
		if node is BossActor and not node.is_queued_for_deletion():
			found.push_back(node)
	return found

func test_the_paladin_against_the_ai_boss_is_yours_at_the_chosen_level() -> void:
	await _begin(ArenaConfig.Role.PALADIN, ArenaConfig.Opponent.AI, 2)
	var avatar: AvatarActor = arena.get_node(^"World/Avatar")
	assert_eq(GameState.avatar_owner_peer_id, 1)
	assert_eq(GameState.avatar_peer_id, 1)
	assert_eq(avatar.get_control_level(), 2)
	assert_false(avatar.can_use(AvatarActor.ACTION_RUN), "level 2 walks and attacks, no more")
	var bosses := _bosses()
	assert_eq(bosses.size(), 1)
	assert_eq(bosses[0].owner_peer_id, DebugManager.DUMMY_BASE_ID, "a CPU boss: BossAI drives it")
	assert_true(bosses[0].is_hostile_to(avatar))

func test_the_boss_form_gets_only_the_chosen_attacks() -> void:
	var all := ArenaConfig.all_boss_attacks()
	assert_gt(all.size(), 1, "the arena lists the boss attacks in data/bosses/")
	await _begin(ArenaConfig.Role.BOSS, ArenaConfig.Opponent.AI, 4, [all[0]] as Array[BossAttack])
	var bosses := _bosses()
	assert_eq(bosses.size(), 1)
	assert_eq(bosses[0].owner_peer_id, 1)
	assert_eq(bosses[0].attacks.size(), 1)
	assert_eq(bosses[0].attacks[0], all[0])
	assert_eq(GameState.avatar_owner_peer_id, GameConstants.GOOD_SIDE, "the AI Paladin is the good faction's")

func test_minions_are_hostile_and_the_paladin_sits_out_a_boss_round() -> void:
	await _begin(ArenaConfig.Role.BOSS, ArenaConfig.Opponent.MINIONS)
	var avatar: AvatarActor = arena.get_node(^"World/Avatar")
	assert_false(avatar.visible)
	assert_false(avatar.can_take_damage(), "he sits the round out unhurt")
	assert_false(avatar.is_hostile_to(arena.get_node(^"MinionManager").get_all_minions()[0]), "and no foe to the minions")
	var minions: Array[MinionActor] = arena.get_node(^"MinionManager").get_all_minions()
	assert_eq(minions.size(), 3)
	for minion in minions:
		assert_eq(minion.minion_type.id, &"skeleton")
		assert_true(minion.is_hostile_to(_bosses()[0]))

func test_a_new_round_replaces_the_last_one() -> void:
	await _begin(ArenaConfig.Role.PALADIN, ArenaConfig.Opponent.MINIONS)
	await _begin(ArenaConfig.Role.PALADIN, ArenaConfig.Opponent.AI)
	assert_eq(arena.get_node(^"MinionManager").get_all_minions().filter(
		func(m: MinionActor) -> bool: return not m.is_queued_for_deletion()).size(), 0)
	assert_eq(_bosses().size(), 1)

func test_the_ai_paladin_goes_for_a_hostile_boss() -> void:
	await _begin(ArenaConfig.Role.BOSS, ArenaConfig.Opponent.AI)
	var avatar: AvatarActor = arena.get_node(^"World/Avatar")
	var boss := _bosses()[0]
	boss.global_position = avatar.global_position + Vector3(0, 0, -4)
	# The shared navigation map can lag a frame or two behind a new arena's floor (reachability is
	# checked against it), so give the pick a few physics frames.
	for i in 30:
		avatar.avatar_ai._blacklist.clear()
		avatar.avatar_ai._update_target()
		if avatar.avatar_ai._target == boss:
			break
		await get_tree().physics_frame
	assert_eq(avatar.avatar_ai._target, boss)

func test_command_line_flags_set_the_config() -> void:
	var config := ArenaConfig.new()
	config.apply_args(PackedStringArray(["--role=boss", "--level=3", "--opponent=minions", "--minion=imp", "--count=5", "--attacks=wide_sweep"]))
	assert_eq(config.role, ArenaConfig.Role.BOSS)
	assert_eq(config.control_level, 3)
	assert_eq(config.opponent, ArenaConfig.Opponent.MINIONS)
	assert_eq(config.minion_type, &"imp")
	assert_eq(config.minion_count, 5)
	assert_eq(config.boss_attacks.size(), 1)
	assert_eq(config.boss_attacks[0].resource_path.get_file(), "wide_sweep.tres")
