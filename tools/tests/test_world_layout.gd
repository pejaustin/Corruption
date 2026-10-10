extends "res://tools/tests/test_base.gd"

## The game world on Austin's 2 km map: one tower per tower site, paired with its slot's rally point,
## map point and player; every place and site stands on the ground and can be walked to from every tower (the holy knights are adopted into the unit root at start, so only the Avatar is checked).

const GROUND_TOLERANCE: float = 3.0
## How near the navmesh a place must be, and how near a path must end, in metres (a unit gives up circling a goal it cannot get within ~1.5 m of).
const NAV_TOLERANCE: float = 2.0

func run_tests() -> void:
	var world := await load_world()
	var towers := Tower.in_slot_order(get_tree())
	check(towers.size() == 4, "exactly four towers (%d)" % towers.size())
	var markers := world.get_node("World/Markers").get_children()
	var points := MapPoint.all_points(get_tree())
	var map := (world.get_node("World/Nav") as NavigationRegion3D).get_navigation_map()
	for i in towers.size():
		var t := towers[i]
		check(t.slot_index == i, "tower %d is in slot %d" % [i, i])
		check(t.get_parent().name in ["Naf Ishun", "Forest Tower", "Volcano Tower", "Avequel'la"], "slot %d stands under Austin's marker %s" % [i, t.get_parent().name])
		check(t.rally_point == markers[i], "slot %d is paired with %s" % [i, markers[i].name])
		check(t.rally_point.global_position.distance_to(t.global_position) < 120.0, "slot %d's rally point is beside its tower (%.0f m)" % [i, t.rally_point.global_position.distance_to(t.global_position)])
		var mp: MapPoint = null
		for p in points:
			if p.kind == MapPoint.Kind.TOWER and p.tower_slot == i:
				mp = p
		check(mp != null and mp.global_position.distance_to(t.courier_spawn.global_position) < 1.0, "slot %d has a map point at its courier spawn" % i)
		check(_ground_y(t.courier_spawn.global_position) != INF and absf(_ground_y(t.courier_spawn.global_position) - t.courier_spawn.global_position.y) < 40.0, "slot %d's courier spawn is on the ground" % i)
	var mm := world.get_node("MinionManager") as MinionManager
	check(mm.get_rally_point_for(1) == towers[0].rally_point, "the first player holds slot 0's rally point")
	var spawn := world.get_node("World/PlayerSpawnPoint").get_node_or_null("1") as Node3D
	var first_spawn := towers[0].get_node("SpawnPoint") as Node3D
	check(spawn != null and spawn.global_position.distance_to(first_spawn.global_position) < 5.0, "the first player appears in slot 0's tower")

	# Everything stands on the ground and is reachable from every tower's courier spawn.
	var spots: Array[Node3D] = []
	for p in points:
		if p.kind != MapPoint.Kind.TOWER:
			spots.append(p)
	for n in ["SiteChapel", "SiteAvatar", "SiteBoss"]:
		spots.append(world.get_node(n))
	spots.append(world.get_node("World/Avatar"))
	for p in world.get_node("World/Places").get_children():
		spots.append(p)
	for s in spots:
		if not s is CharacterBody3D:  # a unit's own body is what the ray would hit
			var g := _ground_y(s.global_position)
			check(g != INF and absf(g - s.global_position.y) < GROUND_TOLERANCE, "%s stands on the ground (%.1f vs %.1f)" % [s.name, s.global_position.y, g])
		var on_mesh := NavigationServer3D.map_get_closest_point(map, s.global_position)
		check(on_mesh.distance_to(s.global_position) < NAV_TOLERANCE, "%s is on the navmesh (%.1f m off)" % [s.name, on_mesh.distance_to(s.global_position)])
	for t in towers:
		var from := t.courier_spawn.global_position
		var bad: Array[String] = []
		for s in spots:
			var path := _path(map, from, s.global_position)
			if path.is_empty() or path[path.size() - 1].distance_to(s.global_position) > NAV_TOLERANCE:
				bad.append(String(s.name))
		check(bad.is_empty(), "slot %d's courier spawn can walk to everything (unreachable: %s)" % [t.slot_index, ", ".join(bad)])

func _ground_y(at: Vector3) -> float:
	## Height of the landscape's ground (collision layer 1, no towers: they are above their own ground) at x, z.
	var space := get_viewport().world_3d.direct_space_state
	var from := Vector3(at.x, at.y + 300.0, at.z)
	var query := PhysicsRayQueryParameters3D.create(from, Vector3(at.x, at.y - 300.0, at.z), 1)
	var hit := space.intersect_ray(query)
	return INF if hit.is_empty() else float(hit.position.y)

func _path(map: RID, from: Vector3, to: Vector3) -> PackedVector3Array:
	## As the units' agents search: more polygons than the default 4096 (the map has ~24k).
	var query := NavigationPathQueryParameters3D.new()
	query.map = map
	query.start_position = from
	query.target_position = to
	query.path_search_max_polygons = GroupManager.PATH_SEARCH_POLYGONS
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query, result)
	return result.path
