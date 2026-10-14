extends Node3D

## Combat test arena (ticket #640): fight as the Paladin (at a chosen control
## level) or as a boss form (with chosen attacks) against a basic AI, any minion
## type, or a second player, without a match. Open tools/arena/arena.tscn and
## press F6, or run
##   godot --path . res://tools/arena/arena.tscn -- --offline --fight
## Esc opens the setup panel: Offline / Host / Join first, then Fight (host).
## A second player runs the arena too and joins the host's address; they play the
## other role. Command line (after `--`): --offline | --host | --join=<ip>,
## --fight, --arena-preset=<res path>, plus ArenaConfig.apply_args flags.
## A round restarts ROUND_RESTART_SECONDS after the Paladin or the boss goes
## down, or after the last minion falls.

const ROUND_RESTART_SECONDS: float = 3.0
## The host listens here (the game's port, scripts/network/enet_network.gd).
const PORT: int = preload("res://scripts/network/enet_network.gd").SERVER_PORT
## Minions stand in a row across the far end, this far apart.
const MINION_SPACING: float = 2.0

## Godot's own "Visible Collision Shapes" (the editor's Debug menu), on in the arena so hit and
## hurt boxes show: set before the shapes enter the tree. `--no-hitboxes` turns it off.
@export var show_collision_shapes: bool = true
## The fight to set up; the panel and the command line start from it.
@export var config: ArenaConfig
@export var boss_scene: PackedScene

## The second player's peer id once they join (host), -1 = none.
var _second_peer: int = -1
## The running round, on every peer (null before the first).
var _round: ArenaConfig = null
var _restart_pending: bool = false
var _is_host: bool = false
var _panel_open: bool = true
## Bumped by every pin, so an older pin's timer doesn't release a newer one.
var _pin_serial: int = 0

@onready var _avatar: AvatarActor = $World/Avatar
@onready var _bosses: Node3D = $World/Bosses
@onready var _player_spot: Marker3D = $World/PlayerSpot
@onready var _foe_spot: Marker3D = $World/FoeSpot
@onready var _parked_spot: Marker3D = $World/ParkedSpot
@onready var _overview_camera: Camera3D = $World/OverviewCamera
@onready var _nav: NavigationRegion3D = $World/Nav
@onready var _minion_manager: MinionManager = $MinionManager
@onready var _panel: ArenaPanel = %ArenaPanel

func _enter_tree() -> void:
	get_tree().debug_collisions_hint = show_collision_shapes and not "--no-hitboxes" in OS.get_cmdline_user_args()

func _ready() -> void:
	config = config.duplicate() if config else ArenaConfig.new()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--arena-preset="):
			var preset := load(arg.split("=", true, 1)[1]) as ArenaConfig
			if preset:
				config = preset.duplicate()
	config.apply_args(args)
	_nav.bake_navigation_mesh(false)  # a flat floor: instant, and stays right if the floor is edited
	# The arena keeps the Paladin's owner fixed per round: no hold fading, no takeovers.
	_avatar.hold.process_mode = Node.PROCESS_MODE_DISABLED
	GameState.avatar_changed.connect(_on_avatar_changed)
	_avatar.died.connect(_on_fighter_died)
	_park_paladin(true)
	_assign_paladin(DebugManager.DUMMY_BASE_ID, -1)
	_panel.show_config(config)
	_panel.offline_pressed.connect(_go_offline)
	_panel.host_pressed.connect(_go_host)
	_panel.join_pressed.connect(_go_join)
	_panel.fight_pressed.connect(_on_fight_pressed)
	_panel.spawn_pressed.connect(_on_spawn_pressed)
	_panel.set_status("Pick Offline, Host or Join.")
	_set_panel_open(true)
	if "--offline" in args:
		_go_offline()
	elif "--host" in args:
		_go_host()
	for arg in args:
		if arg.begins_with("--join="):
			_go_join(arg.split("=", true, 1)[1])
	if "--fight" in args and _is_host:
		await _navigation_ready()
		_on_fight_pressed(config)

func _process(_delta: float) -> void:
	if not _is_host or _round == null or _restart_pending:
		return
	if _round.opponent == ArenaConfig.Opponent.MINIONS and _minion_manager.get_all_minions().filter(
			func(m: MinionActor) -> bool: return m.hp > 0).is_empty():
		_schedule_restart("The minions are down.")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("in-game-menu"):
		_set_panel_open(not _panel_open)
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	get_tree().debug_collisions_hint = false
	if GameState.avatar_changed.is_connected(_on_avatar_changed):
		GameState.avatar_changed.disconnect(_on_avatar_changed)
	NetworkManager.is_hosting_game = false

# --- Network ---

func _go_offline() -> void:
	NetworkManager.is_hosting_game = true
	_is_host = true
	NetworkTime.start()  # with no peer, netfox's clock is ours to start (as the sandbox does)
	_panel.set_network_chosen(true, true)
	_panel.set_status("Offline. Set up the fight and press Fight.")

