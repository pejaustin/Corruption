class_name EnemyState extends ActorState

## Base state for enemy-specific states.
## Provides AI helpers for finding targets and facing directions.

var enemy: EnemyActor:
	get: return actor as EnemyActor

func find_avatar() -> PlayerActor:
	# Legacy helper kept for existing enemy states during the faction/hostility transition.
	# New code should prefer find_hostile_target().
	var avatar_node = actor.get_tree().current_scene.get_node_or_null("World/Avatar")
	if avatar_node and avatar_node is PlayerActor and not avatar_node.is_dormant:
		return avatar_node
	return null

func find_hostile_target() -> Actor:
	var best: Actor = null
	var best_dist: float = INF
	for node in actor.get_tree().get_nodes_in_group(&"actors"):
		var candidate := node as Actor
		if candidate == null or candidate == actor:
			continue
		if not candidate.can_take_damage():
			continue
		if candidate is PlayerActor and (candidate as PlayerActor).is_dormant:
			continue
		if not enemy.is_hostile_to(candidate):
			continue
		if not enemy.can_see(candidate):
			continue
		var d := distance_to(candidate)
		if d < best_dist:
			best_dist = d
			best = candidate
	return best

func distance_to(target: Node3D) -> float:
	var diff := actor.global_position - target.global_position
	diff.y = 0
	return diff.length()

func face_direction(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	# Model faces +Z, but look_at points -Z at target, so look away from dir
	var target := actor.global_position - dir
	actor.look_at(target, Vector3.UP)
