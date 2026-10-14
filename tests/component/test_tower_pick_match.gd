extends "res://tests/support/stage_test.gd"

## From the lobby's picks to the match: the Lobby enforces them, GameState carries them, the seats take the
## picked towers, and a tower nobody picked is left out (TowerPicks.remove_unpicked).

const LOBBY := preload("res://scenes/menus/lobby.tscn")
const HOST_PEER := 1
const CPU_PEER := 9001

func _tower(slot: int) -> Tower:
	var tower := add_tower(0)
	tower.slot_index = slot
	return tower

func _lobby_with_a_cpu() -> Lobby:
	var lobby := LOBBY.instantiate() as Lobby
	stage.add_child(lobby)
	lobby._add_cpu(CPU_PEER, GameConstants.PLAYABLE_FACTIONS[0], "CPU 1")
	return lobby

# --- the lobby ---

func test_two_seats_cannot_hold_one_tower() -> void:
	var lobby := _lobby_with_a_cpu()
	lobby._apply_tower(HOST_PEER, 2)
	lobby._apply_tower(CPU_PEER, 2)
	assert_eq(lobby.player_towers.get(HOST_PEER, -1), 2)
	assert_false(CPU_PEER in lobby.player_towers, "the CPU's pick of the same tower is refused")

func test_start_is_blocked_until_every_seat_has_a_tower() -> void:
	var lobby := _lobby_with_a_cpu()
	lobby._apply_tower(HOST_PEER, 0)
	lobby._apply_ready(HOST_PEER, true)
	assert_true(lobby._start_button.disabled, "the CPU has no tower")
	lobby._apply_tower(CPU_PEER, 3)
	lobby._apply_ready(HOST_PEER, true)
	assert_false(lobby._start_button.disabled, "both seats have a tower and are ready")

func test_picking_a_tower_clears_your_ready() -> void:
	var lobby := _lobby_with_a_cpu()
	lobby._apply_tower(HOST_PEER, 0)
	lobby._apply_ready(HOST_PEER, true)
	lobby._apply_tower(HOST_PEER, 1)
	assert_false(lobby.player_ready[HOST_PEER])

func test_a_departed_seat_frees_its_tower() -> void:
	var lobby := _lobby_with_a_cpu()
	lobby._apply_tower(CPU_PEER, 1)
	lobby._remove_cpu(CPU_PEER)
	lobby._apply_tower(HOST_PEER, 1)
	assert_eq(lobby.player_towers.get(HOST_PEER, -1), 1)

func test_a_late_snapshot_carries_the_picks() -> void:
	var lobby := _lobby_with_a_cpu()
	lobby._sync_all_state(lobby.player_factions.duplicate(), lobby.player_names.duplicate(), {}, {HOST_PEER: 3, CPU_PEER: 0})
	assert_eq(lobby.player_towers, {HOST_PEER: 3, CPU_PEER: 0})

# --- the match ---

func test_the_synced_picks_become_the_seats_slots() -> void:
	GameState.sync_tower_picks({HOST_PEER: 3, 2: 1})
	assert_eq(GameState.tower_picks, {HOST_PEER: 3, 2: 1})
	assert_eq(GameState.player_slots[HOST_PEER], 3)
	var manager := MultiplayerManager.new()
	assert_eq(manager.claim_slot(2), 1, "the picked tower, not the second in join order")
	assert_eq(manager.get_player_slot(HOST_PEER), 3)
	assert_eq(manager.get_next_available_slot(), -1, "no tower is left to add a player to")
	manager.free()

func test_without_picks_seats_follow_join_order() -> void:
	var manager := MultiplayerManager.new()
	assert_eq(manager.claim_slot(5), 0)
	assert_eq(manager.claim_slot(6), 1)
	manager.free()

func test_towers_nobody_picked_are_removed_with_their_gate_point() -> void:
	var towers: Array[Tower] = [_tower(0), _tower(1), _tower(2), _tower(3)]
	var points: Array[MapPoint] = []
	for slot in 4:
		var point := MapPoint.new()
		point.name = "Gate%d" % slot
		point.kind = MapPoint.Kind.TOWER
		point.tower_slot = slot
		stage.add_child(point)
		points.append(point)
	points[0].neighbors = [points[1], points[3]]
	var removed := TowerPicks.remove_unpicked(get_tree(), [0, 2] as Array[int])
	assert_eq(removed, [1, 3] as Array[int])
	var left: Array[int] = []
	for tower in Tower.in_slot_order(get_tree()):
		left.append(tower.slot_index)
	assert_eq(left, [0, 2] as Array[int], "a 2-player match stands on two towers")
	assert_eq(MapPoint.all_points(get_tree()).size(), 2, "the removed towers' gates are off the map")
	assert_true(points[0].neighbors.is_empty(), "nothing still lists a removed point as a neighbour")
	assert_true(towers[1].is_queued_for_deletion())

func test_the_match_removes_unpicked_towers_when_it_binds() -> void:
	for slot in 4:
		_tower(slot)
	GameState.tower_picks = {HOST_PEER: 1, 2: 2}
	mm._setup_minions_node()
	var left: Array[int] = []
	for tower in Tower.in_slot_order(get_tree()):
		left.append(tower.slot_index)
	assert_eq(left, [1, 2] as Array[int])

func test_with_no_picks_every_tower_stays() -> void:
	for slot in 4:
		_tower(slot)
	mm._setup_minions_node()
	assert_eq(Tower.in_slot_order(get_tree()).size(), 4)
