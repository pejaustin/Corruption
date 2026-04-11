class_name EnemyState extends ActorState

## Base state for enemy-specific states.
## Provides AI helpers for finding targets and facing directions.

var enemy: EnemyActor:
	get: return actor as EnemyActor

func find_avatar() -> PlayerActor:
	var avatar_node = actor.get_tree().current_scene.get_node_or_null("World/Avatar")
	if avatar_node and avatar_node is PlayerActor and not avatar_node.is_dormant:
		return avatar_node
	return null

func distance_to(target: Node3D) -> float:
	var diff := actor.global_position - target.global_position
	diff.y = 0
	return diff.length()

func face_direction(dir: Vector3):
	if dir.length() < 0.01:
		return
	# Model faces +Z, but look_at points -Z at target, so look away from dir
	var target := actor.global_position - dir
	actor.look_at(target, Vector3.UP)
