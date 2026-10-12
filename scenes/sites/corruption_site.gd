class_name CorruptionSite extends Node3D

## A corruption site (GDD §7). Host-authoritative.
##
## Taking it (Q11): gather your forces inside `radius` until their strength
## meets the type's threshold, then wait; more strength goes faster. The
## Paladin counts for far more than a troop, so he corrupts much faster.
## Losing it (Q12): a rival meeting the threshold corrupts it back to neutral
## and then to themselves; the good faction purifies it when it stands there
## unopposed; and a held site slips back to neutral when none of the holder's
## forces stay to hold it.
## Holding one grants its type's capability (SiteCapability), queried through
## GameState.has_capability().
##
## Your tower is a permanent site (Q39): `permanent` sites never change hands.
## Hostile forces there with no defenders sack it; see Tower.
##
## Points of interest (Austin, 2026-10-12; SiteType.poi_kind):
## - **Temples** raise their holder's control of the Paladin (AVATAR_CONTROL)
##   and give their own `grant`. Troops take one slowly; the Paladin clearing its
##   dungeon (`paladin_cleared`) corrupts it at once. The Goddess's forces inside
##   (`forces_present`) come back whenever it is purified or returns to neutral.
## - **Runestones**: the Paladin's arena duel with a sealed Dark Lord. The first
##   to win it (`win_runestone`) takes its `grant` (a power); then it is spent
##   for the round.
## - Each site's `grant` is configurable per site, PLACEHOLDER by default.

signal holder_changed(old_holder: int, new_holder: int)
signal sacked_changed(sacked: bool)
## A runestone's power was won (host and clients).
signal runestone_won(peer_id: int, power: StringName)

const GROUP: StringName = &"corruption_sites"
## How often the host re-evaluates who is present.
const TICK_INTERVAL: float = 0.5
## PLACEHOLDER: tuning, not designed — how much the Paladin counts toward a
## site's strength threshold (GDD §7: "corrupts sites much faster than troops").
const AVATAR_STRENGTH: float = 12.0
## Seconds the beacon of light stands over a site after it changes hands.
## PLACEHOLDER: tuning.
const BEACON_SECONDS: float = 20.0
## Unit traits that never count toward a site's strength.
const NON_COMBAT_TRAITS: Array[StringName] = [&"courier", &"info_courier", &"advisor", &"hauler"]

@export var site_type: SiteType
## Units within this horizontal distance count as present.
@export var radius: float = 10.0
## Towers: never changes hands. The holder is set by the owning Tower.
@export var permanent: bool = false
## Temples: the upgrade its crystal gives its holder. Runestones: the power won
## from its sealed Dark Lord. Set per site. PLACEHOLDER: default, not designed
## (Austin's to set).
@export var grant: StringName = &"placeholder_grant"

## Peer holding the site; -1 = neutral.
var holder_peer_id: int = -1
## Corruption progress toward `progress_peer_id`, 0..1. A held site sits at 1.
var progress: float = 0.0
var progress_peer_id: int = -1
## True once any player has held it (first-take beacon vs. change-hands beacon).
var ever_taken: bool = false
## Permanent sites only: hostiles present and no defenders.
var sacked: bool = false
## Set by the good faction's growth (GDD §9 "Draw"): this site can no longer
## be corrupted and is released if held.
var unusable: bool = false
## Allegiance -> strength present at the last tick (host and clients).
var present_strength: Dictionary[int, float] = {}
## Temples: the Goddess's forces hold the dungeon. Cleared by the Paladin; back
## whenever the temple is purified or returns to neutral.
var forces_present: bool = true
## Runestones: who won its power this round (-1 = nobody yet; then it is spent).
var runestone_winner: int = -1

var _tick_timer: float = 0.0
var _beacon_timer: float = 0.0

@onready var _pillar: MeshInstance3D = %Pillar
@onready var _beacon: MeshInstance3D = %Beacon
@onready var _marker_material: StandardMaterial3D = _pillar.material_override as StandardMaterial3D

func _ready() -> void:
	add_to_group(GROUP)
	_refresh_marker()

func grants(capability: StringName) -> bool:
	if unusable or site_type == null:
		return false
	return site_type.capability == capability

func get_display_name() -> String:
	if site_type == null:
		return name
	return site_type.display_name

func get_threshold() -> float:
	var base: float = site_type.strength_threshold if site_type else 3.0
	return base * GoodFaction.threshold_scale()