func _go_host() -> void:
	var configs := NetworkConnectionConfigs.new(NetworkManager.LOCALHOST)
	configs.host_port = PORT
	configs.use_upnp = false
	NetworkManager.host_game(configs)
	_is_host = true
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_panel.set_network_chosen(true, true)
	_panel.set_status("Hosting on port %d. Waiting for player 2 (or fight an AI now)." % PORT)

func _go_join(address: String) -> void:
	if address.is_empty():
		address = NetworkManager.LOCALHOST
	_panel.set_network_chosen(true, false)
	_panel.set_status("Joining %s ..." % address)
	multiplayer.connected_to_server.connect(func() -> void: _panel.set_status("Joined. The host sets up the fight."))
	var configs := NetworkConnectionConfigs.new(address)
	configs.host_port = PORT
	NetworkManager.join_game(configs)

func _on_peer_connected(peer_id: int) -> void:
	if _second_peer > 0:
		return
	_second_peer = peer_id
	_panel.set_status("Player 2 joined (peer %d). Pick \"Second player\" and Fight." % peer_id)
	if _round:
		_start_round(_round)  # bring them into the running round

func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id != _second_peer:
		return
	_second_peer = -1
	_panel.set_status("Player 2 left.")
	if _round and _round.opponent == ArenaConfig.Opponent.PLAYER:
		var solo := _round.duplicate() as ArenaConfig
		solo.opponent = ArenaConfig.Opponent.AI
		_start_round(solo)

# --- Rounds ---

func _on_fight_pressed(new_config: ArenaConfig) -> void:
	config = new_config
	_start_round(config)
	if _round_running():
		_set_panel_open(false)

func _on_spawn_pressed(new_config: ArenaConfig) -> void:
	## More of the chosen minion, without restarting the round.
	if _round == null:
		_on_fight_pressed(new_config)
		return
	_spawn_minions(new_config.minion_type, new_config.minion_count)

func _start_round(round_config: ArenaConfig) -> void:
	## Host: every peer sets the round up the same way. A fight against player 2
	## waits for them to join (_on_peer_connected starts it).
	_round = round_config
	_restart_pending = false
	if not _round_running():
		_panel.set_status("Waiting for player 2: they run the arena and Join this address.")
		return
	_begin_round.rpc(round_config.to_dict(), _second_peer)

func _round_running() -> bool:
	return _round != null and (_round.opponent != ArenaConfig.Opponent.PLAYER or _second_peer > 0)

@rpc("authority", "call_local", "reliable")
func _begin_round(round_dict: Dictionary, second_peer: int) -> void:
	_round = ArenaConfig.from_dict(round_dict)
	_second_peer = second_peer
	_restart_pending = false
	for boss in _bosses.get_children():
		boss.name = "%s_gone" % boss.name  # the new boss takes the name this frame
		boss.queue_free()
	if _is_host:
		for minion in _minion_manager.get_all_minions():
			_minion_manager.despawn_minion(minion)
	var paladin_peer := _paladin_peer()
	var boss_peer := _boss_peer()
	var paladin_fights := _round.role == ArenaConfig.Role.PALADIN or _round.opponent in [ArenaConfig.Opponent.AI, ArenaConfig.Opponent.PLAYER]
	_avatar.control_level_override = _round.control_level
	_park_paladin(not paladin_fights)
	if paladin_fights:
		var spot := _player_spot if _round.role == ArenaConfig.Role.PALADIN else _foe_spot
		_pin_paladin(spot.global_transform, HolySite.PIN_SECONDS)
		if _is_host:
			_avatar.restore_full_hp()
		_assign_paladin(paladin_peer, paladin_peer)
	else:
		# Sitting out: the CPU seat's, so he is no foe to its minions and AvatarAI leaves him standing.
		_assign_paladin(DebugManager.DUMMY_BASE_ID, -1)
	if boss_peer != 0:
		var spot := _player_spot if _round.role == ArenaConfig.Role.BOSS else _foe_spot
		_spawn_boss(boss_peer, spot.global_transform)
	if _is_host and _round.opponent == ArenaConfig.Opponent.MINIONS:
		_spawn_minions(_round.minion_type, _round.minion_count)
	_update_overview_camera()
	_panel.show_config(_round)
	_panel.set_status(_describe_round(paladin_peer, boss_peer))
	var me := multiplayer.get_unique_id()
	if me in [paladin_peer, boss_peer]:
		_set_panel_open(false)

func _assign_paladin(owner_peer: int, controller_peer: int) -> void:
	## Every peer, from the same round: who holds the Paladin and who drives him. Set locally on each
	## peer (GameState's setters are its own RPC bodies), so a late joiner can't keep a stale owner.
	## No Palantir here: the arena possesses him directly.
	if GameState.avatar_peer_id != -1 and GameState.avatar_peer_id != controller_peer:
		GameState._set_avatar(-1)
	if GameState.avatar_owner_peer_id != owner_peer:
		GameState._set_avatar_owner(owner_peer)
	if controller_peer > 0 and GameState.avatar_peer_id != controller_peer:
		GameState._set_avatar(controller_peer)

