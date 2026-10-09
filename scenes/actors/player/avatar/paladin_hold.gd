class_name PaladinHold extends Node

## Who holds the Paladin and how firmly (GDD §8; tickets #554, #555).
## Host-authoritative; a child of AvatarActor (added in code, so the node path
## is the same on every peer). The host ticks it and mirrors the numbers to
## clients for the Palantir prompt and the avatar HUD.
##
## Taking him (Q14):
## - **Takeover by troops**, mirroring CorruptionSite's presence capture: while
##   his HP is at or below TAKEOVER_HP_FRACTION, any player's troop strength
##   inside TAKEOVER_RADIUS that meets TAKEOVER_THRESHOLD builds that player's
##   progress at strength / threshold speed. His company (troops of his own
##   allegiance) present freezes it: they have to be beaten first.
## - **Overpowering** with raw corruption: a player holding strictly more
##   AVATAR_CONTROL sites than his owner can start a slow overpower while
##   looking through a Palantir.
## Keeping him (Q15): the owner's hold fades over HOLD_SECONDS unless he stands
## inside one of the owner's held sites (their tower counts), which keeps it
## full. At zero hold the owner loses him to the good faction. Zero HP is
## handled by AvatarActor._die.

signal changed

const TICK_INTERVAL: float = 0.5
## PLACEHOLDER: tuning — HP fraction at or below which anyone can begin a takeover.
const TAKEOVER_HP_FRACTION: float = 0.3
## PLACEHOLDER: tuning — troops within this horizontal distance of him count.
const TAKEOVER_RADIUS: float = 10.0
## PLACEHOLDER: tuning — troop strength needed to begin turning him.
const TAKEOVER_THRESHOLD: float = 3.0
## PLACEHOLDER: tuning — seconds to turn him with exactly the threshold strength.
const TAKEOVER_SECONDS: float = 15.0
## PLACEHOLDER: tuning — seconds for a stalled takeover to fade from full to nothing.
const TAKEOVER_FADE_SECONDS: float = 30.0
## PLACEHOLDER: tuning — seconds for a hold to fade from full to nothing away
## from the owner's corruption.
const HOLD_SECONDS: float = 300.0
## PLACEHOLDER: tuning — seconds of looking through a Palantir to overpower him.
const OVERPOWER_SECONDS: float = 240.0

## The owner's hold on him, 0..1. Full while he is near their corruption.
var hold: float = 1.0
## peer -> takeover progress 0..1 (troops turning him while he is low).
var takeover: Dictionary[int, float] = {}
## peer -> overpower progress 0..1 (raw corruption from a Palantir).
var overpower: Dictionary[int, float] = {}
## Allegiance -> troop strength near him at the last tick (host only).
var present_strength: Dictionary[int, float] = {}

var _tick_timer: float = 0.0

@onready var _avatar: AvatarActor = get_parent() as AvatarActor

func _ready() -> void:
	GameState.avatar_owner_changed.connect(_on_avatar_owner_changed)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or _avatar == null:
		return
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	var dt := _tick_timer
	_tick_timer = 0.0
	_tick_hold(dt)
	_tick_takeover(dt)
	_tick_overpower(dt)
	_sync.rpc(hold, takeover, overpower)
	changed.emit()

# --- Queries ---

func is_low() -> bool:
	## True while he is weak enough for anyone to begin a takeover.
	return _avatar.hp > 0 and float(_avatar.hp) <= float(_avatar.get_max_hp()) * TAKEOVER_HP_FRACTION

func get_takeover(peer_id: int) -> float:
	return takeover.get(peer_id, 0.0)

func get_overpower(peer_id: int) -> float:
	return overpower.get(peer_id, 0.0)

func is_near_corruption(peer_id: int) -> bool:
	## Inside any site `peer_id` holds (their tower included): the source of
	## corruption that keeps a hold full (Q15).
	if peer_id <= 0:
		return false
	for node in GameState.get_held_sites(peer_id):
		var site := node as CorruptionSite
		if site == null:
			continue
		var offset := _avatar.global_position - site.global_position
		offset.y = 0.0
		if offset.length() <= site.radius:
			return true
	return false

static func control_sites(peer_id: int) -> int:
	## AVATAR_CONTROL sites a player holds. The good faction (-1) has none:
	## neutral sites are not its corruption.
	if peer_id <= 0:
		return 0
	return GameState.count_capability(peer_id, SiteCapability.AVATAR_CONTROL)

