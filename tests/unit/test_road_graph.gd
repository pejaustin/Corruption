extends GutTest

## Orders follow roads (Austin, 2026-10-13): the shortest way by road between two map points, a road costing its
## length. Pure RoadGraph (bare edges), no scene tree.

var graph: RoadGraph

func before_each() -> void:
	# Naf Ishun - its road - Forest Ruins - Hopes Gate, and a long way round from the road to Hopes Gate.
	graph = RoadGraph.new()
	graph.add_edge(&"Tower", &"Road", 200.0)
	graph.add_edge(&"Road", &"Ruins", 300.0)
	graph.add_edge(&"Ruins", &"Gate", 500.0)
	graph.add_edge(&"Road", &"Far", 700.0)
	graph.add_edge(&"Far", &"Gate", 700.0)

func test_the_shortest_way_passes_the_town_in_the_middle() -> void:
	assert_eq(graph.shortest_points(&"Tower", &"Gate"), [&"Tower", &"Road", &"Ruins", &"Gate"] as Array[StringName])

func test_roads_go_both_ways() -> void:
	assert_eq(graph.shortest_points(&"Gate", &"Tower"), [&"Gate", &"Ruins", &"Road", &"Tower"] as Array[StringName])

func test_a_way_avoids_the_points_it_may_not_use() -> void:
	var unknown := func(id: StringName) -> bool: return id != &"Ruins"
	assert_eq(graph.shortest_points(&"Tower", &"Gate", unknown), [&"Tower", &"Road", &"Far", &"Gate"] as Array[StringName])

func test_no_road_no_way() -> void:
	graph.add_edge(&"Island", &"Rock", 10.0)
	assert_eq(graph.shortest_points(&"Tower", &"Island"), [] as Array[StringName])
	var nowhere := func(id: StringName) -> bool: return id == &"Tower"
	assert_eq(graph.shortest_points(&"Tower", &"Gate", nowhere), [] as Array[StringName])

func test_a_point_to_itself_is_just_that_point() -> void:
	assert_eq(graph.shortest_points(&"Ruins", &"Ruins"), [&"Ruins"] as Array[StringName])
	assert_eq(graph.shortest_legs(&"Ruins", &"Ruins"), [] as Array[Dictionary])

func test_legs_say_which_way_each_road_is_walked() -> void:
	var legs := graph.shortest_legs(&"Gate", &"Road")
	assert_eq(legs.size(), 2)
	assert_eq([legs[0]["from"], legs[0]["to"], legs[0]["forward"]], [&"Gate", &"Ruins", false])
	assert_eq([legs[1]["from"], legs[1]["to"], legs[1]["forward"]], [&"Ruins", &"Road", false])
