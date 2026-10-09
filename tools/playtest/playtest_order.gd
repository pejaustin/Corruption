extends Node

## Input-driven playtest of the order loop (CLAUDE.md §2 "Input playtests"):
## select a group piece on the map floor, walk the route, pick the Chapel,
## hand the scroll to the advisor, corrupt it, wait for the report. Only
## InputDriver events act; game state is read for assertions.
## Windowed run:
##   godot --path . --resolution 1280x720 res://tools/playtest/playtest_order.tscn

const WORLD: String = "res://scenes/world/world.tscn"
const Driver := preload("res://tools/playtest/input_driver.gd")
const Placement := preload("res://scenes/actors/minion/advisor_placement.gd")

var failures: int = 0
var steps: int = 0
var drv: Node

func _ready() -> void:
	_run.call_deferred()

func step(cond: bool, what: String) -> void:
	steps += 1
	if cond:
		print("ok   ", what)
	else:
		failures += 1
		print("FAIL ", what)

func _run() -> void:
	await _play()
	drv.release_all()
	print("[playtest] %d steps, %d failed" % [steps, failures])
	get_tree().quit(failures)

func _play() -> void:
	NetworkManager.is_hosting_game = true
	var world: Node = (load(WORLD) as PackedScene).instantiate()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	NetworkTime.start()
	drv = Driver.new()
	add_child(drv)
	await drv.seconds(4.0)
	var mm := world.get_node("MinionManager") as MinionManager
	var gm := world.get_node("GroupManager") as GroupManager
	var player := world.get_node_or_null("World/PlayerSpawnPoint/1") as OverlordActor
	step(player != null, "the local overlord exists")
	if player == null:
		return
	var cam: Camera3D = (player.find_children("*", "CameraInput", true, false)[0] as CameraInput).camera_3d
	drv.bind(player, cam)
	var floor_map := _my_floor(world)
	step(floor_map != null, "my tower has a map floor")
	if floor_map == null:
		return
	var model := KnowledgeManager.local_model()
	var g := gm.get_groups_for(1)[0]
	await drv.seconds(3.0)  # the tower sees the group at its gate
	await drv.key(KEY_F3)  # hide the debug overlay
	await drv.screenshot("00_start")

	# 1. Select my group's piece.
	var piece: MapPiece = null
	for p in floor_map._pieces.values():
		if (p as MapPiece).owner_peer_id == 1 and (p as MapPiece).group_id == g.id:
			piece = p
	step(piece != null, "a piece for my group stands on the floor")
	if piece == null:
		return
	var pp := piece.global_position
	await drv.walk_to(_stand_off(player.global_position, pp, 1.3), 0.25)
	var aimed: bool = await drv.aim_at(pp + Vector3(0, 0.3, 0))
	drv.say("aimed at my group's piece: %s" % aimed)
	await drv.press_action(&"interaction")
	step(floor_map.authoring and g.id in floor_map.selected_groups, "E on the piece starts an order")
	await drv.screenshot("01_piece_selected")

	# 2. Walk over the East road marker.
	var road: MapPointMarker = floor_map._markers[&"RoadEast"]
	var reached: bool = await drv.walk_to(Vector2(road.global_position.x, road.global_position.z), 0.2)
	step(reached, "walked onto the East road marker")
	await drv.seconds(0.3)
	step(&"RoadEast" in floor_map.path_points, "the pencil route records the East road")
	await drv.screenshot("02_route_pencilled")

	# 3. Pick the Chapel as the destination.
	var chapel: MapPointMarker = floor_map._markers[&"Chapel"]
	var cp := chapel.global_position
	await drv.walk_to(_stand_off(player.global_position, cp, 1.9), 0.25)
	aimed = await drv.aim_at(cp + Vector3(0, 0.05, 0))
	drv.say("aimed at the Chapel marker: %s" % aimed)
	await drv.seconds(3.0)  # let the advisor walk to his spot
	var adv0 := _my_advisor(mm)
	step(adv0 != null and not Placement.on_floor(floor_map, adv0.global_position), "the advisor is off the map floor while I stand at it")
	step(not drv.prompt().to_lower().contains("advisor"), "aiming at the Chapel marker does not hit the advisor (prompt: %s)" % drv.prompt())
	await drv.screenshot("03_aim_chapel")
	await drv.press_action(&"interaction")
	step(player.is_holding_order(), "E on the Chapel puts a scroll in hand")
	await drv.screenshot("04_scroll_in_hand")

	# 3b. Stand at the desk: the advisor should come to stand beside it, off the floor.
	var desk := floor_map.get_parent().get_node("Desk") as Node3D
	await drv.walk_to(_stand_off(player.global_position, desk.global_position, 2.2), 0.4, 40.0)
	await drv.seconds(12.0)
	var adv1 := _my_advisor(mm)
	var dd := Vector2(adv1.global_position.x - desk.global_position.x, adv1.global_position.z - desk.global_position.z).length()
	step(dd < 4.0 and not Placement.on_floor(floor_map, adv1.global_position), "the advisor stands near the desk (%.1f m), off the floor" % dd)
	await drv.screenshot("08_advisor_at_desk")

	# 4. Take it to the advisor.
	var advisor: MinionActor = null
	for m in mm.get_minions_for_player(1):
		if m.minion_trait == &"advisor":
			advisor = m
	step(advisor != null, "I have an advisor")
	if advisor == null:
		return
	var ap := advisor.global_position
	await drv.walk_to(_stand_off(player.global_position, ap, 1.2), 0.3, 40.0)
	aimed = await drv.aim_at(ap + Vector3(0, 1.0, 0))
	drv.say("aimed at the advisor: %s" % aimed)
	step(drv.prompt().contains("advisor"), "the prompt offers the advisor's hand-off")
	await drv.press_action(&"interaction")
	var dialogue := AdvisorDialogue.get_instance(get_tree())
	step(dialogue.is_open(), "the advisor's dialogue opens")
	await drv.screenshot("05_advisor_dialogue")
	var pick := -1
	var box: VBoxContainer = dialogue._options_box
	var idx := 0
	for b in box.get_children():
		if not b.is_queued_for_deletion():
			if (b as Button).text.to_lower().contains("corrupt"):
				pick = idx
			idx += 1
	step(pick >= 0, "the dialogue offers 'Corrupt the site'")
	if pick < 0:
		return
	var couriers_before := KnowledgeManager.get_couriers_home(1)
	var stages: Array[String] = []
	var watcher := func() -> void:
		for id in model.orders:
			var st: String = str(model.orders[id]["stage"])
			if stages.is_empty() or stages[-1] != st:
				stages.append(st)
	model.changed.connect(watcher)
	var home_dip := [couriers_before]
	var dip_watch := func() -> void:
		home_dip.append(KnowledgeManager.get_couriers_home(1))
	model.changed.connect(dip_watch)
	await drv.key((KEY_1 + pick) as Key)
	var cmd := -1
	for id in model.orders:
		cmd = id
	step(cmd >= 0 and &"dispatched" in stages or stages.has("dispatched"), "an order was dispatched (stages: %s)" % [stages])
	step(int(model.orders[cmd]["courier_id"]) >= 0 and home_dip.min() < couriers_before, "a courier left the tower (pool dipped to %d)" % home_dip.min())
	step(not player.is_holding_order(), "the scroll left my hand")
	# The courier's round trip to a group at the gate is short; wait for the report.
	Engine.time_scale = 6.0
	var t := 0.0
	while t < 400.0 and model.orders[cmd]["stage"] != &"delivered":
		await drv.seconds(1.0)
		t += 1.0
	Engine.time_scale = 1.0
	step(model.orders[cmd]["stage"] == &"delivered", "the courier came back; report arrived, order delivered (~%.0fs at 6x)" % t)
	step(KnowledgeManager.get_couriers_home(1) == couriers_before, "the courier is back in the pool")
	await drv.seconds(0.4)
	await drv.screenshot("06_advisor_subtitle")
	# Back to the floor to see the ink.
	await drv.walk_to(_stand_off(player.global_position, floor_map.global_position + Vector3(2, 0, 0), 3.0), 0.5, 40.0)
	await drv.aim_at(floor_map.global_position + Vector3(0, 0, 0))
	await drv.seconds(INK_WAIT)
	await drv.screenshot("07_ink_on_floor")

func _my_advisor(mm: MinionManager) -> MinionActor:
	for m in mm.get_minions_for_player(1):
		if m.minion_trait == &"advisor":
			return m
	return null

const INK_WAIT: float = 3.5

func _stand_off(from: Vector3, to: Vector3, dist: float) -> Vector2:
	## A ground point `dist` metres short of `to`, on the line from `from`.
	var f := Vector2(from.x, from.z)
	var t := Vector2(to.x, to.z)
	var d := t - f
	if d.length() < 0.01:
		d = Vector2(-1, 0)
	return t - d.normalized() * dist

func _my_floor(world: Node) -> MapFloor:
	for t in world.get_node("World/Env/Towers").get_children():
		if t is Tower and (t as Tower).owner_peer_id == 1:
			return t.get_node_or_null("MapFloor") as MapFloor
	return null
