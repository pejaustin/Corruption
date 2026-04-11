extends PlayerState

## Commitment-based melee attack. Cannot be cancelled once started.
## Activates the AttackHitbox during a window in the middle of the animation.

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

	if _elapsed >= hitbox_start and _elapsed < hitbox_end and not _hitbox_active:
		_hitbox_active = true
		_set_hitbox_enabled(true)
	elif _elapsed >= hitbox_end and _hitbox_active:
		_hitbox_active = false
		_set_hitbox_enabled(false)

	if _hitbox_active and actor.multiplayer.is_server():
		_check_hits()

	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if _elapsed >= attack_duration:
		if actor.is_on_floor():
			state_machine.transition(&"IdleState")
		else:
			state_machine.transition(&"FallState")

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
		if body.has_method("take_damage"):
			_hit_targets.append(body)
			body.take_damage(actor.get_attack_damage())
