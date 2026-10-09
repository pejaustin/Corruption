extends Interactable

## Tower station for driving the Paladin you hold (GDD §8). You can't claim
## him here: he is taken in the field (beaten and turned by your troops) or
## overpowered. If he's yours, E takes direct control; Q in his body lets go.

func _interactable_ready() -> void:
	# _refresh_prompt, NOT _update_ui_prompt: these fire on global avatar
	# state changes, and an unfocused station must never push its prompt onto
	# the shared InteractionUI.
	GameState.avatar_changed.connect(func(_o: int, _n: int) -> void: _refresh_prompt())
	GameState.avatar_owner_changed.connect(func(_o: int, _n: int) -> void: _refresh_prompt())

func get_prompt_text() -> String:
	var me := get_local_peer_id()
	if GameState.is_avatar_owner(me):
		if GameState.is_avatar(me):
			return "You walk in the Paladin"
		if is_overlord_in_range():
			return "Press E to take hold of the Paladin"
		return "The Paladin is yours"
	if not GameState.has_avatar_owner():
		return "The Paladin answers to the good faction"
	return "The Paladin answers to %s" % GameState.get_player_name(GameState.avatar_owner_peer_id)

func get_prompt_color() -> Color:
	var me := get_local_peer_id()
	if GameState.is_avatar_owner(me):
		return Color(1, 1, 0)
	return GameState.get_player_color(GameState.avatar_owner_peer_id)

func _on_interact() -> void:
	if not is_overlord_in_range():
		return
	var peer_id := get_overlord_peer_id()
	if get_local_peer_id() != peer_id:
		return
	if GameState.is_avatar_owner(peer_id) and not GameState.has_avatar():
		GameState.request_possess_avatar()
