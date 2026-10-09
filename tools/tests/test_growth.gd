extends "res://tools/tests/test_base.gd"

## Getting better (GDD §5): leaders gain experience from kills and learn
## maneuvers at thresholds, teach them to another group (both busy), and relics
## are found at the map, carried home and applied through flags.

func run_tests() -> void:
	var world := await load_world()
	var mm := world.get_node("MinionManager") as MinionManager
	var gm := world.get_node("GroupManager") as GroupManager
	KnowledgeManager.INSTANT_COMMANDS = true
	Engine.time_scale = 6.0
	for m in mm.get_all_minions():
		if m.minion_type_id == &"holy_knight":
			mm.despawn_minion(m)
	await seconds(8.0)  # Let the host bake the world navmesh.
	var model := KnowledgeManager.local_model()

	check(Maneuver.all().size() >= 3 and Relic.all().size() >= 2, "maneuvers and relics load from data/")
	var g := gm.get_groups_for(1)[0]
	check(gm.get_members(g).size() >= 3, "peer 1 starts with a group to work with")

	# Experience and learning.
	g.experience = 4.5
	var near := gm.get_centroid(g) + Vector3(3, 1, 0)
	var id := mm.spawn_neutral_minion(near, &"villager", near)
	await frames(5)
	var victim := mm.get_minion_by_id(id)
	victim.last_hit_by = 1
	victim.take_damage(999)
	await seconds(3.0)
	check(g.experience > 5.0, "a kill earns the killer's nearest group experience (%.1f)" % g.experience)
	check(&"placeholder_a" in g.maneuvers, "crossing a threshold teaches the leader a maneuver")
	var recorded := false
	for r in model.records:
		if r["kind"] == &"maneuver":
			recorded = true
	check(recorded, "the maneuver is written on the desk")
	var kills_before := g.experience
	var far := gm.get_centroid(g) + Vector3(200, 1, 0)
	var far_id := mm.spawn_neutral_minion(far, &"villager", far)
	await frames(5)
	var far_victim := mm.get_minion_by_id(far_id)
	far_victim.last_hit_by = 1
	far_victim.take_damage(999)
	await seconds(3.0)
	check(is_equal_approx(g.experience, kills_before), "a kill far from the group earns it nothing")

	# Teaching.
	var ids: Array[int] = [gm.get_members(g)[0].name.to_int()]
	var student := gm.split_off(g, ids)
	check(student.maneuvers.is_empty() and gm.groups_at_home(1).size() >= 2, "two groups stand at home")
	check(gm.begin_teaching(1), "the advisor can set a leader teaching another group")
	check(g.status == &"teaching" and student.status == &"teaching" and is_equal_approx(student.busy_seconds, Training.TEACHING_SECONDS), "both groups are busy for the teaching time")
	var p := MapPoint.find(get_tree(), &"SettlementSE")
	gm.set_order(student.id, {"route": [p.global_position], "route_points": [&"SettlementSE"], "dest_point": &"SettlementSE", "goal": OrderGoal.Goal.GO_HERE})
	check(not student.has_order(), "a busy group takes no orders")
	g.busy_seconds = 0.5
	student.busy_seconds = 0.5
	await seconds(2.0)
	check(&"placeholder_a" in student.maneuvers and student.busy_seconds <= 0.0 and student.status != &"teaching", "the student learns it and both are free again")

	# Relics.
	var place := world.get_node("World/Places/RelicAvatarSite") as RelicPlace
	var other := world.get_node("World/Places/RelicBossSite") as RelicPlace
	check(place.available and place.get_relic_index() >= 0, "a relic lies at the site")
	var home := gm.get_group(g.id)
	var avatar_point := MapPoint.find(get_tree(), &"AvatarSite")
	KnowledgeManager.request_dispatch({"group_ids": [home.id], "believed": {}, "route_points": [&"AvatarSite"],
		"route": [avatar_point.global_position], "dest_point": &"AvatarSite", "goal": OrderGoal.Goal.RETRIEVE})
	var t := 0.0
	while t < 300.0 and not (home.auto_courier and not home.has_order()):
		await seconds(2.0)
		t += 2.0
	check(not place.available, "the group took the relic up")
	check(home.auto_courier, "bringing it home sets the group's auto_courier flag")
	var has_relic_record := false
	for r in model.records:
		if r["kind"] == &"relic":
			has_relic_record = true
	check(has_relic_record, "the relic is written on the desk")

	# The other relic: a route point, and back where it lay if its carrier falls.
	Relic.at(other.get_relic_index()).apply(1, home)
	check(GameState.get_route_point_bonus(1) == 1, "a relic can grant route points")
	other._sync_available.rpc(false)
	RelicPlace.restore(get_tree(), other.get_relic_index())
	await frames(3)
	check(other.available, "a dropped relic lies where it was found")
	Engine.time_scale = 1.0
	KnowledgeManager.INSTANT_COMMANDS = false
