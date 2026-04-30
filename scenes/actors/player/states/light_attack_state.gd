extends PlayerState

## Tier D — generic light-attack state. Reads its frame data from an exported
## `AttackData` resource so the same script powers light_1 / light_2 / light_3
## without per-step duplication. Combo chaining: if the player buffers another
## light-attack press during the combo window, the state transitions back into
## itself with the next-step's AttackData (resolved via `attack_data.next_attack_id`
## and `AttackData.lookup`). When the buffered press is missing or the combo
## ends (next_attack_id empty), the state self-exits to IdleState/FallState.
##
## Cancel grammar: Roll-cancel is allowed (`cancel_whitelist = [&"RollState",
## &"BackstepState"]`) per Tier C grammar; nothing else interrupts.
##
## Hitbox window: ratio-based by default (the legacy attack_state.gd path).
## `use_animation_keys = true` defers to method-track keys on the swing's
## animation; the state honors `_combo_window_open` / `_combo_window_close`
## either way for the combo gate.
##
## This script REPLACES the legacy `scenes/actors/player/states/attack_state.gd`
## as the canonical light swing. The old file remains for backwards-
## compatibility (existing scenes that still reference AttackState — see the
## file's deprecation comment) but new wiring should use LightAttackState.

@export var attack_data: AttackData
## When true, hitbox enable/disable is driven by animation method-track keys
## on `%AttackHitbox` rather than ratio polling. See attack_state.gd's note;
## same flag, same semantics.
@export var use_animation_keys: bool = false
## Combo step this state represents. 1 = light_1, 2 = light_2, 3 = light_3.
## Used to update `actor.combo_step` so the state_property carries the chain
## position deterministically across rollback resim. The Avatar scene wires
## three LightAttackState nodes (one per step) each with the matching value.
@export var combo_step: int = 1

const LIFESTEAL_RATIO: float = 0.3
const HIT_DEALT_SHAKE_AMPLITUDE: float = 0.06
const HIT_DEALT_SHAKE_DURATION: float = 0.12

func enter(_previous_state: RewindableState, _tick: int) -> void:
	# Shared light-attack entry: clear hitbox, break camouflage, latch combo
	# step. Roll cancels are the only break; cancel_whitelist enforces it.
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()
	if actor.abilities and actor.abilities.is_camouflaged():
		actor.abilities.cancel(&"camouflage")
	cancel_whitelist = [&"RollState", &"BackstepState"]
	# Stamp the chain position so downstream systems (HUD, balance CSV) can
	# read which combo step is active. State_property on PlayerActor.
	actor.combo_step = combo_step
	# Reset the window flag so the previous swing's late open doesn't carry.
	actor.combo_window_open = false
	# Hyper-armor: AttackData can flag a swing as stagger-immune through its
	# active window. Flip on at enter; the active-window check inside tick()
	# manages the on/off transitions.
	if attack_data and attack_data.hyper_armor:
		stagger_immune = false  # off by default; flipped within active window

func display_enter(_previous_state: RewindableState, _tick: int) -> void:
	_play_attack_clip()

