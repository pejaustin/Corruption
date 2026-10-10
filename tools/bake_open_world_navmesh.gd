extends SceneTree
## Bakes an open world's navigation mesh and saves it, as the editor's "Bake NavigationMesh" button would.
## Run: SIZE=2km godot --headless --path . -s res://tools/bake_open_world_navmesh.gd   (SIZE = 400m | 2km | 6km)
## Writes scenes/world/open_world/open_world_<size>_navmesh.res, which open_world_<size>.tscn's Nav region uses.
## The 400m and 6km meshes are baked without the towers (NO_TOWERS=0 keeps them): a tower carries its own navmesh, and
## the coarse copy of its floor that the world bake would add is not joined to it (it cut the 6 km towers off from their
## jump links). The 2 km mesh keeps them, as it was baked and tested.
## REFINE=<metres> overrides the refinement edge length below (0 = off).
## WORLD=1 also writes the game world's: scenes/world/world_navmesh.res for 2km, scenes/world/world_<size>_navmesh.res for
## the others (the world scenes' Nav regions hold the same landscape scenes, so the meshes are identical).

## PLACEHOLDER: tuning, not designed. Per size: [cell size, max climb]. Climb must be at least cell size x tan(max
## slope) or slopes split the mesh into islands (2 m cells with 0.5 m climb gave 110 islands at 2 km; 1 m cells with
## 0.4 m climb cut the volcano tower off from everything).
const PARAMS: Dictionary[String, Array] = {"400m": [0.5, 0.5], "2km": [1.0, 1.0], "6km": [1.5, 1.5]}
## PLACEHOLDER: tuning, not designed. Godot keeps the baked polygons as the contour left them, so on rolling ground they
## are a few huge flat triangles floating up to 35 m off the real ground, and units (whose agents measure in 3D) never
## "arrive". After baking, every triangle edge that lies on the ground is split until none is longer than this many
## metres, and the new vertices are put on the ground. 0 = off. Edges off the ground (tower floors) are left alone.
## 2 km at 40 m: ~24k polygons, ground within 0.4 m on average (12 m gave 195k polygons, which no path search covers;
## 80 m gave 10k polygons at 0.6 m). Paths and agents then need path_search_max_polygons above the polygon count.
## Every length below (this one, the minimum edge, grid, weld and sliver size) is the 2 km value; other sizes scale it by
## their width, and heights (the error and the on-ground tolerance) by their height, read off the exported ground.
const REFINE_EDGE_M: float = 40.0
## How far a baked vertex may be from the ground and still count as standing on it, in metres (contour vertices on
## cliff edges can be a few metres off); such vertices are put exactly on the ground, so no triangle floats over another.
const ON_GROUND_TOLERANCE: float = 6.0   # a height
## Where the navmesh sits above the ground, in metres.
const GROUND_OFFSET: float = 0.1
## PLACEHOLDER: tuning. Triangles steeper than this (the Y of their normal below it; 0.6 = about 53 degrees) are dropped
## after refining: putting vertices on the ground can stretch a triangle over a cliff the bake had left out.
const MIN_NORMAL_Y: float = 0.6
## PLACEHOLDER: tuning. Below the edge length above, an edge is still split while it is longer than REFINE_MIN_EDGE_M and
## the ground at 1/4, 1/2 or 3/4 along it is more than REFINE_ERROR_M off the straight line between its ends: flat
## ground keeps long triangles, creases and slopes get short ones.
const REFINE_MIN_EDGE_M: float = 8.0
const REFINE_ERROR_M: float = 0.8   # a height
## Ground heights are sampled on this grid (metres) once, then looked up.
const HEIGHT_GRID_M: float = 2.0
## Baked vertices closer than this (metres, per axis) after snapping are one vertex.
const WELD_M: float = 0.3
## Triangles smaller than this (square metres) are slivers and are dropped.
const MIN_AREA_M2: float = 0.2
const AGENT_HEIGHT: float = 0.4   # as in world.tscn
const AGENT_RADIUS: float = 0.5
const Ground = preload("res://scripts/build/world_ground.gd")
const WORLD_OUT: String = "res://scenes/world/world_%s_navmesh.res"
const WORLD_OUT_2KM: String = "res://scenes/world/world_navmesh.res"

