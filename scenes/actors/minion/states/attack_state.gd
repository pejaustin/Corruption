extends MinionState

## Minion attack with animation-driven hitbox window.
## Applies damage via Actor.incoming_damage so it flows through the standard pipeline.
## Uses the AttackHitbox component — see scripts/combat/attack_hitbox.gd.

@export var hitbox_start_ratio: float = 0.25
@export var hitbox_end_ratio: float = 0.6
## Profile name to activate on this attack. Empty = first shape child.
@export var hitbox_profile: StringName = &""

var _hitbox_active: bool = false
var _attack_finished: bool = false

func enter(_previous_state: RewindableState, _tick: int) -> void:
	_hitbox_active = false
	_attack_finished = false
	_get_hitbox().disable()
	if actor._animation_player:
		if not actor._animation_player.animation_finished.is_connected(_on_animation_finished):
			actor._animation_player.animation_finished.connect(_on_animation_finished)

func exit(_next_state: RewindableState, _tick: int) -> void:
	_get_hitbox().disable()
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
	var hitbox := _get_hitbox()

	if progress >= hitbox_start_ratio and progress < hitbox_end_ratio and not _hitbox_active:
		_hitbox_active = true
		hitbox.enable(hitbox_profile)
	elif progress >= hitbox_end_ratio and _hitbox_active:
		_hitbox_active = false
		hitbox.disable()

	if _hitbox_active:
		_check_hits(hitbox)

	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if _attack_finished or progress >= 1.0:
		if target and distance_to(target) < minion.attack_range:
			_hitbox_active = false
			_attack_finished = false
			hitbox.disable()
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

func _get_hitbox() -> AttackHitbox:
	# Located via unique_name_in_owner so per-type scenes can parent it under a
	# BoneAttachment3D without touching this script.
	return actor.get_node_or_null(^"%AttackHitbox") as AttackHitbox

func _check_hits(hitbox: AttackHitbox) -> void:
	if hitbox == null:
		return
	var dmg := int(minion.attack_damage * hitbox.get_damage_multiplier())
	for body in hitbox.get_new_hits():
		if body == actor:
			continue
		var other := body as Actor
		if other == null or not minion.is_hostile_to(other):
			continue
		if other is PlayerActor:
			other.incoming_damage += dmg
			other.last_damage_source_peer = minion.owner_peer_id
			if other.controlling_peer_id > 0 and other.controlling_peer_id != multiplayer.get_unique_id():
				other.apply_incoming_damage.rpc_id(other.controlling_peer_id, dmg, minion.owner_peer_id)
		else:
			# Minions don't have a RollbackSynchronizer draining incoming_damage,
			# so apply the hit directly on the host. HP is broadcast to clients
			# via MinionManager._sync_minion_actor.
			var killed := other.hp - dmg <= 0
			other.take_damage(dmg)
			# Raise-dead: if this hit killed the victim, flag for skeleton raise
			if minion.minion_trait == &"raise_dead" and killed:
				var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager")
				if mm and mm.has_method("raise_dead_at"):
					mm.raise_dead_at(minion.owner_peer_id, minion.faction, other.global_position)
