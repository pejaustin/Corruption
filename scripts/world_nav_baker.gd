class_name WorldNavBaker extends Node

## Bakes the parent NavigationRegion3D's navmesh at match start when the scene
## ships without one. The world's navmesh lost its baked polygons when the
## terrain was replaced (commit 8ed6df4), which left every unit outside the
## towers unable to path. Re-baking in the editor (Terrain3D → Bake NavMesh)
## and saving world.tscn makes this a no-op; until then the host bakes on load
## from the Terrain3D heightmap plus any static colliders under the region.
## Only the host runs unit AI, so only the host bakes.

signal baked

@export var terrain: Terrain3D
## Area baked when the navmesh has no baking AABB of its own: the playfield
## around the four towers.
@export var bake_area: AABB = AABB(Vector3(-200, -40, -200), Vector3(400, 120, 400))
## Runtime bakes need a coarser grid than the editor default, or Godot's crash
## guard refuses a playfield this size.
@export var runtime_cell_size: float = 0.5

func _ready() -> void:
	var region := get_parent() as NavigationRegion3D
	if region == null or region.navigation_mesh == null:
		return
	if region.navigation_mesh.get_polygon_count() > 0:
		return
	if not multiplayer.is_server():
		return
	_bake.call_deferred(region)

func _bake(region: NavigationRegion3D) -> void:
	var nav_mesh := region.navigation_mesh
	nav_mesh.cell_size = runtime_cell_size
	nav_mesh.cell_height = runtime_cell_size * 0.5
	NavigationServer3D.map_set_cell_size(region.get_navigation_map(), runtime_cell_size)
	NavigationServer3D.map_set_cell_height(region.get_navigation_map(), runtime_cell_size * 0.5)
	nav_mesh.filter_baking_aabb = bake_area
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nav_mesh, source, region)
	if terrain:
		var aabb := bake_area
		# require_nav = false: the terrain has no painted navigation areas yet, so
		# all of it counts as walkable ground (slopes are culled by the navmesh).
		var faces := terrain.generate_nav_mesh_source_geometry(aabb, false)
		if not faces.is_empty():
			source.add_faces(faces, Transform3D.IDENTITY)
	var started := Time.get_ticks_msec()
	NavigationServer3D.bake_from_source_geometry_data_async(nav_mesh, source, func() -> void:
		region.navigation_mesh = null
		region.navigation_mesh = nav_mesh
		print("[WorldNavBaker] baked world navmesh: %d polygons in %d ms" % [nav_mesh.get_polygon_count(), Time.get_ticks_msec() - started])
		baked.emit())
