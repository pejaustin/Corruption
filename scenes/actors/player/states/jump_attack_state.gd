extends PlayerState

## Tier D — aerial plunge attack. Entered from JumpState/FallState when the
## player presses light_attack or heavy_attack while airborne. Uses
## `jump_attack.tres` by default. The state holds the swing animation through
## landing so a missed plunge eats into a brief recovery on the ground.
##
## Cancel grammar: not cancellable. Once committed in the air, the avatar
## sees through the swing.
##
## Hyper-armor on the landing frame — `attack_data.hyper_armor = true`. Trade
## clean against a held attack on the ground; if both connect, the plunge
## owner doesn't get staggered out of the swing.

@export var attack_data: AttackData

const LIFESTEAL_RATIO: float = 0.3
const HIT_DEALT_SHAKE_AMPLITUDE: float = 0.12
const HIT_DEALT_SHAKE_DURATION: float = 0.20

## Downward velocity applied per tick during the descent portion (before
## landing). Negative = downward in Godot 3D (Y-up). Lets the plunge feel
## decisive even from a small jump.
const PLUNGE_DESCENT_VELOCITY: float = -10.0

var _enter_tick: int = -1
var _has_landed: bool = false

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	_has_landed = false
	action_locked = true
	cancel_whitelist = []  # uninterruptible
	actor.combo_step = 0
	if actor.abilities and actor.abilities.is_camouflaged():
		actor.abilities.cancel(&"camouflage")
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_attack_clip()

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
	var start_r: float = attack_data.hitbox_start_ratio if attack_data else 0.3
	var end_r: float = attack_data.hitbox_end_ratio if attack_data else 0.65
	var profile: StringName = attack_data.hitbox_profile if attack_data else &""
	if hitbox:
		if progress >= start_r and progress < end_r and not hitbox.is_active():
			hitbox.enable(profile)
		elif progress >= end_r and hitbox.is_active():
			hitbox.disable()
	# Hyper-armor across the active window. The landing frame is the riskiest
	# part of a plunge — the AttackData flag carries it.
	if attack_data and attack_data.hyper_armor:
		stagger_immune = progress >= start_r and progress < end_r

	# Drive descent velocity until we hit the floor; gravity is also applied
	# by Actor._rollback_tick, but the explicit set ensures the plunge is
	# decisive even on small jumps where gravity-only would be too slow.
	if not _has_landed and not actor.is_on_floor():
		actor.velocity.y = min(actor.velocity.y, PLUNGE_DESCENT_VELOCITY)
		actor.velocity.x = 0
		actor.velocity.z = 0
	if actor.is_on_floor():
		_has_landed = true
		actor.velocity.x = 0
		actor.velocity.z = 0

	if hitbox and hitbox.is_active():
		_handle_hits(hitbox.get_new_hits())

	physics_move()

	if progress >= 1.0:
		# Landing recovery is the animation's own tail — exit naturally.
		state_machine.transition(&"IdleState" if actor.is_on_floor() else &"FallState")

func _play_attack_clip() -> void:
	if actor._animation_player == null:
		return
	var clip: String = animation_name
	if attack_data and attack_data.animation_name != "":
		clip = attack_data.animation_name
	if clip != "" and actor._animation_player.has_animation(clip):
		actor._animation_player.play(clip)

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
	var attack_mult: float = attack_data.damage_mult if attack_data else 1.7
	var posture_mult: float = attack_data.posture_damage_mult if attack_data else 1.8
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
