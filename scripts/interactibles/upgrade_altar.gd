class_name UpgradeAltar extends Interactable

## Passive container holding five UpgradeSlot child Interactables, one per
## entry in the UPGRADES catalog. The altar itself is no longer interactive —
## its prompt is empty. Each slot is its own E-driven interactable that shows
## the upgrade's name / level / cost and on E asks the altar to purchase it.
##
## Upgrade catalog is authored as UpgradeData resources under res://data/upgrades/.
## Level state lives on GameState.upgrade_levels.

const UPGRADES: Array[UpgradeData] = [
	preload("res://data/upgrades/minion_vitality.tres"),
	preload("res://data/upgrades/minion_ferocity.tres"),
	preload("res://data/upgrades/dark_tithe.tres"),
	preload("res://data/upgrades/avatar_fortitude.tres"),
	preload("res://data/upgrades/avatar_might.tres"),
]

static func get_upgrade_level(peer_id: int, kind: int) -> int:
	return GameState.get_upgrade_level(peer_id, kind)

static func get_upgrade_multiplier(peer_id: int, kind: int) -> float:
	var level := GameState.get_upgrade_level(peer_id, kind)
	for u in UPGRADES:
		if u.kind == kind:
			return u.get_multiplier(level)
	return 1.0

static func get_upgrade_at(slot_index: int) -> UpgradeData:
	if slot_index < 0 or slot_index >= UPGRADES.size():
		return null
	return UPGRADES[slot_index]

func get_prompt_text() -> String:
	return ""

func get_prompt_color() -> Color:
	return Color(0.6, 0.6, 0.6)

func _on_interact() -> void:
	pass

func request_upgrade(slot_index: int) -> void:
	## Called by UpgradeSlot._on_interact. Routes through the altar's
	## host-authoritative RPC for resource debit + level bump.
	var u := get_upgrade_at(slot_index)
	if u == null:
		return
	_request_upgrade.rpc_id(1, u.kind)

@rpc("any_peer", "call_local", "reliable")
func _request_upgrade(kind: int) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	var upgrade := _find_upgrade(kind)
	if upgrade == null:
		return
	var level := GameState.get_upgrade_level(sender, kind)
	if level >= upgrade.max_level:
		return
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	if mm.get_resources(sender) < upgrade.cost:
		return
	mm.resources[sender] -= upgrade.cost
	mm._sync_resources.rpc(sender, mm.resources[sender])
	_apply_upgrade.rpc(sender, kind)

@rpc("authority", "call_local", "reliable")
func _apply_upgrade(peer_id: int, kind: int) -> void:
	GameState.add_upgrade(peer_id, kind)
	print("[UpgradeAltar] Peer %d upgraded kind %d to level %d" % [
		peer_id, kind, GameState.get_upgrade_level(peer_id, kind)
	])

func _find_upgrade(kind: int) -> UpgradeData:
	for u in UPGRADES:
		if u.kind == kind:
			return u
	return null
