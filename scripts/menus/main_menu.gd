extends Control

@export var main_panel: Control
@export var join_panel: Control
@export var lobby_panel: Control
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
