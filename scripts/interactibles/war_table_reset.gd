class_name WarTableReset extends Interactable

## Reset prop on the war table. E discards every draft entry AND clears the
## in-progress selection. Readied / dispatched orders are committed and not
## affected — those run their course (or get killed mid-courier).

func get_prompt_text() -> String:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return ""
	var pid := get_local_peer_id()
	var sel: int = table.get_selection_size()
	var drafts := KnowledgeManager.get_draft_count(pid)
	if sel == 0 and drafts == 0:
		return ""
	if drafts == 0:
		return "[E] clear selection"
	if sel == 0:
		return "[E] discard %d draft%s" % [drafts, "" if drafts == 1 else "s"]
	return "[E] discard %d draft%s + selection" % [drafts, "" if drafts == 1 else "s"]

func get_prompt_color() -> Color:
	return Color(1, 0.5, 0.5)

func _on_interact() -> void:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return
	var pid := get_local_peer_id()
	KnowledgeManager.clear_drafts(pid)
	table.clear_selection()

func _find_war_table() -> WarTable:
	var n: Node = get_parent()
	while n:
		if n is WarTable:
			return n as WarTable
		n = n.get_parent()
	return null
