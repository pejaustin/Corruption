extends Control

@export var main_panel: Control
@export var join_panel: Control
@export var lobby_panel: Control
@export var host_ip_input: LineEdit
@export var host_port_input: LineEdit
## Optional. If a Label named "HostIPLabel" lives anywhere under lobby_panel,
## it'll get filled with the host's public IP when UPnP succeeds (or an error
## message when it doesn't). Lookup is by node name so the label can sit
## wherever the lobby layout wants.
@export var host_ip_label: Label

func _ready() -> void:
	print("Main menu ready...")

	_show_main_panel()

	if OS.has_feature(NetworkManager.DEDICATED_SERVER_FEATURE_NAME):
		print("Calling host game for dedicated server setup...")
		NetworkManager.host_game(NetworkConnectionConfigs.new(NetworkManager.LOCALHOST))

func _show_main_panel() -> void:
	main_panel.visible = true
	join_panel.visible = false
	lobby_panel.visible = false

func _show_join_panel() -> void:
	main_panel.visible = false
	join_panel.visible = true
	lobby_panel.visible = false

func _show_lobby_panel() -> void:
	main_panel.visible = false
	join_panel.visible = false
	lobby_panel.visible = true

func host_game() -> void:
	print("Host game pressed")
	NetworkManager.host_game(NetworkConnectionConfigs.new(NetworkManager.LOCALHOST))
	_show_lobby_panel()
	_set_host_ip_label("Opening UPnP…")
	if NetworkManager.active_network_node and NetworkManager.active_network_node.has_signal("upnp_finished"):
		NetworkManager.active_network_node.upnp_finished.connect(_on_upnp_finished)

func _on_upnp_finished(success: bool, public_ip: String, message: String) -> void:
	if success:
		_set_host_ip_label("Share with friends: %s:%d" % [public_ip, 8080])
	else:
		_set_host_ip_label(message)

func _set_host_ip_label(text: String) -> void:
	if host_ip_label:
		host_ip_label.text = text

func join_game() -> void:
	_show_join_panel()

func _on_join_go_pressed() -> void:
	if host_ip_input.text == "" or host_port_input.text == "":
		return
	var configs: NetworkConnectionConfigs = NetworkConnectionConfigs.new(host_ip_input.text)
	configs.host_port = host_port_input.text.to_int()
	NetworkManager.join_game(configs)
	NetworkManager.load_game_scene()

func _on_join_back_pressed() -> void:
	_show_main_panel()

func _on_lobby_start_pressed() -> void:
	NetworkManager.load_game_scene()

func _on_lobby_back_pressed() -> void:
	NetworkManager.disconnect_from_game()

func exit_game() -> void:
	get_tree().quit(0)
