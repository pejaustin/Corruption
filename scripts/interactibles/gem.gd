extends Interactable

## The win condition. The Avatar entity touches this and the controller presses interact to win.

var _boss: Node

func _interactable_ready() -> void:
	_boss = get_tree().current_scene.get_node_or_null("World/GuardianBoss")

func _is_boss_alive() -> bool:
	return _boss and _boss is GuardianBoss and _boss.hp > 0

func get_prompt_text() -> String:
	if _is_boss_alive():
		return "Defeat the Guardian to claim the gem"
	elif is_avatar_in_range():
		return "Press E to corrupt the gem"
	elif _avatar_in_range and _avatar_in_range.is_dormant:
		return "The Avatar must be claimed first"
	return "The Gem"

func get_prompt_color() -> Color:
	if _is_boss_alive():
		return Color(0.8, 0.2, 0.2)
	elif is_avatar_in_range():
		return Color(1, 0, 0)
	elif _avatar_in_range and _avatar_in_range.is_dormant:
		return Color(0.5, 0.5, 0.5)
	return Color(0.8, 0.2, 0.8)

func _on_interact() -> void:
	if not is_avatar_in_range():
		return
	# If a guardian boss exists, gem can't be used directly
	if _boss and _boss is GuardianBoss:
		return
	GameState.request_win()