func _init() -> void:
	var size: String = OS.get_environment("SIZE") if OS.get_environment("SIZE") != "" else "2km"
	var scene := "res://scenes/world/open_world/open_world_%s.tscn" % size
	var out := "res://scenes/world/open_world/open_world_%s_navmesh.res" % size
	var world: Node = (load(scene) as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var drop_towers := size != "2km"
	if OS.get_environment("NO_TOWERS") != "":
		drop_towers = OS.get_environment("NO_TOWERS") == "1"
	if drop_towers:
		var towers: Array[Node] = []
		for t in world.find_children("*", "Node3D", true, false):
			if t.is_in_group(&"towers"):
				towers.append(t)
		for t in towers:
			t.get_parent().remove_child(t)
			t.queue_free()
	var ground := Ground.new()
	ground.load_size(size)
	var ref_ground := Ground.new()
	ref_ground.load_size("2km")
	var factors := ground.factors_against(ref_ground)
	_min_edge = REFINE_MIN_EDGE_M * factors.x
	_error_m = REFINE_ERROR_M * factors.y
	_on_ground_m = ON_GROUND_TOLERANCE * factors.y
	_weld_m = WELD_M * factors.x
	_min_area = MIN_AREA_M2 * factors.x * factors.x
	_grid_m = HEIGHT_GRID_M * factors.x
	var region := world.get_node("Nav") as NavigationRegion3D
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 4294967291   # as world.tscn had: leaves out the towers' boundary layer
	nm.cell_size = PARAMS[size][0]
	nm.cell_height = 0.1
	nm.agent_max_climb = PARAMS[size][1]
	nm.agent_height = AGENT_HEIGHT
	nm.agent_radius = AGENT_RADIUS
	# A taller-than-wide map is steeper everywhere (6 km: 5/3 as steep), so what was walkable at 2 km stays walkable: the
	# slope limits (agent max slope, and the steepest triangle refining keeps) scale with it. 2 km keeps the defaults.
	var steepness := factors.y / factors.x
	if not is_equal_approx(steepness, 1.0):
		nm.agent_max_slope = rad_to_deg(atan(tan(deg_to_rad(nm.agent_max_slope)) * steepness))
		_min_normal_y = cos(atan(tan(acos(MIN_NORMAL_Y)) * steepness))
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)
	await process_frame
	var refine: float = float(OS.get_environment("REFINE")) if OS.get_environment("REFINE") != "" else REFINE_EDGE_M * factors.x
	if refine > 0.0:
		var geo := world.find_child("geo", true, false) as MeshInstance3D
		_refine(nm, geo, refine)
	print("[bake] ", size, " vertices=", nm.get_vertices().size(), " polygons=", nm.get_polygon_count())
	if nm.get_polygon_count() == 0:
		push_error("bake produced no polygons")
		quit(1)
		return
	var err := ResourceSaver.save(nm, out)
	print("[bake] saved ", out, " err=", err)
	if err == OK and OS.get_environment("WORLD") == "1":
		var world_out := WORLD_OUT_2KM if size == "2km" else WORLD_OUT % size
		err = ResourceSaver.save(nm, world_out)
		print("[bake] saved ", world_out, " err=", err)
	quit(err)


## The constants above, scaled to the size being baked (see REFINE_EDGE_M).
var _min_edge: float = REFINE_MIN_EDGE_M
var _error_m: float = REFINE_ERROR_M
var _on_ground_m: float = ON_GROUND_TOLERANCE
var _weld_m: float = WELD_M
var _min_normal_y: float = MIN_NORMAL_Y
var _min_area: float = MIN_AREA_M2
var _grid_m: float = HEIGHT_GRID_M
var _verts: PackedVector3Array
var _mids: Dictionary[Vector2i, int] = {}
var _grounded: Dictionary[int, bool] = {}
var _tris: Array[PackedInt32Array] = []
var _max_edge: float
var _ground_tri: TriangleMesh
var _ground_xf: Transform3D
var _grid: PackedFloat32Array
var _grid_min: Vector2
var _grid_w: int
var _grid_h: int

func _refine(nm: NavigationMesh, ground: MeshInstance3D, max_edge: float) -> void:
	_max_edge = max_edge
	_ground_tri = ground.mesh.generate_triangle_mesh()
	_ground_xf = ground.global_transform
	_build_height_grid(ground)
	_verts = nm.get_vertices()
	for i in _verts.size():
		if _on_ground(i):
			_verts[i].y = _ground_y(_verts[i]) + GROUND_OFFSET
	# Snapping can put two baked vertices (one above the other at a cliff edge) on the same spot: weld them, or the
	# navigation server sees more than two edges in one place and drops connections.
	var weld: Dictionary[Vector3i, int] = {}
	var remap := PackedInt32Array()
	remap.resize(_verts.size())
	for i in _verts.size():
		var key := Vector3i((_verts[i] / _weld_m).round())
		if not weld.has(key):
			weld[key] = i
		remap[i] = weld[key]
	var polygons: Array[PackedInt32Array] = []
	for i in nm.get_polygon_count():
		var poly := PackedInt32Array()
		for idx in nm.get_polygon(i):
			var m := remap[idx]
			if poly.is_empty() or poly[poly.size() - 1] != m:
				poly.append(m)
		if poly.size() > 1 and poly[0] == poly[poly.size() - 1]:
			poly.remove_at(poly.size() - 1)
		if poly.size() >= 3:
			polygons.append(poly)
	for poly in polygons:
		for k in range(1, poly.size() - 1):
			_split(poly[0], poly[k], poly[k + 1])
	var kept := 0
	nm.clear()
	nm.set_vertices(_verts)
	for t in _tris:
		var cross := (_verts[t[2]] - _verts[t[0]]).cross(_verts[t[1]] - _verts[t[0]])
		if cross.length() < _min_area * 2.0 or absf(cross.normalized().y) < _min_normal_y:
			continue
		nm.add_polygon(t)
		kept += 1
	print("[bake] refined to ", kept, " triangles (", _tris.size() - kept, " too steep dropped), ", _verts.size(), " vertices")

