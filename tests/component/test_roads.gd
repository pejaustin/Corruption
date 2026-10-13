extends "res://tests/support/stage_test.gd"

## Orders follow roads (Austin, 2026-10-13): a Road is a Path3D between two map points; an ordered group walks every
## point of each road on its way, and a courier travels by road too. Three points in a row, A - B - C, joined by two
## roads drawn with a few curve points each (B to C is drawn from C, so it is walked backwards).

const ROAD := preload("res://scenes/map/road.tscn")

var a: MapPoint
var b: MapPoint
var c: MapPoint

func before_each() -> void:
	await super()
	a = _point(&"A", Vector3(0, 0, 0))
	b = _point(&"B", Vector3(40, 0, 0))
	c = _point(&"C", Vector3(40, 0, 30))
	_road(a, b, [Vector3(0, 0, 0), Vector3(15, 0, 5), Vector3(30, 0, 5), Vector3(40, 0, 0)])
	_road(c, b, [Vector3(40, 0, 30), Vector3(45, 0, 15), Vector3(40, 0, 0)])

func after_each() -> void:
	KnowledgeManager.INSTANT_COMMANDS = false
	KnowledgeManager.reset()
	await super()

func _point(id: StringName, at: Vector3) -> MapPoint:
	var p := MapPoint.new()
	p.name = String(id)
	p.point_id = id
	p.position = at
	stage.add_child(p)
	return p

func _road(from: MapPoint, to: MapPoint, points: Array[Vector3]) -> Road:
	var road := ROAD.instantiate() as Road
	road.from_point = from
	road.to_point = to
	road.curve = Curve3D.new()
	for p in points:
		road.curve.add_point(p)
	stage.add_child(road)
	return road

const A_TO_C: Array[Vector3] = [Vector3(0, 0, 0), Vector3(15, 0, 5), Vector3(30, 0, 5), Vector3(40, 0, 0), Vector3(45, 0, 15), Vector3(40, 0, 30)]

func test_the_way_by_road_is_every_curve_point_of_each_road_in_turn() -> void:
	var way := RoadGraph.plan(get_tree(), a, c)
	assert_eq(way["points"], [&"A", &"B", &"C"] as Array[StringName])
	assert_eq(way["route"], A_TO_C)

func test_an_ordered_group_walks_the_road_point_by_point() -> void:
	KnowledgeManager.INSTANT_COMMANDS = true
	var unit := spawn(&"skeleton", 1, a.position)
	var g := gm.create_group(1, [unit.name.to_int()] as Array[int])
	var way := RoadGraph.plan(get_tree(), a, c)
	KnowledgeManager.request_dispatch({"group_ids": [g.id], "believed": {}, "route_points": way["points"], "route": way["route"],
		"paths": {g.id: way["points"]}, "routes": {g.id: way["route"]}, "dest_point": &"C", "goal": OrderGoal.Goal.GO_HERE})
	var walked: Array[Vector3] = []
	while g.current_waypoint() != Vector3.INF and walked.size() < 20:
		walked.append(g.current_waypoint())
		unit.global_position = g.current_waypoint()
		gm._tick_group(g, GroupManager.TICK_INTERVAL)
	assert_eq(walked, A_TO_C)

func test_a_courier_walks_the_road_to_each_stop() -> void:
	var legs: Array[Dictionary] = [{"source_pos": Vector3(41, 0, 29), "search": [], "sub_orders": [{"group_id": 1}]}]
	var stops := KnowledgeManager._by_road(Vector3(1, 0, 0), legs)
	var at: Array[Vector3] = []
	for leg in stops:
		at.append(leg["source_pos"])
	assert_eq(at, A_TO_C + [Vector3(41, 0, 29)] as Array[Vector3])
	assert_true(stops[0].get("via", false) and not stops[stops.size() - 1].get("via", false))
