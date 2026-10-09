class_name GroupManager extends Node

## Host-authoritative unit groups (GDD §3–§5). Every player unit belongs to a
## group; orders go to groups, and groups walk their order's route point by
## point, then act on its goal:
##   - "go here" / "corrupt site" hold the destination whatever happens,
##   - "assess" waits there, then walks back home and reports,
##   - goals that fetch something (haul, capture, the dead, an offer) hand off
##     to a registered goal handler and then walk home.
## A group that can't reach its next point stops there, confused, until a
## courier brings new orders (GDD Q2 — the army stuck at the river).
##
## Groups at their own tower are watched from it and report live. Everything
## else reaches the owner only by courier or by a group coming home.

signal group_created(group: UnitGroup)
signal group_order_changed(group: UnitGroup)
signal group_arrived(group: UnitGroup)
signal group_returned_home(group: UnitGroup)
signal group_disbanded(group_id: int)

const TICK_INTERVAL: float = 0.25
## A group advances to its next route point when its centroid is this close.
const ADVANCE_RADIUS: float = 6.0
## Without getting this much closer for STALL_SECONDS, a group checks whether
## its next point is reachable at all.
const STALL_PROGRESS: float = 1.0
const STALL_SECONDS: float = 8.0
## A path that ends farther than this from the point means "can't get there".
const UNREACHABLE_GAP: float = 4.0
## PLACEHOLDER: tuning, not designed — seconds an assessing group watches its
## destination before heading home.
const ASSESS_SECONDS: float = 20.0
## Units this close to a map point put it on the map when they report.
const DISCOVER_RADIUS: float = 25.0
## How often groups at their tower report what the tower can see.
const HOME_REPORT_INTERVAL: float = 2.0
## Reserved group id for the Paladin when he takes orders like a group.
const AVATAR_GROUP_ID: int = -100
## PLACEHOLDER: tuning, not designed — a kill earns experience for the nearest
## group of the killer's within this distance.
const KILL_CREDIT_RADIUS: float = 25.0

signal maneuver_learned(group: UnitGroup, maneuver_id: StringName)

## Hooks for goals implemented by other systems (haul, capture, gather the
## dead, offer). Callable(group: UnitGroup) -> bool: true when done and the
## group should head home.
var goal_handlers: Dictionary[int, Callable] = {}

var _groups: Dictionary[int, UnitGroup] = {}
var _next_group_id: int = 1
var _tick_timer: float = 0.0
var _home_report_timer: float = 0.0

func _ready() -> void:
	var mm := get_parent().get_node_or_null("MinionManager") as MinionManager
	if mm:
		mm.minion_died.connect(_on_minion_died)

# --- Queries ---

func get_group(group_id: int) -> UnitGroup:
	return _groups.get(group_id)

func get_groups_for(peer_id: int) -> Array[UnitGroup]:
	var out: Array[UnitGroup] = []
	for g in _groups.values():
		if g.owner_peer_id == peer_id:
			out.append(g)
	return out

func all_groups() -> Array[UnitGroup]:
	var out: Array[UnitGroup] = []
	for g in _groups.values():
		out.append(g)
	return out

func get_members(group: UnitGroup) -> Array[MinionActor]:
	var out: Array[MinionActor] = []
	var mm := _mm()
	if mm == null:
		return out
	for mid in group.member_ids:
		var m := mm.get_minion_by_id(mid)
		if m and is_instance_valid(m) and m.can_take_damage():
			out.append(m)
	return out

func get_centroid(group: UnitGroup) -> Vector3:
	var members := get_members(group)
	if members.is_empty():
		return Vector3.INF
	var sum := Vector3.ZERO
	for m in members:
		sum += m.global_position
	return sum / float(members.size())