func _split(a: int, b: int, c: int) -> void:
	## Splits the triangle's longest splittable edge at its midpoint and recurses. Whether an edge is split depends
	## only on its two ends, so neighbouring triangles always split a shared edge the same way (no cracks).
	var ids := [a, b, c]
	var longest := 0.0
	var at := -1
	for i in 3:
		var p: int = ids[i]
		var q: int = ids[(i + 1) % 3]
		var d := _verts[p].distance_to(_verts[q])
		if d > longest and _wants_split(p, q, d):
			longest = d
			at = i
	if at < 0:
		_tris.append(PackedInt32Array([a, b, c]))
		return
	var p: int = ids[at]
	var q: int = ids[(at + 1) % 3]
	var r: int = ids[(at + 2) % 3]
	var m := _midpoint(p, q)
	_split(p, m, r)
	_split(m, q, r)

func _wants_split(p: int, q: int, length: float) -> bool:
	if length <= _min_edge or not _on_ground(p) or not _on_ground(q):
		return false
	if length > _max_edge:
		return true
	for f in [0.25, 0.5, 0.75]:
		var at: Vector3 = _verts[p].lerp(_verts[q], f)
		var g := _ground_y(at)
		if not is_nan(g) and absf(g + GROUND_OFFSET - at.y) > _error_m:
			return true
	return false

func _midpoint(p: int, q: int) -> int:
	var key := Vector2i(mini(p, q), maxi(p, q))
	if _mids.has(key):
		return _mids[key]
	var mid := (_verts[p] + _verts[q]) * 0.5
	var g := _ground_y(mid)
	if not is_nan(g):
		mid.y = g + GROUND_OFFSET
	_verts.append(mid)
	_mids[key] = _verts.size() - 1
	_grounded[_verts.size() - 1] = true
	return _verts.size() - 1

func _on_ground(i: int) -> bool:
	if not _grounded.has(i):
		var g := _ground_y(_verts[i])
		_grounded[i] = not is_nan(g) and absf(_verts[i].y - g) <= _on_ground_m
	return _grounded[i]

func _build_height_grid(ground: MeshInstance3D) -> void:
	var box := _ground_xf * ground.mesh.get_aabb()
	_grid_min = Vector2(box.position.x, box.position.z)
	_grid_w = int(ceil(box.size.x / _grid_m)) + 2
	_grid_h = int(ceil(box.size.z / _grid_m)) + 2
	_grid.resize(_grid_w * _grid_h)
	for gz in _grid_h:
		for gx in _grid_w:
			_grid[gz * _grid_w + gx] = _ray_y(_grid_min.x + gx * _grid_m, _grid_min.y + gz * _grid_m)

func _ray_y(x: float, z: float) -> float:
	var inv := _ground_xf.affine_inverse()
	var a: Vector3 = inv * Vector3(x, 5000.0, z)
	var b: Vector3 = inv * Vector3(x, -5000.0, z)
	var hit := _ground_tri.intersect_ray(a, (b - a).normalized())
	return NAN if hit.is_empty() else (_ground_xf * (hit["position"] as Vector3)).y

func _ground_y(v: Vector3) -> float:
	## Bilinear lookup in the height grid.
	var fx := (v.x - _grid_min.x) / _grid_m
	var fz := (v.z - _grid_min.y) / _grid_m
	var ix := clampi(int(floor(fx)), 0, _grid_w - 2)
	var iz := clampi(int(floor(fz)), 0, _grid_h - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var h00 := _grid[iz * _grid_w + ix]
	var h10 := _grid[iz * _grid_w + ix + 1]
	var h01 := _grid[(iz + 1) * _grid_w + ix]
	var h11 := _grid[(iz + 1) * _grid_w + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
