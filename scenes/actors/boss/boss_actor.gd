class_name BossActor extends PlayerActor

## A boss form in the gauntlet (GDD §8 "Combat" C9, §9): one other player's
## body against the Paladin. Big and slow, with a few heavy telegraphed attacks
## the player picks, seen from a third-person camera. Built like the possessed
## Paladin: netfox predicts the driving peer's input locally and the host is the
## state authority. Not a lasting body: HolySite spawns one per boss turn on
## every peer and frees it afterwards.
##
## - **Driver** (`controlling_peer_id`): the boss's peer. A CPU seat (DebugManager
##   dummy) or a peer who left has none; BossAI drives it on the host instead.
## - **Allegiance** is the boss's peer, so it is hostile to the Paladin's owner.
## - **Attacks** (`attacks`, BossAttack data): windup (telegraphed), active (the
##   blow lands, host only), recovery. `attack_index` and `attack_time` are
##   rollback state so every peer sees the same phase.
## PLACEHOLDER: the model (Blackhorn, retro PSX pack), its clips, the camera distance
## and the walk speed are stand-ins, not designed.

## PLACEHOLDER: tuning — metres per second; a boss does not run.
const WALK_SPEED: float = 3.0
const TURN_SPEED: float = 4.0
## PLACEHOLDER: tuning — targets higher or lower than this off the boss's feet are out of a blow's reach.
## (A blow is a box in front of him, not a hitbox on his limbs: see strike_targets.)
const HIT_HEIGHT: float = 4.0
## PLACEHOLDER: tuning — a target's own width, added to a blow's reach and half-width.
const TARGET_RADIUS: float = 0.5
## PLACEHOLDER: art — the glow on the body at the end of a windup: the overlay's alpha at full charge.
const TELL_GLOW_ALPHA: float = 0.6
## An attack's clip is stretched to the attack's length, but never slower or faster than this.
const MIN_ATTACK_ANIMATION_SPEED: float = 0.5
const MAX_ATTACK_ANIMATION_SPEED: float = 2.0
const TELL_GROUND_HEIGHT: float = 0.1

## Throws, in key order (BossInput.attack_pick indexes this).
@export var attacks: Array[BossAttack] = []
## PLACEHOLDER: tuning — set by HolySite from strength before the boss spawns.
@export var max_hp_value: int = 300
@export var attack_damage: int = 20
## PLACEHOLDER: art — the camera sits this far behind and above him.
@export var camera_offset: Vector3 = Vector3(0, 3.5, 9.0)
## The body mesh whose material overlay glows during a windup.
@export var body_mesh: MeshInstance3D

## Rollback state: which attack he is throwing and how long into it.
var attack_index: int = -1
var attack_time: float = 0.0
## The peer whose boss this is (allegiance), -1 = none.
var owner_peer_id: int = -1
## The peer driving it (input and camera), -1 = nobody, BossAI drives.
var controlling_peer_id: int = -1

## Host: who the current blow has already hit (instance ids), so it lands once.
var _swing_hits: Array[int] = []
## Host: set while the rollback tick drains queued damage, see take_damage.
var _draining: bool = false

@onready var boss_input: BossInput = %BossInput
@onready var boss_camera: AvatarCamera = %BossCamera
@onready var boss_ai: BossAI = %BossAI
@onready var _tell_area: MeshInstance3D = %TellArea
@onready var _tell_label: Label3D = %TellLabel

func _ready() -> void:
	super()
	boss_input.attack_actions.clear()
	for attack in attacks:
		boss_input.attack_actions.push_back(attack.input_action)
	boss_camera.camera_3d.position = camera_offset
	_hide_tell()
	if owner_peer_id > 0 and not DebugManager.is_dummy(owner_peer_id):
		take_control(owner_peer_id)

func _process(_delta: float) -> void:
	_update_tell()

# --- Setup (before the boss is in the tree) ---

func setup(peer_id: int, max_hp: int, damage: int) -> void:
	## Whose boss this is and what he is worth; call before add_child.
	owner_peer_id = peer_id
	max_hp_value = max_hp
	attack_damage = damage

# --- Actor overrides ---

func get_max_hp() -> int:
	return max_hp_value

func get_attack_damage() -> int:
	return attack_damage

func get_allegiance() -> int:
	return owner_peer_id

func try_stagger() -> bool:
	## PLACEHOLDER: rule — a boss is never staggered by a blow (Dark Souls style).
	return false

func take_damage(amount: int) -> void:
	## Blows land on the host outside this boss's rollback tick, and netfox would
	## restore the old HP, so they queue and apply inside it (as the Paladin's do).
	if _draining or not multiplayer.is_server():
		super(amount)
	else:
		incoming_damage += amount

func _rollback_tick(delta: float, tick: int, is_fresh: bool) -> void:
	_draining = true
	super(delta, tick, is_fresh)
	_draining = false

# --- Control and camera ---

func take_control(peer_id: int) -> void:
	## `peer_id` drives the boss and sees through its camera; their overlord idles.
	controlling_peer_id = peer_id
	boss_input.set_controller(peer_id)
	boss_camera.activate(peer_id)
	rollback_synchronizer.process_settings()
	_set_overlord_active(peer_id, false)

