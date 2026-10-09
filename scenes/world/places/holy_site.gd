class_name HolySite extends Node3D

## The holy site at the city's centre (GDD §9). Bringing the Paladin you own
## into it starts the boss gauntlet: every other player, weakest first, plays
## a boss form against him. Beat every boss and you win. A boss who beats him
## takes him (GameState.set_avatar_owner), the gauntlet ends, and he is taken
## to that player's tower. The good faction's draw locks the site for good.
##
## Host-authoritative; the state is mirrored to every peer for the HUD.
## Boss forms are placeholders (data/minions/boss_form.tres) and, for now,
## are always AI-driven; player control of a boss is not built yet.

signal gauntlet_started(challenger: int)
signal boss_changed(peer_id: int, index: int, total: int)
## outcome: &"won", &"lost" (a boss took the Paladin), &"aborted" or &"drawn".
signal gauntlet_ended(outcome: StringName, peer_id: int)

enum State { IDLE, GAUNTLET, ENDED }

const GROUP: StringName = &"holy_site"
const BOSS_TYPE: StringName = &"boss_form"
## PLACEHOLDER: tuning, not designed — how much a held site counts toward a
## player's strength for ordering the gauntlet, and for a boss-type site.
const SITE_WEIGHT: float = 1.0
const BOSS_SITE_WEIGHT: float = 2.0
## PLACEHOLDER: tuning — a boss's health and damage grow by this share of the
## base per point of strength.
const BOSS_HP_PER_STRENGTH: float = 0.25
const BOSS_DAMAGE_PER_STRENGTH: float = 0.1
## PLACEHOLDER: tuning — a boss with nothing held still has this health/damage.
const BOSS_BASE_HP: int = 300
const BOSS_BASE_DAMAGE: int = 20
## Seconds the Paladin is held at the tower he is taken to, so netfox accepts it.
const PIN_SECONDS: float = 0.5
## How far from the centre the Paladin counts as inside.
@export var radius: float = 10.0
## PLACEHOLDER: tuning — where a boss appears, as a distance from the centre.
@export var boss_spawn_distance: float = 8.0

## Mirrored state, readable on every peer.
static var state: State = State.IDLE
static var boss_peer: int = -1
static var boss_index: int = 0
static var boss_total: int = 0

var locked: bool = false

var _challenger: int = -1
var _order: Array[int] = []
var _boss_unit: MinionActor
var _avatar: AvatarActor
var _mm: MinionManager

func _ready() -> void:
	add_to_group(GROUP)
	state = State.IDLE
	boss_peer = -1
	_build_look()

# --- Strength ---

static func strength_of(peer_id: int) -> float:
	## What a player's held corruption sites are worth in the gauntlet: boss
	## sites most. Towers don't count (everyone has one).
	var total := 0.0
	for node in GameState.get_held_sites(peer_id):
		var site := node as CorruptionSite
		if site == null or site.permanent:
			continue
		total += BOSS_SITE_WEIGHT if site.grants(SiteCapability.BOSS_POWER) else SITE_WEIGHT
	return total

static func order_for(challenger: int) -> Array[int]:
	## Everyone but the challenger, weakest first (ties by seat).
	var peers: Array[int] = []
	for p in GameState.get_player_peers():
		if p != challenger:
			peers.append(p)
	peers.sort_custom(func(a: int, b: int) -> bool:
		var sa := strength_of(a)
		var sb := strength_of(b)
		return a < b if is_equal_approx(sa, sb) else sa < sb)
	return peers

static func lock_all(tree: SceneTree) -> void:
	## The good faction has drawn the match: the city centre can't be corrupted.
	for node in tree.get_nodes_in_group(GROUP):
		(node as HolySite).lock()

func lock() -> void:
	locked = true
	if state == State.GAUNTLET:
		_end(&"drawn", -1)

func is_inside(pos: Vector3) -> bool:
	return Vector2(pos.x - global_position.x, pos.z - global_position.z).length() <= radius

# --- Host loop ---

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	match state:
		State.IDLE:
			_watch_for_challenger()
		State.GAUNTLET:
			if GameState.avatar_owner_peer_id != _challenger:
				_end(&"aborted", -1)

func _watch_for_challenger() -> void:
	if locked or not GameState.has_avatar_owner():
		return
	var avatar := _find_avatar()
	if avatar == null or avatar.hp <= 0 or not is_inside(avatar.global_position):
		return
	start_gauntlet(GameState.avatar_owner_peer_id)

