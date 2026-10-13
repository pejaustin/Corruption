extends "res://tests/support/stage_test.gd"

## Avatar encounters (Austin, 2026-10-12): the temple's mini-dungeon and the runestone's
## arena duel. Foes die by being reported dead to the MinionManager, not by fighting
## (combat is test_combat's); the Paladin falls by losing his HP.

const AVATAR := preload("res://scenes/actors/player/avatar/avatar_actor.tscn")
const SITE := preload("res://scenes/sites/corruption_site.tscn")
const TEMPLE_TYPE := preload("res://data/sites/temple.tres")
const RUNESTONE_TYPE := preload("res://data/sites/runestone.tres")
const CHAPEL_TYPE := preload("res://data/sites/corrupted_chapel.tres")

var avatar: AvatarActor

func before_each() -> void:
	await super()
	var world := Node3D.new()
	world.name = "World"
	stage.add_child(world)
	avatar = AVATAR.instantiate() as AvatarActor
	avatar.name = "Avatar"
	world.add_child(avatar)
	avatar.process_mode = Node.PROCESS_MODE_DISABLED
	GameState.set_avatar_owner(1)
	GameState.request_possess_avatar()

func _site(type: SiteType, at := Vector3.ZERO) -> CorruptionSite:
	var site := SITE.instantiate() as CorruptionSite
	site.site_type = type
	site.position = at
	stage.add_child(site)
	site.set_physics_process(false)
	await get_tree().process_frame  # the encounter adds its space deferred
	return site

func _encounter(site: CorruptionSite) -> SiteEncounter:
	return site.get_node_or_null(^"Encounter") as SiteEncounter

func _kill_all(enc: SiteEncounter) -> void:
	for foe in enc.foes_alive():
		foe.hp = 0
		mm.notify_minion_died(foe)

func test_temples_have_a_3_to_5_room_dungeon() -> void:
	var enc := _encounter(await _site(TEMPLE_TYPE))
	assert_between(enc.space.room_count, 3, 5)

func test_runestones_have_a_one_room_arena() -> void:
	var enc := _encounter(await _site(RUNESTONE_TYPE))
	assert_eq(enc.space.room_count, 1)

func test_sites_without_an_encounter_drop_it() -> void:
	var chapel := await _site(CHAPEL_TYPE)
	assert_null(_encounter(chapel))

func test_he_cannot_enter_from_far_away() -> void:
	var enc := _encounter(await _site(TEMPLE_TYPE, Vector3(SiteEncounter.ENTER_RADIUS + 1.0, 0, 0)))
	assert_false(enc.try_enter(1))

func test_only_his_driver_can_take_him_in() -> void:
	var enc := _encounter(await _site(TEMPLE_TYPE))
	assert_false(enc.try_enter(2))
	GameState.request_recall_avatar()
	assert_false(enc.try_enter(1), "owned but not driven")

func test_entering_spawns_the_goddesss_forces() -> void:
	var enc := _encounter(await _site(TEMPLE_TYPE))
	assert_true(enc.try_enter(1))
	assert_true(enc.is_active())
	assert_eq(enc.foes_alive().size(), enc.space.spawns().size())
	assert_false(enc.try_enter(1), "a second entry while inside does nothing")

func test_entering_takes_him_down_to_the_space_and_leaving_brings_him_back() -> void:
	var temple := await _site(TEMPLE_TYPE, Vector3(2, 0, 0))
	var enc := _encounter(temple)
	enc.try_enter(1)
	assert_almost_eq(avatar.global_position, enc.space.entry.global_position, Vector3.ONE * 0.01)
	_kill_all(enc)
	assert_almost_eq(avatar.global_position, Vector3.ZERO, Vector3.ONE * 0.01, "back where he went in")

func test_clearing_every_foe_corrupts_the_temple() -> void:
	var temple := await _site(TEMPLE_TYPE)
	var enc := _encounter(temple)
	enc.try_enter(1)
	watch_signals(enc)
	_kill_all(enc)
	assert_false(enc.is_active())
	assert_eq(temple.holder_peer_id, 1)
	assert_signal_emitted_with_parameters(enc, "encounter_ended", [&"won", 1])
	assert_false(enc.can_enter(), "a corrupted temple has nothing to clear")

func test_one_foe_left_keeps_the_encounter_going() -> void:
	var enc := _encounter(await _site(TEMPLE_TYPE))
	enc.try_enter(1)
	var foes := enc.foes_alive()
	for i in foes.size() - 1:
		mm.notify_minion_died(foes[i])
	assert_true(enc.is_active())

func test_falling_inside_sends_him_out_and_wins_nothing() -> void:
	var temple := await _site(TEMPLE_TYPE)
	var enc := _encounter(temple)
	enc.try_enter(1)
	watch_signals(enc)
	avatar.take_damage(avatar.hp)
	await get_tree().process_frame  # the encounter finishes deferred, after his owner is wiped
	assert_false(enc.is_active())
	assert_eq(temple.holder_peer_id, -1)
	assert_signal_emitted_with_parameters(enc, "encounter_ended", [&"lost", 1])

func test_losing_him_some_other_way_aborts() -> void:
	var temple := await _site(TEMPLE_TYPE)
	var enc := _encounter(temple)
	enc.try_enter(1)
	GameState.set_avatar_owner(2)
	enc._physics_process(0.0)
	assert_false(enc.is_active())
	assert_eq(temple.holder_peer_id, -1)

func test_the_forces_return_to_a_neutral_temple() -> void:
	var temple := await _site(TEMPLE_TYPE)
	var enc := _encounter(temple)
	enc.try_enter(1)
	_kill_all(enc)
	temple._change_holder(-1)
	assert_true(enc.can_enter())
	GameState.request_possess_avatar()
	assert_true(enc.try_enter(1))
	assert_eq(enc.foes_alive().size(), enc.space.spawns().size())

func test_the_arena_holds_one_sealed_dark_lord() -> void:
	var enc := _encounter(await _site(RUNESTONE_TYPE))
	enc.try_enter(1)
	var foes := enc.foes_alive()
	assert_eq(foes.size(), 1)
	assert_eq(foes[0].minion_type.id, &"boss_form")

func test_beating_the_dark_lord_wins_the_runestone() -> void:
	var stone := await _site(RUNESTONE_TYPE)
	var enc := _encounter(stone)
	enc.try_enter(1)
	_kill_all(enc)
	assert_true(stone.is_spent())
	assert_eq(stone.runestone_winner, 1)
	assert_false(enc.can_enter(), "a spent runestone cannot be entered")
