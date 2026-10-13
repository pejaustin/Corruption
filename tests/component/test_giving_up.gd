extends "res://tests/support/stage_test.gd"

## Stuck never lasts forever (Austin, 2026-10-13, #626 #627): a group that gets no closer
## gives up and forms ranks; a blocked courier turns home and says why, or is reported
## lost; a courier that sees its group from afar brings back its state. Units stand still
## (physics off), which is what "walled off" looks like to the group and the courier; the
## groups are ticked with _tick_group and couriers with CourierErrand directly.

const GATE := Vector3(-30, 0, 0)

func after_each() -> void:
	KnowledgeManager.reset()
	await super()

func _group(n: int, at: Vector3, route: Array) -> UnitGroup:
	var ids: Array[int] = []
	for i in n:
		ids.append(spawn(&"skeleton", 1, at + Vector3(0, 0, i)).name.to_int())
	var g := gm.create_group(1, ids)
	gm.set_order(g.id, {"route": route, "goal": OrderGoal.Goal.GO_HERE})
	return g

func _tick(g: UnitGroup, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		gm._tick_group(g, 1.0)
		t += 1.0

func _courier(at: Vector3, sub_orders: Array, source: Vector3) -> MinionActor:
	var id := mm.spawn_named_minion_for_peer(1, &"courier", at, source)
	var c := mm.get_minion_by_id(id)
	c.set_physics_process(false)
	c.return_pos = GATE
	var legs: Array[Dictionary] = [{"source_pos": source, "search": [], "sub_orders": sub_orders}]
	c.delivery_legs = legs
	c.waypoint = source
	c._state_machine.transition(&"ChaseState")
	return c

func _errand(c: MinionActor, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		CourierErrand.tick(c, 1.0)
		t += 1.0

func _courier_records() -> Array:
	return KnowledgeManager.local_model().records.filter(func(r: Dictionary) -> bool: return r.get("kind") == &"courier")

# --- Groups ---

func test_a_walled_off_group_gives_up_and_forms_ranks_where_it_stands() -> void:
	await add_ground()  # The point is reachable on the navmesh, so only giving up stops them.
	var g := _group(3, Vector3.ZERO, [Vector3(30, 0, 0)])
	_tick(g, GroupManager.GIVE_UP_SECONDS - 2.0)
	assert_eq(g.status, &"moving", "still trying before the time is up")
	_tick(g, 3.0)
	assert_eq(g.status, &"stuck")
	for m in gm.get_members(g):
		assert_lt(Vector2(m.waypoint.x, m.waypoint.z).length(), 5.0, "ranks formed where they stand, not at the goal")
	var before: Array[Vector3] = []
	for m in gm.get_members(g):
		before.append(m.waypoint)
	_tick(g, GroupManager.STALL_SECONDS * 3.0)
	var after: Array[Vector3] = []
	for m in gm.get_members(g):
		after.append(m.waypoint)
	assert_eq(after, before, "nothing re-paths until new orders")
	var snap: Dictionary = gm.make_report(g)["groups"][0]
	assert_eq(snap["progress"], &"stuck")
	assert_ne(snap["stuck_pos"], Vector3.INF)

func test_a_fighting_group_is_not_stuck() -> void:
	var g := _group(1, Vector3.ZERO, [Vector3(30, 0, 0)])
	gm.get_members(g)[0]._state_machine.state = &"AttackState"
	_tick(g, GroupManager.GIVE_UP_SECONDS * 2.0)
	assert_ne(g.status, &"stuck")

func test_new_orders_free_a_stuck_group() -> void:
	var g := _group(1, Vector3.ZERO, [Vector3(30, 0, 0)])
	gm._halt(g)
	gm.set_order(g.id, {"route": [Vector3(-10, 0, 0)], "goal": OrderGoal.Goal.GO_HERE})
	assert_eq(g.status, &"moving")
	assert_eq(g.stuck_pos, Vector3.INF)

# --- Couriers ---

func test_a_blocked_courier_turns_home_and_says_why() -> void:
	var g := _group(1, Vector3(200, 0, 0), [Vector3(250, 0, 0)])
	var c := _courier(Vector3.ZERO, [{"group_id": g.id, "cmd_id": 5, "order": {"goal": OrderGoal.Goal.GO_HERE}}], Vector3(200, 0, 0))
	_errand(c, CourierErrand.GIVE_UP_SECONDS + 1.0)
	assert_eq(c.errand_state, &"homeward")
	assert_eq(c.waypoint, GATE)
	assert_true(c.delivery_legs.is_empty())
	KnowledgeManager.courier_arrived_home(c)
	var records := _courier_records()
	assert_eq(records.size(), 1)
	assert_string_contains(records[0]["text"], "could not reach group %d" % g.id)

func test_a_courier_that_cannot_get_home_either_is_reported_lost() -> void:
	var c := _courier(Vector3.ZERO, [], Vector3(200, 0, 0))
	c.delivery_legs.clear()
	c.waypoint = GATE
	c.carried_orders = [{"cmd_id": 9}]
	KnowledgeManager.local_model().orders[9] = {"stage": &"dispatched"}
	_errand(c, CourierErrand.GIVE_UP_SECONDS + 1.0)
	assert_eq(c.errand_state, &"stranded")
	assert_eq(c.waypoint, Vector3.ZERO, "it stops trying")
	_errand(c, CourierErrand.LOST_SECONDS + 1.0)
	assert_eq(_courier_records().size(), 1)
	assert_eq(KnowledgeManager.local_model().orders[9]["stage"], &"lost")
	_errand(c, CourierErrand.LOST_SECONDS + 1.0)
	assert_eq(_courier_records().size(), 1, "reported once")

func test_a_courier_that_sees_its_unreachable_group_brings_back_its_state() -> void:
	var g := _group(2, Vector3(20, 0, 0), [Vector3(60, 0, 0)])
	gm._halt(g)
	var model := KnowledgeManager.local_model()
	model.expect(g.id, 5, Vector3(10, 0, 0), [Vector3(60, 0, 0)], OrderGoal.Goal.GO_HERE, &"", NetworkTime.tick)
	var c := _courier(Vector3.ZERO, [{"group_id": g.id, "cmd_id": 5, "order": {"goal": OrderGoal.Goal.GO_HERE}}], Vector3(40, 0, 0))
	CourierErrand.look(c)
	assert_almost_eq(c.waypoint.x, 20.0, 1.0, "walks to where they are")
	_errand(c, CourierErrand.GIVE_UP_SECONDS + 1.0)
	assert_eq(c.errand_state, &"homeward")
	KnowledgeManager.courier_arrived_home(c)
	assert_eq(model.believed_groups[g.id]["progress"], &"stuck")
	assert_eq(model.piece_state(g.id), &"stuck")
	var text: String = _courier_records()[0]["text"]
	assert_string_contains(text, "saw group %d" % g.id)
	assert_string_contains(text, "is stuck")

func test_a_wall_hides_the_group() -> void:
	var g := _group(1, Vector3(20, 0, 0), [Vector3(60, 0, 0)])
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 6, 20)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(10, 0, 0)
	stage.add_child(wall)
	await get_tree().physics_frame
	var c := _courier(Vector3.ZERO, [{"group_id": g.id, "cmd_id": 5, "order": {"goal": OrderGoal.Goal.GO_HERE}}], Vector3(40, 0, 0))
	CourierErrand.look(c)
	assert_false(c.delivery_legs[0]["sub_orders"][0].has("seen"))

func test_seeing_the_group_is_enough_for_a_check() -> void:
	var g := _group(1, Vector3(20, 0, 0), [Vector3(60, 0, 0)])
	var c := _courier(Vector3.ZERO, [{"group_id": g.id, "cmd_id": 5, "order": {"check": true}}], Vector3(40, 0, 0))
	CourierErrand.look(c)
	assert_true(c.delivery_legs.is_empty())
	assert_eq(c.waypoint, GATE, "heads home")
	assert_eq(c.carried_report["orders"][0]["stage"], &"checked")
	assert_eq(c.carried_report["groups"][0]["progress"], &"en_route")
