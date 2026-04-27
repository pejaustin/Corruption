class_name GemSite extends Interactable

## A minor gem site that can be captured for influence.
## Step 1: Overlord's minions clear the area (minion presence in range).
## Step 2: Avatar walks up and holds E to channel a capture.
## Captured sites grant passive influence to the controlling Overlord.

enum SiteState { NEUTRAL, CLEARED, CAPTURED }

@export var site_name: String = "Gem Site"
@export var influence_per_second: float = 0.5
@export var minion_clear_radius: float = 8.0

@onready var _channel: CaptureChannel = $CaptureChannel

var state: SiteState = SiteState.NEUTRAL
var controlling_faction: int = -1
var controlling_peer_id: int = -1
var _influence_timer: float = 0.0

func _interactable_ready() -> void:
	if _channel:
		_channel.channel_completed.connect(_on_channel_completed)

func get_prompt_text() -> String:
	if _channel and _channel.is_active() and _channel.get_peer_id() == get_local_peer_id():
		return "Capturing %s... (E to cancel)" % site_name
	match state:
		SiteState.NEUTRAL:
			return "%s (send minions to clear)" % site_name
		SiteState.CLEARED:
			var faction_name = GameConstants.faction_names.get(controlling_faction, "Unknown")
			if is_avatar_in_range():
				return "Hold E to capture for %s" % faction_name
			return "%s cleared by %s (Avatar must confirm)" % [site_name, faction_name]
		SiteState.CAPTURED:
			var faction_name = GameConstants.faction_names.get(controlling_faction, "Unknown")
			return "%s [%s]" % [site_name, faction_name]
	return site_name

func get_prompt_color() -> Color:
	match state:
		SiteState.NEUTRAL:
			return Color(0.8, 0.8, 0.8)
		SiteState.CLEARED:
			if is_avatar_in_range():
				return Color(1, 1, 0)
			return Color(0.6, 0.8, 0.6)
		SiteState.CAPTURED:
			return GameConstants.faction_colors.get(controlling_faction, Color.WHITE)
	return Color.WHITE

func _on_interact() -> void:
	if not is_avatar_in_range():
		return
	# Second E-press during our own channel cancels it.
	if _channel and _channel.is_active() and _channel.get_peer_id() == get_local_peer_id():
		_channel.request_cancel()
		return
	if state != SiteState.CLEARED:
		return
	if _channel and _channel.is_active():
		return  # Someone else is already channeling.
	_channel.try_start(_avatar_in_range, get_local_peer_id(), _avatar_in_range.faction)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	if state == SiteState.NEUTRAL:
		_check_minion_clear()

	if state == SiteState.CAPTURED and controlling_peer_id > 0:
		_influence_timer += delta
		if _influence_timer >= 1.0:
			_influence_timer = 0.0
			GameState.add_influence(controlling_peer_id, influence_per_second)

func _check_minion_clear() -> void:
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if not mm:
		return
	for minion in mm.get_all_minions():
		if minion.can_take_damage() and global_position.distance_to(minion.global_position) < minion_clear_radius:
			_set_cleared.rpc(minion.faction, minion.owner_peer_id)
			return

func _on_channel_completed(peer_id: int, faction: int) -> void:
	if not multiplayer.is_server():
		return
	if state != SiteState.CLEARED:
		return
	_set_captured.rpc(faction, peer_id)

@rpc("authority", "call_local", "reliable")
func _set_cleared(faction: int, peer_id: int) -> void:
	state = SiteState.CLEARED
	controlling_faction = faction
	controlling_peer_id = peer_id

@rpc("authority", "call_local", "reliable")
func _set_captured(faction: int, peer_id: int) -> void:
	state = SiteState.CAPTURED
	controlling_faction = faction
	controlling_peer_id = peer_id
	print("[GemSite] %s captured by peer %d (faction %d)" % [site_name, peer_id, faction])

@rpc("authority", "call_local", "reliable")
func reset_site() -> void:
	state = SiteState.NEUTRAL
	controlling_faction = -1
	controlling_peer_id = -1
	_influence_timer = 0.0