func can_overpower(peer_id: int) -> bool:
	## Q14: "overpower his current controller with raw corruption (hard)". A
	## player needs strictly more AVATAR_CONTROL sites than his owner.
	if peer_id <= 0 or GameState.is_avatar_owner(peer_id):
		return false
	return control_sites(peer_id) > control_sites(GameState.avatar_owner_peer_id)

# --- Requests ---

@rpc("any_peer", "call_local", "reliable")
func request_overpower() -> void:
	## Sent from a Palantir. Starts the sender's overpower if they qualify.
	if not multiplayer.is_server():
		request_overpower.rpc_id(1)
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	if can_overpower(sender) and GameState.is_watching(sender) and not overpower.has(sender):
		overpower[sender] = 0.0

@rpc("any_peer", "call_local", "reliable")
func request_cancel_overpower() -> void:
	if not multiplayer.is_server():
		request_cancel_overpower.rpc_id(1)
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1
	overpower.erase(sender)

# --- Host ticks ---

func _tick_hold(dt: float) -> void:
	var owner_peer := GameState.avatar_owner_peer_id
	if owner_peer <= 0:
		hold = 1.0
		return
	if is_near_corruption(owner_peer):
		hold = 1.0
		return
	hold = maxf(0.0, hold - dt / HOLD_SECONDS)
	if hold <= 0.0:
		GameState.set_avatar_owner(GameConstants.GOOD_SIDE)

func _tick_takeover(dt: float) -> void:
	_measure_presence()
	var taker := -1
	var frozen := false
	if is_low():
		var company: float = present_strength.get(_avatar.get_allegiance(), 0.0)
		if company > 0.0:
			frozen = true  # his company stands by him: beat them first
		else:
			# PLACEHOLDER: rule for #573 (contested takeover) — the side with
			# the most strength present progresses; a tie freezes everyone.
			var best := 0.0
			for side in present_strength:
				if side <= 0 or side == GameState.avatar_owner_peer_id:
					continue
				var s: float = present_strength[side]
				if s > best:
					best = s
					taker = side
					frozen = false
				elif is_equal_approx(s, best):
					frozen = true
			if frozen:
				taker = -1
	if frozen:
		return
	for peer in takeover.keys():
		if peer != taker:
			takeover[peer] = maxf(0.0, takeover[peer] - dt / TAKEOVER_FADE_SECONDS)
			if takeover[peer] <= 0.0:
				takeover.erase(peer)
	if taker <= 0:
		return
	var strength: float = present_strength[taker]
	if strength < TAKEOVER_THRESHOLD:
		return
	var rate := dt / TAKEOVER_SECONDS * (strength / TAKEOVER_THRESHOLD)
	takeover[taker] = minf(1.0, get_takeover(taker) + rate)
	if takeover[taker] >= 1.0:
		GameState.set_avatar_owner(taker)

func _tick_overpower(dt: float) -> void:
	for peer in overpower.keys():
		# PLACEHOLDER: rule — an overpower runs only while its player keeps
		# looking through a Palantir and still out-corrupts his owner.
		if not can_overpower(peer) or not GameState.is_watching(peer):
			overpower.erase(peer)
			continue
		overpower[peer] = minf(1.0, overpower[peer] + dt / OVERPOWER_SECONDS)
		if overpower[peer] >= 1.0:
			GameState.set_avatar_owner(peer)
			return

func _measure_presence() -> void:
	present_strength.clear()
	var manager := get_tree().current_scene.get_node_or_null(^"MinionManager") as MinionManager
	if manager == null:
		return
	for minion in manager.get_all_minions():
		if minion == null or not is_instance_valid(minion) or not minion.can_take_damage():
			continue
		if minion.minion_trait in CorruptionSite.NON_COMBAT_TRAITS:
			continue
		var offset := minion.global_position - _avatar.global_position
		offset.y = 0.0
		if offset.length() > TAKEOVER_RADIUS:
			continue
		var side := minion.get_allegiance()
		present_strength[side] = present_strength.get(side, 0.0) + minion.strength

func _on_avatar_owner_changed(_old_owner: int, _new_owner: int) -> void:
	# A new owner starts with a full hold; every takeover starts over.
	hold = 1.0
	takeover.clear()
	if multiplayer.is_server():
		for peer in overpower.keys():
			if not can_overpower(peer):
				overpower.erase(peer)
	changed.emit()

@rpc("authority", "call_remote", "unreliable")
func _sync(h: float, t: Dictionary, o: Dictionary) -> void:
	hold = h
	takeover.clear()
	for peer in t:
		takeover[int(peer)] = float(t[peer])
	overpower.clear()
	for peer in o:
		overpower[int(peer)] = float(o[peer])
	changed.emit()
