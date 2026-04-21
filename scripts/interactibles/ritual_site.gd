class_name RitualSite extends Interactable

## Eldritch ritual site. The Avatar must channel here for several seconds
## to complete the ritual. Completing a ritual grants a permanent bonus
## to the Eldritch Overlord: free domination, corruption boost, etc.
## The Avatar is vulnerable while channeling. Only Eldritch faction can use.

enum RitualState { AVAILABLE, CHANNELING, COMPLETED }

@export var site_name: String = "Ritual Site"
@export var channel_time: float = 5.0
@export var ritual_type: String = "domination_mastery"
## domination_mastery: Domination costs halved
## corruption_surge: Territory corruption spread doubles for 60s
## eldritch_vision: All enemy minions visible on war table for 60s

var state: RitualState = RitualState.AVAILABLE
var _channel_progress: float = 0.0
var _channeling_peer: int = -1

func get_prompt_text() -> String:
	match state:
		RitualState.AVAILABLE:
			if is_avatar_in_range():
				var avatar = _get_avatar()
				if avatar and _is_eldritch_avatar(avatar):
					return "Press E to begin ritual: %s (%.1fs channel)" % [
						_get_ritual_display_name(), channel_time
					]
				return "Ritual Site (Eldritch faction only)"
			return "%s [%s]" % [site_name, _get_ritual_display_name()]
		RitualState.CHANNELING:
			var pct = (_channel_progress / channel_time) * 100.0
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
	if state != RitualState.AVAILABLE:
		return
	if not is_avatar_in_range():
		return
	var avatar = _get_avatar()
	if not avatar or not _is_eldritch_avatar(avatar):
		return
	_request_channel.rpc_id(1)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if state != RitualState.CHANNELING:
		return
	# Check Avatar is still in range and alive
	var avatar = _get_avatar()
	if not avatar or avatar.is_dormant or avatar.hp <= 0:
		_cancel_channel.rpc()
		return
	if global_position.distance_to(avatar.global_position) > 4.0:
		_cancel_channel.rpc()
		return
	_channel_progress += delta
	_sync_channel_progress.rpc(_channel_progress)
	if _channel_progress >= channel_time:
		_complete_ritual.rpc(_channeling_peer)

@rpc("any_peer", "call_local", "reliable")
func _request_channel() -> void:
	if not multiplayer.is_server():
		return
	if state != RitualState.AVAILABLE:
		return
	var avatar = _get_avatar()
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
	_channel_progress = channel_time
	_apply_ritual_bonus(peer_id)
	print("[RitualSite] %s completed by peer %d: %s" % [site_name, peer_id, ritual_type])
	_refresh_prompt()

func _apply_ritual_bonus(peer_id: int) -> void:
	match ritual_type:
		"domination_mastery":
			# Halve domination cost for this peer
			var mm = get_tree().current_scene.get_node_or_null("MinionManager")
			if mm:
				# Store as metadata on the manager
				if not mm.has_meta("domination_discount"):
					mm.set_meta("domination_discount", {})
				var discounts = mm.get_meta("domination_discount")
				discounts[peer_id] = 0.5
		"corruption_surge":
			# Double corruption spread for 60 seconds
			var tm = get_tree().current_scene.get_node_or_null("TerritoryManager")
			if tm:
				tm.set_meta("corruption_surge_peer", peer_id)
				tm.set_meta("corruption_surge_timer", 60.0)
		"eldritch_vision":
			# Grant vision of all enemy minions for 60 seconds
			GameState.set_meta("eldritch_vision_peer", peer_id)
			GameState.set_meta("eldritch_vision_timer", 60.0)

func _get_avatar() -> PlayerActor:
	return get_tree().current_scene.get_node_or_null("World/Avatar")

func _is_eldritch_avatar(avatar: PlayerActor) -> bool:
	if avatar.controlling_peer_id <= 0:
		return false
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if mm:
		return mm._get_player_faction(avatar.controlling_peer_id) == GameConstants.Faction.ELDRITCH
	return false

func _get_ritual_display_name() -> String:
	match ritual_type:
		"domination_mastery":
			return "Domination Mastery"
		"corruption_surge":
			return "Corruption Surge"
		"eldritch_vision":
			return "Eldritch Vision"
	return ritual_type

func _refresh_prompt() -> void:
	if _is_focused:
		InteractionUI.set_prompt(self, get_prompt_text(), get_prompt_color())
