class_name WarTablePiece extends Interactable

## One chess-piece stack on the diorama. Carries 1+ minion ids that all share
## (owner_peer_id, faction). WarTableMap spawns one of these per cluster and
## re-stamps the metadata each render frame:
##   - member_ids: Array[int]
##   - owner_peer_id: int
##   - faction: int
##
## Focus telemetry: notifies the parent WarTable so the inspector knows which
## stack's popup-group is currently under the crosshair (used for the auto-
## close grace timer). E selects: single-member toggles that one id;
## multi-member toggles the ghost popup latch — first E spawns ghosts, second
## E closes them. Per-member picks happen on the ghosts themselves.

func get_prompt_text() -> String:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return ""
	var pid := get_local_peer_id()
	if int(get_meta(&"owner_peer_id", -1)) != pid:
		return ""
	var ids: Array = get_meta(&"member_ids", [] as Array)
	if ids.is_empty():
		return ""
	if ids.size() == 1:
		# Single-member: E selects directly. No popup needed.
		var available := _available_members(pid)
		if available.is_empty():
			return ""
		return "[E] select"
	# Multi-member: E latches the ghost popup open / closed.
	if table.is_popup_open_for(self):
		return "[E] close"
	return "[E] inspect (%d)" % ids.size()

func get_prompt_color() -> Color:
	return Color(1, 1, 0.5)

func _on_interact() -> void:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return
	var pid := get_local_peer_id()
	if int(get_meta(&"owner_peer_id", -1)) != pid:
		return
	var ids: Array = get_meta(&"member_ids", [] as Array)
	if ids.size() == 1:
		# Single member: select directly.
		var available := _available_members(pid)
		if available.is_empty():
			return
		table.toggle_select(available)
	else:
		# Multi member: latch the ghost popup. The inspector reads
		# table._popup_for_stack and spawns ghosts accordingly.
		table.toggle_popup_for(self)

func set_focused(focused: bool, who: Node3D = null) -> void:
	super(focused, who)
	var table := _find_war_table()
	if table == null:
		return
	# Multi-member stacks tell the table they're under the crosshair so the
	# inspector spawns ghost picks above them. Single-member stacks don't need
	# the popup — passing self/null is still cheap and keeps the table's
	# focused-stack reference accurate for any other consumer.
	table.notify_stack_focus(self if focused else null)

func _available_members(peer_id: int) -> Array[int]:
	var ids: Array = get_meta(&"member_ids", [] as Array)
	var out: Array[int] = []
	for raw in ids:
		var mid: int = int(raw)
		if KnowledgeManager.is_minion_pending(peer_id, mid):
			continue
		out.append(mid)
	return out

func _find_war_table() -> WarTable:
	var n: Node = get_parent()
	while n:
		if n is WarTable:
			return n as WarTable
		n = n.get_parent()
	return null
