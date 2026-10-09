class_name SummoningCircle extends Interactable

## The tower's summoning circle (GDD §2, §5): human remains brought to the
## tower are raised here into undead. Passive container for SummoningSlot
## children, one per unit in the local player's roster; each slot raises one
## unit of its type from one body.
##
## PLACEHOLDER: which undead the roster offers and what each costs in remains
## are not designed (unit types are Austin's, GDD §11); every slot costs one body.

func get_prompt_text() -> String:
	return ""

func get_prompt_color() -> Color:
	return Color(0.6, 0.6, 0.6)

func _on_interact() -> void:
	pass

func get_roster() -> Array[MinionType]:
	## The local player's raisable units.
	var faction := GameState.get_faction(multiplayer.get_unique_id())
	var out: Array[MinionType] = []
	for mt in FactionData.get_minion_roster(faction):
		if mt.trait_tag in CorruptionSite.NON_COMBAT_TRAITS:
			continue
		out.append(mt)
	return out

func get_remains() -> int:
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return 0
	return mm.get_remains(multiplayer.get_unique_id())

func request_raise(slot_index: int) -> bool:
	## Called by SummoningSlot._on_interact.
	var pid := multiplayer.get_unique_id()
	if GameState.is_avatar(pid):
		return false
	var roster := get_roster()
	if slot_index < 0 or slot_index >= roster.size():
		return false
	if get_remains() <= 0:
		return false
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return false
	mm.request_raise_from_remains(String(roster[slot_index].id))
	return true
