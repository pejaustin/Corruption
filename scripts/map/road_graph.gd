class_name RoadGraph extends RefCounted

## The road network: map points joined by Road nodes (World/Roads), and the shortest way between two points by road
## (Dijkstra; a road costs its curve's length). Orders follow it (Austin, 2026-10-13): the route from Naf Ishun to
## Hopes Gate always goes through Forest Ruins, and crosses the river where the roads cross it.
## Data-only: built from the Road nodes each time a route is planned (a handful of roads).

## Points closer than this (metres) where two roads meet count as one waypoint.
const JOIN_M: float = 1.0

## point id -> Array of { to: StringName, cost: float, road: int (index into _roads, -1 for a bare edge), forward: bool }
var _edges: Dictionary[StringName, Array] = {}
var _roads: Array[Road] = []

static func from_tree(tree: SceneTree) -> RoadGraph:
	var graph := RoadGraph.new()
	for n in tree.get_nodes_in_group(Road.GROUP):
		var road := n as Road
		if road:
			graph.add_road(road)
	return graph

func add_road(road: Road) -> void:
	if road.from_point == null or road.to_point == null:
		push_warning("%s: a road needs both its From Point and To Point" % road.name)
		return
	_roads.append(road)
	_link(road.from_point.point_id, road.to_point.point_id, road.get_length(), _roads.size() - 1)

func add_edge(a: StringName, b: StringName, cost: float) -> void:
	## A road known only by its ends and length (tests, tools).
	_link(a, b, cost, -1)

func _link(a: StringName, b: StringName, cost: float, road: int) -> void:
	if not _edges.has(a):
		_edges[a] = []
	if not _edges.has(b):
		_edges[b] = []
	_edges[a].append({"to": b, "cost": cost, "road": road, "forward": true})
	_edges[b].append({"to": a, "cost": cost, "road": road, "forward": false})

func shortest_legs(from: StringName, to: StringName, usable: Callable = Callable()) -> Array[Dictionary]:
	## The roads to take, in order: { from, to, road, forward } each. Empty when from == to or there is no way.
	## `usable(point_id) -> bool` leaves out points (and so their roads), e.g. the ones a player has not discovered.
	var legs: Array[Dictionary] = []
	if from == to or not _edges.has(from) or not _edges.has(to):
		return legs
	var dist: Dictionary[StringName, float] = {from: 0.0}
	var came: Dictionary[StringName, Dictionary] = {}
	var done: Dictionary[StringName, bool] = {}
	while true:
		var here: StringName = &""
		var best := INF
		for p in dist:
			if not done.has(p) and dist[p] < best:
				best = dist[p]
				here = p
		if here == &"" or here == to:
			break
		done[here] = true
		for e in _edges[here]:
			var next: StringName = e["to"]
			if done.has(next) or (usable.is_valid() and not usable.call(next)):
				continue
			var d := best + float(e["cost"])
			if d < dist.get(next, INF):
				dist[next] = d
				came[next] = {"from": here, "to": next, "road": e["road"], "forward": e["forward"]}
	if not came.has(to):
		return legs
	var at := to
	while at != from:
		var leg: Dictionary = came[at]
		legs.push_front(leg)
		at = leg["from"]
	return legs

func shortest_points(from: StringName, to: StringName, usable: Callable = Callable()) -> Array[StringName]:
	## Every point on the way, both ends included: [from] when from == to, empty when there is no way.
	var out: Array[StringName] = []
	if from == to:
		out.append(from)
		return out
	var legs := shortest_legs(from, to, usable)
	if legs.is_empty():
		return out
	out.append(from)
	for leg in legs:
		out.append(leg["to"])
	return out

func waypoints(legs: Array[Dictionary]) -> Array[Vector3]:
	## The world points a group walks along those roads: every curve point of each, in order.
	var out: Array[Vector3] = []
	for leg in legs:
		var i := int(leg["road"])
		if i < 0:
			continue
		for p in _roads[i].waypoints(bool(leg["forward"])):
			if not out.is_empty() and out[out.size() - 1].distance_to(p) < JOIN_M:
				continue
			out.append(p)
	return out

func road_for(leg: Dictionary) -> Road:
	var i := int(leg.get("road", -1))
	return _roads[i] if i >= 0 else null

static func nearest_point(tree: SceneTree, pos: Vector3, usable: Callable = Callable()) -> MapPoint:
	## The map point closest to `pos` (flat), among the usable ones.
	var best: MapPoint = null
	var best_d := INF
	for p in MapPoint.all_points(tree):
		if usable.is_valid() and not usable.call(p.point_id):
			continue
		var d := Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = p
	return best

func plan_route(from: MapPoint, to: MapPoint, usable: Callable = Callable()) -> Dictionary:
	## The way by road from one point to another: { points: Array[StringName] (both ends included), route:
	## Array[Vector3] (the waypoints, starting at `from` and ending at `to`) }. Empty when no road leads there.
	var points := shortest_points(from.point_id, to.point_id, usable)
	if points.is_empty():
		return {}
	var route: Array[Vector3] = []
	if from != to:
		route = waypoints(shortest_legs(from.point_id, to.point_id, usable))
	if route.is_empty() or route[route.size() - 1].distance_to(to.global_position) >= JOIN_M:
		route.append(to.global_position)
	return {"points": points, "route": route}

static func plan(tree: SceneTree, from: MapPoint, to: MapPoint, usable: Callable = Callable()) -> Dictionary:
	return from_tree(tree).plan_route(from, to, usable)

static func between(tree: SceneTree, from_pos: Vector3, to_pos: Vector3) -> Array[Vector3]:
	## Waypoints by road between two places anywhere (a courier's legs): from the point nearest one to the point
	## nearest the other. Empty when they share a nearest point or no road joins them.
	var out: Array[Vector3] = []
	var a := nearest_point(tree, from_pos)
	var b := nearest_point(tree, to_pos)
	if a == null or b == null or a == b:
		return out
	var way := plan(tree, a, b)
	if way.is_empty():
		return out
	out.assign(way["route"])
	return out
