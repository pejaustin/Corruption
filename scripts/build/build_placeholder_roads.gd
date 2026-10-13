extends SceneTree
## PLACEHOLDER: stand-in roads, not drawn by Austin. Adds a Road (scenes/map/road.tscn) under World/Roads in
## scenes/world/world.tscn for each pair in LINKS that has none yet, so orders have roads to follow until Austin draws
## the real ones on the terrain. Never touches a road that is already there (his or an earlier stand-in), never removes
## one. A deleted stand-in comes back if this is run again.
## Run: godot --headless --path . -s res://scripts/build/build_placeholder_roads.gd      (DRY=1 only prints)
##
## Each road runs straight from point to point, with a curve point dropped onto the 2 km ground every SPACING_M. A
## straight line that would run through Pale River away from a RiverCrossing goes through the crossing(s) of the towns
## it joins that leave the least of it in the water (Hopes Gate has three). What is still in the water gets no curve
## points (units find their own way over that span; no bridge is invented) and is printed as "WET", for Austin.

const Ground = preload("res://scripts/build/world_ground.gd")
const WORLD: String = "res://scenes/world/world.tscn"
const ROAD_SCENE: String = "res://scenes/map/road.tscn"
const CROSSING_SCENE: String = "res://scenes/world/water/river_crossing.tscn"
const AREAS_JSON: String = "res://art/world/export/areas_2km.json"
const RIVER: String = "Pale River"
## PLACEHOLDER: the old MapPoint.links graph (shipped layout, ticket #584), one road per "from|to" pair.
const LINKS: PackedStringArray = [
	"TowerEast|RoadEast", "TowerSouth|RoadSouth", "TowerWest|RoadWest", "TowerNorth|RoadNorth", "RoadEast|Chapel",
	"RoadEast|SettlementSE", "RoadEast|Ford", "RoadSouth|AvatarSite", "RoadSouth|SettlementSE", "RoadSouth|Crossing",
	"RoadWest|City", "RoadWest|BossSite", "RoadWest|SettlementNW", "RoadWest|Crossing", "RoadNorth|BossSite",
	"RoadNorth|SettlementNW", "RoadNorth|Ford", "Chapel|City", "AvatarSite|City", "BossSite|City",
	"SettlementSE|MineSE", "SettlementNW|MineNW"
]
## PLACEHOLDER: tuning — metres between the curve points of a stand-in road.
const SPACING_M: float = 30.0
## Metres between the samples that measure a line's water.
const WET_STEP_M: float = 2.0

var _ground: Ground
var _river: Array[PackedVector2Array] = []
## { pos: Vector3, radius: float, town: String } per RiverCrossing.
var _crossings: Array[Dictionary] = []

func _init() -> void:
	_build.call_deferred()

func _build() -> void:
	await process_frame   # the autoloads, for the world's scripts to compile
	_ground = Ground.new()
	_ground.load_size("2km")
	_load_river()
	var state := (load(WORLD) as PackedScene).get_state()
	var present: Dictionary[String, bool] = {}
	for i in state.get_node_count():
		if String(state.get_node_path(i, true)) == "./World/Roads":
			present[String(state.get_node_name(i))] = true
	var world: Node = (load(WORLD) as PackedScene).instantiate()
	var landscape := world.get_node("World/Nav/WorldLandscape")
	_find_crossings(landscape)
	var points: Dictionary[String, Vector3] = {}
	var towns: Dictionary[String, String] = {}
	for p in world.get_node("World/MapPoints").get_children():
		points[String(p.name)] = _point_spot(p as Node3D, landscape)
		towns[String(p.name)] = String(p.get("display_name"))
	var subs := ""
	var nodes := ""
	var added := 0
	for pair in LINKS:
		var link := pair.split("|")
		var road_name := "%s_%s" % [link[0], link[1]]
		if present.has(road_name):
			continue
		var ends: Array[String] = [towns[link[0]], towns[link[1]]]
		var corners := _corners(points[link[0]], points[link[1]], ends, road_name)
		var curve := Curve3D.new()
		for p in _samples(corners):
			curve.add_point(p)
		var sub_id := "Curve3D_road_%s" % road_name
		subs += "[sub_resource type=\"Curve3D\" id=\"%s\"]\n_data = %s\npoint_count = %d\n\n" % [sub_id, var_to_str(curve.get("_data")), curve.point_count]
		nodes += "\n[node name=\"%s\" parent=\"World/Roads\" node_paths=PackedStringArray(\"from_point\", \"to_point\") instance=ExtResource(\"94_road\")]\ncurve = SubResource(\"%s\")\nfrom_point = NodePath(\"../../MapPoints/%s\")\nto_point = NodePath(\"../../MapPoints/%s\")\n" % [road_name, sub_id, link[0], link[1]]
		added += 1
	world.free()
	if added == 0 or OS.get_environment("DRY") != "":
		print("[roads] ", added, " to add", " (dry run)" if added else "")
		quit(0)
		return
	_write(state, subs, nodes, present.is_empty())
	print("[roads] added ", added, " stand-in road(s) to ", WORLD)
	quit(0)

