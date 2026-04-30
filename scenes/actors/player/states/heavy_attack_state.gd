extends PlayerState

## Tier D — single heavy swing. No combo string by default; the chain depth
## lives on the light side (light_1 → light_2 → light_3). Pressing heavy with
## the button held past `CHARGE_HOLD_THRESHOLD_TICKS` promotes into
## ChargeWindupState; the snap from heavy to charge happens before the active
## window so the player either commits to the heavy or pivots into charge.
##
## Cancel grammar: Roll/Backstep break out (cancel_whitelist). Other input
## states do not — heavy is a commitment beat.
##
## Damage / posture: pulled from `attack_data` (e.g. `heavy_1.tres`) — bigger
## damage, much higher posture damage, and `hyper_armor = true` over the
## active window.

@export var attack_data: AttackData
@export var use_animation_keys: bool = false

const LIFESTEAL_RATIO: float = 0.3
const HIT_DEALT_SHAKE_AMPLITUDE: float = 0.10
const HIT_DEALT_SHAKE_DURATION: float = 0.18

## Number of ticks the heavy button must be held before HeavyAttackState
## defers to ChargeWindupState. ~6 ticks ≈ 200 ms — long enough to feel
## intentional, short enough that a tap-and-hold flows into the charge.
const CHARGE_HOLD_THRESHOLD_TICKS: int = 6

var _enter_tick: int = -1
var _charge_promoted: bool = false

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	_charge_promoted = false
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()
	if actor.abilities and actor.abilities.is_camouflaged():
		actor.abilities.cancel(&"camouflage")
	cancel_whitelist = [&"RollState", &"BackstepState"]
	# Reset combo step — heavy doesn't extend the light string.
	actor.combo_step = 0

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
	if try_roll():
		return

	# Pre-active-window: if the heavy button is still held past the threshold
	# AND we haven't crossed into the active frames yet, promote to charge.
	# After the active window opens, the heavy commits — releasing or holding
	# the button no longer matters until recovery.
	if not _charge_promoted:
		var elapsed: int = NetworkTime.tick - _enter_tick
		var progress := _get_animation_progress()
		var start_ratio: float = attack_data.hitbox_start_ratio if attack_data else 0.4
		if progress < start_ratio and elapsed >= CHARGE_HOLD_THRESHOLD_TICKS and get_heavy_attack():
			_charge_promoted = true
			state_machine.transition(&"ChargeWindupState")
			return

	# Standard heavy execution path — same shape as LightAttackState minus
	# the combo chain. Hyper-armor is on for the entire active window.
	var progress2 := _get_animation_progress()
	var hitbox := _get_hitbox()
	var start_r: float = attack_data.hitbox_start_ratio if attack_data else 0.4
	var end_r: float = attack_data.hitbox_end_ratio if attack_data else 0.7
	var profile: StringName = attack_data.hitbox_profile if attack_data else &""
	if not use_animation_keys and hitbox:
		if progress2 >= start_r and progress2 < end_r and not hitbox.is_active():
			hitbox.enable(profile)
		elif progress2 >= end_r and hitbox.is_active():
			hitbox.disable()
	if attack_data and attack_data.hyper_armor:
		stagger_immune = progress2 >= start_r and progress2 < end_r

	if attack_data and attack_data.lunge_distance > 0.0 and progress2 >= start_r and progress2 < end_r:
		_apply_lunge(start_r, end_r)
	else:
		actor.velocity.x = 0
		actor.velocity.z = 0

	if hitbox and hitbox.is_active():
		_handle_hits(hitbox.get_new_hits())

	physics_move()

	if progress2 >= 1.0:
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

func _apply_lunge(start_ratio: float, end_ratio: float) -> void:
	var window: float = max(0.0001, end_ratio - start_ratio)
	var anim_length: float = 0.0
	if actor._animation_player and actor._animation_player.current_animation_length > 0.0:
		anim_length = actor._animation_player.current_animation_length
	else:
		anim_length = 1.0
	var window_seconds: float = anim_length * window
	if window_seconds <= 0.0001:
		return
	var speed: float = attack_data.lunge_distance / window_seconds
	var basis_node: Node3D = actor._model if actor._model else actor
	var forward: Vector3 = -basis_node.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	actor.velocity.x = forward.x * speed
	actor.velocity.z = forward.z * speed

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
	var attack_mult: float = attack_data.damage_mult if attack_data else 1.8
	var posture_mult: float = attack_data.posture_damage_mult if attack_data else 2.0
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
