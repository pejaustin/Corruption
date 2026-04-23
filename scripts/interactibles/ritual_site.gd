class_name RitualSite extends Interactable

## Eldritch ritual site. The Avatar channels here for several seconds to
## complete the ritual. Completion grants a bonus (free domination, corruption
## boost, eldritch vision) — the specific effect is authored as a RitualData
## resource so the same scene serves all ritual variants. Only Eldritch can
## channel; the Avatar is vulnerable while channeling.

enum RitualState { AVAILABLE, CHANNELING, COMPLETED }

@export var site_name: String = "Ritual Site"
@export var ritual: RitualData

var state: RitualState = RitualState.AVAILABLE
var _channel_progress: float = 0.0
var _channeling_peer: int = -1

func _get_channel_time() -> float:
	return ritual.channel_time if ritual else 5.0

func _get_ritual_display_name() -> String:
	return ritual.display_name if ritual else "Ritual"

func get_prompt_text() -> String:
	match state:
		RitualState.AVAILABLE:
			if is_avatar_in_range():
				var avatar := _get_avatar()
				if avatar and _is_eldritch_avatar(avatar):
					return "Press E to begin ritual: %s (%.1fs channel)" % [
						_get_ritual_display_name(), _get_channel_time()
					]
				return "Ritual Site (Eldritch faction only)"
			return "%s [%s]" % [site_name, _get_ritual_display_name()]
		RitualState.CHANNELING:
			var pct := (_channel_progress / _get_channel_time()) * 100.0
			return "Channeling %s... %.0f%%" % [_get_ritual_display_name(), pct]
		RitualState.COMPLETED:
			return "%s [Completed]" % site_name
	return site_name

func get_prompt_color() -> Color:
	match state:
		RitualState.AVAILABLE:
			if is_avatar_in_range():
				return Color(0.6, 0.2, 0.9)
			return Color(0.4, 0.1, 0.6)
		RitualState.CHANNELING:
			return Color(0.8, 0.3, 1.0)
		RitualState.COMPLETED:
			return Color(0.3, 0.3, 0.3)
	return Color.WHITE

func _on_interact() -> void:
	if state != RitualState.AVAILABLE or ritual == null:
		return
	if not is_avatar_in_range():
		return
	var avatar := _get_avatar()
	if not avatar or not _is_eldritch_avatar(avatar):
		return
	_request_channel.rpc_id(1)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if state != RitualState.CHANNELING:
		return
	var avatar := _get_avatar()
	if not avatar or avatar.is_dormant or avatar.hp <= 0:
		_cancel_channel.rpc()
		return
	if global_position.distance_to(avatar.global_position) > 4.0:
		_cancel_channel.rpc()
		return
	_channel_progress += delta
	_sync_channel_progress.rpc(_channel_progress)
	if _channel_progress >= _get_channel_time():
		_complete_ritual.rpc(_channeling_peer)

@rpc("any_peer", "call_local", "reliable")
func _request_channel() -> void:
	if not multiplayer.is_server():
		return
	if state != RitualState.AVAILABLE or ritual == null:
		return
	var avatar := _get_avatar()
	if not avatar or not _is_eldritch_avatar(avatar):
		return
	_start_channel.rpc(avatar.controlling_peer_id)

@rpc("authority", "call_local", "reliable")
func _start_channel(peer_id: int) -> void:
	state = RitualState.CHANNELING
	_channel_progress = 0.0
	_channeling_peer = peer_id
	_refresh_prompt()

@rpc("authority", "call_local", "reliable")
func _sync_channel_progress(progress: float) -> void:
	_channel_progress = progress
	_refresh_prompt()

@rpc("authority", "call_local", "reliable")
func _cancel_channel() -> void:
	state = RitualState.AVAILABLE
	_channel_progress = 0.0
	_channeling_peer = -1
	_refresh_prompt()

@rpc("authority", "call_local", "reliable")
func _complete_ritual(peer_id: int) -> void:
	state = RitualState.COMPLETED
	_channel_progress = _get_channel_time()
	_apply_ritual_bonus(peer_id)
	print("[RitualSite] %s completed by peer %d: %s" % [site_name, peer_id, _get_ritual_display_name()])
	_refresh_prompt()

func _apply_ritual_bonus(peer_id: int) -> void:
	if ritual == null:
		return
	match ritual.effect:
		RitualData.Effect.DOMINATION_MASTERY:
			var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
			if mm:
				mm.set_domination_discount(peer_id, ritual.domination_discount)
		RitualData.Effect.CORRUPTION_SURGE:
			var tm := get_tree().current_scene.get_node_or_null("TerritoryManager") as TerritoryManager
			if tm:
				tm.grant_corruption_surge(peer_id, ritual.duration)
		RitualData.Effect.ELDRITCH_VISION:
			GameState.grant_eldritch_vision(peer_id, ritual.duration)

func _get_avatar() -> PlayerActor:
	return get_tree().current_scene.get_node_or_null("World/Avatar")

func _is_eldritch_avatar(avatar: PlayerActor) -> bool:
	if avatar.controlling_peer_id <= 0:
		return false
	return GameState.get_faction(avatar.controlling_peer_id) == GameConstants.Faction.ELDRITCH

func _refresh_prompt() -> void:
	if _is_focused:
		InteractionUI.set_prompt(self, get_prompt_text(), get_prompt_color())
