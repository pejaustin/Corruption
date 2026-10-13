extends "res://tests/support/stage_test.gd"

## Points of interest (Austin, 2026-10-12): temples (the Paladin's dungeon shortcut, the
## Goddess's forces returning), runestones (power won once per round) and burial grounds
## (mined by whoever holds the parent site).

const SITE := preload("res://scenes/sites/corruption_site.tscn")
const BURIAL := preload("res://scenes/sites/burial_ground.tscn")
const TEMPLE_TYPE := preload("res://data/sites/temple.tres")
const RUNESTONE_TYPE := preload("res://data/sites/runestone.tres")

func _site(type: SiteType) -> CorruptionSite:
	var site := SITE.instantiate() as CorruptionSite
	site.site_type = type
	stage.add_child(site)
	site.set_physics_process(false)
	return site

func test_temple_types_hold_a_dungeon_and_runestones_an_arena() -> void:
	assert_eq(TEMPLE_TYPE.poi_kind, SiteType.PoiKind.TEMPLE)
	assert_eq(TEMPLE_TYPE.encounter, SiteType.Encounter.DUNGEON)
	assert_eq(RUNESTONE_TYPE.poi_kind, SiteType.PoiKind.RUNESTONE)
	assert_eq(RUNESTONE_TYPE.encounter, SiteType.Encounter.ARENA)

func test_a_temple_raises_its_holders_paladin_control() -> void:
	var temple := _site(TEMPLE_TYPE)
	assert_eq(PaladinHold.control_sites(1), 0)
	temple._change_holder(1)
	assert_eq(PaladinHold.control_sites(1), 1)

func test_clearing_a_temples_dungeon_corrupts_it_at_once() -> void:
	var temple := _site(TEMPLE_TYPE)
	assert_true(temple.paladin_cleared(1))
	assert_eq(temple.holder_peer_id, 1)
	assert_false(temple.forces_present, "the Goddess's forces are gone")

func test_a_held_temple_has_nothing_to_clear() -> void:
	var temple := _site(TEMPLE_TYPE)
	temple._change_holder(1)
	assert_false(temple.paladin_cleared(2))
	assert_eq(temple.holder_peer_id, 1)

func test_the_forces_return_when_a_temple_goes_neutral() -> void:
	var temple := _site(TEMPLE_TYPE)
	temple.paladin_cleared(1)
	temple._change_holder(-1)
	assert_true(temple.forces_present)

func test_only_temples_can_be_cleared() -> void:
	var stone := _site(RUNESTONE_TYPE)
	assert_false(stone.paladin_cleared(1))

func test_the_first_runestone_winner_takes_its_power() -> void:
	var stone := _site(RUNESTONE_TYPE)
	stone.grant = &"test_power"
	watch_signals(stone)
	assert_true(stone.win_runestone(1))
	assert_true(stone.is_spent())
	assert_eq(CorruptionSite.powers_won(get_tree(), 1), [&"test_power"] as Array[StringName])
	assert_signal_emitted_with_parameters(stone, "runestone_won", [1, &"test_power"])

func test_a_spent_runestone_gives_nothing_more_this_round() -> void:
	var stone := _site(RUNESTONE_TYPE)
	stone.win_runestone(1)
	assert_false(stone.win_runestone(1))
	assert_false(stone.win_runestone(2))
	assert_eq(CorruptionSite.powers_won(get_tree(), 1).size(), 1)
	assert_true(CorruptionSite.powers_won(get_tree(), 2).is_empty())

func _burial(parent: CorruptionSite) -> BurialGround:
	var ground := BURIAL.instantiate() as BurialGround
	ground.troop_trait = &"test_trait"
	parent.add_child(ground)
	return ground

func test_the_parent_sites_holder_mines_its_burial_ground() -> void:
	var temple := _site(TEMPLE_TYPE)
	var ground := _burial(temple)
	temple._change_holder(1)
	watch_signals(ground)
	ground._on_mine()
	assert_eq(mm.get_remains(1), 1)
	assert_eq(ground.bodies_left, ground.capacity - 1)
	assert_signal_emitted_with_parameters(ground, "mined", [1, &"test_trait"])

func test_nobody_mines_under_a_neutral_parent() -> void:
	var ground := _burial(_site(TEMPLE_TYPE))
	ground._on_mine()
	assert_eq(ground.bodies_left, ground.capacity)

func test_an_empty_burial_ground_gives_nothing() -> void:
	var temple := _site(TEMPLE_TYPE)
	var ground := _burial(temple)
	temple._change_holder(1)
	ground.bodies_left = 0
	ground._on_mine()
	assert_eq(mm.get_remains(1), 0)
