extends SceneTree
## One-time use (2026-10-13): computes the height-limited navmesh blockers for the sea and Pale River and the ford heights,
## for tools/deprecated/apply_water_blockers.py to write into art/world/export/world_landscape_<size>.tscn as plain
## NavigationObstacle3D nodes (Austin edits them by hand from then on; nothing rebuilds them).
## Run: SIZE=2km|400m OUT=/abs/file.json godot --headless --path . -s res://tools/deprecated/gen_water_blockers.gd
## Outlines: Austin's guides as last exported (art/world/export/areas_<size>.json; the 400 m sea, never exported at 400 m,
## is the 2 km sea outline at the 400 m preset, 0.2). Water heights: the water surface meshes in the landscape scene.
## A blocker carves only between its bottom and top (Recast marks the spans whose top lies in that band), so ground above
## the water inside an outline stays walkable, and so do bridge decks and Ford slabs above it.

const Ground = preload("res://scripts/build/world_ground.gd")
const LANDSCAPE: String = "res://art/world/export/world_landscape_%s.tscn"
const AREAS_JSON: String = "res://art/world/export/areas_%s.json"
const SEA: String = "Glittering Ocean"
const RIVER: String = "Pale River"
const SIZE_400M_FACTOR: float = 0.2
## PLACEHOLDER: tuning. A blocker's band tops out this far over the water surface (real metres at every size).
const WATER_CLEARANCE_M: float = 0.3
## PLACEHOLDER: tuning. A blocker's band starts this far under the lowest ground inside it.
const BELOW_GROUND_M: float = 2.0
## PLACEHOLDER: tuning. The river is cut into squares this many metres a side (2 km; scaled by the map's width), each
## with its own band, so the band follows the river's surface down its length.
const RIVER_CHUNK_M: float = 25.0
## Ground and water heights are sampled on this grid (2 km metres; scaled by the width).
const SAMPLE_M: float = 2.0
## PLACEHOLDER: tuning. A Ford's top stands this far over the highest blocker band it overlaps.
const FORD_ABOVE_BAND_M: float = 0.2

var _ground: Ground
var _wide: float

func _init() -> void:
	var size := OS.get_environment("SIZE")
	_wide = 1.0 if size == "2km" else SIZE_400M_FACTOR
	_ground = Ground.new()
	_ground.load_size(size)
	var land := (load(LANDSCAPE % size) as PackedScene).instantiate() as Node3D
	var areas: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(AREAS_JSON % size)) as Dictionary)["areas"]
	var sea_areas: Dictionary = areas if areas.has(SEA) else (JSON.parse_string(FileAccess.get_file_as_string(AREAS_JSON % "2km")) as Dictionary)["areas"]
	var sea_outline := _outline(sea_areas[SEA], 1.0 if areas.has(SEA) else SIZE_400M_FACTOR)
	var river_outline := _outline(areas[RIVER], 1.0)
	var out := {"size": size, "sea": {}, "river": [], "fords": []}
	# The sea: one flat band up to its surface.
	var sea_level := _sea_level(land, size)
	var sea_low := _lowest(sea_outline, SAMPLE_M * 5.0 * _wide)
	out["sea"] = {"level": sea_level, "outline": _pts(sea_outline), "bottom": sea_low - BELOW_GROUND_M, "top": sea_level + WATER_CLEARANCE_M}
	# The river: per chunk, up to the highest water surface in it.
	var surface := _river_surface(land, size)
	var chunk := RIVER_CHUNK_M * _wide
	var box := _bounds(river_outline)
	var bands: Array[Dictionary] = []
	var cx := floorf(box.position.x / chunk) * chunk
	while cx < box.end.x:
		var cz := floorf(box.position.y / chunk) * chunk
		while cz < box.end.y:
			var square := PackedVector2Array([Vector2(cx, cz), Vector2(cx + chunk, cz), Vector2(cx + chunk, cz + chunk), Vector2(cx, cz + chunk)])
			for piece in Geometry2D.intersect_polygons(river_outline, square):
				if Geometry2D.is_polygon_clockwise(piece):
					continue
				var top := _highest_water(surface, piece)
				if is_nan(top):
					push_warning("no river surface over a piece at (%d, %d)" % [cx, cz])
					continue
				var band := {"outline": _pts(piece), "bottom": _lowest(piece, SAMPLE_M * _wide) - BELOW_GROUND_M, "top": top + WATER_CLEARANCE_M}
				bands.append(band)
			cz += chunk
		cx += chunk
	out["river"] = bands
	# Fords: each RiverCrossing's slab top over the highest band its disc touches.
	for node in land.find_children("*", "Marker3D", true, false):
		if not node.is_in_group(&"river_crossings") and node.scene_file_path != "res://scenes/world/water/river_crossing.tscn":
			continue
		var at := _global(node as Node3D)
		var r := float(node.get("radius_m"))
		var highest := -INF
		for band in bands:
			var poly := _poly(band["outline"])
			if _near(poly, Vector2(at.x, at.z), r):
				highest = maxf(highest, float(band["top"]))
		(out["fords"] as Array).append({"path": String(land.get_path_to(node)), "x": at.x, "y": at.y, "z": at.z, "radius": r, "top": highest + FORD_ABOVE_BAND_M})
	land.free()
	var f := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("[water] ", size, " sea level ", snappedf(sea_level, 0.01), " band ", snappedf(float(out["sea"]["bottom"]), 0.01), "..", snappedf(float(out["sea"]["top"]), 0.01), "; river pieces ", bands.size(), "; fords ", (out["fords"] as Array).size())
	quit()

