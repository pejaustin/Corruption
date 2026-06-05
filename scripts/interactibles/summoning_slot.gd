class_name SummoningSlot extends Interactable

## One slot on the summoning circle table. Reads the parent SummoningCircle's
## roster, indexes by `slot_index`, and on E asks the circle to summon that
## minion type. Roster lookups happen each prompt frame so faction swaps and
## resource changes show immediately.

@export var slot_index: int = 0

func get_prompt_text() -> String:
	var circle := _find_circle()
	if circle == null:
		return ""
	var pid := get_local_peer_id()
	if GameState.is_avatar(pid):
		return "(release Avatar to summon)"
	var roster := circle.get_roster()
	if slot_index < 0 or slot_index >= roster.size():
		return ""
	var mtype: MinionType = roster[slot_index]
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	var line := "[E] summon %s — HP %d / DMG %d / Cost %d" % [
		mtype.display_name, mtype.hp, mtype.damage, mtype.cost
	]
	if mm:
		var res := mm.get_resources(pid)
		var count := mm.get_minion_count(pid)
		line += "\nResources %.0f | Minions %d/%d" % [
			res, count, MinionManager.MAX_MINIONS_PER_PLAYER
		]
		if res < mtype.cost:
			line += "  (not enough)"
		elif count >= MinionManager.MAX_MINIONS_PER_PLAYER:
			line += "  (cap reached)"
	if mtype.trait_tag != &"":
		line += "  [%s]" % mtype.trait_tag
	return line

func get_prompt_color() -> Color:
	return Color(1, 1, 0)

func _on_interact() -> void:
	var circle := _find_circle()
	if circle:
		circle.request_summon(slot_index)

func _find_circle() -> SummoningCircle:
	var n: Node = get_parent()
	while n:
		if n is SummoningCircle:
			return n as SummoningCircle
		n = n.get_parent()
	return null
