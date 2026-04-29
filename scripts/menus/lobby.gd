class_name Lobby
extends Control

## Lobby scene shown after the host or a client establishes a connection.
## Manages name/faction/ready state across peers and gates a synchronized
## game start. CPU slots are host-controlled bots that fill empty seats —
## on START they're spawned as dummy players (see DebugManager.spawn_lobby_cpus)
## and inherit the lobby's chosen faction + name via GameState.

const PLAYER_PANEL_SCENE: PackedScene = preload("res://scenes/menus/player_panel.tscn")
const DUMMY_BASE_ID: int = 9001  # must match DebugManager.DUMMY_BASE_ID
const MIN_PLAYERS: int = 2
const MAX_NAME_LENGTH: int = 20

# peer_id -> faction id (GameConstants.Faction)
var player_factions: Dictionary[int, int] = {}
# peer_id -> display name
var player_names: Dictionary[int, String] = {}
# peer_id -> ready bool
var player_ready: Dictionary[int, bool] = {}

@onready var _player_list: VBoxContainer = %PlayerList
@onready var _player_count_label: Label = %PlayerCount
@onready var _status_label: Label = %StatusLabel
@onready var _start_button: Button = %StartButton
@onready var _add_cpu_button: Button = %AddCpuButton
@onready var _back_button: Button = %BackButton
@onready var _host_ip_label: Label = %HostIPLabel

var _panels: Dictionary[int, PlayerPanel] = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_start_button.pressed.connect(_on_start_pressed)
	_add_cpu_button.pressed.connect(_on_add_cpu_pressed)
	_back_button.pressed.connect(_on_back_pressed)

	_start_button.visible = multiplayer.is_server()
	_add_cpu_button.visible = multiplayer.is_server()
	_host_ip_label.visible = multiplayer.is_server()

	if multiplayer.is_server():
		_connect_upnp_label()
		var host_id: int = multiplayer.get_unique_id()
		_commit_seat(host_id, _first_available_faction([]), "Host", false)
		# Pick up any already-connected peers in case peer_connected fired
		# before this scene loaded.
		for pid in multiplayer.get_peers():
			var f: int = _first_available_faction(player_factions.values())
			_commit_seat(pid, f, "Player %d" % pid, false)
		_sync_all_state.rpc(player_factions, player_names, player_ready)
	else:
		# Client: ask the host for the current lobby snapshot.
		_request_sync.rpc_id(1)

	_refresh_ui()

# --- peer lifecycle (host only) ---

func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id in player_factions:
		return
	var faction: int = _first_available_faction(player_factions.values())
	var default_name: String = "Player %d" % peer_id
	_commit_seat(peer_id, faction, default_name, false)
	_sync_all_state.rpc(player_factions, player_names, player_ready)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_erase_seat(peer_id)
	_sync_all_state.rpc(player_factions, player_names, player_ready)

func _commit_seat(peer_id: int, faction: int, display_name: String, ready: bool) -> void:
	player_factions[peer_id] = faction
	player_names[peer_id] = display_name
	player_ready[peer_id] = ready

func _erase_seat(peer_id: int) -> void:
	player_factions.erase(peer_id)
	player_names.erase(peer_id)
	player_ready.erase(peer_id)

func _first_available_faction(taken: Array) -> int:
	for f in GameConstants.PLAYABLE_FACTIONS:
		if f not in taken:
			return f
	return GameConstants.PLAYABLE_FACTIONS[0]

# --- helpers ---

func is_cpu(peer_id: int) -> bool:
	return peer_id >= DUMMY_BASE_ID and peer_id < DUMMY_BASE_ID + 100

func _can_edit(peer_id: int) -> bool:
	if peer_id == multiplayer.get_unique_id():
		return true
	if multiplayer.is_server() and is_cpu(peer_id):
		return true
	return false

func _faction_available_for(peer_id: int, faction: int) -> bool:
	if faction not in GameConstants.PLAYABLE_FACTIONS:
		return false
	for pid in player_factions:
		if pid != peer_id and player_factions[pid] == faction:
			return false
	return true

func _next_cpu_id() -> int:
	var i: int = 0
	while i < 100:
		var candidate: int = DUMMY_BASE_ID + i
		if candidate not in player_factions:
			return candidate
		i += 1
	return -1

