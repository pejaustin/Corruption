extends PlayerState

## Commitment-based melee attack. Cannot be cancelled once started.
## Hitbox window is driven by animation progress (ratio of total length),
## so it stays in sync even if animation speed changes.
##
## Uses the AttackHitbox component — named profiles let an attack swap shapes
## mid-swing (Windup/Impact/Recovery). For single-shape setups, leave
## hitbox_profile empty and the one CollisionShape3D child is used.

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

func enter(_previous_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()
	# Attacking breaks camouflage
	if actor.abilities and actor.abilities.is_camouflaged():
		actor.abilities.cancel(&"camouflage")

func exit(_next_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
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

	if hitbox and hitbox.is_active() and actor.multiplayer.is_server():
		_check_hits(hitbox)

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

func _check_hits(hitbox: AttackHitbox) -> void:
	if hitbox == null:
		return
	var base_damage := actor.get_attack_damage()
	var damage_mult := 1.0
	var lifesteal := false
	if actor.abilities:
		damage_mult = actor.abilities.get_damage_multiplier()
		lifesteal = actor.abilities.should_lifesteal()
	var base_final := base_damage * damage_mult * hitbox.get_damage_multiplier()
	for hurtbox in hitbox.get_new_hits():
		var target := hurtbox.get_actor()
		if target == null or target == actor:
			continue
		var final_damage := int(base_final * hurtbox.get_damage_multiplier())
		target.take_damage(final_damage)
		if lifesteal:
			var heal := int(final_damage * LIFESTEAL_RATIO)
			actor.hp = min(actor.hp + heal, actor.get_max_hp())
			actor.hp_changed.emit(actor.hp)
