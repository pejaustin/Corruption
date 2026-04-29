extends Interactable

## Mounted on advisor_actor.tscn as a child Area3D. Lets the owning overlord
## hand pending War Table commands to the Advisor. The Advisor then dispatches
## one Courier per command from the owner's tower spawn point, with each
## courier's waypoint set to the command's target.
##
## When KnowledgeManager.INSTANT_COMMANDS is true (default), War Table clicks
## skip this loop entirely — see knowledge_manager.gd:issue_move_command.

func get_prompt_text() -> String:
	if _player_in_range == null:
		return "Advisor"
	if not _is_owning_overlord_in_range():
		return "Another overlord's Advisor"
	var draft_count := KnowledgeManager.get_draft_count(_player_in_range.name.to_int())
	if draft_count == 0:
		return "E to confer with Advisor"
	return "E to hand orders (%d)" % draft_count

func get_prompt_color() -> Color:
	return Color(0.95, 0.85, 0.55)

func _on_interact() -> void:
	if not _is_owning_overlord_in_range():
		return
	var peer_id := _player_in_range.name.to_int()
	# Route through host. Any peer can request; only the host actually
	# promotes the drafts to dispatched and spawns couriers.
	_request_handoff_rpc.rpc_id(1, peer_id)

@rpc("any_peer", "call_local", "reliable")
func _request_handoff_rpc(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	# Only the owner of the drafts may hand them off.
	if sender != peer_id:
		return
	KnowledgeManager.dispatch_drafts(peer_id)

func _is_owning_overlord_in_range() -> bool:
	## The Advisor only accepts orders from its owner. Owner is identified by
	## walking up the actor parent and reading owner_peer_id off the MinionActor.
	if _player_in_range == null:
		return false
	var advisor := _find_advisor()
	if advisor == null:
		return false
	return _player_in_range.name.to_int() == advisor.owner_peer_id

func _find_advisor() -> MinionActor:
	var parent := get_parent()
	while parent != null:
		if parent is MinionActor:
			return parent
		parent = parent.get_parent()
	return null