func exit(_next_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()
	# Stamp the timeout watchdog; Actor._decay_combo will reset combo_step
	# back to 0 after COMBO_RESET_GRACE_TICKS unless another light hits.
	actor._last_combo_attack_tick = NetworkTime.tick

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if try_roll():
		return
	var progress := _get_animation_progress()
	var hitbox := _get_hitbox()

	# Hitbox window — driven by AttackData if present, else fall back to the
	# legacy state-export ratios (use_animation_keys still wins).
	var start_ratio: float = attack_data.hitbox_start_ratio if attack_data else 0.25
	var end_ratio: float = attack_data.hitbox_end_ratio if attack_data else 0.6
	var profile: StringName = attack_data.hitbox_profile if attack_data else &""
	if not use_animation_keys and hitbox:
		if progress >= start_ratio and progress < end_ratio and not hitbox.is_active():
			hitbox.enable(profile)
		elif progress >= end_ratio and hitbox.is_active():
			hitbox.disable()
	# Hyper-armor active window — only carries when AttackData opts in.
	if attack_data and attack_data.hyper_armor:
		stagger_immune = progress >= start_ratio and progress < end_ratio

	# Apply forward lunge during the active window if AttackData specifies one.
	# Computed as a per-tick velocity ramp so move_and_slide() honors collisions.
	if attack_data and attack_data.lunge_distance > 0.0 and progress >= start_ratio and progress < end_ratio:
		_apply_lunge(start_ratio, end_ratio, progress)
	else:
		actor.velocity.x = 0
		actor.velocity.z = 0

	if hitbox and hitbox.is_active():
		_handle_hits(hitbox.get_new_hits())

	physics_move()

	# Ratio-based combo window fallback. Animation method tracks may also flip
	# `actor.combo_window_open` directly; either path drives the same flag.
	_update_combo_window(progress)

	# Try to chain to the next combo step on a buffered light press inside the
	# window. If it succeeds, transition immediately so the chain doesn't run
	# the recovery tail of the previous swing.
	if actor.combo_window_open and _try_chain():
		return

	if progress >= 1.0:
		# End of recovery — drop into IdleState/FallState. combo_step stays
		# stamped; Actor._decay_combo will reset it after COMBO_RESET_GRACE_TICKS
		# if the player doesn't follow up.
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

# --- Combo chaining ---

func _update_combo_window(progress: float) -> void:
	# Don't override if animation method tracks already flipped the flag this
	# swing — the tracks call `actor._combo_window_open()` / `_combo_window_close()`
	# directly. The ratio path is the fallback for clips without method tracks.
	if attack_data == null:
		return
	var inside: bool = progress >= attack_data.combo_window_start_ratio and progress <= attack_data.combo_window_end_ratio
	# Only assert from the ratio path if no method-track has fired (we detect
	# that by the absence of any explicit toggle this swing — proxied by:
	# during the ratio window we assume nobody else is driving it). This is
	# good enough; if the method tracks land, set use_animation_keys = true and
	# the flag is purely method-driven.
	if not use_animation_keys:
		actor.combo_window_open = inside

func _try_chain() -> bool:
	if attack_data == null or attack_data.next_attack_id == &"":
		return false
	if not player.avatar_input.consume_if_buffered(&"light_attack"):
		return false
	# We're staying in LightAttackState; just swap to the next AttackData and
	# re-enter. The simplest deterministic reset is a transition back into the
	# same state node — but combo_step needs to advance, and our @export is
	# fixed per node. Project pattern: each combo step has its own
	# LightAttackState child node, distinguished by a state name (e.g.
	# LightAttackState1, LightAttackState2, LightAttackState3). The
	# `next_attack_id` field encodes the next state node's name implicitly via
	# the AttackData chain — we resolve via the catalog and look up the state
	# node by id (StringName "LightAttackState<step>").
	var next_data: AttackData = AttackData.lookup(attack_data.next_attack_id)
	if next_data == null:
		push_warning("[LightAttackState] next_attack_id %s not found in catalog" % attack_data.next_attack_id)
		return false
	# Find the sibling state whose attack_data.id matches. Iterate the state
	# machine children once — there are typically <12 states.
	var target_state_name: StringName = _state_name_for_attack(next_data.id)
	if target_state_name == &"":
		# Fallback: stay in this state but mutate attack_data + replay clip.
		# This works because the next swing's animation track triggers the
		# next combo window. Less clean, but supported.
		attack_data = next_data
		actor.combo_step = combo_step + 1
		actor.combo_window_open = false
		_play_attack_clip()
		return true
	state_machine.transition(target_state_name)
	return true

## Resolve the sibling state name carrying the given AttackData id. Avoids
## hard-coding combo step → state-name mapping; any state whose `attack_data`
## resource has the matching id is a valid target.
func _state_name_for_attack(id: StringName) -> StringName:
	var parent := state_machine
	if parent == null:
		return &""
	for child in parent.get_children():
		if child == self:
			continue
		var script_var: Variant = child.get(&"attack_data")
		if script_var is AttackData:
			var data := script_var as AttackData
			if data and data.id == id:
				return StringName(child.name)
	return &""

# --- Lunge ---

## Slide the actor forward over the active window so swings carry distance.
## Distance budget = `attack_data.lunge_distance`; spread over the active
## ratio band, eased linearly. Velocity is set per-tick; physics_move()
## consumes it. Skip when lunge_distance is 0 (the common case for combo
## strings).
func _apply_lunge(start_ratio: float, end_ratio: float, progress: float) -> void:
	var window: float = max(0.0001, end_ratio - start_ratio)
	# Total active window time: animation_length × window_fraction. We deliver
	# `lunge_distance` over that period as a constant velocity.
	var anim_length: float = 0.0
	if actor._animation_player and actor._animation_player.current_animation_length > 0.0:
		anim_length = actor._animation_player.current_animation_length
	else:
		anim_length = 1.0
	var window_seconds: float = anim_length * window
	if window_seconds <= 0.0001:
		return
	var speed: float = attack_data.lunge_distance / window_seconds
	# Forward direction in world XZ — model basis is the right reference here
	# (the visual is what's pointing at the target).
	var basis_node: Node3D = actor._model if actor._model else actor
	var forward: Vector3 = -basis_node.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return
	forward = forward.normalized()
	actor.velocity.x = forward.x * speed
	actor.velocity.z = forward.z * speed

# --- Animation / Hitbox helpers ---

func _play_attack_clip() -> void:
	# AttackData carries the animation; fall back to the configured
	# animation_name on the state node (matches existing pattern).
	if actor._animation_player == null:
		return
	var clip: String = animation_name
	if attack_data and attack_data.animation_name != "":
		clip = attack_data.animation_name
	if clip != "" and actor._animation_player.has_animation(clip):
		actor._animation_player.play(clip)
	# Tier E — apply faction attack-speed multiplier. AvatarActor exposes the
	# value; non-avatar actors fall through to 1.0. We write speed_scale here
	# (rather than on enter) because hitstop's restore branch resets to 1.0,
	# and this clip-replay is the canonical post-hitstop entry point.
	var mult: float = 1.0
	if actor.has_method(&"get_attack_speed_mult"):
		mult = actor.call(&"get_attack_speed_mult")
	if mult != 1.0:
		actor._animation_player.speed_scale = mult

func _get_animation_progress() -> float:
	if not actor._animation_player:
		return 1.0
	var anim_length := actor._animation_player.current_animation_length
	if anim_length <= 0:
		return 1.0
	return clampf(actor._animation_player.current_animation_position / anim_length, 0.0, 1.0)

func _get_hitbox() -> AttackHitbox:
	return actor.get_node_or_null(^"%AttackHitbox") as AttackHitbox

# --- Damage application ---
# Mirrors attack_state.gd's _handle_hits but pipes AttackData multipliers
# through, including the Tier C posture-damage mult.
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
	var attack_mult: float = attack_data.damage_mult if attack_data else 1.0
	var posture_mult: float = attack_data.posture_damage_mult if attack_data else 1.0
	var base_final: float = base_damage * ability_mult * attack_mult * hitbox.get_damage_multiplier()
	for hurtbox in hurtboxes:
		var target := hurtbox.get_actor()
		if target == null or target == actor:
			continue
		var final_damage: int = int(base_final * hurtbox.get_damage_multiplier())
		if is_host:
			# Posture multiplier path: AttackData.posture_damage_mult scales
			# Actor.HIT_POSTURE_PER_HIT, applied INSIDE the victim's
			# take_damage. We can't pass the multiplier through the existing
			# (amount, source) signature without a wider refactor, so we
			# pre-stamp the attacker's `_pending_posture_mult` meta and let the
			# victim read it back. Simple and contained.
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
