extends "res://tests/support/stage_test.gd"

## Couriers walk from map point to neighbouring map point like groups (Austin, 2026-10-13): A - B - C, linked only by
## B's neighbours.

var a: MapPoint
var b: MapPoint
var c: MapPoint

func before_each() -> void:
	await super()
	a = _point(&"A", Vector3(0, 0, 0))
	b = _point(&"B", Vector3(40, 0, 0))
	c = _point(&"C", Vector3(40, 0, 30))
	b.neighbors = [a, c] as Array[MapPoint]

func _point(id: StringName, at: Vector3) -> MapPoint:
	var p := MapPoint.new()
	p.name = String(id)
	p.point_id = id
	p.position = at
	stage.add_child(p)
	return p

func test_a_courier_walks_point_to_point_to_each_stop() -> void:
	var legs: Array[Dictionary] = [{"source_pos": Vector3(41, 0, 29), "search": [], "sub_orders": [{"group_id": 1}]}]
	var stops := KnowledgeManager._by_neighbors(Vector3(1, 0, 0), legs)
	var at: Array[Vector3] = []
	for leg in stops:
		at.append(leg["source_pos"])
	assert_eq(at, [a.position, b.position, c.position, Vector3(41, 0, 29)] as Array[Vector3])
	assert_true(stops[0].get("via", false) and not stops[stops.size() - 1].get("via", false))
