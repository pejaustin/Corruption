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

	var chapel_pos := MapPoint.find(get_tree(), &"Chapel").global_position
	var d0 := model.group_position(g.id, KnowledgeManager.current_tick()).distance_to(chapel_pos)
	check(model.piece_state(g.id) == &"expected", "the sent order makes the piece expected, not missing")
	await seconds(3.0)
	var d1 := model.group_position(g.id, KnowledgeManager.current_tick()).distance_to(chapel_pos)
	check(d1 < d0 - 3.0 and model.piece_state(g.id) != &"missing", "the piece moves toward the destination while expected (%.0f -> %.0f m)" % [d0, d1])

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

	# Beyond the tower's range the group can still be picked and re-ordered.
	var far := gm.get_centroid(g).distance_to(floor_map.get_tower().global_position)
	await seconds(1.0)
	var piece: MapPiece = floor_map._pieces.get(g.id)
	check(piece != null and piece.is_mine(), "the group's piece is still mine and on the floor, %.0f m from the tower" % far)
	floor_map.toggle_group(g.id)
	check(floor_map.authoring, "the far group can be selected")
	floor_map.finish_at(MapPoint.find(get_tree(), &"RoadEast"))
	var again := player.take_order()
	again["goal"] = OrderGoal.Goal.GO_HERE
	var cmd2 := KnowledgeManager.request_dispatch(again)
	t = 0.0
	while t < 200.0 and model.orders[cmd2]["stage"] != &"delivered":
		await seconds(1.0)
		t += 1.0
	check(model.orders[cmd2]["stage"] == &"delivered" and g.get_goal() == OrderGoal.Goal.GO_HERE, "the far group got its new orders (%.0fs)" % t)
	t = 0.0
	while t < 120.0 and KnowledgeManager.get_couriers_home(1) < MatchConfig.STARTING_COURIERS:
		await seconds(1.0)
		t += 1.0

	# A courier sent to check reads the report and leaves the order alone.
	var issued := int(g.order.get("issued_tick", -1))
	floor_map.toggle_group(g.id)
	floor_map.finish_at(MapPoint.find(get_tree(), &"RoadEast"))
	var chk := player.take_order()
	chk["goal"] = OrderGoal.Goal.CHECK
	var cmd3 := KnowledgeManager.request_dispatch(chk)
	t = 0.0
	while t < 200.0 and model.orders[cmd3]["stage"] != &"checked":
		await seconds(1.0)
		t += 1.0
	check(model.orders[cmd3]["stage"] == &"checked", "the check's report comes home (%.0fs)" % t)
	check(int(g.order.get("issued_tick", -2)) == issued and g.get_goal() == OrderGoal.Goal.GO_HERE, "the check left the group's orders alone")
	t = 0.0
	while t < 120.0 and KnowledgeManager.get_couriers_home(1) < MatchConfig.STARTING_COURIERS:
		await seconds(1.0)
		t += 1.0

	# The group is somewhere nobody expects: the courier searches, then it is missing.
	var spot := MapPoint.find(get_tree(), &"RoadEast").global_position
	model.expect(g.id, -1, spot, [spot], OrderGoal.Goal.GO_HERE, &"RoadEast", KnowledgeManager.current_tick())
	for m in gm.get_members(g):
		m.global_position = Vector3(150, 0, -150)
		m.waypoint = m.global_position
	g.clear_order()
	floor_map.toggle_group(g.id)
	floor_map.finish_at(MapPoint.find(get_tree(), &"RoadEast"))
	var chk2 := player.take_order()
	chk2["goal"] = OrderGoal.Goal.CHECK
	KnowledgeManager.request_dispatch(chk2)
	t = 0.0
	while t < 300.0 and model.piece_state(g.id) != &"missing":
		await seconds(2.0)
		t += 2.0
	check(model.piece_state(g.id) == &"missing", "a courier that cannot find them marks the piece missing (%.0fs)" % t)
	piece = floor_map._pieces.get(g.id)
	await seconds(1.0)
	check(piece != null and piece.is_mine() and piece.belief == &"missing", "a missing piece is still mine and selectable")
	var rep := gm.make_report(g)
	rep["source"] = &"courier"
	KnowledgeManager.deliver_report(1, rep)
	check(model.piece_state(g.id) == &"confirmed", "a report of where they really are confirms the piece")
	# A report that agrees with the expectation turns missing back to confirmed.
	var fresh := WorldModel.new()
	fresh.believed_groups[7] = {"id": 7, "pos": spot, "count": 3, "goal": -1}
	fresh.expect(7, 1, spot, [spot + Vector3(100, 0, 0)], OrderGoal.Goal.GO_HERE, &"X", NetworkTime.tick)
	fresh.mark_missing(7, NetworkTime.tick)
	check(fresh.piece_state(7) == &"missing", "model: contradicted by a courier failure, missing")
	fresh.update_group({"id": 7, "pos": spot + Vector3(40, 0, 0), "count": 3, "goal": OrderGoal.Goal.GO_HERE, "obs_tick": NetworkTime.tick}, NetworkTime.tick, &"courier")
	check(fresh.piece_state(7) == &"confirmed", "model: a report on the route confirms it again")
	fresh.update_group({"id": 7, "pos": spot + Vector3(40, 0, 90), "count": 3, "goal": -1, "obs_tick": NetworkTime.tick}, NetworkTime.tick, &"courier")
	check(not fresh.expectations.has(7), "model: a report far off the route replaces the expectation")

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
	for t in Tower.in_slot_order(get_tree()):
		if t is Tower and (t as Tower).owner_peer_id == 1:
			return t.get_node_or_null("MapFloor") as MapFloor
	return null
