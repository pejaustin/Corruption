extends Interactable

## Upgrade Altar in each tower. Spend resources on permanent match-long
## upgrades. Upgrades affect both Overlord tools and Avatar performance when
## that player takes control. Press E to open, 1-5 to select, E to purchase,
## Q to close.
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

var _altar_active: bool = false
var _selected_index: int = 0

static func get_upgrade_level(peer_id: int, kind: int) -> int:
	return GameState.get_upgrade_level(peer_id, kind)

static func get_upgrade_multiplier(peer_id: int, kind: int) -> float:
	var level := GameState.get_upgrade_level(peer_id, kind)
	for u in UPGRADES:
		if u.kind == kind:
			return u.get_multiplier(level)
	return 1.0

func get_prompt_text() -> String:
	if not is_overlord_in_range():
		return "Upgrade Altar"
	var peer_id := get_overlord_peer_id()
	if not _altar_active:
		return "Press E to open Upgrade Altar"
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	var res := mm.get_resources(peer_id) if mm else 0.0
	var lines := "Upgrade Altar — Resources: %.0f\n" % res
	for i in UPGRADES.size():
		var u := UPGRADES[i]
		var level := GameState.get_upgrade_level(peer_id, u.kind)
		var marker := ">> " if i == _selected_index else "   "
		var maxed := " [MAX]" if level >= u.max_level else ""
		lines += "%s[%d] %s (Lv %d/%d, Cost: %d)%s\n" % [
			marker, i + 1, u.display_name, level, u.max_level, u.cost, maxed
		]
		lines += "      %s\n" % u.description
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
	var peer_id := get_overlord_peer_id()
	if get_local_peer_id() != peer_id:
		return
	if not _altar_active:
		_altar_active = true
		_selected_index = 0
		_refresh_prompt()
		return
	if _selected_index >= 0 and _selected_index < UPGRADES.size():
		var u := UPGRADES[_selected_index]
		_request_upgrade.rpc_id(1, u.kind)
		# Refresh after a short delay so the host has time to apply.
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
		var num := -1
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

func _refresh_prompt() -> void:
	if _is_focused and _player_in_range:
		InteractionUI.set_prompt(self, get_prompt_text(), get_prompt_color())
