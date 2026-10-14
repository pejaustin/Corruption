extends "res://tests/support/stage_test.gd"

## The endgame gauntlet (GDD §9), driven by calling start_gauntlet and killing the bosses
## (BossActors) through their own damage path. Walking the Paladin in and the whole match flow are the milestone
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

func _boss() -> BossActor:
	for child in holy.get_children():
		var boss := child as BossActor
		if boss and boss.hp > 0 and not boss.is_queued_for_deletion():
			return boss
	return null

func _start(challenger: int) -> void:
	## Start the gauntlet and let the boss's netfox nodes finish their deferred signal hookup,
	## or freeing it inside the test logs disconnect errors that GUT counts.
	holy.start_gauntlet(challenger)
	await get_tree().process_frame
	await get_tree().process_frame

func _beat_boss() -> void:
	## Lethal damage through the boss's own path (queued, applied in its rollback tick).
	var boss := _boss()
	boss.take_damage(boss.hp)
	boss._rollback_tick(0.0, 0, true)
	await get_tree().process_frame  # the next boss comes on deferred
	await free_netfox_nodes_settled()  # the dead one is freed

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
	await _start(1)
	assert_eq(HolySite.boss_peer, 2)
	assert_not_null(_boss(), "a BossActor stands in the holy site")
	assert_eq(_boss().owner_peer_id, 2)
	assert_eq(_boss().max_hp_value, HolySite.BOSS_BASE_HP)
	assert_eq(_boss().attack_damage, HolySite.BOSS_BASE_DAMAGE)

func test_the_boss_is_driven_by_its_peer_and_hostile_to_the_paladins_owner() -> void:
	GameState.set_avatar_owner(1)
	await _start(1)
	var boss := _boss()
	assert_eq(boss.boss_input.get_multiplayer_authority(), 2, "input authority is the boss's peer")
	assert_eq(boss.boss_camera.get_multiplayer_authority(), 2, "so is the camera's")
	assert_eq(boss.controlling_peer_id, 2)
	assert_eq(boss.get_allegiance(), 2)
	assert_true(boss.is_hostile_to(avatar), "hostile to the Paladin, who fights for peer 1")

func test_a_cpu_seat_gets_a_boss_the_ai_plays() -> void:
	GameState.player_names[9001] = "CPU"
	GameState.set_avatar_owner(1)
	await _start(1)
	var boss := _boss()
	for i in 3:  # the weakest first: seats 2, 3, then the CPU
		if boss.owner_peer_id == 9001:
			break
		await _beat_boss()
		boss = _boss()
	assert_eq(boss.controlling_peer_id, -1)
	assert_true(boss.boss_ai.is_driving())

func test_a_boss_whose_player_left_is_taken_over_by_the_ai() -> void:
	GameState.set_avatar_owner(1)
	await _start(1)
	holy._on_peer_disconnected(2)
	var boss := _boss()
	assert_eq(boss.controlling_peer_id, -1)
	assert_true(boss.boss_ai.is_driving())

func test_beating_a_boss_brings_on_the_next_and_it_is_stronger() -> void:
	_hold(3, SiteType.new())
	GameState.set_avatar_owner(1)
	await _start(1)
	await _beat_boss()
	assert_eq(HolySite.boss_peer, 3)
	assert_gt(_boss().max_hp_value, HolySite.BOSS_BASE_HP)

func test_beating_every_boss_wins() -> void:
	GameState.set_avatar_owner(1)
	watch_signals(GameState)
	await _start(1)
	await _beat_boss()
	await _beat_boss()
	assert_signal_emitted_with_parameters(GameState, "game_won", [1])

func test_a_boss_beating_the_paladin_takes_him_home() -> void:
	var gate := Node3D.new()
	stage.add_child(gate)
	gate.position = Vector3(200, 0, 0)
	mm.bind_peer_courier_spawn(2, gate)
	GameState.set_avatar_owner(1)
	await _start(1)
	avatar.take_damage(avatar.hp)
	await get_tree().process_frame  # handed over deferred, after his owner is wiped
	assert_eq(GameState.avatar_owner_peer_id, 2)
	assert_eq(HolySite.state, HolySite.State.IDLE)
	assert_null(_boss(), "the boss is gone")
	assert_almost_eq(avatar.global_position.x, 200.0, 0.01, "he is at their tower")
	assert_false(avatar.hold.is_contested(), "no contest after a gauntlet loss")
	await free_netfox_nodes_settled()

func test_losing_his_owner_another_way_aborts() -> void:
	GameState.set_avatar_owner(1)
	await _start(1)
	GameState.set_avatar_owner(2)
	holy._physics_process(0.0)
	assert_eq(HolySite.state, HolySite.State.IDLE)
	await free_netfox_nodes_settled()

func test_the_draw_locks_the_site() -> void:
	GameState.set_avatar_owner(1)
	HolySite.lock_all(get_tree())
	holy._watch_for_challenger()
	assert_eq(HolySite.state, HolySite.State.IDLE)

func test_the_draw_ends_a_running_gauntlet() -> void:
	GameState.set_avatar_owner(1)
	await _start(1)
	watch_signals(holy)
	HolySite.lock_all(get_tree())
	assert_signal_emitted_with_parameters(holy, "gauntlet_ended", [&"drawn", -1])
	await free_netfox_nodes_settled()
