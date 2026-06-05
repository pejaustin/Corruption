extends Node3D

## Real-systems harness for the War Table. Spawns the actual OverlordActor as
## peer 1, instances the real war_table.tscn, and spawns real MinionActors via
## MinionManager — so clicking the table actually moves minions you can see
## walking around the playspace in front of you.
##
## Networking is faked with OfflineMultiplayerPeer: multiplayer.get_unique_id()
## returns 1 and multiplayer.is_server() returns true, so the host-authoritative
## paths in MinionManager and MinionActor run locally without a real lobby.
##
## Authoring a starting state:
##   - Drop StartingMinionSpec nodes under the StartingMinions child.
##   - Set each spec's type_id (skeleton/imp/sprite/cultist/...), faction, and
##     owner_peer_id from the inspector. Position the marker where you want
##     the minion. The controller spawns one MinionActor per spec on _ready.
##
## Layout: the field is a full-scale 300×300 region (production map_world_size)
## so broadcast range, courier travel, and visual range run at real distances.
## The overlord, war table, and Advisor live on a 40m observation platform at
## the field's east edge; couriers spawn/despawn at ground level below it.
##
## Hotkeys (mirrored on the HUD):
##   1 — spawn a Skeleton owned by you (UNDEATH) at a random playspace point
##   2 — spawn a Demonic Imp (enemy, owner -1) at a random point
##   3 — spawn a Nature/Fey Sprite (enemy) at a random point
##   4 — spawn an Eldritch Cultist (enemy) at a random point
##   F — cycle your overlord's faction (UNDEATH→DEMONIC→NATURE_FEY→ELDRITCH)
##   K — kill the nearest minion to the overlord, skipping the Advisor
##   Shift+K — same, including the Advisor (advisor-death test)
##   R — reset: despawn all minions, respawn from StartingMinionSpec children
##   T — toggle KnowledgeManager.INSTANT_COMMANDS
##   B — toggle KnowledgeManager.INFINITE_BROADCAST_RANGE
##   M — toggle WarTableMap.SHOW_REALITY (debug overlay of actual courier positions)
##   I — dispatch an info-courier to a random playspace point (fires KnowledgeManager.dispatch_info_courier)
##   V — toggle courier visual-range debug sphere
##   H — cycle Engine.time_scale 1x/2x/4x/8x (real-scale courier trips are long)
##
## Table interaction is the standard single-shot-E flow: aim at a piece and E
## to select (multi-member stacks open the ghost popup), aim at the diorama
## (MapTarget) and E to draft, Paper E to ready, Advisor E to dispatch, Reset E
## to wipe drafts. Ctrl+Left click with the mouse released (Esc) drops a yellow
## debug marker at the projected world point (click→world mapping check).

const LOCAL_PEER_ID: int = 1
const FACTION_CYCLE: Array[int] = [
	GameConstants.Faction.UNDEATH,
	GameConstants.Faction.DEMONIC,
	GameConstants.Faction.NATURE_FEY,
	GameConstants.Faction.ELDRITCH,
]
## Hotkey-spawn IDs live above MinionManager's _next_minion_id counter so the
## two streams can't collide (manager starts at 1; we start at 10000).
const SPAWN_ID_BASE: int = 10000

@export var war_table: WarTable
@export var overlord: OverlordActor
@export var minion_manager: MinionManager
@export var starting_minions_root: Node3D
@export var debug_markers_root: Node3D
@export var status_label: Label
## Half-extent of the playspace on X/Z. Defaults to 145 so spawns stay just
## inside the 300×300 region (matching the production map_world_size — the
## harness field is full scale so broadcast range, courier travel time, and
## visual range behave exactly as in the real game).
@export var playspace_extent: Vector2 = Vector2(145.0, 145.0)

## Engine.time_scale steps cycled by the H hotkey. Real-scale courier trips
## cross ~150m of field; 4x/8x keeps iteration tolerable while waiting.
const TIME_SCALE_STEPS: Array[float] = [1.0, 2.0, 4.0, 8.0]

var _next_spawn_id: int = SPAWN_ID_BASE
var _time_scale_index: int = 0

