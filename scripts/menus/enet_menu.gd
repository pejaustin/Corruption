extends Control

@export var go_button: Button
@export var back_button: Button
@export var host_ip_input: LineEdit # Defaults to "127.0.0.1" (localhost)
@export var host_port_input: LineEdit # Defaults to "8080"
@export var option_label: RichTextLabel

var is_hosting = false
var networkConnection_configs

signal secondary_menu_completed
signal secondary_menu_cancelled

func _enter_tree():
	if is_hosting:
		NetworkManager.host_game(NetworkConnectionConfigs.new(NetworkManager.LOCALHOST))
		$LobbyMenu.visible = true
		$JoinPanel.visible = false
		$LobbyMenu/Start.disabled = false
		_load_lobby()
	else:
		$LobbyMenu.visible = false
		$JoinPanel.visible = true

func _load_lobby():
	# Replace the inline lobby content with the full lobby scene
	var lobby_scene = preload("res://scenes/menus/lobby.tscn")
	var lobby = lobby_scene.instantiate()
	$LobbyMenu.add_child(lobby)

func _on_go_pressed():
	if host_ip_input.text != "" and host_port_input.text != "":
		var network_connection_configs = NetworkConnectionConfigs.new(host_ip_input.text)
		network_connection_configs.host_port = host_port_input.text.to_int()
		NetworkManager.join_game(network_connection_configs)
	secondary_menu_completed.emit()

func _on_back_pressed():
	secondary_menu_cancelled.emit()

func _on_start_pressed():
	secondary_menu_completed.emit()
