class_name EntangleEffect extends AbilityEffect

## Nature/Fey: instant AoE stagger on nearby neutral minions.

const RADIUS: float = 6.0

func _on_activate() -> void:
	if not multiplayer.is_server() or caster == null:
		return
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	for m in mm.get_all_minions():
		if m.owner_peer_id != -1 or m.hp <= 0:
			continue
		if caster.global_position.distance_to(m.global_position) < RADIUS:
			m._state_machine.transition(&"StaggerState")
