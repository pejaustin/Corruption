class_name GemSite extends Interactable

## A minor gem site that can be captured for corruption.
## The Avatar captures freely UNLESS hostile minions (another faction or the
## neutral faction) are nearby — the site is then "contested" and capture is
## blocked until they're cleared (by your minions or the Avatar's own sword).
## Friendly minion presence is never required.
## A held site raises its holder's MAX corruption by max_corruption_contribution
## and regenerates their corruption toward that ceiling at corruption_per_second.
## Sites never deplete — drains (abilities etc.) just refill from held sites.
## Corruption regen from held sites is the ONLY corruption source in the game.

enum SiteState { NEUTRAL, CAPTURED }

@export var site_name: String = "Gem Site"
@export var corruption_per_second: float = 0.5
## How much this site adds to its holder's maximum corruption while held.
@export var max_corruption_contribution: float = 7.0
## Hostile minions within this radius contest the site and block capture.
@export var contest_radius: float = 8.0

@onready var _channel: CaptureChannel = $CaptureChannel

var state: SiteState = SiteState.NEUTRAL
var controlling_faction: int = -1
var controlling_peer_id: int = -1
var _corruption_timer: float = 0.0
var _channeling_faction: int = -1

func _interactable_ready() -> void:
	# DivineIntervention polls this group for held sites.
	add_to_group(&"gem_sites")
	if _channel:
		_channel.channel_started.connect(_on_channel_started)
		_channel.channel_completed.connect(_on_channel_completed)
		_channel.channel_interrupted.connect(_on_channel_interrupted)

func get_prompt_text() -> String:
	if _channel and _channel.is_active() and _channel.get_peer_id() == get_local_peer_id():
		return "Capturing %s... (E to cancel)" % site_name
	match state:
		SiteState.NEUTRAL:
			if is_avatar_in_range():
				if _hostiles_near(_avatar_in_range.faction):
					return "%s — contested (clear hostile minions)" % site_name
				return "Hold E to capture %s" % site_name
			return "%s (capture with your Avatar)" % site_name
		SiteState.CAPTURED:
			var faction_name = GameConstants.faction_names.get(controlling_faction, "Unknown")
			return "%s [%s] (+%.0f max corruption)" % [site_name, faction_name, max_corruption_contribution]
	return site_name

func get_prompt_color() -> Color:
	match state:
		SiteState.NEUTRAL:
			if is_avatar_in_range():
				if _hostiles_near(_avatar_in_range.faction):
					return Color(1, 0.4, 0.3)
				return Color(1, 1, 0)
			return Color(0.8, 0.8, 0.8)
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
	if state != SiteState.NEUTRAL:
		return
	if _channel and _channel.is_active():
		return  # Someone else is already channeling.
	if _hostiles_near(_avatar_in_range.faction):
		return  # Contested — the prompt explains why E does nothing.
	_channel.try_start(_avatar_in_range, get_local_peer_id(), _avatar_in_range.faction)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	# Authoritative contest watch: hostiles arriving mid-channel break it.
	if _channel and _channel.is_active() and _channeling_faction >= 0:
		if _hostiles_near(_channeling_faction):
			_channel.interrupt(&"contested")

	if state == SiteState.CAPTURED and controlling_peer_id > 0:
		_corruption_timer += delta
		if _corruption_timer >= 1.0:
			_corruption_timer = 0.0
			# Regen toward the holder's max (Σ held-site contributions); never push past it.
			var headroom = GameState.get_max_corruption(controlling_peer_id) - GameState.get_corruption(controlling_peer_id)
			var amount = minf(corruption_per_second, headroom)
			if amount > 0.0:
				GameState.add_corruption(controlling_peer_id, amount)

func _hostiles_near(faction: int) -> bool:
	## True if any living minion of a different faction (incl. NEUTRAL) is
	## within contest_radius of the site.
	var mm = get_tree().current_scene.get_node_or_null("MinionManager")
	if not mm:
		return false
	for minion in mm.get_all_minions():
		if minion.faction == faction:
			continue
		if not minion.can_take_damage():
			continue
		if global_position.distance_to(minion.global_position) < contest_radius:
			return true
	return false

func _on_channel_started(_peer_id: int, faction: int) -> void:
	_channeling_faction = faction

func _on_channel_interrupted(_peer_id: int, _reason: StringName) -> void:
	_channeling_faction = -1

func _on_channel_completed(peer_id: int, faction: int) -> void:
	_channeling_faction = -1
	if not multiplayer.is_server():
		return
	if state != SiteState.NEUTRAL:
		return
	if _hostiles_near(faction):
		return  # Contested at the buzzer — no capture.
	_set_captured.rpc(faction, peer_id)

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
	_corruption_timer = 0.0
