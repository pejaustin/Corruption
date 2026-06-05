class_name WarTablePaper extends Interactable

## Orders scroll on the war-table surface. E promotes every draft entry in the
## local peer's WorldModel to the readied stage (paper has been "picked up"
## and committed). Drafts that are already readied or dispatched aren't
## touched. Once readied, the orders are no longer cancelable from the table —
## the overlord must walk to the Advisor to actually dispatch couriers.

func get_prompt_text() -> String:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return ""
	var pid := get_local_peer_id()
	var draft_count := KnowledgeManager.get_draft_count(pid)
	var ready_count := KnowledgeManager.get_readied_count(pid)
	if draft_count == 0 and ready_count == 0:
		return ""
	if draft_count == 0:
		# All current orders already readied — nothing for the paper to promote.
		# Hint the player toward the next step.
		return "(orders ready — see Advisor)"
	if draft_count == 1:
		return "[E] ready 1 order"
	return "[E] ready %d orders" % draft_count

func get_prompt_color() -> Color:
	return Color(0.95, 0.85, 0.55)

func _on_interact() -> void:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return
	var pid := get_local_peer_id()
	if KnowledgeManager.get_draft_count(pid) == 0:
		return
	KnowledgeManager.ready_drafts(pid)

func _find_war_table() -> WarTable:
	var n: Node = get_parent()
	while n:
		if n is WarTable:
			return n as WarTable
		n = n.get_parent()
	return null