func is_held() -> bool:
	return holder_peer_id != -1

func is_kind(kind: SiteType.PoiKind) -> bool:
	return site_type != null and site_type.poi_kind == kind

func get_encounter() -> SiteType.Encounter:
	return site_type.encounter if site_type else SiteType.Encounter.NONE

func is_spent() -> bool:
	## Runestones: its power has been won this round.
	return is_kind(SiteType.PoiKind.RUNESTONE) and runestone_winner != -1

func paladin_cleared(peer_id: int) -> bool:
	## Host: the Paladin, driven by `peer_id`, cleared this temple's dungeon.
	## A shortcut: troops take a temple slowly, the Paladin corrupts it at once.
	## PLACEHOLDER: rule — "at once" (Austin: "at once or much faster").
	if not multiplayer.is_server() or not is_kind(SiteType.PoiKind.TEMPLE) or unusable:
		return false
	if peer_id <= 0 or not forces_present:
		return false
	_change_holder(peer_id)
	return true

func win_runestone(peer_id: int) -> bool:
	## Host: `peer_id`'s Paladin beat this runestone's sealed Dark Lord. The first
	## winner takes the power; after that the runestone is spent for the round.
	if not multiplayer.is_server() or not is_kind(SiteType.PoiKind.RUNESTONE):
		return false
	if peer_id <= 0 or is_spent():
		return false
	_set_runestone_winner.rpc(peer_id)
	return true

static func powers_won(tree: SceneTree, peer_id: int) -> Array[StringName]:
	## Every runestone power `peer_id` has won this round (for their boss form).
	var out: Array[StringName] = []
	for node in tree.get_nodes_in_group(GROUP):
		var site := node as CorruptionSite
		if site and site.is_kind(SiteType.PoiKind.RUNESTONE) and site.runestone_winner == peer_id:
			out.append(site.grant)
	return out

func set_permanent_holder(peer_id: int) -> void:
	## Called by Tower when its seat is bound (every peer).
	permanent = true
	holder_peer_id = peer_id
	progress_peer_id = peer_id
	progress = 1.0
	ever_taken = true
	_refresh_marker()

func make_unusable() -> void:
	## Host-only. The good faction's growth locks this site for good.
	if not multiplayer.is_server() or permanent:
		return
	_set_unusable.rpc()

func debug_give_to(peer_id: int) -> void:
	## Host-only debug shortcut (pause menu "Take Nearest Site").
	if multiplayer.is_server() and not permanent:
		_change_holder(peer_id)

func _physics_process(delta: float) -> void:
	if _beacon_timer > 0.0:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0 and _beacon:
			_beacon.visible = false
	if not multiplayer.is_server():
		return
	_tick_timer += delta
	if _tick_timer < TICK_INTERVAL:
		return
	var dt := _tick_timer
	_tick_timer = 0.0
	_measure_presence()
	if permanent:
		_tick_permanent()
	else:
		_tick_contest(dt)
	_sync_progress.rpc(progress, progress_peer_id, present_strength)

func _measure_presence() -> void:
	present_strength.clear()
	for node in get_tree().get_nodes_in_group(&"actors"):
		var actor := node as Actor
		if actor == null or not actor.can_take_damage():
			continue
		var strength := _strength_of(actor)
		if strength <= 0.0:
			continue
		var offset := actor.global_position - global_position
		offset.y = 0.0
		if offset.length() > radius:
			continue
		var side := actor.get_allegiance()
		present_strength[side] = present_strength.get(side, 0.0) + strength

func _strength_of(actor: Actor) -> float:
	if actor is MinionActor:
		var m := actor as MinionActor
		if m.minion_trait in NON_COMBAT_TRAITS:
			return 0.0
		return m.strength
	if actor is AvatarActor:
		var a := actor as AvatarActor
		if a.is_dormant:
			return 0.0
		return AVATAR_STRENGTH
	return 0.0

