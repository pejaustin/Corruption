extends Area3D

## Place this in each tower. When a player walks up and presses interact (E),
## they claim the Avatar if no one else has it.
## The actual mode switch and teleport is handled by MultiplayerManager.

@export var interact_prompt: Label3D

var _player_in_range: Player = null

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameState.avatar_changed.connect(func(_o, _n): _update_prompt())
	_update_prompt()

func _on_body_entered(body: Node3D):
	if body is Player:
		_player_in_range = body
		_update_prompt()

func _on_body_exited(body: Node3D):
	if body == _player_in_range:
		_player_in_range = null
		_update_prompt()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("player_action_1") and _player_in_range:
		var peer_id = _player_in_range.name.to_int()
		if multiplayer.get_unique_id() == peer_id and not GameState.has_avatar():
			GameState.request_claim_avatar()

func _update_prompt():
	if not interact_prompt:
		return
	if GameState.has_avatar():
		interact_prompt.text = "Avatar is active"
		interact_prompt.modulate = Color(0.5, 0.5, 0.5)
	elif _player_in_range:
		interact_prompt.text = "Press E to claim Avatar"
		interact_prompt.modulate = Color(1, 1, 0)
	else:
		interact_prompt.text = "Claim the Avatar"
		interact_prompt.modulate = Color(1, 1, 1)