func snapshot(group: UnitGroup) -> Dictionary:
	## What a report says about a group.
	return {
		"id": group.id,
		"obs_tick": NetworkTime.tick,
		"pos": get_centroid(group),
		"count": get_members(group).size(),
		"status": group.status,
		"goal": group.get_goal() if group.has_order() else -1,
		"dest_point": group.order.get("dest_point", &""),
		"leader_id": group.leader_id,
		"experience": group.experience,
		"maneuvers": group.maneuvers.duplicate(),
	}

# --- Membership ---

func create_group(owner_peer_id: int, member_ids: Array[int]) -> UnitGroup:
	## Host-only.
	var g := UnitGroup.new()
	g.id = _next_group_id
	_next_group_id += 1
	g.owner_peer_id = owner_peer_id
	_groups[g.id] = g
	for mid in member_ids:
		add_member(g, mid)
	group_created.emit(g)
	return g

func add_member(group: UnitGroup, minion_id: int) -> void:
	var mm := _mm()
	var m := mm.get_minion_by_id(minion_id) if mm else null
	if m:
		var old := get_group(m.group_id)
		if old and old != group:
			old.member_ids.erase(minion_id)
			# The old group's fieldwork stance does not follow the unit.
			m.capture_mode = false
			m.parley_mode = false
		m.group_id = group.id
	if minion_id not in group.member_ids:
		group.member_ids.append(minion_id)
	if group.leader_id == -1:
		group.leader_id = minion_id

func join_home_group(peer_id: int, minion: MinionActor) -> UnitGroup:
	## A unit raised or trained at the tower joins the group mustering there,
	## or starts one.
	var home := _tower_site(peer_id)
	for g in get_groups_for(peer_id):
		if g.has_order():
			continue
		var c := get_centroid(g)
		if c == Vector3.INF or home == null:
			continue
		if _flat(c - home.global_position) <= MinionManager.MUSTER_RADIUS:
			add_member(g, minion.name.to_int())
			return g
	var ids: Array[int] = [minion.name.to_int()]
	return create_group(peer_id, ids)

func split_off(group: UnitGroup, minion_ids: Array[int]) -> UnitGroup:
	## Host-only: move some members into a new group (e.g. training, teaching).
	var g := create_group(group.owner_peer_id, [])
	for mid in minion_ids:
		group.member_ids.erase(mid)
		add_member(g, mid)
	if group.leader_id in minion_ids:
		group.leader_id = group.member_ids[0] if not group.member_ids.is_empty() else -1
	return g

# --- Orders ---

func set_order(group_id: int, order: Dictionary) -> void:
	## Host-only. Delivered by a courier (or instantly in debug).
	if group_id == AVATAR_GROUP_ID:
		_order_avatar(order)
		return
	var g := get_group(group_id)
	if g == null:
		return
	if g.busy_seconds > 0.0:
		KnowledgeManager.deliver_report(g.owner_peer_id, {"source": &"training",
			"lines": ["PLACEHOLDER: Group %d is busy teaching and cannot take orders yet." % g.id]})
		return
	g.clear_order()
	g.order = order.duplicate(true)
	g.status = &"moving"
	g._auto_courier_sent = false
	_send_to_waypoint(g)
	group_order_changed.emit(g)

func _order_avatar(order: Dictionary) -> void:
	var avatar := get_tree().current_scene.get_node_or_null("World/Avatar") as AvatarActor
	if avatar == null or avatar.avatar_ai == null:
		return
	var route: Array = order.get("route", [])
	if route.is_empty():
		return
	avatar.avatar_ai.command_route(route)

# --- Tick ---

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	_tick_timer += delta
	_home_report_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	var dt := _tick_timer
	_tick_timer = 0.0
	for g in _groups.values():
		_tick_group(g, dt)
	if _home_report_timer >= HOME_REPORT_INTERVAL:
		_home_report_timer = 0.0
		_report_groups_at_home()

