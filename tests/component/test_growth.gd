extends "res://tests/support/stage_test.gd"

## Getting better (GDD §5): leaders gain experience from kills and learn maneuvers at
## thresholds, teach them to another group (both busy), and relics are taken up, brought
## home and applied. Experience is given with _gain_experience except in the kill-credit
## tests; groups are ticked by calling _tick_group.

const RELIC_PLACE := preload("res://scenes/world/places/relic_place.tscn")

var fw: FieldWork
var gate: Node3D

func before_each() -> void:
	await super()
	fw = FieldWork.new()
	fw.name = "FieldWork"
	stage.add_child(fw)
	gate = Node3D.new()
	stage.add_child(gate)
	mm.bind_peer_courier_spawn(1, gate)

func after_each() -> void:
	KnowledgeManager.reset()
	await super()

func _group(at := Vector3.ZERO) -> UnitGroup:
	var ids: Array[int] = [spawn(&"skeleton", 1, at).name.to_int()]
	return gm.create_group(1, ids)

func _first_maneuver() -> Maneuver:
	var all := Maneuver.all()
	all.sort_custom(func(a: Maneuver, b: Maneuver) -> bool: return a.experience_required < b.experience_required)
	return all[0]

func test_maneuvers_and_relics_load_from_data() -> void:
	assert_gt(Maneuver.all().size(), 0)
	assert_gt(Relic.all().size(), 0)

# --- Experience ---

func test_a_kill_credits_the_killers_nearest_group() -> void:
	var g := _group()
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(3, 0, 0))
	knight.last_hit_by = 1
	gm._credit_kill(knight)
	assert_eq(g.experience, Training.XP_PER_KILL)

func test_a_kill_far_from_the_group_earns_nothing() -> void:
	var g := _group()
	var knight := spawn(&"holy_knight", GameConstants.GOOD_SIDE, Vector3(GroupManager.KILL_CREDIT_RADIUS + 1.0, 0, 0))
	knight.last_hit_by = 1
	gm._credit_kill(knight)
	assert_eq(g.experience, 0.0)

func test_fighting_earns_experience_over_time() -> void:
	var g := _group()
	gm.get_members(g)[0]._state_machine.state = &"AttackState"
	gm._tick_group(g, 10.0)
	assert_almost_eq(g.experience, Training.XP_PER_FIGHT_SECOND * 10.0, 0.0001)

func test_crossing_a_threshold_learns_the_maneuver_and_writes_it_down() -> void:
	var g := _group()
	var m := _first_maneuver()
	gm._gain_experience(g, m.experience_required - 0.1)
	assert_does_not_have(g.maneuvers, m.id)
	gm._gain_experience(g, 0.1)
	assert_has(g.maneuvers, m.id)
	var titles := KnowledgeManager.local_model().records.map(func(r: Dictionary) -> String: return r.get("title", ""))
	assert_has(titles, m.display_name, "the maneuver is written on the desk")

# --- Teaching ---

func _two_groups_at_home() -> Array[UnitGroup]:
	var teacher := _group(Vector3(1, 0, 0))
	var student := _group(Vector3(-1, 0, 0))
	gm._learn(teacher, _first_maneuver().id)
	return [teacher, student]

func test_a_leader_teaches_another_group_at_home() -> void:
	var pair := _two_groups_at_home()
	assert_true(gm.begin_teaching(1))
	for g in pair:
		assert_eq(g.status, &"teaching")
		assert_eq(g.busy_seconds, Training.TEACHING_SECONDS)

func test_a_busy_group_takes_no_orders() -> void:
	var pair := _two_groups_at_home()
	gm.begin_teaching(1)
	gm.set_order(pair[1].id, {"route": [Vector3(50, 0, 0)]})
	assert_false(pair[1].has_order())

func test_the_student_learns_when_the_time_is_up() -> void:
	var pair := _two_groups_at_home()
	gm.begin_teaching(1)
	for g in pair:
		gm._tick_group(g, Training.TEACHING_SECONDS)
	assert_has(pair[1].maneuvers, _first_maneuver().id)
	assert_ne(pair[1].status, &"teaching")
	assert_true(pair[0].busy_seconds <= 0.0)

func test_nobody_to_teach_nothing_happens() -> void:
	_group()
	_group(Vector3(1, 0, 0))
	assert_false(gm.begin_teaching(1))

func test_groups_away_from_home_cannot_teach() -> void:
	var teacher := _group(Vector3(MinionManager.MUSTER_RADIUS + 10.0, 0, 0))
	gm._learn(teacher, _first_maneuver().id)
	_group()
	assert_false(gm.begin_teaching(1))

# --- Relics ---

func _relic_place(relic: Relic, at := Vector3.ZERO) -> RelicPlace:
	var place := RELIC_PLACE.instantiate() as RelicPlace
	place.relic = relic
	place.position = at
	stage.add_child(place)
	return place

func test_a_group_takes_up_a_relic_where_it_lies() -> void:
	var place := _relic_place(Relic.all()[0])
	var g := _group()
	g.order = {"route": [Vector3.ZERO], "goal": OrderGoal.Goal.RETRIEVE}
	assert_true(fw._retrieve(g))
	assert_false(place.available)
	assert_eq(gm.get_members(g)[0].carrying, &"relic")

func test_a_relic_applies_its_flags() -> void:
	var relic := Relic.new()
	relic.id = &"test_relic"
	relic.display_name = "Test relic"
	relic.grants_auto_courier = true
	relic.route_point_bonus = 1
	var g := _group()
	relic.apply(1, g)
	assert_true(g.auto_courier)
	assert_eq(GameState.get_route_point_bonus(1), 1)

func test_unloading_a_relic_records_it() -> void:
	var g := _group()
	mm.set_carry(gm.get_members(g)[0], &"relic", 0)
	fw._unload(g)
	var kinds := KnowledgeManager.local_model().records.map(func(r: Dictionary) -> StringName: return r.get("kind", &""))
	assert_has(kinds, &"relic")

func test_a_fallen_carrier_drops_the_relic_back_where_it_was() -> void:
	var place := _relic_place(Relic.all()[0])
	var g := _group()
	g.order = {"route": [Vector3.ZERO], "goal": OrderGoal.Goal.RETRIEVE}
	fw._retrieve(g)
	var carrier := gm.get_members(g)[0]
	carrier.take_damage(carrier.hp)
	assert_true(place.available)
