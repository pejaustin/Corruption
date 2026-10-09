class_name AvatarActor extends PlayerActor

## The Paladin (GDD §8). One shared body in the world, always awake.
##
## - **Owner** (`GameState.avatar_owner_peer_id`): the player who holds him, or
##   the good faction (-1). Taking and keeping him: PaladinHold.
## - **Controller** (`GameState.avatar_peer_id`): the owner when they drive him
##   directly from a Palantir; otherwise AvatarAI drives him for whoever owns him.
## - **Control tiers** (Q18): an owner's control level is 1 + the AVATAR_CONTROL
##   sites they hold; each action needs a level (`can_use`), and below
##   RESIST_GOOD_BELOW_LEVEL he refuses to strike the good faction.
## - **Zero HP** (Q15): his corruption is wiped (the good faction has him again)
##   and after RECOVER_DELAY he gets up where he fell, weak; AvatarAI then takes
##   him home to recover.

signal resisted(target: Actor)

const ACTION_WALK: StringName = &"walk"
const ACTION_RUN: StringName = &"run"
const ACTION_JUMP: StringName = &"jump"
const ACTION_ROLL: StringName = &"roll"
const ACTION_ATTACK: StringName = &"attack"
const ACTION_ABILITIES: StringName = &"abilities"
## PLACEHOLDER: rule for #582 (control tiers) — the control level each action
## needs. Level = 1 + AVATAR_CONTROL sites the owner holds.
const CONTROL_UNLOCKS: Dictionary[StringName, int] = {
	ACTION_WALK: 1,
	ACTION_ATTACK: 2,
	ACTION_RUN: 3,
	ACTION_ROLL: 3,
	ACTION_JUMP: 3,
	ACTION_ABILITIES: 4,
}
## PLACEHOLDER: tuning — the highest control level (everything unlocked).
const CONTROL_LEVEL_MAX: int = 4
## PLACEHOLDER: tuning — below this control level he resists striking the good
## faction's priests and soldiers (Q18).
const RESIST_GOOD_BELOW_LEVEL: int = 3
## PLACEHOLDER: wording — the flash shown when he resists a strike.
## PLACEHOLDER: tuning — seconds the resist flash stays up.
const RESIST_FLASH_SECONDS: float = 1.2
## PLACEHOLDER: tuning — seconds he lies at zero HP before getting up.
const RECOVER_DELAY: float = 5.0
## PLACEHOLDER: tuning — fraction of max HP he gets up with after zero HP.
const RECOVER_HP_FRACTION: float = 0.25
## The Paladin's own ability set: the first playable faction's avatar
## abilities, whoever owns him. PLACEHOLDER: which abilities he has (#582).
const ABILITY_PROFILE_FACTION: int = GameConstants.Faction.UNDEATH
## PLACEHOLDER: art direction — viewers are translucent spheres in their seat colour.
const WATCHER_ORB_ALPHA: float = 0.45

## Instanced once per remote viewer (tinted in their seat colour).
@export var watcher_orb_scene: PackedScene

var controlling_peer_id: int = -1
## Legacy flag kept for old test harnesses (activate/deactivate). In play the
## Paladin is never dormant: unowned, he serves the good faction.
var is_dormant: bool = false
var god_mode: bool = false

var _watcher_orbs: Dictionary[int, MeshInstance3D] = {}
## Host: HP to set inside the next rollback tick (recovery, owner change).
## Written there, not from outside the tick loop, or netfox restores the old value.
var _pending_hp: int = -1
## Host: healing to apply inside the next rollback tick (AvatarAI regeneration).
var _pending_heal: int = 0
var _recover_scheduled: bool = false
var _resist_timer: float = 0.0

@onready var avatar_input: AvatarInput = $AvatarInput
@onready var avatar_camera: AvatarCamera = $AvatarCamera
@onready var watcher_label: Label3D = $WatcherLabel
@onready var avatar_ai: AvatarAI = $AvatarAI
## Faction abilities.
@onready var abilities: AvatarAbilities = %AvatarAbilities
## Takeover, overpower and hold (host-authoritative).
@onready var hold: PaladinHold = %PaladinHold
## Live voice among Palantir viewers and his controller.
@onready var voice: PaladinVoice = %PaladinVoice
@onready var _resist_label: Label3D = %ResistLabel

