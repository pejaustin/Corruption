extends "res://tests/support/stage_test.gd"

## The endgame gauntlet (GDD §9), driven by calling start_gauntlet and reporting bosses dead
## to the MinionManager. Walking the Paladin in and the whole match flow are the milestone
## test (tests/integration/test_endgame.tscn).

const HOLY := preload("res://scenes/world/places/holy_site.tscn")
const SITE := preload("res://scenes/sites/corruption_site.tscn")
const RUNESTONE_TYPE := preload("res://data/sites/runestone.tres")

var holy: HolySite
var avatar: AvatarActor

func before_each() -> void:
	await super()
	for peer in [1, 2, 3]:
		GameState.player_names[peer] = "P%d" % peer
	avatar = add_avatar()
	holy = HOLY.instantiate() as HolySite
	stage.add_child(holy)
	holy.set_physics_process(false)

func _hold(peer: int, type: SiteType) -> void:
	var site := SITE.instantiate() as CorruptionSite
	site.site_type = type
	site.position = Vector3(500, 0, 0)
	stage.add_child(site)
	site.set_physics_process(false)
	site._change_holder(peer)

func _boss() -> MinionActor:
	for m in mm.get_all_minions():
		if m.minion_type_id == HolySite.BOSS_TYPE and m.hp > 0 and not m.is_queued_for_deletion():
			return m
	return null

func _beat_boss() -> void:
	var boss := _boss()
	boss.hp = 0
	mm.notify_minion_died(boss)
	await get_tree().process_frame  # the next boss comes on deferred

func test_boss_type_sites_count_for_more() -> void:
	_hold(2, SiteType.new())
	_hold(3, RUNESTONE_TYPE)
	assert_eq(HolySite.strength_of(2), HolySite.SITE_WEIGHT)
	assert_eq(HolySite.strength_of(3), HolySite.BOSS_SITE_WEIGHT)

func test_the_gauntlet_runs_weakest_first() -> void:
	_hold(2, RUNESTONE_TYPE)
	_hold(3, SiteType.new())
	assert_eq(HolySite.order_for(1), [3, 2] as Array[int])

func test_the_paladin_inside_with_his_owner_starts_the_gauntlet() -> void:
	GameState.set_avatar_owner(1)
	holy._watch_for_challenger()
	assert_eq(HolySite.state, HolySite.State.GAUNTLET)

func test_unowned_he_starts_nothing() -> void:
	holy._watch_for_challenger()
	assert_eq(HolySite.state, HolySite.State.IDLE)

func test_away_from_the_site_he_starts_nothing() -> void:
	GameState.set_avatar_owner(1)
	avatar.global_position = Vector3(holy.radius + 1.0, 0, 0)
	holy._watch_for_challenger()
	assert_eq(HolySite.state, HolySite.State.IDLE)

func test_the_weakest_rivals_boss_comes_first_scaled_by_strength() -> void:
	_hold(3, SiteType.new())
	GameState.set_avatar_owner(1)
	holy.start_gauntlet(1)
	assert_eq(HolySite.boss_peer, 2)
	assert_eq(_boss().max_hp_value, HolySite.BOSS_BASE_HP)

func test_beating_a_boss_brings_on_the_next_and_it_is_stronger() -> void:
	_hold(3, SiteType.new())
	GameState.set_avatar_owner(1)
	holy.start_gauntlet(1)
	await _beat_boss()
	assert_eq(HolySite.boss_peer, 3)
	assert_gt(_boss().max_hp_value, HolySite.BOSS_BASE_HP)

func test_beating_every_boss_wins() -> void:
	GameState.set_avatar_owner(1)
	watch_signals(GameState)
	holy.start_gauntlet(1)
	await _beat_boss()
	await _beat_boss()
	assert_signal_emitted_with_parameters(GameState, "game_won", [1])

func test_a_boss_beating_the_paladin_takes_him_home() -> void:
	var gate := Node3D.new()
	stage.add_child(gate)
	gate.position = Vector3(200, 0, 0)
	mm.bind_peer_courier_spawn(2, gate)
	GameState.set_avatar_owner(1)
	holy.start_gauntlet(1)
	avatar.take_damage(avatar.hp)
	await get_tree().process_frame  # handed over deferred, after his owner is wiped
	assert_eq(GameState.avatar_owner_peer_id, 2)
	assert_eq(HolySite.state, HolySite.State.IDLE)
	assert_null(_boss(), "the boss form is gone")
	assert_almost_eq(avatar.global_position.x, 200.0, 0.01, "he is at their tower")
	assert_false(avatar.hold.is_contested(), "no contest after a gauntlet loss")

func test_losing_his_owner_another_way_aborts() -> void:
	GameState.set_avatar_owner(1)
	holy.start_gauntlet(1)
	GameState.set_avatar_owner(2)
	holy._physics_process(0.0)
	assert_eq(HolySite.state, HolySite.State.IDLE)

func test_the_draw_locks_the_site() -> void:
	GameState.set_avatar_owner(1)
	HolySite.lock_all(get_tree())
	holy._watch_for_challenger()
	assert_eq(HolySite.state, HolySite.State.IDLE)

func test_the_draw_ends_a_running_gauntlet() -> void:
	GameState.set_avatar_owner(1)
	holy.start_gauntlet(1)
	watch_signals(holy)
	HolySite.lock_all(get_tree())
	assert_signal_emitted_with_parameters(holy, "gauntlet_ended", [&"drawn", -1])