func _tick_group(g: UnitGroup, dt: float) -> void:
	var members := get_members(g)
	if members.is_empty():
		return
	_note_points(g)
	var fighting := false
	for m in members:
		if m._state_machine.state == &"AttackState":
			fighting = true
			break
	if fighting:
		_gain_experience(g, Training.XP_PER_FIGHT_SECOND * dt)
	if g.busy_seconds > 0.0:
		g.busy_seconds -= dt
		if g.busy_seconds <= 0.0:
			_finish_teaching(g)
		return
	if not g.has_order():
		g.status = &"fighting" if fighting else (g.status if g.status in [&"teaching", &"training"] else &"holding")
		return
	if g.status == &"stuck":
		return  # Waits, confused, for new orders.
	var wp := g.current_waypoint()
	if wp == Vector3.INF:
		_tick_at_destination(g, dt, fighting)
		return
	g.status = &"fighting" if fighting else (&"returning" if g.order.get("homeward", false) else &"moving")
	var centroid := get_centroid(g)
	var d := _flat(centroid - wp)
	if d <= ADVANCE_RADIUS:
		g.route_index += 1
		g.best_distance = INF
		g.stall_timer = 0.0
		if g.current_waypoint() == Vector3.INF:
			_arrive(g)
		else:
			_send_to_waypoint(g)
		return
	if fighting:
		g.stall_timer = 0.0
		return
	if d < g.best_distance - STALL_PROGRESS:
		g.best_distance = d
		g.stall_timer = 0.0
		return
	g.stall_timer += dt
	if g.stall_timer >= STALL_SECONDS:
		g.stall_timer = 0.0
		if not _reachable(members[0], centroid, wp):
			_halt(g)
		else:
			_send_to_waypoint(g)  # Re-issue: members may have given up on a stale path.

func _arrive(g: UnitGroup) -> void:
	if g.order.get("homeward", false):
		g.clear_order()
		g.status = &"holding"
		group_returned_home.emit(g)
		_deliver_home_report(g)
		return
	g.goal_timer = 0.0
	group_arrived.emit(g)

func _tick_at_destination(g: UnitGroup, dt: float, fighting: bool) -> void:
	var goal := g.get_goal()
	if OrderGoal.holds_ground(goal):
		g.status = &"fighting" if fighting else &"holding"
		return
	if goal in goal_handlers:
		g.status = &"fighting" if fighting else &"working"
		var done: bool = (goal_handlers[goal] as Callable).call(g)
		if done:
			_head_home(g)
		return
	# Assess (and any goal without a handler yet): watch, then come home.
	g.status = &"fighting" if fighting else &"assessing"
	g.goal_timer += dt
	if g.goal_timer >= ASSESS_SECONDS:
		_head_home(g)

func _head_home(g: UnitGroup) -> void:
	## Walk back the way they came, then to the tower gate.
	var home := _tower_site(g.owner_peer_id)
	var back: Array = (g.order.get("route", []) as Array).duplicate()
	back.reverse()
	if not back.is_empty():
		back.pop_front()  # Already standing at the destination.
	if g.order.has("home_override"):
		back.append(g.order["home_override"])
	elif home:
		back.append(home.global_position)
	var order := g.order.duplicate(true)
	order["route"] = back
	order["homeward"] = true
	g.order = order
	g.route_index = 0
	g.best_distance = INF
	g.stall_timer = 0.0
	g.status = &"returning"
	if back.is_empty():
		_arrive(g)
	else:
		_send_to_waypoint(g)

func _halt(g: UnitGroup) -> void:
	g.status = &"stuck"
	var mm := _mm()
	for m in get_members(g):
		m.waypoint = m.global_position

func _send_to_waypoint(g: UnitGroup) -> void:
	var wp := g.current_waypoint()
	if wp == Vector3.INF:
		return
	var mm := _mm()
	if mm:
		mm.command_selection_move(g.member_ids, wp)

func _reachable(sample: MinionActor, from: Vector3, to: Vector3) -> bool:
	if sample == null or sample.nav_agent == null:
		return true
	var map_rid := sample.nav_agent.get_navigation_map()
	if not map_rid.is_valid():
		return true
	var path := NavigationServer3D.map_get_path(map_rid, from, to, true)
	if path.is_empty():
		return false
	return _flat(path[path.size() - 1] - to) <= UNREACHABLE_GAP

