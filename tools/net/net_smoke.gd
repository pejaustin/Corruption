extends "res://tests/integration/test_base.gd"

## 4-player network smoke test. tools/net/smoke.sh starts four of these (one host, three joiners) as separate
## headless Godot processes on localhost; each runs the same flow through the real lobby and world, and checks
## what it sees on ITS side. Peers meet at named barriers (`exchange`) and compare what they saw.
## Args after `--`: --role=host|join  --port=N  --players=4
## Each process prints `ok` / `FAIL` / `SKIP` lines and exits with its failure count.

const PHASE_TIMEOUT: float = 240.0
## Seconds the world idles before the state-sync health check.
const IDLE_SETTLE_SECONDS: float = 6.0
## Physics steps per second in the test processes (project default 60; netfox ticks stay at 30 Hz).
const PHYSICS_HZ: int = 30
## Neutral map NPC types the host stops simulating (CPU load shedding, see _freeze_townsfolk).
const TOWNSFOLK: Array[StringName] = [&"villager", &"noble", &"holy_knight"]
## Minions the world has once the map's own NPCs are adopted (4 advisors + the neutral ones).
const TOWNSFOLK_ADOPTED: int = 30
## Unit types that stay when the fight's troops are sent away (couriers and advisors are the owner's staff).
const KEEP_TYPES: Array[StringName] = [&"courier", &"advisor"]
## Peers' network ticks must agree within this many ticks before positions are compared; tries before giving up.
const SETTLE_TICKS: int = 12
const SETTLE_ATTEMPTS: int = 40
const AGREE_ATTEMPTS: int = 15
const WORLD_NODE: String = "MinionManager"
## An overlord's floor is in the tower: within this many metres of it on the ground plane.
const TOWER_FLOOR_RADIUS: float = 15.0
## Troops the first player's side puts around the neutral Paladin to bring him down (tool setting, not game design).
const TROOPS_AT_PALADIN: int = 16
## Seconds the troops get to bring him down.
## How far from the holy site the Paladin is set down, metres (tool setting).
const CAMP_METRES: float = 150.0
const FIGHT_WAVES: int = 4
const DEFEAT_TIMEOUT: float = 240.0
## How far the possessed Paladin must walk, metres, to show his position syncs.
const WALK_METRES: float = 4.0
## Peers' views of a stationary body agree within this many metres.
const PEERS_AGREE_METRES: float = 0.5

var role: String = "host"
## Shown in log lines: host, join1, join2, join3.
var label: String = "host"
var port: int = 0
var expected: int = 4
var skips: int = 0

# Barrier state. Host: arrivals per tag. Everyone: released values per tag.
var _arrivals: Dictionary[String, Dictionary] = {}
var _released: Dictionary[String, Dictionary] = {}

## Phases after the world is up, in order (name -> method). --stop-after=<name> ends the run early (debugging).
const PHASES: Dictionary[String, StringName] = {
	"towers": &"_phase_towers",
	"orders": &"_phase_orders",
	"sites": &"_phase_sites",
	"paladin_move": &"_phase_paladin_move",
	"paladin": &"_phase_paladin",
	"mirror": &"_phase_mirror",
	"endgame": &"_phase_endgame",
}
var stop_after: String = ""
## World size the host picks in the lobby: 400m | 2km | 6km (MatchConfig.WORLD_SIZE_BY_NAME).
var world_name: String = "400m"
var world: Node
var me: int = 0

# What this peer observed (filled by signal hooks from the moment the world is up).
var _reports: Array[Dictionary] = []
var _site_events: Array[Dictionary] = []
var _wins: Array[int] = []
var _draws: int = 0
var _live_poses: Dictionary[int, int] = {}
var _settle_count: int = 0

func run_tests() -> void:
	_parse_args()
	# Four full worlds share this machine's cores. The host's ~45 minions cost ~35 ms per physics step; at the
	# default 60 Hz it falls to a few fps, ticks arrive in bursts and clients reject its state as stale.
	# (Lower than 30 Hz makes the actors' velocities NaN.) See also _freeze_townsfolk.
	Engine.physics_ticks_per_second = PHYSICS_HZ
	# The runner must outlive the scene changes (lobby, world): it stops being the current scene.
	get_tree().current_scene = null
	await _phase_connect()
	await _phase_lobby()
	await _phase_world_ready()
	for name in PHASES:
		await call(PHASES[name])
		_probe("after " + name)
		if name == stop_after:
			break
	await sync_point("all_done")
	print("[net:%s] %d skipped" % [label, skips])

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--port="):
			port = a.substr(7).to_int()
		elif a.begins_with("--stop-after="):
			stop_after = a.substr(13)
		elif a.begins_with("--world="):
			world_name = a.substr(8)
		elif a.begins_with("--name="):
			label = a.substr(7)
		elif a.begins_with("--players="):
			expected = a.substr(10).to_int()

# --- Output ---

func check(cond: bool, what: String) -> void:
	checks += 1
	if cond:
		print("  ok   [%s] %s" % [label, what])
	else:
		failures += 1
		print("  FAIL [%s] %s" % [label, what])

func skip(what: String, reason: String) -> void:
	skips += 1
	print("  SKIP [%s] %s -- %s" % [label, what, reason])

func phase(name: String) -> void:
	print("[net:%s] == %s" % [label, name])

func abort(why: String) -> void:
	failures += 1
	print("  FAIL [%s] ABORT: %s" % [label, why])
	print("[tests] %d checks, %d failed" % [checks, failures])
	get_tree().quit(failures)

# --- Waiting ---

func wait_for(cond: Callable, timeout_s: float = 30.0) -> bool:
	## Polls every frame, in wall-clock seconds. True if `cond` held in time.
	var start := Time.get_ticks_msec()
	while not cond.call():
		if float(Time.get_ticks_msec() - start) / 1000.0 > timeout_s:
			return false
		await get_tree().process_frame
	return true

# --- Barriers between the four processes ---

