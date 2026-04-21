extends Interactable

## Upgrade Altar in each tower. Spend resources on permanent upgrades
## that persist for the match. Upgrades affect both Overlord tools and
## Avatar performance when that player takes control.
## Press E to open, 1-3 to select upgrade, E to purchase, Q to close.

enum UpgradeType { MINION_HP, MINION_DAMAGE, RESOURCE_RATE, AVATAR_HP, AVATAR_DAMAGE }

class Upgrade:
	var type: UpgradeType
	var display_name: String
	var description: String
	var cost: int
	var max_level: int

	func _init(p_type: UpgradeType, p_name: String, p_desc: String, p_cost: int, p_max: int):
		type = p_type
		display_name = p_name
		description = p_desc
		cost = p_cost
		max_level = p_max

const UPGRADES: Array[Dictionary] = [
	{ "type": 0, "name": "Minion Vitality", "desc": "+20% minion HP", "cost": 15, "max": 3 },
	{ "type": 1, "name": "Minion Ferocity", "desc": "+20% minion damage", "cost": 15, "max": 3 },
	{ "type": 2, "name": "Dark Tithe", "desc": "+25% resource gain", "cost": 20, "max": 2 },
	{ "type": 3, "name": "Avatar Fortitude", "desc": "+25% Avatar HP when you control", "cost": 25, "max": 2 },
	{ "type": 4, "name": "Avatar Might", "desc": "+20% Avatar damage when you control", "cost": 25, "max": 2 },
]

var _altar_active: bool = false
var _selected_index: int = 0

# peer_id -> { upgrade_type: int -> level: int }
# Stored on MinionManager metadata for global access
static func get_upgrade_level(peer_id: int, upgrade_type: int) -> int:
	var gs = Engine.get_singleton("GameState") if Engine.has_singleton("GameState") else null
	if not gs:
		return 0
	if not gs.has_meta("upgrades"):
		return 0
	var upgrades = gs.get_meta("upgrades")
	if peer_id not in upgrades:
		return 0
	return upgrades[peer_id].get(upgrade_type, 0)

static func get_upgrade_multiplier(peer_id: int, upgrade_type: int) -> float:
	var level = get_upgrade_level(peer_id, upgrade_type)
	match upgrade_type:
		UpgradeType.MINION_HP, UpgradeType.MINION_DAMAGE, UpgradeType.AVATAR_DAMAGE:
			return 1.0 + level * 0.2
		UpgradeType.RESOURCE_RATE:
			return 1.0 + level * 0.25
		UpgradeType.AVATAR_HP:
			return 1.0 + level * 0.25
	return 1.0

func get_prompt_text() -> String:
	if not is_overlord_in_range():
		return "Upgrade Altar"
	var peer_id = get_overlord_peer_id()
	if not _altar_active:
		return "Press E to open Upgrade Altar"
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	var res = mm.get_resources(peer_id) if mm else 0.0
	var lines = "Upgrade Altar — Resources: %.0f\n" % res
	for i in UPGRADES.size():
		var u = UPGRADES[i]
		var level = _get_level(peer_id, u["type"])
		var marker = ">> " if i == _selected_index else "   "
		var maxed = " [MAX]" if level >= u["max"] else ""
		lines += "%s[%d] %s (Lv %d/%d, Cost: %d)%s\n" % [
			marker, i + 1, u["name"], level, u["max"], u["cost"], maxed
		]
		lines += "      %s\n" % u["desc"]
	lines += "Press 1-5 to select, E to purchase, Q to close"
	return lines

func get_prompt_color() -> Color:
	if _altar_active:
		return Color(0.8, 0.6, 1.0)
	elif is_overlord_in_range():
		return Color(1, 1, 0)
	return Color(0.6, 0.6, 0.6)

func _on_interact() -> void:
	if not is_overlord_in_range():
		return
	var peer_id = get_overlord_peer_id()
	if get_local_peer_id() != peer_id:
		return
	if not _altar_active:
		_altar_active = true
		_selected_index = 0
		_refresh_prompt()
		return
	# Purchase selected upgrade
	if _selected_index >= 0 and _selected_index < UPGRADES.size():
		var u = UPGRADES[_selected_index]
		_request_upgrade.rpc_id(1, u["type"])
		# Refresh after a short delay for server to process
		get_tree().create_timer(0.1).timeout.connect(_refresh_prompt)

func _on_player_exited() -> void:
	_altar_active = false

func _unhandled_input(event: InputEvent) -> void:
	if _altar_active and event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_altar_active = false
			_refresh_prompt()
			get_viewport().set_input_as_handled()
			return
		var num = -1
		if event.keycode == KEY_1: num = 0
		elif event.keycode == KEY_2: num = 1
		elif event.keycode == KEY_3: num = 2
		elif event.keycode == KEY_4: num = 3
		elif event.keycode == KEY_5: num = 4
		if num >= 0 and num < UPGRADES.size():
			_selected_index = num
			_refresh_prompt()
			get_viewport().set_input_as_handled()
			return
	super(event)

@rpc("any_peer", "call_local", "reliable")
func _request_upgrade(upgrade_type: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	# Find upgrade data
	var u_data: Dictionary
	for u in UPGRADES:
		if u["type"] == upgrade_type:
			u_data = u
			break
	if u_data.is_empty():
		return
	var level = _get_level(sender, upgrade_type)
	if level >= u_data["max"]:
		return
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if not mm:
		return
	if mm.get_resources(sender) < u_data["cost"]:
		return
	mm.resources[sender] -= u_data["cost"]
	mm._sync_resources.rpc(sender, mm.resources[sender])
	_apply_upgrade.rpc(sender, upgrade_type)

@rpc("authority", "call_local", "reliable")
func _apply_upgrade(peer_id: int, upgrade_type: int) -> void:
	if not GameState.has_meta("upgrades"):
		GameState.set_meta("upgrades", {})
	var upgrades = GameState.get_meta("upgrades")
	if peer_id not in upgrades:
		upgrades[peer_id] = {}
	upgrades[peer_id][upgrade_type] = upgrades[peer_id].get(upgrade_type, 0) + 1
	print("[UpgradeAltar] Peer %d upgraded %d to level %d" % [
		peer_id, upgrade_type, upgrades[peer_id][upgrade_type]
	])

func _get_level(peer_id: int, upgrade_type: int) -> int:
	if not GameState.has_meta("upgrades"):
		return 0
	var upgrades = GameState.get_meta("upgrades")
	if peer_id not in upgrades:
		return 0
	return upgrades[peer_id].get(upgrade_type, 0)

func _refresh_prompt() -> void:
	if _is_focused and _player_in_range:
		InteractionUI.set_prompt(self, get_prompt_text(), get_prompt_color())
