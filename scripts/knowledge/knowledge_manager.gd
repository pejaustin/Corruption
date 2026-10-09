extends Node

## Autoload. Information and orders (GDD §3–§4): couriers carry everything.
##
## Each player has a WorldModel on their own machine. It changes only when:
##   - their tower sees something at its gate (GroupManager home reports),
##   - a courier or a group comes home with a report,
##   - a beacon rises over a site (everyone sees those),
##   - they drive the Paladin, who lets his controller see the field.
## Orders leave the tower only by courier. Couriers are scarce (a pool per
## player), can be killed or captured, and a captured courier's papers can be
## read by a captor with that ability (Q4; how it's unlocked is Austin's).
##
## The simulation is host-authoritative; reports travel host -> owner by RPC.

signal report_received(report: Dictionary)
## The local player's advisor says something (shown as a subtitle).
signal advisor_spoke(line: String)
signal couriers_changed(count: int)

## Debug: deliver orders instantly instead of by courier.
static var INSTANT_COMMANDS: bool = false

## Trait tags of courier units.
const COURIER_TRAITS: Array[StringName] = [&"courier"]
## Units no report ever mentions as sightings (your own staff).
const UNTRACKED_TRAITS: Array[StringName] = [&"courier", &"advisor"]
## Reserved id of the Paladin in reports, pieces and orders.
const AVATAR_ID: int = GroupManager.AVATAR_GROUP_ID
## How often the controller's view through the Paladin refreshes their model.
const AVATAR_SIGHT_INTERVAL: float = 0.5
## Units within this distance of the Paladin are seen by his controller.
const AVATAR_SIGHT_RADIUS: float = 30.0

var _models: Dictionary[int, WorldModel] = {}
var _next_command_id: int = 1
var _avatar_sight_timer: float = 0.0

## Host: couriers waiting at each player's tower.
var couriers_home: Dictionary[int, int] = {}
## Host: players able to read captured couriers' papers (ticket #543).
var can_read_couriers: Dictionary[int, bool] = {}
## Host: courier trainings in progress: { peer_id, unit_id, remaining }.
var _trainings: Array[Dictionary] = []

func _ready() -> void:
	GameState.site_changed.connect(_on_site_changed)

func get_model(peer_id: int) -> WorldModel:
	if peer_id not in _models:
		var model := WorldModel.new()
		_models[peer_id] = model
		_seed_known_points(model)
	return _models[peer_id]

func has_model(peer_id: int) -> bool:
	return peer_id in _models

func local_model() -> WorldModel:
	return get_model(multiplayer.get_unique_id())

func current_tick() -> int:
	return NetworkTime.tick

func reset() -> void:
	_models.clear()
	couriers_home.clear()
	can_read_couriers.clear()
	_trainings.clear()
	_next_command_id = 1

func _process(delta: float) -> void:
	_seed_pending_models()
	_avatar_sight_timer += delta
	if _avatar_sight_timer >= AVATAR_SIGHT_INTERVAL:
		_avatar_sight_timer = 0.0
		_update_avatar_sight()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_tick_trainings(delta)

# --- Map knowledge ---

func _seed_known_points(model: WorldModel) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	for p in MapPoint.all_points(tree):
		if p.known_at_start:
			model.known_points[p.point_id] = true

func _seed_pending_models() -> void:
	## Models made before the world loaded learn the starting points late.
	for model in _models.values():
		if model.known_points.is_empty():
			_seed_known_points(model)

func _on_site_changed(site: Node, _old: int, new_holder: int, _first: bool) -> void:
	## Beacons are visible from every balcony (GDD §7), so every player learns
	## a change of hands — though not who did it beyond the beacon's colour.
	for model in _models.values():
		model.believed_sites[StringName(site.name)] = {"holder": new_holder, "tick": current_tick()}
		model.changed.emit()

# --- Reports ---

func deliver_report(peer_id: int, report: Dictionary) -> void:
	## Host-only: hand a report to its owner's machine.
	if peer_id <= 0:
		return
	if peer_id == multiplayer.get_unique_id():
		_apply_report(report)
	elif peer_id in multiplayer.get_peers():
		_report_rpc.rpc_id(peer_id, report)

@rpc("authority", "reliable")
func _report_rpc(report: Dictionary) -> void:
	_apply_report(report)