# --- Information ---

func log_sighting(group_id: int, entry: Dictionary) -> void:
	var g := get_group(group_id)
	if g == null:
		return
	g.field_log[int(entry.get("id", -1))] = entry

func notify_member_hit(minion: MinionActor) -> void:
	## Host-only. The first hit on a group with a runner sends one home.
	var g := get_group(minion.group_id)
	if g == null or not g.auto_courier or g._auto_courier_sent:
		return
	g._auto_courier_sent = true
	KnowledgeManager.send_runner_home(g, get_centroid(g))

func _note_points(g: UnitGroup) -> void:
	var c := get_centroid(g)
	if c == Vector3.INF:
		return
	for p in MapPoint.all_points(get_tree()):
		if p.point_id in g.discovered_points:
			continue
		if _flat(p.global_position - c) <= DISCOVER_RADIUS:
			g.discovered_points.append(p.point_id)
	for r in resources_near(c):
		g.seen_resources[r["site"]] = int(r["pile"])

func make_report(g: UnitGroup) -> Dictionary:
	## A group's report, emptying its log: what a courier or the group itself
	## carries home.
	return {
		"groups": [snapshot(g)],
		"sightings": g.take_log(),
		"points": g.take_points(),
		"resources": g.take_resources(),
	}

func resources_near(pos: Vector3) -> Array:
	## What the ledger learns: the goods piled at resource locations nearby.
	var out: Array = []
	if pos == Vector3.INF:
		return out
	for n in get_tree().get_nodes_in_group(ResourceSite.GROUP):
		var r := n as ResourceSite
		if r and _flat(r.global_position - pos) <= DISCOVER_RADIUS:
			out.append({"site": StringName(r.name), "pile": r.get_pile()})
	return out

func _deliver_home_report(g: UnitGroup) -> void:
	var report := make_report(g)
	report["source"] = &"returned"
	KnowledgeManager.deliver_report(g.owner_peer_id, report)

func _report_groups_at_home() -> void:
	## The tower sees whatever stands at its gate.
	for g in _groups.values():
		var home := _tower_site(g.owner_peer_id)
		if home == null:
			continue
		var c := get_centroid(g)
		if c == Vector3.INF or _flat(c - home.global_position) > home.radius:
			continue
		var report := make_report(g)
		report["source"] = &"home"
		KnowledgeManager.deliver_report(g.owner_peer_id, report)

# --- Deaths and succession ---

func _on_minion_died(minion: MinionActor) -> void:
	_credit_kill(minion)
	var g := get_group(minion.group_id)
	if g == null:
		return
	var mid := minion.name.to_int()
	g.member_ids.erase(mid)
	if g.member_ids.is_empty():
		_groups.erase(g.id)
		group_disbanded.emit(g.id)
		return
	if g.leader_id == mid:
		_succeed_leader(g)

func _succeed_leader(g: UnitGroup) -> void:
	## GDD Q36: when a leader dies someone steps up and remembers some of the
	## leader's maneuvers but loses others.
	g.leader_id = g.member_ids[0]
	var kept: Array[StringName] = []
	for m in g.maneuvers:
		if randf() < Training.SUCCESSION_KEEP_CHANCE:
			kept.append(m)
	g.maneuvers = kept
	g.experience *= Training.SUCCESSION_KEEP_EXPERIENCE

# --- Experience, maneuvers and teaching (GDD §5, Q35/Q36) ---

func _credit_kill(dead: MinionActor) -> void:
	## The killer's nearest group, if one was close, earns its leader experience.
	var killer := dead.last_hit_by
	if killer <= 0 or killer == dead.owner_peer_id:
		return
	var best: UnitGroup = null
	var best_d := KILL_CREDIT_RADIUS
	for g in get_groups_for(killer):
		var c := get_centroid(g)
		if c == Vector3.INF:
			continue
		var d := _flat(c - dead.global_position)
		if d <= best_d:
			best_d = d
			best = g
	if best:
		_gain_experience(best, Training.XP_PER_KILL)

