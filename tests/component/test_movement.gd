extends "res://tests/support/stage_test.gd"

## Unit movement and targeting (audit 2026-10-13). Targeting is decided by calling the
## state's scan directly. The walking tests run real physics on a small baked navmesh;
## tools/gut.sh runs with --fixed-fps, so game seconds pass faster than real ones.

var _default_rate: int

func before_each() -> void:
	await super()
	_default_rate = Engine.physics_ticks_per_second

func after_each() -> void:
	Engine.physics_ticks_per_second = _default_rate
	await super()

func _state(unit: MinionActor) -> MinionState:
	return unit.get_node(^"RewindableStateMachine/IdleState") as MinionState

# --- Targeting ---

func test_a_unit_picks_the_nearest_hostile() -> void:
	await add_ground()
	var skel := spawn(&"skeleton", 1)
	spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(8, 0, 0))
	var near := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(4, 0, 0))
	spawn(&"skeleton", 1, Vector3(1, 0, 0))
	assert_eq(_state(skel)._scan_for_target(), near)

func test_the_dead_are_never_picked() -> void:
	await add_ground()
	var skel := spawn(&"skeleton", 1)
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(4, 0, 0))
	knight.hp = 0
	assert_null(_state(skel)._scan_for_target())

func test_a_target_out_of_vertical_reach_is_out_of_range() -> void:
	var skel := spawn(&"skeleton", 1)
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(1, MinionState.MAX_VERTICAL_REACH + 1.0, 0))
	assert_eq(_state(skel).distance_to(knight), INF)

func test_an_unreachable_target_is_ignored_for_a_while() -> void:
	await add_ground()
	var skel := spawn(&"skeleton", 1)
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(0, 0, 10 + MinionState.MAX_NAV_GAP + 1.0))  # off the ground's edge
	assert_null(_state(skel)._scan_for_target())
	assert_true(skel.is_ignoring(knight))

func test_a_target_is_kept_between_scans() -> void:
	await add_ground()
	var skel := spawn(&"skeleton", 1)
	var far := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(8, 0, 0))
	var state := _state(skel)
	assert_eq(state.find_hostile_target(), far)
	spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(2, 0, 0))
	assert_eq(state.find_hostile_target(), far, "no rescan before SCAN_INTERVAL")

# --- Walking (real physics) ---

func _measure_speed(rate: int) -> float:
	Engine.physics_ticks_per_second = rate
	var skel := spawn_live(&"skeleton", 1, Vector3(-30, 0.5, 0))
	skel.waypoint = mm.snap_to_navmesh_point(Vector3(30, 0, 0))
	await run_physics(1.0)  # up to speed, off the spawn
	var start := skel.global_position
	await run_physics(2.0)
	assert_true(skel.velocity.is_finite() and skel.global_position.is_finite(), "finite at %d Hz" % rate)
	var moved := Vector2(skel.global_position.x - start.x, skel.global_position.z - start.z).length()
	var expected := skel.move_speed
	mm.despawn_minion(skel)
	return moved / 2.0 / expected

func test_units_walk_at_their_set_speed_at_any_physics_rate() -> void:
	await add_ground()
	for rate in [30, 60, 120]:
		var ratio := await _measure_speed(rate)
		assert_almost_eq(ratio, 1.0, 0.2, "speed / move_speed at %d Hz" % rate)

func test_a_jump_lands_where_it_aims() -> void:
	await add_ground()
	var skel := spawn_live(&"skeleton", 1, Vector3(0, 0.5, 0))
	await run_physics(0.5)
	var target := mm.snap_to_navmesh_point(skel.global_position + Vector3(6, 0, 0))
	skel.waypoint = skel.global_position
	skel.jump_target = target
	skel._state_machine.transition(&"JumpState")
	var waited := 0.0
	while skel._state_machine.state == &"JumpState" and waited < 4.0:
		await run_physics(0.1)
		waited += 0.1
	assert_lt(waited, 4.0, "the jump ends")
	assert_almost_eq(Vector2(skel.global_position.x, skel.global_position.z), Vector2(target.x, target.z), Vector2.ONE * 1.0)

func test_a_chaser_closes_and_swings_at_a_walking_target() -> void:
	await add_ground()
	var skel := spawn_live(&"skeleton", 1, Vector3(-30, 0.5, 0))
	var knight := spawn_live(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(-24, 0.5, 0))
	knight.aggro_radius = 0.0  # he only walks his waypoint
	knight.move_speed = skel.move_speed * 0.5
	knight.nav_agent.max_speed = knight.move_speed
	knight.waypoint = mm.snap_to_navmesh_point(Vector3(30, 0, 0))
	var swung := false
	var elapsed := 0.0
	while elapsed < 7.0 and not swung:
		await run_physics(0.1)
		elapsed += 0.1
		swung = skel._state_machine.state == &"AttackState"
	assert_true(swung, "swung within %.1f s" % elapsed)

func test_an_off_mesh_waypoint_settles_idle() -> void:
	await add_ground()
	var skel := spawn_live(&"skeleton", 1, Vector3(0, 0.5, 0))
	await run_physics(0.5)
	skel.waypoint = mm.snap_to_navmesh_point(Vector3(14, 0, 0)) + Vector3(0, 4, 0)
	var changes := 0
	var last: StringName = skel._state_machine.state
	for i in 90:
		await run_physics(0.1)
		if skel._state_machine.state != last:
			changes += 1
			last = skel._state_machine.state
	assert_lt(changes, 4, "no Idle <-> Chase flipping")
	assert_eq(last, &"IdleState")
