extends PlayerState

## Tier D — riposte (execution) attacker side. Entered from
## `try_riposte()` when the player presses heavy_attack near a target whose
## `is_ripostable` flag is set (Tier C's PostureBrokenState sets this).
##
## Behavior on enter (host-authoritative for the position snap):
##   1. Read the pending victim from `player.meta._pending_riposte_target`.
##   2. Snap the attacker's position to a melee-range offset from the victim,
##      rotated to face them. Snapping is one-shot at enter (same on every
##      peer because `transform` is in state_properties).
##   3. Force the victim into RiposteVictimState — host-only call.
##   4. Play `<library>/riposte_attacker` clip (falls back to attack clip).
##
## Damage / posture: pulled from `attack_data` (default `riposte.tres`).
## Massive damage_mult, zero posture damage (the victim is already broken).
## Full i-frames for the entire animation — `stagger_immune = true` from
## enter to exit. Cancel grammar: empty `cancel_whitelist` (uninterruptible).
##
## Networking: position snap and state transition are state_property-driven,
## so they replay deterministically on every peer. The forced
## RiposteVictimState transition uses the same authority pattern as
## ForcedRecovery (Tier C).

@export var attack_data: AttackData

const LIFESTEAL_RATIO: float = 0.3
const HIT_DEALT_SHAKE_AMPLITUDE: float = 0.16
const HIT_DEALT_SHAKE_DURATION: float = 0.3

## Distance the attacker is snapped to in front of the victim (meters).
## Must be inside the victim's hurtbox reach so the active window connects.
const RIPOSTE_OFFSET_DISTANCE: float = 1.4

var _enter_tick: int = -1
var _victim: Actor = null

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	action_locked = true
	cancel_whitelist = []  # uninterruptible
	stagger_immune = true  # full i-frames; held across exit
	actor.combo_step = 0
	# Pick up the victim stamped by `try_riposte`. Cleared after read.
	if player.has_meta(&"_pending_riposte_target"):
		_victim = player.get_meta(&"_pending_riposte_target") as Actor
		player.remove_meta(&"_pending_riposte_target")
	# Position snap — one-shot at enter, replicated via :transform state_property.
	if _victim and is_instance_valid(_victim):
		_snap_to_victim()
	# Host-authoritative: force the victim into RiposteVictimState. Same
	# authority pattern as ForcedRecovery (which Tier C used for parry).
	if actor.multiplayer.is_server() and _victim and is_instance_valid(_victim):
		if _victim._state_machine and _victim._state_machine.get_node_or_null(^"RiposteVictimState") != null:
			_victim._state_machine.transition(&"RiposteVictimState")
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_riposte_clip()