func _gain_experience(g: UnitGroup, amount: float) -> void:
	g.experience += amount
	for m in Maneuver.all():
		if g.experience >= m.experience_required and m.id not in g.maneuvers:
			_learn(g, m.id)

func _learn(g: UnitGroup, maneuver_id: StringName) -> void:
	var m := Maneuver.find(maneuver_id)
	if m == null or maneuver_id in g.maneuvers:
		return
	g.maneuvers.append(maneuver_id)
	maneuver_learned.emit(g, maneuver_id)
	KnowledgeManager.deliver_report(g.owner_peer_id, {"source": &"training",
		"lines": ["PLACEHOLDER: The leader of group %d learned %s." % [g.id, m.display_name]],
		"records": [{"kind": &"maneuver", "title": m.display_name,
			"text": "PLACEHOLDER: Learned by the leader of group %d. %s" % [g.id, m.description]}]})

func groups_at_home(peer_id: int) -> Array[UnitGroup]:
	## Groups standing idle at their tower gate.
	var out: Array[UnitGroup] = []
	var mm := _mm()
	var gate := mm.get_courier_spawn_for(peer_id) if mm else null
	if gate == null:
		return out
	for g in get_groups_for(peer_id):
		var c := get_centroid(g)
		if g.has_order() or g.busy_seconds > 0.0 or g.status == &"training" or c == Vector3.INF:
			continue
		if _flat(c - gate.global_position) <= MinionManager.MUSTER_RADIUS:
			out.append(g)
	return out

func begin_teaching(peer_id: int) -> bool:
	## Host-only (advisor option). The best-taught leader at home teaches one
	## maneuver to the group at home that knows the fewest of his; both groups
	## are busy for Training.TEACHING_SECONDS. PLACEHOLDER: the advisor picks
	## the pair; choosing them by hand is not built.
	var home := groups_at_home(peer_id)
	home.sort_custom(func(a: UnitGroup, b: UnitGroup) -> bool:
		if a.maneuvers.size() != b.maneuvers.size():
			return a.maneuvers.size() > b.maneuvers.size()
		return a.experience > b.experience)
	for teacher in home:
		if teacher.maneuvers.is_empty():
			break
		var student: UnitGroup = null
		var lesson: StringName = &""
		for other in home:
			if other == teacher:
				continue
			for mid in teacher.maneuvers:
				if mid not in other.maneuvers:
					if student == null or other.maneuvers.size() < student.maneuvers.size():
						student = other
						lesson = mid
					break
		if student:
			teacher.busy_seconds = Training.TEACHING_SECONDS
			student.busy_seconds = Training.TEACHING_SECONDS
			teacher.status = &"teaching"
			student.status = &"teaching"
			student.teaching_maneuver = lesson
			KnowledgeManager.deliver_report(peer_id, {"source": &"training",
				"lines": ["PLACEHOLDER: The leader of group %d begins teaching group %d." % [teacher.id, student.id]]})
			return true
	KnowledgeManager.deliver_report(peer_id, {"source": &"training",
		"lines": ["PLACEHOLDER: There is no leader here with something to teach another group."]})
	return false

func _finish_teaching(g: UnitGroup) -> void:
	g.status = &"holding"
	if g.teaching_maneuver != &"":
		_learn(g, g.teaching_maneuver)
		g.teaching_maneuver = &""

# --- Helpers ---

func _mm() -> MinionManager:
	var scene := get_tree().current_scene
	return scene.get_node_or_null("MinionManager") as MinionManager if scene else null

func _tower_site(peer_id: int) -> CorruptionSite:
	for n in get_tree().get_nodes_in_group(Tower.GROUP):
		var t := n as Tower
		if t and t.owner_peer_id == peer_id:
			return t.site
	return null

static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
