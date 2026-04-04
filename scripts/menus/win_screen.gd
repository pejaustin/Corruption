extends Control

@onready var winner_label: Label = $VBoxContainer/WinnerLabel
@onready var return_button: Button = $VBoxContainer/ReturnButton

func _ready():
	visible = false
	GameState.game_won.connect(_on_game_won)
	return_button.pressed.connect(_on_return_pressed)

func _on_game_won(peer_id: int):
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if peer_id == multiplayer.get_unique_id():
		winner_label.text = "YOU CORRUPTED THE GEM!\nVICTORY!"
	else:
		winner_label.text = "Player %d corrupted the gem.\nDEFEAT." % peer_id

func _on_return_pressed():
	NetworkManager.disconnect_from_game()