func _apply_report(report: Dictionary) -> void:
	var model := local_model()
	var tick := current_tick()
	var source: StringName = report.get("source", &"courier")
	for g in report.get("groups", []):
		model.update_group(g, tick, source)
	for gid in report.get("lost_groups", []):
		model.believed_groups.erase(int(gid))
	for s in report.get("sightings", []):
		if int(s.get("owner_peer_id", -1)) == multiplayer.get_unique_id():
			continue
		model.update_enemy(s)
	var new_points: Array[StringName] = []
	for pid in report.get("points", []):
		var id := StringName(pid)
		if not model.is_point_known(id):
			model.known_points[id] = true
			new_points.append(id)
	for r in report.get("resources", []):
		model.ledger[StringName(r.get("site", &""))] = {"pile": int(r.get("pile", 0)), "tick": tick}
	for o in report.get("orders", []):
		var cmd := int(o.get("cmd_id", -1))
		if cmd in model.orders:
			model.orders[cmd]["stage"] = o.get("stage", &"delivered")
	var lines := _report_lines(report, new_points)
	if source != &"home" or not lines.is_empty():
		pass
	if not lines.is_empty():
		model.last_report_lines = lines
		model.add_record(&"report", _report_title(report), "\n".join(lines), tick)
		for line in lines:
			advisor_spoke.emit(line)
	model.changed.emit()
	report_received.emit(report)

func _report_title(report: Dictionary) -> String:
	## PLACEHOLDER: wording, not written by Austin.
	match report.get("source", &"courier"):
		&"returned":
			return "A group came home"
		&"runner":
			return "A runner came home"
		&"captured":
			return "Captured papers"
		&"training":
			return "Training"
	return "A courier came home"

func _report_lines(report: Dictionary, new_points: Array[StringName]) -> Array[String]:
	## PLACEHOLDER: wording, not written by Austin (the advisor's voice, #585).
	var out: Array[String] = []
	var source: StringName = report.get("source", &"courier")
	if source == &"home":
		return out  # Watching your own gate is not news.
	for line in report.get("lines", []):
		out.append(String(line))
	for g in report.get("groups", []):
		var where := _point_name(StringName(g.get("dest_point", &"")))
		out.append("Group %d: %d strong, %s%s." % [
			int(g.get("id", 0)), int(g.get("count", 0)), String(g.get("status", &"holding")),
			(" near %s" % where) if where != "" else ""])
	for gid in report.get("lost_groups", []):
		out.append("Group %d is gone." % int(gid))
	var enemies: int = (report.get("sightings", []) as Array).size()
	if enemies > 0:
		out.append("They saw %d of the enemy." % enemies)
	if not new_points.is_empty():
		var names: Array[String] = []
		for p in new_points:
			names.append(_point_name(p))
		out.append("New places for the map: %s." % ", ".join(names))
	for f in report.get("failures", []):
		out.append("Could not find group %d where you thought it was." % int(f.get("group_id", 0)))
	return out

func _point_name(point_id: StringName) -> String:
	if point_id == &"":
		return ""
	var p := MapPoint.find(get_tree(), point_id)
	return p.get_label() if p else String(point_id)

func _update_avatar_sight() -> void:
	## The Paladin's owner always knows where he is (corruption binds them);
	## while driving him they also see what's around him (GDD §8).
	var me := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 1
	if not GameState.is_avatar_owner(me):
		if has_model(me):
			get_model(me).believed_groups.erase(AVATAR_ID)
		return
	var scene := get_tree().current_scene
	var avatar := scene.get_node_or_null("World/Avatar") as AvatarActor if scene else null
	if avatar == null or avatar.hp <= 0:
		return
	var model := get_model(me)
	model.believed_groups[AVATAR_ID] = {
		"id": AVATAR_ID, "pos": avatar.global_position, "count": 1,
		"status": &"possessed" if GameState.is_avatar(me) else &"holding",
		"goal": -1, "dest_point": &"", "tick": current_tick(), "source": &"avatar",
	}
	if GameState.is_avatar(me):
		var mm := scene.get_node_or_null("MinionManager") as MinionManager
		if mm:
			for m in mm.get_all_minions():
				if m.get_allegiance() == me or m.minion_trait in UNTRACKED_TRAITS:
					continue
				if m.global_position.distance_to(avatar.global_position) <= AVATAR_SIGHT_RADIUS:
					model.update_enemy({"id": m.name.to_int(), "pos": m.global_position,
						"owner_peer_id": m.owner_peer_id, "faction": m.faction, "observed_tick": current_tick()})
	model.changed.emit()