func release_control() -> void:
	## Nobody drives him (the player left, or the turn is over): BossAI does, and
	## the former driver's view goes back to their overlord.
	var former := controlling_peer_id
	controlling_peer_id = -1
	boss_input.set_controller(-1)
	boss_camera.deactivate()
	rollback_synchronizer.process_settings()
	if former > 0:
		_set_overlord_active(former, true)

func _set_overlord_active(peer_id: int, active: bool) -> void:
	var points := get_tree().current_scene.get_node_or_null("World/PlayerSpawnPoint")
	if points == null:
		return
	var overlord := points.get_node_or_null(str(peer_id)) as OverlordActor
	if overlord:
		overlord.set_overlord_active(active)

# --- Animation ---

func _on_display_state_changed(old_state: RewindableState, new_state: RewindableState) -> void:
	super(old_state, new_state)
	if new_state is BossAttackState:
		_play_attack_animation()

func _play_attack_animation() -> void:
	## The attack's clip, stretched over the whole attack (windup, blow, recovery) so the
	## swing reads against the telegraph. PLACEHOLDER: the hit frame is not matched to the
	## active window, only the clip's length to the attack's.
	var attack := current_attack()
	if attack == null or _animation_player == null or not _animation_player.has_animation(attack.animation):
		return
	var length := _animation_player.get_animation(attack.animation).length
	var speed := clampf(length / maxf(attack.total_seconds(), 0.01), MIN_ATTACK_ANIMATION_SPEED, MAX_ATTACK_ANIMATION_SPEED)
	_animation_player.play(attack.animation, -1.0, speed)
	_animation_player.seek(attack_time * speed, true)

# --- Attacks ---

func current_attack() -> BossAttack:
	if attack_index < 0 or attack_index >= attacks.size():
		return null
	return attacks[attack_index]

func attack_phase() -> BossAttack.Phase:
	var attack := current_attack()
	if attack == null:
		return BossAttack.Phase.DONE
	return attack.phase_at(attack_time)

func begin_attack() -> void:
	attack_time = 0.0
	_swing_hits.clear()

func end_attack() -> void:
	attack_index = -1
	attack_time = 0.0
	_swing_hits.clear()

func strike_targets() -> void:
	## Host: land the current blow on every hostile actor inside its box (once
	## each). Called every tick of the active phase.
	var attack := current_attack()
	if attack == null or not multiplayer.is_server():
		return
	var damage := int(attack_damage * attack.damage_multiplier)
	var to_local := _model.global_transform.affine_inverse()
	for node in get_tree().get_nodes_in_group(&"actors"):
		var target := node as Actor
		if target == null or not is_hostile_to(target) or not target.can_take_damage():
			continue
		if target.get_instance_id() in _swing_hits:
			continue
		var local := to_local * target.global_position
		# The model faces +Z; the box starts at the boss and runs `reach` ahead.
		if local.z < -TARGET_RADIUS or local.z > attack.reach + TARGET_RADIUS:
			continue
		if absf(local.x) > attack.width * 0.5 + TARGET_RADIUS or absf(local.y) > HIT_HEIGHT:
			continue
		_swing_hits.push_back(target.get_instance_id())
		_deal(target, damage)

func _deal(target: Actor, damage: int) -> void:
	if target is AvatarActor:
		var avatar := target as AvatarActor
		avatar.last_hit_by = owner_peer_id
		avatar.incoming_damage += damage
		if avatar.controlling_peer_id > 0 and avatar.controlling_peer_id != multiplayer.get_unique_id():
			avatar.apply_incoming_damage.rpc_id(avatar.controlling_peer_id, damage, owner_peer_id)
	else:
		target.take_damage(damage)

# --- Telegraph (display only, from rollback state, so every peer sees it) ---

func _update_tell() -> void:
	var attack := current_attack()
	if attack == null or hp <= 0 or _state_machine.state != &"BossAttackState":
		_hide_tell()
		return
	var phase := attack_phase()
	if phase == BossAttack.Phase.RECOVERY or phase == BossAttack.Phase.DONE:
		_hide_tell()
		return
	_tell_label.text = attack.display_name
	_tell_label.visible = true
	_tell_area.visible = true
	var box := _tell_area.mesh as BoxMesh
	box.size = Vector3(attack.width, TELL_GROUND_HEIGHT, attack.reach)
	_tell_area.position = Vector3(0, TELL_GROUND_HEIGHT, attack.reach * 0.5)
	var charge := clampf(attack_time / maxf(attack.windup_seconds, 0.01), 0.0, 1.0)
	if phase == BossAttack.Phase.ACTIVE:
		charge = 1.0
	_set_glow(TELL_GLOW_ALPHA * charge)

func _hide_tell() -> void:
	_tell_label.visible = false
	_tell_area.visible = false
	_set_glow(0.0)

func _set_glow(alpha: float) -> void:
	if body_mesh == null:
		return
	var material := body_mesh.material_overlay as StandardMaterial3D
	if material:
		material.albedo_color.a = alpha