func _paladin_peer() -> int:
	## Who drives the Paladin this round: a peer, or -1 for AvatarAI.
	if _round.role == ArenaConfig.Role.PALADIN:
		return 1
	return _second_peer if _round.opponent == ArenaConfig.Opponent.PLAYER else GameConstants.GOOD_SIDE

func _boss_peer() -> int:
	## Whose boss this round has: a peer, the CPU seat (BossAI drives), or 0 for none.
	if _round.role == ArenaConfig.Role.BOSS:
		return 1
	match _round.opponent:
		ArenaConfig.Opponent.PLAYER: return _second_peer
		ArenaConfig.Opponent.AI: return DebugManager.DUMMY_BASE_ID
	return 0

func _spawn_boss(peer_id: int, at: Transform3D) -> void:
	var boss := boss_scene.instantiate() as BossActor
	boss.name = "Boss%d" % peer_id
	if not _round.boss_attacks.is_empty():
		boss.attacks = _round.boss_attacks.duplicate()
	boss.setup(peer_id, _round.boss_hp, _round.boss_damage)
	_bosses.add_child(boss)
	boss.global_transform = at
	boss.boss_input.input_enabled = not _panel_open
	if _is_host:
		boss.died.connect(_on_fighter_died)

func _spawn_minions(type_id: StringName, count: int) -> void:
	## Host: hostile to both players (the CPU seat owns them).
	if not _is_host:
		return
	var across := _foe_spot.global_transform.basis.x
	for i in count:
		var offset := across * (i - (count - 1) / 2.0) * MINION_SPACING
		_minion_manager.spawn_unit_for_peer(DebugManager.DUMMY_BASE_ID, type_id, _foe_spot.global_position + offset)

func _on_fighter_died() -> void:
	if _is_host and _round and not _restart_pending:
		_schedule_restart("Down!")

func _schedule_restart(why: String) -> void:
	_restart_pending = true
	_announce.rpc("%s Next round in %d s." % [why, int(ROUND_RESTART_SECONDS)])
	get_tree().create_timer(ROUND_RESTART_SECONDS).timeout.connect(func() -> void:
		if _restart_pending and _round:
			_start_round(_round))

@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	_panel.set_status(text)

func _describe_round(paladin_peer: int, boss_peer: int) -> String:
	var me := multiplayer.get_unique_id()
	var parts: Array[String] = []
	if paladin_peer == me:
		parts.push_back("You: the Paladin, control level %d." % _round.control_level)
	elif boss_peer == me:
		parts.push_back("You: the boss form.")
	else:
		parts.push_back("You are watching.")
	match _round.opponent:
		ArenaConfig.Opponent.AI: parts.push_back("Against the AI.")
		ArenaConfig.Opponent.PLAYER: parts.push_back("Against player 2.")
		ArenaConfig.Opponent.MINIONS: parts.push_back("Against %d %s." % [_round.minion_count, _round.minion_type])
		ArenaConfig.Opponent.NONE: parts.push_back("Nobody to fight.")
	return " ".join(parts)

# --- Bodies, cameras, input ---

func _park_paladin(parked: bool) -> void:
	## Out of this round: hidden and unhurt on the ledge at the parked spot. He keeps
	## running (netfox ticks him whatever his process mode, and a disabled body has no space).
	_avatar.visible = not parked
	_avatar.god_mode = parked
	if parked:
		_pin_paladin(_parked_spot.global_transform, 0.0)

func _pin_paladin(at: Transform3D, seconds: float) -> void:
	## Move him the rollback-safe way (a plain teleport is undone when netfox replays older ticks):
	## pinned there for `seconds`, or until the next pin when 0.
	_pin_serial += 1
	_avatar.pin_transform(at)
	if seconds > 0.0:
		var serial := _pin_serial
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if serial == _pin_serial:
				_avatar.unpin_transform())

func _navigation_ready() -> void:
	## The floor's navmesh is baked on ready; units query the map, which syncs a few physics frames later.
	var nav_map := get_world_3d().navigation_map
	while NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		await get_tree().physics_frame

func _on_avatar_changed(_old_peer: int, new_peer: int) -> void:
	## What MultiplayerManager does in a match: the controller drives him, else AvatarAI.
	if new_peer > 0:
		_avatar.possess(new_peer)
	else:
		_avatar.release_control()
	_update_overview_camera()

func _update_overview_camera() -> void:
	## The overview camera when this peer drives nothing.
	var me := multiplayer.get_unique_id()
	var drives := GameState.avatar_peer_id == me and _avatar.visible
	for boss in _bosses.get_children():
		if boss is BossActor and not boss.is_queued_for_deletion() and boss.controlling_peer_id == me:
			drives = true
	if not drives:
		_overview_camera.make_current()

func _set_panel_open(open: bool) -> void:
	_panel_open = open
	_panel.visible = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	_avatar.avatar_input.input_enabled = not open
	for boss in _bosses.get_children():
		if boss is BossActor:
			boss.boss_input.input_enabled = not open
