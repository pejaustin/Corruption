extends SceneTree
## Bakes an open world's navigation mesh and saves it, as the editor's "Bake NavigationMesh" button would.
## Run: SIZE=2km godot --headless --path . -s res://tools/bake_open_world_navmesh.gd   (SIZE = 2km | 6km)
## Writes scenes/world/open_world/open_world_<size>_navmesh.res, which open_world_<size>.tscn's Nav region uses.

## PLACEHOLDER: tuning, not designed. Per size: [cell size, max climb]. Climb must be at least cell size x tan(max
## slope) or slopes split the mesh into islands (2 m cells with 0.5 m climb gave 110 islands at 2 km).
const PARAMS: Dictionary[String, Array] = {"2km": [1.0, 1.0], "6km": [2.0, 2.0]}
const AGENT_HEIGHT: float = 0.4   # as in world.tscn
const AGENT_RADIUS: float = 0.5

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
	nm.cell_size = PARAMS[size][0]
	nm.cell_height = 0.1
	nm.agent_max_climb = PARAMS[size][1]
	nm.agent_height = AGENT_HEIGHT
	nm.agent_radius = AGENT_RADIUS
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)
	await process_frame
	print("[bake] ", size, " vertices=", nm.get_vertices().size(), " polygons=", nm.get_polygon_count())
	if nm.get_polygon_count() == 0:
		push_error("bake produced no polygons")
		quit(1)
		return
	var err := ResourceSaver.save(nm, out)
	print("[bake] saved ", out, " err=", err)
	quit(err)
