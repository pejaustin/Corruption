extends ActorState

## Stagger state. Actor is stunned briefly after taking a hit.
## Returns to IdleState when duration elapses.

var _elapsed: float = 0.0

func enter(previous_state: RewindableState, tick: int):
	_elapsed = 0.0
	actor.velocity.x = 0
	actor.velocity.z = 0

func tick(delta: float, tick: int, is_fresh: bool):
	_elapsed += delta
	actor.velocity.x = 0
	actor.velocity.z = 0
	physics_move()
	if _elapsed >= actor.get_stagger_duration():
		state_machine.transition(&"IdleState")