func _write(state: SceneState, subs: String, nodes: String, need_container: bool) -> void:
	var text := FileAccess.get_file_as_string(WORLD)
	if not text.contains("path=\"%s\"" % ROAD_SCENE):
		var last_ext := text.rfind("[ext_resource")
		var after_ext := text.find("\n", last_ext) + 1
		text = text.substr(0, after_ext) + "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"94_road\"]\n" % ROAD_SCENE + text.substr(after_ext)
	var first_node := text.find("\n[node ") + 1
	text = text.substr(0, first_node) + subs + text.substr(first_node)
	if need_container and not text.contains("[node name=\"Roads\" type=\"Node3D\" parent=\"World\""):
		nodes = "\n[node name=\"Roads\" type=\"Node3D\" parent=\"World\"]\n" + nodes
	# After the map points (parents come before children; the Roads are siblings of MapPoints).
	var places := text.find("[node name=\"Places\" type=\"Node3D\" parent=\"World\"")
	text = text.substr(0, places) + nodes.trim_prefix("\n") + "\n" + text.substr(places)
	var file := FileAccess.open(WORLD, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _point_spot(p: Node3D, landscape: Node) -> Vector3:
	## Where the point stands in play: a tower point on its tower's courier gate (MapPoint._snap), any other on the ground.
	var slot := int(p.get("tower_slot"))
	if slot >= 0:
		for t in landscape.find_children("Tower", "Node3D", true, false):
			if int(t.get("slot_index")) == slot and t.has_node("CourierSpawn"):
				var gate := _global(t.get_node("CourierSpawn"))
				return gate.origin
	var at := _global(p).origin
	var g := _ground.y_at(at.x, at.z)
	return Vector3(at.x, g if not is_nan(g) else at.y, at.z)

func _corners(a: Vector3, b: Vector3, towns: Array[String], road_name: String) -> Array[Vector3]:
	## a and b, with the crossing(s) of the towns it joins between them that leave the least of the road in the river
	## (then the shortest). Straight when it does not touch the water.
	var best: Array[Vector3] = [a, b]
	var best_wet := _wet_length(best)
	if best_wet == 0.0:
		return best
	var best_len := _length(best)
	var mine: Array[Vector3] = []
	for c in _crossings:
		if towns.has(c["town"]):
			mine.append(c["pos"])
	var options: Array[Array] = []
	for v1 in mine:
		options.append([a, v1, b])
		for v2 in mine:
			if v2 != v1:
				options.append([a, v1, v2, b])
	for option in options:
		var typed: Array[Vector3] = []
		typed.assign(option)
		var wet := _wet_length(typed)
		var length := _length(typed)
		if wet < best_wet - WET_STEP_M or (absf(wet - best_wet) <= WET_STEP_M and length < best_len):
			best = typed
			best_wet = wet
			best_len = length
	if best.size() > 2:
		print("[roads] ", road_name, " goes through ", best.size() - 2, " river crossing(s) of ", towns)
	if best_wet > 0.0:
		print("[roads] WET: ", road_name, " runs %d m through Pale River away from any crossing (%s); no curve points there" % [roundi(best_wet), _wet_spans(best)])
	return best

func _samples(corners: Array[Vector3]) -> Array[Vector3]:
	## Every corner, and a point every SPACING_M between, on the ground. The ends stay where the points stand; a point
	## that would stand in the river away from a crossing is left out (units find their own way over that span).
	var out: Array[Vector3] = [corners[0]]
	for i in range(1, corners.size()):
		var a := corners[i - 1]
		var b := corners[i]
		var steps := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / SPACING_M))
		for k in range(1, steps + 1):
			var p := a.lerp(b, float(k) / steps)
			var last := k == steps and i == corners.size() - 1
			if not last:
				if k < steps and _is_wet(Vector2(p.x, p.z)):
					continue
				var g := _ground.y_at(p.x, p.z)
				if not is_nan(g):
					p.y = g
			out.append(p)
	return out

