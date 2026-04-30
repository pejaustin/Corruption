extends PlayerState

## Tier D — heavy-charge release. Entered from ChargeWindupState the moment
## the heavy button is released. Reads `actor.charge_start_tick` (a synced
## state_property) to compute charge_level: 0 = light release (the press
## was effectively a tap that briefly visited windup), 1 = mid release,
## 2 = full release.
##
## Picks an AttackData per level:
##   - level 0: falls back to `mid_attack_data` (typically `heavy_1.tres`)
##   - level 1: also `mid_attack_data` with a small damage boost (default to
##     `heavy_1.tres` unless authoring chooses a dedicated mid release)
##   - level 2: `full_attack_data` (typically `charge_release.tres`)
##
## Hyper-armor is on for the entire active window (charge releases are
## commitment beats — they cannot be staggered out of). Damage is the
## meatiest in the moveset and posture damage is correspondingly massive.
##
## Cancel grammar: not cancellable. Roll inside the release just no-ops.

@export var light_attack_data: AttackData
@export var mid_attack_data: AttackData
@export var full_attack_data: AttackData

const FULL_CHARGE_TICKS: int = 15  # ~0.5s — full charge threshold
const MID_CHARGE_TICKS: int = 6    # ~0.2s — mid charge threshold

const LIFESTEAL_RATIO: float = 0.3
const HIT_DEALT_SHAKE_AMPLITUDE: float = 0.14
const HIT_DEALT_SHAKE_DURATION: float = 0.22

var _resolved_data: AttackData = null
var _enter_tick: int = -1

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_enter_tick = NetworkTime.tick
	action_locked = true
	cancel_whitelist = []  # uninterruptible
	# Charge level: how long was the button held in windup? Use the synced
	# `actor.charge_start_tick` which the windup state stamped. Fallback to
	# 0 if entered without a windup (defensive).
	var held_ticks: int = 0
	if actor.charge_start_tick >= 0:
		held_ticks = NetworkTime.tick - actor.charge_start_tick
	_resolved_data = _pick_data_for_level(held_ticks)
	# Clear the charge tick now that we've consumed it.
	actor.charge_start_tick = -1
	actor.combo_step = 0
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_release_clip()

func exit(_next_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()
	_enter_tick = -1

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if _enter_tick < 0:
		_enter_tick = NetworkTime.tick
	# No cancel path — uninterruptible.
	var progress := _get_animation_progress()
	var hitbox := _get_hitbox()
	var data: AttackData = _resolved_data
	var start_r: float = data.hitbox_start_ratio if data else 0.35
	var end_r: float = data.hitbox_end_ratio if data else 0.7
	var profile: StringName = data.hitbox_profile if data else &""
	if hitbox:
		if progress >= start_r and progress < end_r and not hitbox.is_active():
			hitbox.enable(profile)
		elif progress >= end_r and hitbox.is_active():
			hitbox.disable()
	# Hyper-armor: always on for charge releases — they're commitment beats.
	stagger_immune = progress >= start_r and progress < end_r

	if data and data.lunge_distance > 0.0 and progress >= start_r and progress < end_r:
		_apply_lunge(start_r, end_r)
	else:
		actor.velocity.x = 0
		actor.velocity.z = 0

	if hitbox and hitbox.is_active():
		_handle_hits(hitbox.get_new_hits())

	physics_move()

	if progress >= 1.0:
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

## Level picker: 0 = light release, 1 = mid, 2 = full. Threshold values are
## documented constants; tune on a per-faction basis (Tier E).
func _pick_data_for_level(held_ticks: int) -> AttackData:
	if held_ticks >= FULL_CHARGE_TICKS:
		return full_attack_data if full_attack_data else mid_attack_data
	if held_ticks >= MID_CHARGE_TICKS:
		return mid_attack_data if mid_attack_data else light_attack_data
	return light_attack_data if light_attack_data else mid_attack_data

func _apply_lunge(start_ratio: float, end_ratio: float) -> void:
	var data: AttackData = _resolved_data
	if data == null or data.lunge_distance <= 0.0:
		return
	var window: float = max(0.0001, end_ratio - start_ratio)
	var anim_length: float = 0.0
	if actor._animation_player and actor._animation_player.current_animation_length > 0.0:
		anim_length = actor._animation_player.current_animation_length
	else:
		anim_length = 1.0
	var window_seconds: float = anim_length * window
	if window_seconds <= 0.0001:
		return
	var speed: float = data.lunge_distance / window_seconds
	var basis_node: Node3D = actor._model if actor._model else actor
	var forward: Vector3 = -basis_node.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	actor.velocity.x = forward.x * speed
	actor.velocity.z = forward.z * speed

func _play_release_clip() -> void:
	var anim: AnimationPlayer = actor._animation_player
	if anim == null:
		return
	var clip: String = animation_name
	if _resolved_data and _resolved_data.animation_name != "":
		clip = _resolved_data.animation_name
	if clip != "" and anim.has_animation(clip):
		anim.play(clip)

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
	var data: AttackData = _resolved_data
	var is_host := actor.multiplayer.is_server()
	var base_damage := actor.get_attack_damage()
	var ability_mult: float = 1.0
	var lifesteal: bool = false
	if actor.abilities:
		ability_mult = actor.abilities.get_damage_multiplier()
		lifesteal = actor.abilities.should_lifesteal()
	var attack_mult: float = data.damage_mult if data else 2.5
	var posture_mult: float = data.posture_damage_mult if data else 3.0
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
