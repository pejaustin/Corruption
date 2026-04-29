extends MinionState

## Forced retreat: navigate to the owner peer's tower spawn marker. On arrival,
## flush the actor's _field_log into the owner's WorldModel via
## KnowledgeManager.flush_observations and transition back to IdleState. The
## minion does not engage hostiles in transit (no aggro check, no attack hand-
## off) — it's running for home.
##
## Triggered from MinionState._check_retreat() when:
##   - actor.can_retreat is true (opt-in via MinionType)
##   - hp <= max_hp_value * retreat_hp_threshold
## Reused by InfoCourierObserveState when the observation timer expires —
## that state transitions to RetreatState explicitly so the return-and-flush
## path is one piece of code.
##
## Host-only logic; clients receive position and state via MinionManager sync.

const ARRIVAL_DISTANCE: float = 1.5

func tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if not multiplayer.is_server():
		return
	var spawn := _find_owner_spawn()
	if spawn == null:
		# Nowhere to retreat to — fall back to idle (drop the run-home loop;
		# the minion just stops). Flushing without a tower binding makes no
		# sense, so we keep the log around in case a binding lands later.
		state_machine.transition(&"IdleState")
		return

	var target: Vector3 = spawn.global_position
	if actor.global_position.distance_to(target) <= ARRIVAL_DISTANCE:
		_arrive_home()
		return

	var nav := minion.nav_agent
	if nav == null:
		state_machine.transition(&"IdleState")
		return

	nav.target_position = target
	if nav.is_navigation_finished():
		_arrive_home()
		return

	var next_pos: Vector3 = nav.get_next_path_position()
	var dir := next_pos - actor.global_position
	dir.y = 0
	if dir.length() > 0.01:
		dir = dir.normalized()
		nav.set_velocity(dir * minion.move_speed)
		actor.velocity.x = minion.safe_velocity.x
		actor.velocity.z = minion.safe_velocity.z
		face_direction(dir)
	physics_move()

func _find_owner_spawn() -> MinionSpawnPoint:
	var scene := actor.get_tree().current_scene
	if scene == null:
		return null
	var mm := scene.get_node_or_null("MinionManager") as MinionManager
	if mm == null:
		return null
	return mm.get_spawn_point_for(minion.owner_peer_id)

func _arrive_home() -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	# Flush whatever this minion observed into the owner's WorldModel. Empty
	# logs are fine — the call is a no-op.
	KnowledgeManager.flush_observations(minion.owner_peer_id, minion._field_log.values())
	minion._field_log.clear()
	# Heal back to a small buffer so the retreat-trigger threshold doesn't
	# immediately re-fire and pin the minion in a Retreat→Idle→Retreat loop.
	# Not full heal; that's a balance lever for the design pass.
	var heal_to: int = int(minion.max_hp_value * 0.5)
	if minion.hp < heal_to:
		minion.hp = heal_to
	state_machine.transition(&"IdleState")
