extends Interactable

## Place in each tower. Overlord walks up, looks at it, presses E to
## spend resources and summon a minion at ground level below the tower.
## Pressing 1-3 selects which minion type from the faction roster.

var _selected_type_index: int = 0
var _circle_active: bool = false

func get_prompt_text() -> String:
	if not is_overlord_in_range():
		return "Summoning Circle"
	var peer_id = get_overlord_peer_id()
	if GameState.is_avatar(peer_id):
		return "Cannot summon while controlling Avatar"
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if not mm:
		return "Summoning Circle (not ready)"
	var faction = mm._get_player_faction(peer_id)
	var roster = FactionData.get_minion_roster(faction)
	var res = mm.get_resources(peer_id)
	var count = mm.get_minion_count(peer_id)
	if not _circle_active:
		return "Press E to open Summoning Circle (Resources: %.0f | Minions: %d/%d)" % [
			res, count, MinionManager.MAX_MINIONS_PER_PLAYER
		]
	# Show roster with selected type highlighted
	var lines := "Summoning Circle — Resources: %.0f | Minions: %d/%d\n" % [
		res, count, MinionManager.MAX_MINIONS_PER_PLAYER
	]
	for i in roster.size():
		var mtype = roster[i]
		var marker = ">> " if i == _selected_type_index else "   "
		lines += "%s[%d] %s (HP:%d DMG:%d SPD:%.1f Cost:%d)" % [
			marker, i + 1, mtype.display_name, mtype.hp, mtype.damage, mtype.speed, mtype.cost
		]
		if mtype.trait_tag != "":
			lines += " [%s]" % mtype.trait_tag
		if i < roster.size() - 1:
			lines += "\n"
	lines += "\nPress 1-3 to select, E to summon, Q to close"
	return lines

func get_prompt_color() -> Color:
	if not is_overlord_in_range():
		return Color(0.8, 0.4, 1.0)
	if _circle_active:
		return Color(1, 0.8, 0)
	return Color(1, 1, 0)

func _on_interact() -> void:
	if not is_overlord_in_range():
		return
	var peer_id = get_overlord_peer_id()
	if get_local_peer_id() != peer_id:
		return
	if GameState.is_avatar(peer_id):
		return
	if not _circle_active:
		_circle_active = true
		_selected_type_index = 0
		_refresh_prompt()
		return
	# Summon the selected type
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		var faction = mm._get_player_faction(peer_id)
		var roster = FactionData.get_minion_roster(faction)
		if _selected_type_index < roster.size():
			mm.request_summon_minion(String(roster[_selected_type_index].id))
		_refresh_prompt()

func _on_player_exited() -> void:
	_circle_active = false

func _unhandled_input(event: InputEvent) -> void:
	if _circle_active and event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_circle_active = false
			_refresh_prompt()
			get_viewport().set_input_as_handled()
			return
		# Number keys select minion type
		var num = -1
		if event.keycode == KEY_1:
			num = 0
		elif event.keycode == KEY_2:
			num = 1
		elif event.keycode == KEY_3:
			num = 2
		if num >= 0:
			var peer_id = get_overlord_peer_id()
			var mm = get_tree().current_scene.get_node_or_null("MinionManager")
			if mm:
				var faction = mm._get_player_faction(peer_id)
				var roster = FactionData.get_minion_roster(faction)
				if num < roster.size():
					_selected_type_index = num
					_refresh_prompt()
			get_viewport().set_input_as_handled()
			return
	super(event)

func _refresh_prompt() -> void:
	if _is_focused and _player_in_range:
		InteractionUI.set_prompt(self, get_prompt_text(), get_prompt_color())
