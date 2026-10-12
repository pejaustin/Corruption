extends SceneTree

## Bakes the navmeshes of the encounter spaces (temple dungeon, runestone arena)
## from their static colliders and saves them next to the scenes.
##   godot --headless --path . -s res://tools/bake_encounter_navmesh.gd
## Run it after changing a layout in scenes/sites/encounter/. PLACEHOLDER layouts.

const SPACES: Dictionary[String, String] = {
	"res://scenes/sites/encounter/temple_dungeon.tscn": "res://scenes/sites/encounter/placeholder/temple_dungeon_navmesh.res",
	"res://scenes/sites/encounter/runestone_arena.tscn": "res://scenes/sites/encounter/placeholder/runestone_arena_navmesh.res",
}

func _process(_delta: float) -> bool:
	for scene_path in SPACES:
		var navmesh := NavigationMesh.new()
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		navmesh.geometry_collision_mask = 1
		navmesh.agent_radius = 0.6
		navmesh.agent_height = 2.0
		navmesh.cell_size = 0.25
		navmesh.cell_height = 0.25
		var root := (load(scene_path) as PackedScene).instantiate()
		root.name = "Space"
		get_root().add_child(root)
		var data := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(navmesh, data, root)
		NavigationServer3D.bake_from_source_geometry_data(navmesh, data)
		print("[bake] %s: %d polygons" % [scene_path.get_file(), navmesh.get_polygon_count()])
		ResourceSaver.save(navmesh, SPACES[scene_path])
		root.queue_free()
	return true