func exit(_next_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()
	_enter_tick = -1

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
	var progress := _get_animation_progress()
	var hitbox := _get_hitbox()
	var start_r: float = attack_data.hitbox_start_ratio if attack_data else 0.4
	var end_r: float = attack_data.hitbox_end_ratio if attack_data else 0.6
	var profile: StringName = attack_data.hitbox_profile if attack_data else &""
	if hitbox:
		if progress >= start_r and progress < end_r and not hitbox.is_active():
			hitbox.enable(profile)
		elif progress >= end_r and hitbox.is_active():
			hitbox.disable()
	stagger_immune = true  # full duration

	actor.velocity.x = 0
	actor.velocity.z = 0

	if hitbox and hitbox.is_active():
		_handle_hits(hitbox.get_new_hits())

	physics_move()

	if progress >= 1.0:
		state_machine.transition(&"IdleState" if actor.is_on_floor() else &"FallState")

func _snap_to_victim() -> void:
	# Compute the offset point in front of the victim (model -Z = forward).
	var basis_node: Node3D = _victim._model if _victim._model else _victim
	var victim_forward: Vector3 = -basis_node.global_basis.z
	victim_forward.y = 0.0
	if victim_forward.length_squared() < 0.0001:
		victim_forward = Vector3.FORWARD
	victim_forward = victim_forward.normalized()
	# Place attacker `OFFSET_DISTANCE` in front of victim, facing the victim.
	var snap_pos: Vector3 = _victim.global_position + victim_forward * RIPOSTE_OFFSET_DISTANCE
	snap_pos.y = actor.global_position.y  # don't yank vertically
	actor.global_position = snap_pos
	# Face the victim. Rotate the model basis if the avatar uses a separate
	# model node (PlayerActor pattern); otherwise rotate the actor.
	var face: Vector3 = (_victim.global_position - snap_pos)
	face.y = 0.0
	if face.length_squared() > 0.0001:
		face = face.normalized()
		var target_basis: Basis = Transform3D().looking_at(-face, Vector3.UP).basis
		if actor._model:
			actor._model.global_transform.basis = target_basis
		else:
			actor.global_transform.basis = target_basis

func _play_riposte_clip() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var library := _resolve_library_prefix()
	if library != "":
		var full: String = "%s/riposte_attacker" % library
		if anim.has_animation(full):
			anim.play(full)
			return
	# Fallback to attack_data clip or configured animation_name.
	var clip: String = animation_name
	if attack_data and attack_data.animation_name != "":
		clip = attack_data.animation_name
	if clip != "" and anim.has_animation(clip):
		anim.play(clip)

func _resolve_library_prefix() -> String:
	var configured: String = animation_name
	var slash: int = configured.find("/")
	if slash <= 0:
		return ""
	return configured.substr(0, slash)

func _get_animation_progress() -> float:
	if not actor._animation_player:
		return 1.0
	var anim_length := actor._animation_player.current_animation_length
	if anim_length <= 0:
		return 1.0
	return clampf(actor._animation_player.current_animation_position / anim_length, 0.0, 1.0)

func _get_hitbox() -> AttackHitbox:
	return actor.get_node_or_null(^"%AttackHitbox") as AttackHitbox

func _handle_hits(hurtboxes: Array[Hurtbox]) -> void:
	var hitbox := _get_hitbox()
	if hitbox == null or hurtboxes.is_empty():
		return
	var is_host := actor.multiplayer.is_server()
	var base_damage := actor.get_attack_damage()
	var ability_mult: float = 1.0
	var lifesteal: bool = false
	if actor.abilities:
		ability_mult = actor.abilities.get_damage_multiplier()
		lifesteal = actor.abilities.should_lifesteal()
	var attack_mult: float = attack_data.damage_mult if attack_data else 4.0
	var posture_mult: float = attack_data.posture_damage_mult if attack_data else 0.0
	var base_final: float = base_damage * ability_mult * attack_mult * hitbox.get_damage_multiplier()
	for hurtbox in hurtboxes:
		var target := hurtbox.get_actor()
		if target == null or target == actor:
			continue
		var final_damage: int = int(base_final * hurtbox.get_damage_multiplier())
		if is_host:
			target.set_meta(&"_pending_posture_mult", posture_mult)
			target.take_damage(final_damage, actor)
			target.remove_meta(&"_pending_posture_mult")
			if lifesteal and final_damage > 0:
				var heal: int = int(final_damage * LIFESTEAL_RATIO)
				actor.hp = min(actor.hp + heal, actor.get_max_hp())
				actor.hp_changed.emit(actor.hp)
		_spawn_local_hit_feedback(hurtbox, target)

func _spawn_local_hit_feedback(hurtbox: Hurtbox, target: Actor) -> void:
	if NetworkRollback.is_rollback():
		return
	if player.controlling_peer_id != multiplayer.get_unique_id():
		return
	var contact_point: Vector3 = hurtbox.global_position
	HitFx.spawn(hurtbox.material_kind, contact_point, target)
	var camera := player.avatar_camera as AvatarCamera
	if camera:
		camera.shake(HIT_DEALT_SHAKE_AMPLITUDE, HIT_DEALT_SHAKE_DURATION)
