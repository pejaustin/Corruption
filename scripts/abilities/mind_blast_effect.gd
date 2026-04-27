class_name MindBlastEffect extends AbilityEffect

## Eldritch: instant cone stagger on neutral minions in front of the Avatar.

const RANGE: float = 10.0
const CONE_ANGLE_DEG: float = 45.0

func _on_activate() -> void:
	if not multiplayer.is_server() or caster == null:
		return
	var mm := get_tree().current_scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return
	var forward := -caster.global_basis.z
	for m in mm.get_all_minions():
		if m.owner_peer_id != -1 or m.hp <= 0:
			continue
		var to_target := (m.global_position - caster.global_position).normalized()
		var angle := rad_to_deg(forward.angle_to(to_target))
		if angle < CONE_ANGLE_DEG and caster.global_position.distance_to(m.global_position) < RANGE:
			m.try_stagger()
