extends MinionState

## Minion attack with animation-driven hitbox window.
## Applies damage via Actor.incoming_damage so it flows through the standard pipeline.
## Uses the AttackHitbox component — see scripts/combat/attack_hitbox.gd.

## Animation-progress window that enables the hitbox. Ignored when
## use_animation_keys is true.
@export var hitbox_start_ratio: float = 0.25
@export var hitbox_end_ratio: float = 0.6
## Profile name to activate on this attack. Empty = first shape child.
@export var hitbox_profile: StringName = &""
## When true, the script never toggles the hitbox — only animation method
## track keys (enable/disable calls on %AttackHitbox) do. Hit-detection still
## polls while the hitbox is active. Prevents double-firing when both paths
## run on the same animation.
@export var use_animation_keys: bool = false

func enter(_previous_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()

func exit(_next_state: RewindableState, _tick: int) -> void:
	var hitbox := _get_hitbox()
	if hitbox:
		hitbox.disable()

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if check_retreat():
		return
	var target := find_hostile_target()
	if target:
		var dir := (target.global_position - actor.global_position)
		dir.y = 0
		if dir.length() > 0.01:
			face_direction(dir.normalized())

	var progress := _get_animation_progress()
	var hitbox := _get_hitbox()

	# Script-driven path. Types without a hitbox silently skip.
	if not use_animation_keys and hitbox:
		if progress >= hitbox_start_ratio and progress < hitbox_end_ratio and not hitbox.is_active():
			hitbox.enable(hitbox_profile)
		elif progress >= hitbox_end_ratio and hitbox.is_active():
			hitbox.disable()

	# Poll overlaps while the hitbox is active, regardless of who toggled it.
	if hitbox and hitbox.is_active():
		_check_hits(hitbox)

	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()

	if progress >= 1.0:
		if target and distance_to(target) < minion.attack_range:
			if hitbox:
				hitbox.disable()
			if actor._animation_player:
				actor._animation_player.seek(0.0)
				actor._animation_player.play(animation_name)
		elif target and distance_to(target) < minion.aggro_radius:
			state_machine.transition(&"ChaseState")
		else:
			state_machine.transition(&"IdleState")

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
	var base_dmg := minion.attack_damage * hitbox.get_damage_multiplier()
	for hurtbox in hitbox.get_new_hits():
		var other := hurtbox.get_actor()
		if other == null or other == actor:
			continue
		if not minion.is_hostile_to(other):
			continue
		var dmg := int(base_dmg * hurtbox.get_damage_multiplier())
		# Tier F — friendly-fire gate. The avatar leg dual-writes via
		# `incoming_damage` (no source on the resulting take_damage call),
		# which means the gate inside `Actor.take_damage` can't see the
		# attacker. Apply the filter here so FF-off cleanly drops the hit.
		if not DamageFilter.allow(actor, other):
			continue
		if other is AvatarActor:
			other.incoming_damage += dmg
			other.last_damage_source_peer = minion.owner_peer_id
			if other.controlling_peer_id > 0 and other.controlling_peer_id != multiplayer.get_unique_id():
				other.apply_incoming_damage.rpc_id(other.controlling_peer_id, dmg, minion.owner_peer_id)
		else:
			# Minions don't have a RollbackSynchronizer draining incoming_damage,
			# so apply the hit directly on the host. HP is broadcast to clients
			# via MinionManager._sync_minion_actor. Tier C: pass `actor` as the
			# source so victims (other minions, bosses) can run block/parry/
			# posture-on-attacker logic. Avatars use the dual-write
			# `incoming_damage` path above; that leg still passes null source
			# (see comment in actor.gd:_rollback_tick) — Tier C accepts that
			# limitation rather than rewiring the dual-write to carry actors.
			var killed := other.hp - dmg <= 0
			other.take_damage(dmg, actor)
			# Raise-dead: if this hit killed the victim, flag for skeleton raise
			if minion.minion_trait == &"raise_dead" and killed:
				var mm := actor.get_tree().current_scene.get_node_or_null("MinionManager")
				if mm and mm.has_method("raise_dead_at"):
					mm.raise_dead_at(minion.owner_peer_id, minion.faction, other.global_position)
		_spawn_local_hit_feedback(hurtbox, other)

## Local-only hit feedback. HitFx skips itself during rollback resim. Damage
## itself runs above and is host-authoritative.
func _spawn_local_hit_feedback(hurtbox: Hurtbox, target: Actor) -> void:
	if NetworkRollback.is_rollback():
		return
	HitFx.spawn(hurtbox.material_kind, hurtbox.global_position, target)