func notify_minion_removed(minion_id: int) -> void:
	## Units that are gone stop being "seen" only when someone reports it; the
	## local model keeps its stale belief. Kept for API compatibility.
	pass

# --- Orders ---

func request_dispatch(order: Dictionary) -> int:
	## Owner-local: the advisor sends an order. `order` = { group_ids, believed
	## (group id -> Vector3), route_points: Array[StringName], route:
	## Array[Vector3], dest_point, goal }. Returns the command id.
	var cmd_id := _next_command_id
	_next_command_id += 1
	var entry := order.duplicate(true)
	entry["cmd_id"] = cmd_id
	var model := local_model()
	model.orders[cmd_id] = {
		"group_ids": order.get("group_ids", []), "route_points": order.get("route_points", []),
		"dest_point": order.get("dest_point", &""), "goal": order.get("goal", OrderGoal.Goal.GO_HERE),
		"stage": &"requested", "courier_id": -1, "tick": current_tick(),
	}
	model.changed.emit()
	if multiplayer.is_server():
		_dispatch(multiplayer.get_unique_id(), entry)
	else:
		_request_dispatch_rpc.rpc_id(1, entry)
	return cmd_id

@rpc("any_peer", "reliable")
func _request_dispatch_rpc(order: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_dispatch(multiplayer.get_remote_sender_id(), order)

func _dispatch(peer_id: int, order: Dictionary) -> void:
	## Host-only.
	var cmd_id := int(order.get("cmd_id", -1))
	var gm := _gm()
	var mm := _mm()
	if gm == null or mm == null:
		return
	var core := {
		"route": order.get("route", []), "route_points": order.get("route_points", []),
		"dest_point": order.get("dest_point", &""), "goal": order.get("goal", OrderGoal.Goal.GO_HERE),
		"promise": order.get("promise", &""), "issued_tick": current_tick(),
	}
	var group_ids: Array = order.get("group_ids", [])
	if INSTANT_COMMANDS:
		for gid in group_ids:
			gm.set_order(int(gid), core)
		_dispatch_result(peer_id, cmd_id, &"delivered", -1)
		return
	if get_couriers_home(peer_id) <= 0:
		_dispatch_result(peer_id, cmd_id, &"refused", -1)
		return
	var gate := mm.get_courier_spawn_for(peer_id)
	if gate == null:
		_dispatch_result(peer_id, cmd_id, &"refused", -1)
		return
	var believed: Dictionary = order.get("believed", {})
	var legs: Array[Dictionary] = []
	for gid in group_ids:
		legs.append({
			"source_pos": believed.get(gid, believed.get(int(gid), gate.global_position)),
			"sub_orders": [{"group_id": int(gid), "order": core, "cmd_id": cmd_id}],
		})
	legs = _order_legs_greedy(gate.global_position, legs)
	var first: Vector3 = legs[0]["source_pos"] if not legs.is_empty() else gate.global_position
	var scout_route: Array = []
	if group_ids.is_empty():
		scout_route = (order.get("route", []) as Array).duplicate()
		if not scout_route.is_empty():
			first = scout_route[0]
	var courier_id := mm.spawn_named_minion_for_peer(peer_id, &"courier", gate.global_position, first)
	if courier_id < 0:
		_dispatch_result(peer_id, cmd_id, &"refused", -1)
		return
	_set_couriers_home(peer_id, get_couriers_home(peer_id) - 1)
	var courier := mm.get_minion_by_id(courier_id)
	if courier:
		courier.delivery_legs = legs
		courier.scout_route = scout_route
		courier.return_pos = gate.global_position
		courier.return_zone = gate as Area3D
		courier.carried_orders = [order.duplicate(true)]
	_dispatch_result(peer_id, cmd_id, &"dispatched", courier_id)

func _dispatch_result(peer_id: int, cmd_id: int, stage: StringName, courier_id: int) -> void:
	if peer_id == multiplayer.get_unique_id():
		_apply_dispatch_result(cmd_id, stage, courier_id)
	else:
		_dispatch_result_rpc.rpc_id(peer_id, cmd_id, stage, courier_id)

@rpc("authority", "reliable")
func _dispatch_result_rpc(cmd_id: int, stage: StringName, courier_id: int) -> void:
	_apply_dispatch_result(cmd_id, stage, courier_id)

func _apply_dispatch_result(cmd_id: int, stage: StringName, courier_id: int) -> void:
	var model := local_model()
	if cmd_id in model.orders:
		model.orders[cmd_id]["stage"] = stage
		model.orders[cmd_id]["courier_id"] = courier_id
	if stage == &"refused":
		advisor_spoke.emit("PLACEHOLDER: There is no courier at the tower to carry that.")
	elif stage == &"dispatched":
		advisor_spoke.emit("PLACEHOLDER: The courier is on its way.")
	model.changed.emit()

func _order_legs_greedy(start: Vector3, legs: Array[Dictionary]) -> Array[Dictionary]:
	## Nearest-first visiting order for a courier's stops.
	var remaining: Array[Dictionary] = legs.duplicate()
	var ordered: Array[Dictionary] = []
	var cursor: Vector3 = start
	while not remaining.is_empty():
		var best_i: int = 0
		var best_d2: float = INF
		for i in remaining.size():
			var d2 := cursor.distance_squared_to(remaining[i].get("source_pos", cursor))
			if d2 < best_d2:
				best_d2 = d2
				best_i = i
		var pick: Dictionary = remaining[best_i]
		ordered.append(pick)
		remaining.remove_at(best_i)
		cursor = pick.get("source_pos", cursor)
	return ordered

# --- Couriers coming home, dying, captured ---

func courier_arrived_home(courier: MinionActor) -> void:
	## Host-only: a courier walked back through its gate.
	var peer := courier.owner_peer_id
	_set_couriers_home(peer, get_couriers_home(peer) + 1)
	var report := courier.carried_report.duplicate(true)
	report["source"] = &"runner" if courier.is_runner else &"courier"
	var sightings: Array = report.get("sightings", [])
	sightings.append_array(courier._field_log.values())
	report["sightings"] = sightings
	var points: Array = report.get("points", [])
	for p in courier.discovered_points:
		if p not in points:
			points.append(p)
	report["points"] = points
	deliver_report(peer, report)

func courier_lost(courier: MinionActor, killer_peer: int) -> void:
	## Host-only: a courier died on the road. Killed by a rival, it counts as
	## captured; with the ability, the captor reads what it carried.
	if killer_peer <= 0 or killer_peer == courier.owner_peer_id:
		return
	if not can_read_couriers.get(killer_peer, false):
		return
	var lines: Array[String] = []
	for o in courier.carried_orders:
		lines.append("PLACEHOLDER: %s ordered %d group(s) to %s: %s." % [
			GameState.get_player_name(courier.owner_peer_id), (o.get("group_ids", []) as Array).size(),
			_point_name(StringName(o.get("dest_point", &""))), OrderGoal.name_of(int(o.get("goal", 0)))])
	var report := courier.carried_report.duplicate(true)
	report["source"] = &"captured"
	report["lines"] = lines
	report.erase("groups")  # Their groups, not yours: kept as text only.
	deliver_report(killer_peer, report)

func send_runner_home(group: UnitGroup, from_pos: Vector3) -> void:
	## Host-only: a group sends a runner home with its report (ticket #544).
	var mm := _mm()
	var gm := _gm()
	if mm == null or gm == null:
		return
	var gate := mm.get_courier_spawn_for(group.owner_peer_id)
	if gate == null:
		return
	var id := mm.spawn_named_minion_for_peer(group.owner_peer_id, &"courier", from_pos, gate.global_position)
	var runner := mm.get_minion_by_id(id)
	if runner == null:
		return
	runner.is_runner = true
	runner.return_pos = gate.global_position
	runner.return_zone = gate as Area3D
	var report := gm.make_report(group)
	report["lines"] = ["PLACEHOLDER: Group %d is under attack." % group.id]
	runner.carried_report = report
	# A runner is an extra courier: it joins the pool when it arrives.

# --- Courier pool and training ---

func get_couriers_home(peer_id: int) -> int:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		return couriers_home.get(peer_id, 0)
	return local_model().couriers_home

func give_starting_couriers(peer_id: int) -> void:
	## Host-only, once per player at match start (GDD Q38).
	_set_couriers_home(peer_id, MatchConfig.STARTING_COURIERS)

func _set_couriers_home(peer_id: int, count: int) -> void:
	couriers_home[peer_id] = maxi(0, count)
	if peer_id == multiplayer.get_unique_id():
		_sync_couriers(couriers_home[peer_id])
	elif peer_id in multiplayer.get_peers():
		_sync_couriers.rpc_id(peer_id, couriers_home[peer_id])

@rpc("authority", "reliable")
func _sync_couriers(count: int) -> void:
	local_model().couriers_home = count
	couriers_changed.emit(count)

func request_train_courier() -> void:
	## Owner-local (advisor option). One courier trains one regular unit at the
	## tower; both are busy until it's done (GDD Q5).
	if multiplayer.is_server():
		_train_courier(multiplayer.get_unique_id())
	else:
		_request_train_rpc.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_train_rpc() -> void:
	if multiplayer.is_server():
		_train_courier(multiplayer.get_remote_sender_id())

func can_train_courier(peer_id: int) -> bool:
	return get_couriers_home(peer_id) > 0 and _unit_at_home(peer_id) != null

func _train_courier(peer_id: int) -> void:
	var unit := _unit_at_home(peer_id)
	if unit == null or get_couriers_home(peer_id) <= 0:
		deliver_report(peer_id, {"source": &"training", "lines": ["PLACEHOLDER: There is no one here to train."]})
		return
	_set_couriers_home(peer_id, get_couriers_home(peer_id) - 1)
	var gm := _gm()
	var g := gm.get_group(unit.group_id) if gm else null
	if g:
		var ids: Array[int] = [unit.name.to_int()]
		var trainee := gm.split_off(g, ids)
		trainee.status = &"training"
	_trainings.append({"peer_id": peer_id, "unit_id": unit.name.to_int(), "remaining": Training.COURIER_TRAINING_SECONDS})
	deliver_report(peer_id, {"source": &"training", "lines": ["PLACEHOLDER: A courier begins training one of ours."]})

func _tick_trainings(delta: float) -> void:
	var done: Array[Dictionary] = []
	for t in _trainings:
		t["remaining"] = float(t["remaining"]) - delta
		if float(t["remaining"]) <= 0.0:
			done.append(t)
	for t in done:
		_trainings.erase(t)
		var mm := _mm()
		var peer := int(t["peer_id"])
		var unit := mm.get_minion_by_id(int(t["unit_id"])) if mm else null
		if unit and unit.can_take_damage():
			# The trainee becomes a courier; the trainer comes back with it.
			mm.notify_minion_died(unit)
			_set_couriers_home(peer, get_couriers_home(peer) + 2)
			deliver_report(peer, {"source": &"training", "lines": ["PLACEHOLDER: A new courier is ready."]})
		else:
			_set_couriers_home(peer, get_couriers_home(peer) + 1)

func is_training(unit_id: int) -> bool:
	for t in _trainings:
		if int(t["unit_id"]) == unit_id:
			return true
	return false

func _unit_at_home(peer_id: int) -> MinionActor:
	var mm := _mm()
	var gm := _gm()
	if mm == null or gm == null:
		return null
	var site: CorruptionSite = null
	for n in get_tree().get_nodes_in_group(Tower.GROUP):
		var t := n as Tower
		if t and t.owner_peer_id == peer_id:
			site = t.site
	if site == null:
		return null
	for m in mm.get_minions_for_player(peer_id):
		if m.minion_trait != &"" or not m.can_take_damage() or is_training(m.name.to_int()):
			continue
		var g := gm.get_group(m.group_id)
		if g and g.has_order():
			continue
		var off := m.global_position - site.global_position
		if Vector2(off.x, off.z).length() <= site.radius:
			return m
	return null

# --- Helpers ---

func _mm() -> MinionManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("MinionManager") as MinionManager if scene else null

func _gm() -> GroupManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("GroupManager") as GroupManager if scene else null
