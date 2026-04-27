extends Interactable

## The win condition. Avatar channels a capture on the gem; the channel
## broadcasts to all players (clouds darken, rumble, etc.) and on completion
## the controlling peer wins.

@onready var _channel: CaptureChannel = $CaptureChannel

var _boss: Node

func _interactable_ready() -> void:
	_boss = get_tree().current_scene.get_node_or_null("World/GuardianBoss")
	if _channel:
		_channel.channel_completed.connect(_on_channel_completed)

func _is_boss_alive() -> bool:
	return _boss and _boss is GuardianBoss and _boss.hp > 0

func get_prompt_text() -> String:
	if _channel and _channel.is_active() and _channel.get_peer_id() == get_local_peer_id():
		return "Corrupting the gem... (E to cancel)"
	if _is_boss_alive():
		return "Defeat the Guardian to claim the gem"
	elif is_avatar_in_range():
		return "Hold E to corrupt the gem"
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
	if _channel and _channel.is_active() and _channel.get_peer_id() == get_local_peer_id():
		_channel.request_cancel()
		return
	if _is_boss_alive():
		return
	if _channel and _channel.is_active():
		return
	_channel.try_start(_avatar_in_range, get_local_peer_id(), _avatar_in_range.faction)

func _on_channel_completed(peer_id: int, _faction: int) -> void:
	if not multiplayer.is_server():
		return
	if _is_boss_alive():
		return
	GameState._announce_win.rpc(peer_id)
