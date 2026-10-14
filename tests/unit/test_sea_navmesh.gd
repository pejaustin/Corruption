extends GutTest

## The sea blocks movement (Austin, 2026-10-12): no navmesh polygon may lie under the Glittering Ocean. Reads the saved
## navmesh and the sea's NavigationObstacle3D band (art/world/README.md "Water: blockers and bridges"); no world loaded.
## Both sit at the world origin with no transform (World/Nav and the landscape's Waters branch).

const WORLDS: Array = [
	["2 km", "res://scenes/world/world_navmesh.res", "res://art/world/export/waters_2km.tscn"],
	["400 m", "res://scenes/world/world_400m_navmesh.res", "res://art/world/export/waters_400m.tscn"],
]
const SEA_BLOCKERS: String = "Glittering Ocean/Blockers"

func test_no_walkable_polygon_lies_under_the_sea(params: Array = use_parameters(WORLDS)) -> void:
	var navmesh := load(params[1]) as NavigationMesh
	var waters: Node3D = autofree((load(params[2]) as PackedScene).instantiate())
	var blockers := waters.get_node_or_null(SEA_BLOCKERS)
	assert_not_null(blockers, "%s: the sea has blockers" % params[0])
	if blockers == null:
		return
	var verts := navmesh.get_vertices()
	var under: int = 0
	for blocker: NavigationObstacle3D in blockers.get_children():
		var outline := PackedVector2Array()
		for v in blocker.vertices:
			var p: Vector3 = blocker.transform * v
			outline.append(Vector2(p.x, p.z))
		# Recast rounds heights to its cell height, so the shore's edge polygons may sit a cell under the band's top.
		var band_top: float = blocker.position.y + blocker.height - navmesh.cell_height
		for i in navmesh.get_polygon_count():
			var poly := navmesh.get_polygon(i)
			var centre := Vector3.ZERO
			for idx in poly:
				centre += verts[idx]
			centre /= poly.size()
			if centre.y < band_top and Geometry2D.is_point_in_polygon(Vector2(centre.x, centre.z), outline):
				under += 1
	assert_eq(under, 0, "%s: navmesh polygons under the sea" % params[0])