func _outline(area: Dictionary, factor: float) -> PackedVector2Array:
	var loop := PackedVector2Array()
	for p in (area["outlines"] as Array)[0]:
		loop.append(Vector2(p[0], p[1]) * factor)
	if Geometry2D.is_polygon_clockwise(loop):
		loop.reverse()
	return loop

func _pts(poly: PackedVector2Array) -> Array:
	var a: Array = []
	for p in poly:
		a.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return a

func _poly(a: Array) -> PackedVector2Array:
	var poly := PackedVector2Array()
	for p in a:
		poly.append(Vector2(p[0], p[1]))
	return poly

func _bounds(poly: PackedVector2Array) -> Rect2:
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	return r

func _samples(poly: PackedVector2Array, step: float) -> PackedVector2Array:
	## Grid points inside the polygon, plus its corners.
	var out := PackedVector2Array(poly)
	var r := _bounds(poly)
	var x := r.position.x
	while x <= r.end.x:
		var z := r.position.y
		while z <= r.end.y:
			if Geometry2D.is_point_in_polygon(Vector2(x, z), poly):
				out.append(Vector2(x, z))
			z += step
		x += step
	return out

func _lowest(poly: PackedVector2Array, step: float) -> float:
	var low := INF
	for p in _samples(poly, step):
		var y := _ground.y_at(p.x, p.y)
		if not is_nan(y):
			low = minf(low, y)
	return low

func _highest_water(surface: Array, poly: PackedVector2Array) -> float:
	var high := -INF
	for p in _samples(poly, SAMPLE_M * _wide):
		var y := _hit(surface, p)
		if not is_nan(y):
			high = maxf(high, y)
	return NAN if high == -INF else high

func _hit(surface: Array, p: Vector2) -> float:
	var xf: Transform3D = surface[1]
	var inv := xf.affine_inverse()
	var h := (surface[0] as TriangleMesh).intersect_segment(inv * Vector3(p.x, 3000.0, p.y), inv * Vector3(p.x, -3000.0, p.y))
	return NAN if h.is_empty() else (xf * (h["position"] as Vector3)).y

func _near(poly: PackedVector2Array, c: Vector2, r: float) -> bool:
	if Geometry2D.is_point_in_polygon(c, poly):
		return true
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(c, poly[i], poly[(i + 1) % poly.size()])
		if q.distance_to(c) <= r:
			return true
	return false

func _global(n: Node3D) -> Vector3:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t.origin

func _mesh_node(land: Node, path: String) -> MeshInstance3D:
	return land.get_node(path) as MeshInstance3D

func _river_surface(land: Node, size: String) -> Array:
	var mi := _mesh_node(land, "Waters/%s/Surface" % RIVER if size == "2km" else "Waters/%s" % RIVER)
	return [mi.mesh.generate_triangle_mesh(), _xf(mi)]

func _sea_level(land: Node, size: String) -> float:
	var mi := _mesh_node(land, "Waters/%s/Surface" % SEA if size == "2km" else "Ocean")
	var xf := _xf(mi)
	var aabb := xf * mi.mesh.get_aabb()
	if aabb.size.y > 0.01:
		push_warning("the sea surface is not flat (%s m); using its top" % aabb.size.y)
	return aabb.end.y

func _xf(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