# --- panel-driven mutations ---

# These are connected to PlayerPanel signals; the panel emits its own peer_id
# as the first argument so a single handler covers every panel in the list.

func request_set_name(peer_id: int, new_name: String) -> void:
	var trimmed: String = new_name.strip_edges()
	if trimmed.length() > MAX_NAME_LENGTH:
		trimmed = trimmed.substr(0, MAX_NAME_LENGTH)
	if trimmed.is_empty():
		trimmed = "Player %d" % peer_id
	if multiplayer.is_server():
		_set_name.rpc(peer_id, trimmed)
	else:
		_request_name_change.rpc_id(1, peer_id, trimmed)

func request_set_faction(peer_id: int, faction: int) -> void:
	if multiplayer.is_server():
		if not _faction_available_for(peer_id, faction):
			_refresh_ui()
			return
		_set_faction.rpc(peer_id, faction)
	else:
		_request_faction_change.rpc_id(1, peer_id, faction)

func request_toggle_ready(peer_id: int, ready: bool) -> void:
	if multiplayer.is_server():
		_set_ready.rpc(peer_id, ready)
	else:
		_request_ready_change.rpc_id(1, peer_id, ready)

func request_remove_cpu(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if not is_cpu(peer_id):
		return
	_remove_cpu.rpc(peer_id)

# --- RPC: name ---

@rpc("any_peer", "call_local", "reliable")
func _request_name_change(peer_id: int, new_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if peer_id != sender and not is_cpu(peer_id):
		return  # can only rename yourself; CPUs are host-only
	_set_name.rpc(peer_id, new_name)

@rpc("authority", "call_local", "reliable")
func _set_name(peer_id: int, new_name: String) -> void:
	_apply_name(peer_id, new_name)

func _apply_name(peer_id: int, new_name: String) -> void:
	if peer_id in player_names:
		player_names[peer_id] = new_name
		_refresh_ui()

# --- RPC: faction ---

@rpc("any_peer", "call_local", "reliable")
func _request_faction_change(peer_id: int, faction: int) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if peer_id != sender and not is_cpu(peer_id):
		return
	if not _faction_available_for(peer_id, faction):
		# Snap requester back to current truth.
		_sync_all_state.rpc(player_factions, player_names, player_ready)
		return
	_set_faction.rpc(peer_id, faction)

@rpc("authority", "call_local", "reliable")
func _set_faction(peer_id: int, faction: int) -> void:
	_apply_faction(peer_id, faction)

func _apply_faction(peer_id: int, faction: int) -> void:
	if peer_id in player_factions:
		player_factions[peer_id] = faction
		# Picking a new faction clears your ready so others get a fresh confirmation.
		if peer_id in player_ready and not is_cpu(peer_id):
			player_ready[peer_id] = false
		_refresh_ui()

# --- RPC: ready ---

@rpc("any_peer", "call_local", "reliable")
func _request_ready_change(peer_id: int, ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if peer_id != sender:
		return  # CPUs never un-ready; clients can't ready others
	_set_ready.rpc(peer_id, ready)

@rpc("authority", "call_local", "reliable")
func _set_ready(peer_id: int, ready: bool) -> void:
	_apply_ready(peer_id, ready)

func _apply_ready(peer_id: int, ready: bool) -> void:
	if peer_id in player_ready:
		player_ready[peer_id] = ready
		_refresh_ui()

# --- CPU slots (host only) ---

func _on_add_cpu_pressed() -> void:
	if not multiplayer.is_server():
		return
	if player_factions.size() >= GameConstants.MAX_PLAYERS:
		return
	var cpu_id: int = _next_cpu_id()
	if cpu_id == -1:
		return
	var faction: int = _first_available_faction(player_factions.values())
	var default_name: String = "CPU %d" % (cpu_id - DUMMY_BASE_ID + 1)
	_add_cpu.rpc(cpu_id, faction, default_name)

@rpc("authority", "call_local", "reliable")
func _add_cpu(cpu_id: int, faction: int, default_name: String) -> void:
	_commit_seat(cpu_id, faction, default_name, true)
	_refresh_ui()

@rpc("authority", "call_local", "reliable")
func _remove_cpu(cpu_id: int) -> void:
	_erase_seat(cpu_id)
	_refresh_ui()

# --- late-join sync ---

@rpc("any_peer", "call_local", "reliable")
func _request_sync() -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	_sync_all_state.rpc_id(sender, player_factions, player_names, player_ready)

@rpc("authority", "call_local", "reliable")
func _sync_all_state(factions: Dictionary, names: Dictionary, ready: Dictionary) -> void:
	# call_local on the host hands us the same dict references we passed in,
	# so we must copy before clearing — otherwise we'd zero out the source.
	var f := factions.duplicate()
	var n := names.duplicate()
	var r := ready.duplicate()
	player_factions.clear()
	player_names.clear()
	player_ready.clear()
	for pid in f:
		player_factions[int(pid)] = int(f[pid])
	for pid in n:
		player_names[int(pid)] = String(n[pid])
	for pid in r:
		player_ready[int(pid)] = bool(r[pid])
	_refresh_ui()

# --- UI refresh ---

func _refresh_ui() -> void:
	var seats: Array = player_factions.keys()
	seats.sort()

	# Drop panels for departed seats.
	for pid in _panels.keys():
		if pid not in seats:
			_panels[pid].queue_free()
			_panels.erase(pid)

	for pid in seats:
		var panel: PlayerPanel
		if pid in _panels:
			panel = _panels[pid]
		else:
			panel = PLAYER_PANEL_SCENE.instantiate() as PlayerPanel
			_player_list.add_child(panel)
			_panels[pid] = panel
			panel.display_name_changed.connect(request_set_name)
			panel.faction_changed.connect(request_set_faction)
			panel.ready_changed.connect(request_toggle_ready)
			panel.cpu_remove_requested.connect(request_remove_cpu)

		var available: Array[int] = []
		for f in GameConstants.PLAYABLE_FACTIONS:
			if _faction_available_for(pid, f):
				available.append(f)
		panel.update_view(
			pid,
			player_names.get(pid, ""),
			player_factions.get(pid, GameConstants.PLAYABLE_FACTIONS[0]),
			player_ready.get(pid, false),
			is_cpu(pid),
			_can_edit(pid),
			multiplayer.is_server(),
			available
		)

	var count: int = seats.size()
	_player_count_label.text = "%d / %d Players" % [count, GameConstants.MAX_PLAYERS]

	var enough_players: bool = count >= MIN_PLAYERS
	var all_ready: bool = enough_players
	if all_ready:
		for pid in player_ready:
			if not player_ready[pid]:
				all_ready = false
				break

	_start_button.disabled = not (multiplayer.is_server() and all_ready)
	_add_cpu_button.disabled = not multiplayer.is_server() or count >= GameConstants.MAX_PLAYERS

	if not enough_players:
		_status_label.text = "Need at least %d players (real or CPU)" % MIN_PLAYERS
	elif not all_ready:
		_status_label.text = "Waiting for players to ready up…"
	elif multiplayer.is_server():
		_status_label.text = "All set — start the game"
	else:
		_status_label.text = "Waiting for host to start…"

# --- start (synchronized) ---

func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	var cpu_seats: Array[int] = []
	for pid in player_factions:
		if is_cpu(pid):
			cpu_seats.append(pid)
	# Stash CPU ids on the autoload so they survive the scene change. The world
	# scene's MultiplayerManager picks them up after registering real peers.
	DebugManager.pending_cpu_ids = cpu_seats
	GameState.sync_player_factions.rpc(player_factions)
	GameState.sync_player_names.rpc(player_names)
	_begin_game.rpc()

@rpc("authority", "call_local", "reliable")
func _begin_game() -> void:
	NetworkManager.load_game_scene()

# --- back ---

func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_game()

# --- UPnP host IP display (host only) ---

func _connect_upnp_label() -> void:
	var net := NetworkManager.active_network_node
	if net and net.has_signal("upnp_finished"):
		net.upnp_finished.connect(_on_upnp_finished)

func _on_upnp_finished(success: bool, public_ip: String, message: String) -> void:
	if success:
		_host_ip_label.text = "Share with friends: %s:%d" % [public_ip, 8080]
	else:
		_host_ip_label.text = message