func _tick_contest(dt: float) -> void:
	if unusable:
		return
	var sides: Array[int] = []
	for side in present_strength:
		sides.append(side)
	if sides.size() > 1:
		return  # Contested: they fight it out; nothing moves until one side is left.
	if sides.is_empty():
		_tick_unattended(dt)
		return
	var side: int = sides[0]
	var strength: float = present_strength[side]
	if side == GameConstants.GOOD_SIDE:
		# Purification: the good faction unwinds whatever corruption is here.
		var purify: float = site_type.purify_seconds if site_type else 45.0
		_reduce_progress(dt / purify)
		return
	if holder_peer_id == side:
		return  # Holding, guarded.
	var threshold := get_threshold()
	if strength < threshold:
		return  # Not enough force to start corrupting.
	var rate := dt / (site_type.corrupt_seconds if site_type else 60.0) * (strength / threshold)
	if progress_peer_id != side and progress > 0.0:
		# A rival's corruption has to be undone first (rivals corrupt it over).
		_reduce_progress(rate)
		return
	progress_peer_id = side
	progress = minf(1.0, progress + rate)
	if progress >= 1.0:
		_change_holder(side)

func _tick_unattended(dt: float) -> void:
	if progress <= 0.0:
		return
	# Nobody here: a held site slips back unless some of the holder's forces
	# stay (Q12); half-done corruption fades the same way.
	var slip: float = site_type.slip_seconds if site_type else 180.0
	_reduce_progress(dt / slip)

func _reduce_progress(amount: float) -> void:
	progress = maxf(0.0, progress - amount)
	if progress <= 0.0:
		progress_peer_id = -1
		if holder_peer_id != -1:
			_change_holder(-1)

func _tick_permanent() -> void:
	var defended: bool = present_strength.get(holder_peer_id, 0.0) > 0.0
	var hostile := false
	for side in present_strength:
		if side != holder_peer_id:
			hostile = true
	var now_sacked := hostile and not defended
	if now_sacked != sacked:
		_set_sacked.rpc(now_sacked)

func _change_holder(new_holder: int) -> void:
	var first := not ever_taken and new_holder != -1
	_set_holder.rpc(new_holder, first)

@rpc("authority", "call_local", "reliable")
func _set_holder(new_holder: int, first_taken: bool) -> void:
	var old := holder_peer_id
	holder_peer_id = new_holder
	if new_holder != -1:
		ever_taken = true
		progress_peer_id = new_holder
		progress = 1.0
	if is_kind(SiteType.PoiKind.TEMPLE):
		# Taken, the Goddess's forces are gone; purified or back to neutral, they return.
		forces_present = new_holder == -1
	_refresh_marker()
	_light_beacon()
	holder_changed.emit(old, new_holder)
	GameState.site_changed.emit(self, old, new_holder, first_taken)

@rpc("authority", "call_local", "reliable")
func _set_runestone_winner(peer_id: int) -> void:
	runestone_winner = peer_id
	runestone_won.emit(peer_id, grant)

@rpc("authority", "call_local", "reliable")
func _set_sacked(value: bool) -> void:
	sacked = value
	sacked_changed.emit(value)

@rpc("authority", "call_local", "reliable")
func _set_unusable() -> void:
	unusable = true
	if multiplayer.is_server() and holder_peer_id != -1:
		_change_holder(-1)
	progress = 0.0
	progress_peer_id = -1
	_refresh_marker()

@rpc("authority", "call_remote", "unreliable")
func _sync_progress(p: float, p_peer: int, strengths: Dictionary) -> void:
	progress = p
	progress_peer_id = p_peer
	present_strength.clear()
	for side in strengths:
		present_strength[int(side)] = float(strengths[side])

# --- Presentation (PLACEHOLDER art, authored in corruption_site.tscn: a stone disc and a pillar tinted by holder) ---

func _refresh_marker() -> void:
	if _marker_material == null:
		return
	var color: Color
	if unusable:
		color = Color(0.25, 0.25, 0.25)
	elif holder_peer_id == -1:
		color = site_type.neutral_color if site_type else Color(0.75, 0.75, 0.7)
	else:
		color = GameState.get_player_color(holder_peer_id)
	_marker_material.albedo_color = color
	_marker_material.emission = color

func _light_beacon() -> void:
	## GDD §7: a beacon in the sky, seen from the balcony, marks a site taken
	## for the first time, changing hands, or returning to neutral.
	if _beacon == null or permanent:
		return
	var color := Color(1, 1, 1, 0.35)
	if holder_peer_id != -1:
		color = GameState.get_player_color(holder_peer_id)
		color.a = 0.45
	(_beacon.material_override as StandardMaterial3D).albedo_color = color
	_beacon.visible = true
	_beacon_timer = BEACON_SECONDS