func exchange(tag: String, value: Variant = null) -> Dictionary:
	## Every peer arrives at `tag` with a value; returns {peer_id: value} once all `expected` peers have.
	if multiplayer.is_server():
		_record_arrival(tag, multiplayer.get_unique_id(), value)
	else:
		_arrive.rpc_id(1, tag, value)
	var ok := await wait_for(func() -> bool: return _released.has(tag), PHASE_TIMEOUT)
	if not ok:
		abort("barrier '%s' timed out" % tag)
		await get_tree().create_timer(5.0).timeout
	return _released.get(tag, {})

func sync_point(tag: String) -> void:
	await exchange(tag)

@rpc("any_peer", "call_remote", "reliable")
func _arrive(tag: String, value: Variant) -> void:
	if multiplayer.is_server():
		_record_arrival(tag, multiplayer.get_remote_sender_id(), value)

func _record_arrival(tag: String, from: int, value: Variant) -> void:
	var seen: Dictionary = _arrivals.get(tag, {})
	seen[from] = value
	_arrivals[tag] = seen
	if seen.size() >= expected:
		_release.rpc(tag, seen)

@rpc("authority", "call_local", "reliable")
func _release(tag: String, values: Dictionary) -> void:
	_released[tag] = values.duplicate()

func all_equal(values: Dictionary) -> bool:
	var first: Variant = null
	var have_first := false
	for pid in values:
		if not have_first:
			first = values[pid]
			have_first = true
		elif values[pid] != first:
			return false
	return have_first

# --- Phase: connect ---

func _phase_connect() -> void:
	phase("connect")
	var cfg := NetworkConnectionConfigs.new(NetworkManager.LOCALHOST)
	cfg.host_port = port
	cfg.use_upnp = false
	if role == "host":
		NetworkManager.host_game(cfg)
		NetworkManager.load_lobby_scene()
		print("[net:host] listening on %d" % port)
	else:
		NetworkManager.join_game(cfg)
		var net: Node = NetworkManager.active_network_node
		net.network_client_connected.connect(NetworkManager.load_lobby_scene, CONNECT_ONE_SHOT)
	var ok := await wait_for(func() -> bool: return get_tree().current_scene is Lobby and multiplayer.has_multiplayer_peer(), 60.0)
	check(ok, "reached the lobby scene")
	if not ok:
		abort("never reached the lobby")
		return
	me = multiplayer.get_unique_id()
	check((me == 1) == (role == "host"), "host is peer 1, joiners are not (peer %d)" % me)

# --- Phase: lobby ---

func _phase_lobby() -> void:
	phase("lobby")
	var lobby := get_tree().current_scene as Lobby
	var seated := await wait_for(func() -> bool: return lobby.player_factions.size() == expected and lobby.player_names.size() == expected, 60.0)
	check(seated, "lobby shows all %d players (%d seen)" % [expected, lobby.player_factions.size()])
	var seats := await exchange("lobby_seats", str(lobby.player_factions.keys()))
	check(all_equal(seats), "every peer sees the same lobby seats")
	if role == "host":
		# The host's size picker, as the player uses it; the choice reaches the joiners' labels by RPC.
		var size_id: int = MatchConfig.WORLD_SIZE_BY_NAME[world_name]
		lobby._world_size_selector.item_selected.emit(lobby._world_size_selector.get_item_index(size_id))
	else:
		var size_id: int = MatchConfig.WORLD_SIZE_BY_NAME[world_name]
		var shown := await wait_for(func() -> bool: return lobby.world_size == size_id, 30.0)
		check(shown, "the host's world size (%s) shows in my lobby" % world_name)
	# Every seat picks its own tower, in the reverse of join order, so a pass proves the pick (not join order) decides
	# the seat. The ready comes after: a pick clears it. Starting is blocked until all seats have one.
	var seats_sorted: Array = lobby.player_factions.keys()
	seats_sorted.sort()
	var my_seat: int = seats_sorted.find(me)
	var my_tower: int = expected - 1 - my_seat
	lobby.request_set_tower(me, my_tower)
	var picked := await wait_for(func() -> bool: return lobby.player_towers.size() == expected, 60.0)
	check(picked, "every peer sees all %d towers picked" % expected)
	check(lobby.player_towers.get(me, -1) == my_tower, "my pick (%s) stands" % TowerPicks.slot_names(lobby.world_size).get(my_tower, "?"))
	var picks := await exchange("lobby_towers", str(_sorted_pairs(lobby.player_towers)))
	check(all_equal(picks), "every peer sees the same tower picks")
	lobby.request_toggle_ready(me, true)
	var ready_ok := await wait_for(func() -> bool:
		if lobby.player_ready.size() != expected:
			return false
		for pid in lobby.player_ready:
			if not lobby.player_ready[pid]:
				return false
		return true, 60.0)
	check(ready_ok, "every peer sees all players ready")
	await sync_point("lobby_ready")
	if role == "host":
		check(not lobby._start_button.disabled, "the Start button is enabled for the host")
		lobby._start_button.pressed.emit()

# --- Phase: world ---

func _phase_world_ready() -> void:
	phase("world")
	var ok := await wait_for(func() -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.get_node_or_null(WORLD_NODE) != null, 120.0)
	check(ok, "the match scene loaded from the lobby's Start")
	if not ok:
		abort("world never loaded")
		return
	world = get_tree().current_scene
	KnowledgeManager.report_received.connect(func(r: Dictionary) -> void: _reports.append(r))
	GameState.site_changed.connect(func(site: Node, old: int, now: int, first: bool) -> void:
		_site_events.append({"site": site.name, "old": old, "new": now, "first": first}))
	GameState.game_won.connect(func(peer: int) -> void: _wins.append(peer))
	GameState.game_drawn.connect(func() -> void: _draws += 1)
	GameState.mirror_live_pose_received.connect(func(sender: int, _frame: PackedByteArray) -> void: _live_poses[sender] = _live_poses.get(sender, 0) + 1)
	await sync_point("world_loaded")

