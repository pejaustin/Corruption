class_name HolySite extends Node3D

## The holy site at the city's centre (GDD §9). Bringing the Paladin you own
## into it starts the boss gauntlet: every other player, weakest first, plays
## a boss form against him. Beat every boss and you win. A boss who beats him
## takes him (GameState.set_avatar_owner), the gauntlet ends, and he is taken
## to that player's tower. The good faction's draw locks the site for good.
##
## Host-authoritative; the state is mirrored to every peer for the HUD.
## A boss form is a BossActor (boss_scene): the boss's own player plays it
## through a third-person camera (Dark Souls style), or BossAI does for a CPU
## seat or a peer who left. One is spawned on every peer per boss turn.

signal gauntlet_started(challenger: int)
signal boss_changed(peer_id: int, index: int, total: int)
## outcome: &"won", &"lost" (a boss took the Paladin), &"aborted" or &"drawn".
signal gauntlet_ended(outcome: StringName, peer_id: int)

enum State { IDLE, GAUNTLET, ENDED }

const GROUP: StringName = &"holy_site"
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
## The player-driven boss form, instanced once per boss turn on every peer.
@export var boss_scene: PackedScene

## Mirrored state, readable on every peer.
static var state: State = State.IDLE
static var boss_peer: int = -1
static var boss_index: int = 0
static var boss_total: int = 0

var locked: bool = false

var _challenger: int = -1
var _order: Array[int] = []
var _boss: BossActor
var _avatar: AvatarActor
var _mm: MinionManager

@onready var _disc: MeshInstance3D = %Disc

func _ready() -> void:
	add_to_group(GROUP)
	state = State.IDLE
	boss_peer = -1
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_fit_look()

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

static func city_centre(tree: SceneTree) -> Vector3:
	## The holy site at the city centre, or the world origin if the map has none.
	var site := tree.get_first_node_in_group(GROUP) as Node3D
	return site.global_position if site else Vector3.ZERO

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
	_set_state(State.GAUNTLET, peer, index)
	_spawn_boss.rpc(peer, pos, strength_of(peer))
	_boss = get_node_or_null(_boss_name(peer)) as BossActor
	if _boss:
		_boss.died.connect(_on_boss_died)
	boss_changed.emit(peer, index, boss_total)

static func _boss_name(peer: int) -> String:
	return "Boss%d" % peer

@rpc("authority", "call_local", "reliable")
func _spawn_boss(peer: int, pos: Vector3, strength: float) -> void:
	## On every peer: the same node name and path, so netfox pairs the boss up.
	var boss := boss_scene.instantiate() as BossActor
	boss.name = _boss_name(peer)
	_scale_boss(boss, peer, strength)
	add_child(boss)
	boss.global_position = pos

@rpc("authority", "call_local", "reliable")
func _free_boss(peer: int) -> void:
	var boss := get_node_or_null(_boss_name(peer)) as BossActor
	if boss == null:
		return
	boss.release_control()  # the player's view goes back to their overlord
	boss.queue_free()

@rpc("authority", "call_local", "reliable")
func _release_boss(peer: int) -> void:
	## The boss's player left: the host's BossAI plays it from here.
	var boss := get_node_or_null(_boss_name(peer)) as BossActor
	if boss:
		boss.release_control()

func _scale_boss(boss: BossActor, peer: int, strength: float) -> void:
	## Boss stats scale with the sites its player holds (before it is in the tree).
	boss.setup(peer,
		int(BOSS_BASE_HP * (1.0 + BOSS_HP_PER_STRENGTH * strength)),
		int(BOSS_BASE_DAMAGE * (1.0 + BOSS_DAMAGE_PER_STRENGTH * strength)))

func _on_boss_died() -> void:
	## Host: the boss fell. Gone at once, the next one deferred so it is out of the way.
	if state != State.GAUNTLET or _boss == null:
		return
	_free_boss.rpc(boss_peer)
	_boss = null
	_after_boss_fell.call_deferred()

func _on_peer_disconnected(peer: int) -> void:
	if state == State.GAUNTLET and peer == boss_peer:
		_release_boss.rpc(peer)

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
		# He appears at the winner's tower straight away (Austin, 2026-10-12, #576).
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
	if _boss and is_instance_valid(_boss):
		_free_boss.rpc(boss_peer)
	_boss = null
	_order.clear()
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

func _fit_look() -> void:
	## The pale disc is authored in holy_site.tscn (PLACEHOLDER art); it only
	## follows the site's radius.
	var mesh := _disc.mesh as CylinderMesh
	mesh.top_radius = radius
	mesh.bottom_radius = radius
