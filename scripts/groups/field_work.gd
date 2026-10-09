class_name FieldWork extends Node

## The goals that fetch something (GDD §5–§6), run for GroupManager:
##   - carry the dead home: pick up bodies near the destination, bring them to
##     the tower, where each becomes remains to raise at the summoning circle;
##   - bring back a living human: subdue a human without killing them (blows
##     stop short of death), carry them — hurting the carrier hurts the
##     captive — to a corrupted chapel you hold, where they become a thrall;
##   - haul the goods home: load goods piled at a resource location, carry
##     them to the tower's treasury (carriers killed by a rival lose them to
##     the killer);
##   - take an offer to the noble: carry goods from the treasury and buy a
##     noble with them and a promise (spare their settlement, or assassinate
##     a rival).
## Host-only. One node in the world.

## Units work within this distance of their order's destination.
const WORK_RADIUS: float = 20.0
const PICKUP_DISTANCE: float = 2.0
## PLACEHOLDER: tuning, not designed — a fighting human can be taken once at
## or below this share of health.
const SUBDUE_FRACTION: float = 0.4
## PLACEHOLDER: tuning — share of a carrier's damage the captive takes.
const CAPTIVE_HURT_SHARE: float = 0.5
## PLACEHOLDER: tuning — goods one unit carries.
const CARRY_GOODS: int = 5
## PLACEHOLDER: tuning — goods a noble asks for (what a bought noble gives is
## Austin's, ticket #586).
const NOBLE_PRICE: int = 20
## Give up a fetching goal after this many seconds at the destination.
const WORK_TIMEOUT: float = 60.0

static var instance: FieldWork

func _ready() -> void:
	instance = self
	var gm := get_parent().get_node_or_null("GroupManager") as GroupManager
	if gm == null:
		return
	gm.goal_handlers[OrderGoal.Goal.GATHER_DEAD] = _gather_dead
	gm.goal_handlers[OrderGoal.Goal.CAPTURE] = _capture
	gm.goal_handlers[OrderGoal.Goal.HAUL] = _haul
	gm.goal_handlers[OrderGoal.Goal.OFFER] = _offer
	gm.group_order_changed.connect(_on_order_changed)
	gm.group_returned_home.connect(_unload)

# --- Goal handlers (return true when done: the group heads home) ---

func _gather_dead(g: UnitGroup) -> bool:
	var mm := _mm()
	var dest := _destination(g)
	var free: Array[Body] = []
	for b in mm.get_bodies():
		if _flat(b.global_position - dest) <= WORK_RADIUS:
			free.append(b)
	var all_carry := true
	for m in _gm().get_members(g):
		if m.carrying != &"":
			continue
		all_carry = false
		var b := _nearest(m.global_position, free)
		if b == null:
			continue
		if _flat(b.global_position - m.global_position) <= PICKUP_DISTANCE:
			mm.take_body(b)
			mm.set_carry(m, &"body")
			free.erase(b)
		else:
			m.waypoint = b.global_position
	return all_carry or free.is_empty() or _timed_out(g)

func _capture(g: UnitGroup) -> bool:
	var mm := _mm()
	var dest := _destination(g)
	var humans: Array[Node3D] = []
	for m in mm.get_all_minions():
		if m.is_human and m.owner_peer_id <= 0 and m.can_take_damage() and _flat(m.global_position - dest) <= WORK_RADIUS:
			humans.append(m)
	var all_carry := true
	var any_captive := false
	for m in _gm().get_members(g):
		m.capture_mode = true
		if m.carrying == &"captive":
			any_captive = true
			continue
		all_carry = false
		var h := _nearest(m.global_position, humans) as MinionActor
		if h == null:
			continue
		var subdued := h.attack_damage == 0 or h.hp <= int(h.get_max_hp() * SUBDUE_FRACTION)
		if subdued and _flat(h.global_position - m.global_position) <= PICKUP_DISTANCE:
			m.captive_hp = h.hp
			m.captive_type = h.minion_type_id
			mm.despawn_minion(h)
			mm.set_carry(m, &"captive")
			humans.erase(h)
			any_captive = true
		else:
			m.waypoint = h.global_position
	var done := (any_captive and (all_carry or humans.is_empty())) or _timed_out(g)
	if done:
		for m in _gm().get_members(g):
			m.capture_mode = false
		var chapel := _held_chapel(g.owner_peer_id, dest)
		if chapel:
			g.order["home_override"] = chapel.global_position
	return done

func _haul(g: UnitGroup) -> bool:
	var mm := _mm()
	var site := ResourceSite.near(get_tree(), _destination(g), WORK_RADIUS)
	if site == null:
		return true
	var all_carry := true
	for m in _gm().get_members(g):
		if m.carrying != &"":
			continue
		all_carry = false
		if _flat(site.global_position - m.global_position) <= site.radius:
			var n := site.take(CARRY_GOODS)
			if n > 0:
				mm.set_carry(m, &"goods", n)
		else:
			m.waypoint = site.global_position
	return all_carry or site.get_pile() <= 0 or _timed_out(g)