func _phase_towers() -> void:
	phase("seats and towers")
	var gs := GameState
	var bound := await wait_for(func() -> bool:
		if gs.player_slots.size() < expected:
			return false
		for t in Tower.in_slot_order(get_tree()):
			if t.owner_peer_id <= 0:
				return false
		return true, 60.0)
	await _freeze_townsfolk()
	check(bound, "every tower is bound to a player on this peer (%d slots)" % gs.player_slots.size())
	var slots := await exchange("slots", str(_sorted_pairs(gs.player_slots)))
	check(all_equal(slots), "all peers agree on the seat -> tower slot table")
	var owners_by_slot: Dictionary = {}
	for t in Tower.in_slot_order(get_tree()):
		owners_by_slot[t.slot_index] = t.owner_peer_id
	var owners := await exchange("tower_owners", str(_sorted_pairs(owners_by_slot)))
	check(all_equal(owners), "all peers agree on Tower.owner_peer_id for every slot")
	var distinct: Dictionary = {}
	var matches_slots := true
	for slot in owners_by_slot:
		distinct[owners_by_slot[slot]] = true
		if gs.player_slots.get(owners_by_slot[slot], -99) != slot:
			matches_slots = false
	check(distinct.size() == expected and matches_slots, "each player has their own tower and it is their seat's slot")
	check(gs.tower_picks == gs.player_slots, "the seat -> tower slot table is the lobby's picks, not join order")
	check(Tower.in_slot_order(get_tree()).size() == expected, "only the %d picked towers are left in the match (%d here)" % [expected, Tower.in_slot_order(get_tree()).size()])
	check(gs.player_factions.size() == expected and gs.player_names.size() == expected, "factions and names reached this peer for all %d seats" % expected)
	# Overlord bodies: one per peer, owned by that peer, standing at their own tower.
	var spawn := world.get_node("World/PlayerSpawnPoint")
	var bodies_ok := await wait_for(func() -> bool: return _overlords_ready(spawn), 60.0)
	check(bodies_ok, "every peer's overlord body exists here, owned by that peer")
	var near := await wait_for(func() -> bool: return _overlords_in_towers(spawn), 20.0)
	check(near, "each overlord stands in their own tower")
	await get_tree().create_timer(IDLE_SETTLE_SECONDS).timeout
	var stale := _stale_synchronizers()
	check(stale.is_empty(), "no rollback synchronizer here has lost the host's state (%s)" % str(stale))
	if not near:
		for t in Tower.in_slot_order(get_tree()):
			var body := spawn.get_node_or_null(str(t.owner_peer_id)) as Node3D
			print("  [%s] overlord %d at %s, tower slot %d at %s" % [label, t.owner_peer_id, body.global_position if body else "none", t.slot_index, t.global_position])

func _overlords_in_towers(spawn: Node) -> bool:
	for t in Tower.in_slot_order(get_tree()):
		var body := spawn.get_node_or_null(str(t.owner_peer_id)) as Node3D
		# Their floor is high up the tower, so compare on the ground plane.
		if body == null or _flat(body.global_position, t.global_position) > TOWER_FLOOR_RADIUS:
			return false
	return true

func _overlords_ready(spawn: Node) -> bool:
	for pid in GameState.player_slots:
		var body := spawn.get_node_or_null(str(pid))
		if body == null:
			return false
		# The body is host-simulated; the seat's owner holds authority over its input node (OverlordActor._enter_tree).
		var inputs := body.find_children("*", "PlayerInput", true, false)
		if inputs.is_empty() or inputs[0].get_multiplayer_authority() != pid:
			return false
	return true

func _settle() -> void:
	## After a heavy stretch the host's tick count can trail its clock, and clients throw its state away as stale
	## until it catches up. Wait until every peer's NetworkTime.tick is within SETTLE_TICKS of the others.
	for attempt in SETTLE_ATTEMPTS:
		_settle_count += 1
		var ticks := await exchange("settle_%d" % _settle_count, NetworkTime.tick)
		await get_tree().process_frame
		var lo := 1 << 30
		var hi := 0
		for pid in ticks:
			lo = mini(lo, int(ticks[pid]))
			hi = maxi(hi, int(ticks[pid]))
		if hi - lo <= SETTLE_TICKS:
			return
		await get_tree().create_timer(1.0).timeout
	print("  [%s] note: ticks never converged" % label)

func _freeze_townsfolk() -> void:
	## Load shedding so four worlds fit on one machine: the host stops simulating the neutral villagers, nobles and
	## guards the map starts with (23 of ~45 minions). They still exist and are still synced; nothing below needs them.
	if role != "host":
		return
	var mm := world.get_node("MinionManager") as MinionManager
	await wait_for(func() -> bool: return mm.get_all_minions().size() >= TOWNSFOLK_ADOPTED, 30.0)
	var frozen := 0
	for m in mm.get_all_minions():
		if m.owner_peer_id == -1 and m.minion_type_id in TOWNSFOLK:
			m.process_mode = Node.PROCESS_MODE_DISABLED
			frozen += 1
	print("  [%s] note: froze %d neutral townsfolk on the host to save CPU" % [label, frozen])

