extends Node

# Autoloader (singleton) to manage network setup (ENet P2P).
# IMPORTANT:
# Variables like is_hosting_game must be reset upon exiting to main menu after a game has been played.

const GAME_SCENE: String = "res://scenes/world/world.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/menus/main_menu.tscn"
const LOCALHOST: String = "127.0.0.1"
const DEDICATED_SERVER_FEATURE_NAME: String = "dedicated_server"
const _NETWORK_SCENE: String = "res://scenes/network/enet_network.tscn"

var _loading_scene: PackedScene = preload("res://scenes/loading.tscn")
var _active_loading_scene: Node
var active_network_node: Node
var is_hosting_game: bool = false
var active_host_ip: String = ""

func host_game(network_connection_configs: NetworkConnectionConfigs) -> void:
	print("Host game")

	# Keep these before the network scene is instantiated, to allow its _ready function to correctly read these properties.
	is_hosting_game = true
	active_host_ip = network_connection_configs.host_ip

	# We add the scene representing the network to the current tree
	# so that we can access the multiplayer APIs
	var network_scene: PackedScene = load(_NETWORK_SCENE)
	active_network_node = network_scene.instantiate()
	add_child(active_network_node)

	active_network_node.create_server_peer(network_connection_configs)

func join_game(network_connection_configs: NetworkConnectionConfigs) -> void:
	print("Join game, host_ip: %s:%s" % [network_connection_configs.host_ip, network_connection_configs.host_port])
	show_loading()

	var network_scene: PackedScene = load(_NETWORK_SCENE)
	active_network_node = network_scene.instantiate()
	add_child(active_network_node)

	# Connect client-side lifecycle signals
	active_network_node.network_server_disconnected.connect(disconnect_from_game)

	await active_network_node.create_client_peer(network_connection_configs)
	hide_loading()

func load_game_scene() -> void:
	_load_game_scene()

# Use this to kill the network connection and clean up for return to main menu
func disconnect_from_game() -> void:
	_load_main_menu_scene()

	NetworkTime.stop() # Stops the network type synchronizer from spamming ping RPCs after disconnect
	multiplayer.multiplayer_peer = null # Disconnect peer

	# Remove any child networks nodes
	for child in get_children():
		print("Removing child network node")
		child.queue_free()

	# Reset properties
	GameState.reset()
	reset_network_properties()

	# Make sure player has mouse access to select menu options
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Hit this in case we disconnected during loading screen
	hide_loading()

func reset_network_properties() -> void:
	is_hosting_game = false
	active_host_ip = ""

	if active_network_node != null:
		active_network_node.queue_free()
		active_network_node = null

func _load_game_scene() -> void:
	print("NetworkManager: Loading game scene...")
	get_tree().call_deferred(&"change_scene_to_packed", preload(GAME_SCENE))

func _load_main_menu_scene() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func show_loading() -> void:
	print("Show loading")
	_active_loading_scene = _loading_scene.instantiate()
	get_tree().root.add_child(_active_loading_scene)

func hide_loading() -> void:
	print("Hide loading")
	if _active_loading_scene != null:
		get_tree().root.remove_child(_active_loading_scene)
		_active_loading_scene.queue_free()
