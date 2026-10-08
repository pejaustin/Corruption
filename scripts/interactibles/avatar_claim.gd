extends Interactable

## Place this in each tower. When a player walks up, looks at it, and presses E,
## they claim the Avatar: an unowned avatar is claimed (own + possess in one
## step); your own uncontrolled avatar is re-possessed; a rival's avatar can't
## be touched here — take it in the field.

func _interactable_ready() -> void:
	# _refresh_prompt, NOT _update_ui_prompt: these fire on global avatar
	# state changes, and an unfocused station must never push its prompt onto
	# the shared InteractionUI — that's how "Your Avatar awaits" got stuck on
	# screen after a Q from across the map (nothing ever cleared it because
	# the station was never focused).
	GameState.avatar_changed.connect(func(_o, _n): _refresh_prompt())
	GameState.avatar_owner_changed.connect(func(_o, _n): _refresh_prompt())

func get_prompt_text() -> String:
	var me := get_local_peer_id()
	if not GameState.has_avatar_owner():
		if is_overlord_in_range():
			return "Press E to claim the Avatar"
		return "Claim the Avatar"
	if GameState.is_avatar_owner(me):
		if GameState.is_avatar(me):
			return "You walk in the Avatar"  # not normally visible while possessing
		if is_overlord_in_range():
			return "Press E to possess your Avatar"
		return "Your Avatar awaits"
	var owner_faction := GameState.get_faction(GameState.avatar_owner_peer_id)
	var fname: String = GameConstants.faction_names.get(owner_faction, "another")
	return "Avatar sworn to %s" % fname

func get_prompt_color() -> Color:
	var me := get_local_peer_id()
	if not GameState.has_avatar_owner() or GameState.is_avatar_owner(me):
		return Color(1, 1, 0)
	var owner_faction := GameState.get_faction(GameState.avatar_owner_peer_id)
	return GameConstants.faction_colors.get(owner_faction, Color(0.5, 0.5, 0.5))

func _on_interact() -> void:
	if not is_overlord_in_range():
		return
	var peer_id = get_overlord_peer_id()
	if get_local_peer_id() != peer_id:
		return
	# Host validates: claims if unowned, possesses if we own it uncontrolled.
	var owns := GameState.is_avatar_owner(peer_id)
	if not GameState.has_avatar_owner() or (owns and not GameState.has_avatar()):
		GameState.request_claim_avatar()
