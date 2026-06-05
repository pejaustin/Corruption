extends Interactable

## Mounted on advisor_actor.tscn as a child Area3D. Lets the owning overlord
## hand readied War Table commands to the Advisor. The Advisor then dispatches
## one Courier per command from the owner's tower spawn point, with each
## courier's waypoint set to the command's target.
##
## Pipeline: drafts are recorded at the war-table MapTarget; the Paper on the
## table promotes drafts → readied; the Advisor (this handoff) promotes readied
## → dispatched. Drafts still on the table are NOT touched by this interaction.
##
## When KnowledgeManager.INSTANT_COMMANDS is true (default), War Table clicks
## skip this loop entirely — see knowledge_manager.gd:issue_move_command.

func get_prompt_text() -> String:
	if _player_in_range == null:
		return "Advisor"
	if not _is_owning_overlord_in_range():
		return "Another overlord's Advisor"
	var ready_count := KnowledgeManager.get_readied_count(_player_in_range.name.to_int())
	if ready_count == 0:
		return "E to confer with Advisor"
	return "E to hand orders (%d)" % ready_count

func get_prompt_color() -> Color:
	return Color(0.95, 0.85, 0.55)

func _on_interact() -> void:
	if not _is_owning_overlord_in_range():
		return
	# Owner-authoritative handoff: the readied entries live in THIS machine's
	# local WorldModel (models are never replicated), so KnowledgeManager
	# gathers them here and ships the payload to the host, which spawns the
	# couriers and confirms each entry back. See request_dispatch.
	KnowledgeManager.request_dispatch(_player_in_range.name.to_int())

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
