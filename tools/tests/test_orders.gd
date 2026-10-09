extends "res://tools/tests/test_base.gd"

## Orders and information (GDD §3–§4): a group is selected on the floor map,
## a route walked, a destination picked, the scroll handed to the advisor,
## a courier carries it, the group corrupts the site, and the courier brings
## the news home. A courier sent alone discovers an unknown point.

func run_tests() -> void:
	var world := await load_world()
	var mm := world.get_node("MinionManager") as MinionManager
	var gm := world.get_node("GroupManager") as GroupManager
	await seconds(1.0)
	var groups := gm.get_groups_for(1)
	check(groups.size() == 1 and gm.get_members(groups[0]).size() == MatchConfig.STARTING_GROUP_SIZE, "start: one group of %d" % MatchConfig.STARTING_GROUP_SIZE)
	check(KnowledgeManager.get_couriers_home(1) == MatchConfig.STARTING_COURIERS, "start: %d couriers at home" % MatchConfig.STARTING_COURIERS)
	var model := KnowledgeManager.local_model()
	check(model.is_point_known(&"Chapel") and not model.is_point_known(&"Ford"), "start: chapel known, ford not")
	await seconds(2.5)
	var g := groups[0]
	check(model.believed_groups.has(g.id), "the tower sees the group at its gate")

	# Author the order on the floor.
	var floor_map := _my_floor(world)
	check(floor_map != null, "my tower has a map floor")
	floor_map.toggle_group(g.id)
	check(floor_map.authoring, "selecting a piece starts an order")
	floor_map.path_points.append(&"RoadEast")
	var player := floor_map.local_player()
	floor_map.finish_at(MapPoint.find(get_tree(), &"Chapel"))
	check(player.is_holding_order(), "picking the destination puts a scroll in hand")
	var order := player.take_order()
	order["goal"] = OrderGoal.Goal.CORRUPT
	var cmd := KnowledgeManager.request_dispatch(order)
	check(model.orders[cmd]["stage"] == &"dispatched", "the advisor dispatches it with a courier")
	check(KnowledgeManager.get_couriers_home(1) == MatchConfig.STARTING_COURIERS - 1, "the courier leaves the pool")

	Engine.time_scale = 6.0
	var chapel := world.get_node("SiteChapel") as CorruptionSite
	var t := 0.0
	while t < 120.0 and not g.has_order():
		await seconds(1.0)
		t += 1.0
	check(g.has_order() and g.get_goal() == OrderGoal.Goal.CORRUPT, "the courier delivers the order (%.0fs)" % t)
	t = 0.0
	while t < 200.0 and chapel.holder_peer_id != 1:
		await seconds(2.0)
		t += 2.0
	check(chapel.holder_peer_id == 1, "the group takes the chapel (%.0fs)" % t)
	t = 0.0
	while t < 120.0 and KnowledgeManager.get_couriers_home(1) < MatchConfig.STARTING_COURIERS:
		await seconds(1.0)
		t += 1.0
	check(KnowledgeManager.get_couriers_home(1) == MatchConfig.STARTING_COURIERS, "the courier comes home (%.0fs)" % t)
	check(model.orders[cmd]["stage"] == &"delivered", "its report confirms the delivery")

	# A courier alone, sent past the unknown ford and back.
	var scout := {"group_ids": [], "believed": {}, "route_points": [&"RoadEast", &"Ford"],
		"route": [MapPoint.find(get_tree(), &"RoadEast").global_position, MapPoint.find(get_tree(), &"Ford").global_position],
		"dest_point": &"Ford", "dest_kind": MapPoint.Kind.CROSSING, "goal": OrderGoal.Goal.SCOUT}
	KnowledgeManager.request_dispatch(scout)
	t = 0.0
	while t < 200.0 and not model.is_point_known(&"Ford"):
		await seconds(2.0)
		t += 2.0
	check(model.is_point_known(&"Ford"), "a scouting courier puts the ford on the map (%.0fs)" % t)
	Engine.time_scale = 1.0

func _my_floor(world: Node) -> MapFloor:
	for t in world.get_node("World/Env/Towers").get_children():
		if t is Tower and (t as Tower).owner_peer_id == 1:
			return t.get_node_or_null("MapFloor") as MapFloor
	return null
