extends Control

@onready var winner_label: Label = $VBoxContainer/WinnerLabel
@onready var return_button: Button = $VBoxContainer/ReturnButton

func _ready() -> void:
	visible = false
	GameState.game_won.connect(_on_game_won)
	GameState.game_drawn.connect(_on_game_drawn)
	return_button.pressed.connect(_on_return_pressed)

func _on_game_won(peer_id: int) -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if peer_id == multiplayer.get_unique_id():
		winner_label.text = "PLACEHOLDER: You beat the gauntlet.\nVICTORY!"
	else:
		winner_label.text = "PLACEHOLDER: %s beat the gauntlet.\nDEFEAT." % GameState.get_player_name(peer_id)

func _on_game_drawn() -> void:
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	winner_label.text = "PLACEHOLDER: The city centre can no longer be corrupted.\nDRAW."

func _on_return_pressed() -> void:
	NetworkManager.disconnect_from_game()