func _offer(g: UnitGroup) -> bool:
	var mm := _mm()
	var dest := _destination(g)
	var goods := 0
	for m in _gm().get_members(g):
		if m.carrying == &"goods":
			goods += m.carry_amount
	var noble: MinionActor = null
	for m in mm.get_all_minions():
		if m.is_noble and m.owner_peer_id <= 0 and m.can_take_damage() and _flat(m.global_position - dest) <= WORK_RADIUS:
			noble = m
			break
	var lines: Array[String] = []
	if noble == null:
		lines.append("PLACEHOLDER: There was no noble there to make the offer to.")
	elif goods < NOBLE_PRICE:
		lines.append("PLACEHOLDER: The noble wanted more than we carried.")
	else:
		var left := NOBLE_PRICE
		for m in _gm().get_members(g):
			if m.carrying != &"goods" or left <= 0:
				continue
			var used := mini(left, m.carry_amount)
			left -= used
			mm.set_carry(m, &"goods" if m.carry_amount - used > 0 else &"", m.carry_amount - used)
		var promise: StringName = g.order.get("promise", &"")
		if promise == &"":
			promise = &"spare"
		var s := Settlement.find(get_tree(), noble.settlement_name)
		if s:
			s.promises[g.owner_peer_id] = promise
		mm.set_unit_owner(noble, g.owner_peer_id)
		lines.append("PLACEHOLDER: The noble accepted, on your promise to %s." % ("spare their settlement" if promise == &"spare" else "assassinate a rival"))
	g.order["report_lines"] = lines
	return true

# --- Order changes, unloading, deaths ---

func _on_order_changed(g: UnitGroup) -> void:
	for m in _gm().get_members(g):
		m.capture_mode = false
	if g.get_goal() != OrderGoal.Goal.OFFER:
		return
	# Goods for an offer come from the treasury: those at home load up.
	var mm := _mm()
	var gate := mm.get_courier_spawn_for(g.owner_peer_id)
	if gate == null:
		return
	for m in _gm().get_members(g):
		if m.carrying != &"" or _flat(m.global_position - gate.global_position) > MinionManager.MUSTER_RADIUS:
			continue
		var n := mini(CARRY_GOODS, mm.get_treasury(g.owner_peer_id))
		if n <= 0:
			break
		mm.add_treasury(g.owner_peer_id, -n)
		mm.set_carry(m, &"goods", n)

func _unload(g: UnitGroup) -> void:
	var mm := _mm()
	var peer := g.owner_peer_id
	var bodies := 0
	var goods := 0
	var thralls := 0
	var at_chapel := _held_chapel(peer, _gm().get_centroid(g), 25.0) != null
	for m in _gm().get_members(g):
		match m.carrying:
			&"body":
				bodies += 1
			&"goods":
				goods += m.carry_amount
			&"captive":
				if at_chapel:
					mm.spawn_unit_for_peer(peer, &"thrall", m.global_position + Vector3(1, 0.5, 0))
					thralls += 1
				else:
					bodies += 1  # Brought to the tower instead: killed, to be raised.
		if m.carrying != &"":
			mm.set_carry(m, &"")
	if bodies > 0:
		mm.add_remains(peer, bodies)
	if goods > 0:
		mm.add_treasury(peer, goods)
	var lines: Array[String] = []
	lines.append_array(g.order.get("report_lines", []))
	if bodies > 0:
		lines.append("PLACEHOLDER: %d bodies laid by the summoning circle." % bodies)
	if goods > 0:
		lines.append("PLACEHOLDER: %d goods carried into the treasure room." % goods)
	if thralls > 0:
		lines.append("PLACEHOLDER: %d captives dominated at the chapel." % thralls)
	if not lines.is_empty():
		KnowledgeManager.deliver_report(peer, {"source": &"returned", "lines": lines})

static func on_unit_died(m: MinionActor) -> void:
	## Host-only, from MinionActor._die.
	var scene := m.get_tree().current_scene
	var mm := scene.get_node_or_null("MinionManager") as MinionManager if scene else null
	if mm == null:
		return
	if m.is_human and m.owner_peer_id <= 0:
		mm.spawn_body(m.global_position)
		Settlement.on_human_killed(m)
	match m.carrying:
		&"body", &"captive":
			mm.spawn_body(m.global_position)
		&"goods":
			# Stolen: a rival who struck the carrier picks the goods up.
			for other in mm.get_minions_for_player(m.last_hit_by):
				if other.carrying == &"" and other.minion_trait == &"" and other.global_position.distance_to(m.global_position) <= 4.0:
					mm.set_carry(other, &"goods", m.carry_amount)
					break

static func on_carrier_hit(m: MinionActor, amount: int) -> void:
	## Host-only: a captive shares its carrier's wounds and can die of them.
	if m.carrying != &"captive":
		return
	m.captive_hp -= int(amount * CAPTIVE_HURT_SHARE)
	if m.captive_hp <= 0:
		var mm := m.get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
		if mm:
			mm.set_carry(m, &"")
			mm.spawn_body(m.global_position)

# --- Helpers ---

func _destination(g: UnitGroup) -> Vector3:
	var route: Array = g.order.get("route", [])
	return route[route.size() - 1] if not route.is_empty() else _gm().get_centroid(g)

func _timed_out(g: UnitGroup) -> bool:
	g.goal_timer += GroupManager.TICK_INTERVAL
	return g.goal_timer >= WORK_TIMEOUT

func _held_chapel(peer_id: int, near_pos: Vector3, max_dist: float = INF) -> CorruptionSite:
	var best: CorruptionSite = null
	var best_d := max_dist
	for n in GameState.get_held_sites(peer_id):
		var site := n as CorruptionSite
		if site == null or not site.grants(SiteCapability.DOMINATE_THRALLS):
			continue
		var d := _flat(site.global_position - near_pos)
		if d <= best_d:
			best_d = d
			best = site
	return best

static func _nearest(from: Vector3, nodes: Array) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for n in nodes:
		var node := n as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var d := from.distance_squared_to(node.global_position)
		if d < best_d:
			best_d = d
			best = node
	return best

static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

func _mm() -> MinionManager:
	return get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager

func _gm() -> GroupManager:
	return get_tree().current_scene.get_node_or_null("GroupManager") as GroupManager