func _length(corners: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, corners.size()):
		total += Vector2(corners[i].x - corners[i - 1].x, corners[i].z - corners[i - 1].z).length()
	return total

func _wet_length(corners: Array[Vector3]) -> float:
	## Metres of the line through the corners that run through the river outside a crossing.
	var wet := 0.0
	for i in range(1, corners.size()):
		var a := Vector2(corners[i - 1].x, corners[i - 1].z)
		var flat := Vector2(corners[i].x, corners[i].z) - a
		var steps := maxi(1, ceili(flat.length() / WET_STEP_M))
		for k in range(1, steps + 1):
			if _is_wet(a + flat * (float(k) / steps)):
				wet += flat.length() / steps
	return wet

func _wet_spans(corners: Array[Vector3]) -> String:
	## Where the wet stretches are, as "x,z..x,z" pairs (for the report).
	var spans: Array[String] = []
	var from := Vector2.INF
	var last := Vector2.INF
	for i in range(1, corners.size()):
		var a := Vector2(corners[i - 1].x, corners[i - 1].z)
		var flat := Vector2(corners[i].x, corners[i].z) - a
		var steps := maxi(1, ceili(flat.length() / WET_STEP_M))
		for k in range(0, steps + 1):
			var p := a + flat * (float(k) / steps)
			if _is_wet(p):
				if from == Vector2.INF:
					from = p
				last = p
			elif from != Vector2.INF:
				spans.append("%d,%d..%d,%d" % [from.x, from.y, last.x, last.y])
				from = Vector2.INF
	if from != Vector2.INF:
		spans.append("%d,%d..%d,%d" % [from.x, from.y, last.x, last.y])
	return "; ".join(spans)

func _is_wet(p: Vector2) -> bool:
	## In the river and not within a crossing.
	var inside := false
	for loop in _river:
		if Geometry2D.is_point_in_polygon(p, loop):
			inside = true
			break
	if not inside:
		return false
	for c in _crossings:
		var cp: Vector3 = c["pos"]
		if p.distance_to(Vector2(cp.x, cp.z)) <= float(c["radius"]):
			return false
	return true

func _load_river() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AREAS_JSON))
	var area: Dictionary = data["areas"][RIVER]
	for loop in area["outlines"]:
		var poly := PackedVector2Array()
		for v in loop:
			poly.append(Vector2(float(v[0]), float(v[1])))
		_river.append(poly)

func _find_crossings(landscape: Node) -> void:
	for n in landscape.find_children("*", "Node3D", true, false):
		if n.scene_file_path == CROSSING_SCENE:
			_crossings.append({"pos": _ground_at(_global(n).origin), "radius": float(n.get("radius_m")), "town": String(n.get_parent().name)})
	print("[roads] ", _crossings.size(), " river crossings")

func _ground_at(p: Vector3) -> Vector3:
	var g := _ground.y_at(p.x, p.z)
	return Vector3(p.x, g if not is_nan(g) else p.y, p.z)

func _global(node: Node) -> Transform3D:
	## Global transform of a node that is not in the tree.
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n is Node3D:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf
