extends EnemyState

## Enemy attack with hitbox window driven by animation progress.
## Faces target, activates hitbox mid-animation, then returns to chase or idle.

@export var hitbox_start_ratio: float = 0.25
@export var hitbox_end_ratio: float = 0.6

var _hitbox_active: bool = false
var _hit_targets: Array[Node3D] = []
var _attack_finished: bool = false

func enter(previous_state: RewindableState, tick: int) -> void:
	_hitbox_active = false
	_attack_finished = false
	_hit_targets.clear()
	_set_hitbox_enabled(false)
	if actor._animation_player:
		if not actor._animation_player.animation_finished.is_connected(_on_animation_finished):
			actor._animation_player.animation_finished.connect(_on_animation_finished)

func exit(next_state: RewindableState, tick: int) -> void:
	_set_hitbox_enabled(false)
	_hitbox_active = false
	if actor._animation_player and actor._animation_player.animation_finished.is_connected(_on_animation_finished):
		actor._animation_player.animation_finished.disconnect(_on_animation_finished)

func tick(delta: float, tick: int, is_fresh: bool) -> void:
	# Face target throughout attack
	var avatar := find_avatar()
	if avatar:
		var dir := (avatar.global_position - actor.global_position)
		dir.y = 0
		if dir.length() > 0.01:
			face_direction(dir.normalized())

	var progress := _get_animation_progress()

	# Hitbox window
	if progress >= hitbox_start_ratio and progress < hitbox_end_ratio and not _hitbox_active:
		_hitbox_active = true
		_set_hitbox_enabled(true)
	elif progress >= hitbox_end_ratio and _hitbox_active:
		_hitbox_active = false
		_set_hitbox_enabled(false)

	if _hitbox_active:
		_check_hits()

	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	# Attack finished — pick next state
	if _attack_finished or progress >= 1.0:
		if avatar and not avatar.is_dormant and distance_to(avatar) < EnemyActor.ATTACK_RANGE:
			# Still in range, attack again
			_hitbox_active = false
			_attack_finished = false
			_hit_targets.clear()
			_set_hitbox_enabled(false)
			# Replay the attack animation
			if actor._animation_player:
				actor._animation_player.seek(0.0)
				actor._animation_player.play(animation_name)
		elif avatar and not avatar.is_dormant and distance_to(avatar) < EnemyActor.DEAGGRO_RADIUS:
			state_machine.transition(&"ChaseState")
		else:
			state_machine.transition(&"IdleState")

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
	var bodies := hitbox.get_overlapping_bodies()
	for body in bodies:
		if body == actor:
			continue
		if body in _hit_targets:
			continue
		if body is PlayerActor:
			_hit_targets.append(body)
			var dmg := actor.get_attack_damage()
			body.incoming_damage += dmg
			body.last_damage_source_peer = -1
			# Also notify controlling peer so they stagger locally (avoids rubberband)
			if body.controlling_peer_id > 0 and body.controlling_peer_id != multiplayer.get_unique_id():
				body.apply_incoming_damage.rpc_id(body.controlling_peer_id, dmg, -1)
