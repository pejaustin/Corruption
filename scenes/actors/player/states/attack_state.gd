extends PlayerState

## DEPRECATED — Tier D split this into `light_attack_state.gd`,
## `heavy_attack_state.gd`, `charge_windup_state.gd`, `charge_release_state.gd`,
## `sprint_attack_state.gd`, `jump_attack_state.gd`, and the riposte pair.
##
## This file is kept for backwards-compatibility with scenes that still wire
## a single AttackState node (the avatar_actor.tscn references an `AttackState`
## script-only node that may not be re-pointed yet). New work should use
## LightAttackState / HeavyAttackState etc. via the `data/attacks/*.tres`
## resources. See docs/technical/tier-d-implementation.md for the full
## migration story.
##
## Behavior unchanged: commitment-based melee attack, ratio-driven hitbox
## window. AttackHitbox profile names let it swap shapes mid-swing.

## Hitbox activates at this fraction of the attack animation. Ignored when
## use_animation_keys is true.
@export var hitbox_start_ratio: float = 0.25
## Hitbox deactivates at this fraction. Ignored when use_animation_keys is true.
@export var hitbox_end_ratio: float = 0.6
## Profile name to activate on this attack. Empty = first shape child.
@export var hitbox_profile: StringName = &""
## When true, the script never toggles the hitbox — only animation method
## track keys on %AttackHitbox do. Hit-detection still polls while the hitbox
## is active. Prevents double-firing when both paths run on the same animation.
@export var use_animation_keys: bool = false

const LIFESTEAL_RATIO: float = 0.3

## Camera-shake feel knobs. Local-only — never enters rollback state.
const HIT_DEALT_SHAKE_AMPLITUDE: float = 0.06
const HIT_DEALT_SHAKE_DURATION: float = 0.12

func enter(_previous_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()
	# Attacking breaks camouflage
	if actor.abilities and actor.abilities.is_camouflaged():
		actor.abilities.cancel(&"camouflage")
	# Placeholder commitment: lock the entire attack so cancel_whitelist gates
	# external transitions. Replace with per-frame method-track keys
	# (lock_action / unlock_action) once authored — see action-gating.md.
	# action_locked = true

func exit(_next_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	# Roll is the only authored cancel out of an attack — try_roll routes
	# through actor.try_transition, which respects this state's cancel_whitelist.
	if try_roll():
		return
	# Termination is driven purely by animation progress (deterministic across
	# peers given the same state-entry tick). The animation_finished signal
	# path was removed because its wall-clock timing desynced remote peers
	# and caused rollback rubberband.
	var progress := _get_animation_progress()
	var hitbox := _get_hitbox()

	if not use_animation_keys and hitbox:
		if progress >= hitbox_start_ratio and progress < hitbox_end_ratio and not hitbox.is_active():
			hitbox.enable(hitbox_profile)
		elif progress >= hitbox_end_ratio and hitbox.is_active():
			hitbox.disable()

	if hitbox and hitbox.is_active():
		# Host applies damage; every peer collects hits for local FX. The hitbox
		# tracks "reported" hurtboxes per activation so a peer running the loop
		# twice (e.g. host) doesn't fire FX twice. Order of operations: drain
		# the hits once, fan out FX always, only host applies damage / lifesteal.
		var hits := hitbox.get_new_hits()
		_handle_hits(hits)

	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if progress >= 1.0:
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

func _get_animation_progress() -> float:
	if not actor._animation_player:
		return 1.0
	var anim_length := actor._animation_player.current_animation_length
	if anim_length <= 0:
		return 1.0
	return clampf(actor._animation_player.current_animation_position / anim_length, 0.0, 1.0)

func _get_hitbox() -> AttackHitbox:
	# Located via unique_name_in_owner so subtypes can parent it wherever they
	# want (e.g. under a BoneAttachment3D so it tracks the sword).
	return actor.get_node_or_null(^"%AttackHitbox") as AttackHitbox

## Per-tick hit handler. Runs on every peer so attacker-local FX (sparks +
## camera shake) play for whoever is actually swinging. Host additionally
## applies damage + lifesteal.
func _handle_hits(hurtboxes: Array[Hurtbox]) -> void:
	var hitbox := _get_hitbox()
	if hitbox == null or hurtboxes.is_empty():
		return
	var is_host := actor.multiplayer.is_server()
	var base_damage := actor.get_attack_damage()
	var damage_mult := 1.0
	var lifesteal := false
	if actor.abilities:
		damage_mult = actor.abilities.get_damage_multiplier()
		lifesteal = actor.abilities.should_lifesteal()
	var base_final := base_damage * damage_mult * hitbox.get_damage_multiplier()
	for hurtbox in hurtboxes:
		var target := hurtbox.get_actor()
		if target == null or target == actor:
			continue
		var final_damage := int(base_final * hurtbox.get_damage_multiplier())
		if is_host:
			target.take_damage(final_damage, actor)
			if lifesteal:
				var heal := int(final_damage * LIFESTEAL_RATIO)
				actor.hp = min(actor.hp + heal, actor.get_max_hp())
				actor.hp_changed.emit(actor.hp)
		_spawn_local_hit_feedback(hurtbox, target)

## Local-only feedback when this attack lands a hit. HitFx and camera shake
## both gate themselves against resimulation — see hit_fx.gd and the comment
## in avatar_camera.shake. Hit-flash is owned by the victim Actor's
## took_damage emission, so it's not double-driven from here. Only fires on
## the controlling peer's screen — clients shouldn't see other players' hit
## sparks twice (once from their own attack, once from the host's resim).
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
