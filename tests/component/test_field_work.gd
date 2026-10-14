extends "res://tests/support/stage_test.gd"

## Field work (GDD §5–§6): each fetching goal's handler run directly on a group standing at
## its destination, and unloading at home. Walking there is test_movement's; deaths are
## caused by take_damage, not by fighting.

const SITE := preload("res://scenes/sites/corruption_site.tscn")
const CHAPEL_TYPE := preload("res://data/sites/corrupted_chapel.tres")
const RESOURCE_SITE := preload("res://scenes/world/places/resource_site.tscn")

var fw: FieldWork

func before_each() -> void:
	await super()
	MatchConfig.humans_kill_only = false  # Captives, thralls and nobles are built, switched off for the MVP.
	fw = FieldWork.new()
	fw.name = "FieldWork"
	stage.add_child(fw)

func after_each() -> void:
	KnowledgeManager.reset()
	await super()

func _group(n: int, at := Vector3.ZERO, goal := OrderGoal.Goal.GO_HERE) -> UnitGroup:
	## n of player 1's skeletons in one group at `at`, ordered to work there.
	var ids: Array[int] = []
	for i in n:
		ids.append(spawn(&"skeleton", 1, at + Vector3(i * 0.5, 0, 0)).name.to_int())
	var g := gm.create_group(1, ids)
	g.order = {"route": [at], "goal": goal}
	return g

func _human(type_id: StringName, at := Vector3.ZERO) -> MinionActor:
	return spawn(type_id, GameConstants.GOOD_SIDE, at)

# --- The dead ---

func test_a_killed_human_leaves_a_body() -> void:
	var villager := _human(&"villager")
	villager.take_damage(villager.hp)
	assert_eq(mm.get_bodies().size(), 1)

func test_a_group_picks_up_bodies_at_its_destination() -> void:
	var g := _group(2, Vector3.ZERO, OrderGoal.Goal.GATHER_DEAD)
	mm.spawn_body(Vector3(0.5, 0, 0))
	assert_true(fw._gather_dead(g), "done when the bodies are taken")
	assert_eq(mm.get_bodies().size(), 0)
	var carried := gm.get_members(g).filter(func(m: MinionActor) -> bool: return m.carrying == &"body")
	assert_eq(carried.size(), 1)

func test_bodies_brought_home_become_remains() -> void:
	var g := _group(2)
	for m in gm.get_members(g):
		mm.set_carry(m, &"body")
	fw._unload(g)
	assert_eq(mm.get_remains(1), 2)
	assert_eq(gm.get_members(g)[0].carrying, &"")

func test_a_fallen_body_carrier_drops_the_body() -> void:
	var g := _group(1)
	var m := gm.get_members(g)[0]
	mm.set_carry(m, &"body")
	m.take_damage(m.hp)
	assert_eq(mm.get_bodies().size(), 1)

# --- Goods ---

func test_units_load_goods_at_a_resource_site() -> void:
	var site := RESOURCE_SITE.instantiate() as ResourceSite
	site.starting_overseers = 0
	stage.add_child(site)
	site.pile = 12
	var g := _group(2, Vector3.ZERO, OrderGoal.Goal.HAUL)
	fw._haul(g)
	var loads: Array[int] = []
	for m in gm.get_members(g):
		loads.append(m.carry_amount)
	assert_eq(loads, [FieldWork.CARRY_GOODS, FieldWork.CARRY_GOODS] as Array[int])
	assert_eq(site.get_pile(), 12 - 2 * FieldWork.CARRY_GOODS)

func test_goods_brought_home_reach_the_treasury() -> void:
	var g := _group(2)
	for m in gm.get_members(g):
		mm.set_carry(m, &"goods", 5)
	fw._unload(g)
	assert_eq(mm.get_treasury(1), 10)

func test_a_rival_who_kills_a_carrier_takes_the_goods() -> void:
	var g := _group(1)
	var carrier := gm.get_members(g)[0]
	mm.set_carry(carrier, &"goods", 5)
	var rival := spawn(&"skeleton", 2, Vector3(1, 0, 0))
	carrier.last_hit_by = 2
	carrier.take_damage(carrier.hp)
	assert_eq(rival.carrying, &"goods")
	assert_eq(rival.carry_amount, 5)

# --- Captives ---

func test_a_subdued_human_is_carried_off() -> void:
	var villager := _human(&"villager", Vector3(0.5, 0, 0))
	var g := _group(1, Vector3.ZERO, OrderGoal.Goal.CAPTURE)
	villager.hp = int(villager.get_max_hp() * FieldWork.SUBDUE_FRACTION)
	assert_true(fw._capture(g))
	assert_eq(gm.get_members(g)[0].carrying, &"captive")
	assert_true(villager.is_queued_for_deletion(), "the human left the field")

func test_nobles_are_never_captured() -> void:
	var noble := _human(&"noble", Vector3(0.5, 0, 0))
	noble.hp = 1
	var g := _group(1, Vector3.ZERO, OrderGoal.Goal.CAPTURE)
	fw._capture(g)
	assert_eq(gm.get_members(g)[0].carrying, &"")

