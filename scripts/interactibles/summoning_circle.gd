class_name SummoningCircle extends Interactable

## Passive container holding three SummoningSlot child Interactables, one per
## faction-roster index. The circle itself is no longer interactive — its
## prompt is empty. The slots are individual E-driven interactables that look
## up the local peer's roster on each prompt refresh and summon their slot's
## minion type on E.
##
## Roster comes from the local peer's faction (via MinionManager). When the
## faction changes (debug cycle, faction swap), the slots automatically rebind
## because they ask for the roster every prompt frame.

func get_prompt_text() -> String:
	return ""

func get_prompt_color() -> Color:
	return Color(0.6, 0.6, 0.6)

func _on_interact() -> void:
	pass

func get_roster() -> Array:
	## Returns the local peer's faction roster, or [] if the manager isn't ready.
	var pid := multiplayer.get_unique_id()
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return []
	var faction = mm._get_player_faction(pid)
	return FactionData.get_minion_roster(faction)

func request_summon(slot_index: int) -> bool:
	## Called by SummoningSlot._on_interact. Routes through MinionManager's
	## existing host-authoritative spawn RPC.
	var pid := multiplayer.get_unique_id()
	if GameState.is_avatar(pid):
		return false
	var roster := get_roster()
	if slot_index < 0 or slot_index >= roster.size():
		return false
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return false
	mm.request_summon_minion(String(roster[slot_index].id))
	return true
