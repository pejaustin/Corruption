extends GutTest

## Orders walk from map point to neighbouring map point (Austin, 2026-10-13): the shortest way along neighbours, a step
## costing the straight-line distance between the two points. Pure PointGraph, no scene tree.

var graph: PointGraph

func before_each() -> void:
	# Naf Ishun - its road point - Forest Ruins - Hopes Gate, and a long way round from the road point to Hopes Gate.
	graph = PointGraph.new()
	graph.add_edge(&"Tower", &"Road", 200.0)
	graph.add_edge(&"Road", &"Ruins", 300.0)
	graph.add_edge(&"Ruins", &"Gate", 500.0)
	graph.add_edge(&"Road", &"Far", 700.0)
	graph.add_edge(&"Far", &"Gate", 700.0)

func test_the_shortest_way_passes_the_point_in_the_middle() -> void:
	assert_eq(graph.shortest_points(&"Tower", &"Gate"), [&"Tower", &"Road", &"Ruins", &"Gate"] as Array[StringName])

func test_a_way_avoids_the_points_it_may_not_use() -> void:
	var unknown := func(id: StringName) -> bool: return id != &"Ruins"
	assert_eq(graph.shortest_points(&"Tower", &"Gate", unknown), [&"Tower", &"Road", &"Far", &"Gate"] as Array[StringName])

func test_no_link_no_way() -> void:
	graph.add_edge(&"Island", &"Rock", 10.0)
	assert_eq(graph.shortest_points(&"Tower", &"Island"), [] as Array[StringName])

func test_a_point_to_itself_is_just_that_point() -> void:
	assert_eq(graph.shortest_points(&"Ruins", &"Ruins"), [&"Ruins"] as Array[StringName])

func test_a_neighbour_listed_on_one_point_links_both_ways() -> void:
	var a := _point(&"A", Vector3.ZERO)
	var b := _point(&"B", Vector3(30, 0, 40))
	var c := _point(&"C", Vector3(30, 0, 100))
	a.neighbors = [b] as Array[MapPoint]
	c.neighbors = [b] as Array[MapPoint]
	var g := PointGraph.from_points([a, b, c] as Array[MapPoint])
	assert_eq(g.shortest_points(&"C", &"A"), [&"C", &"B", &"A"] as Array[StringName])
	assert_eq(g.links().size(), 2)
	for p in [a, b, c]:
		p.free()

func test_the_route_is_where_each_point_on_the_way_stands() -> void:
	var a := _point(&"A", Vector3.ZERO)
	var b := _point(&"B", Vector3(30, 0, 40))
	var c := _point(&"C", Vector3(30, 0, 100))
	b.neighbors = [a, c] as Array[MapPoint]
	var way := PointGraph.from_points([a, b, c] as Array[MapPoint]).plan_route(a, c)
	assert_eq(way["points"], [&"A", &"B", &"C"] as Array[StringName])
	assert_eq(way["route"], [Vector3.ZERO, Vector3(30, 0, 40), Vector3(30, 0, 100)] as Array[Vector3])
	for p in [a, b, c]:
		p.free()

func _point(id: StringName, at: Vector3) -> MapPoint:
	var p := MapPoint.new()
	p.point_id = id
	p.position = at
	return p
