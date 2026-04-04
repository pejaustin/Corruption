extends Area3D

## The win condition. The Avatar entity touches this and the controller presses interact to win.

@export var interact_prompt: Label3D

var _avatar_in_range: Avatar = null

func _ready():
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D):
	if body is Avatar:
		_avatar_in_range = body
		_update_prompt()

func _on_body_exited(body: Node3D):
	if body == _avatar_in_range:
		_avatar_in_range = null
		_update_prompt()

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("player_action_1") and _avatar_in_range:
		if not _avatar_in_range.is_dormant:
			var controller = _avatar_in_range.controlling_peer_id
			if multiplayer.get_unique_id() == controller:
				GameState.request_win()

func _update_prompt():
	if not interact_prompt:
		return
	if _avatar_in_range and not _avatar_in_range.is_dormant:
		interact_prompt.text = "Press E to corrupt the gem"
		interact_prompt.modulate = Color(1, 0, 0)
	elif _avatar_in_range and _avatar_in_range.is_dormant:
		interact_prompt.text = "The Avatar must be claimed first"
		interact_prompt.modulate = Color(0.5, 0.5, 0.5)
	else:
		interact_prompt.text = "The Gem"
		interact_prompt.modulate = Color(0.8, 0.2, 0.8)