func _ready() -> void:
	super()
	GameState.watcher_count_changed.connect(_on_watcher_count_changed)
	GameState.avatar_owner_changed.connect(_on_avatar_owner_changed)
	_update_watcher_label(0)
	abilities.setup(self, ABILITY_PROFILE_FACTION)

func _process(delta: float) -> void:
	_update_watcher_orbs()
	if _resist_timer > 0.0:
		_resist_timer -= delta
		if _resist_timer <= 0.0:
			_resist_label.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if controlling_peer_id != multiplayer.get_unique_id():
		return
	if not avatar_input.input_enabled:
		return
	if event.is_action_pressed("cancel"):
		GameState.request_recall_avatar()
	if abilities and can_use(ACTION_ABILITIES):
		if event.is_action_pressed("secondary_ability"):
			abilities.activate_ability(0)
		elif event.is_action_pressed("item_1"):
			abilities.activate_ability(1)
		elif event.is_action_pressed("item_2"):
			abilities.activate_ability(2)

## The Paladin fights for whoever holds him; unheld, for the good faction.
func get_allegiance() -> int:
	return GameState.avatar_owner_peer_id if GameState.has_avatar_owner() else GameConstants.GOOD_SIDE

# --- Control tiers and resistance (GDD §8 "Imperfect ARPG", Q18) ---

func get_control_level() -> int:
	## Unowned he is the good faction's own and holds nothing back.
	if not GameState.has_avatar_owner():
		return CONTROL_LEVEL_MAX
	var level := 1 + PaladinHold.control_sites(GameState.avatar_owner_peer_id)
	return clampi(level, 1, CONTROL_LEVEL_MAX)

func can_use(action: StringName) -> bool:
	return get_control_level() >= CONTROL_UNLOCKS.get(action, 1)

func resists_striking(target: Actor) -> bool:
	## True when his owner's hold is too weak to make him strike the good faction.
	if target == null or not GameState.has_avatar_owner():
		return false
	return target.get_allegiance() == GameConstants.GOOD_SIDE and get_control_level() < RESIST_GOOD_BELOW_LEVEL

func strike(target: Actor, damage: int) -> bool:
	## Host: one landed blow from his attack. Returns false when he resists.
	if resists_striking(target):
		show_resistance(target)
		return false
	if target is MinionActor:
		(target as MinionActor).last_hit_by = get_allegiance()
	target.take_damage(damage)
	return true

func show_resistance(target: Actor = null) -> void:
	## Host: flash the resist feedback on every peer (throttled per swing).
	resisted.emit(target)
	if multiplayer.is_server() and _resist_timer <= 0.0:
		_flash_resistance.rpc()

# --- Healing (host) ---

func heal(amount: int) -> void:
	## Host-only. Applied inside the next rollback tick (see _pending_heal).
	if multiplayer.is_server() and amount > 0:
		_pending_heal += amount

# --- Combat overrides ---

func can_take_damage() -> bool:
	if god_mode or is_dormant:
		return false
	return hp > 0

## Called by host (enemy/minion attacks) to apply damage through the rollback
## owner, since incoming_damage is drained inside the rollback tick.
@rpc("any_peer", "call_local", "reliable")
func apply_incoming_damage(amount: int, _source_peer: int) -> void:
	incoming_damage += amount

func _die() -> void:
	super()
	if not multiplayer.is_server():
		return
	# GDD §8 (Q15): at zero HP his corruption is wiped and the controller loses him.
	GameState.set_avatar_owner(GameConstants.GOOD_SIDE)
	if not _recover_scheduled:
		_recover_scheduled = true
		get_tree().create_timer(RECOVER_DELAY).timeout.connect(_recover_in_place)

func _recover_in_place() -> void:
	## He gets up where he fell, weak; AvatarAI takes him home to recover.
	_recover_scheduled = false
	if hp <= 0:
		_pending_hp = maxi(1, int(get_max_hp() * RECOVER_HP_FRACTION))

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	super(delta, tick, is_fresh)
	if not multiplayer.is_server():
		return
	if _pending_hp >= 0:
		var was_down := hp <= 0
		hp = mini(_pending_hp, get_max_hp())
		_pending_hp = -1
		hp_changed.emit(hp)
		if was_down and hp > 0:
			_state_machine.transition(&"IdleState")
	if _pending_heal > 0 and hp > 0:
		hp = mini(hp + _pending_heal, get_max_hp())
		hp_changed.emit(hp)
	_pending_heal = 0

