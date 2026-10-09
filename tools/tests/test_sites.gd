extends "res://tools/tests/test_base.gd"

## Corruption sites (GDD §7): threshold + rate, rivals, slipping, purifying,
## capabilities, the tower as a permanent site.

func run_tests() -> void:
	var world := await load_world()
	var gs := GameState
	var mm := world.get_node("MinionManager") as MinionManager
	var chapel := world.get_node("SiteChapel") as CorruptionSite
	check(chapel != null and chapel.site_type != null, "chapel site exists with a type")
	check(not gs.has_capability(1, SiteCapability.DOMINATE_THRALLS), "no chapel capability at start")

	# One skeleton is below the threshold: nothing happens.
	Engine.time_scale = 4.0
	var near := chapel.global_position + Vector3(2, 1, 0)
	mm.spawn_unit_for_peer(1, &"", near)
	await frames(5)
	_hold_all(mm, 1, chapel.global_position)
	await seconds(4.0)
	check(chapel.progress == 0.0, "one unit under the threshold does not corrupt")

	# Enough units: progress rises, then the site is held.
	for i in 4:
		mm.spawn_unit_for_peer(1, &"", near + Vector3(0, 0, i))
	await frames(5)
	_hold_all(mm, 1, chapel.global_position)
	await seconds(6.0)
	check(chapel.progress > 0.0 and chapel.progress_peer_id == 1, "threshold met: corruption progresses")
	chapel.progress = 0.99
	await seconds(2.0)
	check(chapel.holder_peer_id == 1, "site taken at full progress")
	check(gs.has_capability(1, SiteCapability.DOMINATE_THRALLS), "holding the chapel grants its capability")

	# Unguarded: it slips back.
	for m in mm.get_minions_for_player(1):
		mm.notify_minion_died(m)
	await frames(5)
	chapel.progress = 0.02
	await seconds(6.0)
	check(chapel.holder_peer_id == -1, "unguarded site slips back to neutral")
	check(not gs.has_capability(1, SiteCapability.DOMINATE_THRALLS), "capability lost with the site")

	# The good faction purifies half-done corruption.
	chapel.progress = 0.5
	chapel.progress_peer_id = 1
	mm.spawn_neutral_minion(near, &"holy_knight")
	await seconds(3.0)
	check(chapel.progress < 0.5, "good faction purifies corruption it stands in")

	# The tower is a permanent site held by its owner.
	var towers := world.get_node("World/Env/Towers")
	var mine: CorruptionSite = null
	for t in towers.get_children():
		if t is Tower and (t as Tower).owner_peer_id == 1:
			mine = (t as Tower).site
	check(mine != null and mine.permanent and mine.holder_peer_id == 1, "your tower is a permanent site you hold")
	check(gs.has_capability(1, SiteCapability.TOWER), "the tower grants its capability")
	Engine.time_scale = 1.0

func _hold_all(mm: MinionManager, peer: int, pos: Vector3) -> void:
	for m in mm.get_minions_for_player(peer):
		if m.minion_trait == &"":
			m.waypoint = pos