func _probe(tag: String) -> void:
	var counts: Dictionary = {}
	for m in (world.get_node("MinionManager") as MinionManager).get_all_minions():
		var key := "%s/%d" % [m.minion_type_id, m.owner_peer_id if m.owner_peer_id < 2 else 9]
		counts[key] = counts.get(key, 0) + 1
	print("  [%s] minions %s" % [label, str(counts)])
	var avatar := world.get_node("World/Avatar") as AvatarActor
	var rs := avatar.rollback_synchronizer
	var ht = rs._history_transmitter
	print("  [%s] perf %s: fps %d process %.1f ms physics %.1f ms objects %d nodes %d" % [label, tag, Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	print("  [%s] probe %s: tick %d state_tick %d predicted=%s simulated=%s owned_in=%d owned_st=%d auth_in=%d" % [label, tag, NetworkTime.tick, ht.get_latest_state_tick(), ht._is_predicted_tick, NetworkRollback.is_simulated(avatar), ht._get_owned_input_props().size(), ht._get_owned_state_props().size(), avatar.avatar_input.get_multiplayer_authority()])

func _stale_synchronizers() -> Array[String]:
	## Netfox resimulates from the newest authoritative state a synchronizer with inputs has seen; if that is older
	## than the history limit the rollback loop warns and clamps every tick.
	var out: Array[String] = []
	for node in world.find_children("*", "RollbackSynchronizer", true, false):
		var sync := node as RollbackSynchronizer
		if sync.input_properties.is_empty() or sync._history_transmitter == null:
			continue
		if NetworkTime.tick - sync._history_transmitter.get_latest_state_tick() > NetworkRollback.history_limit:
			out.append(str(world.get_path_to(sync)))
	return out

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _sorted_pairs(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append([k, d[k]])
	return out

# --- Phase: orders and couriers ---

func _phase_orders() -> void:
	phase("orders and couriers")
	var model := KnowledgeManager.local_model()
	var seen := await wait_for(func() -> bool: return not model.believed_groups.is_empty(), 90.0)
	check(seen, "the tower's gate report put my starting group on my map")
	var mine: Array = model.believed_groups.keys()
	var all_groups := await exchange("groups", mine)
	var disjoint := true
	var union: Dictionary = {}
	for pid in all_groups:
		for gid in all_groups[pid]:
			if union.has(gid):
				disjoint = false
			union[gid] = pid
	check(disjoint and union.size() == expected, "every player's map holds only their own group (%d groups across %d peers)" % [union.size(), all_groups.size()])
	var couriers_ok := await wait_for(func() -> bool: return KnowledgeManager.get_couriers_home(me) == MatchConfig.STARTING_COURIERS, 30.0)
	check(couriers_ok, "my tower has its %d starting couriers (%d)" % [MatchConfig.STARTING_COURIERS, KnowledgeManager.get_couriers_home(me)])
	await sync_point("orders_go")
	var floor_map := _my_floor()
	check(floor_map != null and floor_map.local_player() != null, "my tower has a map floor and I have my overlord here")
	var gid: int = mine[0]
	floor_map.toggle_group(gid)
	floor_map.finish_at(MapPoint.find(get_tree(), &"RoadEast"))
	var player := floor_map.local_player()
	check(player.is_holding_order(), "picking a destination puts the scroll in my hand")
	# Every advisor answers only to its own overlord, on every peer's copy of the world.
	var advisors_ok := true
	var mine_handoff: Interactable = null
	for t in Tower.in_slot_order(get_tree()):
		var handoff := _handoff_of(t)
		if handoff == null:
			advisors_ok = false
			continue
		handoff.set_focused(true, player)
		var is_mine: bool = t.owner_peer_id == me
		if handoff._is_owning_overlord_in_range() != is_mine or (t.advisor.owner_peer_id == me) != is_mine:
			advisors_ok = false
		if is_mine:
			mine_handoff = handoff
		else:
			handoff.set_focused(false)
	check(advisors_ok and mine_handoff != null, "my advisor accepts me and the other three refuse me, on this peer")
	# E on my advisor with the scroll in hand asks for the goal; pick "go there" from the dialogue as a player would.
	var dialogue := AdvisorDialogue.get_instance(get_tree())
	mine_handoff._on_interact()
	check(dialogue.is_open(), "the advisor asks what the orders are")
	var pick := -1
	var buttons := dialogue._options_box.get_children()
	for i in buttons.size():
		if (buttons[i] as Button).text.contains(OrderGoal.name_of(OrderGoal.Goal.GO_HERE)):
			pick = i
	check(pick >= 0, "'%s' is one of the advisor's choices" % OrderGoal.name_of(OrderGoal.Goal.GO_HERE))
	dialogue.choose(pick)
	check(not player.is_holding_order(), "the scroll left my hand")
	mine_handoff.set_focused(false)
	var cmd: int = model.orders.keys()[0] if not model.orders.is_empty() else -1
	check(cmd >= 0, "the advisor sent the order (command %d)" % cmd)
	var dispatched := await wait_for(func() -> bool: return model.orders[cmd]["stage"] == &"dispatched", 30.0)
	check(dispatched, "the host dispatched my order with a courier (stage %s)" % model.orders[cmd]["stage"])
	check(KnowledgeManager.get_couriers_home(me) == MatchConfig.STARTING_COURIERS - 1, "the courier left my pool (%d at home)" % KnowledgeManager.get_couriers_home(me))
	var delivered := await wait_for(func() -> bool: return model.orders[cmd]["stage"] == &"delivered", 240.0)
	check(delivered, "the courier's report reached me: order delivered (stage %s)" % model.orders[cmd]["stage"])
	var home := await wait_for(func() -> bool: return KnowledgeManager.get_couriers_home(me) == MatchConfig.STARTING_COURIERS, 120.0)
	check(home, "my courier is home again (%d at home)" % KnowledgeManager.get_couriers_home(me))
	# Only the sender hears: every courier report here mentions only my groups, and I got my own.
	var courier_reports := 0
	var foreign := 0
	for r in _reports:
		if r.get("source", &"") != &"courier":
			continue
		courier_reports += 1
		for g in r.get("groups", []):
			if int(g.get("id", -1)) not in mine:
				foreign += 1
	check(courier_reports >= 1, "I received my courier's report (%d)" % courier_reports)
	check(foreign == 0, "no courier report mentioned anyone else's group (%d foreign)" % foreign)
	var counts := await exchange("courier_reports", courier_reports)
	var total := 0
	for pid in counts:
		total += int(counts[pid])
	check(courier_reports == 1 and total == expected, "each of the %d couriers reported to its own player, once (%d reports in all)" % [expected, total])
	if role == "host":
		var gm := world.get_node("GroupManager") as GroupManager
		var all_ordered := await wait_for(func() -> bool:
			for pid in GameState.player_slots:
				var groups := gm.get_groups_for(pid)
				if groups.is_empty() or not groups[0].has_order():
					return false
			return true, 30.0)
		check(all_ordered, "on the host, every player's group received the order their courier carried")
	var order_cmds: Array = model.orders.keys()
	check(order_cmds == [cmd], "my model holds only my own order")

func _handoff_of(t: Tower) -> Interactable:
	## The advisor's handoff Interactable (the advisor stands in the minions node once the match has adopted it).
	for n in t.advisor.find_children("*", "Interactable", true, false):
		if n.has_method(&"_is_owning_overlord_in_range"):
			return n as Interactable
	return null

func _my_floor() -> MapFloor:
	for t in Tower.in_slot_order(get_tree()):
		if t.owner_peer_id == me:
			var floors := t.find_children("*", "MapFloor", true, false)
			return floors[0] if not floors.is_empty() else null
	return null

# --- Phase: corruption sites change hands ---

func _phase_sites() -> void:
	phase("corruption sites")
	var peers: Array[int] = GameState.get_player_peers()
	var a: int = peers[1]
	var b: int = peers[2]
	var site := world.get_node("SiteChapel") as CorruptionSite
	var beacon := site.get_node("%Beacon") as Node3D
	check(site.holder_peer_id == -1 and not beacon.visible, "the chapel starts neutral with no beacon")
	_site_events.clear()
	await sync_point("site_start")
	if role == "host":
		site.debug_give_to(a)
	var took := await wait_for(func() -> bool: return site.holder_peer_id == a, 20.0)
	check(took, "a site is taken: this peer sees the new holder (peer %d)" % a)
	check(not _site_events.is_empty() and _site_events[0]["new"] == a and _site_events[0]["old"] == -1 and _site_events[0]["first"], "site_changed fired here: neutral -> player, first take")
	check(beacon.visible, "the beacon is lit here")
	var model := KnowledgeManager.local_model()
	var believed := await wait_for(func() -> bool: return model.believed_sites.get(StringName(site.name), {}).get("holder", -2) == a, 10.0)
	check(believed, "my world model learned the new holder from the beacon")
	var holders := await exchange("site_holder", [site.holder_peer_id, site.ever_taken, site.progress_peer_id])
	check(all_equal(holders), "all peers agree on holder, ever_taken and progress owner")
	# It changes hands again, then returns to neutral.
	_site_events.clear()
	await sync_point("site_to_b")
	if role == "host":
		site.debug_give_to(b)
	var changed := await wait_for(func() -> bool: return site.holder_peer_id == b, 20.0)
	check(changed and not _site_events.is_empty() and _site_events[0]["old"] == a and not _site_events[0]["first"], "it changes hands: player -> player, not a first take")
	_site_events.clear()
	await sync_point("site_to_neutral")
	if role == "host":
		site.debug_give_to(-1)
	var neutral := await wait_for(func() -> bool: return site.holder_peer_id == -1, 20.0)
	check(neutral and not _site_events.is_empty() and _site_events[0]["new"] == -1, "it returns to neutral and every peer is told")
	check(beacon.visible, "the beacon marks the return to neutral")

# --- Phase: the Paladin ---

func _phase_paladin_move() -> void:
	phase("the Paladin is set down away from the holy site")
	var gs := GameState
	var avatar := world.get_node("World/Avatar") as AvatarActor
	# He starts inside the holy site, where an owned Paladin starts the boss gauntlet at once (GDD §9), so first
	# move him away: the host puts the unowned Paladin on open ground and every peer must see him arrive.
	var holy := world.get_node("World/Places/HolySite") as HolySite
	var camp := Vector3.ZERO
	await sync_point("paladin_move")
	if role == "host":
		camp = _walkable_spot_near(holy.global_position, CAMP_METRES)
		avatar.pin_transform(Transform3D(Basis.IDENTITY, camp + Vector3.UP))
		get_tree().create_timer(0.5).timeout.connect(avatar.unpin_transform)
	var camps := await exchange("paladin_camp", camp)
	camp = camps[1]
	var moved := await wait_for(func() -> bool: return _flat(avatar.global_position, camp) < 3.0, 30.0)
	if not moved:
		var rs := avatar.rollback_synchronizer
		print("  [%s] sync debug: tick %d latest_state_tick %d pos %s camp %s pinned=%s auth=%d" % [label, NetworkTime.tick, rs._history_transmitter.get_latest_state_tick(), avatar.global_position, camp, avatar._is_pinned, avatar.get_multiplayer_authority()])
	check(moved and not holy.is_inside(avatar.global_position), "the host moved the unowned Paladin out of the holy site and I see him there (%.1f m off)" % _flat(avatar.global_position, camp))



func _phase_paladin() -> void:
	phase("the Paladin")
	var gs := GameState
	var peers: Array[int] = gs.get_player_peers()
	var owner_id: int = peers[1]  # a joiner, so ownership and control cross the network
	var watcher_a: int = peers[2] if peers.size() > 2 else -1
	var watcher_b: int = peers[3] if peers.size() > 3 else -1
	var avatar := world.get_node("World/Avatar") as AvatarActor
	var holy := world.get_node("World/Places/HolySite") as HolySite
	var owner_events: Array[int] = []
	gs.avatar_owner_changed.connect(func(_old: int, new: int) -> void: owner_events.append(new))
	check(gs.avatar_owner_peer_id == -1 and avatar.get_allegiance() == GameConstants.GOOD_SIDE, "the Paladin starts with the good faction on this peer")

	# a) Defeated by a player's troops, a neutral Paladin goes to that player.
	await sync_point("paladin_fight")
	# The host sends the troops in waves until he falls (he kills a wave now and then).
	var taken := false
	for wave in FIGHT_WAVES:
		if role == "host":
			var mm := world.get_node("MinionManager") as MinionManager
			for i in TROOPS_AT_PALADIN:
				mm.spawn_unit_for_peer(owner_id, &"", avatar.global_position + Vector3(2.0 + float(i % 4), 0.5, float(i / 4) - 1.0))
		taken = await wait_for(func() -> bool: return gs.avatar_owner_peer_id == owner_id, DEFEAT_TIMEOUT / FIGHT_WAVES)
		if taken:
			break
	check(taken, "defeated by player %d's troops, the neutral Paladin went to them (owner %d)" % [owner_id, gs.avatar_owner_peer_id])
	check(not owner_events.is_empty() and owner_events[0] == owner_id, "avatar_owner_changed fired here for the new owner")
	check(avatar.get_allegiance() == owner_id, "he fights for his new owner here")
	var healed := await wait_for(func() -> bool: return avatar.hp == avatar.get_max_hp(), 30.0)
	check(healed, "he is up at full HP on this peer (%d/%d)" % [avatar.hp, avatar.get_max_hp()])
	if role == "host":
		# The fight is over: send the troops home (frees the host's CPU).
		var fight_mm := world.get_node("MinionManager") as MinionManager
		for m in fight_mm.get_minions_for_player(owner_id):
			if m.minion_type_id not in KEEP_TYPES:
				fight_mm.despawn_minion(m)
	await _settle()
	var owners := await exchange("paladin_owner", [gs.avatar_owner_peer_id, gs.avatar_peer_id, avatar.faction])
	check(all_equal(owners), "all peers agree on his owner, controller and faction")

	# b) The owner scries and possesses him; control and position reach everyone.
	await sync_point("paladin_possess")
	var pal := _my_palantir()
	check(pal != null, "my tower has a Palantir")
	if me == owner_id:
		_scry(pal)
		var watching := await wait_for(func() -> bool: return gs.is_watching(me), 10.0)
		check(watching, "the owner looking in shows as a watcher")
		pal._on_scry_interact()
	var driven := await wait_for(func() -> bool: return gs.avatar_peer_id == owner_id and avatar.controlling_peer_id == owner_id, 20.0)
	check(driven, "the owner possessed him: controller %d here" % gs.avatar_peer_id)
	check(avatar.avatar_input.get_multiplayer_authority() == owner_id, "his input authority moved to the owner on this peer")
	var ctrl := await exchange("paladin_ctrl", [gs.avatar_peer_id, avatar.controlling_peer_id, avatar.avatar_input.get_multiplayer_authority()])
	check(all_equal(ctrl), "all peers agree on controller and input authority")
	# The owner walks him with the "forward" action held, as a player would.
	var start_pos := avatar.global_position
	print("  [%s] note: Paladin at %s before the walk; site distance %.0f" % [label, start_pos, _flat(start_pos, (world.get_node("SiteAvatar") as Node3D).global_position)])
	await sync_point("paladin_walk")
	if me == owner_id:
		Input.action_press("forward")
	var walked := await wait_for(func() -> bool: return _flat(avatar.global_position, start_pos) > WALK_METRES, 30.0)
	print("  [%s] note: Paladin at %s after the walk (hp %d, owner %d, ctrl %d)" % [label, avatar.global_position, avatar.hp, gs.avatar_owner_peer_id, gs.avatar_peer_id])
	check(walked, "his position moved here when the owner walked him (%.1f m)" % _flat(avatar.global_position, start_pos))
	if not walked:
		print("  [%s] walk debug: state=%s input_dir=%s enabled=%s ctrl=%d hp=%d vel=%s pos=%s" % [label, avatar._state_machine.state, avatar.avatar_input.input_dir, avatar.avatar_input.input_enabled, avatar.avatar_input.controlling_peer_id, avatar.hp, avatar.velocity, avatar.global_position])
	await sync_point("paladin_walked")
	if me == owner_id:
		Input.action_release("forward")
	await get_tree().create_timer(2.0).timeout
	await _settle()
	var spread := 0.0
	for attempt in AGREE_ATTEMPTS:
		_settle_count += 1
		var spots := await exchange("paladin_pos_%d" % _settle_count, avatar.global_position)
		spread = 0.0
		for a in spots:
			for b in spots:
				spread = maxf(spread, (spots[a] as Vector3).distance_to(spots[b]))
		if spread < PEERS_AGREE_METRES:
			break
		await get_tree().create_timer(1.0).timeout
	check(spread < PEERS_AGREE_METRES, "all peers see him in the same place once he stops (spread %.2f m)" % spread)

	# c) Palantir viewers are seen by the others: orbs, the watcher list and the voice group.
	await sync_point("paladin_watch")
	if me == watcher_a or me == watcher_b:
		_scry(pal)
	var seen := await wait_for(func() -> bool: return gs.watchers.size() == 2 and gs.is_watching(watcher_a) and gs.is_watching(watcher_b), 20.0)
	check(seen, "both viewers are in the watcher list here (%s)" % str(gs.watchers))
	var remote_viewers: Array[int] = []
	for v in [watcher_a, watcher_b]:
		if v != me:
			remote_viewers.append(v)
	var orbs := await wait_for(func() -> bool:
		for v in remote_viewers:
			if avatar.find_child("WatcherOrb%d" % v, false, false) == null or v not in gs.watcher_positions:
				return false
		return gs.watcher_positions.size() == remote_viewers.size(), 20.0)
	check(orbs, "a watcher orb stands at each other viewer's camera here (%d orbs)" % remote_viewers.size())
	check(avatar.find_child("WatcherOrb%d" % me, false, false) == null, "I do not see an orb for my own camera")
	check(gs.watcher_count == 2 and avatar.watcher_label.visible, "the Paladin shows how many are watching (%d)" % gs.watcher_count)
	var voice_peers := gs.get_paladin_voice_peers()
	voice_peers.sort()
	var expect_voice: Array[int] = [owner_id, watcher_a, watcher_b]
	expect_voice.sort()
	check(voice_peers == expect_voice, "voice group = viewers plus his controller %s" % str(voice_peers))
	var speaking := await wait_for(func() -> bool: return avatar.voice.is_speaking() == (me in expect_voice), 10.0)
	check(speaking, "my voice channel is %s (I %s in the group)" % ["open" if me in expect_voice else "closed", "am" if me in expect_voice else "am not"])
	var groups := await exchange("voice_group", str(voice_peers))
	check(all_equal(groups), "all peers agree on the voice group")
	skip("Paladin voice audio capture/playback", "no microphone, audio device or real voice in headless runs; only group membership and the channel state are checked")
	await sync_point("paladin_watching_done")
	if me == watcher_a or me == watcher_b:
		pal._stop_scrying(true)
	var cleared := await wait_for(func() -> bool: return gs.watchers.is_empty() and gs.watcher_positions.is_empty() and avatar.find_child("WatcherOrb*", false, false) == null, 20.0)
	check(cleared, "stopping the scry clears the watchers and their orbs here")
	var quiet := await wait_for(func() -> bool: return avatar.voice.is_speaking() == (me == owner_id), 10.0)
	var only_owner: Array[int] = [owner_id]
	check(quiet and gs.get_paladin_voice_peers() == only_owner, "the voice group is just his controller again")

	# The owner lets go with Q: the AI drives him again and everyone agrees.
	await sync_point("paladin_recall")
	if me == owner_id:
		gs.request_recall_avatar()
	var released := await wait_for(func() -> bool: return gs.avatar_peer_id == -1 and avatar.controlling_peer_id == -1 and gs.avatar_owner_peer_id == owner_id, 20.0)
	check(released, "recalling releases control but keeps ownership here")
	await sync_point("paladin_done")
	check(avatar.avatar_input.get_multiplayer_authority() == 1, "his input authority is back with the host here")

func _walkable_spot_near(from: Vector3, metres: float) -> Vector3:
	## A point about `metres` along the walking path out of `from` towards the first tower.
	var map := (world.get_node("World/Nav") as NavigationRegion3D).get_navigation_map()
	var towers := Tower.in_slot_order(get_tree())
	var path := NavigationServer3D.map_get_path(map, from, towers[0].global_position, true)
	for p in path:
		if _flat(p, from) >= metres:
			return p
	return from

func _my_palantir() -> Interactable:
	for t in Tower.in_slot_order(get_tree()):
		if t.owner_peer_id == me:
			return t.find_child("Palantir", true, false) as Interactable
	return null

func _scry(pal: Interactable) -> void:
	## Looks into my Palantir as the interaction ray would hand it over.
	var body := world.get_node("World/PlayerSpawnPoint/%d" % me) as OverlordActor
	pal.set_focused(true, body)
	pal._on_interact()

# --- Phase: the mirror ---

func _phase_mirror() -> void:
	phase("the mirror")
	var peers: Array[int] = GameState.get_player_peers()
	# Two calls at once, so a ring that reaches the wrong mirror shows. Host -> peers[3] is answered and goes live;
	# peers[1] -> peers[2] is not answered, so it falls back to a recorded message.
	var answered_caller: int = peers[0]
	var answered_callee: int = peers[3]
	var lone_caller: int = peers[1]
	var lone_callee: int = peers[2]
	var mirror := _my_mirror()
	check(mirror != null and mirror.is_mine(), "my tower has a mirror and it is mine")
	var body := world.get_node("World/PlayerSpawnPoint/%d" % me) as OverlordActor
	mirror.set_focused(true, body)  # as if the interaction ray found it
	await sync_point("mirror_ring")
	if me == answered_caller:
		mirror.start_call(answered_callee)
	elif me == lone_caller:
		mirror.start_call(lone_callee)
	var want: int = -1
	if me == answered_callee:
		want = answered_caller
	elif me == lone_callee:
		want = lone_caller
	var rung := await wait_for(func() -> bool: return mirror._incoming_caller == want and (want == -1 or mirror._ring_glow.visible), 20.0)
	check(rung, "%s" % ("my mirror rings for peer %d and glows" % want if want != -1 else "my mirror is not ringing"))
	await get_tree().create_timer(1.0).timeout
	var rings := await exchange("mirror_rings", mirror._incoming_caller)
	var expect_rings := {answered_caller: -1, answered_callee: answered_caller, lone_caller: -1, lone_callee: lone_caller}
	check(rings == expect_rings, "each call rang only its own callee's mirror %s" % str(rings))
	# The answered call goes live.
	if me == answered_callee:
		mirror._on_interact()
	var live_expected := me == answered_caller or me == answered_callee
	var live_ok := await wait_for(func() -> bool: return (mirror._state == mirror.State.LIVE) == live_expected, 20.0)
	check(live_ok, "%s" % ("the answered call is live on my mirror" if live_expected else "my mirror is not on a call"))
	if live_expected:
		var other: int = answered_callee if me == answered_caller else answered_caller
		var posed := await wait_for(func() -> bool: return _live_poses.get(other, 0) >= 3 and mirror._live_frame.size() > 0, 20.0)
		check(posed, "live pose frames from peer %d reach my mirror (%d frames)" % [other, _live_poses.get(other, 0)])
		check(mirror._ring_glow.visible == false and mirror._incoming_caller == -1, "the ring stopped once it was answered")
	skip("live call voice (capture, downsample, playback)", "no microphone or audio device headless; the voice packets would be empty")
	skip("recorded message audio and the mirror's pose capture from a moving player", "headless: no mic, and the overlord model has no animation to capture; the pose bytes sent are the idle skeleton")
	await sync_point("mirror_live_checked")
	# Nobody answers the other call: its timeout runs out and it falls back to recording.
	if me == lone_caller:
		mirror._process_calling(mirror.RING_TIMEOUT)  # stands in for waiting out the 20 s ring (headless, same code path)
	var fell_back := await wait_for(func() -> bool: return mirror._state == (mirror.State.RECORDING if me == lone_caller else mirror._state), 10.0)
	if me == lone_caller:
		check(fell_back and mirror._notice != "", "unanswered: the call fell back to recording and I was told")
		for i in 6:
			mirror._process_recording(0.1)
		mirror._stop_recording()
		check(mirror._state == mirror.State.PREVIEW, "the recording is ready to preview")
		mirror._on_interact()  # E in the preview sends it
		check(mirror._state == mirror.State.IDLE, "sent: my mirror is idle again")
	if me == lone_callee:
		var stopped := await wait_for(func() -> bool: return mirror._incoming_caller == -1 and not mirror._ring_glow.visible, 20.0)
		check(stopped, "the caller giving up stopped my ring")
		var got := await wait_for(func() -> bool: return mirror._inbox.size() == 1, 20.0)
		check(got, "the recorded message reached my inbox")
		if got:
			var msg: MirrorMessage = mirror._inbox[0]
			check(msg.sender_peer_id == lone_caller and msg.recipient_peer_id == me, "it is from peer %d and addressed to me" % lone_caller)
			check(msg.frame_count() >= 6 and msg.pose_frame_size > 0 and msg.duration > 0.0, "it carries %d pose frames over %.1fs" % [msg.frame_count(), msg.duration])
	await sync_point("mirror_message_sent")
	await get_tree().create_timer(1.0).timeout
	if me != lone_callee:
		check(mirror._inbox.is_empty(), "no recorded message landed in my inbox (it was not for me)")
	# The live call ends from one side; the other side hears.
	if me == answered_caller:
		mirror._on_interact()
	if live_expected:
		var ended := await wait_for(func() -> bool: return mirror._state == mirror.State.IDLE, 20.0)
		check(ended, "ending the call from one side ended it on mine")

func _my_mirror() -> Interactable:
	for t in Tower.in_slot_order(get_tree()):
		if t.owner_peer_id == me:
			return t.find_child("Mirror", true, false) as Interactable
	return null

# --- Phase: the gauntlet, the win and the draw ---

func _phase_endgame() -> void:
	phase("gauntlet, win and draw")
	var gs := GameState
	var owner_id: int = gs.avatar_owner_peer_id
	var avatar := world.get_node("World/Avatar") as AvatarActor
	var holy := world.get_node("World/Places/HolySite") as HolySite
	var mm := world.get_node("MinionManager") as MinionManager
	check(owner_id > 0 and HolySite.state == HolySite.State.IDLE, "an owned Paladin outside the holy site: no gauntlet yet (owner %d)" % owner_id)
	var order := HolySite.order_for(owner_id)
	var orders := await exchange("gauntlet_order", str(order))
	check(all_equal(orders) and order.size() == expected - 1, "all peers work out the same boss order %s" % str(order))
	await sync_point("gauntlet_go")
	if role == "host":
		avatar.avatar_input.ai_driver = null  # keep his AI from walking him back out
		avatar.pin_transform(Transform3D(Basis.IDENTITY, holy.global_position + Vector3.UP))
		get_tree().create_timer(1.0).timeout.connect(avatar.unpin_transform)
	var started := await wait_for(func() -> bool: return HolySite.state == HolySite.State.GAUNTLET, 60.0)
	check(started, "his owner brought him to the holy site: the gauntlet is on here")
	var inside := await wait_for(func() -> bool: return holy.is_inside(avatar.global_position), 30.0)
	check(started and inside, "he stands inside the holy site on this peer")
	var first := await wait_for(func() -> bool: return HolySite.boss_total == expected - 1 and HolySite.boss_peer == order[0], 20.0)
	check(first, "first boss is peer %d of %d here" % [HolySite.boss_peer, HolySite.boss_total])
	var boss_seen := await wait_for(func() -> bool: return _boss_of(mm, HolySite.boss_peer) != null, 20.0)
	check(boss_seen, "the first boss form exists on this peer")
	# Beat the bosses one by one (the host lands the blows a fight would).
	var beaten: Array[int] = []
	for i in order.size():
		var boss_peer: int = order[i]
		var present := await wait_for(func() -> bool: return HolySite.boss_peer == boss_peer and _boss_of(mm, boss_peer) != null, 30.0)
		check(present, "boss %d of %d (peer %d) is up here" % [i + 1, order.size(), boss_peer])
		await sync_point("boss_up_%d" % i)
		if role == "host":
			var boss := _boss_of(mm, boss_peer)
			if boss:
				boss.take_damage(99999)
		beaten.append(boss_peer)
	var won := await wait_for(func() -> bool: return not _wins.is_empty(), 60.0)
	var expect_wins: Array[int] = [owner_id]
	check(won and _wins == expect_wins, "the win reached this peer: peer %d" % (_wins[0] if not _wins.is_empty() else -1))
	check(HolySite.state == HolySite.State.ENDED, "the holy site shows the match ended here")
	var win_screen := world.find_child("WinScreen", true, false) as Control
	var label := win_screen.get_node("VBoxContainer/WinnerLabel") as Label
	var expect_word := "VICTORY" if me == owner_id else "DEFEAT"
	check(win_screen.visible and label.text.contains(expect_word), "my win screen reads %s" % expect_word)
	var wins := await exchange("wins", str(_wins))
	check(all_equal(wins), "every peer was told the same winner")
	# The good faction's draw.
	await sync_point("draw_go")
	var gf := world.get_node("GoodFaction") as GoodFaction
	if role == "host":
		GoodFaction.step = GoodFaction.DRAW_AT_STEP - 1  # stands in for 14 growth steps of waiting
		gf._grow()
	var drawn := await wait_for(func() -> bool: return _draws >= 1, 30.0)
	check(drawn and _draws == 1, "the draw announcement reached this peer once (%d)" % _draws)
	check(GoodFaction.step == GoodFaction.DRAW_AT_STEP, "the good faction's growth step is mirrored here (%d)" % GoodFaction.step)
	if role == "host":
		check(holy.locked, "on the host the holy site is locked by the draw")
	var marchers := await wait_for(func() -> bool: return _holy_knights(mm) >= GoodFaction.MARCH_SIZE, 30.0)
	check(marchers, "the good faction's late march exists on this peer (%d knights)" % _holy_knights(mm))
	var draws := await exchange("draws", _draws)
	check(all_equal(draws), "every peer saw the draw exactly as often")

func _boss_of(mm: MinionManager, peer: int) -> MinionActor:
	for m in mm.get_minions_for_player(peer):
		if m.minion_type_id == &"boss_form" and m.hp > 0:
			return m
	return null

func _holy_knights(mm: MinionManager) -> int:
	var n := 0
	for m in mm.get_all_minions():
		if m.minion_type_id == GoodFaction.MARCH_UNIT and m.owner_peer_id == -1:
			n += 1
	return n
