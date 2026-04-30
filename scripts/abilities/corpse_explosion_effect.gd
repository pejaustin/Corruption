class_name CorpseExplosionEffect extends AbilityEffect

## Undeath: instant AoE damage to nearby neutral minions.

const RADIUS: float = 8.0
const DAMAGE: int = 40

func _on_activate() -> void:
	if not multiplayer.is_server() or caster == null:
		return
	var mm := _minion_manager()
	if mm == null:
		return
	for m in mm.get_all_minions():
		if m.owner_peer_id != -1 or m.hp <= 0:
			continue
		if caster.global_position.distance_to(m.global_position) < RADIUS:
			# AoE damage attributed to the caster — lights up Tier C's
			# behind-attack lock break and Tier D's posture-on-attacker path
			# when the caster is a player. Block doesn't apply to AoE in this
			# tier (the caster is the source, but the explosion is omnidirectional);
			# is_blocking_against will incidentally pass when the caster happens
			# to be in the victim's front cone, which is acceptable behaviour
			# for "you guarded against the warlock who lit the bomb."
			m.take_damage(DAMAGE, caster)

func _minion_manager() -> MinionManager:
	return get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
