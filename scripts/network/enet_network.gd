extends Node

signal network_client_connected
signal network_server_disconnected
## Emitted on the host once UPnP discovery + port mapping completes (or fails).
## `public_ip` is empty on failure; `message` is human-readable status for the
## lobby UI. Always emitted exactly once per server session.
signal upnp_finished(success: bool, public_ip: String, message: String)

const SERVER_PORT = 8080
const UPNP_DESC: String = "Corruption"

var _upnp_thread: Thread
var _upnp_mapped: bool = false

# func _ready():
	# Leaving note for clarity...
	# No connection exists when this _ready runs, it has yet to be established.
	# You cannot rely on authority checks until the connection has been made.

func create_server_peer(network_connection_configs: NetworkConnectionConfigs) -> void:
	var enet_network_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	enet_network_peer.create_server(SERVER_PORT, GameConstants.MAX_PLAYERS)
	multiplayer.multiplayer_peer = enet_network_peer
	_start_upnp_async()

## Discovers the gateway and opens SERVER_PORT on a worker thread so the host
## boot doesn't stall on the ~2s UPNP.discover() call. Result is reported via
## the `upnp_finished` signal on the main thread.
func _start_upnp_async() -> void:
	if _upnp_thread != null:
		return
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)

func _upnp_worker() -> void:
	var upnp := UPNP.new()
	var discover_err := upnp.discover()
	if discover_err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_emit_upnp_result", false, "", "UPnP discover failed (code %d)" % discover_err)
		return
	var gateway := upnp.get_gateway()
	if gateway == null or not gateway.is_valid_gateway():
		call_deferred("_emit_upnp_result", false, "", "UPnP: no usable gateway")
		return
	var map_err := upnp.add_port_mapping(SERVER_PORT, SERVER_PORT, UPNP_DESC, "UDP", 0)
	if map_err != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_emit_upnp_result", false, "", "UPnP port mapping failed (code %d)" % map_err)
		return
	var public_ip := upnp.query_external_address()
	call_deferred("_emit_upnp_result", true, public_ip, "UPnP open at %s:%d" % [public_ip, SERVER_PORT])

func _emit_upnp_result(success: bool, public_ip: String, message: String) -> void:
	_upnp_mapped = success
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if success:
		print(message)
	else:
		push_warning(message + " — fall back to Tailscale, manual port forward, or LAN")
	upnp_finished.emit(success, public_ip, message)

func _exit_tree() -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if _upnp_mapped:
		var upnp := UPNP.new()
		if upnp.discover() == UPNP.UPNP_RESULT_SUCCESS:
			upnp.delete_port_mapping(SERVER_PORT, "UDP")
		_upnp_mapped = false

func create_client_peer(network_connection_configs: NetworkConnectionConfigs) -> void:
	setup_client_connection_signals()

	var enet_network_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	enet_network_peer.create_client(network_connection_configs.host_ip, network_connection_configs.host_port)
	multiplayer.multiplayer_peer = enet_network_peer

func _connected_to_server() -> void:
	# Once our peer has a confirmed connection to the server/host, emit the connected signals
	# to prepare for game play. Right now it just loads the game scene on the client.
	print("Client connected to server/host, on peer %s with auth: %s" % [multiplayer.get_unique_id(), get_multiplayer_authority()])
	if not is_multiplayer_authority():
		network_client_connected.emit()

func _server_disconnected() -> void:
	print("Server disconnected!")
	network_server_disconnected.emit()

func setup_client_connection_signals() -> void:
	multiplayer.connected_to_server.connect(_connected_to_server)
	multiplayer.server_disconnected.connect(_server_disconnected)
	#multiplayer.peer_connected.connect(_client_connected) # Right now there's no reason to use this...
