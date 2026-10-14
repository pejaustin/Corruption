class_name SummoningSlot extends Interactable

## One slot on the summoning circle. Raises one unit of its roster type from
## one body waiting at the tower.

@export var slot_index: int = 0

func get_prompt_text() -> String:
	var circle := _find_circle()
	if circle == null:
		return ""
	if GameState.is_avatar(get_local_peer_id()):
		return "(release the Paladin to raise the dead)"
	var roster := circle.get_roster()
	if slot_index < 0 or slot_index >= roster.size():
		return ""
	var mtype: MinionType = roster[slot_index]
	var remains := circle.get_remains()
	if remains <= 0:
		return "%s — no remains to raise. Bring bodies home." % mtype.display_name
	return "[E] raise a %s (%d remains here)" % [mtype.display_name, remains]

func get_prompt_color() -> Color:
	var circle := _find_circle()
	if circle and circle.get_remains() > 0:
		return Color(0.7, 1.0, 0.7)
	return Color(0.6, 0.6, 0.6)

func _on_interact() -> void:
	var circle := _find_circle()
	if circle:
		circle.request_raise(slot_index)

func _find_circle() -> SummoningCircle:
	var n: Node = get_parent()
	while n:
		if n is SummoningCircle:
			return n as SummoningCircle
		n = n.get_parent()
	return null
