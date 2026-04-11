extends EnemyState

## Enemy attack with hitbox window, mirrors player attack pattern.
## Faces target, activates hitbox mid-animation, then returns to chase or idle.

@export var attack_duration: float = 0.8
@export var hitbox_start: float = 0.2
@export var hitbox_end: float = 0.5

var _elapsed: float = 0.0
var _hitbox_active: bool = false
var _hit_targets: Array = []

func enter(previous_state: RewindableState, tick: int):
	_elapsed = 0.0
	_hitbox_active = false
	_hit_targets.clear()
	_set_hitbox_enabled(false)

func exit(next_state: RewindableState, tick: int):
	_set_hitbox_enabled(false)
	_hitbox_active = false

func tick(delta: float, tick: int, is_fresh: bool):
	_elapsed += delta

	# Face target throughout attack
	var avatar := find_avatar()
	if avatar:
		var dir := (avatar.global_position - actor.global_position)
		dir.y = 0
		if dir.length() > 0.01:
			face_direction(dir.normalized())

	# Hitbox window
	if _elapsed >= hitbox_start and _elapsed < hitbox_end and not _hitbox_active:
		_hitbox_active = true
		_set_hitbox_enabled(true)
	elif _elapsed >= hitbox_end and _hitbox_active:
		_hitbox_active = false
		_set_hitbox_enabled(false)

	if _hitbox_active:
		_check_hits()

	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	# Attack finished — pick next state
	if _elapsed >= attack_duration:
		if avatar and not avatar.is_dormant and distance_to(avatar) < EnemyActor.ATTACK_RANGE:
			# Still in range, attack again
			_elapsed = 0.0
			_hitbox_active = false
			_hit_targets.clear()
			_set_hitbox_enabled(false)
		elif avatar and not avatar.is_dormant and distance_to(avatar) < EnemyActor.DEAGGRO_RADIUS:
			state_machine.transition(&"ChaseState")
		else:
			state_machine.transition(&"IdleState")

func _set_hitbox_enabled(enabled: bool):
	var hitbox: Area3D = actor.get_node_or_null("AttackHitbox")
	if hitbox:
		hitbox.get_node("CollisionShape3D").disabled = not enabled

func _check_hits():
	var hitbox: Area3D = actor.get_node_or_null("AttackHitbox")
	if not hitbox:
		return
	for body in hitbox.get_overlapping_bodies():
		if body == actor:
			continue
		if body in _hit_targets:
			continue
		if body is PlayerActor:
			_hit_targets.append(body)
			body.incoming_damage += actor.get_attack_damage()
