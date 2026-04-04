extends Control

@onready var player_list = $VBoxContainer/PlayerList
@onready var start_button = $VBoxContainer/StartButton
@onready var faction_selector = $VBoxContainer/FactionSelector
@onready var player_count_label = $VBoxContainer/PlayerCount

var player_factions: Dictionary = {} # peer_id -> Faction enum

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_setup_faction_selector()
	_update_player_list()

	if multiplayer.is_server():
		# Register the host
		player_factions[1] = GameConstants.Faction.UNDEATH
		_update_player_list()

func _setup_faction_selector():
	faction_selector.clear()
	for faction in GameConstants.Faction.values():
		faction_selector.add_item(GameConstants.faction_names[faction], faction)
	faction_selector.selected = 0

func _on_faction_selected(index: int):
	var faction = faction_selector.get_item_id(index)
	_set_faction.rpc(multiplayer.get_unique_id(), faction)

@rpc("any_peer", "call_local", "reliable")
func _set_faction(peer_id: int, faction: int):
	player_factions[peer_id] = faction as GameConstants.Faction
	_update_player_list()

func _on_peer_connected(peer_id: int):
	if multiplayer.is_server():
		# Assign a default faction, avoiding duplicates when possible
		var taken = player_factions.values()
		var assigned = GameConstants.Faction.UNDEATH
		for faction in GameConstants.Faction.values():
			if faction not in taken:
				assigned = faction
				break
		player_factions[peer_id] = assigned

		# Sync full state to all peers
		_sync_all_factions.rpc(player_factions)

func _on_peer_disconnected(peer_id: int):
	player_factions.erase(peer_id)
	_update_player_list()

@rpc("authority", "call_local", "reliable")
func _sync_all_factions(factions: Dictionary):
	player_factions = factions
	_update_player_list()

func _update_player_list():
	# Clear existing entries
	for child in player_list.get_children():
		child.queue_free()

	var player_panel_scene = preload("res://scenes/menus/player_panel.tscn")
	var count = player_factions.size()

	for peer_id in player_factions:
		var panel = player_panel_scene.instantiate()
		player_list.add_child(panel)
		var display_name = "Player %d" % peer_id
		if peer_id == 1:
			display_name += " (Host)"
		panel.set_player(display_name, peer_id)
		panel.set_faction(player_factions[peer_id])

	player_count_label.text = "%d / %d Players" % [count, GameConstants.MAX_PLAYERS]

	if multiplayer.is_server():
		start_button.disabled = false

func _on_start_game_pressed():
	if multiplayer.is_server():
		NetworkManager.load_game_scene()
