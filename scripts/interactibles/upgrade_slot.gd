class_name UpgradeSlot extends Interactable

## One pedestal on the upgrade altar. Reads `UpgradeAltar.UPGRADES[slot_index]`
## for its catalog entry, the local peer's level for that upgrade off
## GameState, and the local peer's resources off MinionManager. E asks the
## parent altar to purchase the upgrade.

@export var slot_index: int = 0

func get_prompt_text() -> String:
	var altar := _find_altar()
	if altar == null:
		return ""
	var u: UpgradeData = UpgradeAltar.get_upgrade_at(slot_index)
	if u == null:
		return ""
	var pid := get_local_peer_id()
	var level := GameState.get_upgrade_level(pid, u.kind)
	if level >= u.max_level:
		return "%s [MAX %d/%d]\n%s" % [u.display_name, level, u.max_level, u.description]
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	var res: float = 0.0
	if mm:
		res = mm.get_resources(pid)
	var afford := "" if res >= u.cost else "  (need %.0f)" % u.cost
	return "[E] %s — Lv %d/%d, Cost %d%s\n%s" % [
		u.display_name, level, u.max_level, u.cost, afford, u.description
	]

func get_prompt_color() -> Color:
	return Color(0.85, 0.65, 1.0)

func _on_interact() -> void:
	var altar := _find_altar()
	if altar:
		altar.request_upgrade(slot_index)

func _find_altar() -> UpgradeAltar:
	var n: Node = get_parent()
	while n:
		if n is UpgradeAltar:
			return n as UpgradeAltar
		n = n.get_parent()
	return null
