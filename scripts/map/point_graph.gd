class_name PointGraph extends RefCounted

## The map points joined by their neighbours (MapPoint.neighbors), and the shortest way between two points along them
## (Dijkstra; a step between two neighbours costs the straight-line distance between them). Orders follow it (Austin,
## 2026-10-13: "build a node tree of neighbors, and then the walk paths from each can be emergent"): a group walks
## from point to point, and the navmesh finds the way between each two. Links are two-way: A–B counts if either
## lists the other.
## Data-only: built from the MapPoints each time a route is planned (a handful of points).

## point id -> (neighbour id -> cost)
var _edges: Dictionary[StringName, Dictionary] = {}
## point id -> where it stands
var _spots: Dictionary[StringName, Vector3] = {}

static func from_tree(tree: SceneTree) -> PointGraph:
	return from_points(MapPoint.all_points(tree))

static func from_points(points: Array[MapPoint]) -> PointGraph:
	var graph := PointGraph.new()
	for p in points:
		graph.add_point(p.point_id, spot(p))
	for p in points:
		for n in p.neighbors:
			if n != null and n != p:
				graph.add_edge(p.point_id, n.point_id, spot(p).distance_to(spot(n)))
	return graph

static func spot(p: MapPoint) -> Vector3:
	## Where a point stands in play (a tower point on its gate once MapPoint._snap has run).
	return p.global_position if p.is_inside_tree() else p.position

func add_point(id: StringName, at: Vector3) -> void:
	_spots[id] = at
	if not _edges.has(id):
		_edges[id] = {}

func add_edge(a: StringName, b: StringName, cost: float) -> void:
	## A two-way link (listing it twice keeps one).
	for id in [a, b]:
		if not _edges.has(id):
			_edges[id] = {}
	_edges[a][b] = cost
	_edges[b][a] = cost

func is_linked(a: StringName, b: StringName) -> bool:
	return _edges.has(a) and (_edges[a] as Dictionary).has(b)

func links() -> Array[Array]:
	## Every link once, as [a, b].
	var out: Array[Array] = []
	for a in _edges:
		for b in _edges[a]:
			if String(a) < String(b):
				out.append([a, b])
	return out

func shortest_points(from: StringName, to: StringName, usable: Callable = Callable()) -> Array[StringName]:
	## Every point on the way, both ends included: [from] when from == to, empty when there is no way.
	## `usable(point_id) -> bool` leaves out points, e.g. the ones a player has not discovered.
	var out: Array[StringName] = []
	if from == to:
		out.append(from)
		return out
	if not _edges.has(from) or not _edges.has(to):
		return out
	var dist: Dictionary[StringName, float] = {from: 0.0}
	var came: Dictionary[StringName, StringName] = {}
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
		for next: StringName in _edges[here]:
			if done.has(next) or (usable.is_valid() and not usable.call(next)):
				continue
			var d := best + float(_edges[here][next])
			if d < dist.get(next, INF):
				dist[next] = d
				came[next] = here
	if not came.has(to):
		return out
	var at := to
	while at != from:
		out.push_front(at)
		at = came[at]
	out.push_front(from)
	return out

func spots_of(points: Array[StringName]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id in points:
		out.append(_spots.get(id, Vector3.ZERO))
	return out

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
	## The way from one point to another along neighbours: { points: Array[StringName] (both ends included), route:
	## Array[Vector3] (where each of those points stands, in order) }. Empty when no way leads there.
	var points := shortest_points(from.point_id, to.point_id, usable)
	if points.is_empty():
		return {}
	return {"points": points, "route": spots_of(points)}

static func plan(tree: SceneTree, from: MapPoint, to: MapPoint, usable: Callable = Callable()) -> Dictionary:
	return from_tree(tree).plan_route(from, to, usable)

static func between(tree: SceneTree, from_pos: Vector3, to_pos: Vector3) -> Array[Vector3]:
	## The points to walk between two places anywhere (a courier's legs): from the point nearest one to the point
	## nearest the other, both included. Empty when they share a nearest point or no way joins them.
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