func test_a_captive_brought_to_your_chapel_becomes_a_thrall() -> void:
	var chapel := SITE.instantiate() as CorruptionSite
	chapel.site_type = CHAPEL_TYPE
	stage.add_child(chapel)
	chapel.set_physics_process(false)
	chapel._change_holder(1)
	var g := _group(1)
	mm.set_carry(gm.get_members(g)[0], &"captive")
	fw._unload(g)
	var thralls := mm.get_minions_for_player(1).filter(func(m: MinionActor) -> bool: return m.minion_type_id == &"thrall")
	assert_eq(thralls.size(), 1)

func test_a_captive_brought_home_is_killed_for_remains() -> void:
	var g := _group(1)
	mm.set_carry(gm.get_members(g)[0], &"captive")
	fw._unload(g)
	assert_eq(mm.get_remains(1), 1)

func test_a_captive_shares_its_carriers_wounds() -> void:
	var g := _group(1)
	var carrier := gm.get_members(g)[0]
	mm.set_carry(carrier, &"captive")
	carrier.captive_hp = 10
	FieldWork.on_carrier_hit(carrier, 8)
	assert_eq(carrier.captive_hp, 10 - int(8 * FieldWork.CAPTIVE_HURT_SHARE))
	FieldWork.on_carrier_hit(carrier, 100)
	assert_eq(carrier.carrying, &"", "the captive died of them")
	assert_eq(mm.get_bodies().size(), 1)

# --- Offers ---

func _settlement_noble() -> MinionActor:
	var s := Settlement.new()
	s.name = "TestVillage"
	s.villagers = 0
	s.nobles = 0
	s.soldiers = 0
	stage.add_child(s)
	var noble := _human(&"noble", Vector3(1, 0, 0))
	noble.settlement_name = &"TestVillage"
	return noble

func test_goods_and_a_promise_buy_a_noble() -> void:
	var noble := _settlement_noble()
	var g := _group(4, Vector3.ZERO, OrderGoal.Goal.OFFER)
	g.order["promise"] = &"spare"
	for m in gm.get_members(g):
		mm.set_carry(m, &"goods", FieldWork.NOBLE_PRICE / 4)
	fw._offer(g)
	assert_eq(noble.owner_peer_id, 1)
	assert_eq(Settlement.find(get_tree(), &"TestVillage").promises.get(1), &"spare")
	for m in gm.get_members(g):
		assert_eq(m.carrying, &"", "the price is paid")

func test_too_few_goods_buy_nothing() -> void:
	var noble := _settlement_noble()
	var g := _group(1, Vector3.ZERO, OrderGoal.Goal.OFFER)
	mm.set_carry(gm.get_members(g)[0], &"goods", FieldWork.NOBLE_PRICE - 1)
	fw._offer(g)
	assert_eq(noble.owner_peer_id, -1)

func test_killing_their_people_breaks_the_promise() -> void:
	var noble := _settlement_noble()
	var g := _group(4, Vector3.ZERO, OrderGoal.Goal.OFFER)
	for m in gm.get_members(g):
		mm.set_carry(m, &"goods", FieldWork.NOBLE_PRICE / 4)
	fw._offer(g)
	var villager := _human(&"villager", Vector3(3, 0, 0))
	villager.settlement_name = &"TestVillage"
	villager.last_hit_by = 1
	villager.take_damage(villager.hp)
	assert_eq(noble.owner_peer_id, -1, "the noble turns back")

# --- MVP switch: humans are only killed (MatchConfig.humans_kill_only) ---

func test_with_the_switch_on_no_capture_or_offer_goal_is_offered() -> void:
	MatchConfig.humans_kill_only = true
	var goals := OrderGoal.goals_for(MapPoint.Kind.SETTLEMENT, true)
	assert_false(OrderGoal.Goal.CAPTURE in goals)
	assert_false(OrderGoal.Goal.OFFER in goals)
	assert_true(OrderGoal.Goal.GO_HERE in goals, "undead can still be posted")
	assert_true(OrderGoal.Goal.GO_HERE in OrderGoal.goals_for(MapPoint.Kind.RESOURCE, true))

func test_with_the_switch_on_nothing_is_captured_or_bought() -> void:
	MatchConfig.humans_kill_only = true
	var villager := _human(&"villager", Vector3(0.5, 0, 0))
	villager.hp = 1
	var g := _group(1, Vector3.ZERO, OrderGoal.Goal.CAPTURE)
	assert_true(fw._capture(g), "done at once")
	assert_eq(gm.get_members(g)[0].carrying, &"")
	var noble := _settlement_noble()
	mm.set_carry(gm.get_members(g)[0], &"goods", FieldWork.NOBLE_PRICE)
	assert_true(fw._offer(g))
	assert_eq(noble.owner_peer_id, -1)

func test_with_the_switch_on_a_work_site_needs_an_undead_overseer() -> void:
	MatchConfig.humans_kill_only = true
	var site := RESOURCE_SITE.instantiate() as ResourceSite
	stage.add_child(site)
	_human(&"villager", Vector3(1, 0, 0))
	assert_false(site.is_worked(), "a human cannot be made to work it")
	spawn(&"skeleton", 1, Vector3(2, 0, 0))
	assert_true(site.is_worked(), "one of your undead posted there does")
