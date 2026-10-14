class_name BossAttackState
extends BossState

## One heavy blow, windup -> active -> recovery (BossAttack timings), committed:
## he stands still and cannot be interrupted. The blow lands only in the active
## phase, on the host. Time is rollback state (BossActor.attack_time), so every
## peer replays the same phases.

func enter(_previous_state: RewindableState, _tick: int) -> void:
	actor.velocity = Vector3.ZERO
	boss.begin_attack()

func exit(_next_state: RewindableState, _tick: int) -> void:
	boss.end_attack()

func tick(delta: float, _tick: int, is_fresh: bool) -> void:
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	if boss.current_attack() == null:
		state_machine.transition(&"IdleState")
		return
	boss.attack_time += delta
	match boss.attack_phase():
		BossAttack.Phase.ACTIVE:
			if is_fresh:
				boss.strike_targets()
		BossAttack.Phase.DONE:
			state_machine.transition(&"IdleState")
