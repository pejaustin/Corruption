extends SceneTree
## Bakes an open world's navigation mesh and saves it, as the editor's "Bake NavigationMesh" button would.
## Run: SIZE=2km godot --headless --path . -s res://tools/bake_open_world_navmesh.gd   (SIZE = 400m | 2km | 6km)
## Writes scenes/world/open_world/open_world_<size>_navmesh.res, which open_world_<size>.tscn's Nav region uses.
## REFINE=<metres> overrides the refinement edge length below (0 = off).
## WORLD=1 also writes scenes/world/world_navmesh.res, the game world's (world.tscn's Nav region holds the same
## landscape scene, so the mesh is identical; use SIZE=2km).

## PLACEHOLDER: tuning, not designed. Per size: [cell size, max climb]. Climb must be at least cell size x tan(max
## slope) or slopes split the mesh into islands (2 m cells with 0.5 m climb gave 110 islands at 2 km; 1 m cells with
## 0.4 m climb cut the volcano tower off from everything).
const PARAMS: Dictionary[String, Array] = {"400m": [0.5, 0.5], "2km": [1.0, 1.0], "6km": [2.0, 2.0]}
## PLACEHOLDER: tuning, not designed. Godot keeps the baked polygons as the contour left them, so on rolling ground they
## are a few huge flat triangles floating up to 35 m off the real ground, and units (whose agents measure in 3D) never
## "arrive". After baking, every triangle edge that lies on the ground is split until none is longer than this many
## metres, and the new vertices are put on the ground. 0 = off. Edges off the ground (tower floors) are left alone.
## 2 km at 40 m: ~24k polygons, ground within 0.4 m on average (12 m gave 195k polygons, which no path search covers;
## 80 m gave 10k polygons at 0.6 m). Paths and agents then need path_search_max_polygons above the polygon count.
const REFINE_EDGE_M: Dictionary[String, float] = {"400m": 0.0, "2km": 40.0, "6km": 0.0}
## How far a vertex may be from the ground and still count as standing on it, in metres.
const ON_GROUND_TOLERANCE: float = 1.5
const AGENT_HEIGHT: float = 0.4   # as in world.tscn
const AGENT_RADIUS: float = 0.5
const WORLD_OUT: String = "res://scenes/world/world_navmesh.res"

func _init() -> void:
	var size: String = OS.get_environment("SIZE") if OS.get_environment("SIZE") != "" else "2km"
	var scene := "res://scenes/world/open_world/open_world_%s.tscn" % size
	var out := "res://scenes/world/open_world/open_world_%s_navmesh.res" % size
	var world: Node = (load(scene) as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var region := world.get_node("Nav") as NavigationRegion3D
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 4294967291   # as world.tscn had: leaves out the towers' boundary layer
	nm.cell_size = PARAMS[size][0]
	nm.cell_height = 0.1
	nm.agent_max_climb = PARAMS[size][1]
	nm.agent_height = AGENT_HEIGHT
	nm.agent_radius = AGENT_RADIUS
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)
	await process_frame
	var refine: float = float(OS.get_environment("REFINE")) if OS.get_environment("REFINE") != "" else REFINE_EDGE_M[size]
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
		err = ResourceSaver.save(nm, WORLD_OUT)
		print("[bake] saved ", WORLD_OUT, " err=", err)
	quit(err)


var _verts: PackedVector3Array
var _mids: Dictionary[Vector2i, int] = {}
var _grounded: Dictionary[int, bool] = {}
var _tris: Array[PackedInt32Array] = []
var _max_edge: float
var _ground_tri: TriangleMesh
var _ground_xf: Transform3D

func _refine(nm: NavigationMesh, ground: MeshInstance3D, max_edge: float) -> void:
	_max_edge = max_edge
	_ground_tri = ground.mesh.generate_triangle_mesh()
	_ground_xf = ground.global_transform
	_verts = nm.get_vertices()
	var polygons: Array[PackedInt32Array] = []
	for i in nm.get_polygon_count():
		polygons.append(nm.get_polygon(i))
	for poly in polygons:
		for k in range(1, poly.size() - 1):
			_split(poly[0], poly[k], poly[k + 1])
	nm.clear()
	nm.set_vertices(_verts)
	for t in _tris:
		nm.add_polygon(t)
	print("[bake] refined to ", _tris.size(), " triangles, ", _verts.size(), " vertices")

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
		if d > _max_edge and d > longest and _on_ground(p) and _on_ground(q):
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

func _midpoint(p: int, q: int) -> int:
	var key := Vector2i(mini(p, q), maxi(p, q))
	if _mids.has(key):
		return _mids[key]
	var mid := (_verts[p] + _verts[q]) * 0.5
	var g := _ground_y(mid)
	if not is_nan(g):
		mid.y = g + (_verts[p].y + _verts[q].y) * 0.5 - _ground_y_cached(p, q)
	_verts.append(mid)
	_mids[key] = _verts.size() - 1
	_grounded[_verts.size() - 1] = true
	return _verts.size() - 1

func _ground_y_cached(p: int, q: int) -> float:
	## Mean ground height under the two ends, so the new vertex keeps the baked mesh's small offset above the ground.
	return (_ground_y(_verts[p]) + _ground_y(_verts[q])) * 0.5

func _on_ground(i: int) -> bool:
	if not _grounded.has(i):
		var g := _ground_y(_verts[i])
		_grounded[i] = not is_nan(g) and absf(_verts[i].y - g) <= ON_GROUND_TOLERANCE
	return _grounded[i]

func _ground_y(v: Vector3) -> float:
	var inv := _ground_xf.affine_inverse()
	var a: Vector3 = inv * Vector3(v.x, 5000.0, v.z)
	var b: Vector3 = inv * Vector3(v.x, -5000.0, v.z)
	var hit := _ground_tri.intersect_ray(a, (b - a).normalized())
	return NAN if hit.is_empty() else (_ground_xf * (hit["position"] as Vector3)).y
