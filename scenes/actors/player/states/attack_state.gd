extends PlayerState

## Commitment-based melee attack. Cannot be cancelled once started.
## Hitbox window is driven by animation progress (ratio of total length),
## so it stays in sync even if animation speed changes.
##
## Uses the AttackHitbox component — named profiles let an attack swap shapes
## mid-swing (Windup/Impact/Recovery). For single-shape setups, leave
## hitbox_profile empty and the one CollisionShape3D child is used.

## Hitbox activates at this fraction of the attack animation
@export var hitbox_start_ratio: float = 0.25
## Hitbox deactivates at this fraction
@export var hitbox_end_ratio: float = 0.6
## Profile name to activate on this attack. Empty = first shape child.
@export var hitbox_profile: StringName = &""

const LIFESTEAL_RATIO: float = 0.3

var _hitbox_active: bool = false
var _attack_finished: bool = false

func enter(previous_state: RewindableState, tick: int) -> void:
	_hitbox_active = false
	_attack_finished = false
	_get_hitbox().disable()
	# Attacking breaks camouflage
	if actor.abilities and actor.abilities.is_camouflaged():
		actor.abilities.cancel(&"camouflage")
	# Listen for animation end
	if actor._animation_player:
		if not actor._animation_player.animation_finished.is_connected(_on_animation_finished):
			actor._animation_player.animation_finished.connect(_on_animation_finished)

func exit(next_state: RewindableState, tick: int) -> void:
	_get_hitbox().disable()
	_hitbox_active = false
	if actor._animation_player and actor._animation_player.animation_finished.is_connected(_on_animation_finished):
		actor._animation_player.animation_finished.disconnect(_on_animation_finished)

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	var progress := _get_animation_progress()
	var hitbox := _get_hitbox()

	if progress >= hitbox_start_ratio and progress < hitbox_end_ratio and not _hitbox_active:
		_hitbox_active = true
		hitbox.enable(hitbox_profile)
	elif progress >= hitbox_end_ratio and _hitbox_active:
		_hitbox_active = false
		hitbox.disable()

	if _hitbox_active and actor.multiplayer.is_server():
		_check_hits(hitbox)

	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if _attack_finished or progress >= 1.0:
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

func _on_animation_finished(_anim_name: StringName) -> void:
	_attack_finished = true

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
	var final_damage := int(base_damage * damage_mult * hitbox.get_damage_multiplier())
	for body in hitbox.get_new_hits():
		if body == actor:
			continue
		if body.has_method("take_damage"):
			body.take_damage(final_damage)
			if lifesteal:
				var heal := int(final_damage * LIFESTEAL_RATIO)
				actor.hp = min(actor.hp + heal, actor.get_max_hp())
				actor.hp_changed.emit(actor.hp)
