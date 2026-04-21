extends PlayerState

## Commitment-based melee attack. Cannot be cancelled once started.
## Hitbox window is driven by animation progress (ratio of total length),
## so it stays in sync even if animation speed changes.

## Hitbox activates at this fraction of the attack animation
@export var hitbox_start_ratio: float = 0.25
## Hitbox deactivates at this fraction
@export var hitbox_end_ratio: float = 0.6

const LIFESTEAL_RATIO: float = 0.3

var _hitbox_active: bool = false
var _hit_targets: Array[Node3D] = []
var _attack_finished: bool = false

func enter(previous_state: RewindableState, tick: int) -> void:
	_hitbox_active = false
	_attack_finished = false
	_hit_targets.clear()
	_set_hitbox_enabled(false)
	# Attacking breaks camouflage
	if actor.abilities and actor.abilities.is_camouflaged():
		actor.abilities._deactivate_effect("camouflage")
		actor.abilities._active_effects.erase("camouflage")
	# Listen for animation end
	if actor._animation_player:
		if not actor._animation_player.animation_finished.is_connected(_on_animation_finished):
			actor._animation_player.animation_finished.connect(_on_animation_finished)

func exit(next_state: RewindableState, tick: int) -> void:
	_set_hitbox_enabled(false)
	_hitbox_active = false
	if actor._animation_player and actor._animation_player.animation_finished.is_connected(_on_animation_finished):
		actor._animation_player.animation_finished.disconnect(_on_animation_finished)

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	var progress := _get_animation_progress()

	if progress >= hitbox_start_ratio and progress < hitbox_end_ratio and not _hitbox_active:
		_hitbox_active = true
		_set_hitbox_enabled(true)
	elif progress >= hitbox_end_ratio and _hitbox_active:
		_hitbox_active = false
		_set_hitbox_enabled(false)

	if _hitbox_active and actor.multiplayer.is_server():
		_check_hits()

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

func _set_hitbox_enabled(enabled: bool) -> void:
	var hitbox: Area3D = actor.get_node_or_null("AttackHitbox")
	if hitbox:
		hitbox.get_node("CollisionShape3D").disabled = not enabled

func _check_hits() -> void:
	var hitbox: Area3D = actor.get_node_or_null("AttackHitbox")
	if not hitbox:
		return
	var base_damage := actor.get_attack_damage()
	var damage_mult := 1.0
	var lifesteal := false
	if actor.abilities:
		damage_mult = actor.abilities.get_damage_multiplier()
		lifesteal = actor.abilities.should_lifesteal()
	var final_damage := int(base_damage * damage_mult)
	for body in hitbox.get_overlapping_bodies():
		if body == actor:
			continue
		if body in _hit_targets:
			continue
		if body.has_method("take_damage"):
			_hit_targets.append(body)
			body.take_damage(final_damage)
			if lifesteal:
				var heal := int(final_damage * LIFESTEAL_RATIO)
				actor.hp = min(actor.hp + heal, actor.get_max_hp())
				actor.hp_changed.emit(actor.hp)
