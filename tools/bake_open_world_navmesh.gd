extends SceneTree
## Bakes the open world's navigation mesh and saves it, as the editor's "Bake NavigationMesh" button would.
## Run: godot --headless --path . -s res://tools/bake_open_world_navmesh.gd
## Parameters live on the NavigationMesh resource (scenes/world/open_world/open_world_navmesh.res); only the baked
## polygons are written here.

const SCENE := "res://scenes/world/open_world/open_world.tscn"
const OUT := "res://scenes/world/open_world/open_world_navmesh.res"

func _init() -> void:
	var world: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	var region := world.get_node("Nav") as NavigationRegion3D
	var nm := region.navigation_mesh
	region.bake_navigation_mesh(false)
	await process_frame
	print("[bake] vertices=", nm.get_vertices().size(), " polygons=", nm.get_polygon_count())
	if nm.get_polygon_count() == 0:
		push_error("bake produced no polygons")
		quit(1)
		return
	var err := ResourceSaver.save(nm, OUT)
	print("[bake] saved ", OUT, " err=", err)
	quit(err)
