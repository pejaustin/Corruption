class_name MinionState extends ActorState

## Base state for minion-specific states. Uses faction-aware hostility to pick targets.

var minion: MinionActor:
	get: return actor as MinionActor

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
		if not minion.is_hostile_to(candidate):
			continue
		if not minion.can_see(candidate):
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
	var target := actor.global_position - dir
	actor.look_at(target, Vector3.UP)
