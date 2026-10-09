extends "res://tools/tests/test_base.gd"

## Troops and goods (GDD §5–§6): carrying the dead home to raise them,
## hauling goods into the treasury (and the ledger), capturing a live human
## for a thrall at a corrupted chapel, buying a noble with goods and a
## promise, and breaking that promise.

var mm: MinionManager
var gm: GroupManager

func run_tests() -> void:
	var world := await load_world()
	mm = world.get_node("MinionManager") as MinionManager
	gm = world.get_node("GroupManager") as GroupManager
	KnowledgeManager.INSTANT_COMMANDS = true
	Engine.time_scale = 6.0
	await seconds(8.0)  # Let the host bake the world navmesh.
	var g := gm.get_groups_for(1)[0]

	# The village's soldiers would fight the group; this test is about carrying.
	for m in mm.get_all_minions():
		if m.minion_type_id == &"holy_knight":
			mm.despawn_minion(m)
	# The dead.
	var villager := _first_human(&"SettlementSE", false)
	check(villager != null, "the south-east village has villagers")
	villager.last_hit_by = 1
	villager.take_damage(999)
	await seconds(1.0)
	check(mm.get_bodies().size() >= 1, "a killed human leaves a body")
	_order(g, &"SettlementSE", OrderGoal.Goal.GATHER_DEAD)
	var remains_before := mm.get_remains(1)
	await _until(func() -> bool: return mm.get_remains(1) > remains_before, 240.0)
	check(mm.get_remains(1) > remains_before, "the group carries the body home as remains")

	# Goods.
	var mine := world.get_node("World/Places/MineSE") as ResourceSite
	mine.pile = 30.0
	_order(g, &"MineSE", OrderGoal.Goal.HAUL)
	await _until(func() -> bool: return mm.get_treasury(1) > 0, 240.0)
	check(mm.get_treasury(1) > 0, "hauled goods reach the treasury (%d)" % mm.get_treasury(1))
	check(KnowledgeManager.local_model().ledger.has(&"MineSE"), "the ledger has a report on the mine")

	# A live captive for a thrall (earlier fighting may have thinned the village).
	_add_villagers(world, 2)
	(world.get_node("SiteChapel") as CorruptionSite).debug_give_to(1)
	_order(g, &"SettlementSE", OrderGoal.Goal.CAPTURE)
	await _until(func() -> bool: return _count_type(1, &"thrall") > 0, 300.0)
	check(_count_type(1, &"thrall") > 0, "a captive brought to the chapel becomes a thrall")

	# Buying a noble.
	mm.add_treasury(1, 40)
	g = _group_at_home()
	_order(g, &"SettlementSE", OrderGoal.Goal.OFFER, &"spare")
	var noble := _first_human(&"SettlementSE", true)
	if noble == null:
		# The earlier fighting may have killed the village's noble: it gets another.
		var village := world.get_node("World/Places/SettlementSE") as Node3D
		var nid := mm.spawn_neutral_minion(village.global_position + Vector3.UP, &"noble", village.global_position)
		noble = mm.get_minion_by_id(nid)
		noble.settlement_name = &"SettlementSE"
	await _until(func() -> bool: return noble and noble.owner_peer_id == 1, 300.0)
	check(noble != null and noble.owner_peer_id == 1, "goods and a promise buy the noble")

	# Breaking the promise.
	_add_villagers(world, 1)
	var other := _first_human(&"SettlementSE", false)
	if other:
		other.last_hit_by = 1
		other.take_damage(999)
		await seconds(1.0)
	check(noble != null and noble.owner_peer_id == -1, "killing their people turns the noble back")
	Engine.time_scale = 1.0
	KnowledgeManager.INSTANT_COMMANDS = false

func _add_villagers(world: Node, n: int) -> void:
	var village := world.get_node("World/Places/SettlementSE") as Node3D
	for i in n:
		var id := mm.spawn_neutral_minion(village.global_position + Vector3(i, 1, 0), &"villager", village.global_position)
		var m := mm.get_minion_by_id(id)
		if m:
			m.settlement_name = &"SettlementSE"

func _order(g: UnitGroup, point: StringName, goal: int, promise: StringName = &"") -> void:
	var p := MapPoint.find(get_tree(), point)
	KnowledgeManager.request_dispatch({"group_ids": [g.id], "believed": {}, "route_points": [point],
		"route": [p.global_position], "dest_point": point, "goal": goal, "promise": promise})

func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while t < limit and not cond.call():
		await seconds(2.0)
		t += 2.0

func _first_human(settlement: StringName, noble: bool) -> MinionActor:
	for m in mm.get_all_minions():
		if m.settlement_name == settlement and m.is_noble == noble and m.is_human and m.owner_peer_id <= 0 and m.can_take_damage() and m.attack_damage == 0:
			return m
	return null

func _count_type(peer: int, type_id: StringName) -> int:
	var n := 0
	for m in mm.get_minions_for_player(peer):
		if m.minion_type_id == type_id:
			n += 1
	return n

func _group_at_home() -> UnitGroup:
	var best: UnitGroup = null
	for g in gm.get_groups_for(1):
		if best == null or gm.get_members(g).size() > gm.get_members(best).size():
			best = g
	return best
