extends Interactable

## Place this in each tower. When a player walks up, looks at it, and presses E,
## they claim the Avatar if no one else has it.

func _interactable_ready() -> void:
	GameState.avatar_changed.connect(func(_o, _n): _update_ui_prompt())

func get_prompt_text() -> String:
	if GameState.has_avatar():
		return "Avatar is active"
	elif is_overlord_in_range():
		return "Press E to claim Avatar"
	return "Claim the Avatar"

func get_prompt_color() -> Color:
	if GameState.has_avatar():
		return Color(0.5, 0.5, 0.5)
	return Color(1, 1, 0)

func _on_interact() -> void:
	if not is_overlord_in_range():
		return
	var peer_id = get_overlord_peer_id()
	if get_local_peer_id() == peer_id and not GameState.has_avatar():
		GameState.request_claim_avatar()