# --- Activation (legacy harnesses) ---

func activate(peer_id: int) -> void:
	controlling_peer_id = peer_id
	is_dormant = false
	hp = get_max_hp()
	hp_changed.emit(hp)
	avatar_input.set_controller(peer_id)
	avatar_camera.activate(peer_id)
	rollback_synchronizer.process_settings()
	faction = GameState.get_faction(peer_id)

func deactivate() -> void:
	controlling_peer_id = -1
	is_dormant = true
	faction = GameConstants.Faction.NEUTRAL
	avatar_input.set_controller(-1)
	avatar_camera.deactivate()
	rollback_synchronizer.process_settings()
	velocity = Vector3.ZERO
	_state_machine.transition(&"IdleState")

# --- Possession (ownership/control split) ---

func possess(peer_id: int) -> void:
	## Take direct control: drives input/camera only. HP and faction are
	## OWNERSHIP-scoped (_on_avatar_owner_changed) — re-possessing your own
	## Paladin doesn't heal him.
	controlling_peer_id = peer_id
	is_dormant = false
	avatar_input.set_controller(peer_id)
	avatar_camera.activate(peer_id)
	rollback_synchronizer.process_settings()
	if avatar_ai:
		avatar_ai.clear_orders()  # the owner took the wheel — pending AI orders are void

func release_control() -> void:
	## Nobody drives him: AvatarAI does, for his owner or the good faction.
	controlling_peer_id = -1
	is_dormant = false
	avatar_input.set_controller(-1)
	avatar_camera.deactivate()
	rollback_synchronizer.process_settings()
	velocity = Vector3.ZERO
	if hp > 0:
		_state_machine.transition(&"IdleState")

func _on_avatar_owner_changed(_old_owner: int, new_owner: int) -> void:
	if avatar_ai:
		avatar_ai.clear_orders()  # a new master's pawn doesn't keep old orders
	if new_owner > 0:
		faction = GameState.get_faction(new_owner)
		# PLACEHOLDER: rule — a player who takes him gets him at full HP.
		if multiplayer.is_server() and hp > 0:
			_pending_hp = get_max_hp()
	else:
		faction = GameConstants.Faction.NEUTRAL

# --- Watchers (GDD §8 "Seen by all") ---

func _on_watcher_count_changed(count: int) -> void:
	_update_watcher_label(count)

func _update_watcher_label(count: int) -> void:
	if not watcher_label:
		return
	if count > 0:
		watcher_label.visible = true
		watcher_label.text = "(%d watching)" % count # PLACEHOLDER: wording
	else:
		watcher_label.visible = false

func _update_watcher_orbs() -> void:
	## Each viewer is a ghostly orb at their scry camera, orbiting him as they
	## look around. Only remote viewers have positions here (your own camera is
	## inside your own orb).
	var positions := GameState.watcher_positions
	for peer_id in _watcher_orbs.keys():
		if peer_id not in positions:
			_watcher_orbs[peer_id].queue_free()
			_watcher_orbs.erase(peer_id)
	for peer_id in positions:
		if peer_id not in _watcher_orbs:
			_watcher_orbs[peer_id] = _create_watcher_orb(peer_id)
		_watcher_orbs[peer_id].global_position = positions[peer_id]

func _create_watcher_orb(peer_id: int) -> MeshInstance3D:
	## One orb per viewer: an instance of the authored watcher_orb.tscn, tinted.
	var orb := watcher_orb_scene.instantiate() as MeshInstance3D
	orb.name = "WatcherOrb%d" % peer_id
	var color := GameState.get_player_color(peer_id)
	var mat := orb.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, WATCHER_ORB_ALPHA)
	mat.emission = color
	add_child(orb)
	return orb

# --- Resist feedback ---

@rpc("authority", "call_local", "reliable")
func _flash_resistance() -> void:
	_resist_label.visible = true
	_resist_timer = RESIST_FLASH_SECONDS