func _enter_tree() -> void:
	# Must be set BEFORE any child _ready fires. CameraInput._ready captures
	# the mouse and marks its Camera3D current only if multiplayer.get_unique_id()
	# matches its parent overlord's name; without the peer here it sees 0 and
	# leaves the mouse free + camera inactive. OverlordActor._enter_tree also
	# wants this set so set_multiplayer_authority(1) takes effect.
	if multiplayer.multiplayer_peer == null:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _ready() -> void:
	assert(war_table, "Assign war_table in the inspector")
	assert(overlord, "Assign overlord in the inspector")
	assert(minion_manager, "Assign minion_manager in the inspector")
	# PlayerInput._gather is connected to NetworkTime.before_tick_loop. Without
	# starting the netfox tick loop it never fires, so WASD does nothing. As
	# host (offline peer = id 1) start() returns synchronously.
	if NetworkTime.has_method("start"):
		NetworkTime.start()
	GameState.player_factions[LOCAL_PEER_ID] = GameConstants.Faction.UNDEATH
	# MinionManager._setup_minions_node runs deferred from _ready and parents
	# its Minions container under World. Wait one frame so the container
	# exists before we spawn into it.
	await get_tree().process_frame
	# This harness has no Tower / MultiplayerManager infrastructure, so we
	# bind the local peer's spawn point directly. KnowledgeManager.dispatch_*
	# uses this to know where to spawn couriers from. Without it, drafts and
	# info-courier dispatches silently no-op (push_warning to console).
	var spawn_point := get_node_or_null("World/PlayerSpawnPoint") as MinionSpawnPoint
	if spawn_point != null:
		minion_manager.bind_peer_spawn_point(LOCAL_PEER_ID, spawn_point)
	else:
		push_warning("[WarTableTest] World/PlayerSpawnPoint missing — courier dispatch will silently no-op until added")
	# Couriers despawn when their CharacterBody3D enters this Area3D's collision
	# shape (see MinionActor._physics_process zone-overlap check). Without it
	# the courier walks home and just sits there — no return_zone means no
	# despawn. Production builds get this from each Tower's CourierSpawn child.
	var courier_spawn := get_node_or_null("World/CourierSpawn") as Area3D
	if courier_spawn != null:
		minion_manager.bind_peer_courier_spawn(LOCAL_PEER_ID, courier_spawn)
	else:
		push_warning("[WarTableTest] World/CourierSpawn missing — couriers will not despawn on return")
	_spawn_starting_state()
	_refresh_status()

func _spawn_starting_state() -> void:
	if starting_minions_root == null:
		return
	for child in starting_minions_root.get_children():
		if child is StartingMinionSpec:
			var spec: StartingMinionSpec = child
			_spawn_minion(spec.type_id, spec.faction, spec.owner_peer_id, spec.global_position)

func _spawn_minion(type_id: StringName, faction: int, owner_id: int, pos: Vector3) -> void:
	# _spawn_minion_rpc is @rpc("authority", "call_local"). Under
	# OfflineMultiplayerPeer we are the authority, so .rpc() runs locally.
	var id := _next_spawn_id
	_next_spawn_id += 1
	minion_manager._spawn_minion_rpc.rpc(id, owner_id, faction, pos, String(type_id), pos)

func _random_playspace_point() -> Vector3:
	return Vector3(
		randf_range(-playspace_extent.x, playspace_extent.x),
		0.0,
		randf_range(-playspace_extent.y, playspace_extent.y),
	)

func _dispatch_info_courier_to_random_point() -> void:
	## Drives war-table.md step 8 (courier-for-information). The harness fakes
	## a player decision to send eyes — in the real game this dispatch would
	## eventually route through a war-table composition surface.
	var target := _random_playspace_point()
	KnowledgeManager.dispatch_info_courier(LOCAL_PEER_ID, target)

# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := true
		match event.keycode:
			KEY_1:
				_spawn_minion(&"skeleton", GameConstants.Faction.UNDEATH, LOCAL_PEER_ID, _random_playspace_point())
			KEY_2:
				_spawn_minion(&"imp", GameConstants.Faction.DEMONIC, -1, _random_playspace_point())
			KEY_3:
				_spawn_minion(&"sprite", GameConstants.Faction.NATURE_FEY, -1, _random_playspace_point())
			KEY_4:
				_spawn_minion(&"cultist", GameConstants.Faction.ELDRITCH, -1, _random_playspace_point())
			KEY_F:
				_cycle_own_faction()
			KEY_K:
				# Plain K skips the Advisor — on the platform it is always the
				# nearest minion to the overlord, so without the filter K could
				# never reach the field. Shift+K includes it (advisor-death test).
				_kill_nearest_to_overlord(event.shift_pressed)
			KEY_H:
				_time_scale_index = (_time_scale_index + 1) % TIME_SCALE_STEPS.size()
				Engine.time_scale = TIME_SCALE_STEPS[_time_scale_index]
			KEY_R:
				_reset_to_starting_state()
			KEY_T:
				KnowledgeManager.INSTANT_COMMANDS = not KnowledgeManager.INSTANT_COMMANDS
			KEY_B:
				KnowledgeManager.INFINITE_BROADCAST_RANGE = not KnowledgeManager.INFINITE_BROADCAST_RANGE
			KEY_M:
				WarTableMap.SHOW_REALITY = not WarTableMap.SHOW_REALITY
			KEY_I:
				_dispatch_info_courier_to_random_point()
			KEY_V:
				DebugManager.toggle_courier_visual_range()
			_:
				handled = false
		if handled:
			_refresh_status()

func _input(event: InputEvent) -> void:
	# Esc handler: this scene has no pause menu, so without it the captured
	# mouse traps the user. Toggle mouse capture; second press recaptures.
	# Shift+Esc quits the scene outright.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if event.shift_pressed:
			get_tree().quit()
		else:
			var captured := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return
	# Use _input (not _unhandled_input) for Ctrl+Click so we beat war_table.gd's
	# left-click → command_move_to_click handler. Only intercept when the user
	# is actually using the table (mouse visible) AND holding Ctrl.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_key_pressed(KEY_CTRL) and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
			_handle_debug_click(event.position)
			get_viewport().set_input_as_handled()

func _handle_debug_click(screen_pos: Vector2) -> void:
	var ci: CameraInput = overlord.get_node_or_null("CameraInput") as CameraInput
	if ci == null or ci.camera_3d == null or war_table == null or war_table.map == null:
		return
	var world_pos: Vector3 = war_table.map.camera_ray_to_world(ci.camera_3d, screen_pos)
	if world_pos == Vector3.INF:
		return
	_drop_debug_marker(world_pos)

func _drop_debug_marker(world_pos: Vector3) -> void:
	if debug_markers_root == null:
		return
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	marker.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 0)
	mat.emission_enabled = true
	mat.emission = Color(1, 1, 0)
	mat.emission_energy_multiplier = 0.5
	marker.material_override = mat
	debug_markers_root.add_child(marker)
	marker.global_position = world_pos

# --- Hotkey handlers ---

func _cycle_own_faction() -> void:
	var current: int = GameState.get_faction(LOCAL_PEER_ID)
	var idx: int = FACTION_CYCLE.find(current)
	var next: int = FACTION_CYCLE[(idx + 1) % FACTION_CYCLE.size()]
	GameState.set_faction_override(LOCAL_PEER_ID, next)

func _kill_nearest_to_overlord(include_advisor: bool = false) -> void:
	if minion_manager == null or overlord == null:
		return
	var closest: MinionActor = null
	var closest_dist: float = INF
	for m in minion_manager.get_all_minions():
		if not include_advisor and m.minion_type_id == &"advisor":
			continue
		var d: float = m.global_position.distance_to(overlord.global_position)
		if d < closest_dist:
			closest_dist = d
			closest = m
	if closest:
		# notify_minion_died is the proper teardown — fires KnowledgeManager
		# notify_minion_removed (so table pieces disappear) and broadcasts
		# _remove_minion to free the actor.
		minion_manager.notify_minion_died(closest)

func _reset_to_starting_state() -> void:
	if minion_manager == null:
		return
	for m in minion_manager.get_all_minions():
		minion_manager.notify_minion_died(m)
	# notify_minion_died only flags the minion; the actual queue_free runs on
	# the next frame via _remove_minion.rpc. Wait so respawn doesn't collide.
	await get_tree().process_frame
	_spawn_starting_state()
	_refresh_status()

# --- HUD ---

func _refresh_status() -> void:
	if status_label == null:
		return
	var my_faction: int = GameState.get_faction(LOCAL_PEER_ID)
	var my_faction_name: String = GameConstants.faction_names.get(my_faction, "?")
	var counts: Dictionary[int, int] = {}
	if minion_manager:
		for m in minion_manager.get_all_minions():
			counts[m.faction] = counts.get(m.faction, 0) + 1
	var count_str: String = ""
	for f in counts:
		count_str += "%s:%d  " % [GameConstants.faction_names.get(f, "?"), counts[f]]
	if count_str == "":
		count_str = "(none)"
	status_label.text = "War Table Test — real systems, full-scale 300x300 field\nYou are peer %d, faction: %s\nMinions: %s\n\n[Esc] release/recapture mouse  [Shift+Esc] quit\n[1] spawn Skeleton (yours)\n[2] spawn Imp (Demonic, neutral owner)\n[3] spawn Sprite (Nature/Fey)\n[4] spawn Cultist (Eldritch)\n[F] cycle your faction\n[K] kill nearest minion (skips Advisor; Shift+K includes)\n[R] reset to authored starting state\n[I] dispatch info-courier to a random point\n[V] courier visual-range sphere\n[H] time scale: %.0fx\n[T] INSTANT_COMMANDS: %s\n[B] INFINITE_BROADCAST_RANGE: %s\n[M] SHOW_REALITY (war table debug overlay): %s\n\nAim and press E: piece → select (stacks open ghost popup),\nmap → draft, Paper → ready, Advisor → dispatch, Reset → wipe drafts.\n" % [
		LOCAL_PEER_ID,
		my_faction_name,
		count_str,
		Engine.time_scale,
		"ON" if KnowledgeManager.INSTANT_COMMANDS else "OFF",
		"ON" if KnowledgeManager.INFINITE_BROADCAST_RANGE else "OFF",
		"ON" if WarTableMap.SHOW_REALITY else "OFF",
	]
