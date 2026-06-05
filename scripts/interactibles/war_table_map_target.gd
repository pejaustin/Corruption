class_name WarTableMapTarget extends Interactable

## Flat Area3D covering the diorama surface. When the local peer has a
## selection built up and is aiming at empty map, E here records a draft for
## that selection at the aim point. The destination is computed by projecting
## the player's screen-center crosshair onto the diorama plane via the parent
## WarTable.
##
## The collision shape is intentionally thin so pieces (which sit above the
## diorama) intercept the InteractionRayCast first when aimed directly.

func get_prompt_text() -> String:
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return ""
	if not table.has_selection():
		return ""
	return "[E] target here (%d selected)" % table.get_selection_size()

func get_prompt_color() -> Color:
	return Color(0.4, 1, 0.4)

func _on_interact() -> void:
	if _player_in_range == null:
		return
	var table := _find_war_table()
	if table == null or not table.is_active_for_local_peer():
		return
	table.issue_draft_at_aim(_player_in_range)

func _find_war_table() -> WarTable:
	var n: Node = get_parent()
	while n:
		if n is WarTable:
			return n as WarTable
		n = n.get_parent()
	return null
