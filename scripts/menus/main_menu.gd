extends Control

@export var main_panel: Control
@export var join_panel: Control
@export var host_ip_input: LineEdit
@export var host_port_input: LineEdit

func _ready() -> void:
	print("Main menu ready...")
	_show_main_panel()

	if OS.has_feature(NetworkManager.DEDICATED_SERVER_FEATURE_NAME):
		print("Calling host game for dedicated server setup...")
		NetworkManager.host_game(NetworkConnectionConfigs.new(NetworkManager.LOCALHOST))

func _show_main_panel() -> void:
	main_panel.visible = true
	join_panel.visible = false

func _show_join_panel() -> void:
	main_panel.visible = false
	join_panel.visible = true

func host_game() -> void:
	print("Host game pressed")
	NetworkManager.host_game(NetworkConnectionConfigs.new(NetworkManager.LOCALHOST))
	NetworkManager.load_lobby_scene()

func join_game() -> void:
	_show_join_panel()

func _on_join_go_pressed() -> void:
	if host_ip_input.text == "" or host_port_input.text == "":
		return
	var configs: NetworkConnectionConfigs = NetworkConnectionConfigs.new(host_ip_input.text)
	configs.host_port = host_port_input.text.to_int()

	# join_game creates the network node and starts connecting. We hook the
	# accept signal AFTER the node exists so the lobby loads only once the
	# server has accepted us — otherwise the late-join sync against an
	# unconnected peer never resolves.
	NetworkManager.join_game(configs)
	if NetworkManager.active_network_node and NetworkManager.active_network_node.has_signal("network_client_connected"):
		NetworkManager.active_network_node.network_client_connected.connect(
			NetworkManager.load_lobby_scene, CONNECT_ONE_SHOT
		)

func _on_join_back_pressed() -> void:
	_show_main_panel()

func exit_game() -> void:
	get_tree().quit(0)
