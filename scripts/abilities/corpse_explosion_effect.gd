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
			m.take_damage(DAMAGE)

func _minion_manager() -> MinionManager:
	return get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
