extends GutTest

## The lobby's tower picks (TowerPicks): one seat per tower, every seat needs one, and the tower names come from the
## landscape scene's markers.

func test_a_tower_can_be_picked_once() -> void:
	var picks: Dictionary = {1: 2}
	assert_false(TowerPicks.can_pick(picks, 9001, 2), "a second seat can't take a held tower")
	assert_true(TowerPicks.can_pick(picks, 9001, 1))

func test_you_can_pick_your_own_tower_again_or_change_it() -> void:
	var picks: Dictionary = {1: 2}
	assert_true(TowerPicks.can_pick(picks, 1, 2))
	assert_true(TowerPicks.can_pick(picks, 1, 3))

func test_only_the_four_slots_are_towers() -> void:
	assert_false(TowerPicks.can_pick({}, 1, -1))
	assert_false(TowerPicks.can_pick({}, 1, GameConstants.MAX_PLAYERS))
	assert_true(TowerPicks.can_pick({}, 1, GameConstants.MAX_PLAYERS - 1))

func test_every_seat_needs_a_tower() -> void:
	assert_false(TowerPicks.all_picked([1, 9001], {1: 0}))
	assert_true(TowerPicks.all_picked([1, 9001], {1: 0, 9001: 3}))

func test_picked_slots_are_listed_in_order() -> void:
	assert_eq(TowerPicks.picked_slots({1: 3, 9001: 0}), [0, 3] as Array[int])

func test_tower_names_are_the_markers_names_at_every_size() -> void:
	for size in MatchConfig.LANDSCAPE_SCENES:
		var names := TowerPicks.slot_names(size)
		assert_eq(names.size(), GameConstants.MAX_PLAYERS, "four towers at size %d" % size)
	var names_2km := TowerPicks.slot_names(MatchConfig.WorldSize.NORMAL)
	assert_eq(names_2km[0], "Naf Ishun")
	assert_eq(names_2km[1], "Forest Tower")
	assert_eq(names_2km[2], "Volcano Tower")
	assert_eq(names_2km[3], "Avequel'la")