func start_gauntlet(challenger: int) -> void:
	if not multiplayer.is_server() or state != State.IDLE or locked:
		return
	_challenger = challenger
	_order = order_for(challenger)
	_avatar = _find_avatar()
	_mm = _find_mm()
	if _avatar == null or _mm == null:
		return
	if not _avatar.died.is_connected(_on_paladin_died):
		_avatar.died.connect(_on_paladin_died)
	if not _mm.minion_died.is_connected(_on_minion_died):
		_mm.minion_died.connect(_on_minion_died)
	boss_total = _order.size()
	_set_state(State.GAUNTLET, -1, 0)
	gauntlet_started.emit(challenger)
	_next_boss()

# --- The gauntlet ---

func _next_boss() -> void:
	if _order.is_empty():
		_win()
		return
	var peer: int = _order.pop_front()
	var index := boss_total - _order.size()
	var angle := TAU * float(index) / float(maxi(boss_total, 1))
	var pos := global_position + Vector3(cos(angle), 0.0, sin(angle)) * boss_spawn_distance + Vector3.UP
	var id := _mm.spawn_named_minion_for_peer(peer, BOSS_TYPE, pos)
	_boss_unit = _mm.get_minion_by_id(id)
	if _boss_unit:
		_scale_boss(_boss_unit, strength_of(peer))
	_set_state(State.GAUNTLET, peer, index)
	boss_changed.emit(peer, index, boss_total)

func _scale_boss(unit: MinionActor, strength: float) -> void:
	## Boss stats scale with the sites its player holds.
	unit.max_hp_value = int(BOSS_BASE_HP * (1.0 + BOSS_HP_PER_STRENGTH * strength))
	unit.hp = unit.max_hp_value
	unit.attack_damage = int(BOSS_BASE_DAMAGE * (1.0 + BOSS_DAMAGE_PER_STRENGTH * strength))

func _on_minion_died(minion: MinionActor) -> void:
	if state != State.GAUNTLET or minion != _boss_unit:
		return
	_boss_unit = null
	# Next frame, so the dead boss is out of the way of the next spawn.
	_after_boss_fell.call_deferred()

func _after_boss_fell() -> void:
	if state == State.GAUNTLET:
		_next_boss()

func _on_paladin_died() -> void:
	## Host: a boss beat the Paladin. He is the boss's now. (Deferred, so it
	## lands after the Paladin's own death wipes his owner.)
	if state != State.GAUNTLET or boss_peer < 0:
		return
	var winner := boss_peer
	_end(&"lost", winner)
	_hand_over.call_deferred(winner)

func _hand_over(winner: int) -> void:
	GameState.set_avatar_owner(winner)
	if _avatar == null or _mm == null:
		return
	var gate := _mm.get_courier_spawn_for(winner)
	if gate:
		# PLACEHOLDER: #576 — how he is taken to the winner's tower; a plain teleport.
		# Pinned for a moment so the rollback tick keeps the new position.
		_avatar.pin_transform(Transform3D(Basis.IDENTITY, gate.global_position + Vector3.UP))
		get_tree().create_timer(PIN_SECONDS).timeout.connect(_avatar.unpin_transform)

func _win() -> void:
	var winner := _challenger
	_end(&"won", winner)
	state = State.ENDED
	_sync_state.rpc(state, -1, 0, 0)
	GameState.announce_win(winner)

func _end(outcome: StringName, peer_id: int) -> void:
	if _avatar and _avatar.died.is_connected(_on_paladin_died):
		_avatar.died.disconnect(_on_paladin_died)
	if _mm and _mm.minion_died.is_connected(_on_minion_died):
		_mm.minion_died.disconnect(_on_minion_died)
	var unit := _boss_unit
	_boss_unit = null
	_order.clear()
	if unit and is_instance_valid(unit) and unit.hp > 0 and _mm:
		_mm.despawn_minion(unit)
	_set_state(State.IDLE, -1, 0)
	gauntlet_ended.emit(outcome, peer_id)

func _set_state(new_state: State, peer_id: int, index: int) -> void:
	_sync_state.rpc(new_state, peer_id, index, boss_total)

@rpc("authority", "call_local", "reliable")
func _sync_state(new_state: int, peer_id: int, index: int, total: int) -> void:
	state = new_state as State
	boss_peer = peer_id
	boss_index = index
	boss_total = total

# --- Lookups ---

func _find_avatar() -> AvatarActor:
	return get_tree().current_scene.get_node_or_null("World/Avatar") as AvatarActor

func _find_mm() -> MinionManager:
	return get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager

func _build_look() -> void:
	## PLACEHOLDER: art — a pale disc on the ground marks the holy site.
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.1
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.75, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	disc.position = Vector3(0, 0.1, 0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
