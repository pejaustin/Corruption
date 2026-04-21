extends MinionState

## Minion attack with animation-driven hitbox window.
## Applies damage via Actor.incoming_damage so it flows through the standard pipeline.

@export var hitbox_start_ratio: float = 0.25
@export var hitbox_end_ratio: float = 0.6

var _hitbox_active: bool = false
var _hit_targets: Array[Node3D] = []
var _attack_finished: bool = false

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_hitbox_active = false
	_attack_finished = false
	_hit_targets.clear()
	_set_hitbox_enabled(false)
	if actor._animation_player:
		if not actor._animation_player.animation_finished.is_connected(_on_animation_finished):
			actor._animation_player.animation_finished.connect(_on_animation_finished)

func exit(_next_state: RewindableState, _tick: int) -> void:
	_set_hitbox_enabled(false)
	_hitbox_active = false
	if actor._animation_player and actor._animation_player.animation_finished.is_connected(_on_animation_finished):
		actor._animation_player.animation_finished.disconnect(_on_animation_finished)

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	var target := find_hostile_target()
	if target:
		var dir := (target.global_position - actor.global_position)
		dir.y = 0
		if dir.length() > 0.01:
			face_direction(dir.normalized())

	var progress := _get_animation_progress()

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

	if _attack_finished or progress >= 1.0:
		if target and distance_to(target) < minion.attack_range:
			_hitbox_active = false
			_attack_finished = false
			_hit_targets.clear()
			_set_hitbox_enabled(false)
			if actor._animation_player:
				actor._animation_player.seek(0.0)
				actor._animation_player.play(animation_name)
		elif target and distance_to(target) < minion.aggro_radius:
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
		var shape := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape:
			shape.disabled = not enabled

func _check_hits() -> void:
	var hitbox: Area3D = actor.get_node_or_null("AttackHitbox")
	if not hitbox:
		return
	var dmg := minion.attack_damage
	for body in hitbox.get_overlapping_bodies():
		if body == actor or body in _hit_targets:
			continue
		var other := body as Actor
		if other == null or not minion.is_hostile_to(other):
			continue
		_hit_targets.append(body)
		if other is PlayerActor:
			other.incoming_damage += dmg
			other.last_damage_source_peer = minion.owner_peer_id
			if other.controlling_peer_id > 0 and other.controlling_peer_id != multiplayer.get_unique_id():
				other.apply_incoming_damage.rpc_id(other.controlling_peer_id, dmg, minion.owner_peer_id)
		else:
			other.incoming_damage += dmg
			# Raise-dead: if we just put this victim to 0, flag for skeleton raise
			if minion.minion_trait == &"raise_dead" and other.hp - dmg <= 0:
				var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager")
				if mm and mm.has_method("raise_dead_at"):
					mm.raise_dead_at(minion.owner_peer_id, minion.faction, other.global_position)
