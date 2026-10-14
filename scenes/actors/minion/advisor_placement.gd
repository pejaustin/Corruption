extends RefCounted

## Where the advisor stands (Austin, 2026-10-09: "stand close by when the player
## is in range of any interactable"). Pure helpers used by the advisor's idle and
## follow states; the chosen spot lives in `minion.waypoint`.

## PLACEHOLDER: tuning — overlord-to-station distance that counts as "at the station".
const STATION_RANGE: float = 4.0
## PLACEHOLDER: tuning — how far from the station the advisor stands.
const STAND_OFF: float = 1.8
## PLACEHOLDER: tuning — keep this far from the overlord when picking a spot.
const MIN_FROM_OVERLORD: float = 1.6
## PLACEHOLDER: tuning — keep this far off the line between overlord and station.
const CLEAR_OF_LINE: float = 1.0
## PLACEHOLDER: tuning — keep the walk to the spot this far from the overlord, so he never walks into him and stalls.
const CLEAR_OF_WALK: float = 1.0
## PLACEHOLDER: tuning — margin around the map floor's square he never enters.
const FLOOR_MARGIN: float = 1.0
## PLACEHOLDER: tuning — at the map floor he re-picks his edge spot once the overlord is this far away.
const FLOOR_RETARGET: float = 7.0
## PLACEHOLDER: tuning — seconds before he may switch to another station.
const RETARGET_DWELL: float = 1.0
## PLACEHOLDER: tuning — arrival radius at his spot, in metres.
const ARRIVE_RADIUS: float = 0.8

static func tower_of(advisor: Node) -> Node3D:
	for t in advisor.get_tree().get_nodes_in_group(Tower.GROUP):
		if (t as Tower).advisor == advisor:
			return t as Node3D
	return null

static func map_floor(tower: Node) -> MapFloor:
	return tower.get_node_or_null("MapFloor") as MapFloor

## True when `p` is inside the floor's square plus the margin.
static func on_floor(floor_map: MapFloor, p: Vector3, extra: float = 0.0) -> bool:
	if floor_map == null:
		return false
	var l := floor_map.to_local(p)
	var h := floor_map.floor_size * 0.5 + FLOOR_MARGIN + extra
	return absf(l.x) < h and absf(l.z) < h

static func stations(tower: Node, advisor: Node) -> Array[Interactable]:
	var out: Array[Interactable] = []
	# find_children() type matching ignores script class_names, so filter by hand.
	for n in tower.find_children("*", "Area3D", true, false):
		var it := n as Interactable
		if it != null and not advisor.is_ancestor_of(it) and it.is_visible_in_tree():
			out.append(it)
	return out

static func nearest_in_range(tower: Node, advisor: Node, overlord: Node3D) -> Interactable:
	var best: Interactable = null
	var best_d := STATION_RANGE
	for it in stations(tower, advisor):
		var d := _flat(it.global_position - overlord.global_position).length()
		if d <= best_d:
			best_d = d
			best = it
	return best

static func flat_dist(a: Vector3, b: Vector3) -> float:
	return _flat(a - b).length()

static func _flat(v: Vector3) -> Vector3:
	v.y = 0.0
	return v

static func _snap(advisor: Node3D, p: Vector3) -> Vector3:
	var nmap := advisor.get_world_3d().navigation_map
	if not nmap.is_valid():
		return p
	return NavigationServer3D.map_get_closest_point(nmap, p)

## A navmesh spot near `station`, off the map floor, clear of the overlord and of
## the overlord-station line. Falls back to `home` when none fits.
static func spot_for(advisor: Node3D, s: Vector3, overlord: Node3D, floor_map: MapFloor, home: Vector3) -> Vector3:
	var o := overlord.global_position
	var best := home
	var best_score := INF
	for i in 12:
		var a := TAU * float(i) / 12.0
		var cand := _snap(advisor, s + Vector3(cos(a), 0.0, sin(a)) * STAND_OFF)
		if _flat(cand - (s + Vector3(cos(a), 0.0, sin(a)) * STAND_OFF)).length() > 0.6 or absf(cand.y - s.y) > 1.5:
			continue
		# Spots sit an arrival radius beyond the margin, so arriving short is still off the floor.
		if on_floor(floor_map, cand, ARRIVE_RADIUS):
			continue
		if _flat(cand - o).length() < MIN_FROM_OVERLORD:
			continue
		var so := _flat(o - s)
		if so.length() > 0.5:
			var t := clampf(_flat(cand - s).dot(so) / so.length_squared(), 0.0, 1.0)
			if _flat(cand - s).distance_to(so * t) < CLEAR_OF_LINE:
				continue
		# Not behind the overlord: a straight walk past him ends pressed against him, going nowhere.
		var from := _flat(advisor.global_position)
		var walk := _flat(cand) - from
		if walk.length_squared() > 0.01:
			var wt := clampf((_flat(o) - from).dot(walk) / walk.length_squared(), 0.0, 1.0)
			if (_flat(o) - (from + walk * wt)).length() < CLEAR_OF_WALK:
				continue
		var score := _flat(cand - o).length() + _flat(cand - advisor.global_position).length() * 0.3
		if score < best_score:
			best_score = score
			best = cand
	return best

## Closest spot outside the floor keep-out square to `p`, snapped to the navmesh.
static func push_off_floor(advisor: Node3D, floor_map: MapFloor, p: Vector3) -> Vector3:
	if floor_map == null or not on_floor(floor_map, p, ARRIVE_RADIUS):
		return p
	var l := floor_map.to_local(p)
	var h := floor_map.floor_size * 0.5 + FLOOR_MARGIN + ARRIVE_RADIUS + 0.3
	if absf(l.x) > absf(l.z):
		l.x = h * signf(l.x if l.x != 0.0 else 1.0)
	else:
		l.z = h * signf(l.z if l.z != 0.0 else 1.0)
	return _snap(advisor, floor_map.to_global(l))
